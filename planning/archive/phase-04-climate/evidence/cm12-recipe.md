# CM12 host recipe: the integrated run, with the CM01 to CM03 rechecks

DATE: 2026-11-18
STATUS: Run 2026-11-18 on `1ca85729`: part A by the stage agent, part B by the conductor, all as expected ([evidence](cm12-20261118.md)). Part C is Ed's verification pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM12](../ACCEPTANCE.md) on the final head of P4c-12, SketchUp 2026 on macOS, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md), and in the same
run the rechecks of CM01, CM02 and CM03, whose ledger rows read `needs_recheck` after later stages. Each case is
in [`cases.json`](../../../native-acceptance/cases.json) and is begun and finished on its own fixture. Write
`<run>` as `cm12-<yyyymmdd>`. Synthetic data only: the invented folder `tests/fixtures/climate/folder/`
(stations around the reference site 40.0, -100.0, 500 m), the private synthetic Models `blank-template.skp`
and `envelope/reference-assigned.skp`. Nothing is read from the licensed corpus.

`B` stands for `uv run tools/hostkit/host_bridge.py` (in zsh, a wrapper script); `D` for the absolute path of
`_private/host/<run>/driver/`. The drivers there are `cm12.rb` (composed from the CM05 to CM11 drivers),
`cm03.rb` and `external_writer.rb` (CM03's, with its folders in `folders-cm03/`). Each `B eval` is its own call,
so the panel's timers run between them; a panel read posts its answer, read with `CM12.result('<name>')` in
the next call. Labelled development arrangements, as in the drivers' headers: the DOM probe on the panel's
own callback, scripted DOM events in the real HtmlDialog, the folder chooser stood in once per add, the Export
tab's approval stood in, the reference fixture's one Face given its Assembly again (CM05), and in part A only,
SketchUp's geolocation stood in by `ShadowInfo` and `GeoReference`'s `UsesGeoReferencing` (owed check 4).

**What it touches.** The cases write this computer's settings file, `~/Library/Application Support/PH-Composer/`,
and CM03's steps rename, relocate and remove every listed folder. So every case runs from no settings folder:
A0 moves an existing one aside into the run folder, and the run ends (B7) by removing what the cases left and
moving it back, checked byte for byte.

## Part A: the bridge, no window focus (the stage agent)

### A0. Build and install the final head

```sh
pgrep -x SketchUp || echo none           # none: the gate and the host share port 46110
make rbz install bridge-install
P="$HOME/Library/Application Support/PH-Composer"
if [ -d "$P" ]; then mv "$P" _private/host/<run>/settings-before; fi   # noted: moved aside or absent
ls "$P" 2>/dev/null || echo absent
```

Every case below runs on A0's installation of the final head. Where a referenced recipe's step 1 checks out a
branch or runs `make rbz install bridge-install`, leave that out: only its launch, `state` and `begin` apply.

### A1. CM03: the settings file, panel closed

Its [recipe](cm03-recipe.md) steps 1 to 6 (step 7 and the cleanup of step 8 come in B6), with `--control native` and its eight assertions, the fixture
`_private/host/<run>/CM03/cm03.skp` from `blank-template.skp`, `D/cm03.rb` for its driver and
`D/external_writer.rb` for the second process. Quit SketchUp.

### A2. CM01: the walkthrough and save and reopen

Its [recipe](cm01-recipe.md) steps 1, 2 and 4 on `_private/host/<run>/CM01/cm01.skp`, launched with
`--fresh-from _private/host/blank-template.skp`: `begin CM01` with its four
assertions, `ClimateSiteWalkthrough.state` and `.run` (seven steps), then `B save`, `B quit`, `B launch` the same
file and `ClimateSiteWalkthrough.verify` with nothing run first. Undo and Redo are part B.

### A3. CM02: the walkthrough and save and reopen

Its [recipe](cm02-recipe.md) steps 1, 2 and 4 on `_private/host/<run>/CM02/cm02.skp`, launched with
`--fresh-from _private/host/blank-template.skp`: `begin CM02`, `state`,
`run_hand` (eight steps), `ClimateStationSeed.seed`, `run_station` (ten steps), then save, quit, launch and
`ClimateWalkthrough.verify`. Undo and Redo are part B.

### A4. CM12: begin, from a fresh process

```sh
B launch "$PWD/_private/host/<run>/CM12/cm12.skp" --fresh-from _private/host/envelope/reference-assigned.skp
B state       # SketchUp 2026, the installed build, cm12.skp the only document
uv run tools/hostkit/acceptance_case.py begin CM12 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM12/cm12.skp --fixture-id "fresh copy of envelope/reference-assigned.skp" \
  --control combined --assert folder --assert site-typed --assert site-map --assert site-geolocation \
  --assert picker --assert attach --assert reopen-no-folder --assert replace --assert edit --assert hand \
  --assert design --assert export --assert privacy --assert mechanical --assert polish \
  --window "cm12.skp the only document in a fresh process" \
  --target "a two-Zone reference Model with no site and no climate; a synthetic climate data folder" \
  --probe "the probe.dom read on the panel's own callback; scripted DOM events; labelled stand-ins"
B eval "load '$D/cm12.rb'; CM12.state"     # site not_set, climate none, no folders, geolocated false
B eval "CM12.repair_fixture"                # assign completed; blocking []
```

### A5. Add the folder and read its counts (board 3)

```sh
B eval "CM12.make_folder"; B eval "CM12.open_panel"; B eval "CM12.click_tab('climate')"; B eval "CM12.click_card('phius')"
B eval "CM12.click(CM12::HEAD, 'Climate Data on This Computer…')"
B eval "CM12.choose_next"; B eval "CM12.click(CM12::DATA, 'Add Folder…')"
B eval "CM12.name_folder('Synthetic Dataset')"; B eval "CM12.data"
#   one row, Synthetic Dataset, with its stations, states and files not read by kind as CM12.folders
#   gives them: the -mon2.txt variant, the malformed file and the .xls file are not stations; no Rescan
B eval "CM12.folders"; B eval "CM12.click(CM12::DATA, 'Done')"
```

### A6. Set the site three ways (boards 1, 21, 22)

```sh
# typed (with no site, Set Location… is in the Phius pane; once a site is set, it is in the page header
# while the Site location card is selected)
B eval "CM12.click(CM12::PANE, 'Set Location…')"
B eval "CM12.fill(CM12::SETLOC, 'Latitude', '41.5')"; B eval "CM12.fill(CM12::SETLOC, 'Longitude', '-99.0')"
B eval "CM12.fill(CM12::SETLOC, 'Elevation', '450')"; B eval "CM12.setloc"
B eval "CM12.click(CM12::SETLOC, 'Set Location')"; B eval "CM12.state"     # site set, 41.5, -99.0, 450
# a click on the map (scripted pointer events; the real click is B1)
B eval "CM12.click_card('site')"; B eval "CM12.click(CM12::HEAD, 'Set Location…')"; B eval "CM12.press_map(60, 40)"; B eval "CM12.setloc"
#   latitude and longitude changed from 41.5 and -99.0; elevation kept
B eval "CM12.click(CM12::SETLOC, 'Set Location')"; B eval "CM12.state"
# SketchUp's geolocation (stood in), the elevation typed
B eval "CM12.geolocate"                     # georeferenced true; read 40.0, -100.0, hours null
B eval "CM12.click(CM12::HEAD, 'Set Location…')"; B eval "CM12.click(CM12::SETLOC, 'Read from SketchUp Geolocation')"
B eval "CM12.setloc"                        # Latitude 40, Longitude -100; Elevation not filled by the read
B eval "CM12.fill(CM12::SETLOC, 'Elevation', '500')"; B eval "CM12.click(CM12::SETLOC, 'Set Location')"
B eval "CM12.state"                         # site 40.0, -100.0, 500: the reference site
B eval "CM12.click_card('phius')"
```

### A7. The picker: nearest, a passing and a failing verdict, attach (boards 4, 11)

```sh
B eval "CM12.click(CM12::PHIUS, 'Choose Station…')"; B eval "CM12.picker"
#   open; sorted by distance; XB/CAFE_STATION-mon.txt first
B eval "CM12.find_nearest"; B eval "CM12.picker"      # selected XB/CAFE_STATION-mon.txt; within true
B eval "CM12.pick('XB/OUTSIDE_ELEVATION-mon.txt')"; B eval "CM12.picker"   # outside true; warning true
B eval "CM12.pick('XB/CAFE_STATION-mon.txt')"; B eval "CM12.submit_picker"
B eval "CM12.climate"                                 # complete; station CAFE_STATION; verdict pass; edited 0
```

### A8. Save, remove the folder's setting, reopen (boards 6, 14)

```sh
B eval "CM12.snapshot('attached')"          # the whole climate.get value, as_read and provenance, to CM12/attached.json
B save; B eval "CM12.remove_folders"; B quit
B launch "$PWD/_private/host/<run>/CM12/cm12.skp"
B eval "load '$D/cm12.rb'; CM12.compare('attached')"   # equal: true, every value, as_read and provenance
B eval "CM12.state"                        # no folders; source not_on_this_computer
B eval "CM12.open_panel"; B eval "CM12.click_tab('climate')"; B eval "CM12.click_card('phius')"
B eval "CM12.attached"                      # shown; no notice; Where this lives: not on this computer
B eval "CM12.click(CM12::HEAD, 'Replace…')"; B eval "CM12.attached"   # explain names no climate data folder
```

### A9. Restore the folder, replace the station (board 16)

```sh
B eval "CM12.click(CM12::HEAD, 'Climate Data on This Computer…')"; B eval "CM12.choose_next"
B eval "CM12.click(CM12::DATA, 'Add Folder…')"; B eval "CM12.name_folder('Synthetic Dataset')"
B eval "CM12.click(CM12::DATA, 'Done')"; B eval "CM12.climate"          # source found
B eval "CM12.click(CM12::HEAD, 'Replace…')"; B eval "CM12.picker"      # title Replace Phius climate data
B eval "CM12.pick('XA/INSIDE_BOTH-mon.txt')"; B eval "CM12.picker"     # compare_rows 3; submit Replace
B eval "CM12.submit_picker"; B eval "CM12.climate"                     # station INSIDE_BOTH; verdict pass
```

### A10. Edit a value and see the mark (board 15)

```sh
B eval "CM12.click(CM12::HEAD, 'Edit Values…')"; B eval "CM12.editor"
B eval "CM12.type(13, '77')"; B eval "CM12.click(CM12::EDITOR, 'Save')"
B eval "CM12.climate"; B eval "CM12.attached"   # edited 1; tags include Edited; one is-edited cell
```

### A11. The design temperatures, and Mechanical's reads

```sh
B eval "CM12.click_card('design')"
B eval "CM12.fill(CM12::PANE, '99% heating dry bulb', '-17.2', 'Enter')"
B eval "CM12.fill(CM12::PANE, '1% cooling dry bulb', '30.1', 'Enter')"; B eval "CM12.blur(CM12::PANE, '1% cooling dry bulb')"
B eval "CM12.state"; B eval "CM12.mechanical"     # design set; air_c_count 12, all numbers; design_state set
B eval "CM12.fill(CM12::PANE, '99% heating dry bulb', '', 'Enter')"
B eval "CM12.fill(CM12::PANE, '1% cooling dry bulb', '', 'Enter')"; B eval "CM12.blur(CM12::PANE, '1% cooling dry bulb')"
B eval "CM12.state"                                # design not_set
```

### A12. Export (board 18)

```sh
B eval "CM12.start_export('cm12')"
B wait-for export_finished --param session=<session> --param caller=<caller> --param task=<task> --deadline 180 --interval 2 --json
B eval "CM12.export_outcome('cm12')"   # completed; cm12.hbjson and its report
B eval "CM12.export_check('cm12')"     # same Site on every segment; the reference location; provenance
                                       # user_defined (one edit), dataset and station named in the report;
                                       # no run, home or settings path in any file or answer
B eval "CM12.privacy"                  # no path in any answer or the log
```

### A13. A climate typed by hand on a second Model (boards 12, 20)

`Sketchup.open_file` of a second document does not make it the active Model while no SketchUp window is key
(host control notes), so the second Model has its own process.

```sh
B save; B quit
B launch "$PWD/_private/host/<run>/CM12/cm12-hand.skp" --fresh-from _private/host/blank-template.skp
B eval "load '$D/cm12.rb'; CM12.state"       # title cm12-hand; climate none; the folder listed
B eval "CM12.mechanical"                     # climate none, design not_set: what Mechanical's finding reads
B eval "CM12.open_panel"; B eval "CM12.click_tab('climate')"; B eval "CM12.click_card('phius')"
B eval "CM12.click(CM12::PHIUS, 'Enter Values by Hand…')"; B eval "CM12.paste(0)"; B eval "CM12.editor"
B eval "CM12.type('Name', 'Typed Street')"; B eval "CM12.type('Station elevation', '92')"
B eval "CM12.click(CM12::EDITOR, 'Save')"; B eval "CM12.climate"    # incomplete; origin hand; missing swing, wind
B eval "CM12.mechanical"                     # climate incomplete; air_c 12 numbers
B quit                                       # cm12-hand.skp is not saved
B launch "$PWD/_private/host/<run>/CM12/cm12.skp"
B eval "load '$D/cm12.rb'; CM12.open_panel"; B eval "CM12.size(1280, 800)"
B eval "CM12.click_tab('climate')"; B eval "CM12.click_card('phius')"; B eval "CM12.state"
```

Leave SketchUp as part B needs it: a fresh process with `cm12.skp` alone, saved, the panel open at 1280 x 800
on the Climate tab with the Phius card showing the attached climate (Inside Both XA, one edited value), the
folder set up.

## Part B: real input and native Undo (the conductor, one hold)

The panel may be on another Space: `app_bring_to_current_space`, then System Events
`tell application "System Events" to tell process "SketchUp" to set position of window "PH-Composer" to {40, 60}`.
**AXRaise the panel window before each click in it.** **The Edit menu needs an AXRaise of the document window**
(by its title) first. After each step, read the result through the bridge, not from pixels; each read is
`B eval "CM12.<read>"` and then `B eval "CM12.result('<name>')"` for a panel read.

### B1. CM12: a real click on the map

1. Click the **Site location** card, then **Set Location…** in the page header. `CM12.setloc`: open, the map
   drawn.
2. Click once on the map, away from the site's pin, without dragging. `CM12.setloc`: Latitude and Longitude
   differ from 40 and -100; Elevation still 500.
3. Click **Cancel**, then the **Phius climate data** card. `CM12.state`: the site still 40.0, -100.0, 500.

### B2. SketchUp's geolocation, on a Model never geolocated

Part A stood the geolocation in on `cm12.skp`, so this runs on a fresh copy instead, with coordinates the stand-in
never wrote.

```sh
cp _private/host/blank-template.skp _private/host/<run>/CM12/cm12-geo.skp
B eval "Sketchup.open_file('$PWD/_private/host/<run>/CM12/cm12-geo.skp')"
```

AXRaise the `cm12-geo.skp` window so it becomes the active Model, then `B eval "CM12.state"`: title
`cm12-geo`, geolocation geolocated false, site not_set. The panel follows the active Model; select the Site
location card.

1. AXRaise `cm12-geo.skp`. **Window > Model Info > Geo-location > Set Manual Location…**, latitude `42.3`,
   longitude `-73.4`, OK, close Model Info. `B eval "CM12.state"`: `geolocation` as SketchUp now reports it, and
   `B eval "[Sketchup.active_model.georeferenced?, Sketchup.active_model.shadow_info['Latitude']]"`.
2. AXRaise the panel. **Set Location…**, **Read from SketchUp Geolocation**. `CM12.setloc`: Latitude 42.3 and
   Longitude -73.4 with Elevation empty (the panel's **Set Location…** is in the page header while the Site
   location card is selected), or, if SketchUp reports the manual location not geolocated, the status
   "This SketchUp model has no geolocation." Either is recorded.
   - Filled: type Elevation `100`, **Set Location**: `CM12.state` site 42.3, -73.4, 100. `site-geolocation` passes.
   - No geolocation: Set Location stays disabled with the fields empty; **Cancel**. `site-geolocation` reads
     blocked, part A's stand-in run its only pass, until Ed decides (packet STATUS, owed check 4 item 2). Type no
     coordinates in its place.
3. AXRaise the `cm12.skp` window to return (`CM12.state` title `cm12`) and select the Phius climate data card;
   `cm12-geo.skp` is never saved and closes with the quit after B3.

### B3. CM12: Replace as one native Undo step

1. With the Phius climate data card selected, click **Replace…** in the page header. The picker opens. Click the
   row **Café Station XB**, then **Replace**.
   `CM12.climate`: station `CAFE_STATION`, edited 0.
2. AXRaise `cm12.skp`. **Edit > Undo Replace Climate Station**: `CM12.climate` station `INSIDE_BOTH`, edited 1.
   **Edit > Redo Replace Climate Station**: `CAFE_STATION` again. One step each way, the titles exact.

Then `B eval "CM12.cleanup(false)"` (folders and the run's folder copies; the settings folder stays for B6),
`B save` is not needed, `B quit`.

### B4. CM01: Undo and Redo through the Edit menu

```sh
B launch "$PWD/_private/host/<run>/CM01/cm01-undo.skp" --fresh-from _private/host/blank-template.skp
B eval "load '$PWD/tools/examples/climate/site_walkthrough.rb'; ClimateSiteWalkthrough.run"   # passed true
```

Then the four Undo and four Redo rows of the [CM01 recipe](cm01-recipe.md#3-undo-and-redo-through-the-edit-menu),
reading the Edit menu's first item before each click and `ClimateSiteWalkthrough.state` after it; after the last
Redo, `ClimateSiteWalkthrough.verify` passes. `B quit` (no save).

### B5. CM02: Undo and Redo through the Edit menu

```sh
B launch "$PWD/_private/host/<run>/CM02/cm02-undo.skp" --fresh-from _private/host/blank-template.skp
B eval "load '$PWD/tools/examples/climate/climate_walkthrough.rb'; load '$PWD/tools/examples/climate/station_seed.rb'; ClimateWalkthrough.run_hand"
B eval 'ClimateStationSeed.seed'
B eval 'ClimateWalkthrough.run_station'
```

Then the eight Undo and eight Redo rows of the [CM02 recipe](cm02-recipe.md#3-undo-and-redo-through-the-edit-menu),
each state compared whole; after the eighth Redo, `ClimateWalkthrough.verify` passes. `B quit` (no save).

### B6. CM03: the real folder chooser

```sh
B launch "$PWD/_private/host/<run>/CM03/cm03-chooser.skp" --fresh-from _private/host/blank-template.skp
mkdir -p "_private/host/<run>/folders-cm03/Phius native"
B eval "load '$D/cm03.rb'; PhComposer::NativeApproval.setup(CM03.context, 'ph_composer.climate.folders.add', {}).slice('status','code','value')"
```

The sheet "Add Climate Data Folder" opens; choose `folders-cm03/Phius native` and press **Open**: `completed`,
name `Phius native`. Run it again and press **Cancel**: `cancelled`, nothing added. Then `CM03.privacy` (all
false), `B diagnostics --json` holds no path, `CM03.remove_all`, `CM03.cleanup(true)`, `B quit`.

### B7. Put this computer's settings back

```sh
P="$HOME/Library/Application Support/PH-Composer"
ls "$P" 2>/dev/null || echo absent        # absent after the cleanups
if [ -d _private/host/<run>/settings-before ]; then cp -Rp _private/host/<run>/settings-before "$P" && diff -r _private/host/<run>/settings-before "$P" && echo restored; fi
```

Hand back with the run log. The stage agent writes each case's `observations.json` and runs
`acceptance_case.py finish` for CM01, CM02, CM03 and CM12 with `--evidence` naming
`planning/archive/phase-04-climate/evidence/cm12-<yyyymmdd>.md`.

## Part C: Ed's verification pass

1. The packet STATUS's "For Ed's verification pass" items for P4c-06 to P4c-11, which CM12 walks again
   end to end; the UI polish assertion of CM12 is his.
2. B2 if it read "no geolocation" for a manual location: whether that is acceptable.
3. Whether CM04 to CM10, which read `needs_recheck` from later stages, stand on the CM12 run or are each rerun
   (packet STATUS, "Before archive").

CM12 reads "agent run Pass; Ed's pass pending" until Ed has done part C.
