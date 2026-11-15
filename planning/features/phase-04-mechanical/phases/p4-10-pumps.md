# P4-10: pumps

DATE: 2026-10-21
STATUS: Requested. A gate stub: written in full after its interview. Table shape and columns settled 2026-11-15 (D4-13, D4-20); the interview is otherwise open. See [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry gates

P4-07 merged; the pumps interview (family 5): which supportive device types are offered (4, 6, 7, 10) and the IHG profile choices.

## Owns

Family 5: a Pump kind over `PhSupportiveDevice` (device type, quantity, watts, khrs, IHG factor and profile), the `pump_ids` slot, a section through `add_supportive_device`, the family view. Note from the trace: PHX merges duplicate supportive devices by key across Rooms and reads them through a Room's Spaces (metr-export's row).

## Reuses

P4-08's shape; the W quantity.

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
