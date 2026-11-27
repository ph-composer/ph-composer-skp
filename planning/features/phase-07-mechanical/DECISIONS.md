# Phase 4, mechanical: findings from source, and the decisions that follow

DATE: 2026-10-21
STATUS: Scoped. Part 1 is findings read from source on `main` at `420c783a` and the honeybee-ph and PHX checkouts on 2026-10-21. Part 2 was answered by Ed on 2026-10-21, every row as recommended; see "Ed's answers". The interviews (Q1 to Q12, V1 to V6, hot water H1 to H7) are answered and live in the equipment PRD. Part 3 records the wireframe review of 2026-11-15: findings F15 to F19 and decisions D4-13 to D4-20, several revising earlier answers. Part 4 records the review of 2026-11-22 after Phase 6 Programs: findings F21 to F39 and decisions D4-21 to D4-27, which Ed answered the same day, every one as recommended. Part 6 records the hold 2 review of 2026-11-27: findings F41 to F45 and decisions D4-38 to D4-49, every one answered as recommended.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

The [equipment PRD](equipment/PRD.md) is the interview record: its decisions table (Q1 to Q12),
family 1 (V1 to V6) and family 2 (hot water H1 to H7) hold Ed's answers of 2026-10-21. This file
does not restate them. Part 1 lists what the code and the stack say beyond the PRD; Part 2 lists
the choices those facts force at planning, each with a recommendation. The bindings that follow
are in [CONTRACTS.md](CONTRACTS.md); they change when an answer differs.

Decisions are D4-01 to D4-12, findings F1 to F14. Stages are P4-01 to P4-15, tracked in
[STATUS.md](STATUS.md). A reference to a Spaces or thermal-bridge decision always says which.

Paths are relative to `src/ph_composer/` unless stated. "Read from source" means the file was read,
not that the consequence was reproduced on a host or in a test.

## Part 1: findings

### Code on `main`

| # | Finding | Consequence |
| --- | --- | --- |
| F1 | `reference_identity` refuses an entry whose `record["id"]` is not a non-empty String (`core/records/reference_resolution.rb`, 3b F6) | The Serves record carries an `eqa_` id (CONTRACTS section 2) |
| F2 | The Zone reference target declares `locate:` (`features/zones/declarations/zone.rb:13`, `Occurrences.locate_zone`), and `request.locate(kind, reference)` resolves a writable entity with the owner's refusals (`shell/handler_request.rb:101`) | Serves resolves the Zone Group through Zones' own locate; no new Zones read |
| F3 | `transition_contributor` on `ph_composer.zones.occurrence_independent` gives a child its own restorable step in the Zone copy's proposal; `tests/support/zone_child_fixture.rb` is a second child built from public contracts alone, re-issuing tag ids by allocator | The Zone-copy contributor is the fixture's shape with one record per Zone (D4-04) |
| F4 | `Assembly::Operations.delete` calls `request.retarget_references(kind, from:, to:)` for a replacement and `propose_delete(..., reference_plan:)`; an explicit null clears references through referrer handlers (`context/CONTRACTS.md`, "Geometry records and occurrence references") | Delete in use per slot follows it (D4-05) |
| F5 | `assembly.py` `_attach` groups a section's objects by `attachment.key(translated)`, one host per object, and attaches each host's objects in one call | A shared item needs one object per served Room, or a new attachment shape (D4-01) |
| F6 | `Section.required_for_export` defaults True; Spaces is required (D3a-9); the thermal-bridge section will be the first optional one (D3b-20, H18) | Equipment chooses (D4-06) |
| F7 | `stack.PACKAGES` lists `honeybee_ph` and `honeybee_energy_ph` and not `honeybee_phhvac`; `load` raises `ValueError` for an unlisted top-level package; the pinned wheel ships `honeybee_phhvac` | One line in P4-01 (CONTRACTS A1) |
| F8 | `html/index.html` holds a disabled "Systems" button beside a disabled "Thermal Bridges" button, each with `data-tooltip="Planned"`; a `data-pane` is created by `panel.section` when absent, the tab button is not | P4-05 edits the composition root once (A2); 3b's P3b-05 edits the sibling button |
| F9 | `core/units.rb` has `airflow`, `volume`, `heat_loss_rate`, `conductivity`, `length` and no electric-efficiency, litre or temperature quantity; the panel registry has 18 quantities (units STATUS) | A3 adds what V4 and the tank fields need. Superseded 2026-11-22 by F31: `temperature` exists; electric efficiency and litres are still missing |
| F10 | Spaces' `ph_composer.spaces.all` `zones` rows carry `airflows` (null while any Space inherits), `inheriting_count` and `imbalanced`, and `Spaces::Metrics.imbalanced?` is the 10 percent rule | The balance by ventilator sums those rows per served Zone and reuses the rule (D4-10). Changed 2026-11-22 (F24): the rows carry `airflow_mode` in place of `inheriting_count`, and `airflows` is null while the Zone is By Program |
| F11 | `features/zones/colour_modes.rb` registers `entity_kind: "zone"` modes whose projection walks `entries(read.model)` | `by_ventilator` takes that shape; P4-01 confirms the projection can key by Zone id (CONTRACTS section 7, question 3) |

### honeybee-ph 1.33.65 and PHX

| # | Finding | Consequence |
| --- | --- | --- |
| F12 | `RoomPhHvacProperties` has `set_ventilation_system`, `set_hot_water_system`, `add_heating_system`, `add_heat_pump_system`, `add_supportive_device`, `add_exhaust_vent_device`, `add_renewable_device`; one ventilation and one hot water system per Room | The one-per-Zone rules (V1, hot water H6) match the carrier |
| F13 | PHX keys ventilation systems, tanks and heaters by identity across Rooms (`create_variant.py`, `get_mech_device_by_key`, `device_in_collections`); requires a unit on every ventilation system; takes tap points, recirculation temperature and hours once per variant and falls back to 60 °C and 24 h when systems disagree; skips a Room with no system; reads exhaust ventilators and supportive devices through a Room's Spaces | D4-01's shared-identifier rule is what PHX dedups on; `equipment.recirc_disagrees` (CONTRACTS section 6); the Spaces-walk consequence is metr-export's |
| F14 | `PhHotWaterSystem` has four typed tank slots (`tank_1`, `tank_2`, `tank_buffer`, `tank_solar`) and no calculation-method field; PHX's `PhxRecirculationParameters.calc_method` is written to WUFI and METr but never set from HBJSON ([honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135)) | Tank slotting needs a rule (D4-07); the method field waits (D4-12) |

## Part 2: decisions for Ed

Each row names the stages it blocks. A stage does not start until every row it names has an
answer. Kind: Code, UI or Scope.

| ID | Kind | Question | Recommendation | Blocks |
| --- | --- | --- | --- | --- |
| D4-01 | Code | An item serves several Zones and a section attaches one host per object (F5). One translated object per (item, Zone) pair sharing the item's identifier, or a new attachment shape? | One object per pair. Each `PhVentilationSystem` and `PhHotWaterSystem` is built per served Room with identifiers derived from the item id, so honeybee-ph holds equal objects on each Room and PHX's key dedup (F13) sees one device. The assembly is unchanged; `conformance` checks the identifiers agree across Rooms. The alternative, a multi-host attachment, changes `assembly.py` for one consumer | P4-04, P4-06 |
| D4-02 | Code | One feature for seven families, or one per family? (Q1 said one packet) | One feature, `ph_composer.equipment`, with a folder per family and one `serves/` folder. One composition-root entry, one codes noun, one Serves record with a slot per family. A layer test keeps family folders from naming Zones. Seven features would need seven Serves records or a shared one none owns | P4-02 |
| D4-03 | Code | The Serves record's shape (Q3) | One dictionary `ph_composer.equipment_serves` on the Zone Group with one slot per family: single references for Ventilator and Hot Water System, arrays for the rest, each a core `Records::Reference`; an `eqa_` id (F1); removed when every slot empties. A record per (Zone, item) pair would need an id per pair and a walk to answer "what serves this Zone" | P4-03 |
| D4-04 | Code | What does a copied Zone keep? (Q3's answer: what serves it) | Everything: the copy's Serves record is kept verbatim except its `eqa_` id, which the transition contributor re-issues in the Zone's own proposal (F3), so two Zones never share an `entity_id`. A shared Ventilator serving both copies is a legitimate model (one unit, two apartments) and the user reassigns when it is not. Dropping the record on copy would lose the multifamily case Q4 named | P4-03 |
| D4-05 | Code | Delete in use, per slot (F4) | Without a replacement: refuse while any Serves slot names the item, listing the Zones. With `replacement_id`: rewrite that slot on every Serves record. With explicit null: clear the slot, removing a record that empties. One proposal, one Undo step, as Assemblies | P4-02, P4-03 |
| D4-06 | Code | Are the equipment sections required for export? (F6) | Yes, `required_for_export = True`, as Spaces (D3a-9). Ruby filters what is not exportable before translation with its own findings (an unserved item, an omitted Zone), so a translation or attach failure is a real fault. The thermal-bridge section's optionality (D3b-20) rests on runs being derived; equipment records are authored | P4-04, P4-06 |
| D4-07 | Code | Hot water H3 chose a free tank list slotted at export. By list order alone, or by a role? | By role. Each tank carries `role`: `storage`, `buffer` or `solar`. Storage tanks fill `tank_1` then `tank_2` in list order; the buffer tank fills `tank_buffer`, the solar tank `tank_solar`. A third storage tank, or a second buffer or solar, is `equipment.tank_unslotted`, omitted with a non-blocking finding. honeybee-ph's slots are typed (F14), so pure order would put a buffer tank in `tank_2` silently | P4-06 |
| D4-08 | UI | The Systems tab's layout (Q9, D4 of the cross-cutting register) | Enable the reserved tab (F8). One subtabs row, Equipment, ERV ducting, Hot-water piping, each listed only once built, as Zone views are. Inside Equipment, a family selector as a select in the page header, one inventory table beneath it; not a second subtabs row. The UI polish review in P4-05 may revise | P4-05 |
| D4-09 | Code | Piping and ducting objects belong inside equipment's translated systems, and a section attaches only to `MODEL`, `ROOM` or `FACE` | The later section `requires` the equipment section and, in `translate`, adds its elements to the required object it was handed (the coordinator orders sections by requirements, and objects are shared references); the equipment section attaches afterwards. No new attachment host. Bound now so P4-04's section keeps its objects mutable and keyed by (item, Zone); confirmed when piping is planned | P4-04 (shape), P4-13, P4-14 |
| D4-10 | Code | Where is the balance by ventilator computed? (Q11, F10) | In a pure Ruby function in `serves/balance.rb` over Spaces' Zone rows and the Serves rows, exposed on `ventilators.all` and the snapshot section. The feature therefore requires `ph_composer.spaces`; its family folders never read it. The alternative, computing it in the panel from two sections, puts a rule in JavaScript | P4-05 |
| D4-11 | Code | Which unit rows does Phase 4 add? (F9, V4) | `electric_efficiency` (Wh/m³ stored, W/cfm in IP), `volume_l` (litres stored, US gallons in IP), and `temperature` (°C stored, °F in IP) unless the panel registry already has it; W, kWh and kBtu/h wait for the families that show them. Recorded in the units packet as its Q3 outcome | P4-05, P4-07 |
| D4-12 | Code | Hot water H5: store the piping calculation method now. How does it sit until the pinned wheel carries the field? | A nullable field on the Hot Water System record, shown in the view, written to the honeybee-ph object only when the loaded class accepts it (checked at translate), otherwise `equipment.method_not_exported`, non-blocking. Not passed as `user_data`, which nothing standard reads. When the wheel is bumped the check becomes a no-op and the finding disappears | P4-06 |

## Ed's answers

Ed answered D4-01 on its own and then accepted every remaining recommendation on 2026-10-21.
A row here supersedes the recommendation in Part 2; none differs.

| ID | Answer | Date |
| --- | --- | --- |
| D4-01 | As recommended: One translated object per (item, served Zone) pair with equal identifiers | 2026-10-21 |
| D4-02 | As recommended: One feature, `ph_composer.equipment` | 2026-10-21 |
| D4-03 | As recommended: One `ph_composer.equipment_serves` dictionary per Zone Group, a slot per family, `eqa_` id | 2026-10-21 |
| D4-04 | As recommended: A copied Zone keeps its Serves record; only the id is re-issued | 2026-10-21 |
| D4-05 | As recommended: Refuse in use, rewrite with a replacement, clear with null | 2026-10-21 |
| D4-06 | As recommended: `required_for_export = True` | 2026-10-21 |
| D4-07 | As recommended: Slot by role: storage to tank 1 and 2 in order, buffer, solar; the rest unslotted | 2026-10-21 |
| D4-08 | As recommended: Enable the reserved tab; one subtabs row; a family select in the page header | 2026-10-21 |
| D4-09 | As recommended: The later section requires the equipment section and adds to its object before attach | 2026-10-21 |
| D4-10 | As recommended: A pure Ruby read in `serves/balance.rb` over Spaces' Zone rows; the feature requires Spaces | 2026-10-21 |
| D4-11 | As recommended: `electric_efficiency`, `volume_l`, `temperature` | 2026-10-21 |
| D4-12 | As recommended: A nullable record field, written only when the loaded class accepts it | 2026-10-21 |

## Part 3: wireframe review, 2026-11-15

Ed reviewed the [Mechanical tab wireframes](mockups/README.md) on 2026-11-15 and answered the
questions below against them. A row that revises an earlier answer says which; the earlier row
stays as the record of what was first decided. Findings continue from F14 and decisions from
D4-12. CONTRACTS, ACCEPTANCE and the stage documents P4-05 to P4-11 are not yet re-bound to these
answers; [STATUS](STATUS.md) lists what each owes.

### Findings

"Read from source" as in Part 1. The Phius workbook was read outside this repository and is not
part of it.

| # | Finding | Consequence |
| --- | --- | --- |
| F15 | The Phius Heat Pump Performance Estimator v25.1.2 takes outdoor compressors and condensing units only, and says not to include interior heads or air handling units. Per row: quantity, heating capacity at 17 and 47 °F with either two COPs or an HSPF, cooling capacity at 95 °F with either EER and SEER or IEER. Indoor fans enter only as watts, and only when the rating excludes fan power | Nothing on an indoor model exports as performance (D4-15, D4-20) |
| F16 | The estimator's results are one rated-monthly heat pump (coverage, two weighted COPs at 17 and 47 °F) and one recirculation-air cooling set (number of systems, capacity, air flow, coil temperature, weighted COP), split across systems above 682 kBtu/h. It derates HSPF and SEER by climate, citing FSEC-PF-413-04, and takes fan run-time from WUFI's monthly demands. Ground-source and water-source have their own sections | The results map onto `PhHeatPumpRatedMonthly` and `PhHeatPumpCoolingParams_Recirculation` in the pinned wheel. The blend needs climate data (D4-15) |
| F17 | In the pinned wheel `PhHotWaterSystem.recirc_temp` and `recirc_hours` are read-only properties: length-weighted averages over the recirculation piping, 60.0 and 24 with none. `number_tap_points` is settable and otherwise counts branch fixtures | A System cannot carry typed recirculation values (D4-18). CONTRACTS section 2's `recirc_temp_c` and `recirc_hours` fields go |
| F18 | honeybee_grasshopper_ph builds one `PhHotWaterSystem` and sets the same instance on each chosen Room (`gh_compo_io/shw/create_system.py`, `apply_shw.py`), and gives a Room with no service hot water load a nominal one. PHX adds each tank and heater once by key, sets tap points from the last Room read without summing, and keeps one recirculation setting (`from_HBJSON/create_variant.py`, read from the PHX checkout) | One System record serving Zones is the stack's own shape (D4-17). Several Systems pool downstream. The nominal hot water load is a [Phase 4a](../../archive/phase-06-program/README.md) question |
| F19 | `honeybee_energy_ph/hvac/hot_water.py` and `properties/hot_water/hw_system.py` are deprecated stubs that raise; the live classes are in `honeybee_phhvac` | Sections use `honeybee_phhvac` only |

### Decisions

| ID | Kind | Answer, 2026-11-15 | Revises | Blocks |
| --- | --- | --- | --- | --- |
| D4-13 | UI | The primary tab is named Mechanical. Its subtabs are by system: Ventilation, Heat Pumps, Hot Water, Pumps, Fans, Electric Heating, each its own subtab. A pill row under the subtabs picks one table inside a system. Ducting is a pill under Ventilation and Piping a pill under Hot Water | D4-08; equipment Q9; UI baseline U1's "Systems" tab and its Equipment, ERV ducting and Hot-water piping subtabs | P4-05, P4-07, P4-13, P4-14 |
| D4-14 | Code, UI | Heat pumps are four tables, as PH-Navigator has them: Equipment · Outdoor, Equipment · Indoor, Units · Outdoor, Units · Indoor. Outdoor equipment stores the estimator's inputs (F15). An outdoor model may name one paired indoor model, because many ratings hold only for that combination | Equipment Q4, for family 3 only | P4-08 |
| D4-15 | Code | Serves sits on the indoor unit and names Zones. Export is one blended air-source heat pump for the building, on every Room an indoor unit serves, computed by the estimator's method from the outdoor equipment rows and their unit counts (F16). An HSPF or HSPF2 row converts as the estimator does. Version 1 leaves out fans and pumps tied to the heat pump, so it needs no WUFI run-time step, and covers air-source only. The calculation is written in this repository from the published method with synthetic test cases; the workbook stays out, and a private comparison test skips when it is absent | Family 3's open question | P4-08 |
| D4-16 | UI | The blended result is a fifth, read-only pill in Heat Pumps, laid out in the estimator's sections and labels: Inputs for Energy Model, Climate Information, Pumps or Fans, Performance Data, Weighted Value Calculations. A header action copies the rows in the estimator's layout | | P4-08 |
| D4-17 | Code, UI | Hot water is three tables: Systems, Heaters, Tanks. A Hot Water System is one record that serves Zones, as a Ventilator does; heaters and tanks are flat rows that each name their System. A Model may hold several Systems, with a non-blocking note that WUFI and METr pool them and keep one tap-point count (F18). Tank roles and slots stay as D4-07 | Hot water H1 and H7; H3's list becomes the Tanks table | P4-06, P4-07 |
| D4-18 | Code | Recirculation temperature and hours are read-only on the Systems table, read from the recirculation pipes (F17). Tap points stay a System value | Hot water H4, for temperature and hours | P4-06, P4-13 |
| D4-19 | Code | A heater's Type picks which efficiency input is live: the energy factor for a heat pump inside, a COP pair for an outdoor heat pump, the annual performance value for the annual kind, none for electric. Phius's product-specific heat pump water heater estimators are later scope | | P4-06 |
| D4-20 | UI, Code | Every Mechanical table carries Tag, Manufacturer, Model and Notes, the fields that export, and Serves. Tag is the record's name. Export fields come first; the identity columns follow and can be hidden. No Status, attached files, photos or links in the MVP. Documentation fields come in a later stage, so the kinds must accept added fields | Ventilators V3's column list gains Manufacturer and Model | P4-02, P4-05 to P4-11 |

### Entry gate added

D4-15 needs the Model's climate: a Phius location, or the ASHRAE 99% and 1% design temperatures
with the monthly values the derating reads. Ed, 2026-11-15: Climate is built first and planned in
its own thread, and this packet assumes it supplies that data.
[Climate data](../../archive/phase-04-climate/README.md) is the existing packet, drafted as a
post-MVP request.

### Recorded since, from the Climate packet

| # | Finding | Consequence |
| --- | --- | --- |
| F20 | The estimator's derating reads two values per location from its own table, the ASHRAE 1% cooling and 99% heating dry bulb, and its input-power totals read the share of months whose mean temperature is below 17 and below 47 °F (workbook formulas read 2026-11-15, outside this repository). A Phius station file carries the monthly means and neither design temperature | The blend takes the monthly means from the Model's climate and the two design temperatures from the user: [Climate PRD](../../archive/phase-04-climate/PRD.md), W4. Without them the blended heat pump is left out with a finding and export proceeds |

D4-13's tab row gains two neighbours settled in the Climate packet on 2026-11-16: Climate is the
first primary tab, and the row reads Climate, Zones, Assemblies, Window Types, Thermal Bridges,
Programs, Mechanical, Library, Export. The row shipped with Programs after Zones (Part 4, F32);
Mechanical's place in it is D4-27.

### Open after the review

1. Equipment · Indoor. Ed first chose PH-Navigator's full column set, then answered D4-20
   (identity and export fields only). The wireframe draws identity only, since F15 leaves nothing
   on an indoor model to export. Ed has not confirmed that reading.
2. D4-20 asks that kinds accept added fields. CONTRACTS section 2 fixes each kind at
   `schema_version` 1 with its final field set because the engine has no migrations. How a later
   stage adds documentation fields is unanswered. Closed 2026-11-22 (Part 4, F34): the kind's
   `schema_version` moves and the fixtures are rewritten.
3. The HSPF conversion and the climate derating are not written. Every derived number on the
   Blended result wireframe is a placeholder. The cooling coil temperature shown is honeybee-ph's
   default and was not checked against the estimator, and the estimator's split above 682 kBtu/h
   has no agreed handling.
4. Not drawn: Units · Outdoor's columns, row actions, the New-record forms, the Ventilator
   disclosure for the two optional fields (V3), and the 360 x 520 panel size.
5. Pumps, Fans and Electric Heating have their table shape and columns from D4-13 and D4-20.
   Their interviews are otherwise open; Q6 still describes the Fan record.
6. A served Room needs a service hot water load before its system means anything downstream
   (F18). Phase 4a owns loads. Closed 2026-11-22 (Part 4, F33): every exported Room's ProgramType
   carries one.

## Part 4: review after Programs, 2026-11-22

Phase 3b (thermal bridges), Climate, Shading and Programs all merged after Parts 1 and 2 were read
at `420c783a`. This part re-reads what the packet depends on at `main` `8c710412`, the day
[Phase 6: Programs](../../archive/phase-06-program/README.md) was archived. Findings continue from
F20 and decisions from D4-20.

Two kinds of result. Where the code settles a fact, the packet's documents are corrected in the
same change and the finding says where. Where the code would reverse or extend an answer Ed gave,
the row was put to Ed as a decision with a recommendation. He answered all seven on 2026-11-22
("Ed's answers, 2026-11-22", below), and CONTRACTS, ACCEPTANCE, PLAN and the stage documents were
re-bound to them in the same change.

"Run" means run on 2026-11-22 against the pinned wheels in this repository's virtual environment.
"Read" means read in source and not reproduced.

### Findings

| # | Finding | Consequence |
| --- | --- | --- |
| F21 | Phase 3b is complete: P3b-01 to P3b-09 merged through PRs #302 and #308 to #315 and the packet was archived on 2026-10-26. The run builder still lives in `features/thermal_bridges/runs/` | Applied. The P3b-01 ordering gate, the shared-file coordination with a Phase 3b branch and the edge-stage gates on P4-13 and P4-14 are met. Piping and ducting wait on their interviews and on this phase's own stages. Moving the run builder to `core/` is still P4-13's |
| F22 | `FEATURES` in `extension.rb` is `[Assemblies, Zones, Windows, Spaces, ThermalBridges, Shading, Climate, Certification, Programs]`. `stack.PACKAGES` now lists `PHX` and still not `honeybee_phhvac`. Run against the `PLANNING_IDS` pattern: a planted `P4-01`, `M01`, `P4-08b` and `M16` all pass the lint | Applied. Equipment registers after `Programs`. A1 stands as drafted. A4 stands without the Phase 3b ordering and must also catch the lettered stage id and the two-digit register ids |
| F23 | The pins moved: honeybee-ph 1.33.68 (was 1.33.65) and, as an optional `phx` test group that is not shipped, PHX 1.59.4. Run at 1.33.68: `RoomPhHvacProperties` has the methods F12 lists; `PhHotWaterSystem.recirc_temp` and `recirc_hours` have no setter and `number_tap_points` has one; no attribute of the class names a calculation method. [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135) is open | F12, F14 and F17 hold at the new pin, so D4-12 and D4-18 stand. The field lists in the three PRDs were read at 1.33.65 and were not re-read; P4-01 re-reads the ones its stages use |
| F24 | Spaces' reads changed in Phase 6 (`context/CONTRACTS.md`, "Translation sections and artifacts"; API 1.77). A Zone row carries `airflow_mode`, `by_program` until any of its Spaces stores a rate and `detailed` after; its `airflows` are null while By Program. Zone rows no longer carry `inheriting_count`; a `building_segments` row carries `by_program_zone_count`. Read in PHX 1.59.4 (`from_HBJSON/create_rooms.py`): a Space with no rate of its own takes its share of the Program's flow as both supply and extract | Applied as renames: F10, CONTRACTS section 4, P4-05 and M05 say "By Program" where they said "inherits". What the balance shows for a By Program Zone is D4-24 |
| F25 | The [Phase 6 handoff](../../archive/phase-06-program/STATUS.md#handoff-to-phase-7-mechanical) left open how a Space would name a ventilation unit of its own. Run at 1.33.68: a honeybee-ph `Space` has no ventilation or unit attribute. Read in PHX 1.59.4 (`from_HBJSON/create_rooms.py`): each Space takes `vent_unit_id_num` from its host Room's `ph_hvac.ventilation_system` | The stack has nowhere to put a unit per Space, and V1 already says two different units mean the Zone is split. Serves on the Zone is the whole of it; nothing is added for a Space. That handoff row is closed |
| F26 | Programs ships a Zone's assignment as a structured extension on the Zone record, `ph_composer.programs.zone_assignment`, not as a record of its own on the Zone Group (`context/CONTRACTS.md`, "Occupancy"). Programs writes it through Zones' proposal participant `ph_composer.zones.stage_extension`, which checks the payload with the namespace's validator and refuses as any Zone write does. The payload declares its references, so a named record refuses a plain delete as `reference.in_use`, and a delete with a replacement moves each payload in the same Undo step. The declaration admits `one` or `many` (`core/records/extension.rb`), but every reference Programs ships is `one`: no shipped payload exercises the in-use scan or the replacement move over a `many` reference. The payload travels with a copied Zone with no contributor. Declared `required` and claimed through `entity_projections`, it exports from Zones' own section | This is the shipped pattern for what D4-03 and D4-04 design differently: D4-21 |
| F27 | "Equipment Set" is now a shipped term of Programs: the kind `ph_composer.programs.equipment_set` with prefix `eqs_`, the field `equipment_set_id`, the operations `ph_composer.programs.equipment_sets.*` and the codes `programs.equipment_set_non_residential` and `programs.equipment_watts_residential`. This packet plans the feature id `ph_composer.equipment`, the code noun `equipment` and the prefix `eqa_`, on a tab named Mechanical | D4-22 |
| F28 | The Building Segment is the unit of export (`context/CONTRACTS.md`, "Building Segments at export"). A Zone in no Building Segment is left out with everything on it, and each owner notes `<noun>.zone_left_out` as info and skips its own findings inside that Zone. PHX merges a Segment's Rooms and writes one Variant per Segment. Programs refuses a Dwelling whose Zones lie in two Segments | Applied: `equipment.zone_omitted` becomes `equipment.zone_left_out` and follows that rule, read from the Zones projection's `exported`. What "for the building" means in D4-15 and D4-17, and an item that serves Zones in two Segments, is D4-23 |
| F29 | The model assembly now attaches at four hosts, `MODEL`, `SEGMENT`, `ROOM` and `FACE`, in that order (`context/CONTRACTS.md`, "Translation sections and artifacts"). A `SEGMENT` host is the one `BldgSegment` a Segment's Rooms share, changed in place | D4-09's question names three hosts. Its answer stands: a duct or pipe belongs inside equipment's object, which no host is. The Segment settings of F30 attach at `SEGMENT` |
| F30 | Phase 6 left three `BldgSegment` values to this phase (C4a-5 and its handoff): `set_points.mechanical_cooling`, `mech_room_temp` and `summer_ventilation`. Run at 1.33.68: they default to `False`, 20.0 and a `SummerVentilation` object with eleven fields (ventilation system, daytime and nighttime window and extract air changes, fan powers, the summer bypass mode and three nighttime controls). Read: honeybee_grasshopper_ph's Building Segment component takes `mechanical_cooling` and `mech_room_temp` as inputs (`gh_compo_io/building_segment.py`), and PHX 1.59.4 copies both to the Variant (`from_HBJSON/create_variant.py`). Programs' `SetPointSection.attach` sets `set_points.winter` and `.summer` in place and touches nothing else | Allocated to a new stage, [P4-08b](phases/p4-08b-segment-mechanical-settings.md), register row M16: a Building Segment settings section and its export, by the shipped seam (`context/EXTENSIBILITY.md`, "Building Segment settings"). Whether mechanical cooling is entered or derived is D4-26 |
| F31 | Both unit registries now carry `temperature`, `temperature_difference`, `power`, `power_per_area`, `airflow_per_person` and `airflow_per_area` (`core/units.rb`, `html/unit_tables.js`). Neither carries an electric-efficiency or a litre quantity | Applied: D4-11 and A3 shrink to `electric_efficiency` and `volume_l`. F9 is superseded |
| F32 | The tab row as shipped is Climate, Zones, Programs, Assemblies, Window Types, Thermal Bridges, Library, Export, then the reserved disabled Systems button (`html/index.html`). The row noted under "Recorded since" on 2026-11-17 put Programs after Thermal Bridges | A2 still turns the reserved button into the Mechanical tab (D4-13). Where it sits in the row is D4-27 |
| F33 | Every Program holds a Service hot water load and the Program export writes a `ServiceHotWater` on every ProgramType (`context/CONTRACTS.md`, "Programs, Schedules and Equipment Sets"; `program_sections.py`) | Part 3's open item 6 is closed: an exported Room always carries the load. PHX still reads hot water from the system, not from that load (Phase 6 F4a-11) |
| F34 | Phase 6 worked under Ed's standing guidance that there are no users and so no migrations: a schema that changes moves its version and the fixtures are rewritten ([Phase 6 CONTRACTS](../../archive/phase-06-program/CONTRACTS.md)). The Zone record moved to schema 3 that way | Part 3's open item 2 is closed: a later stage adds documentation fields by moving the kind's `schema_version` |
| F35 | Programs works out everything it exports in one pure Ruby plan (`ExportPlan`), which the preflight reads for the same findings, and its Python sections compute nothing beyond honeybee's own conversions (`context/CONTRACTS.md`, "Program export"; AGENTS.md's rule that domain calculations live in Ruby) | Applied to CONTRACTS sections 1 and 6: the tank slotting (D4-07) and the blended heat pump (D4-15) are pure Ruby, read by the preflight and carried to Python as values |
| F36 | `context/EXTENSIBILITY.md`, "Metadata and structured extension data", names "the future mechanical entities": each new entity keeps a `user_data` map, reads it with `extension_data` and `extension_status`, writes it through one guarded route, follows the lifecycle rules, carries it to its HBJSON object or leaves it out with `export.metadata_omitted`, and gains a row in `docs/USER_DATA.md` | Applied: CONTRACTS section 2 states the obligation and P4-02, P4-03 and P4-06 each gain the step |
| F37 | The installed-size baseline was reset to 26,093,959 bytes at Phase 6's entry, against a ceiling of 28,000,000 (`tools/runtime/vendor.py`). Phase 6 closed with 1,171,308 bytes under the ceiling, so the ceiling binds before the growth allowance does | Applied: P4-01 measures the installed size at entry, and P4-15 and M15 cite these keys in place of Phase 3b's baseline |
| F38 | Every Phase 6 export stage added a PHX round trip under `tests/python/test_*_phx_round_trip.py`, run in the `phx` group and skipped without it. This packet sends every PHX claim to metr-export, on the 2026-10-21 fact that PHX was not installed | D4-25 |
| F39 | Phase 6 shipped the Zones / Programs view: assignment per Zone on the Zones tab, over checked rows, under Building Segment heading rows, with the rows of a single dwelling locked | No change. Q10 keeps a Zone view of equipment for later, and D4-20 puts Serves on each table. P4-05's Zone picker lists Zones under their Building Segment headings as that view does, Zones in no Segment included, and offers a whole Segment at once |

### Decisions

As put to Ed. Each names what it revises. The answers follow the table.

| ID | Kind | Question | Recommendation | Would revise | Blocks |
| --- | --- | --- | --- | --- | --- |
| D4-21 | Code | Is Serves a record of its own on the Zone Group, as planned, or a structured extension on the Zone record, as Programs' assignment is (F26)? | The extension: `ph_composer.equipment.zone_serves` on the Zone record, a `one` reference for the Ventilator and Hot Water System slots and a `many` reference for each later family, written through `ph_composer.zones.stage_extension`, declared `required` and claimed by the equipment export. It retires the `eqa_` id, the Serves reference target, the Zone-copy contributor and CONTRACTS section 7's first question, and a copied Zone keeps what serves it with no code. Costs: every Serves write is a Zone record update, refused on a locked or shared Zone; the generic metadata routes can write the payload, so a rule that spans records is a finding there and a refusal only in equipment's own actions; and the `many` slots of the later families would be the first use of a `many` reference in a payload, which P4-01 proves by test before P4-03 leans on it | D4-03 and D4-04 in mechanism, not in outcome; F1 to F3 | P4-01, P4-03 |
| D4-22 | Code | Does the feature keep the name `ph_composer.equipment` beside Programs' Equipment Sets (F27)? | No: `ph_composer.mechanical`, the code noun `mechanical`, the folders `features/mechanical/` and `html/features/mechanical/`, matching the tab. "Equipment" stays a glossary word for the records together. Nothing is built, so the rename costs only this packet's documents | The name in D4-02; its answer, one feature, stands | P4-01, P4-02 |
| D4-23 | Code | A Building Segment exports as its own Variant (F28). What is "the building" for the blended heat pump (D4-15) and the hot water pooling note (D4-17), and may one item serve Zones in two Segments? | Per Building Segment. The blend is worked out once per exported Segment, from the outdoor equipment whose indoor units serve that Segment's Zones. The pooling note reads per Segment. An item serving Zones in two Segments is allowed, as honeybee-ph allows one object on any Rooms, with a non-blocking finding that each Segment's file carries the whole item | D4-15 and D4-17, by making them exact | P4-06, P4-08 |
| D4-24 | UI, Code | What does the balance by ventilator show for a served Zone that is By Program (F24)? | The Program's flow for that Zone, counted as both supply and extract, which is what PHX writes. A new Model is a single dwelling on the residential default, so every Zone starts By Program and a dash would be the usual reading. It makes the Serves half of the feature read `ph_composer.programs.zones` and require Programs. Until answered the binding is the handoff's: a dash while any served Zone is By Program | Q11 and D4-10, by extending them | P4-05 |
| D4-25 | Scope | PHX is installed for tests (F38). Do this phase's export stages prove what PHX builds from the HBJSON? | Yes. Each export stage adds a PHX round trip in the `phx` group, as Phase 6's did: one device for an item on several Rooms, tanks and heaters once, exhaust and supportive devices through a Room's Spaces. Opening the file in METr and every METr field claim stay metr-export's | The split in PLAN, ACCEPTANCE and CONTRACTS section 7 that sends every PHX claim to metr-export | P4-04, P4-06 and every later export stage |
| D4-26 | Code, UI | Is mechanical cooling entered on the Building Segment or derived from the heat pumps that serve it (F30)? | Entered, as honeybee-ph's Grasshopper component has it: a switch in a Mechanical section of the Segment settings, off by default, beside the mechanical room temperature at 20 °C. A non-blocking finding when the switch and the blended heat pump's cooling disagree. Summer ventilation has eleven fields and gets its own interview | | P4-08b |
| D4-27 | UI | Where does the Mechanical tab sit in the row as shipped (F32)? | After Thermal Bridges: Climate, Zones, Programs, Assemblies, Window Types, Thermal Bridges, Mechanical, Library, Export | The order noted on 2026-11-17 | P4-05 |

### Ed's answers, 2026-11-22

Ed approved D4-21 to D4-27 together on 2026-11-22, every one as recommended. A row here
supersedes the recommendation above; none differs. Each also supersedes the earlier answer it
names, which stays in Parts 2 and 3 as the record of what was first decided.

| ID | Answer | Supersedes | Date |
| --- | --- | --- | --- |
| D4-21 | As recommended: Serves is a structured extension on the Zone record, written through `ph_composer.zones.stage_extension`, with no id, target or Zone-copy contributor of its own | The mechanism of D4-03 and D4-04. Their outcome stands: one set of slots per Zone, and a copied Zone keeps what serves it | 2026-11-22 |
| D4-22 | As recommended: the feature is `ph_composer.mechanical`, its code noun `mechanical`, its folders `features/mechanical/` and `html/features/mechanical/`. "Equipment" stays the glossary word for the records together, so the `equipment/` feature packet and the stage file names keep it | The name in D4-02. One feature stands | 2026-11-22 |
| D4-23 | As recommended: the blended heat pump and the hot water pooling note are per Building Segment; an item may serve Zones in two Segments, with a non-blocking finding | Makes D4-15 and D4-17 exact | 2026-11-22 |
| D4-24 | As recommended: a By Program Zone counts its Program's flow as both supply and extract in the balance; the feature requires Programs | Extends Q11 and D4-10 | 2026-11-22 |
| D4-25 | As recommended: each export stage adds a PHX round trip in the `phx` test group; the METr file and its import stay metr-export's | The 2026-10-21 split that sent every PHX claim to metr-export | 2026-11-22 |
| D4-26 | As recommended: mechanical cooling is entered on the Building Segment, off by default, beside the mechanical room temperature at 20 °C, with a non-blocking finding when it disagrees with the blended heat pump's cooling. Summer ventilation is interviewed on its own | | 2026-11-22 |
| D4-27 | As recommended: the Mechanical tab sits after Thermal Bridges and before Library | The order noted on 2026-11-17 | 2026-11-22 |

What the answers leave to the stages, none of it a new question for Ed:

- D4-21: no shipped payload holds a `many` reference (F26). P4-01 proves the in-use scan, the
  replacement move and the Zone copy over one before P4-03 builds on it.
- D4-21: the feature's actions stage a whole payload and never remove one, so "served by
  nothing" has two stored forms, no payload and a payload with every slot empty. The reads treat
  them as one.
- D4-21: the payload is `local_only` in P4-03 and becomes `required` in P4-04 with the export
  claim, since a `required` namespace with no claim blocks every export (Programs did the same
  between its P4a-08 and P4a-10).
- D4-24: the balance adds a `ph_composer.programs.zones` read to the Ventilators snapshot, a read
  whose cost Phase 6 logged as a follow-up. P4-05 takes it once per snapshot.
- D4-26: the eleven summer ventilation fields wait for their interview, which gates P4-08b.

### Part 3's open items, restated

All six items from Part 3 are now closed: items 2 and 6 on 2026-11-22 (F34, F33), items 1, 3 and 4 on 2026-11-23 (D4-28 to D4-30), and item 5 on 2026-11-23 (D4-33 to D4-35).

## Part 5: kickoff review and remaining interviews, 2026-11-23

Answered by Ed on 2026-11-23 before kickoff. Findings continue from F39 and decisions from D4-27.

### Findings

| # | Finding | Consequence |
| --- | --- | --- |
| F40 | Run at PHX 1.59.4 (`PHX/to_WUFI_XML/_bug_fixes.py:10`, `split_cooling_into_multiple_systems`, called from `hbjson_to_wufi_xml.py:265`): PHX already splits cooling capacity above WUFI-Passive's 200 kW per-device cap when writing WUFI XML; METr has no such cap | PH-Composer exports one blended `PhHeatPumpRatedMonthly` per Building Segment with the full cooling capacity and never splits it (D4-29) |

### Decisions

| ID | Kind | Question | Answer, 2026-11-23 | Blocks |
| --- | --- | --- | --- | --- |
| D4-28 | UI, Code | `Heat Pumps › Equipment · Indoor` columns (Part 3 open item 1) | Identity columns only (`Tag`, `Manufacturer`, `Model`, `Notes`) for v1, consistent with D4-20 and F15 | P4-08 |
| D4-29 | Code | Heat pump blend edge cases: `min_coil_temp` and cooling > 682 kBtu/h (200 kW) (Part 3 open item 3) | Fixed default `min_coil_temp = 12.0 °C` in v1 (recorded as verified against the estimator in the private test; the estimator holds 45 °F, and Ed confirmed 12.0 °C knowing it on 2026-11-24, as the note below the table says). No split above 200 kW in PH-Composer or HBJSON: export one blended system per Building Segment with full capacity and let PHX handle the WUFI-XML split downstream (F40), with an optional non-blocking info note on export | P4-08 |
| D4-30 | UI | Undrawn UI details (`Units · Outdoor` columns, row actions, New-record forms, Ventilator optional-field disclosure, 360 × 520 layout; Part 3 open item 4) | Skip additional static wireframes; build directly from the shipped UI kit patterns (`inventory.js`, `record_form.js`, collapsed per-row disclosure, responsive kit rules) and verify under `ph-composer-ui-polish` | P4-05, P4-07, P4-08 |
| D4-31 | Scope | Host-gate cadence (`PLAN.md`) | Batch SketchUp host gates by milestone (`MS1` after P4-04, `MS2` after P4-07, `MS3` after P4-14/P4-15), with full offline `make ci` and PHX round trips on every stage PR | P4-01 to P4-15 |
| D4-32 | UI, Code | `P4-08b` Summer ventilation fields on Building Segment | Expose the 4 core fields (`summer_bypass_mode` default `4-Always`, `ventilation_system_ach` default blank/`None`, `daytime_window_ach` default `0.0`, `nighttime_window_ach` default `0.0`). Omit the 7 extract-system/night-flush fields from the v1 UI and export honeybee-ph defaults | P4-08b |
| D4-33 | UI, Code | `P4-09` Electric heaters (Family 4) | `Tag`, `Coverage (%)` (`0.0–1.0` stored, `0–100%` displayed, default `100%`), `Serves` (`many` slot `heater_ids`), hideable `Manufacturer`, `Model`, `Notes`. No cross-family heating-coverage-sum validation in v1 | P4-09 |
| D4-34 | UI, Code | `P4-10` Pumps (Family 5, `PhSupportiveDevice`) | Offer all four `device_type` values (`4` heat circ, `6` DHW circ [default], `7` DHW storage load, `10` other). Keep `ihg_utilization_factor` (`1.0`) and `ihg_usage_profile` (auto-seeded from `device_type`) editable behind a collapsed per-row disclosure. Emit a non-blocking finding if a Pump serves a Zone with no Spaces | P4-10 |
| D4-35 | UI, Code | `P4-11` Fans (Family 6, exhaust ventilator + linked supportive device) | Default `Type` to `User-defined` (all three kinds offered: `Kitchen hood`, `Dryer`, `User-defined`). Put `Power (W)` on the row (blank = no linked supportive device), auto-derive `annual_period_operation_khrs` from `annual_runtime_minutes / 60,000`, and tuck `In conditioned space` (default `true`) + optional runtime override (`khrs`) behind a collapsed per-row disclosure. Emit a non-blocking finding if a Fan serves a Zone with no Spaces | P4-11 |
| D4-36 | Code, UI | `P4-13` Hot water piping interview (`hot-water-piping/PRD.md`, Q1–Q13) | Confirmed all as recommended: tree by vertex connection (no edge registry), native Line tool in Piping groups (outside Zone groups, multiple groups per Hot Water System), Pipe Type = spec only (with insulation, Model-local), nominal METr diameter dropdown (`diameter_mm`), `Pipe-Segment` and `Twig` on screen, trunk `multiplier` exposed; Q5/Q12 already settled by H5/D4-12 and D4-13 | P4-13 |
| D4-37 | Code, UI | `P4-14` ERV ducting interview (`erv-ducting/PRD.md`, Q1–Q9) | Confirmed all as recommended: two cold runs only (between ventilator and exterior, labeled clearly), `Outdoor air` / `Exhaust air` labels on screen, direction on the edge/line, repeated units by both group copy and run `quantity`, native Line tool in Ducting groups outside Zone groups, Duct Types Model-local, two cold-duct length columns contributed to the Ventilators table via `table_contributions.js`; Q8 already settled by D4-13 | P4-14 |

Note on D4-29, 2026-11-24: P4-08 found that the Phius estimator's `Inputs for Energy Model` holds a constant 45 °F (7.2 °C) minimum coil temperature in v25.1.1 and v25.1.2, not the 12.0 °C D4-29 records as verified ([p4-08 evidence](evidence/p4-08-heat-pumps.md)). Ed confirmed 12.0 °C on 2026-11-24 knowing that difference ("Keep 12.0 °C"). The code writes 12.0 °C and does not change.

## Part 6: hold 2 review, 2026-11-27

Answered by Ed on 2026-11-27 after the second MS3 full-screen hold ([MS3 evidence](../../native-acceptance/evidence/phase-07-ms3.md),
[MS2 evidence](../../native-acceptance/evidence/phase-07-ms2.md)). Findings continue from F40 and decisions from
D4-37. Every answer was the recommendation.

### Findings

| # | Finding | Consequence |
| --- | --- | --- |
| F41 | `UXR-COLOUR` was written on 2026-10-07; [#286](https://github.com/bldgtyp/ph-composer/pull/286) (2026-10-21) made a paint tool lease its Colour-by mode and give the prior mode back when it stops ([contributor architecture](../../../context/EXTENSIBILITY.md), "Give the Colour-by mode back"). Hold 2 read exactly the lease: Escape after painting from Off left Off; from Boundary, Boundary; Assembly paint started from Boundary, Boundary; a Face type override picked mid-paint survived | The case text, not the build, is out of date (D4-38) |
| F42 | A planar recirculation loop closes into a Face SketchUp fills automatically; Make then refuses `target.wrong_kind` ("A selected line bounds a Face", `line_groups/make.rb`), naming the cause and not the fix. M13e passed only with a hand-erase step outside its recipe | Any planar loop or ring main meets it (D4-39) |
| F43 | The 360 × 520 panel at (1628, 245) painted blank and reported `visibilityState` hidden; the same size at (900, 245) rendered. `document.hidden` is true while the host window is occluded ([measured host behavior](../../../context/SKETCHUP_HOST_BEHAVIOR.md)), and viewport clicks had sent the panel behind the model window, whose frame holds the whole 360 × 520 panel at that position | A capture artifact, not a product defect (D4-40) |
| F44 | Since [#410](https://github.com/bldgtyp/ph-composer/pull/410) (2026-11-09) a pasted or added plain Group copy is given its own contents at once, joined to the paste (`features/zones/zone/copied_groups.rb`), so `ZO-O7`'s copied-Group refusal cannot be reached through a native copy. Hold 2 read the copy with a new Zone id at once. A labelled bridge `active_path=` into a component placement then crashed SketchUp 26.1 inside its own notification code, with no PH-Composer frames above it | The clause describes the state before #410, and the rerun opens placements natively (D4-41) |
| F45 | Hold 2 UI findings: line groups named by persistent id ("Piping group 49013"); every new Pipe Type and Duct Type takes one default colour; the Ventilator delete dialog does not name the Ducting groups it leaves unlinked; the `session.busy` refusal prints the host's internal tool name ("The SketchTool tool is in use", `shell/context_commands.rb`); "Zone Zone A" when a Zone is named "Zone A"; the pipe-assign tool misses a line clicked 4 px off it; the Make reason icon wraps onto its own line at 1280 px | D4-42 to D4-48 |

### Decisions

| ID | Kind | Question | Answer, 2026-11-27 | Blocks |
| --- | --- | --- | --- | --- |
| D4-38 | Scope | `UXR-COLOUR` `escape-retains-boundary` and `assembly-stop-retains` fail against text older than #286 | Rewrite both clauses to the lease contract (stopping restores the mode from before painting unless the user picked another meanwhile) and rerun them at the next sitting. The hold 2 fail rows stand; the readbacks are not re-graded against text written after the run | next sitting |
| D4-39 | Code, UI | Make on lines SketchUp closed into a Face | Make erases every Face whose edges are all among the selected lines, in the same Undo step, and reports the count ("Removed 1 Face the lines closed"). A Face with any unselected edge still refuses, and the message names the fix (erase the Face, keep its lines, Make again). Make never touches geometry outside the selection. M13e's recipe drops its hand-erase step | follow-up PR, M13e and M14f rerun |
| D4-40 | Scope | The blank 360 × 520 panel | Closed as a capture artifact. Hold recipes bring the panel forward (Extensions > Open PH-Composer) before a panel capture that follows a viewport click; it reopens only if it recurs with the panel known to be in front | none |
| D4-41 | Scope | `ZO-O7` `component-copy-shared` and the crash | Rewrite the Group half: a pasted or added Group copy reads a new Zone id at once, one Undo removes the paste, the original is unchanged. The component half is unchanged (shared by design, refused, Explode, then independent). Placements are opened natively (Edit Component or a double-click), never by a bridge `active_path=`. The whole case reruns from a fresh process | next sitting |
| D4-42 | UI, Code | Line group names | The first free number per kind: "Piping group 1", "Ducting group 2", as Building Segments take "Building Segment N" | follow-up PR |
| D4-43 | UI, Code | Pipe Type and Duct Type colours | Each new type takes the next unused colour of the categorical palette; clearing a colour returns the type to its assigned one | follow-up PR |
| D4-44 | UI | The Ventilator delete dialog | Names the Ducting groups it leaves unlinked ("Ducting group 2 will lose its Ventilator."), capped with "and N more" | follow-up PR |
| D4-45 | UI, Code | The `session.busy` tool name | Map host tool names to SketchUp's menu names ("The Line tool is in use…"); an unmapped name reads "A SketchUp tool is in use…" | follow-up PR |
| D4-46 | UI | The doubled kind word | Quote the user's name after the kind: Zone “Zone A” | follow-up PR |
| D4-47 | UI, Code | Pipe-assign pick reach | Measure the native Select tool's pick aperture on the host and use the same, so the tool picks what Select would | follow-up PR, host measurement |
| D4-48 | UI | The Make reason icon at 1280 px | The icon stays beside the reason; the reason text wraps | follow-up PR |
| D4-49 | UI | A panel reset for type colours: a null `color` returns a Pipe or Duct Type to its `assigned_color` (D4-43), but only through the API; Codex raised the missing panel reset twice on #604 | The shared colour picker offers **Reset to default** for a record whose kind names a default colour, shown only while the stored colour differs from it; it writes `color: null` through the record's own update, one Undo step. A kind with no default shows no reset. Pipe Types and Duct Types name their `assigned_color`; Thermal Bridge Types and Assemblies fall back to a colour by id that their reads do not expose, so they show none until a read carries it | follow-up PR |

## Part 7: closeout decisions, 2026-11-27

Answered by Ed on 2026-11-27, each as recommended: the fifteen decisions [P4-15's evidence](evidence/p4-15-acceptance.md)
lists under "For Ed", read again against `main` at `6cad268e`, and the wording of `M01`. Decisions continue from
D4-49; "For Ed N" is that list's number. D4-53 to D4-62 and D4-64 keep what the stages built as inferred. D4-63 is
the one change to the product.

| ID | Kind | Question | Answer, 2026-11-27 | Blocks |
| --- | --- | --- | --- | --- |
| D4-50 | Code | For Ed 1: the installed-size baseline and limits, now that Phase 7 has used the headroom. `main` at `6cad268e` was put to Ed at 27,987,931 bytes installed, about 12 KB under the 28,000,000-byte ceiling; Phase 7 grew the extension 1,146,123 bytes from the 26,841,808 at P4-01's entry | Baseline 27,987,931, ceiling 30,000,000, growth allowance unchanged at 2,500,000 (`tools/runtime/vendor.py`, the runtime manifest regenerated). The ceiling stays the nearer limit, 2,012,069 above the baseline. D3a-20 and D4c-33 each raised it by 2,000,000. Keeping one copy of the repeated licence text (about 173 KB) is a follow-up | the closeout PR, before the final sitting |
| D4-51 | Scope | For Ed 2: which stale cases outside M01 to M16 the final sitting repeats. On `6cad268e`, 70 name a path Phase 7 changed: the 48 in P4-15's table and 22 more since #592 | `PG03`, `S10` and `T05` only, the cases whose observed behaviour Phase 7 changed: Spaces' export projection leaves out the Spaces of a Zone in no Building Segment (`features/spaces/export.rb`), and the shared Delete dialog and inventory table gained combined usage, Clear per record and a blocked state (`html/inventory_forms.js`, `html/inventory.js`). The others stay `needs_recheck` with their last outcome, screened by dependency path, the reason recorded in [P4-15's evidence](evidence/p4-15-acceptance.md). `M15`'s last clause names the three | final sitting |
| D4-52 | Scope | For Ed 3: what "the same HBJSON" means when a saved Model is reopened and exported again. Two exports of one Model from two Python processes have the same length and differ in two places only: the random identifiers honeybee-ph gives objects the export never names (`uuid4` in its `_base.py`), under `properties.ph.bldg_segments` and `properties.ph.team`, and the order of the lists under `properties.energy`, which honeybee-energy builds from sets. Everything under `rooms` is identical | Compared by section, read from the two files: `rooms` exact, honeybee-ph's random identifiers masked, the `properties.energy` lists compared as sets. The case texts of `M04`, `M06`, `M08` to `M11`, `M13d`, `M14e` and `M16` say so. `M10`'s recorded swap came from a readback helper that reloaded the file and dumped a Python set, not from the export (honeybee-phhvac sorts a Room's supportive devices by identifier), so `M10` reruns with a file-level compare. Whole-file equality, with deterministic identifiers and sorted lists, is a follow-up candidate | case text; final sitting |
| D4-53 | Code | For Ed 4: a duct run of quantity N exports as N identical elements | Keep. honeybee-ph's `PhDuctElement` has no quantity and PHX's `PhxDuctElement.quantity` always reads 1, so N elements is what a Grasshopper model of N identical ducts carries. A quantity on the element is an upstream change | none |
| D4-54 | Code | For Ed 5: whether a Ventilator's Quantity multiplies its ducts | Keep: the ducts drawn for a Ventilator are one unit's and its Quantity does not multiply them, as honeybee-ph and PHX read the pair. A run's own quantity is where repeated ducts are entered | none |
| D4-55 | Code | For Ed 6: a large duct quantity multiplies the HBJSON, each element once per served Room | Keep the 10,000 cap (`features/ducting/assignment/schema.rb`). An element is about 450 bytes per served Room | none |
| D4-56 | UI | For Ed 7: what Locate selects for `ducting.group_unlinked` | Keep: it opens the group and selects that run's ducts, as piping's group findings do. The group is relinked in the panel's groups table | none |
| D4-57 | Scope | For Ed 8: a pipe tree lives in one Piping group, so a riser group with per-floor branch groups does not export | Keep one tree per Piping group for Phase 7. A riser taking branches drawn in other groups is a follow-up feature | none |
| D4-58 | Code | For Ed 9: recirculation temperature and hours, and a trunk's multiplier and demand recirculation, sit on the pipe assignment | Keep: it is honeybee-ph's own record shape (`PhHvacPipeSegment` and `PhHvacPipeTrunk`) | none |
| D4-59 | Code | For Ed 10: the Systems table's recirculation columns moved from Mechanical's read to piping, removing a shipped API field | Keep: nothing outside the repository depends on the field yet | none |
| D4-60 | Code | For Ed 11: the Hot Water System and Ventilator deletes route other features' references through `request.retarget_references` | Keep: it is the seam Assemblies, Window Types, window products and Programs use | none |
| D4-61 | Code | For Ed 12: three Phius estimator expressions kept as written in the heat pump blend (`features/mechanical/heat_pumps/blend.rb`) | Keep the blend faithful to the Phius estimator v25.1.2, the workbook a Phius reviewer checks the inputs against | none |
| D4-62 | Code | For Ed 13: which defaults summer ventilation's omitted values export (D4-32) | Keep honeybee-ph's class defaults. PHX 1.59.4 reads the values and writes only the bypass mode to WUFI-Passive, METr and PHPP, so neither choice changes a result today. Revisit when PHX writes the others | none |
| D4-63 | Code, UI | For Ed 14: an Electric Heater serving a Zone with no Spaces has no finding of its own | Change: an Electric Heater raises the non-blocking `mechanical.zone_without_spaces` that Pumps and Fans raise (D4-34, D4-35), because PHX reads heating systems through a Room's Spaces as it reads their devices (API 1.112). Heat pumps, tanks and hot water heaters are read the same way and are left as a follow-up | the closeout PR; `M09` at the final sitting |
| D4-64 | Scope | For Ed 15: PHX 1.59.4 drops an exhaust ventilator's quantity, so WUFI-Passive and METr see one exhaust device per Fan | Keep PH-Composer's export, which sets the quantity on both honeybee-ph objects. Filed upstream as [PH-Tools/PHX#177](https://github.com/PH-Tools/PHX/issues/177); when it is fixed, bump the pin and assert the quantity in the Fan round trip | none |
| D4-65 | Scope | `M01`'s load-order clause cannot be observed on the host: the export status and diagnostics record no module loads, and the case text ruled out the offline probe that covers it | The clause moves to offline evidence: the `hvac_seam` probe of `tools/runtime/browser_check.py --translation`, which loads `honeybee_ph` and then `honeybee_phhvac` through `stack.load` in the shipped Pyodide page under Chromium 88 and reads a Room's `ph_hvac` ([p4-01-contracts](evidence/p4-01-contracts.md)). The host case keeps the export in the host's runtime and the reload of both Rooms' `ph_hvac`, and reruns over the bridge | case text; final sitting |

## Ledger

| Date | Event |
| --- | --- |
| 2026-10-21 | Drafted from `420c783a` and the three interviews of the same day: fourteen findings, twelve decisions. None answered. |
| 2026-10-21 | Ed answered D4-01 to D4-12, all as recommended. The bindings in CONTRACTS stand as drafted. |
| 2026-11-15 | Wireframe review with Ed: findings F15 to F19, decisions D4-13 to D4-20 (Part 3). D4-08 and the interview answers Q4 (heat pumps), Q9, H1, H4 and H7 are revised. Bindings and stages not yet re-planned. |
| 2026-11-17 | F20 recorded (what the estimator reads from climate) and the tab row's order noted, both from the [Climate packet](../../archive/phase-04-climate/PRD.md), which is now Phase 4 and precedes this phase. |
| 2026-11-22 | Reviewed against `main` at `8c710412` after Phase 6 was archived (Part 4): findings F21 to F39, the settled ones applied to the packet; decisions D4-21 to D4-27 opened, none answered. Part 3's open items 2 and 6 closed. |
| 2026-11-22 | Ed answered D4-21 to D4-27, all as recommended. CONTRACTS, ACCEPTANCE, PLAN and the stage documents re-bound to them: Serves as a payload on the Zone record, the feature renamed `ph_composer.mechanical`, the Building Segment as the scope of the blend, the balance reading Programs' flow, PHX round trips in the export stages, mechanical cooling entered, the tab after Thermal Bridges. |
| 2026-11-23 | Kickoff review and remaining interviews (Part 5): F40 verified in PHX 1.59.4; Ed answered D4-28 to D4-37 (Part 3 open items closed, host gates batched by milestone, and all remaining interviews complete: summer ventilation, electric heaters, pumps, fans, hot water piping and ERV ducting). |
| 2026-11-24 | Ed confirmed D4-29's 12.0 °C minimum coil temperature, knowing the estimator holds 45 °F (7.2 °C) (the note under D4-29). No code change. |
| 2026-11-27 | Hold 2 review (Part 6): findings F41 to F45; Ed answered D4-38 to D4-48, all as recommended. Two case texts (`UXR-COLOUR`, `ZO-O7`) are rewritten for the next sitting; D4-39 and D4-42 to D4-48 go to one follow-up PR. |
| 2026-11-27 | Ed answered D4-49 (Part 6): Reset to default in the shared colour picker for Pipe Types and Duct Types, in its own PR stacked on #604. |
| 2026-11-27 | Closeout decisions (Part 7): Ed answered D4-50 to D4-65, all as recommended. D4-50 resets the installed-size baseline and raises the ceiling; D4-63 adds the no-Spaces finding for Electric Heaters; D4-51, D4-52 and D4-65 set the final sitting's cases and their text; the rest keep what was built. |
