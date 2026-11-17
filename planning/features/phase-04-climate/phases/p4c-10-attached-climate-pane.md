# P4c-10: The attached climate pane

DATE: 2026-11-17
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4c-09. Owns the Phius climate data pane once a climate is in the Model: what it shows,
the marks for an edited and for a changed source, and the actions Replace, Update from File,
Restore Original Values and Clear. The editor that Edit Values opens is P4c-11; this stage
places the button.

Behavior: [PRD](../PRD.md), "An attached climate". Names: [CONTRACTS](../CONTRACTS.md) sections
3, 4 and 6. Answers: W8, J3, J6, J7. Boards: 5 (`PhiusAttached`), 6 (`OtherComputer`), 15
(`PhiusEdited`), 17 (`SourceChanged`), 19 (`PhiusFailAttached`); 7 and 23 for the narrow sizes.
Paths are relative to `src/ph_composer/`.

Load the UI polish skill and its patterns reference first.

## Entry checks

1. Apply the page-header action rule from the UI polish skill to this pane's five actions
   (Replace, Edit Values, Restore Original Values, Update from File, Clear) and record which is
   primary and which sit in the overflow. The boards are the starting point.
2. Check the monthly tables at 420 and 360 px: twelve month columns do not fit. Decide between
   horizontal scroll inside the table and a transposed table, and record it as a UI decision in
   [DECISIONS](../DECISIONS.md).
3. Confirm `climate.source_status` is cheap enough to ask each time the pane is shown; it reads
   the disk (P4c-04's measurement).

## Steps

1. **Header**: the station or typed name, the dataset, and the card's state tags: Pass, Outside
   Phius limits, Edited, Incomplete, Source changed.
2. **Limit check block**: distance and elevation difference, each against its Phius limit, and
   the verdict (boards 5 and 19). A failing station reads as outside the Phius limits, with one
   line that Phius asks for a custom dataset beyond them. It is worked out from `climate.get`
   each time and follows a site change with no action here (J7).
3. **Values**: monthly temperatures (air, dewpoint, sky), monthly radiation (north, east, south,
   west, global), and peak loads (Heating 1, Heating 2, Cooling 1) with a Cooling 2 column shown
   as not part of a Phius file; station elevation, daily swing, and the wind speed as an
   editable field with its prefill noted (W8). Read-only tables through the unit preference.
4. **Edited marks** (board 15): each edited cell is marked, with its as-read value on hover; the
   header's Edited tag; Restore Original Values runs `restore_original` in one Undo step. A
   wind-speed change marks nothing.
5. **Where this lives**: what the Model holds; whether the source is on this computer, from
   `source_status`; what the climate is ready for (export, and the heat pump when the design
   temperatures are set).
6. **Source changed** (board 17): a quiet mark and Update from File, which opens the picker's
   Replace view on the matched station. Nothing updates on its own.
7. **Another computer** (board 6): with no folder the pane reads in full with no notice; only
   Where this lives says the source is not on this computer. Replace stays enabled and, with no
   folder, explains and offers Choose Climate Data Folder and Enter Values by Hand (J6).
8. **Clear**: `climate.clear`, one Undo step, no confirm; the pane returns to P4c-08's state.
9. **Docs.** `docs/PRODUCT.md` gains reading an attached climate, the edited mark and what
   another computer sees; the Design System re-sync if the kit changed.

## Source

| File | Disposition |
| --- | --- |
| `html/table.js`, `html/page_header.js`, `html/overlay.js` (`ActionMenu`, `Bubble`) | Reused |
| `html/features/climate/` from P4c-06, P4c-08 and P4c-09 | The frame, the empty states and the picker |
| `mockups/canvas/project/` boards 5, 6, 15, 17, 19 | Structure reference only |

## Tests (write first)

1. The pane renders a station-origin record: every table, the limit block, the Cooling 2 column
   marked as not part of the file.
2. A failing verdict, a changed site and no site each show their limit block state.
3. Edited cells are marked from `edited_cells`; Restore sends one action; a wind-speed edit
   sends `save_values` and marks nothing.
4. Source status found, changed and not on this computer each show their Where this lives line;
   changed shows Update from File; none of the three raises a notice.
5. With no folder, Replace opens the explanation with its two choices.
6. Clear sends one action with no confirm.
7. IP and SI on every value; browser checks at the three panel sizes.

## Host gate

CM10 in [ACCEPTANCE](../ACCEPTANCE.md): Ed at the mouse; UI polish review recorded.

## Leaves for the next stage

P4c-11 wires Edit Values and Enter Values by Hand, and the pane of a hand-entered climate.

## Done when

CM10 passes and the narrow table layout is recorded.
