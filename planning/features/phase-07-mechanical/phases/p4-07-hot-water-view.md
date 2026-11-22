# P4-07: the Hot water view

DATE: 2026-10-21
STATUS: Scoped. To be re-planned against D4-13 and D4-17 (2026-11-15): three flat tables under the Hot Water subtab, not system rows with child rows. See [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15). Corrected 2026-11-22: `temperature` already exists in both unit registries (F31, [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4-05 and P4-06, D4-11, and hot water H7. Owns the Hot water family view in the
Equipment subtab: system rows, tank and heater child rows, the system values, the Serves column,
litres and temperature under IP, and the `By hot water system` mode. After this stage families 1
and 2 are on screen: milestone MS2.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Family 2" and hot water H7. Load the
UI polish skill first. Pattern: the Zones tab's tree table (Zone views, Spaces' child rows) for
rows beneath a row; P4-05's Ventilators table for the rest.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The view.** `html/features/mechanical/hot_water.js`: system rows with name, tap points,
   recirculation temperature and hours, the calculation method (D4-12, with its finding shown
   while the wheel lacks the field), the Serves chips and the balance-free columns; tank and
   heater rows beneath each system opened by its chevron, each editable in place; Add tank and
   Add heater on the system row; a tank's role and type as enum cells and its expected slot read
   from the row; a heater's variant choosing which cells are live.
2. **Units (A3, D4-11).** `volume_l` in both registries with vectors. `temperature` exists (F31).
3. **Colour-by.** `by_hot_water_system`, `entity_kind: "zone"`, as `by_ventilator`.
4. **Preview and checks.** Extend the preview fixture and `mechanical_checks.cjs`; regenerate the
   manifests.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `html/features/spaces/view.js`, `cells.js` | Pattern for child rows and nested in-place cells |
| `html/features/mechanical/ventilators.js` (P4-05) | The sibling view |

## Tests (write first)

1. Editing a tank cell sends `hot_water_systems.update` with the whole `tanks` array and
   `expected_values`; a refused draft is kept.
2. Add tank appends a child with defaults; Add heater with the chosen variant exposes only its
   fields.
3. Litres vectors; a litres and a temperature draft each keep their unit through a switch.
4. `by_hot_water_system` entries per served Zone.

## Host gate

Fresh process: every gesture in M07 with Ed at the mouse. Record with `acceptance_case.py`.

## Out of scope

Piping (P4-13). Heat pumps and the other families.

## Done when

- M07 has evidence in `../evidence/p4-07-hot-water-view.md`, with the UI polish review recorded.
- `make ci` passes on both Rubies; the manifests are current.
