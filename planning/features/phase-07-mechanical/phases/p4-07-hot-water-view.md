# P4-07: the Hot Water subtab (Systems, Heaters, Tanks)

DATE: 2026-10-21
STATUS: Scoped. Re-bound 2026-11-23 to D4-13, D4-17 to D4-20, D4-30 and D4-31: three flat pill tables (`Systems`, `Heaters`, `Tanks`) under the `Hot Water` subtab; read-only recirculation from piping; closes milestone MS2 with the MS2 host sitting.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-05 and P4-06, D4-11, D4-13, D4-17 to D4-20, D4-30 and D4-31. Owns the `Hot Water` system subtab on the Mechanical tab with its three flat pill tables (`Systems`, `Heaters`, `Tanks`; `Piping` pill added in P4-13), litres (`volume_l`) under IP, and the `By hot water system` Colour-by mode. After this stage families 1 and 2 are on screen: milestone `MS2`.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Family 2", and [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15). Load `.agents/skills/ph-composer-ui-polish/SKILL.md` first. Reference [wireframes](../mockups/README.md) (`HotWaterSystems.dc.html`, `HotWater.dc.html`, `HotWaterTanks.dc.html`).

Paths are relative to `src/ph_composer/`.

## Steps

1. **The Hot Water subtab and three pill tables (D4-13, D4-17 to D4-20).** `html/features/mechanical/hot_water.js`:
   - `Systems` pill: `Tag`, `Serves` (Zone chips + picker), `Tap points`, read-only `Recirculation` (temperature and hours read from piping, dash/defaults when none, D4-18), `Calculation method` (D4-12 with finding badge while wheel lacks the field), non-blocking pooling notice when > 1 served System shares a Building Segment (D4-17, D4-23), hideable `Manufacturer`, `Model`, `Notes`.
   - `Heaters` pill: `Tag`, `System` (picker over `hot_water_system`), `Type` (variant), `Coverage (%)`, `In conditioned space`, and only the active variant's efficiency cell(s) live (D4-19), hideable `Manufacturer`, `Model`, `Notes`.
   - `Tanks` pill: `Tag`, `System` (picker), `Role` (`storage`, `buffer`, `solar`), `Export slot` (read-only from `slotting.rb`, D4-07), `Type`, `Qty`, `Capacity` (`volume_l`), `Standby loss` (`W/K`), `In conditioned space`, plus remaining tank fields and hideable `Manufacturer`, `Model`, `Notes`.
2. **Units (A3, D4-11).** `volume_l` in `core/units.rb` and `html/unit_tables.js` with vectors (litres stored, US gallons in IP). `temperature` already exists in both registries (F31).
3. **Colour-by.** `by_hot_water_system`, `entity_kind: "zone"`, matching `by_ventilator`.
4. **Preview and checks.** Extend the preview fixture in `tools/ui-preview/host.js` and `mechanical_checks.cjs`; regenerate the panel and vendor manifests.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `html/features/mechanical/ventilators.js`, `section.js` (P4-05) | The sibling flat-table view and pill-row subtab pattern |
| `core/units.rb`, `html/unit_tables.js`, `tests/support/units_vectors.json` | The quantity registry and vectors |

## Tests (write first)

1. Editing a System, Heater or Tank cell sends its respective `.update` action with `expected_values`; a refused draft is kept.
2. Changing a Heater's `variant` enables only its efficiency field(s) and clears/omits the others (D4-19).
3. Litres (`volume_l`) vectors round-trip between L and US gal; a litres draft keeps its unit through a unit switch.
4. `by_hot_water_system` entries per served Zone.

## Host gate (`MS2` sitting, D4-31)

Fresh process: run the `MS2` sitting covering M05, M06 and M07 with Ed at the mouse (Mechanical tab, Ventilators + balance, Hot Water Systems/Heaters/Tanks, `By ventilator` and `By hot water system`, export and HBJSON reload). Record with `acceptance_case.py`.

## Out of scope

Piping (P4-13). Heat pumps and the other families.

## Done when

- M07 has evidence in `../evidence/p4-07-hot-water-view.md`, with the UI polish review recorded.
- `make ci` passes on both Rubies; the manifests are current.
