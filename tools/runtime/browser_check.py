# /// script
# requires-python = ">=3.11"
# dependencies = ["websocket-client>=1.7"]
# ///
"""Boot the shipped runtime page in Chromium 88, the host floor's engine, and probe it.

Serves the manifest's assets with the isolation headers the extension's asset server sends, loads
html/runtime/index.html headless, and sends two probes at once. It checks cross-origin isolation,
single-flight boot, that importing the translation package loads none of the stack, and the cold-boot
and warm round-trip ceilings in the manifest. Not part of `make ci`: it launches a browser, and a
browser pass is not host evidence.

    uv run tools/runtime/browser_check.py [--download-chromium] [--out result.json]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import uuid
import zipfile
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import websocket  # ty: ignore[unresolved-import]  # PEP 723 dependency, not in the dev venv

ROOT = Path(__file__).resolve().parents[2]
EXTENSION = ROOT / "src" / "ph_composer"
MANIFEST = json.loads((EXTENSION / "vendor" / "manifest.json").read_text())
PAGE = "html/runtime/index.html"
# The predecessor's cached Chromium 88 snapshot, shared so it downloads once per machine.
DEFAULT_CHROME = (
    Path.home() / ".cache/ph-navigator-sketchup/chromium-88/chrome-mac/Chromium.app/Contents/MacOS/Chromium"
)
CHROME_DOWNLOAD = "https://commondatastorage.googleapis.com/chromium-browser-snapshots/Mac/827102/chrome-mac.zip"
REQUIRED_MAJOR = 88


def free_port() -> int:
    with socket.socket() as candidate:
        candidate.bind(("127.0.0.1", 0))
        return int(candidate.getsockname()[1])


def download_chrome(binary: Path) -> None:
    if not binary.exists():
        destination = binary.parents[3]
        destination.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="phc-chrome-") as temporary:
            archive = Path(temporary) / "chrome.zip"
            print(f"Downloading Chromium 88 to {destination}", file=sys.stderr)
            urllib.request.urlretrieve(CHROME_DOWNLOAD, archive)
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(destination)
    for path in [*binary.parents[2].rglob("Contents/MacOS/*"), *binary.parents[2].rglob("chrome_crashpad_handler")]:
        if path.is_file():
            path.chmod(path.stat().st_mode | 0o111)


def chrome_major(binary: Path) -> int:
    output = subprocess.run([str(binary), "--version"], capture_output=True, text=True, check=True).stdout
    if not (match := re.search(r"(\d+)\.", output)):
        raise SystemExit(f"could not read the Chromium version from {output!r}")
    return int(match.group(1))


class RuntimeHandler(SimpleHTTPRequestHandler):
    """Serves declared assets only, with the headers runtime/http.rb sends."""

    allowed = set(MANIFEST["assets"]) | {MANIFEST["manifest_asset"]}

    def translate_path(self, path: str) -> str:
        relative = path.split("?", 1)[0].lstrip("/")
        return str(EXTENSION / (relative if relative in self.allowed else "__undeclared__"))

    def guess_type(self, path: Any) -> str:
        relative = Path(path).relative_to(EXTENSION).as_posix()
        entry = MANIFEST["assets"].get(relative)
        return str(entry["mime"]) if entry else "application/json"

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, format: str, *args: Any) -> None:
        return


class CDP:
    """The few Chrome DevTools Protocol calls the check needs, over one websocket."""

    def __init__(self, url: str) -> None:
        self.socket = websocket.create_connection(url, timeout=60)
        self.next_id = 0
        self.console: list[str] = []

    def send(self, method: str, **params: Any) -> dict[str, Any]:
        self.next_id += 1
        self.socket.send(json.dumps({"id": self.next_id, "method": method, "params": params}))
        while True:
            message = json.loads(self.socket.recv())
            if message.get("method") == "Runtime.exceptionThrown":
                self.console.append(message["params"]["exceptionDetails"].get("text", "exception"))
            if message.get("id") == self.next_id:
                return dict(message)

    def evaluate(self, expression: str) -> Any:
        result = self.send("Runtime.evaluate", expression=expression, awaitPromise=True, returnByValue=True)["result"]
        if "exceptionDetails" in result:
            raise RuntimeError(json.dumps(result["exceptionDetails"])[:1000])
        return result["result"].get("value")


def page_websocket(port: int) -> str:
    deadline = time.time() + 30
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/json", timeout=2) as response:
                pages = [target for target in json.load(response) if target.get("type") == "page"]
            if pages:
                return str(pages[0]["webSocketDebuggerUrl"])
        except (OSError, ValueError):
            pass
        time.sleep(0.2)
    raise SystemExit("Chromium did not expose a page over CDP")


# Installed before the page's own script: the host callback the page reports to.
DRIVER = """
window.__phc = {messages: []};
window.sketchup = {ph_composer_runtime: function (text) { window.__phc.messages.push(JSON.parse(text)); }};
Object.defineProperty(window, "loadPyodide", {
  configurable: true,
  get: function () { return window.__phc.loader; },
  set: function (loader) {
    if (typeof loader !== "function") { window.__phc.loader = loader; return; }
    window.__phc.loader = function (options) {
      return loader(options).then(function (runtime) { window.__phc.runtime = runtime; return runtime; });
    };
  }
});
"""

PROBE = """
new Promise(function (resolve) {
  function probe(id) {
    PhComposerRuntime.receive({type: "runtime.probe", payload: {request_id: id, deadline_ms: %d}});
  }
  probe("browser-one");
  probe("browser-two");
  var deadline = Date.now() + 30000;
  (function poll() {
    var results = window.__phc.messages.filter(function (m) { return m.type === "runtime.result"; });
    if (results.length >= 2 || Date.now() > deadline) {
      return resolve({messages: window.__phc.messages, isolated: window.crossOriginIsolated === true});
    }
    setTimeout(poll, 100);
  }());
});
"""


def run_browser(binary: Path, translation: bool = False) -> dict[str, Any]:
    major = chrome_major(binary)
    server = ThreadingHTTPServer(("127.0.0.1", free_port()), RuntimeHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{server.server_address[1]}/{PAGE}?session=browser"
    debug_port = free_port()
    profile = Path(tempfile.mkdtemp(prefix="phc-c88-"))
    process = subprocess.Popen(
        [
            str(binary),
            "--headless",
            "--no-first-run",
            "--disable-gpu",
            "--disable-background-networking",
            f"--remote-debugging-port={debug_port}",
            f"--user-data-dir={profile}",
            "about:blank",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    client = None
    try:
        client = CDP(page_websocket(debug_port))
        client.send("Runtime.enable")
        client.send("Page.enable")
        client.send("Page.addScriptToEvaluateOnNewDocument", source=DRIVER)
        client.send("Page.navigate", url=url)
        observed = wait_for_page(client)
        observed.update(client.evaluate(PROBE % MANIFEST["gates"]["boot_deadline_ms"]))
        if translation:
            observed["export_translation"] = check_translation(client)
    finally:
        if client:
            client.socket.close()
        process.terminate()
        process.wait(timeout=10)
        server.shutdown()
        shutil.rmtree(profile, ignore_errors=True)
    return verdict(major, observed, client.console if client else [])


def check_translation(client: CDP) -> dict[str, Any]:
    """Exercise the shipped authored-construction composition and compare pinned native wheel output."""
    document = json.loads((ROOT / "tests/fixtures/phase_one/two_zones_extraction.json").read_text())
    # The retained Phase 1 fixture predates Window contributors. The current composition declares
    # their empty sections even when a Model has no Units; retain the historical authored records.
    for name in ("window_constructions", "apertures"):
        document["sections"][f"ph_composer.windows.export.{name}"] = {"version": 1, "records": []}
    # One synthetic Space on Zone A, with a supply rate, so honeybee-ph's Space objects and the airflow rule
    # take the same path through both runtimes.
    floor = [[1.0, 1.0, 0.0], [3.0, 1.0, 0.0], [3.0, 3.0, 0.0], [1.0, 3.0, 0.0]]
    top = [[x, y, 2.5] for x, y, _z in floor]
    prism = [floor, top] + [[floor[i], floor[(i + 1) % 4], top[(i + 1) % 4], top[i]] for i in range(4)]
    document["sections"]["ph_composer.spaces.export.spaces"] = {
        "version": 2,
        "records": [
            {
                "id": "spc_BrowserCheck",
                "zone_id": "zon_AAAAAAAAAAAA",
                "name": "Kitchen",
                "number": "101",
                "v_sup_m3h": 60.0,
                "airflow_mode": "detailed",
                "volumes": [
                    {
                        "id": "vol_BrowserCheck",
                        "display_name": "",
                        "avg_ceiling_height_m": 2.5,
                        "floor_id": "flr_BrowserCheck",
                        "geometry": prism,
                        "floor_segments": [
                            {
                                "id": "fsg_BrowserCheck",
                                "display_name": "",
                                "weighting_factor": 1.0,
                                "net_area_factor": 1.0,
                                "loops_m": [floor],
                            }
                        ],
                    }
                ],
            }
        ],
    }
    request = {"request_id": "browser-export", "deadline_ms": 15000, "document": document}
    response = client.evaluate(
        """
new Promise(function (resolve, reject) {
  PhComposerRuntime.receive({type: "runtime.translate", payload: REQUEST});
  var deadline = Date.now() + 30000;
  (function poll() {
    var result = window.__phc.messages.find(function (m) { return m.type === "runtime.translation"; });
    if (result) return resolve(result.payload);
    if (Date.now() > deadline) return reject(new Error("translation timed out"));
    setTimeout(poll, 100);
  }());
});
""".replace("REQUEST", json.dumps(request))
    )
    if response.get("error"):
        # Surface the Python exception only in this development check, never in the shipped panel.
        diagnostic = json.dumps("from ph_composer_translation.entry import export_json\nexport_json(_phc_document)")
        client.evaluate(f"window.__phc.runtime.runPythonAsync({diagnostic})")
        raise RuntimeError(f"shipped export runtime failed: {response['error']}")
    result = response["result"]
    source = "\n".join(
        [
            "from ph_composer_translation.entry import export_json",
            f"export_json({json.dumps(json.dumps(document))})",
        ]
    )
    assert result["summary"]["publishable"] is True, result
    canonical = result["canonical_model"]
    assert {key: canonical[key] for key in ("rooms", "faces", "surface_pairs")} == {
        "rooms": 2,
        "faces": 12,
        "surface_pairs": 1,
    }, canonical
    model = json.loads(canonical["hbjson"])
    constructions = {row["identifier"]: row for row in model["properties"]["energy"]["constructions"]}
    # The interior Surface pair exports the one Assembly, reversed on one side.
    assert set(constructions) == {"ph_composer_asm_Single000001", "ph_composer_asm_Single000001_reversed"}
    for room in model["rooms"]:
        for face in room["faces"]:
            identifier = face["properties"]["energy"]["construction"]
            assert identifier in constructions
            assert constructions[identifier]["user_data"]["ph_composer"]["assembly_id"] == "asm_Single000001"
    with tempfile.TemporaryDirectory(prefix="phc-native-wheels-") as temporary:
        wheel_path = Path(temporary) / "wheels"
        for filename in MANIFEST["wheel_order"]:
            with zipfile.ZipFile(EXTENSION / "vendor/wheels" / filename) as wheel:
                wheel.extractall(wheel_path)
        script = Path(temporary) / "parity.py"
        native_source = "\n".join(
            [
                "import sys",
                f"sys.path[:0] = {[str(wheel_path), str(EXTENSION / 'python')]!r}",
                source.rsplit("\n", 1)[0],
                "print(" + source.rsplit("\n", 1)[1] + ")",
            ]
        )
        script.write_text(native_source)
        native = subprocess.run([sys.executable, "-S", str(script)], capture_output=True, text=True, check=True)
        native_result = json.loads(native.stdout)
        assert comparable_result(native_result) == comparable_result(result), "native/Pyodide model content differs"
    return {
        "shipped_authored_construction_translation": True,
        "native_pyodide_model_parity": True,
        "comparison": "Normalize upstream PH default UUIDs, hash-ordered definition lists and int/float only.",
        "synthetic_result": result,
    }


def comparable_result(result: dict[str, Any]) -> dict[str, Any]:
    """Compare exact values and authored references; scope normalization to upstream-created defaults.

    HB-PH initializes otherwise unauthored team/site/certification children with uuid4 identifiers.
    HB-Energy emits its global material/construction sets, and the Model's own materials, constructions,
    schedules, schedule type limits and program types, in hash-set order. A number crosses the JavaScript
    bridge without its int/float distinction, so 1.0 and 1 compare equal. None of these differences
    changes this fixture's authored Room/Face/segment identities or Surface/construction references.
    This is comparison-only: the exported HBJSON is never rewritten or a golden replaced.
    """
    copied = json.loads(json.dumps(result))
    model = json.loads(copied["canonical_model"]["hbjson"])
    replacements: dict[str, str] = {}

    def defaults(value: Any, path: str) -> None:
        if isinstance(value, dict):
            identifier = value.get("identifier")
            if isinstance(identifier, str):
                try:
                    uuid.UUID(identifier)
                    replacements[identifier] = path
                except ValueError:
                    pass
            for key, child in value.items():
                defaults(child, f"{path}/{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                defaults(child, f"{path}/{index}")

    ph = model["properties"]["ph"]
    defaults(ph["team"], "ph/team")
    for segment in ph["bldg_segments"]:
        defaults(segment, "ph/segment/" + segment["identifier"])

    def replace(value: Any) -> Any:
        if isinstance(value, str):
            return replacements.get(value, value)
        if isinstance(value, float) and value.is_integer():
            return int(value)
        if isinstance(value, list):
            return [replace(child) for child in value]
        if isinstance(value, dict):
            return {key: replace(child) for key, child in value.items()}
        return value

    # Sorted after the default UUIDs are replaced, so a definition carrying one sorts the same in both runtimes.
    model = replace(model)
    energy = model["properties"]["energy"]
    for field in ("materials", "constructions"):
        energy["global_construction_set"][field].sort(key=lambda definition: definition["identifier"])
    for field in ("materials", "constructions", "schedules", "schedule_type_limits", "program_types"):
        energy.get(field, []).sort(key=lambda definition: definition["identifier"])
    copied["canonical_model"]["hbjson"] = json.dumps(model, sort_keys=True, separators=(",", ":"))
    return copied


def wait_for_page(client: CDP) -> dict[str, Any]:
    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            if client.evaluate("typeof PhComposerRuntime") == "object":
                return {}
        except RuntimeError:
            pass
        time.sleep(0.2)
    raise SystemExit("the runtime page did not load")


def verdict(major: int, observed: dict[str, Any], console: list[str]) -> dict[str, Any]:
    results = [message["payload"] for message in observed["messages"] if message["type"] == "runtime.result"]
    gates = MANIFEST["gates"]
    checks = {
        "chromium_88": major == REQUIRED_MAJOR,
        "cross_origin_isolated": observed.get("isolated") is True,
        "two_results": len(results) == 2,
        "no_errors": all("error" not in result for result in results),
        "single_flight_boot": len(results) == 2 and all(result.get("boot_count") == 1 for result in results),
        "stack_not_loaded": len(results) == 2 and all(result.get("stack_loaded") == [] for result in results),
        "translation_answers": len(results) == 2
        and all(result.get("translation_state") == "complete" for result in results),
        "cold_boot_within_ceiling": bool(results)
        and all(result.get("cold_boot_ms", 10**9) <= gates["cold_boot_ceiling_ms"] for result in results),
        "warm_round_trip_within_ceiling": bool(results)
        and all(result.get("warm_round_trip_ms", 10**9) <= gates["warm_round_trip_ceiling_ms"] for result in results),
    }
    if "export_translation" in observed:
        checks["export_translation"] = observed["export_translation"]["shipped_authored_construction_translation"]
    return {
        "verdict": "PASS" if all(checks.values()) else "FAIL",
        "checks": checks,
        "results": results,
        "console": console,
        **({"export_translation": observed["export_translation"]} if "export_translation" in observed else {}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--download-chromium", action="store_true", help="download the pinned Chromium 88 if absent")
    parser.add_argument("--chrome", type=Path, default=DEFAULT_CHROME)
    parser.add_argument("--out", type=Path)
    parser.add_argument(
        "--translation", action="store_true", help="check authored HBJSON translation against the pinned native wheels"
    )
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "tools" / "runtime" / "vendor.py"), "--check"], check=True)
    if args.download_chromium:
        download_chrome(args.chrome)
    if not args.chrome.exists():
        raise SystemExit(f"Chromium 88 not found at {args.chrome}; pass --download-chromium")
    result = run_browser(args.chrome, args.translation)
    print(json.dumps(result, indent=2))
    if args.out:
        args.out.write_text(json.dumps(result, indent=2) + "\n")
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
