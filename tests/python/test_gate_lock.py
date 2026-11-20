"""tools/gate_lock.sh: two gates never run at once, and a lock left by an exited owner is taken over."""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

LOCK_SCRIPT = Path(__file__).resolve().parents[2] / "tools" / "gate_lock.sh"


def run_locked(lock: Path, command: str) -> subprocess.Popen[str]:
    env = {**os.environ, "PH_COMPOSER_GATE_LOCK": str(lock)}
    return subprocess.Popen([str(LOCK_SCRIPT), "sh", "-c", command], env=env, stdout=subprocess.PIPE, text=True)


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
    assert not lock.exists()


def test_a_lock_whose_owner_has_exited_is_taken_over(tmp_path: Path) -> None:
    lock = tmp_path / "gate.lock"
    lock.mkdir()
    exited = subprocess.Popen(["true"])
    exited.wait()
    (lock / "pid").write_text(f"{exited.pid}\n")
    gate = run_locked(lock, "echo ran")
    assert gate.communicate(timeout=20)[0].strip().endswith("ran")
    assert gate.returncode == 0
    assert not lock.exists()
