# P4-08 evidence: heat pumps

DATE: 2026-11-24
Register row: [M08](../ACCEPTANCE.md). Stage: [P4-08](../phases/p4-08-heat-pumps.md).
Branched from `feat/phase-07-mechanical-p4-07` at `9d963e82` (PR #570); #570 merged to `main` as `d292f45a`, and
the branch was rebased onto `main`. Branch `feat/phase-07-mechanical-p4-08`.

Offline evidence only. No SketchUp process was started. The host case `M08` (in
`planning/native-acceptance/cases.json`) is owed to the MS3 sitting (D4-31); nothing here is host evidence. M08 stays
Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Four kinds | `features/mechanical/heat_pumps/outdoor_equipment.rb` (both models), `units.rb` (both units) | `hp_outdoor_equipment` (`hpo`), `hp_indoor_equipment` (`hpi`, identity only, D4-28), `hp_outdoor_unit` (`hou`), `hp_indoor_unit` (`hiu`), schema 1. Capacities are kW. Each rating mode reads only its own values; the other's stay stored. `missing_inputs` names what the blend still needs |
| 2. Operations and reads | `catalog_operations.rb` (shared with hot water, whose `HotWater::Operations` now delegates), `heat_pumps/operations.rb`, `heat_pumps/reads.rb`, `heat_pump_reads.rb`, `declarations/heat_pumps.rb` | `heat_pumps.<table>.list`, `.all` (snapshot section), `create`, `update`, `duplicate`, `delete` with `replacement_id`, one Undo step each; `heat_pumps.blended` and its section `heat_pumps_blended`. Rows carry counts, an indoor unit's Zones and the plan's findings; an incomplete outdoor model reads `export_ready` false |
| 3. Serves slot | `serves/payload.rb`, `serves/operations.rb`, `declarations/serves.rb` | `hp_indoor_unit_ids` (`many`), payload schema 3. `serves.clear` takes `item_id` to take one item off a list slot |
| 4. Blend and plan | `heat_pumps/blend.rb`, `heat_pump_plan.rb` | The estimator's v25.1.2 air-source arithmetic in IP; one row per outdoor model with its outdoor units' summed quantity; one blend per exported Building Segment, identifier from the Segment name's SHA-256; findings `hp_climate_missing`, `hp_unit_unpaired`, `hp_equipment_incomplete` (new), `hp_cooling_over_200kw`, `item_across_segments` on the outdoor unit, `zone_left_out`, `item_missing` |
| 5. Export | `heat_pump_export.rb`, `climate/export.rb` (`projection`), Python `mechanical_sections.py` (`HeatPumpSection`), `contract/mechanical_records.py`, `composition.py` | One `PhHeatPumpRatedMonthly` per (Segment, served Zone) pair with recirculation cooling, `min_coil_temp` 12.0 °C, fixed identifiers on the four cooling parameter sets; `add_heat_pump_system`; required for export; digest per row and `conformance` per Room. Climate's Site export gains a `projection` (monthly mean air temperatures and both design temperatures) that the heat pump section reads |
| 6. Preflight and Locate | `preflight.rb`, `locate.rb` | Heat pump rows under the new section; `hp_outdoor_equipment_ids`, `hp_outdoor_unit_ids`, `hp_indoor_unit_ids` |
| 7. Panel | `html/features/mechanical/heat_pumps.js`, `heat_pump_units.js`, `heat_pump_blended.js`, `equipment_table.js` (TagForm takes several parents), `serves.js` (list slots), `mechanical.css`; `unit_tables.js` and `fields.js` (`capacity`, kW and kBtu/h) | Heat Pumps subtab with the five pills; Units · Indoor grouped by outdoor unit; Blended result in the estimator's five sections with Copy for the estimator |
| 8. Docs | `docs/AGENT_GUIDE.md` (and the shipped guide), `docs/USER_DATA.md`, `context/CONTRACTS.md`, `context/AGENT_INTERFACE.md`, `context/UBIQUITOUS_LANGUAGE.md`; API 1.93 | |

## Departures and choices

- **Operation names.** CONTRACTS bound `hp_outdoor_equipment.*`; a snapshot section named for that prefix collides with
  the kind id `ph_composer.mechanical.hp_outdoor_equipment` (registration refused it). The four tables are
  `heat_pumps.outdoor_equipment.*` and so on, beside `heat_pumps.blended`. CONTRACTS section 3 corrected.
- **Capacities in kW**, not W as first bound: honeybee-ph's recirculation capacity is kW and the panel's new `capacity`
  quantity shows kW and kBtu/h. CONTRACTS section 2 corrected.
- **New code `mechanical.hp_equipment_incomplete`.** A model created from its Tag has no capacities, so the blend must
  leave it out with a finding; the same code names an HSPF model with no cooling share (below). CONTRACTS section 6
  gains it.
- **Rating modes keep the other mode's values** (unlike a Heater's variant), so switching back restores them and the
  panel changes a mode with one guarded choice.
- **Climate at export.** CONTRACTS named `ph_composer.climate.export.climate`, which does not exist; an export
  contributor reads the snapshot, so Climate's Site export gains a `projection`, the published way one section reads
  another. The live reads use `climate.get` and `design_temperatures.get` as Climate's contract says.
- **Monthly means** feed only the Climate Information (heating months and their shares): the estimator reads them in
  the fan and pump terms, which D4-15 leaves out. They are still required for the blend, as F20 and M08 say.
- **Faithful to the estimator.** The blend keeps the workbook's expressions, including three that read unusually; each
  is for Ed's judgment, not changed here:
  1. An HSPF row is weighted by its share of cooling capacity, not heating, and gives one value to both COPs, so a
     heating-only HSPF model adds no heating COP. The plan notes it (`hp_equipment_incomplete`) and leaves out a
     Segment whose blend then has no COP.
  2. The HSPF derating's second temperature term multiplies the design temperature, not its square.
  3. v25.1.2 picks the SEER derating branch by the SEER as entered and derates the weighted SEER; v25.1.1 picked it by
     the weighted SEER.
- **Minimum coil temperature.** D4-29 fixes 12.0 °C (53.6 °F) and says it was verified against the estimator. The
  estimator's `Inputs for Energy Model` holds a constant 45 °F (7.2 °C) in v25.1.1 and v25.1.2. The code writes
  12.0 °C as decided; the private comparison leaves this value out. For Ed's judgment.
- **The Blended result shows IP**, the estimator's units, whatever the unit preference, so the copied rows paste beside
  the estimator unchanged. A Segment over 682 kBtu/h shows the estimator's Number of Systems Needed and exports one
  system with the whole capacity (D4-29).
- **Two pairs equal per Segment.** A Segment's blend is written to every served Zone the blend reaches: a Zone whose
  indoor units reach only incomplete models gets no heat pump.

## Tests

| Stage doc test | Test |
| --- | --- |
| 1. Schema round trips; identity-only indoor; guarded deletes down the chain | `tests/mechanical_heat_pump_test.rb`: `test_the_four_kinds_round_trip_with_their_defaults_and_an_indoor_model_is_identity_only`, `test_a_unit_naming_a_missing_model_or_none_refuses_and_a_rating_mode_reads_only_its_values`, `test_deletes_refuse_in_use_down_the_chain_and_a_replacement_moves_what_names_them`, `test_the_list_slot_holds_several_indoor_units_and_clear_takes_out_one` |
| 2. Blend synthetic cases | `tests/mechanical_heat_pump_blend_test.rb` (16 tests): COP pair weighting, HSPF2 conversion and derating, the HSPF cooling weighting, EER2/SEER2 conversion and IEER, airflow and capacity, climate months; the plan: one blend per Segment, summed quantities, Segments apart with `item_across_segments`, missing climate, over 200 kW unsplit, unpaired units, incomplete model, an HSPF model with no cooling share, a missing indoor unit, a left-out Zone |
| 3. Private workbook comparison | `tests/heat_pump_estimator_private_test.rb`, reading `_private/heat_pumps/estimator_cases.json` (gitignored, `MANIFEST.md`); skips with its reason when absent. On this computer: 9 workbooks with air-source rows (v25.1.1 and v25.1.2), 654 assertions, all equal to 1e-9 relative |
| 4. Python section, conformance, PHX | `tests/python/test_heat_pump_sections.py` (10), `tests/python/test_heat_pumps_phx_round_trip.py` (1, `phx` group); Ruby golden `tests/fixtures/mechanical/heat_pump_extraction.json` from `tests/mechanical_heat_pump_export_test.rb` (6: the reference, no climate, two Segments and over 200 kW, unpaired and incomplete, user data omitted, privacy) |
| 5. UI | `tests/mechanical_heat_pump_panel_test.js` (4), `tools/ui-preview/mechanical_checks.cjs` heat pump steps |
| Also | `tests/mechanical_heat_pump_test.rb` `test_the_blended_result_needs_the_climate_and_then_blends_each_segment`; Serves payload problems for the list slot; dependency test now requires Climate |

## Gate

`make ci` on Ruby 3.2.2 and 2.7.2 at `84e57814`: each "Ruby suite, 10 processes: 3400 runs, 47112 assertions,
0 failures, 0 errors, 1 skips", JavaScript 1,191 passed, Python 410 passed and 1 skipped, hostkit 48 runs, "RBZ
verified: 762 files, 8865356 bytes, 27282675 bytes installed". At `1a45af69` (the review fixes), both Rubies: "3401
runs, 47116 assertions, 0 failures, 0 errors, 1 skips", JavaScript 1,191, Python 410 passed and 1 skipped, "RBZ
verified: 762 files, 8865809 bytes, 27284951 bytes installed", 715,049 under the 28,000,000 ceiling (P4-07 left
27,147,850). At `a683cf91` (the cycle 2 fix), both Rubies: 3401 runs, 47116 assertions, 1 skip; JavaScript 1,192;
Python 410 passed, 1 skipped; "RBZ verified: 762 files, 8866558 bytes, 27287391 bytes installed", 712,609 under the
ceiling. `uv run tools/runtime/vendor.py --check`: 207 assets, 8 wheels.

`uv run --group phx pytest tests/python`: 410 passed, 1 skipped (`PH_COMPOSER_MAP_DATA` unset); the PHX round trips
(`-k phx_round_trip`) 16 executed, 0 skipped, one of them heat pumps: two Rooms of one Building Segment give one
`PhxHeatPumpMonthly` with the blend's COPs, full heating and cooling coverage and its recirculation cooling, named
once in WUFI XML with `MaxRecirculationAirCoolingPower`.

Browser checks: `make ui-checks UI_CHECKS=tools/ui-preview/mechanical_checks.cjs` passes on both heads (a local Chrome
run, not Chromium 88 or HtmlDialog evidence); the heat pump steps run at 1280 x 800, 420 x 732 and 360 x 520 with no
sideways scroll. The other 38 browser scripts were not run on this head: the stage changes only the Mechanical tab
and a new `capacity` quantity. Screenshots: [Equipment · Outdoor](p4-08/heat-pumps-outdoor.png),
[under IP](p4-08/heat-pumps-outdoor-ip.png), [Units · Indoor](p4-08/heat-pumps-units-indoor.png),
[at 420 px](p4-08/heat-pumps-units-indoor-420x732.png), [Blended result](p4-08/heat-pumps-blended.png),
[at 360 x 520](p4-08/heat-pumps-blended-result-360x520.png).

Design System: re-synced from `main@d292f45a` (#570) as artifact version 35, the P4-07 kit changes (Table's
`readOnly` cells and the `percent` quantity, `ReplacementForm`'s `allowClear` as a function, Export readiness grouped
by section); `bundle.css` checked against its eight stylesheets on that commit and unchanged. This stage changes no
bundled stylesheet; its kit-wide change, the `capacity` quantity, is owed to the sync after this PR merges.

Not run: anything in SketchUp.

## Review

Strong lane, UI. The architecture review and Ruby quality rubrics were loaded before the design; the stage reuses
the shared `EquipmentTable`, pill row, Zone picker and `CatalogOperations` rather than forking them, keeps the blend
and plan pure, and keeps every Serves-naming read out of the family folder (`tests/mechanical_dependency_test.rb`).

- Sonnet adversarial read before the gate: no P1; 3 P2 and 9 P3. Fixed: the preview host's fake delete now treats a
  null replacement as the real action does and checks the replacement exists; an HSPF model with no cooling share is
  noted per model (`hp_equipment_incomplete`) instead of silently or as one Segment-level row; `missing_inputs`
  tolerates an unknown mode; `serves.clear` checks `item_id`'s kind; the agent guide names both meanings of
  `hp_equipment_incomplete`; the private test asserts the heating COPs of an untyped-cooling case. Declined: the
  export reading no unreadable ids (the reader refuses an unreadable record before the plan runs), a zero cooling
  capacity counting as missing (consistent in Ruby and the panel), per-request memoising of the reads (no
  measurement), and a finding for a unit whose model is unreadable (its own unreadable row blocks).
- Codex gpt-6-astra cycle 1 on `84e57814`: 2 P2, both fixed in `1a45af69` (a blank clears a capacity or rating; a
  served unit naming a missing outdoor unit or model reports blocking `mechanical.item_missing`), each thread answered.
- Codex gpt-6-astra cycle 2 on `1a45af69`: 1 P2, fixed in `a683cf91` (each table's delete offers a replacement, and
  clearing only where nothing needs the record), thread answered. That commit merges after the two-cycle cap
  unreviewed.
