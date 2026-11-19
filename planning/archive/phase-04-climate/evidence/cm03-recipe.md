# CM03 host recipe: the settings file and climate data folders

DATE: 2026-11-18
STATUS: Run 2026-11-18 on `45224965`: Pass ([evidence](cm03-20261118.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM03](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, the panel closed, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM03` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/computer_settings_test.rb` and `tests/climate_folders_test.rb` in the PR's `make ci`; the
platform clause (another platform is unavailable) is offline only, since the host is macOS. Write
`<run>` as `cm03-<yyyymmdd>`.

The driver lives in the run folder, `_private/host/<run>/driver/`: `cm03.rb` (bridge side) and
`external_writer.rb` (the second process). Product writes go through the public
`ph_composer.climate.folders.*` operations. One labelled development stand-in replaces the native
chooser in steps 2 to 5: for one call, `UI.select_directory` answers a synthetic folder under
`<run>/folders/`, and the command runs through `NativeApproval.setup`, the panel's route. It writes
nothing to SketchUp's preferences. Step 7 is the real chooser.

**What it touches.** The case writes Ed's real settings file,
`~/Library/Application Support/PH-Composer/settings.json`. Before the run the folder was absent
(owed check 1). Step 8 removes it again when it was absent at step 1, and otherwise clears only the
case's own sections.

`B` below stands for `uv run tools/hostkit/host_bridge.py`; in zsh call it through a wrapper script,
since an unquoted variable is not split. `D` is the absolute path of `_private/host/<run>/driver/cm03.rb`.
Each `B eval` is its own call.

## 1. Build, install, open the fixture, begin

```sh
git switch feature/climate-p4c-03 && git pull --ff-only     # the PR head under test
make rbz install bridge-install
mkdir -p _private/host/<run>/CM03
B launch "$PWD/_private/host/<run>/CM03/cm03.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm03.skp only
uv run tools/hostkit/acceptance_case.py begin CM03 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM03/cm03.skp --fixture-id "fresh copy of blank-template.skp" \
  --control native --assert settings-file --assert restart --assert two-processes \
  --assert unreadable --assert scripted-refused --assert privacy --assert summary --assert chooser \
  --window "cm03.skp the only document in a fresh process, panel closed" \
  --target "this computer's settings file and Climate's section" \
  --probe "none; public API through the bridge, the chooser stood in for steps 2 to 5"
B eval "load '$D'; CM03.state"
```

The first state must read `directory_exists: false`, `list_status: completed` with no folders, and
summary `No climate data folder`. If the folder exists, note it: step 8 then keeps it.

## 2. First write, and add survives a restart

```sh
B eval "load '$D'; CM03.scripted_add"     # refused, access.user_required, effect none
B eval "load '$D'; CM03.state"            # still directory_exists: false
B eval "load '$D'; CM03.add('Phius A')"   # completed, name "Phius A", found true
B eval "load '$D'; CM03.state"
B quit
B launch "$PWD/_private/host/<run>/CM03/cm03.skp"
B eval "load '$D'; CM03.state"
```

- The scripted add opens no dialog and leaves no folder.
- After the add: `directory_exists` and `file_exists` true, `inside_versioned_folder` false,
  `directory_mode` `700`, `file_mode` `600`, children `settings.json` and `settings.lock`, summary
  `1 folder`. The checkout sits under the home folder, so `display_location` reads `~/` and the
  path to `folders/Phius A`, never the absolute path.
- After the restart the same row, same id.

## 3. Rename, locate and remember survive a restart

```sh
B eval "load '$D'; CM03.rename('Phius 2022')"
B quit && B launch "$PWD/_private/host/<run>/CM03/cm03.skp"
B eval "load '$D'; CM03.state"            # name "Phius 2022"
B eval "load '$D'; CM03.locate('Phius B')"
B eval "load '$D'; CM03.remember_dataset"
B quit && B launch "$PWD/_private/host/<run>/CM03/cm03.skp"
B eval "load '$D'; CM03.state"            # same id, "Phius 2022", location ends Phius B, last_dataset_id the id
```

## 4. A folder not found keeps its row

```sh
B eval "load '$D'; CM03.add('Phius C')"   # summary "2 folders"
B eval "load '$D'; CM03.unplug('Phius C')"   # Phius C found false, row kept
B eval "load '$D'; CM03.replug('Phius C')"   # found true again
```

## 5. Two processes, then an unreadable file

Start the second process and, at once, the SketchUp loop:

```sh
/usr/bin/ruby _private/host/<run>/driver/external_writer.rb "$PWD" 200 > _private/host/<run>/CM03/external.txt &
B eval "load '$D'; CM03.write_section(200)"
wait
cat _private/host/<run>/CM03/external.txt
B eval "load '$D'; CM03.sections.slice('ph_composer.cm03_host', 'ph_composer.cm03_external', 'ph_composer.climate')"
```

Both sections read `{"count"=>200}` and Climate's section still holds its two folders.

```sh
B eval "load '$D'; CM03.damage"   # list refused climate.settings_unreadable, summary "The climate data settings cannot be read", rename refused, bytes_kept true
B eval "load '$D'; CM03.repair"   # list completed, "2 folders"
```

## 6. Remove survives a restart; privacy

```sh
B eval "load '$D'; CM03.remove_all"
B eval "load '$D'; CM03.privacy"
B quit && B launch "$PWD/_private/host/<run>/CM03/cm03.skp"
B eval "load '$D'; CM03.state"            # no folders, summary "No climate data folder"
B eval "load '$D'; CM03.privacy"
B diagnostics --json > _private/host/<run>/CM03/diagnostics.json
```

`privacy` must read `run_path_found`, `home_path_found` and `settings_path_found` false, over every
answer of the process and the log on disk. Also search `diagnostics.json` for the run folder's path.

## 7. The native chooser (conductor, SketchUp in front)

Needs SketchUp in front and a person or a hold for the dialog. Open the chooser through the native
route and choose `_private/host/<run>/folders/Phius native` (make the folder first):

```sh
mkdir -p "_private/host/<run>/folders/Phius native"
B eval "load '$D'; PhComposer::NativeApproval.setup(CM03.context, 'ph_composer.climate.folders.add', {}).slice('status','code','value')"
```

The macOS folder sheet titled "Add Climate Data Folder" opens; choose the folder and press Open. The
answer is `completed` with name `Phius native`. Then `CM03.privacy` (both false) and `B diagnostics
--json` hold no path. Cancel once as well: the answer is `cancelled` and nothing is added. Then
`CM03.remove_all`.

## 8. Clean up and record

```sh
B eval "load '$D'; CM03.cleanup(true)"    # true only when step 1 read directory_exists false
B quit
ls "$HOME/Library/Application Support/PH-Composer"   # absent again
```

Write `<run>/CM03/observations.json`, one row per assertion (`settings-file`, `restart`,
`two-processes`, `unreadable`, `scripted-refused`, `privacy`, `summary`, `chooser`), then:

```sh
uv run tools/hostkit/acceptance_case.py finish CM03 --run-dir _private/host/<run> \
  --evidence planning/archive/phase-04-climate/evidence/cm03-<yyyymmdd>.md
```

CM01 and CM02 read `needs_recheck` after this stage: their paths include `features/climate/*` and
`declarations/*`, which this stage changes (`install.rb`, `codes.rb`, `declarations/folders.rb`).
Run their recipes in the same session, each in its own fresh Model.
