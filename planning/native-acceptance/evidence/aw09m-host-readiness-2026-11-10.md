# AW09M host-readiness measurement

DATE: 2026-11-10
CASE: `AW09M` (measurement for agent-workflows AW-09, before any guard code)
BUILD: installed RBZ from `07ef553e` (AW-08 head, branch `feat/agent-workflows-aw-09`), SHA-256 `1043e661…`;
SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1; real loopback listener on 46110.
FIXTURE: fresh copy of the blank template, the only document in a fresh process; nine Groups and an approved
destination added by labelled bridge setup.

## What drove each row

Full-screen control was requested once and not answered within the time limit. A background click on the
viewport is refused while SketchUp is in the background, so **no row is a native mid-gesture**. Rows were driven by
background toolbar presses, a public view command, System Events menu clicks, and labelled development evals, as
named below. A development recorder (tools observer, transaction and activation observers, listener handoff and
run, a 0.5 s UI-timer tick) was loaded by bridge eval; its status and code counts equal the client's rows apart
from three explained extra calls.

Each probe ran, in order: `context`, a read, `materials.create`, `zones.make`, Colour-by on and off,
`context.open` and `context.root`, a 320 x 240 capture and an export start polled to its end.

| Row | Driven by | Result |
| --- | --- | --- |
| Select idle | nothing | Every call completed in 0.06 to 0.25 s; both writes committed |
| Move tool chosen, idle | toolbar press (native control, no gesture) | Every call completed except `context.open`, refused `session.busy`. Move stayed active; the tools observer reported Move state 0 after each commit |
| Move or Line partway through, held drag | not run | Needs full-screen control. Missing prerequisite: one approved full-screen hold |
| PH-Composer Classify tool | `zones.faces.choose` (scripted activation) | As Move idle; the same tool instance stayed active |
| Deferred work pending | development fault holding `pending?` | `context` answered busy with the reason; every other call `session.busy`; nothing written |
| Make Component sheet open | Edit menu through System Events | Timers kept ticking; a write committed while the sheet was open; Create then made its component |
| Blocking message box open | development eval of `UI.messagebox` | No tick for 20 s. Both calls timed out at the client after 15 s. After OK the worker read the buffered requests and the write **committed 5 s after the client had given up** |
| Another Model shown | File > New through System Events | Writes landed on the hidden target's Undo stack, but **every transaction callback arrived at the shown Model's observers**: the shown session's revision went 1 to 21 with no change of its own, and the target kept two own commits pending, so a later commit on it did not advance its revision once (19 stayed 19). `context.open` was honoured on the hidden Model; `context.root` refused `session.inactive` |
| Target closing | close button and Don't Save through System Events, during a 300-call loop | With the Save sheet open, writes still committed. After Don't Save the **first write failed `operation.rollback_unverified`**: `Sessions.all` raised `TypeError` removing a view observer from the deleted Model, after the session was already dropped, so its own detach never ran. Every later call answered `session.unknown` |

## What the evidence settles

- Reads, writes, Colour-by, capture and export start are harmless with a non-Select tool chosen but idle, native
  or PH-Composer's. This does not settle a gesture partway through: those rows stay open.
- Three defects are reproduced: a late write after a blocking modal, misattributed transaction callbacks for a
  write to a Model that is not shown, and a failed prune when the target closes.
- A sheet such as Make Component does not stop timers, so it is not a busy state the listener can see.

Raw rows, the recorder log and the cross-check are kept in `_private/host/aw09/run1/AW09M/` (not committed).
