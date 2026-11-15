# P4a-07: Program, Schedule and Equipment Set records

DATE: 2026-11-15
STATUS: Scoped (rewritten after the Programs tab review). Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-06 (the `ph_composer.programs` feature exists). Owns the three catalog kinds, the
residential default and the Model's default Program setting, their operations and reads, and their
library kinds, including the library coordinator's new dependency copy. Panel closed: no screen
(the Programs tab is P4a-11), no Zone assignment (P4a-08), no export (P4a-10).

Behavior: [Phase 4a PRD](../PRD.md), "Programs tab". Names: [CONTRACTS](../CONTRACTS.md) section 5.
Answers: Q4a-02, Q4a-07, Q4a-09, Q4a-13, Q4a-15, Q4a-19, Q4a-22, Q4a-23, Q4a-25, Q4a-33 in
[DECISIONS](../DECISIONS.md). Field sources: [loads and schedules](../research/loads-and-schedules.md)
sections 1 to 8 and 10. Paths are relative to `src/ph_composer/`.

## Steps

1. **Units.** Store every value in the honeybee SI unit its HBJSON field uses (people per m²,
   W/m², m³/s per person and per m², m³/s per Zone, 1/h, m³/s per m² of exterior area at 4 Pa,
   L/h per m², °C), each field with its `x-unit`, so P4a-10 writes values without conversion. The
   panel converts for display (m³/h, IP).
2. **Schedule kind** `ph_composer.programs.schedule` (`sch_`): `name`, `type` (`fractional`,
   `activity`, `temperature`, `ventilation`) and one PH form by type:
   - fractional and activity: `start_h`, `end_h`, `fraction_on`, `fraction_off`;
   - temperature: `value_c` (a constant; setbacks wait for the hourly editor);
   - ventilation: `periods`, exactly four in the order `high`, `standard`, `basic`, `minimum`, each
     `hours` and `fraction`, the hours totalling 24 (Q4a-33);
   - all: `days_per_week` (1 to 7) and `weeks_per_year` (1 to 52).
   A pure Ruby function returns the 24-hour profile and the full-load hours for the editor's strip.
   The honeybee ruleset is written at export (P4a-10).
3. **Program kind** `ph_composer.programs.program` (`pgm_`): `name`, `notes`, and eight load
   sections, each with its Schedule references (Q4a-02):
   - `people`: `people_per_area` or `rule: "phius_residential"`; `occupancy_schedule_id`,
     `activity_schedule_id`; radiant and latent fractions;
   - `lighting`: `watts_per_area` or `rule: "phius_interior"` with `high_efficacy_fraction`;
     `schedule_id`; return air, radiant and visible fractions;
   - `electric_equipment` and `gas_equipment`: `watts_per_area`, `schedule_id`, radiant, latent and
     lost fractions;
   - `service_hot_water`: `flow_per_area` or `rule: "building_america"`; `target_temperature_c`;
     `schedule_id`; sensible and latent fractions;
   - `infiltration`: `flow_per_exterior_area`, `schedule_id`;
   - `ventilation`: `flow_per_person`, `flow_per_area`, `flow_per_zone`, `air_changes_per_hour`,
     `schedule_id` (a ventilation Schedule); method fixed to Sum (Q4a-15);
   - `setpoint`: `heating_c` and `cooling_c`, or `heating_schedule_id` and `cooling_schedule_id`;
     `dehumidify_rh`, `humidify_rh`.
   Each section may carry `source` (the base program a library value came from, Q4a-25). A rule
   load may be switched to a fixed value and back; the rule's inputs are kept.
4. **Equipment Set kind** `ph_composer.programs.equipment_set` (`eqs_`): `name`; `devices` as
   `Records::Part`s, each one of the 14 honeybee-ph `PhEquipment` types (dishwasher, clothes washer,
   clothes dryer, refrigerator, freezer, fridge-freezer, cooktop, Phius MEL, Phius interior,
   exterior and garage lighting, custom annual electric, lighting and MEL) with the common fields
   and its type's own (CONTRACTS section 5, Q4a-36). A per-type field table in
   `features/programs/equipment_types.rb`, from the pinned honeybee-ph `ph_equipment.py` and
   honeybee_grasshopper_ph `create_elec_equip.py`, drives validation, the dialog and export. Device
   operations: `equipment_sets.add_device`, `update_device` (type fixed), `delete_device`, each one
   Undo step, addressed by part id.
5. **Residential default and the Model default.** A frozen definition in code
   (`features/programs/default_program.rb`), from the pinned honeybee-ph rules and schedules. Reads
   never write: while the Model holds no default Program record, reads answer the frozen definition
   under its reserved id. **The first write that touches it materializes it** as an ordinary record
   with `source` naming PH-Composer's default, with its Schedules. A Programs Model setting
   (`ph_composer.programs_settings`, `default_program_id`) names the default; absent means the
   frozen one. Deleting the default Program refuses `programs.default_in_use`.
   `ph_composer.programs.reset_default` rewrites it from the definition, one Undo step (Q4a-23).
6. **Operations** for each kind: create (a free name: "Program 2"), update with guarded
   `expected_values`, rename, duplicate (a "(copy)" name; Schedules shared, not copied), delete
   (guarded by incoming references: Zone assignments, Segment `default_program_id`, the Model
   default, Programs using a Schedule; delete with a named replacement rewrites them). One Undo
   step each. Reads: `programs.all`, `schedules.all`, `equipment_sets.all` with used-by counts.
7. **Library kinds** (Q4a-19, Q4a-22): wire kinds `programs`, `schedules`, `equipment_sets` in
   `docs/LIBRARY_FILE_FORMAT.md`, each with its `kind_descriptor`, wire mapping, fingerprint and
   create, replace and assign callbacks, through the existing coordinator as Materials and Frames.
8. **Dependency copy** (new in the coordinator, `library/copy_participant.rb`, `catalog.rb`): a
   kind declares `dependencies(record) -> [{kind, id}]`; copying a Program also copies each Schedule
   it references in the same proposal, reusing a local copy found by source identity, and remaps
   the references. A missing dependency in the library refuses the copy
   (`library.dependency_missing`, new). Document it in `context/CONTRACTS.md` beside the library
   rules and give Bookshelfing in `context/UBIQUITOUS_LANGUAGE.md` its implemented meaning.
9. **Contract and docs.** Declarations, codes, API minor bump with change note, `make fixtures`;
   an agent guide recipe; a panel-closed walkthrough under `tools/examples/programs/`; glossary rows
   (Program, Schedule, Equipment Set, residential default).

## Source

| File | Disposition |
| --- | --- |
| `features/windows/products/schema.rb`, `operations.rb`, `declarations/records.rb` | Pattern for kinds, operations and declarations |
| `features/assemblies/` (Assembly with `Records::Part` layers) | Pattern for Equipment Set devices as parts |
| `library/kind_descriptor.rb`, `copy_participant.rb`, `catalog.rb`, `features/assemblies/library_kind.rb` | Library kind pattern; the dependency copy is new |
| `core/model_settings.rb` (the `ModelSettings` primitive) | The default Program setting |

## Tests (write first)

1. Each kind's schema round trip; an unknown key and a wrong version are unreadable.
2. Schedule: a ventilation form whose hours do not total 24 refuses; the profile and full-load
   hours of each form match hand values.
3. Program: a rule load round trips with its inputs; switching to a value and back keeps them.
4. Residential default: a read of a fresh Model answers it without writing; the first edit
   materializes it once; Reset restores it; deleting it while default refuses.
5. Delete: refused while referenced; with a replacement, every reference rewritten in one Undo step.
6. Library: copy a Program from a synthetic library file; its Schedules come with it; a second copy
   reuses the local Program and Schedules; a Schedule missing from the file refuses the copy.
7. `user_data` survives edit, duplicate, Undo/Redo and reopen on each kind and on devices.
8. The panel-closed walkthrough runs through registered actions only.

## Host gate

PG07 in [ACCEPTANCE](../ACCEPTANCE.md).

## Done when

PG07 passes, the library file format and contracts are updated, and the walkthrough runs.
