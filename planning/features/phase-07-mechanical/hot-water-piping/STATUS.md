# Hot water piping: status

DATE: 2026-10-21
STATUS: Merged to main, host cases owed to MS3: P4-13a merged (#576); P4-13b merged (#577); P4-13c merged (#578); P4-13d merged (#579); P4-13e merged (#580). P4-14c2 (#584, in review) moves piping's group and clear operations into `line_groups/` and closes four parity gaps with ducting. Interviewed 2026-11-23 (D4-36, Q1–Q13 all as recommended); planned in full 2026-11-24 as P4-13a to P4-13e.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## State

PRD drafted 2026-09-18 from Ed's brief (build pipe-types, draw pipes, select edge, assign
pipe-type), the predecessor's `planning/phases/M1_piping.md`, honeybee-ph's
`hot_water_piping.py` and `hot_water_system.py`, and PHX's METr writer. Interviewed 2026-11-23 (D4-36).

Re-baselined on 2026-10-21 against `main` at `420c783a`. The PRD's "What main and Phase 3b
supply" table replaces the port disposition. Changes of substance: the snapshot's Edge entries
exist (G-02); the chain rule, edge records, edge tool and stroke weight are Phase 3b stages, not
"adapted from the Classify tool"; records lose their timestamps and gain `color`; the by-connection
tree needs no parent reference and no edge registry; the section's attachment to equipment's Hot
Water System is an open plan item; acceptance is an HBJSON reload, METr rows go to metr-export;
Q13 added. honeybee-ph fields re-read at the pinned 1.33.65.

This packet's stage is [P4-13](../phases/p4-13-hot-water-piping.md) in the
[phase ledger](../STATUS.md), a gate stub until this interview runs; Phase 3b's edge stages merged on
2026-10-26.

## Next step

[P4-13a](../phases/p4-13a-pipe-types.md), the piping feature and Pipe Types, is merged (#576), and
[P4-13b](../phases/p4-13b-piping-groups-and-assignment.md), Piping groups and the pipe assignment, is merged (#577), and
[P4-13c](../phases/p4-13c-tree-and-schedule.md), the chain rule in `core/`, the tree and the schedule, is merged (#578), and
[P4-13d](../phases/p4-13d-piping-export.md), the piping export, is merged (#579), and
[P4-13e](../phases/p4-13e-piping-view.md), the Piping pills, Colour-by and the pipe tool, is merged (#580)
([the parent index](../phases/p4-13-hot-water-piping.md)). Stages and their state live in the
[phase ledger](../STATUS.md).

## Blockers

- None from Phase 3b: the edge store, chain rule, edge tool and edge contributor are on `main`
  (P3b-03 to P3b-08); the rules are in `context/TECH_STACK.md`, "Edge-owned assignments".
- The Hot Water System record, which the equipment packet owns; its family was interviewed on
  2026-10-21 (H1 to H7) and revised on 2026-11-15: tap points sit on the system record and
  recirculation temperature and hours are read from this packet's recirculation pipes (D4-18), and the simplified methods
  wait on a honeybee-ph field (H5, [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135)).
- None from the edge identity spike: it passed on 2026-09-18 ([B4](../../../archive/phase-00-foundation/evidence/spike-edge.md));
  its open cases closed in P3b-01 (T01).

## Owed from Phase 3b

| Item | Source | Disposition here |
| --- | --- | --- |
| A Model-level edge registry for identity-bearing assignments (B4's registry question) | D3b-01, handed over by Phase 3b P3b-09 | Answered: none. Q1 chose the tree by connection (D4-36), so no assignment carries a parent; recorded in [P4-13b](../phases/p4-13b-piping-groups-and-assignment.md) |
| Moving the run builder to `core/` | 3b STATUS, "Deferred out of this plan" | Done in [P4-13c](../phases/p4-13c-tree-and-schedule.md) (merged, #578): the chain rule is `core/edge_runs.rb` with 3b's chain-rule tests in `tests/edge_runs_test.rb`, the thermal-bridge goldens unchanged |

## Verification

P4-13a offline: [p4-13a-pipe-types](../evidence/p4-13a-pipe-types.md). P4-13b offline:
[p4-13b-piping-groups-and-assignment](../evidence/p4-13b-piping-groups-and-assignment.md). P4-13c offline:
[p4-13c-tree-and-schedule](../evidence/p4-13c-tree-and-schedule.md). P4-13d offline:
[p4-13d-piping-export](../evidence/p4-13d-piping-export.md). P4-13e offline:
[p4-13e-piping-view](../evidence/p4-13e-piping-view.md). No host evidence yet; the host cases run in MS3.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted. |
| 2026-10-21 | Phase 4 planned in detail; this packet's stage is a gate stub in the phase ledger. |
| 2026-10-21 | Re-baselined against `main` at `420c783a`: foundation and remote blockers removed, Phase 3b dependencies named stage by stage, records and export mapping corrected, Q13 added. No interview, no implementation. |
| 2026-10-26 | Phase 3b P3b-09 handoff: the edge tagging rules point at `context/TECH_STACK.md`, the edge stages are on `main`, and the edge registry question (D3b-01) is this packet's. |
| 2026-11-22 | Phase reviewed after Phase 6 Programs: the stale Phase 3b gate wording removed here and in the PRD; recirculation temperature and hours noted as read from this packet's pipes (D4-18). No interview, no implementation. |
| 2026-11-23 | Interviewed: Q1 to Q13 all as recommended (D4-36). |
| 2026-11-24 | Planned in full as P4-13a to P4-13e in the phase packet; the registry question answered "none" and the run builder's move allocated to P4-13c. No implementation. |
| 2026-11-24 | P4-13a implemented on `feat/phase-07-mechanical-p4-13a` and in review (#576): the `ph_composer.piping` feature and the Pipe Type kind, panel closed; host case `M13a` owed to MS3. |
| 2026-11-24 | P4-13b implemented on `feat/phase-07-mechanical-p4-13b` and in review: Piping groups and the pipe assignment, panel closed; the Hot Water System delete routes other features' referrers through the engine's retargeters; host case `M13b` owed to MS3. |
| 2026-11-24 | P4-13b merged (#577). P4-13c implemented on `feat/phase-07-mechanical-p4-13c` and in review: the chain rule moved to `core/edge_runs.rb`, the tree by connection, the recirculation sum, findings and the schedule; host case `M13c` owed to MS3. |
| 2026-11-24 | P4-13c merged (#578). P4-13d implemented on `feat/phase-07-mechanical-p4-13d` and in review: the piping export into each Hot Water System's hot water systems, conformance and a PHX round trip; host case `M13d` owed to MS3. |
| 2026-11-24 | P4-13d merged (#579). P4-13e implemented on `feat/phase-07-mechanical-p4-13e` and in review: the Pipe Types and Piping pills, the assign bar and pipe tool, the schedule, the Systems table's recirculation columns, the two Colour-by modes; host case `M13e` owed to MS3. |
| 2026-11-25 | P4-13e merged (#580). Every sub-stage is on `main`; host cases `M13a` to `M13e` owed to MS3. |
