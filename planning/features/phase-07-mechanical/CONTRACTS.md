# Phase 4 contract bindings: mechanical equipment

DATE: 2026-10-21
STATUS: Scoped. Re-bound on 2026-11-23 to the wireframe decisions (D4-13 to D4-20), the Programs review (D4-21 to D4-27) and the kickoff review (D4-28 to D4-37). P4-01 answered the questions in section 7 by test on 2026-11-23 and recorded the answers, the corrections they made and the architecture review in section 8. Families 4 to 6, Segment mechanical settings, piping and ducting are interviewed (D4-32 to D4-37) and bind their exact field tables when their stage documents are written in full.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

The [equipment PRD](equipment/PRD.md) defers exact names and schemas to its plan. This file is
that binding, the counterpart of Phase 3b's [thermal-bridge bindings](../../archive/phase-03b-thermal-bridges/CONTRACTS.md)
and Phase 3a's [Spaces bindings](../../archive/phase-03a-spaces/CONTRACTS.md). It restates no
behavior. Where a row and the PRD disagree about behavior, the PRD wins and this file is corrected.
Where a row follows a decision in [DECISIONS.md](DECISIONS.md), it names the decision; D4-01 to
D4-12 were answered as recommended on 2026-10-21 and D4-21 to D4-27 on 2026-11-22. Interview answers are cited as the PRD numbers them: Q1 to Q12 (shared shape), V1 to
V6 (Ventilators) and hot water H1 to H7. A bare `H` number below with "hot water" in front is the
interview; the foundation additions of this packet are numbered A1 onward to avoid the clash with
the Spaces and thermal-bridge H1 to H18.

`context/CONTRACTS.md` owns the foundation mechanics these bindings sit on: registration, the
public interface, outcomes, revisions, retries, records and translation sections. Read it first.
Paths below are relative to `src/ph_composer/`.

Rows marked **new** do not exist yet. Rows marked **exists** were read in source at `420c783a`;
the ones this file's 2026-11-22 corrections touch were re-read at `8c710412`.
P4-01 confirmed the names against the code on 2026-11-23 (section 8); a stage may rename one only by editing this
file in the same change.

## 1. Feature and composition

| Feature id | Folder | Requires | Registered in |
| --- | --- | --- | --- |
| `ph_composer.mechanical` (new; D4-22), Ruby module `Mechanical` | `features/mechanical/` | `ph_composer.zones`, `ph_composer.spaces` (D4-02, D4-10); `ph_composer.programs` from P4-05 (D4-24); `ph_composer.climate` from P4-08 (D4-15) | `FEATURES`, last, after Programs (F22): `[Assemblies, Zones, Windows, Spaces, ThermalBridges, Shading, Climate, Certification, Programs, Mechanical]` |

One feature for the six families (D4-02, from Q1; the seventh, appliances, is Programs' Equipment
Sets). It is named for its tab (D4-22): "equipment" stays the glossary word for its records
together, and Programs owns the term Equipment Set. Two layers inside it: the family kinds are
layer 1 definitions that validate without a Zone (the Zone child pattern's "definition values and
rules"); Serves is layer 3, a payload on a Zone record. A test holds the line from
P4-02: nothing under `features/mechanical/<family>/` names Zones, Spaces, Programs, the Zone
record or `serves/`. Nothing under another feature's folder names this one.

Proposed layout, following `features/windows/install.rb` and `features/spaces/install.rb`:

```
features/mechanical/
  install.rb  codes.rb  refuses.rb  snapshot.rb  export.rb  colour_modes.rb
  ventilators/   schema.rb  operations.rb  reads.rb
  hot_water/     systems.rb  heaters.rb  tanks.rb  operations.rb  reads.rb  slotting.rb  (three flat kinds, D4-17; slotting pure, D4-07; built in P4-06)
  export_zones.rb  ventilation_plan.rb  export.rb  hot_water_plan.rb  hot_water_export.rb  preflight.rb  (P4-06: the shared Zone read, one preflight)
  heat_pumps/    outdoor_equipment.rb (both models)  units.rb (both units)  operations.rb  reads.rb  blend.rb  (four flat kinds, D4-14; blend pure, D4-15, F35; built in P4-08)
  catalog_operations.rb  heat_pump_plan.rb  heat_pump_reads.rb  heat_pump_export.rb  (P4-08: the CRUD every flat catalog shares, the per-Segment plan, the reads that name Serves, the export)
  electric_heaters/  schema.rb  reads.rb  (one flat kind, D4-33; its CRUD is CatalogOperations; built in P4-09)
  electric_heater_plan.rb  electric_heater_export.rb  (P4-09: the per-pair plan and the export)
  pumps/  schema.rb  reads.rb  (one flat kind over PhSupportiveDevice, D4-34; its CRUD is CatalogOperations; built in P4-10)
  pump_plan.rb  pump_export.rb  (P4-10: the per-pair plan, the no-Spaces finding and the export)
  serves/        payload.rb  operations.rb  reads.rb  balance.rb               (payload: the extension and its validator, D4-21)
  declarations/  shapes.rb  ventilators.rb  hot_water.rb  heat_pumps.rb  electric_heaters.rb  pumps.rb  serves.rb
  <family>/      one folder per later family, bound by its stage
html/features/mechanical/
  section.js  subtabs.js  ventilators.js  hot_water.js  heat_pumps.js  heat_pump_units.js  heat_pump_blended.js  electric_heaters.js  pumps.js  optional_values.js  serves.js  mechanical.css
python/ph_composer_translation/
  mechanical_sections.py       (ventilation, hot water, heat pump, electric heater and pump sections; later families add theirs)
  contract/mechanical_records.py
```

`serves/balance.rb` is pure: it takes detached Zone rows (the Spaces sums and, for a By Program
Zone, Programs' flow, D4-24) and the Serves rows and returns each Ventilator's supply, extract and
imbalance, so the read and offline tests share one function.

Every value the export derives is worked out the same way, in pure Ruby over plain records, read
by the preflight for its findings and carried to the Python section as a value: the tank slots
(D4-07) and the blended heat pump (D4-15). The Python sections build honeybee-ph objects and
compute nothing beyond its own conversions, as Programs' export does (F35).

Every record this feature adds meets the metadata obligation `context/EXTENSIBILITY.md` sets for
mechanical entities ("Metadata and structured extension data"): a `user_data` map, read with
`extension_data` and `extension_status`, written through one guarded route, kept through
Duplicate, Undo and a Zone copy, and at export either carried to the record's own honeybee-ph
object or left out with `export.metadata_omitted`; and a row in `docs/USER_DATA.md` (F36). At the pinned 1.33.68
`PhHotWaterSystem` has no `user_data`, so a Hot Water System's map is left out with that finding; the Ventilator,
its system, the heaters, the tanks and the heat pump classes carry one (section 8).

## 2. Records

### Ventilator (catalog record, family 1)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.mechanical.ventilator` (new) | Ventilator | `vnt` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.ventilator` |

| Field | Shape | Required | Note |
| --- | --- | --- | --- |
| `name`, `notes`, `datasheet_links`, `source` | `Fields.common` (exists) | `name` | `name` is displayed as `Tag` (D4-20); `source` defaults to `{"kind": "manual"}` |
| `manufacturer`, `model` | string or null | no | D4-20 identity columns on every Mechanical table, hideable in the UI |
| `quantity` | integer, minimum 1 | yes, default 1 | Q4; honeybee-ph `Ventilator.quantity` |
| `sensible_heat_recovery`, `latent_heat_recovery` | number 0 to 1, `x-unit` `fraction` | yes, defaults 0.0 | Unitless fractions (V4); `fraction` as a Glazing's `g_value` declares it (P4-02) |
| `electric_efficiency_wh_m3` | number, minimum 0, `x-unit` `Wh/m3` | yes, default 0.55 | Shown W/cfm under IP (V4, A3) |
| `frost_protection_reqd` | boolean | yes, default true | |
| `temperature_below_defrost_used_c` | number, `x-unit` `C` | yes, default -5 | |
| `in_conditioned_space` | boolean | yes, default true | |
| `subsoil_heat_exchange_efficiency` | number 0 to 1 or null, `x-unit` `fraction` | no | Disclosed, blank by default (V3) |
| `preheated_intake_temperature_c` | number or null, `x-unit` `C` | no | Disclosed, blank by default (V3) |

`schema_version` 1 with this field set; later additions bump `schema_version` and rewrite fixtures (F34). No timestamps. `sys_type` is not a field: the section writes 1 (V2). No rated flow (V6).

### Hot Water (catalog records, family 2; three flat kinds per D4-17)

D4-17 replaces the single nested record with three flat catalog kinds: **Hot Water System** (serves Zones), **Hot Water Heater** (names its System) and **Hot Water Tank** (names its System). Recirculation temperature and hours are read-only from recirculation piping (F17, D4-18) and are not stored on the System record.

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.mechanical.hot_water_system` (new) | Hot Water System | `hws` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hot_water_system` |
| `ph_composer.mechanical.hot_water_heater` (new) | Hot Water Heater | `hwh` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hot_water_heater` |
| `ph_composer.mechanical.hot_water_tank` (new) | Hot Water Tank | `hwt` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hot_water_tank` |

**Hot Water System (`hws_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer` (string or null), `model` (string or null), `number_tap_points` (integer >= 0 or null; honeybee-ph `number_tap_points`; P4-06 made it >= 1, since the setter reads 0 as unset and would count the piping's fixtures instead), `piping_calc_method` (integer 1 to 4 or null; H5, D4-12 — written to honeybee-ph only when the loaded class accepts it).

**Hot Water Heater (`hwh_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer` (string or null), `model` (string or null), `hot_water_system_id` (declared `one` reference to `ph_composer.mechanical.hot_water_system`, required), `variant` (enum `electric`, `heat_pump_annual`, `heat_pump_monthly`, `heat_pump_inside`; H2), `percent_coverage` (number 0 to 1, default 1.0), `in_conditioned_space` (boolean, default true), and the variant's efficiency fields (D4-19): `total_system_perf_ratio` (annual), `cop_1`, `ambient_temp_1_c`, `cop_2`, `ambient_temp_2_c` (monthly), `annual_energy_factor` (inside), none for `electric`. A variant's fields are required for that variant and must be absent for the others.

**Hot Water Tank (`hwt_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer` (string or null), `model` (string or null), `hot_water_system_id` (declared `one` reference to `ph_composer.mechanical.hot_water_system`, required), `role` (enum `storage`, `buffer`, `solar`; D4-07), `tank_type` (enum `0-NO STORAGE TANK`, `1-DHW AND HEATING`, `2-DHW ONLY`; default `2-DHW ONLY`), `quantity` (integer >= 1, default 1), `in_conditioned_space` (boolean, default true), `solar_connection` (boolean, default false), `solar_losses_w` (number >= 0, default 0.0), `storage_loss_rate_w_k` (number >= 0, `x-unit` `W/K`, default 0.0), `storage_capacity_l` (number >= 0, `x-unit` `L`, default 300), `standby_losses_w_k` (`x-unit` `W/K`, default 4.0), `standby_fraction` (0 to 1, default 0.3), `room_temp_c` (`x-unit` `C`, default 20), `water_temp_c` (`x-unit` `C`, default 60). The units are honeybee-ph's docstrings at 1.33.68: `solar_losses` in W, `storage_loss_rate` and `standby_losses` in W/K (section 8).

Deleting a Hot Water System follows `reference.in_use` for both Serves payloads and referencing Heaters and Tanks (refuse in use, or rewrite with `replacement_id`). P4-06: `replacement_id: null` empties the Zones' slots only; Heaters and Tanks require a System, so one still naming it refuses, and nothing cascades.

### Heat Pumps (catalog records, family 3; four flat kinds per D4-14, D4-15, D4-28)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.mechanical.hp_outdoor_equipment` (new) | Heat Pump Outdoor Equipment | `hpo` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hp_outdoor_equipment` |
| `ph_composer.mechanical.hp_indoor_equipment` (new) | Heat Pump Indoor Equipment | `hpi` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hp_indoor_equipment` |
| `ph_composer.mechanical.hp_outdoor_unit` (new) | Heat Pump Outdoor Unit | `hou` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hp_outdoor_unit` |
| `ph_composer.mechanical.hp_indoor_unit` (new) | Heat Pump Indoor Unit | `hiu` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hp_indoor_unit` |

**Outdoor Equipment (`hpo_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer`, `model`, `paired_indoor_equipment_id` (optional `one` ref to `hp_indoor_equipment`, D4-14), and the Phius estimator inputs (F15, D4-14, D4-15): `heating_cap_17f_kw` and `heating_cap_47f_kw` (`x-unit` `kW`, shown kBtu/h in IP through the panel's `capacity` quantity; P4-08 stores kW, honeybee-ph's recirculation capacity unit, rather than the `_w` first bound), `heating_rating_mode` (`cop_pair` default, or `hspf`), `cop_17f` and `cop_47f` (read when `cop_pair`, default 2.5 each), `hspf_value` and `hspf_version` (`hspf` or `hspf2`, default `hspf2`, read when `hspf`), `cooling_cap_95f_kw` (`x-unit` `kW`, nullable if heating-only), `cooling_rating_mode` (`eer_seer`, `ieer` or null), `eer`, `seer` and `seer_version` (`seer` or `seer2`, default `seer2`, read when `eer_seer`), `ieer` (read when `ieer`). P4-08: each mode reads only its own values and the other's stay stored (unlike a Heater's variant); capacities stay absent until given, and a model lacking a value the blend needs is left out with `mechanical.hp_equipment_incomplete`. The conversion and derating are the estimator's v25.1.2 expressions (`blend.rb`; context/CONTRACTS.md, "Mechanical equipment").

**Indoor Equipment (`hpi_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer`, `model` — identity columns only in v1 (D4-28, D4-20, F15).

**Outdoor Unit (`hou_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer`, `model`, `outdoor_equipment_id` (`one` ref to `hp_outdoor_equipment`, required), `quantity` (integer >= 1, default 1), `in_conditioned_space` (boolean, default false).

**Indoor Unit (`hiu_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer`, `model`, `indoor_equipment_id` (`one` ref to `hp_indoor_equipment`, required), `outdoor_unit_id` (`one` ref to `hp_outdoor_unit`, required), `quantity` (integer >= 1, default 1), `in_conditioned_space` (boolean, default true). Serves names `hp_indoor_unit` ids (D4-15).

### Electric Heater (catalog record, family 4; D4-33, built in P4-09)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.mechanical.electric_heater` (new) | Electric Heater | `ehr` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.electric_heater` |

**Electric Heater (`ehr_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer` (string or null), `model` (string or null), `percent_coverage` (number 0 to 1, required, default 1.0; shown 0 to 100%). honeybee-ph's `PhHeatingDirectElectric` carries nothing else; it has no `in_conditioned_space`. Serves names `ehr_` ids in the `heater_ids` list (payload schema 4). No coverage-sum check across heaters or families (D4-33).

### Pump (catalog record, family 5; D4-34, built in P4-10)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.mechanical.pump` (new) | Pump | `pmp` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.pump` |

**Pump (`pmp_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer` (string or null), `model` (string or null), and honeybee-ph's `PhSupportiveDevice` values: `device_type` (4, 6, 7 or 10, required, default 6), `quantity` (integer >= 1, default 1), `in_conditioned_space` (boolean, default true), `norm_energy_demand_w` (W >= 0, default 0, the Grasshopper component's), `annual_period_operation_khrs` (>= 0, default 8.76), `ihg_utilization_factor` (0 to 1, default 1.0) and `ihg_usage_profile` (1 to 4 or absent; absent follows `device_type`, as the Grasshopper component reads a blank one: 4 gives 2, 6 and 7 give 4, 10 gives 1). The two IHG values sit behind a collapsed per-row disclosure (D4-34). Serves names `pmp_` ids in the `pump_ids` list (payload schema 5).

### Fan (catalog record, family 6; D4-35, built in P4-11)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.mechanical.fan` (new) | Fan | `fan` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.fan` |

**Fan (`fan_`):** `Fields.common` (`name` shown as `Tag`), `manufacturer` (string or null), `model` (string or null), honeybee-ph's exhaust ventilator values: `exhaust_type` (`kitchen_hood`, `dryer` or `user_defined`, required, default `user_defined`), `quantity` (integer >= 1, default 1), `exhaust_flow_rate_m3h` (m3/h >= 0, default 0), `annual_runtime_minutes` (>= 0, default 0); and the optional electric block, a linked `PhSupportiveDevice` type 10: `norm_energy_demand_w` (W >= 0 or absent; absent means no supportive device), `in_conditioned_space` (boolean, default true) and `annual_period_operation_khrs` (>= 0 or absent; absent follows the runtime, `annual_runtime_minutes / 60,000`). The last two sit behind a collapsed per-row disclosure (D4-35). Serves names `fan_` ids in the `fan_ids` list (payload schema 6).

### Serves (a payload on the Zone record, layer 3)

D4-21, answered 2026-11-22: Serves is stored as Programs stores a Zone's assignment
(`context/CONTRACTS.md`, "Occupancy"; `features/programs/occupancy.rb`), a structured extension on
the Zone record. It is not a record of its own: it has no id, no dictionary and no reference
target. This replaces the `ph_composer.equipment_serves` record with its `eqa_` id that D4-03
first bound.

| Namespace | On | Schema version | Export relevance |
| --- | --- | --- | --- |
| `ph_composer.mechanical.zone_serves` (new) | Each Zone record (`Zones::REFERENCE_KIND`), in its `extension_data` | 1 | `local_only` when P4-03 registers it, `required` from P4-04, in the same change as the export contributor's claim (section 6). A `required` namespace with no claim blocks every export of a record that carries it, so the two never land apart; Programs kept its extensions `local_only` the same way until its export stage. Once `required`, a payload this version does not understand blocks the export |

| Field | Shape | Declared reference | Note |
| --- | --- | --- | --- |
| `ventilator_id` | a `vnt_` id or null | `$.ventilator_id` to `ph_composer.mechanical.ventilator`, cardinality `one` | V1: one per Zone, which the single slot makes structural |
| `hot_water_system_id` | an `hws_` id or null | `$.hot_water_system_id` to `ph_composer.mechanical.hot_water_system`, cardinality `one` | Hot water H6: one per Zone |
| `hp_indoor_unit_ids`, `heater_ids`, `pump_ids`, `fan_ids` | a list of ids, empty for none | cardinality `many`, each to its family's kind (`hp_indoor_unit` for heat pumps) | Each later family adds its slot in its stage and moves the payload's schema version (F34). A heat pump slot names indoor units (D4-15) |

The validator (`serves/payload.rb`) takes a whole payload: every slot the installed version
declares is present, each id is of its slot's kind or null, a list holds no id twice, and no other
key is allowed. This feature's actions always stage a whole payload and never remove one, so a
Zone served by nothing is either a Zone with no payload or one whose every slot is empty; the reads answer both as unserved, and
`serves.clear` stages the empty payload.

**Writes.** The feature's own actions build the new payload and hand it to Zones' proposal
participant `ph_composer.zones.stage_extension` (exists, `features/zones/extension_staging.rb`),
which checks it with the validator and stages one Zone update step in the caller's proposal. Zones
owns the write: a locked Zone, a shared definition or a nested path refuses with Zones' `target.*`
codes, and no mechanical code writes a Zone record. The generic metadata routes can store the
payload too, so a rule the validator cannot see is a finding there and a refusal only in the
feature's own actions. A slot naming an item that is gone is not such a rule: P4-03 found that
every route through the engine, `update_metadata` included, refuses a declared reference to no
stored record as `reference.invalid`, so only a Zone record written outside the engine, such as
one pasted from another Model, can carry one, and the reads report it as `mechanical.item_missing`.

**References and delete in use (D4-05).** The declared references put each named item in the
engine's incoming-reference scan, so a plain delete refuses `reference.in_use` while a Zone names
it, as a Program a Zone names does. Delete with `replacement_id` moves each payload naming the
item to the replacement through `stage_extension` in the same proposal, and delete with an
explicit null stages the slot emptied, each one Undo step, as Programs' deletes do (API 1.84). The
`many` slots are the first `many` reference in a payload (F26); P4-01 proved the scan, the move and the copy over
one (section 8). The engine does the scan; the move is this feature's code, as it is Programs': read the Zones
through `ph_composer.zones.all`, stage each changed payload through `stage_extension`, and hand the returned
`zone_entries` to `propose_delete` as a `Records::ReferencePlan`. A list that already holds the replacement keeps it
once, since the validator refuses an id twice. Like Programs', the move reads only a payload whose status is `understood`; one that is invalid, outdated or unsupported is left as stored, and the engine's incoming check then refuses the delete. The move reads the stored payloads; a delete that writes the same payload earlier in its own proposal builds the move from that write instead.

**A copied Zone (D4-04).** The payload is part of the Zone record and travels with a native copy,
so the copy keeps what serves it. The feature declares no transition contributor and re-issues
nothing.

**Metadata (F36).** Serves holds no `user_data` of its own: it is a payload on the Zone, whose map
is Zones'. The catalog kinds above keep theirs through the engine.

## 3. Operations

Every name starts with `ph_composer.mechanical.`. Each query, action and view command is registered
with schemas and an example, so `docs/API_REFERENCE.md` regenerates and the reference test covers
it. Id params carry the prefix pattern, for example `^vnt_[A-Za-z0-9]{12}$`.

| Name | Verb | Stage | Purpose |
| --- | --- | --- | --- |
| `ventilators.all` | query | P4-02 | Every Ventilator with its values, `export_ready` and `export_blockers`; from P4-03 the Zones it serves and, from P4-05, its balance |
| `ventilators.list` | query | P4-02 | One bounded page of the same rows in id order, with `ids` and `fields`. Added by P4-02: the registry requires an `all` read's `response:` to name a bounded query it prefers |
| `ventilators` | snapshot section | P4-02 | The same projection for the panel |
| `ventilators.create`, `.update`, `.duplicate` | action | P4-02 | Values with `expected_values`; `user_data` |
| `ventilators.delete` | action | P4-02; replacement from P4-03 | Guarded delete, refused `reference.in_use` while a Zone names it; `replacement_id` moves every Serves slot naming it; explicit null clears them, one Undo step |
| `serves.assign` | action | P4-03 | Zone references with `expected_values`, one slot and one item id; a filled single slot is replaced after a refusal names the current item (V1, hot water H6): the action refuses `mechanical.slot_filled` unless `replace: true`. Staged through `ph_composer.zones.stage_extension` |
| `serves.clear` | action | P4-03 | Zone references and a slot, or every slot |
| `serves.all` | query, snapshot section | P4-03 | Every Zone occurrence with its Serves slots, resolved item names, and findings |
| `serves.list` | query | P4-03 | One bounded page of the same rows, in Zone id then occurrence path order. Serves rows grow with the Model, so the `all` read names it in `response:` |
| `hot_water_systems.all`, `hot_water_systems` | query, snapshot section | P4-06 | Hot Water Systems with served Zones, heater/tank counts, read-only recirculation (from piping, D4-18) and Segment pooling note (D4-17, D4-23). P4-06 adds `hot_water_systems.list`, `hot_water_heaters.list` and `hot_water_tanks.list`: the registry requires an `all` read to name a bounded query it prefers, as P4-02 found |
| `hot_water_systems.create`, `.update`, `.duplicate`, `.delete` | action | P4-06 | System record CRUD; guarded delete covers both Serves payloads and referencing Heaters/Tanks |
| `hot_water_heaters.all`, `hot_water_heaters`, `.create`, `.update`, `.duplicate`, `.delete` | query, snapshot section, action | P4-06 | Flat Hot Water Heaters table (D4-17, D4-19), each naming its `hot_water_system_id` |
| `hot_water_tanks.all`, `hot_water_tanks`, `.create`, `.update`, `.duplicate`, `.delete` | query, snapshot section, action | P4-06 | Flat Hot Water Tanks table (D4-17), each naming its `hot_water_system_id`, `role` and computed export slot (D4-07) |
| `heat_pumps.outdoor_equipment.*`, `heat_pumps.indoor_equipment.*`, `heat_pumps.outdoor_units.*`, `heat_pumps.indoor_units.*` | query, snapshot section, action | P4-08 | Four flat Heat Pumps tables (D4-14, D4-28): `list`, `all`, snapshot section, `create`, `update`, `duplicate`, `delete` (with `replacement_id`). P4-08 renamed them from `hp_outdoor_equipment.*`: a snapshot section named for its prefix would have taken the kind id `ph_composer.mechanical.hp_outdoor_equipment` |
| `heat_pumps.blended`, `heat_pumps_blended` | query, snapshot section | P4-08 | Read-only blended heat pump result per Building Segment in the Phius estimator's layout (D4-15, D4-16, D4-23) |
| `electric_heaters.list`, `.all`, `electric_heaters`, `.create`, `.update`, `.duplicate`, `.delete` | query, snapshot section, action | P4-09 | The flat Electric Heaters table (D4-33): CRUD through `CatalogOperations`; delete with `replacement_id` rewrites every Zone's `heater_ids`, null drops it from them |
| `pumps.list`, `.all`, `pumps`, `.create`, `.update`, `.duplicate`, `.delete` | query, snapshot section, action | P4-10 | The flat Pumps table (D4-34): CRUD through `CatalogOperations`; rows add `ihg_usage_profile_default`; delete with `replacement_id` rewrites every Zone's `pump_ids`, null drops it from them |
| `fans.list`, `.all`, `fans`, `.create`, `.update`, `.duplicate`, `.delete` | query, snapshot section, action | P4-11 | The flat Fans table (D4-35): CRUD through `CatalogOperations`; rows add `annual_period_operation_khrs_default`; delete with `replacement_id` rewrites every Zone's `fan_ids`, null drops it from them |
| `by_ventilator`, `by_hot_water_system` | colour mode | P4-05, P4-07 | `entity_kind: "zone"`: each Zone in its serving item's colour; unserved Zones uncoloured; the legend row counts Zones. The projection gives one entry per row of `ph_composer.zones.all`, which is one per Zone occurrence (two occurrences may share a Zone id), its value from that Zone's payload, and resolves the row's `reference.zone_path` with the core `OccurrencePath.resolve` for the entity and world transform, naming nothing of Zones' (section 8) |
| `preflight` | query | P4-04 | The export preflight rows, passed to `export_contributor(preflight:)`. One query for the feature (P4-06): the export pane runs each contributor's named preflight, so only the Ventilator export names it, and each family's rows carry that family's `section` |

Codes are declared once with `feature.code` in `features/mechanical/codes.rb` under the noun
`mechanical`. P4-02 raises none of its own (its refusals are the foundation's), so the file arrives with the first,
`mechanical.slot_filled` in P4-03. Refusals that Zones owns keep Zones' `target.*` codes, and a delete in use keeps the
foundation's `reference.in_use`.

Every registration is an agent-facing surface. A stage that adds a name declares `response:` and
`while_busy:` on a query (an `all` read declares `response: {"bounded" => false}` and a bounded
`list` where rows can grow with the Model: Serves rows do, item rows do not), `preconditions:` and
`transitions:` on an action, `side_effects:` on a view command; bumps `API::MINOR` once with one
`API::CHANGES` row; adds or extends the Mechanical recipe in `docs/AGENT_GUIDE.md`, which
`tests/agent_guide_test.rb` checks against the registry. The MCP connection serves a fixed verb
table over these registrations; no feature adds a tool.

## 4. Cross-feature seams

| From | To | Mechanism | Used for |
| --- | --- | --- | --- |
| Serves | Zones | `request.query("ph_composer.zones.all")` (exists) | Listing Zone occurrences to serve, their names, Building-Segments and Levels |
| Serves | Zones | The proposal participant `ph_composer.zones.stage_extension` (exists) | Every write of a Serves payload, with Zones' validation and write refusals (D4-21) |
| Serves | Zones | Nothing: the payload is part of the Zone record | What a copied Zone keeps (D4-04) |
| Balance | Spaces | `request.query("ph_composer.spaces.all")` (exists), the `zones` rows | Supply, extract and `airflow_mode` per served Zone in Detailed airflows (Q11, V6). A By Program Zone's sums are null (F24). Spaces no longer answers `imbalanced` (API 1.21), so `serves/balance.rb` holds the rule, more than a tenth of the larger, per ventilator (P4-05) |
| Colour-by | Zones | `request.query("ph_composer.zones.occurrences")` (new in P4-05) | Each Zone occurrence's reference and Serves payload without its Faces, so an unreadable Face record does not turn `by_ventilator` off (section 8, question 3) |
| Balance | Programs | `request.query("ph_composer.programs.zones")` (exists), the Zone rows' `ventilation_m3h` and `ventilation_source` | A By Program Zone's flow, counted as both its supply and its extract, which is what PHX writes for it (D4-24). Null while Programs cannot work it out, and the balance then reads a dash |
| Heat pump blend | Climate | `request.query("ph_composer.climate.climate.get")` and `ph_composer.climate.design_temperatures.get` (exists, met 2026-11-18) | Twelve monthly mean air temperatures and ASHRAE 99% heating / 1% cooling dry bulb for the Phius estimator's climate derating (D4-15, F20), in the live reads (Blended result, preflight, table findings). At export the same values come from the Site export's `projection` (P4-08), since an export contributor reads the snapshot and runs no query |
| Mechanical contributor | Zones contributor | `requires: ["ph_composer.zones.export.zones"]`, read with `reader.section`; `entity_projections` claiming `ph_composer.mechanical.zone_serves` on `Zones::REFERENCE_KIND`, read with `reader.entity_projection`, as Programs claims its assignment | Zone id, Room identifier and `exported` per Zone occurrence path, and each Zone's Serves slots; a Zone in no Building Segment is left out (F28) |
| Segment settings (P4-08b) | Zones | A namespace on `ph_composer.zones.building_segment`, `segmentSettingsSection`, an `entity_projections` claim and `Attachment(SEGMENT)` (exists, `context/EXTENSIBILITY.md`, "Building Segment settings") | Mechanical cooling, the mechanical room temperature and summer ventilation on the shared `BldgSegment` (F30) |
| Mechanical sections (Python) | Zone section | `Requirement` on `ph_composer.zones.export.zones` and `Attachment(ROOM)` keyed by the Zone's Room identifier (D4-01) | Setting each served Room's `ph_hvac` system |
| Piping and ducting sections (later) | Mechanical sections | `Requirement` on the mechanical section; add to the required object in `translate` (D4-09) | Ducts into the `PhVentilationSystem`, trunks into the `PhHotWaterSystem` |

Every arrow points down a layer or sideways to a layer 3 peer through a published read or
participant. Zones, Spaces and Programs gain nothing. A piping or ducting section adds to this
feature's object and not to a host:
the assembly's four hosts are `MODEL`, `SEGMENT`, `ROOM` and `FACE` (F29), and none of them is a
ventilation or hot water system.

## 5. Foundation and owner additions

Numbered A1 onward. Each names no mechanical concept and lands in the stage listed with its own
tests.

| # | Addition | Where | Stage |
| --- | --- | --- | --- |
| A1 | `honeybee_phhvac` and `honeybee_energy_ph.properties.load` reachable through the stack seam: add `honeybee_phhvac` to `stack.PACKAGES`; `tests/python/test_imports.py` iterates that set and needs no change beyond the runtime probe that the package imports in Pyodide | `python/ph_composer_translation/stack.py`, `tools/runtime/browser_check.py` probe | P4-01, done (section 8) |
| A2 | The reserved Systems button becomes the live Mechanical tab (D4-13): the disabled button in `html/index.html`, last in the shipped row after Export (F32), moves to sit after Thermal Bridges and before Library (D4-27) and becomes `data-tab="mechanical"` with a `data-pane="mechanical"`. The row then reads Climate, Zones, Programs, Assemblies, Window Types, Thermal Bridges, Mechanical, Library, Export. Inside Mechanical, subtabs are by system (`Ventilation`, `Heat Pumps`, `Hot Water`, `Pumps`, `Fans`, `Electric Heating`) with a shared pill row beneath them for each system's tables (D4-13) | `html/index.html`, `html/pill_row.js` (or kit part), generated script list | P4-05, built (in review) |
| A3 | Units: `electric_efficiency` (Wh/m³ to W/cfm, V4) and `volume_l` (litres to US gallons), in Ruby `core/units.rb` where a report shows them and in `html/unit_tables.js` with vectors; recorded in the units packet as its Q3 outcome. `temperature` and `power` exist in both registries (F31) | `core/units.rb`, `html/unit_tables.js`, `tests/support/units_vectors.json` | P4-05 (efficiency), P4-07 (litres) |
| A4 | `PLANNING_IDS` matches this packet's ids: a stage `P4-01`, a lettered stage `P4-08b`, and a register row `M01` to `M16`, but not an SVG path's move command (`M12 4v16`) | `Makefile`, `tests/python/test_githooks.py` | P4-01, done (section 8) |
| A5 | Not needed. Zones' `stage_extension` participant exists and is the one route Serves writes by (D4-21). Kept so numbering stays stable | none | none |

`tools/ui-preview/host.js` publishes a fixed map of section names in its synthetic snapshot. Every
stage that adds a panel section adds its preview fixture there and a `*_checks.cjs` under
`tools/ui-preview/` through the shared browser-evidence collector, and regenerates the panel script
list with `make panel-manifest`.

## 6. Findings and export

Findings are `{code, section, object_id, message, blocks_export, locate}` from the preflight
query and the Python sections.

| Code | PRD row or decision | Blocks export | Repair |
| --- | --- | --- | --- |
| `mechanical.item_unserved` | An item serves no Zone; not exported | no | Assign it, or leave it |
| `mechanical.zone_unventilated` | A Zone with no Ventilator (V5) | no | Assign one |
| `mechanical.zone_no_hot_water` | A Zone with no Hot Water System (hot water H6) | no | Assign one |
| `mechanical.item_missing` | A Serves slot names an item that is not in the Model. No route through the engine can leave one (section 2); a Zone record written outside it, such as one pasted from another Model, can | yes | Reassign with `replace`, or Clear |
| `mechanical.item_across_segments` | An item serves Zones in more than one Building Segment (D4-23). Allowed, as honeybee-ph allows one object on any Rooms; each Segment's Variant carries the whole item | no | Informational; split the item if the Segments have separate plant |
| `mechanical.zone_left_out` | The served Zone is in no Building Segment, so it is left out of the export (F28). Info, as `space.zone_left_out` is; the unserved-Zone findings above skip such a Zone | no; that Room is not written | Move the Zone into a Building Segment |
| `mechanical.tank_unslotted` | More storage tanks than slots, or a second buffer or solar tank (D4-07) | no; the tank is omitted | Remove or re-role it |
| `mechanical.hot_water_pooled` | More than one served Hot Water System in the same Building Segment (D4-17, D4-23, F18); WUFI/METr pool tanks/heaters and keep one tap-point count | no | Informational; consolidate into one System if one plant |
| `mechanical.method_not_exported` | `piping_calc_method` set while the pinned wheel has no field (D4-12) | no | Informational until honeybee_ph#135 lands |
| `mechanical.hp_climate_missing` | Model climate monthly means or ASHRAE 99%/1% design temperatures missing/incomplete when Heat Pumps are served (F20, D4-15) | no; blended heat pump omitted | Complete Climate location and design temperatures |
| `mechanical.hp_unit_unpaired` | Outdoor unit has no served indoor unit, or indoor unit is unserved (D4-14, D4-15) | no; unit omitted from blend | Pair and assign indoor units to Zones |
| `mechanical.hp_equipment_incomplete` | An outdoor model lacks a value the blend needs, or a Building Segment's models blend to no heating COP (an HSPF model with no cooling share, as the estimator weights it). Added by P4-08 | no; the model, or that Segment's blend, is left out | Enter the model's capacities and ratings |
| `mechanical.hp_cooling_over_200kw` | Building Segment blended cooling capacity exceeds 200 kW / 682 kBtu/h (D4-29, F40) | no | Informational; PH-Composer exports one system (METr has no cap; PHX splits on WUFI-XML export) |
| `mechanical.segment_cooling_mismatch` | A Building Segment's mechanical cooling switch is on and its exported blend has no cooling (no blend counts as none), or off and its blend cools (D4-26). Added by P4-08b | no | Switch it to match, or change the heat pumps serving the Segment |
| `mechanical.zone_without_spaces` | An item PHX reads through a Room's Spaces (a Pump or a Fan) serves an exported Zone that no Space names (D4-34, D4-35). The HBJSON carries it on that Room; PHX reads it only through another Room it serves in the same Building Segment. Added by P4-10 through `ExportZones.spaceless_findings`, which takes the family's slot and label | no; the pair is written | Add Spaces to the Zone |
| `object.unavailable` (foundation code) | A record failed to translate or attach | yes (D4-06) | The message carries the cause |

| Section id | Object | Requires | Notes |
| --- | --- | --- | --- |
| `ph_composer.mechanical.export.ventilation` (new) | One `PhVentilationSystem` per (Ventilator, served Zone) pair, `sys_type` 1, holding a `Ventilator` with the record's values; identifiers derive from the item id so every Room an item serves carries the same ids (D4-01) | `ph_composer.zones.export.zones` | Attaches at `ROOM`, keyed by the Zone's Room identifier; `attach` calls `set_ventilation_system`. `required_for_export = True` (D4-06). Result fields: one row per (item, Zone) with identifiers and values; `conformance` checks each reloaded Room's `ph_hvac.ventilation_system.ventilation_unit` against them and that the same item carries one identifier across Rooms. Every (item, Zone) object of one item must be equal, ducts included (D4-09): honeybee-ph refuses to reload two ventilation systems that share an identifier and differ (section 8) |
| `ph_composer.mechanical.export.hot_water` (P4-06) | One `PhHotWaterSystem` per (system, served Zone) pair built from the flat System, Heater and Tank records (D4-17): tanks slotted by `slotting.rb` (D4-07) into `tank_1`, `tank_2`, `tank_buffer`, `tank_solar`, each role's tanks in name then id order (record ids are random, so "list order" is the Tag); heaters through `add_heater`; `number_tap_points` set; `recirc_temp`/`recirc_hours` left to honeybee-ph's read-only piping properties (F17, D4-18); `piping_calc_method` only when the loaded class accepts it (D4-12) | `ph_composer.zones.export.zones`, and `ph_composer.mechanical.export.ventilation` for the Zones: one contributor may claim a payload, so the Ventilator export claims Serves for the feature and its `projection` gives every Zone with its slots (P4-06) | Attaches at `ROOM` through `set_hot_water_system`. `required_for_export = True`. Result fields: the systems with their slot assignment and omitted tanks; `conformance` reads back each slot's identifier and capacity, and records in its result fields each (System, Zone) row's digest of the system's `to_dict()` as translated, and `conformance` compares each reloaded Room's system against its own row's digest. A plain equality check after reload cannot work: honeybee-ph keeps the last of two systems sharing an identifier and gives it to every Room, so the overwritten Room's digest is what shows the difference (section 8) |
| `ph_composer.mechanical.export.heat_pumps` (P4-08) | One blended `PhHeatPumpRatedMonthly` (with `PhHeatPumpCoolingParams_Recirculation`, `min_coil_temp = 12.0 °C`, full blended capacity with no > 200 kW split per D4-29) per exported Building Segment, computed in pure Ruby (`blend.rb`, F35) and attached to every served Room in that Segment with shared identifiers per Segment (D4-01, D4-15, D4-23) | `ph_composer.zones.export.zones`, `ph_composer.mechanical.export.ventilation` (the Zones), and `ph_composer.climate.export.site`, whose `projection` (added by P4-08) gives the monthly mean air temperatures and design temperatures; the section id first bound here, `export.climate`, does not exist | Attaches at `ROOM` through `add_heat_pump_system`. `required_for_export = True`. Result fields: per-Segment blended COPs, cooling capacity, airflow and annual COP; `conformance` reads back each served Room's `ph_hvac.heat_pump_systems` and compares each against the digest its own row recorded at translation, as for hot water (section 8) |
| `ph_composer.mechanical.export.electric_heaters` (P4-09) | One `PhHeatingDirectElectric` per (Electric Heater, served Zone) pair under the heater's id, with its Tag, coverage and `user_data` (D4-01, D4-33), worked out in pure Ruby (`electric_heater_plan.rb`); a Room holds every heater serving it | `ph_composer.zones.export.zones`, `ph_composer.mechanical.export.ventilation` (the Zones) | Attaches at `ROOM` through `add_heating_system`, once per heater. `required_for_export = True`. Result fields: one row per pair with its digest; `conformance` compares each reloaded Room's heater with its own row's digest (honeybee-ph keeps the last of heating systems sharing an identifier) and refuses an unreported heating system |
| `ph_composer.mechanical.export.pumps` (P4-10) | One `PhSupportiveDevice` per (Pump, served Zone) pair under the pump's id, with its Tag, values, the usage profile resolved in Ruby and `user_data` (D4-01, D4-34), worked out in pure Ruby (`pump_plan.rb`); a Room holds every pump serving it | `ph_composer.zones.export.zones`, `ph_composer.mechanical.export.ventilation` (the Zones) and `ph_composer.spaces.export.spaces`, whose `projection` gains `space_count` (P4-10) | Attaches at `ROOM` through `add_supportive_device`, once per pump, the profile set after the type. `required_for_export = True`. Result fields: one row per pair with its values and digest; `conformance` compares each reloaded Room's pump with its own row's digest and refuses an unreported supportive device under a Pump id |
| `ph_composer.mechanical.export.fans` (P4-11) | Per (Fan, served Zone) pair, one exhaust ventilator of the class its type names under the fan's id with its Tag, quantity, flow (m3/s), runtime and `user_data`, and, when the fan has power, a linked type 10 `PhSupportiveDevice` under the same id with its quantity, power, the operation resolved in Ruby and in conditioned space (Q6, D4-01, D4-35), worked out in pure Ruby (`fan_plan.rb`) | As the Pump export | Attaches at `ROOM` through `add_exhaust_vent_device` and, with power, `add_supportive_device`, once per fan. `required_for_export = True`. Result fields: one row per pair with the exhaust and supportive device values and both digests; `conformance` compares each reloaded Room's fan objects with its own row, refuses a Fan-id supportive device on a row without power and any unreported Fan-id object. PHX 1.59.4 drops the exhaust ventilator's `quantity` |
| `ph_composer.mechanical.export.segments` (P4-08b) | One record per exported Building Segment: `mechanical_cooling`, `mech_room_temp_c` and four summer ventilation values from the `ph_composer.mechanical.segment` extension, defaults written out (D4-26, D4-32) | `ph_composer.zones.export.zones` (claiming the namespace on the Building Segment kind) and `ph_composer.mechanical.export.heat_pumps`, whose `projection` gives each blend's cooling | Attaches at `SEGMENT`; sets `set_points.mechanical_cooling`, `mech_room_temp` and four `summer_ventilation` fields, never `set_points.winter` or `.summer`. `required_for_export = True`. Result fields: each Segment's six values; `conformance` reads them back |

PHX merges a Building Segment's Rooms and writes one Variant per Segment (F28), so the Building
Segment is "the building" wherever this packet says so (D4-23): the hot water pooling note of
D4-17 names the Systems that serve one Segment, and the blended heat pump of D4-15 is worked out
once per exported Segment from the outdoor equipment whose indoor units serve that Segment's
Zones. An item on Rooms in two Segments is written to both and noted
`mechanical.item_across_segments`.

Each export stage proves what PHX builds from its HBJSON by a round trip in the `phx` test group
(D4-25), `tests/python/test_<section>_phx_round_trip.py`, skipped without the group as Programs'
are: one device for an item on several Rooms, tanks and heaters once per Segment. The METr file
and its import stay metr-export's.

Both sections declare the `user_data_keys` they pass through. The extraction contract is pinned by
a fixture both Ruby and Python read (`tests/fixtures/mechanical/`), as the other sections are.

## 7. Questions P4-01 answers by test

1. Does a `many` reference in a structured extension on a Zone record behave as the `one`
   references Programs ships do (D4-21, F26)? Stage a test payload with a `one` and a `many`
   reference through `ph_composer.zones.stage_extension` and show: a plain delete of an item
   either names refuses `reference.in_use`; a delete with a replacement moves both in one Undo
   step; a native Zone copy carries the payload; a locked Zone refuses the write. Expected yes.
   A no is corrected in the engine, not worked around here. This replaces the first draft's
   question, which D4-21 retired.
2. Does one translated object per (item, Zone) pair, sharing the item's identifier, survive
   honeybee's `to_dict` and `from_dict` on two Rooms and PHX's key deduplication
   (`get_mech_device_by_key`)? Expected yes for both halves: the HBJSON reload, and a PHX round
   trip in the `phx` test group that finds one device (D4-25).
3. Does a Colour-by projection with `entity_kind: "zone"` reach Zone occurrences from a read
   without walking the Model, as `features/zones/colour_modes.rb` `entries(read.model)` does?
   Bind `by_ventilator` to that shape.
4. Does `honeybee_phhvac` import in the installed Pyodide runtime, with `honeybee_phhvac.properties`
   extending `Room.properties.ph_hvac` once `honeybee_ph` is loaded (`assembly.py` loads
   `honeybee_ph` today)?

## 8. What P4-01 found

Answered on 2026-11-23 against `main` at `2c0e13c2` with honeybee-ph 1.33.68 and PHX 1.59.4. The evidence, with
the commands and counts, is [p4-01-contracts.md](evidence/p4-01-contracts.md).

| Question (section 7) | Answer | Evidence | Correction made |
| --- | --- | --- | --- |
| 1. A `many` reference in a Zone payload | Yes. A test-only feature with a `one` and a `many` reference in a payload staged through `ph_composer.zones.stage_extension` shows: a plain delete of an item named only in the list refuses `reference.in_use`, as one named in the single slot does; a delete with a replacement moves both slots of two Zones in one Undo step, and Undo restores both; a list already holding the replacement keeps it once; a copy of the Zone Group carrying its attribute dictionaries, as a native copy does, made independent keeps the payload, and its list still blocks a delete (the native gesture itself is a host check, P4-03's); a locked Zone refuses the write and the replacement delete, writing nothing and adding no operation. The engine proves the scan (`Extension.referenced_ids` reads an array), the projected delete and the copy; the move is feature code (section 2). Breaking the array scan fails two of the six tests | `tests/zone_payload_references_test.rb`, `tests/support/zone_payload_probe.rb` | Section 2, "References and delete in use": the move's shape and the de-duplication. No engine change |
| 2. One object per (item, Zone) pair sharing identifiers | Yes, both halves. Two Rooms each given their own `PhVentilationSystem` and `Ventilator` with equal identifiers write equal HBJSON, and honeybee-ph reloads them onto one system object whose unit carries the record's values. PHX makes one ventilation device, named once in WUFI XML and once in METr JSON, and both Rooms' Spaces point at it. Two such systems that differ do not reload: honeybee-ph refuses `Conflicting ventilation systems share identifier`. Read, not run: its hot water and heat pump reloads key by identifier with no such check, so the last Room's object wins | `tests/python/test_shared_ventilator.py`, `tests/python/test_shared_ventilator_phx_round_trip.py` (`phx` group) | Section 6: every (item, Zone) object of one item is equal, ducts and pipes included (D4-09), and the hot water and heat pump sections record each (item, Zone) object's digest at translation for `conformance` to compare per Room, since the reload resolves a difference before `conformance` runs |
| 3. A Zone-keyed Colour-by projection from a read | Yes for occurrence identity and transforms; not without a walk. A projection over `read.query("ph_composer.zones.all")`, one entry per row, that resolves each row's `reference.zone_path` with the core `OccurrencePath.resolve` reaches the same entities, paths and world transforms as Zones' `by_zone`, a Zone inside a moved Group and a copy that keeps its Zone id (two occurrences, two entries) included, and the service counts its legend rows. Colours and legend order are the mode's own (`by_zone` spreads its ramp; P4-05 chooses). The projection names nothing of Zones', but `zones.all` walks the Model and validates every Face record for its panel totals, and `OccurrencePath.resolve` walks from the root per row, so an unrelated unreadable Face can turn the mode off. P4-05 measures the cost and tests an invalid Face, and binds `by_ventilator` to a narrower Zones occurrence read if `zones.all` refuses one | `tests/zone_payload_references_test.rb` | Section 3, `by_ventilator`: bound to that shape |
| 4. `honeybee_phhvac` in the Pyodide runtime | Yes, offline. `honeybee_ph` already imports `honeybee_phhvac` (its `__init__` extends the Room), so the seam change admits the package to `stack.load` and loads nothing new. In the shipped runtime page under Chromium 88, after a translation installs the wheels, `stack.load("honeybee_phhvac")` loads after `honeybee_ph`, a Room's `properties.ph_hvac` is `RoomPhHvacProperties` and takes a `PhVentilationSystem`. The installed host case is owed to MS1 | `tools/runtime/browser_check.py --translation` (`hvac_seam: true`); case `M01` in `planning/native-acceptance/cases.json` | Section 5, A1: done |

The wheel re-read (step 0), against the fields sections 2 and 6 bind:

| Class at 1.33.68 | Finding | Correction made |
| --- | --- | --- |
| `Ventilator`, `PhVentilationSystem` | Every field in section 2 is present, with the defaults bound there (quantity 1, 0.55 Wh/m³, frost protection on, -5 °C, both optional fields `None`); `sys_type` defaults to 1. Both carry `user_data` | None |
| `PhHotWaterSystem` | `tank_1`, `tank_2`, `tank_buffer`, `tank_solar` are plain attributes; `number_tap_points` has a setter; `recirc_temp` and `recirc_hours` have none (F23 holds). No calculation-method field (D4-12 holds). **No `user_data`** | Section 1: a Hot Water System's map is left out with `export.metadata_omitted` |
| `PhHvacHotWaterTank` | Defaults as bound. `storage_loss_rate` is W/K, not W; `solar_losses` is W | Section 2: `storage_loss_rate_w_k` |
| Hot water heaters | Electric, `HeatPump_Annual` (`total_system_perf_ratio`, `annual_COP`), `HeatPump_Monthly` (`COP_1`, `COP_2`, `ambient_temp_1`, `ambient_temp_2`), `HeatPump_Inside` (`annual_energy_factor`, `annual_COP`, `total_system_perf_ratio`); `percent_coverage` defaults to 1.0. PHX copies whatever attribute names its heater classes share | None: D4-19 binds one input per Type. P4-06's PHX round trip shows PHX copies `total_system_perf_ratio` to `PhxHeatPumpAnnual.params`, `annual_energy_factor` to `PhxHeatPumpHotWater.params` and the four monthly values to `PhxHeatPumpMonthly.params`, leaving `annual_COP` None; what WUFI XML and METr then show of them stays metr-export's |
| `PhHeatPumpRatedMonthly`, `PhHeatPumpCoolingParams_Recirculation` | `COP_1`, `COP_2`, `ambient_temp_1`, `ambient_temp_2`; the recirculation parameters `used`, `annual_COP`, `capacity`, `flow_rate_m3_hr`, `flow_rate_variable`, `min_coil_temp` (default 12.0, D4-29), `single_speed` | None |
| `RoomPhHvacProperties` | `set_ventilation_system`, `set_hot_water_system`, `add_heating_system`, `add_heat_pump_system`, `add_supportive_device`, `add_exhaust_vent_device`, `add_renewable_device`, as F12 lists | None |

Architecture review of the corrected bindings (the repo's `ph-composer-architecture-review` rubric, with the Ruby
quality criteria for the test-only payload feature), recorded in the evidence file. No blocking finding; three
notes carried to the stages:

- P4-03 writes the replacement move itself, as Programs' `Assignments.retarget` does; nothing in Zones or the
  engine changes, and a third payload owner may later justify a shared helper.
- P4-05: `OccurrencePath.resolve` walks each path from the Model root, so the projection costs a walk per Zone on
  top of `zones.all`'s own, and `zones.all` validates Face records the mode does not need. Measure it on a large
  Model and test it beside an invalid Face before the Colour-by mode ships.
- P4-04, P4-06 and the drawn packets: equal identifiers must mean equal objects (question 2), so a section that adds
  ducts or pipes adds them to every (item, Zone) object of the item, and the hot water and heat pump sections record
  each object's digest at translation for `conformance` to compare per Room, since their reload hides a difference.

The installed size on `main` at `2c0e13c2` is 26,841,808 bytes (`make rbz-check`, 708 files, RBZ 8,721,080 bytes):
747,849 over the 26,093,959-byte baseline, inside the 2,500,000-byte growth allowance, and 1,158,192 under the
28,000,000-byte ceiling, which binds first (F37). This stage changes the size by the manifest's own few bytes.

