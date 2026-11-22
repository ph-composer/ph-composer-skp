# Phase 4: mechanical, tracking ledger

DATE: 2026-10-21
STATUS: Scoped. Interviewed (shared shape, Ventilators, hot water) and planned as P4-01 to P4-15 on 2026-10-21; D4-01 to D4-12 answered as recommended the same day; nothing authorized or implemented. Wireframes reviewed 2026-11-15: D4-13 to D4-20 answered, revising D4-08 and five interview answers; CONTRACTS, ACCEPTANCE and stages P4-05 to P4-11 owe re-planning; Climate's entry gate for the heat pumps met 2026-11-18. Reviewed 2026-11-22 after Phase 6 Programs: stale gates and facts corrected, stage P4-08b added; D4-21 to D4-27 answered the same day, all as recommended, and the bindings re-bound to them.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

This is the one place Phase 4 completeness is read from. Update it in the same change as any
stage's state. The three feature packets ([equipment](equipment/STATUS.md),
[hot-water-piping](hot-water-piping/STATUS.md), [erv-ducting](erv-ducting/STATUS.md)) keep their
interview state and point here for stages; they hold no competing progress ledger. States use
the canon vocabulary: `Requested`, `Scoped`, `In progress`, `Blocked`, `In review`,
`Implemented on branch`, `Merged to main`, `Complete`, `Deferred`, `Superseded`.

## State

PRDs drafted 2026-09-18 and re-baselined against `main` at `420c783a` on 2026-10-21. The same
day Ed answered the equipment shared shape (Q1 to Q12), Ventilators (V1 to V6) and hot water
(H1 to H7); the equipment PRD is the record. Planned in detail from those answers: fourteen
findings and twelve decisions in [DECISIONS.md](DECISIONS.md), bindings in
[CONTRACTS.md](CONTRACTS.md), fifteen stages in [phases/](phases) and fifteen register rows in
[ACCEPTANCE.md](ACCEPTANCE.md). P4-01 to P4-07 and P4-15 are planned in full; P4-08 to P4-14 are
gate stubs until families 3 to 7, piping and ducting are interviewed. Since then family 7 went to
Phase 6 (P4-12 superseded), heat pumps were settled at the wireframe review, and the review of
2026-11-22 added the stub P4-08b and register row M16.

## Next step

1. Re-bind before any go on P4-05 to P4-08: CONTRACTS, ACCEPTANCE and those stage documents are
   re-planned against the wireframe decisions D4-13 to D4-20 ("Owed after the wireframe review",
   below), and the four items still open in
   [DECISIONS, Part 3](DECISIONS.md#part-3-wireframe-review-2026-11-15) are put to Ed. D4-21 to
   D4-27 are answered and already bound.
2. Ed creates the phase issue and says go on P4-01. Nothing blocks it: Phase 3b closed on
   2026-10-26. P4-02 first needs one row of the wireframe re-plan, the Ventilator's Manufacturer
   and Model fields (D4-20), bound in CONTRACTS section 2; P4-03 and P4-04 wait on nothing else.

## Entry gates

| Gate | State |
| --- | --- |
| The equipment shared shape, Ventilators and hot water interviewed | Done 2026-10-21 |
| Ed answers D4-01 to D4-12 | Done 2026-10-21, all as recommended |
| A Phase 4 issue exists on `ph-composer/ph-composer-skp`, and every header's `ISSUE` line points at it | Open. Create on Ed's say |
| Ed authorizes implementation, stage by stage or for a run of stages | Open |
| Ed answers D4-21 to D4-27 | Done 2026-11-22, all as recommended |
| P3b-01 merged before P4-01 (both edit the `PLANNING_IDS` line) | Met: Phase 3b closed 2026-10-26, P3b-01 to P3b-09 merged |
| The other shared files (`extension.rb`, `index.html`, `composition.py`, `assembly.py`, `api.rb`, the agent guide) are never open on two branches at once | No other phase is in progress on 2026-11-22; the rule now holds between this phase's own parallel stages (PLAN, "Order and parallel work") |
| Families 3 to 6 interviewed before P4-08 to P4-11 (family 7, appliances, is Programs') | Heat pumps settled at the wireframe review, 2026-11-15 (D4-14 to D4-16). Pumps, Fans and Electric Heating: table shape and columns only (D4-13, D4-20), interviews otherwise open |
| Climate supplies a location or design temperatures and monthly values, before P4-08 (D4-15) | Met 2026-11-18 by the Climate phase: `ph_composer.climate.climate.get` gives the twelve monthly mean air temperatures and `ph_composer.climate.design_temperatures.get` the two design temperatures with their state, read back on the host in Climate's integrated run ([CM12 evidence](../../archive/phase-04-climate/evidence/cm12-20261118.md), [contract](../../archive/phase-04-climate/CONTRACTS.md#9-what-other-features-read)). This authorizes nothing here |
| Phase 3b P3b-03, P3b-04, P3b-06, P3b-07 and P3b-08 merged, then the piping and ducting interviews, before P4-13 and P4-14 | The Phase 3b stages are met (2026-10-26). The two interviews are open |
| Summer ventilation interviewed before P4-08b | Open. D4-26 was answered on 2026-11-22 |

## Stage ledger

"Offline" is `make ci` on both Rubies at the stage's gate. "Host" is the stage's host gate in a
fresh process. "Review" is the one review the ladder assigns. A stage is `Implemented on branch`
only when all three are done and its evidence file exists.

| Stage | Title | State | Blocked by | Branch / PR | Offline | Host | Review | Evidence | Register |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [P4-01](phases/p4-01-equipment-contracts-and-seams.md) | Equipment contracts, lint and the Pyodide seam | Scoped | Ed's go | | | | architecture review | | M01 |
| [P4-02](phases/p4-02-equipment-feature-and-ventilator-kind.md) | The equipment feature and the Ventilator kind | Scoped | P4-01; the Ventilator's D4-20 fields bound | | | | ordinary | | M02 |
| [P4-03](phases/p4-03-serves-assignment.md) | Serves: the assignment payload on the Zone | Scoped | P4-02 | | | | strong | | M03 |
| [P4-04](phases/p4-04-ventilator-export.md) | Ventilator export | Scoped | P4-03 | | | | strong | | M04 |
| [P4-05](phases/p4-05-systems-tab-and-ventilators-view.md) | The Systems tab and the Ventilators view | Scoped | P4-04; the wireframe re-plan | | | | ordinary, UI | | M05 |
| [P4-06](phases/p4-06-hot-water-records-and-export.md) | Hot Water System records and export | Scoped | P4-03; the wireframe re-plan | | | | strong | | M06 |
| [P4-07](phases/p4-07-hot-water-view.md) | The Hot water view | Scoped | P4-05, P4-06 | | | | ordinary, UI | | M07 |
| [P4-08](phases/p4-08-heat-pumps.md) | Heat pumps | Requested | P4-07; the full document | | | | | | M08 |
| [P4-08b](phases/p4-08b-segment-mechanical-settings.md) | Building Segment mechanical settings | Requested | P4-02, P4-08; the summer ventilation interview | | | | | | M16 |
| [P4-09](phases/p4-09-electric-heaters.md) | Electric heaters | Requested | P4-07; the interview | | | | | | M09 |
| [P4-10](phases/p4-10-pumps.md) | Pumps | Requested | P4-07; the interview | | | | | | M10 |
| [P4-11](phases/p4-11-fans.md) | Fans | Requested | P4-10; the interview | | | | | | M11 |
| [P4-12](phases/p4-12-appliances.md) | Appliances | Superseded by [Phase 4a](../../archive/phase-06-program/README.md) (Q4a-03) | n/a | | | | | | M12 |
| [P4-13](phases/p4-13-hot-water-piping.md) | Hot water piping | Requested | P4-06; the interview | | | | | | M13 |
| [P4-14](phases/p4-14-erv-ducting.md) | ERV ducting | Requested | P4-04, P4-13; the interview | | | | | | M14 |
| [P4-15](phases/p4-15-acceptance-and-handoff.md) | Acceptance and handoff | Scoped | all stages | | | | integration | | M15 |

## Milestones

| Milestone | After | Meaning |
| --- | --- | --- |
| MS1 | P4-04 | Ventilators complete as data and exported; the B4 HBJSON proof |
| MS2 | P4-07 | Families 1 and 2 on screen; the drawn packets have what they export into |
| MS3 | P4-14 | Everything a METr model needs before its first run is in HBJSON |

## Decisions

| ID | Kind | Subject | Blocks | State |
| --- | --- | --- | --- | --- |
| D4-01 | Code | One translated object per (item, served Zone) pair | P4-04, P4-06 | Answered 2026-10-21 |
| D4-02 | Code | One feature for seven families | P4-02 | Answered 2026-10-21; named `ph_composer.mechanical` by D4-22 |
| D4-03 | Code | The Serves record: one dictionary per Zone with a slot per family, `eqa_` id | P4-03 | Answered 2026-10-21; mechanism superseded by D4-21 |
| D4-04 | Code | A copied Zone keeps its Serves record, id re-issued | P4-03 | Answered 2026-10-21; mechanism superseded by D4-21 |
| D4-05 | Code | Delete in use per slot: refuse, replace or clear | P4-02, P4-03 | Answered 2026-10-21 |
| D4-06 | Code | Equipment sections required for export | P4-04, P4-06 | Answered 2026-10-21 |
| D4-07 | Code | Tank slotting by role | P4-06 | Answered 2026-10-21 |
| D4-08 | UI | The Systems tab: one subtabs row, a family selector in the page header | P4-05 | Answered 2026-10-21 |
| D4-09 | Code | Piping and ducting add to equipment's objects before attach | P4-04, P4-13, P4-14 | Answered 2026-10-21 |
| D4-10 | Code | Balance by ventilator as a pure Ruby read over Spaces' rows | P4-05 | Answered 2026-10-21 |
| D4-11 | Code | Unit rows: electric efficiency, litres, temperature | P4-05, P4-07 | Answered 2026-10-21 |
| D4-12 | Code | The calculation method field, written only when the wheel accepts it | P4-06 | Answered 2026-10-21 |
| D4-13 | UI | A Mechanical tab, subtabs by system, a pill row for tables; revises D4-08 | P4-05, P4-07, P4-13, P4-14 | Answered 2026-11-15 |
| D4-14 | Code, UI | Heat pumps as four tables with the estimator's inputs and pairing; revises Q4 for heat pumps | P4-08 | Answered 2026-11-15 |
| D4-15 | Code | Serves on the indoor unit; one blended air-source heat pump by the Phius estimator's method | P4-08 | Answered 2026-11-15 |
| D4-16 | UI | The blended result as a read-only view in the estimator's layout | P4-08 | Answered 2026-11-15 |
| D4-17 | Code, UI | Hot water as Systems, Heaters and Tanks; a System serves Zones; revises H1 and H7 | P4-06, P4-07 | Answered 2026-11-15 |
| D4-18 | Code | Recirculation temperature and hours read-only, from piping; revises H4 | P4-06, P4-13 | Answered 2026-11-15 |
| D4-19 | Code | A heater's Type picks its efficiency input | P4-06 | Answered 2026-11-15 |
| D4-20 | UI, Code | Tag, Manufacturer, Model, Notes and export fields on every table; no documentation fields in the MVP | P4-02, P4-05 to P4-11 | Answered 2026-11-15 |
| D4-21 | Code | Serves as a structured extension on the Zone record, as Programs' assignment is; revises the mechanism of D4-03 and D4-04 | P4-01, P4-03 | Answered 2026-11-22 |
| D4-22 | Code | The feature is `ph_composer.mechanical`; revises D4-02's name | P4-01, P4-02 | Answered 2026-11-22 |
| D4-23 | Code | The Building Segment as the scope of the blended heat pump and hot water pooling; an item may serve two Segments, with a finding | P4-06, P4-08 | Answered 2026-11-22 |
| D4-24 | UI, Code | The balance counts a By Program Zone's Program flow as supply and extract; the feature requires Programs | P4-05 | Answered 2026-11-22 |
| D4-25 | Scope | A PHX round trip in each of this phase's export stages | P4-04, P4-06, later export stages | Answered 2026-11-22 |
| D4-26 | Code, UI | Mechanical cooling entered on the Building Segment, off by default | P4-08b | Answered 2026-11-22 |
| D4-27 | UI | The Mechanical tab sits after Thermal Bridges, before Library | P4-05 | Answered 2026-11-22 |

## Owed from elsewhere, allocated here

| Item | Source | Stage | State |
| --- | --- | --- | --- |
| Units Q3: power, energy, capacity, litres, ventilator efficiency displays | [units packet](../cross-phase/units/STATUS.md) | P4-05, P4-07, later families | Scoped (D4-11). `temperature` and `power` exist in both registries since Climate and Programs; electric efficiency and litres are still to add (F31) |
| The edge tagging rules in `context/`, the registry question (D3b-01) and moving the run builder to `core/` | Phase 3b P3b-09 handoff | P4-13 | Phase 3b closed 2026-10-26: the edge rules are in `context/TECH_STACK.md`, "Edge-owned assignments". The registry question and the run builder's move are still P4-13's |
| The balance by ventilator and the Ventilation and Heat pump assignment surfaces | Spaces STATUS, "Deferred out of this plan" | P4-05 (balance, Q11); Zone views not built (Q10) | Scoped |
| Mechanical cooling and the mechanical room temperature (C4a-5): a Building Segment settings section and export contributor setting `set_points.mechanical_cooling` and `mech_room_temp` only, beside the set points Programs writes | [Phase 6 handoff](../../archive/phase-06-program/STATUS.md#handoff-to-phase-7-mechanical) | [P4-08b](phases/p4-08b-segment-mechanical-settings.md), with summer ventilation, which the handoff also names (F30) | Allocated 2026-11-22; mechanical cooling is entered (D4-26); the summer ventilation interview is open |
| The ventilation unit per Space: Phase 6 ships the per-Zone airflow mode and per-Space rates; honeybee-ph carries the unit on the Room. The balance reads each served Zone row's `airflow_mode` (CONTRACTS section 4; the row's `inheriting_count` is gone) and counts a By Program Zone's Program flow as its supply and extract (D4-24) | [Phase 6 handoff](../../archive/phase-06-program/STATUS.md#handoff-to-phase-7-mechanical) | P4-03, P4-05 | Closed 2026-11-22 as a question (F25): Serves on the Zone is the whole of it. The read is renamed in CONTRACTS section 4, P4-05 and M05 (F24), and a By Program Zone shows its Program's flow (D4-24) |

## Deferred out of this plan

| Item | Where it waits |
| --- | --- |
| Every METr file and import row: duct `lassVU`, the pipe diameter enum, and what METr shows for a shared item. What PHX builds from the HBJSON (one device or three for a shared item, the Spaces walk for exhaust and supportive devices) is proved here by round trip since D4-25 | [metr-export](../unscheduled/metr-export/README.md) |
| The simplified hot water methods' export | [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135), then a wheel bump |
| Boilers, wood boilers, district heat, PV (Q7) | Later scope; PV with roadmap 5.5 |
| Equipment library kinds (Q8) | Roadmap 5.4 |
| Ventilation and Heat pump views of the Zones tab (Q10) | After MS2, if wanted; the Zone views contract admits them |
| Occupancy, lighting and the other Room loads (Q12) | [Phase 6 Programs](../../archive/phase-06-program/README.md): complete 2026-11-22 and archived; PG01 to PG12 pass on the host |

## Owed after the wireframe review

Nothing below is done. Each row is re-planned before its stage is authorized.

| Document | Owes | Decisions |
| --- | --- | --- |
| [CONTRACTS](CONTRACTS.md) section 2 | Ventilator gains manufacturer and model. Hot Water System loses its nested tanks and heaters and its recirculation fields; Heater and Tank become kinds that reference a System. Four heat pump kinds. The Serves slots follow: a heat pump slot names indoor units | D4-14, D4-15, D4-17, D4-18, D4-20 |
| CONTRACTS sections 3, 5 and 6 | Operations and snapshot sections per table (A2 already names the Mechanical tab and its place, bound 2026-11-22); findings for an unpaired or unserved unit, a tank with no slot and pooled Systems; the blended heat pump section and its climate requirement | D4-13 to D4-18 |
| [ACCEPTANCE](ACCEPTANCE.md) M05 to M08 and the reference model | Gestures and expected HBJSON for the new tables and the blended heat pump | D4-13 to D4-19 |
| [P4-05](phases/p4-05-systems-tab-and-ventilators-view.md) | The Mechanical tab, system subtabs and the pill row in place of the Equipment subtab and family select | D4-13, D4-20 |
| [P4-06](phases/p4-06-hot-water-records-and-export.md), [P4-07](phases/p4-07-hot-water-view.md) | Three kinds and three tables in place of one kind with child rows; recirculation read-only | D4-17 to D4-19 |
| [P4-08](phases/p4-08-heat-pumps.md) | Written in full: four kinds, the blend, the result view, the Climate gate | D4-14 to D4-16 |
| P4-09 to P4-11 | Each a flat table in its own subtab; interviews still owed | D4-13, D4-20 |
| The piping and ducting PRDs | Where each lives: a pill under Hot Water and under Ventilation | D4-13 |
| [UI baseline](../../ui-baseline/README.md), `context/UBIQUITOUS_LANGUAGE.md` | Noted on 2026-11-15; the shared pill row is a new kit part for the UI polish review | D4-13 |

## Bound after the Programs review

Ed answered D4-21 to D4-27 on 2026-11-22 and each was bound in the same change. Nothing in this
table is implemented.

| Decision | Bound in | Still owed |
| --- | --- | --- |
| D4-21 | [CONTRACTS](CONTRACTS.md) sections 1 to 4 and 7; [P4-01](phases/p4-01-equipment-contracts-and-seams.md) step 1; [P4-03](phases/p4-03-serves-assignment.md); M01 and M03 | P4-01's test of a `many` reference in a payload |
| D4-22 | The feature id, code noun, kind, operation and section ids, and source paths in CONTRACTS, [ACCEPTANCE](ACCEPTANCE.md), [PLAN](PLAN.md) and the stage documents | `context/UBIQUITOUS_LANGUAGE.md` at P4-15. The `equipment/` packet, the stage file names and the interview records keep "equipment", the glossary word for the records together |
| D4-23 | CONTRACTS section 6 (`mechanical.item_across_segments`); [P4-06](phases/p4-06-hot-water-records-and-export.md); [P4-08](phases/p4-08-heat-pumps.md) | The pooling note and the blend are written with their stages' wireframe re-plan |
| D4-24 | CONTRACTS sections 1 and 4; [P4-05](phases/p4-05-systems-tab-and-ventilators-view.md); M05 and the reference model | |
| D4-25 | PLAN; ACCEPTANCE M04, M06, M16 and the completion boundary; CONTRACTS section 7; P4-01, P4-04, P4-06 and P4-08b | The round trips of the stages still stubs, written with their full documents |
| D4-26 | [P4-08b](phases/p4-08b-segment-mechanical-settings.md); M16 | The summer ventilation interview, then the full stage document |
| D4-27 | CONTRACTS A2; P4-05; the [UI baseline](../../ui-baseline/README.md) | |

## Verification

None. Nothing is implemented. DECISIONS Part 1 was read from source and not reproduced; P4-01
reproduces what the stages depend on. Part 4 says for each finding whether it was run against the
pinned wheels on 2026-11-22 or read.

## How to update this file

1. When a stage starts: state `In progress`, fill Branch.
2. At its gate: record the `make ci` result, the host gate result with the ledger case ids, and
   the review outcome in the three columns, and link the evidence file.
3. Then `Implemented on branch`; after merge `Merged to main` with the PR number.
4. Flip the matching [ACCEPTANCE](ACCEPTANCE.md) row in the same change.
5. Add a ledger row below for each of the above.
6. Mirror the summary line into [planning/STATUS.md](../../STATUS.md) and the Phase 4 table in
   [ROADMAP.md](../../ROADMAP.md).

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | The three PRDs drafted. |
| 2026-10-21 | PRDs re-baselined against `main` at `420c783a`. |
| 2026-10-21 | Equipment interviewed: the shared shape Q1 to Q12, Ventilators V1 to V6, hot water H1 to H7; honeybee_ph#135 filed for the calculation-method field. |
| 2026-10-21 | Planned in detail: fourteen findings, twelve decisions D4-01 to D4-12, bindings with additions A1 to A5, stages P4-01 to P4-15 (P4-08 to P4-14 as gate stubs), register M01 to M15 with a hand-calculated reference model. No decision answered, no stage authorized. |
| 2026-10-21 | Ed answered D4-01 to D4-12, all as recommended; P4-02 to P4-07 lose their decision blockers. Waiting on the phase issue and the go on P4-01. |
| 2026-11-15 | Wireframes reviewed with Ed ([mockups](mockups/README.md)): D4-13 to D4-20 answered and F15 to F19 recorded in DECISIONS Part 3. D4-08 and the answers Q4 (heat pumps), Q9, H1, H4 and H7 revised. Climate added as an entry gate for P4-08. Bindings, register and stages P4-05 to P4-11 owe re-planning; nothing authorized. |
| 2026-11-18 | Climate's entry gate for P4-08 met: Climate P4c-12's integrated run read `climate.get` and `design_temperatures.get` on the host with a complete, an incomplete and no climate, and set, incomplete and unset design temperatures, as Climate CONTRACTS section 9 says. Nothing authorized. |
| 2026-11-22 | Reviewed against `main` at `8c710412` after Phase 6 Programs was archived ([DECISIONS, Part 4](DECISIONS.md#part-4-review-after-programs-2026-11-22)): findings F21 to F39. Applied: the Phase 3b gates are met, the pins, composition order, Spaces read names, units, export hosts and the left-out Zone rule are corrected across the packet, M12 is superseded, and the Phase 6 handoff is allocated to a new stage P4-08b with register row M16. Opened, unanswered: D4-21 to D4-27. Nothing authorized. |
| 2026-11-22 | Ed answered D4-21 to D4-27, all as recommended. Bound the same day ("Bound after the Programs review"): Serves is a payload on the Zone record, the feature is `ph_composer.mechanical`, the Building Segment scopes the blend and the pooling, the balance reads Programs' flow for a By Program Zone, each export stage gains a PHX round trip, mechanical cooling is entered, and the tab sits after Thermal Bridges. P4-01 to P4-04 lose their decision blockers. Nothing authorized. |
