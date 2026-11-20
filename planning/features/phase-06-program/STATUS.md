# Phase 4a status

DATE: 2026-11-20
STATUS: Authorized 2026-11-20: Ed authorized P4a-01 to P4a-12 through the implement-loop, with the merge delegated. The authorization does not cover the F4a-13 honeybee-ph and PHX fix or creating the ph-composer-standards repository. P4a-01 implemented on branch.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

The one place this packet's progress is read from.

## Ledger

| Step | State | Date | Record |
| --- | --- | --- | --- |
| Research: honeybee-energy programs, loads and schedules | Complete | 2026-11-14 | [programs](research/honeybee-energy-programs.md), [loads and schedules](research/loads-and-schedules.md) |
| Research: honeybee-ph extensions and PHX consumption | Complete | 2026-11-14 | [PH stack](research/ph-stack-consumption.md) |
| Research: PH-Composer current state and seams | Complete | 2026-11-14 | [current state](research/ph-composer-current-state.md) |
| Findings and interview questions | Complete | 2026-11-14 | [DECISIONS.md](DECISIONS.md) |
| Interview | Complete | 2026-11-14 | [answers](DECISIONS.md#answered): 15 answered, Q4a-08 decided on delegation; Q4a-01, Q4a-16, Q4a-18 open and non-gating |
| Research after redirects: honeybee-ph Process, occupancy and residential program | Complete | 2026-11-14 | F4a-17 to F4a-21 |
| UI prototype: Program tab, Zones/Programs page | Complete | 2026-11-15 | [mockups/](mockups/README.md): five journeys, Q4a-19 to Q4a-28 raised. First review 2026-11-14: shape accepted; Q4a-19, Q4a-20 and Q4a-26 (Single dwelling switch) answered and prototyped; Q4a-27 (switch on by default) and Q4a-28 (Phius values may be published) answered 2026-11-15 |
| Research: Zone ventilation and Space airflows | Complete | 2026-11-15 | [ventilation](research/ventilation.md): F4a-24 to F4a-29; Q4a-29 to Q4a-32 raised |
| UI prototype: Building Segments, Single dwelling per Segment, Zones / Spaces airflows | Complete | 2026-11-15 | [mockups/](mockups/README.md); BS-1 to BS-6 and Q4a-27 to Q4a-32 answered |
| PRD, contracts, plan and stages for the Zones tab | Scoped | 2026-11-15 | [PRD](PRD.md), [Building Segments PRD](building-segments/PRD.md), [CONTRACTS](CONTRACTS.md), [PLAN](PLAN.md), [ACCEPTANCE](ACCEPTANCE.md), [phases/](phases); C4a-5 and C4a-7 to C4a-10 answered; C4a-2, C4a-3, C4a-4, C4a-6 settle in their stages; consistency sweep folded in |
| Authorization: P4a-01 to P4a-12 | Authorized | 2026-11-20 | Ed, through the implement-loop with the merge delegated; not the F4a-13 fix, not the ph-composer-standards repository |
| P4a-01 Building Segment membership | Implemented on branch | 2026-11-20 | Branch `feature/phase-06-program-p4a-01`. Entry check: installed size 26,093,959 bytes on `main` at `4d346ab4` (`make rbz-check`), written to `installed_baseline_bytes` (C4a-14). Zone schema 3, last-Segment refusal `zone.option_last_segment`, null destination, default rule, `removed_extensions`, null `update_field`, Make and Restore, colour-by row, interim export block; API 1.73. `tests/zone_segment_membership_test.rb` 14 runs, 199 assertions; the panel-closed walkthrough `tools/examples/authoring/segment_membership_walkthrough.rb` and `tests/segment_membership_walkthrough_test.rb` 1 run, 12 assertions; `tests/zone_options_panel_test.js`, `overview_panel_test.js`, `zone_views_panel_test.js` 124 pass. Codex (gpt-6-astra) cycle 1 on `f089ef70`: 2 findings, fixed in `37c0d82a`; cycle 2 on `37c0d82a`: 3 findings, fixed after the two-cycle cap (unreviewed fix commit named in the PR). Host gate PG01 on `53c72dbc`: walkthrough, bridge-sent Undo and Redo, save and fresh-process reopen pass ([evidence](evidence/pg01-segment-membership-bridge.md)); native Edit-menu Undo and Redo owed to the batched sitting, ledger row `unknown` |
| P4a-02 to P4a-12 | Authorized | 2026-11-20 | P4a-12 is the closing outline |
| Programs tab review (G1) | Complete | 2026-11-15 | Q4a-21 to Q4a-25 and Q4a-33 to Q4a-36 answered; C4a-5 and C4a-7 to C4a-10 answered |
| Review against Climate and Shading | Complete | 2026-11-20 | Read against the two archived packets and `main` at `b409bdbc`; no code run. The `phx` test group already exists, so P4a-03 no longer adds it; C4a-11 to C4a-14 raised in [CONTRACTS](CONTRACTS.md#open-contract-questions) and answered by Ed the same day, each as recommended; stage notes added to P4a-03, P4a-04, P4a-06, P4a-07, P4a-10, P4a-11 and P4a-12 |
| GitHub issue | Created | 2026-11-20 | [#538](https://github.com/ph-composer/ph-composer-skp/issues/538) (Q4a-18) |
| honeybee-ph and PHX fix for F4a-13 | Requested | | Q4a-08; cross-repo, own authorization |

## Blockers and dependencies

- Occupancy and lighting operating periods wait on the honeybee-ph and PHX fix for F4a-13
  (Q4a-08); until then those Schedules export as rulesets only. Ventilation Schedules write their
  periods now (C4a-10). Nothing else is blocked.
- The Mechanical packet's P4-12 (appliances) is superseded: this packet owns appliances as Equipment Sets
  (Q4a-03). Nothing in Phase 7 mechanical blocks this packet.
- P4a-03's entry check chooses the honeybee-ph pin for `PhEquipment` (F4a-18) and moves the `phx` test
  group with it (C4a-11, Ed, 2026-11-20). Today the group pins PHX 1.57.5, the latest release over
  honeybee-ph 1.33.65.
- P4a-01's entry check reset the installed-size baseline to 26,093,959 bytes, measured on `main` at
  `4d346ab4` (C4a-14, Ed, 2026-11-20).
- Building Segment management, the Segment settings dialog and Zones outside every Segment are
  stages P4a-01 to P4a-04 ([building-segments](building-segments/PRD.md)), ahead of the Programs
  stages (BS-5).
- The Phius program library files live in the planned [ph-composer-standards](../unscheduled/ph-composer-standards/README.md)
  repository (Q4a-19). Ed cleared publishing them on 2026-11-15 (Q4a-28); they wait on the repository
  and on the Program and Schedule kinds.

## Verification

Research claims were checked against the pinned wheels (honeybee-energy 1.123.23, honeybee-ph
1.33.65) and, for PHX, against the local checkout at 1.59.1. Example HBJSON dicts were produced by
running honeybee-energy. Spot-checked by hand: the Phius base programs (F4a-14), PHX's unguarded schedule `ph` reads
(F4a-15) and the ExhaustAir pin difference (F4a-16). The PHX double count (F4a-13) was confirmed
by running a Phius meeting-room People and Lighting load through PHX's schedule builders.

Since then Climate added the `phx` test group at PHX 1.57.5. The PHX findings above were read at
1.59.1 and have not been rerun at 1.57.5; P4a-03's entry check sets the pins they are rerun on (C4a-11).
