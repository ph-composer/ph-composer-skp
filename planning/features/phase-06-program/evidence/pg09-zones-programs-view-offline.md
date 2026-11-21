# PG09: the Zones / Programs view, offline rows

DATE: 2026-11-20
STATUS: Offline rows, the panel tests and the browser check pass on the stage branch; every host row (panel gestures in SketchUp with Ed at the mouse, native Undo and Redo of each edit, the UI polish review in the host) is owed to the batched sitting under case `PG09`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-09 stage, offline, against the SketchUp stub on Ruby 3.2.2 and 2.7.2, in Node for the panel, and in
the preview's Chrome for the browser check. SketchUp was not launched (conductor decision: earlier launches this run
reached no bridge).

Commands:
`ruby -Itests tests/zones_programs_view_test.rb` (4 runs, 84 assertions, 0 failures on each Ruby);
`node --test tests/zones_programs_panel_test.js` (15 pass);
`make ui-checks UI_CHECKS="tools/ui-preview/programs_view_checks.cjs tools/ui-preview/segment_rows_checks.cjs"`
(pass, through `browser_evidence.cjs`).

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| The view registers on the Zone views host after Spaces, listed while `ph_composer.programs.occupancy` publishes | Pass | `zones_programs_panel_test.js` "the view registers after Spaces": id, label Programs, order 30, its section; the view row reads Geometry, Programs (Spaces not loaded there); the browser check opens it from the Programs tab |
| Columns, each per-area basis in its header tooltip | Pass | Same test: every column; the iCFA header names the Phius residential rules' basis |
| Journey 1: the house locked, its bedrooms on the house row, the lock bubble, unlocking from settings | Pass | `programs_view_checks.cjs` step 1: a locked Zone has no checkbox and five locked pills; the house row's bedrooms amber until 3 is entered, sent as the Segment's `ph_composer.programs.segment` payload; the lock bubble from a locked cell, Open settings opening House's settings, Single dwelling unchecked and saved, the Zones unlocked; the Dwelling bubble names House and its units. Panel tests: the lock bubble from a locked cell and from the Single dwelling tag; the house row's Save payload |
| Journey 2: apartments one Dwelling each from the selection bar | Pass | Browser check step 2: `assign_dwelling` `each` with both Zones, the chips name each; bedrooms on Apt 1 sent as `set_counts`. Panel test: the bar's Program, One shared dwelling and Add to (only the Segment's Dwellings) each one request for every checked Zone; Equipment Set one `assign_equipment_set` with the Dwelling and the loose Zone |
| Journey 3: a library Program copied on choice and reused | Pass | Ruby `test_a_library_program_on_a_zone_copies_once_and_a_second_zone_reuses_it`: `assign_library_program` copies Office with its Schedule and assigns Apt 1 in one operation, Undo removes all, Redo restores; `keep_local` on Corridor copies nothing more. Browser check step 3: the library row offered under "copies into this file", one `assign_library_program`, then listed once under In this file and assigned to Apt 2 with `assign_program` |
| Journey 4: the school's flag and assignment | Pass | Browser check step 4: the Classroom's row flag names its finding, its Equipment Set reads a dash, and assigning Phius NR Office clears the flag |
| The Dwelling bubble | Pass | Panel test: its choice applies `assign_dwelling` at once (`none`), Units writes `dwellings.update` guarded by the units read |
| Every edit one Undo step; a stale value refuses and the cell returns to the Model's value | Pass, offline | Each control sends one action with the painted `expected_revision` (panel tests); a refused outcome leaves the Program select at the Model's value; Ruby: the house row's settings Save is one operation and a stale revision refuses `revision.stale`; the library copy and assignment are one operation |
| Unknown values | Pass | Ruby `test_the_read_gives_heading_sums_unknown_value_reasons_and_the_dwellings`: people unknown until the house's bedrooms, with the reason; heading sums with `incomplete`; the Dwellings in the read. Panel test: the amber "?" with its reason on the row and the heading |
| IP and SI | Pass | Panel tests: ft², cfm and W headers; 215.3 ft² and 29.4 cfm cells. Browser check: the IP headers |
| 420 px: the table scrolls, the selection bar wraps | Pass | Browser check: no sideways pane scroll at 1280, 420 and 360 px with the bar showing (`pane_fit.cjs`); `programs-420.png` shows the bar wrapped to one field a line |
| Host: panel gestures with Ed at the mouse, native Undo and Redo, UI polish review in SketchUp | Owed | Batched sitting, case `PG09` |

## Limits

- The preview host simulates the Programs writes (`tools/ui-preview/host.js`, `programsAction`); the rules and the
  derived loads it fills in are Ruby's and are covered by the Ruby tests, not by the browser check.
- The browser check runs in the preview's Chrome, not the HtmlDialog's Chromium 88.
