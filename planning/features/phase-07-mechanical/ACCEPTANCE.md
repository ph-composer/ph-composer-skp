# Phase 4 acceptance register: mechanical

DATE: 2026-10-21
STATUS: Scoped. No row has evidence. Re-bound 2026-11-23 to the wireframe decisions (D4-13 to D4-20), Programs review (D4-21 to D4-27) and kickoff review/interviews (D4-28 to D4-37). Host gates are batched by milestone (MS1 after P4-04, MS2 after P4-07, MS3 after P4-14/P4-15; D4-31). M16, M09, M10 and M11 were filled in on 2026-11-24 with P4-08b's, P4-09's, P4-10's and P4-11's, M13 the same day as five sub-rows, M13a to M13e, one per P4-13 sub-stage, and M14 the same day as six, M14a to M14f, one per P4-14 sub-stage, with the ERV ducting case.
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
| M08 | Mechanical, P4-08 | Heat Pumps subtab with five pills (`Equipment · Outdoor`, `Equipment · Indoor`, `Units · Outdoor`, `Units · Indoor`, `Blended result`, D4-14, D4-16, D4-28): identity-only Indoor Equipment, paired indoor model on Outdoor Equipment, Serves on Indoor Units (`hp_indoor_unit_ids`, D4-15), pure Ruby blend per Building Segment (`blend.rb`, F35, D4-23) with HSPF/HSPF2 conversion and Climate derating (F20), read-only Blended result view in the Phius estimator's sections with copy action, `mechanical.hp_climate_missing` when Climate is incomplete, `mechanical.hp_unit_unpaired` for unpaired/unserved units, and `mechanical.hp_cooling_over_200kw` info note with no HBJSON split (D4-29, F40); exported HBJSON reloads with one `PhHeatPumpRatedMonthly` (plus `PhHeatPumpCoolingParams_Recirculation`, `min_coil_temp = 12.0 °C`) per Building Segment on every served Room, proved in PHX round trip (D4-25); private comparison test against the Phius workbook skips cleanly when absent (D4-15) | Open: offline evidence recorded ([p4-08](evidence/p4-08-heat-pumps.md)); host owed MS3 |
| M09 | Mechanical and export, P4-09 | The Electric Heater kind (D4-33): Tag, Coverage stored 0.0 to 1.0 and shown 0 to 100%, 100% on create, hideable Manufacturer, Model and Notes (D4-20); a coverage outside 0 to 1 refuses `params.invalid` and writes nothing; create, in-place edit with stale-value refusal, duplicate with `user_data`, guarded delete refusing `reference.in_use` while a Zone names it, delete with a replacement moving every Zone's `heater_ids` (kept once where the list holds it) and with null emptying them, each one Undo step; the `heater_ids` `many` Serves slot (payload schema 4): one heater on Zone A and Zone B and a second on Zone A, Clear taking one out; the Electric Heating subtab with its Heaters pill (D4-13), Coverage edited in percent, the Serves chips and Zone picker, Locate narrowing to `electric_heater_ids`; no finding when two heaters on one Zone sum past 100% (D4-33); `mechanical.item_unserved`, `mechanical.zone_left_out` and `mechanical.item_across_segments` never blocking and `mechanical.item_missing` blocking, the same in the preflight and the export notes; the exported HBJSON reloading with Room A holding two `PhHeatingDirectElectric` and Room B one, each under its heater's id with its Tag, coverage and `user_data`, and `conformance` passing; through PHX in the `phx` test group two `PhxHeaterElectric` devices, each once, with their coverage as `space_heating_percent` (D4-25); the UI polish review recorded; the host case `M09` (create, edit, Serves, delete with replacement, native Undo and Redo, export and reload, save and reopen) in the MS3 sitting (D4-31) | Open: offline evidence recorded ([p4-09](evidence/p4-09-electric-heaters.md)); host owed MS3 (case `M09`) |
| M10 | Mechanical and export, P4-10 | The Pump kind (D4-34): Tag, Type offering the four `device_type` values (heating circulation 4, hot water circulation 6 by default, hot water storage load 7, other 10), Quantity, Power in W (0 on create), Operation in kh a year (8.76), In conditioned space (yes), hideable Manufacturer, Model and Notes (D4-20); the internal heat gain utilization factor (1.0) and usage profile behind a collapsed per-row disclosure, the profile following the type until the user overrides it (D4-34); a value outside its range refuses `params.invalid` and writes nothing; create, in-place edit with stale-value refusal, duplicate with `user_data`, guarded delete refusing `reference.in_use` while a Zone names it, delete with a replacement moving every Zone's `pump_ids` (kept once) and with null emptying them, each one Undo step; the `pump_ids` `many` Serves slot (payload schema 5): one pump on Zone A and Zone B and a second on Zone A, Clear taking one out; the Pumps subtab with its Pumps pill (D4-13), the Serves chips and Zone picker, Locate narrowing to `pump_ids`; `mechanical.zone_without_spaces` on a pump serving an exported Zone no Space names, never blocking, the pair still written (D4-34), from a helper Fans reuse; `mechanical.item_unserved`, `mechanical.zone_left_out` and `mechanical.item_across_segments` never blocking and `mechanical.item_missing` blocking, the same in the preflight and the export notes; the exported HBJSON reloading with Room A holding two `PhSupportiveDevice` and Room B one, each under its pump's id with its Tag, values, resolved profile and `user_data`, and `conformance` passing; through PHX in the `phx` test group two `PhxSupportiveDevice`, each once, with their values, a pump on a Room with Spaces and one without giving one device and a pump only on a Room with no Spaces giving none (D4-25); the UI polish review recorded; the host case `M10` (create, edit, the disclosure, Serves, delete with replacement, native Undo and Redo, export and reload, save and reopen) in the MS3 sitting (D4-31) | Open: offline evidence recorded ([p4-10](evidence/p4-10-pumps.md)); host owed MS3 (case `M10`) |
| M11 | Mechanical and export, P4-11 | The Fan kind (Q6, D4-35): Tag, Type offering Kitchen hood, Dryer and User-defined (User-defined by default), Quantity (1), Flow in the airflow quantity (0 m³/h), Runtime in minutes a year (0), Power in W (blank on create; blank means no linked supportive device), hideable Manufacturer, Model and Notes (D4-20); In conditioned space (yes) and an Operation override in kh a year behind a collapsed per-row disclosure, the operation following the runtime as `annual_runtime_minutes / 60,000` until the user overrides it (D4-35); a value outside its range refuses `params.invalid` and writes nothing; create, in-place edit with stale-value refusal, duplicate with `user_data`, guarded delete refusing `reference.in_use` while a Zone names it, delete with a replacement moving every Zone's `fan_ids` (kept once) and with null emptying them, each one Undo step; the `fan_ids` `many` Serves slot (payload schema 6): one fan on Zone A and Zone B and a second on Zone A, Clear taking one out; the Fans subtab with its Fans pill (D4-13), the Serves chips and Zone picker, Locate narrowing to `fan_ids`; `mechanical.zone_without_spaces` on a fan serving an exported Zone no Space names, never blocking, the pair still written, from P4-10's helper (D4-35); `mechanical.item_unserved`, `mechanical.zone_left_out` and `mechanical.item_across_segments` never blocking and `mechanical.item_missing` blocking, the same in the preflight and the export notes; the exported HBJSON reloading with each served Room holding one exhaust ventilator of the fan's class per fan under its id, with its Tag, quantity, flow in m³/s, runtime and `user_data`, and, for a kitchen hood with Power, a linked type 10 `PhSupportiveDevice` under the same id with its quantity, watts and resolved kilohours, a fan without Power holding none, and `conformance` passing; through PHX in the `phx` test group one record becoming two objects with Power (an exhaust device on the Zone and a supportive device) and one without, each once, a fan on a Room with Spaces and one without reaching PHX once and a fan only on a Room with no Spaces giving none (D4-25); the UI polish review recorded; the host case `M11` (create, edit, the disclosure, Serves, delete with replacement, native Undo and Redo, export and reload, save and reopen) in the MS3 sitting (D4-31) | Open: offline evidence recorded ([p4-11](evidence/p4-11-fans.md)); host owed MS3 (case `M11`) |
| M12 | Equipment, P4-12 | Superseded 2026-11-14 with its stage: appliances and the Phius default set are Programs' Equipment Sets, accepted there as PG07, PG10 and PG11b ([Phase 6 ACCEPTANCE](../../archive/phase-06-program/ACCEPTANCE.md)) | Superseded |
| M13a | Piping, P4-13a | The `ph_composer.piping` feature, last in `FEATURES`, requiring Mechanical and Zones, with nothing under Mechanical naming it; the Pipe Type kind (`ppt_`, Q3, Q9): Tag, Material (Copper L), Diameter from the eight nominal sizes stored in mm (1/2 in, 12.7 mm, Q4), insulation 12.7 mm at 0.04 W/(m K), reflective, quality 1 on create; a material, diameter, thickness, conductivity or quality out of range refuses `params.invalid` and writes nothing; guarded update, duplicate with `user_data`, delete, each one Undo step; insulation with no conductivity is the type's export blocker `piping.insulation_conductivity_missing`; `PLANNING_IDS` refuses a planted `M13a`; the host case `M13a` (panel-closed script, Undo and Redo, save and reopen) in the MS3 sitting (D4-31) | Open: offline evidence recorded in [p4-13a-pipe-types](evidence/p4-13a-pipe-types.md); host owed MS3 |
| M13b | Piping, P4-13b | A Piping group (`ppg_`) created at the root by `groups.create`, linked to HWS-1 and opened for drawing in one Undo step; `groups.link` and `unlink` with stale-value refusal; a group inside a Zone Group refuses `piping.group_in_zone` (Q13) and inside a Piping group `piping.group_nested`; the pipe assignment (`ppe_`) with a Pipe Type, a role (`trunk`, `branch`, `twig`, `recirculation`) and the role's values, a trunk's `multiplier` and `demand_recirculation`, a recirculation pipe's `water_temp_c` and `daily_period`, absent for the other roles; assign and clear over explicit references, one Undo step, refusing as a whole for a stale target, an Edge outside a Piping group, a write refusal or 251 Edges; a split Edge reads two pipes with one id, `copied`; deleting a Pipe Type in use refuses `reference.in_use`, with a replacement or null rewrites every Edge in one Undo step; deleting a Hot Water System a group names refuses, with a replacement retargets the group through the engine; no edge registry (Q1); the host case `M13b`, which measures what nothing has yet: an empty Group created by an operation survives and opens, the Line tool draws into the open group, a line from the middle of a loose Edge splits it and shares the vertex, crossing loose lines split each other, a pasted group's assign refuses through shared storage (MS3) | Open: offline evidence recorded in [p4-13b-piping-groups-and-assignment](evidence/p4-13b-piping-groups-and-assignment.md); host owed MS3 |
| M13c | Piping, P4-13c | The chain rule moved to `core/edge_runs.rb` with Phase 3b's chain-rule tests, the thermal-bridge goldens byte-identical and `acceptance_ledger.py status --changed`'s stale count recorded; on the hot water piping case below one trunk (multiplier 12), three branches each under it, six twigs two under each branch and two recirculation runs (their values differ), lengths equal to hand measurement to 0.001 m; a trunk changing Pipe Type is two trunks; a branch through a tee is one branch; a broken branch raises `piping.branch_unconnected`, a twig on a trunk `piping.twig_unconnected`, both blocking, a trunk with no branch and a branch at a type change warn; identifiers deterministic, a split Edge two segments; the recirculation sum per System equal to honeybee-ph's length-weighted temperature and truncated hours, nested as honeybee-ph nests them (54.09 °C and 19 h on the case, 24 for one run of uneven 24 h pipes and for the case's loop at 24 h, 60 and 24 with none; two runs of 3.3 m and 1.7 m at 24 h give honeybee-ph's 23); the `schedule` read with rows, totals, `systems` and `types` rows and `runs.locate`; the schedule measured on 50,000 Edges; the host case `M13c` with the stale thermal-bridge cases repeated (MS3) | Open: offline evidence recorded in [p4-13c-tree-and-schedule](evidence/p4-13c-tree-and-schedule.md); host owed MS3 |
| M13d | Piping and export, P4-13d | The pinned wheel's piping classes and the absent calculation-method attribute confirmed and cited; one extraction record per System with pipes; the Python section adds the trunk with its branches and twigs and the recirculation element to every (System, Zone) `PhHotWaterSystem` before the hot water section attaches it (D4-09); the exact HBJSON reloads with both Rooms' systems carrying them, equal hot water digests, `recirc_temp` and `recirc_hours` equal to the Ruby values, blank tap points reading the twig count; `conformance` refuses a differing, missing or unreported trunk; a blocking finding keeps the section unwritten with the same rows in the preflight; `piping.system_unexported` when a System's pipes go nowhere; a forced translate failure blocks (D4-06); through PHX in the `phx` test group one trunk, each branch and twig once, multiplier 12 and one recirculation element, and none from a Room with no Spaces (D4-25); the host case `M13d` (export, reload, save, reopen and re-export) in the MS3 sitting | Open: offline evidence recorded in [p4-13d-piping-export](evidence/p4-13d-piping-export.md); host owed MS3 |
| M13e | Piping and UI kit, P4-13e | The `Pipe Types` and `Piping` pills after Tanks under Hot Water (D4-13): Pipe Types with nominal diameters and used length; the assign bar with the role's values only for its role, New Piping group and Assign by clicking; the Piping groups with their System; the schedule by System, group and role with totals, findings and Locate; the Systems table's recirculation columns contributed by piping and mechanical's field removed; `hours_per_day` vectors; `piping_by_role` and `piping_by_type` with stroke weight and legend lengths; the pipe tool armed with a type, role and values, one Undo step per gesture; the PRD's acceptance shape on the hot water piping case below with Ed at the mouse, Undo per assign, save and reopen, the panel at three sizes and the UI polish review recorded (host case `M13e`, MS3) | Open: offline evidence recorded in [p4-13e-piping-view](evidence/p4-13e-piping-view.md); host owed MS3 |
| M14a | Ducting, P4-14a | The `ph_composer.ducting` feature, last in `FEATURES` after Piping, requiring Mechanical and Zones, with nothing under Mechanical or Piping naming it and nothing under ducting naming piping; the Duct Type kind (`dct_`, Q7): Tag, Round by default at 160 mm, insulation 25.4 mm at 0.04 W/(m K), reflective; a Rectangular type holds width and height and no diameter; a missing or other-shape dimension, a non-positive dimension, a negative thickness or a conductivity of 0 refuses `params.invalid` and writes nothing; a shape change drops the old dimensions in one Undo step; guarded update, duplicate with `user_data`, delete, each one Undo step; insulation with no conductivity is the type's export blocker `ducting.insulation_conductivity_missing`; the host case runs panel closed | Open: offline evidence recorded in [p4-14a-duct-types](evidence/p4-14a-duct-types.md); host owed MS3 |
| M14b | Line groups, P4-14b | The `line_groups/` foundation package naming no feature, holding the line-group targets, write steps, walk, selection rows, schedule paging and Locate parameterized by a feature's spec; piping moved onto it with every piping test unchanged, the piping goldens and `docs/API_REFERENCE.md` byte-identical and no API bump; `acceptance_ledger.py status --changed`'s stale count recorded and M13b to M13e's dependency patterns naming the package; no host case of its own | Open: offline evidence recorded in [p4-14b-line-group-layer](evidence/p4-14b-line-group-layer.md); host owed MS3 (M13b to M13e on the moved code) |
| M14c | Ducting, P4-14c | A Ducting group (`dcg_`) created at the root by `groups.create`, linked to ERV-1 and opened for drawing in one Undo step; `groups.link` and `unlink` with stale-value refusal; a group inside a Zone Group refuses `ducting.group_in_zone` and inside a Ducting group `ducting.group_nested`; a copied group keeps its Ventilator; the duct assignment (`dce_`) with a Duct Type, a direction (`outdoor_air`, `exhaust_air`) and a quantity (1 by default); assign and clear over explicit references, one Undo step, refusing as a whole for a stale target, an Edge outside a Ducting group, a write refusal or 251 Edges; delete in use for Duct Types (refused, replaced, cleared, atomic through shared storage) and for Ventilators, whose delete now routes foreign referrers through `request.retarget_references` naming no feature; the host case on M13b's H1 and H2 | Open |
| M14d | Ducting, P4-14d | On the [ERV ducting case](#erv-ducting-case-p4-14) four runs of 2.500, 1.800, 2.500 and 1.500 m to 0.001 m, ERV-1's lengths 2.500 and 1.800 m and ERV-2's 2.500 and 3.000 m (quantity 2); runs keyed by occurrence, direction, Duct Type and quantity, with no chain rule; identifiers deterministic across scans and a split; every finding case fires on its case only, `ducting.run_missing` not for an unserved Ventilator; the schedule, its paged reads, `runs.locate`, `used_length_m` and the `ducting_ventilators` section (or the recorded reason it is fetched); the measurement recorded | Open |
| M14e | Ducting and export, P4-14e | The pinned wheel's ducting classes and the absent quantity carrier confirmed and cited; one extraction record per Ventilator with ducts, in metres; the Python section appends the elements to every (Ventilator, Zone) `PhVentilationSystem` before the ventilation section attaches it (D4-09); the exact HBJSON reloads with each Room's system carrying its runs, the shared case's two Rooms with equal identifiers and no reload refusal, a quantity of 2 as two elements, and both total lengths equal to the Ruby values; `conformance` refuses a differing, missing, unreported or wrongly directed element; a blocking finding keeps the section unwritten with the same rows in the preflight; `ducting.ventilator_unexported`; through PHX in the `phx` group two devices with two and three ducts in the base case and one device with two ducts in the shared case (D4-25); save, reopen and re-export give the same HBJSON | Open |
| M14f | Ducting and UI kit, P4-14f | The `Duct Types` and `Ducting` pills after Ventilators under Ventilation (D4-13): Duct Types with shape-specific dimensions and used length; the cold-runs line (Q1); the assign bar with Outdoor air and Exhaust air (Q2), type and quantity, and New Ducting group; the Ducting groups with their Ventilator; the schedule by Ventilator, group and direction with totals, findings and Locate; the Ventilators table's `Outdoor air duct` and `Exhaust air duct` columns contributed by ducting (Q9); `ducting_by_direction` and `ducting_by_type` with stroke weight and legend lengths; the PRD's acceptance shape on the ERV ducting case from a fresh process with Ed at the mouse, at the three panel sizes, with the UI polish review | Open |
| M15 | Integration, P4-15 | Both offline Ruby gates, coverage, browser and runtime checks; packaged inventory and footprint through `vendor.py --check` against its keys: the 28,000,000 byte ceiling and the growth allowance over the baseline Phase 6 reset to 26,093,959 (F37); the PRD's acceptance shape from a fresh process on the reference model with a nested Zone, a copied Zone, two Models, Undo/Redo, save and reopen, and export; the `phx` group's round trips green; every METr file and import row named in metr-export with its owner | Open |
| M16 | Mechanical and export, P4-08b | The `ph_composer.mechanical.segment` extension on the Building Segment record: mechanical cooling entered as a switch, off by default, and the mechanical room temperature at 20 °C by default (D4-26), with the four summer ventilation values of D4-32 (bypass mode `4-Always`, ventilation system air changes blank, daytime and nighttime window air changes 0.0) and nothing else; a partial, extra-field or out-of-range payload refuses `validation.failed` and writes nothing; `ph_composer.mechanical.segment.get` reads the defaults until a payload is stored; the Mechanical section of the Building Segment settings, after Comfort, saving in one Undo step with the other sections, and Undo restoring both; `mechanical.segment_cooling_mismatch`, a warning that never blocks, in the preflight and as an export note, when the switch is on and the Segment's exported blend has no cooling (none counts) or off and it cools; one export record per exported Segment, defaults included; the exported HBJSON reloading with each Segment's `set_points.mechanical_cooling`, `mech_room_temp` and four `summer_ventilation` values as entered, the seven omitted summer ventilation fields at honeybee-ph's `SummerVentilation` defaults, and the winter and summer set points Programs wrote unchanged; a Segment with no stored settings reloading with honeybee-ph's defaults; a PHX round trip reading mechanical cooling, the mechanical room temperature and summer ventilation on each Variant, and the room temperature and bypass mode in the WUFI XML and METr JSON (D4-25); the host case `M16` (native Undo and Redo of the Save, save and reopen, export) in the MS3 sitting (D4-31) | Open: offline evidence recorded ([p4-08b](evidence/p4-08b-segment-mechanical-settings.md)); host owed MS3 (case `M16`) |

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

### Hot water piping case, P4-13

A case P4-13's sub-stages add, not part of the base fixture, so the base export and M06's 60 °C and 24 h with no
piping stay as above. Three storeys of 3 m are drawn as lines only; the pipes belong to HWS-1, which serves Zones A and
B (Q8), and sit outside every Zone Group (Q13).

| Pipe Type | Material | Diameter | Insulation | Conductivity, W/(m K) |
| --- | --- | --- | --- | --- |
| PT-1 | 6, PEX | 3/4 in, 19.05 mm | 12.7 mm, reflective, quality 1 | 0.04 |
| PT-2 | 6, PEX | 1/2 in, 12.7 mm | 0 mm | 0.04 |

Piping group PG-1 at the Model root, identity transform, linked to HWS-1. Every line is drawn in PG-1, endpoints in
metres; a tee is a shared vertex, so a line meeting another's middle splits it there (host case H3 in P4-13b).

| Run | Role and values | Type | Edges | Length, m |
| --- | --- | --- | --- | --- |
| Riser | trunk, multiplier 12, no demand recirculation | PT-1 | (1,1,0)-(1,1,3), (1,1,3)-(1,1,6), (1,1,6)-(1,1,9) | 9.000 |
| Floor 1 | branch | PT-2 | (1,1,3)-(3,1,3), (3,1,3)-(5,1,3) | 4.000 |
| Floor 2 | branch | PT-2 | (1,1,6)-(3,1,6), (3,1,6)-(5,1,6) | 4.000 |
| Floor 3 | branch | PT-2 | (1,1,9)-(2.5,1,9), (2.5,1,9)-(4,1,9) | 3.000 |
| Twigs on floor 1 | twig | PT-2 | (3,1,3)-(3,2,3); (5,1,3)-(5,2.5,3) | 1.000; 1.500 |
| Twigs on floor 2 | twig | PT-2 | (3,1,6)-(3,2,6); (5,1,6)-(5,2.5,6) | 1.000; 1.500 |
| Twigs on floor 3 | twig | PT-2 | (2.5,1,9)-(2.5,2,9); (4,1,9)-(4,2,9) | 1.000; 1.000 |
| Loop up | recirculation, 55 °C, 18 h | PT-1 | (1.2,1,0)-(1.2,1,9) | 9.000 |
| Loop across | recirculation, 50 °C, 24 h | PT-1 | (1.2,1,9)-(1.2,3,9) | 2.000 |

Expected: one trunk of 9.000 m with multiplier 12 and three branches (4.000, 4.000, 3.000 m), each holding two twigs;
two recirculation runs (their values differ, so they do not chain); 17 Edges; totals trunk 9.000, branch 11.000, twig
7.000, distribution 27.000 and recirculation 11.000 m. HWS-1's recirculation: 11.000 m, temperature
(9 x 55 + 2 x 50) / 11 = 54.09 °C, hours the truncation of (9 x 18 + 2 x 24) / 11 = 19.09, so 19. After export and
reload, both Rooms' `ph_hvac.hot_water_system` carry that trunk, its branches and six fixtures, the two recirculation
elements, `recirc_temp` 54.09 and `recirc_hours` 19, with `number_tap_points` 8 as entered (6, the twig count, with tap
points blank).

| Case | Expected |
| --- | --- |
| Move Floor 2's first line to start at (1.05,1,6) | `piping.branch_unconnected` on Floor 2 only, blocking; its twigs still hang from it |
| Clear Floor 3's two lines | `piping.twig_unconnected` on floor 3's two twigs, blocking |
| Set the riser's top line to multiplier 6 | Two trunks, 6.000 m (multiplier 12) and 3.000 m (multiplier 6); Floor 2 touches both and takes the one whose identifier sorts first, with `piping.parent_ambiguous`, not blocking |
| Unlink PG-1 | `piping.group_unlinked`, blocking |
| Set both loop lines to 24 h | Hours 24, not 23 |
| Paste PG-1 in place | Two occurrences sharing storage: two of each run with distinct identifiers, `piping.shared_definition`; an assign through either refuses until one is made unique |

### ERV ducting case, P4-14

A case P4-14's sub-stages add, not part of the base fixture. It uses the base case (ERV-1 serves A, ERV-2 serves B)
unless a row says the shared case. The two cold runs of each Ventilator are drawn as lines only, in Ducting groups at
the Model root, outside every Zone Group (Q5); each Ducting group names its Ventilator (Q6).

| Duct Type | Shape | Size | Insulation | Conductivity, W/(m K) |
| --- | --- | --- | --- | --- |
| DT-1 | Round | 160 mm diameter | 25.4 mm, reflective | 0.04 |
| DT-2 | Rectangular | 200 mm wide, 100 mm high | 50.8 mm, not reflective | 0.035 |

Ducting groups DG-1 (linked to ERV-1) and DG-2 (linked to ERV-2), identity transforms. Endpoints in metres.

| Group | Run | Type | Quantity | Edges | Length, m |
| --- | --- | --- | --- | --- | --- |
| DG-1 | Outdoor air | DT-1 | 1 | (1,0.5,2.8)-(1,2,2.8), (1,2,2.8)-(2,2,2.8) | 2.500 |
| DG-1 | Exhaust air | DT-1 | 1 | (1.5,0.5,2.8)-(1.5,1.5,2.8), (1.5,1.5,2.8)-(2.3,1.5,2.8) | 1.800 |
| DG-2 | Outdoor air | DT-2 | 1 | (6,0.5,2.8)-(6,3,2.8) | 2.500 |
| DG-2 | Exhaust air | DT-2 | 2 | (7,0.5,2.8)-(7,2,2.8) | 1.500 |

Expected: four runs from six Edges. The Ventilators table reads ERV-1 2.500 m outdoor air and 1.800 m exhaust air, and
ERV-2 2.500 m and 3.000 m (1.500 m at quantity 2). After export and reload, Room A's `ph_hvac.ventilation_system`
(ERV-1) holds one `supply_ducting` element (`duct_type` 1, two round segments, diameter 0.16, width and height None,
insulation 0.0254 at 0.04, reflective) and one `exhaust_ducting` element (`duct_type` 2, 1.800 m); Room B's (ERV-2)
holds one rectangular supply element (width 0.2, height 0.1, insulation 0.0508 at 0.035, not reflective) and two
exhaust elements of 1.500 m with distinct identifiers. `supply_ducting_total_length` and `exhaust_ducting_total_length`
read 2.5 and 1.8 on Room A and 2.5 and 3.0 on Room B. In the shared case (ERV-1 serves A and B), both Rooms carry
DG-1's two elements with equal identifiers, the reload does not refuse, and DG-2's ducts raise
`ducting.ventilator_unexported`.

| Case | Expected |
| --- | --- |
| Clear DG-1's two Exhaust air lines | `ducting.run_missing` on ERV-1, not blocking; ERV-1's system carries its supply element only |
| Delete ERV-2 with null | DG-2 unlinked: `ducting.group_unlinked`, blocking, whose Locate selects DG-2 |
| Delete ERV-1 with ERV-2 as replacement | DG-1 and Zone A's Serves slot name ERV-2, one Undo step that Undo restores |
| Set DT-2's conductivity to null | `ducting.insulation_conductivity_missing` (50.8 mm of insulation), blocking |
| Delete DT-1 with null | `ducting.type_missing` on DG-1's four lines, blocking |
| Set DG-1's second Outdoor air line to DT-2 | Two Outdoor air runs for ERV-1 (1.500 m round, 1.000 m rectangular), two supply elements; ERV-1's outdoor air length still 2.500 m |
| Paste DG-1 in place | Two occurrences sharing storage: two of each DG-1 run with distinct identifiers, `ducting.shared_definition`; ERV-1's lengths 5.000 and 3.600 m; an assign through either refuses until one is made unique |
| Move DG-1 into Zone A's Group | `ducting.group_in_zone`, blocking |

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

M01 to M16 close Phase 4, M12 as superseded and M13 as its five sub-rows. What PHX builds from the HBJSON is in this register
as a round trip per export stage (D4-25): one device or three for a shared item, tanks and heaters
once, and the Spaces walk for exhaust and supportive devices when their stages are planned. The
METr file itself and its import into METr are excluded and stay open in
[metr-export](../unscheduled/metr-export/README.md). The simplified hot water
methods wait on honeybee_ph#135. SketchUp 2023 and Windows remain their own gates.
