# P4-05: the Systems tab and the Ventilators view

DATE: 2026-10-21
STATUS: Scoped. To be re-planned against D4-13 and D4-20 (2026-11-15): the tab is Mechanical, with a subtab per system and a pill row, not an Equipment subtab with a family select. See [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15). Corrected 2026-11-22 after Phase 6 Programs: the By Program wording and the units step; then bound to D4-24 and D4-27, answered the same day. See [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4-04, D4-08, D4-10 and D4-11, and Q9 to Q11, V3 and V4, D4-24 and D4-27. Owns the panel: the Systems tab, the Equipment subtab, the family selector, the
Ventilators table with the Serves column and the balance, the two disclosed fields, the W/cfm
quantity, and the `By ventilator` Colour-by mode. Every control calls an operation P4-02 to P4-04
registered; the panel computes nothing but the balance comes from a Ruby read (D4-10).

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Behaviors" and "Family 1". Load
`.agents/skills/ph-composer-ui-polish/SKILL.md` first. The [UI baseline](../../../ui-baseline/README.md)
rules the Systems tab's subtabs (its row "Systems: Equipment, ERV ducting and Hot-water piping
peer subtabs"); read its Assemblies and Window Types rows, whose inventory and subtab patterns
this tab follows.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The pane (A2).** Enable the reserved tab in `html/index.html`: the disabled "Systems" button
   becomes the Mechanical tab, `data-tab="mechanical"` with a `data-pane="mechanical"`, moved to
   sit after Thermal Bridges and before Library (D4-13, D4-27). The composition-root edit the rules
   permit. Add the new modules and run `make panel-manifest`.
2. **Subtabs and selector (D4-08).** `html/features/mechanical/section.js` registers the pane's
   section and `panel.workedOn("ph_composer.mechanical", "mechanical")`; the shared `subtabs.js` row
   lists Equipment, and later ERV ducting and Hot-water piping once their sections publish.
   `families.js`: a select in the page header choosing the family; one inventory table beneath it;
   the choice remembered on this computer as a display preference, never written to the Model.
3. **Balance read (D4-10).** `serves/balance.rb`, pure: per Ventilator, the served Zones' supply
   and extract sums from `ph_composer.spaces.all`'s Zone rows, null while any served Zone's sum is
   null, `imbalanced` by `Spaces::Metrics`' rule. A served Zone in Detailed airflows gives its
   Spaces' sums. A served Zone that is By Program (`airflow_mode`, F24) gives its Program's flow,
   `ventilation_m3h` on its `ph_composer.programs.zones` row, as both supply and extract, which is
   what PHX writes for it (D4-24); the feature gains `requires: ["ph_composer.programs"]` here.
   The sums are null, and the row reads a dash, only while Programs cannot work that flow out.
   The Ventilators snapshot section takes that Programs read once per snapshot and shares it:
   Phase 6 logged the cost of its Zone reads on every snapshot as a follow-up. Exposed on `ventilators.all` rows and the
   snapshot section.
4. **Ventilators table.** `ventilators.js` on `html/inventory.js`: name, quantity, sensible,
   latent, electric efficiency (the new quantity), frost protection, defrost temperature, in
   conditioned space, the Serves column as Zone chips with a Zone picker calling `serves.assign`
   (listing Zones under their Building Segment headings as the Zone views do, Zones in no
   Segment included, with a whole Segment offered at once, F39; offering replace when the slot is
   filled, V1) and `serves.clear`, the balance columns (supply,
   extract, marker, a dash while a served Zone's flow is unknown), and a per-row disclosure for the two optional fields
   (V3). Add, duplicate, delete with the `ReplacementForm` offering replacement or clear (D4-05),
   in-place and range edits through `record_edits` and `inventory_grid`, column sort and value
   filters, a `tableId` so `table_contributions.js` can add the duct-length columns later
   (ducting Q9).
5. **Units (A3, D4-11).** `electric_efficiency` in `core/units.rb` and `html/unit_tables.js` with
   vectors, Wh/m³ stored and W/cfm under IP; a draft keeps its unit through a switch.
6. **Colour-by.** `features/mechanical/colour_modes.rb`: `by_ventilator`, `entity_kind: "zone"`,
   each served Zone in its item's colour from the ramp, unserved Zones absent, legend rows counting
   Zones; label carries the item name.
7. **Preview and manifests.** A preview fixture in `tools/ui-preview/host.js`'s section map and an
   `mechanical_checks.cjs` under `tools/ui-preview/` through the shared `support/browser_evidence.cjs`
   collector; regenerate the panel manifest and the vendor manifest.

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
5. The family select changes the table without a Model write; the choice is remembered.
6. `by_ventilator` entries: one per served Zone keyed by Zone id, none for an unserved Zone.
7. The panel layout test: nothing outside `html/features/` names this feature.

## Host gate

Fresh process: every gesture in M05 on the reference model with Ed at the mouse; the Phase 3a Zone
views cases the ledger screens for `index.html` and the kit files repeated. Record with
`acceptance_case.py`.

## Out of scope

Hot water (P4-07). Zone views of equipment (Q10, deferred). A toolbar.

## Done when

- M05 has evidence in `../evidence/p4-05-systems-tab.md`, with the UI polish review recorded.
- `make ci` passes on both Rubies; the panel manifest and the vendor manifest are current.
