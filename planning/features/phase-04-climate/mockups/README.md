# Climate tab wireframes

DATE: 2026-11-15
STATUS: Reviewed. Drawn 2026-11-15 from Ed's request for a Climate tab that works like PH-Navigator's, with climate data loaded from a folder on the user's computer. Ed answered all nine questions below on 2026-11-15 and 2026-11-16, and the [PRD](../PRD.md) was revised to them (its W1 to W9). Static wireframes, not a screen; no panel code.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Seven static artboards. The [PRD](../PRD.md) is the behaviour; these illustrate it. All station names, coordinates and values are synthetic; no
licensed climate data is in this folder.

## Viewing

- Local: `make ui-preview`, then open
  `http://127.0.0.1:8765/planning/features/phase-04-climate/mockups/`. `index.html`
  frames each artboard with the panel's own stylesheets and shows its notes beneath it.
  `?board=Main` shows one board, named by its file without `.dc.html`.
- Design canvas: the same files are published to a private Design canvas built on the PH-Composer
  Design System. `canvas/project/` is its source: `canvas.json` is the index and each `*.dc.html`
  is one artboard. The `support.js` and `ds/` paths in an artboard resolve only on the canvas.

## Boards

| # | File | Shows |
| --- | --- | --- |
| 1 | `Main.dc.html` | The Climate tab with Site location selected and Set Location open: typed coordinates, elevation and climate zone, and Read from SketchUp Geolocation |
| 2 | `PhiusEmpty.dc.html` | Phius climate data selected on a computer with no climate folder |
| 3 | `DataSetup.dc.html` | Climate data on this computer: the folders, what was found in each, the files not read by kind, and what is kept where. Updated for journey J1 |
| 4 | `Picker.dc.html` | Set Phius climate data: every station on an outline map, the site, the 50 mile ring, a State filter, the verdict and Attach |
| 5 | `PhiusAttached.dc.html` | An attached station: the limit check, monthly temperatures and radiation, peak loads, and where the data lives |
| 6 | `OtherComputer.dc.html` | The same Model on a computer with no climate folder |
| 7 | `Narrow.dc.html` | The tab at 420 px wide |

Not drawn: the Design temperatures card's own screen, entering values by hand, scanning in progress, a folder
that has moved, a station file that changed since it was attached, charts, and the 360 x 520 size.

## How it is meant to work

1. The user names one or more folders of climate files on their own computer. PH-Composer reads
   every recognised station file under a folder, subfolders included; a Phius station's state is
   the name of the folder it sits in.
2. Each folder's location and the name the user gives it are kept in PH-Composer's own settings
   file in the user's folder on that computer, read by every SketchUp version (settled
   2026-11-15). No list of stations is stored; the folder is read when the station picker opens.
3. Attaching a station copies its values into the Model with the dataset name, the station name
   and a checksum, and no folder path. That is the PRD's snapshot rule.
4. The Model then reads in full on any computer. Only replacing the station needs the folder.

## Decisions for Ed

| # | Question | Drawn as |
| --- | --- | --- |
| 1 | The map. The panel reaches no network (`context/TECH_STACK.md`, "Panel"), so web map tiles cannot load | Settled 2026-11-16: an outline map shipped with the extension, with world countries and US and Canadian state and province borders from public-domain data; no web tiles. Pan and zoom, click a station to select it, hover for its details, click to place the site in Set Location. Revises the PRD's "does not host a climate map"; "no map tiles" stands |
| 2 | Location with no network: no address search, elevation lookup or climate-zone lookup | Typed fields and a one-way read from SketchUp's geolocation (PRD Q5, Q6) |
| 3 | Which sources. The PRD has user-owned monthly files, a local EPW and manual paste, with peak loads supplied separately | Settled 2026-11-16: separate cards as PH-Navigator, for Phius climate data and an Hourly weather file; no PHI for now. In the first version Phius climate data is the only climate and the one that exports, set from a station in the folder or typed and pasted by hand. The Hourly weather file card is shown as Planned; the PRD's EPW route waits for it |
| 4 | Design temperatures. The Phius heat pump estimator's derating reads the ASHRAE 99% heating and 1% cooling dry bulb for the location, and a Phius station file carries neither | Settled 2026-11-16: two typed values on their own card. Export does not wait on them; without them only the blended heat pump is left out, with a finding |
| 5 | Where the folder setting lives | Settled 2026-11-15: a dialog opened from the Climate tab, also listed in the Setup view with a one-line summary. The setting is stored in PH-Composer's own settings file, not SketchUp's preferences; the user types the dataset name, prefilled from the folder's name; the first version recognises Phius station files only |
| 6 | The record kind: the PRD's `climates` library kind through the provider seam, or a separate folder source | Settled 2026-11-16 (code): Climate is its own feature, not a Library kind. A Model holds one site and one Phius climate, which is what exports; replacing the station is one Undo step. One built-in Phius reader now; a registered format contract waits until the hourly weather file gives a second example. Revises the PRD's Q3 and its "Library provider seam" row |
| 7 | A primary Climate tab, and where it sits | Settled 2026-11-16: the first tab, before Zones: Climate, Zones, Assemblies, Window Types, Thermal Bridges, Programs, Mechanical, Library, Export. Open: which tab the panel opens on, since Zones is where most work happens |
| 8 | What a Phius station file does not supply: ground temperatures, a second cooling case, one annual wind speed | Settled 2026-11-16: three peak-load cases is the complete set for a Phius station and Cooling 2 stays empty; ground temperatures stay empty and unflagged; average wind speed is typed, prefilled with the mean of the file's January and July values. A station's values may be edited after attaching, and the source is then marked as edited in the tab and the Export report. Whether export must write a placeholder for the empty slots is settled with the export stage |
| 9 | Where the packet sits | Settled 2026-11-15: promoted to Phase 4, ahead of Mechanical |

## Using these during the build

These are the reference for the screens when the stages are built. They are static markup, not
panel code: nothing here is copied into `src/`.

- The [PRD](../PRD.md) owns behaviour. Where a board and the PRD differ, the PRD wins and the
  board is corrected.
- Each board uses the panel's real class names and stylesheets, so its structure (page header,
  subtabs, inventory controls, table, dialog) is the structure to build. Classes defined in a
  board's own `<style>` block are wireframe-only stand-ins for parts the kit does not have yet.
- The notes in `canvas/project/canvas.json` hold what was settled against each board and when.
- Before building a screen, load the UI polish skill and check the board at the panel's three
  sizes; only 1280 x 800 and one 420 px board are drawn.

Kit parts these boards assume and the panel does not have yet: the source cards in the sidebar,
the outline map with its markers, ring, zoom buttons and hover tip, and the station list rows.

## Checked

Every board loads in the local viewer at its own size with no console error. The Design canvas
rendering was not checked.
