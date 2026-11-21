# PG11: the Programs tab, offline rows

DATE: 2026-11-20
STATUS: Offline rows, the panel tests and the browser check pass on the stage branch; every host row (panel gestures in SketchUp with Ed at the mouse, native Undo and Redo, the host UI polish review) is owed to the batched sitting under case `PG11`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-11 stage, offline, against the SketchUp stub on Ruby 3.2.2, in Node for the panel and in the
preview's Chrome for the browser check, on the preview fixture `programs` (the residential default and its
Schedules, a Phius office copied from a library, an empty Wet lab Program, two Equipment Sets, and a library
file of Phius multifamily Programs and Schedules). SketchUp was not launched (conductor decision).

Commands:
`ruby -Itests tests/occupancy_assignments_test.rb` (28 runs, 0 failures);
`ruby -Itests tests/program_records_test.rb` (23 runs, 0 failures);
`node --test tests/programs_tab_panel_test.js` (6 pass);
`make ui-checks UI_CHECKS="tools/ui-preview/programs_tab_checks.cjs"` (pass, through `browser_evidence.cjs`), with
`library_checks`, `builder_checks`, `windows_checks`, `programs_view_checks`, `panel_policy_checks` and
`preview_checks` for the shared sidebar and the panel shell (each passes).

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| Three subtabs, each with the right sidebar: sources, grouping, open from a row | Pass, offline | Browser check steps "the tab opens on the Model's default Program", "a Program missing values flags each card; a row opens it", "Schedules group by type; Equipment Sets list this file's Sets"; panel test "the tab opens on the Model's default Program" |
| Copy from a library with its Schedules | Pass, offline | Browser check "a library Program is copied from the sidebar": the library's `schedules` catalog is read beside its `programs`, the copy sends no assignment and the row ends in a check. The copy of the Schedules themselves is the coordinator's (PG07b) |
| Accordion cards open and close by pointer and keyboard; summaries; missing-value flags | Pass, offline | Browser check "cards open and close by pointer and by keyboard", "closed cards read on one line", the Wet lab's eight flags; Ruby `test_the_snapshot_carries_each_collection_and_a_program_row_names_its_missing_values` |
| Rule switch | Pass, offline | Browser check "the rule switches to a fixed value and back"; panel test "the rule switch is one update" |
| Every edit one registered action; a stale value refuses and the field shows the Model's value | Pass, offline | Panel tests "a value commits as one update of its load", "a refused value lets the Model's value back into the field"; browser check "a value changed meanwhile refuses". One Undo step per action is the host's (PG11) |
| New, rename in place, Duplicate, Delete with replacement, Reset on the default | Pass, offline | Browser check steps of the same names; panel tests "a used record's Delete names its replacement" and "Reset is offered on PH-Composer's own default only" |
| Delete with replacement moves Zone assignments and Segment settings in one Undo step | Pass, offline | Ruby `test_a_delete_with_a_replacement_moves_zone_and_segment_payloads_in_one_undo_step` (Program and Equipment Set, Undo of each), `test_a_delete_with_a_replacement_refuses_whole_when_a_zone_is_locked` |
| IP and SI | Pass, offline | Browser check "IP shows people per ft² and SI people per m²"; panel test of a value stored in m³/s and shown in m³/h |
| Narrow widths: the sidebar drops beneath the editor without moving it | Pass, offline | Browser check "the pane at every panel size" at 1280 × 800, 420 × 732 and 360 × 520 |
| Panel gestures in SketchUp, native Undo and Redo, host UI polish review | Owed | Case `PG11`, the batched sitting |

The ventilation total warning and Equipment Set devices moved to P4a-11b with their editors (PG11b).
