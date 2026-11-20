# PG07b: Program, Schedule and Equipment Set library kinds, offline rows

DATE: 2026-11-20
STATUS: Offline rows pass on the stage branch; the installed-RBZ rows (a copy from a library file, native Undo and Redo) are owed to the batched sitting under case `PG07b`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-07b stage, offline, on Ruby 3.2.2 and 2.7.2 against the SketchUp stub. SketchUp was not
launched (conductor decision: two earlier launches this run reached no bridge).

Command, both Rubies (49 runs, 794 assertions, 0 failures on each, measured on `6849bee4` plus the final test commit):
`ruby -Itests -e 'require "./tests/program_library_kinds_test"; require "./tests/library_programs_walkthrough_test";
require "./tests/library_registration_test"; require "./tests/library_assignment_contract_test";
require "./tests/library_export_test"'`.

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| A library Program copies with its Schedules | Pass | `test_a_program_copies_with_its_schedules_once_and_a_second_copy_reuses_them`: one copy creates the Program and its two Schedules, each Schedule once though two slots name the first; the Program's slots name the local ids, its snapshot keeps the library ids; every stored record passes its kind |
| A second copy reuses them | Pass | The same test: `in_file` reads `reuse` for the Program and both Schedules with `source_changed` false; `keep_local` answers the same local id, effect `none`, no dependencies, and the record counts are unchanged. `test_a_second_program_naming_copied_schedules_reuses_them_by_source`: a Schedule copied first is `reused` |
| A Schedule missing from the library file refuses the copy and writes nothing | Pass | `test_a_schedule_missing_from_the_library_or_unloaded_refuses_and_writes_nothing`: `library.dependency_missing` with kind, library, record id and `catalog_state` `loaded`, revision unchanged, no records; with the `schedules` kind unloaded, `catalog_state` `unloaded` |
| A same-named local Schedule of other values refuses | Pass | `test_a_local_schedule_of_the_same_name_and_other_values_refuses_until_it_is_resolved`: `library.review_required` naming the second Schedule after the first was staged, revision unchanged, nothing written; after `use_library` on that Schedule the Program copies and reuses it. `test_a_schedule_of_the_wrong_type_for_its_load_refuses_the_copy`: `validation.failed` on `lighting.schedule_id` |
| Each kind's wire mapping and fingerprint round trip; an Equipment Set's devices keep their types and fields | Pass | `test_each_kind_maps_round_trips_and_fingerprints_canonically`: map of reverse is the mapped values for each kind; `1` and `1.0` fingerprint alike; a changed Schedule reference changes the Program's fingerprint; an absent load or value takes a new Program's; devices keep type and given fields, the type's defaults filling the rest |
| An Equipment Set copies with new device ids; a replacement keeps matching devices | Pass | `test_an_equipment_set_copies_with_new_device_ids_and_a_replacement_keeps_matching_devices`: `dev_` ids allocated; `use_library` keeps the first device's id and `user_data` with the new value; a replacement that would drop a device holding `user_data` refuses `validation.failed` |
| Copy plus assignment as the Model's default is one Undo step | Pass | `test_copy_and_model_default_assignment_are_one_undo_step`: one operation; the default names the copy; the residential default is written first; Undo removes every Program and Schedule and restores the settings; Redo restores the copy; a stale `expected_settings` refuses `target.changed` with nothing written |
| The published contract: describe, discovery, assignment from the descriptor | Pass | `test_describe_names_the_dependency_and_the_assignment`; `library_assignment_contract_test`: Programs and Equipment Sets assign as the Model's default from the published example; Schedules alone are unassignable; `test_dependencies_name_registered_other_kinds_with_callable_list_and_remap` |
| An exported Program brings its Schedules; device maps are reported | Pass | `test_an_exported_program_brings_its_schedules_and_copies_into_a_fresh_model`: a selected Program and Equipment Set export with both Schedules though neither the selection nor `kinds` names them; the preview lists `devices[].user_data`; the file copies into a fresh Model, creating both Schedules; a Schedule the export cannot label refuses the preview `library.dependency_missing` |
| A Program replacement copies a newly named Schedule | Pass | `test_a_program_replacement_copies_a_newly_named_schedule`: the library Program now names a third Schedule; `in_file` reads `source_changed` true; `use_library` reuses the two local Schedules, creates the third and names it in the Program |
| The published fixture reads | Pass | `test_the_published_programs_fixture_reads_each_kind`: two Schedules (each with the `library.row_optional_absent` warning a Schedule row always carries), one Program and one Equipment Set, nothing unavailable |
| The panel-closed walkthrough | Pass | `tests/library_programs_walkthrough_test.rb`: the copy with its Schedules as the default is one Undo step named "Copy Library Record", a second copy reuses everything, Undo empties the stores; the walkthrough names no `PhComposer::Programs` constant |
| The installed RBZ: a copy from a library file, native Edit-menu Undo and Redo | Owed | Batched sitting, case `PG07b` in the case ledger |

## Limits

- A Schedule row always reads with `library.row_optional_absent`: the file reader warns for every absent optional
  field, and a row gives only its own form's fields.
- Library export counts and writes stored records only, so PH-Composer's unwritten residential default is not
  exported until a write stores it.
