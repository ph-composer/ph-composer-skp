# P4a-08: Dwellings, Zone assignments and Single dwelling

DATE: 2026-11-15
STATUS: Outline. Rewritten after the Programs tab review (gate G1). Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-07. Adds Dwellings, the per-Zone assignment extension, the Ruby derivations, Single dwelling and the Occupancy section. Behavior: [Phase 4a PRD](../PRD.md), "Single dwelling" and "Dwellings"; names: [CONTRACTS](../CONTRACTS.md) sections 2, 5 and 6.

## Outline

1. `programs.dwelling` (`dwl_`) and its operations; a Dwelling with no Zones is deleted with the last Zone that leaves.
2. The `ph_composer.programs` extension on Zone records: Program, Dwelling, counts, Equipment Set; assignment operations with one Undo step each.
3. Derivations in Ruby: effective Program, Dwelling, bedrooms and occupants with the Phius rule, Zone people, Zone ventilation from either source.
4. Single dwelling on the Segment extension: the derived lock, switching on with its confirmation, switching off keeping what it set, Zones moving in and out; the Occupancy section.
5. C4a-2 and C4a-3.

## Settle at G1

Q4a-21 (Equipment Set on the Dwelling or the Zone), Q4a-24 (counts per Zone or per Dwelling); C4a-7 (Single dwelling's default) if Ed has not answered it with this plan.

## Host gate

PG08: Single dwelling on and off, Undo/Redo, copying a Zone, a Dwelling across Segments refused.
