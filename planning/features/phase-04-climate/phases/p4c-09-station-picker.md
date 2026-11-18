# P4c-09: The station picker

DATE: 2026-11-17
STATUS: Implemented on branch `feature/climate-p4c-09`, 2026-11-18; CM09 not run. Authorized with every Climate stage on 2026-11-17 ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Entry and scope

Requires P4c-04, P4c-07 and P4c-08. Owns Set Phius Climate Data: every station of one dataset on
the outline map and in a list, with the site, the 50 mile ring, filters, the verdict, and Attach
or Replace. It reads `stations.list` and calls `attach_station`; it holds no rule of its own.

Behavior: [PRD](../PRD.md), "Choosing a station". Names: [CONTRACTS](../CONTRACTS.md) sections
4 and 6. Answers: W1, J3, J7; D4c-06. Boards: 4 (`Picker`, drawn narrowed to one state; it opens
on All), 11 (`PickerFail`), 16 (`PickerReplace`). Paths are relative to `src/ph_composer/`.

Load the UI polish skill and its patterns reference first.

## Entry checks

1. With P4c-04's measured read time, decide whether the picker shows a brief reading state. The
   wireframes draw none by choice; add one only if the read was sliced.
2. Check the picker at 420 and 360 px, which are not drawn: decide whether the map stacks above
   the list or sits behind a toggle, and record it as a UI decision in
   [DECISIONS](../DECISIONS.md).
3. Draw about 1,000 markers and 1,000 list rows from invented data and confirm selection and
   hover stay responsive; if the list needs windowing, use the table's own means.

## Steps

1. **Dialog** (`html/features/climate/picker.js`): the map (P4c-07's kit part) beside the list.
   Opened by Choose Station, by Replace, and by Update from File with the matched station
   preselected.
2. **Opening state** (J3): the dataset is the attached station's if its source is on this
   computer, else `last_dataset_id`, else the only or first folder; sorted by distance; the map
   framed on the 50 mile ring around the site; State on All.
3. **List rows**: station, state, distance, elevation difference, and a Pass or Fail tag from
   `stations.list`. Distances and elevations through the unit preference.
4. **Controls**: Dataset (changes the folder and stores it with `folders.remember_dataset`),
   State (the folder names found), a search by name, and Find Nearest, which returns to the
   opening view.
5. **Map**: every listed station as a marker toned by verdict, the site pin and the ring. A
   click selects a station in both map and list and scrolls the row into view; a hover shows
   name, distance, elevation difference and verdict.
6. **Selection footer**: the selected station's verdict against both limits. For a failing
   station (board 11) a warning that it is outside the Phius limits, and Attach still enabled
   with no confirm step.
7. **Attach**: `attach_station`, then the dialog closes on the attached pane.
8. **Replace** (board 16): with a climate already in the Model, the footer shows the current and
   the selected station side by side (dataset, distance, elevation difference, verdict) and
   says how many edited values will be lost; the button reads Replace. One Undo step.
9. **Docs.** `docs/PRODUCT.md` gains choosing a station and what Pass and Fail mean, citing the
   Phius limits and saying PH-Composer reports and does not approve.

## Source

| File | Disposition |
| --- | --- |
| `html/outline_map.js` from P4c-07 | Reused |
| `html/table.js`, `html/view_controls.js`, `html/overlay.js` | List, filters and dialog |
| `mockups/canvas/project/` boards 4, 11, 16 | Structure reference only |

## Tests (write first)

1. The opening state: dataset choice by each of the three rules, sort by distance, State on All,
   the frame on the ring.
2. State filter, search and Find Nearest; Dataset changes the list and sends the remember command.
3. Map and list select together both ways; hover shows the four facts.
4. A failing station shows the warning and attaches with one action and no confirm.
5. With a climate attached the comparison shows, lost edits are counted from
   `climate.get`'s edited cells, and Replace sends one action.
6. A refusal (site not set, file gone, file unreadable) stays in the dialog as a notice and
   nothing is attached.
7. No station value beyond name, location and elevation is in any message the panel sends or
   receives while the picker is open.
8. Browser checks at the three panel sizes; keyboard reach from the list to Attach.

## Host gate

CM09 in [ACCEPTANCE](../ACCEPTANCE.md): Ed at the mouse with a real-size folder.

## Leaves for the next stage

P4c-10 builds the pane the picker closes on, and its Replace and Update from File open this
dialog.

## Done when

CM09 passes and the narrow layout is recorded.

## Departures, 2026-11-18

- **One read for the whole list** (D4c-30): the picker reads `stations.all`, new at API 1.68, not
  `stations.list`. A 1,007-station folder is 19 bounded pages of `stations.list` at about 0.1 s each, and the
  picker shows every station on one map. `stations.all` answers the same rows unpaged, declared
  `response.bounded: false` with `stations.list` preferred, as the Zones and Thermal Bridges panel reads are.
- **Entry check 1**: no separate reading state. The read is synchronous (D4c-21), so the list's empty line
  says "Reading the stations…" until it answers. In Chrome with 1,007 invented stations the picker opened in
  150 to 190 ms, a State filter took about 30 ms and a marker click about 12 ms
  (`tools/ui-preview/climate_picker_checks.cjs`); the host's time is CM09's.
- **Entry check 2** (D4c-29): below 900 px the map sits above the list, both shorter, and the dialog scrolls to
  its sticky Cancel and Attach. Below 500 px the State column gives way to the name (the State filter stays);
  at 360 px the list scrolls sideways inside itself to its Result column.
- **Entry check 3**: no windowing. The table's own `rowHidden` narrows the 1,000 rows; rows are built once and
  a selection repaints two rows and the markers.
- **Test 7, read to D4c-06**: the station reads (`stations.all`) and the attach and replace carry no station
  value beyond key, name, state, place and elevation. In Replace the picker also reads `climate.get` for the
  lost edits, as step 8 and test 5 ask; that is the Model's own climate, not a station file read.
- **Elevation difference**: the size is the host's limit check; its sign (+ above the site, − below) comes from
  comparing the station's and the site's elevations, as boards 4 and 16 draw "+11 m" and "11 m higher".
- **Replace before the attached pane**: P4c-10 builds the pane, but CM09 needs Replace now. The interim
  attached pane gains a Replace Station button; P4c-10 replaces it. Update from File's entry is
  `openPicker({ folder_id, station_key })`, tested and not yet wired.
- **The limits in words** are said in miles and feet in both unit systems ("Within the Phius limits of 50 mi and
  400 ft"), as Set Location says them (P4c-07); board 4 draws km and m. The list's result chip reads Pass or
  Fail, as drawn; the hover tip says "Outside Phius limits", as the card does.
- **The search** is the kit's filter field ("Search stations"); the boards draw none. A State column is in
  the list as step 3 asks; the boards draw none.
- The Phius pane's dataset rule moved to `shared.openingDataset`, so the pane and the picker name the same one.
- **Cases the plan does not name**: a filter that hides the selected station selects the first station it
  leaves, so Attach never takes a station the list and the map do not show; Enter in the search narrows and
  never submits; the list is read again when the site changes, not on every revision; without a site the
  interim Replace Station is disabled with its reason, as the picker needs the site.
