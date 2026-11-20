# PG03: Building Segment export rules, offline rows and PHX round trip

DATE: 2026-11-20
STATUS: Offline rows and the PHX round trip pass on the stage branch; the packaged RBZ export and the panel offer in SketchUp are owed to the batched sitting.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-03 stage, offline: the Ruby suite against the SketchUp stub, the panel tests in Node, and the
Python translation with the optional `phx` group (`uv run --group phx pytest tests/python`). No host.

## Entry checks

| Check | Result |
| --- | --- |
| The pins (C4a-11) | honeybee-ph **1.33.68** and PHX **1.59.1**, both on PyPI. The two honeybee-ph wheels differ only in `load/_ph_equip_types.py`, `load/ph_equipment.py` and `properties/load/equipment.py` (F4a-18: `quantity` defaults to 1, the custom annual types multiply by it, no `PhEquipmentCollection`); nothing in the translation imports them. PHX 1.59.1 needs honeybee-ph 1.33.68 or later. Recorded in `pyproject.toml`, `uv.lock`, `tools/runtime/vendor.py`, the vendored wheel and the runtime manifest |
| Site and Shade round trips on the new pins | `tests/python/test_site_phx_round_trip.py` (2) and `test_shade_phx_round_trip.py` (1) pass |
| Findings read at 1.59.1 (F4a-09, F4a-10, F4a-24 to F4a-28) | The released PHX 1.59.1 wheel's Python files are identical to the local checkout the research read (`diff -rq`, cache and index files aside), and the released honeybee-ph 1.33.68 matches its checkout, so the source-read findings stand on the pins. F4a-28's run was on the same code |
| A Building Segment name with a space | **Reproduced on PHX 1.59.1.** The Board 18 reference with Segments "Main Building" and "Annex", without the test's underscore workaround: `AssertionError: Illegal character " " found in honeybee object identifier`, raised from `PHX/from_HBJSON/cleanup.py` `merge_rooms`, which names the merged Room after the Segment's display name. The PHX issue is its own authorization and was not opened |

## Rows

The reference is synthetic (`tests/segment_export_rules_test.rb`): Living and Kitchen in House; one ADU Zone in
ADU whose west wall is two Faces, one shared with each House Zone; one Space and one assigned Edge in ADU, one
Edge in Living. It departs from ACCEPTANCE's two-Zone ADU so that one Attached zone is named by two Rooms,
which the duplicate question needs.

| Assertion | Result | Evidence |
| --- | --- | --- |
| Export refuses with no Zone in a Segment | Pass | `zone.no_segment` from the preflight and the section (`test_with_no_zone_in_a_building_segment_export_refuses`) |
| A Zone in no Segment is absent with its Faces, Spaces and Edges, and the finding counts them | Pass | No ADU record, Face, Space or run in the extraction; preflight info rows `zone.left_out` ("ADU (8 Faces)"), `space.zone_left_out`, `thermal_bridge.zone_left_out`; the same as report notes. Window Units on its Faces: `window_export_test.rb` |
| An empty Segment is absent with its info line | Pass | `zone.segment_empty` naming ADU, as a preflight row and a note |
| A Surface Face whose partner is left out refuses naming the Face | Pass | `face.partner_left_out` on `fac_L…4` and `fac_K…4`, blocking, naming Zone ADU; the extraction refuses with the Face's id |
| The offer reclassifies those Faces and creates or reuses the Attached zone in one Undo step | Pass offline | `attached_zone.offer` lists both sides of both pairs; `create_and_assign` makes all four AttachedZone, no `adjacency`, one operation; Undo restores both Surface pairs and removes the record; an Attached zone already named ADU is reused through `classify`. Panel: `tests/segment_rows_panel_test.js` (offer, reuse wording, Not now, the queue). In SketchUp: owed |
| Moving back leaves them Attached zone with the Solve notice | Pass offline | The read counts 2 AttachedZone Faces and offers none; the panel notice names Solve adjacencies. In SketchUp: owed |
| A marked Face in a left-out Zone exports as "<Zone> Shading"; a mark above it reaches none of its Faces | Pass | `ADU Shading`; no Shade under the marked Group |
| The Site section's Segment count matches the reloaded Model | Pass | `building_segments` 1, one Segment in the reloaded HBJSON (`test_segment_phx_round_trip.py`) |
| WUFI XML and METr JSON from the pinned PHX, the Attached zone read back | Pass | One Variant, House. WUFI XML: Zones House (`KindZone` 1) and ADU (`KindZone` 2, `KindAttachedZone` 1, `TemperatureReductionFactorUserDefined` 0.95); the wall component facing it has `OuterAttachment` = ADU's `IdentNr`. METr JSON: `lZone` House (`typeZ` 1) and ADU (`typeZ` 2); 24 m² of wall with `idEC` = ADU's id |
| The per-Room duplicate | **Disproved** for the default conversion: `convert_hb_model_to_PhxProject` merges a Segment's Rooms (`cleanup.merge_rooms`) before `create_attached_zones_from_hb_room` runs once on the merged Room, which keys by boundary identifier. One Attached zone named by two Rooms reaches WUFI and METr once |
| The packaged RBZ exports both reference models | Owed | Batched sitting |

## Limits found

- **METr carries no reduction factor.** PHX 1.59.1's METr writer gives every zone `desCondZ.TRedUD` 1.0, its
  schema default (`to_METr_JSON/metr_schemas.py`), so the ADU's 0.95 reaches WUFI-Passive only. A PHX
  follow-up, its own authorization.
- The export writes the Attached zone's name and factor only; its kind stays in the Model, and the zone type is
  "Unheated space", as honeybee-ph's Grasshopper component writes it.
- AttachedZone Faces did not translate before this stage (`_boundary_name` knew only Outdoors, Ground and
  Adiabatic): the stage adds the Faces section's `attached_zone` (section version 2) and the `PhAdditionalZone`
  translation.
