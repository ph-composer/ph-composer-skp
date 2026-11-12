# /// script
# requires-python = ">=3.11"
# ///
"""Drive the real SketchUp host from a terminal through the development bridge.

The bridge (tools/hostkit/host_bridge.rb, installed with `make bridge-install`) evaluates Ruby inside
the running SketchUp on the main thread. This client wraps it with the lifecycle steps that need
care on macOS: launching with one document (and no recovered-version prompt for a scratch fixture),
quitting without a save dialog however many documents are open, saving past the Purge Unused prompt,
and waiting for deferred work.

    uv run tools/hostkit/host_bridge.py launch <model.skp> [--fresh-from <accepted.skp>]
    uv run tools/hostkit/host_bridge.py eval 'PhComposerHost.state'
    uv run tools/hostkit/host_bridge.py eval --file scenario.rb
    uv run tools/hostkit/host_bridge.py state
    uv run tools/hostkit/host_bridge.py save
    uv run tools/hostkit/host_bridge.py shot <name> --dir <evidence-dir>
    uv run tools/hostkit/host_bridge.py key 53            # Escape, through System Events
    uv run tools/hostkit/host_bridge.py show-model <title text>  # fronts SketchUp, then hands focus back
    uv run tools/hostkit/host_bridge.py console --tail 40  # what the Ruby Console showed
    uv run tools/hostkit/host_bridge.py wait-for session_settled --param session=<uuid> --deadline 30 --json
    uv run tools/hostkit/host_bridge.py diagnostics --session <uuid> --severity warning --json
    uv run tools/hostkit/host_bridge.py fault arm failed_write --session <uuid> --key unit_system --json
    uv run tools/hostkit/host_bridge.py quit

`eval` prints captured stdout, then the result (JSON when the value serializes, else `inspect`).
Exit status 1 on a Ruby error, 2 when the bridge is unreachable. `wait-for` polls a named read-only
condition in separate host calls (tools/hostkit/host_wait.py) and exits 0 only when it was met. `fault`
arms, observes and restores a named development fault (tools/hostkit/host_faults.py) and exits 0 only when
the operation held.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import math
import os
import signal
import socket
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any

# ty checks a PEP 723 script in its own environment, without the script's directory that Python puts on
# sys.path at run time, so this sibling import resolves when run and not for ty.
import host_diagnostics  # ty: ignore[unresolved-import]
import host_faults  # ty: ignore[unresolved-import]
import host_wait  # ty: ignore[unresolved-import]

SUPPORT = Path.home() / "Library" / "Application Support"
APP = Path("/Applications/SketchUp {version}/SketchUp.app")
HELPERS = Path(__file__).resolve().parent / "host_helpers.rb"
ESCAPE_KEY_CODE = 53
# A wait poll's reply is a small projection; anything larger is not one, and parsing it could outlast the budget.
MAX_WHOLE_REPLY_BYTES = 1024 * 1024


class BridgeError(RuntimeError):
    pass


# ----------------------------------------------------------------------------- transport


def state_path(version: str) -> Path:
    return SUPPORT / f"SketchUp {version}" / "SketchUp" / "ph_composer_host_bridge.json"


def read_state(version: str) -> dict[str, Any] | None:
    path = state_path(version)
    if not path.is_file():
        return None
    state = json.loads(path.read_text())
    try:
        pid = int(state["pid"])
        if pid <= 0:  # 0 and negative pids signal process groups, and would look alive
            return None
        os.kill(pid, 0)
    except (OSError, ValueError, OverflowError):
        return None
    return state


def request(state: dict[str, Any], payload: dict[str, Any], timeout: float, *, whole: bool = False) -> dict[str, Any]:
    """One request and its reply. `timeout` bounds each socket operation; with `whole`, it bounds the request
    as a whole: every operation gets only what is left, and TimeoutError is raised once nothing is."""
    payload = dict(payload, token=state["token"])
    deadline = time.monotonic() + timeout

    def remaining() -> float:
        left = deadline - time.monotonic()
        if left <= 0:
            raise TimeoutError("the reply did not arrive within the remaining budget")
        return left

    with socket.create_connection(("127.0.0.1", int(state["port"])), timeout=timeout) as sock:
        if whole:
            sock.settimeout(remaining())
        sock.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        chunks: list[bytes] = []
        received = 0
        while True:
            if whole:
                sock.settimeout(remaining())
            chunk = sock.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
            received += len(chunk)
            if whole and received > MAX_WHOLE_REPLY_BYTES:
                raise ValueError(f"the reply exceeded {MAX_WHOLE_REPLY_BYTES} bytes")
    line = b"".join(chunks).decode("utf-8").strip()
    if not line:
        raise ConnectionError("empty reply from the bridge")
    return json.loads(line)


def wait(version: str, timeout: float) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = read_state(version)
        if state is not None:
            try:
                answer = request(state, {"ping": True}, timeout=5.0)
                if answer.get("ok"):
                    return state
            except OSError:
                pass
        time.sleep(1.0)
    raise TimeoutError(f"no host bridge within {timeout:.0f}s")


def reply(version: str, code: str, timeout: float = 300.0) -> dict[str, Any]:
    """Send Ruby to the live bridge and return its whole reply document, error replies included.
    The `eval` command needs the document (stdout, backtrace, ok); `evaluate` needs the value."""
    state = read_state(version)
    if state is None:
        raise BridgeError("host bridge is not running (no live state file)")
    return request(state, {"code": code}, timeout=timeout)


def evaluate(version: str, code: str, timeout: float = 300.0) -> Any:
    """Evaluate Ruby and return its JSON value (or `inspect` text). Raises BridgeError on a Ruby error."""
    answer = reply(version, code, timeout=timeout)
    if not answer.get("ok"):
        trace = "\n  ".join(answer.get("backtrace", [])[:6])
        raise BridgeError(f"{answer.get('error')}\n  {trace}".rstrip())
    value = answer.get("value")
    return value if value is not None else answer.get("result")


def evaluate_in_background(version: str, code: str) -> subprocess.Popen[bytes]:
    """Start an eval in a child process so this process can dismiss a dialog it triggers."""
    return subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "--sketchup-version", version, "eval", code],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


# ----------------------------------------------------------------------------- macOS control


def sketchup_running() -> bool:
    return subprocess.run(["pgrep", "-x", "SketchUp"], capture_output=True, check=False).returncode == 0


def send_key(key_code: int) -> None:
    """Send a key to SketchUp through System Events (needs Accessibility for the terminal app)."""
    subprocess.run(
        [
            "osascript",
            "-e",
            f'tell application "System Events" to tell process "SketchUp" to key code {key_code}',
        ],
        capture_output=True,
        check=False,
        timeout=15,
    )


def sketchup_bundle(version: str) -> str:
    return f"com.sketchup.SketchUp.{version}"


def frontmost_app() -> str | None:
    """The bundle id of the frontmost app, to hand focus back to (needs Accessibility)."""
    script = 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'
    try:
        done = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, check=False, timeout=15)
    except (subprocess.SubprocessError, OSError):
        return None
    return (done.stdout or "").strip() or None


def activate_app(bundle_id: str) -> None:
    """Best effort: a focus change that fails or times out must not abort a launch or a quit."""
    with contextlib.suppress(subprocess.SubprocessError, OSError):
        subprocess.run(
            ["osascript", "-e", f'tell application id "{bundle_id}" to activate'],
            capture_output=True,
            check=False,
            timeout=15,
        )


def restore_focus(version: str, previous: str | None) -> None:
    if previous is not None and previous != sketchup_bundle(version):
        activate_app(previous)


def activate_sketchup_once(version: str) -> None:
    """Bring SketchUp to the front for a moment, then hand focus back to the app that had it.
    SketchUp 2026 opened by `open -a` in the background can load no Ruby extension, the bridge
    included, until it is activated once."""
    previous = frontmost_app()
    try:
        activate_app(sketchup_bundle(version))
        time.sleep(1.0)
    finally:
        restore_focus(version, previous)


# Raises a document window, which makes its Model the active one. Closing the active Model leaves
# `Sketchup.active_model` nil while SketchUp is in the background, even with another document window open.
RAISE_DOCUMENT = (
    'tell application "System Events" to tell process "SketchUp"\n'
    'set docWindows to (windows whose name contains " - SketchUp")\n'
    'if (count of docWindows) is 0 then return "phc_no_window"\n'
    "set frontmost to true\n"
    'perform action "AXRaise" of (item 1 of docWindows)\n'
    'return "phc_raised"\n'
    "end tell"
)


def raise_document(version: str) -> str:
    """Make a remaining document window key through System Events, then hand focus back. "phc_raised",
    "phc_no_window", or why the raise failed."""
    previous = frontmost_app()
    try:
        done = subprocess.run(
            ["osascript", "-e", RAISE_DOCUMENT], capture_output=True, text=True, check=False, timeout=15
        )
        time.sleep(1.0)
    except (subprocess.SubprocessError, OSError) as error:
        return str(error)
    finally:
        restore_focus(version, previous)
    if done.returncode != 0:
        return (done.stderr or "").strip() or f"osascript exited {done.returncode}"
    return done.stdout.strip()


# show-model: AXRaise the one document window whose title part (its name before " - SketchUp") contains the
# wanted text, which makes its Model the active one and fires `onActivateModel`. The windows are listed and
# matched before SketchUp is fronted, so a refusal leaves the screen alone. Values arrive as `argv` after `--`,
# never in a script's source. Focus goes back by System Events process name: `tell application "Rhinoceros"`
# names a process, not an app, and fails.
DOCUMENT_MARK = " - SketchUp"
UNSAVED_TITLE = "Untitled"
DOCUMENT_WINDOWS = (
    'tell application "System Events" to tell process "SketchUp"\n'
    f'set names to name of (windows whose name contains "{DOCUMENT_MARK}")\n'
    "set AppleScript's text item delimiters to linefeed\n"
    "return names as text\n"
    "end tell"
)
RAISE_WINDOW = (
    "on run argv\n"
    "set wanted to item 1 of argv\n"
    'tell application "System Events" to tell process "SketchUp"\n'
    "set matching to (windows whose name is wanted)\n"
    'if (count of matching) is not 1 then return "phc_changed"\n'
    "set frontmost to true\n"
    'perform action "AXRaise" of (item 1 of matching)\n'
    'return "phc_raised"\n'
    "end tell\n"
    "end run"
)
FRONTMOST_PROCESS = 'tell application "System Events" to get name of first process whose frontmost is true'
FRONT_PROCESS = (
    "on run argv\n"
    "set wanted to item 1 of argv\n"
    'tell application "System Events" to set frontmost of process wanted to true\n'
    "end run"
)
# A lambda with a block-local variable: the bridge evaluates every call in one shared binding.
ACTIVE_TITLE = "->(; m) { m = Sketchup.active_model; m && m.title }.call"
SHOW_DEADLINE_S = 15.0
MAX_SHOW_DEADLINE_S = 120.0
SHOW_INTERVAL_S = 0.25
RESTORE_CHECKS = 8


def osascript(script: str, *args: str) -> tuple[bool, str]:
    """Run one AppleScript with `args` as its argv: whether it succeeded, and its output or why it failed."""
    try:
        done = subprocess.run(
            ["osascript", "-e", script, "--", *args], capture_output=True, text=True, check=False, timeout=15
        )
    except (subprocess.SubprocessError, OSError) as error:
        return False, str(error)
    if done.returncode != 0:
        return False, (done.stderr or "").strip() or f"osascript exited {done.returncode}"
    return True, (done.stdout or "").strip()


def frontmost_process() -> str | None:
    ok, name = osascript(FRONTMOST_PROCESS)
    return name if ok and name else None


def restore_process(name: str) -> bool:
    """Front the process `name` and read back that it is frontmost; activation can lag the request."""
    osascript(FRONT_PROCESS, name)
    for _ in range(RESTORE_CHECKS):
        if frontmost_process() == name:
            return True
        time.sleep(SHOW_INTERVAL_S)
    return frontmost_process() == name


def contains(title: str, wanted: str) -> bool:
    """The one match rule for a window's title part and the Model's title, so both sides agree."""
    return wanted.casefold() in title.casefold()


def wait_for_title(
    read: Callable[[str, float], Any], wanted: str, deadline_s: float
) -> tuple[str, str | None, str | None]:
    """Poll the active Model's title until it contains `wanted` under one deadline: the ending (`shown`,
    `timed_out`, `read_failed` or `bridge_unavailable`), the last title read, and why it ended when it was
    not shown. A reply that arrives after the deadline is `timed_out`, never `shown`."""
    started = time.monotonic()
    title: str | None = None
    while True:
        remaining = deadline_s - (time.monotonic() - started)
        if remaining <= 0:
            return "timed_out", title, "the active Model's title never contained the wanted text"
        try:
            observed = read(ACTIVE_TITLE, remaining)
        except host_wait.ReadError as error:
            return "read_failed", title, str(error)
        except TimeoutError:
            return "timed_out", title, "the last read did not answer within the remaining budget"
        except OSError as error:
            return "bridge_unavailable", title, str(error)
        title = observed if isinstance(observed, str) else None
        if time.monotonic() - started > deadline_s:
            return "timed_out", title, "the last read answered after the deadline"
        if title is not None and contains(title, wanted):
            return "shown", title, None
        time.sleep(min(SHOW_INTERVAL_S, max(0.0, deadline_s - (time.monotonic() - started))))


def show_model(version: str, wanted: str, deadline_s: float) -> dict[str, Any]:
    """Show the Model whose document window's title part contains `wanted`, then hand focus back to the
    process that had it. Refuses, without fronting SketchUp, when no window or more than one matches, the
    bridge is not answering, or the frontmost process cannot be read (focus could not go back). Once a raise
    is attempted, focus is handed back on every path. `deadline_s` bounds the wait for the switch only."""
    result: dict[str, Any] = {
        "ending": "refused",
        "wanted": wanted,
        "window": None,
        "before": None,
        "shown": None,
        "previous": None,
        "restored": None,
        "error": None,
    }
    if not wanted.strip():
        return result | {"error": "the wanted title text is empty"}
    if not (math.isfinite(deadline_s) and 0 < deadline_s <= MAX_SHOW_DEADLINE_S):
        return result | {"error": f"the deadline must be above 0 and at most {MAX_SHOW_DEADLINE_S:.0f} seconds"}
    try:
        raise_and_wait(version, wanted, deadline_s, result)
    except KeyboardInterrupt:
        result |= {"ending": "cancelled", "error": "interrupted by the developer"}
    return result


def raise_and_wait(version: str, wanted: str, deadline_s: float, result: dict[str, Any]) -> None:
    """show_model's steps, filling `result` in place as they go, so an interrupt still reports what was done."""
    read = bridge_read(version)
    try:
        result["before"] = read(ACTIVE_TITLE, 10.0)
    except host_wait.ReadError as error:
        result["error"] = f"the active Model's title could not be read: {error}"
        return
    except OSError as error:
        result |= {"ending": "bridge_unavailable", "error": str(error)}
        return
    if (previous := frontmost_process()) is None:
        result["error"] = "the frontmost process could not be read, so focus could not be handed back"
        return
    result["previous"] = previous
    ok, listing = osascript(DOCUMENT_WINDOWS)
    if not ok:
        result["error"] = f"the document windows could not be read: {listing}"
        return
    windows = [name for name in listing.splitlines() if DOCUMENT_MARK in name]
    matching = [name for name in windows if contains(name.rpartition(DOCUMENT_MARK)[0], wanted)]
    if not matching:
        result["error"] = f"no document window's title contains the wanted text; open: {windows}"
        return
    if len(matching) > 1:
        result["error"] = f"more than one document window matches: {matching}"
        return
    if matching[0].startswith(UNSAVED_TITLE):
        # An unsaved Model's Ruby title is empty, so its switch could never be confirmed.
        result["error"] = f"an unsaved Model cannot be confirmed by its title: {matching[0]}"
        return
    result["window"] = matching[0]
    try:
        ok, answer = osascript(RAISE_WINDOW, matching[0])
        if ok and answer == "phc_raised":
            result["ending"], result["shown"], result["error"] = wait_for_title(read, wanted, deadline_s)
        else:
            result |= {"ending": "raise_failed", "error": f"the window could not be raised: {answer}"}
    finally:
        try:
            result["restored"] = restore_process(previous)
        except KeyboardInterrupt:  # restore once more, then let the interrupt end the command as cancelled
            result["restored"] = restore_process(previous)
            raise


def run_with_dialog_guard(version: str, code: str, timeout: float = 120.0, escape_after: float = 3.0) -> str:
    """Run `code`; if the reply has not returned after `escape_after` seconds, send Escape to
    dismiss a modal dialog (the SketchUp 2026 Purge Unused prompt on save) and keep waiting."""
    child = evaluate_in_background(version, code)
    started = time.monotonic()
    while child.poll() is None:
        time.sleep(1.0)
        if time.monotonic() - started > escape_after:
            send_key(ESCAPE_KEY_CODE)
        if time.monotonic() - started > timeout:
            child.kill()
            raise BridgeError("the guarded eval did not return; a dialog may still be open in SketchUp")
    out, err = child.communicate()
    if child.returncode != 0:
        raise BridgeError(err.decode("utf-8", "replace").strip() or out.decode("utf-8", "replace"))
    return out.decode("utf-8", "replace").strip()


# Closes the active document and discards its changes, with no save prompt and no save: a Save As to a
# scratch path would move a "This Model only" agent token onto that path. `Model#close(true)` also closes
# a document while SketchUp is in the background, where `performClose:` does nothing. Only the active
# Model is reachable from Ruby, so a second document (after Cmd-N, say) is closed on the next pass, once
# its window is raised; terminating with one still dirty waits on a save sheet until the process is killed.
CLOSE_ACTIVE = (
    'm = Sketchup.active_model; if !m then :phc_no_document else guid = m.guid; m.close(true); "phc_closed:#{guid}" end'
)
ACTIVE_GUID = "m = Sketchup.active_model; m ? m.guid : :phc_no_document"
MAX_DOCUMENTS = 8


def last_value(output: str) -> str:
    """The eval's printed value: its last output line, unquoted (console prints come before it)."""
    lines = output.strip().splitlines()
    return lines[-1].strip().strip('"') if lines else ""


def document_left(version: str, guid: str) -> bool:
    """Whether the document `guid` stopped being the active one within five seconds. The last check
    raises rather than reading a bridge error as "still open"."""
    for _ in range(9):
        time.sleep(0.5)
        with contextlib.suppress(BridgeError, OSError, TimeoutError):
            if evaluate(version, ACTIVE_GUID, timeout=10.0) != guid:
                return True
    time.sleep(0.5)
    return evaluate(version, ACTIVE_GUID, timeout=10.0) != guid


def close_active(version: str) -> str:
    return last_value(run_with_dialog_guard(version, CLOSE_ACTIVE, timeout=60.0))


def close_documents(version: str) -> str:
    """Close every open document without saving it, one active document at a time; say how far it got."""
    closed = 0
    for _ in range(MAX_DOCUMENTS):
        try:
            answer = close_active(version)
            if answer == "phc_no_document":
                if (raised := raise_document(version)) == "phc_no_window":
                    return f"closed {closed} documents"
                if raised != "phc_raised":
                    return (
                        f"closed {closed} documents; stopped: no active Model and no window could be raised: {raised}"
                    )
                if (answer := close_active(version)) == "phc_no_document":
                    return f"closed {closed} documents; stopped: a document window is open but no Model is active"
            if not answer.startswith("phc_closed:"):
                return f"closed {closed} documents; stopped: the close step answered {answer!r}"
            guid = answer.removeprefix("phc_closed:")
            if not document_left(version, guid):
                return f"closed {closed} documents; stopped: the active document stayed open after its close"
        except (BridgeError, OSError, TimeoutError) as error:
            return f"closed {closed} documents; the close step failed: {error}"
        closed += 1
    return f"closed {closed} documents; stopped at the limit of {MAX_DOCUMENTS}"


def quit_sketchup(version: str) -> str:
    """Quit without a save dialog: close every open document, discarding its changes, then terminate.
    A host the bridge cannot reach, or one still on a prompt after 30 seconds, is killed."""
    if not sketchup_running():
        return "SketchUp not running"
    state = read_state(version)
    note = "no live bridge, so no document could be closed"
    if state is not None:
        note = close_documents(version)
        with contextlib.suppress(BridgeError, OSError, TimeoutError):
            request(state, {"code": 'Sketchup.send_action("terminate:")'}, timeout=10.0)
    for _ in range(30):
        if not sketchup_running():
            return f"SketchUp quit cleanly ({note})"
        time.sleep(1.0)
    subprocess.run(["pkill", "-9", "-x", "SketchUp"], capture_output=True, check=False)
    return f"SketchUp did not quit within 30s; killed ({note}; its documents may be restored on the next launch)"


def recovery_copy(version: str, model: Path) -> Path | None:
    """SketchUp's autosave copy of `model`, which it offers back ("The recovered version of this file is newer")
    on the next open, for a scratch fixture only: under a `_private/` corpus or the temporary folder. A
    user's own document keeps its recovery copy."""
    scratch = "_private" in model.parts or str(model).startswith(("/private/tmp/", "/tmp/"))
    return SUPPORT / f"SketchUp {version}" / "SketchUp" / "working" / model.name if scratch else None


def open_windows() -> str:
    """The names of SketchUp's open windows, to say which prompt is blocking (needs Accessibility)."""
    try:
        done = subprocess.run(
            ["osascript", "-e", 'tell application "System Events" to get name of every window of process "SketchUp"'],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
    except (subprocess.SubprocessError, OSError) as error:
        return f"(not readable: {error})"
    return done.stdout.strip() or done.stderr.strip() or "(none readable)"


ACTIVATE_AFTER = 25.0


def wait_for_launch(version: str, timeout: float) -> dict[str, Any]:
    """Wait for the bridge of a SketchUp just opened. If it has written no state file `ACTIVATE_AFTER`
    seconds in while SketchUp runs, startup is stalled in the background: activate SketchUp once.
    Either way the wait runs to the full `timeout`."""
    deadline = time.monotonic() + timeout
    first = min(ACTIVATE_AFTER, timeout)
    try:
        return wait(version, first)
    except TimeoutError:
        if timeout <= first:
            raise
    activated = not state_path(version).is_file() and sketchup_running()
    if activated:
        print(f"no bridge state file {first:.0f}s into the launch; activating SketchUp once")
        activate_sketchup_once(version)
    try:
        return wait(version, deadline - time.monotonic())
    except TimeoutError:
        note = f" (SketchUp activated once at {first:.0f}s)" if activated else ""
        raise TimeoutError(f"no host bridge within {timeout:.0f}s{note}") from None


def launch(version: str, model: Path, fresh_from: Path | None, timeout: float) -> dict[str, Any]:
    """Quit any running SketchUp, open `model` as the only document, wait for the bridge, load helpers."""
    if fresh_from is not None:
        model.write_bytes(fresh_from.read_bytes())
    print(quit_sketchup(version))
    if (copy := recovery_copy(version, model)) is not None:
        copy.unlink(missing_ok=True)
    for _ in range(20):
        if not sketchup_running():
            break
        time.sleep(1.0)
    state_path(version).unlink(missing_ok=True)
    app = Path(str(APP).format(version=version))
    for _attempt in range(5):
        done = subprocess.run(["open", "-a", str(app), str(model)], capture_output=True, check=False)
        if done.returncode == 0:
            break
        time.sleep(3.0)
    else:
        raise BridgeError(f"could not open {model} with {app}")
    try:
        state = wait_for_launch(version, timeout)
    except TimeoutError as error:
        raise TimeoutError(
            f"{error}; a SketchUp prompt may be waiting, possibly on another display. Open windows: {open_windows()}"
        ) from error
    evaluate(version, f"load {json.dumps(str(HELPERS))}")
    opened = evaluate(version, "File.basename(Sketchup.active_model.path.to_s)")
    if opened != model.name:
        raise BridgeError(f"SketchUp restored another document ({opened}); quit cleanly and launch again")
    return state


def save(version: str) -> str:
    return run_with_dialog_guard(version, "Sketchup.active_model.save; :saved")


def tail(path: Path, lines: int) -> str:
    if not path.is_file():
        return f"(no file at {path})"
    return "\n".join(path.read_text(errors="replace").splitlines()[-lines:])


# ----------------------------------------------------------------------------- commands

# One entry per command: how it extends the subparser, and what it does. A new command is one
# entry, not another branch in a chain that had grown to 82 lines and a second copy of `evaluate`.


def takes_nothing(parser: argparse.ArgumentParser) -> None:
    pass


def run_wait(args: argparse.Namespace, version: str) -> None:
    state = wait(version, args.timeout)
    print(f"bridge ready on port {state['port']} (pid {state['pid']})")


def run_ping(args: argparse.Namespace, version: str) -> None:
    print(evaluate(version, ":pong"))


def run_quit(args: argparse.Namespace, version: str) -> None:
    print(quit_sketchup(version))


def configure_launch(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("model")
    parser.add_argument("--fresh-from")


def run_launch(args: argparse.Namespace, version: str) -> None:
    state = launch(
        version,
        Path(args.model).resolve(),
        Path(args.fresh_from).resolve() if args.fresh_from else None,
        min(args.timeout, 180.0),
    )
    print(f"launched {args.model}; bridge on port {state['port']} (pid {state['pid']}); helpers loaded")


def configure_eval(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("code", nargs="?")
    parser.add_argument("--file")
    parser.add_argument("--json", action="store_true")


def run_eval(args: argparse.Namespace, version: str) -> int:
    code = Path(args.file).read_text() if args.file else args.code
    if code is None:
        raise BridgeError("eval needs code or --file")
    answer = reply(version, code, timeout=args.timeout)
    if args.json:
        print(json.dumps(answer, indent=2))
        return 0 if answer.get("ok") else 1
    if answer.get("stdout"):
        text = answer["stdout"]
        sys.stdout.write(text if text.endswith("\n") else text + "\n")
    if not answer.get("ok"):
        print(f"ERROR {answer.get('error')}", file=sys.stderr)
        for line in answer.get("backtrace", []):
            print(f"  {line}", file=sys.stderr)
        return 1
    value = answer.get("value")
    print(json.dumps(value) if value is not None else answer.get("result"))
    return 0


def run_state(args: argparse.Namespace, version: str) -> None:
    print(json.dumps(evaluate(version, "PhComposerHost.state"), indent=2))


def run_save(args: argparse.Namespace, version: str) -> None:
    print(save(version))


def configure_shot(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("name")
    parser.add_argument("--dir", required=True)


def run_shot(args: argparse.Namespace, version: str) -> None:
    name = json.dumps(args.name)
    directory = json.dumps(str(Path(args.dir).resolve()))
    print(evaluate(version, f"PhComposerHost.shot({name}, {directory})"))


def configure_key(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("key_code", type=int)


def run_key(args: argparse.Namespace, version: str) -> None:
    send_key(args.key_code)
    print(f"sent key code {args.key_code} to SketchUp")


def configure_tail(default: int) -> Callable[[argparse.ArgumentParser], None]:
    def configure(parser: argparse.ArgumentParser) -> None:
        parser.add_argument("--tail", type=int, default=default)

    return configure


def run_console(args: argparse.Namespace, version: str) -> None:
    state = read_state(version)
    path = (
        Path(state["console_log"])
        if state and state.get("console_log")
        else state_path(version).with_suffix(".console.log")
    )
    print(tail(path, args.tail))


def configure_show_model(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("title", help="text the document window's name and the Model's title both contain")
    parser.add_argument("--deadline", type=float, default=SHOW_DEADLINE_S, help="seconds to wait for the switch")


def run_show_model(args: argparse.Namespace, version: str) -> int:
    result = show_model(version, args.title, args.deadline)
    print(json.dumps(result, indent=2, allow_nan=False))
    if result["ending"] == "bridge_unavailable":
        return 2
    return 0 if result["ending"] == "shown" and result["restored"] else 1


def configure_wait_for(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("condition", help=f"one of {', '.join(sorted(host_wait.CONDITIONS))}")
    parser.add_argument("--param", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--deadline", type=float, default=host_wait.DEFAULT_DEADLINE_S, help="overall seconds")
    parser.add_argument("--interval", type=float, default=host_wait.DEFAULT_INTERVAL_S, help="seconds between polls")
    parser.add_argument("--json", action="store_true", help="print the versioned result document")
    parser.add_argument(
        "--diagnostics", action="store_true", help="add the session's recent warnings and errors from the log"
    )


def bridge_read(version: str) -> Callable[[str, float], Any]:
    """One wait poll: a single eval that must finish, connection to last byte, within the wait's remaining
    budget. Malformed bridge data is a lost bridge, not a crash."""

    def read(code: str, timeout: float) -> Any:
        deadline = time.monotonic() + timeout
        try:
            state = read_state(version)
            if state is None:
                raise ConnectionError("host bridge is not running (no live state file)")
            if not (isinstance(state, dict) and isinstance(state.get("token"), str)):
                raise ConnectionError("the bridge's state file is not a state document")
            left = deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError("finding the bridge used the whole remaining budget")
            answer = request(state, {"code": code}, timeout=left, whole=True)
        except (ValueError, TypeError, KeyError, OverflowError, UnicodeDecodeError) as error:
            # Includes JSONDecodeError: a partial state file or reply, or one of the wrong shape.
            raise ConnectionError(f"the bridge's state file or reply was malformed: {error}") from error
        if not isinstance(answer, dict):
            raise ConnectionError("the bridge's reply was not a result document")
        if not answer.get("ok"):
            raise host_wait.ReadError(str(answer.get("error")))
        return answer.get("value")

    return read


def run_wait_for(args: argparse.Namespace, version: str) -> int:
    params, refused = host_wait.parse_params(args.param)
    read = bridge_read(version)
    result = host_wait.wait_for(
        args.condition, params, read, refused=refused, deadline_s=args.deadline, interval_s=args.interval
    )
    # Read within what is left of the deadline; never after a cancel, a refusal or a lost bridge.
    if args.diagnostics and result.ending not in ("invalid_condition", "bridge_unavailable", "cancelled"):
        budget = args.deadline - result.elapsed_ms / 1000
        result.diagnostics = host_diagnostics.for_wait(read, params, budget)
    if args.json:
        print(json.dumps(result.document(), indent=2, allow_nan=False))
    else:
        print(result.summary())
        if result.diagnostics is not None:
            print(host_diagnostics.summary(result.diagnostics))
    if result.ending == "met":
        return 0
    return 2 if result.ending == "bridge_unavailable" else 1


def configure_diagnostics(parser: argparse.ArgumentParser) -> None:
    for name in ("session", "incident", "run-id", "severity", "cursor"):
        parser.add_argument(f"--{name}")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--newest", action="store_true", help="the most recent matches instead of a page")
    parser.add_argument("--json", action="store_true", help="print the versioned read document")


def run_diagnostics(args: argparse.Namespace, version: str) -> int:
    names = {"session": "session", "incident": "incident", "run_id": "run_id", "severity": "severity"}
    filters: dict[str, Any] = {key: getattr(args, attr) for key, attr in names.items() if getattr(args, attr)}
    if args.cursor:
        filters["cursor"] = args.cursor
    if args.limit is not None:
        filters["limit"] = args.limit
    if args.newest:
        filters["newest"] = True
    try:
        document = host_diagnostics.read(bridge_read(version), filters, timeout=args.timeout)
    except host_wait.ReadError as error:
        raise BridgeError(str(error)) from error
    print(json.dumps(document, indent=2, allow_nan=False) if args.json else host_diagnostics.summary(document))
    return 0 if document.get("status") == "read" else 1


def configure_fault(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("operation", choices=host_faults.OPERATIONS)
    parser.add_argument("fault", choices=host_faults.NAMES)
    parser.add_argument("--session")
    parser.add_argument("--request", help="lost_reply: the request id whose result is dropped")
    parser.add_argument("--drop", action="append", help="silent_runtime: a runtime message type to drop")
    parser.add_argument("--key", help="failed_write: the display-preference key whose writes fail")
    parser.add_argument("--json", action="store_true", help="print the versioned control document")


def run_fault(args: argparse.Namespace, version: str) -> int:
    target = {name: value for name in ("session", "request", "drop", "key") if (value := getattr(args, name))}
    try:
        document = host_faults.run(bridge_read(version), args.operation, args.fault, target)
    except host_wait.ReadError as error:
        raise BridgeError(str(error)) from error
    output = (
        json.dumps(document, indent=2, allow_nan=False) if args.json else host_faults.summary(args.operation, document)
    )
    print(output)
    return 0 if host_faults.succeeded(args.operation, document) else 1


COMMANDS: dict[str, tuple[Callable[[argparse.ArgumentParser], None], Callable[..., Any]]] = {
    "wait": (takes_nothing, run_wait),
    "ping": (takes_nothing, run_ping),
    "quit": (takes_nothing, run_quit),
    "launch": (configure_launch, run_launch),
    "eval": (configure_eval, run_eval),
    "state": (takes_nothing, run_state),
    "save": (takes_nothing, run_save),
    "shot": (configure_shot, run_shot),
    "key": (configure_key, run_key),
    "console": (configure_tail(40), run_console),
    "show-model": (configure_show_model, run_show_model),
    "wait-for": (configure_wait_for, run_wait_for),
    "diagnostics": (configure_diagnostics, run_diagnostics),
    "fault": (configure_fault, run_fault),
}


# ----------------------------------------------------------------------------- CLI


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sketchup-version", default="2026")
    parser.add_argument("--timeout", type=float, default=300.0, help="seconds to wait for a reply or a completion")
    sub = parser.add_subparsers(dest="command", required=True)
    for name, (configure, _run) in COMMANDS.items():
        configure(sub.add_parser(name))
    args = parser.parse_args()

    try:
        return COMMANDS[args.command][1](args, args.sketchup_version) or 0
    except BridgeError as error:
        print(f"ERROR {error}", file=sys.stderr)
        return 1
    except (OSError, TimeoutError) as error:
        print(f"host bridge unreachable: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    sys.exit(main())
