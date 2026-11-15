# P4-06: Hot Water System records and export

DATE: 2026-10-21
STATUS: Scoped. To be re-planned against D4-17 to D4-19 (2026-11-15): Systems, Heaters and Tanks are three kinds, and recirculation temperature and hours are read from piping. See [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4-03 and D4-01, D4-06, D4-07 and D4-12, with hot water H1 to H6. Owns family 2 as
data: the Hot Water System kind with tanks and heaters as nested children, its operations, the
Serves slot, the system values, the pure slotting rule, the hot water section and its conformance.
Panel closed. Can run beside P4-04 and P4-05 after P4-03; serialise its `composition.py` edit
with P4-04's.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Family 2". Names:
[CONTRACTS](../CONTRACTS.md) sections 2, 3 and 6. Pattern: the Assembly kind's nested layers
(`features/assemblies/assembly/schema.rb`) and P4-04's section.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The kind.** `hot_water/schema.rb`, `tanks.rb`, `heaters.rb`: `ph_composer.equipment.hot_water_system`,
   prefix `hws`, `schema_version` 1, `Fields.common` plus `number_tap_points`, `recirc_temp_c`,
   `recirc_hours`, `piping_calc_method` (nullable, D4-12), `tanks` (TANK with `tnk_` ids, `role`,
   `tank_type` and the fields CONTRACTS lists) and `heaters` (HEATER with `htr_` ids and
   `variant`). `validate` holds the per-variant field rule and unique nested ids. Confirm the
   units of `solar_losses` and `storage_loss_rate` against honeybee-ph's docstrings and correct
   CONTRACTS.
2. **Slotting (D4-07).** `hot_water/slotting.rb`, pure: tanks to `tank_1`, `tank_2`,
   `tank_buffer`, `tank_solar` by role and list order; the rest `equipment.tank_unslotted`. One
   function for the read, the preflight and the section's extraction.
3. **Operations and declarations.** `create`, `update` (whole nested arrays, as Assembly layers),
   `duplicate` (regenerating `tnk_` and `htr_` ids through `propose_duplicate`'s block), `delete`
   with replacement and clear (D4-05); `hot_water_systems.all` and the snapshot section, rows
   carrying each tank's slot. The Serves record gains `hot_water_system_id` (one line; hot water
   H6 applies the V1 and V5 rules: `equipment.slot_filled`, `equipment.zone_no_hot_water`). API
   minor bump and change row; agent guide recipe.
4. **Section.** `HotWaterSection` in `equipment_sections.py`: one `PhHotWaterSystem` per (system,
   served Zone) pair (D4-01), tanks set on their slots as `PhHvacHotWaterTank`, heaters through
   `add_heater` by variant class, `number_tap_points`, `recirc_temp`, `recirc_hours`;
   `piping_calc_method` written only when the loaded class accepts it, otherwise
   `equipment.method_not_exported` (D4-12); `required_for_export = True`; `attach` calls
   `set_hot_water_system`. Findings: `equipment.recirc_disagrees` when two exported systems
   differ (hot water H4). `result_fields` and `conformance` per CONTRACTS section 6. Contributor,
   preflight rows, fixture and report table as P4-04 built them.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/assemblies/assembly/schema.rb`, `assembly/operations.rb` | Pattern for nested children with regenerated ids |
| `features/equipment/ventilators/`, `export.rb`, `equipment_sections.py` (P4-02, P4-04) | The sibling family's shape |
| honeybee-ph `honeybee_phhvac/hot_water_system.py`, `hot_water_devices.py` (1.33.65) | The carrier; `PhHvacHotWaterHeaterBuilder` for the variant classes |

## Tests (write first)

1. Schema round trip with three tanks and two heaters; a heater with another variant's field
   refuses; duplicate `tnk_` ids refuse.
2. Duplicate regenerates nested ids and keeps values.
3. Slotting on the reference system; a fourth storage tank and a second buffer are unslotted;
   an empty list gives four empty slots.
4. The section builds the slots and heaters; two Rooms served by one system carry one identifier;
   conformance reads back capacity and identifier per slot.
5. `piping_calc_method` set: no field in the dict on 1.33.65 and the finding; a stub class with
   the attribute receives it.
6. Two exported systems with different `recirc_temp_c` raise `equipment.recirc_disagrees`; an
   unserved system raises nothing.
7. The Serves slot: assign, replace, clear, delete with replacement for a Hot Water System.

## Host gate

Fresh process: a panel-closed walkthrough authors HWS-1 with its tanks and heaters, assigns it to
A and B, exports, and the exact HBJSON reloads with both Rooms' systems as ACCEPTANCE expects;
Undo/Redo, save, reopen. Record with `acceptance_case.py`.

## Out of scope

The Hot water view (P4-07). Piping into the system (P4-13). The simplified methods' export.

## Done when

- M06 has evidence in `../evidence/p4-06-hot-water-records.md`.
- `make ci` passes on both Rubies; the vendor manifest is refreshed.
