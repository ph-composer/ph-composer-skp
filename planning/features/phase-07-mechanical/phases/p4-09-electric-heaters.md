# P4-09: electric heaters

DATE: 2026-10-21
STATUS: Planned in full 2026-11-24 from the stub of 2026-10-21, D4-13, D4-20, D4-25, D4-30, D4-31 and D4-33, and the [equipment PRD](../equipment/PRD.md), "Family 4". Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host gate runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-07 (merged, #570) and the electric heaters interview (D4-33, 2026-11-23), with D4-13, D4-20, D4-25,
D4-30 and D4-31. Stacks on P4-08b's branch while #572 is open; it touches none of P4-08b's files beyond the shared
registration lists.

Owns family 4 end to end, the smallest family:

- One flat catalog kind, the Electric Heater (`ph_composer.mechanical.electric_heater`, `ehr`), and its operations.
- The `heater_ids` (`many`) Serves slot on the Zone record, moving the Serves payload's `schema_version` from 3 to 4
  (F34).
- The `ph_composer.mechanical.export.electric_heaters` export section: one `PhHeatingDirectElectric` per (heater,
  served Zone) pair, added to the Room through `add_heating_system`, with its preflight rows, conformance and a PHX
  round trip (D4-25).
- The `Electric Heating` subtab on the Mechanical tab with one pill, `Heaters` (D4-13), built on the shared
  `EquipmentTable` (D4-30).

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Family 4", and
[DECISIONS, Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23) (D4-33). Names:
[CONTRACTS](../CONTRACTS.md) sections 2, 3 and 6. Pattern: the Ventilator (one kind, Serves on the kind itself,
one object per (item, Zone) pair under the item's identifier) with the heat pump indoor unit's `many` slot and
picker. Load `.agents/skills/ph-composer-ui-polish/SKILL.md` before building the screen.

Paths are relative to `src/ph_composer/`.

## What the sources settle

Read in the pinned wheel `vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl`:

| Source | What it says | This stage |
| --- | --- | --- |
| `honeybee_phhvac/heating.py`, `PhHeatingSystem` | `identifier`, `display_name`, `user_data` (from `_PhHVACBase`), `heating_type` (the class name) and `percent_coverage`, default 1.0; `to_dict` and `from_dict` carry all five | Tag is the display name, the record id the identifier, `percent_coverage` stored 0.0 to 1.0 with default 1.0 (D4-33), `user_data` carried |
| `honeybee_phhvac/heating.py`, `PhHeatingDirectElectric` | Adds nothing to the base. The module's other classes (fossil and wood boilers, district) are out of scope (equipment Q7) | The only class this stage builds |
| `honeybee_phhvac/properties/room.py`, `add_heating_system` | Adds to the Room's set of heating systems; a Room may hold several, written sorted by identifier | One call per heater serving the Room; several heaters on one Zone give several systems |
| `honeybee_phhvac/properties/model.py` | The Model's reload keys heating systems by identifier and keeps the last, as it does heat pumps | Each result row records its object's digest at translation for `conformance` to compare per Room (CONTRACTS section 8, question 2) |

The Grasshopper component (`honeybee_grasshopper_ph`, `gh_compo_io/hvac/create_space_conditioning_sys.py` and
`add_systems.py`, read in the local checkout at `8967c64`; not vendored) builds one `PhHeatingDirectElectric` with a
display name and `_percent_bldg_heating_covered` (default 1.0) and adds the same object to every chosen Room. One
record serving several Zones, exported under one identifier, is that shape.

Read in PHX 1.59.4 (`from_HBJSON/create_variant.py`, `add_heating_systems_from_hb_rooms`;
`from_HBJSON/create_hvac.py`, `build_phx_heating_electric`): PHX walks each Room's Spaces, takes each heating
system once by key and builds a `PhxHeaterElectric` whose `usage_profile.space_heating_percent` is the coverage.

## Inferred in planning

None of these is a choice of behavior the sources leave open; each follows the pattern or the code as built.

- The kind's label is **Electric Heater**, after the PRD's family name and the `Electric Heating` subtab (D4-13); the
  stub's "Direct Electric Heater" names honeybee-ph's class, which the export section builds. Kind id
  `ph_composer.mechanical.electric_heater`, prefix `ehr` (free), operations and snapshot section
  `ph_composer.mechanical.electric_heaters`, export section `ph_composer.mechanical.export.electric_heaters`.
- The kind holds `Fields.common` (Tag, Notes), `manufacturer`, `model` and `percent_coverage` (number 0 to 1,
  required, default 1.0). `PhHeatingDirectElectric` has no `in_conditioned_space`, so the record has none.
- The pill is **Heaters**, as Hot Water's heater pill reads; the subtab's order is 60, after the Ventilation (10),
  Heat Pumps (20) and Hot Water (30) subtabs, leaving 40 and 50 to Pumps and Fans (D4-13's order).
- No new `mechanical.*` code. The family reports the shared item findings, `mechanical.item_unserved`,
  `mechanical.zone_left_out`, `mechanical.item_across_segments` and `mechanical.item_missing` (blocking), as the
  Ventilator does. A Zone with no Electric Heater gets no finding: D4-33 names none, and a Zone a heat pump heats needs
  none. No coverage-sum check across heaters or families (D4-33).
- `ExportZones.item_findings` reads a single slot; it gains a `many` slot read rather than a third copy beside the heat
  pump plan's.
- `user_data` is carried to the `PhHeatingDirectElectric`, which round-trips it; a row in `docs/USER_DATA.md` (F36).
- No Colour-by mode. `ColourModes` colours a Zone by one item in a single slot; a Zone may hold several heaters, and
  P4-08 added none for its `many` slot either.
- No export report section: only the Ventilator export writes one.

## Steps

1. **The kind (D4-20, D4-33).** `features/mechanical/electric_heaters/schema.rb`: `ELECTRIC_HEATER_KIND`, the
   fields above with the source snapshot, `DEFAULTS = {"percent_coverage" => 1.0}`, `Records::RecordKind` schema
   version 1. Persistence through `CatalogOperations` unchanged (create, update, duplicate, delete), and reads through
   `DefinitionLists` with Serves' `usage` (the Zones each serves and its findings), as the Ventilator's are. Nothing
   in the folder names Zones, Spaces, Programs or `serves/` (`tests/mechanical_dependency_test.rb`).
2. **The Serves slot.** `serves/payload.rb`: `heater_ids`, `many`, to `ph_composer.mechanical.electric_heater`;
   payload `schema_version` 4. Assign adds a heater beside those a Zone holds; Clear with `item_id` takes one out;
   the kind's delete moves or empties every Zone's list through `Serves::Operations.delete`, one Undo step. The
   `serves.assign` description names both list slots.
3. **Declarations.** `declarations/electric_heaters.rb`: the kind, `electric_heaters.list`, `.all` and the snapshot
   section, `.create`, `.update`, `.duplicate` and `.delete` (with `replacement_id`, null emptying the Zones' lists),
   registered after heat pumps in `install.rb`. API minor bump with one `API::CHANGES` row; `docs/AGENT_GUIDE.md`
   and the shipped guide gain an "Electric heaters" recipe; `context/AGENT_INTERFACE.md`; `make fixtures`.
4. **The plan (F35).** `electric_heater_plan.rb`, pure: one pair per (heater, exported Zone) whose `heater_ids`
   names it, `{id, item_id, zone_id, identifier, display_name, percent_coverage, user_data}`, the identifier the
   heater id so every Room it serves carries one object (D4-01); the shared item findings and a Zone naming a heater
   not in the Model (`mechanical.item_missing`, blocking). The preflight and the export read the same plan.
5. **Export, preflight and Locate.** `electric_heater_export.rb`: the contributor, requiring the Zones section and the
   Ventilator export (which claims the Serves payload), its notes and blocking findings as the heat pump export's,
   `preflight_rows` (unreadable heaters and their metadata problems first). `Preflight::FAMILIES` gains it;
   `Locate::ITEMS` gains `electric_heater_ids`, which the panel table accepts.
6. **Python (D4-25).** `ElectricHeaterSection` in `mechanical_sections.py` and `ElectricHeaterRecord` in
   `contract/mechanical_records.py`: `translate` builds a fresh `PhHeatingDirectElectric` with the identifier, the
   Tag as display name, the coverage and `user_data`; `attach` at `ROOM` calls `add_heating_system` once per object
   (several per Room allowed); `required_for_export = True`; result rows `electric_heaters` with each object's digest;
   `conformance` reads back each Room's heating systems by identifier against its own rows' digests and refuses a
   Room holding one the run did not report. Registered in `composition.py` after the heat pump section.
7. **The Electric Heating subtab (D4-13, D4-20, D4-30).** `html/features/mechanical/electric_heaters.js`: one
   `EquipmentTable` with Tag, `Coverage` (the stored fraction shown and entered in percent through the Heaters
   table's `percent` quantity, 0 to 100), `Serves` (Zone chips and the `many` Zone picker, as Units · Indoor),
   hideable Manufacturer, Model and Notes; New asks for the Tag; Duplicate; Delete with a replacement or clearing the
   Zones; Locate's narrowing by `electric_heater_ids`. An unserved heater reads "Serves no Zone" in its Serves cell, as
   a Ventilator does. Added to `index.html`,
   the panel manifest and the preview (`tools/ui-preview/host.js`, `fixtures.js`, `mechanical_checks.cjs`); the
   runtime manifest is refreshed.
8. **Documents.** `context/CONTRACTS.md` (the export section after the heat pump export), the packet CONTRACTS
   (sections 2, 3 and 6), `context/UBIQUITOUS_LANGUAGE.md` (an Electric Heater row; the Mechanical tab row brought up
   to date), `docs/PRODUCT.md` (an "Add electric heaters" section; the Mechanical tab's subtab list), `docs/USER_DATA.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/mechanical/ventilators/`, `ventilation_plan.rb`, `export.rb` (P4-02, P4-04) | The one-kind family and per-pair export |
| `features/mechanical/catalog_operations.rb`, `heat_pump_plan.rb`, `serves/` (P4-08) | The shared CRUD, the `many` slot and its findings |
| `html/features/mechanical/equipment_table.js`, `heat_pump_units.js`, `hot_water_heaters.js` (P4-07, P4-08) | The table, the `many` Serves picker, the coverage percent |
| honeybee-ph `honeybee_phhvac/heating.py`, `properties/room.py` (pinned 1.33.68) | `PhHeatingDirectElectric`, `add_heating_system` |

## Tests (write first)

1. Ruby (`tests/mechanical_electric_heater_test.rb`): a heater created with only a Tag takes coverage 1.0 and no
   Manufacturer or Model; coverage below 0 or above 1 refuses `params.invalid` (the action's schema carries the range); a taken Tag refuses; guarded
   update, duplicate with `user_data`; a heater on two Zones and two heaters on one Zone through `serves.assign`;
   Clear with `item_id` takes one out; a plain delete while a Zone names it refuses `reference.in_use`; delete with a
   replacement moves every Zone's list (a list already holding the replacement keeps it once) and delete with null
   empties it, each one Undo step that Undo restores.
2. Plan and export (`tests/mechanical_electric_heater_export_test.rb`): one pair per (heater, exported Zone) under
   the heater id; two heaters on one Zone give two pairs; two heaters at 100% on one Zone export with no finding
   (D4-33); an unserved heater, a served Zone in no Building Segment and a heater on two Segments give their shared
   findings, never blocking; a Zone naming a heater not in the Model blocks; the preflight's rows carry the same code,
   section and object as the export's notes; `user_data` reaches the pair. The golden
   (`tests/fixtures/mechanical/electric_heater_extraction.json`) feeds the Python tests.
3. Python (`tests/python/test_electric_heater_sections.py`): each record builds a `PhHeatingDirectElectric` with its
   identifier, display name, coverage and `user_data`; two heaters on one Room give two heating systems; the HBJSON
   reloads with each Room's systems; `conformance` refuses a Room whose heater differs from its own row's digest, a
   Room missing a reported heater and a Room holding one the run did not report.
4. PHX round trip (`tests/python/test_electric_heaters_phx_round_trip.py`, `phx` group): two Rooms with Spaces in one
   Segment, one heater on both and a second on one, give two `PhxHeaterElectric` devices, each once, with their
   coverage as `space_heating_percent`.
5. Panel (`tests/mechanical_electric_heater_panel_test.js`): the Electric Heating subtab and its Heaters pill; a
   coverage edit in percent sends `electric_heaters.update` with the fraction and its `expected_values`, a value
   outside 0 to 100 is refused before it is sent and a refused draft is kept; the Serves chips open the `many` picker;
   Locate narrows to `electric_heater_ids`. `make ui-checks` runs the Mechanical script over the new table at the
   three panel sizes.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M09` in `planning/native-acceptance/cases.json`. Offline `make ci`,
browser checks and the PHX round trip pass on this stage's PR.

## Out of scope

Boilers and district heating (equipment Q7). A coverage-sum check across heaters or with heat pumps (D4-33). A
Colour-by mode for the list slot. A finding for a heater serving a Zone with no Spaces, which PHX reads heating
systems through: D4-34 and D4-35 give pumps and fans one, D4-33 does not.

## Done when

- M09 has offline evidence in `../evidence/p4-09-electric-heaters.md`, with the UI polish review recorded; host
  verification lands in `MS3`.
- `make ci` passes on both Rubies; the panel and vendor manifests are current.
