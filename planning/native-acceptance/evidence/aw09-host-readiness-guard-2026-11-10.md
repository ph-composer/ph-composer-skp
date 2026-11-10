# AW09 host-readiness guard

DATE: 2026-11-10
CASE: `AW09` (gate for agent-workflows AW-09, on the head that goes to merge)
BUILD: installed RBZ from `ca99acbe` (branch `feat/agent-workflows-aw-09`, PR #449), SHA-256 `3a70f542…`;
SketchUp 26.1.188, macOS 26.7.1; real loopback listener on 46110; normal composition, no recorder or patch.
FIXTURE: fresh copy of the blank template, the only document in a fresh process; nine Groups and an approved
destination added by labelled bridge setup.

Every row was driven by MCP calls, System Events menu and button clicks and labelled bridge evals. None is a native
viewport gesture: those rows of the earlier [AW09M measurement](aw09m-host-readiness-2026-11-10.md) remain open.

| Assertion | Result |
| --- | --- |
| Select idle unchanged | Reads, a Material create and a Zone make, Colour-by, context open and root, and capture completed |
| A call whose client gave up never runs | A Material create sent while a message box was open timed out at the client after 10 s. After OK, the revision stayed 8 and no Material was added; the log records the call as `abandoned`. The same key sent again committed once, and a second resend answered that same outcome with no new Material |
| A hidden Model's writes count for it alone | With another Model shown, a Material create and a Zone make on the target advanced its revision 9 to 11 while the shown Model stayed at 1. Once the target was shown again, its next commit advanced it to 12 |
| Navigation needs the shown Model | `context.open` on the hidden target refused `session.inactive`; its path stayed at the root |
| Target closing | During a 300-call loop, the target closed with Don't Save: 41 calls completed, 259 answered `session.unknown`, none failed, nothing in the warning log |

Limitation kept: a commit made on a hidden Model by a script outside any PH-Composer operation (a bridge eval here)
still advanced the shown Model's revision, 1 to 4, because SketchUp reports it there and nothing claims it.

Raw rows and state reads are kept in `_private/host/aw09/run2/AW09/` (not committed).
