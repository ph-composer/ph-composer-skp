# Phase 4, mechanical: findings from source, and the decisions that follow

DATE: 2026-10-21
STATUS: Scoped. Part 1 is findings read from source on `main` at `420c783a` and the honeybee-ph and PHX checkouts on 2026-10-21. Part 2 was answered by Ed on 2026-10-21, every row as recommended; see "Ed's answers". The interviews (Q1 to Q12, V1 to V6, hot water H1 to H7) are answered and live in the equipment PRD. Part 3 records the wireframe review of 2026-11-15: findings F15 to F19 and decisions D4-13 to D4-20, several revising earlier answers.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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
| F9 | `core/units.rb` has `airflow`, `volume`, `heat_loss_rate`, `conductivity`, `length` and no electric-efficiency, litre or temperature quantity; the panel registry has 18 quantities (units STATUS) | A3 adds what V4 and the tank fields need |
| F10 | Spaces' `ph_composer.spaces.all` `zones` rows carry `airflows` (null while any Space inherits), `inheriting_count` and `imbalanced`, and `Spaces::Metrics.imbalanced?` is the 10 percent rule | The balance by ventilator sums those rows per served Zone and reuses the rule (D4-10) |
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
| F18 | honeybee_grasshopper_ph builds one `PhHotWaterSystem` and sets the same instance on each chosen Room (`gh_compo_io/shw/create_system.py`, `apply_shw.py`), and gives a Room with no service hot water load a nominal one. PHX adds each tank and heater once by key, sets tap points from the last Room read without summing, and keeps one recirculation setting (`from_HBJSON/create_variant.py`, read from the PHX checkout) | One System record serving Zones is the stack's own shape (D4-17). Several Systems pool downstream. The nominal hot water load is a [Phase 4a](../phase-06-program/README.md) question |
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
Programs, Mechanical, Library, Export.

### Open after the review

1. Equipment · Indoor. Ed first chose PH-Navigator's full column set, then answered D4-20
   (identity and export fields only). The wireframe draws identity only, since F15 leaves nothing
   on an indoor model to export. Ed has not confirmed that reading.
2. D4-20 asks that kinds accept added fields. CONTRACTS section 2 fixes each kind at
   `schema_version` 1 with its final field set because the engine has no migrations. How a later
   stage adds documentation fields is unanswered.
3. The HSPF conversion and the climate derating are not written. Every derived number on the
   Blended result wireframe is a placeholder. The cooling coil temperature shown is honeybee-ph's
   default and was not checked against the estimator, and the estimator's split above 682 kBtu/h
   has no agreed handling.
4. Not drawn: Units · Outdoor's columns, row actions, the New-record forms, the Ventilator
   disclosure for the two optional fields (V3), and the 360 x 520 panel size.
5. Pumps, Fans and Electric Heating have their table shape and columns from D4-13 and D4-20.
   Their interviews are otherwise open; Q6 still describes the Fan record.
6. A served Room needs a service hot water load before its system means anything downstream
   (F18). Phase 4a owns loads.

## Ledger

| Date | Event |
| --- | --- |
| 2026-10-21 | Drafted from `420c783a` and the three interviews of the same day: fourteen findings, twelve decisions. None answered. |
| 2026-10-21 | Ed answered D4-01 to D4-12, all as recommended. The bindings in CONTRACTS stand as drafted. |
| 2026-11-15 | Wireframe review with Ed: findings F15 to F19, decisions D4-13 to D4-20 (Part 3). D4-08 and the interview answers Q4 (heat pumps), Q9, H1, H4 and H7 are revised. Bindings and stages not yet re-planned. |
| 2026-11-17 | F20 recorded (what the estimator reads from climate) and the tab row's order noted, both from the [Climate packet](../../archive/phase-04-climate/PRD.md), which is now Phase 4 and precedes this phase. |
