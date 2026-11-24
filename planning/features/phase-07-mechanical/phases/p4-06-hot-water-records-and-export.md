# P4-06: Hot Water System, Heater and Tank records and export

DATE: 2026-10-21
STATUS: Scoped. Re-bound 2026-11-23 to D4-17 to D4-20, D4-23, D4-25 and D4-31: Systems, Heaters and Tanks are three flat catalog kinds; recirculation temperature and hours are read-only from piping (not stored on System); PHX round trip included; host gate runs in the MS2 sitting after P4-07.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-03 and D4-01, D4-06, D4-07, D4-12, D4-17 to D4-20, D4-23 and D4-25, with hot water H2 to H6. Owns family 2 as data: the three flat kinds (`hot_water_system`, `hot_water_heater`, `hot_water_tank`), their operations, the Serves slot (`hot_water_system_id`), the pure slotting rule, the hot water export section, conformance and the PHX round trip. Panel closed. Can run beside P4-04 and P4-05 after P4-03; serialise its `composition.py` edit with P4-04's.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "Family 2", and [DECISIONS, Part 3](../DECISIONS.md#part-3-wireframe-review-2026-11-15). Names: [CONTRACTS](../CONTRACTS.md) sections 2, 3 and 6. Pattern: P4-02's catalog kinds and P4-04's section.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The three kinds (D4-17, D4-18, D4-19, D4-20).** `hot_water/systems.rb`, `heaters.rb`, `tanks.rb`:
   - `ph_composer.mechanical.hot_water_system` (`hws`): `Fields.common`, `manufacturer`, `model`, `number_tap_points` (int >= 0 or null), `piping_calc_method` (int 1..4 or null, D4-12). No `recirc_temp_c` or `recirc_hours` (F17, D4-18).
   - `ph_composer.mechanical.hot_water_heater` (`hwh`): `Fields.common`, `manufacturer`, `model`, `hot_water_system_id` (declared `one` ref to `hot_water_system`), `variant` (`electric`, `heat_pump_annual`, `heat_pump_monthly`, `heat_pump_inside`), `percent_coverage` (0..1, default 1.0), `in_conditioned_space`, and only the active variant's efficiency fields (D4-19).
   - `ph_composer.mechanical.hot_water_tank` (`hwt`): `Fields.common`, `manufacturer`, `model`, `hot_water_system_id` (declared `one` ref to `hot_water_system`), `role` (`storage`, `buffer`, `solar`; D4-07), `tank_type`, `quantity`, `in_conditioned_space`, `solar_connection`, `solar_losses_w`, `storage_loss_rate_w_k` (W/K, honeybee-ph's `storage_loss_rate`), `storage_capacity_l`, `standby_losses_w_k`, `standby_fraction`, `room_temp_c`, `water_temp_c`. P4-01 confirmed the units at 1.33.68: `solar_losses` in W, `storage_loss_rate` in W/K ([CONTRACTS section 8](../CONTRACTS.md#8-what-p4-01-found)).
2. **Slotting (D4-07, F35).** `hot_water/slotting.rb`, pure: per System, slots its Tank records into `tank_1`, `tank_2`, `tank_buffer`, `tank_solar` by role and stable order; overflow tanks raise `mechanical.tank_unslotted`. One pure function shared by reads, preflight and export extraction.
3. **Operations and declarations.** CRUD (`all`, snapshot section, `create`, `update`, `duplicate`, `delete`) for all three kinds. Deleting a System checks `reference.in_use` across both Serves payloads and referencing Heaters and Tanks (with replacement support, D4-05). Serves payload gains `hot_water_system_id` (`one` ref, moving payload `schema_version` per F34; hot water H6 applies V1/V5 rules: `mechanical.slot_filled`, `mechanical.zone_no_hot_water`). `hot_water_systems.all` exposes read-only recirculation (null/defaults until P4-13 piping contributes it) and the per-Segment pooling note (`mechanical.hot_water_pooled`, D4-17, D4-23). API minor bump, `API::CHANGES` row and agent guide recipe.
4. **Section and PHX round trip (D4-25).** `HotWaterSection` in `mechanical_sections.py`: one `PhHotWaterSystem` per (system, served Zone) pair (D4-01), tanks set on their slots as `PhHvacHotWaterTank`, heaters through `add_heater` by variant class, `number_tap_points` set; `recirc_temp`/`recirc_hours` left to honeybee-ph's read-only piping properties (F17, D4-18); `piping_calc_method` written only when the loaded class accepts it, otherwise `mechanical.method_not_exported` (D4-12); `required_for_export = True`; `attach` calls `set_hot_water_system`. Findings: `mechanical.hot_water_pooled` when > 1 served System exists in one Building Segment, and `mechanical.item_across_segments` when one System serves Zones in two Segments (D4-23). Add `tests/python/test_hot_water_phx_round_trip.py` in the `phx` test group proving two Rooms of one Segment served by one System yield its tanks and heaters once.
5. **Metadata (F36).** All three kinds carry `user_data` maps, read/written through the guarded route, carried to HBJSON or noted `export.metadata_omitted`, with rows in `docs/USER_DATA.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/mechanical/ventilators/`, `export.rb`, `mechanical_sections.py` (P4-02, P4-04) | The sibling family's shape |
| honeybee-ph `honeybee_phhvac/hot_water_system.py`, `hot_water_devices.py` (pinned 1.33.68) | The carrier; `PhHvacHotWaterHeaterBuilder` for the variant classes |

## Tests (write first)

1. Schema round trip for System, Heater and Tank; a Heater with another variant's field refuses (D4-19); a Heater or Tank referencing a missing System refuses.
2. Deleting a System referenced by Zones, Heaters or Tanks refuses `reference.in_use`; delete with `replacement_id` retargets all referrers in one Undo step.
3. Slotting on the reference system (T1 -> `tank_1`, T2 -> `tank_2`, T3 -> `tank_buffer`); a fourth storage tank and a second buffer raise `mechanical.tank_unslotted`; empty list gives four empty slots.
4. The section builds slots and heaters; two Rooms served by one System carry one identifier; `conformance` reads back capacity and identifier per slot, and refuses when two Rooms' systems under one identifier were translated unequal (each row's digest, CONTRACTS section 6); PHX round trip finds tanks and heaters once per Segment.
5. `piping_calc_method` set: no field in the dict on the pinned wheel and `mechanical.method_not_exported`; a stub class with the attribute receives it.
6. Two served Systems in one Building Segment raise `mechanical.hot_water_pooled`; an unserved System raises `mechanical.item_unserved` only; one System serving two Segments raises `mechanical.item_across_segments`.
7. The Serves slot: assign, replace, clear, delete with replacement for a Hot Water System.

## Host gate

Batched into the `MS2` sitting after P4-07 (D4-31). Offline `make ci` and PHX round trip pass on this stage's PR.

## Out of scope

The Hot water view (P4-07). Piping into the system (P4-13). The simplified methods' export.

## Done when

- M06 has evidence in `../evidence/p4-06-hot-water-records.md`.
- `make ci` passes on both Rubies; the vendor manifest is refreshed.
