# Phase 4 acceptance register: mechanical

DATE: 2026-10-21
STATUS: Scoped. No row has evidence. M08 to M14 are filled in when their stages are planned after their interviews.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The [equipment PRD](equipment/PRD.md), "Acceptance shape", supplies the per-family case. This
register supplies the closure gates for Phase 4. Record a source-controlled evidence summary per
stage under this folder's `evidence/` with commit, build, fixtures, checks, exact host versions and
remaining limits. Keep SKP files and captures in `_private/`.

Ids use the prefix M. `A`, `E`, `S`, `R`, `T`, `UXR`, `PS`, `DV`, `ZO`, `GH`, `SH`, `UXK`, `HGUI`
and `PTAB` are taken in [`native-acceptance/cases.json`](../../native-acceptance/cases.json) (read
2026-10-21). A case row carries `authority`, `id`, `label`, `mode`, `native_control_required` and
`paths`; record each run with `acceptance_case.py begin` and `finish` so the ledger row is a Pass.

| ID | Owner, stage | Required evidence | State |
| --- | --- | --- | --- |
| M01 | Shared, P4-01 | CONTRACTS section 7's four questions answered by focused test and recorded in a new section 8; architecture review recorded; `PLANNING_IDS` refuses a planted `P4-01` and `M01` in `src/`; `honeybee_phhvac` loads through `stack.load` in the installed Pyodide runtime and `Room.properties.ph_hvac` exists after `honeybee_ph` loads | Open |
| M02 | Equipment, P4-02 | Schema round trip for the Ventilator; defaults on create (quantity 1, 0.55 Wh/m³, frost protection, -5 °C); the two optional fields absent by default and null-able; a recovery fraction outside 0 to 1 refuses; guarded delete refuses while in use (from P4-03 on); `user_data` and extension payloads survive edit, Duplicate, Undo/Redo and reopen; a panel-closed script creates, edits and duplicates a Ventilator through registered actions only; the layer test holds | Open |
| M03 | Equipment, P4-03 | Assign and Clear on explicit Zone references, each one Undo step; a second Ventilator on a served Zone refuses `equipment.slot_filled` and assigns with `replace: true` (V1); a stale `expected_values` refuses the whole command and writes nothing; refusals through a locked Group, a shared definition and a nested Zone path carry Zones' `target.*` codes; delete with replacement rewrites every Serves slot, direct and nested, in one Undo step, and Undo restores the item and every slot; delete with explicit null clears the slots and removes emptied records; a native copy of a served Zone keeps its items with a new `eqa_` id in the copy's Undo step (D4-04); a record whose slots all empty is absent; `equipment.zone_unventilated` on an unserved Zone and `equipment.item_unserved` on an unassigned item, neither blocking | Open |
| M04 | Equipment and export, P4-04 | The normal packaged RBZ exports the reference model; the exact HBJSON reloads; Room A's and Room B's `ph_hvac.ventilation_system` each hold a `Ventilator` with the record's values and `sys_type` 1; the shared case gives both Rooms one identifier (D4-01); an unserved item is absent and disclosed; a Zone omitted from export gets no system and the finding names it; a forced translate failure blocks the pair (D4-06); the metadata guard passes; save, reopen and re-export give the same HBJSON | Open |
| M05 | Equipment, UI kit, Colour-by and units, P4-05 | The Systems tab on the host: the Equipment subtab, the family selector, the Ventilators table with create, in-place edit with stale-value refusal, duplicate, guarded delete and delete with replacement, the Serves column's Zone picker, the two disclosed fields, the balance columns reading 60 / 50 imbalanced for ERV-1 and 40 / 40 for ERV-2 and 100 / 90 balanced in the shared case, a dash while a served Space inherits; electric efficiency shows 0.45 Wh/m³ under SI and its W/cfm value under IP and a draft keeps its unit through a switch; `By ventilator` colours Zone A and Zone B by their item and leaves an unserved Zone uncoloured, with Zone counts in the legend; the Phase 3a Zone views cases the ledger screens are repeated; the UI polish review recorded | Open |
| M06 | Equipment and export, P4-06 | Hot Water System round trip with three tanks and two heaters; a heater carrying another variant's field refuses; Duplicate regenerates `tnk_` and `htr_` ids; the slotting rule on the reference system gives `tank_1` T1, `tank_2` T2, `tank_buffer` T3, `tank_solar` none; a fourth storage tank raises `equipment.tank_unslotted` and is omitted without blocking; the exported HBJSON reloads with both Rooms' `ph_hvac.hot_water_system` holding those slots, two heaters, 8 tap points, 55 °C and 18 h; two systems with different recirculation values raise `equipment.recirc_disagrees`; `piping_calc_method` set gives `equipment.method_not_exported` and no field in HBJSON on the pinned wheel (D4-12); a panel-closed script authors the system | Open |
| M07 | Equipment and UI kit, P4-07 | The Hot water family view: system rows with tank and heater child rows opened by the chevron, Add tank and Add heater on the system row, in-place edits of nested rows with stale-value refusal, the role and type enums, litres under SI and US gallons under IP, the Serves column; `By hot water system` colours served Zones; the UI polish review recorded | Open |
| M08 | Equipment, P4-08 | Defined when heat pumps are planned after their interview | Open |
| M09 | Equipment, P4-09 | Defined when electric heaters are planned after their interview | Open |
| M10 | Equipment, P4-10 | Defined when pumps are planned after their interview | Open |
| M11 | Equipment, P4-11 | Defined when fans are planned after their interview; must cover a kitchen hood exporting as an exhaust ventilator and a linked supportive device (Q6) | Open |
| M12 | Equipment, P4-12 | Defined when appliances are planned after their interview; must cover the Phius default set exporting as Process loads (Q12) | Open |
| M13 | Piping, P4-13 | Defined when hot water piping is planned after its interview and Phase 3b's edge stages; its PRD's acceptance shape is the draft | Open |
| M14 | Ducting, P4-14 | Defined when ERV ducting is planned after its interview; its PRD's acceptance shape is the draft | Open |
| M15 | Integration, P4-15 | Both offline Ruby gates, coverage, browser and runtime checks; packaged inventory and footprint through `vendor.py --check` against its keys and the growth budget D3a-20 set, with the baseline reset at the Phase 3b close recorded; the PRD's acceptance shape from a fresh process on the reference model with a nested Zone, a copied Zone, two Models, Undo/Redo, save and reopen, and export; every METr row named in metr-export with its owner | Open |

## Synthetic reference model

Extend the Phase 2 and 3b reference: adjacent boxes, Zone A 5 x 4 x 3 m spanning x 0 to 5 m and
Zone B 4 x 4 x 3 m spanning x 5 to 9 m, both y 0 to 4 m, one Building-Segment. Each Zone holds
one Space with one Volume whose Floor Segment is the whole floor, with user-specified airflows:

| Space | Zone | Supply, m³/h | Extract, m³/h | Transfer, m³/h |
| --- | --- | --- | --- | --- |
| A1 | A | 60 | 50 | 0 |
| B1 | B | 40 | 40 | 0 |

### Ventilators

| Item | Sensible | Latent | Electric efficiency, Wh/m³ | Frost protection | Defrost, °C | In conditioned space | Quantity | Optional |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ERV-1 | 0.85 | 0.60 | 0.45 | yes | -5 | yes | 1 | none |
| ERV-2 | 0.75 | 0.00 | 0.35 | no | -5 | no | 1 | subsoil efficiency 0.20 |

Base case: ERV-1 serves A, ERV-2 serves B. Shared case (M04, M05): ERV-1 serves A and B, ERV-2
serves nothing.

| Balance | Supply | Extract | Imbalanced (more than 10 percent of the larger) |
| --- | --- | --- | --- |
| ERV-1, base | 60 | 50 | yes: 10 > 6 |
| ERV-2, base | 40 | 40 | no |
| ERV-1, shared | 100 | 90 | no: 10 is not more than 10 |

### Hot Water System HWS-1, serves A and B

Tap points 8, recirculation 55 °C for 18 h, `piping_calc_method` null.

| Tank | Role | Type | Capacity, L | Standby, W/K | Expected slot |
| --- | --- | --- | --- | --- | --- |
| T1 | storage | `2-DHW ONLY` | 300 | 4.0 | `tank_1` |
| T2 | storage | `2-DHW ONLY` | 200 | 3.0 | `tank_2` |
| T3 | buffer | `1-DHW AND HEATING` | 80 | 1.5 | `tank_buffer` |

`tank_solar` stays empty.

| Heater | Variant | Coverage | Fields |
| --- | --- | --- | --- |
| H-E | electric | 0.3 | in conditioned space |
| H-HP | heat_pump_annual | 0.7 | `total_system_perf_ratio` 2.5 |

### Expected HBJSON after reload

| Room | `ph_hvac.ventilation_system` | `ph_hvac.hot_water_system` |
| --- | --- | --- |
| A | `sys_type` 1; `ventilation_unit` with ERV-1's values, identifier derived from ERV-1's id | HWS-1's identifier; `tank_1` T1, `tank_2` T2, `tank_buffer` T3, `tank_solar` None; heaters H-E and H-HP; `number_tap_points` 8; `recirc_temp` 55; `recirc_hours` 18 |
| B | ERV-2's values (base) or the same identifier as Room A's (shared case) | The same identifier and content as Room A's |

Compare identifiers after save, reopen and HBJSON reload; matching counts alone do not prove a
round trip.

### Finding cases

Each is added by its stage's test or host gate, not left in the base fixture, so the base export
stays clean.

| Case | Expected |
| --- | --- |
| Clear ERV-2 from Zone B | `equipment.zone_unventilated` on B, `equipment.item_unserved` on ERV-2; export proceeds without a system on Room B |
| Assign ERV-2 to Zone A without `replace` | `equipment.slot_filled` naming ERV-1; nothing written |
| Delete ERV-1 while it serves A | Refused, naming Zone A; with ERV-2 as replacement, A's slot names ERV-2 in one Undo step |
| Copy Zone B natively | The copy keeps ERV-2 and HWS-1 with a new `eqa_` id; `By ventilator` colours both Zones ERV-2's colour |
| Add T4, storage, 150 L | `equipment.tank_unslotted` on T4; T4 absent from HBJSON; the pair is written |
| Add HWS-2 serving nothing with recirculation 60 °C | No disagreement (unserved systems are not exported); replace HWS-1 on B with HWS-2 (`replace: true`, hot water H6): HWS-1 serves A, HWS-2 serves B, `equipment.recirc_disagrees` on both |
| Set `piping_calc_method` 2 on HWS-1 | `equipment.method_not_exported`; no method field in HBJSON on 1.33.65 |
| Omit Zone B from export | Room B absent; `equipment.zone_omitted` on ERV-2's and HWS-1's rows for B; Room A unchanged |
| Force the ventilation section's translate to fail for ERV-1 (test seam) | `object.unavailable`, blocking; the pair is not written (D4-06) |

## Agent workflow coverage

Carried from the agent-workflows review on 2026-11-10. Every durable record, child collection and
assignment Phase 4 adds meets the [workflow acceptance matrix](../../code-review/agent-workflows-2026-11/COVERAGE.md#workflow-acceptance-that-every-future-feature-should-meet):
a client with only the installed connection discovers its schema, enumerates every object with an
empty selection, reads exact references, values and SI units in pages within the reply budget,
previews and applies each supported edit, reads the outcome back and locates it. Exercise
unassigned, unreadable, unavailable-extension, orphaned and copied objects, and add the new
operations to the installed guide. M15's fresh-process run includes one recorded client session
that does this for each new family, as the agent-workflows AW10 case did. This adds evidence to
the rows above; it adds no product scope.

## Completion boundary

M01 to M15 close Phase 4. Every METr check, including whether PHX writes one device or three for
a shared item and the Spaces-walk consequence for exhaust and supportive devices, is excluded and
stays open in [metr-export](../unscheduled/metr-export/README.md). The simplified hot water
methods wait on honeybee_ph#135. SketchUp 2023 and Windows remain their own gates.
