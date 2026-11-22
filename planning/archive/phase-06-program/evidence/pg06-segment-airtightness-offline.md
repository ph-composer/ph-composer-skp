# PG06: Building Segment airtightness, offline rows and PHX read-back

DATE: 2026-11-20
STATUS: Offline rows and the PHX read-back pass on the stage branch; the installed-RBZ rows are owed to the batched sitting under case `PG06`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-06 stage, offline: the Ruby suite against the SketchUp stub, the panel tests in Node and the
Python translation with the optional `phx` group on PHX 1.59.1 over honeybee-ph 1.33.68
(`uv run --group phx pytest tests/python`). SketchUp was not launched: the conductor's brief kept this stage off
the host after two launches reached no bridge.

## The reference

Synthetic (`tests/segment_airtightness_test.rb`): Living (5 × 4 m) and Kitchen (5 × 4 m) in House share an
interior Surface pair; the ADU (4 × 8 m) in ADU has a west wall of two Faces, each paired with a House Zone across
the Segment boundary; every floor is on the Ground, the Kitchen's and the ADU's north walls are Adiabatic, every
Zone is 3 m high and holds one Space whose Floor Segment is the Zone's floor, 2.5 m clear, Living's at a net area
factor of 0.9. House is n50 2.0 with one side exposed,
moderate screening; ADU is q50 0.6 with several sides exposed, high screening. Segment names hold no space.

House tells PHX's area rules apart. Its merged Room keeps 158 m² (each Zone's floor and roof 20, west 12, east
12 to the ADU, Living's south or the Kitchen's Adiabatic north 15) and drops the interior pair; its Outdoors and
Ground area is 119 m², its Spaces 95 m³ (45 and 50). An area that left out the Adiabatic wall (143 m²), kept the interior pair (188 m²) or dropped the
cross-Segment pair (134 m²), or a volume that ignored the net area factor (100 m³), would move the n50 PHX
reports.

## C4a-4

Answered from the pinned PHX and proven by the round trip. q50 needs no area: PHX's q50 is the flow times
(50/4)^0.65 × 3600 (`from_HBJSON/create_variant.py`, flow exponent 0.65, air density 1). n50 is that q50 times
`variant.get_total_gross_envelope_area()` over the Variant's net volume: the gross area of every Face of the
merged Room (`cleanup.merge_rooms`, which drops a Surface Face whose other side is in the same Segment) and the
sum of its honeybee-ph Spaces' net volumes. The `cleanup.py` exposed-area rule (Outdoors and Ground) only weights
`merge_infiltrations`; every Room of a Segment carries one flow, so it returns that flow, and matters only when
it is 0. PH-Composer's own envelope sum is therefore not used: the area is Zones' list of the Faces PHX keeps
(`Zones::Faces::ExportProjection.segment_envelope`).

## Rows

| Assertion | Result | Evidence |
| --- | --- | --- |
| The feature installs with its dependencies | Pass | `ph_composer.programs` requires `ph_composer.zones`, `ph_composer.spaces` and `ph_composer.certification`; listed in `extension.rb` (`test_the_feature_requires_zones_spaces_and_certification_and_writes_the_choices`; `loader_test.rb`, `example_foundation_test.rb`, the host helper test) |
| The Airtightness section round trips | Pass | `ph_composer.programs.airtightness.get` reads the defaults (n50, null, several sides exposed with no screening) with `stored` false, then the saved values with `understood`; a save is one operation and two Undos restore the defaults; a blank result saves as null; a value of 0, -1.5 or "2", an unknown basis or wind exposure, a missing `value` or an extra field refuses `validation.failed` and writes nothing; a Segment's settings go with it on delete and Undo restores them |
| Conversion against the PHX formula, both bases | Pass | `test_the_conversion_inverts_phxs_for_both_bases`: q50 0.6 and n50 2.0 over 158 m² and 95 m³ each come back through PHX's formula, written out independently in the test, within 1e-12 |
| The section | Pass | `tests/airtightness_section_panel_test.js`, 3 tests: Ruby's bases, wind exposures and defaults (`tests/fixtures/segments/airtightness_choices.json`); listed after General; the defaults on a Segment with none, the stored values on one with settings; the unit follows the basis; one change sends the three values in the one `save_segment_settings` request, a typed " 1.5 " as 1.5 and a blank as null; an untouched section sends nothing; 0, -1, "tight", "1,5" and "0x10" hold Save with the reason |
| An n50 and a q50 Segment each read back from the WUFI XML and METr JSON within 0.01 | Pass, with a departure | `tests/python/test_airtightness_phx_round_trip.py` on PHX 1.59.1. Neither file carries n50: WUFI writes q50 as `EnvelopeAirtightnessCoefficient` and METr as `tightEnv50` with `n50` NaN. ADU's q50 reads 0.6 from both; House's q50 reads 1.2025 (2.0 × 95 / 158) from both, and PHX's own n50 on the House Variant reads 2.0 (envelope 158.0 m², net volume 95.0 m³). The n50 read back is PHX's Variant, not a file |
| With no test result the Program's Infiltration, or PHX's default, exports | Pass | A Segment with settings and no result writes its Zones' records with a null flow (`test_no_result_writes_the_wind_exposure_alone_and_no_settings_write_no_record`), and each Room's Infiltration equals the one it has without the section: none here, as no Program is assigned yet, so PHX keeps its default (`test_a_segment_with_no_test_result_keeps_the_rooms_own_infiltration`). A Segment with no settings writes no record |
| Wind exposure reaches `BldgSegment` | Pass | Python: each Segment's `BldgSegment.wind_exposure_type` on reload; WUFI XML `BuildingWindExposure` reads House 5 and ADU 3. Every value Ruby offers is accepted by the pinned honeybee-ph enum, and the default is honeybee-ph's own |
| Refusals | Pass | An n50 result on a Segment with no Spaces refuses `airtightness.no_net_volume` naming the Segment, and q50 exports; a result on a Segment with no Outdoors or Ground Face refuses `airtightness.no_exposed_face`. Python withholds the model for a record naming the wrong Segment, an unknown wind exposure or a flow of 0 |
| The installed RBZ: the section in the real dialog, native Undo and Redo, save and reopen, Delete, Export of the reference | Owed | Batched sitting, case `PG06` in the case ledger |

## Limits found

- The section shows q50 in m³/h·m² only, as the PRD and prototype do; with IP units it does not offer cfm50/ft².
  A unit quantity for airflow per area is P4a-07's.
- The two refusals are raised when the extraction runs, not in the export preflight, so the user meets them at
  Export rather than in the preflight list.
- The panel shows no converted value: the prototype has none, and the conversion runs at export.
