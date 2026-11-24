# P4-11: fans

DATE: 2026-10-21
STATUS: Requested. A gate stub: table shape and columns settled 2026-11-15 (D4-13, D4-20) and interview completed 2026-11-23 (D4-35); ready to be written in full. See [DECISIONS, Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry gates

P4-10 merged, because a Fan's electric block exports as a supportive device; the fans interview (family 6), following Q6: an exhaust ventilator record with an optional electric block.

## Owns

Family 6: a Fan kind with the exhaust kind (kitchen hood, dryer, user-defined), `exhaust_flow_rate_m3h`, `annual_runtime_minutes`, `quantity` and the optional electric block (W, khrs, in conditioned space); the `fan_ids` slot; a section adding an exhaust ventilator through `add_exhaust_vent_device` and, when the block is filled, a linked `PhSupportiveDevice` type 10 through `add_supportive_device`; the family view. M11 must show one record becoming two honeybee-ph objects.

## Reuses

P4-10's supportive device translation; the `airflow` quantity (m³/h stored, cfm in IP).

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
