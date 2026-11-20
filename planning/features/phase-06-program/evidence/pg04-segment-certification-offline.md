# PG04: Phius certification on Building Segments, offline rows and PHX read-back

DATE: 2026-11-20
STATUS: Offline rows and the PHX read-back pass on the stage branch; the installed-RBZ rows are owed to the batched sitting under case `PG04`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-04 stage, offline: the Ruby suite against the SketchUp stub, the panel tests in Node and the
Python translation with the optional `phx` group (`uv run --group phx pytest tests/python`). SketchUp was not
launched: the two previous stages' launches reached no bridge, and diagnosing that needs Ed at the screen.

## The reference

Synthetic (`tests/segment_certification_test.rb`): three separate box Zones, Living and Kitchen in House and
Annex in ADU, every Face classified, none shared, and a third Segment, Spare, that no Zone names. Segment names
hold no space, which PHX 1.59.1's `cleanup.merge_rooms` refuses (P4a-03; it does not touch this round trip
otherwise). House carries residential, Phius 2018 ZERO, other, complete, mixed; ADU non-residential, Phius 2021
ZERO, school, under construction, retrofit. No value on either is a default, because the five defaults are
honeybee-ph's own and a default-valued round trip would pass with no export at all.

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| With a `required` Segment extension present, export still runs (the projection claims it) | Pass | A development namespace `test.note.segment`, `required`, on House and Spare: with its claim the preflight has no blocking row and the extraction carries one row, House, `path` null (`test_a_claimed_required_segment_extension_exports_with_a_null_path_for_named_segments_only`); without a claim both refuse `extension.unavailable` (`test_a_required_segment_extension_with_no_claim_blocks_the_preflight_and_the_export`); a claim on the Segment kind from a feature that does not require Zones refuses registration |
| The section's values round trip | Pass | `ph_composer.certification.segment.get` reads the defaults with `stored` false and `extension_status` null, then the saved values with `understood`; the save is one operation, and Undo restores the defaults; a rename keeps them; a value not offered, a missing field or an extra field refuses `validation.failed` and writes nothing; a stored invalid payload reads the defaults with `extension_status` `invalid`, and a stored null or false envelope with `unsupported` |
| They copy with the Segment | **Open** | No operation copies a Building Segment record. Adopting a copied Zone makes its Segment from the Zone's evidence, which since P4a-02 holds the Segment's values only, so it brings no settings (`features/zones/options/definitions.rb`, `SEGMENT_EVIDENCE`). Nothing to test until a Segment copy exists |
| They go with it on delete, and a merge keeps the survivor's only | Pass | `options.remove` of Spare reports `removed_extensions` with the namespace, and Undo restores the values; `options.merge` of ADU into House reports ADU's namespace and House keeps its own values |
| The section | Pass | `tests/certification_section_panel_test.js`, 5 tests: listed after General with five choices whose values and defaults equal Ruby's (`tests/fixtures/segments/certification_choices.json`); defaults on a Segment with none, the stored values on one with settings; an untouched section sends nothing; one change sends all five in the one `save_segment_settings` request; a stored value the section does not offer is kept, shows no choice and holds Save; a stored payload that is not an object opens the dialog with a notice and sends nothing for it |
| Export writes each to `BldgSegment.phius_certification` | Pass | One record per exported Segment (two, though House holds two Zones), the defaults written for a Segment with none; Spare's settings are not in the extraction; a stored invalid payload on House or on Spare blocks the preflight and the export with `extension.invalid`; legacy Zones write no record. Python: the golden reloads with House's and ADU's five honeybee-ph values on their `BldgSegment`s; a two-Segment model keeps the `Site` the Site section set on both after the `segment` host attaches; every value Ruby offers is accepted by the pinned honeybee-ph enum; a record naming no exported Segment or holding an unknown value withholds the model; conformance refuses a value changed after assembly (`tests/python/test_certification_sections.py`, 5 tests) |
| PHX reads them back into the WUFI XML | Pass | `tests/python/test_certification_phx_round_trip.py` on PHX 1.59.1: two Variants; WUFI XML `BuildingCategory`, `PH_CertificateCriteria`, `OccupancyTypeResidential`, `BuildingStatus`, `BuildingType` read House 1, 6, 6, 3, 3 and ADU 2, 8, 5, 2, 2; METr JSON `bCatResnR`, `certCri`, `typeOccR`, `bStatus`, `tBState` read the same |
| The installed RBZ: the section in the real dialog, native Undo and Redo, save and reopen, Delete and merge, Export of the reference | Owed | Batched sitting, case `PG04` in the case ledger |

## Limits found

- The pinned honeybee-ph `PhiusBuildingCertificationProgram` stops at Phius 2021, so Phius 2024 CORE and ZERO
  cannot be chosen. The section offers the enum's six Phius programs; "Default" and "Italian" are left out.
- A Segment no exported Zone names keeps its settings in the Model, but an unreadable payload on it still
  blocks the export: Zones' section reads every valid Segment through the metadata boundary, as it always has.
