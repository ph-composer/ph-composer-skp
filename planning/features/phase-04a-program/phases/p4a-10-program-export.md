# P4a-10: Program export

DATE: 2026-11-15
STATUS: Outline. Rewritten after the Programs tab review (gate G1). Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-08. Writes everything Programs owns into the HBJSON and adds the read-only Comfort section. Names: [CONTRACTS](../CONTRACTS.md) section 7; research: [PH stack](../research/ph-stack-consumption.md).

## Outline

1. Each Room's effective Program as a honeybee `ProgramType` with its loads and Schedules.
2. The honeybee-ph People extension per Dwelling (F4a-19); Equipment Set devices as `PhEquipment` Process loads (F4a-17).
3. Segment set points from the Zones' Programs, with the disagreement finding (Q4a-04); the Comfort section shows them.
4. The Program's Infiltration where the Segment has no test result (P4a-06).
5. A PHX round trip of the five prototype journeys reading back occupancy, lighting, equipment, ventilation and set points.

## Settle at G1

Which loads PHX ignores that still export for EnergyPlus fidelity (Q4a-02, Q4a-05); the F4a-13 fix's timing.

## Host gate

PG10: the round trip above on the packaged RBZ.
