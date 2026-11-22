# P4-08: heat pumps

DATE: 2026-10-21
STATUS: Requested. A gate stub: written in full after its interview. Interview settled at the wireframe review of 2026-11-15 (D4-14 to D4-16); the full document is owed and the stage also waits on Climate. See [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15). Climate's gate was met on 2026-11-18. Noted 2026-11-22 after Phase 6 Programs: the blend is per Building Segment (D4-23, answered the same day) and pure Ruby. See [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry gates

P4-07 merged; the heat pumps interview (family 3), which decides whether the editor shows all four cooling sub-blocks or Recirculation only, and the variant set (annual, rated monthly, combined).

## Owns

Family 3 as data, section and view: a Heat Pump kind with `percent_coverage`, a variant and its cooling parameters; the `heat_pump_ids` Serves slot (cardinality many); a section adding each pump to its served Rooms through `add_heat_pump_system` (D4-01); the family view.

## Noted 2026-11-22

The text above predates the wireframe review and is replaced when the full document is written.
Three things the full document takes from the review after Programs:

- **The Building Segment (D4-23).** PHX writes one Variant per Building Segment, so "one
  blended heat pump for the building" (D4-15) means one blend per exported Segment, over the
  outdoor equipment whose indoor units serve that Segment's Zones. Outdoor equipment whose indoor
  units serve two Segments counts in both and is noted `mechanical.item_across_segments`.
- **A PHX round trip (D4-25)** in the `phx` group, for the blended heat pump and its cooling.
- **Where the blend is computed (F35).** In pure Ruby over plain records, read by the preflight
  for its findings and carried to the Python section as values, as Programs' export plan is.
- **Requires Climate.** The feature gains `requires: ["ph_composer.climate"]` here, for the
  monthly means and the two design temperatures.

Mechanical cooling on the Building Segment is [P4-08b](p4-08b-segment-mechanical-settings.md),
which follows this stage.

## Reuses

P4-02's kind shape, P4-03's Serves slot line, P4-04's section shape, P4-05's view and the W, kW and kBtu/h quantities (units Q3, D4-11).

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
