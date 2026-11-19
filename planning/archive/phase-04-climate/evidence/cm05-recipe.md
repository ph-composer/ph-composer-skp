# CM05 host recipe: the site and climate in the exported HBJSON

DATE: 2026-11-18
STATUS: Run 2026-11-18 on `e4392993`: Pass ([evidence](cm05-20261118.md)). Every step ran through the bridge; none needed SketchUp in front.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM05](../ACCEPTANCE.md) on the PR head, SketchUp 2026 on macOS, the panel closed, through the
[native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md). The case
is `CM05` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_export_test.rb`, `tests/python/test_site_sections.py` and, with the `phx` group,
`tests/python/test_site_phx_round_trip.py`. Write `<run>` as `cm05-<yyyymmdd>`.

The driver is `_private/host/<run>/driver/cm05.rb`; the read-back is `driver/readback.py`. Product
reads and writes go through the public `ph_composer.climate.*` operations and `API.start_export`. Two
labelled development stand-ins, both proved before: `UI.select_directory` answers a copy of the
invented climate folder for one `folders.add` call (CM03), and `ApprovedLocations.approve` stands in
for the Export tab's "Allow agents to export here" (SH3-A8E, DV4). Every value is invented: the
fixture is `tests/fixtures/climate/folder/`. The export opens its own runtime window; the driver
hands focus back to the app that was in front.

**What it touches.** Ed's settings file, `~/Library/Application Support/PH-Composer/settings.json`:
step 1 records whether its folder exists, and step 6 removes it when it was absent.

`B` stands for `uv run -q tools/hostkit/host_bridge.py`, `D` the driver's absolute path. Each `B eval`
is its own call. `export <name>` is the three calls:

```sh
B eval "load '$D'; CM05.start_export('<name>')"   # completed, a task id, the caller, the session
B wait-for export_finished --param session=<s> --param caller=<c> --param task=<t> --deadline 180 --interval 2 --json
B eval "load '$D'; CM05.outcome('<name>')"        # export.complete, <name>.hbjson and its report beside it
```

## 1. Build, install, open the fixture, begin

The fixture predates the interior-pair Assembly rule: before the first export, the driver's
`repair_fixture` gives one interior Face its Assembly again through the public
`zones.faces.assign_assembly` (labelled in `steps.md`). The whole of steps 1 to 4 after `begin` is
`sh _private/host/<run>/cm05-run.sh`.

```sh
make rbz install bridge-install
mkdir -p _private/host/<run>/CM05/out
cp _private/host/envelope/reference-assigned.skp _private/host/<run>/CM05/cm05.skp
B launch "$PWD/_private/host/<run>/CM05/cm05.skp"
uv run tools/hostkit/acceptance_case.py begin CM05 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM05/cm05.skp --fixture-id "fresh copy of envelope/reference-assigned.skp" \
  --control bridge --assert table-rows --assert provenance --assert findings --assert same-site \
  --assert defaults --assert round-trip --assert privacy \
  --window "cm05.skp the only document in a fresh process, panel closed" \
  --target "the reference Model's site, climate and design temperatures, and its exported HBJSON" \
  --probe "none; public API through the bridge, the chooser and the export approval stood in"
B eval "load '$D'; CM05.state"    # settings_exists noted; site not_set; climate none; preflight []
```

## 2. The reference Models, one export each

| Name | Arrange (driver calls) | Preflight (climate codes) |
| --- | --- | --- |
| `h-neither` | none | none |
| `g-site-alone` | `set_site` with `hours_from_utc` -6 | none |
| `a-board18` | `add_fixture`, `set_site` (offset unset), `set_design`, `attach`, `edit_one` | `climate.utc_offset_not_set` |
| `b-unedited` | `set_site` (offset -6), `clear_climate`, `attach` | none |
| `c-failing` | `attach('XA/OUTSIDE_DISTANCE-mon.txt')` (replaces) | `climate.outside_phius_limits` |
| `d-hand` | `hand_climate` | `climate.not_checked` |
| `e-incomplete` | `empty_one` | `climate.incomplete`, `climate.not_checked` |
| `f-no-site` | `clear_site` | `climate.site_not_set`, `climate.incomplete`, `climate.not_checked` |

After each arrangement, `B eval "load '$D'; CM05.state"`, then `export <name>`. Every export ends
`export.complete` with no blocking finding.

## 3. Read back (offline, outside SketchUp)

```sh
uv run --group phx python -I _private/host/<run>/driver/readback.py _private/host/<run>/CM05/out _private/host/<run>
uv sync     # take the phx group back out of .venv
```

Expected per export: one Site on every Building Segment (`same_site_everywhere`); `h-neither` and
`f-no-site` default Location and Climate; `g-site-alone` its Location (40.0, -100.0, 500 m, zone 15,
offset -6) over the default Climate with no provenance; `a-board18` `user_defined`, one edited value,
the station's coordinates, `source_uri` null, offset null (`<dUTC/>`, METr NaN); `b-unedited`
`phius_approved`; `c-failing` written with its provenance; `d-hand` `user_defined` with null station
coordinates; `e-incomplete` its Location over the default Climate. Cooling 2 equals Cooling 1 where a
climate is written. WUFI XML and METr JSON give the site's latitude, both elevations, the climate zone,
January's air temperature and the four peak-load temperatures. `path_leaks` is empty for every file.

## 4. Privacy and clean up

```sh
B eval "load '$D'; CM05.privacy"      # run_path_found and home_path_found false
B diagnostics --json > _private/host/<run>/CM05/diagnostics.json
B eval "load '$D'; CM05.cleanup(<true when step 1 read settings_exists false>)"
B quit
```

Write `<run>/CM05/observations.json`, one row per assertion, and:

```sh
uv run tools/hostkit/acceptance_case.py finish CM05 --run-dir _private/host/<run> \
  --evidence planning/archive/phase-04-climate/evidence/cm05-<yyyymmdd>.md
```
