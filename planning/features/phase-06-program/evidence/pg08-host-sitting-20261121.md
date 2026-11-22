# PG08: Dwellings and Single dwelling, host sitting

DATE: 2026-11-21
STATUS: Ten rows pass on the installed RBZ. The Segment heading tags and findings in the views are still owed (Ed at the mouse or background control).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the second part of the Phase 4a batched host sitting, on branch `acceptance/phase-06-sitting` at `08a06474`,
with no computer-use card. The development bridge drove the rows and read them back, and System Events pressed the
native Edit-menu items (Undo, Redo, Copy, Paste In Place). Raw logs stay in
`_private/host/phase06-sitting-20261121/PG08/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the two-Segment reference, sha256 `70e5bd6ea735df29a9f007bf516a976660833a57582067a4e09c9fa9511578eb`, the only document in a fresh process |
| Reference | House is the house reference: five Zones with Spaces, 82.14 m2 of Space floor. ADU (two Zones) is a second residential Segment. The Apartments reference was not used in this case |
| Hand values | People, lighting and ventilation were computed from the drawn Space outlines and the Phius rules (occupants = bedrooms + units; honeybee-ph's interior lighting rule; 0.4 ACH over 2.5 m Spaces), not taken from a product read |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG08/house-single-dwelling-read | Pass | With no payload stored, House reads as a single dwelling. Its Zones read the House dwelling, and no Dwelling record exists |
| PG08/house-derivations | Pass | After the Segment settings Save with 3 bedrooms, House reads 4 occupants by the rule. Every Zone's floor area, people, lighting and ventilation match the hand values |
| PG08/single-dwelling-off | Pass | One Save makes the House Dwelling (3 bedrooms of its own), and all five Zones join it on the residential default. Native Undo and Redo each restore their state exactly |
| PG08/single-dwelling-on | Pass | One Save deletes the Dwelling and clears the Zones. Native Undo and Redo each restore their state exactly |
| PG08/assign-dwelling | Pass | `assign_dwelling` with choice each gives Bedroom 1 and Bedroom 2 a Dwelling apiece in one step, undone and redone natively |
| PG08/set-counts | Pass | `set_counts` writes in one step, undone and redone natively |
| PG08/assign-program | Pass | `assign_program` puts Bath on Office in one step. Native Undo returns it to the residential default, and Redo restores Office |
| PG08/dwelling-across-segments-refused | Pass | A shared Dwelling across House and ADU, and a House Zone moved into the ADU Dwelling, both refuse `programs.dwelling_across_segments` and write nothing; the revision is unchanged |
| PG08/zone-copy-keeps-dwelling | Pass | Edit > Copy and Paste In Place copy Bedroom 1. The copy takes an id of its own and keeps the original's Dwelling and counts. Native Undo of the paste restores the state before it exactly, and Redo restores the copy |
| PG08/adu-derivations | Pass | With the ADU Dwelling summing its Zones' bedrooms (0 + 1, 2 occupants by the rule), both Zones match the hand values |
| PG08/panel-segment-headings | Owed | The Single dwelling tag, the Segment heading findings and the Occupancy section in the dialog were not observed. They need background control or Ed at the mouse |

## Limits

- The Zone copy's selection was set through the bridge as labelled setup; the copy itself used the native Edit menu.
  The pasted Zone took its own id at paste time, so `make_independent` had nothing to do and refused
  `zone.identity_unique`.
- The derivations cover the house reference and a two-Zone Dwelling. The Apartments reference's derivations were
  not rerun in the host (offline evidence covers them).
