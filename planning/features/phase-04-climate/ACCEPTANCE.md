# Phase 4 acceptance register: Climate

DATE: 2026-11-17
STATUS: Scoped. CM01 to CM11 are written; CM12 follows the closing stage. Nothing run.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

The [PRD](PRD.md) supplies the behavior and its acceptance shape; this register supplies one
closure gate per stage. Record a source-controlled evidence summary per stage under `evidence/`
(commit, build, fixtures, checks, exact host versions, remaining limits). SKP files and captures
stay in `_private/`, and so does anything read from the private climate corpus.

Ids use the prefix CM; the prefixes in [`native-acceptance/cases.json`](../../native-acceptance/cases.json)
are taken (read 2026-11-17). Each host case is added to that file when its stage is authorized
and recorded with `acceptance_case.py begin` and `finish` so its ledger row is a Pass.

| ID | Owner, stage | Required evidence | State |
| --- | --- | --- | --- |
| CM01 | Climate, units, P4c-01 | The feature installs and declares its codes; the new quantities convert both ways and agree between Ruby and JavaScript on the shared vectors; a new Model reads site Not set with no write; a site update with one or two of latitude, longitude and elevation refuses and writes nothing; the ten zone codes accept and any other refuses; hours from UTC is stored only as typed; each design temperature saves alone as one Undo step, clears to null, and reads Not set, Incomplete or Set, with the warning when heating is at or above cooling; a stale `expected_values` refuses. Host: the panel-closed walkthrough, Undo, Redo, save and fresh reopen | Not started. Case `CM01` added to `cases.json`; [recipe](evidence/cm01-recipe.md) prepared |
| CM02 | Climate, P4c-02 | The climate kind round trips; no key holds a path; a hand-entered climate saves with gaps and reads Incomplete with what is missing; complete follows D4c-08; edited cells are exactly the differences from the as-read copy and never include wind speed; Restore returns the as-read values and refuses for a hand-entered climate; Clear deletes the climate and leaves the site and design temperatures; an edit and a Restore each rewrite the stored provenance with the values; each is one Undo step. The limit check: pass and fail on each limit alone at the boundary, Not checked with no site and with no station coordinates, and a changed site changes the verdict with nothing stored. Host: Undo, Redo, save and fresh reopen | Not started |
| CM03 | Shell, Climate, P4c-03 | The macOS half of owed check 1 recorded. The settings file is created on first write in the PH-Composer folder outside SketchUp's folders; add, rename, locate and remove each survive a restart; two processes writing different sections lose neither; an unreadable file is left as stored and reported; a scripted add with no approval is refused; no path appears in an operation's params, result or the diagnostic log; the Setup summary reads each state; on a platform other than macOS the service is unavailable. Host: SketchUp 2026 on macOS, restart and reread. Windows and a second SketchUp version are deferred (E3) | Not started |
| CM04 | Climate, P4c-04 | Owed check 3 recorded. On the synthetic folder: stations, states and files not read are counted by kind; a stray `-mon` variant and a malformed file are not stations; Windows-1252 text reads correctly; the list gives distance, elevation difference and verdict against the site; attach copies the values, the as-read copy, the source and the wind-speed prefill in one Undo step, and refuses with no site; attach over an existing climate replaces it in one Undo step; source status reads found, changed and not on this computer, matched across folders whatever they are named; attach runs with the panel closed. The private-corpus test skips when its variable is unset. Host: a real-size folder's read time, and a cloud-synced folder | Not started |
| CM05 | Climate, export, P4c-05 | Owed check 6 recorded. The HBJSON reloads in the pinned stack with the same `Site` on every Building Segment; Cooling 2 equals Cooling 1; an unset zone writes Not defined and an unset offset writes empty, each with its finding; an unedited station is `phius_approved`, an edited one and a hand-entered one `user_defined`; assumptions carry the station's coordinates and the edited values; `source_uri` is absent; an incomplete climate and a climate with no site are left out with their findings and the export still runs; a site with no climate writes its `Location` over honeybee-ph's default `Climate` with no finding, and a Model with neither leaves honeybee-ph's default `Site` with no finding and no remark in the report (E1, E2); the stored provenance is passed through; a failing station and a hand-entered climate without coordinates carry theirs; the report's climate section shows every line of board 18 and the design temperatures, and no folder location is in the HBJSON, the report or the result. Round trip: WUFI XML and METr JSON from the pinned PHX with the four peak-load cases read back | Not started |
| CM06 | Climate, UI kit, P4c-06 | Owed check 4 recorded. Climate is the first tab and the panel still opens on Zones; the sidebar cards show their states and the Hourly weather file card reads Planned and does nothing; Site location reads Not set on a new Model; Set Location sets the site from typed values in one Undo step and refuses a partial site in the dialog; Read from SketchUp Geolocation fills what the host check proved and never elevation; the design temperatures commit per field; IP and SI; the tab row and both panes at 420 and 360 px. UI polish review recorded; Ed at the mouse | Not started |
| CM07 | UI kit, Climate, P4c-07 | Owed check 2 recorded: the data's source, licence and version, the bytes it adds to the RBZ, and its draw time on the Chromium 88 floor. The map pans, zooms and resets; a click in Set Location places the site and fills latitude and longitude; with a station attached the map shows it with its ring and warns before a Set that would make it fail; the page reaches no network and reports no content-policy violation; keyboard reach for zoom and for placing by typed values. Ed at the mouse | Not started |
| CM08 | Climate, UI, P4c-08 | Climate Data on This Computer lists each folder with name, location, format, stations, states and files not read by kind; Add Folder, the name edit, Remove; a folder not found offers Locate and Remove and its stations are absent from the picker; no Rescan and no new-station notice; the dialog opens from the tab and from the Setup view, whose entry shows its summary; the Phius pane reads its three empty states (no folder, no site, ready). UI polish review recorded; Ed at the mouse | Not started |
| CM09 | Climate, UI, P4c-09 | The picker opens sorted by distance, framed on the 50 mile ring, State on All, on the attached station's dataset or the last used; Find Nearest; the State filter; Dataset; map and list select together; hover details; a failing station shows the warning before Attach and attaches with no confirm; with a station attached the two are compared, lost edits are named and Replace is one Undo step. Ed at the mouse | Not started |
| CM10 | Climate, UI, P4c-10 | The pane shows station, dataset, limit check, monthly temperatures and radiation, peak loads with Cooling 2 marked as not part of a Phius file, wind speed and Where this lives; edited cells are marked and Restore Original Values clears them; a changed source file shows the quiet mark and Update from File; with no folder the pane reads in full with no notice and Replace explains; a failing station reads as outside the Phius limits; Clear is one Undo step with no confirm; IP and SI; 420 and 360 px. Ed at the mouse | Not started |
| CM11 | Climate, UI, P4c-11 | Owed check 5 recorded, with nothing from the real files kept. One paste of a synthetic block fills the grid; any cell types; the name and station elevation are needed to save; it saves with gaps, the card reads Incomplete and the pane lists what is missing; without coordinates the check reads Not checked, entered by hand; the same editor opens for Edit Values and marks the station edited; a stale save refuses and the grid keeps the draft. Ed at the mouse | Not started |
| CM12 | Integration, P4c-12 | Both offline Ruby gates, coverage, browser and runtime checks; packaged footprint against the current baseline; the PRD's acceptance shape from a fresh process, end to end, on SketchUp 2026 (the second-version step is deferred, E3); context, docs and glossary folded; Mechanical's reads confirmed | Not started |

## Native host cases

What must be seen in a real SketchUp, beyond the offline suite. Each is part of the register row
named.

| Case | Row | What the host proves |
| --- | --- | --- |
| Undo names and steps | CM01, CM02, CM04 | Each action is one entry in Edit > Undo under its declared name; Redo restores it |
| Save and reopen | CM01, CM02 | The site, the climate with its as-read copy and the design temperatures read back from a saved SKP in a fresh process |
| The settings folder | CM03 | Owed check 1, macOS half: the application-support folder as SketchUp 2026's Ruby sees it, outside the versioned folder, writable and reread after a restart |
| Folder chooser | CM03 | `UI.select_directory` through the approval route returns a folder and nothing is logged |
| Read time | CM04 | Owed check 3: a real-size folder in SketchUp's Ruby, cold and warm; a cloud-synced folder with files not downloaded |
| Geolocation | CM06 | Owed check 4: an ungeolocated Model and a geolocated one |
| Map on the floor | CM07 | Owed check 2: the map in the real HtmlDialog on the current host. The Chromium 88 floor is held by the ESLint API list and the browser evidence tool; a SketchUp 2023 run belongs to the [2023 floor](../unscheduled/sketchup-2023-floor/README.md) packet |
| Clipboard | CM11 | Owed check 5: a block copied in Excel and in a text editor pastes into the real panel |
| Packaged export | CM05, CM12 | The RBZ build exports and the report opens with its climate section |

## Synthetic reference data

Public fixtures stay synthetic. No station name, coordinate or value comes from a licensed file.

1. **Climate data folder**: `tests/fixtures/climate/folder/` with state subfolders and Phius-shaped
   `-mon.txt` files of invented stations: at least one passing and one failing each limit from the
   reference site, one near-duplicate name (`-mon2.txt`), one malformed file, one `.xls`-named
   file and one unrelated file, so every count has a case. One file holds a non-ASCII
   Windows-1252 character in its name line.
2. **Second folder** with one station of the same name and state and different values, for
   Source changed and for matching across folders.
3. **Reference site**: a typed latitude, longitude and elevation chosen so the fixture stations
   fall on both sides of each limit.
4. **Paste block**: a tab-separated block in the grid's order, complete, and a second with gaps.
5. **Reference Model**: a synthetic Model with two Building Segments, to prove one `Site` on
   each.

The private corpus is used only by tests that skip without it, for real-size read time and for
owed check 5. Its location is recorded only in the gitignored `_private/climate/MANIFEST.md`.
