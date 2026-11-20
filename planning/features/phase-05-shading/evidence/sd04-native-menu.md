# SD04: Set as Shading and Clear Shading in the native menus

DATE: 2026-11-20
STATUS: Recorded. Host run from the packaged RBZ under one full-screen hold.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Head `906a102c`, SketchUp 26.1.188, panel closed. Run files and menu screenshots under
`_private/host/sd04-20261119/` (not tracked).

| Selection | Right-click PH-Composer submenu |
| --- | --- |
| Two loose Faces | Set as Shading, no Clear Shading |
| Closed Group | Set as Shading only (with Make Zone) |
| A Face inside an open Group inside Zone A | Set as Shading, no Clear Shading |
| An Edge alone | No Shading item |
| The Zone Group | No Shading item |
| A cutting component's Face (stands in for a pane Face; same rule) | No Shading item |
| A marked Face | Clear Shading, no Set as Shading |

Choosing an item writes one Undo step ("Set as Shading", "Clear Shading"); Edit > Undo and Redo reverse and
replay it. The status bar names what was tagged or cleared, what was already shading, what was left out with its
reason and how many other entities were ignored. A selection that changes nothing writes no Undo entry. The
Extensions > PH-Composer items stay enabled for any selection and explain a refusal in the status bar. The
session diagnostics hold no `menu_failed`.
