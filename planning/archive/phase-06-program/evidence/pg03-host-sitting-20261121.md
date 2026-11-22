# PG03: Building Segment export rules, host sitting

DATE: 2026-11-21
STATUS: Six rows pass on the installed RBZ. The panel's move-out offer and move-back notice are still owed (Ed at the mouse or background control).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the second part of the Phase 4a batched host sitting, on branch `acceptance/phase-06-sitting` at `08a06474`,
with no computer-use card. The development bridge drove the rows and read them back, and System Events pressed the
native Edit-menu items. Raw logs, the exported HBJSON and the PHX output stay in
`_private/host/phase06-sitting-20261121/PG03/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the two-Segment reference, sha256 `70e5bd6ea735df29a9f007bf516a976660833a57582067a4e09c9fa9511578eb`, the only document in a fresh process |
| Reference | ACCEPTANCE's third model, built through public operations (box geometry and floor outlines drawn by Ruby as labelled setup). House holds Living-Kitchen, Bedroom 1, Bedroom 2, Bath, and Hall and stair. ADU holds ADU Living, whose west wall is one Surface pair with Living-Kitchen's east wall (6 x 3 m), and ADU Bed. Every Zone has Spaces, and one roof Edge in Living-Kitchen and one in ADU Living carry a Thermal Bridge Type |
| Read-back | PHX 1.59.1 over honeybee-ph 1.33.68, the repository's `phx` group |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG03/left-out-preflight | Pass | After moving ADU Living out of every Segment, the preflight blocks with `face.partner_left_out` on the House side of the pair, naming Zone ADU Living. It also lists `zone.left_out` (6 Faces), `space.zone_left_out` (1 Space) and `thermal_bridge.zone_left_out` (1 Edge) |
| PG03/attached-zone-one-step | Pass | The offer names both sides of the pair. `create_and_assign` makes one Attached zone, ADU Living, and both Faces become AttachedZone with no adjacency, which clears the blocking row. The Edit menu reads "Undo Create and Assign Attached Zone" |
| PG03/native-undo-redo | Pass | Edit > Undo, pressed through System Events, restores both Surface sides and removes the record, while ADU Living stays out. Edit > Redo restores the Attached zone exactly |
| PG03/export-left-out | Pass | The export completes. The HBJSON has no ADU Living Room, Space or Edge; the name appears only as the Living-Kitchen wall's attached zone. The report names the left-out Zone with its 6 Faces, 1 Space and 1 Edge |
| PG03/phx-readback | Pass | WUFI XML: in the House Variant, ADU Living is an attached zone (KindZone 2, factor 0.95), and the shared wall's OuterAttachment points to it. METr JSON: ADU Living has typeZ 2, and one 18 m2 wall names it |
| PG03/move-back-read | Pass | After ADU Living moves back into ADU, the offer lists no Faces and counts 1 of ADU Living's Faces as already naming the Attached zone. Both Faces stay AttachedZone |
| PG03/panel-offer | Owed | The panel's offer was not driven. It needs background control or Ed at the mouse |
| PG03/panel-move-back-notice | Owed | The panel's notice was not observed. Only its read was checked |

## Limits

- The export approval was a labelled development stand-in for the Export tab (`ApprovedLocations.approve`), as in
  part 1 of the sitting. It was revoked after the export.
- No row checks devices. In the WUFI XML, the House Variant's attached zone ADU Living carries the House's 9 devices as
  well as the House zone, 18 in the Variant. PHX 1.59.1 adds each Room's devices to every zone of the Variant
  (`from_HBJSON/create_variant.py`). Whether WUFI-Passive then counts them twice was not checked.
- METr's attached-zone reduction factor reads 1.0, PHX 1.59.1's schema default, as P4a-03 recorded offline.
- An Edit-menu title read without fronting SketchUp returned the previous step's label. Every label used for a press
  was read with the document window fronted.
