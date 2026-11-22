# Research: how honeybee-ph and PHX extend and consume Programs

DATE: 2026-11-14
STATUS: Research complete. Reference for the Phase 4a interview and UI prototype.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The honeybee-energy Program is the HBJSON carrier. What reaches WUFI-Passive, METr and PHPP is
decided by honeybee-ph's extensions and by what PHX reads. A field PHX ignores is HBJSON fidelity
only. Baseline: honeybee-ph 1.33.65 (pinned), PHX 1.59.1 (local checkout, not shipped). Paths are
relative to each repository: `honeybee_ph/` for honeybee-ph, `PHX/` for PHX.

## 1. What honeybee-ph extends

`honeybee_energy_ph/_extend_honeybee_energy_ph.py` adds a `ph` extension to five honeybee-energy
classes plus an empty one on ServiceHotWater:

| Class | `properties.ph` | Notes |
| --- | --- | --- |
| People | `PeoplePhProperties`: `number_people` (average PH occupants, float), `number_bedrooms` (int), `dwellings` (`PhDwellings{identifier, num_dwellings}`), `id_num` | `honeybee_energy_ph/properties/load/people.py` |
| Lighting | `LightingPhProperties`: `target_lux` (300), `target_lux_height` (0.8 m), `equipment` (one PhEquipment) | `.../load/lighting.py` |
| ElectricEquipment | `ElectricEquipmentPhProperties`: writes only `type`; the legacy `equipment_collection` migrates to Process loads (honeybee-ph decision 0009) | `.../load/equipment.py` |
| Process | `ProcessPhProperties.equipment`: one PhEquipment (appliance, lighting device) | `.../load/process.py` |
| ScheduleRuleset | `ScheduleRulesetPhProperties`: `operating_weeks_year` (52.1429), `operating_days_wk` (7), `operating_periods` (a collection of `DailyOperationPeriod{name, start_hour, end_hour, operation_fraction}`), `id_num` | `.../properties/ruleset.py` |
| ServiceHotWater | empty; `to_dict` writes nothing | `.../properties/hot_water/hw_program.py` |

**Not extended:** ProgramType, Ventilation, Infiltration, Setpoint, GasEquipment,
ScheduleFixedInterval.

Serialization: honeybee-energy writes `properties: {type, ph: {...}}` and creates the `ph` object
on first access, so with honeybee-ph loaded every People load and ScheduleRuleset carries a
default `ph` block. On load, an absent `ph` block is safe; a present one must be complete. People
needs `id_num`, `number_bedrooms` and `number_people`; ScheduleRuleset needs `id_num`,
`operating_weeks_year`, `operating_days_wk` and `operating_periods.collection`, or loading raises
`KeyError`. honeybee-ph-schema has no model for any of these; the runtime `to_dict` is the contract.

PhEquipment (`honeybee_energy_ph/load/ph_equipment.py`): `equipment_type`, `display_name`,
`identifier`, `reference_quantity` (1 PH-case occupants, 2 zone occupants, 4 units, 5 user),
`quantity`, `in_conditioned_space`, `reference_energy_norm`, `energy_demand` (kWh/a per unit),
`energy_demand_per_use`, `combined_energy_factor`, `ihg_utilization_factor`, plus per-type extras
(dishwasher, washer, dryer, cooktop, Phius lighting `frac_high_efficiency`). PHX deduplicates
devices by `identifier` across merged Rooms, so identifiers must be stable per device.

## 2. What PHX reads, load by load

PHX merges every Room of a building segment into one variant zone (`PHX/from_HBJSON/cleanup.py`,
`create_project.py`), then reads per-Space values from each Space's original host Room.

### People and occupancy

| Source | PHX use | Destination |
| --- | --- | --- |
| `People.people_per_area` | Per-Space peak occupancy = `people_per_area × floor area × Space floor share`, only when the dwelling has no explicit `number_people` (`create_rooms.py`) | WUFI `NumberOccupants`; METr `nOcc` per space |
| `ph.number_people` | Summed on merge → zone occupant quantity | WUFI `OccupantQuantityUserDef` (truncated to int); METr `nOcc` |
| `ph.number_bedrooms` | Summed → zone bedrooms | WUFI `NumberBedrooms`; METr `nBedR` |
| `ph.dwellings.num_dwellings` | Groups Rooms by dwelling identifier → unit count | WUFI `NumberUnits`; METr `nUnits`; PHPP Verification |
| `occupancy_schedule` | Occupancy utilization pattern (section 3) | WUFI `UtilizationPatternsPH` |
| activity schedule, radiant/latent fractions | ignored | |

Residential occupants, bedrooms and dwellings live on `People.properties.ph`, never on the Room or
building segment. `BldgSegment.num_dwelling_units` is serialised but PHX never reads it.

### Lighting

| Source | PHX use | Destination |
| --- | --- | --- |
| `Lighting.watts_per_area` | Per-Space installed power | WUFI `InstalledLightingPower`; METr `instLP` |
| `Lighting.schedule` | Full-load hours = annual operating hours × relative factor | WUFI `LightingFullLoadHours`; METr `lFLoadH` |
| `ph.equipment` | Residential only: a lighting HomeDevice | WUFI HomeDevice; PHPP Electricity |
| `ph.target_lux`, `target_lux_height` | ignored; WUFI gets a hardcoded 300 lux | |

### Electric equipment, Process and appliances

PHX forks on `bldg_segment.phius_certification.building_category_type`:

| Source | Residential | Phius non-residential |
| --- | --- | --- |
| `ElectricEquipment.watts_per_area` + schedule | ignored | W/m² × floor area × full-load hours / 1000 (`create_process_loads.py`) |
| `Process.watts`, schedule, `fuel_type`, `lost_fraction` | ignored | `watts × FLH`; non-electric fuel skipped; `lost_fraction < 1` counts as inside |
| `Process.properties.ph.equipment` (PhEquipment) | read; each device to the appliance list | dropped with a warning |
| GasEquipment | ignored | warning only |

A PHI non-residential building takes the residential path.

### Ventilation

| Source | PHX use | Destination |
| --- | --- | --- |
| `Ventilation` per-person, per-area, per-zone and ACH | **summed** (`method` ignored), split by Space floor share, × 3600 to m³/h | WUFI `DesignVolumeFlowRateSupply/Exhaust`; METr `dVFrSup/dVFrEx` |
| `Ventilation.schedule` | Ventilation utilization pattern (section 3) | WUFI `UtilizationPatternVent`; METr; PHPP collapses to three speeds |
| `Space.properties.ph._v_sup`, `_v_eta`, `_v_tran` (m³/s) | Each non-None value overrides the load-derived flow | as above, plus transfer |
| Room ventilation system id | links the Space to its ventilator | WUFI `IdentNrVentilationUnit` |

No Ventilation load gives zero flow on a 24 h, 100 % default pattern. PH-Composer already writes
`_v_*` with an any-set rule (all unset writes None; otherwise unset rates are 0). honeybee-ph's
Grasshopper component sets unset values to 0, which zeroes extract when only supply is given.

### Service hot water

PHX never reads `service_hot_water` (no occurrence in `PHX/PHX/`). Hot water demand in WUFI and
METr is the tool's own occupancy-based default; the system (tanks, heaters, piping) comes from
`honeybee_phhvac`. The SHW load affects EnergyPlus only.

### Infiltration and airtightness

The HB Infiltration load is **the only airtightness path**. There is no PH field.

- Stored: `flow_per_exterior_area`, m³/s·m² at 4 Pa. Merged Rooms average it by exposed area.
- PHX converts (`create_variant.py`): `q50 = flow × (50/4)^0.65 × 3600` m³/h·m² (≈ × 18,600), with
  flow exponent 0.65 and air density 1; `n50 = q50 × gross envelope area / net volume`.
- Destinations: WUFI `EnvelopeAirtightnessCoefficient` (q50), METr `tightEnv50`, PHPP n50.
- The infiltration schedule is ignored.

To author n50 or q50 the exporter must invert this: `flow_per_exterior_area = q50 / 3600 /
(50/4)^0.65`, with q50 from n50 via net volume and envelope area. PHX's envelope area must be the
same area the exporter divides by, or the round trip drifts.

### Setpoints

The HB Setpoint load is ignored. PHX reads `bldg_segment.set_points.{winter, summer,
mechanical_cooling}` (defaults 20 and 25 °C) for WUFI/METr `indoorT` and `overhTLim` and PHPP
Verification.

## 3. Schedules into utilization patterns

PHX picks a branch per schedule by whether `ph.operating_periods` is non-empty
(`PHX/from_HBJSON/create_schedules.py`).

| Pattern | PH-style branch (operating periods present) | HB-style fallback (no periods) |
| --- | --- | --- |
| Ventilation | Period names **must be** `high`, `standard`, `basic`, `minimum`, else `AttributeError`. Hours = end − start; speed = `operation_fraction`; days and weeks from the `ph` block | Four-bin histogram of hourly (ventilation schedule × zone flow + occupancy schedule × per-person flow) / peak |
| Occupancy | First period's start and end only; days = weeks × days; relative factor = `annual_average_operating_fraction` | 0 to 24 h, 365 days, factor = mean of hourly values |
| Lighting | as occupancy | as occupancy |

`force_max_utilization_hours` rewrites the high period so ventilation totals 24 h.

**Observed cross-repo discrepancy (PH-style occupancy and lighting).**
`annual_average_operating_fraction` (`honeybee_ph/honeybee_energy_ph/properties/ruleset.py:213`) is
Σ(period hours × fraction) / 24. PHX uses it as the relative utilization factor and also writes the
period's start and end hours, so the daily window counts twice. A Phius non-residential meeting-room
program (occupancy 07:00 to 18:00 at 0.5 on 250 days; lighting 11 h at 1.0) comes out as:

| Output | PHX writes | Program intent |
| --- | --- | --- |
| Occupancy relative factor | 11 × 0.5 / 24 = 0.229 | 0.5 |
| WUFI relative absenteeism | 0.771 | 0.5 |
| Lighting full-load hours | 250 × 11 × (11/24) = 1,260 | 2,750 |

The PHX characterization test `tests/test_from_HBJSON/test_create_schedules/test_hb_style_fallback.py`
pins the current output, not a specification. Decided 2026-11-14: fix honeybee-ph's property, then
PHX ([DECISIONS.md](../DECISIONS.md#answered), Q4a-08).

**Reproduction, run 2026-11-14** (PHX venv: PHX 1.56.104 editable, honeybee-ph 1.33.68,
honeybee-energy 1.117.10). Build People and Lighting from
`PHIUS_programs.PHIUS_library["2021::PHIUS_NR::Office_Meeting_Room"]` with honeybee-ph's
`library/programtypes.py` `build_hb_people_from_Phius_data` and `build_hb_lighting_from_Phius_data`,
set them on `Room.from_box`, and call PHX `from_HBJSON/create_schedules.py`
`build_occupancy_schedule_from_hb_room` and `build_lighting_schedule_from_hb_room`. Result:
occupancy 07:00 to 18:00, 250 days, factor 0.2292; lighting factor 0.4583, 1,260.4 full-load hours
against 2,750 operating hours; the EnergyPlus occupancy schedule is a constant 0.2292 over 8,760 h. The SFH default schedules carry no operating periods, so
they take the HB-style path and are unaffected.

Also: the constant schedules honeybee-ph builds for Phius programs apply the daily fraction to all
8,760 hours, so EnergyPlus never sees the operating days.

## 4. Where PH program defaults live

- **Phius non-residential and multifamily common areas.**
  `honeybee_ph_standards/programtypes/PHIUS_programs.py`: 44 entries (34 `PHIUS_NonRes`, 10
  `PHIUS_MultiFamily`), each with people (start, end, days, relative factor, people per area),
  lighting (hours, days, factor, power density, target lux) and equipment (annual factor, power
  density). `build_hb_program_from_Phius_data` (`honeybee_energy_ph/library/programtypes.py`)
  duplicates a base program and replaces people, lighting and equipment; ventilation, infiltration
  and setpoint come from the base. **All 44 base programs are `2019::...` honeybee-energy-standards
  ids, which PH-Composer does not ship**, so the builder cannot run in the export runtime as pinned.
- **Phius residential (SFH).** The Grasshopper "Set Res Program" component
  (`honeybee_grasshopper_ph/honeybee_ph_rhino/gh_compo_io/program/set_res_program.py`): People with
  `people_per_area = number_people / floor area`; lighting at 80 % RESNET with a
  `PhPhiusLightingInterior` device; ElectricEquipment 0 W; infiltration 0.0003 m³/s·m²;
  Ventilation 0.4 ACH, no schedule; ServiceHotWater from Building America gallons/day (EnergyPlus
  only); the Phius default appliances as Process loads with `watts = annual average wattage`.
  Default schedules: `honeybee_ph_standards/schedules/hbph_sfh_*.json`.
- **Phius appliance defaults.** `ph_default_equip[cls]["PHIUS"]` through `PhEquipment.phius_default()`.
- **Phius multifamily calculators.** `honeybee_energy_ph/load/phius_mf.py`, `phius_residential.py`
  and the Grasshopper "Set Phius MF Res / NonRes" components, which split building totals across
  Rooms on shared-identifier devices.
- **PHI.** No program library. PHPP computes occupancy and internal gains itself from
  `phi_certification` settings. PH-Composer targets Phius only (founding brief).

### The PH Grasshopper program components

The PH-specific affordances, beside the Honeybee ones in
[honeybee-energy-programs.md](honeybee-energy-programs.md#5-authoring-affordances-in-honeybee-grasshopper).
All live in `honeybee_grasshopper_ph/honeybee_ph_rhino/gh_compo_io/program/`:

| Module | Affordance |
| --- | --- |
| `find_phius_program.py` | Pick a Phius non-residential or multifamily program by name |
| `set_res_program.py` | Apply the Phius single-family program from occupants and floor area |
| `set_res_occupancy.py`, `get_res_occupancy.py` | Set or read occupants and bedrooms on People `ph` |
| `set_dwelling.py` | Group Rooms into a dwelling (`PhDwellings`) |
| `set_phius_mf_res.py`, `set_phius_mf_nonres.py`, `get_phius_mf_*_data.py` | Phius multifamily calculator: split building totals across Rooms |
| `create_operating_period.py` | Build a `DailyOperationPeriod` |
| `create_vent_schd.py` | Ventilation schedule from high, standard, basic and minimum periods |
| `create_elec_equip.py`, `add_process_equip.py` | Build PhEquipment and attach it as Process loads |

## 5. Placement summary

| Value | Must be on |
| --- | --- |
| Non-residential occupancy (`people_per_area`), lighting `watts_per_area`, non-res MEL `watts_per_area`, ventilation flows and schedule, infiltration `flow_per_exterior_area`, non-res Process `watts` | the honeybee-energy load |
| `number_people`, `number_bedrooms`, `dwellings`, PhEquipment, schedule operating periods | the load's or schedule's `properties.ph` |
| Space `_v_sup`, `_v_eta`, `_v_tran` | `space.properties.ph` |
| Setpoints, Phius building category and use type | the building segment |

Ignored by PHX: activity schedule, Ventilation `method`, ServiceHotWater, the Setpoint load,
GasEquipment, lighting target lux, `BldgSegment.num_dwelling_units`, residential
ElectricEquipment and `Process.watts`, extra occupancy and lighting periods, the infiltration
schedule. Each is still valid HBJSON and still matters to EnergyPlus.
