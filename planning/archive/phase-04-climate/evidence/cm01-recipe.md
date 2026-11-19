# CM01 host recipe: site and design temperatures, panel closed

DATE: 2026-11-17
STATUS: Run 2026-11-17 ([evidence](cm01-20261117.md)) and rechecked 2026-11-18 ([evidence](cm01-20261118.md)): Pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

Runs [CM01](../ACCEPTANCE.md) on the merged head, SketchUp 2026 on macOS, the panel closed, through
the [native acceptance skill](../../../../.agents/skills/ph-composer-native-acceptance/SKILL.md).
The case is `CM01` in [`cases.json`](../../../native-acceptance/cases.json). The offline half is
`tests/climate_settings_test.rb`, `tests/climate_site_walkthrough_test.rb` and the units tests in the
merged PR's `make ci`. Paths in `_private/` stay there; write `<run>` as `cm01-<yyyymmdd>`.

## 1. Build, install and open the fixture

```sh
git switch main && git pull --ff-only
make rbz install bridge-install
mkdir -p _private/host/<run>/CM01
uv run tools/hostkit/host_bridge.py launch "$PWD/_private/host/<run>/CM01/cm01.skp" \
  --fresh-from _private/host/blank-template.skp
uv run tools/hostkit/host_bridge.py state      # SketchUp 2026, the installed build, cm01.skp only
uv run tools/hostkit/acceptance_case.py begin CM01 --run-dir _private/host/<run> \
  --fixture _private/host/<run>/CM01/cm01.skp --fixture-id "fresh copy of blank-template.skp" \
  --control native --assert walkthrough --assert undo-names --assert undo-redo --assert save-reopen \
  --window "cm01.skp the only document in a fresh process, panel closed" \
  --target "the Model's site and design temperatures" --probe "none; public API reads through the bridge"
```

## 2. Run the walkthrough

```sh
uv run tools/hostkit/host_bridge.py eval \
  "load '$PWD/tools/examples/climate/site_walkthrough.rb'; ClimateSiteWalkthrough.state"
uv run tools/hostkit/host_bridge.py eval 'ClimateSiteWalkthrough.run'
```

The first call must show `site.state` `not_set` and `design_temperatures.state` `not_set` (the
`walkthrough` assertion's starting read). `run` must return `passed: true` with seven steps:
discover, site not set, `site.update`, three `design_temperatures.update`, read back. Run it once
per fresh Model: a second `run` fails at "site not set". Use `verify` to read back afterwards.

## 3. Undo and Redo through the Edit menu

Under one full-screen hold, open the Edit menu before each Undo and record its first item's title.
Read state in a separate bridge call after each step.

| Step | Edit menu shows | Then `ClimateSiteWalkthrough.state` reads |
| --- | --- | --- |
| Undo 1 | Undo Change Design Temperature | `design_temperature_source` null, state `set` |
| Undo 2 | Undo Change Design Temperature | `cooling_1_c` null, state `incomplete` |
| Undo 3 | Undo Change Design Temperature | `heating_99_c` null, state `not_set` |
| Undo 4 | Undo Set Site Location | site state `not_set` |
| Redo four times | Redo Set Site Location first, then Redo Change Design Temperature three times | `ClimateSiteWalkthrough.verify` gives `passed: true` |

```sh
uv run tools/hostkit/host_bridge.py eval 'ClimateSiteWalkthrough.state'
uv run tools/hostkit/host_bridge.py eval 'ClimateSiteWalkthrough.verify'
```

## 4. Save and reopen in a fresh process

```sh
uv run tools/hostkit/host_bridge.py save
uv run tools/hostkit/host_bridge.py quit
uv run tools/hostkit/host_bridge.py launch "$PWD/_private/host/<run>/CM01/cm01.skp"
uv run tools/hostkit/host_bridge.py eval \
  "load '$PWD/tools/examples/climate/site_walkthrough.rb'; ClimateSiteWalkthrough.verify"
```

`verify` compares against constants in the walkthrough, so it must give `passed: true` in the new
process with nothing run first.

## 5. Record

Write `<run>/CM01/observations.json`, one row per assertion, then:

```sh
uv run tools/hostkit/acceptance_case.py finish CM01 --run-dir _private/host/<run> \
  --evidence planning/archive/phase-04-climate/evidence/cm01-<yyyymmdd>.md
```

The evidence document records the commit, the installed build, the fixture, each assertion and the
exact host versions. CM01 becomes Pass in [ACCEPTANCE](../ACCEPTANCE.md) only from that ledger row.
