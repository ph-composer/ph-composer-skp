# /// script
# requires-python = ">=3.11"
# ///
"""Vendor, describe and verify the runtime payload the extension serves to its Python runtime.

The manifest (`src/ph_composer/vendor/manifest.json`) is what the shipped asset server trusts: every
asset it may serve, with its size, SHA-256 and MIME type, plus the pinned Pyodide source and the
performance gates. This tool writes it and checks the tree against it.

    uv run tools/runtime/vendor.py                    # download Pyodide, verify it, write the manifest
    uv run tools/runtime/vendor.py --refresh-manifest # after editing shipped html/ or python/ files
    uv run tools/runtime/vendor.py --check            # offline: tree, pins, gates and size budget agree
    uv run tools/runtime/vendor.py --pins-check       # shipped wheels agree with pyproject.toml
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tarfile
import tempfile
import tomllib
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EXTENSION = ROOT / "src" / "ph_composer"
VENDOR = EXTENSION / "vendor"
MANIFEST = VENDOR / "manifest.json"
MANIFEST_ASSET = "vendor/manifest.json"
PYODIDE_VERSION = "0.24.1"
PYODIDE_SHA256 = "7470bde4b38aa1fcc82d7f64d23b938510f10d7ff349b7a309d4e43a0e143443"
PYODIDE_SOURCE_BYTES = 4_604_614
PYODIDE_URL = (
    f"https://github.com/pyodide/pyodide/releases/download/{PYODIDE_VERSION}/pyodide-core-{PYODIDE_VERSION}.tar.bz2"
)
RUNTIME_FILES = ("pyodide.js", "pyodide.asm.js", "pyodide.asm.wasm", "pyodide-lock.json", "python_stdlib.zip")
# The folders the asset server may serve from. The panel page, the translation package and the
# Pyodide core; nothing else under the extension is reachable over loopback.
ASSET_ROOTS = ("html", "python", "vendor/pyodide", "vendor/wheels")


@dataclass(frozen=True)
class PackagePin:
    name: str
    version: str
    filename: str
    url_path: str
    sha256: str
    license: str
    holder: str


# Exact pure-Python translation path pins. CLI/schema-validation and optional simulation
# dependencies are outside this runtime; actual native/Pyodide path parity is an acceptance gate.
PACKAGE_PINS: tuple[PackagePin, ...] = (
    PackagePin(
        name="ladybug-geometry",
        version="1.35.3",
        filename="ladybug_geometry-1.35.3-py3-none-any.whl",
        url_path="4d/7c/0aade0858e173e329eac14cf6477ad2f8bd57fe5505fce82da73251b69d5",
        sha256="e7cce5e1c41f9863ddf37d0cc03249921d23a25caafff47730a9f9f67bf9f8b4",
        license="AGPL-3.0",
        holder="Ladybug Tools",
    ),
    PackagePin(
        name="ladybug-geometry-polyskel",
        version="1.7.52",
        filename="ladybug_geometry_polyskel-1.7.52-py3-none-any.whl",
        url_path="ea/3a/5de078edceca160fc5dc02d20a3a522bfcf5d03c4647999f852b28999c4c",
        sha256="c31d5a59b21847bc9b108bf227ecd3ca04d4be1d353e0975e86cdc4230c330a1",
        license="AGPL-3.0",
        holder="Ladybug Tools",
    ),
    PackagePin(
        name="ladybug-core",
        version="0.44.56",
        filename="ladybug_core-0.44.56-py3-none-any.whl",
        url_path="31/c0/b04628ffc84f9580d26d72d58d11f833380661314bcada7fc4ae55b596e2",
        sha256="213833188498e08d3b9a1a6da141de9a5856bd442cf4967e865a4437776a7603",
        license="AGPL-3.0",
        holder="Ladybug Tools",
    ),
    PackagePin(
        name="honeybee-standards",
        version="2.0.7",
        filename="honeybee_standards-2.0.7-py2.py3-none-any.whl",
        url_path="17/55/4a94086c7054db931527be64bb1d4ae0ec37a17867dec0671709d71a0fd7",
        sha256="194245b5bfa8f571c09b3ed8f40ee38b1a71c2c6a03b49701a19ffc3efe54679",
        license="GPL-3.0 (metadata classifier); MIT (bundled LICENSE)",
        holder="Ladybug Tools",
    ),
    PackagePin(
        name="honeybee-core",
        version="1.64.65",
        filename="honeybee_core-1.64.65-py3-none-any.whl",
        url_path="d5/87/940c8ebe18c370d5f1e5e044f589643c9b68c9b9c1e6a52ad8f1080d9e2d",
        sha256="e5aa2e668952385a2b47ba18a94e64113d553f66ac7d328cfd62c6e6334b04ea",
        license="AGPL-3.0",
        holder="Ladybug Tools",
    ),
    PackagePin(
        name="honeybee-energy",
        version="1.123.23",
        filename="honeybee_energy-1.123.23-py3-none-any.whl",
        url_path="fe/6c/0f829cd768acf43c53253d8fbd1c3f7b4498d7f7c1f009080af6d20c2907",
        sha256="384ff7552c131cc700b6c86f85afa39dfba1f7a3037bdb43e380d1a0f2de34e0",
        license="AGPL-3.0",
        holder="Ladybug Tools",
    ),
    PackagePin(
        name="ph-units",
        version="1.5.38",
        filename="ph_units-1.5.38-py3-none-any.whl",
        url_path="1e/19/ae8ecfb3de7d612f77b6c64dd80ee8f345f318fd826d831ead14c23308c8",
        sha256="ee9963cf573d82401e8fba78ecbb7d6dc267835ae4a81bf33ed4ddf1206d4dbd",
        license="GPL-3.0-or-later",
        holder="Package contributors (see bundled wheel license)",
    ),
    PackagePin(
        name="honeybee-ph",
        version="1.33.65",
        filename="honeybee_ph-1.33.65-py3-none-any.whl",
        url_path="58/eb/c7581cd58ee81a3b5cc81187947ce2bea3c712adcccfaef488959c56ca4c",
        sha256="b9b44a76806ec6ba66010a0023addd99c0279fea9dce9aab58b67031d421cece",
        license="GPL-3.0-or-later",
        holder="Package contributors (see bundled wheel license)",
    ),
)

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".json": "application/json",
    ".wasm": "application/wasm",
    ".zip": "application/zip",
    ".whl": "application/octet-stream",
    ".py": "text/plain; charset=utf-8",
    ".svg": "image/svg+xml",
}
# Carried from the predecessor's frozen manifest. Raising one is a recorded decision; the installed limits
# were raised by D3a-20 (2026-10-16). The installed size may grow at most `installed_growth_bytes` past
# `installed_baseline_bytes`, the size at the last phase close: more needs a recorded decision, and each
# phase close resets the baseline (Phase 3b's, D3b-24, 2026-10-26).
GATES: dict[str, Any] = {
    "panel_ready_target_ms": 1_000,
    "panel_ready_ceiling_ms": 2_000,
    "cold_boot_target_ms": 4_000,
    "cold_boot_ceiling_ms": 6_000,
    "warm_round_trip_target_ms": 20,
    "warm_round_trip_ceiling_ms": 100,
    "installed_target_bytes": 24_000_000,
    "installed_ceiling_bytes": 26_000_000,
    "installed_baseline_bytes": 24_541_739,
    "installed_growth_bytes": 1_500_000,
    "boot_deadline_ms": 15_000,
    "pump_target_ms": 20,
    "pump_ceiling_ms": 50,
    "platform_win": {"cold_boot_ceiling_ms": 12_000},
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download(url: str, destination: Path) -> None:
    request = urllib.request.Request(url, headers={"User-Agent": "ph-composer-vendor/1"})
    with urllib.request.urlopen(request, timeout=300) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def vendor() -> None:
    """Replace the Pyodide core with the pinned release, verified by hash, and rewrite the manifest."""
    runtime_dir = VENDOR / "pyodide"
    if runtime_dir.exists():
        shutil.rmtree(runtime_dir)
    runtime_dir.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="ph-composer-runtime-") as temporary:
        tarball = Path(temporary) / f"pyodide-core-{PYODIDE_VERSION}.tar.bz2"
        download(PYODIDE_URL, tarball)
        if (actual := sha256(tarball)) != PYODIDE_SHA256:
            raise SystemExit(f"pyodide core sha256 mismatch: expected {PYODIDE_SHA256}, got {actual}")
        with tarfile.open(tarball, "r:bz2") as archive:
            members = {Path(member.name).name: member for member in archive.getmembers() if member.isfile()}
            for filename in RUNTIME_FILES:
                source = archive.extractfile(members[filename])
                if source is None:
                    raise SystemExit(f"pyodide core is missing {filename}")
                with (runtime_dir / filename).open("wb") as output:
                    shutil.copyfileobj(source, output)
    wheel_dir = VENDOR / "wheels"
    wheel_dir.mkdir(parents=True, exist_ok=True)
    for pin in PACKAGE_PINS:
        destination = wheel_dir / pin.filename
        if not destination.exists() or sha256(destination) != pin.sha256:
            download(f"https://files.pythonhosted.org/packages/{pin.url_path}/{pin.filename}", destination)
        if sha256(destination) != pin.sha256:
            raise SystemExit(f"wheel sha256 mismatch: {pin.filename}")
    write_manifest()
    check()


def asset_files(extension: Path = EXTENSION) -> list[Path]:
    return sorted(
        path
        for root in ASSET_ROOTS
        for path in (extension / root).rglob("*")
        if path.is_file()
        and "__pycache__" not in path.parts
        and path.suffix != ".pyc"
        and not path.name.startswith(".")
    )


def translation_assets(extension: Path = EXTENSION) -> list[str]:
    """The translation package's modules, in the order the loader writes them into the runtime."""
    return [
        path.relative_to(extension).as_posix()
        for path in asset_files(extension)
        if path.is_relative_to(extension / "python") and path.suffix == ".py"
    ]


def mime_type(path: Path) -> str:
    return MIME_TYPES.get(path.suffix.lower(), "application/octet-stream")


def build_manifest(extension: Path = EXTENSION) -> dict[str, Any]:
    assets = {
        path.relative_to(extension).as_posix(): {
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
            "mime": mime_type(path),
        }
        for path in asset_files(extension)
    }
    return {
        "schema_version": 1,
        "manifest_asset": MANIFEST_ASSET,
        "pyodide": {
            "version": PYODIDE_VERSION,
            "python_version": "3.11.3",
            # The repository's LICENSE is MPL-2.0; the release's package.json declares Apache-2.0.
            # Both are recorded until the licensing gate settles the notice (docs/LICENSING.md).
            "license": "MPL-2.0",
            "package_json_license": "Apache-2.0",
            "cpython_license": "PSF-2.0",
            "source": PYODIDE_URL,
            "source_bytes": PYODIDE_SOURCE_BYTES,
            "source_sha256": PYODIDE_SHA256,
            "assets": {filename: assets.get(f"vendor/pyodide/{filename}") for filename in RUNTIME_FILES},
        },
        "packages": [package_entry(pin) for pin in PACKAGE_PINS],
        "wheel_order": [pin.filename for pin in PACKAGE_PINS],
        "translation_assets": translation_assets(extension),
        "gates": GATES,
        "assets": assets,
    }


def package_entry(pin: PackagePin) -> dict[str, Any]:
    return {
        "name": pin.name,
        "version": pin.version,
        "filename": pin.filename,
        "source": f"https://files.pythonhosted.org/packages/{pin.url_path}/{pin.filename}",
        "sha256": pin.sha256,
        "license": pin.license,
        "copyright_holder": pin.holder,
    }


def write_manifest() -> None:
    MANIFEST.write_text(json.dumps(build_manifest(), indent=2, sort_keys=True) + "\n")


def refresh_manifest() -> None:
    missing = [name for name in RUNTIME_FILES if not (VENDOR / "pyodide" / name).is_file()]
    if missing:
        raise SystemExit(f"the Pyodide core is incomplete ({missing}); run tools/runtime/vendor.py first")
    # Refreshing re-hashes html/ and python/ edits; it never adopts a changed Pyodide file.
    pinned = json.loads(MANIFEST.read_text())["pyodide"]["assets"] if MANIFEST.exists() else {}
    for name, entry in pinned.items():
        if entry["sha256"] != sha256(VENDOR / "pyodide" / name):
            raise SystemExit(f"vendor/pyodide/{name} differs from the pinned release; run tools/runtime/vendor.py")
    write_manifest()
    check()


def problems(manifest: dict[str, Any], extension: Path = EXTENSION) -> list[str]:
    """Every disagreement between the manifest, the pins in this file and the files on disk."""
    found: list[str] = []
    expected = build_manifest(extension)
    for key in ("schema_version", "manifest_asset", "gates", "translation_assets", "packages", "wheel_order"):
        if manifest.get(key) != expected[key]:
            found.append(f"{key} drift")
    if manifest.get("pyodide") != expected["pyodide"]:
        found.append("Pyodide pin or asset drift")
    declared, actual = manifest.get("assets", {}), expected["assets"]
    found.extend(f"undeclared asset: {name}" for name in sorted(set(actual) - set(declared)))
    found.extend(f"missing asset: {name}" for name in sorted(set(declared) - set(actual)))
    for name in sorted(set(actual) & set(declared)):
        for field in ("bytes", "sha256", "mime"):
            if declared[name].get(field) != actual[name][field]:
                found.append(f"{field} mismatch: {name}")
    return found


def installed_bytes(manifest: dict[str, Any], manifest_bytes: int) -> int:
    return sum(entry["bytes"] for entry in manifest["assets"].values()) + manifest_bytes


def check() -> None:
    if not MANIFEST.exists():
        raise SystemExit("runtime manifest is missing; run tools/runtime/vendor.py")
    manifest = json.loads(MANIFEST.read_text())
    found = problems(manifest)
    total = installed_bytes(manifest, MANIFEST.stat().st_size)
    if total > GATES["installed_ceiling_bytes"]:
        found.append(f"runtime payload {total} bytes exceeds the {GATES['installed_ceiling_bytes']}-byte ceiling")
    if found:
        raise SystemExit("runtime verification failed:\n  " + "\n  ".join(found))
    over = " (over the target)" if total > GATES["installed_target_bytes"] else ""
    print(f"Runtime verified: {len(manifest['assets'])} assets, {len(PACKAGE_PINS)} wheels, {total} bytes{over}")


def pins_check() -> None:
    """The wheels that ship against the wheels the offline Python tests install. Nothing else compares
    them, so a version bump in one could pass every other check."""
    with (ROOT / "pyproject.toml").open("rb") as handle:
        dependencies = tomllib.load(handle)["project"]["dependencies"]
    declared = dict(requirement.split("==", 1) for requirement in dependencies if "==" in requirement)
    shipped = {pin.name: pin.version for pin in PACKAGE_PINS}
    found = [
        f"{name}: ships {version}, pyproject.toml pins {declared.get(name, 'nothing')}"
        for name, version in sorted(shipped.items())
        if declared.get(name) != version
    ]
    found.extend(
        f"{name} {version} is pinned for tests but does not ship"
        for name, version in sorted(declared.items())
        if name not in shipped
    )
    if found:
        raise SystemExit("Wheel pins disagree:\n  " + "\n  ".join(found))
    print(f"Wheel pins agree: {len(shipped)} wheels")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--check", action="store_true", help="verify the tree without network access")
    action.add_argument("--refresh-manifest", action="store_true", help="re-hash after editing html/ or python/")
    action.add_argument("--pins-check", action="store_true", help="compare shipped wheels with pyproject.toml")
    args = parser.parse_args()
    if args.check:
        check()
    elif args.refresh_manifest:
        refresh_manifest()
    elif args.pins_check:
        pins_check()
    else:
        vendor()


if __name__ == "__main__":
    main()
