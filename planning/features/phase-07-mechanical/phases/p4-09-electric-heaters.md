# P4-09: electric heaters

DATE: 2026-10-21
STATUS: Requested. A gate stub: table shape and columns settled 2026-11-15 (D4-13, D4-20) and interview completed 2026-11-23 (D4-33); ready to be written in full. See [DECISIONS, Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry gates

P4-07 merged; the electric heaters interview (family 4), the smallest: a name and `percent_coverage`.

## Owns

Family 4: a Direct Electric Heater kind, the `heater_ids` Serves slot, a section through `add_heating_system` with `PhHeatingDirectElectric`, the family view.

## Reuses

Everything from P4-08; no new quantity.

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
