# PG08: Dwellings, Zone assignments and Single dwelling, offline rows

DATE: 2026-11-20
STATUS: Offline rows and the browser check pass on the stage branch; every host row (Single dwelling on and off, native Undo and Redo, copying a Zone, the heading tag and findings in SketchUp) is owed to the batched sitting under case `PG08`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-08 stage, offline, against the SketchUp stub on Ruby 3.2.2 and 2.7.2, in Node for the panel, and in
the preview's Chrome for the browser check. SketchUp was not launched (conductor decision: earlier launches this run
reached no bridge).

Commands:
`ruby -Itests tests/occupancy_assignments_test.rb` (26 runs, 510 assertions, 0 failures on each Ruby, on `c4a8280e`);
`node --test tests/occupancy_section_panel_test.js` (7 pass);
`make ui-checks UI_CHECKS=tools/ui-preview/segment_rows_checks.cjs` (pass, through `browser_evidence.cjs`).

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| Each assign action is one Undo step and round trips | Pass | `test_each_assign_action_is_one_undo_step_and_round_trips`: `assign_program`, `assign_dwelling`, `set_counts` and both forms of `assign_equipment_set` each add one operation; the Corridor's assignment reads back whole; five Undos return it to unassigned |
| An emptied Dwelling goes | Pass | `test_each_and_none_create_and_delete_dwellings`: `each` makes one Dwelling per Zone; moving a Zone to the other's leaves one, deleted in the same step (`deleted_dwelling_ids`); `none` deletes the last |
| A Dwelling across Segments refuses | Pass | `test_a_dwelling_across_segments_refuses_and_a_single_dwelling_zone_refuses`: `existing` and `shared` across House and Apartments refuse `programs.dwelling_across_segments`, the revision unchanged; a Zone of a single dwelling refuses `programs.single_dwelling` |
| Single dwelling on: Zones cleared, emptied Dwellings deleted, summed bedrooms, one Undo step | Pass | `test_switching_on_clears_the_zones_and_deletes_their_dwellings_in_one_undo_step`: the preview sums the Zones' bedrooms to 2; one Save clears every Zone and deletes both Dwellings; the house reads 2 bedrooms and 3 occupants by the Phius rule; Undo restores both Dwellings and the counts |
| Off and on keep the house's counts; a count cleared in the switching Save stays cleared; overridden Zone counts never reach the house | Pass | `test_house_counts_survive_off_and_on_and_an_explicit_null_is_kept`, `test_overridden_assignments_neither_count_in_the_house_nor_outlive_switching_off` |
| Single dwelling off: Zones keep the Dwelling and the default Program, one Undo step | Pass | `test_switching_off_makes_the_house_a_dwelling_its_zones_keep_in_one_undo_step` (a Dwelling named House with the 3 bedrooms, every Zone in it, no Program of its own); `test_switching_off_where_the_segment_names_a_default_keeps_the_models`; `test_a_rename_and_the_switch_land_together_in_one_save` (a rename's evidence rewrite and the Zone writes chain in one step) |
| An absent payload reads as on; a non-residential Segment is never one | Pass | `test_an_absent_payload_reads_as_single_dwelling_and_a_non_residential_segment_is_never_one`; `test_a_category_change_alone_writes_no_assignment` |
| Copying a Zone copies its assignment and keeps its Dwelling (C4a-2) | Pass | `test_a_copied_zone_keeps_its_assignment_and_dwelling`: after `make_independent`, both Zones name the same Dwelling |
| Derivations match hand values on the house | Pass | `test_the_house_derives_people_lighting_and_ventilation_by_the_phius_rules`: 3 bedrooms give 4 occupants; Living's peak people 4 / 0.7208 × 20/36 (floor area); lighting from `lighting_interior` over 34 m² of iCFA, 248.99 kWh from the vendored honeybee-ph 1.33.68 wheel, over 1/24 × 8,760 h, × 20/34 (iCFA, the Bath weighted 0.5); ventilation 0.4 ACH × 50 m³; set points 20 and 25 °C |
| Derivations match hand values on the apartments | Pass | `test_an_apartment_derives_from_its_program_and_detailed_airflows` (people, lighting and ventilation per m²; disagreeing set points; a detailed Zone's larger of supply 60 and extract 45 m³/h); `test_a_dwelling_of_two_units_counts_them_in_the_rules` (occupants 3 + 2; lighting 400.49 kWh from the wheel for two units) |
| Findings on Programs' actions and after a generic metadata write | Pass | `test_findings_follow_programs_actions_and_generic_metadata_writes`, `test_a_zone_moved_between_segments_is_a_finding_the_action_repairs`, `test_a_zone_left_assigned_in_a_single_dwelling_is_a_finding` |
| Delete guards | Pass | `test_naming_the_unwritten_default_stores_it_and_a_used_record_refuses_delete` (a Program a Zone names refuses `reference.in_use`, with or without a replacement; a Dwelling likewise); `test_an_equipment_set_delete_moves_its_dwellings_to_the_replacement` |
| No export blocks on an assignment | Pass | `test_an_assignment_never_blocks_export`: both extensions are `local_only` |
| Zones' participant | Pass | `test_the_participant_refuses_a_locked_zone_and_writes_nothing`; `test_a_zone_update_step_restores_the_record_it_replaced` |
| Occupancy section and heading in the panel | Pass | `tests/occupancy_section_panel_test.js`: house rows on a Segment with no settings; disabled with its reason while the certification draft is non-residential, following the draft; switching on names what gives way and enters the summed bedrooms; an unreadable count holds Save; typing keeps the field; the Single dwelling tag and the Segment's findings on the headings |
| Browser check | Pass | `segment_rows_checks.cjs`: the tag and the finding flag on the headings; the dialog lists General, Occupancy, Phius certification, Airtightness and the example Note; the Occupancy section fits at 1280, 420 and 360 px; a non-residential category disables Single dwelling with its reason; Save sends the five fields |
| Host: on and off, Undo/Redo, copy a Zone, the tag and findings on headings in every view | Owed | Batched sitting, case `PG08` |

## Limits

- The yearly means follow honeybee-ph's `annual_average_operating_fraction` (daily full-load hours over 24); PHX's
  own full-load hours for lighting were not cross-checked here.
- The browser check runs in the preview's Chrome, not the HtmlDialog's Chromium 88.
