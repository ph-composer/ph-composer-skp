# P4-11: fans

DATE: 2026-10-21
STATUS: Merged to main 2026-11-24 (#575, squash `a963b22e`); offline evidence in [p4-11-fans](../evidence/p4-11-fans.md), host case `M11` owed to MS3. Planned in full 2026-11-24 from the stub of 2026-10-21, D4-01, D4-13, D4-20, D4-25, D4-30, D4-31, D4-34 and D4-35, and the [equipment PRD](../equipment/PRD.md), "Family 6". Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host gate runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-10 (#574, which builds the supportive device translation, `ExportZones.spaceless_findings` and the
`electric_power` and `kilohours` quantities) and the fans interview (D4-35, 2026-11-23), with D4-01, D4-13, D4-20,
D4-25, D4-30 and D4-31. Stacks on P4-10's branch while #574 is open; it adds to the same registration lists and the
Serves payload after P4-10's slot.

Owns family 6 end to end:

- One flat catalog kind, the Fan (`ph_composer.mechanical.fan`, `fan`), and its operations: an exhaust ventilator
  (its type, flow, runtime and quantity) with an optional electric block (power, in conditioned space, a runtime
  override), as Q6 and D4-35 settle.
- The `fan_ids` (`many`) Serves slot on the Zone record, moving the Serves payload's `schema_version` from 5 to 6
  (F34).
- The `ph_composer.mechanical.export.fans` export section: per (fan, served Zone) pair, one exhaust ventilator added to
  the Room through `add_exhaust_vent_device` and, when the fan's Power is filled, a linked `PhSupportiveDevice` of type
  10 through `add_supportive_device`, with its preflight rows, conformance and a PHX round trip proving one record
  becomes two honeybee-ph objects with Power and one without (D4-25).
- `mechanical.zone_without_spaces` for a Fan serving an exported Zone with no Spaces (D4-35), through P4-10's
  `ExportZones.spaceless_findings` and the Spaces read lifted beside it, not a copy.
- The `Fans` subtab on the Mechanical tab with one pill, `Fans` (D4-13), built on the shared `EquipmentTable` (D4-30),
  `In conditioned space` and the runtime override behind a collapsed per-row disclosure (D4-35).

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Family 6", and
[DECISIONS, Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23) (D4-35). Names:
[CONTRACTS](../CONTRACTS.md) sections 2, 3 and 6. Pattern: the Pump (one kind, a `many` slot, objects per (item, Zone)
pair under the item's identifier, a per-row disclosure). Load `.agents/skills/ph-composer-ui-polish/SKILL.md` before
building the screen.

Paths are relative to `src/ph_composer/`.

## What the sources settle

Read in the pinned wheel `vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl`:

| Source | What it says | This stage |
| --- | --- | --- |
| `honeybee_phhvac/ventilation.py`, `_ExhaustVentilatorBase` | `identifier`, `display_name`, `user_data` (from `_PhHVACBase`), `device_class_name` (the class name), `quantity` (1), `annual_runtime_minutes` (0.0) and `exhaust_flow_rate_m3s` (0.0); `to_dict` and `from_dict` carry all of them. The module says exhaust ventilators are not part of the ventilation system and are added to the Room like appliances | Tag is the display name, the record id the identifier; flow stored in m³/h (the `airflow` quantity) and written as m³/s; runtime in minutes a year; `user_data` carried |
| Same file, `ExhaustVentKitchenHood`, `ExhaustVentDryer`, `ExhaustVentUserDefined` and `PhExhaustDeviceBuilder` | Three subclasses that add nothing but their display name default; the builder reloads by `device_class_name` | The three types D4-35 offers, stored as `kitchen_hood`, `dryer` and `user_defined` |
| `honeybee_phhvac/supportive_device.py`, `PhSupportiveDevice` | As P4-10 read it: `device_type` 10 by default with usage profile 1 (all year), `quantity`, `in_conditioned_space`, `norm_energy_demand_W`, `annual_period_operation_khrs`, `ihg_utilization_factor` (1.0) | The linked device: type 10, the fan's quantity, power, in conditioned space and operation; factor and profile left at the class's |
| `honeybee_phhvac/properties/room.py`, `add_exhaust_vent_device`, `add_supportive_device` | Each adds to its own set on the Room, written sorted by identifier | One call of each per fan serving the Room |
| `honeybee_phhvac/properties/model.py`, `_build_mechanical_devices_from_dict` | The Model's reload keys `exhaust_vent_devices` and `supportive_devices` in two separate maps, each by identifier, keeping the last | The two objects of one fan share the fan's identifier without colliding; each row records each object's digest for `conformance` (CONTRACTS section 8, question 2) |

The Grasshopper components (`honeybee_grasshopper_ph`, `gh_compo_io/hvac/create_exhaust_vent.py` and
`add_exhaust_vent.py`, read in the local checkout at `8967c64`; not vendored) offer `1-Dryer`, `2-Kitchen Hood` and
`3-User Defined`, take the flow in m³/s and the annual runtime in minutes (0 when blank), leave `quantity` at the
class's 1, and add the same object to every chosen Room. A fan's electricity is a separate supportive device the user
builds with P4-10's component; no component links the two.

Read in PHX 1.59.4: `from_HBJSON/create_variant.py`, `add_exhaust_vent_devices_from_hb_rooms`, walks each Room's
Spaces, reads each Space's exhaust ventilators through its host Room, and adds a device to every simulated Zone of the
Variant unless one with its key (the identifier) is already there; `create_hvac.py`, `build_phx_exhaust_vent_device`,
builds a `PhxExhaustVentilatorRangeHood`, `PhxExhaustVentilatorDryer` or `PhxExhaustVentilatorUserDefined` and copies
the display name, the flow (m³/s times 3600) and the runtime. It does not copy `quantity`: a probe on 2026-11-24 with a
kitchen hood of quantity 3 gave a PHX device of quantity 1. Supportive devices reach the Variant's mechanical
collection as P4-10 traced. So in PHX one fan becomes one exhaust device on each simulated Zone and, with Power, one
supportive device; a Room with no Spaces contributes neither. The round trip proves both, and asserts the exhaust
quantity only in the HBJSON (D4-25).

## Inferred in planning

None of these is a choice of behavior the sources leave open in a way that changes the work; each follows the stub,
D4-35, the pattern, honeybee-ph or its Grasshopper components. The one with a consequence for results is marked for
Ed.

- **The type** is `exhaust_type`, one of `kitchen_hood`, `dryer` and `user_defined`, default `user_defined` (D4-35),
  labelled Kitchen hood, Dryer and User-defined; the Python section maps each to its honeybee-ph class.
- **Flow** is `exhaust_flow_rate_m3h`, m³/h in the `airflow` quantity (cfm under IP), 0 by default (the class's),
  written as `exhaust_flow_rate_m3s` (divided by 3600) once, in Python.
- **Runtime** is `annual_runtime_minutes`, minutes a year, 0 by default (the class's and the component's). It shows in
  a new `annual_minutes` quantity, `min/yr` and unconverted under IP like P4-10's `kilohours`, so the regional number
  format applies. It changes the shared unit registries, so the Design System re-sync P4-10 owes covers it too.
- **Power** is `norm_energy_demand_w` in P4-10's `electric_power` quantity, absent on create. Absent means no linked
  supportive device (D4-35); 0 W is filled and writes a device drawing nothing.
- **Operation** follows the runtime: the stored `annual_period_operation_khrs` is an override, absent by default, and
  absent means `annual_runtime_minutes / 60,000` (D4-35). The export resolves it in Ruby (`Fans.annual_period_operation_khrs`)
  and sends the resolved value; the read row adds `annual_period_operation_khrs_default`, the value the runtime gives,
  so the disclosure shows it, as P4-10's `ihg_usage_profile_default` does.
- **In conditioned space** is `in_conditioned_space`, default true (D4-35). It and the override are stored whatever
  Power holds and export only with it.
- **The linked device's quantity is the fan's.** honeybee-ph describes both classes' `quantity` as the number of
  identical devices, so a record standing for three hoods draws three times its Power. PHX keeps the supportive device's
  quantity and drops the exhaust ventilator's (above). *For Ed:* this is the one inferred value that changes exported
  energy.
- **The linked device's identifier is the fan's id**, shared with its exhaust ventilator (D4-01: objects under the
  item's identifier). honeybee-ph and PHX keep the two in separate collections. Its utilization factor (1.0) and usage
  profile (1, all year, from type 10) stay at the class's: D4-35 offers neither.
- The kind's label is **Fan**; kind id `ph_composer.mechanical.fan`, prefix `fan` (free), operations and snapshot
  section `ph_composer.mechanical.fans`, export section `ph_composer.mechanical.export.fans`.
- **The finding** is P4-10's `mechanical.zone_without_spaces` from `ExportZones.spaceless_findings` with the slot
  `fan_ids` and the label Fan. The live Spaces read that feeds it (`PumpExport.spaced`, written for the pump slot) and
  the export's set of Zones with Spaces move to `ExportZones`, taking the slot, and both exports call them. The code's
  description and the preflight's name both families.
- The pill is **Fans**; the subtab's order is 50, after Pumps (40) and before Electric Heating, D4-13's order.
- The family reports the shared item findings, `mechanical.item_unserved`, `mechanical.zone_left_out`,
  `mechanical.item_across_segments` and `mechanical.item_missing` (blocking), as the Pump does. A Zone with no Fan gets
  no finding.
- `user_data` is carried to both objects, which round-trip it; a row in `docs/USER_DATA.md` (F36).
- `conformance` checks only exhaust ventilators and supportive devices whose identifier is a Fan id, so the Pump
  section's devices on the same Room pass; and refuses a Room holding a Fan-id supportive device whose row reports no
  Power.
- The disclosure reuses `optional_values.js`: `In conditioned space` is a choice of Yes and No with no blank, default
  Yes; the override is a blank-allowed `kilohours` field whose empty input shows the value the runtime gives. The part
  gains that placeholder; it is a Mechanical part, not a kit part.
- No Colour-by mode (a list slot, as for Pumps). No export report section.

## Steps

1. **The kind (D4-20, D4-35).** `features/mechanical/fans/schema.rb`: `FAN_KIND`, the fields above with the source
   snapshot, `DEFAULTS` (`exhaust_type` `user_defined`, `quantity` 1, `exhaust_flow_rate_m3h` 0.0,
   `annual_runtime_minutes` 0.0, `in_conditioned_space` true), `annual_period_operation_khrs(values)`,
   `Records::RecordKind` schema version 1; `fans/reads.rb` with the default operation on each row. Persistence through
   `CatalogOperations` unchanged, and reads through `DefinitionLists` with Serves' `usage`. Nothing in the folder names
   Zones, Spaces, Programs or `serves/` (`tests/mechanical_dependency_test.rb`).
2. **The Serves slot.** `serves/payload.rb`: `fan_ids`, `many`, to `ph_composer.mechanical.fan`; payload
   `schema_version` 6. Assign adds a fan beside those a Zone holds; Clear with `item_id` takes one out; the kind's
   delete moves or empties every Zone's list through `Serves::Operations.delete`, one Undo step. The `serves.assign`
   description names the list slots.
3. **Declarations.** `declarations/fans.rb`: the kind, `fans.list`, `.all` and the snapshot section, `.create`,
   `.update`, `.duplicate` and `.delete` (with `replacement_id`, null emptying the Zones' lists), registered after
   Pumps in `install.rb`. API minor bump with one `API::CHANGES` row; `docs/AGENT_GUIDE.md` and the shipped guide gain
   a "Fans" recipe; `context/AGENT_INTERFACE.md`; `make fixtures`.
4. **The plan (F35).** `fan_plan.rb`, pure: one pair per (fan, exported Zone) whose `fan_ids` names it,
   `{id, item_id, zone_id, identifier, display_name, exhaust_type, quantity, exhaust_flow_rate_m3h,
   annual_runtime_minutes, norm_energy_demand_w, in_conditioned_space, annual_period_operation_khrs, user_data}` under
   the fan id (D4-01), Power null when blank and the operation resolved; the shared item findings; a Zone naming a fan
   not in the Model (`mechanical.item_missing`, blocking); and `ExportZones.spaceless_findings` over the exported Zones
   with no Spaces.
5. **The shared Spaces read.** `export_zones.rb` gains the export's set of Zones with a Space (from Spaces'
   projection) and the preflight's live read (from `ph_composer.spaces.all`, a Space inside a left-out Zone leaving
   with it, read only while an exported Zone's slot names an item, nil when it refuses), both taking the slot;
   `PumpExport` calls them instead of its own. `codes.rb` and the preflight description name Pumps and Fans.
6. **Export, preflight and Locate.** `fan_export.rb`: the contributor, requiring the Zones section, the Ventilator
   export and Spaces' section, its notes and blocking findings as the Pump export's, `preflight_rows` (unreadable fans
   and their metadata problems first). `Preflight::FAMILIES` gains it; `Locate::ITEMS` gains `fan_ids`, which the panel
   table accepts.
7. **Python (D4-25).** `FanSection` in `mechanical_sections.py` and `FanRecord` in `contract/mechanical_records.py`:
   `translate` builds a fresh exhaust ventilator of the type's class with the identifier, the Tag as display name,
   quantity, runtime, flow in m³/s and `user_data`, and, when Power is filled, a fresh `PhSupportiveDevice` with the
   same identifier and name, `device_type` 10, the quantity, power, operation, in conditioned space and `user_data`;
   `attach` at `ROOM` calls `add_exhaust_vent_device` once per fan and `add_supportive_device` once per fan with Power;
   `required_for_export = True`; result rows `fans` with the exhaust digest and the supportive device's (null without
   Power); `conformance` reads back each Room's Fan-id exhaust ventilators and supportive devices by identifier against
   its own rows and refuses a Room holding a Fan-id object the run did not report. Registered in `composition.py` after
   the Pump section.
8. **The Fans subtab (D4-13, D4-20, D4-30, D4-35).** `html/features/mechanical/fans.js`: one `EquipmentTable` with
   Tag, `Type` (a choice of the three), `Quantity`, `Flow` (airflow), `Runtime` (min/yr), `Power` (W, blank allowed),
   `Serves` (Zone chips and the `many` Zone picker), hideable Manufacturer, Model and Notes; a row action opening the
   electric values (In conditioned space; Operation, blank for "from runtime"), pressed while either differs from its
   default; New asks for the Tag; Duplicate; Delete with a replacement or clearing the Zones; Locate's narrowing by
   `fan_ids`. The `annual_minutes` quantity joins `unit_tables.js`, `fields.js` and `core/units.rb`. Added to
   `index.html`, the panel manifest and the preview (`tools/ui-preview/host.js`, `fixtures.js`,
   `mechanical_checks.cjs`); the runtime manifest is refreshed.
9. **Documents.** `context/CONTRACTS.md` (the kind, Serves schema 6, the export section after the Pump export, the
   finding naming Fans), the packet CONTRACTS (sections 2, 3 and 6), `context/UBIQUITOUS_LANGUAGE.md` (a Fan row; the
   Mechanical tab row), `docs/PRODUCT.md` (an "Add fans" section; the subtab list), `docs/USER_DATA.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/mechanical/pumps/`, `pump_plan.rb`, `pump_export.rb` (P4-10) | The one-kind family with a list slot, per-pair export and the no-Spaces finding |
| `features/mechanical/catalog_operations.rb`, `export_zones.rb`, `serves/` | The shared CRUD, the list slot, the item findings and the shared Spaces read |
| `html/features/mechanical/equipment_table.js`, `pumps.js`, `optional_values.js` | The table, the list picker, the per-row disclosure |
| honeybee-ph `honeybee_phhvac/ventilation.py`, `supportive_device.py`, `properties/room.py` (pinned 1.33.68) | The three exhaust ventilator classes, `PhSupportiveDevice`, `add_exhaust_vent_device`, `add_supportive_device` |

## Tests (write first)

1. Ruby (`tests/mechanical_fan_test.rb`): a fan created with only a Tag is a user-defined exhaust of quantity 1, 0 m³/h
   and 0 minutes, no Power, in conditioned space and no operation override, whose resolved operation is 0; a runtime of
   60,000 minutes resolves 1.0 kh and an override of 2.5 keeps 2.5; a type outside the three, a quantity below 1 and a
   negative flow, runtime, power or override refuse `params.invalid`; a taken Tag refuses; guarded update, duplicate
   with `user_data`; a fan on two Zones and two fans on one Zone through `serves.assign`; Clear with `item_id`; a plain
   delete while a Zone names it refuses `reference.in_use`; delete with a replacement moves every Zone's list (kept
   once) and delete with null empties it, each one Undo step that Undo restores.
2. Plan and export (`tests/mechanical_fan_export_test.rb`): one pair per (fan, exported Zone) under the fan id with
   the operation resolved and Power null when blank; two fans on one Zone give two pairs; an unserved fan, a served Zone
   in no Building Segment and a fan on two Segments give their shared findings, never blocking; a Zone naming a fan not
   in the Model blocks; a fan on a Zone with no Space gives `mechanical.zone_without_spaces`, not blocking, its pair
   still written; the preflight's rows carry the same code, section and object as the export's notes; `user_data`
   reaches the pair; the Pump export's tests pass unchanged through the lifted Spaces read. The golden
   (`tests/fixtures/mechanical/fan_extraction.json`) feeds the Python tests.
3. Python (`tests/python/test_fan_sections.py`): each record builds the exhaust ventilator of its type with its
   identifier, display name, values (flow in m³/s) and `user_data`; a record with Power also builds a type 10
   `PhSupportiveDevice` under the same identifier with the quantity, power, operation and in conditioned space; one
   without builds none; two fans on one Room give two exhaust ventilators; the HBJSON reloads with each Room's devices;
   `conformance` refuses a Room whose fan differs from its row's digest, a Room missing a reported fan or its
   supportive device, a Room holding a Fan-id supportive device for a row without Power, and a Room holding a Fan id the
   run did not report, and passes a Pump's supportive device on the same Room.
4. PHX round trip (`tests/python/test_fans_phx_round_trip.py`, `phx` group): two Rooms with Spaces in one Segment, a
   kitchen hood with Power on both and a dryer without Power on one, give two exhaust devices on the simulated Zone,
   each once, with their class, flow (m³/h within a tolerance) and runtime and their Tags as names, and one supportive
   device, the hood's, with its type 10, quantity, watts and kilohours: one record becomes two objects with Power and
   one without; a fan on a Room with Spaces and a Room without still reaches PHX once; a fan only on a Room with no
   Spaces gives none.
5. Panel (`tests/mechanical_fan_panel_test.js`): the Fans subtab and its pill; a type change sends `fans.update` with
   its `expected_values`; a negative flow, runtime or power is refused before it is sent, and a blank Power sends null;
   the disclosure shows In conditioned space and the operation from runtime as the empty field's placeholder, sends an
   override and a blank as null, and its action is pressed while a value differs from its default; the Serves chips
   open the `many` picker; Locate narrows to `fan_ids`. `make ui-checks` runs the Mechanical script over the new table at
   the three panel sizes.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M11` in `planning/native-acceptance/cases.json`. Offline `make ci`,
browser checks and the PHX round trip pass on this stage's PR.

## Out of scope

A bare fan with no exhaust air (a Pumps-tab Other device, Q6). A Zone with no Fan. A Colour-by mode for the list slot.
Editing the linked device's utilization factor or usage profile. Compensating for PHX's dropped exhaust quantity. The
Serves keyboard focus lost after a save, which P4-09 reported across the tables with a Serves column (a follow-up of
its own).

## Done when

- M11 has offline evidence in `../evidence/p4-11-fans.md`, with the UI polish review recorded; host verification lands
  in `MS3`.
- `make ci` passes on both Rubies; the panel and vendor manifests are current.
