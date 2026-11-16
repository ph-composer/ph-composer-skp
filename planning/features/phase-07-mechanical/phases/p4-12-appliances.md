# P4-12: appliances

DATE: 2026-10-21
STATUS: Superseded 2026-11-14 by [Phase 4a](../../phase-06-program/DECISIONS.md#answered) (Q4a-03): appliances become Zone Equipment Sets there. Kept as the record of the original scope.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry gates

P4-07 merged; the appliances interview (family 7), following Q12: per-item records and the Phius default set as Process loads, with where the per-Zone dwelling and bedroom counts the default set needs are stored.

## Owns

Family 7: appliance records over the `PhEquipment` classes, the Phius residential and multifamily default sets, the Serves relation for a Room load, and a section that writes honeybee-energy `Process` loads carrying `ProcessPhProperties` on each served Room (the route PHX reads into METr), not the deprecated `electric_equipment` route; the family view. The boundary with the Zone loads packet is Q12's.

## Reuses

P4-03's Serves pattern; P4-04's section shape with a different host property; the kWh quantity.

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
