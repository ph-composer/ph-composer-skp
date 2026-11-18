# CM04 host recipe: the station reader, the station list and attach

DATE: 2026-11-18
STATUS: Run 2026-11-18 on `47f26946`: Pass ([evidence](cm04-20261118.md)). Steps 1 to 6 run by the stage, step 7 by the conductor.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM04](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, the panel closed, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM04` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_station_file_test.rb`, `tests/climate_folder_scan_test.rb`,
`tests/climate_stations_test.rb` and `tests/climate_walkthrough_test.rb` in the PR's `make ci`. Write
`<run>` as `cm04-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm04.rb`. Product reads and writes go through the public
`ph_composer.climate.*` operations. One labelled development stand-in replaces the native folder
chooser, which CM03 proved: for one call, `UI.select_directory` answers a folder and `folders.add`
runs through `NativeApproval.setup`, the panel's route.

**Licensed data.** Step 2 reads the private corpus that `_private/climate/MANIFEST.md` locates. Its
path is passed in the eval and never printed; the driver answers counts and seconds only, because the
bridge tees the console to a log. Nothing from it is attached.

**What it touches.** The case writes Ed's settings file,
`~/Library/Application Support/PH-Composer/settings.json`. Step 1 records whether the folder exists;
step 6 removes it again when it was absent, and otherwise removes only the case's folders.

`B` stands for `uv run tools/hostkit/host_bridge.py`; in zsh call it through a wrapper script.
`D` is the absolute path of the driver and `C` the corpus's text-file tree. Each `B eval` is its own
call.

## 1. Build, install, open the fixture, begin

```sh
git switch feature/climate-p4c-04 && git pull --ff-only     # the PR head under test
make rbz install bridge-install
mkdir -p _private/host/<run>/CM04
B launch "$PWD/_private/host/<run>/CM04/cm04.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm04.skp only
uv run tools/hostkit/acceptance_case.py begin CM04 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM04/cm04.skp --fixture-id "fresh copy of blank-template.skp" \
  --control native --assert read-time --assert counts --assert list --assert attach \
  --assert replace --assert source-status --assert privacy --assert undo-redo \
  --window "cm04.skp the only document in a fresh process, panel closed" \
  --target "the Model's climate and this computer's climate data folders" \
  --probe "none; public API through the bridge, the chooser stood in"
B eval "load '$D'; CM04.state"     # settings_exists noted; no folders; site not_set; climate none
```

## 2. Read time of a real-size folder (owed check 3 through the product)

```sh
B eval "load '$D'; CM04.add_corpus('$C')"         # completed, an id
B eval "load '$D'; CM04.set_site"                 # committed: stations.list needs the site
B eval "load '$D'; CM04.corpus_timing('<id>')"    # twice: the first read in the process, then again
B eval "load '$D'; CM04.corpus_timing('<id>')"
```

Expected: 1,007 stations in 50 states, `complete` true, `files_not_read_total` 5; the walk, the
`folders.list` and the first `stations.list` page each under 0.5 s; the first page within the
24,576-byte reply; every page together gives 1,007 rows. Record the seconds. The cloud-synced,
not-downloaded case is not run (see [owed check 3](owed-check-3-20261118.md)).

## 3. Counts and the list on the invented folder

```sh
B eval "load '$D'; CM04.add_fixture('folder', 'Phius A')"
B eval "load '$D'; CM04.state"         # Phius A: format phius_station_file, 5 stations, 3 states,
                                       # files_not_read .txt 2, .md 1, .xls 1; total 4; complete true
B eval "load '$D'; CM04.list('Phius A')"
```

The list, nearest first: `XB/CAFE_STATION-mon.txt` 5.5598 km, 120 m, pass; `XB/OUTSIDE_ELEVATION`
11.1195 km, 123 m, fail; `XB/XC/NESTED` (state `XC`) 11.1195 km, 0 m, pass; `XA/INSIDE_BOTH`
77.8366 km, 121 m, pass; `XA/OUTSIDE_DISTANCE` 82.2844 km, 0 m, fail. No `-mon2.txt` and no
`MALFORMED` row.

## 4. Attach and replace with the panel closed

```sh
B eval "load '$D'; CM04.attach('Phius A', 'XA/INSIDE_BOTH-mon.txt')"   # committed, complete
B eval "load '$D'; CM04.state"   # name "Inside Both XA", station_name INSIDE_BOTH, dataset "Phius A",
                                 # verdict pass, edited 0, wind 3.0, as_read_air_jan 1.0
B eval "load '$D'; CM04.attach('Phius A', 'XB/CAFE_STATION-mon.txt')"  # refused target.changed
B eval "load '$D'; CM04.edit_one"                                      # committed (Edit Climate Values)
B eval "load '$D'; CM04.replace('Phius A', 'XB/CAFE_STATION-mon.txt')" # committed, replaced
                                 # {"name":"Inside Both XA","origin":"station","lost_edited_cells":1}
B eval "load '$D'; CM04.state"   # name "Café Station XB", edited 0, wind 6.0
```

The no-site refusal is offline only (`tests/climate_stations_test.rb`): this Model's site is set in
step 2.

## 5. Source status across folders

```sh
B eval "load '$D'; CM04.source_status"                        # found, Phius A, XB/CAFE_STATION-mon.txt
B eval "load '$D'; CM04.rewrite('Phius A', 'XA/INSIDE_BOTH-mon.txt')"   # INSIDE_BOTH changes on disk
B eval "load '$D'; CM04.replace('Phius A', 'XA/INSIDE_BOTH-mon.txt')"   # committed, lost 0
B eval "load '$D'; CM04.restore_file('Phius A', 'XA/INSIDE_BOTH-mon.txt')"
B eval "load '$D'; CM04.source_status"                        # changed
B eval "load '$D'; CM04.unplug('Phius A')"
B eval "load '$D'; CM04.source_status"                        # not_on_this_computer
B eval "load '$D'; CM04.add_fixture('second_folder', 'Other name')"
B eval "load '$D'; CM04.source_status"                        # found, the Other name folder
```

## 6. Privacy, then clean up

```sh
B eval "load '$D'; CM04.privacy('$C')"     # run_path_found, home_path_found, extra_found all false
B diagnostics --json > _private/host/<run>/CM04/diagnostics.json
```

Leave the Model and the folders in place for step 7. After it:

```sh
B eval "load '$D'; CM04.cleanup(<true when step 1 read settings_exists false>)"
B quit
```

## 7. Edit > Undo and Redo (conductor, SketchUp in front)

Edit > Undo is disabled while SketchUp is in the background, so this needs a full-screen hold.
From step 5's end, read the Edit menu's first item before each click through System Events, then
`CM04.state` after it:

| Click | Menu item | State after |
| --- | --- | --- |
| Undo 1 | Undo Replace Climate Station | name "Café Station XB" |
| Undo 2 | Undo Replace Climate Station | name "Inside Both XA", edited 1 |
| Undo 3 | Undo Edit Climate Values | name "Inside Both XA", edited 0 |
| Undo 4 | Undo Attach Climate Station | climate none |
| Redo 1 to 4 | Redo Attach, Edit, Replace, Replace | back to step 5's state, name "Inside Both XA" |

Step 5's replace attached the rewritten `INSIDE_BOTH`, so Undo 1 returns to "Café Station XB", and
the four Redos end on the rewritten "Inside Both XA" again. Then write `<run>/CM04/observations.json`, one row per assertion, and:

```sh
uv run tools/hostkit/acceptance_case.py finish CM04 --run-dir _private/host/<run> \
  --evidence planning/features/phase-04-climate/evidence/cm04-<yyyymmdd>.md
```

CM02 and CM03 read `needs_recheck` after this stage, since it changes `climate/record.rb`,
`folders/operations.rb`, `declarations/folders.rb`, `codes.rb` and `install.rb`; they are rerun in
P4c-12's fresh-process run.
