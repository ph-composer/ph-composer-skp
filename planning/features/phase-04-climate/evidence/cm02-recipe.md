# CM02 host recipe: the climate record, panel closed

DATE: 2026-11-17
STATUS: Prepared for the conductor. Not run.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM02](../ACCEPTANCE.md) on the merged head, SketchUp 2026 on macOS, the panel closed, through
the [native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md).
The case is `CM02` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_record_test.rb`, `tests/climate_record_operations_test.rb` and
`tests/climate_walkthrough_test.rb` in the merged PR's `make ci`. Paths in `_private/` stay there;
write `<run>` as `cm02-<yyyymmdd>`.

No public operation attaches a station until P4c-04, so the station half uses the development seed
`tools/examples/climate/station_seed.rb`: it builds a synthetic station with
`Climate::Record.from_station` and writes it as one Undo step, "Seed Station Climate". Every other
step goes through registered operations. CM01's ledger row reads `needs_recheck` after this stage
(its paths include `features/climate/*`, `declarations/*` and `site_walkthrough.rb`), so run
CM01's recipe in the same hold, in its own fresh Model.

## 1. Build, install and open the fixture

```sh
git switch main && git pull --ff-only
make rbz install bridge-install
mkdir -p _private/host/<run>/CM02
uv run tools/hostkit/host_bridge.py launch "$PWD/_private/host/<run>/CM02/cm02.skp" \
  --fresh-from _private/host/blank-template.skp
uv run tools/hostkit/host_bridge.py state      # SketchUp 2026, the installed build, cm02.skp only
uv run tools/hostkit/acceptance_case.py begin CM02 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM02/cm02.skp --fixture-id "fresh copy of blank-template.skp" \
  --control native --assert walkthrough --assert undo-names --assert undo-redo --assert save-reopen \
  --window "cm02.skp the only document in a fresh process, panel closed" \
  --target "the Model's climate record and site" --probe "none; public API reads through the bridge"
```

## 2. Run the walkthrough

Each line is its own bridge call, in this order:

```sh
uv run tools/hostkit/host_bridge.py eval \
  "load '$PWD/tools/examples/climate/climate_walkthrough.rb'; load '$PWD/tools/examples/climate/station_seed.rb'; ClimateWalkthrough.state"
uv run tools/hostkit/host_bridge.py eval 'ClimateWalkthrough.run_hand'
uv run tools/hostkit/host_bridge.py eval 'ClimateStationSeed.seed'
uv run tools/hostkit/host_bridge.py eval 'ClimateWalkthrough.run_station'
```

- The first call must read Undo 8's row below: no site, no climate.
- `run_hand` must return `passed: true` with eight steps: no climate, `climate.enter_values`,
  incomplete, `climate.save_values`, complete, restore refuses (`climate.no_original`, nothing
  written), `climate.clear`, cleared.
- `seed` must return `seeded: true`.
- `run_station` must return `passed: true` with ten steps: seeded station, `site.update`,
  passes near, `climate.save_values`, edited, `climate.restore_original`, restored,
  `site.update`, fails far with nothing stored, read back.

Run it once per fresh Model: a second `run_hand` fails at "no climate".

## 3. Undo and Redo through the Edit menu

Click Edit > Undo and Edit > Redo through System Events. Before each click, read the Edit menu's
first item title. After each click, read the state in a separate bridge call:

```sh
uv run tools/hostkit/host_bridge.py eval 'ClimateWalkthrough.state'
```

It returns one compact JSON object with string keys. Compare it whole with the row.

| Step | Edit menu shows | Then `ClimateWalkthrough.state` reads |
| --- | --- | --- |
| Undo 1 | Undo Set Site Location | `{"site":"set","site_latitude_deg":41.1,"climate":"complete","origin":"station","source_type":"phius_approved","edited":0,"air_c_jan":-2.0,"as_read_air_c_jan":-2.0,"verdict":"pass"}` |
| Undo 2 | Undo Restore Climate Values | `{"site":"set","site_latitude_deg":41.1,"climate":"complete","origin":"station","source_type":"user_defined","edited":1,"air_c_jan":-9.0,"as_read_air_c_jan":-2.0,"verdict":"pass"}` |
| Undo 3 | Undo Edit Climate Values | `{"site":"set","site_latitude_deg":41.1,"climate":"complete","origin":"station","source_type":"phius_approved","edited":0,"air_c_jan":-2.0,"as_read_air_c_jan":-2.0,"verdict":"pass"}` |
| Undo 4 | Undo Set Site Location | `{"site":"not_set","site_latitude_deg":null,"climate":"complete","origin":"station","source_type":"phius_approved","edited":0,"air_c_jan":-2.0,"as_read_air_c_jan":-2.0,"verdict":"not_checked"}` |
| Undo 5 | Undo Seed Station Climate | `{"site":"not_set","site_latitude_deg":null,"climate":"none","origin":null,"source_type":null,"edited":0,"air_c_jan":null,"as_read_air_c_jan":null,"verdict":null}` |
| Undo 6 | Undo Clear Climate | `{"site":"not_set","site_latitude_deg":null,"climate":"complete","origin":"hand","source_type":"user_defined","edited":0,"air_c_jan":1.5,"as_read_air_c_jan":null,"verdict":"not_checked"}` |
| Undo 7 | Undo Edit Climate Values | `{"site":"not_set","site_latitude_deg":null,"climate":"incomplete","origin":"hand","source_type":"user_defined","edited":0,"air_c_jan":null,"as_read_air_c_jan":null,"verdict":"not_checked"}` |
| Undo 8 | Undo Enter Climate Values | `{"site":"not_set","site_latitude_deg":null,"climate":"none","origin":null,"source_type":null,"edited":0,"air_c_jan":null,"as_read_air_c_jan":null,"verdict":null}` |

Then Redo eight times. The Edit menu shows, in order: Redo Enter Climate Values, Redo Edit Climate
Values, Redo Clear Climate, Redo Seed Station Climate, Redo Set Site Location, Redo Edit Climate
Values, Redo Restore Climate Values, Redo Set Site Location. After Redo n (1 to 7) the state reads the row of
Undo 8 - n, and after the eighth:

```sh
uv run tools/hostkit/host_bridge.py eval 'ClimateWalkthrough.verify'
```

must give `passed: true`, with the state
`{"site":"set","site_latitude_deg":42.0,"climate":"complete","origin":"station","source_type":"phius_approved","edited":0,"air_c_jan":-2.0,"as_read_air_c_jan":-2.0,"verdict":"fail"}`.

## 4. Save and reopen in a fresh process

```sh
uv run tools/hostkit/host_bridge.py save
uv run tools/hostkit/host_bridge.py quit
uv run tools/hostkit/host_bridge.py launch "$PWD/_private/host/<run>/CM02/cm02.skp"
uv run tools/hostkit/host_bridge.py eval \
  "load '$PWD/tools/examples/climate/climate_walkthrough.rb'; ClimateWalkthrough.verify"
```

`verify` compares against constants in the walkthrough, so it must give `passed: true` in the new
process with nothing run first; `as_read_air_c_jan` shows the as-read copy came back with the
record.

## 5. Record

Write `<run>/CM02/observations.json`, one row per assertion, then:

```sh
uv run tools/hostkit/acceptance_case.py finish CM02 --run-dir _private/host/<run> \
  --evidence planning/features/phase-04-climate/evidence/cm02-<yyyymmdd>.md
```

The evidence document records the commit, the installed build, the fixture, each assertion and the
exact host versions. CM02 becomes Pass in [ACCEPTANCE](../ACCEPTANCE.md) only from that ledger row.
