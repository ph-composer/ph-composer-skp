# P4-10: pumps

DATE: 2026-10-21
STATUS: Planned in full 2026-11-24 from the stub of 2026-10-21, D4-13, D4-20, D4-25, D4-30, D4-31 and D4-34, and the [equipment PRD](../equipment/PRD.md), "Family 5". Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host gate runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-07 (merged, #570) and the pumps interview (D4-34, 2026-11-23), with D4-13, D4-20, D4-25, D4-30 and D4-31.
Stacks on P4-09's branch while #573 is open; it adds to the same registration lists and the Serves payload after
P4-09's slot.

Owns family 5 end to end:

- One flat catalog kind, the Pump (`ph_composer.mechanical.pump`, `pmp`), and its operations.
- The `pump_ids` (`many`) Serves slot on the Zone record, moving the Serves payload's `schema_version` from 4 to 5
  (F34).
- The `ph_composer.mechanical.export.pumps` export section: one `PhSupportiveDevice` per (pump, served Zone) pair,
  added to the Room through `add_supportive_device`, with its preflight rows, conformance and a PHX round trip
  (D4-25).
- A non-blocking finding when a Pump serves an exported Zone with no Spaces (D4-34), shaped so P4-11's Fans report
  the same finding with the same code and helper (D4-35).
- The `Pumps` subtab on the Mechanical tab with one pill, `Pumps` (D4-13), built on the shared `EquipmentTable`
  (D4-30), the two internal heat gain values behind a collapsed per-row disclosure (D4-34).

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Family 5", and
[DECISIONS, Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23) (D4-34). Names:
[CONTRACTS](../CONTRACTS.md) sections 2, 3 and 6. Pattern: the Electric Heater (one kind, a `many` slot, one object
per (item, Zone) pair under the item's identifier) with the Ventilator's per-row disclosure. Load
`.agents/skills/ph-composer-ui-polish/SKILL.md` before building the screen.

Paths are relative to `src/ph_composer/`.

## What the sources settle

Read in the pinned wheel `vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl`:

| Source | What it says | This stage |
| --- | --- | --- |
| `honeybee_phhvac/supportive_device.py`, `PhSupportiveDevice` | `identifier`, `display_name`, `user_data` (from `_PhHVACBase`), `device_type` (default 10), `quantity` (1), `in_conditioned_space` (True), `norm_energy_demand_W` (1.0), `annual_period_operation_khrs` (8.76), `ihg_utilization_factor` (1.0, 0 to 1) and `ihg_usage_profile`; `to_dict` and `from_dict` carry all of them | Tag is the display name, the record id the identifier, the other seven are stored, `user_data` carried |
| Same file, `device_type` setter and `default_ihg_usage_profile` | Setting `device_type` re-seeds `ihg_usage_profile` from it: 4 gives 2 (winter), 6 and 7 give 4 (none, booked in hot water distribution), 10 and any other give 1 (all year). The comment says an explicit profile must be set after the type | The Python section sets `device_type` first and the profile after it |
| `honeybee_phhvac/properties/room.py`, `add_supportive_device` | Adds to the Room's set of supportive devices; a Room may hold several, written sorted by identifier | One call per pump serving the Room |
| `honeybee_phhvac/properties/model.py` | The Model's reload keys supportive devices by identifier and keeps the last, as it does heating systems | Each result row records its object's digest at translation for `conformance` to compare per Room (CONTRACTS section 8, question 2) |

The Grasshopper component (`honeybee_grasshopper_ph`, `gh_compo_io/hvac/create_supportive_device.py` and
`add_supportive_devices.py`, read in the local checkout at `8967c64`; not vendored) offers the four types as
`4-Heat Circulation Pump`, `6-DHW Circulation Pump`, `7-DHW Storage Pump` and `10-Other / Custom`, defaults
`norm_energy_demand_W` to 0.0, `annual_period_operation_khrs` to 8.76 and `ihg_utilization_factor` to 1.0, and
derives the profile from the type when its input is blank, or sets the given one. It adds the same object to every
chosen Room.

Read in PHX 1.59.4 (`from_HBJSON/create_variant.py`, `add_supportive_devices_from_hb_room`;
`from_HBJSON/create_hvac.py`, `build_phx_supportive_device`): PHX walks each Room's Spaces, reads each Space's
supportive devices through its host Room, skips a key already in the Variant's collection and builds one
`PhxSupportiveDevice` with every field above. Then `merge_all_devices` groups by identifier, so one pump on several
Rooms of a Segment is one device. A Room with no Spaces contributes none; a pump that serves it and a Room with
Spaces in the same Segment still reaches PHX through the other Room. The round trip proves both (D4-25).

## Inferred in planning

None of these is a choice of behavior the sources leave open in a way that changes the work; each follows the
pattern, honeybee-ph or its Grasshopper component.

- **The IHG profile is stored as an override.** `ihg_usage_profile` is an integer 1 to 4 or null, null by default,
  and null means "from the device type", as the Grasshopper component reads a blank input. Changing the type of a
  pump with no override changes its profile with it, which is honeybee-ph's re-seeding; an override the user set
  stays. The export resolves it in Ruby (`Pumps.ihg_usage_profile`) and sends the resolved value. The read row adds
  `ihg_usage_profile_default`, the profile the type gives, so the disclosure shows it without a copy of the table in
  JavaScript.
- **`in_conditioned_space` is on the row.** D4-34 does not name it, but the PRD's family 5 lists it, the class
  carries it, PHX copies it and D4-20 puts the fields that export on the row. Default true (the class's). D4-34 puts
  only the two IHG values behind the disclosure.
- **Power defaults to 0 W**, the Grasshopper component's default (the class's is 1.0), so New asks only for the Tag
  and a new pump adds no energy until its power is entered. Power is shown in W under both unit systems, as WUFI-Passive
  and METr take a pump's electrical input; it uses no unit quantity (the `power` quantity converts to Btu/h).
- **Operation** is `annual_period_operation_khrs`, kilohours a year, 8.76 by default (the whole year), a plain number.
- The kind's label is **Pump**; kind id `ph_composer.mechanical.pump`, prefix `pmp` (free), operations and snapshot
  section `ph_composer.mechanical.pumps`, export section `ph_composer.mechanical.export.pumps`. Stored field names
  follow the class with an SI suffix: `device_type`, `quantity`, `in_conditioned_space`, `norm_energy_demand_w`,
  `annual_period_operation_khrs`, `ihg_utilization_factor`, `ihg_usage_profile`.
- Type labels follow the glossary's "hot water" for DHW: Heating circulation pump (4), Hot water circulation pump
  (6, the default), Hot water storage load pump (7), Other (10). Profile labels: All year (1), Winter (2), Summer (3),
  None (hot water) (4).
- **The finding** is `mechanical.zone_without_spaces`, a warning, one per (item, exported Zone with no Space) on the
  item's row, from a helper in `ExportZones` that takes the family's slot and label, so Fans call it with theirs. A
  Zone has no Spaces when no Space record names it, which is what PHX walks (a Space with no Volume still exports a
  honeybee-ph Space, with Spaces' own `space.empty`). The preflight counts Spaces from `ph_composer.spaces.all`
  (`space_count`); the export reads Spaces' projection, which gains `space_count` and a row for every exported Zone
  holding a Space, Volume or not. Programs reads that projection's totals with zero defaults, so a row with no Volume
  reads as before.
- The pill is **Pumps**; the subtab's order is 40, after Hot Water (30) and before Fans (50) and Electric Heating (60),
  D4-13's order.
- The family reports the shared item findings, `mechanical.item_unserved`, `mechanical.zone_left_out`,
  `mechanical.item_across_segments` and `mechanical.item_missing` (blocking), as the Electric Heater does. A Zone with
  no Pump gets no finding.
- `user_data` is carried to the `PhSupportiveDevice`, which round-trips it; a row in `docs/USER_DATA.md` (F36).
- `conformance` checks only supportive devices whose identifier is a Pump id, so P4-11's Fans can add their own
  supportive devices to the same Rooms.
- The disclosure extends the shared `optional_values.js` with a choice field and a per-field default (the action is
  pressed while a value differs from its default), in a shape P4-11's boolean and runtime override can use. It is a
  Mechanical part, not a kit part, so no Design System re-sync follows.
- No Colour-by mode (a list slot, as for heat pump indoor units and Electric Heaters). No export report section.

## Steps

1. **The kind (D4-20, D4-34).** `features/mechanical/pumps/schema.rb`: `PUMP_KIND`, the fields above with the source
   snapshot, `DEFAULTS` (`device_type` 6, `quantity` 1, `in_conditioned_space` true, `norm_energy_demand_w` 0.0,
   `annual_period_operation_khrs` 8.76, `ihg_utilization_factor` 1.0), `DEFAULT_IHG_USAGE_PROFILE` by type and
   `ihg_usage_profile(values)`, `Records::RecordKind` schema version 1. Persistence through `CatalogOperations`
   unchanged, and reads through `DefinitionLists` with Serves' `usage`. Nothing in the folder names Zones, Spaces,
   Programs or `serves/` (`tests/mechanical_dependency_test.rb`).
2. **The Serves slot.** `serves/payload.rb`: `pump_ids`, `many`, to `ph_composer.mechanical.pump`; payload
   `schema_version` 5. Assign adds a pump beside those a Zone holds; Clear with `item_id` takes one out; the kind's
   delete moves or empties every Zone's list through `Serves::Operations.delete`, one Undo step. The `serves.assign`
   description names the list slots.
3. **Declarations.** `declarations/pumps.rb`: the kind, `pumps.list`, `.all` and the snapshot section, `.create`,
   `.update`, `.duplicate` and `.delete` (with `replacement_id`, null emptying the Zones' lists), registered after
   Electric Heaters in `install.rb`. API minor bump with one `API::CHANGES` row; `docs/AGENT_GUIDE.md` and the
   shipped guide gain a "Pumps" recipe; `context/AGENT_INTERFACE.md`; `make fixtures`.
4. **The plan (F35).** `pump_plan.rb`, pure: one pair per (pump, exported Zone) whose `pump_ids` names it,
   `{id, item_id, zone_id, identifier, display_name, device_type, quantity, in_conditioned_space,
   norm_energy_demand_w, annual_period_operation_khrs, ihg_utilization_factor, ihg_usage_profile, user_data}` with
   the profile resolved, under the pump id (D4-01); the shared item findings; a Zone naming a pump not in the Model
   (`mechanical.item_missing`, blocking); and `ExportZones.spaceless_findings` over the exported Zones with no Spaces.
5. **The no-Spaces finding.** `codes.rb` gains `mechanical.zone_without_spaces`. `ExportZones.spaceless_findings
   (exported, items, slot, label, spaced)` gives one non-blocking finding per (item, served exported Zone not in
   `spaced`). Spaces' projection (`features/spaces/export.rb`, `zone_totals`) gains `space_count` and a row for every
   exported Zone holding a Space.
6. **Export, preflight and Locate.** `pump_export.rb`: the contributor, requiring the Zones section, the Ventilator
   export and Spaces' section, its notes and blocking findings as the Electric Heater export's, `preflight_rows`
   (unreadable pumps and their metadata problems first, the Zones with Spaces from `ph_composer.spaces.all`).
   `Preflight::FAMILIES` gains it; `Locate::ITEMS` gains `pump_ids`, which the panel table accepts.
7. **Python (D4-25).** `PumpSection` in `mechanical_sections.py` and `PumpRecord` in `contract/mechanical_records.py`:
   `translate` builds a fresh `PhSupportiveDevice` with the identifier, the Tag as display name, `device_type` before
   `ihg_usage_profile`, the other values and `user_data`; `attach` at `ROOM` calls `add_supportive_device` once per
   object; `required_for_export = True`; result rows `pumps` with each object's digest; `conformance` reads back each
   Room's Pump-id supportive devices by identifier against its own rows' digests and refuses a Room holding a Pump id
   the run did not report. Registered in `composition.py` after the Electric Heater section.
8. **The Pumps subtab (D4-13, D4-20, D4-30, D4-34).** `html/features/mechanical/pumps.js`: one `EquipmentTable` with
   Tag, `Type` (a choice of the four), `Quantity`, `Power` (W), `Operation` (kh/yr), `In conditioned space`, `Serves`
   (Zone chips and the `many` Zone picker), hideable Manufacturer, Model and Notes; a row action opening the internal
   heat gain values (Utilization factor, a fraction; Usage profile, a choice of "From type (its label)" and the four),
   pressed while either differs from its default; New asks for the Tag; Duplicate; Delete with a replacement or
   clearing the Zones; Locate's narrowing by `pump_ids`. `optional_values.js` gains the choice field and defaults.
   Added to `index.html`, the panel manifest and the preview (`tools/ui-preview/host.js`, `fixtures.js`,
   `mechanical_checks.cjs`); the runtime manifest is refreshed.
9. **Documents.** `context/CONTRACTS.md` (the kind, Serves schema 5, the export section after the Electric Heater
   export, the new finding and the Spaces projection's `space_count`), the packet CONTRACTS (sections 2, 3 and 6),
   `context/UBIQUITOUS_LANGUAGE.md` (a Pump row; the Mechanical tab row), `docs/PRODUCT.md` (an "Add pumps" section;
   the subtab list), `docs/USER_DATA.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/mechanical/electric_heaters/`, `electric_heater_plan.rb`, `electric_heater_export.rb` (P4-09) | The one-kind family with a list slot and per-pair export |
| `features/mechanical/catalog_operations.rb`, `export_zones.rb`, `serves/` | The shared CRUD, the list slot and the item findings |
| `features/spaces/export.rb` (`zone_totals`) | Gains `space_count` for the no-Spaces finding |
| `html/features/mechanical/equipment_table.js`, `electric_heaters.js`, `ventilators.js`, `optional_values.js` | The table, the list picker, the per-row disclosure |
| honeybee-ph `honeybee_phhvac/supportive_device.py`, `properties/room.py` (pinned 1.33.68) | `PhSupportiveDevice`, `add_supportive_device` |

## Tests (write first)

1. Ruby (`tests/mechanical_pump_test.rb`): a pump created with only a Tag takes type 6, quantity 1, 0 W, 8.76 kh,
   in conditioned space, factor 1.0 and no profile override, whose resolved profile is 4; a type outside the four, a
   profile outside 1 to 4, a factor outside 0 to 1, a quantity below 1 and a negative power refuse `params.invalid`;
   a taken Tag refuses; a pump with no override changing type 6 to 4 resolves profile 2, and one with override 3 keeps
   3; guarded update, duplicate with `user_data`; a pump on two Zones and two pumps on one Zone through
   `serves.assign`; Clear with `item_id`; a plain delete while a Zone names it refuses `reference.in_use`; delete with
   a replacement moves every Zone's list (kept once) and delete with null empties it, each one Undo step that Undo
   restores.
2. Plan and export (`tests/mechanical_pump_export_test.rb`): one pair per (pump, exported Zone) under the pump id with
   the resolved profile; two pumps on one Zone give two pairs; an unserved pump, a served Zone in no Building Segment
   and a pump on two Segments give their shared findings, never blocking; a Zone naming a pump not in the Model
   blocks; a pump on a Zone with no Space gives `mechanical.zone_without_spaces`, not blocking, its pair still
   written, and a pump on a Zone whose one Space has no Volume gives none; the preflight's rows carry the same code,
   section and object as the export's notes; `user_data` reaches the pair. The golden
   (`tests/fixtures/mechanical/pump_extraction.json`) feeds the Python tests.
3. Python (`tests/python/test_pump_sections.py`): each record builds a `PhSupportiveDevice` with its identifier,
   display name, values and `user_data`, the profile override surviving the type; two pumps on one Room give two
   devices; the HBJSON reloads with each Room's devices; `conformance` refuses a Room whose pump differs from its own
   row's digest, a Room missing a reported pump and a Room holding a Pump id the run did not report, and passes a
   supportive device of another identifier.
4. PHX round trip (`tests/python/test_pumps_phx_round_trip.py`, `phx` group): two Rooms with Spaces in one Segment,
   one pump on both and a second on one, give two `PhxSupportiveDevice`, each once, with their type, quantity, watts,
   kilohours, factor and profile and their Tags as names; a pump on a Room with Spaces and a Room without gives one
   device; a pump only on a Room with no Spaces gives none.
5. Panel (`tests/mechanical_pump_panel_test.js`): the Pumps subtab and its pill; a type change sends `pumps.update`
   with its `expected_values`; a power below 0 is refused before it is sent; the disclosure shows the profile from the
   type, sends an override and a return to "From type" as null, and its action is pressed while a value differs from
   its default; the Serves chips open the `many` picker; Locate narrows to `pump_ids`. `make ui-checks` runs the
   Mechanical script over the new table at the three panel sizes.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M10` in `planning/native-acceptance/cases.json`. Offline `make ci`,
browser checks and the PHX round trip pass on this stage's PR.

## Out of scope

Fans and their linked supportive device (P4-11). A Zone with no Pump. A Colour-by mode for the list slot. The Serves
keyboard focus lost after a save, which P4-09 reported across the three tables with a Serves column (a follow-up of
its own).

## Done when

- M10 has offline evidence in `../evidence/p4-10-pumps.md`, with the UI polish review recorded; host verification
  lands in `MS3`.
- `make ci` passes on both Rubies; the panel and vendor manifests are current.
