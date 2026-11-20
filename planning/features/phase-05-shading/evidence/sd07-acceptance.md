# SD07: integration acceptance

DATE: 2026-11-20
STATE: Not run on the host. This file holds the offline part; the host part is owed to the batched host pass.

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

## Host part, owed

The PRD's acceptance shape from a fresh process: tag from the right-click menu, Undo and Redo, a second
Model, save and reopen, Colour-by, export, reload, PHX conversion, then Ed opens both files. The run order,
controls and full-screen steps are in the private batch recipe, `_private/host/batch-20261119/RECIPE.md`.
