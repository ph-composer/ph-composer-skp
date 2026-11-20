"""Run a command while holding the machine-wide gate lock, so two `make ci` runs never overlap.

Two full gates at once (two stage worktrees, or a gate beside a Codex review's test runs) pushed the load
average to 16 and the Ruby 2.7 suite past its 900 s limit. A second caller waits and says so. The lock is an
advisory `flock` on one file, held by this wrapper and inherited by the command: the kernel releases it when
the last holder exits, however it exits, so nothing is ever reclaimed or deleted.

Usage: python3 tools/gate_lock.py <command> [args...]
"""

from __future__ import annotations

import fcntl
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def lock_path() -> Path:
    named = os.environ.get("PH_COMPOSER_GATE_LOCK")
    return Path(named) if named else Path(tempfile.gettempdir()) / "ph-composer-gate.lock"


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: gate_lock.py <command> [args...]", file=sys.stderr)
        return 2
    path = lock_path()
    with path.open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print(f"gate: another make ci holds {path}; waiting", flush=True)
            fcntl.flock(handle, fcntl.LOCK_EX)
        # The command inherits the locked descriptor, so the lock stays held while it or anything it started
        # runs, even if this wrapper is killed first.
        return subprocess.call(argv, pass_fds=(handle.fileno(),))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
