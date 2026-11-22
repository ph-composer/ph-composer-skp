# PG06: Building Segment airtightness, host sitting

DATE: 2026-11-21
STATUS: Seven rows pass on the installed RBZ. The settings dialog's Airtightness section is still owed (Ed at the mouse or background control).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the Phase 4a batched host sitting on branch `acceptance/phase-06-sitting` at `08a06474`, with no
computer-use card. The rows were driven by the development bridge, and the native menu presses by System Events.
Raw logs, the exported HBJSON and the PHX output stay in `_private/host/phase06-sitting-20261121/PG06/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the blank synthetic template, sha256 `2ae1418dddca85afb7c271896a005d14d814df562a231633631ea3ec57121063`, the only document in a fresh process |
| Reference | The same reference as PG04: three separate 3 m box Zones, Living and Kitchen in House and ADU in ADU, with one Space per Zone at the default 2.5 m height |
| Values | House: n50 2.0, one side exposed, moderate screening. ADU: q50 0.6, several sides exposed, high screening |
| Read-back | PHX 1.59.1 over honeybee-ph 1.33.68, the repository's `phx` group |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG06/dialog-section | Owed | The settings dialog was not opened. It needs background control or Ed at the mouse. The public read on both new Segments returned n50, no result and the default wind exposure, unstored |
| PG06/save-one-step | Pass | `ph_composer.zones.save_segment_settings`, the operation the dialog's Save sends, saved both Segments. Each read back stored and understood, and the Edit menu read "Undo Change Building Segment Settings" |
| PG06/refusal | Pass | Results of 0 and of -1.5 were each refused `validation.failed` by the operation, and the revision did not change. This is the operation's refusal, not the dialog holding Save |
| PG06/native-undo-redo | Pass | Right after the ADU save, Edit > Undo was pressed through System Events. ADU read its defaults again and House kept n50 2.0. Edit > Redo restored q50 0.6 |
| PG06/save-reopen | Pass | Saved, quit and reopened in a fresh process. Both Segments read the same values |
| PG06/delete-names | Pass | Deleting a Segment with airtightness settings reported the `ph_composer.programs.airtightness` namespace in `removed_extensions` |
| PG06/export | Pass | The export completed. Every Zone's Room carries an Infiltration and each `BldgSegment` carries its wind exposure (House 5, ADU 3) |
| PG06/phx-readback | Pass | ADU's q50 reads 0.6 from both the WUFI XML and the METr JSON. House's q50 reads 0.838 from both, which is 2.0 × 78.75 m³ / 188 m². PHX's own House Variant reports n50 2.00, within 0.01 |

## Limits

- Neither file carries n50 (METr writes it as NaN), so n50 is read back from PHX's Variant, as in the offline row.
- The export approval was a labelled development stand-in for the Export tab (`ApprovedLocations.approve`).
- The reference's Zones touch nowhere, so this host run does not exercise PHX's interior-pair area rule. The
  offline row covers it.
