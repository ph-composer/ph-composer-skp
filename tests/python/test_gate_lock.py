"""tools/gate_lock.py: two gates never run at once, and nothing a finished holder left behind blocks the next."""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

LOCK_SCRIPT = Path(__file__).resolve().parents[2] / "tools" / "gate_lock.py"


def run_locked(lock: Path, command: str) -> subprocess.Popen[str]:
    env = {**os.environ, "PH_COMPOSER_GATE_LOCK": str(lock)}
    return subprocess.Popen(
        [sys.executable, str(LOCK_SCRIPT), "sh", "-c", command], env=env, stdout=subprocess.PIPE, text=True
    )


def test_a_second_gate_waits_for_the_first_to_finish(tmp_path: Path) -> None:
    lock = tmp_path / "gate.lock"
    log = tmp_path / "order"
    first = run_locked(lock, f"echo first-start >> {log}; sleep 1; echo first-end >> {log}")
    time.sleep(0.3)
    second = run_locked(lock, f"echo second >> {log}")
    first.wait(timeout=20)
    waited = second.communicate(timeout=20)[0]
    assert log.read_text().split() == ["first-start", "first-end", "second"]
    assert "waiting" in waited


def test_a_killed_holder_releases_the_lock(tmp_path: Path) -> None:
    lock = tmp_path / "gate.lock"
    holder = run_locked(lock, "sleep 30")
    time.sleep(0.3)
    holder.kill()
    holder.wait(timeout=20)
    gate = run_locked(lock, "echo ran")
    assert gate.communicate(timeout=20)[0].strip() == "ran"
    assert gate.returncode == 0


def test_the_command_exit_status_is_returned(tmp_path: Path) -> None:
    gate = run_locked(tmp_path / "gate.lock", "exit 3")
    gate.wait(timeout=20)
    assert gate.returncode == 3
