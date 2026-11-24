# P4-05: the Mechanical tab and the Ventilators view

DATE: 2026-10-21
STATUS: In review (2026-11-24), offline evidence in [p4-05-systems-tab](../evidence/p4-05-systems-tab.md); host owed to MS2. Scoped and re-bound 2026-11-23 to D4-13, D4-20, D4-24, D4-27, D4-30 and D4-31: the primary tab is Mechanical (after Thermal Bridges, before Library), with subtabs by system and a shared pill row beneath them; Ventilators carries Tag, export fields first and hideable identity columns (`Manufacturer`, `Model`, `Notes`); host gate runs in the MS2 sitting after P4-07.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-04, D4-10, D4-11, D4-13, D4-20, D4-24, D4-27, D4-30 and D4-31, with Q10, Q11, V3 and V4. Owns the panel: the Mechanical tab, the system subtabs (`Ventilation`, with sibling subtabs registered as each family lands), the shared pill row (`Ventilators`, with `Ducting` added in P4-14), the Ventilators table with Serves and balance, the two disclosed optional fields, the W/cfm quantity, and the `By ventilator` Colour-by mode. Every control calls an operation P4-02 to P4-04 registered; the panel computes nothing and reads the balance from Ruby (D4-10).

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Behaviors" and "Family 1", and [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15). Load `.agents/skills/ph-composer-ui-polish/SKILL.md` first. Check the [wireframes](../mockups/README.md) (`Main.dc.html`, `Narrow.dc.html`) and build undrawn details (row actions, New-record form, per-row disclosure, 360 × 520) directly from the shipped UI kit patterns (D4-30).

Paths are relative to `src/ph_composer/`.

## Steps

1. **The pane (A2).** Enable the reserved tab in `html/index.html`: the disabled "Systems" button becomes the Mechanical tab, `data-tab="mechanical"` with a `data-pane="mechanical"`, moved to sit after Thermal Bridges and before Library (D4-13, D4-27). Add the new modules and run `make panel-manifest`.
2. **System subtabs and shared pill row (D4-13).** `html/features/mechanical/section.js` registers the pane's section and `panel.workedOn("ph_composer.mechanical", "mechanical")`. System subtabs use the shared `subtabs.js` nav (`Ventilation`, and later `Heat Pumps`, `Hot Water`, `Pumps`, `Fans`, `Electric Heating` as each lands). Add a shared pill-row kit part (`html/pill_row.js` or equivalent under the UI polish review) beneath the subtabs to pick one table inside a system (`Ventilators` now; `Ducting` in P4-14). Remember active subtab and pill on this computer as a display preference, never written to the Model.
3. **Balance read (D4-10, D4-24).** `serves/balance.rb`, pure: per Ventilator, the served Zones' supply and extract sums from `ph_composer.spaces.all`'s Zone rows, `imbalanced` by the rule Spaces once held (more than a tenth of the larger), which left `Spaces::Metrics` in API 1.21 and now lives in `balance.rb`. A served Zone in Detailed airflows gives its Spaces' sums. A served Zone that is By Program (`airflow_mode`, F24) gives its Program's flow, `ventilation_m3h` on its `ph_composer.programs.zones` row, as both supply and extract (D4-24); the feature gains `requires: ["ph_composer.programs"]` here. The sums are null, and the row reads a dash, only while Programs cannot work that flow out. The Ventilators snapshot section takes that Programs read once per snapshot and shares it. Exposed on `ventilators.all` rows and the snapshot section.
4. **Ventilators table (D4-20, D4-30).** `ventilators.js` on `html/inventory.js`: `Tag` (`name`), export fields first (quantity, sensible, latent, electric efficiency, frost protection, defrost temperature, in conditioned space, balance columns, Serves chips with Zone picker grouped by Building Segment offering a whole Segment at once and replace on `mechanical.slot_filled`, F39, V1), then hideable identity columns (`Manufacturer`, `Model`, `Notes`, D4-20), and a collapsed per-row disclosure for the two optional fields (V3, D4-30). Add, duplicate, delete with `ReplacementForm` offering replacement or clear (D4-05), in-place and range edits through `record_edits` and `inventory_grid`, column sort and value filters, and a `tableId` so `table_contributions.js` can add the duct-length columns in P4-14 (ducting Q9).
5. **Units (A3, D4-11).** `electric_efficiency` in `core/units.rb` and `html/unit_tables.js` with vectors, Wh/m³ stored and W/cfm under IP; a draft keeps its unit through a switch.
6. **Colour-by.** `features/mechanical/colour_modes.rb`: `by_ventilator`, `entity_kind: "zone"`, each served Zone in its item's colour from the ramp, unserved Zones absent, legend rows counting Zones; label carries the item name.
7. **Preview and manifests.** Add the preview fixture in `tools/ui-preview/host.js` and `mechanical_checks.cjs` under `tools/ui-preview/` through `support/browser_evidence.cjs` (including 1280 × 800, 420 px and 360 × 520 checks); regenerate the panel manifest and vendor manifest.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `html/features/windows/section.js`, `inventory.js` | Pattern for a pane with subtabs and an inventory |
| `html/features/zones/assembly_assignment.js` | Pattern for a picker that assigns a definition to occurrences |
| `html/features/zones/zone_cells.js` | Pattern for in-place cells on Zone rows, for the chips |
| `features/zones/colour_modes.rb`, `features/spaces/colour_modes.rb` | Pattern for a Zone-keyed mode and a grouped mode |
| `core/units.rb`, `html/unit_tables.js`, `tests/support/units_vectors.json` | The quantity registry and vectors |

## Tests (write first)

1. The table sends `ventilators.update` with `values` and `expected_values` and keeps a refused
   draft.
2. The Zone picker sends `serves.assign` with the Zone references, the slot and the item, and
   offers replace on `mechanical.slot_filled`.
3. The balance read on the reference rows gives 60 / 50 imbalanced, 40 / 40 not, 100 / 90 not,
   Zone A set By Program gives ERV-1 Zone A's Program flow as both supply and extract, and the
   shared case that flow plus Zone B's 40 / 40; null with a dash when Programs gives no flow.
4. `electric_efficiency` vectors: 0.55 Wh/m³ to its W/cfm value and back within the shared
   tolerance; the Ruby and panel registries agree.
5. Switching subtabs and pills changes the table without a Model write; the choice is remembered.
6. `by_ventilator` entries: one per served Zone keyed by Zone id, none for an unserved Zone.
7. The panel layout test: nothing outside `html/features/` names this feature.

## Host gate

Batched into the `MS2` sitting after P4-07 (D4-31): every gesture in M05 on the reference model with Ed at the mouse, plus the Phase 3a Zone views cases the ledger screens for `index.html` and the kit files repeated. Record with `acceptance_case.py`.

## Out of scope

Hot water (P4-07). Zone views of equipment (Q10, deferred). A toolbar.

## Done when

- M05 has evidence in `../evidence/p4-05-systems-tab.md`, with the UI polish review recorded.
- `make ci` passes on both Rubies; the panel manifest and the vendor manifest are current.
