# P3b-06 evidence: the thermal-bridge Colour-by mode (T06)

DATE: 2026-10-26
STATUS: Host gate run on branch `feature/thermal-bridges-p3b-06` at `3d7045a7` (PR #312), SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1. All six assertions pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T06](../ACCEPTANCE.md). Offline half: `tests/thermal_bridge_colour_mode_test.rb` (8 runs: world
segments through two composed transforms at the mode's stroke, the legend and HUD in both unit systems, a missing
type, an invalid assignment, a hidden tag, tag folder and ancestor, per-placement counting, select and isolate,
no write), `tests/colour_by_derived_test.rb` (the Edge entry, `stroke:` and its refusal, a hidden tag folder) and
the two folder cases in `tests/colour_by_test.rb`, green on Ruby 3.2.2 and 2.7.2; `make ci` green at `3d7045a7`.
Review (strong): one pre-gate Sonnet read (11 items, the real ones fixed before the PR) and two Codex gpt-6-astra
cycles with the architecture and Ruby rubrics on PR #312 (cycle 1: 1 P2, fixed in `3d7045a7`; cycle 2: no
findings). Host half: recorded through `tools/hostkit/acceptance_case.py` in `_private/host/t06/T06/` (gitignored;
synthetic fixture, no project data). The ledger row records a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `3d7045a7`, SHA-256 `07fb26c4a8ee876db5d762760ca3e37424923952178a890efe280230600de635` |
| Fixture | `_private/host/t06/T06/t06.skp` (SHA-256 `5ddd125b`), a copy of the T04 reference base: Zones A, B and W, Zone W in a Group turned 30 degrees, five types, every Face classified, nothing assigned. The six `edges.assign` calls of `ThermalBridgeColourByWalkthrough.assign` are labelled setup |
| Measurement Model | `_private/host/t06/measure.skp`, a copy of T04's `measure-classified.skp`: 50,040 Edges, 5,000 assigned, every Face classified |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal; the measurement in its own fresh process |
| Controls | Native Colour by menu through System Events for turning the mode on and off; bridge for setup and readbacks; window captures by window id |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Native menu | Extensions > PH-Composer > Colour by > Thermal bridges turned the mode on: `colour_by.state` reads `ph_composer.thermal_bridges.by_type`, "Thermal bridges", entity kind `edge`; stroke 5 | `1-report.json` |
| Thick, coloured, depth-tested | 17 assigned Edges draw in four type colours and nothing else; unassigned Edges stay native. Zone W's roof inside the turned wrapper draws in place. Ground Edges behind the boxes do not show through; the Slab edge shows through the translucent glazing only | `1-on.png`, `1-close.png` |
| Hidden tag, folder and ancestor | Each hides its Edges and keeps the legend: a tagged Balcony Edge; the same tag, its own flag visible, moved into a folder that is then hidden (the folder events rebuilt the drawing); the turned wrapper hidden (Parapet 20 points to 12, Parapet (10) kept) | `2-*.json`, `2-*.png` |
| HUD in the display units | HUD and panel legend agree: Parapet (10) 34 m, Footing (3) 12 m, Slab edge (3) 14 m, Balcony (1) 4 m; after a switch to IP both read 111.55 ft, 39.37 ft, 45.93 ft, 13.12 ft. 34 m is the hand calculation's 26 m of Parapet plus Zone W's 8 m | `3-units-*.json`, `3-units-ip.png` |
| Legend select and Show only this | `select_row` on Parapet selected the ten Parapet Edges across the three Zones and framed them; `isolate` on Slab edge drew only its segments with "Showing only: Slab edge" and every count kept; no row restored all | `4-*.json`, `4-*.png` |
| Draw cost | See below | `5-cost.json` |

## Draw cost at 5,000 assigned Edges

Thirty samples each, milliseconds, `zoom_extents` on the measurement Model, the overlay spike's paired
forced-redraw method plus the Ruby side of `draw`.

| Phase | Median | Max |
| --- | --- | --- |
| Rebuild (`invalidate!(force: true)`) | 224.8 | 264.5 |
| Overlay `draw`, Ruby side, 10,000 segment points | 7.5 | 18.8 |
| `View#refresh`, mode on | 8.8 | 21.7 |
| `View#refresh`, mode off | 2.1 | 16.1 |
| Added per frame, paired | 7.7 | 19.7 |

A frame costs about what the spike's 10,000 triangles cost. The rebuild runs once per committed change while the
mode is on: the 125 ms Model walk T04 measured plus the entries. It is over the 200 ms refresh target only by the
walk's own cost on a Model this size; recorded, not changed.

## Earlier cases the ledger screens

`acceptance_ledger.py status --changed` for the shipping files this stage changed lists the Colour-by cases (A08,
UXK1, ZO-H1 to ZO-H3, ZO-O7, six UXR cases, S05, S09), the registry cases (A04, A09, R01 to R06, E15, E17) and T04.
What changed under them is additive: a mode without `stroke:` draws its lines at the old weight, a tag outside any
hidden folder is skipped exactly as before, the observer gains events, and the registry gains an optional field.
They were not rerun one by one. Regression on the host, fresh process on the reference base
(`_private/host/t06/regression/`): Face type from the native menu reads Wall (13), Floor (3), Roof or ceiling (3)
and fills as before; Window Type reads its one Unit. The reference Window Type has no operation, so S05's
operation marks are covered offline only (`tests/window_colour_modes_test.rb`). T06 itself repeats S05's derived
geometry checks on a real mode: depth, tag, hidden ancestor, legend counts and draw cost.

## Host facts recorded here

- `LayersObserver` callbacks fire for tag folders through the API: hiding a folder rebuilt the drawing (rebuild
  count 12 to 14 in the recorded run) and moving a tag into a new folder did too (9 to 11 in the smoke run before
  it), two rebuilds per change, so a folder hidden in the Tags panel reaches Colour by without a revision. A drag
  in the Tags panel itself was not driven.

## Limits

- A mode's rebuild walks the whole Model on every committed change while it is on (225 ms at 50,040 Edges).
- A missing type's row reads "Missing type"; two missing types are two rows with that label.
- `run_locate` keeps its own copy of the tag folder walk; a third hex-to-rgb copy is in the mode. Both are
  follow-ups.
