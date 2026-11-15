# P4-09: electric heaters

DATE: 2026-10-21
STATUS: Requested. A gate stub: written in full after its interview. Table shape and columns settled 2026-11-15 (D4-13, D4-20); the interview is otherwise open. See [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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
