# PG02: Segment heading rows and settings, offline and browser rows

DATE: 2026-11-20
STATUS: Offline and browser rows pass; the UI polish review is recorded below. The panel gestures in SketchUp are owed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-02 stage on PR [#540](https://github.com/ph-composer/ph-composer-skp/pull/540). The offline
suites and the browser checks named below passed again on the PR head `50ed6d4a`, after the last review
fix. Screenshots stay in `_private/ui/pg02-20261120/`.

## What ran

| Row | Result | Evidence |
| --- | --- | --- |
| Heading rows in Geometry and Spaces: two lines, Default tag, sums, Actions cell | Pass | `tests/segment_rows_panel_test.js`; `tools/ui-preview/segment_rows_checks.cjs` at 1280 x 800, 420 x 732 and 360 x 520, no sideways scroll |
| No Building Segment group: last, muted, only while it holds a Zone | Pass | Panel tests; the browser check after Delete moved a Zone to none |
| New Building Segment names and opens in place | Pass | Panel test (Enter renames, Escape keeps the name); browser check (the name has focus, Enter applies) |
| Move from the Geometry and Spaces selection bars | Pass | Panel tests for both bars; browser check moved a checked Zone into a new Segment |
| Delete with a destination, naming the Zones and the settings that go | Pass | Panel test; browser check chose No Building Segment |
| The settings dialog saves General and every changed section as one request; a refused payload blocks Save | Pass | Panel tests; browser check with the development Note section at every panel size |
| Save is one Undo step across two namespaces; a validator's refusal writes nothing; a locked member does not block a settings save; `zones.segment_settings_saved` reaches a contributor | Pass | `tests/segment_settings_test.rb` against the SketchUp stub |
| A `segmentHeading` contribution shows in every view | Pass | Panel test in Geometry and Spaces |
| The Geometry column and the Manage dialog are gone | Pass | Panel tests; `zone_options_checks.cjs` now manages Levels only |
| Cancel, close and Escape write nothing | Pass | Panel test for each route; browser check for Escape |
| A Shift-click range across Segments, a name changed elsewhere during New, a Zone with no Faces moved from the Geometry bar | Pass | Panel tests added for the second Codex review's findings |
| Bridge rows: New and a settings save each one native Undo step, a settings-only save past a locked member | Owed | The stage's launch of the installed build on `50ed6d4a` reached no bridge in 180 s and no SketchUp window was readable, so nothing ran; SketchUp was quit through hostkit. Case `PG02` is in the case ledger for the batched sitting |
| Panel gestures in SketchUp, Ed at the mouse | Owed | Runs in the conductor's batched sitting on the final head |

## UI polish review

Read against the [UI polish skill](../../../../.claude/skills/ph-composer-ui-polish/SKILL.md) and the
mockups (`j3-*`, `j1-segment-actions`, `j4-long-name`), from the browser check's screenshots.

- **Hierarchy.** The heading row is a firmer band than a Zone row (the kit's heading row in `table.css`),
  with the name on the first line and the tags on the second; a Segment with no tags takes one line, as
  the PRD says. No Zone count and no subtitle.
- **Actions.** Settings and Delete show on hover in the Actions cell, as other row actions do. Delete
  on the last Segment stays on screen with its reason. New Building Segment is an icon after the count,
  as in the mockup.
- **Dialogs.** The settings dialog uses the shared form dialog: close icon, Cancel then Save, Save
  disabled with the problem shown under the sections. Label beside control at desktop width, stacked
  below 500 px; at 360 x 520 the body scrolls and Save stays in view. The first pass stacked the colour
  field and the joins checkbox under the shared form dialog's label rules; the rules now outrank them.
- **Words.** "Building Segment", "No Building Segment", "New Zones join this Segment" and "Default"
  follow the glossary; no code or id shows.
- **Narrow panels.** The selection bar's Building Segment field wraps its label above its choice at the
  narrowest width (caught by `selected_solve_checks.cjs` at 280 px and fixed).
- **Open.** The heading band's colour (`--line`) is darker than a Zone row's; Ed's host review may tune it.
  The Planned settings rows the PRD lists are not built in this stage.
