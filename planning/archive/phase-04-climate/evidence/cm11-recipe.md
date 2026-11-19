# CM11 host recipe: hand entry and Edit Values

DATE: 2026-11-18
STATUS: Written after the last review fix of PR #522. Part A run by the stage agent on `408285df`, all as expected (`_private/host/cm11-20261118/CM11/steps.md`); part B run by the conductor under one hold, all as expected ([evidence](cm11-20261118.md)); part C is Ed's verification pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM11](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM11` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_values_editor_test.js` and the browser check `tools/ui-preview/climate_values_checks.cjs`.
Write `<run>` as `cm11-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm11.rb`, CM10's with the values editor's reads and gestures, and
the same read-only probe on the panel's `receive`. Panel actions in part A are scripted DOM events in the real
HtmlDialog, labelled as such, and a paste in part A is a scripted `ClipboardEvent` through the grid's own
listener: they prove the wiring and what is sent, not a native gesture or the system clipboard. Adding a
folder uses the labelled `UI.select_directory` stand-in CM03 proved.

**Data.** Every value is invented. The paste block is `CM11.block`: eight rows led by a label ("Series 1" to
"Series 8"), the first six of fifteen values and the last two of twelve, value `r * 20 + c + 0.5` for row `r`
and column `c`, with CRLF line ends. The folder `Hand One` holds one invented station, Alder Field (QA, 18 km
north of the site at 40.0, -100.0, 500 m). No licensed data is read in parts A and B.

**What it touches.** The case writes Ed's settings file. A1 records whether its folder exists;
`CM11.cleanup` removes only the case's folder, and the settings folder when the case created it.

`B` stands for `uv run tools/hostkit/host_bridge.py` (in zsh, the wrapper script); `D` is the driver's
absolute path. Each `B eval` is its own call, so the panel's timers run between them; read a result with
`B eval "CM11.result('editor')"` (or `'pane'`, `'click'`, `'card'`) after the call that posts it.
`CM11.editor` posts `editor`: the title, the six fields with their values and whether read only, the cell
count, the first and last cell, Heating 1's dewpoint cell, invalid cells, the row headings, the paste notice,
the status line beside Save, Save disabled or not, and whether the dialog fits and its grid scrolls.
`CM11.detail` answers the Model's climate: state, origin, missing rows, edited cells, the limit check, and
January air, December sky, Cooling's global radiation, Heating 1's dewpoint, wind speed and elevation.

## Part A: bridge, no window focus (the stage agent)

### A1. Build, install, open the fixture, begin

```sh
make rbz install bridge-install                                   # on the PR head
B launch "$PWD/_private/host/<run>/CM11/cm11.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm11.skp only
uv run tools/hostkit/acceptance_case.py begin CM11 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM11/cm11.skp --fixture-id "fresh copy of blank-template.skp" \
  --control combined --assert enter --assert paste --assert save-needs --assert gaps --assert not-checked \
  --assert edit-hand --assert edit-station --assert stale --assert sizes --assert undo --assert real-paste \
  --assert licensed-paste --assert polish --window "cm11.skp the only document in a fresh process" \
  --target "the site set, no climate data folder, then a synthetic folder of the case's" \
  --probe "the probe.dom read on the panel's own callback; scripted paste events; a labelled chooser stand-in"
B eval "load '$D'; CM11.state"           # settings_exists noted; site not_set; climate none
B eval "CM11.set_site"
```

### A2. Enter Values by Hand with no folder (board 12)

```sh
B eval "CM11.open_panel"; B eval "CM11.click_tab('climate')"; B eval "CM11.click_card('phius')"
B eval "CM11.read"                     # state no_folder
B eval "CM11.click('Enter Values by Hand…')"; B eval "CM11.editor"
#   open; title "Enter Phius climate values"; 120 cells, all empty; Save disabled; fits; not sideways
```

### A3. One paste, its label column left out

```sh
B eval "CM11.paste(0)"; B eval "CM11.editor"
#   first "0.5"; last (sky temperature, Cooling) ""; Heating 1 dewpoint ""; notice "Pasted 8 rows."
B eval "CM11.paste(15, CM11.block(8, false))"; B eval "CM11.editor"
#   notice "The pasted block is 8 rows by 15 values; from this cell the grid holds 7 by 15. Nothing was filled."
```

### A4. Save waits for the name and elevation, and saves with gaps

```sh
B eval "CM11.type('Name', 'Invented Street')"; B eval "CM11.editor"      # Save still disabled
B eval "CM11.type('Station elevation', '92')"; B eval "CM11.editor"      # Save enabled
B eval "CM11.editor_click('Save')"; B eval "CM11.detail"
#   state incomplete; origin hand; missing [daily_temp_swing_k, wind_speed_m_s]; check no_station_coordinates;
#   air_jan 0.5; sky_dec 151.5; global_cool 114.5; dewpoint_heat_1 null
B eval "CM11.editor"; B eval "CM11.read"; B eval "CM11.card"
#   editor closed; tags [Incomplete]; notice "Incomplete: Daily temperature swing; Average wind speed. Export ...";
#   limit check "Not checked, entered by hand: ..."; card "... Incomplete"
```

### A5. Edit Values on the hand climate completes it

```sh
B eval "CM11.click('Edit Values…')"; B eval "CM11.editor"
#   title "Edit climate values"; Name "Invented Street", not read only; first "0.5"
B eval "CM11.type('Daily temperature swing', '11')"; B eval "CM11.type('Average wind speed', '3.5')"
B eval "CM11.editor_click('Save')"; B eval "CM11.detail"     # state complete; missing []; edited []
B eval "CM11.read"; B eval "CM11.card"                        # no Incomplete tag; card "Not checked"
```

### A6. A stale save keeps the draft

```sh
B eval "CM11.click('Edit Values…')"; B eval "CM11.type(0, '7')"
B eval "CM11.change_elsewhere"                                # an agent's write while the editor is open
B eval "CM11.editor_click('Save')"; B eval "CM11.editor"
#   open; status names the refusal; first "7"; Save enabled
B eval "CM11.editor_click('Cancel')"; B eval "CM11.detail"    # air_jan 0.5: nothing saved
```

### A7. Edit Values on a station marks it edited (board 15)

```sh
B eval "CM11.clear"; B eval "CM11.make_folder"; B eval "CM11.add_folder"     # id noted
B eval "CM11.attach('<id>')"; B eval "CM11.climate"                           # complete, ALDER_FIELD, edited 0
B eval "CM11.click_card('site')"; B eval "CM11.click_card('phius')"
B eval "CM11.click('Edit Values…')"; B eval "CM11.editor"
#   Name "Alder Field" read only; Latitude and Longitude read only
B eval "CM11.type(13, '77')"; B eval "CM11.editor_click('Save')"; B eval "CM11.detail"
#   edited [{row: air_c, column: heat_2}] (cell 13 is outdoor temperature, Heating 2)
B eval "CM11.read"            # tags [Pass, Edited]; "1 value differs from the station file: ..."
B eval "CM11.click('Restore Original Values')"; B eval "CM11.climate"         # edited 0
```

### A8. Sizes

```sh
B eval "CM11.click('Edit Values…')"
B eval "CM11.size(420, 732)"; B eval "CM11.editor"; B eval "CM11.size(360, 520)"; B eval "CM11.editor"
#   fits; not sideways; grid scrolls
B eval "CM11.size(1280, 800)"; B eval "CM11.editor_click('Cancel')"
B eval "CM11.clear"; B eval "CM11.read"                         # state ready
```

Leave the panel and the Model as they are for part B: the panel at 1280 x 800 on the Climate tab with the Phius
card, no climate in the Model, the site set and the folder set up, so the pane reads "No Phius climate data in
this Model" with Choose Station and Enter Values by Hand.

## Part B: real input, a real paste and native Undo (the conductor, one hold)

The panel may be on another Space: `app_bring_to_current_space`, then System Events
`tell application "System Events" to tell process "SketchUp" to set position of window "PH-Composer" to {40, 60}`.
AXRaise the panel window before clicking in it. The Edit menu needs an AXRaise of the document window
(`cm11.skp`) first. Each step has a DOM read the conductor checks through the bridge instead of pixels.

**Clipboard.** Before step 2, put this synthetic block on the clipboard with
`ruby -e 'print Array.new(8) { |r| (["Series #{r + 1}"] + Array.new(r >= 6 ? 12 : 15) { |c| format("%.1f", r * 20 + c + 0.5) }).join("\t") }.join("\r\n") + "\r\n"' | pbcopy`,
the same text as `CM11.block` (the driver itself loads only inside SketchUp). It is eight lines, tab-separated, CRLF line ends, the first line beginning `Series 1	0.5	1.5`
and the last `Series 8	140.5	141.5 … 151.5`. Reading it back with `pbpaste | head -1` is enough.

1. AXRaise the panel. Click **Enter Values by Hand…**. `CM11.editor`: open, 120 empty cells, Save disabled.
2. Click the first cell (Outdoor temperature, Jan) and press **Cmd+V**. `CM11.editor`: first "0.5", last
   (sky temperature, Cooling) "", notice "Pasted 8 rows.". This is the real clipboard through the real paste.
3. Click **Name**, type `Real Street`; click **Station elevation**, type `92`; press **Tab** once and type `11`
   in Daily temperature swing, **Tab** and `3.5` in Average wind speed. Click the grid's first cell, press
   **Down Arrow** twice (East, Jan, its text selected) and type `9`. `CM11.editor`: Save enabled.
4. Click **Save**. `CM11.detail`: state complete, origin hand, name "Real Street";
   `B eval "CM11.query('climate.get').dig('value', 'climate', 'values', 'monthly', 'rad_east_kwh_m2', 0)"` reads 9. AXRaise `cm11.skp`, **Edit > Undo Enter Climate Values**: `CM11.detail` state none;
   **Edit > Redo Enter Climate Values**: complete again. One Undo step each way.
5. AXRaise the panel. Click **Edit Values…** in the page header, click the last cell (Sky temperature, Cooling),
   select all, type `2`, press **Return**, then click **Save**. `CM11.detail`: complete. AXRaise `cm11.skp`,
   **Edit > Undo Edit Climate Values**: `CM11.detail` returns the earlier values; Redo.
6. Capture the editor by window id at 1280, 420 (`CM11.size(420, 732)`) and 360 (`CM11.size(360, 520)`) px,
   opened with Edit Values, then Cancel and `CM11.size(1280, 800)`. Keep the captures under
   `_private/host/<run>/CM11/`.

Before stopping, close any bubble or dialog left open. Then `B eval "CM11.cleanup(<created>)"` (true when no
settings folder existed before the case), `B quit`, and `acceptance_case.py finish CM11 --run-dir
_private/host/<run> --evidence planning/archive/phase-04-climate/evidence/<run>.md` with the observations
from parts A and B in `_private/host/<run>/CM11/observations.json` (`licensed-paste` and `polish` blocked on
part C).

## Part C: Ed's verification pass

Ed at the mouse, with his own licensed files; nothing from them is saved, captured or quoted, and the Model is
closed without saving afterwards.

1. **A Phius workbook.** In Excel, select the eight series rows of the SI block, from the label column to the
   Cooling column, and copy. In the panel, Enter Values by Hand, click the first cell, paste. Expected: every
   month filled, the design columns filled for the first six rows and empty for dewpoint and sky, "Pasted 8
   rows." with no count.
2. **A station text file.** Open a `-mon.txt` file in TextEdit, select the eight series lines, copy, and paste
   into the first cell. Expected: the same, with "6 values were not numbers and were left empty." for the notes
   in the dewpoint and sky lines.
3. Cancel the editor. Record in the evidence only the shape seen (rows, columns, the notice), never a value.
4. The P4c-11 items under "For Ed's verification pass" in the [packet STATUS](../STATUS.md#for-eds-verification-pass).

CM11 reads "agent run Pass; Ed's pass pending" until Ed has done part C.
