# SD07: integration acceptance

DATE: 2026-11-20
STATE: Pass 2026-11-20 on `906a102c`. Host part run 2026-11-20; Ed opened both files and reported them right ("looks ok in METr", "WUFI looks right"); all ten assertions recorded `pass` with `acceptance_case.py finish`.

## Offline part, P5s-07 branch

Run on the P5s-06 head with the P5s-07 changes, macOS, Ruby 3.2.2 and 2.7.2, CPython 3.11.13.

| Check | Command | Result |
| --- | --- | --- |
| Gate, Ruby 3.2.2 | `make ci` (`RUBY_TEST_TIMEOUT=2400` for the machine's load) | green on the commit; counts in the PR body |
| Gate, Ruby 2.7.2 (the SketchUp 2023 floor) | `make ci RUBY=<rbenv 2.7.2>/bin/ruby` | lint, JavaScript (1031 pass) and Python (297 passed, 1 skipped) green; the Ruby suite passed its 900 s limit at a load average of 16, so it was rerun alone with `RUBY_TEST_TIMEOUT=2400`: 3120 runs, one failure, `api_test.rb` pinning API minor 71, fixed with the 1.72 bump and green on 2.7.2 |
| Coverage | `make coverage` | Ruby 97.2% of 31,266 lines (minimum 93%); JavaScript 97.4% of 19,604 lines (minimum 94%); Python 94.95% (minimum 92%) |
| Runtime page in Chromium 88 | `make runtime-browser-check` | pass, no console errors |
| Footprint | `uv run tools/runtime/vendor.py --check` | "Runtime verified: 171 assets, 8 wheels, 22487023 bytes" |
| Browser checks | `make ui-checks` | every check passes but `assembly_hover` ("the center has the normal segment hover wash"), which fails the same way on a rerun. Phase 5 changed no file under `src/ph_composer/html/` or `tools/ui-preview/`, so it predates this packet; a follow-up, not an SD07 finding. `inventories` timed out once under load and passed on its rerun |

Coverage ran before the P5s-07 preflight fix (3,117 Ruby runs); the gates above ran after it.

## Preview files for Ed

Written by `_private/host/batch-20261119/convert.py --reference` from the reference model as
`tests/python/test_shade_phx_round_trip.py` builds it: a synthetic HBJSON fixture, not a SketchUp export.
Pinned PHX 1.57.5, honeybee-ph 1.33.65. In `_private/host/sd07-20261119/preview/`:

- `reference-model.hbjson`: 1 Room, 18 orphaned Shades in five components (Fin 2, Louvre 6, Neighbour 6,
  Shading 3, Zone A Shading 1), one holed, one Variant.
- `reference-model-wufi.xml`: five shading `Component` blocks by name.
- `reference-model-metr.json`: the same five, `idIC` -1.

They are for an early look in WUFI-Passive and METr. The authoritative files come from the host export in SD07
(batch recipe, Part C). The fixture's geometry differs from the host build's: the "Shading" component is
40 m² here and about 5 m² on the host build, so areas do not compare between them.

## Host part, as planned

The PRD's acceptance shape from a fresh process: tag from the right-click menu, Undo and Redo, a second
Model, save and reopen, Colour-by, export, reload, PHX conversion, then Ed opens both files. The run order,
controls and full-screen steps are in the private batch recipe, `_private/host/batch-20261119/RECIPE.md`.

## Host part, 2026-11-20

`main` at `906a102c`, installed RBZ, SketchUp 26.1.188, panel closed. Fixture: the reference model built by
`SD06.setup` in a fresh copy of the blank template, nothing tagged, opened in a fresh process. Run folder
`_private/host/sd07-20261119/SD07/` (not tracked).

| Step | Gesture | Result |
| --- | --- | --- |
| 1 | Right-click three root Faces (two loose, one holed) > PH-Composer > Set as Shading | "Tagged 3 entities as shading."; Shading 3 |
| 2 | Right-click the closed Group Neighbour > Set as Shading | Neighbour 6 |
| 3 | Right-click the three Louvre placements > Set as Shading | Louvre 6 |
| 4 | Inside Zone A, right-click the overhang Face and the Fin Group > Set as Shading | Zone A Shading 1, Fin 2; no blocking finding |
| 5 | Edit > Undo (Close, then Set as Shading), then Redo twice | Step 4's marks off, then back |
| 6 | File > New; Colour by > Shading in it | No marks, empty legend; the first Model's mode stayed off |
| 7 | File > Close on the second Model | No prompt; the first Model's revision unchanged |
| 8 | Colour by > Shading in the reference Model | 18 occurrences in five rows; window shot |
| 9 | Right-click a Louvre placement | Clear Shading only |
| 10 | Save, quit, fresh launch of the saved file | Same five components; Colour by > Shading again shows 18 |
| 11 | Export from the reopened Model | `export.complete`; 18 detached Shades, one with its hole, 1 Room |
| 12 | Pinned PHX (`phx` 1.57.5, `honeybee-ph` 1.33.65) | Five shading components in WUFI XML and METr JSON, `InnerAttachment` -1, `idIC` -1, areas match |

Files for Ed's check, converted from the step 11 export:
`_private/host/batch-20261119/ed-files/sd07/sd07-reopened-wufi.xml` and
`_private/host/batch-20261119/ed-files/sd07/sd07-reopened-metr.json`.

## Ed's check in METr, 2026-11-20

Ed opened `sd07-reopened-metr.json` in METr v.1.98/2.75 and reported "looks ok in METr" with a screenshot
(`_private/host/sd07-20261119/SD07/ed/metr-check.webp`). The five shading components appear under Remaining
elements as C.1 Louvre, C.2 Neighbour, C.3 Zone A Shading, C.4 Shading and C.5 Fin; Shading reads Type Opaque,
Inner side and Outer side Outer air; the 3D view draws the holed Face with its hole. METr's two errors (interior
conditioned floor area and net volume below range) come from the reference model's 5 x 5 x 3 m test Zone, not
from shading.

## Ed's check in WUFI-Passive, 2026-11-20

Ed opened `sd07-reopened-wufi.xml` in WUFI-Passive V.3.6.0.1 and reported "WUFI looks right"
(`_private/host/sd07-20261119/SD07/ed/wufi-check.txt`). His screenshot (`ed/wufi-check.webp`) shows the five
components under Remaining elements (Louvre, Neighbour, Zone A Shading, Shading, Fin) and the holed Face drawn
as one polygon cut along a diagonal to its hole. He then answered the research note's three open questions
([research note](../research/honeybee-ph-and-phx-shading.md#answered-by-ed-in-wufi-passive-2026-11-20)).

## Ledger row

SD07 `pass` on `906a102c`, ten assertions, the last two Ed's checks of the WUFI XML and the METr JSON, in
`planning/native-acceptance/results.jsonl` (evidence path recorded under the packet's former location,
`planning/features/phase-05-shading/`, and mapped in `planning/native-acceptance/evidence-locations.json`).
