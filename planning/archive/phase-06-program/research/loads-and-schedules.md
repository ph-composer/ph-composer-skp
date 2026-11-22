# Research: honeybee-energy loads and schedules

DATE: 2026-11-14
STATUS: Research complete. Field-level reference for the Phase 4a interview, UI prototype and exporter.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Every load and schedule class a Program carries: constructor, stored units, validation, defaults
and the exact HBJSON dict. Baseline is honeybee-energy 1.123.23
([honeybee-energy-programs.md](honeybee-energy-programs.md#baseline)); the `load/` and `schedule/`
modules cited here are byte-identical to the local checkout. Schema references are to the local
`honeybee-schema` (`honeybee_schema/energy/load.py`, `schedule.py`). Example dicts were produced by
running the library.

## 0. Rules an exporter must follow

1. **Stricter of Python and schema.** They disagree:

   | Field | Python | Schema |
   | --- | --- | --- |
   | People `radiant_fraction + latent_fraction` | no sum check | ≤ 1 when latent is a number |
   | Infiltration coefficients | any float | ≥ 0 |
   | ServiceHotWater `target_temperature` | 0 to 100 inclusive | > 0 |
   | Setpoint humidity schedules | setting one fills the other with `HumidNoLimit` or `DeHumidNoLimit` | both required together |
   | ScheduleFixedInterval value count | 24·ts to 8760·ts, any count | also a multiple of 24·ts |

2. **Type limits are never checked against values.** A Fractional schedule holding 5 is accepted.
   Loads check only the attached type limit's `unit` (Fractional loads need `fraction` with limits
   0 to 1; People activity needs `ActivityLevel`; Setpoint needs `C`; humidity needs `%`). A
   schedule with no type limit passes every check. PH-Composer must validate values itself.
3. **Emit `Always On` and `Fractional`** in the Model's schedules and type limits whenever a load
   uses them. Loading has no library fallback.
4. **One identifier per distinct ScheduleDay, and a ScheduleDay belongs to one ruleset.** Loading
   keys days by identifier, so two days with one identifier silently collapse to the last.
5. **Assignment locks.** Every load and program setter calls `lock()` on the schedule it receives.
   Edit a duplicate.
6. **Equality ignores `display_name` and `user_data`.** Two loads with equal values and
   identifiers but different names are the same object to a deduplicating `set()`.
7. **Ventilation with no schedule equals Ventilation on `Always On`** by hash, but the dicts differ:
   the first omits `schedule`.
8. **Numbers serialise as floats.** `Time` is `[h, m]`; `Date` is `[m, d]`, or `[m, d, 1]` for a
   leap-year date.
9. **`_si` accessors are not always the stored unit.** `people_per_area_si` is m²/person; the
   `flow_*_si` accessors are L/s. Store and emit the plain properties.

Shared load base (`load/_base.py`): `identifier` (`valid_ep_string`), `display_name`, `user_data`,
extension `properties` (`properties.ph` with honeybee-ph loaded, see
[ph-stack-consumption.md](ph-stack-consumption.md)), `duplicate()` (schedules are shared, not
copied), `lock()`. Every schedule slot accepts ScheduleRuleset or ScheduleFixedInterval only.

## 1. People (`load/people.py`)

`People(identifier, people_per_area, occupancy_schedule=None, activity_schedule=None,
radiant_fraction=0.3, latent_fraction=autocalculate, carbon_dioxide_generation_rate=3.82e-8)`

| Property | Stored unit | Validation | Default |
| --- | --- | --- | --- |
| `people_per_area` | people per m² floor, peak | ≥ 0 | required |
| `occupancy_schedule` | fraction of peak | fractional type | `Always On` |
| `activity_schedule` | W per person | ActivityLevel type | `Seated Adult Activity` (120 W) |
| `radiant_fraction` | share of sensible heat | 0 to 1 | 0.3 |
| `latent_fraction` | share of total heat | 0 to 1 or Autocalculate | Autocalculate |
| `carbon_dioxide_generation_rate` | m³/s·W | ≥ 0 | 3.82e-8, written only when different |

```json
{"type": "PeopleAbridged", "identifier": "ppl", "people_per_area": 0.05, "radiant_fraction": 0.3,
 "latent_fraction": {"type": "Autocalculate"}, "occupancy_schedule": "Always On",
 "activity_schedule": "Seated Adult Activity"}
```

`area_per_person` is derived and not serialised. Both schedules are always written.

## 2. Lighting (`load/lighting.py`)

`Lighting(identifier, watts_per_area, schedule=None, return_air_fraction=0, radiant_fraction=0.32,
visible_fraction=0.25)`

- `watts_per_area`: W/m² floor, ≥ 0. Schedule fractional, default `Always On`.
- The three fractions are each 0 to 1 and sum to at most 1. `baseline_watts_per_area` is written
  only when set.

```json
{"type": "LightingAbridged", "identifier": "lgt", "watts_per_area": 5.0, "return_air_fraction": 0.0,
 "radiant_fraction": 0.32, "visible_fraction": 0.25, "schedule": "Always On"}
```

## 3. ElectricEquipment and GasEquipment (`load/equipment.py`)

`(identifier, watts_per_area, schedule=None, radiant_fraction=0, latent_fraction=0, lost_fraction=0)`.
W/m² floor; fractions 0 to 1, sum at most 1. The two classes are identical except for `type`
(`ElectricEquipment[Abridged]`, `GasEquipment[Abridged]`) and compare unequal to each other.

```json
{"type": "ElectricEquipmentAbridged", "identifier": "ee", "watts_per_area": 3.0, "radiant_fraction": 0.0,
 "latent_fraction": 0.0, "lost_fraction": 0.0, "schedule": "Always On"}
```

## 4. ServiceHotWater (`load/hotwater.py`)

`ServiceHotWater(identifier, flow_per_area, schedule=None, target_temperature=60,
sensible_fraction=0.2, latent_fraction=0.05)`

- `flow_per_area`: **L/h per m² floor, peak**. × 0.024542 gives gph/ft².
- `target_temperature`: °C at the fixture after mixing. At 60 °C the flow is heater-temperature water.
- `sensible_fraction` and `latent_fraction` are the shares that become zone gains; the rest is
  lost down the drain.
- `from_watts_per_area` and `set_watts_per_area(w, mains=10)` convert a heat rate to flow.

```json
{"type": "ServiceHotWaterAbridged", "identifier": "shw", "flow_per_area": 0.15, "target_temperature": 60.0,
 "sensible_fraction": 0.2, "latent_fraction": 0.05, "schedule": "Always On"}
```

ServiceHotWater is demand. Supply is `SHWSystem` (`shw.py`) on `room.properties.energy.shw`:
`equipment_type` (gas, electric or heat-pump water heaters, tankless and district variants),
`heater_efficiency`, `ambient_condition`, `ambient_loss_coefficient`. The PH stack ignores both and
uses its own hot water system (phase-07-mechanical equipment, hot water H1 to H7).

## 5. Process (`load/process.py`)

`Process(identifier, watts, schedule=None, fuel_type='Electricity', end_use_category='Process',
radiant_fraction=0, latent_fraction=0, lost_fraction=0)`

- `watts`: **absolute W per Room, not per area**.
- `fuel_type`: one of `Electricity, NaturalGas, Propane, FuelOilNo1, FuelOilNo2, Diesel, Gasoline,
  Coal, Steam, DistrictHeating, DistrictCooling, OtherFuel1, OtherFuel2, None`, case-insensitive on
  input, canonical case on output.
- `end_use_category`: free `valid_ep_string`, spaces allowed (`"Clothes Drying"`). `"General"`
  reports under Interior Equipment.
- **Room-only.** Not a ProgramType slot; no `average`. `from_dict` takes no `schedules` argument.

```json
{"type": "ProcessAbridged", "identifier": "pr", "watts": 500.0, "schedule": "Always On",
 "fuel_type": "Electricity", "end_use_category": "Process", "radiant_fraction": 0.0,
 "latent_fraction": 0.0, "lost_fraction": 0.0}
```

## 6. Infiltration (`load/infiltration.py`)

`Infiltration(identifier, flow_per_exterior_area, schedule=None, constant_coefficient=1,
temperature_coefficient=0, velocity_coefficient=0)`

- `flow_per_exterior_area`: **m³/s per m² of exposed exterior area (walls and roofs), at about
  4 Pa operating pressure.** Not a 50 Pa test result. Typical: 0.0001 tight, 0.0003 average, 0.0006
  leaky.
- Absolute flow = `flow_per_exterior_area × room.exposed_area`.
- Coefficients (constant, × ΔT in °C, × wind speed in m/s) are written only when not 1, 0, 0.
  Reference sets: EnergyPlus 1/0/0, BLAST 0.606/0.03636/0.1177, DOE-2 0/0/0.224.

```json
{"type": "InfiltrationAbridged", "identifier": "inf", "flow_per_exterior_area": 0.0001, "schedule": "Always On"}
```

## 7. Ventilation, outdoor air (`load/ventilation.py`)

`Ventilation(identifier, flow_per_person=0, flow_per_area=0, flow_per_zone=0, air_changes_per_hour=0,
schedule=None, method='Sum', effectiveness_cooling=1, effectiveness_heating=1, secondary_recirculation=0)`

| Property | Stored unit |
| --- | --- |
| `flow_per_person` | m³/s per person (0.01 = 10 L/s ≈ 21 cfm) |
| `flow_per_area` | m³/s per m² floor |
| `flow_per_zone` | m³/s per Room |
| `air_changes_per_hour` | 1/h of Room volume |
| `schedule` | optional fractional; multiplies the total |
| `method` | `Sum` or `Max` of the four terms |

- Design flow (`room_absolute_flow`) = per-person × People `people_per_area` × floor area, plus
  per-area × floor area, plus ACH × volume / 3600, plus per-zone, combined by `method`, divided by
  the lower effectiveness.
- A ventilation schedule equal to the occupancy schedule approximates demand control.
- `to_dict` writes only non-default keys:

```json
{"type": "VentilationAbridged", "identifier": "v"}
{"type": "VentilationAbridged", "identifier": "v", "flow_per_person": 0.0085, "flow_per_area": 0.0003, "method": "Max"}
```

- `combine_room_ventilations` merges Rooms into one zone: per-zone summed, per-area by floor area,
  ACH by volume, per-person the max.

## 8. Setpoint (`load/setpoint.py`)

`Setpoint(identifier, heating_schedule, cooling_schedule, humidifying_schedule=None,
dehumidifying_schedule=None, setpoint_cutout_difference=0)`

- Heating and cooling schedules are required, Temperature type (°C). Humidity schedules are
  Percent and travel as a pair.
- The convenience setters `heating_setpoint = 20` and `cooling_setpoint = 25` build constant
  rulesets named `'{id}_HtgSetp'` and `'{id}_ClgSetp'`.

```json
{"type": "SetpointAbridged", "identifier": "sp", "heating_schedule": "sp_HtgSetp", "cooling_schedule": "sp_ClgSetp"}
```

## 9. Room-only, not Program sections

- DaylightingControl (`load/daylight.py`): sensor point in model coordinates, illuminance setpoint
  (300 lux), control fractions. No identifier. Geometry-bound.
- Fans, window ventilation control, internal masses: simulation detail, out of scope.

## 10. Schedules

### ScheduleTypeLimit (`schedule/typelimit.py`)

Immutable: `identifier, lower_limit, upper_limit, numeric_type (Continuous|Discrete), unit_type`.
Absent limits serialise as `{"type": "NoLimit"}`. The library ships nine:

| Identifier | Lower | Upper | Numeric | unit_type | Used by |
| --- | --- | --- | --- | --- | --- |
| Fractional | 0 | 1 | Continuous | Dimensionless | every load schedule |
| On-Off | 0 | 1 | Discrete | Dimensionless | availability; passes the fractional check |
| Temperature | -273.15 | none | Continuous | Temperature | setpoints |
| Activity Level | 0 | none | Continuous | ActivityLevel | People activity |
| Power | none | none | Continuous | Power | |
| Humidity | 0 | 100 | Continuous | Percent | humidity setpoints |
| Angle, Delta Temperature, Control Level | | | | | not needed |

### ScheduleDay (`schedule/day.py`)

`ScheduleDay(identifier, values, times=None, interpolate=False)`. `times` mark **when each value
begins** (Ladybug convention, not EnergyPlus "until"); the first is 0:00. No abridged form, no
`user_data`. `from_values_at_timestep(id, values, ts)` compresses a 24-hour grid into change points,
the natural input from a UI grid.

```json
{"type": "ScheduleDay", "identifier": "Wk_Monday", "values": [0.0, 1.0, 0.0], "times": [[0, 0], [9, 0], [17, 0]], "interpolate": false}
```

### ScheduleRule (`schedule/rule.py`)

One ScheduleDay plus seven `apply_<day>` flags and a `start_date` / `end_date` (a reversed range
wraps New Year). Inside a ruleset it is always abridged and writes all flags and both dates.

```json
{"type": "ScheduleRuleAbridged", "schedule_day": "Wk_Monday", "apply_sunday": false, "apply_monday": true,
 "apply_tuesday": true, "apply_wednesday": true, "apply_thursday": true, "apply_friday": true,
 "apply_saturday": false, "start_date": [1, 1], "end_date": [12, 31]}
```

### ScheduleRuleset (`schedule/ruleset.py`)

`ScheduleRuleset(identifier, default_day_schedule, schedule_rules=None, schedule_type_limit=None,
holiday_schedule=None, summer_designday_schedule=None, winter_designday_schedule=None)`

- Rules are in priority order, index 0 highest. A day with no applicable rule uses the default day.
- Holiday and design days are optional ScheduleDays on the ruleset, not rule flags. Design days
  size HVAC only.
- `day_schedules` in the dict lists each distinct day once, full form, in both abridged and full
  rulesets. The only difference between the two forms is the type limit: an identifier or the full
  dict.
- Helpers: `from_constant_value`, `from_daily_values` (24·ts values),
  `from_week_daily_values` (seven days plus holiday and optional design days; days with identical
  values share a rule), `values(timestep)` (8760·ts), `data_collection`, `average_schedules`,
  `max_schedules`.

```json
{"type": "ScheduleRulesetAbridged", "identifier": "Occ",
 "day_schedules": [{"type": "ScheduleDay", "identifier": "Occ_Day Schedule", "values": [0.5], "times": [[0, 0]], "interpolate": false}],
 "default_day_schedule": "Occ_Day Schedule", "schedule_type_limit": "Fractional"}
```

Traps: `from_week_daily_values` names the winter design day from the summer identifier when both
are derived, and it requires `holiday_values`. `duplicate()` can emit the same day identifier
twice when one day fills two rules.

### ScheduleFixedInterval (`schedule/fixedinterval.py`)

`values` for 8760 × timestep, `timestep`, `start_date`, `placeholder_value`, `interpolate`. About
44 KB of JSON per schedule at timestep 1, about 456 KB at timestep 4. **No `properties.ph` and
PHX reads `properties.ph` unguarded on People, Lighting and Ventilation schedules**, so a fixed
interval schedule there breaks PHX. Use ScheduleRuleset for anything PHX reads.

### Library schedules

Defaults (`energy_default.json`, shipped): `Always On` (constant 1, Fractional), `Seated Adult
Activity` (constant 120 W), and six `Generic Office ...` schedules. The standards extension (not
shipped) holds 3,347 rulesets, including `Always Off` and the DOE apartment schedules.
