# P4c-09: The station picker

DATE: 2026-11-17
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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
