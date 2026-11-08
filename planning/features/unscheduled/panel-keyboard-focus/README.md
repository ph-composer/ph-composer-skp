# Panel keyboard focus and announcements

DATE: 2026-10-03
STATUS: Requested. Carried from the archived UI and UX refinement packet; none reproduced under a
test yet.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The [UI and UX refinement](../../../archive/ui-ux-refinement/STATUS.md) pass noted places where
keyboard focus falls to the page after an action, and two where a screen reader is told nothing.
A pointer user sees no fault in any of them. They are gathered here because most share one cause:
a surface that rebuilds its markup on every repaint and so drops the focused element.

| ID | Where | What happens |
| --- | --- | --- |
| K1 | Export header | It is rebuilt on every repaint, so Choose destination and Cancel export lose focus |
| K2 | Assembly Builder | The work surface is rebuilt on every repaint, so focus falls to the page after any toolbar action |
| K3 | Window Types, anchor bubble | After an anchor choice re-arms a placing tool, focus falls to the page |
| K4 | Assemblies, "+ New Assembly" | After a refused New Assembly, focus is not returned to the button |
| K5 | Zones / Geometry, "Show all" | Focus drops to the page |
| K6 | Inventory sort toggle | The state change is not announced to a screen reader |
| K7 | Library | A surface that is not a kit `Inventory` shows, and so announces, no count |

Next step: decide whether K1 and K2 are fixed in the kit (a repaint that keeps or restores the
focused control) or per surface. A kit-level answer likely closes K3 to K5 as well. Load the
ui-polish and architecture-review skills before designing it.
