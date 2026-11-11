# AW10 integrated acceptance

DATE: 2026-11-10
CASES: `AW05R`, `AW10`, `AW10H`, `AW10G` (agent-workflows AW-10)
BUILD: installed RBZ from `e5e1f4b3` (branch `feat/agent-workflows-aw-10`, stacked on PR #449); SketchUp 26.1.188,
macOS 26.7.1; real loopback listener on 46110; normal composition.

## AW05R: AW-05's two blocked rows

FIXTURE: fresh copy of the blank template, the only document in a fresh process. Labelled bridge setup: 450 loose
Faces each stamped by its own legacy Zone and 80 Component instances carrying a Zone record (store writes: the
product has no authoring route for either), and a 30 m x 30 m floor Face with 450 holes. The client made the floor a
Space through `spaces.create`.

| Assertion | Result |
| --- | --- |
| Restore offers | Summary 450 offers and 80 findings; whole `zones.list` refused oversize; 450 offers paged in 6 pages equal the in-process read; one offer's `entity_ids` rejoined by fragment with size and SHA-256 |
| Component Zone findings | 80 findings paged in 3 pages, equal to the in-process read |
| Floor Segment loops | Loops with `loops_m` refused oversize; 451 loops (outer and 450 holes) rejoined from `spaces.detail` fragments, equal to the in-process read |
| Budget, no side effect | 22 read replies, largest 16,832 bytes; revision unchanged by the reads |

Raw replies are kept in `_private/host/aw10/run1/AW05R/` (not committed).

## AW10: integrated scenario on recorded clients (13 of 14 pass; gesture row blocked)

FIXTURE: Model A, a fresh copy of the blank template as `a/house.skp`, the only document in a fresh process; Model B,
another copy as `b/house.skp`. Labelled bridge setup: two touching boxes (5 x 4 x 3 m and 4 x 4 x 3 m), 60 loose
Edges carrying assignments a deleted Zone left, a one-Material file library, an approved export destination, Model
B opened with one flat Face. Between client sessions the user's two Space floor surfaces were drawn at the root
(first touching, then redrawn inset 5 cm). A token for Model A only (read, view, model_write, setup, export,
capture) was connected for both clients by the Agent Access dialog's own Connect message into a scratch home.
Panel closed and nothing selected throughout.

CLIENTS: Claude Code 2.1.317 (`claude-sonnet-5-5`, `--restricted --tools Read --strict-mcp-config` with Connect's
entry; built-in skills only, no operator skills, memory or advisor; three sessions) and codex-cli 0.167.0
(`gpt-6.1-sol`, a scratch `CODEX_HOME` holding Connect's config and the auth link; two sessions). Each started from
an empty folder with no repository and learned the product from the guide served by `discover`.

| Assertion | Result |
| --- | --- |
| Scope | Two open Models named `house.skp`. Each Model-only token's `discover` listed only its own Model; naming the other session refused `session.unknown` both ways |
| Claude Code recipes | Guide read through `discover`; context verified; targets found with nothing selected; every write read back. Refusals met and handled: `reference.invalid`, `validation.failed`, `classified`, `shares_edge`, `params.invalid` |
| Codex recipes | Same, after one fix: `codex exec` refuses every MCP write under its approval policy until the entry sets `default_tools_approval_mode = "approve"` (now in the user guide) |
| Zones and Spaces | Two Zones from the unselected Groups (Make Zone classified all 12 Faces), Building-Segment and Level created and set, one adjacency pair; Living and Bedroom created in their Zones from the floor surfaces, Volumes 2.7 m (51.597 and 41.067 m3) |
| Materials, Assembly, library | Two Materials, a three-layer Assembly read back by layer, the library Material copied and assigned to a segment in one previewed copy, the Assembly on the six outside walls. Not exercised: counterpart orientation (the Surface pair carries no Assembly) |
| Windows | Frame, Glazing, 3 x 2 Type and its elements; one Window placed centred from the south wall's host extent (no holes), renamed and read back |
| Thermal bridges | Edges found with nothing selected; Type created, assigned by reference, read, cleared, reassigned; the 14 m run read; 60 orphan findings paged (3 pages), repaired and rechecked to 0 |
| Blocked export | 72 QA findings paged (10 blocking); the export ended `window_type.operation_incomplete` with no files; after a human edit, a new session read that task by id and saw it describes revision 98 |
| HBJSON | Blockers fixed, export completed at revision 103. Independently: HBJSON (52,883 bytes) and report match the receipt's size and SHA-256; rooms are the two Zone ids; faces carry the Assembly identifier, Ground, Outdoors and Surface conditions and 6 apertures on Zone West; the library Material is 0.042 W/mK |
| View | Zone Colour-by, locate, capture, off. The client stated the image has geometry and the window but no zone colours, legend or overlays. The capture is a local path, so the recipe needs a client that reads local files |
| Faults (harness) | Stale revision refused, nothing written; a human edit between read and write refused, the reread retry committed once; a lost reply resent with its key committed once and answered the same outcome again; the key reused with other params refused `request.sequence_conflict`; `context.open` on Model A while Model B was shown refused `session.inactive`; after Model B closed (File > Close, Don't Save) its token's call refused `session.unknown` and `discover` named why; after revoke, HTTP 401 |
| Undo and Redo | Edit > Undo Assign Assembly through System Events cleared the four floor and roof assignments, Redo restored them |
| Save and reopen | Cmd-S through System Events; after a fresh launch every Material, Assembly, Zone, Face, Space, Unit and the run equal the saved state; a new Model-only token read it over MCP |
| Gesture conflict | Blocked; needs the AW10H hold |

Driven by: the clients for every build, edit, QA and export step; a harness over the real listener for the faults
(it reads the token Connect saved, never prints it); System Events for window switching, close, Undo, Redo and save.
The clients held only the MCP tools (Claude Code also Read). Not native gestures: everything here is menu, keyboard or MCP.

Not exercised here: copied and locked Zone conflicts (AW01 covers them natively; the legacy case is AW05R); Material edits beyond create, read and copy; a host extent with holes (AW05's 450-hole host covers it); Unit type change and repair; counterpart orientation; exact-revision export start (A16, deferred); artifact bytes and operation history (A14, deferred); the gesture conflict (AW10H).

Found on the way, recorded as follow-ups in the packet ledger: the guide does not say that Make Zone classifies the
Faces, that options must exist before a Zone uses them, that a Zone's classified floor cannot seed a Space or that
touching floors refuse per Face, the Window Type element id and span conventions, that `create_preview` is a query,
or that `volumes.list` needs a `space`; `host_bridge.py quit` saves each document to a discard path, so a Model-only
token follows that Save As and no longer serves the reopened file; a `pushpull` on a just-opened second Model crashed
SketchUp (run `AW10-crashed`, now in `context/SKETCHUP_HOST_BEHAVIOR.md`).

## AW10H: the held native rows (run 4: dialog and Line pass, Move fails)

FIXTURE: fresh copy of the blank template; nine Groups and an approved destination by labelled setup, the AW-09
development recorder checked against a shipping context read (`run_end` completed/ok, SelectionTool in both), a
Codex profile saved and the listener moved to 46111 so the Agent Access dialog offered Repair.

Full-screen control was approved, then each of three `computer_batch` calls (a screenshot; then a 5 s wait and a
screenshot) was aborted as a user interrupt before its first action. Control was released and not requested
again. All seven rows are recorded `blocked`: the dialog's Repair, Revoke, Revoke confirmation and Done as native
clicks, Move click-move, Move held drag and Line partway through, and the guard decision that depends on them.
Missing prerequisite: one uninterrupted full-screen hold. The ready recipe is `_private/host/aw10/HELD_RUN.md`.

### Run 2 (2026-11-10, main `3da2a9ab`): blocked again, before the hold

Installed RBZ from `make rbz && make install` on main `3da2a9ab`, SketchUp 26.1.188, fresh process, the same
fixture and labelled setup. Preparation was verified: the recorder's `run_end` matched the client's check row
(context completed/ok, SelectionTool in both), and the dialog setup now connected both clients, Claude Code (client
id `claude_code`) and Codex, with the saved setups on 46110 and the listener on 46111, so both rows offered Repair.
`request_full_control` was then called once and its approval card went unanswered within the time limit; it was
not requested again, so no native click or gesture was made. All seven rows are recorded `blocked` a second time,
and the guard decision stays open. Cleanup revoked every token and the destination the run made, put the listener
back on 46110, removed the scratch client home and quit SketchUp cleanly. Missing prerequisite unchanged: one
approved, uninterrupted full-screen hold (recipe `_private/host/aw10/HELD_RUN.md`).

### Run 3 (2026-11-11, main `95147b5e`): approved, then interrupted

Same installed build (shipped source unchanged since `3da2a9ab`), fresh process, same fixture and labelled setup.
Preparation verified again: recorder `run_end` equal to the client's check row, both clients offering Repair with
the listener on 46111. `request_full_control` was approved; the first `computer_batch` (one screenshot) was then
aborted as a user interrupt before its first action. Control was released and not requested again. All seven rows
are recorded `blocked` a third time; the guard decision stays open. Cleanup read back as in run 2.

### Run 4 (2026-11-11, main `95147b5e`): one uninterrupted hold; Move fails, guard required

Installed RBZ from main `95147b5e`, SketchUp 26.1.188, fresh process, the same fixture and labelled setup, one
approved full-screen hold run from the conductor session, uninterrupted. The recorder's `run_end` counts equal the
client rows (38: completed/ok 34, refused `revision.stale` 2, busy `session.busy` 2).

| Assertion | Result |
| --- | --- |
| Dialog Repair | Pass: native click on Repair (Codex) with the listener on 46111; notice "Codex is set up to read its token"; the saved URL reads 46111 |
| Dialog Revoke and confirm | Pass: the confirmation named both affected profiles (Claude Code, Codex); after its Revoke both rows say no live token |
| Dialog Done | Pass: the scripted issue step was refused (empty capabilities), so the token was made natively (New token, Read only, Create); Done returned to the main screen listing it. No screenshot of the issued token kept |
| Move click-move | Fail: with MoveTool in state 1 (box displaced), `materials.create` committed and SketchUp reset MoveTool to state 0 between `onTransactionStart` and `onTransactionCommit`; the box returned to its origin and the tool waited for a new pick. Undo held Make Zone, Create Material and the fixture, no Move. `context.open` answered `session.busy`, `moved` `revision.stale`; reads, Colour-by, capture and export start unaffected |
| Move held drag | Fail: the same while the button was held; the box was back at its origin before mouse-up, no Move in the Undo stack |
| Line | Pass: with SketchTool in state 1 the same writes committed (Zone 8), the start point held, the second click drew the Edge, and Draw Line was its own Undo step above Make Zone; Redo restored it |
| Guard decision | Required: a write cancels a Move partway through; scoped by the evidence to MoveTool in a state other than 0 |

Raw recorder, client rows, Edit menu labels and screenshots are kept in `_private/host/aw10/run4/AW10H/` (not
committed).

## AW10G: the Move guard (implemented, re-measurement pending)

From run 4, choice D17-f: every action refuses `session.busy`, before it takes a sequence, while MoveTool is in a
state other than 0, with a message naming the tool; `context` readiness reports it. SketchUp's Line tool stays
unguarded, and reads, view commands and export start are unchanged. Offline tests in `tests/gesture_guard_test.rb`
cover the tool-state transitions, the refusal and the same sequence running after the Move ends. Case `AW10G`
re-measures click-move, held drag and Line on the installed build; recipe `_private/host/aw10/HELD_RUN.md`.
