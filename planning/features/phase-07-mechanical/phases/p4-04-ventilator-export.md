# P4-04: Ventilator export

DATE: 2026-10-21
STATUS: In review 2026-11-24 on `feat/phase-07-mechanical-p4-04` (#567); offline evidence in [p4-04-ventilator-export](../evidence/p4-04-ventilator-export.md), host case `M04` owed to MS1. Corrected 2026-11-22 after Phase 6 Programs: the left-out Zone rule, the pinned wheel. A PHX round trip added the same day (D4-25). See [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-03, D4-01, D4-06 and D4-09. This stage appends one section to `composition.py` and
changes `assembly.py` only if P4-01's tests require it. Owns the export contributor, its preflight, the Python ventilation
section, its result fields and conformance, and the HBJSON half of B4's proof. After this stage
Ventilators are complete as data and exported: milestone MS1.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Export" and "Family 1", and
"Acceptance shape". Names: [CONTRACTS](../CONTRACTS.md) section 6. Pattern: Spaces'
`features/spaces/export.rb` and `space_sections.py`, the shipped Room-attaching section.

Paths are relative to `src/ph_composer/`.

## Steps

1. **Contributor.** `features/mechanical/export.rb`: `feature.export_contributor` for
   `ph_composer.mechanical.export.ventilation`, `requires: ["ph_composer.zones.export.zones"]`,
   and `entity_projections` claiming `ph_composer.mechanical.zone_serves` on the Zone record
   (D4-21, as Programs claims its assignment); the same change moves that extension from
   `local_only` to `required`, so no commit holds a required namespace without its claim, projecting one row per (Ventilator, served Zone)
   pair from the Ventilator records and the claimed Serves payloads,
   leaving out unserved items and Zones in no Building Segment (the Zones projection's
   `exported`, F28), each with its own finding. The rows are one pure plan the preflight also
   reads (F35). Declare
   the `result` fields through `Export::Privacy` and the report callback.
2. **Preflight.** `mechanical.preflight` query: every finding of CONTRACTS section 6 this stage
   raises, with where it is and its repair.
3. **Section.** `python/ph_composer_translation/mechanical_sections.py` and
   `contract/mechanical_records.py`: `VentilationSection`, `requires` the Zone section,
   `attaches = Attachment(ROOM, key: zone_id)`, `required_for_export = True` (D4-06). `translate`
   builds a `PhVentilationSystem` with `sys_type` 1 holding a `Ventilator` with the record's
   values, identifiers derived from the item id so every served Room carries the same (D4-01);
   objects stay mutable and keyed by (item, Zone) so a later section may add ducting before attach
   (D4-09). `attach` calls `set_ventilation_system`. `result_fields`: one row per pair.
   `conformance`: each reloaded Room's `ph_hvac.ventilation_system.ventilation_unit` matches its
   row and one item carries one identifier across Rooms. Add the section to `composition.py`.
4. **Fixture.** `tests/fixtures/mechanical/` pins the extraction contract both sides read.
5. **Report.** The Export report gains a "Mechanical: Ventilators" table: item, served Zones,
   quantity, efficiencies; unserved items listed in one line.
6. **Agent guide.** The recipe gains the export read-back.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/spaces/export.rb`, `python/ph_composer_translation/space_sections.py`, `contract/space_records.py` | Pattern for contributor, preflight, section, result fields and conformance |
| `tests/python/test_space_sections.py`, `test_room_attachment.py` | Pattern for the section and reload tests |
| honeybee-ph `honeybee_phhvac/ventilation.py`, `properties/room.py` (pinned 1.33.68; P4-01 re-reads the fields) | The carrier |

## Tests (write first)

1. The contributor projects one row per (item, Zone) pair, none for an unserved item or a
   Zone in no Building Segment, with the findings.
2. The section builds a system per row with the record's values and `sys_type` 1; identifiers
   agree across two Rooms served by one item.
3. The assembled Model's two Rooms reload with their units; conformance passes; a tampered
   identifier fails it.
4. A record with a recovery fraction above 1 (planted in the extraction) fails as `RecordError`
   and blocks the pair (D4-06).
5. The privacy allowlist admits only the declared result fields; the metadata guard passes.
6. The report renders the table and the unserved line.
7. A PHX round trip in the `phx` group, `tests/python/test_ventilation_phx_round_trip.py`,
   skipped without it (D4-25): the base case gives two ventilation devices and the shared case
   one.

## Host gate

Fresh process, normal packaged RBZ, the reference model in both the base and the shared case:
export, reload the exact HBJSON in the pinned stack and read back both Rooms; move Zone B to No
Building Segment and export again; save, reopen and re-export give the same HBJSON. Record with `acceptance_case.py`.

## Out of scope

The Systems tab (P4-05). Hot water (P4-06). Ducting into the system (P4-14). METr.

## Done when

- M04 has evidence in `../evidence/p4-04-ventilator-export.md`.
- `make ci` passes on both Rubies; the vendor manifest is refreshed; fixtures regenerate with
  no unrelated diff.
