# Phase 4 contract bindings: equipment

DATE: 2026-10-21
STATUS: Scoped. Proposed bindings for the shared shape and families 1 and 2, drafted from source at `420c783a` and the interviews of 2026-10-21. P4-01 confirms the questions in section 7 by test and runs the architecture review before any feature stage starts. Families 3 to 7, piping and ducting bind their names after their interviews.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The [equipment PRD](equipment/PRD.md) defers exact names and schemas to its plan. This file is
that binding, the counterpart of Phase 3b's [thermal-bridge bindings](../../archive/phase-03b-thermal-bridges/CONTRACTS.md)
and Phase 3a's [Spaces bindings](../../archive/phase-03a-spaces/CONTRACTS.md). It restates no
behavior. Where a row and the PRD disagree about behavior, the PRD wins and this file is corrected.
Where a row follows a decision in [DECISIONS.md](DECISIONS.md), it names the decision; all were
answered as recommended on 2026-10-21. Interview answers are cited as the PRD numbers them: Q1 to Q12 (shared shape), V1 to
V6 (Ventilators) and hot water H1 to H7. A bare `H` number below with "hot water" in front is the
interview; the foundation additions of this packet are numbered A1 onward to avoid the clash with
the Spaces and thermal-bridge H1 to H18.

`context/CONTRACTS.md` owns the foundation mechanics these bindings sit on: registration, the
public interface, outcomes, revisions, retries, records and translation sections. Read it first.
Paths below are relative to `src/ph_composer/`.

Rows marked **new** do not exist yet. Rows marked **exists** were read in source at `420c783a`.
Names are proposals until P4-01 closes; a stage may rename one only by editing this file in the
same change.

## 1. Feature and composition

| Feature id | Folder | Requires | Registered in |
| --- | --- | --- | --- |
| `ph_composer.equipment` (new) | `features/equipment/` | `ph_composer.zones`, `ph_composer.spaces` (D4-02, D4-10) | `FEATURES`, after thermal bridges: `[Assemblies, Zones, Windows, Spaces, ThermalBridges, Equipment]` |

One feature for the seven families (D4-02, from Q1). Two layers inside it: the family kinds are
layer 1 definitions that validate without a Zone (the Zone child pattern's "definition values and
rules"); the Serves record is layer 3, a record on a Zone occurrence. A test holds the line from
P4-02: nothing under `features/equipment/<family>/` names Zones, Spaces, the Zone Group or
`serves/`. Nothing under another feature's folder names equipment.

Proposed layout, following `features/windows/install.rb` and `features/spaces/install.rb`:

```
features/equipment/
  install.rb  codes.rb  refuses.rb  snapshot.rb  export.rb  colour_modes.rb
  ventilators/   schema.rb  operations.rb
  hot_water/     schema.rb  tanks.rb  heaters.rb  operations.rb  slotting.rb   (slotting pure, D4-07)
  serves/        schema.rb  store.rb  operations.rb  steps.rb  reference_target.rb  balance.rb  zone_copy.rb
  declarations/  shapes.rb  ventilators.rb  hot_water.rb  serves.rb
  <family>/      one folder per later family, bound by its stage
html/features/equipment/
  section.js  families.js  ventilators.js  hot_water.js  serves.js  equipment.css
python/ph_composer_translation/
  equipment_sections.py        (ventilation and hot water sections; later families add theirs)
  contract/equipment_records.py
```

`serves/balance.rb` is pure: it takes detached Zone rows (the Spaces sums) and the Serves rows and
returns each Ventilator's supply, extract and imbalance, so the read and offline tests share one
function.

## 2. Records

### Ventilator (catalog record, family 1)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.equipment.ventilator` (new) | Ventilator | `vnt` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.equipment.ventilator` |

| Field | Shape | Required | Note |
| --- | --- | --- | --- |
| `name`, `notes`, `datasheet_links`, `source` | `Fields.common` (exists) | `name` | `source` defaults to `{"kind": "manual"}` |
| `quantity` | integer, minimum 1 | yes, default 1 | Q4; honeybee-ph `Ventilator.quantity` |
| `sensible_heat_recovery`, `latent_heat_recovery` | number 0 to 1 | yes, defaults 0.0 | Unitless fractions (V4) |
| `electric_efficiency_wh_m3` | number, minimum 0, `x-unit` `Wh/m3` | yes, default 0.55 | Shown W/cfm under IP (V4, A3) |
| `frost_protection_reqd` | boolean | yes, default true | |
| `temperature_below_defrost_used_c` | number, `x-unit` `C` | yes, default -5 | |
| `in_conditioned_space` | boolean | yes, default true | |
| `subsoil_heat_exchange_efficiency` | number 0 to 1 or null | no | Disclosed, blank by default (V3) |
| `preheated_intake_temperature_c` | number or null, `x-unit` `C` | no | Disclosed, blank by default (V3) |

`schema_version` 1 with this final field set, because the engine has no migrations. No
timestamps. `sys_type` is not a field: the section writes 1 (V2). No rated flow (V6).

### Hot Water System (catalog record, family 2)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.equipment.hot_water_system` (new) | Hot Water System | `hws` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.equipment.hot_water_system` |

| Field | Shape | Required | Note |
| --- | --- | --- | --- |
| `name`, `notes`, `datasheet_links`, `source` | `Fields.common` | `name` | |
| `number_tap_points` | integer, minimum 0, or null | no | Hot water H4; honeybee-ph `_number_tap_points` |
| `recirc_temp_c` | number, `x-unit` `C` | yes, default 60.0 | Hot water H4 |
| `recirc_hours` | number 0 to 24 | yes, default 24 | Hot water H4 |
| `piping_calc_method` | integer 1 to 4 or null | no | Hot water H5: stored, exported only once the pinned wheel carries the field (D4-12) |
| `tanks` | array of TANK, any length | yes, default `[]` | Hot water H3; nested identities `tnk_` as Assembly layers carry `lyr_` |
| `heaters` | array of HEATER, any length | yes, default `[]` | Hot water H2 |

TANK: `id` (`tnk_`), `name`, `role` (enum `storage`, `buffer`, `solar`; D4-07), `tank_type` (enum
honeybee-ph's `0-NO STORAGE TANK`, `1-DHW AND HEATING`, `2-DHW ONLY`; default `2-DHW ONLY`),
`quantity` (integer, minimum 1), `in_conditioned_space`, `solar_connection`, `solar_losses_w`
(number, minimum 0), `storage_loss_rate_w` (number, minimum 0), `storage_capacity_l` (number,
minimum 0, `x-unit` `L`, default 300), `standby_losses_w_k` (`x-unit` `W/K`, default 4.0),
`standby_fraction` (0 to 1, default 0.3), `room_temp_c` (default 20), `water_temp_c` (default
60). Units of `solar_losses` and `storage_loss_rate` are confirmed against honeybee-ph's
docstrings in P4-06; the suffixes above are the proposal.

HEATER: `id` (`htr_`), `name`, `variant` (enum `electric`, `heat_pump_annual`,
`heat_pump_monthly`, `heat_pump_inside`; hot water H2), `percent_coverage` (0 to 1, default 1.0),
`in_conditioned_space`, and the variant's fields: `total_system_perf_ratio` (annual),
`cop_1`, `ambient_temp_1_c`, `cop_2`, `ambient_temp_2_c` (monthly), `annual_energy_factor`
(inside). A variant's fields are required for that variant and must be absent for the others;
the kind's `validate` holds that rule, as `Assembly::Schema.problems` holds the layer rules.

Nested ids are regenerated by Duplicate through `propose_duplicate`'s block, as Assemblies do.

### Serves (entity-owned record, layer 3)

| Dictionary | Entity | Key | Identity |
| --- | --- | --- | --- |
| `ph_composer.equipment_serves` (new) | The Zone Group, through `Records::EntityStore` (exists; Spaces' precedent for a Group) | `record` | `eqa_` id, because the engine requires an id on every reference-target record (3b F6). One record per Zone occurrence; absent means the Zone is served by nothing |

| Field | Shape | Required | Note |
| --- | --- | --- | --- |
| `id` | `eqa_` plus twelve characters | yes | Proves identity in a reference (`entity_id`); re-issued by the Zone-copy contributor (D4-04) |
| `ventilator_id` | core `Records::Reference` to `ph_composer.equipment.ventilator`, cardinality one, or null | no | V1: one per Zone |
| `hot_water_system_id` | reference to `ph_composer.equipment.hot_water_system`, cardinality one, or null | no | Hot water H6: one per Zone |
| `heat_pump_ids`, `heater_ids`, `pump_ids`, `fan_ids` | arrays of references, cardinality many; absent until the family's stage binds its kind | no | Each later family adds its slot in its stage, as one line in the schema (D4-03) |
| `schema_version`, `user_data`, `extension_data` | engine reserved | | |

A record whose every slot is empty is removed rather than kept empty, so "served by nothing" has
one representation.

### Serves reference target

| Target id | Occurrence reference | Records provider | `locate:` |
| --- | --- | --- | --- |
| `ph_composer.equipment.serves` (new) | `{ "zone_id", "zone_path", "entity_id" }`: the Zone reference shape plus the `eqa_` id, or null for an unserved Zone | Every Zone occurrence from `ph_composer.zones.all` (copies and nested Zones included) that carries the dictionary; entries are `Records::ReferenceEntry(kind, key: zone_path, record)` | `request.locate("ph_composer.zones.zone", reference)` (exists, `features/zones/declarations/zone.rb`), then the store's read on the located Group; a Group whose record gained or changed its id refuses `target.changed`; Zones' `target.*` codes for locked, shared or nested paths pass through unchanged |

The target declares `references: [ventilator_id, hot_water_system_id, ...]` so the engine's
incoming-reference scan refuses deleting an item while a Zone names it, as a Face naming an
Assembly does. Delete with a replacement rewrites the slot on every Serves record through
`request.retarget_references`; delete with an explicit null clears the slot, removing the record
when it empties (D4-05). The item and its referrer are one feature, so the delete calls its own
rewrite step directly and registers no retargeter.

## 3. Operations

Every name starts with `ph_composer.equipment.`. Each query, action and view command is registered
with schemas and an example, so `docs/API_REFERENCE.md` regenerates and the reference test covers
it. Id params carry the prefix pattern, for example `^vnt_[A-Za-z0-9]{12}$`.

| Name | Verb | Stage | Purpose |
| --- | --- | --- | --- |
| `ventilators.all` | query | P4-02 | Every Ventilator with its values, `export_ready` and `export_blockers`; from P4-03 the Zones it serves and, from P4-05, its balance |
| `ventilators` | snapshot section | P4-02 | The same projection for the panel |
| `ventilators.create`, `.update`, `.duplicate` | action | P4-02 | Values with `expected_values`; `user_data` |
| `ventilators.delete` | action | P4-02; replacement from P4-03 | Guarded delete; `replacement_id` rewrites every Serves slot naming it; explicit null clears them, one Undo step |
| `serves.assign` | action | P4-03 | Zone references with `expected_values`, one slot and one item id; a filled single slot is replaced after a refusal names the current item (V1, hot water H6): the action refuses `equipment.slot_filled` unless `replace: true` |
| `serves.clear` | action | P4-03 | Zone references and a slot, or the whole record |
| `serves.all` | query, snapshot section | P4-03 | Every Zone occurrence with its Serves record, resolved item names, and findings |
| `hot_water_systems.all`, `hot_water_systems` | query, snapshot section | P4-06 | As Ventilators; rows carry tanks and heaters as nested arrays and the slotting each tank will take at export (D4-07) |
| `hot_water_systems.create`, `.update`, `.duplicate`, `.delete` | action | P4-06 | Tanks and heaters are edited through `update` with the whole nested array, as Assembly layers are |
| `by_ventilator`, `by_hot_water_system` | colour mode | P4-05, P4-07 | `entity_kind: "zone"`: each Zone in its serving item's colour; unserved Zones uncoloured; the legend row counts Zones |
| `preflight` | query | P4-04 | The export preflight rows, passed to `export_contributor(preflight:)` |

Codes are declared once with `feature.code` in `features/equipment/codes.rb` under the noun
`equipment`. Refusals that Zones owns keep Zones' `target.*` codes.

Every registration is an agent-facing surface. A stage that adds a name declares `response:` and
`while_busy:` on a query (an `all` read declares `response: {"bounded" => false}` and a bounded
`list` where rows can grow with the Model: Serves rows do, item rows do not), `preconditions:` and
`transitions:` on an action, `side_effects:` on a view command; bumps `API::MINOR` once with one
`API::CHANGES` row; adds or extends the equipment recipe in `docs/AGENT_GUIDE.md`, which
`tests/agent_guide_test.rb` checks against the registry. The MCP connection serves a fixed verb
table over these registrations; no feature adds a tool.

## 4. Cross-feature seams

| From | To | Mechanism | Used for |
| --- | --- | --- | --- |
| Serves | Zones | `request.query("ph_composer.zones.all")` (exists) | Listing Zone occurrences to serve, their names, Building-Segments and Levels |
| Serves | Zones | `request.locate("ph_composer.zones.zone", reference)` (exists) | The Zone Group a Serves record sits on, with Zones' write refusals |
| Serves | Zones | `transition_contributor` on `ph_composer.zones.occurrence_independent` (exists) | What a copied Zone keeps (D4-04) |
| Balance | Spaces | `request.query("ph_composer.spaces.all")` (exists), the `zones` rows | Supply, extract, `inheriting_count` and `imbalanced` per served Zone (Q11, V6) |
| Equipment contributor | Zones contributor | `requires: ["ph_composer.zones.export.zones"]`, read with `reader.section` | Zone id, Room identifier and omission state per Zone occurrence path |
| Equipment sections (Python) | Zone section | `Requirement` on `ph_composer.zones.export.zones` and `Attachment(ROOM)` keyed by the Zone's Room identifier (D4-01) | Setting each served Room's `ph_hvac` system |
| Piping and ducting sections (later) | Equipment sections | `Requirement` on the equipment section; add to the required object in `translate` (D4-09) | Ducts into the `PhVentilationSystem`, trunks into the `PhHotWaterSystem` |

Every arrow points down a layer or sideways to a layer 3 peer through a published read. Zones and
Spaces gain nothing.

## 5. Foundation and owner additions

Numbered A1 onward. Each names no equipment concept and lands in the stage listed with its own
tests.

| # | Addition | Where | Stage |
| --- | --- | --- | --- |
| A1 | `honeybee_phhvac` and `honeybee_energy_ph.properties.load` reachable through the stack seam: add `honeybee_phhvac` to `stack.PACKAGES`; `tests/python/test_imports.py` iterates that set and needs no change beyond the runtime probe that the package imports in Pyodide | `python/ph_composer_translation/stack.py`, `tools/runtime/` probe | P4-01 |
| A2 | The reserved Systems tab becomes live: the disabled button in `html/index.html` becomes `data-tab="systems"` with a `data-pane="systems"`; the Equipment subtab and the family selector are the feature's own modules (D4-08) | `html/index.html`, generated script list | P4-05 |
| A3 | Units: `electric_efficiency` (Wh/m³ to W/cfm, V4), `volume_l` (litres to US gallons) and, if absent from the panel registry, `temperature` (°C to °F), in Ruby `core/units.rb` where a report shows them and in `html/unit_tables.js` with vectors; recorded in the units packet as its Q3 outcome | `core/units.rb`, `html/unit_tables.js`, `tests/support/units_vectors.json` | P4-05 (efficiency), P4-07 (litres, temperature) |
| A4 | `PLANNING_IDS` matches `P4-01` (no letter after the digit) and `M01` | `Makefile` | P4-01, after P3b-01's edit |
| A5 | Not needed. The Zone reference target's `locate:` exists and resolves the Group Serves writes to. Kept so numbering stays stable | none | none |

`tools/ui-preview/host.js` publishes a fixed map of section names in its synthetic snapshot. Every
stage that adds a panel section adds its preview fixture there and a `*_checks.cjs` under
`tools/ui-preview/` through the shared browser-evidence collector, and regenerates the panel script
list with `make panel-manifest`.

## 6. Findings and export

Findings are `{code, section, object_id, message, blocks_export, locate}` from the preflight
query and the Python sections.

| Code | PRD row or decision | Blocks export | Repair |
| --- | --- | --- | --- |
| `equipment.item_unserved` | An item serves no Zone; not exported | no | Assign it, or leave it |
| `equipment.zone_unventilated` | A Zone with no Ventilator (V5) | no | Assign one |
| `equipment.zone_no_hot_water` | A Zone with no Hot Water System (hot water H6) | no | Assign one |
| `equipment.item_missing` | A Serves slot names a deleted item | yes | Reassign or Clear |
| `equipment.zone_omitted` | The served Zone is omitted from export | no; that Room gets nothing | The Zone's own finding |
| `equipment.tank_unslotted` | More storage tanks than slots, or a second buffer or solar tank (D4-07) | no; the tank is omitted | Remove or re-role it |
| `equipment.recirc_disagrees` | Two served systems disagree on recirculation temperature or hours; PHX falls back (hot water H4) | no | Align them |
| `equipment.method_not_exported` | `piping_calc_method` set while the pinned wheel has no field (D4-12) | no | Informational until honeybee_ph#135 lands |
| `object.unavailable` (foundation code) | A record failed to translate or attach | yes (D4-06) | The message carries the cause |

| Section id | Object | Requires | Notes |
| --- | --- | --- | --- |
| `ph_composer.equipment.export.ventilation` (new) | One `PhVentilationSystem` per (Ventilator, served Zone) pair, `sys_type` 1, holding a `Ventilator` with the record's values; identifiers derive from the item id so every Room an item serves carries the same ids (D4-01) | `ph_composer.zones.export.zones` | Attaches at `ROOM`, keyed by the Zone's Room identifier; `attach` calls `set_ventilation_system`. `required_for_export = True` (D4-06). Result fields: one row per (item, Zone) with identifiers and values; `conformance` checks each reloaded Room's `ph_hvac.ventilation_system.ventilation_unit` against them and that the same item carries one identifier across Rooms |
| `ph_composer.equipment.export.hot_water` (new) | One `PhHotWaterSystem` per (system, served Zone) pair: tanks slotted by `slotting.rb`'s rule (D4-07) into `tank_1`, `tank_2`, `tank_buffer`, `tank_solar`; heaters through `add_heater`; `number_tap_points`, `recirc_temp`, `recirc_hours`; `piping_calc_method` only when the loaded class accepts it (D4-12) | `ph_composer.zones.export.zones` | Attaches at `ROOM` through `set_hot_water_system`. `required_for_export = True`. Result fields: the systems with their slot assignment and omitted tanks; `conformance` reads back each slot's identifier and capacity |

Both sections declare the `user_data_keys` they pass through. The extraction contract is pinned by
a fixture both Ruby and Python read (`tests/fixtures/equipment/`), as the other sections are.

## 7. Questions P4-01 answers by test

1. Does `Records::EntityStore` with a second feature's dictionary on a Zone Group pass
   `Dictionaries.register`, the export attribute guard and Zones' own reads untouched (Zones'
   `entity_record(..., target_kind:)` claims only its own namespaces)? Expected yes; the
   `zone_child_fixture.rb` precedent stores on Groups inside a Zone, not on the Zone Group itself.
2. Does one translated object per (item, Zone) pair, sharing the item's identifier, survive
   honeybee's `to_dict` and `from_dict` on two Rooms and PHX's key deduplication
   (`get_mech_device_by_key`)? Expected yes for the HBJSON half; the PHX half is metr-export's.
3. Does a Colour-by projection with `entity_kind: "zone"` reach Zone occurrences from a read
   without walking the Model, as `features/zones/colour_modes.rb` `entries(read.model)` does?
   Bind `by_ventilator` to that shape.
4. Does `honeybee_phhvac` import in the installed Pyodide runtime, with `honeybee_phhvac.properties`
   extending `Room.properties.ph_hvac` once `honeybee_ph` is loaded (`assembly.py` loads
   `honeybee_ph` today)?
