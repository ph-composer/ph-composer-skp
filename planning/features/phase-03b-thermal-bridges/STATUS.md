# Phase 3b: thermal bridges, tracking ledger

DATE: 2026-10-03
STATUS: In progress. P3b-01 merged to `main` 2026-10-22 (PR #302); P3b-02 merged 2026-10-25 (PR #308); P3b-03 merged 2026-10-25 (PR #309); P3b-04 merged 2026-10-26 (PR #310); P3b-05 merged 2026-10-26 (PR #311); P3b-06 merged 2026-10-26 (PR #312); P3b-07 merged 2026-10-26 (PR #313); P3b-08 in progress on branch; P3b-02 to P3b-09 authorized 2026-10-25 as one pull request each.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

This is the one place Phase 3b completeness is read from. Update it in the same change as any
stage's state. States use the canon vocabulary: `Requested`, `Scoped`, `In progress`, `Blocked`,
`In review`, `Implemented on branch`, `Merged to main`, `Complete`, `Deferred`, `Superseded`.

## State

PRD drafted 2026-09-18. Planned in detail on 2026-10-03 against the code on `main` at `08c4807`:
twenty-six findings, the PRD's eleven questions and twenty-one plan decisions in
[DECISIONS.md](DECISIONS.md), bindings in [CONTRACTS.md](CONTRACTS.md), nine stages in
[phases/](phases) and nine acceptance rows in [ACCEPTANCE.md](ACCEPTANCE.md). Ed answered every
question the same day; the PRD and `context/UBIQUITOUS_LANGUAGE.md` carry the answers.

Re-baselined on 2026-10-21 against `main` at `420c783a`, 385 commits after the plan was drafted.
[DECISIONS](DECISIONS.md), Part 1b, re-reads every finding: the engine requires an id on every
reference-target record, so the assignment carries a `tbe_` id; Zones' path resolution exists and
`zones.containment` generalises it; P3a-05's `derived` segments, per-colour line batches and legend
figures are on `main`; G-02's Edge entries are in the snapshot; Spaces is the first `ROOM` section;
every registration is now an agent surface with an API change row; the foundation owns
`context.open`; the host kit has bounded waits, diagnostics and fault controls. CONTRACTS, PLAN,
ACCEPTANCE, the PRD and every stage are corrected. Two decisions added, D3b-22 (no re-issue of
duplicated `tbe_` ids) and D3b-23 (runs join by container path plus vertex id), and answered as
recommended the same day; no stage authorized.

## Next step

P3b-01 merged to `main` as `91366643` ([PR #302](https://github.com/ph-composer/ph-composer-skp/pull/302)); T01 passes. On 2026-10-25 Ed authorized the rest of the packet through the PR loop, one branch and pull request per stage, with the merge delegated on green CI. P3b-02 merged to `main` as `b4b6d08c` ([PR #308](https://github.com/ph-composer/ph-composer-skp/pull/308)); T02 passes. P3b-03 merged to `main` as `96d09161` ([PR #309](https://github.com/ph-composer/ph-composer-skp/pull/309)); T03 passes. P3b-04 merged to `main` as `85d81a46` ([PR #310](https://github.com/ph-composer/ph-composer-skp/pull/310)); T04 passes; the schedule is read on request (D3b-13, DECISIONS F37). P3b-05 merged to `main` as `de76ddba` ([PR #311](https://github.com/ph-composer/ph-composer-skp/pull/311)); T05 passes. P3b-06 merged to `main` as `da53f66e` ([PR #312](https://github.com/ph-composer/ph-composer-skp/pull/312)); T06 passes. P3b-07 merged to `main` as `15c9c535` ([PR #313](https://github.com/ph-composer/ph-composer-skp/pull/313)); T07 passes. P3b-08 is in progress on `feature/thermal-bridges-p3b-08`.

## Entry gates

| Gate | State |
| --- | --- |
| Ed answers PRD Q1 to Q11 (the interview) and D3b-01 to D3b-21 | Done 2026-10-03 |
| Ed answers D3b-22 (before P3b-03) and D3b-23 (before P3b-04) | Done 2026-10-21 |
| A Phase 3 issue exists on `ph-composer/ph-composer-skp`, and every header's `ISSUE` line points at it | Done 2026-10-21: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301) |
| Ed authorizes implementation, stage by stage or for a run of stages | Done: P3b-01 on 2026-10-21; P3b-02 to P3b-09 on 2026-10-25, through the PR loop with the merge delegated |
| P3a-01 merged before P3b-03 and P3b-08 start; P3a-05 merged before P3b-06 starts | Closed: P3a-01 merged through PR #135, P3a-05 through PRs #147 and #148; Phase 3a closed 2026-10-17 |

## Stage ledger

"Offline" is `make ci` on both Rubies at the stage's gate. "Host" is the stage's host gate in a
fresh process. "Review" is the one review the ladder assigns. A stage is `Implemented on branch`
only when all three are done and its evidence file exists.

| Stage | Title | State | Blocked by | Branch / PR | Offline | Host | Review | Evidence | Register |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [P3b-01](phases/p3b-01-thermal-bridge-contracts-and-edge-host-facts.md) | Thermal-bridge contracts and edge host facts | Merged to main | | [PR #302](https://github.com/ph-composer/ph-composer-skp/pull/302), squash `91366643` | `make ci` green at `b013f330` and on the evidence head (Ruby 3.2.2); the new test also on 2.7.2 | T01 run 2026-10-21 on 26.1.188 at `bec31a4c`: the five B4 cases with native Undo, Redo, save and fresh-process reopen, eight assertions pass | architecture review done: Codex gpt-6-astra with the architecture and Ruby rubrics, two cycles (2 P2 + 1 P3, then 3 P2), all six fixed in `31ddfb03` and `b013f330` | | [evidence](evidence/p3b-01-edge-host-facts.md) | T01 |
| [P3b-02](phases/p3b-02-thermal-bridge-type-records.md) | Thermal Bridge Type records and operations | Merged to main | | [PR #308](https://github.com/ph-composer/ph-composer-skp/pull/308), squash `b4b6d08c` | `make ci` green at `6a805df1` (Ruby 3.2.2: 2,129 runs); the new tests also on 2.7.2 | T02 run 2026-10-25 on 26.1.188 at `6a805df1`: walkthrough, six native Undo and Redo steps, save and fresh-process reopen, three assertions pass | ordinary: Sonnet pre-gate read (5 fixed), Codex gpt-6.1-sol two cycles (1 P2 fixed in `6c87c98d`, 1 P2 declined as a cross-catalog follow-up) | [evidence](evidence/p3b-02-type-records.md) | T02 |
| [P3b-03](phases/p3b-03-edge-assignment.md) | Edge assignment, Zone containment and edge picking | Merged to main | | [PR #309](https://github.com/ph-composer/ph-composer-skp/pull/309), squash `96d09161` | `make ci` green at `089db1b8` (Ruby 3.2.2: 2,150 runs); the new and touched suites also on 2.7.2 | T03 run 2026-10-25 on 26.1.188 at `089db1b8`: selection and assign, native Undo and Redo, a Zone under a turned wrapper, the Window Unit and root refusals, delete with replacement and Undo, a split, save and fresh-process reopen; seven assertions pass | strong: Sonnet pre-gate read (6 fixed), Codex gpt-6-astra two cycles with the architecture and Ruby rubrics (1 P1 + 2 P2, then 2 P2; all fixed in `15159983` and `089db1b8`) | [evidence](evidence/p3b-03-edge-assignment.md) | T03 |
| [P3b-04](phases/p3b-04-runs-and-schedule.md) | Runs, the schedule read and findings | Merged to main | | [PR #310](https://github.com/ph-composer/ph-composer-skp/pull/310), squash `85d81a46` | `make ci` green at `e618f1e3`; the new and touched suites also on 2.7.2 | T04 run 2026-10-26 on 26.1.188 at `e618f1e3`: the hand calculation, the same read inside open contexts, counted-twice with native Undo, outside a Zone, `runs.locate` into a wrapped Zone, the 50,000 Edge measurement (`schedule.all` 1.84 s, so read on request); six assertions pass | ordinary: Sonnet pre-gate read (13 of 19 fixed), Codex gpt-6.1-sol two cycles (2 P2, then 1 P2 + 1 P3; all fixed in `77587f50` and `e618f1e3`) | [evidence](evidence/p3b-04-runs-and-schedule.md) | T04 |
| [P3b-05](phases/p3b-05-thermal-bridges-tab.md) | The Thermal Bridges tab | Merged to main | | [PR #311](https://github.com/ph-composer/ph-composer-skp/pull/311), squash `de76ddba` | `make ci` green on every head (Ruby 3.2.2 suite, 750 JS tests); the touched Ruby suites also on 2.7.2; `make ui-checks` for the new check, inventories, Library and Windows | T05 run 2026-10-26 on 26.1.188 at `028905ab`, Ed at the mouse: assign from the bar and the menu, Clear, native Undo, a unit switch with a draft, the Schedule and Locate into a wrapped Zone, METr's words; seven assertions pass; Ed accepted the screen after five changes | ordinary, UI: Sonnet pre-gate read (13 items, all fixed); Codex gpt-6.1-sol two cycles (2 P2, then 1 P2; all fixed) | [evidence](evidence/p3b-05-thermal-bridges-tab.md) | T05 |
| [P3b-06](phases/p3b-06-thermal-bridge-colour-by.md) | The thermal-bridge Colour-by mode | Merged to main | | [PR #312](https://github.com/ph-composer/ph-composer-skp/pull/312), squash `da53f66e` | `make ci` green at `3d7045a7` (Ruby 3.2.2: 2,191 runs; 750 JS tests); the new and touched suites also on 2.7.2 | T06 run 2026-10-26 on 26.1.188 at `3d7045a7`: the native menu, thick coloured depth-tested Edges in a turned nested Zone, a hidden tag, tag folder and ancestor, the HUD in SI and IP, select and Show only this, 7.7 ms a frame and 225 ms a rebuild at 5,000 assigned Edges; six assertions pass | strong: Sonnet pre-gate read (11 items, the real ones fixed), Codex gpt-6-astra two cycles with the architecture and Ruby rubrics (1 P2 fixed in `3d7045a7`, then none) | [evidence](evidence/p3b-06-colour-by.md) | T06 | | T06 |
| [P3b-07](phases/p3b-07-edge-tool.md) | The edge tool | Merged to main | P3b-05, P3b-06 | [PR #313](https://github.com/ph-composer/ph-composer-skp/pull/313), squash `15c9c535` | `make ci` green at `a0a765a6` (Ruby 3.2.2: 2,212 runs; 754 JS tests); `make ui-checks` for the thermal-bridges check at the three panel sizes | T07 run 2026-10-26 on 26.1.188 at `a0a765a6`, Ed at the mouse: hover, clicks and a drag with one Undo each, a type change and Escape mid-drag, a Model switch, a raised callback, the root and Window Unit refusals, 251 Edges refused whole, Stop; eleven assertions pass; 185 ms to assign 250 Edges, 1.3 ms median per newly hovered Edge at 50,040 Edges | ordinary, UI: Sonnet pre-gate read (9 items, fixed); Codex gpt-6.1-sol two cycles (1 P2, then 1 P2; both fixed) | [evidence](evidence/p3b-07-edge-tool.md) | T07 |
| [P3b-08](phases/p3b-08-thermal-bridge-export.md) | Thermal-bridge export | In review | P3b-04 | `feature/thermal-bridges-p3b-08` | Ruby 3.2.2: 2,223 runs; 754 JS tests; 258 Python tests | | strong: Sonnet pre-gate read (no high; 3 medium, 8 low; fixed or recorded) | | T08 |
| [P3b-09](phases/p3b-09-thermal-bridge-acceptance-and-handoff.md) | Thermal-bridge acceptance and handoff | Scoped | P3b-01 to P3b-08 | | | | none; consolidation | | T09 |

## Deferred foundation stages

Three stages of the refactoring program's
[geometry contribution contracts](../cross-phase/geometry-contribution-contracts/PLAN.md)
packet ([#118](https://github.com/ph-composer/ph-composer-skp/issues/118)) need this track as their adopter.
They are deferred here until the P3b stage named in "Picked up by" starts. Their plan text stays in
that packet; this ledger owns when they run.

| Stage | Scope | State | Picked up by | Note |
| --- | --- | --- | --- | --- |
| G-01 | Confirm the Edge facts (`vertex_ids`, `face_ids`, visibility), per-segment versus whole-run filtering, legend counting through `member`, line width | Answered 2026-10-21 by P3b-01; closes with G-04 | P3b-01 | Document stage. The line primitive is settled (D3a-5, 2026-10-15): Edges draw as `derived` segments with a per-mode stroke (H14). P3b-01 answered the rest on 2026-10-21: `vertex_ids` and `face_ids`, keyed with the container path, are enough for run formation (D3b-23); an Edge entry carries its path, so visibility is the service's path walk and needs no fact; filtering is per entry, one Edge each, and the legend counts entries, so no `member` key; the line width is the mode's `stroke:`. P3b-01 records the answers in both packets |
| G-03 | `ColourBy::LineEntry`, the service branch, the overlay line pass | Superseded 2026-10-15 | P3b-06, after G-01 | Not built: P3a-05's design note settled one line primitive, `derived` segments on an ordinary entry (`context/EXTENSIBILITY.md`, "Colour-by derived geometry"). An Edge entry carries the Edge as `entity` and its segment in `derived`; P3b-06 adds only a mode-level stroke weight |
| G-04 | Thermal-bridge adoption: native drawing proof, export of runs, the 50,000 Edge measurement | Native drawing proof done in P3b-06 (T06); export of runs and the snapshot measurement wait for P3b-08 | P3b-06 and P3b-08 | Closes F06 once G-02 and G-03 both have this adopter in use |

G-02 is already on `main` ([PR #119](https://github.com/ph-composer/ph-composer-skp/pull/119)): the export
`GeometrySnapshot` has an `edge` entry for every Edge occurrence (world SI endpoints, vertex ids,
Face ids, dictionaries), with Edges inside cutting components dropped as Faces are. H15 is done;
P3b-08 adds only its contributor, which filters edge entries by its own dictionary, and measures
the snapshot on the 50,000 Edge Model.

## Milestones

| Milestone | After | Meaning |
| --- | --- | --- |
| T-M1 | P3b-04 | Thermal bridges complete as data: types, assignments, runs and findings through the public API, panel closed, host-proven |
| T-M2 | P3b-05 | Authoring on screen: the earliest point worth a hands-on pass by Ed |
| T-M3 | P3b-08 | Exported to HBJSON and read back on the reference model |

## Decisions

D3b-01 to D3b-21 answered on 2026-10-03; the answers are in [DECISIONS.md](DECISIONS.md), "Ed's
answers". D3b-22 and D3b-23 were added by the re-baseline of 2026-10-21 and answered the same day.

| ID | Kind | Subject | Blocks | State |
| --- | --- | --- | --- | --- |
| Q1 to Q11 | Mixed | The PRD's interview questions ([list](DECISIONS.md#prd-questions)); Q3 confirmed by D3 | P3b-01 to P3b-08 | Answered 2026-10-03 |
| D3b-01 | Code | Edge is the record; no Model-level edge registry | P3b-03 | Answered 2026-10-03 |
| D3b-02 | Code | Edge assignment carries no id, unless the target contract needs one | P3b-03 | Answered 2026-10-03 |
| D3b-03 | Code | Group stored as honeybee-ph's strings, shown in METr's words | P3b-02 | Answered 2026-10-03 |
| D3b-04 | Code | Group required, default `15-Ambient` | P3b-02 | Answered 2026-10-03 |
| D3b-05 | Code | Type fields: the common set, psi, group, colour; no timestamps | P3b-02 | Answered 2026-10-03 |
| D3b-06 | Code | A run is a maximal chain; T junctions split; loops close | P3b-04 | Answered 2026-10-03 |
| D3b-07 | Code | Run names and identifiers are derived | P3b-04 | Answered 2026-10-03 |
| D3b-08 | Code | Keep `quantity`; the PHX consequence goes to metr-export | P3b-03 | Answered 2026-10-03 |
| D3b-09 | Code | Zones publishes `zones.containment` | P3b-03 | Answered 2026-10-03 |
| D3b-10 | Code | Writes through shared storage refuse; shared tags count per occurrence | P3b-03, P3b-04 | Answered 2026-10-03 |
| D3b-11 | Code | Edges draw as P3a-05 `derived` segments with a stroke weight | P3b-06 | Answered 2026-10-03 |
| D3b-12 | UI | The HUD label carries total length | P3b-06 | Answered 2026-10-03 |
| D3b-13 | Code | Live schedule, measured; scan on request as fallback | P3b-04 | Answered 2026-10-03 |
| D3b-14 | Code | Gesture ceiling owned by the thermal-bridge schema, 250 to start | P3b-03, P3b-07 | Answered 2026-10-03 |
| D3b-15 | Code | Window-perimeter warning through a Windows outline read | P3b-08 | Answered 2026-10-03 |
| D3b-16 | Code | Interior-junction and counted-twice warnings | P3b-04 | Answered 2026-10-03 |
| D3b-17 | UI | Types and Schedule subtabs | P3b-05 | Answered 2026-10-03 |
| D3b-18 | UI | The edge tool stays in Phase 3 as the secondary route | P3b-07 | Answered 2026-10-03 |
| D3b-19 | Planning | Where the plan lives; superseded the same day by the split into Phase 3a and 3b | none | Answered 2026-10-03; superseded |
| D3b-20 | Code | The thermal-bridge export section is optional; only failed runs are omitted (differs from the recommendation) | P3b-08 | Answered 2026-10-03 |
| D3b-21 | Code | A type with no psi-value blocks export only when assigned | P3b-04, P3b-08 | Answered 2026-10-03 |
| D3b-22 | Code | The assignment's `tbe_` id, required by the engine, is not re-issued after a split or copy; reads mark it `copied` | P3b-03 | Answered 2026-10-21 |
| D3b-23 | Code | Runs join by a shared vertex keyed on container path plus vertex id; the 0.0254 mm tolerance serves only the cross-Zone and window-perimeter checks | P3b-04 | Answered 2026-10-21 |

## Owed from elsewhere, allocated here

| Item | Source | Stage | State |
| --- | --- | --- | --- |
| Optional attaching section rule | R05 item 4 | P3b-08, because D3b-20 makes the thermal-bridge section the first optional attaching section (H18) | Implemented on branch (P3b-08) |
| B4's open edge cases (Divide, Weld, push-pull removal, intersect, heal) | B4 spike limits | P3b-01 | Scoped |
| Window-edge rule for tagged edges | B4 disposition 4 | P3b-08 through D3b-15 | Implemented on branch (P3b-08): `thermal_bridge.on_window_perimeter` |

## Deferred out of this plan

| Item | Where it waits |
| --- | --- |
| METr thermal-bridge rows and PHX's treatment of `quantity` (F18, unreproduced) | [metr-export](../unscheduled/metr-export/README.md) |
| Thermal Bridge Types as a library kind (Q8) | Roadmap 5.4 |
| A Model-level edge registry for identity-bearing assignments (D3b-01) | [hot-water-piping](../phase-04-mechanical/hot-water-piping/README.md), [erv-ducting](../phase-04-mechanical/erv-ducting/README.md) |
| Moving the run builder to `core/` | When piping or ducting needs the same chain rule |
| A toolbar button for the edge tool | [zones-entry-points](../unscheduled/zones-entry-points/README.md) E1 |
| A compact default `fields` projection for every catalog `.list` (Assemblies, Materials, Window products and Types, Thermal Bridge Types), so one record over the agent reply budget cannot stop a page walk (Codex review of PR #308) | Unscheduled; needs its own issue |

## Verification

None. Nothing is implemented. DECISIONS Part 1 and Part 1b were read from source and not
reproduced; P3b-01 reproduces what the stages depend on.

## How to update this file

1. When a stage starts: state `In progress`, fill Branch.
2. At its gate: record the `make ci` result, the host gate result with the ledger case ids, and
   the review outcome in the three columns, and link the evidence file.
3. Then `Implemented on branch`; after merge `Merged to main` with the PR number.
4. Flip the matching [ACCEPTANCE](ACCEPTANCE.md) row in the same change.
5. Add a ledger row below for each of the above.
6. Mirror the summary line into [planning/STATUS.md](../../STATUS.md) and the Phase 3 table in
   [ROADMAP.md](../../ROADMAP.md).

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted. |
| 2026-09-18 | Scoping review moved point-bridge support to central decision D3 and rejected a fake 1 m linear proxy as the recommendation. |
| 2026-09-18 | D3 confirmed: the MVP is linear-only; point thermal bridges and chi-values are wholly out. |
| 2026-10-03 | Planned in detail inside the Phase 3 coordinating packet, beside the Spaces stages: twenty-six findings, the PRD's eleven questions and twenty-one decisions, bindings H11 to H17, register T01 to T09 with a hand-calculated reference model. |
| 2026-10-03 | Interview complete: Ed answered Q1 to Q11 and every plan decision one at a time, all as recommended except D3b-20 (the export section is optional; only failed runs are omitted). R05 item 4 moved to P3b-08. PRD, glossary, CONTRACTS, P3b-01, P3b-08 and the register updated. |
| 2026-10-03 | Ed split Phase 3 into two flat packets, `phase-03a-spaces/` and `phase-03b-thermal-bridges/`, and the ids restarted per sub-phase. Thermal-bridge stages P3-13 to P3-21 became P3b-01 to P3b-09, decisions D3-13 to D3-33 became D3b-01 to D3b-21, findings TF1 to TF26 became F1 to F26; S and T acceptance ids and H numbers are unchanged. |
| 2026-10-16 | Handoff from Phase 3a (P3a-12 step 9). Built and observed on the host (P3a-12), ready to reuse: the viewport-tool shape in `features/spaces/mark_tool.rb` (no operation of its own; each completed gesture is one public `invoke` and one Undo step; picks through `Pick.face_path`, drags through `core/` `DragSet`; a move without `MK_LBUTTON` cancels the gesture, and macOS sets that flag on every held move, `context/SKETCHUP_HOST_BEHAVIOR.md`). Also: Colour-by `derived` polygons and segments as P3a-05 shipped them (`ColourBy::Derived.new(polygons:, segments:)`, segments drawn at the overlay's outline weight, so H14's per-mode stroke weight is still P3b-06's), and the container rule (a stamped Group's Faces leave Zone inventories, CONTRACTS section 8). The `derived` shape is the one this packet's CONTRACTS assume for `by_type`. |
| 2026-10-21 | Re-baselined against `main` at `420c783a` (DECISIONS Part 1b, F27 to F36): F6 settled (records need an id), F7, F10, F14, F15, F24 changed, F8, F9, F25 superseded by P3a-05 and G-02. CONTRACTS section 8 answers five of section 7's questions from code; H15 done; H17 and H18 narrowed; the assignment reference takes the Face shape. D3b-22 and D3b-23 added, open. The D3b-12 HUD label takes the service's "label (count) figure" shape. PLAN, ACCEPTANCE, the PRD and every stage document corrected; the Phase 3a gates recorded as met. No decision answered, no stage authorized. |
| 2026-10-21 | Ed answered D3b-22 and D3b-23 as recommended; P3b-03 and P3b-04 lose their decision blockers. Waiting on the phase issue and the go on P3b-01. |
| 2026-10-21 | Phase issue [#301](https://github.com/ph-composer/ph-composer-skp/issues/301) created; every header in the packet points at it. Waiting on the go on P3b-01. |
| 2026-10-21 | Ed authorized P3b-01 as its own pull request through the loop. Branch `feature/thermal-bridges-p3b-01`: `tests/edge_record_contract_test.rb` answers CONTRACTS section 7 questions 2 and 3; `PLANNING_IDS` fails `S01`, `T01` and `F26`; T01 added to the native-acceptance cases; the edge spike gained the five open cases; G-01 answered in both packets. Host gate pending. |
| 2026-10-21 | PR #302 opened; Codex gpt-6-astra reviewed twice with the architecture rubric. Fixed: the retag case shared no operation with its registry write; the scan dropped dictionaries; the PRD's Runs rule still said tolerance; run identifiers collided for coincident placements, so they now digest the container path (D3b-07 under D3b-23); the "export attribute guard" claim was false and is corrected in F5, CONTRACTS section 8 and `core/dictionaries.rb`; the spike setup refuses a reused Model. `make ci` green at `b013f330`. State `In review`; the host gate is the one open item of T01. |
| 2026-10-21 | T01 host gate run on the PR head: the five B4 cases with native Undo, Redo, save and fresh-process reopen, eight assertions pass; results folded into `context/SKETCHUP_HOST_BEHAVIOR.md` and the heal consequence into D3b-22's row. P3b-01 `Implemented on branch`. |
| 2026-10-22 | PR #302 merged to `main` as `91366643` (squash, auto-merge on green CI); branch deleted locally and on the remote. P3b-01 `Merged to main`. |
| 2026-10-25 | Ed authorized P3b-02 to P3b-09 through the PR loop, one pull request per stage, merge delegated on green CI. P3b-02 started on `feature/thermal-bridges-p3b-02`: the feature, the Thermal Bridge Type kind, `types.list`, `types.all` and its section, the four actions, API minor 10, the walkthrough and the agent-guide recipe. CONTRACTS corrected: `color` is stored once authored and read as `display.color`, as Assemblies do, because the engine mints the id inside `propose_create`; `types.list` added as the bounded read `types.all` prefers. |
| 2026-10-25 | PR #308 opened. Pre-gate Sonnet read: `types.delete` lacked `copy.rule_missing`, a hostkit test expected four features, three assertions were weak; all fixed. Codex gpt-6.1-sol cycle 1: `types.list` exceeded the reply budget at its default limit; fixed in `6c87c98d` with `Pages.bounded` and a regression test. Cycle 2: a single oversized row cannot be paged past without a `fields` projection; declined as a cross-catalog follow-up. The walkthrough now checks `user_data` and an authored colour (`6a805df1`). T02 host gate passed on `6a805df1`. P3b-02 `Implemented on branch`. |
| 2026-10-25 | PR #308 merged to `main` as `b4b6d08c` (squash, auto-merge on green CI); branch deleted locally and on the remote. P3b-02 `Merged to main`. |
| 2026-10-25 | P3b-03 started on `feature/thermal-bridges-p3b-03`: `ph_composer.zones.containment` and `Zones::Occurrences.resolve_element` (H11), `Pick.edge_path` (H12), the Edge assignment record and its `ph_composer.thermal_bridges.edge` target, `edges.assign`, `edges.clear`, `edges.selection` and its section, `types.delete` with `replacement_id`, API minor 11. |
| 2026-10-25 | Pre-gate Sonnet read of P3b-03: fixed a dedupe key that merged two references with one root path, invalid assignments that could not be cleared or read, an unbounded `ignored` list and stranded-Edge detail, and missing stranded routes; added tests for the limit itself, the selection client, the step's apply-time recheck and an invalid record. Recorded, not changed: delete with replacement locates each Edge with a per-step persistent-id scan, as Assembly retarget does; P3b-04 measures it at 5,000 Edges. |
| 2026-10-25 | PR #309 opened. Codex gpt-6-astra cycle 1 (1 P1, 2 P2), all fixed: `edges.clear` and a delete with a null replacement now check that no record still names a removed assignment id (`check_identity_removal!`, skipping ids a surviving copy keeps); selection `values` and `expected_values` are plain objects so a malformed stored value still reads and clears; `edges.selection` is bounded and paged, its cursor bound to the selection and the revision, and `edges.selection_all` is the unbounded read the panel section and the menu route use. The reference-model builder was smoke-run on the host. |
| 2026-10-25 | Codex gpt-6-astra cycle 2 on `15159983` (2 P2), both fixed: an assignment record with a missing or invalid id now reads with a null `entity_id` and clears, guarded by its values, and assign gives it a fresh id; a locked Group at the end of a path now refuses a write to itself (`target.locked`) in containment and strict resolution alike. Review cycles at their cap of two. |
| 2026-10-26 | T05 host gate with Ed. His first pass and review (at `9015df8b`) asked for five changes: confirmations for Assign and Clear, used length a dash once stale, a Locate that keeps the read current, a control row that does not reflow, and columns that fit the panel; made in `028905ab`. The recorded run on `028905ab` passes all seven assertions ([evidence](evidence/p3b-05-thermal-bridges-tab.md)). METr's third group word is "Basement floor" (D3b-03); the label changed in the next commit. P3b-05 `Implemented on branch`. |
| 2026-10-25 | T03 host gate passed on `089db1b8` (seven assertions; [evidence](evidence/p3b-03-edge-assignment.md)). Recorded host facts: opening a Group through `active_path` is an Undo entry of its own, and positions read inside an open context are world coordinates, which the reference-model helper must account for (fixed with P3b-04). P3b-03 `Implemented on branch`. |
| 2026-10-25 | PR #309 merged to `main` as `96d09161` (squash, auto-merge on green CI); branch deleted locally and on the remote. P3b-03 `Merged to main`. P3b-04 started on `feature/thermal-bridges-p3b-04`. |
| 2026-10-25 | P3b-04 built: the pure run builder, schedule and findings under `runs/`, the scan, `schedule.list`, `schedule.all`, `runs.locate`, API minor 12; `zones.containment` answers the Zone's name. Measured D3b-13 on a 50,040 Edge Model with 5,000 assigned: Zones' per-path scans made the read 22.6 s; a per-read `Zones::ChildLookup` brought it to 1.83 s, still over budget, so the schedule is read on request with no snapshot section (DECISIONS F37 to F40). ACCEPTANCE's shared-wall case corrected to `counted_twice` only (F39). |
| 2026-10-25 | PR #310 opened. Pre-gate Sonnet read: 19 items, 13 fixed (a run over 500 Edges failed the result schema; a page outgrew its budget; tied runs and a loop hung from a junction named by fact order; quantity 1 and 1.0 split; a quadratic counted-twice lookup; `session.inactive` undeclared; a bad cursor walked first; locate scanned per path), the rest recorded or declined. Codex gpt-6.1-sol cycle 1 (2 P2): `runs.locate` could not take a whole long run, and an unclassified Face counted toward an interior junction; fixed in `77587f50`. Cycle 2 (1 P2, 1 P3): a tag in a hidden tag folder passed the hidden check, and two host rows on wrapper identity conflicted; fixed in `e618f1e3` after re-measuring. |
| 2026-10-26 | T04 host gate passed on `e618f1e3` (six assertions; [evidence](evidence/p3b-04-runs-and-schedule.md)). P3b-04 `Implemented on branch`. |
| 2026-10-26 | PR #310 merged to `main` as `85d81a46` (squash, auto-merge on green CI); branch deleted locally and on the remote. P3b-04 `Merged to main`. P3b-05 started on `feature/thermal-bridges-p3b-05`. |
| 2026-10-26 | P3b-05 built: the Thermal Bridges tab with Types and Schedule subtabs, the assign bar, the "Thermal bridge" right-click menu, the preview fixture and browser check; the Materials Duplicate form moved into the kit; the inventory Name header kept sticky (a 4 px pane overhang on every inventory). Pre-gate Sonnet read: 13 items, 12 fixed (Delete could not clear a type used only outside a Zone; a hidden Schedule repainted on every snapshot; the menu client refused a selection the bar would assign; the type list rebuilt under an open dropdown; the New form's Create and Enter; the narrowed menu rescue; tests), the row-click wording recorded in the stage notes. State `In review`. |
| 2026-10-26 | PR #311 opened. Codex gpt-6.1-sol cycle 1 (2 P2): Clear skipped an invalid assignment that reads with no values (bar and menu), and the Types table lacked the stage's column sort and value filters; both fixed, the second by an opt-in `columnMenus` on the kit `Inventory`. The preview's counted-twice fixture now names one container, as the real finding does. |
| 2026-10-26 | Codex gpt-6.1-sol cycle 2 (1 P2): a click on a Schedule row did not locate its run, as the PRD and step 4 ask (the pre-gate read raised it too); fixed, the icon kept as the keyboard route. Review cycles at their cap of two. |
| 2026-10-26 | PR #311 merged to `main` as `de76ddba` (squash, auto-merge on green CI); branch deleted locally and on the remote. P3b-05 `Merged to main`; its JS test count corrected to 750. P3b-06 started on `feature/thermal-bridges-p3b-06`. |
| 2026-10-26 | P3b-06 built: `colour_mode(..., stroke:)` (1 to 10 pixels, checked at registration, the width of the mode's derived lines), the `ph_composer.thermal_bridges.by_type` mode (one entry per assigned Edge occurrence: the Edge as entity, its world segment as `derived`, the type's colour and name, its length as the legend figure; a missing type incomplete) at stroke 5, `Tessellation.skipped?` walking tag folders and the tag observer publishing folder events. Pre-gate Sonnet read: 11 items; fixed the missing folder event, a missing-type label that showed the id, the stroke and composition tests, a per-placement test, a real tag-folder stub, the stroke's own refusal wording and the contract text; recorded the `run_locate` copy of the folder walk and a third hex-to-rgb copy as follow-ups. |
| 2026-10-26 | PR #312 opened. Codex gpt-6-astra cycle 1 (1 P2): a tag moved into or out of a hidden folder arrives as `onParentFolderChanged`, which the tag observer did not forward; fixed, with a test moving a tag in and out. Cycle 2 on `3d7045a7`: no findings. |
| 2026-10-26 | T06 host gate passed on `3d7045a7` (six assertions; [evidence](evidence/p3b-06-colour-by.md)): 5,000 assigned Edges add 7.7 ms a frame and 225 ms a rebuild; folder events reach Colour by on the host. The earlier Colour-by cases the ledger screens accepted by construction, with a Face type and Window Type regression on the host; S05's operation marks offline only. G-04's native drawing proof done. P3b-06 `Implemented on branch`. |
| 2026-10-26 | PR #312 merged to `main` as `da53f66e` (squash, auto-merge on green CI); branch deleted locally and on the remote. P3b-06 `Merged to main`; its Ruby run count corrected to 2,191. P3b-07 started on `feature/thermal-bridges-p3b-07`. |
| 2026-10-26 | P3b-07 built: `features/thermal_bridges/edge_tool.rb`, Mark floor's gesture lifecycle over Edges (`Pick.edge_path`, `zones.containment` per hovered path kept for one revision and edit context, the type, quantity and revision frozen at button-down, a `DragSet` one past the limit so `edges.assign` refuses an over-limit gesture, every cancel route, `ColourBy::Lease` on `by_type`); the hovered Edge drawn at 8 px in the type's colour, or red with the reason as its tooltip when it would refuse. `edge_tool.state`, the `edge_tool` snapshot section and the `edge_tool.choose` and `edge_tool.stop` view commands, API minor 13, "Assign by clicking…" and "Stop assigning by clicking" in the "Thermal bridge" menu, and the agent-guide sentence naming `edges.assign` as the equivalent. The assign bar gains "Assign by clicking", pressed while the tool runs (a second click stops it), and Stop beside it; its type and quantity stay open with nothing selected, show what a running tool assigns, and re-arm it on a change. |
| 2026-10-26 | P3b-07 pre-gate Sonnet read: no high findings, nine items. Fixed a nil tooltip off an Edge, Enter in Quantity writing to the selection while the tool runs, a type chosen with nothing selected lost on selecting unassigned Edges, the collected highlight recolouring when the tool is re-armed mid-drag, `choose` changing state before a refused read, hex and infinite quantities from the menu, a trailing separator, and "Assign by clicking…" joining every right-click; tests added for an edit-path change, a non-Escape cancel and the separator. The hover cost of `zones.containment` per newly hovered path is measured in T07 rather than optimised blind. State `In review`. |
| 2026-10-26 | PR #313 opened. Codex gpt-6.1-sol cycle 1 (1 P2): a type name holding "|" split the native menu's dropdown; fixed in `eceadb3c`. Cycle 2 (1 P2): a numbered label could repeat a real name; fixed in `c64836e7`. Review cycles at their cap of two. |
| 2026-10-26 | T07 host gate with Ed at the mouse. Run 1 at `c64836e7` stopped after the hover step: the arm button lost its pressed look once focus moved to SketchUp, since the kit styles a pressed text button only on hover and focus; fixed in `a0a765a6` (feature stylesheet, browser check moves focus away first). Run 2 at `a0a765a6` passes all eleven assertions ([evidence](evidence/p3b-07-edge-tool.md)): 185 ms to assign 250 Edges, 11 ms to refuse 251, and a newly hovered Edge costs 1.3 ms median, 7.7 ms max, in a 7,506-entity Zone of the 50,040-Edge Model, so the containment read stays uncached. A Window Unit's Edge refuses as a cutting component. P3b-07 `Implemented on branch`. |
| 2026-10-26 | PR #313 merged to `main` as `15c9c535` (squash, auto-merge on green CI); branch deleted locally and on the remote. P3b-07 `Merged to main`. P3b-08 started on `feature/thermal-bridges-p3b-08`. |
| 2026-10-26 | P3b-08 built: `features/thermal_bridges/export.rb`, the export section over the snapshot's assigned Edge entries through the schedule's own `Runs::Schedule.call` (requires the Zones, Faces and Apertures sections; the Zones and Apertures sections gain a registered `projection:`), blocking on a missing type or psi-value and noting every other finding through the new public `reader.note`; `export_preflight` with the window-perimeter warning over the new bounded `ph_composer.windows.units.outlines`; Python `thermal_bridge_sections.py`, optional, attaching at `ROOM` and checking every run before adding any; `assemble` withholds the canonical model only for a required section's refusal (H18, R05 item 4); API minor 14; the shared fixture `tests/fixtures/thermal_bridges/extraction.json`. A host smoke export of the reference model before review read back the five runs on one Building-Segment and passed conformance. |
| 2026-10-26 | P3b-08 pre-gate Sonnet read: no high findings. Fixed: Zone ownership found by rescanning the snapshot per Edge (quadratic at scale; now `Zones::ExportProjection::Owners`, read once, and a component-storage index), the preflight collapsing to one blocking row when Windows' outlines read refuses (now skipped when nothing is assigned, and a non-blocking row saying the perimeter check was skipped), and a refusal test seam that planted a bridge conformance then refused (now an overridable `refused` check, exercised through `export_json`). Added: the result-field contract as a Ruby-written fixture the Python rows are held to, two Building-Segments, a required section's refusal, invalid and unreadable assignments, the outline paging loop and the Apertures outlines. Recorded, not changed: a copied Group's shared storage reads as unshared in the export, and the live and export outlines come from Windows' two placements of a Unit. State `In review`. |
| 2026-10-26 | PR #314 opened; Codex gpt-6-astra cycle 1 (strong review): 1 P2 (`units.outlines` declared an `ids` filter it never applied; it now takes only `limit` and `cursor`) and 1 P3 (the export reached into Zones' internals for ownership; the Zones projection now publishes each Zone's held container paths and the contributor applies the ownership rule to it). Both fixed with tests. |
