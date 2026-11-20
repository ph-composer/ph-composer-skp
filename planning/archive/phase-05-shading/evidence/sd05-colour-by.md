# SD05: the Shading Colour-by mode on the host

DATE: 2026-11-20
STATUS: Recorded. Host run from the packaged RBZ.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Head `906a102c`, SketchUp 26.1.188, panel closed. Run files and window shots under
`_private/host/sd05-20261119/` (not tracked).

| Assertion | Result |
| --- | --- |
| Mode | Five legend rows (Fin 2, Louvre 6, Neighbour 6, Shading 3, Zone A Shading 1), 18 occurrences, areas in m², matching `shading.list` |
| Nested and repeated | All three Louvre placements, the overhang and Fin in Zone A, Neighbour's nested Face and the holed Face (hole open) are coloured; nothing else is |
| Display units | Switching PH-Composer's display units to IP shows ft² and back to SI shows m², with no rebuild. The HUD takes the new units at the next viewport redraw |
| Hidden tag | A Louvre placement on a hidden tag stops drawing; the legend still counts it |
| Live update | Clear Shading from the right-click menu drops the Shading row from 3 to 2 at once; Undo brings it back |
| Off | The drawing and legend go; nothing is written |
| Repaint at 5,000 Shading Faces | Rebuild median 351 ms, refresh median 30 ms: about 380 ms, over the 200 ms target |

The fixture's Louvre component is named "Louvre#2" from leftover definitions in its build; the reference model
expects "Louvre".

Follow-ups: the rebuild at 5,000 Shading Faces misses the 200 ms target (P5s-05 named the per-Face area
calculation as the first thing to cut); the legend does not redraw the moment the display-units preference changes.
