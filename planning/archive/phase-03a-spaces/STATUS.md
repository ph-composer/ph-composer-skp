# Phase 3a: Spaces, tracking ledger

DATE: 2026-10-17
STATUS: Complete 2026-10-17 and archived. P3a-01 to P3a-12 merged to main (PRs #135 to #171); S01 to S11 pass with ledger results and S12's integrated run is done; the earlier cases the Spaces changes screened were rerun, and the two regressions found (#179, #188) were fixed (#187, #190) and rechecked. ZO-O7 fails on #181, a follow-up. Not released.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#133](https://github.com/bldgtyp/ph-composer/issues/133)

This is the one place Phase 3a completeness is read from. Update it in the same change as any
stage's state. States use the canon vocabulary: `Requested`, `Scoped`, `In progress`, `Blocked`,
`In review`, `Implemented on branch`, `Merged to main`, `Complete`, `Deferred`, `Superseded`.

## State

PRD drafted 2026-09-18 from Ed's brief (Spaces inherit from their Zone, the one ventilation
override, equipment on the Zone, volume as the missing piece), the predecessor's Spaces feature,
honeybee-ph's Space classes, the 2019 dPH+ Rooms extension and the Phius iCFA and net volume
rules. Interviewed the same day: two rounds, 18 decisions, recorded in the PRD and folded into its
behavior sections. Shared understanding reached, pending Ed's confirmation of the record.

Planned in detail on 2026-10-03: twelve stages, P3a-01 to P3a-12. A review of the PRD against
`main` at `70c340f` found twenty-two differences and raised twelve decisions, D3a-1 to D3a-12, all
open. Amendments for those twelve questions wait for Ed's answers and are listed in
[DECISIONS](DECISIONS.md).

Ed confirmed [D3a-13](DECISIONS.md#confirmed-copy-decision-d3a-13) on 2026-10-12: Spaces included
in a Zone copy become independent authored instances, including their descendants and membership
references; Window Units follow their existing Type protocol. This qualifies PRD Q20 and adds
P3a-04/S04/S10/S12 integration requirements. The twelve earlier decisions remain open. No Spaces
stage or child-copy mechanism is authorized or implemented.

Re-baselined on 2026-10-15 against `main` at `87bdc62`, about 240 commits after the plan was
drafted. [DECISIONS](DECISIONS.md), Part 1b, re-reads every finding: the Ruby units and the
section-cycle refusal are merged; D3a-13's Zone-copy mechanism exists (`transition_contributor`,
with Windows as the first adopter); Zones copies are made independent automatically; record
`user_data` can pass through to HBJSON; Zones / Faces is table-first. Foundation stages are
corrected; screen stages carry a note and wait for the UI discussion. Two decisions added:
D3a-14 and D3a-15.

The UI and UX discussion with Ed on 2026-10-15, worked through a [mockup](mockups/README.md),
made Spaces a view of the Zones tab (D3a-16) with a numeric weighting factor (D3a-17), answered
D3a-6, D3a-7, D3a-11 and D3a-14, superseded D3a-8 and raised D3a-18. The screen stages are now
P3a-06 (Zone views), P3a-07 (the Spaces view, absorbing airflows and the balance) and P3a-08 (Mark
floor and Create Space).

Ed then answered every remaining decision, each as recommended, and confirmed the PRD's
interview record (2026-10-15). The PRD carries every amendment.

## Next step

None. Ed closed Phase 3a on 2026-10-17 and the packet is archived. Open follow-ups are GitHub issues,
listed under "Deferred out of this plan" below; Phase 3b's dependency on P3a-01 and P3a-05 is met.

## Blockers

- None from the overlay spike: it passed on 2026-09-18 ([B2](../phase-00-foundation/evidence/spike-overlay.md)), and translucent
  depth-tested fills work on the proving host, so the volume preview needs no edge fallback.
- The foundation transplant landed without the deferred-reconciliation primitives, the
  edit-context writer or Volume protection this PRD expected from it. P3a-03 builds them.
- None from decisions: all answered 2026-10-15.

## Entry gates

| Gate | State |
| --- | --- |
| Ed confirms the Spaces PRD's interview record (pending since 2026-09-18) | Closed 2026-10-15 |
| D3a-1 answered (blocks P3a-01) | Closed 2026-10-15 |
| D3a-2 to D3a-5, D3a-9, D3a-10, D3a-12, D3a-15 and D3a-18 answered, each before the stage it blocks | Closed 2026-10-15 |
| The Spaces UI and UX discussion held and the screen stages revised | Closed 2026-10-15: D3a-16 and D3a-17; P3a-06 to P3a-08 restructured |
| A phase issue exists on `bldgtyp/ph-composer`, and every header's `ISSUE` line points at it | Closed 2026-10-15: [#133](https://github.com/bldgtyp/ph-composer/issues/133) |
| Ed authorizes implementation, stage by stage or for a run of stages | Closed 2026-10-15: the whole packet, one stage per pull request, merged on green CI |
| Phase 2 review refactors that touch the same shared files are merged or parked | Closed: [shared-deep-freeze](../shared-deep-freeze.md) merged through PR #83 on 2026-10-07 |

## Stage ledger

"Offline" is `make ci` on both Rubies at the stage's gate. "Host" is the stage's host gate in a
fresh process. "Review" is the one review the ladder assigns. A stage is `Implemented on branch`
only when all three are done and its evidence file exists.

| Stage | Title | State | Blocked by | Branch / PR | Offline | Host | Review | Evidence | Register |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [P3a-01](phases/p3a-01-contracts-and-groundwork.md) | Contracts and groundwork | Merged to main | | PR [#135](https://github.com/bldgtyp/ph-composer/pull/135), `a501ac3` | `make ci` pass (Ruby 3.2.2 local; 2.7.2 in CI) | S01 pass in the 2026-10-16 rerun (ledger), 26.1.188 | Codex gpt-6-astra, two passes: 1 P1 and 4 P2, all fixed | [p3a-01](evidence/p3a-01-groundwork.md) | S01 |
| [P3a-02](phases/p3a-02-space-records-and-operations.md) | Space records and operations | Merged to main: slice A through PR [#136](https://github.com/bldgtyp/ph-composer/pull/136) (`0421e2e`), slice B through PR [#137](https://github.com/bldgtyp/ph-composer/pull/137) (`b193dbc`) | | #136, #137 | `make ci` pass on each slice (Ruby 3.2.2 local; 2.7.2 in CI) | S02 pass; rerun pass 2026-10-16 (ledger), 26.1.188 | slice A: Codex gpt-6.1-sol, two passes, 3 P1 and 4 P2, all fixed; slice B: Codex gpt-6.1-sol, two passes, 6 P1 and 3 P2, all fixed | [p3a-02](evidence/p3a-02-space-records.md) | S02 |
| [P3a-03](phases/p3a-03-edit-contexts-protection-and-reconciliation.md) | Edit contexts, protection and reconciliation | Merged: slice A through PR [#138](https://github.com/bldgtyp/ph-composer/pull/138) (`5db65ac`), slice B through PR [#140](https://github.com/bldgtyp/ph-composer/pull/140) (`67469be`); native rows run in P3a-12 | | #138, #140 | `make ci` pass on each slice | S03 pass in the 2026-10-16 rerun (ledger), 26.1.188 | Codex gpt-6-astra, two passes per slice: slice A 1 P1 and 1 P2, slice B 4 P1 and 2 P2, all fixed | [p3a-03](evidence/p3a-03-contexts-and-reconciliation.md) | S03 |
| [P3a-04](phases/p3a-04-copies-and-move-space-to-zone.md) | Copies and Move Space to Zone | Merged in four slices: A [#141](https://github.com/bldgtyp/ph-composer/pull/141) (`92fede8`), B1 [#142](https://github.com/bldgtyp/ph-composer/pull/142) (`a838feb`), B2 [#144](https://github.com/bldgtyp/ph-composer/pull/144) (`adcd7e3`), B3 [#146](https://github.com/bldgtyp/ph-composer/pull/146) (`b328e7f`). native rows run in P3a-12 | P3a-03 | #141, #142, #144, #146 | `make ci` pass | S04 pass in the 2026-10-16 rerun (ledger), 26.1.188 | strong: two passes per PR; A 10, B1 8, B2 6, B3 5 findings, all fixed (each PR's last fixes gated by `make ci` only, review cap) | [p3a-04](evidence/p3a-04-copies-and-move.md) | S04 |
| [P3a-05](phases/p3a-05-colour-by-derived-geometry-and-readouts.md) | Colour-by derived geometry and readouts | Merged in two slices: A [#147](https://github.com/bldgtyp/ph-composer/pull/147) (`7c7521b`), B [#148](https://github.com/bldgtyp/ph-composer/pull/148) (`74365c7`); overlay captures in P3a-12 | P3a-01 | #147, #148 | `make ci` pass | S05 pass in the 2026-10-16 rerun (ledger, synthetic composition), draw cost re-measured | strong: slice A two passes, 2 P1 and 6 P2, fixed (last three gated by `make ci` only, review cap); slice B two passes, 1 P2 fixed, then approved | [p3a-05](evidence/p3a-05-colour-by-extension.md) | S05 |
| [P3a-06](phases/p3a-06-zone-views.md) | Zone views | Merged through PR [#149](https://github.com/bldgtyp/ph-composer/pull/149) (`42b6316`) | Entry gates | #149 | `make ci` pass; `make ui-checks` pass | S06 pass in the 2026-10-16 rerun (ledger, synthetic composition); #179 regression on the narrow Zones tab, fixed by #187 and rechecked (A09 pass); the narrow selection bar (#188) fixed by #190 and rechecked | strong: two passes, 5 P1 and 8 P2, all fixed (second pass's five gated by `make ci` only, review cap) | [p3a-06](evidence/p3a-06-zone-views.md) | S06 |
| [P3a-07](phases/p3a-07-spaces-view.md) | The Spaces view | Implemented in five pull requests: A [#150](https://github.com/bldgtyp/ph-composer/pull/150) (`7619964`), B [#151](https://github.com/bldgtyp/ph-composer/pull/151) (`a9d2f72`), C1 [#152](https://github.com/bldgtyp/ph-composer/pull/152) (`34db51a`), C2 [#153](https://github.com/bldgtyp/ph-composer/pull/153) (`803e95b`) merged; D [#155](https://github.com/bldgtyp/ph-composer/pull/155) (`3e0dd5a`) merged | P3a-04, P3a-06 | #150 to #153, #155 | `make ci` pass; `make ui-checks` pass | S07 pass in the 2026-10-16 rerun (ledger), except the 300-Space timing (#154) | ordinary, UI: A 7 P2; B 7 P2; C1 1 P1 and 8 P2; C2 5 P1 and 7 P2; D 3 P2 and 1 P3; all fixed (each PR's last fixes gated by `make ci` only, review cap) | [p3a-07](evidence/p3a-07-spaces-view.md) | S07 |
| [P3a-08](phases/p3a-08-mark-floor-and-create-space.md) | Mark floor and Create Space | Merged in three slices: A [#156](https://github.com/bldgtyp/ph-composer/pull/156) (`271367d`), B [#159](https://github.com/bldgtyp/ph-composer/pull/159) (`aa88a96`), C [#160](https://github.com/bldgtyp/ph-composer/pull/160) (`f780797`) | P3a-03, P3a-07 | #156, #159, #160 | `make ci` pass; `make ui-checks` pass | S08 pass in the 2026-10-16 rerun (ledger) | A strong: two passes, 3 P1, 9 P2 and 1 P3, all fixed; B ordinary: two passes, 6 P2, all fixed; C strong: two passes, 2 P1 and 5 P2, all fixed | [p3a-08](evidence/p3a-08-mark-floor.md) | S08 |
| [P3a-09](phases/p3a-09-space-modes-preview-labels-totals.md) | Modes, preview, labels and totals | Merged in three slices: A [#162](https://github.com/bldgtyp/ph-composer/pull/162) (`7e87397`), B [#163](https://github.com/bldgtyp/ph-composer/pull/163) (`a8930e4`), C [#164](https://github.com/bldgtyp/ph-composer/pull/164) (`e30528c`) | P3a-05, P3a-07, P3a-08 | #162, #163, #164 | `make ci` pass; `make ui-checks` pass | S09 pass in the 2026-10-16 rerun (ledger) | A strong: two passes, 3 P1 and 5 P2, all fixed; B ordinary: two passes, 4 P2, all fixed; C ordinary: two passes, 1 P2, fixed | [p3a-09](evidence/p3a-09-space-modes.md) | S09 |
| [P3a-10](phases/p3a-10-spaces-export.md) | Spaces export | Merged in two slices: A [#165](https://github.com/bldgtyp/ph-composer/pull/165) (`558ab56`), B [#166](https://github.com/bldgtyp/ph-composer/pull/166) (`12b7fa7`) | P3a-04 | #165, #166 | `make ci` pass; `make ui-checks` pass; `make runtime-browser-check` pass | S10 pass in the 2026-10-16 rerun (ledger) | A strong: two passes, 1 P1 and 5 P2, all fixed; B strong: two passes, 1 P1 and 2 P2, all fixed | [p3a-10](evidence/p3a-10-spaces-export.md) | S10 |
| [P3a-11](phases/p3a-11-height-from-solid.md) | Height from solid | Merged to main through PR [#167](https://github.com/bldgtyp/ph-composer/pull/167) (`f910452`) | P3a-07 | #167 | `make ci` pass; `make ui-checks` pass | S11 pass in the 2026-10-16 rerun (ledger), native Undo included | ordinary, UI: two passes, 3 P2 and 1 P3, all fixed | [p3a-11](evidence/p3a-11-height-from-solid.md) | S11 |
| [P3a-12](phases/p3a-12-spaces-acceptance-and-handoff.md) | Spaces acceptance and handoff | Merged to main through PR [#171](https://github.com/bldgtyp/ph-composer/pull/171); integrated run done, Ed's four items answered, acceptance rerun recorded in PR [#186](https://github.com/bldgtyp/ph-composer/pull/186); #179 and #188 fixed (#187, #190) and rechecked; closing is Ed's call | all | `feature/spaces-p3a-12` | `make ci` pass on Ruby 3.2.2 and 2.7.2 | S12 integrated run, 26.1.188 | none; consolidation | [p3a-12](evidence/p3a-12-acceptance.md) | S12 |

Milestones: M1 after P3a-04 (Spaces as data), M2 after P3a-08 (authoring on screen) and M3 after P3a-10
(exported and read back) are all met: S03, S04, S08 and S10 pass with ledger results in the 2026-10-16 rerun.
Register ids S01 to S12 are in [ACCEPTANCE.md](ACCEPTANCE.md).

## Decisions

| ID | Kind | Subject | Blocks | State |
| --- | --- | --- | --- | --- |
| D3a-1 | Code | Zones' rule for a Space group inside a Zone | P3a-01 | Answered 2026-10-15: stamped Group is a container |
| D3a-2 | Code | Foundation ids, not UUIDs | P3a-02 | Answered 2026-10-15: foundation ids |
| D3a-3 | Code | `duplicate_identity` local to Spaces | P3a-04 | Answered 2026-10-15: Spaces-local |
| D3a-4 | Code | Edit-context writer and deferred work live in `session/` | P3a-03 | Answered 2026-10-15: `session/` |
| D3a-5 | Code | The Colour-by extension; operation marks in the same stage | P3a-05 | Answered 2026-10-15: `derived` and readouts; marks in P3a-05 |
| D3a-6 | UI | Where Spaces live on screen | P3a-07 | Answered 2026-10-15: a view of the Zones tab (D3a-16) |
| D3a-7 | UI | How Mark floor and Create Space start | P3a-08 | Answered 2026-10-15: column-menu paint; native context menu |
| D3a-8 | Code | Balance grouping as a function | none | Superseded 2026-10-15: no balance view; sums on Zone rows |
| D3a-9 | Code | The Spaces export section is required for export | P3a-10 | Answered 2026-10-15: required |
| D3a-10 | Code | A blocked run still reports its schedules, labelled | P3a-10 | Answered 2026-10-15: shown, labelled |
| D3a-11 | UI | The Level rail and saved column layout | P3a-07 | Answered 2026-10-15: no rail; layout follows the shared table |
| D3a-12 | UI | What the 10 percent imbalance is measured against | P3a-07 | Answered 2026-10-15: of the larger sum |
| D3a-13 | Behavior | Independent Space children in a proven Zone copy; Windows follow their Type protocol | P3a-04; acceptance S04/S10/S12 | Confirmed 2026-10-12; delivered in P3a-04 B3; host evidence 2026-10-16 in [p3a-12](evidence/p3a-12-acceptance.md) |
| D3a-14 | UI and behavior | A standalone native Space copy made independent automatically, as Zones' copy watcher does | P3a-04 | Answered 2026-10-15: yes |
| D3a-15 | Code | Spaces opts in to `user_data` pass-through to HBJSON | P3a-10 | Answered 2026-10-15: yes |
| D3a-16 | UI | One Zones tab with views: Faces, Spaces, later loads and equipment | P3a-06, P3a-07 | Answered 2026-10-15 |
| D3a-17 | UI and code | Weighting factor, a number from 0 to 1 with quick picks | P3a-02, P3a-07, P3a-08 | Answered 2026-10-15 |
| D3a-18 | UI | Select by through column filters and check-all, no cell menu | P3a-07 | Answered 2026-10-15: filter and check-all |
| D3a-19 | Behavior | Autosave closes an open Volume under the predecessor's save rule; keep it or unlock again after a save. A native Cmd+S also leaves the path at the Model root, not the Space (P3a-12) | none (follow-up) | Answered 2026-10-16: B3 after the spike, a save leaves the open Volume unlocked and the user in it; Volumes saved unlocked are protected on open. Implemented on `feature/spaces-save-keeps-volume-d3a-19` ([evidence](evidence/d3a-19-save-keeps-volume.md)) |
| D3a-20 | Delivery | Installed footprint limits: raise to a 24 MB target and 26 MB ceiling, plus a 1.5 MB per-phase growth budget | Phase 3b packaging | Answered 2026-10-16: yes; enforced by `rbz-check` from the PR that applies it |

## Owed from elsewhere, allocated here

| Item | Source | Stage | State |
| --- | --- | --- | --- |
| Derived-geometry Colour-by extension | D2-6 | P3a-05 | Merged through #147 |
| Window Type operation marks | D2-6 | P3a-05 slice B (D3a-5) | Merged through #148 |
| Empty Room defect | R05 item 1 | P3a-01 | Merged through #135: refused as `object.unavailable` |
| Section-read cycle refusal | R05 item 2 | none | Delivered on `main` by PR #122 (`registration.cycle`); P3a-01 corrects validation-and-export's STATUS |
| Results from runs that cannot publish | R05 item 3 | P3a-10 | Merged through #166 (D3a-10) |
| Optional attaching section rule | R05 item 4 | Moved to Phase 3b, [P3b-08](../phase-03b-thermal-bridges/phases/p3b-08-thermal-bridge-export.md), which delivers the first optional attaching section (D3b-20) | Moved |
| Restore Zone reads Space stamps | zones Q14 | P3a-04 | Implemented in slice B1 |
| Where Zones appear, re-ruled | zones Q13 | none | Settled 2026-10-15 by D3a-16: every view of the Zones tab shows the Zone rows |
| Unit-switch repaint cost on a large table | units U1-F1 | P3a-07, measure first | Browser preview median 815 ms at 300 Spaces (P3a-12); host measurement in #154 |
| Ruby `volume` and `airflow` quantities | [units packet](../../features/cross-phase/units/STATUS.md), standalone extraction confirmed 2026-10-07 | none | Merged through PR #84. Nothing left for Spaces but to use them |

## Deferred out of this plan

| Item | Where it waits |
| --- | --- |
| "Through PHX" and METr room checks | [metr-export](../../features/unscheduled/metr-export/README.md) |
| Height drag handle (Q6) | Spaces PRD, non-goals |
| Toolbar buttons for Classify, Place and Mark floor | [zones-entry-points](../../features/unscheduled/zones-entry-points/README.md) E1 |
| Airflow balance by ventilator; by-unit and by-system modes; the Ventilation and Heat pump assignment views, or Systems tabs listing the Zones each unit serves | [equipment](../../features/phase-04-mechanical/equipment/README.md) |
| Occupancy, Electric loads and appliances, Lighting and Hot water Zone views | The Zone loads packet, not yet drafted; P3a-06's contract admits a view with no child rows |
| Inherited airflow values from Zone loads | The Zone loads packet, not yet drafted |
| One shared duplicate-identity contract across Zones, Windows and Spaces | [#145](https://github.com/bldgtyp/ph-composer/issues/145) (D3a-3), recorded as P3a-04 closed |
| `Zones::Names::State` and the Zones copy watcher on the deferred-work primitive | [#139](https://github.com/bldgtyp/ph-composer/issues/139) (D3a-4) |
| `Zones::Names::State` container observation on `session/ContainerWatch` | [#143](https://github.com/bldgtyp/ph-composer/issues/143) (P3a-04 B2) |
| Panel Cmd+Z and Cmd+Shift+Z reaching SketchUp's Undo and Redo | [#168](https://github.com/bldgtyp/ph-composer/issues/168) (P3a-12) |
| Floor outlines flush with Zone walls split the walls; Create Space refuses them | [#169](https://github.com/bldgtyp/ph-composer/issues/169) (P3a-12) |
| Spaces wording and display points from the integrated run | [#170](https://github.com/bldgtyp/ph-composer/issues/170) (P3a-12) |
| Spaces view unit-switch repaint on a 300-Space table, measured on the host | [#154](https://github.com/bldgtyp/ph-composer/issues/154) (U1-F1) |
| Panel keeps showing a closed Model until another document is activated | [#174](https://github.com/bldgtyp/ph-composer/issues/174) (acceptance rerun) |
| Intermittent TypeError in container_added and zone_container_listener | [#175](https://github.com/bldgtyp/ph-composer/issues/175) (acceptance rerun) |
| AuthoringWalkthrough edits Zone options with raw strings and reports passed anyway | [#176](https://github.com/bldgtyp/ph-composer/issues/176) (acceptance rerun) |
| Corrections walkthrough r01_check assumes exactly two placements | [#177](https://github.com/bldgtyp/ph-composer/issues/177) (acceptance rerun) |
| Narrow native-acceptance case dependency patterns | [#178](https://github.com/bldgtyp/ph-composer/issues/178) (acceptance rerun) |
| Zones tab: a narrow panel scrolls the whole tab sideways (P3a-06 regression); fixed by #187 and rechecked | [#179](https://github.com/bldgtyp/ph-composer/issues/179) (acceptance rerun) |
| Narrow Zones tab: the selection bar overruns the table (Solve under the footer at 420 px, header covered at 360 x 520); fixed by #190 and rechecked | [#188](https://github.com/bldgtyp/ph-composer/issues/188) (#179 recheck) |
| cases.json: S07 asserts the Spaces selection bar but does not depend on `selection_bar.js` or `overview.js` | [#191](https://github.com/bldgtyp/ph-composer/issues/191) (#188 recheck) |
| Manage Building Segments merge note says Level | [#180](https://github.com/bldgtyp/ph-composer/issues/180) (acceptance rerun) |
| Make Zone independent: component and copied-Group remedies that do not work | [#181](https://github.com/bldgtyp/ph-composer/issues/181) (acceptance rerun) |
| Make Component on a Zone Group empties the Zones tab | [#182](https://github.com/bldgtyp/ph-composer/issues/182) (acceptance rerun) |
| Colour by Space: Spaces sharing one colour | [#183](https://github.com/bldgtyp/ph-composer/issues/183) (acceptance rerun) |
| Height from solid menu silent on a wrong selection | [#184](https://github.com/bldgtyp/ph-composer/issues/184) (acceptance rerun) |
| Zones tab: a focused filter blocks switching views | [#185](https://github.com/bldgtyp/ph-composer/issues/185) (acceptance rerun) |

## Verification

No Spaces stage verification. The standalone Ruby units slice is tracked in the
[units execution receipt](../../features/cross-phase/units/STATUS.md#current-execution-receipt). It does not
close S01 or the Spaces entry gates. The findings in DECISIONS Part 1 were read from source
and not reproduced.

## How to update this file

1. When a stage starts: state `In progress`, fill Branch.
2. At its gate: record the `make ci` result, the host gate result with the ledger case ids, and
   the review outcome in the three columns, and link the evidence file.
3. Then `Implemented on branch`; after merge `Merged to main` with the PR number.
4. Flip the matching ACCEPTANCE row in the same change.
5. When a decision is answered: record Ed's answer and date in DECISIONS, set the row here to
   `Answered`, and apply the PRD amendment DECISIONS lists for it.
6. Add a ledger row below for each of the above.
7. Mirror the summary line into [planning/STATUS.md](../../STATUS.md) and the Phase 3 table in
   [ROADMAP.md](../../ROADMAP.md).

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted. |
| 2026-09-18 | Interview complete: 18 decisions. Notable: membership is the parent group with Spaces drawn anywhere; no iCFA enforcement; two-state iCFA factor; all three airflows; an airflow balance view grouped by Zone now and by ventilator later; Move Space to Zone; colour field dropped. |
| 2026-09-18 | Architecture review run against `context/EXTENSIBILITY.md` and folded into the PRD, then removed. Q19: Mark floor is a sibling tool owned by Spaces. Q20: a copy is the blocking `duplicate_identity` finding with a Make independent repair. Q21: any airflow set makes unset read as zero; all unset inherits the Zone's load; the exporter writes explicit zeros so PHX is unchanged. Q22: Colour-by gains an open entity kind, derived geometry and readouts. Q23: sloped floors export projected. Q24: Move Space to Zone's record transition. Also added: the port disposition, identifiers and `user_data` on the records, the m3/h to m3/s conversion, the Room section dependency, the balance view's grouping provider. Open: the translation-section dependency question in the foundation packet. |
| 2026-09-30 | Phase directory created as a router when feature packets were regrouped by phase. |
| 2026-10-03 | Spaces planned in detail: the coordinating packet, twelve stage documents, twenty-two findings and twelve decisions for Ed. The translation-section dependency question is closed by the merged `Requirement` and `Attachment(ROOM)` (F18). No implementation authorized. |
| 2026-10-03 | Ed split Phase 3 into two flat packets, `phase-03a-spaces/` and `phase-03b-thermal-bridges/`. The Spaces feature packet (PRD, README, STATUS) merged into this folder; stages P3-01 to P3-12 became P3a-01 to P3a-12 and decisions D3-1 to D3-12 became D3a-1 to D3a-12. S ids, F ids and H numbers are unchanged. R05 item 4 moved to Phase 3b. |
| 2026-10-07 | Ed authorized extracting Ruby volume/airflow groundwork into the units branch. P3a-01 reuses it; all Spaces stage gates remain open. |
| 2026-10-15 | Re-baselined against `main` at `87bdc62`: DECISIONS Part 1b re-reads F1 to F22 and adds F23 to F27; recommendations refreshed for D3a-3, D3a-4, D3a-5, D3a-6, D3a-9 and D3a-11; D3a-14 and D3a-15 added; CONTRACTS, PLAN, ACCEPTANCE and the foundation stages corrected; screen stages noted and held for the UI and UX discussion. No decision answered, no stage authorized. |
| 2026-10-15 | UI and UX discussion: Spaces is a view of the Zones tab (D3a-16), the factor is a numeric weighting factor (D3a-17), D3a-6, D3a-7, D3a-11 and D3a-14 answered, D3a-8 superseded, D3a-18 raised. P3a-06 is now Zone views, P3a-07 the Spaces view (absorbing the former airflow and balance stage) and P3a-08 Mark floor and Create Space. PRD, CONTRACTS, PLAN and ACCEPTANCE amended; mockups added. |
| 2026-10-15 | Ed answered D3a-1 to D3a-5, D3a-9, D3a-10, D3a-12, D3a-15 and D3a-18, each as recommended, and confirmed the interview record. Remaining entry gates: the phase issue and Ed's go. |
| 2026-10-15 | Phase issue [#133](https://github.com/bldgtyp/ph-composer/issues/133) created; every header in the packet points at it. The only open entry gate is Ed's go. |
| 2026-10-15 | Ed authorized the whole packet, one stage per pull request. P3a-01 implemented on `feature/spaces-p3a-01`: the nested-container rule, the empty-Room refusal, CONTRACTS section 8; S01 passed on the host. |
| 2026-10-15 | P3a-01 merged to main through PR #135 (`a501ac3`) after two Codex gpt-6-astra passes (1 P1, 4 P2, all fixed). P3a-02 split into slices A and B, one host gate after B. |
| 2026-10-15 | P3a-02 merged to main through #136 and #137. P3a-03 slice A merged through #138. P3a-03 slice B implemented; its host gate ran the bridge and background rows (pass) and found two transform defects, fixed; the native-keystroke rows wait for Ed's screen-takeover approval. D3a-19 (autosave closes an open Volume) raised; follow-up #139 filed. |
| 2026-10-15 | P3a-03 slice B merged through #140 after two strong review passes; the review replaced `context.enter_volume` with the action `volumes.unprotect` and `context.open` (CONTRACTS section 8). Native-keystroke host rows still pending. P3a-04 slice A implemented. |
| 2026-10-15 | P3a-04 slice A merged through #141 after two strong review passes (ten findings fixed; the last three not re-reviewed, at the cap). Slice B split into B1 (Zones container stamps and Restore), B2 (the copy watcher) and B3 (the Zone-copy contributor and walkthrough). |
| 2026-10-15 | P3a-04 B1 merged through #142 (Zones keeps container stamps current; Restore recovers stamped Groups) after two strong passes, eight findings fixed. Follow-up #143 filed (Zones container observation onto `session/ContainerWatch`). |
| 2026-10-15 | P3a-04 B2 merged through #144 (the `container_added` event and the Space copy watcher) after two strong passes, six findings fixed. B3 (`follow_zone_copy`, walkthrough) implemented. S04 bridge rows ran and passed on 26.1.188; the native rows wait with S03's. Refactor candidate #145 (D3a-3) filed. M1 implemented; its native rows pending. |
| 2026-10-15 | P3a-04 B3 merged through #146 after two strong passes (five findings fixed); P3a-04 complete, its native S04 rows pending. P3a-05 design note reviewed against the architecture rubric and slice A (derived geometry and readouts) implemented; G-03's `LineEntry` superseded. |
| 2026-10-15 | P3a-05 slice A merged through #147 (derived geometry, readouts, the example) after two strong passes, eight findings fixed. Slice B (Window Type operation marks) implemented; D2-6's marks recorded as delivered in the window-types packet. P3a-06's design note written and reviewed. |
| 2026-10-15 | P3a-02 host gate passed (S02): the panel-closed walkthrough, one native Undo and Redo per write, native copy, cut and Make Unique of a Space Group, airflow states and `user_data` through save and reopen, two Models isolated. Slice A reviewed twice and fixed. |
| 2026-10-16 | P3a-11 merged through #167. P3a-12's integrated host run on 26.1.188: S03, S04 (with D3a-13) and S07 to S10 observed on the host and S11 partly, none with a ledger result; S05 and S06 partly run; host measurements recorded (solid volume, held-drag flags, context changes as Undo entries). Offline gates pass on both Rubies. Follow-ups #168 to #170 filed. Waiting on Ed: record or rerun the host rows under the acceptance procedure, rerun or accept the 31 earlier cases the ledger screens stale, the 24 MB ceiling (5,937 bytes left), D3a-19. |
| 2026-10-16 | Ed answered P3a-12's four items: (1) rerun S03, S04 and S07 to S11 under the native-acceptance procedure, with capture baselines, observe receipts and ledger results, including S11's native Undo; (2) rerun all 31 earlier cases the ledger screens, in the same host session; (3) D3a-20, raise the footprint limits to 24 MB target and 26 MB ceiling with a 1.5 MB per-phase growth budget; (4) D3a-19, restore the user after a save, spike first. Follow-up: narrow the broad dependency patterns in `cases.json`. |
| 2026-10-16 | Acceptance rerun on `main` at `e6059fa9` (RBZ `28bac2c8`), with capture baselines, observe receipts and ledger results: S01 to S11 pass (S05 and S06 in synthetic composition); 30 of the 31 screened earlier cases rerun (R05 superseded), all passing except A09 and UXR-PAINT (#179) and ZO-O7 (#181); normal restoration verified. Follow-ups #174 to #185 filed. |
| 2026-10-16 | #179 fixed through #187 (`9781190f`, RBZ `89afe2ef`) and rechecked on the host: A09 and UXR-PAINT rerun in full with capture baselines, receipts and ledger results; the other 13 screened cases unaffected by construction. A09 passes. UXR-PAINT passes except the narrow clause, which fails on #188 (the selection bar overruns the table; at 420 px a result of the fix's wrapping control row, at 360 x 520 pre-existing). Normal restoration verified. |
| 2026-10-17 | #188 fixed through #190 (`3db8f281`, RBZ `11b5f00f`): the Zones table fits its pane, and the selection bar docks beneath the table where floating would cover its header (Ed's choice). Host recheck with capture baselines, receipts and ledger results: A09, UXR-SOLVE and UXR-PAINT pass; the other 14 screened cases unaffected by construction (ZO-O7 keeps its fail on #181). Normal restoration verified. Follow-up #191 (S07's dependency paths). |
| 2026-10-17 | Ed closed Phase 3a; packet archived as `phase-03a-spaces` (issue #133 closed). The archive move rewrote one link in `context/SKETCHUP_HOST_BEHAVIOR.md`, which makes the ledger screen A02, A05 and R01 to R04 stale; a link path changes nothing they assert (over-broad pattern, #178). |
