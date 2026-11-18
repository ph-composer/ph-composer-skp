# CM08 host recipe: Climate Data on This Computer and the Phius pane's empty states

DATE: 2026-11-18
STATUS: Written after the last review fix of PR #519 (head `94b26a96`). Parts A and B ran 2026-11-18 on that head ([evidence](cm08-20261118.md)); part C is Ed's verification pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM08](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM08` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_data_panel_test.js`, the route tests in `tests/setup_entries_test.rb`, the folder and station
tests in `tests/climate_folders_test.rb` and `tests/climate_stations_test.rb`, and the browser check
`tools/ui-preview/climate_data_checks.cjs`. Write `<run>` as `cm08-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm08.rb`. It prepends the read-only probe on the panel's
`receive` that CM06 and CM07 used: the page posts `{type: "probe.dom"}` reads through its own callback and
the host keeps them. Panel actions in part A are scripted DOM events in the real HtmlDialog, labelled as
such: they prove the wiring and what is sent, not a native gesture. Where part A needs the folder chooser, a
labelled stand-in answers `UI.select_directory` once with a synthetic folder, the route CM03 proved.

**Folders.** Part A uses copies of the invented reference folder `tests/fixtures/climate/folder` (five
stations in states XA, XB and XC, plus files not read) under `_private/host/<run>/driver/folders/`. Part B's
real folder may be the private corpus, which `_private/climate/MANIFEST.md` locates; no station name,
coordinate or value from it goes into the evidence, the captures committed or a review, only counts.

**What it touches.** The case writes Ed's settings file,
`~/Library/Application Support/PH-Composer/settings.json`. Step A1 records whether its folder exists;
`CM08.cleanup` removes only the case's folders, and the settings folder when the case created it.

`B` stands for `uv run tools/hostkit/host_bridge.py`; in zsh call it through a wrapper script. `D` is the
absolute path of the driver. Each `B eval` is its own call, so the panel's timers run between them; read a
result with `B eval "CM08.result('<name>')"` after the read that posts it.

## Part A: bridge, no window focus (the stage agent)

### A1. Build, install, open the fixture, begin

```sh
make rbz install bridge-install                                   # on the PR head
B launch "$PWD/_private/host/<run>/CM08/cm08.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm08.skp only
uv run tools/hostkit/acceptance_case.py begin CM08 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM08/cm08.skp --fixture-id "fresh copy of blank-template.skp" \
  --control combined --assert list --assert add-name --assert remove --assert not-found \
  --assert no-rescan --assert routes --assert pane-states --assert sizes --assert chooser \
  --assert polish --window "cm08.skp the only document in a fresh process" \
  --target "no site, no climate, no climate data folder of the case's" \
  --probe "the probe.dom read on the panel's own callback; a labelled chooser stand-in in part A"
B eval "load '$D'; CM08.state"          # settings_exists noted; site not_set; climate none
```

### A2. The pane with no folder (board 2), and Choose Climate Data Folder

```sh
B eval "CM08.open_panel"; B eval "CM08.click_tab('climate')"; B eval "CM08.click_card('phius')"
B eval "CM08.read('pane')"; B eval "CM08.result('pane')"    # state no_folder; Choose Climate Data Folder;
                                                           # Enter Values by Hand disabled
B eval "CM08.make_folder('Set A')"; B eval "CM08.choose_next('Set A')"
B eval "CM08.click(CM08::PHIUS, 'Choose Climate Data Folder…')"
B eval "CM08.read('data')"; B eval "CM08.result('data')"    # open; one row; its name open, prefilled "Set A"
B eval "CM08.name('Station Set A')"; B eval "CM08.read('data')"
#   the row reads Station Set A, ~/…/Set A, Phius monthly station files, 5, 3, files not read by kind
```

### A3. Counts read on each open, no Rescan, no notice

```sh
B eval "CM08.click(CM08::DIALOG, 'Done')"; B eval "CM08.add_station('Set A')"
B eval "CM08.click(\"document.querySelector('[data-pane=climate] .phc-heading')\", 'Climate Data on This Computer…')"
B eval "CM08.read('data')"     # stations 6, rescan false, no status line
```

### A4. A cancelled chooser, a refused overlap, the name's Escape

```sh
B eval "CM08.choose_next(nil)"; B eval "CM08.click(CM08::DIALOG, 'Add Folder…')"; B eval "CM08.read('data')"
#   one row, no status
B eval "CM08.choose_next('Set A')"; B eval "CM08.click(CM08::DIALOG, 'Add Folder…')"; B eval "CM08.read('data')"
#   one row; the status names the overlap, inside the dialog
B eval "CM08.click(CM08::DIALOG, 'Rename Station Set A')"; B eval "CM08.name('Other', 'Escape')"
B eval "CM08.read('data')"     # the name unchanged, the dialog open
```

### A5. A folder not found, its stations absent, Locate, Remove

```sh
B eval "CM08.move_folder('Set A', 'Set A moved')"; B eval "CM08.click(CM08::DIALOG, 'Done')"
B eval "CM08.set_site"         # completed: the site 40.0, -100.0, 500 m
B eval "CM08.click(\"document.querySelector('[data-pane=climate] .phc-heading')\", 'Climate Data on This Computer…')"
B eval "CM08.read('data')"     # found false; Folder not found; Locate… and Remove; the note
B eval "CM08.stations('<id>')" # refused, climate.folder_not_found: absent from the picker
B eval "CM08.choose_next('Set A moved')"; B eval "CM08.click(CM08::DIALOG, 'Locate Station Set A')"
B eval "CM08.read('data')"     # found true, the counts back
B eval "CM08.click(CM08::DIALOG, 'Done')"; B eval "CM08.read('pane')"   # state ready: Station Set A · 6 stations
```

### A6. The Setup view and the Extensions menu routes (C4c-3)

```sh
B eval "CM08.click_tab('setup')"; B eval "CM08.read('setup')"   # the Climate entry, "1 folder, 6 stations"
B eval "CM08.click(\"document.querySelector('[data-pane=setup]')\", 'Climate Data on This Computer…')"
B eval "CM08.read('data')"     # open, on the Climate tab
B eval "CM08.click(CM08::DIALOG, 'Done')"; B eval "CM08.close_panel"
B eval "CM08.run_menu_item"    # the menu item's handler with the panel closed: the panel opens
B eval "CM08.read('data')"     # open, on the Climate tab, once the page has started
```

### A7. Sizes, Remove, cleanup

```sh
B eval "CM08.size(420, 732)"; B eval "CM08.read('data')"; B eval "CM08.size(360, 520)"; B eval "CM08.read('data')"
#   sideways false, the box inside the window; capture the panel window by id at each size
B eval "CM08.size(1280, 800)"; B eval "CM08.click(CM08::DIALOG, 'Remove Station Set A')"
B eval "CM08.read('confirm')"  # "Remove Station Set A?", Models keep their climates
B eval "CM08.click(\"document.querySelector('dialog.phc-confirm-dialog')\", 'Remove')"; B eval "CM08.read('data')"
B eval "CM08.read('pane')"     # after Done: no_folder again
```

Capture with `screencapture -x -o -l <id>` from this shell; the panel's window id comes from
`CGWindowListCopyWindowInfo` (owner SketchUp, name PH-Composer). With SketchUp in the background the
HtmlDialog does not repaint after a resize, so a capture at 420 or 360 px is blank until the window is in
front: the sizes are proved by the DOM read in part A and captured in part B. Keep captures in
`_private/host/<run>/CM08/`; commit none that shows a real folder.

## Part B: the native chooser and real input (the conductor, one hold)

The panel may open on a display the conductor cannot see: first move it with System Events,
`tell application "System Events" to tell process "SketchUp" to set position of window "PH-Composer" to {40, 60}`;
the conductor may need `app_bring_to_current_space` first. The Extensions menu needs an AXRaise of the
document window (`cm08.skp`), not the panel. Each step has a DOM read the conductor checks through the
bridge instead of pixels: `B eval "CM08.read('data')"`, `CM08.read('pane')`, `CM08.read('setup')`, then
`CM08.result(...)`.

1. On the Climate tab with the Phius card selected and no folder (`CM08.read('pane')`: `no_folder`), click
   **Choose Climate Data Folder…**. The real "Add Climate Data Folder" sheet opens. Choose a real folder (the
   private corpus, or `_private/host/<run>/driver/folders/Set A`). The dialog shows its row with the name
   field open and focused, prefilled from the folder's name.
2. Type a dataset name and press **Enter**. The row shows it (`CM08.read('data')`).
3. Hover the row, click its **pencil**, type another name, press **Escape**: the name is unchanged and the
   dialog stays open. Press **Escape** again: the dialog closes.
4. Reopen it from the page header. Click the pencil, type a name, then click **Add Folder…** directly: the
   name is saved and the sheet opens; press **Cancel** in the sheet. Nothing is added (`CM08.read('data')`).
5. With a folder moved away (`CM08.move_folder`), reopen the dialog: the row reads Folder not found. Click
   **Locate…**; in the real sheet choose the moved folder. The row is found again.
6. Click **Remove** on a row, then **Remove** in the confirm. Click **Done**.
7. **Extensions > PH-Composer > Climate > Climate Data on This Computer…** with the panel closed: the panel
   opens on the Climate tab with the dialog open (`CM08.read('data')`).
8. Gear (Setup view) > **Climate Data on This Computer…**: the same.
9. Capture the panel window by id with the dialog open at 1280, 420 (`CM08.size(420, 732)`) and 360
   (`CM08.size(360, 520)`) px, and the Phius pane in each of its three states.

Then `B eval "CM08.cleanup(<settings_existed>)"`, and `acceptance_case.py finish CM08` with the
observations from parts A and B (`polish` blocked on part C).

## Part C: Ed's verification pass

The items under "For Ed's verification pass" in the [packet STATUS](../STATUS.md#for-eds-verification-pass).
CM08 reads "agent run Pass; Ed's pass pending" until Ed has done them.
