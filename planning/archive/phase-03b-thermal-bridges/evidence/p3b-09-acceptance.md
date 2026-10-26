# P3b-09 evidence: thermal-bridge acceptance and handoff (T09)

DATE: 2026-10-26
STATUS: Integrated host run on branch `feature/thermal-bridges-p3b-09` from `main` at `b73e5c0b` (P3b-01 to P3b-08 merged), SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1. All ten host assertions and every offline gate pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T09](../ACCEPTANCE.md). The host half was recorded through `tools/hostkit/acceptance_case.py` in
`_private/host/t09/T09/` (gitignored; synthetic fixture, no project data). The ledger row records a branch commit,
not `main`.

## Offline gates

All on the stage's code, which is `main` at `b73e5c0b` (P3b-09 changes no shipped source).

| Gate | Result |
| --- | --- |
| `make ci`, Ruby 3.2.2 | Green on the merged P3b-08 head; again on this branch's final head |
| `make ci RUBY=<2.7.2>` | Green: 2,224 runs, 25,235 assertions, no failure; 754 JS tests; 258 Python tests |
| `make coverage` | Ruby 97.2% of 23,135 lines (minimum 93%); JavaScript 96.8% of 14,606 lines (minimum 94%); Python 95.2% (minimum 92%) |
| `make ui-checks` | Every browser check passes, the thermal-bridges check among them, Library and Window screens at 1280, 900, 420 and 280 px |
| `make runtime-browser-check` | `chromium_88: true`; cold boot 2,276 ms (ceiling 6,000), warm round trip 0.6 to 1.7 ms (ceiling 100) |
| `vendor.py --check` | 148 assets, 8 wheels (the Phase 3a set), 21,971,479 bytes runtime |
| Packaged footprint (`rbz-check`) | 524 files, 7,961,683 bytes packed, 24,541,739 bytes installed: under the 26,000,000 ceiling, 547,656 past the 23,994,083 baseline (budget 1,500,000), above the 24,000,000 target. The baseline is reset to 24,541,739 at this close ([D3b-24](../DECISIONS.md)) |

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `b73e5c0b`, SHA-256 `081458737a14b091abb5537685184aefe40a6fc43164ede3588a2a26a6778244` |
| Fixture | `_private/host/t09/T09/t09.skp` (SHA-256 `f84f4426`), a copy of `t09-reference-base.skp`: the reference geometry from `ThermalBridgeReferenceModel.build` (Zones A and B, Zone W inside a Group turned 30 degrees, a Window Unit on Zone A's south wall, the Balcony line, a line at the Model root, every Face classified), one complete Assembly on all 19 Zone Faces, and no Thermal Bridge Type |
| Processes | Fresh launches through `host_bridge.py launch`: the authoring session; the reopen and export; a restoration read |
| Controls | The computer-use controller in background mode for the panel, the menu bar (Extensions, Edit, File) and viewport clicks; the bridge for labelled setup (selections as a user would make them, cameras, the split line, the export's approved location) and every readback, one per call. Driver record: `_private/host/t09/T09/steps.md` |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Types in the panel | The five types through New Thermal Bridge Type: Parapet 0.05 Ambient, Slab edge 0.12 Perimeter, Footing -0.02 Basement floor, Balcony 0.25 Ambient, Draft with no psi-value | `1-types.json`, `1-types-panel.jpg` |
| Assign bar | Zone A's and Zone B's roof perimeters, "Assigned Parapet to 3 Edges." each: Parapet 1 14.000 m, Parapet 2 12.000 m | `2-assign-a.json`, `3-before-undo.json` |
| Undo and Redo | Edit read "Undo Assign Thermal Bridge" with the model window key; Undo removed exactly Parapet 2, Redo restored it | `3-after-undo.json`, `3-after-redo.json` |
| Menu route | Edit > 3 Edges > Thermal bridge listed the five types; Slab edge 1 (14.000 m) and Footing 1 (12.000 m) | `4-menu-*.json` |
| Edge tool | Armed from the bar: Balcony at quantity 2 on the Balcony line (4.000 m, quantity 2); Parapet on Zone W's four roof Edges inside the turned wrapper, a closed 8.000 m run, Parapet 3; Stop | `5-*.json`, `5-*.jpg` |
| Two Models | A second Model opened with its own session and no records while t09 kept its 5 types and 17 assigned Edges; closing it left t09's six runs | `6-*.json` |
| Split and heal | A line from the middle of an assigned roof Edge split it into two pieces carrying the same `tbe_` id; Parapet 1 stayed one 14.000 m run; erasing the line healed it to three Edges | `7-*.json` |
| Save and reopen | A fresh process read the same types and six runs; totals 6 runs, 5.140 W/K, ACCEPTANCE's 4.740 plus Zone W's 0.400 | `9-reopened.json` |
| Export and reload | One Building-Segment for the three Rooms carrying the six runs with ACCEPTANCE's lengths, psi-values, groups and quantities (Balcony 1 a `LineSegment3D`, the rest `Polyline3D`, Parapet 3 closed with 5 points); conformance passes on the reloaded bytes | `10-readback.json` |
| Restoration | A fresh process with the normal RBZ and no run helper or fault module read the saved schedule and quit cleanly | `11-restoration-*` |

## Limits of this run

- The right-click itself was not driven: a ChatGPT window overlay blocked full-screen clicks over the viewport. The
  menu route used SketchUp's selection submenu (Edit > 3 Edges), which carries the same "Thermal bridge" handler.
  T05 drove the right-click with Ed at the mouse.
- Background control cannot make a second Model window SketchUp's active Model, so the panel did not follow it;
  the panel's Model switch was covered by T07 and the Phase 1 two-Model cases.
- File > Save stayed disabled under background control; the Model was saved through `Model#save`.
- The quantity field took "12" when the controller's select-all missed it; it was corrected to 2 and read back
  through `edge_tool.state` before the click.

## Handoff

- The edge tagging rules are in `context/TECH_STACK.md`, "Edge-owned assignments"; hot-water-piping and
  erv-ducting now point at them and at the edge tool, and the edge registry question (D3b-01) is
  hot-water-piping's.
- The PHX quantity check is in metr-export (P3b-08). G-01 and G-04 close in the geometry-contribution-contracts
  packet.
