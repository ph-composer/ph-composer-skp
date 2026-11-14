# Phase 4a status

DATE: 2026-11-14
STATUS: Requested. Research complete and interviewed; UI prototype next.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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
| UI prototype: Program tab, Zones/Programs page | Requested | | |
| PRD, contracts, stages | Requested | | |
| GitHub issue | Requested | | Q4a-18 |
| honeybee-ph and PHX fix for F4a-13 | Requested | | Q4a-08; cross-repo, own authorization |

## Blockers and dependencies

- Writing honeybee-ph operating periods waits on the honeybee-ph and PHX fix for F4a-13
  (Q4a-08). The PH schedule form writes rulesets only until then; nothing else is blocked.
- Phase 4 P4-12 (appliances) is superseded: this packet owns appliances as Equipment Sets
  (Q4a-03). Nothing in Phase 4 mechanical blocks this packet.
- Before implementation: choose the honeybee-ph pin for `PhEquipment` (F4a-18).

## Verification

Research claims were checked against the pinned wheels (honeybee-energy 1.123.23, honeybee-ph
1.33.65) and, for PHX, against the local checkout at 1.59.1. Example HBJSON dicts were produced by
running honeybee-energy. Spot-checked by hand: the Phius base programs (F4a-14), PHX's unguarded schedule `ph` reads
(F4a-15) and the ExhaustAir pin difference (F4a-16). The PHX double count (F4a-13) was confirmed
by running a Phius meeting-room People and Lighting load through PHX's schedule builders.
