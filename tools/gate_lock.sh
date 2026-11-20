#!/bin/sh
# Runs its arguments while holding the machine-wide gate lock, so two `make ci` runs never overlap: two
# full gates at once (two stage worktrees, or a gate beside a Codex review's test runs) pushed the load
# average to 16 and the Ruby 2.7 suite past its 900 s limit. A second caller waits and says so. The lock is a
# directory holding only the owner's pid file; a lock whose owner has exited is released and taken over.
set -u
LOCK="${PH_COMPOSER_GATE_LOCK:-${TMPDIR:-/tmp}/ph-composer-gate.lock}"

release() {
  rm -f "$LOCK/pid"
  rmdir "$LOCK" 2>/dev/null || true
}

announced=""
while ! mkdir "$LOCK" 2>/dev/null; do
  owner=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
    release
    continue
  fi
  if [ -z "$announced" ]; then
    echo "gate: another make ci holds $LOCK (pid ${owner:-starting}); waiting"
    announced=1
  fi
  sleep 2
done
echo $$ > "$LOCK/pid"
trap release EXIT
trap 'exit 130' INT TERM
"$@"
