# Equipment

DATE: 2026-10-21
STATUS: Scoped. Shared shape (Q1 to Q12), Ventilators (V1 to V6) and hot water (H1 to H7) interviewed 2026-10-21; families 3 to 7 not yet interviewed. Re-baselined against `main` at `420c783a` the same day.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

A METr model is not complete without its ventilators, heat pumps, water heaters, tanks, pumps
and appliances. Today a consultant exports geometry and then types all of that into METr by
hand, again for every variant. The data is small, tabular and has no geometry. What SketchUp
adds is the Zone: the consultant can say "this ERV serves these two Zones" against the thing
they can see.

## What main supplies today

Read on 2026-10-21 at `420c783a`. Paths are relative to `src/ph_composer/`. This replaces the
2026-09-18 port disposition, which assumed the foundation transplant was still ahead.

| Need | State | Where |
| --- | --- | --- |
| Catalog record kinds with the common authored fields (`name`, `notes`, `datasheet_links`, `source`), validation, references and referrer handlers | Exists | `core/records/` (`RecordKind`, `Engine`, `Catalog`, `AuthoringFields.common`); `context/CONTRACTS.md`, "Records and extension data" and "Handler-side dependency reads". Records carry no timestamps; `id`, `schema_version`, `user_data` and `extension_data` are reserved |
| Entity-owned records and reference targets, for an assignment that lives on a Zone Group | Exists | `core/records/entity_store.rb`, `reference_target.rb`; `context/EXTENSIBILITY.md`, "Records inside a Zone occurrence"; Windows and Spaces are the two shipped children |
| Inventory table, in-place cell drafts, record forms, unit fields | Exists | `html/inventory.js`, `inventory_grid.js`, `record_edits.js`, `record_form.js`, `unit_field.js`; the Assemblies Materials table and Window Types are the shipped examples |
| A primary tab with subtabs | Partly | `html/subtabs.js` is the shared subtabs nav (Window Types / U-Values / Schedule). The Systems tab D4 confirmed does not exist: the tab row in `html/index.html` is Zones, Assemblies, Window Types, Library, Export, and a new tab is one button plus one pane there |
| Per-Zone rows on the Zones tab | Exists | Zone views, `html/table_views.js` (`context/EXTENSIBILITY.md`, "Zone views"): a view registers under `"ph_composer.zones"` with its own columns and child rows; a view with no child rows is admitted |
| Per-Zone airflow sums | Exists | `ph_composer.spaces.all` Zone rows: supply, extract and transfer summed over user-specified Spaces, null while any Space inherits, `imbalanced` at 10 percent of the larger (D3a-12). There is no balance view and no grouping function: D3a-8 was superseded on 2026-10-15 |
| Colour-by modes, derived geometry, readouts | Exists | `colour_by/`; `context/EXTENSIBILITY.md`, "Colour-by modes", "Colour-by derived geometry", "Colour-by readouts" |
| Export contributor, preflight, translation sections that attach to a Room, result fields, conformance | Exists | `export/`; `python/ph_composer_translation/sections.py`, `assembly.py`; Spaces is the shipped Room-attaching section (`features/spaces/export.rb`, `space_sections.py`) |
| honeybee-ph's mechanical classes in the pinned runtime | Partly | The pinned wheel `honeybee_ph-1.33.65` ships `honeybee_phhvac` and `honeybee_energy_ph`. `python/ph_composer_translation/stack.py` lists the packages its `load` serves and `honeybee_phhvac` is not among them, so the first mechanical section adds it there and to `tests/python/test_imports.py` |
| Display units for equipment quantities | Partly | Panel: 18 quantities; Ruby report: 10, including `volume` and `airflow` (PR #84). Litres, capacity in kBtu/h and ventilator efficiency in W/cfm are [units Q3](../../cross-phase/units/PRD.md), still proposals |
| Agent access | Exists | Every registered query and action is an agent-facing surface (Phase 3a1): a query declares `response:` and `while_busy:`, an action `preconditions:`, and a new feature bumps `API::MINOR` in `shell/api.rb` with one `API::CHANGES` row. A list read that can grow with the Model is paged, as `ph_composer.spaces.list` is |
| METr | Deferred | PHX is not in the pinned wheels. [metr-export](../../unscheduled/metr-export/README.md) owns conversion and import; every METr row below is checked there |

The predecessor's Q1 and B4 briefs (`../../ph-navigator-sketchup/planning/phases/`) still apply as
read on 2026-09-18: roster kept, one family per interview, no data sheet hosting, no spec status.
B4's single-Room problem is gone: PH-Composer exports one honeybee Room per Zone
(`model_sections.py`, `ZoneSection`).

## Vocabulary

Proposed. `context/UBIQUITOUS_LANGUAGE.md` carries the shared-shape answer (one record per item,
no definition and instance split) and is extended at each family's interview.

| Term | Meaning |
| --- | --- |
| Equipment item | One record in one family. Model-local |
| Serves | The relation between an equipment item and a Zone |
| Ventilator | METr's and honeybee-ph's word for an ERV or HRV unit |
| Hot Water System | The container for tanks, heaters and piping. One per plant |

## The shared shape

Every family follows this. The family sections add only fields.

### Records

```
<Family item>   id, name, notes, datasheet_links, source,          (the common set)
                <family fields with SI unit suffixes>, quantity,
                in_conditioned_space, schema_version

Serves          ph_composer.equipment_assignment on the Zone Group: the ids of the
                items serving that Zone, by family slot (Q3)
```

`created_at` and `updated_at` from the first draft are gone: no shipped record carries them and
D3b-05 dropped them from Thermal Bridge Types for the same reason.

The first draft stored assignment as id fields on the Zone record (`ventilator_id`,
`heat_pump_ids[]`, ...). Zones names no feature, and the accepted
[Zone child pattern](../../../archive/code-review-refactoring/ZONE_CHILD_PATTERN.md) keeps
"equipment schema branches" out of the parent owner. Ed chose on 2026-10-21 (Q3): an entity-owned
record on the Zone Group in this feature's own dictionary, as a Window Unit's record sits on its
instance and a Space's on its Group. A copied Zone carries its served items; this feature
contributes to `ph_composer.zones.occurrence_independent` to decide what the copy keeps. The
Model-level alternative, keyed by item id and `zone_id`, was not taken.

[spaces](../../../archive/phase-03a-spaces/PRD.md) fixed that equipment belongs to the Zone and
a Space inherits it. Appliances are the exception, see family 7.

### Behaviors

- The Equipment subtab under the primary Systems tab (D4) has a family selector, one family's
  inventory table at a time (Q9), with inline edit, Add, Duplicate and Delete.
- A "Serves" column lists Zones as chips. Editing it opens a Zone picker.
- The other side of the relation, which items serve a Zone, is read from the Serves column
  alone (Q10). A Ventilation or Heat pump view of the Zones tab can follow later through the
  shipped Zone views contract without touching Zones; Spaces had deferred that choice here.
- Delete of an item in use follows the Assembly delete contract (`context/CONTRACTS.md`,
  "Geometry records and occurrence references"): refuse while in use, or name a replacement, or
  pass null to clear every reference through the registered referrer handlers, in one Undo step.
  Registration admits no confirmation policy but `none`, so the first draft's "asks, then clears"
  is not available to an action.
- An item that serves no Zone is a non-blocking finding and is not exported, since honeybee-ph
  has nowhere to put it.
- Registers Colour-by modes `By ventilator` and `By hot water system`.
- Owns the airflow balance by ventilator, shown on the Ventilator's row (Q11): the served
  Zones' supply and extract sums from `ph_composer.spaces.all`, the same 10 percent marker, a
  dash while any served Space inherits. The assignment half of this feature therefore requires
  `ph_composer.spaces` as well as `ph_composer.zones`; the definitions never do.

### Export

honeybee-ph attaches mechanical equipment per Room through `room.properties.ph_hvac`. Verified
at 1.33.65 on 2026-10-21: `set_ventilation_system`, `set_hot_water_system`,
`add_heating_system`, `add_heat_pump_system`, `add_supportive_device`, `add_exhaust_vent_device`
and `add_renewable_device`; one ventilation system and one hot water system per Room, sets of the
rest. A PH-Composer Zone is one Room, so each item maps onto the slots of the Rooms it serves.

Open plan item: a translation section's `Attachment.key` names one host per translated object
(`sections.py`). An item serving three Zones is therefore either one translated object per
(item, Zone) pair sharing the item's identifier, or a new attachment shape. Decide at planning,
with the shipped Spaces section as the pattern. Whether PHX then writes one METr device or three
is a [metr-export](../../unscheduled/metr-export/README.md) row.

Field units below are read from the honeybee-ph class docstrings where they state one. Fields
with no stated unit are confirmed at the family's interview. Class and field names were
re-read against the pinned wheel, 1.33.65, on 2026-10-21.

## Family 1: Ventilators

`Ventilator`: `display_name`, `quantity`, `sensible_heat_recovery`, `latent_heat_recovery`,
`electric_efficiency` (Wh/m³, default 0.55), `frost_protection_reqd`,
`temperature_below_defrost_used` (°C, default -5), `in_conditioned_space`,
`subsoil_heat_exchange_efficiency` and `preheated_intake_temperature_c` (both optional). It sits
inside a `PhVentilationSystem` with `sys_type` (default 1, balanced with heat recovery), the unit
and the two duct lists. A Room holds one ventilation system.

PH-Composer records one Ventilator and builds the system around it at export. The user never
sees a separate "system" record. PHX requires a unit on every system (`validate_ventilation_system_source`),
keys the system by identity so one record serving several Zones becomes one METr device, and
skips a Room with no system without error.

Interviewed 2026-10-21; Ed answered each as recommended:

| # | Question | Answer, 2026-10-21 |
| --- | --- | --- |
| V1 | Code. One ventilation system per Room: what does a Zone with two units do? | One Ventilator per Zone, enforced: assigning a second replaces the first after a refusal names it. Identical units are the record's `quantity`; two different units mean the Zone is split |
| V2 | Code. Offer `sys_type` values other than 1? | No. Fixed at 1, balanced with heat recovery, not shown |
| V3 | UI. Which fields are on the row? | The seven core fields as columns; `subsoil_heat_exchange_efficiency` and `preheated_intake_temperature_c` behind a per-row disclosure, blank by default |
| V4 | UI. Electric efficiency in IP? | W/cfm, stored Wh/m³; a new quantity row for the units packet (its Q3). Recovery efficiencies stay unitless |
| V5 | Code. A Zone with no Ventilator | A warning, not blocking: the preflight names each unventilated Zone and export proceeds |
| V6 | UI and code. Does the record carry a rated flow? | No. The row shows supply and extract summed from the served Zones' Spaces (Q11), read-only; nothing stored, since honeybee-ph has no field for it |

## Family 2: Hot water, tanks and heaters

`PhHotWaterSystem`: four tank slots (`tank_1`, `tank_2`, `tank_buffer`, `tank_solar`), a set of
heaters, the distribution trunks, the recirculation elements and `number_tap_points`.

`PhHvacHotWaterTank`: `tank_type`, `quantity`, `in_conditioned_space`, `solar_connection`,
`solar_losses`, `storage_loss_rate`, `storage_capacity` (litres, default 300),
`standby_losses` (W/K, default 4.0), `standby_fraction`, `room_temp`, `water_temp`.

Heaters share `percent_coverage` and `in_conditioned_space`. Variants: Electric; Boiler (fuel,
condensing, efficiencies, return and boiler temperatures); Wood boiler; District; Heat pump
monthly (two COPs at two ambient temperatures); Heat pump annual (`total_system_perf_ratio`);
Heat pump inside (`annual_energy_factor`).

The system also carries `number_tap_points`, `recirc_temp` and `recirc_hours`. PHX keys tanks
and heaters by identity across Rooms, takes tap points, recirculation temperature and hours once
per variant and falls back to 60 °C and 24 h when systems disagree, and has a four-value piping
calculation method enum (`PhxHotWaterPipingCalcMethod`) that `PhHotWaterSystem` has no field for.

PH-Composer records a Hot Water System with tanks and heaters as child rows. The piping
packet links its Piping groups to it.

Interviewed 2026-10-21; Ed answered each as recommended except H3:

| # | Question | Answer, 2026-10-21 |
| --- | --- | --- |
| H1 | Code. One system record with children, or separate Tank and Heater records? | One Hot Water System record; tanks and heaters are its children. One id to assign, copy and delete |
| H2 | Scope. Which heater variants first? | Electric and the three heat pump variants (annual, monthly, inside). Boilers and district stay out, as Q7 says |
| H3 | Code. Keep honeybee-ph's four fixed tank slots? | No: a free list of tanks on the system, slotted into `tank_1`, `tank_2`, `tank_buffer`, `tank_solar` at export in list order, with a warning past four. Departs from the recommendation; the slot each tank lands in is decided at planning (by tank type, or by order) |
| H4 | Code. Where do tap points, recirculation temperature and hours live? | On the system record; the piping packet reads them for the recirculation loop. Two systems that disagree get a warning naming PHX's fallback |
| H5 | Code. Piping Q5 wants the simplified methods as a choice on the system, and honeybee-ph has no field for it | Add the field upstream first: [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135), filed 2026-10-21, asks for the calculation method and the simplified-method inputs on `PhHotWaterSystem`, read by PHX. PH-Composer stores the choice and exports it once the pinned wheel carries it; until then only drawn pipes export |
| H6 | Code. One system per Zone | Yes, the Ventilator rules: a second assignment replaces the first after a refusal names it; an unserved Zone warns and does not block |
| H7 | UI. How are tanks and heaters edited? | Child rows under the system row, opened by its chevron, edited in place, with Add tank and Add heater on the system row |

## Family 3: Heat pumps

`PhHeatPumpSystem` with `percent_coverage` and a `cooling_params` block. Variants: Annual
(`total_system_perf_ratio`), Rated monthly (`COP_1` at `ambient_temp_1` -8.333 °C, `COP_2` at
`ambient_temp_2` 8.333 °C, which are 17 °F and 47 °F), and Combined. Cooling parameters hold
four sub-blocks, each with a `used` flag: Ventilation, Recirculation, Dehumidification, Panel.
Recirculation carries `capacity`, `min_coil_temp`, `flow_rate_m3_hr`, `flow_rate_variable`,
`single_speed` and `annual_COP`.

Open: whether the editor shows all four cooling sub-blocks or only Recirculation, which is the
mini-split case and nearly every project.

## Family 4: Electric heaters

`PhHeatingDirectElectric`: `percent_coverage` and a name. The smallest family. The same
`PhHeatingSystem` base has Fossil boiler, Wood boiler and District variants, which Ed's list
leaves out. See Q7.

## Family 5: Pumps

`PhSupportiveDevice`: `device_type` (4 heat circulation pump, 6 DHW circulation pump, 7 DHW
storage load pump, 10 other), `quantity`, `in_conditioned_space`, `norm_energy_demand_W`,
`annual_period_operation_khrs` (default 8.76), `ihg_utilization_factor`, `ihg_usage_profile`.

## Family 6: Fans

honeybee-ph has no "Fan" class, and the stack writes a fan as two different things. Traced on
2026-10-21 through honeybee-ph 1.33.65 and PHX (`from_HBJSON/create_variant.py`,
`to_WUFI_XML/xml_schemas.py`, `to_METr_JSON/metr_schemas.py`):

- **Exhaust ventilators** (`ExhaustVentKitchenHood`, `ExhaustVentDryer`,
  `ExhaustVentUserDefined`, all on `_ExhaustVentilatorBase`) hold `quantity`,
  `annual_runtime_minutes` and `exhaust_flow_rate_m3s`, on `ph_hvac.exhaust_vent_devices`. PHX
  puts them in each Zone's exhaust collection; WUFI gets `ExhaustVents` on the Zone (type, m³/h,
  runtime), METr gets `lExhVent` per zone. Ventilation air, no electricity.
- **Fan electricity** is a `PhSupportiveDevice` type 10 (watts, khrs, in conditioned space) on
  `ph_hvac.supportive_devices`. PHX merges duplicates into the variant's mech collection; WUFI
  writes it as auxiliary energy, METr as `lSuppDev`.

One consequence for metr-export: both PHX readers walk `room.properties.ph.spaces` and read each
device through the Space's host Room, so a Room with no Spaces contributes no exhaust ventilators
and no supportive devices to the METr model, whatever its `ph_hvac` holds. HBJSON is unaffected.

Ed chose on 2026-10-21 (Q6): a Fan record is an exhaust ventilator (kind, flow, runtime,
quantity) with an optional electric block (W, khrs, in conditioned space). One row on screen; at
export the electric block becomes a linked supportive device of type 10 beside the exhaust
ventilator, so a kitchen hood with a known draw is two honeybee-ph objects from one record.

## Family 7: Appliances

`PhEquipment` subclasses in `honeybee_energy_ph/load/ph_equipment.py`: dishwasher, clothes
washer, clothes dryer, refrigerator, freezer, fridge-freezer, cooktop, Phius MEL, Phius interior,
exterior and garage lighting, three custom annual entries, and three elevator types. Shared
fields: `quantity`, `in_conditioned_space`, `reference_quantity`, `reference_energy_norm`,
`energy_demand` (kWh), `energy_demand_per_use`, `comment`.

These are a Room load, not `ph_hvac`. Two routes exist in honeybee-ph 1.33.65: the older one on
the Room's `electric_equipment` through `ElectricEquipmentPhProperties`, which `ph_equipment.py`
marks for deprecation, and the current one, a `PhEquipment` held by `ProcessPhProperties` on a
honeybee-energy `Process` load (`honeybee_energy_ph/properties/load/process.py`), which PHX reads
from `room.properties.energy.process_loads` into METr's home devices. This packet uses Process
loads (Q12). honeybee-ph also ships Phius residential and multifamily default sets
(`phius_residential.py`, `phius_mf.py`), which compute the standard appliance list from
bedroom and dwelling counts.

Spaces deferred "Occupancy, Electric loads and appliances, Lighting and Hot water" Zone views to
a Zone loads packet that is not drafted. Ed settled the boundary on 2026-10-21 (Q12): this packet
owns the appliance records and the Phius default set; the Zone loads packet, when drafted, owns
occupancy, lighting and the other loads and reuses the same Room-load section.

Open: whether appliances are authored per item, or the user picks "Phius residential defaults"
for a Zone and edits only the exceptions. Recommendation: the default set first. It is what
most Phius models use and needs dwelling count and bedroom count per Zone, nothing else.

## Decisions for the interview

Shared shape first. Each family gets its own round later. Ed answered Q1 to Q12 on 2026-10-21,
every one as recommended; Q6 was re-asked after the stack was traced (family 6). This table is
the interview record.

| # | Question | Recommendation | Ed's answer, 2026-10-21 |
| --- | --- | --- | --- |
| Q1 | One packet with seven family phases, or seven packets? | One packet, one PRD section and one phase per family. The shape is shared and the families are small | One packet |
| Q2 | Family order? | Ventilators, hot water, heat pumps, electric heaters, pumps, appliances, fans | As recommended |
| Q3 | Code. Where is assignment stored? | Changed 2026-10-21. Not on the Zone record: Zones names no feature. An entity-owned record on the Zone Group in this feature's dictionary, following Windows and Spaces, so a copied Zone keeps what serves it; the Model-level alternative is recorded above | A record on the Zone Group |
| Q4 | A product definition reused with different installed quantities: two records, or a type and instances? | One record with a `quantity`. No type and instance split. Duplicate covers the rest. Q1 of the predecessor asked this and the honeybee-ph classes answer it | One record with `quantity` |
| Q5 | Is equipment placed in the model as geometry? | No. Records only. A Ventilator has no position. Ducts and pipes give the lengths that matter | No, records only |
| Q6 | Code. Fans: exhaust ventilators, supportive devices, or both? Re-asked after tracing the stack (family 6) | One record: an exhaust ventilator with an optional electric block exported as a linked supportive device. The first draft's "anything else is a Pumps-tab Other device" still holds for a bare fan with no exhaust air | Exhaust ventilator with an optional electric block that exports as a linked type 10 supportive device |
| Q7 | Boilers, wood boilers, district heat and PV are in honeybee-ph and not on the list. In or out? | Out for MVP, recorded as later. PV waits for the climate and site packet | Out for MVP |
| Q8 | Are equipment items a library kind? | Later. The libraries interview named Ventilators and Heat Pumps as likely future kinds (libraries Q2; roadmap 5.4) | Later, roadmap 5.4 |
| Q9 | One Equipment tab with sub-tabs, or the predecessor's reserved "HVAC" tab plus others? | Confirmed in D4: one Systems primary tab, with Equipment, ERV ducting and Hot-water piping as peer subtabs. Equipment owns the seven family views. The tab is new in `index.html` | Family selector, one table at a time |
| Q10 | UI. Added 2026-10-21. Where does a Zone show what serves it: a Ventilation view and a Heat pump view of the Zones tab, or only the Systems table listing the Zones each unit serves? | The Systems table alone, first. A Zone view costs a module per family and the shipped Zone views contract admits it later without touching Zones | The Systems table alone, first |
| Q11 | UI. Added 2026-10-21. Where is the balance by ventilator shown? | On the Ventilator's row in the Systems table: served Zones' supply and extract sums and the 10 percent marker, a dash while any served Space inherits. Spaces keeps balance by Zone | On the Ventilator's row |
| Q12 | Code. Added 2026-10-21. Does family 7 own the Room's electric equipment load, or does the undrafted Zone loads packet? Appliances now travel as Process loads in honeybee-ph | This packet owns the appliance records and their default set, exported as Process loads; the Zone loads packet, when drafted, owns occupancy, lighting and the non-appliance loads and reuses the same Room-load section | This packet, exported as Process loads |

## Non-goals

No data sheet storage beyond links. No specification status. No sizing or load calculation. No
schedules. No equipment geometry.

## Acceptance shape

Per family, on a synthetic two-Zone model: create two items, serve one Zone with one and both
Zones with the other, export, reload the exact HBJSON in the pinned honeybee stack and find each
object once on the right Rooms with the right values, through the section's `conformance` check
as Spaces does. Delete an item in use and Undo it. Save and reopen. The ventilator family also
closes the HBJSON half of B4's proof: two Zones, two ventilators, distinct on two Rooms. The METr
half, that PHX keeps them distinct, is a metr-export row.

## Prior art and evidence

- Predecessor `planning/phases/Q1_equipment.md`, `B4_ventilation-units.md`
  (`../../ph-navigator-sketchup/`).
- honeybee-ph `honeybee_phhvac/`: `ventilation.py`, `heat_pumps.py`, `heating.py`,
  `hot_water_devices.py`, `hot_water_system.py`, `supportive_device.py`,
  `properties/room.py`. Re-read at 1.33.65 on 2026-10-21.
- honeybee-ph `honeybee_energy_ph/load/`: `ph_equipment.py`, `phius_residential.py`,
  `phius_mf.py`; `honeybee_energy_ph/properties/load/equipment.py`.
- PHX `model/enums/hvac.py`, `to_METr_JSON/metr_schemas.py`: not re-read; PHX is not in the
  pinned runtime.
- The shipped Room-attaching section: `src/ph_composer/features/spaces/export.rb` and
  `python/ph_composer_translation/space_sections.py`.
