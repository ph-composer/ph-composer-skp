# Research: the honeybee-energy Program pattern

DATE: 2026-11-14
STATUS: Research complete. Reference for the Phase 4a interview and UI prototype.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

How honeybee-energy models a Program, how a Room inherits and overrides it, how a Model writes it
to HBJSON, where library programs come from, and which authoring operations the Honeybee
Grasshopper components offer. The load and schedule classes are in
[loads-and-schedules.md](loads-and-schedules.md).

## Baseline

Citations are to the wheels PH-Composer ships (`src/ph_composer/vendor/wheels/`,
`pyproject.toml`), not to local checkouts:

| Package | Pinned | Note |
| --- | --- | --- |
| honeybee-energy | 1.123.23 | The local `honeybee-energy` checkout is a fork at 1.121.21.dev1 that adds `ExhaustAir` (`load/exhaust.py`, a ProgramType `exhaust` slot, a Room `exhaust` override). The pinned wheel has none of it. `programtype.py` and `properties/room.py` differ by 87 and 104 lines; every `load/` and `schedule/` module except a docstring in `ventilation.py` is identical |
| honeybee-core | 1.64.65 | |
| honeybee-standards | 2.0.7 | `energy_default.json`: 2 programs, 8 schedules, 9 type limits |
| honeybee-energy-standards | not shipped | The DOE/ASHRAE program library (239 programs per vintage, 3,347 schedules, about 12 MB on disk) |
| honeybee-ph | 1.33.65 | Local checkout 1.33.68 differs only in `honeybee_energy_ph/properties/load/equipment.py` (legacy equipment migration) |
| PHX | not shipped | Downstream only. `stack.PACKAGES` names it; no wheel is vendored. Local checkout 1.59.1 |

`ExhaustAir` is out of scope until the pin moves past it.

## 1. ProgramType

`honeybee_energy/programtype.py`. A ProgramType is a named bundle of up to eight load objects, each
with its own schedules. It holds no geometry and no absolute quantities: every load is normalised
(per floor area, per person, per exterior area or per Room).

| Slot | Class | Normalised by | Schedules carried | Absent means |
| --- | --- | --- | --- | --- |
| `people` | People | people per m² floor | occupancy (fractional), activity (W/person) | no occupants |
| `lighting` | Lighting | W per m² floor | one fractional | no lighting |
| `electric_equipment` | ElectricEquipment | W per m² floor | one fractional | none |
| `gas_equipment` | GasEquipment | W per m² floor | one fractional | none |
| `service_hot_water` | ServiceHotWater | L/h per m² floor | one fractional | no hot water use |
| `infiltration` | Infiltration | m³/s per m² exposed exterior area | one fractional | no leakage |
| `ventilation` | Ventilation | four terms: per person, per m² floor, per Room, ACH | optional fractional | no outdoor-air requirement |
| `setpoint` | Setpoint | none | heating, cooling (°C); optional humidify/dehumidify (%) | the Room cannot be conditioned |

- Constructor: `ProgramType(identifier, people=None, lighting=None, electric_equipment=None,
  gas_equipment=None, service_hot_water=None, infiltration=None, ventilation=None, setpoint=None)`
  (`programtype.py:68`). Every slot is optional and type-asserted on set.
- **Not in a ProgramType:** Process loads, daylighting control, window ventilation control, fans
  and internal masses. These are Room-only (section 2).
- `identifier`: `valid_ep_string`: ASCII, none of `, ; ! \n \t`, at most 100 characters, spaces
  allowed. `display_name`: free text, defaults to the identifier, serialised only when set.
  `user_data`: an optional JSON-safe dict.
- `schedules` (`:210`) lists every schedule its loads carry; `schedules_unique` deduplicates.
- `@lockable`. `lock()` locks every load too. A Room locks its program on assignment, so a program
  shared by many Rooms is immutable once assigned: edit a duplicate, then reassign.
- Equality and hash use the identifier plus the hash of each load. `display_name` and `user_data`
  do not count.
- `to_dict(abridged)` (`:368`): `type` is `ProgramType` or `ProgramTypeAbridged`, then
  `identifier`, then each present slot as that load's dict (abridged loads name schedules by
  identifier), then `display_name` and `user_data` if set. Absent slots are omitted, never null.
- `from_dict_abridged(data, schedule_dict)` (`:323`) raises `ValueError` naming a missing schedule.
- `ProgramType.average(identifier, programs, weights, timestep_resolution)` (`:494`): a weighted
  blend, slot by slot. Each load class supplies its own `average`. Weights must sum to 1.
  Intensities average with the raw weights, so a slot present in only some programs is diluted by
  the others' absence. The blended schedules get derived identifiers such as
  `'{id}_Occ Schedule'`.
- `diversify(count, ...)` (`:402`): random Gaussian variants with offset schedules. Simulation-study
  tool, not authoring.

A library example, abridged (honeybee-energy-standards `2019::MidriseApartment::Apartment`): People
0.0283 /m² on `ApartmentMidRise OCC_APT_SCH`, Lighting 9.36 W/m², ElectricEquipment 6.67 W/m²,
ServiceHotWater 0.149 L/h·m² at 60 °C, Infiltration 0.000569 m³/s·m², Ventilation 0.35 ACH with no
schedule, Setpoint with heating and cooling schedules, `user_data.source = "US DOE"`.

## 2. Room inheritance and overrides

`honeybee_energy/properties/room.py`, `RoomEnergyProperties`.

- **Program assignment.** `program_type` (`:126`). Unset returns the library `Plenum` program, with
  no loads and no setpoint (`:134`). Setting it locks the program.
- **Per-load override.** Each of the eight slots has a Room-level override that is None by default.
  The getter returns the override if set, otherwise the program's load. Setting one locks the load.
- `has_overridden_loads` (`:442`) is true when any override is set. `reset_loads_to_program()`
  (`:1247`) clears every override.
- **Room-only loads:** `process_loads` (a list of Process, `:399`), `daylighting_control`,
  `window_vent_control`, `fans`, `internal_masses`, plus `shw` (the SHWSystem supply equipment) and
  `hvac`.
- `is_conditioned` (`:437`) is true only with both an `hvac` and a setpoint. Setpoint matters only
  for EnergyPlus; the PH path reads setpoints elsewhere (see
  [ph-stack-consumption.md](ph-stack-consumption.md)).

**Absolute values become per-area overrides.** The `absolute_*` methods (`:486` to `:620`) take a
Room total and write a normalised override:

| Method | Writes |
| --- | --- |
| `absolute_people(count)` | `people_per_area = count / floor_area` |
| `absolute_lighting(W)`, `absolute_electric_equipment(W)`, `absolute_gas_equipment(W)` | `watts_per_area = W / floor_area` |
| `absolute_service_hot_water(L/h)` | `flow_per_area = flow / floor_area` |
| `absolute_infiltration(m³/s)` | `flow_per_exterior_area = flow / exposed_area` |
| `absolute_infiltration_ach(ach)` | `ach × volume / 3600`, then as above |
| `absolute_ventilation(m³/s)` | zeroes per-person, per-area and ACH; sets `flow_per_zone` |

- `_dup_load` (`:1716`) duplicates the inherited load, renames it `'{room_id}_{load_name}'` and
  keeps its schedules. With no load to duplicate it creates a zero load on `Always On`.
- `_absolute_by_floor` (`:1737`) leaves the load unchanged when floor area is zero. A Room with no
  floor face therefore silently keeps a zero load.
- **Consequence for PH-Composer:** an absolute value is a Room fact, not a program fact. If a user
  types "4 occupants" for a Zone, the HBJSON form of that is a Room-level People override whose
  `people_per_area` depends on that Room's exported floor area.

**Room dict** (`to_dict`, `:1480`). Inside a Model the type is `RoomEnergyPropertiesAbridged`:
`program_type` is an identifier and loads are abridged. Override keys (`people`, `lighting`,
`electric_equipment`, `gas_equipment`, `service_hot_water`, `infiltration`, `ventilation`,
`setpoint`) appear only when set. `process_loads` is a list, present only when non-empty.

## 3. Model emission

`honeybee_energy/properties/model.py`, `_add_sched_type_objs_to_dict` (`:2748`).

- `properties.energy.program_types`: every unique program assigned to a Room, abridged.
  `program_types` (`:380`) collects only programs set on Rooms (`_program_type`), not the
  inherited Plenum.
- `properties.energy.schedules`: every schedule reachable from programs, Room overrides, Process
  loads, HVAC and shades, deduplicated by value with `set()`, always abridged.
- `properties.energy.schedule_type_limits`: the full type-limit dicts those schedules name.
- **Loading has no library fallback** (`load_properties_from_dict`, `:2115`). Every schedule and
  type limit a program names must be in the file, including `Always On` and `Fractional`. Only
  People special-cases `"always on"` and `"seated adult activity"`.
- Two schedules with the same identifier and different values both survive `set()` and collide on
  load. `check_duplicate_schedule_identifiers` and `check_duplicate_program_type_identifiers` are
  the validators.
- `IMMUTABLE_SCHEDULES = ('Always On', 'Seated Adult Activity', 'HumidNoLimit', 'DeHumidNoLimit')`
  (`lib/schedules.py:21`) are never renamed by `reset_resource_ids` (`model.py:1811`). They are
  stable identifiers an exporter can rely on.

## 4. Where programs come from

`honeybee_energy/lib/programtypes.py`, `lib/_loadprogramtypes.py`.

1. **Defaults** from `honeybee_standards/energy_default.json`: `Plenum` and
   `Generic Office Program`, locked.
2. **Standards extension**, honeybee-energy-standards, read lazily from
   `programtypes/<vintage>_data.json`. Vintages: `pre_1980`, `1980_2004`, `2004`, `2007`, `2010`,
   `2013`, `2016`, `2019` and `breeam`. Identifiers are `'<vintage>::<BuildingType>::<SpaceType>'`,
   for example `2019::MidriseApartment::Apartment`. `programtypes_registry/<vintage>_registry.json`
   maps each building type to its space types. `building_mix.json` gives each building type's space
   ratios; `building_program_type_by_identifier` blends them with `ProgramType.average`.
3. **User libraries**: JSON files in the user's standards folder. They cannot overwrite a default
   identifier.

`program_type_by_identifier(id)` searches the defaults, then the extension data. **PH-Composer ships
only the defaults.** Any lookup of a `2019::...` id fails in the export runtime today, which matters
for honeybee-ph's Phius programs ([ph-stack-consumption.md](ph-stack-consumption.md), section 3).

## 5. Authoring affordances in Honeybee Grasshopper

The honeybee_grasshopper_energy components are the user-facing affordances the Program tab should
match. Each one names an operation PH-Composer would need.

| Component | What it does | Operation it implies |
| --- | --- | --- |
| HB Search Programs | Filter library programs by building type, vintage (default 2019) and keywords | Browse and search a program library |
| HB Building Programs | List building types | Library facet |
| HB ProgramType | New program from a `base_program_` (object or library id; default Plenum) with any slot replaced | Create from scratch or from a template; replace one load |
| HB People, HB Lighting, HB Equipment, HB Service Hot Water, HB Infiltration, HB Ventilation, HB Setpoint | Build one load with its values and schedules | Edit one load (a section of the Program editor) |
| HB Process Load | Build a Process load (absolute W, fuel type, end-use category) | Room-level only; not a Program section |
| HB Deconstruct ProgramType, HB Deconstruct People / Lighting / Equipment / Hot Water / Infiltration / Ventilation / Setpoint | Read a program's loads and values | Inspect, the read side of the editor |
| HB Blend ProgramTypes | Weighted average of programs, ratios summing to 1 | Make a mixed program |
| HB Apply ProgramType | Assign a program to Rooms or a whole Model; `overwrite_` clears Room overrides | Assign; reset overrides on assign |
| HB Apply Load Values | Set per-area or per-person values on Rooms or Programs (people/m², W/m², L/h·m², infiltration m³/s·m², ventilation per floor, per person, ACH) | Edit values without touching schedules; creates a load on Always On when absent |
| HB Apply Absolute Load Values | Set Room totals (people, W, L/h, infiltration ACH, ventilation m³/s) normalised per Room | Per-Zone absolute override |
| HB Apply Room Schedules | Replace the schedule on each load of Rooms or Programs; errors if that load is absent | Swap schedules independently of values |
| HB Constant Schedule | 1 value or 24 hourly values, every day, with a type limit | Simple schedule editor |
| HB Weekly Schedule | 24 values per weekday, optional holiday and design days | Week-grid editor |
| HB Seasonal Schedule | Base schedule plus season schedules over date ranges | Rule list with date ranges |
| HB Fixed Interval Schedule | 8760 × timestep values | Import of measured data; large in HBJSON |
| HB Search Schedules, HB Deconstruct Schedule, HB Schedule to Data | Library lookup, read back, plot as hourly data | Schedule browser and chart |

Not affordances for PH-Composer: HB Fan Ventilation, HB Ventilation Control, HB Apply Daylight
Control and the simulation result components.
