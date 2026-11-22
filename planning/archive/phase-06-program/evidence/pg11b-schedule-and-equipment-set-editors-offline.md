# PG11b: the Schedule and Equipment Set editors, offline rows

DATE: 2026-11-21
STATUS: Offline rows, the panel tests and the browser check pass on the stage branch; every host row (panel gestures in SketchUp with Ed at the mouse, native Undo and Redo, the host UI polish review) is owed to the batched sitting under case `PG11b`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-11b stage, offline, against the SketchUp stub on Ruby 3.2.2 and 2.7.2, in Node for the panel and in
the preview's Chrome for the browser check, on the preview fixture `programs` (its Schedules now include a
temperature Schedule, and the default Equipment Set a fridge-freezer, a dishwasher, an electric dryer and the Phius
MEL, each with every field its type carries). The preview answers the device types read from the golden
`tests/fixtures/programs/device_types.json`, which `tests/program_records_test.rb` keeps equal to
`EquipmentTypes.catalog`. SketchUp was not launched (conductor decision).

Commands:
`ruby -Itests tests/program_records_test.rb` (24 runs, 322 assertions, 0 failures on Ruby 3.2.2 and 2.7.2);
`program_export_test.rb` (19 runs, 0 failures on each Ruby) for the export's weekdays, now `ScheduleProfile`'s;
`api_test.rb` (47 runs, 0 failures);
`node --test tests/programs_editors_panel_test.js tests/programs_tab_panel_test.js` (32 pass, 23 of them this stage's);
`make ui-checks UI_CHECKS="tools/ui-preview/programs_editors_checks.cjs tools/ui-preview/programs_tab_checks.cjs"`
(both pass, through `browser_evidence.cjs`), with `programs_view_checks` and `library_checks` for the shared
sidebar and fixture (each passes).

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| Each Schedule type's form | Pass, offline | Browser check steps "a fractional Schedule's form", "an activity Schedule reads W per person; a temperature Schedule one value", "ventilation hours wait amber"; panel tests "a Schedule value commits as one update", "a temperature Schedule is one value in the display units" |
| The ventilation total warning | Pass, offline | Browser check "ventilation hours wait amber until they total 24 h": nothing sent at 26 h, the subtab switch refused, one update of `periods` at 24 h guarded by the periods as drawn; panel tests "ventilation hours wait as one draft", "Escape restores a held draft of the periods" |
| The strip and the week row | Pass, offline | Browser check: 24 bars, Monday to Friday on for a five-day Schedule, every day for a temperature Schedule, the bars following a saved end hour; Ruby `test_each_form_draws_its_profile_and_full_load_hours` (`weekdays`) |
| Device add, the gas dryer's extra fields | Pass, offline | Browser check "Add device lays out each type": all fourteen types from the device types, then a gas dryer's gas fields shown only for `gas_exhaust_air`, `add_device` with them; Ruby `test_device_types_say_which_fields_apply_only_under_another_fields_values`; panel tests "Add device lays out a type's fields", "every type lays out from the catalog" |
| Device edit (each type's fields) | Pass, offline | Browser check "a row click edits": the type fixed, only `quantity` sent, guarded as opened; panel test "Edit sends only what changed" |
| Device delete | Pass, offline | Browser check and panel test: the confirmation names the device, the Set and Dwelling House; `delete_device` sent |
| Every edit one registered action; a stale value refuses and the field returns to the Model's value | Pass, offline | Panel test "a Schedule value commits as one update of that field" (refused, then the Model's value); browser check "a device changed meanwhile refuses, and the dialog keeps the draft". One Undo step per action is the host's (PG11b; Ruby's device and Schedule operations are one operation each, PG07) |
| IP and SI | Pass, offline | Browser check: a temperature Schedule in °F under IP, stored as 21.11 °C; °C back in SI |
| Narrow widths: the device grid and the Schedule form at 420 and 360 px | Pass, offline | Browser check "the Schedule form at every panel size" and "the device grid and the device dialog at every panel size": no sideways scroll at 1280 × 800, 420 × 732 and 360 × 520, the dialog inside the pane |
| Panel gestures in SketchUp, native Undo and Redo, host UI polish review | Owed | Case `PG11b`, the batched sitting |
