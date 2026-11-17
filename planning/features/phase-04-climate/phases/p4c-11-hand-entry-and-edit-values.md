# P4c-11: Hand entry and Edit Values

DATE: 2026-11-17
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4c-10 and owed check 5. Owns the one editor behind Enter Values by Hand and Edit
Values: a grid in the order of a Phius climate file, filled by one paste or by typing, saved
with gaps; and the pane of a hand-entered climate. It calls `climate.save_values` and holds no
rule: completeness and edited cells come back from Ruby.

Behavior: [PRD](../PRD.md), "An attached climate" (the hand-entry bullets). Names:
[CONTRACTS](../CONTRACTS.md) section 3. Answers: W3, W8, J4, J7, R3; D4c-08. Boards: 12
(`HandEntry`), 20 (`HandEnteredPane`), 15 (`PhiusEdited`, reached from here). Paths are relative
to `src/ph_composer/`.

Load the UI polish skill and its patterns reference first.

## Licensed data

Owed check 5 handles real files. Nothing copied from them is saved, committed, captured or
quoted: the evidence records the shape of the block (rows, columns, separators, labels present
or not) and nothing else. The test fixtures are invented blocks.

## Entry checks

**Owed check 5.** With Ed's own licensed files, before the grid's paste is written:

1. Copy the block from a real Phius `.xls` workbook in Excel and paste it into a scratch page
   that prints the clipboard's shape: row count, column count, separators, whether labels and
   blank columns come with it, and the row order of the eight series.
2. The same from a station text file opened in a text editor.
3. The PRD notes that in one workbook two series rows held twelve values, with no design
   columns. Record whether that is general and what the grid does with a row of twelve: fill the
   months and leave the design cells empty, which saves as Incomplete.
4. Decide from these whether one accepted layout is enough or the paste must also accept a
   block with a leading label column. Record it as a UI decision in
   [DECISIONS](../DECISIONS.md). The grid's row order is the PRD's: outdoor temperature, north,
   east, south, west, global, dewpoint, sky.

## Steps

1. **Editor** (`html/features/climate/values_editor.js`, a `formDialog`). Above the grid: name
   and station elevation, both needed; daily temperature swing and average wind speed, typed
   with no prefill; optional latitude and longitude (board 12).
2. **Grid**: eight series rows by twelve months, then Heating 1, Heating 2 and Cooling. Units
   in the row headings from the unit preference, fixed for the draft when the first key or paste
   lands, as every unit field does. Any cell can be typed; arrow keys and Tab move between cells.
3. **Paste**: one block fills the grid from the focused cell, using `inventory_grid.js`'s
   tab-separated `parse`. A block larger than the grid is refused with a notice and nothing is
   filled; a cell that is not a number is left empty and counted in the notice. A paste is one
   draft change and saves nothing.
4. **Save**: enabled with a name and a station elevation. One `save_values`, one Undo step. It
   saves with gaps (J4); a stale record refuses and the draft stays in the grid.
5. **Edit Values** on an attached station: the same editor opened on the record. On save the
   pane shows the edited marks P4c-10 draws. The name and coordinates of a station are shown
   read-only here; replacing the station is the picker's job.
6. **Hand-entered pane** (board 20): the tables as P4c-10 draws them, with no edited mark and no
   source block; Incomplete on the card with the list of what is missing from `climate.get`;
   the limit check as for a station when coordinates were typed, else "Not checked, entered by
   hand".
7. **Enable the buttons** P4c-08 left disabled.
8. **Docs.** `docs/PRODUCT.md` gains entering a climate by hand, including that stations
   outside the USA come in this way from a Phius workbook (R3) and export as user-defined.

## Source

| File | Disposition |
| --- | --- |
| `html/inventory_grid.js` (`parse`, the paste listener), `html/unit_field.js`, `html/record_edits.js` | The paste and the cell editing; reused, extended only if the grid needs a kit part of its own |
| `html/overlay.js` (`formDialog`) | Reused |
| `mockups/canvas/project/` boards 12, 20 | Structure reference only |

## Tests (write first)

1. A complete synthetic block pasted at the first cell fills all 120 cells; pasted elsewhere it
   fills from there; an oversized block is refused whole.
2. A block with gaps, and a row of twelve values, fill what they hold and leave the rest empty.
3. Save is disabled without a name or a station elevation; with them it sends one action whose
   values match the grid in SI, in both display profiles.
4. A saved climate with gaps reads Incomplete with the missing cells named; completing it
   clears the mark.
5. Without coordinates the check reads Not checked, entered by hand; with them it runs.
6. Edit Values on a station changes one cell, the pane marks it, and Restore clears it.
7. A stale save refuses and the grid keeps the draft.
8. Keyboard: every cell reachable; browser checks at the three panel sizes, the grid scrolling
   inside the dialog.

## Host gate

CM11 in [ACCEPTANCE](../ACCEPTANCE.md): the paste from a real workbook and a real text file into
the real panel, by Ed, with nothing from them kept.

## Leaves for the next stage

P4c-12 closes the register.

## Done when

CM11 passes and owed check 5 is recorded by shape only.
