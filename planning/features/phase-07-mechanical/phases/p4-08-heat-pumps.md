# P4-08: Heat Pumps (four tables, pure Ruby blend, blended result view and export)

DATE: 2026-10-21
STATUS: Scoped. Written in full on 2026-11-23 from D4-14 to D4-16, D4-20, D4-23, D4-25 and D4-28 to D4-31. Climate's entry gate was met on 2026-11-18. Host gate runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-07, `ph_composer.climate` (met 2026-11-18), D4-14 to D4-16, D4-20, D4-23, D4-25 and D4-28 to D4-31. Owns family 3 end to end:
- Four flat catalog kinds (`hp_outdoor_equipment`, `hp_indoor_equipment`, `hp_outdoor_unit`, `hp_indoor_unit`) and their CRUD operations.
- The `hp_indoor_unit_ids` (`many`) Serves slot on the Zone record (moving the Serves payload `schema_version`, F34).
- The pure Ruby per-Building-Segment blended air-source heat pump calculation (`heat_pumps/blend.rb`, F35, D4-15, D4-23) following the published Phius Heat Pump Performance Estimator method (HSPF/HSPF2 conversion, FSEC climate derating using Climate's 12 monthly means and ASHRAE 99%/1% design temperatures, F20; `min_coil_temp = 12.0 °C`; no > 200 kW split in HBJSON per D4-29 and F40).
- The `Heat Pumps` subtab on the Mechanical tab with five pills: `Equipment · Outdoor`, `Equipment · Indoor`, `Units · Outdoor`, `Units · Indoor` (grouped by outdoor unit, carrying `Serves`), and read-only `Blended result` in the estimator's sections with a copy action (D4-16).
- The `ph_composer.mechanical.export.heat_pumps` Python section, conformance check and PHX round trip (`tests/python/test_heat_pumps_phx_round_trip.py`, D4-25).

Behavior owner: [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15) and [Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23). Names: [CONTRACTS](../CONTRACTS.md) sections 2, 3, 4 and 6. Reference [wireframes](../mockups/README.md) (`HeatPumpsEquipOutdoor.dc.html`, `HeatPumpsEquipIndoor.dc.html`, `HeatPumpsUnitsIndoor.dc.html`, `HeatPumpsBlended.dc.html`). Load `.agents/skills/ph-composer-ui-polish/SKILL.md` before building the screens.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The four kinds (D4-14, D4-20, D4-28).** `features/mechanical/heat_pumps/`:
   - `outdoor_equipment.rb` (`hpo_`): `Fields.common`, `manufacturer`, `model`, optional `paired_indoor_equipment_id` (`one` ref to `hp_indoor_equipment`), heating capacities at 17 °F and 47 °F (`W`, shown kBtu/h in IP), heating rating mode (`cop_pair` or `hspf`/`hspf2`), cooling capacity at 95 °F (`W`, nullable), cooling rating mode (`eer_seer`/`seer2` or `ieer`).
   - `indoor_equipment.rb` (`hpi_`): `Fields.common`, `manufacturer`, `model` — identity columns only in v1 (D4-28).
   - `outdoor_unit.rb` (`hou_`): `Fields.common`, `manufacturer`, `model`, `outdoor_equipment_id` (`one` ref), `quantity` (int >= 1), `in_conditioned_space` (default false).
   - `indoor_unit.rb` (`hiu_`): `Fields.common`, `manufacturer`, `model`, `indoor_equipment_id` (`one` ref), `outdoor_unit_id` (`one` ref), `quantity` (int >= 1), `in_conditioned_space` (default true).
   - Metadata (F36): all four kinds carry `user_data`, guarded routes, and rows in `docs/USER_DATA.md`.
2. **Serves slot and operations.** Add `hp_indoor_unit_ids` (`many` ref to `hp_indoor_unit`) to `serves/payload.rb` (bumping payload `schema_version`, F34). Register CRUD (`all`, snapshot section, `create`, `update`, `duplicate`, `delete` with `reference.in_use` and replacement) for all four kinds, plus read-only `heat_pumps.blended` query and snapshot section. Feature gains `requires: ["ph_composer.climate"]`. API minor bump, `API::CHANGES` row and agent guide recipe.
3. **Pure Ruby blend (D4-15, D4-23, D4-29, F20, F35).** `heat_pumps/blend.rb`: pure Ruby over detached records plus Climate's `climate.get` (12 monthly means) and `design_temperatures.get` (ASHRAE 99% heating, 1% cooling). Computes one blended air-source heat pump per exported Building Segment from the outdoor equipment whose outdoor units have indoor units serving that Segment's Zones:
   - Weighted heating COP at 17 °F and 47 °F (converting HSPF/HSPF2 with FSEC climate derating), `percent_coverage = 1.0`.
   - Weighted recirculation cooling (`capacity`, `flow_rate_m3_hr`, `annual_COP`, `min_coil_temp = 12.0 °C`, `single_speed = false`, `flow_rate_variable = true`).
   - No > 200 kW split in HBJSON (D4-29, F40): emit non-blocking `mechanical.hp_cooling_over_200kw` info when a Segment's cooling exceeds 200 kW / 682 kBtu/h.
   - Findings: `mechanical.hp_climate_missing` (non-blocking, omits blend if Climate monthly means or design temperatures are missing/incomplete, F20); `mechanical.hp_unit_unpaired` (non-blocking, unpaired/unserved unit); `mechanical.item_across_segments` (non-blocking, outdoor unit whose indoor units serve > 1 Segment, D4-23).
   - Keep the Phius workbook outside this repo; add a synthetic-case public test suite plus a gitignored private comparison test that skips cleanly when the workbook is absent (D4-15).
4. **Export section and PHX round trip (D4-01, D4-25).** `HeatPumpSection` in `mechanical_sections.py`: builds one `PhHeatPumpRatedMonthly` (with `PhHeatPumpCoolingParams_Recirculation`) per exported Building Segment from the Ruby-computed values, attaches to every served Room in that Segment via `add_heat_pump_system` with shared identifiers per Segment (`required_for_export = True`), `result_fields` and `conformance`. Add `tests/python/test_heat_pumps_phx_round_trip.py` in the `phx` group proving one blended heat pump per Segment in PHX.
5. **Heat Pumps subtab and five pills (D4-13, D4-14, D4-16, D4-30).** `html/features/mechanical/heat_pumps.js`:
   - `Equipment · Outdoor`, `Equipment · Indoor` (identity-only), `Units · Outdoor` (kit columns per D4-30), `Units · Indoor` (grouped by outdoor unit, carrying `Serves` chips + Zone picker), and read-only `Blended result` in the Phius estimator's five sections (`Inputs for Energy Model`, `Climate Information`, `Pumps or Fans`, `Performance Data`, `Weighted Value Calculations`) with a header Copy action.
   - Extend preview fixture in `tools/ui-preview/host.js` and `mechanical_checks.cjs`; regenerate panel and vendor manifests.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/mechanical/hot_water/`, `html/features/mechanical/hot_water.js` (P4-06, P4-07) | Sibling multi-table family pattern |
| `features/climate/` (`climate.get`, `design_temperatures.get`) | Published Climate reads (met 2026-11-18) |
| honeybee-ph `honeybee_phhvac/heat_pumps.py` (pinned 1.33.68) | `PhHeatPumpRatedMonthly`, `PhHeatPumpCoolingParams_Recirculation` |

## Tests (write first)

1. Schema round trips for all four kinds; `hp_indoor_equipment` accepts identity-only fields; guarded deletes enforce `reference.in_use` across equipment -> units -> Serves.
2. Pure Ruby `blend.rb` synthetic test cases: COP-pair weighted average, HSPF/HSPF2 climate-derated conversion, cooling blend with `min_coil_temp = 12.0 °C`, missing Climate -> `mechanical.hp_climate_missing`, > 200 kW -> single unsplit system + `mechanical.hp_cooling_over_200kw`, multi-Segment -> one blend per Segment + `mechanical.item_across_segments`.
3. Optional private workbook comparison test (skips cleanly when `_private/` workbook is absent).
4. Python section + `conformance` + PHX round trip (`test_heat_pumps_phx_round_trip.py`): two Rooms in one Segment yield one blended heat pump in PHX.
5. UI preview checks across all five pills (including copy action on `Blended result` and 360 × 520 layout).

## Host gate

Batched into the `MS3` sitting after P4-14/P4-15 (D4-31). Offline `make ci`, browser checks and PHX round trip pass on this stage's PR.

## Out of scope

Ground-source and water-source heat pumps, indoor fan run-time from WUFI (D4-15), Building Segment mechanical cooling switch (P4-08b), piping and ducting.

## Done when

- M08 offline checks, PHX round trip and UI polish review are recorded; host verification lands in `MS3`.
- `make ci` passes on both Rubies; panel and vendor manifests are current.
