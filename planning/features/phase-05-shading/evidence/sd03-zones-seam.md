# SD03: Shading and the Zones seam on the host

DATE: 2026-11-20
STATUS: Recorded. Host run from the packaged RBZ.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Head `906a102c`, SketchUp 26.1.188, panel closed. Run files under `_private/host/sd03-20261119/` (not tracked).

| Assertion | Result |
| --- | --- |
| Envelope exclusion | Tagging the overhang Face and the Fin Group takes Zone A from 9 Faces to 6 and its unclassified findings from 3 to 0 |
| Room closed | Zone A exports 6 Faces; honeybee `check_solid` passes, 75 m³ |
| Zones actions | Classify naming the tagged Face refuses `face.outside_envelope`; Suggest classification and Solve adjacencies change nothing |
| Clearing the mark | The Face returns to Zone A as unclassified, with its finding |
| Classified Face | Refuses the tag with `shading.face_classified`; after Clear classification the tag lands; each step is one native Undo |
| Zone inside a marked Group | Make Zone keeps its 6 Faces; the preflight raises `shading.zone_inside` |
| Classify tool | A click on the tagged Face writes nothing |

The extraction for the Room check left out the Spaces contributor: the fixture carries an orphan Space for SD02's
refusal rows, which blocks a full export and is unrelated to shading.

Follow-up: the Classify tool's status message for a Shading Face inside a Zone reads "That Face is in no Zone.
Make it a Zone first, then classify its Faces." The Face is in a Zone but outside its envelope; the message should
say it is a shading surface.
