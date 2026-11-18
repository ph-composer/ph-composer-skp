# CM07 host recipe: the outline map and placing the site in Set Location

DATE: 2026-11-18
STATUS: Written after the last review fix of PR #518. Part A is the stage agent's (bridge, no window focus); part B needs real mouse gestures and SketchUp in front and is the conductor's; part C is Ed's verification pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM07](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM07` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/outline_map_test.js`, `tests/map_projection_test.js`, `tests/map_ring_test.rb`, the map tests in
`tests/climate_panel_test.js`, `tests/python/test_map_borders.py` and the browser check
`tools/ui-preview/outline_map_checks.cjs`. Write `<run>` as `cm07-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm07.rb`, CM06's with map reads added. It prepends the same
read-only probe on the panel's `receive`: the page posts `{type: "probe.dom"}` reads through its own
callback and the host keeps them. Map gestures in part A are scripted `PointerEvent`s and `WheelEvent`s in
the real HtmlDialog, labelled as such: they prove the wiring, the projection and what is sent, not a
native gesture. The fixture's climate is the synthetic station of
`tools/examples/climate/station_seed.rb` (41.0, -74.0, 30 m); no licensed climate data is used.

`B` stands for `uv run tools/hostkit/host_bridge.py`; in zsh call it through a wrapper script. `D` is the
absolute path of the driver. Each `B eval` is its own call, so the panel's timers run between them.

## Part A: bridge, no window focus (the stage agent)

### A1. Build, install, open the fixture, begin

```sh
make rbz install bridge-install                                   # on the PR head
B launch "$PWD/_private/host/<run>/CM07/cm07.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm07.skp only
uv run tools/hostkit/acceptance_case.py begin CM07 --run-dir _private/host/<run> ...
B eval "load '$D'; CM07.seed"          # the station climate and the site 41.1, -74.0, 40 m: two Undo steps
B eval "CM07.open_panel"; B eval "CM07.click_tab('climate')"; B eval "CM07.watch"
```

### A2. First paint, the station and its ring, and the opening check

```sh
B eval "CM07.open_timed";  B eval "CM07.result('open_timed')"     # firstPaintMs, borders true
B eval "CM07.map_read";    B eval "CM07.result('map')"            # station tone ok, ring true, pin set,
                                                                 # warning null, setDisabled false
```

### A3. Place, type, warn, pan, zoom, reset

```sh
B eval "CM07.press(60, 40)";  B eval "CM07.map_read";  B eval "CM07.result('map')"
#   latitude and longitude filled to four decimals, pin moved; far from the station: the warning names
#   the distance and Set stays enabled once it shows
B eval "CM07.fill(CM07::DIALOG, 'Latitude', '41.12')"; B eval "CM07.fill(CM07::DIALOG, 'Longitude', '-74.01')"
B eval "CM07.map_read";  B eval "CM07.result('map')"             # pin moved, warning gone
B eval "CM07.press(200, 200, 260, 230)"; B eval "CM07.map_read"  # a pan: transform changed, values unchanged
B eval "CM07.wheel(-240)"; B eval "CM07.result('wheel')"         # true: the dialog does not scroll
B eval "CM07.map_button('Zoom in')"; B eval "CM07.map_button('Reset map view')"; B eval "CM07.map_read"
```

### A4. Frame time, network and content policy, keyboard reach, sizes

```sh
B eval "CM07.frames";   B eval "CM07.result('frames')"           # pan and zoom frame intervals, script time
B eval "CM07.network";  B eval "CM07.result('network')"          # added: [], violations: []
B eval "CM07.result('map')"                                      # controls: three, tabIndex 0, enabled
B eval "CM07.size(420, 732)"; B eval "CM07.map_read"; B eval "CM07.size(360, 520)"; B eval "CM07.map_read"
```

Capture the panel window by id at each size (`screencapture -x -o -l <id>`, from this shell). Then set
the site with Set Location (scripted click) and read `CM07.state`: the site as typed, one Set Site
Location step.

## Part B: real gestures and native Undo (the conductor, one hold)

The panel opens on a display the conductor cannot see: first move it with System Events,
`tell application "System Events" to tell process "SketchUp" to set position of window "PH-Composer" to {40, 60}`.
The Edit menu needs an AXRaise of the document window (`cm07.skp`), not the panel.

1. Open Set Location on the Climate tab.
2. **Drag to pan**: press on the map and drag about 150 px; the borders move with the pointer and the
   latitude and longitude fields do not change.
3. **Wheel**: scroll over the map, then over the zoom buttons; the map zooms about the pointer each time
   and the dialog does not scroll.
4. **Zoom in, Zoom out, Reset map view** by click, then by keyboard: Tab from the Longitude field
   backwards (Shift-Tab) or from the dialog's close button until a zoom button has focus, press Space or
   Enter.
5. **Click to place**: click well away from the station's ring; the fields fill, the pin moves and the
   amber warning appears; Set Location is enabled. Click inside the ring; the warning goes.
6. **Hover** the station marker; the cursor is a pointer and its ring outline turns red.
7. **Type** a latitude and longitude off the view (for example 21.3, -157.8); the map pans to the pin.
8. Click **Set Location**; read `CM07.state` through the bridge.
9. **Native Undo and Redo**: Edit > Undo ("Undo Set Site Location") and Redo; the site card follows.

Then `acceptance_case.py finish CM07` with the observations from parts A and B.

## Part C: Ed's verification pass

The items under "For Ed's verification pass" in the [packet STATUS](../STATUS.md#for-eds-verification-pass).
CM07 reads "agent run Pass; Ed's pass pending" until Ed has done them.
