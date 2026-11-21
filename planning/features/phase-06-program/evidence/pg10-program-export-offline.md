# PG10: the Program export, offline rows

DATE: 2026-11-20
STATUS: Offline rows, the Python translation, the PHX round trip of the five journeys, the panel tests and the Segment settings browser check pass on the stage branch; every host row (the packaged RBZ exporting the five journeys, the round trip of that export, the Comfort section and a preflight Locate in SketchUp) is owed to the batched sitting under case `PG10`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-10 stage, offline, against the SketchUp stub on Ruby 3.2.2 and 2.7.2, the pinned Python stack
(honeybee-energy 1.123.23, honeybee-ph 1.33.68) and PHX 1.59.1 from the `phx` group, in Node for the panel and in
the preview's Chrome for the browser check. SketchUp was not launched (conductor decision).

Commands:
`ruby -Itests tests/program_export_test.rb` (17 runs, 346 assertions, 0 failures on each Ruby);
`uv run pytest tests/python/test_program_sections.py` (6 pass); `uv run --group phx pytest tests/python` (every Python test, the round trips among them, pass); `make runtime-browser-check` (PASS: the shipped runtime page in Chromium 88 translates the two-Zone fixture, Program sections included);
`uv run --group phx pytest tests/python/test_program_phx_round_trip.py` (2 pass);
`node --test tests/occupancy_section_panel_test.js tests/zones_programs_panel_test.js` (32 pass);
`make ui-checks UI_CHECKS="tools/ui-preview/segment_rows_checks.cjs"` (pass, through `browser_evidence.cjs`).

The synthetic Model (tests/program_export_test.rb) holds the five journeys in three Building Segments: House, a
single dwelling of three bedrooms over Living, Kitchen and Bedroom; Apartments, Apt 1 (two bedrooms) and Apt 2
(one bedroom, two units) one Dwelling each on the residential default, Corridor and Laundry in none on a Common
Program, Laundry with its own Equipment Set; School, non-residential, a Classroom on a 5-day, 44-week Schedule and
a Lab with temperature set point Schedules, a ventilation Schedule and the Laundry Set. Its extraction is the golden
`tests/fixtures/programs/extraction.json`.

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| Contract records match hand values per Dwelling | Pass | `test_the_house_is_one_program_type_with_its_counts_and_devices_on_its_largest_room`: people per area 4 occupants (Phius rule) over the presence mean and 48 m²; lighting from `lighting_interior` over 48 m² of iCFA and the lighting mean, per 48 m²; hot water from Building America by 3 bedrooms, per 48 m²; 3 bedrooms, 4 occupants and the 8 devices on Living, none on Kitchen |
| Rulesets carry weekday rules and the weeks-off range; ventilation Schedules their four periods | Pass | `test_a_five_day_44_week_schedule_rules_weekdays_and_leaves_a_summer_block_off`: Monday to Friday, operating 1 January to 3 July and 29 August to 31 December; `test_a_ventilation_schedule_carries_its_four_periods_from_midnight`. Python `test_schedules_carry_their_weekday_rules_weeks_off_and_ventilation_periods`: the reloaded ruleset's two rules, weekday flags, dates, honeybee-ph days 5 and weeks 44, no periods on the School day, four on Lab air |
| One ProgramType per Dwelling group for a rule Program, one for a plain Program | Pass | Python `test_the_journeys_reload_with_a_program_type_per_dwelling_and_one_for_a_plain_program`; Ruby `test_apartments_take_a_program_type_each_and_their_units_multiply_the_devices` |
| People extension and Process devices on the right Rooms; quantities times units; the default Set where none is assigned | Pass | Python `test_each_room_carries_its_counts_dwelling_and_devices`: counts on Living, a shared `PhDwellings`, Apt 2's two units and each default device at quantity 2, Laundry's washer and dryer, Corridor untagged |
| Set points on each Segment | Pass | Python `test_each_segment_takes_its_set_points`; Ruby `test_the_school_writes_its_schedules_and_its_first_zones_set_points`: School 20 and 26 °C from its first Zone, the Classroom |
| Preflight rows on their cases | Pass | `test_the_five_journeys_preflight_unblocked_with_their_warnings_and_write_the_golden` (two `programs.set_points_disagree`, `programs.equipment_set_non_residential` with its Locate); `test_a_program_value_missing_blocks_the_export_and_locates_its_zones`; `test_a_heating_schedule_above_the_cooling_set_point_blocks`; `test_a_fresh_house_exports_with_no_counts_and_says_so`; `test_a_rule_program_over_no_dwelling_exports_the_zone_alone_with_a_note`; `test_a_dwelling_with_no_floor_face_exports_its_rule_loads_at_zero_with_a_note`; `test_a_name_that_reads_as_a_local_path_stays_in_the_model`; `test_legacy_zones_export_their_program_alone_and_no_set_points`; `test_a_zone_in_no_dwelling_keeps_no_counts_from_a_stale_assignment`; `test_the_locate_command_opens_the_zones_view_with_its_zones` |
| The PHX round trip of the five journeys | Pass | `test_the_five_journeys_read_back_occupancy_devices_ventilation_and_set_points`: per Variant in WUFI XML (and METr where it carries them) units, occupants, bedrooms and set points equal the extraction's; House 4 occupants, Apartments 6 over 3 units; 9, 11 and 0 devices, the Apartments' default devices merged to quantity 3; the School's supply 102.6 and 360 m³/h and lighting 8 and 10 W/m², the House's lighting its rule's W/m²; METr's units, occupants and bedrooms. `test_utilization_patterns_read_back_the_schedule_forms`: the Lab's ventilation pattern (6 days, 52 weeks, 2, 10, 8 and 4 h at 1.0, 0.8, 0.5 and 0.3) in WUFI XML and METr; the School day's relative absenteeism 1 − 8 × 220 / 8,760; every Variant's q50 the Programs' infiltration as PHX converts it, no Segment having a test result |
| The Comfort section shows the set points | Pass, offline | `occupancy_section_panel_test.js` "the Comfort section shows the set points read only and saves nothing"; the browser check lists Comfort among the shipped sections |
| The packaged RBZ exports the five journeys; the round trip reads them back; Comfort and Locate in SketchUp | Owed | Case `PG10`, the batched sitting |
