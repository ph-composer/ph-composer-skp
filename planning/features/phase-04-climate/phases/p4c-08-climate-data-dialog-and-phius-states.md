# P4c-08: Climate Data on This Computer and the Phius pane's empty states

DATE: 2026-11-17
STATUS: Merged to main 2026-11-18 (PR #519, `7bcb6672`); CM08 agent run Pass, Ed's pass pending. Authorized with every Climate stage on 2026-11-17 ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Entry and scope

Requires P4c-03, P4c-04 and P4c-06. Owns the Climate Data on This Computer dialog, its route
from the Setup view, and the Phius climate data pane while nothing is attached. The picker is
P4c-09 and the attached pane P4c-10.

Behavior: [PRD](../PRD.md), "Climate data on this computer" and "Choosing a station" (the first
three bullets). Names: [CONTRACTS](../CONTRACTS.md) sections 5 and 6. Answers: W5, J1, J3, J6,
R4; D4c-10; C4c-3. Boards: 2 (`PhiusEmpty`), 3 (`DataSetup`), 9 (`PhiusNeedsSite`), 10
(`PhiusReady`), 14 (`DataSetupMoved`). Paths are relative to `src/ph_composer/`.

Load the UI polish skill and its patterns reference first.

## Entry checks

1. C4c-3: read `shell/setup_entries.rb` and `shell/panel.rb` and fix how the Setup entry's Ruby
   handler opens a dialog that lives in the panel.
2. Read `html/library/setup.js` for how the Library's setup dialog runs a setup command through
   the native chooser and settles its result; follow it.
3. Check boards 3 and 14 at 420 and 360 px, which are not drawn.

## Steps

1. **The dialog** (`html/features/climate/data_setup.js`, a `formDialog`): one row per folder
   with its name, display location, format, stations and states, and the files not read grouped
   by kind ("1,150 Excel files, 4 other"), so other formats do not read as a failure. It reads
   `folders.list` each time it opens. There is no Rescan and no notice of new stations (J1, R4).
2. **Add Folder**: runs `folders.add`; the native chooser opens; the new row appears with its
   name open for editing, prefilled from the folder (D4c-10); committing runs `folders.rename`.
   A cancelled chooser changes nothing. An overlapping folder shows the refusal.
3. **Remove**: in the row's actions, with the shared confirm naming the dataset and saying that
   Models keep their climates.
4. **A folder not found** (board 14): the row says so and offers Locate (`folders.locate`) and
   Remove. Nothing is removed automatically.
5. **What is kept where**: the dialog's closing block, as the PRD words it.
6. **Setup view entry**: `feature.menu_item("ph_composer.climate.data.open", label: "Climate
   Data on This Computer…", menu: "Climate", in_setup: true, summary:)`, with the summary from
   P4c-03 and P4c-04. Its button opens this dialog (C4c-3). A summary that raises leaves the
   entry showing, as the contract says.
7. **Phius climate data pane, nothing attached**:
   - no folder (board 2): says so, says why PH-Composer ships none, and offers Choose Climate
     Data Folder and Enter Values by Hand;
   - a folder and no site (board 9): asks for the site first and offers Set Location; Enter
     Values by Hand stays available;
   - a folder and a site (board 10): names the dataset and its station count and offers Choose
     Station and Enter Values by Hand.
   Choose Station and Enter Values by Hand are wired in P4c-09 and P4c-11; until then they are
   present and disabled with their reason, so the pane's layout is final here.
8. **Docs.** `docs/PRODUCT.md` gains setting up climate data, written for an outside reader:
   what PH-Composer reads, that it copies nothing, and what a licence means for the user.

## Source

| File | Disposition |
| --- | --- |
| `html/library/setup.js`, `library/setup_commands.rb` | Pattern for a setup dialog driving approved commands |
| `html/overlay.js` (`formDialog`), `html/table.js` | Reused |
| `html/sections/setup.js`, `shell/setup_entries.rb` | The Setup view route |
| `mockups/canvas/project/` boards 2, 3, 9, 10, 14 | Structure reference only |

## Tests (write first)

1. The dialog lists folders from a stubbed `folders.list`, with counts and not-read kinds
   worded as the PRD has them; a folder with only other formats reads as zero stations, not as
   an error.
2. Add Folder sends the setup command and opens the name for editing on the answer; a cancel
   and a refusal each leave the list unchanged with the right notice.
3. A folder not found shows Locate and Remove; Locate repairs the row.
4. The dialog reads the list again on every open and shows no Rescan control.
5. The three pane states follow the summary and the folder list; the site-first state offers
   Set Location and opens P4c-06's dialog.
6. The Setup view's button opens the dialog on the Climate tab.
7. Browser checks at the three panel sizes.

## Host gate

CM08 in [ACCEPTANCE](../ACCEPTANCE.md): Ed at the mouse with a real folder; UI polish review
recorded.

## Leaves for the next stage

P4c-09 enables Choose Station; P4c-11 enables Enter Values by Hand.

## Done when

CM08 passes and C4c-3 is answered.

## Departures, 2026-11-18

- **C4c-3** (D4c-27): the handler calls `session.open_in_panel(owner, intent)`. The shell shows the panel and
  sends `panel.navigate` with the owner and the intent, held in `shell/panel_outbox.rb` with the session's
  notices until the page has started and shows that Model; the page finds the tab with `panel.tabFor(owner)`,
  so Ruby names no tab. The same handler serves the Setup view and the Extensions menu with the panel closed.
  Moving the waiting notices into the outbox kept `Panel` within its 300-line limit.
- **The pane's cases the plan does not name** (D4c-28): a folder set up but not found counts as none, and the
  no-folder state then says the folder cannot be found and offers the dialog instead of Choose Climate Data
  Folder; board 10 names the dataset the picker opens on (the one used last if found, else the first found that
  holds stations, else the first found). Settings that cannot be read show their message with only Enter Values
  by Hand. The pane reads `folders.list` each time it is shown and after the dialog closes; the list is not a
  snapshot section, because it walks the disk.
- **Choose Climate Data Folder** opens the dialog and starts Add Folder at once, so the name is asked in the
  row as D4c-10 has it.
- **One primary in the dialog**, as the Library's setup dialog has it: Add Folder while no folder is set up,
  Done once one is. Board 3 draws Add Folder primary always. The board's footer hint moved above the "kept"
  block, so the footer holds only its two buttons.
- **Rename** is a pencil on the row, shown on hover or focus (always below 1040 px), with the same check and
  cross as a Window Type's name; boards 3 and 14 draw none. Remove and Locate are text buttons, as drawn.
- **Entry check 3**: below 1040 px the dialog's rows stack, each value after its label, because the seven
  columns stop fitting the dialog there; the browser check measures 1280, 1060, 800, 420 and 360 px.
- **Words not on the boards**: a folder with no station files reads "No station files"; a folder read only in
  part and a folder not found each get a line below the table; a row's Remove asks "Remove <name>?" and says
  the folder and its files are not touched and Models keep their climates. Kinds not read are named for Excel,
  CSV, PDF, EPW, text and zip files, and the rest are "other".
- **"Absent from the picker"** is held by `stations.list` refusing `climate.folder_not_found` for a folder that
  is gone (`tests/climate_stations_test.rb`); the picker is P4c-09's.

