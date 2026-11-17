# P4c-08: Climate Data on This Computer and the Phius pane's empty states

DATE: 2026-11-17
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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
