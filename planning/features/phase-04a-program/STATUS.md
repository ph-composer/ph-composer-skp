# Phase 4a status

DATE: 2026-11-14
STATUS: Requested. Research complete; interview next.
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
| Interview | Requested | | Q4a-01 to Q4a-18 |
| UI prototype: Program tab, Zones/Programs page | Requested | | |
| PRD, contracts, stages | Requested | | |
| GitHub issue | Requested | | Q4a-18 |

## Blockers and dependencies

- Q4a-08, the PHX operating-period discrepancy (F4a-13), blocks a schedule editor that emits
  operating periods. It does not block a rulesets-only editor.
- None on Phase 4 mechanical. Phase 4 stage P4-12 (appliances) reads this packet's answer to
  Q4a-11 for per-Zone dwelling and bedroom counts.

## Verification

Research claims were checked against the pinned wheels (honeybee-energy 1.123.23, honeybee-ph
1.33.65) and, for PHX, against the local checkout at 1.59.1. Example HBJSON dicts were produced by
running honeybee-energy. Spot-checked by hand: the PHX double count (F4a-13), the Phius base
programs (F4a-14), PHX's unguarded schedule `ph` reads (F4a-15) and the ExhaustAir pin difference
(F4a-16).
