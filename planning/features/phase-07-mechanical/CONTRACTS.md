# Phase 4 contract bindings: mechanical equipment

DATE: 2026-10-21
STATUS: Scoped. Proposed bindings for the shared shape and families 1 and 2, drafted from source at `420c783a` and the interviews of 2026-10-21. P4-01 confirms the questions in section 7 by test and runs the architecture review before any feature stage starts. Families 3 to 7, piping and ducting bind their names after their interviews. Not yet re-bound to the wireframe decisions of 2026-11-15 (D4-13 to D4-20): the Hot Water System shape, its recirculation fields, the heat pump kinds, the tab name and the column set below are superseded where they disagree with [DECISIONS, Part 3](DECISIONS.md#part-3-wireframe-review-2026-11-15); [STATUS](STATUS.md) lists what is owed. Corrected 2026-11-22 to the code at `8c710412` after Phase 6 Programs ([DECISIONS, Part 4](DECISIONS.md#part-4-review-after-programs-2026-11-22)): composition order, Spaces read names, units, export hosts and the left-out Zone rule. Re-bound the same day to Ed's answers D4-21 to D4-27: Serves is a payload on the Zone record, the feature is `ph_composer.mechanical`, the balance reads Programs for a By Program Zone, and the export stages carry PHX round trips.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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
Names are proposals until P4-01 closes; a stage may rename one only by editing this file in the
same change.

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
  ventilators/   schema.rb  operations.rb
  hot_water/     schema.rb  tanks.rb  heaters.rb  operations.rb  slotting.rb   (slotting pure, D4-07)
  serves/        payload.rb  operations.rb  reads.rb  balance.rb               (payload: the extension and its validator, D4-21)
  declarations/  shapes.rb  ventilators.rb  hot_water.rb  serves.rb
  <family>/      one folder per later family, bound by its stage
html/features/mechanical/
  section.js  families.js  ventilators.js  hot_water.js  serves.js  mechanical.css
python/ph_composer_translation/
  mechanical_sections.py       (ventilation and hot water sections; later families add theirs)
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
object or left out with `export.metadata_omitted`; and a row in `docs/USER_DATA.md` (F36).

## 2. Records

### Ventilator (catalog record, family 1)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.mechanical.ventilator` (new) | Ventilator | `vnt` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.ventilator` |

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
| `ph_composer.mechanical.hot_water_system` (new) | Hot Water System | `hws` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.mechanical.hot_water_system` |

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
| `heat_pump_ids`, `heater_ids`, `pump_ids`, `fan_ids` | a list of ids, empty for none | cardinality `many`, each to its family's kind | Each later family adds its slot in its stage and moves the payload's schema version (F34). A heat pump slot names indoor units (D4-15) |

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
payload too, so a rule the validator cannot see (a slot naming an item that is gone) is a finding
there and a refusal only in the feature's own actions.

**References and delete in use (D4-05).** The declared references put each named item in the
engine's incoming-reference scan, so a plain delete refuses `reference.in_use` while a Zone names
it, as a Program a Zone names does. Delete with `replacement_id` moves each payload naming the
item to the replacement through `stage_extension` in the same proposal, and delete with an
explicit null stages the slot emptied, each one Undo step, as Programs' deletes do (API 1.84). The
`many` slots are the first `many` reference in a payload (F26); section 7's first question proves
the scan and the move over one.

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
| `ventilators` | snapshot section | P4-02 | The same projection for the panel |
| `ventilators.create`, `.update`, `.duplicate` | action | P4-02 | Values with `expected_values`; `user_data` |
| `ventilators.delete` | action | P4-02; replacement from P4-03 | Guarded delete, refused `reference.in_use` while a Zone names it; `replacement_id` moves every Serves slot naming it; explicit null clears them, one Undo step |
| `serves.assign` | action | P4-03 | Zone references with `expected_values`, one slot and one item id; a filled single slot is replaced after a refusal names the current item (V1, hot water H6): the action refuses `mechanical.slot_filled` unless `replace: true`. Staged through `ph_composer.zones.stage_extension` |
| `serves.clear` | action | P4-03 | Zone references and a slot, or every slot |
| `serves.all` | query, snapshot section | P4-03 | Every Zone occurrence with its Serves slots, resolved item names, and findings |
| `hot_water_systems.all`, `hot_water_systems` | query, snapshot section | P4-06 | As Ventilators; rows carry tanks and heaters as nested arrays and the slotting each tank will take at export (D4-07) |
| `hot_water_systems.create`, `.update`, `.duplicate`, `.delete` | action | P4-06 | Tanks and heaters are edited through `update` with the whole nested array, as Assembly layers are |
| `by_ventilator`, `by_hot_water_system` | colour mode | P4-05, P4-07 | `entity_kind: "zone"`: each Zone in its serving item's colour; unserved Zones uncoloured; the legend row counts Zones |
| `preflight` | query | P4-04 | The export preflight rows, passed to `export_contributor(preflight:)` |

Codes are declared once with `feature.code` in `features/mechanical/codes.rb` under the noun
`mechanical`. Refusals that Zones owns keep Zones' `target.*` codes, and a delete in use keeps the
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
| Balance | Spaces | `request.query("ph_composer.spaces.all")` (exists), the `zones` rows | Supply, extract, `airflow_mode` and `imbalanced` per served Zone in Detailed airflows (Q11, V6). A By Program Zone's sums are null (F24) |
| Balance | Programs | `request.query("ph_composer.programs.zones")` (exists), the Zone rows' `ventilation_m3h` and `ventilation_source` | A By Program Zone's flow, counted as both its supply and its extract, which is what PHX writes for it (D4-24). Null while Programs cannot work it out, and the balance then reads a dash |
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
| A1 | `honeybee_phhvac` and `honeybee_energy_ph.properties.load` reachable through the stack seam: add `honeybee_phhvac` to `stack.PACKAGES`; `tests/python/test_imports.py` iterates that set and needs no change beyond the runtime probe that the package imports in Pyodide | `python/ph_composer_translation/stack.py`, `tools/runtime/` probe | P4-01 |
| A2 | The reserved Systems button becomes the live Mechanical tab (D4-13): the disabled button in `html/index.html`, last in the shipped row after Export (F32), moves to sit after Thermal Bridges and before Library (D4-27) and becomes `data-tab="mechanical"` with a `data-pane="mechanical"`. The row then reads Climate, Zones, Programs, Assemblies, Window Types, Thermal Bridges, Mechanical, Library, Export. The subtabs and tables inside it are the feature's own modules, owed to the wireframe re-plan | `html/index.html`, generated script list | P4-05 |
| A3 | Units: `electric_efficiency` (Wh/m³ to W/cfm, V4) and `volume_l` (litres to US gallons), in Ruby `core/units.rb` where a report shows them and in `html/unit_tables.js` with vectors; recorded in the units packet as its Q3 outcome. `temperature` and `power` exist in both registries (F31) | `core/units.rb`, `html/unit_tables.js`, `tests/support/units_vectors.json` | P4-05 (efficiency), P4-07 (litres) |
| A4 | `PLANNING_IDS` matches this packet's ids: a stage `P4-01`, a lettered stage `P4-08b`, and a register row `M01` to `M16`. None is caught today (F22) | `Makefile` | P4-01 |
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
| `mechanical.item_missing` | A Serves slot names an item that is not in the Model. The feature's own deletes cannot leave one (section 2); a payload stored through the generic metadata routes can | yes | Reassign or Clear |
| `mechanical.item_across_segments` | An item serves Zones in more than one Building Segment (D4-23). Allowed, as honeybee-ph allows one object on any Rooms; each Segment's Variant carries the whole item | no | Informational; split the item if the Segments have separate plant |
| `mechanical.zone_left_out` | The served Zone is in no Building Segment, so it is left out of the export (F28). Info, as `space.zone_left_out` is; the unserved-Zone findings above skip such a Zone | no; that Room is not written | Move the Zone into a Building Segment |
| `mechanical.tank_unslotted` | More storage tanks than slots, or a second buffer or solar tank (D4-07) | no; the tank is omitted | Remove or re-role it |
| `mechanical.recirc_disagrees` | Two served systems disagree on recirculation temperature or hours; PHX falls back (hot water H4) | no | Align them |
| `mechanical.method_not_exported` | `piping_calc_method` set while the pinned wheel has no field (D4-12) | no | Informational until honeybee_ph#135 lands |
| `object.unavailable` (foundation code) | A record failed to translate or attach | yes (D4-06) | The message carries the cause |

| Section id | Object | Requires | Notes |
| --- | --- | --- | --- |
| `ph_composer.mechanical.export.ventilation` (new) | One `PhVentilationSystem` per (Ventilator, served Zone) pair, `sys_type` 1, holding a `Ventilator` with the record's values; identifiers derive from the item id so every Room an item serves carries the same ids (D4-01) | `ph_composer.zones.export.zones` | Attaches at `ROOM`, keyed by the Zone's Room identifier; `attach` calls `set_ventilation_system`. `required_for_export = True` (D4-06). Result fields: one row per (item, Zone) with identifiers and values; `conformance` checks each reloaded Room's `ph_hvac.ventilation_system.ventilation_unit` against them and that the same item carries one identifier across Rooms |
| `ph_composer.mechanical.export.hot_water` (new) | One `PhHotWaterSystem` per (system, served Zone) pair: tanks slotted by `slotting.rb`'s rule (D4-07) into `tank_1`, `tank_2`, `tank_buffer`, `tank_solar`; heaters through `add_heater`; `number_tap_points`, `recirc_temp`, `recirc_hours`; `piping_calc_method` only when the loaded class accepts it (D4-12) | `ph_composer.zones.export.zones` | Attaches at `ROOM` through `set_hot_water_system`. `required_for_export = True`. Result fields: the systems with their slot assignment and omitted tanks; `conformance` reads back each slot's identifier and capacity |

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
