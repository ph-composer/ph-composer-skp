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

The target is met at the median, not on every repaint.

## Host check of the legend repaint and the Classify message (`63730e18`)

Run by the conductor on the RBZ installed from PR head `63730e18` (code identical to `a0d8cb7e`), fixture a
fresh copy of SD02's reference model with `SD05.tag_reference` applied. No full-screen hold was granted, so it
ran under background control: menus through System Events, viewport clicks by background click, the status
bar and the HUD read from window captures. Read-backs under `_private/host/shading-followups/HC/` (not
tracked).

| Check | How | Result |
| --- | --- | --- |
| Legend in SI | Colour by > Shading from the menu | HUD areas in m² |
| Units to IP | `Preferences.set("unit_system", "IP")` by bridge, the call the panel makes; the panel itself was not clicked | HUD showed ft² (12.92, 893.4, 53.82, 64.58, 53.82) on the next window capture with no viewport interaction; `rebuilds` stayed 1 |
| Units back to SI | Same, by bridge | m² at once; `rebuilds` 1 |
| Reset display preferences | Not run here; see the full-screen check below | |
| Tagged overhang inside Zone A | Zone A open, Set Face Type > Wall from the menu, background click | Status bar "That Face is not part of the Zone's envelope. Nothing was written."; revision unchanged, no Face record |
| Loose untagged Face | Zone A closed, background click | "That Face is in no Zone. Make it a Zone first, then classify its Faces." |
| Ordinary Zone Face | Set Face Type > Floor, click the roof | Floor 2 / Wall 4; Edit reads "Undo Classify Faces"; one Undo restored RoofCeiling 1 (revision 12 to 13) |
| Hover tooltips | Not captured here; see the full-screen check below | |

## Full-screen check of the remaining rows (`e25886b6`)

Run by the conductor under a full-screen hold Ed granted on 2026-11-20, on the RBZ installed from PR #536's head
`e25886b6` (code identical to `a0d8cb7e`), fixture a fresh copy of SD02's reference model with
`SD05.tag_reference` applied. Read-backs and window captures under `_private/host/shading-followups/HC2/` (not
tracked).

| Check | How | Result |
| --- | --- | --- |
| Tooltip, ordinary Zone Face | Classify tool with Wall, pointer moved onto a Zone A wall | "Zone A: Wall, Outdoors suggested" drawn by the pointer (the control: tooltips do show in a capture) |
| Tooltip, tagged overhang inside Zone A | The tool's own `onMouseMove` called by bridge at the overhang's screen point, because synthetic pointer moves reached SketchUp only intermittently; SketchUp's pick at that point returns the overhang alone | Tooltip "That Face is not part of the Zone's envelope."; the hover highlight cleared; no Face record |
| Tooltip, loose Face in no Zone | Same route, Zone A closed, pointer point on the `spare` Face | Tooltip "That Face is in no Zone. Make it a Zone first, then classify its Faces." |
| Units to IP from the panel | The panel's own IP toggle, clicked natively, with the legend uncovered | HUD showed ft² at once with no viewport interaction |
| Reset display preferences | Help & Diagnostics > More actions > Reset display preferences, confirmed | HUD back to m² at once, panel back to SI, Colour-by mode still Shading; `rebuilds` 5 before and after |

Every row this note left open now has a host result. The tooltip rows drove the tool's own handler rather than a
live pointer, which is the remaining gap between this check and a person moving the mouse.

