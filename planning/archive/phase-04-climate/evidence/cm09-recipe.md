# CM09 host recipe: the station picker

DATE: 2026-11-18
STATUS: Written after the last review fix of PR #520 (head `fab641b3`). Part A is the stage agent's; part B is the conductor's hold; part C is Ed's verification pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM09](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM09` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_picker_test.js`, `tests/climate_stations_test.rb` and the browser check
`tools/ui-preview/climate_picker_checks.cjs`. Write `<run>` as `cm09-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm09.rb`, with the read-only probe on the panel's `receive` that
CM06 to CM08 used. Panel actions in part A are scripted DOM events in the real HtmlDialog, labelled as such:
they prove the wiring and what is sent, not a native gesture. Adding a folder uses a labelled stand-in that
answers `UI.select_directory` once, the route CM03 proved.

**Folders.** Part A writes two real-size synthetic folders under `_private/host/<run>/driver/folders/`:
`Picker One` with 1,007 invented stations in eight invented states (`QA` to `QH`) around the site (40.0,
-100.0, 500 m), about one in nine more than 122 m above it, and `Picker Two` with 200. Their names are made
up, so reads over them may name a station. The private corpus may be added once, for a timing and counts only
(`CM09.add_corpus`, its location in `_private/climate/MANIFEST.md`): reads over it pass `names = false`, and
no capture of it is committed.

**What it touches.** The case writes Ed's settings file. A1 records whether its folder exists;
`CM09.cleanup` removes only the case's folders, and the settings folder when the case created it.

`B` stands for `uv run tools/hostkit/host_bridge.py` (in zsh, the wrapper script); `D` is the driver's
absolute path. Each `B eval` is its own call, so the panel's timers run between them; read a result with
`B eval "CM09.result('picker')"` (or `'tip'`, `'act'`, `'pane'`) after the call that posts it.

## Part A: bridge, no window focus (the stage agent)

### A1. Build, install, open the fixture, begin

```sh
make rbz install bridge-install                                   # on the PR head
B launch "$PWD/_private/host/<run>/CM09/cm09.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm09.skp only
uv run tools/hostkit/acceptance_case.py begin CM09 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM09/cm09.skp --fixture-id "fresh copy of blank-template.skp" \
  --control combined --assert opening --assert find-nearest --assert state-filter --assert dataset \
  --assert select-together --assert hover --assert failing --assert replace --assert undo --assert sizes \
  --assert polish --window "cm09.skp the only document in a fresh process" \
  --target "the site set, no climate, two synthetic folders of the case's" \
  --probe "the probe.dom read on the panel's own callback; a labelled chooser stand-in for Add Folder"
B eval "load '$D'; CM09.state"           # settings_exists noted; site not_set; climate none
B eval "CM09.make_folder('Picker One', 1007)"; B eval "CM09.make_folder('Picker Two', 200)"
B eval "CM09.add_synthetic('Picker One')"; B eval "CM09.add_synthetic('Picker Two')"   # ids noted
B eval "CM09.set_site"; B eval "CM09.remember('<Picker Two id>')"
B eval "CM09.time_all('<Picker One id>')"   # seconds, 1,007 rows, bytes, the count that pass
```

### A2. Opening state (board 4): the dataset used last, sorted, State on All, the ring

```sh
B eval "CM09.open_panel"; B eval "CM09.click_tab('climate')"; B eval "CM09.click_card('phius')"
B eval "CM09.read_pane"       # ready; Choose Station… enabled
B eval "CM09.open_picker"; B eval "CM09.read"
#   open; title "Set Phius climate data"; dataset Picker Two (index 1, the one remembered); rows 200; points
#   200; sorted true; state ""; selected_index 0; ring true; framed true; opened_ms
B eval "CM09.set_dataset(0)"; B eval "CM09.read"
#   rows 1007, points 1007, sorted, selected_index 0, framed; settings last_dataset_id is Picker One
```

### A3. State, search, Find Nearest

```sh
B eval "CM09.set_state(3)"; B eval "CM09.result('act')"; B eval "CM09.read"   # one state's rows = points; ms
B eval "CM09.search('Picker QD 1011')"; B eval "CM09.read"                     # rows 1, selected 0
B eval "CM09.zoom"; B eval "CM09.find_nearest"; B eval "CM09.read"
#   rows 1007, state "", search "", selected_index 0, framed true
```

### A4. Map and list together, hover, keyboard

```sh
B eval "CM09.click_marker(5)"; B eval "CM09.result('act')"; B eval "CM09.read"
#   selected_index 5; marker_matches true; marker_current 1; ms
B eval "CM09.click_row(2)"; B eval "CM09.read"       # selected_index 2; marker_matches true
B eval "CM09.hover(0)"; B eval "CM09.result('tip')"  # shown, 3 lines: name, "<d> km · ±<e> m", verdict
B eval "CM09.keyboard"; B eval "CM09.result('act')"  # moved true; next: Cancel, Attach
```

### A5. A failing station (board 11), attached with no confirm

```sh
B eval "CM09.read"   # find a row whose verdict is Fail: click_row(<i>) until outside is true
B eval "CM09.click_row(<i>)"; B eval "CM09.read"
#   outside true; warning true; still_attachable true; submit Attach enabled; confirm false
B eval "CM09.commit"; B eval "CM09.read"; B eval "CM09.climate"
#   open false; climate complete, station the failing one, verdict fail; no confirm dialog
```

### A6. Replace (board 16): the two compared, lost edits named

```sh
B eval "CM09.edit_two"; B eval "CM09.climate"            # edited 2
B eval "CM09.remember('<Picker Two id>')"                  # so the attached station's dataset decides
B eval "CM09.read_pane"; B eval "CM09.open_picker('Replace Station…')"; B eval "CM09.read"
#   title "Replace Phius climate data"; dataset the attached station's (Picker One); attached_marks 1;
#   lost 2; submit Replace
B eval "CM09.js('cut', \"var c = Array.prototype.filter.call(document.querySelectorAll('dialog.climate-picker td.col-station'), function (td) { return /Attached/.test(td.textContent); })[0]; return c ? c.scrollWidth > c.clientWidth + 1 : null;\")"
#   result('cut') false: the name and its Attached chip fit
B eval "CM09.click_row(0)"; B eval "CM09.read"             # compare_rows 3 (heading, Now, New)
B eval "CM09.commit"; B eval "CM09.climate"                # station the nearest; edited 0
```

### A7. Sizes, refusals, the real folder, cleanup

```sh
B eval "CM09.open_picker('Replace Station…')"
B eval "CM09.size(420, 732)"; B eval "CM09.read"; B eval "CM09.size(360, 520)"; B eval "CM09.read"
#   sideways false, the box inside the window
B eval "CM09.size(1280, 800)"; B eval "CM09.cancel"
B eval "CM09.add_corpus('<the manifest's text-file folder>')"; B eval "CM09.time_all('<corpus id>')"
#   counts and seconds only
```

Leave the panel and the Model as they are for part B; `CM09.cleanup` runs after it. After part A on
`fab641b3` the process holds: the panel at 1280 x 800 on the Climate tab, the Phius card's interim pane
(`attached`, Replace Station… enabled), the picker closed; the site set; Picker One's nearest station attached
(edited 0); Picker One and Picker Two set up, Picker Two remembered; the corpus folder removed again.

## Part B: real input and native Undo (the conductor, one hold)

The panel may be on another Space: `app_bring_to_current_space`, then System Events
`tell application "System Events" to tell process "SketchUp" to set position of window "PH-Composer" to {40, 60}`.
The Edit menu needs an AXRaise of the document window (`cm09.skp`). Each step has a DOM read the conductor
checks through the bridge instead of pixels: `B eval "CM09.read"` then `B eval "CM09.result('picker')"`,
and `B eval "CM09.climate"` for the Model.

1. In the Phius pane, click **Replace Station…**. The picker opens on Picker One. `CM09.read`: title
   "Replace Phius climate data", `dataset` 0, `attached_marks` 1, `lost` null, rows 1007.
2. Drag the map to pan and scroll the wheel over it. `CM09.read`: `framed` false. Click **Find Nearest**.
   `CM09.read`: `framed` true, rows 1007, `state` "", `search` "", `selected_index` 0.
3. Click a station's dot on the map inside the ring. `CM09.read`: `selected_index` is its row, `marker_matches`
   true, `marker_current` 1; `CM09.read_focus` then `CM09.result('focus')`: `list_scroll` shows the row in view.
4. Hover another dot. `CM09.read_tip` then `CM09.result('tip')`: `shown` true, `lines` 3, `facts` "<d> mi ·
   ±<e> ft", `verdict` Pass or "Outside Phius limits".
5. Click the first row's name, press **Down** twice, then **Tab** until the focus leaves the list.
   `CM09.read`: `selected_index` 2. `CM09.read_focus`: `text` "Cancel"; one more **Tab**: "Replace".
6. Click the 10th row's name, **Picker QB 1009** (Fail, 521.65 ft higher). `CM09.read`: `outside` true,
   `warning` true, `submit` Replace enabled. Press **Replace**. `CM09.climate`: station `PICKER_1009`, verdict
   fail; no confirm appeared (`CM09.read`: `open` false).
7. AXRaise `cm09.skp`, then **Edit > Undo Replace Climate Station**. `CM09.climate`: station `PICKER_1001`,
   verdict pass. **Edit > Redo Replace Climate Station**: `PICKER_1009` again. One Undo step each way.
8. Reopen Replace Station…; capture the panel window by id at 1280, 420 (`CM09.size(420, 732)`) and 360
   (`CM09.size(360, 520)`) px with a failing station selected (board 11's warning, board 16's table), then
   `CM09.size(1280, 800)`. Keep the captures under `_private/host/cm09-20261118/CM09/`.

Before stopping, close any dialog or confirm left open (`B eval "CM09.cancel"` closes the picker). Then
`B eval "CM09.cleanup(true)"` (no settings folder existed before the case), `B quit`, and
`acceptance_case.py finish CM09 --run-dir _private/host/cm09-20261118 --evidence
planning/archive/phase-04-climate/evidence/cm09-20261118.md` with the observations from parts A and B in
`_private/host/cm09-20261118/CM09/observations.json` (`polish` blocked on part C).

## Part C: Ed's verification pass

The P4c-09 items under "For Ed's verification pass" in the [packet STATUS](../STATUS.md#for-eds-verification-pass).
CM09 reads "agent run Pass; Ed's pass pending" until Ed has done them.
