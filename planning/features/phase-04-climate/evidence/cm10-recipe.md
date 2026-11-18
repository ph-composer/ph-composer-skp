# CM10 host recipe: the attached climate pane

DATE: 2026-11-18
STATUS: Written after the last review fix of PR #521. Part A is the stage agent's; part B is the conductor's hold; part C is Ed's verification pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM10](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM10` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_attached_test.js` and the browser check `tools/ui-preview/climate_attached_checks.cjs`.
Write `<run>` as `cm10-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm10.rb`, with the read-only probe on the panel's `receive` that
CM06 to CM09 used. Panel actions in part A are scripted DOM events in the real HtmlDialog, labelled as such:
they prove the wiring and what is sent, not a native gesture. Adding a folder uses a labelled stand-in that
answers `UI.select_directory` once, the route CM03 proved.

**Folder.** Part A writes one synthetic folder, `Pane One`, under `_private/host/<run>/driver/folders/`, with
three invented stations around the site (40.0, -100.0, 500 m): Alder Field (QA, 18 km north, 11 m higher, Pass),
Birch Point (QA, 41 km, 52 m lower, Pass) and Cedar Ridge (QB, 66 km, 310 m higher, Fail). No licensed data
is read.

**What it touches.** The case writes Ed's settings file. A1 records whether its folder exists;
`CM10.cleanup` removes only the case's folder, and the settings folder when the case created it.

`B` stands for `uv run tools/hostkit/host_bridge.py` (in zsh, the wrapper script); `D` is the driver's
absolute path. Each `B eval` is its own call, so the panel's timers run between them; read a result with
`B eval "CM10.result('pane')"` (or `'click'`, `'picker'`) after the call that posts it. `CM10.read` posts
`pane`: the heading, tags, lines above the values, each table's row names and first row, the edited cells'
tooltips, the wind field, Where this lives, the page header's buttons, any floating notice or open dialog,
and whether the panel scrolls sideways.

## Part A: bridge, no window focus (the stage agent)

### A1. Build, install, open the fixture, begin

```sh
make rbz install bridge-install                                   # on the PR head
B launch "$PWD/_private/host/<run>/CM10/cm10.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm10.skp only
uv run tools/hostkit/acceptance_case.py begin CM10 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM10/cm10.skp --fixture-id "fresh copy of blank-template.skp" \
  --control combined --assert pane --assert limit --assert tables --assert edited --assert restore \
  --assert source-changed --assert no-folder --assert failing --assert clear --assert units --assert sizes \
  --assert polish --window "cm10.skp the only document in a fresh process" \
  --target "the site set, a synthetic folder of the case's, one station attached" \
  --probe "the probe.dom read on the panel's own callback; a labelled chooser stand-in for Add Folder"
B eval "load '$D'; CM10.state"           # settings_exists noted; site not_set; climate none
B eval "CM10.make_folder"; B eval "CM10.add_folder"            # id noted
B eval "CM10.set_site"; B eval "CM10.attach('<id>')"; B eval "CM10.climate"   # complete, ALDER_FIELD, pass
B eval "CM10.time_source"                                       # entry check 3: seconds
```

### A2. The pane (board 5)

```sh
B eval "CM10.open_panel"; B eval "CM10.click_tab('climate')"; B eval "CM10.click_card('phius')"
B eval "CM10.read"
#   state attached; name "Alder Field"; tags [Pass]; no notices; sections: limit check rows Distance and
#   Elevation; Monthly temperatures rows Air, Dewpoint, Sky, Ground; Monthly radiation North to Global;
#   Peak loads Heating 1, Heating 2, Cooling 1, Cooling 2; Where this lives "Source found ..."; header buttons
#   Climate Data on This Computer…, Edit Values… (disabled), Replace… (primary), More climate actions
```

### A3. Edited cells and Restore (board 15), the wind speed

```sh
B eval "CM10.edit_two"; B eval "CM10.read"
#   tags [Pass, Edited]; a line "2 values differ from the station file: ..."; edited 2 tooltips "Edited. The
#   station file reads ..."
B eval "CM10.click('Restore Original Values')"; B eval "CM10.climate"; B eval "CM10.read"   # edited 0
B eval "CM10.type_wind('4.5')"; B eval "CM10.climate"; B eval "CM10.read"
#   wind 4.5; edited 0; no Edited tag
```

### A4. A changed source (board 17) and Update from File

```sh
B eval "CM10.change_source"; B eval "CM10.click_card('site')"; B eval "CM10.click_card('phius')"
B eval "CM10.read"      # tags include "Source changed"; Where this lives "Source changed ... Update from File…"
B eval "CM10.click('Update from File…')"; B eval "CM10.picker"
#   open; title "Replace Phius climate data"; selected "QA/ALDER_FIELD-mon.txt"
B eval "CM10.cancel_picker"
```

### A5. A failing station (board 19), IP and SI

```sh
B eval "CM10.set_site({ 'latitude_deg' => 40.0, 'longitude_deg' => -100.0, 'elevation_m' => 300.0 })"
B eval "CM10.read"      # tags [Outside Phius limits, ...]; "Outside the Phius limits: ... higher than the site. ..."
B eval "CM10.units('IP')"; B eval "CM10.read"; B eval "CM10.units('SI')"; B eval "CM10.read"
B eval "CM10.set_site"
```

### A6. No folder (board 6): read in full, no notice, Replace explains

```sh
B eval "CM10.remove_folder('<id>')"; B eval "CM10.click_card('site')"; B eval "CM10.click_card('phius')"
B eval "CM10.read"      # every section present; Where this lives "Not on this computer ..."; notice null
B eval "CM10.click('Replace…')"; B eval "CM10.read"
#   explain "Replace ... There is no climate data folder ... Choose Climate Data Folder… Enter Values by Hand…"
B eval "CM10.add_folder"                                        # the new id noted
```

### A7. Clear, sizes

```sh
B eval "CM10.menu_clear"; B eval "CM10.climate"; B eval "CM10.read"   # state none; pane ready; confirm false
B eval "CM10.attach('<new id>')"
B eval "CM10.size(420, 732)"; B eval "CM10.read"; B eval "CM10.size(360, 520)"; B eval "CM10.read"
#   sideways false; the monthly tables' boxes scroll
B eval "CM10.size(1280, 800)"; B eval "CM10.edit_two"
```

Leave the panel and the Model as they are for part B: the panel at 1280 x 800 on the Climate tab with the
Phius card, Alder Field attached with two edited values, the source found, the folder set up.

## Part B: real input and native Undo (the conductor, one hold)

The panel may be on another Space: `app_bring_to_current_space`, then System Events
`tell application "System Events" to tell process "SketchUp" to set position of window "PH-Composer" to {40, 60}`.
AXRaise the panel window before clicking in it. The Edit menu needs an AXRaise of the document window
(`cm10.skp`) first. Each step has a DOM read the conductor checks through the bridge instead of pixels:
`B eval "CM10.read"` then `B eval "CM10.result('pane')"`, and `B eval "CM10.climate"` for the Model.

1. Hover an edited cell in Monthly temperatures (January, Air). The tooltip reads "Edited. The station file
   reads ...". `CM10.read`: `edited` has 2 entries, `tags` include Edited.
2. Click **Restore Original Values** in the edited line. `CM10.climate`: edited 0. `CM10.read`: no Edited tag.
3. AXRaise `cm10.skp`, then **Edit > Undo Restore Climate Values**. `CM10.climate`: edited 2.
   **Edit > Redo Restore Climate Values**: edited 0. One Undo step each way.
4. AXRaise the panel. Click the Average wind speed field, select all, type `5`, press **Return**.
   `CM10.climate`: wind 5, edited 0. AXRaise `cm10.skp`, **Edit > Undo Edit Climate Values**: wind back to
   its earlier value.
5. AXRaise the panel. Click **More climate actions** (the ellipsis at the header's right), then **Clear**.
   `CM10.read`: `state` ready, `confirm` false; `CM10.climate`: state none. AXRaise `cm10.skp`,
   **Edit > Undo Clear Climate**: `CM10.climate` complete, ALDER_FIELD; `CM10.read`: the pane again.
6. Capture the panel window by id at 1280, 420 (`CM10.size(420, 732)`) and 360 (`CM10.size(360, 520)`) px,
   scrolled to the top and to Where this lives, then `CM10.size(1280, 800)`. Keep the captures under
   `_private/host/<run>/CM10/`.

Before stopping, close any bubble or dialog left open. Then `B eval "CM10.cleanup(<created>)"` (true when no
settings folder existed before the case), `B quit`, and `acceptance_case.py finish CM10 --run-dir
_private/host/<run> --evidence planning/features/phase-04-climate/evidence/<run>.md` with the observations
from parts A and B in `_private/host/<run>/CM10/observations.json` (`polish` blocked on part C).

## Part C: Ed's verification pass

The P4c-10 items under "For Ed's verification pass" in the [packet STATUS](../STATUS.md#for-eds-verification-pass).
CM10 reads "agent run Pass; Ed's pass pending" until Ed has done them.
