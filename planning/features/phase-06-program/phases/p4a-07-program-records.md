# P4a-07a: Program, Schedule and Equipment Set records

DATE: 2026-11-15
STATUS: Implemented on branch 2026-11-20 as P4a-07a; PG07's native Undo, Redo and reopen rows owed. Split on 2026-11-20: steps 7 and 8 (library kinds and dependency copy) and test 6 moved to [P4a-07b](p4a-07b-program-library-kinds.md). Authorized 2026-11-20 with the rest of Phase 4a ([STATUS](../STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

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

0. **Pin.** P4a-03's entry check chose the honeybee-ph pin for `PhEquipment` (F4a-18; C4a-11, Ed,
   2026-11-20). Build the per-type field table from that pinned wheel.
1. **Units.** Store every value in the honeybee SI unit its HBJSON field uses (people per m²,
   W/m², m³/s per person and per m², m³/s per Zone, 1/h, m³/s per m² of exterior area at 4 Pa,
   L/h per m², °C), each field with its `x-unit`, so P4a-10 writes values without conversion. The
   panel converts for display (m³/h, IP). `core/units.rb` and the panel's units have `airflow`, `area`
   and `temperature`; add the quantities these fields need (power, power per area, people per area,
   airflow per person and per area) on both sides with shared vectors in
   `tests/support/units_vectors.json`, as Climate did for its own.
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
   with `source` naming PH-Composer's default, with its Schedules. A Programs Model setting,
   `ph_composer.programs.settings`, holds `default_program_id` and `default_equipment_set_id`;
   absent means the frozen ones. A settings proposal guards its whole dictionary, so decide here
   whether the two defaults share one (CONTRACTS section 5). **The default Equipment Set** (the eight honeybee-ph Phius
   defaults, F4a-20) follows the same pattern. Deleting either default refuses
   `programs.default_in_use`. `ph_composer.programs.reset_default` rewrites either from its
   definition, one Undo step (Q4a-23).
6. **Operations** for each kind: create (a free name: "Program 2"), update with guarded
   `expected_values`, rename, duplicate (a "(copy)" name; Schedules shared, not copied), delete
   (guarded by the incoming references that exist at this stage: Segment `default_program_id`,
   the Model defaults, Programs using a Schedule; P4a-08 adds Zone assignments and Dwellings; delete
   with a named replacement rewrites them). One Undo
   step each. Reads: `programs.all`, `schedules.all`, `equipment_sets.all` with used-by counts.
7. **Moved to [P4a-07b](p4a-07b-program-library-kinds.md).** **Library kinds** (Q4a-19, Q4a-22): wire kinds `programs`, `schedules`, `equipment_sets` in
   `docs/LIBRARY_FILE_FORMAT.md`, each with its `kind_descriptor`, wire mapping, fingerprint and
   create, replace and assign callbacks, through the existing coordinator as Materials and Frames.
8. **Moved to P4a-07b.** **Dependency copy** (new in the coordinator, `library/copy_participant.rb`, `catalog.rb`): a
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
6. Moved to P4a-07b. Library: copy a Program from a synthetic library file; its Schedules come with it; a second copy
   reuses the local Program and Schedules; a Schedule missing from the file refuses the copy.
7. `user_data` survives edit, duplicate, Undo/Redo and reopen on each kind and on devices.
8. The panel-closed walkthrough runs through registered actions only.

## Host gate

PG07 in [ACCEPTANCE](../ACCEPTANCE.md).

## Done when

PG07 passes, the contracts are updated, and the walkthrough runs. The library file format is P4a-07b's.

## Split and decisions (2026-11-20)

The stage was split because the library half changes the neutral library coordinator, a foundation contract,
and adds three adapters and the file-format document: on its own it is a full reviewable PR, and P4a-08 needs
only the records. P4a-07a is steps 0 to 6 and 9 with tests 1 to 5, 7 and 8; P4a-07b is steps 7 and 8 with
test 6. P4a-09 (journey 2's library Programs copied on choice) and P4a-11 (the sidebar's copy with Schedules) now
need P4a-07b as well, as does stage S3 of the ph-composer-standards plan.

Decided in P4a-07a, each recorded in `context/CONTRACTS.md`, "Programs, Schedules and Equipment Sets":

- **Activity form.** An activity Schedule's values are `watts_on` and `watts_off`, W per person; `fraction_on`
  and `fraction_off` stay the fractional form's, so no field's unit depends on the type.
- **Whole hours.** `start_h`, `end_h` and each ventilation period's `hours` are integers, so the 24-hour strip
  and the profile are exact. Full-load hours count days off as zero: the daily sum on days_per_week ×
  weeks_per_year operating days, honeybee-ph's operating-day count. P4a-10's ruleset writes days off at zero.
- **Default Schedules.** honeybee-ph's occupancy, lighting and hot water schedules are hourly profiles; a
  fractional form holds two levels. Each default Schedule holds its profile's daily mean all day. PHX reads a
  schedule without operating periods as 0 to 24 h at its mean, and the Phius People and lighting rules divide by
  that mean, so WUFI-Passive, METr and the rules see the honeybee-ph values; EnergyPlus loses the hourly shape
  until the hourly editor (Q4a-07). Set Residential Program gives Ventilation no schedule (full flow); the
  default is the prototype's "Constant ventilation", the standard period 24 h at 1.0.
- **Default devices.** The eight are `set_res_program.py`'s, not `create_elec_equip.py`'s Phius list: interior
  lighting rides on the Program's Lighting load (F4a-20). honeybee-ph gives garage lighting quantity 0, which
  PHX reads as 1 (F4a-18), and a device's quantity is at least 1, so it is 1; garage lighting allows reference
  quantity 2 (the wheel) and 8 (the component), which disagree.
- **Device fields.** honeybee-ph's `capacity` is place settings on a dishwasher and m³ on a washer, so the keys
  are `capacity_place_settings` and `capacity_m3`; enumerations are stored as snake-case values mapped to
  honeybee-ph's strings in `equipment_types.rb`. The clothes dryer carries no `energy_demand` (WUFI-Passive and
  METr read its CEF).
- **One settings dictionary.** Each settings update guards only the fields it names, so the two defaults share
  `ph_composer.programs.settings` without staling each other. The reserved ids are never stored.
- **Unwritten defaults.** The default Program with its Schedules, and the default Set, are bundles written whole
  by the first write that touches them, including a settings update that makes another record the default.
  The generic `records.*` routes see stored records only. Reset rewrites the record and writes back a missing
  default Schedule; an edited one stays, and a default Schedule given another type refuses the reset.
- **Deleting a default.** Without a replacement it refuses `programs.default_in_use`; with one, the default
  moves to it (step 5 and step 6 read together). An unwritten default deleted that way takes its Schedules out
  of the reads with it.
- **Guarded uses at this stage.** The Model defaults and Programs naming a Schedule; the Segment's
  `default_program_id` arrives with `ph_composer.programs.segment` in P4a-08, which registers its own
  retargeter. A Schedule a Program uses keeps its type.
- **Rename** is `update` with a `name`; no separate action.
- **Units.** `power`, `power_per_area`, `people_per_area`, `airflow_per_person` and `airflow_per_area` on both
  sides with shared vectors. The two airflows display m³/h, as `airflow` does; Programs store honeybee's m³/s,
  which the panel scales by 3600 (P4a-11).
- **Not here.** Snapshot sections for the panel wait for the Programs tab (P4a-11).
