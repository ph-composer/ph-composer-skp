# P4-08: heat pumps

DATE: 2026-10-21
STATUS: Requested. A gate stub: written in full after its interview. Interview settled at the wireframe review of 2026-11-15 (D4-14 to D4-16); the full document is owed and the stage also waits on Climate. See [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry gates

P4-07 merged; the heat pumps interview (family 3), which decides whether the editor shows all four cooling sub-blocks or Recirculation only, and the variant set (annual, rated monthly, combined).

## Owns

Family 3 as data, section and view: a Heat Pump kind with `percent_coverage`, a variant and its cooling parameters; the `heat_pump_ids` Serves slot (cardinality many); a section adding each pump to its served Rooms through `add_heat_pump_system` (D4-01); the family view.

## Reuses

P4-02's kind shape, P4-03's Serves slot line, P4-04's section shape, P4-05's view and the W, kW and kBtu/h quantities (units Q3, D4-11).

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
