# PG07: Program, Schedule and Equipment Set records, offline rows

DATE: 2026-11-20
STATUS: Offline rows pass on the stage branch; the installed-RBZ rows (native Undo and Redo, save and fresh-process reopen) are owed to the batched sitting under case `PG07`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-07a stage, offline, on Ruby 3.2.2 and 2.7.2 against the SketchUp stub and in Node for the units.
SketchUp was not launched. The library rows moved to PG07b with the split.

Commands, both Rubies (30 runs, 456 assertions, 0 failures on each):
`ruby -Itests -e 'require "./tests/program_records_test"; require "./tests/program_records_walkthrough_test";
require "./tests/units_test"'`; and `node --test tests/units_test.js` (22 pass).

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| Each kind round trips; an unknown key and another version are unreadable | Pass | `test_each_kind_round_trips_and_an_unknown_key_or_another_version_is_unreadable`: a created Program, Schedule and Equipment Set read back as plain JSON; a stored extra key or schema version 2 reads `record.unreadable` |
| Every default is a valid record; every type's new device fits its type | Pass | `test_every_frozen_default_is_a_valid_record_and_every_default_device_fits_its_type`: the default Program, six Schedules and eight-device Set pass their kinds; each of the fourteen types' new devices passes `EquipmentTypes.problems` |
| A ventilation Schedule must total 24 h | Pass | Periods of 2, 14, 6 and 1 h refuse `validation.failed` with the revision unchanged; 2, 14, 6 and 2 h store, with the profile and daily full-load hours 2 + 14 × 0.77 + 6 × 0.54 + 2 × 0.4; periods out of order refuse |
| The profile and full-load hours of each form match hand values | Pass | `test_each_form_draws_its_profile_and_full_load_hours`: 7 to 18 h at 0.5 with 0.1 otherwise, 5 days, 50 weeks, is 6.8 h a day and 1,700 h a year; 22 to 6 h wraps midnight; activity and temperature draw their levels with null full-load hours |
| A Schedule's type is kept while a Program uses it; a Program refuses a Schedule of the wrong type | Pass | `test_a_schedule_a_program_uses_keeps_its_type`, `test_a_new_type_swaps_the_form_and_a_program_refuses_a_schedule_of_the_wrong_type` |
| An Equipment Set's update cannot replace its devices; a reset refuses a name another record holds | Pass | `test_an_equipment_set_update_cannot_replace_its_devices` (`params.invalid`; the device keeps its type), `test_reset_refuses_to_write_back_a_schedule_whose_name_another_took` (`validation.failed`, revision unchanged) |
| A rule load keeps its inputs across a switch to a value and back | Pass | `test_a_rule_load_keeps_its_inputs_across_a_switch_to_a_value_and_back`: Lighting `phius_interior` with fraction 0.8, switched to 2.5 W/m² and back, reads the rule, 0.8 and 2.5 |
| The residential default reads without a write | Pass | `test_a_fresh_model_reads_the_defaults_without_writing`: the Program, six Schedules and eight-device Set read `stored` false, `settings.get` names the reserved ids, the revision and the stores are unchanged |
| It writes once, with its Schedules, on the first edit | Pass | `test_the_first_edit_writes_the_default_with_its_schedules_once_and_undo_returns_to_the_definition`: one operation; a second edit edits the stored record; two Undos return to the unwritten definition |
| Reset restores it | Pass | `test_reset_restores_the_default_program_and_writes_back_a_missing_schedule` (one Undo step; a Schedule deleted with a replacement is written back); `test_reset_refuses_a_name_another_record_took_and_reports_a_dropped_devices_map` |
| It refuses delete while default; the same for the default Equipment Set | Pass | `test_the_default_refuses_delete_until_a_replacement_takes_over`, `test_the_default_equipment_set_writes_once_on_a_device_change_resets_and_refuses_delete`: `programs.default_in_use` without a replacement; with one, the default moves |
| The Model's defaults | Pass | `test_a_stored_default_moves_with_a_replacement_and_a_settings_change_keeps_the_residential_default`: a settings update stores the displaced residential default; an update guarded on one default ignores the other; naming the current default writes nothing; the reserved id is never stored; Undo restores the previous default |
| Device add, edit and delete are each one Undo step, with each type's fields validated | Pass | `test_device_add_edit_and_delete_are_each_one_undo_step_with_each_types_fields`: three operations; a Phius MEL refuses `energy_demand`; a refrigerator refuses reference quantity 1; a type change refuses `params.invalid`; a stale `expected_values` refuses `target.changed` |
| Guarded delete and delete with replacement | Pass | `test_a_used_schedule_refuses_delete_and_a_replacement_rewrites_every_use_in_one_undo_step`: `reference.in_use`; a temperature replacement refuses; a fractional one rewrites both Programs' three slots in one step, undone whole; `test_an_unwritten_default_schedule_deletes_with_a_replacement_from_its_own_bundle` |
| `user_data` survives edit, duplicate, Undo/Redo and reopen on each kind and on devices | Pass | `test_user_data_survives_edit_duplicate_undo_redo_and_reopen_on_each_kind_and_on_devices`: the record maps on the three kinds and a device's map, through an edit, a device edit, duplicates (the copied device with a new id), Undo, Redo, save and reopen |
| The panel-closed walkthrough runs through registered actions only | Pass | `tests/program_records_walkthrough_test.rb`: seven writes, seven Undo names in order, all undone to the starting reads and redone, then save, reopen and verify; the walkthrough names no `PhComposer::Programs` constant |
| The installed RBZ: the walkthrough, native Edit-menu Undo and Redo, save and fresh-process reopen | Owed | Batched sitting, case `PG07` in the case ledger |

## Limits

- Default occupancy, lighting and hot water Schedules hold honeybee-ph's hourly profiles at their daily mean
  (the stage doc's "Split and decisions"); EnergyPlus loses the hourly shape until the hourly editor.
- The stub's Undo and Redo replay the dictionary writes; the native Edit menu is the owed row.
