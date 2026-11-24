# Phase 4 acceptance register: mechanical

DATE: 2026-10-21
STATUS: Scoped. No row has evidence. Re-bound 2026-11-23 to the wireframe decisions (D4-13 to D4-20), Programs review (D4-21 to D4-27) and kickoff review/interviews (D4-28 to D4-37). Host gates are batched by milestone (MS1 after P4-04, MS2 after P4-07, MS3 after P4-14/P4-15; D4-31). M09 to M11, M13, M14 and M16 are filled in when their stage documents are written in full.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

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
| M01 | Shared, P4-01 | CONTRACTS section 7's four questions answered by focused test and recorded in a new section 8, the first being a `many` reference in a payload on a Zone record (D4-21) and the second including its PHX round trip (D4-25); architecture review recorded; `PLANNING_IDS` refuses a planted `P4-01`, `P4-08b`, `M01` and `M16` in `src/`; `honeybee_phhvac` loads through `stack.load` in the installed Pyodide runtime and `Room.properties.ph_hvac` exists after `honeybee_ph` loads | Open: offline evidence recorded ([p4-01-contracts](evidence/p4-01-contracts.md)); host case `M01` owed to MS1 |
| M02 | Mechanical, P4-02 | Schema round trip for the Ventilator; defaults on create (quantity 1, 0.55 Wh/m³, frost protection, -5 °C); the two optional fields absent by default and null-able; a recovery fraction outside 0 to 1 refuses; guarded delete refuses while in use (from P4-03 on, offline in [p4-03-serves](evidence/p4-03-serves.md)); `user_data` and extension payloads survive edit, Duplicate, Undo/Redo and reopen; a panel-closed script creates, edits and duplicates a Ventilator through registered actions only; the layer test holds | Open: offline evidence recorded ([p4-02-ventilator-kind](evidence/p4-02-ventilator-kind.md)); host case `M02` owed to MS1. The delete-in-use clause is P4-03's |
| M03 | Mechanical, P4-03 | Assign and Clear on explicit Zone references, each one Undo step; a second Ventilator on a served Zone refuses `mechanical.slot_filled` and assigns with `replace: true` (V1); a stale `expected_values` refuses the whole command and writes nothing; refusals through a locked Group, a shared definition and a nested Zone path carry Zones' `target.*` codes; a plain delete of an item a Zone names refuses `reference.in_use`; delete with replacement moves every Serves slot, direct and nested, in one Undo step, and Undo restores the item and every slot; delete with explicit null empties the slots; a native copy of a served Zone keeps its items, with no step of this feature in the copy's Undo step (D4-04, D4-21); a Zone whose slots are all empty reads as served by nothing, as a Zone with no payload does; a Serves write leaves Programs' assignment on the same Zone untouched; `mechanical.zone_unventilated` on an unserved Zone and `mechanical.item_unserved` on an unassigned item, neither blocking | Open: offline evidence recorded ([p4-03-serves](evidence/p4-03-serves.md)); host case `M03` owed to MS1 |
| M04 | Mechanical and export, P4-04 | The normal packaged RBZ exports the reference model; the exact HBJSON reloads; Room A's and Room B's `ph_hvac.ventilation_system` each hold a `Ventilator` with the record's values and `sys_type` 1; the shared case gives both Rooms one identifier (D4-01), and through PHX in the `phx` test group the base case gives two ventilation devices and the shared case one (D4-25); an unserved item is absent and disclosed; a served Zone in no Building Segment is left out with `mechanical.zone_left_out` and its Room is absent; a forced translate failure blocks the pair (D4-06); the metadata guard passes; save, reopen and re-export give the same HBJSON | Open: offline evidence recorded ([p4-04-ventilator-export](evidence/p4-04-ventilator-export.md)); host owed MS1 (case `M04`). Save, reopen and re-export are the host case's |
| M05 | Mechanical, UI kit, Colour-by and units, P4-05 | The Mechanical tab on the host (after Thermal Bridges and before Library, D4-27): system subtabs (`Ventilation`, and later sibling subtabs) with the shared pill row (`Ventilators`, and later `Ducting`, D4-13), the Ventilators table with Tag, export fields first and hideable identity columns (`Manufacturer`, `Model`, `Notes`, D4-20), create, in-place edit with stale-value refusal, duplicate, guarded delete and delete with replacement, the Serves column's Zone picker (grouped by Building Segment, F39), the collapsed per-row disclosure for the two optional fields (V3, D4-30), the balance columns reading 60 / 50 imbalanced for ERV-1 and 40 / 40 for ERV-2 and 100 / 90 balanced in the shared case, a served Zone set By Program counted at its Program's flow as both supply and extract, and a dash only while Programs gives no flow (D4-24); electric efficiency shows 0.45 Wh/m³ under SI and its W/cfm value under IP and a draft keeps its unit through a switch; `By ventilator` colours Zone A and Zone B by their item and leaves an unserved Zone uncoloured, with Zone counts in the legend; the Phase 3a Zone views cases the ledger screens are repeated; the UI polish review recorded (verified at MS2 sitting, D4-31) | Open: offline evidence recorded ([p4-05-systems-tab](evidence/p4-05-systems-tab.md)); host owed MS2 (case `M05`) |
| M06 | Mechanical and export, P4-06 | Flat Hot Water System, Heater and Tank records (D4-17) round trip with three tanks and two heaters referencing HWS-1; a heater carrying another variant's field refuses (D4-19); deleting HWS-1 while referenced by Zones, Heaters or Tanks refuses `reference.in_use` and supports replacement; the slotting rule on the reference system gives `tank_1` T1, `tank_2` T2, `tank_buffer` T3, `tank_solar` none; a fourth storage tank raises `mechanical.tank_unslotted` and is omitted without blocking; the exported HBJSON reloads with both Rooms' `ph_hvac.hot_water_system` holding those slots, two heaters, 8 tap points, and honeybee-ph's read-only recirculation defaults (60 °C, 24 h with no piping, F17, D4-18); through PHX in the `phx` test group the two Rooms' one System gives its tanks and heaters once (D4-25); two served Systems in one Building Segment raise `mechanical.hot_water_pooled` (D4-17, D4-23); `piping_calc_method` set gives `mechanical.method_not_exported` and no field in HBJSON on the pinned wheel (D4-12) | Open: offline evidence recorded ([p4-06](evidence/p4-06-hot-water-records.md)); host owed MS2 |
| M07 | Mechanical and UI kit, P4-07 | The Hot Water subtab with three flat pill tables (`Systems`, `Heaters`, `Tanks`, D4-13, D4-17): Systems shows Tag, Serves, tap points, read-only recirculation (from piping, D4-18), calculation method and the Segment pooling note; Heaters shows System picker, Type/variant with only its live efficiency cells active (D4-19), coverage and in-conditioned-space; Tanks shows System picker, Role, Type, expected export slot, capacity (litres under SI, US gallons under IP) and standby losses; hideable Manufacturer/Model/Notes (D4-20); `By hot water system` colours served Zones; the UI polish review recorded (verified at MS2 sitting, D4-31) | Open: offline evidence recorded ([p4-07](evidence/p4-07-hot-water-view.md)); host owed MS2 |
| M08 | Mechanical, P4-08 | Heat Pumps subtab with five pills (`Equipment · Outdoor`, `Equipment · Indoor`, `Units · Outdoor`, `Units · Indoor`, `Blended result`, D4-14, D4-16, D4-28): identity-only Indoor Equipment, paired indoor model on Outdoor Equipment, Serves on Indoor Units (`hp_indoor_unit_ids`, D4-15), pure Ruby blend per Building Segment (`blend.rb`, F35, D4-23) with HSPF/HSPF2 conversion and Climate derating (F20), read-only Blended result view in the Phius estimator's sections with copy action, `mechanical.hp_climate_missing` when Climate is incomplete, `mechanical.hp_unit_unpaired` for unpaired/unserved units, and `mechanical.hp_cooling_over_200kw` info note with no HBJSON split (D4-29, F40); exported HBJSON reloads with one `PhHeatPumpRatedMonthly` (plus `PhHeatPumpCoolingParams_Recirculation`, `min_coil_temp = 12.0 °C`) per Building Segment on every served Room, proved in PHX round trip (D4-25); private comparison test against the Phius workbook skips cleanly when absent (D4-15) | Open |
| M09 | Mechanical, P4-09 | Defined when electric heaters are planned after their interview | Open |
| M10 | Mechanical, P4-10 | Defined when pumps are planned after their interview | Open |
| M11 | Mechanical, P4-11 | Defined when fans are planned after their interview; must cover a kitchen hood exporting as an exhaust ventilator and a linked supportive device (Q6) | Open |
| M12 | Equipment, P4-12 | Superseded 2026-11-14 with its stage: appliances and the Phius default set are Programs' Equipment Sets, accepted there as PG07, PG10 and PG11b ([Phase 6 ACCEPTANCE](../../archive/phase-06-program/ACCEPTANCE.md)) | Superseded |
| M13 | Piping, P4-13 | Defined when hot water piping is planned after its interview; its PRD's acceptance shape is the draft | Open |
| M14 | Ducting, P4-14 | Defined when ERV ducting is planned after its interview; its PRD's acceptance shape is the draft | Open |
| M15 | Integration, P4-15 | Both offline Ruby gates, coverage, browser and runtime checks; packaged inventory and footprint through `vendor.py --check` against its keys: the 28,000,000 byte ceiling and the growth allowance over the baseline Phase 6 reset to 26,093,959 (F37); the PRD's acceptance shape from a fresh process on the reference model with a nested Zone, a copied Zone, two Models, Undo/Redo, save and reopen, and export; the `phx` group's round trips green; every METr file and import row named in metr-export with its owner | Open |
| M16 | Mechanical and export, P4-08b | Defined when the stage is written in full, after the summer ventilation interview. Must cover: mechanical cooling entered as a switch, off by default, and the mechanical room temperature at 20 °C by default (D4-26); the finding when the switch and the blended heat pump's cooling disagree; a PHX round trip reading both values on the Variant (D4-25); the Mechanical section of the Building Segment settings saving in one Undo step with the other sections; the exported HBJSON reloading with each Segment's `set_points.mechanical_cooling`, `mech_room_temp` and `summer_ventilation` as entered and the winter and summer set points Programs wrote unchanged; a Segment with no stored settings reloading with honeybee-ph's defaults | Open |

## Synthetic reference model

Extend the Phase 2 and 3b reference: adjacent boxes, Zone A 5 x 4 x 3 m spanning x 0 to 5 m and
Zone B 4 x 4 x 3 m spanning x 5 to 9 m, both y 0 to 4 m, one Building-Segment. Each Zone holds
one Space with one Volume whose Floor Segment is the whole floor, with the rates below entered, so
both Zones are in Detailed airflows:

| Space | Zone | Supply, m³/h | Extract, m³/h | Transfer, m³/h |
| --- | --- | --- | --- | --- |
| A1 | A | 60 | 50 | 0 |
| B1 | B | 40 | 40 | 0 |

Since Phase 6 the one Building Segment of a new Model is residential with Single dwelling on
(`context/CONTRACTS.md`, "Occupancy"), so this model's export also carries what Programs writes
for its default. That was read from the contract and not exported here. The tables below list
`ph_hvac` only; nothing here asserts or changes what Programs writes.

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

Tap points 8, `piping_calc_method` null; recirculation temperature and hours are read-only from recirculation piping (honeybee-ph defaults 60 °C / 24 h with no piping, F17, D4-18). Tanks (`T1`, `T2`, `T3`) and heaters (`H-E`, `H-HP`) are flat records referencing `HWS-1` (D4-17).

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
| A | `sys_type` 1; `ventilation_unit` with ERV-1's values, identifier derived from ERV-1's id | HWS-1's identifier; `tank_1` T1, `tank_2` T2, `tank_buffer` T3, `tank_solar` None; heaters H-E and H-HP; `number_tap_points` 8; read-only `recirc_temp` 60.0 and `recirc_hours` 24 (no piping yet, D4-18) |
| B | ERV-2's values (base) or the same identifier as Room A's (shared case) | The same identifier and content as Room A's |

Compare identifiers after save, reopen and HBJSON reload; matching counts alone do not prove a
round trip.

### Finding cases

Each is added by its stage's test or host gate, not left in the base fixture, so the base export
stays clean.

| Case | Expected |
| --- | --- |
| Clear ERV-2 from Zone B | `mechanical.zone_unventilated` on B, `mechanical.item_unserved` on ERV-2; export proceeds without a system on Room B |
| Assign ERV-2 to Zone A without `replace` | `mechanical.slot_filled` naming ERV-1; nothing written |
| Delete ERV-1 while it serves A | Refused, naming Zone A; with ERV-2 as replacement, A's slot names ERV-2 in one Undo step |
| Copy Zone B natively | The copy keeps ERV-2 and HWS-1: its Serves payload came with the Zone record (D4-21); `By ventilator` colours both Zones ERV-2's colour |
| Add T4, storage, 150 L | `mechanical.tank_unslotted` on T4; T4 absent from HBJSON; the pair is written |
| Add HWS-2 serving nothing, then assign HWS-2 to B (`replace: true`, hot water H6) | Unserved HWS-2 raises `mechanical.item_unserved` only; once HWS-1 serves A and HWS-2 serves B in the same Building Segment, `mechanical.hot_water_pooled` fires as non-blocking info (D4-17, D4-23) |
| Set `piping_calc_method` 2 on HWS-1 | `mechanical.method_not_exported`; no method field in HBJSON on the pinned wheel, 1.33.68 |
| Move Zone B to No Building Segment | Room B absent; `mechanical.zone_left_out` on ERV-2's and HWS-1's rows for B; no `mechanical.zone_unventilated` or `mechanical.zone_no_hot_water` for B; Room A unchanged |
| Clear Space A1's three rates, so Zone A is By Program | ERV-1's balance reads Zone A's Program flow, the `ventilation_m3h` of its `ph_composer.programs.zones` row, as both supply and extract, not imbalanced (D4-24) |
| Put Zone B in a second Building Segment in the shared case | `mechanical.item_across_segments` on ERV-1 and HWS-1, not blocking; each Segment's Rooms carry the whole item (D4-23) |
| Force the ventilation section's translate to fail for ERV-1 (test seam) | `object.unavailable`, blocking; the pair is not written (D4-06) |

## Agent workflow coverage

Carried from the agent-workflows review on 2026-11-10. Every durable record, child collection and
assignment Phase 4 adds meets the [workflow acceptance matrix](../../archive/agent-workflows-review-2026-11/COVERAGE.md#workflow-acceptance-that-every-future-feature-should-meet):
a client with only the installed connection discovers its schema, enumerates every object with an
empty selection, reads exact references, values and SI units in pages within the reply budget,
previews and applies each supported edit, reads the outcome back and locates it. Exercise
unassigned, unreadable, unavailable-extension, orphaned and copied objects, and add the new
operations to the installed guide. M15's fresh-process run includes one recorded client session
that does this for each new family, as the agent-workflows AW10 case did. This adds evidence to
the rows above; it adds no product scope.

## Completion boundary

M01 to M16 close Phase 4, M12 as superseded. What PHX builds from the HBJSON is in this register
as a round trip per export stage (D4-25): one device or three for a shared item, tanks and heaters
once, and the Spaces walk for exhaust and supportive devices when their stages are planned. The
METr file itself and its import into METr are excluded and stay open in
[metr-export](../unscheduled/metr-export/README.md). The simplified hot water
methods wait on honeybee_ph#135. SketchUp 2023 and Windows remain their own gates.
