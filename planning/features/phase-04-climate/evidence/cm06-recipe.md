# CM06 host recipe: the Climate tab, Site location and Design temperatures

DATE: 2026-11-18
STATUS: Written after the last review fix of PR #517. Part A runs through the bridge with no window focus; part B needs SketchUp in front and is the conductor's; part C is Ed's verification pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM06](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM06` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_panel_test.js`, `tests/climate_geolocation_test.rb` and the browser check
`tools/ui-preview/climate_checks.cjs` in the PR's `make ci` and evidence. Write `<run>` as
`cm06-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm06.rb`. It prepends a read-only probe on the panel's
`receive` (the SH-03-A8 arrangement): the page posts `{type: "probe.dom"}` reads through its own
callback and the host keeps them. Panel actions in part A are scripted DOM events in the real
HtmlDialog, labelled as such: they prove the panel's wiring and what it sends, not a native gesture.
Model reads go through the public `ph_composer.climate.*` queries.

`B` stands for `uv run tools/hostkit/host_bridge.py`; in zsh call it through a wrapper script. `D` is
the absolute path of the driver. Each `B eval` is its own call, so the panel's timers run between them.

## Part A: bridge, no window focus (the stage agent)

### A1. Build, install, open the fixture, begin

```sh
git switch feature/climate-p4c-06 && git pull --ff-only     # the PR head under test
make rbz install bridge-install
mkdir -p _private/host/<run>/CM06
B launch "$PWD/_private/host/<run>/CM06/cm06.skp" --fresh-from _private/host/blank-template.skp
B state      # SketchUp 2026, the installed build, cm06.skp only
uv run tools/hostkit/acceptance_case.py begin CM06 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM06/cm06.skp --fixture-id "fresh copy of blank-template.skp" \
  --control combined --assert tab-order --assert cards --assert site-not-set --assert set-location \
  --assert partial-refused --assert geolocation --assert design-per-field --assert units \
  --assert narrow --assert undo-redo --assert polish \
  --window "cm06.skp the only document in a fresh process, the panel open" \
  --target "the Model's site and design temperatures" \
  --probe "probe.dom reads through the panel's own callback; scripted DOM events, labelled"
B eval "load '$D'; CM06.state"       # site not_set, design not_set, geolocation geolocated false
B eval "load '$D'; CM06.open_panel"
```

### A2. Tab order and the opening tab

```sh
B eval "CM06.read('tabs')";  B eval "CM06.result('tabs')"
```

Expected: the first button is Climate, then Zones; Zones is pressed; the Climate pane is hidden.

### A3. The cards, the Planned card and Site location Not set

```sh
B eval "CM06.click_tab('climate')"
B eval "CM06.read('cards')";  B eval "CM06.result('cards')"
B eval "CM06.click_card('hourly')";  B eval "CM06.read('cards')";  B eval "CM06.result('cards')"
B eval "CM06.read('pane')";  B eval "CM06.result('pane')"
```

Expected: Site location, Phius climate data and Design temperatures read Not set; Hourly weather file
reads Planned, is disabled, and the click leaves Site location current; the pane is the empty state
with Set Location in the header and in the pane.

### A4. Set Location: a partial site, geolocation, then Set

```sh
B eval "CM06.click_button(CM06::PANE, 'Set Location…')"
B eval "CM06.fill(CM06::DIALOG, 'Latitude', '42.3233')"
B eval "CM06.fill(CM06::DIALOG, 'Longitude', '-73.3887')"
B eval "CM06.read('dialog')";  B eval "CM06.result('dialog')"         # setDisabled true: a partial site
B eval "CM06.click_button(CM06::DIALOG, 'Read from SketchUp Geolocation')"
B eval "CM06.read('dialog')";  B eval "CM06.result('dialog')"         # status: no geolocation; fields kept
B eval "CM06.fill(CM06::DIALOG, 'Elevation', '300')"
B eval "CM06.select(CM06::DIALOG, 'Climate zone', '15')"
B eval "CM06.fill(CM06::DIALOG, 'Hours from UTC', '-5')"
B eval "CM06.click_button(CM06::DIALOG, 'Set Location')"
B eval "CM06.state"            # site set, five fields as typed; modified true
B eval "CM06.read('cards')";  B eval "CM06.result('cards')"           # the site card's two lines
```

### A5. Design temperatures per field, the warning, IP

```sh
B eval "CM06.click_card('design')"
B eval "CM06.fill(CM06::PANE, '99% heating dry bulb', '-17.2', 'Enter')"
B eval "CM06.state"            # heating -17.2, cooling null, state incomplete
B eval "CM06.fill(CM06::PANE, '1% cooling dry bulb', '30.1')";  B eval "CM06.blur(CM06::PANE, '1% cooling dry bulb')"
B eval "CM06.state"            # both, state set
B eval "CM06.fill(CM06::PANE, 'Source (optional)', 'Synthetic note', 'Enter')"
B eval "CM06.fill(CM06::PANE, '99% heating dry bulb', '35', 'Enter')"
B eval "CM06.state"            # heating 35, warning climate.heating_not_below_cooling
B eval "CM06.read('pane')";  B eval "CM06.result('pane')"             # the warning line
B eval "CM06.fill(CM06::PANE, '99% heating dry bulb', '', 'Enter')"
B eval "CM06.state"            # heating null: clearing unsets
B eval "CM06.click_button(CM06::APP, 'IP')"
B eval "CM06.fill(CM06::PANE, '99% heating dry bulb', '5', 'Enter')"
B eval "CM06.state"            # heating -15.0 °C
B eval "CM06.click_card('site')";  B eval "CM06.read('pane')";  B eval "CM06.result('pane')"  # elevation in ft
B eval "CM06.click_button(CM06::APP, 'SI')"
```

### A6. The narrow widths

```sh
B eval "CM06.size(420, 732)";  B eval "CM06.read('tabs')";  B eval "CM06.result('tabs')"
B eval "CM06.read('cards')";  B eval "CM06.result('cards')"           # select shown, list hidden
B eval "CM06.size(360, 520)";  B eval "CM06.read('tabs')";  B eval "CM06.result('tabs')"
B eval "CM06.read('cards')";  B eval "CM06.result('cards')"
```

Capture the panel window by id at each size (`screencapture -x -o -l <id>`, from this shell, never
inside SketchUp), per the native acceptance skill.

### A7. Undo names, read only

```sh
osascript -e 'tell application "System Events" to tell process "SketchUp" to get name of menu item 1 of menu "Edit" of menu bar 1'
```

Expected: "Undo Change Design Temperature". Record each observation in
`_private/host/<run>/CM06/observations.json` and the steps in `steps.md`.

## Part B: SketchUp in front (the conductor, one hold)

On the same Model and head, the panel open:

1. **Native Undo and Redo.** Edit > Undo through the design-temperature steps and Set Site Location,
   reading the Edit menu's label before each; the panel repaints each value back; Edit > Redo
   restores them.
2. **Real clicks in the panel**: the Climate tab, the Hourly weather file card (nothing happens), Set
   Location with a partial site (Set disabled), Tab between the two design temperatures (each saves),
   Escape in the source note (the saved note returns), and the narrow select at 420 px.
3. **Owed check 4, item 2 proper** ([evidence](owed-check-4-20261118.md#left-for-the-conductor-needs-sketchup-in-front)):
   Add Location on a scratch copy, then Set Manual Location on another, each read with the
   owed-check probe, then Read from SketchUp Geolocation in the Climate tab.

Then `acceptance_case.py finish CM06` with the observations from parts A and B.

## Part C: Ed's verification pass

The items under "For Ed's verification pass" in the [packet STATUS](../STATUS.md#for-eds-verification-pass).
CM06 reads "agent run Pass; Ed's pass pending" until Ed has done them.
