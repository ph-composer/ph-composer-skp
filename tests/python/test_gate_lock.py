"""tools/gate_lock.py: two gates never run at once, even after the first wrapper is killed."""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

LOCK_SCRIPT = Path(__file__).resolve().parents[2] / "tools" / "gate_lock.py"
DEADLINE = 20.0


def run_locked(lock: Path, command: str) -> subprocess.Popen[str]:
    env = {**os.environ, "PH_COMPOSER_GATE_LOCK": str(lock)}
    return subprocess.Popen(
        [sys.executable, str(LOCK_SCRIPT), "sh", "-c", command], env=env, stdout=subprocess.PIPE, text=True
    )


def wait_for(path: Path) -> None:
    end = time.monotonic() + DEADLINE
    while not path.exists():
        assert time.monotonic() < end, f"{path.name} never appeared"
        time.sleep(0.02)


def held_command(tmp_path: Path, log: Path) -> str:
    """A first gate that signals it holds the lock and finishes only when told to."""
    started, release = tmp_path / "started", tmp_path / "release"
    return f"touch {started}; while [ ! -f {release} ]; do sleep 0.02; done; echo first-end >> {log}"


def test_a_second_gate_waits_for_the_first_to_finish(tmp_path: Path) -> None:
    lock, log = tmp_path / "gate.lock", tmp_path / "order"
    first = run_locked(lock, held_command(tmp_path, log))
    wait_for(tmp_path / "started")
    second = run_locked(lock, f"echo second >> {log}")
    assert second.stdout is not None
    assert "waiting" in second.stdout.readline()
    (tmp_path / "release").touch()
    first.wait(timeout=DEADLINE)
    second.wait(timeout=DEADLINE)
    assert log.read_text().split() == ["first-end", "second"]


def test_the_lock_stays_held_while_a_killed_wrappers_command_runs(tmp_path: Path) -> None:
    lock, log = tmp_path / "gate.lock", tmp_path / "order"
    first = run_locked(lock, held_command(tmp_path, log))
    wait_for(tmp_path / "started")
    first.kill()
    first.wait(timeout=DEADLINE)
    second = run_locked(lock, f"echo second >> {log}")
    assert second.stdout is not None
    assert "waiting" in second.stdout.readline()
    (tmp_path / "release").touch()
    second.wait(timeout=DEADLINE)
    assert log.read_text().split() == ["first-end", "second"]


def test_the_command_exit_status_is_returned(tmp_path: Path) -> None:
    gate = run_locked(tmp_path / "gate.lock", "exit 3")
    gate.wait(timeout=DEADLINE)
    assert gate.returncode == 3
