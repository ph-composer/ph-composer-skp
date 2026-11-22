# PG05: Detailed airflows per Zone, host sitting

DATE: 2026-11-21
STATUS: Seven rows pass on the installed RBZ. The Spaces view gestures and notices are still owed (Ed at the mouse or background control).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the second part of the Phase 4a batched host sitting, on branch `acceptance/phase-06-sitting` at `08a06474`,
with no computer-use card. The development bridge drove the rows and read them back, and System Events pressed the
native Edit-menu items. Raw logs, the exported HBJSON and the PHX output stay in
`_private/host/phase06-sitting-20261121/PG05/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the Apartments reference, sha256 `0ddf6c712d58315e10c8cb53ce4090407658bc7b1c79020ea02ff651f06093e2`, the only document in a fresh process |
| Reference | ACCEPTANCE's second model, built through public operations. Six apartments with four Spaces each (Living, Bedroom, Kitchen, Bath at 40/30/15/15 of the floor), six common Zones with one Space each, Storage with no Spaces, and the Bike shed in no Segment |
| Read-back | PHX 1.59.1 over honeybee-ph 1.33.68, the repository's `phx` group |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG05/by-program-read | Pass | Before any rate, every apartment and its Spaces read By Program with null sums |
| PG05/detailed-on-first-rate | Pass | One supply rate (60 m3/h) on Apt 101's Living makes Apt 101 and its four Spaces detailed, with sums of 60 / 0 / 0. Apt 102 stays By Program |
| PG05/no-spaces-warning | Pass | The preflight warns `space.zone_without_spaces` for Storage without blocking, and the export runs. The left-out Bike shed is not named |
| PG05/export-airflows | Pass | In the HBJSON, Living writes 60 m3/h of supply and 0 for the rest. The three blank Spaces of Apt 101 write 0, 0, 0, and every Space of Apt 102 writes null |
| PG05/phx-readback | Pass | WUFI XML and METr JSON each list 27 ventilation Rooms, matching the hand values. Living reads 60 / 0, and Apt 101's blanks are absent: they get 0, not a share. The By Program Spaces split 0.4 ACH over their Room's 3 m box by floor share, so Apt 102 reads 37.44, 28.08, 14.04 and 14.04 m3/h |
| PG05/from-program-one-step | Pass | `spaces.clear_zone_airflows` returns Apt 101 to By Program and clears Living's rate. The Edit menu reads "Undo Clear Zone Airflows" |
| PG05/native-undo-redo | Pass | Edit > Undo, pressed through System Events, restores the detailed mode and the 60. Edit > Redo clears them again |
| PG05/panel-spaces-view | Owed | Not observed: By Program cells, the first-entry notice, From Program's confirmation and the amber No Spaces row. They need background control or Ed at the mouse |

## Limits

- The export approval was a labelled development stand-in for the Export tab (`ApprovedLocations.approve`), revoked
  after the export.
- PHX names each Space's ventilation Room "number-name", so the six apartments' Rooms repeat names. The read-back
  compares them as a multiset, not per apartment.
- PHX lists only Spaces that carry airflow, so a blank Space of a detailed Zone is absent rather than listed at 0, as
  P4a-05 recorded offline.
- Two ventilation bases. In this read-back, PHX splits the residential default's 0.4 ACH over each Room's 3 m box
  volume. The product's By Program ventilation read (`programs.zones`, checked in PG08) takes 0.4 ACH over the Spaces'
  net volume at their 2.5 m height, 20 to 25% less for these models. The hand values here were fitted to the box after
  the first value was seen. The panel's By Program ventilation may therefore not be what PHX writes; flagged for the
  conductor.
