# P4-04: Ventilator export

DATE: 2026-10-21
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4-03, D4-01, D4-06 and D4-09. `composition.py` and `assembly.py` are shared with Phase
3b's P3b-08: not open on both branches at once; this stage appends one section and changes
`assembly.py` only if P4-01's tests require it. Owns the export contributor, its preflight, the Python ventilation
section, its result fields and conformance, and the HBJSON half of B4's proof. After this stage
Ventilators are complete as data and exported: milestone MS1.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Export" and "Family 1", and
"Acceptance shape". Names: [CONTRACTS](../CONTRACTS.md) section 6. Pattern: Spaces'
`features/spaces/export.rb` and `space_sections.py`, the shipped Room-attaching section.

Paths are relative to `src/ph_composer/`.

## Steps

1. **Contributor.** `features/equipment/export.rb`: `feature.export_contributor` for
   `ph_composer.equipment.export.ventilation`, `requires: ["ph_composer.zones.export.zones"]`,
   projecting one row per (Ventilator, served Zone) pair from the snapshot and the Serves records,
   leaving out unserved items and Zones the Zone section omits, each with its own finding. Declare
   the `result` fields through `Export::Privacy` and the report callback.
2. **Preflight.** `equipment.preflight` query: every finding of CONTRACTS section 6 this stage
   raises, with where it is and its repair.
3. **Section.** `python/ph_composer_translation/equipment_sections.py` and
   `contract/equipment_records.py`: `VentilationSection`, `requires` the Zone section,
   `attaches = Attachment(ROOM, key: zone_id)`, `required_for_export = True` (D4-06). `translate`
   builds a `PhVentilationSystem` with `sys_type` 1 holding a `Ventilator` with the record's
   values, identifiers derived from the item id so every served Room carries the same (D4-01);
   objects stay mutable and keyed by (item, Zone) so a later section may add ducting before attach
   (D4-09). `attach` calls `set_ventilation_system`. `result_fields`: one row per pair.
   `conformance`: each reloaded Room's `ph_hvac.ventilation_system.ventilation_unit` matches its
   row and one item carries one identifier across Rooms. Add the section to `composition.py`.
4. **Fixture.** `tests/fixtures/equipment/` pins the extraction contract both sides read.
5. **Report.** The Export report gains an "Equipment: Ventilators" table: item, served Zones,
   quantity, efficiencies; unserved items listed in one line.
6. **Agent guide.** The recipe gains the export read-back.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/spaces/export.rb`, `python/ph_composer_translation/space_sections.py`, `contract/space_records.py` | Pattern for contributor, preflight, section, result fields and conformance |
| `tests/python/test_space_sections.py`, `test_room_attachment.py` | Pattern for the section and reload tests |
| honeybee-ph `honeybee_phhvac/ventilation.py`, `properties/room.py` (1.33.65) | The carrier |

## Tests (write first)

1. The contributor projects one row per (item, Zone) pair, none for an unserved item or an
   omitted Zone, with the findings.
2. The section builds a system per row with the record's values and `sys_type` 1; identifiers
   agree across two Rooms served by one item.
3. The assembled Model's two Rooms reload with their units; conformance passes; a tampered
   identifier fails it.
4. A record with a recovery fraction above 1 (planted in the extraction) fails as `RecordError`
   and blocks the pair (D4-06).
5. The privacy allowlist admits only the declared result fields; the metadata guard passes.
6. The report renders the table and the unserved line.

## Host gate

Fresh process, normal packaged RBZ, the reference model in both the base and the shared case:
export, reload the exact HBJSON in the pinned stack and read back both Rooms; omit Zone B and
export again; save, reopen and re-export give the same HBJSON. Record with `acceptance_case.py`.

## Out of scope

The Systems tab (P4-05). Hot water (P4-06). Ducting into the system (P4-14). METr.

## Done when

- M04 has evidence in `../evidence/p4-04-ventilator-export.md`.
- `make ci` passes on both Rubies; the vendor manifest is refreshed; fixtures regenerate with
  no unrelated diff.
