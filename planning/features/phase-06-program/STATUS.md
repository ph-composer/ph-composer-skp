# Phase 4a status

DATE: 2026-11-15
STATUS: Scoped (2026-11-15). P4a-01 to P4a-11 ready to authorize. No stage authorized.
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
| UI prototype: Program tab, Zones/Programs page | Complete | 2026-11-15 | [mockups/](mockups/README.md): five journeys, Q4a-19 to Q4a-28 raised. First review 2026-11-14: shape accepted; Q4a-19, Q4a-20 and Q4a-26 (Single dwelling switch) answered and prototyped; Q4a-27 (switch on by default) and Q4a-28 (Phius values may be published) answered 2026-11-15 |
| Research: Zone ventilation and Space airflows | Complete | 2026-11-15 | [ventilation](research/ventilation.md): F4a-24 to F4a-29; Q4a-29 to Q4a-32 raised |
| UI prototype: Building Segments, Single dwelling per Segment, Zones / Spaces airflows | Complete | 2026-11-15 | [mockups/](mockups/README.md); BS-1 to BS-6 and Q4a-27 to Q4a-32 answered |
| PRD, contracts, plan and stages for the Zones tab | Scoped | 2026-11-15 | [PRD](PRD.md), [Building Segments PRD](building-segments/PRD.md), [CONTRACTS](CONTRACTS.md), [PLAN](PLAN.md), [ACCEPTANCE](ACCEPTANCE.md), [phases/](phases); C4a-5 and C4a-7 to C4a-10 answered; C4a-2, C4a-3, C4a-4, C4a-6 settle in their stages; consistency sweep folded in |
| P4a-01 to P4a-11 | Scoped | 2026-11-15 | Ready to authorize; P4a-12 is the closing outline |
| Programs tab review (G1) | Complete | 2026-11-15 | Q4a-21 to Q4a-25 and Q4a-33 to Q4a-36 answered; C4a-5 and C4a-7 to C4a-10 answered |
| GitHub issue | Requested | | Q4a-18 |
| honeybee-ph and PHX fix for F4a-13 | Requested | | Q4a-08; cross-repo, own authorization |

## Blockers and dependencies

- Occupancy and lighting operating periods wait on the honeybee-ph and PHX fix for F4a-13
  (Q4a-08); until then those Schedules export as rulesets only. Ventilation Schedules write their
  periods now (C4a-10). Nothing else is blocked.
- Phase 4 P4-12 (appliances) is superseded: this packet owns appliances as Equipment Sets
  (Q4a-03). Nothing in Phase 4 mechanical blocks this packet.
- P4a-07 chooses the honeybee-ph pin for `PhEquipment` first (F4a-18).
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
