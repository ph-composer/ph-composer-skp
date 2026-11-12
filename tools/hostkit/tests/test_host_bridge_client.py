"""Exercise the bridge client's transport and dialog guard without SketchUp, a port or a clock.

The client is what every host gate runs through, so a defect here reads as a host defect. The
socket, the child process, System Events and the clock are all replaced: what is under test is
the client's own decisions, not the machine it usually talks to.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import shutil
import socket
import subprocess
import threading
import time
import unittest
from collections.abc import Callable
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import ClassVar, Self
from unittest.mock import patch

import host_bridge as hb


class FakeSocket:
    """A connection that answers once, in as many chunks as the test asks for."""

    def __init__(self, chunks: list[bytes]) -> None:
        self.chunks = list(chunks)
        self.sent = b""

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *_exception: object) -> None:
        self.chunks = []

    def sendall(self, payload: bytes) -> None:
        self.sent += payload

    def settimeout(self, _seconds: float) -> None:
        pass

    def recv(self, _size: int) -> bytes:
        return self.chunks.pop(0) if self.chunks else b""


class FakeChild:
    """A child process that stays alive for `alive_polls` polls, then exits with `returncode`."""

    def __init__(self, alive_polls: int, returncode: int = 0, out: bytes = b"saved\n") -> None:
        self.alive_polls = alive_polls
        self.returncode = returncode
        self.out = out
        self.killed = False

    def poll(self) -> int | None:
        if self.alive_polls > 0:
            self.alive_polls -= 1
            return None
        return self.returncode

    def communicate(self) -> tuple[bytes, bytes]:
        return self.out, b""

    def kill(self) -> None:
        self.killed = True


class FakeClock:
    """A clock that only advances when the code under test sleeps."""

    def __init__(self) -> None:
        self.now = 1000.0

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


class ReadStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        support = Path(self.directory.name)
        patcher = patch.object(hb, "SUPPORT", support)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.path = hb.state_path("2026")
        self.path.parent.mkdir(parents=True)

    def write_state(self, pid: int) -> None:
        self.path.write_text(json.dumps({"pid": pid, "port": 51000, "token": "t"}))

    def test_no_state_file_means_no_bridge(self) -> None:
        self.assertIsNone(hb.read_state("2026"))

    def test_a_state_file_for_a_dead_process_is_not_a_live_bridge(self) -> None:
        # The file outlives the process it describes: SketchUp can be killed, or crash, and the
        # client must not report a bridge that nothing is listening on.
        self.write_state(2_000_000_000)
        self.assertIsNone(hb.read_state("2026"))

    def test_a_state_file_naming_a_process_group_or_an_impossible_pid_is_not_a_live_bridge(self) -> None:
        for pid in (0, -1, 99_999_999_999_999_999_999):
            with self.subTest(pid=pid):
                self.write_state(pid)
                self.assertIsNone(hb.read_state("2026"))

    def test_a_state_file_for_a_live_process_is_returned(self) -> None:
        self.write_state(os.getpid())  # this process: alive, and signalable without privileges
        state = hb.read_state("2026")
        assert state is not None
        self.assertEqual(state["port"], 51000)


class RequestTest(unittest.TestCase):
    state: ClassVar[dict[str, object]] = {"pid": 1, "port": 51000, "token": "secret-token"}

    def send(self, chunks: list[bytes]) -> FakeSocket:
        sock = FakeSocket(chunks)
        with patch.object(hb.socket, "create_connection", return_value=sock):
            self.reply = hb.request(self.state, {"code": ":ok"}, timeout=5.0)
        return sock

    def test_the_token_is_added_and_one_newline_terminated_line_is_sent(self) -> None:
        sock = self.send([b'{"ok":true,"value":1}\n'])

        self.assertEqual(sock.sent.count(b"\n"), 1)
        self.assertEqual(json.loads(sock.sent.decode()), {"code": ":ok", "token": "secret-token"})
        self.assertEqual(self.reply, {"ok": True, "value": 1})

    def test_a_reply_split_across_chunks_is_reassembled(self) -> None:
        # The bridge answers with whole result documents, which run past one recv.
        self.send([b'{"ok":true,"val', b'ue":{"a":1}}', b"\n"])

        self.assertEqual(self.reply, {"ok": True, "value": {"a": 1}})

    def test_a_closed_connection_with_no_reply_is_an_error_not_an_empty_result(self) -> None:
        with self.assertRaises(ConnectionError):
            self.send([])


class EvaluateTest(unittest.TestCase):
    def test_without_a_live_state_file_evaluate_refuses_before_connecting(self) -> None:
        with patch.object(hb, "read_state", return_value=None), self.assertRaises(hb.BridgeError):
            hb.evaluate("2026", ":ok")

    def test_a_ruby_error_reply_becomes_a_bridge_error_carrying_the_backtrace(self) -> None:
        answer = {"ok": False, "error": "NoMethodError", "backtrace": ["a.rb:1", "b.rb:2"]}
        with patch.object(hb, "reply", return_value=answer), self.assertRaises(hb.BridgeError) as raised:
            hb.evaluate("2026", "nope")

        self.assertIn("NoMethodError", str(raised.exception))
        self.assertIn("a.rb:1", str(raised.exception))

    def test_inspect_text_is_returned_when_the_value_did_not_serialize(self) -> None:
        with patch.object(hb, "reply", return_value={"ok": True, "result": "#<Sketchup::Model>"}):
            self.assertEqual(hb.evaluate("2026", "m"), "#<Sketchup::Model>")


class WaitReadTest(unittest.TestCase):
    """A wait poll is one eval: a host error is a read failure, a missing bridge is a lost connection."""

    def test_a_ruby_error_reply_is_a_read_error_and_a_value_is_returned(self) -> None:
        read = hb.bridge_read("2026")
        with patch.object(hb, "read_state", return_value={"port": 1, "token": "t"}):
            with (
                patch.object(hb, "request", return_value={"ok": False, "error": "NameError"}),
                self.assertRaises(hb.host_wait.ReadError),
            ):
                read(":x", 1.0)
            with patch.object(hb, "request", return_value={"ok": True, "value": {"busy": None}}) as sent:
                self.assertEqual(read(":x", 2.5), {"busy": None})
        self.assertAlmostEqual(sent.call_args.kwargs["timeout"], 2.5, delta=0.1, msg="the request gets what is left")
        self.assertLessEqual(sent.call_args.kwargs["timeout"], 2.5)

    def test_no_live_bridge_is_a_connection_error(self) -> None:
        with patch.object(hb, "read_state", return_value=None), self.assertRaises(ConnectionError):
            hb.bridge_read("2026")(":x", 1.0)

    def test_a_malformed_state_file_or_truncated_reply_is_a_lost_bridge_not_a_crash(self) -> None:
        read = hb.bridge_read("2026")
        with (
            patch.object(hb, "read_state", side_effect=json.JSONDecodeError("partial", "{", 1)),
            self.assertRaises(ConnectionError),
        ):
            read(":x", 1.0)
        with (
            patch.object(hb, "read_state", return_value={"port": 1, "token": "t"}),
            patch.object(hb.socket, "create_connection", return_value=FakeSocket([b'{"ok":tr'])),
            self.assertRaises(ConnectionError),
        ):
            read(":x", 1.0)

    def test_a_state_document_of_the_wrong_shape_is_a_lost_bridge(self) -> None:
        read = hb.bridge_read("2026")
        for state in ([], {"port": "invalid", "token": "t"}, {"port": 1}):
            with (
                self.subTest(state=state),
                patch.object(hb, "read_state", return_value=state),
                self.assertRaises(ConnectionError),
            ):
                read(":x", 1.0)

    def test_an_oversized_poll_reply_is_malformed_not_parsed(self) -> None:
        big = [b'{"ok":true,"value":"', b"x" * (hb.MAX_WHOLE_REPLY_BYTES + 1), b'"}\n']
        with (
            patch.object(hb, "read_state", return_value={"port": 1, "token": "t"}),
            patch.object(hb.socket, "create_connection", return_value=FakeSocket(big)),
            self.assertRaises(ConnectionError),
        ):
            hb.bridge_read("2026")(":x", 1.0)

    def test_finding_the_bridge_counts_against_the_budget(self) -> None:
        def slow_state(_version: str) -> dict[str, object]:
            time.sleep(0.15)
            return {"port": 1, "token": "t"}

        with (
            patch.object(hb, "read_state", side_effect=slow_state),
            patch.object(hb, "request") as sent,
            self.assertRaises(TimeoutError),
        ):
            hb.bridge_read("2026")(":x", 0.1)
        sent.assert_not_called()

    def test_a_whole_request_deadline_bounds_a_slow_multipart_reply(self) -> None:
        # A real loopback socket: the reply arrives in three parts 200 ms apart, so each recv alone would
        # fit a 300 ms per-operation timeout while the request as a whole does not.
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)

        def answer() -> None:
            connection, _address = server.accept()
            with connection:
                connection.recv(65536)
                for part in (b'{"ok":true,', b'"value":1', b"}\n"):
                    time.sleep(0.2)
                    with contextlib.suppress(OSError):  # the client has given up by the last part
                        connection.sendall(part)

        thread = threading.Thread(target=answer, daemon=True)
        thread.start()
        state = {"port": server.getsockname()[1], "token": "t"}
        started = time.monotonic()
        with self.assertRaises(TimeoutError):
            hb.request(state, {"code": ":x"}, timeout=0.3, whole=True)
        self.assertLess(time.monotonic() - started, 0.45)
        thread.join(2)
        server.close()


class DialogGuardTest(unittest.TestCase):
    """The guard exists because SketchUp's Purge Unused prompt blocks the save it was asked for."""

    def guard(self, child: FakeChild, **options: float) -> tuple[str, list[int], FakeChild]:
        clock = FakeClock()
        keys: list[int] = []
        with (
            patch.object(hb, "evaluate_in_background", return_value=child),
            patch.object(hb, "send_key", side_effect=keys.append),
            patch.object(hb.time, "monotonic", clock.monotonic),
            patch.object(hb.time, "sleep", clock.sleep),
        ):
            return hb.run_with_dialog_guard("2026", ":ok", **options), keys, child

    def test_a_reply_within_escape_after_never_sends_a_key(self) -> None:
        out, keys, _ = self.guard(FakeChild(alive_polls=2))

        self.assertEqual(out, "saved")
        self.assertEqual(keys, [])

    def test_escape_goes_to_sketchup_once_per_second_after_the_grace_period(self) -> None:
        _out, keys, _ = self.guard(FakeChild(alive_polls=6), escape_after=3.0)

        # Polls at 1s to 6s: the first three are inside the grace period, the last three are not.
        self.assertEqual(keys, [hb.ESCAPE_KEY_CODE] * 3)

    def test_a_child_that_never_returns_is_killed_and_reported_as_an_open_dialog(self) -> None:
        child = FakeChild(alive_polls=100)
        with self.assertRaises(hb.BridgeError) as raised:
            self.guard(child, timeout=10.0)

        self.assertTrue(child.killed)
        self.assertIn("dialog may still be open", str(raised.exception))

    def test_a_failed_child_reports_its_own_error_rather_than_a_guard_timeout(self) -> None:
        with self.assertRaises(hb.BridgeError) as raised:
            self.guard(FakeChild(alive_polls=1, returncode=1, out=b"ERROR RuntimeError\n"))

        self.assertIn("RuntimeError", str(raised.exception))


class QuitTest(unittest.TestCase):
    """Every open document is closed, its changes discarded, before terminate; no document still means a clean quit."""

    def quit_with(
        self,
        replies: list[object],
        active: Callable[[list[str]], str] = lambda _calls: "another-document",
        windows: list[str] | None = None,
    ) -> tuple[str, list[str]]:
        """`active` answers the active-document check, given the calls so far; `windows` answers each raise."""
        calls: list[str] = []
        answers = iter(replies)
        raises = iter(windows or [])

        def guard(_version: str, code: str, **_options: float) -> str:
            calls.append(code)
            answer = next(answers)
            if isinstance(answer, Exception):
                raise answer
            return f"console line mentioning none\n{answer}\n"

        def raise_document(_version: str) -> str:
            calls.append("raise")
            return next(raises, "phc_no_window")

        running = iter([True, False])
        with (
            patch.object(hb, "sketchup_running", side_effect=lambda: next(running)),
            patch.object(hb, "read_state", return_value={"port": 1, "token": "t"}),
            patch.object(hb, "run_with_dialog_guard", side_effect=guard),
            patch.object(hb, "evaluate", side_effect=lambda *_args, **_kw: active(calls)),
            patch.object(hb, "raise_document", side_effect=raise_document),
            patch.object(hb, "request", side_effect=lambda _state, payload, **_kw: calls.append(payload["code"])),
            patch.object(hb.time, "sleep"),
        ):
            return hb.quit_sketchup("2026"), calls

    def test_each_open_document_is_closed_until_none_is_left_then_terminate(self) -> None:
        outcome, calls = self.quit_with(['"phc_closed:g1"', '"phc_closed:g2"', '"phc_no_document"'])
        self.assertEqual(outcome, "SketchUp quit cleanly (closed 2 documents)")
        self.assertEqual(calls[:2], [hb.CLOSE_ACTIVE, hb.CLOSE_ACTIVE])
        self.assertEqual(calls[-2:], ["raise", 'Sketchup.send_action("terminate:")'])

    def test_a_failed_close_step_is_reported_and_still_terminates(self) -> None:
        outcome, calls = self.quit_with([hb.BridgeError("the close step failed")])
        self.assertEqual(
            outcome, "SketchUp quit cleanly (closed 0 documents; the close step failed: the close step failed)"
        )
        self.assertEqual(calls[-1], 'Sketchup.send_action("terminate:")')

    def test_a_document_that_stays_active_is_reported_open_not_closed(self) -> None:
        # Counting a close that did nothing as closed on every pass reported "closed 8 documents" for one.
        outcome, calls = self.quit_with(['"phc_closed:g1"'], active=lambda _calls: "g1")
        self.assertEqual(
            outcome,
            "SketchUp quit cleanly (closed 0 documents; stopped: the active document stayed open after its close)",
        )
        self.assertEqual(calls[1:], ['Sketchup.send_action("terminate:")'])

    def test_a_document_left_without_an_active_model_is_raised_and_closed(self) -> None:
        # Closing the active document in the background leaves no active Model while another window is open.
        outcome, calls = self.quit_with(
            ['"phc_closed:g1"', '"phc_no_document"', '"phc_closed:g2"', '"phc_no_document"'], windows=["phc_raised"]
        )
        self.assertEqual(outcome, "SketchUp quit cleanly (closed 2 documents)")
        self.assertEqual(calls.count("raise"), 2)
        outcome, _calls = self.quit_with(['"phc_no_document"', '"phc_no_document"'], windows=["phc_raised"])
        self.assertIn("a document window is open but no Model is active", outcome)

    def test_a_raise_that_fails_or_an_unexpected_answer_stops_the_count_and_says_why(self) -> None:
        outcome, _calls = self.quit_with(['"phc_no_document"'], windows=["not allowed assistive access"])
        self.assertIn("no active Model and no window could be raised: not allowed assistive access", outcome)
        outcome, _calls = self.quit_with(['""'])
        self.assertEqual(outcome, "SketchUp quit cleanly (closed 0 documents; stopped: the close step answered '')")

    def test_the_raise_reads_osascript_s_answer_or_its_failure(self) -> None:
        replies = (
            (subprocess.CompletedProcess([], 0, "phc_raised\n", ""), "phc_raised"),
            (subprocess.CompletedProcess([], 0, "phc_no_window\n", ""), "phc_no_window"),
            (subprocess.CompletedProcess([], 1, "", "execution error\n"), "execution error"),
        )
        for done, expected in replies:
            with (
                patch.object(hb.subprocess, "run", return_value=done),
                patch.object(hb, "frontmost_app", return_value=None),
                patch.object(hb.time, "sleep"),
            ):
                self.assertEqual(hb.raise_document("2026"), expected)

    @unittest.skipUnless(shutil.which("ruby"), "needs a ruby to run the close step")
    def test_the_close_step_discards_changes_without_saving_and_tolerates_no_document(self) -> None:
        # A save to a scratch path is a Save As, which moves a "This Model only" agent token onto it.
        stub = (
            'class M; def guid; "G"; end; def save(path); $saved = path; true; end; '
            "def close(ignore_changes = false); $closed = ignore_changes; nil; end; end; "
            "module Sketchup; def self.active_model; $model; end; "
            "def self.send_action(action); $action = action; true; end; end; "
        )
        cases = (
            ("nil", [":phc_no_document", "nil", "nil", "nil"]),
            ("M.new", ['"phc_closed:G"', "true", "nil", "nil"]),
        )
        for model, expected in cases:
            script = (
                f"{stub}$model = {model}; value = ({hb.CLOSE_ACTIVE}); "
                "puts value.inspect, $closed.inspect, $saved.inspect, $action.inspect"
            )
            result = subprocess.run(["ruby", "-e", script], capture_output=True, text=True, check=True)
            self.assertEqual(result.stdout.split(), expected, model)


class LaunchTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        patcher = patch.object(hb, "SUPPORT", Path(self.directory.name))
        patcher.start()
        self.addCleanup(patcher.stop)

    def launch(self, model: Path, wait: object) -> None:
        with (
            patch.object(hb, "quit_sketchup", return_value="SketchUp not running"),
            patch.object(hb, "sketchup_running", return_value=False),
            patch.object(hb.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)),
            patch.object(hb, "wait", side_effect=wait),
            patch.object(hb, "evaluate", side_effect=[None, model.name]),
            patch.object(hb, "open_windows", return_value="Open File"),
            patch.object(hb.time, "sleep"),
            patch("builtins.print"),
        ):
            hb.launch("2026", model, None, 5.0)

    def test_a_scratch_fixtures_recovery_copy_is_removed_before_the_open(self) -> None:
        with TemporaryDirectory() as folder:
            copy = Path(folder) / "a09.skp"
            copy.write_text("autosave")
            with patch.object(hb, "recovery_copy", return_value=copy):
                self.launch(Path("/repo/_private/run/a09.skp"), lambda *_args: {"port": 1, "pid": 2})
            self.assertFalse(copy.exists())

    def test_a_launch_that_never_reaches_the_bridge_names_the_open_windows_and_stays_a_timeout(self) -> None:
        with patch.object(hb, "recovery_copy", return_value=None), self.assertRaises(TimeoutError) as raised:
            self.launch(Path("/repo/_private/run/a09.skp"), TimeoutError("no host bridge within 5s"))
        self.assertIn("Open windows: Open File", str(raised.exception))


class StalledLaunchTest(unittest.TestCase):
    """SketchUp opened in the background can load no extension, the bridge included, until activated once."""

    def wait_for_launch(self, waits: list[object], running: bool = True, state_file: bool = False) -> list[str]:
        activated: list[str] = []
        with TemporaryDirectory() as folder, patch.object(hb, "SUPPORT", Path(folder)):
            if state_file:
                hb.state_path("2026").parent.mkdir(parents=True)
                hb.state_path("2026").write_text("{}")
            with (
                patch.object(hb, "wait", side_effect=waits),
                patch.object(hb, "sketchup_running", return_value=running),
                patch.object(hb, "activate_sketchup_once", side_effect=activated.append),
                patch("builtins.print"),
            ):
                self.state = hb.wait_for_launch("2026", 180.0)
        return activated

    def test_a_bridge_that_starts_on_its_own_is_never_activated(self) -> None:
        self.assertEqual(self.wait_for_launch([{"port": 1}]), [])

    def test_no_state_file_after_the_threshold_activates_sketchup_once_and_keeps_waiting(self) -> None:
        self.assertEqual(self.wait_for_launch([TimeoutError("no host bridge"), {"port": 1}]), ["2026"])
        self.assertEqual(self.state, {"port": 1})

    def test_time_spent_activating_comes_out_of_the_launch_timeout(self) -> None:
        clock = FakeClock()
        budgets: list[float] = []

        def waited(_version: str, budget: float) -> dict[str, int]:
            budgets.append(budget)
            clock.sleep(budget)
            if len(budgets) == 1:
                raise TimeoutError("no host bridge")
            return {"port": 1}

        with (
            TemporaryDirectory() as folder,
            patch.object(hb, "SUPPORT", Path(folder)),
            patch.object(hb.time, "monotonic", clock.monotonic),
            patch.object(hb, "activate_sketchup_once", side_effect=lambda _version: clock.sleep(10.0)),
            patch.object(hb, "sketchup_running", return_value=True),
            patch.object(hb, "wait", side_effect=waited),
            patch("builtins.print"),
        ):
            hb.wait_for_launch("2026", 180.0)
        self.assertEqual(budgets, [hb.ACTIVATE_AFTER, 180.0 - hb.ACTIVATE_AFTER - 10.0])

    def test_a_written_state_file_or_a_sketchup_not_running_is_not_the_stall_and_the_wait_runs_on(self) -> None:
        # The bridge writes its state before its main-thread pump answers, so a slow start is not a stall.
        for options in ({"state_file": True}, {"running": False}):
            self.assertEqual(self.wait_for_launch([TimeoutError("no host bridge"), {"port": 1}], **options), [])
            self.assertEqual(self.state, {"port": 1})

    def test_activation_hands_focus_back_to_the_app_that_had_it(self) -> None:
        for previous, expected in (
            ("com.apple.Terminal", ["com.sketchup.SketchUp.2026", "com.apple.Terminal"]),
            (None, ["com.sketchup.SketchUp.2026"]),
        ):
            activated: list[str] = []
            with (
                patch.object(hb, "frontmost_app", return_value=previous),
                patch.object(hb, "activate_app", side_effect=activated.append),
                patch.object(hb.time, "sleep"),
            ):
                hb.activate_sketchup_once("2026")
            self.assertEqual(activated, expected, previous)

    def test_a_focus_change_that_times_out_never_aborts_the_launch_or_quit(self) -> None:
        timeout = subprocess.TimeoutExpired(["osascript"], 15)
        with patch.object(hb.subprocess, "run", side_effect=timeout), patch.object(hb.time, "sleep"):
            hb.activate_sketchup_once("2026")
            self.assertEqual(hb.raise_document("2026"), str(timeout))


class ShowModelTest(unittest.TestCase):
    """show-model fronts SketchUp only for exactly one matching window, waits for the switch, and hands focus
    back by process name once a raise was attempted. osascript, the bridge and the clock are stubbed."""

    WINDOW = 'b07 "draft" - SketchUp Pro 2026'
    OTHER = "a09 - SketchUp Pro 2026"

    def show(
        self,
        windows: list[str] | None = None,
        raised: subprocess.CompletedProcess[str] | None = None,
        titles: list[object] | None = None,
        frontmost: list[str] | None = None,
        wanted: str = 'B07 "draft"',
        deadline: float = 5.0,
    ) -> tuple[dict[str, object], list[list[str]]]:
        """`windows` answers the listing, `raised` the raise, `titles` each title read, `frontmost` each
        frontmost read. Failures come back as osascript gives them: a non-zero exit with stderr."""
        calls: list[list[str]] = []
        listing = "\n".join(windows if windows is not None else [self.OTHER, self.WINDOW])
        title_reads = iter(titles if titles is not None else ["a09", 'b07 "draft"'])
        frontmost_reads = iter(frontmost if frontmost is not None else ["Rhinoceros", "Rhinoceros"])
        clock = FakeClock()

        def run(command: list[str], **_options: object) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            script = command[2]
            if script == hb.FRONTMOST_PROCESS:
                return subprocess.CompletedProcess(command, 0, f"{next(frontmost_reads, '')}\n", "")
            if script == hb.DOCUMENT_WINDOWS:
                return subprocess.CompletedProcess(command, 0, f"{listing}\n", "")
            if script == hb.RAISE_WINDOW:
                return raised or subprocess.CompletedProcess(command, 0, "phc_raised\n", "")
            return subprocess.CompletedProcess(command, 0, "", "")

        def read(code: str, _timeout: float) -> object:
            self.assertEqual(code, hb.ACTIVE_TITLE)
            answer = next(title_reads, "a09")
            if isinstance(answer, BaseException):
                raise answer
            return answer

        with (
            patch.object(hb.subprocess, "run", side_effect=run),
            patch.object(hb, "bridge_read", return_value=read),
            patch.object(hb.time, "monotonic", clock.monotonic),
            patch.object(hb.time, "sleep", clock.sleep),
        ):
            return hb.show_model("2026", wanted, deadline), calls

    def scripts(self, calls: list[list[str]]) -> list[str]:
        names = {
            hb.FRONTMOST_PROCESS: "frontmost",
            hb.DOCUMENT_WINDOWS: "list",
            hb.RAISE_WINDOW: "raise",
            hb.FRONT_PROCESS: "restore",
        }
        return [names[command[2]] for command in calls]

    def test_one_matching_window_is_raised_the_switch_awaited_and_focus_handed_back_by_process_name(self) -> None:
        result, calls = self.show()
        self.assertEqual(
            result,
            {
                "ending": "shown",
                "wanted": 'B07 "draft"',
                "window": self.WINDOW,
                "before": "a09",
                "shown": 'b07 "draft"',
                "previous": "Rhinoceros",
                "restored": True,
                "error": None,
            },
        )
        self.assertEqual(self.scripts(calls), ["frontmost", "list", "raise", "restore", "frontmost"])
        # Values travel as argv after `--`, never inside a script's source.
        self.assertEqual(calls[2][3:], ["--", self.WINDOW])
        self.assertEqual(calls[3][3:], ["--", "Rhinoceros"])

    def test_no_match_or_more_than_one_match_is_refused_without_fronting_or_restoring(self) -> None:
        for windows, wanted, error in (
            ([self.OTHER], "b07", "no document window's title contains"),
            # Only the title part counts: the suffix would match a window the Model's title never contains.
            ([self.OTHER, self.WINDOW], "SketchUp Pro", "no document window's title contains"),
            ([self.WINDOW, 'b07 "draft" copy - SketchUp Pro 2026'], "b07", "more than one document window"),
        ):
            result, calls = self.show(windows=windows, wanted=wanted)
            self.assertEqual(result["ending"], "refused", wanted)
            self.assertIn(error, str(result["error"]))
            self.assertEqual((result["restored"], result["shown"]), (None, None))
            self.assertEqual(self.scripts(calls), ["frontmost", "list"])

    def test_nothing_is_fronted_when_a_check_before_the_raise_fails(self) -> None:
        cases = (
            ("unreadable frontmost", lambda: self.show(frontmost=[""]), "refused", ["frontmost"]),
            ("no bridge", lambda: self.show(titles=[ConnectionError("no bridge")]), "bridge_unavailable", []),
            ("blank text", lambda: self.show(wanted="  "), "refused", []),
            ("NaN deadline", lambda: self.show(deadline=float("nan")), "refused", []),
            ("zero deadline", lambda: self.show(deadline=0.0), "refused", []),
            ("long deadline", lambda: self.show(deadline=hb.MAX_SHOW_DEADLINE_S + 1), "refused", []),
        )
        for label, show, ending, scripts in cases:
            result, calls = show()
            self.assertEqual((result["ending"], self.scripts(calls)), (ending, scripts), label)

    def test_a_raise_that_fails_still_hands_focus_back(self) -> None:
        # The raise fronts SketchUp before AXRaise, so a failure after it may already have changed the screen.
        failed = subprocess.CompletedProcess([], 1, "", "execution error: AXRaise failed (-1719)\n")
        result, calls = self.show(raised=failed)
        self.assertEqual((result["ending"], result["restored"]), ("raise_failed", True))
        self.assertIn("AXRaise failed", str(result["error"]))
        self.assertEqual(self.scripts(calls)[-2:], ["restore", "frontmost"])

    def test_a_switch_that_never_comes_ends_at_the_deadline_and_still_hands_focus_back(self) -> None:
        result, calls = self.show(titles=["a09"] * 100)
        self.assertEqual((result["ending"], result["shown"], result["restored"]), ("timed_out", "a09", True))
        self.assertEqual(self.scripts(calls)[-2:], ["restore", "frontmost"])
        for failure, ending in (
            (hb.host_wait.ReadError("NoMethodError"), "read_failed"),
            (ConnectionResetError("the bridge went away"), "bridge_unavailable"),
            (KeyboardInterrupt(), "cancelled"),
        ):
            result, _calls = self.show(titles=["a09", failure])
            self.assertEqual((result["ending"], result["restored"]), (ending, True))

    def test_a_restore_that_does_not_take_reports_restored_false(self) -> None:
        result, calls = self.show(frontmost=["Rhinoceros"] + ["SketchUp"] * 20)
        self.assertEqual((result["ending"], result["restored"]), ("shown", False))
        self.assertEqual(self.scripts(calls).count("frontmost"), 1 + hb.RESTORE_CHECKS + 1)

    def test_the_command_exits_zero_only_when_shown_and_restored(self) -> None:
        args = argparse.Namespace(title="b07", deadline=5.0)
        for result, code in (
            ({"ending": "shown", "restored": True}, 0),
            ({"ending": "shown", "restored": False}, 1),
            ({"ending": "raise_failed", "restored": True}, 1),
            ({"ending": "refused", "restored": None}, 1),
            ({"ending": "bridge_unavailable", "restored": None}, 2),
        ):
            with patch.object(hb, "show_model", return_value=result), patch("builtins.print"):
                self.assertEqual(hb.run_show_model(args, "2026"), code, result)


class RecoveryCopyTest(unittest.TestCase):
    def test_only_a_scratch_fixture_has_its_recovery_copy_cleared(self) -> None:
        working = hb.SUPPORT / "SketchUp 2026" / "SketchUp" / "working"
        self.assertEqual(hb.recovery_copy("2026", Path("/repo/_private/host/run/a09.skp")), working / "a09.skp")
        self.assertEqual(hb.recovery_copy("2026", Path("/private/tmp/scratch.skp")), working / "scratch.skp")
        self.assertIsNone(hb.recovery_copy("2026", Path("/Users/someone/Projects/house.skp")))


class TailTest(unittest.TestCase):
    def test_tail_names_a_missing_file_instead_of_printing_nothing(self) -> None:
        with TemporaryDirectory() as directory:
            absent = Path(directory) / "console.log"
            self.assertIn(str(absent), hb.tail(absent, 10))

    def test_tail_returns_the_last_lines_and_survives_undecodable_bytes(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "console.log"
            path.write_bytes(b"one\ntwo\n" + b"\xff\xfe" + b"\nfour\n")

            self.assertEqual(hb.tail(path, 2).splitlines()[-1], "four")


class CommandRegistryTest(unittest.TestCase):
    def test_the_registry_is_exactly_the_documented_command_set(self) -> None:
        # Exact, not a subset: a command silently dropped from the registry is a command the
        # usage block still promises.
        self.assertEqual(
            set(hb.COMMANDS),
            {
                "wait",
                "ping",
                "quit",
                "launch",
                "eval",
                "state",
                "save",
                "shot",
                "key",
                "console",
                "show-model",
                "wait-for",
                "diagnostics",
                "fault",
            },
        )
        for name, (configure, run) in hb.COMMANDS.items():
            self.assertTrue(callable(configure), name)
            self.assertTrue(callable(run), name)


if __name__ == "__main__":
    unittest.main()
