# PG04: Phius certification on Building Segments, host sitting

DATE: 2026-11-21
STATUS: Six rows pass on the installed RBZ. The settings dialog's section is still owed (Ed at the mouse or background control).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the Phase 4a batched host sitting on branch `acceptance/phase-06-sitting` at `08a06474`, with no
computer-use card. The rows were driven by the development bridge, and the native menu presses by System Events.
Raw logs, the exported HBJSON and the PHX output stay in `_private/host/phase06-sitting-20261121/PG04/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the blank synthetic template, sha256 `2ae1418dddca85afb7c271896a005d14d814df562a231633631ea3ec57121063`, the only document in a fresh process |
| Reference | Three separate 3 m box Zones, drawn by Ruby as labelled setup: Living and Kitchen in House, ADU in ADU. Then public operations only: Make Zone, Segments, one Assembly on every Face, one Space per Zone |
| Values | House: residential, Phius 2018 ZERO, other, complete, mixed (category is the default, the other four are not). ADU: non-residential, Phius 2021 ZERO, school, under construction, retrofit (none is a default) |
| Read-back | PHX 1.59.1 over honeybee-ph 1.33.68, the repository's `phx` group |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG04/dialog-section | Owed | The settings dialog was not opened. It needs background control or Ed at the mouse. The public read on both new Segments returned the defaults, unstored |
| PG04/save-one-step | Pass | `ph_composer.zones.save_segment_settings` saved all five values, first on House and then on ADU. This is the operation the dialog's Save sends, here sent through the public API. Each Segment read back stored and understood, and the Edit menu read "Undo Change Building Segment Settings" |
| PG04/native-undo-redo | Pass | Right after the ADU save, Edit > Undo was pressed through System Events. ADU read the defaults again, unstored, and House kept its values. Edit > Redo restored ADU's five values |
| PG04/save-reopen | Pass | Saved, quit and reopened in a fresh process. Both Segments read the same values |
| PG04/delete-merge | Pass | Deleting a Segment with settings reported its certification namespace in `removed_extensions`. Merging a second such Segment into House also reported that Segment's namespace, and House kept its own values |
| PG04/export | Pass | The export completed (`export.complete`). Each `BldgSegment` carries its Segment's five values |
| PG04/phx-readback | Pass | The WUFI XML and the METr JSON each hold two Variants. House reads 1, 6, 6, 3, 3 and ADU reads 2, 8, 5, 2, 2 (category, program, use, status, type) |

## Limits

- The export approval was a labelled development stand-in for the Export tab (`ApprovedLocations.approve`), as in
  the Climate acceptance runs.
- The reference's Zones touch nowhere, so no Surface pair is exercised.
