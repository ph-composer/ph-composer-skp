# Shading follow-ups: Colour-by rebuild at 5,000 Shading Faces

DATE: 2026-11-20
STATUS: Recorded. Bridge-only host measurement, development eval.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: context [#526](https://github.com/ph-composer/ph-composer-skp/issues/526); fix in [#536](https://github.com/ph-composer/ph-composer-skp/pull/536)

SketchUp 26.1.188, Ruby 3.2.2, packaged RBZ installed with `make install` from each head, panel closed. The
fixture is SD05's timing Model: a new Model with its template figure erased, 50 named Groups of 10 Groups of 10
one-metre Faces, the 50 outer Groups tagged through `shading.assign`, the Shading mode on. Run files under
`_private/host/shading-followups/` (not tracked).

## Where the time went (before, `211c3380`)

Medians of five, in ms.

| Piece | ms |
| --- | --- |
| Forced rebuild (`invalidate!(force: true)`) | 322 |
| Projection (`ColourModes.entries`) | 177 |
| of which the walk alone | 30 |
| of which `FaceCapture` area | about 135 |
| `Face#area(transform)` over the same walk, area only | 2 |
| `Drawing#add` over the entries | about 100: Face mesh and loops 32, section planes 23, visibility 16 |
| `view.refresh` | 29 |

`Face#area(transform)` matched the `FaceCapture` area for all 5,000 occurrences within 2.1e-15 m², and under
scaled (2, 3, 1), mirrored, mirrored and scaled, and rotated and scaled transforms; a holed Face agreed with
and without a mirrored scale. Under a singular transform it answers 0, where `FaceCapture` refuses. A Face with a
glued cutting component read 9,600 in² from `Face#area` against 10,000 from its loops, so such a Face keeps the
loop read.

## After (`a0d8cb7e`)

Changes: Shading area from `Face#area(transform)` when nothing is glued to the Face (`Shading::Inventory.area_m2`,
shared with `shading.list`); section planes read once per container instead of once per Face.

Three runs of `SD05.time_repaint(7)`, 21 rebuilds and 21 refreshes:

| Measure | ms |
| --- | --- |
| Rebuild median | 162.9 (range 149.0 to 184.5) |
| Refresh median | 27.0 |
| Median rebuild plus median refresh | 189.9, against the 200 ms target |
| Paired rebuild plus refresh over 200 | 6 of 21 (worst 223.8, a 45 ms refresh) |

Projection median 37.6 ms (walk 29.6). The remaining rebuild cost is the shared Colour-by drawing (Face meshes,
visibility, the hatch and publish), which no further contained change in this PR cut by 10 ms or more.
