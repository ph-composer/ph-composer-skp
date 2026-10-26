# Phase 3 contract bindings: thermal bridges

DATE: 2026-10-03
STATUS: Scoped. Proposed bindings, drafted from source at `08c4807`, updated to Ed's answers of 2026-10-03 and re-read against `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b; section 8 below). P3b-01 confirms the two questions still open in section 7 and runs the architecture review before any feature stage starts.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

The [PRD](PRD.md) defers exact names and schemas to its plan. This file is that binding, the
counterpart of Phase 3a's [Spaces bindings](../../archive/phase-03a-spaces/CONTRACTS.md), whose H1 to H10 these
numbers follow. It restates no
behavior. Where a row and the PRD disagree about behavior, the PRD wins and this file is corrected.
Where a row follows a decision in [DECISIONS.md](DECISIONS.md), it names the decision; all were
answered on 2026-10-03.

`context/CONTRACTS.md` owns the foundation mechanics these bindings sit on: registration, the
public interface, outcomes, revisions, retries, records and translation sections. Read it first.
Paths below are relative to `src/ph_composer/`.

Rows marked **new** do not exist yet. Rows marked **exists** were read in source at `420c783a`.
Names are proposals until P3b-01 closes; a stage may rename one only by editing this file in the
same change. The assignment's copy rule (D3b-22) and the run builder's join rule (D3b-23) were
answered as recommended on 2026-10-21 and are bound below.

## 1. Feature and composition

| Feature id | Folder | Requires | Registered in |
| --- | --- | --- | --- |
| `ph_composer.thermal_bridges` (exists from P3b-02) | `features/thermal_bridges/` | `ph_composer.zones`; `ph_composer.windows` added by P3b-08 (D3b-15) | `FEATURES`, last: `[Assemblies, Zones, Windows, Spaces, ThermalBridges]` |

Layer 3 of `context/EXTENSIBILITY.md`'s layering, like window Units and Spaces, with one
difference: the Thermal Bridge Type is a layer 1 definition that lives inside the feature, as
Windows keeps its products and types beside its Units. A test holds the internal line from P3b-02:
nothing under `features/thermal_bridges/type/` names Zones, an Edge or a run. Nothing under
`features/zones/`, `features/windows/`, `features/assemblies/` or `features/spaces/` names thermal
bridges. Spaces and thermal bridges are peers and neither requires the other.

Proposed layout, following `features/windows/install.rb` and `features/zones/install.rb`:

```
features/thermal_bridges/
  install.rb  codes.rb  run_locate.rb  snapshot.rb  export.rb  colour_modes.rb  edge_tool.rb
  type/        schema.rb  operations.rb  reads.rb
  assignment/  schema.rb (record and store)  operations.rb  steps.rb  reference_target.rb  selection.rb
  runs/        chains.rb  schedule.rb  findings.rb      (pure Ruby, no SketchUp)
  scan/        occurrences.rb
  declarations/ shapes.rb  types.rb  assignment.rb  schedule.rb  viewport.rb
html/features/thermal_bridges/
  section.js  types.js  schedule.js  assign.js  edge_tool.js  thermal_bridges.css
python/ph_composer_translation/
  thermal_bridge_sections.py
```

`runs/` is pure: it takes detached edge facts (Zone id, type id, quantity, occurrence path, world
endpoints in metres and the snapshot's `vertex_ids`, keyed with the container path, D3b-23) and returns runs, lengths and
findings, so the schedule and the export contributor compute runs with one function and offline
tests need no stub. It moves to `core/` only when piping or ducting arrives as its second user and
needs the same chain rule.

## 2. Records

### Thermal Bridge Type (catalog record)

| Kind id | Label | Prefix | Store |
| --- | --- | --- | --- |
| `ph_composer.thermal_bridges.type` (exists from P3b-02) | Thermal Bridge Type | `tbt` | `DictionaryStore`, Model dictionary `ph_composer.records.ph_composer.thermal_bridges.type` |

| Field | Shape | Required | Note |
| --- | --- | --- | --- |
| `name`, `notes`, `datasheet_links`, `source` | `Fields.common` (exists, `core/records/authoring_fields.rb`) | `name` | `datasheet_links` carries the psi-value calculation report (Q9). `source` defaults to `{"kind": "manual"}` |
| `psi_w_mk` | number or null, signed, `x-unit` `W/mK` | no | Null is incomplete and blocks export. Negative is legal |
| `group` | enum `15-Ambient`, `16-Perimeter`, `17-FS/BC` | yes, default `15-Ambient` | D3b-03, D3b-04. honeybee-ph's strings, stored; the panel shows METr's words |
| `color` | hex `#rrggbb` | no; stored once authored | As Assemblies (`features/assemblies/assembly/schema.rb`): reads show `display.color`, the stored colour or the ramp's by id, because the engine mints the id inside `propose_create` (P3b-02) |

`schema_version` 1 with this final field set, because the engine has no migrations. No
`created_at` or `updated_at` (D3b-05). `user_data` and `extension_data` are the engine's reserved
fields.

### Edge assignment (entity-owned record)

| Dictionary | Entity | Key | Identity |
| --- | --- | --- | --- |
| `ph_composer.thermal_bridge` (new) | The `Sketchup::Edge` | `record`, through `Records::EntityStore` (exists) | `tbe_` id. The engine requires one on every reference-target record (section 8, question 1), which settles D3b-02's fallback. A split or a native copy duplicates it (B4); reads mark an id held by more than one Edge as `copied`, nothing re-issues it and no repair exists (D3b-22, answered 2026-10-21) |

| Field | Shape | Required | Note |
| --- | --- | --- | --- |
| `id` | `tbe_` plus twelve characters, `Identity.fresh` | yes | Proves identity in a reference, as `fac_` does; it is not a run's identity (D3b-07) |
| `thermal_bridge_type_id` | core `Records::Reference` to `ph_composer.thermal_bridges.type`, cardinality one | yes | A dangling id is a read state, not a repair. Because it is required, "clear" means removing the dictionary: `edges.clear`, and `types.delete` with an explicit null replacement, both remove the record rather than null the field |
| `quantity` | number, exclusive minimum 0 | yes, default 1 | D3b-08 |
| `schema_version`, `user_data`, `extension_data` | engine reserved | | `user_data` follows the EXTENSIBILITY copy policy; a native copy carries it verbatim |

### Edge reference target

| Target id | Occurrence reference | Records provider | `locate:` |
| --- | --- | --- | --- |
| `ph_composer.thermal_bridges.edge` (new) | `{ "zone_id", "zone_path", "entity_path", "entity_id" }`, the Face reference shape (`context/CONTRACTS.md`, "Geometry records and occurrence references"): `zone_path` root to the holding Zone, `entity_path` from inside the Zone to the Edge, `entity_id` the `tbe_` id or null for an unassigned Edge | A whole-Model walk for tagged Edges, every Group and ComponentInstance including shared definitions and cutting instances, so an orphaned or shared tag still blocks deleting its type; entries are `Records::ReferenceEntry(kind, key: path, record)` as `Zones::Faces::ReferenceTargets.entries` builds them | The owner's resolver over Zones' path resolution (H11): `Zones::Occurrences.resolve_element` resolves the Zone and every step and refuses with `target.*` codes; the owner checks the leaf is an Edge, refuses a path whose Edge gained or changed its record as `target.changed`, refuses no duplicated `tbe_` id (D3b-22), and never searches by geometry. `locate_index:` builds a `Zones::Index` (P3b-03) |

The target declares `references: [thermal_bridge_type_id]` so the engine's incoming-reference
scan refuses deleting a Thermal Bridge Type while an Edge names it, exactly as a Face naming an
Assembly does. Delete with replacement passes the rewritten occurrences to `propose_delete` as a
`reference_plan`. Because the type and its referrer are one feature, the delete calls its own
rewrite step directly; it registers no retargeter.

The Face shape is chosen over the Window unit's root-only `entity_path` because an Edge is
assignable only inside a Zone (PRD, "Assign") and the Zone's path is what `zones.containment`
answers; an orphaned tag outside every Zone is still found by the records provider, with an empty
`zone_path`, so it blocks the type's deletion and reads as `thermal_bridge.outside_zone`.

## 3. Operations

Every name starts with `ph_composer.thermal_bridges.`. Each query, action and view command is
registered with schemas and an example, so `docs/API_REFERENCE.md` regenerates and the reference
test covers it. Id params carry the prefix pattern, for example `^tbt_[A-Za-z0-9]{12}$`.

| Name | Verb | Stage | Purpose |
| --- | --- | --- | --- |
| `types.list` | query | P3b-02 | One bounded page of the same rows; the bounded read `types.all` names as `prefer` |
| `types.all` | query | P3b-02 | Every type with its values, `display.color`, `export_ready` and `export_blockers`. Used length is the schedule's `totals.by_type`, not a field here: snapshot sections are separate reads, so carrying it would walk the Model twice (P3b-04) |
| `types` | snapshot section | P3b-02 | The same projection for the panel |
| `types.create`, `types.update`, `types.duplicate` | action | P3b-02 | Values with `expected_values`; `user_data` |
| `types.delete` | action | P3b-02; replacement from P3b-03 | Guarded delete; with `replacement_id` every assigned Edge is rewritten to it, and with an explicit null every assigned Edge's dictionary is removed, in the same proposal and Undo step |
| `edges.assign` | action | P3b-03 | Explicit Edge references, a type id, a quantity, and each target's `expected_values`. Assign and reassign. One Undo step. Each target resolves through the Edge target's `locate:`, which already answers every containment refusal, so the action does not also call `zones.containment` (P3b-03) |
| `edges.clear` | action | P3b-03 | Explicit Edge references. Removes the assignment dictionary |
| `edges.selection` | query | P3b-03 | The current native selection as Edge references, each with its Zone containment, current assignment and write refusal; one bounded page, its cursor bound to the selection and the revision (P3b-03, Codex review) |
| `edges.selection_all` | query | P3b-03 | The same, unbounded, naming `edges.selection` as `prefer`; the panel section and the menu route read it |
| `edges.selected` | snapshot section | P3b-03 | `edges.selection_all`, for the panel's assign bar |
| `schedule.list` | query | P3b-04 | One bounded page of runs, each with identifier (`tb_` and a digest of Zone, type, container path and canonical points, D3b-07 and D3b-23), Zone and its Building-Segment, type, length in metres, psi, quantity, `heat_loss_w_k` (psi times length times quantity), points, Edge paths (what `runs.locate` takes) and findings; `totals` by type (run and Edge counts, used length, heat loss) and by group over every run; the first 50 `edge_findings` (assigned Edges no Zone holds) and unreadable assignments, with their counts. The runs share the page's byte budget with what travels beside them; one run larger than the budget is sent alone, so a run of a few hundred Edges can exceed a caller's reply budget until a `fields` projection exists (the catalog follow-up in STATUS) |
| `schedule.all` | query | P3b-04 | The same, unbounded, naming `schedule.list` as `prefer`. No snapshot section: D3b-13 measured it over the refresh budget (DECISIONS F37), so the panel reads it on opening the Schedule and on Refresh |
| `runs.locate` | view command | P3b-04 | Takes `edge_paths`, as a run's or finding's `locate` carries them (a run has no stored identity). Opens the Edges' container through the foundation's `ph_composer.context.open` code path (`ContextCommands.move`, D3a1-04), selects the Edges and frames their world points. Refuses Edges in different containers (`params.invalid`) and a hidden Edge or ancestor (`thermal_bridge.hidden`) |
| `assign_menu` | `menu_entries` | P3b-05 | "Thermal bridge" submenu on a selection of Edges: one item per type, then Clear |
| `by_type` | colour mode | P3b-06 | Assigned Edges in their type's colour at the mode's stroke weight; label carries total length (D3b-12) |
| `edge_tool.choose`, `edge_tool.stop` | view command | P3b-07 | Start the tool armed with a type, or stop it |
| `edge_tool` | snapshot section | P3b-07 | The armed type and whether the tool has the viewport |
| `edge_tool.state` | query | P3b-07 | What the snapshot section reads: `active`, `thermal_bridge_type_id`, `quantity` and `gesture_limit` |
| `export_preflight` | query | P3b-08 | The export preflight rows, passed to `export_contributor(preflight:)`; named as Zones', Windows' and Spaces' are |

Codes are declared once with `feature.code` in `features/thermal_bridges/codes.rb` under the noun
`thermal_bridge`. Refusals that Zones owns keep Zones' `target.*` codes.

Every registration is an agent-facing surface (DECISIONS F27). A stage that adds a name:

- declares the keywords the registry now takes: `response:` and `while_busy:` on a query,
  `preconditions:` and `transitions:` on an action, `side_effects:`, `preconditions:` and
  `capability:` on a view command (`view` for `runs.locate` and the edge tool's commands);
- bumps `API::MINOR` once and adds one `API::CHANGES` row naming the new or changed shapes
  (`context/CONTRACTS.md`, "API changes"), which the generated reference lists;
- adds or extends the thermal-bridge recipe in `docs/AGENT_GUIDE.md`, which
  `tests/agent_guide_test.rb` checks against the registry;
- states, for any pointer route, its explicit-reference equivalent (`context/AGENT_INTERFACE.md`,
  "Documentation and contributor obligations"): the edge tool's is `edges.assign`.

The MCP connection serves a fixed verb table over these registrations; no feature adds a tool.

## 4. Cross-feature seams

| From | To | Mechanism | Used for |
| --- | --- | --- | --- |
| Thermal bridges | Zones | `request.query("ph_composer.zones.containment", paths:)` (new, H11) | Which Zone occurrence holds an Edge path, its Building-Segment, and the `target.*` refusal a write through it meets |
| Thermal bridges | Zones | `request.query("ph_composer.zones.faces.host_context", ...)` (exists) on each assigned Edge's Faces | Whether the Edge bounds a classified envelope Face, and their boundary conditions, for the stray-line and interior-junction findings |
| Thermal bridges | Windows | `request.query("ph_composer.windows.units.outlines", ...)` (new, H16) (D3b-15) | World outline of each placed Unit, for the window-perimeter warning |
| Edge tool | Thermal bridges actions | `API.invoke` with its own caller handle | One gesture, one `edges.assign`, one Undo step |
| `runs.locate` | Foundation `ContextCommands` | `ph_composer.context.open(path)` (exists, D3a1-04) through `EditContext.enter` | Opening a nested Zone's context before selecting a run's Edges |
| `by_type` mode | `colour_by/` | `colour_mode` entries carrying the Edge as `entity` and its world segment as `derived` (P3a-05), with the stroke weight from H14 | The viewport colouring |
| Thermal-bridge contributor | Zones contributors | `requires:` the Zones and Faces sections, read with `reader.section` (P3b-08) | Zone id, path, name and Building-Segment per Zone occurrence (a projection the Zones section registers in P3b-08; no omission state exists, F38), and each Zone Face's record, for the Face findings |
| Thermal-bridge contributor | Windows contributor | `requires:` the Apertures section, read with `reader.section` (P3b-08) | Each placed Unit's world outline, the snapshot twin of `units.outlines`, for the window-perimeter note in the report |
| Thermal-bridge section (Python) | Zone section | `Requirement` on `ph_composer.zones.export.zones` and `Attachment(ROOM)` keyed by the Zone's Room identifier | Adds each run to the Room's shared `BldgSegment` |

Every arrow points down a layer, sideways to a layer 3 peer through a published read (Windows, D3b-15), or goes through the foundation. Zones and Windows each gain one read that names no
thermal-bridge concept.

## 5. Foundation and owner additions

Numbered after the Spaces bindings' H1 to H10. Each names no thermal-bridge concept and lands in
the stage listed with its own tests.

| # | Addition | Where | Stage |
| --- | --- | --- | --- |
| H11 | `ph_composer.zones.containment` (exists from P3b-03): for native root-to-entity paths, the Zone occurrence that holds each (`zone_id`, `zone_path`, `name` from P3b-04, `building_segment`, `level`) with the `entity_path` inside it, or none with a reason (`not_found` for a step missing or repeated, added by P3b-03; `outside_zone`, `cutting_instance`, `nested_container` under D3a-1, `not_a_drawing_element`), and the `write_refusal` a write through that path meets. Its Ruby half for a `locate:`, which has no request, is `Zones::Occurrences.resolve_element(model, reference, noun:, mutable:, index:)`. Built on what exists: `Zones::Occurrences.occurrence_at` and `occurrence_for_path` already resolve a path along its own collections to the innermost Zone and answer nil for those reasons without naming them, and accept a Face leaf only (DECISIONS F7). H11 generalises the leaf to any drawing element, returns the reason, and `host_context` keeps its Face-only shape over the same code | `features/zones/zone/occurrences.rb`, `features/zones/declarations/` | P3b-03 |
| H12 | `Pick.edge_path(view, x, y)` (new): the first pick path ending in a `Sketchup::Edge`, with the same rules as `face_path` | `core/pick.rb` | P3b-03 |
| H13 | Not needed. An Edge is drawn through P3a-05's `derived` segments (D3b-11); `colour_by/tessellation.rb` is unchanged. The number is kept so later references stay stable | none | none |
| H14 | A stroke weight for `derived` segments, declared per mode (`colour_mode(..., stroke:)`) (new), drawn on the per-colour line batch P3a-05 built (`colour_by/drawing.rb`, `@lines`; `overlay.rb`, `LINE_WIDTH`). One mode is active at a time, so one width per mode costs no extra pass (section 8, question 7) | `shell/registry.rb`, `shell/declarations.rb`, `colour_by/overlay.rb` | P3b-06 |
| H15 | Exists (G-02, PR #119). `GeometrySnapshot` records an `edge` entry for every Edge occurrence outside a cutting component: `path`, `transform`, `dictionaries`, `points_m` in world metres, `vertex_ids` and `face_ids` within its container. The contributor filters on its own dictionary. P3b-08 only measures the snapshot on the 50,000 Edge Model | `export/geometry_snapshot.rb` | done |
| H16 | `ph_composer.windows.units.outlines` (exists from P3b-08): for each placed Unit, bounded pages of its reference, host Face reference (or null) and world outline polygon in metres (D3b-15), from `ReadContext#read_polygon`. The nearest existing read, `units.host_extent`, gives the same outlines as bounding rectangles in a Face's own offsets for one host Face. Its export twin is the Apertures section's registered `projection:`, the outlines `ExportAssessment` already places, so the contributor reads them from the snapshot | `features/windows/declarations/units.rb`, `features/windows/units/outlines.rb`, `features/windows/export.rb` | P3b-08 |
| H17 | `PLANNING_IDS` already matches `P3b-01` and `D3b-02` (DECISIONS F15). Remaining: the acceptance ids (`T01`; `S01` for the archived Spaces register) and two-digit finding ids (`F26`) | `Makefile` | P3b-01 |
| H18 | Optional attaching sections (R05 item 4, D3b-20). `Section.required_for_export` exists (`sections.py:125`), and `_attach` already writes each refused object's `object.unavailable` finding with `blocks_export = required_for_export` (`assembly.py:77`). The one remaining gate: `assemble` sets `translation.canonical` only when every `_attach` returned complete (`assembly.py:40-47`), so an optional section's refusal still withholds the canonical model. Change: a refusal from a section with `required_for_export = False` does not withhold the model; a required section keeps today's rule | `python/ph_composer_translation/assembly.py`; `context/CONTRACTS.md`, "Translation sections and artifacts" | P3b-08, delivered |

`tools/ui-preview/host.js` publishes a fixed map of section names in its synthetic snapshot. Every
stage that adds a panel section adds its preview fixture there and a `*_checks.cjs` under
`tools/ui-preview/` through the shared browser-evidence collector, and regenerates the panel script
list with `make panel-manifest`.

## 6. Findings and export

Findings are `{code, section, object_id, message, blocks_export, locate}` from the preflight
query and the Python section. The same codes appear per run in `schedule` as `{code, message,
blocks_export, locate}`, `locate` naming the Edges the finding is about; P3b-08's preflight adds
`section` and `object_id`. `counted_twice` compares whole Edges: an Edge one Zone splits where the
other does not is not found (P3b-04).

| Code | PRD row or decision | Blocks export | Repair |
| --- | --- | --- | --- |
| `thermal_bridge.type_missing` | Assignment names a deleted type | yes | Reassign or Clear, by `runs.locate` |
| `thermal_bridge.psi_missing` | Type has no psi-value. Blocks only when an Edge is assigned to it (D3b-21) | yes, when assigned | Enter the psi-value |
| `thermal_bridge.outside_zone` | Assigned Edge outside any Zone group | no; not exported | Move into a Zone, or Clear |
| `thermal_bridge.no_envelope_face` | Assigned Edge bounds no classified envelope Face | no | Review; the likely cause is a stray line |
| `thermal_bridge.interior_junction` | D3b-16: every Zone Face on the Edge is Surface or To neighbour | no | Review |
| `thermal_bridge.counted_twice` | D3b-16: coincident with an assigned Edge in another Zone | no | Clear one |
| `thermal_bridge.shared_definition` | D3b-10: tag inside a shared definition, counted per occurrence | no | Informational |
| `thermal_bridge.on_window_perimeter` | Q11, D3b-15 | no | Clear; window install psi belongs to the Window Type |
| `thermal_bridge.zone_omitted` | The holding Zone is omitted from export. Not registered: no Zone omission state exists (DECISIONS F38); P3b-08 adds it only if the Zones section gains one | no; not exported | The Zone's own finding |
| `thermal_bridge.hidden` | P3b-04: `runs.locate` refuses an Edge, or a Group holding it, that is hidden or on a hidden tag | not a finding; a refusal | Show it and locate again |
| `object.unavailable` (foundation code, from the translation) | D3b-20: a run failed to translate or attach | no, because the section is optional; that run is not exported | The message carries the cause; the report lists the run |

The PRD's "type has no group" row is removed under D3b-04. "Two types on one edge" cannot occur:
an Edge holds one assignment dictionary.

| Section id | Object | Requires | Notes |
| --- | --- | --- | --- |
| `ph_composer.thermal_bridges.export.thermal_bridges` (exists from P3b-08) | One honeybee-ph `PhThermalBridge` per run: `Polyline3D`, or `LineSegment3D` for one Edge; `display_name`, `psi_value`, `group_type` 15, 16 or 17, `quantity`; `fRsi_value` and `is_interior_pipe` at their defaults | The Zones, Faces and Apertures sections (Ruby); `ph_composer.zones.export.zones` (Python) | Attaches at `ROOM`, keyed by the Room the Zone section builds; `attach` calls `add_new_thermal_bridge` on that Room's shared `ph_bldg_segment`. `required_for_export = False` (D3b-20): a run that fails to translate or attach is omitted with the assembly's non-blocking `object.unavailable` finding and the canonical pair is still written. `attach` validates every run before adding any, and raises `AttachmentRefused` naming only the refused runs, so no refused run is left half-added to the segment. Declares `user_data_keys: ["ph_composer.thermal_bridge_type_id"]`. Result fields: one row per run with identifier, Zone id, type id, length in metres, psi, quantity, group; `conformance` checks the reloaded `properties.ph.bldg_segments[*].thermal_bridges` against them |

The extraction contract is pinned by a fixture both Ruby and Python read
(`tests/fixtures/thermal_bridges/`), as the other sections are.

## 7. Questions P3b-01 answers

Five of the seven questions drafted on 2026-10-03 were answered by reading `420c783a` on
2026-10-21; the other two by a focused test in P3b-01 the same day. All seven are in section 8.
The host half of question 2 (the real `Sketchup::Edge` carrying a dictionary through Undo, save and
reopen) is B4's measured fact and T01's host gate, not the test's.

## 8. Contract answers, 2026-10-21

| Q | Answer | Evidence |
| --- | --- | --- |
| 1 | Yes. `reference_identity` refuses an entry whose `record["id"]` is not a non-empty String as `record.unreadable`, and `check_identity_removal!` names the referrer by `record.fetch("id")`. D3b-02's fallback applies: the assignment carries a `tbe_` id (section 2); the copy rule is D3b-22 | `core/records/reference_resolution.rb:70-72`, `:77-83` |
| 2 | Yes, with no change. `EntityStore` writes, reads and deletes a record on a stub Edge through the same `get_attribute`, `set_attribute` and `delete_attribute` every entity answers, and `EntityStore.new` registers the dictionary in `Dictionaries.names`. There is no export attribute guard over that list: `GeometrySnapshot.read_dictionaries` captures every `ph_composer.` dictionary by prefix, so the snapshot's `edge` entry for the Edge, inside a Group, carries the record beside its `vertex_ids` and `face_ids` whether or not the name is registered. The question's premise was wrong (DECISIONS F5, corrected); what the test proves is the capture boundary the contributor reads from | `tests/edge_record_contract_test.rb`, `test_an_entity_store_round_trips_a_record_on_an_edge_and_the_snapshot_reads_it`; `core/records/entity_store.rb:13` |
| 3 | Yes. `faces.host_context` answers each of an Edge's Faces by the Edge's path with the Face's id in place of the Edge's, with the Zone reference and the write refusal, and answers nothing for the Edge's own path. H11 therefore answers containment and the refusal for the Edge, and the Edge's Faces come from `faces.host_context` over the snapshot's `face_ids` | `tests/edge_record_contract_test.rb`, `test_host_context_answers_an_edges_faces_by_their_paths_and_nothing_for_the_edge_itself`; `features/zones/faces/operations.rb:87-99` |
| 4 | Yes, by precedent. Spaces requires Zones and reads `ph_composer.zones.faces.host_context` with native paths through `request.query` (`features/spaces/create_route.rb:13`, `mark_placement.rb:12`); the handler-side read validates params and result and detaches the result (`tests/feature_composition_test.rb`, `test_handler_read_uses_declared_dependency_and_validates_nested_params`). A Windows read behaves the same once `ph_composer.windows` is in `requires:` | `features/spaces/create_route.rb`; `shell/handler_request.rb` |
| 5 | Yes. Spaces attaches at `ROOM` keyed by the Zone id, which is the Room's identifier, after the Zone section's `MODEL` attach shares the segment; `test_room_attachment.py` reloads the result. The two-Rooms-one-segment test for runs is still P3b-08's | `python/ph_composer_translation/space_sections.py:50-55`; `assembly.py:40-47`; `tests/python/test_room_attachment.py:95` |
| 6 | Yes. `Preferences.unit_system` is read in Ruby, and the Colour-by service formats an entry's `figure` in the display units when it sums legend rows and draws the HUD. D3b-12 is met by giving each entry `figure: ["length", metres]`; the row reads "Parapet (12) 26.0 m" | `shell/preferences.rb`; `colour_by/legend.rb:19-41`; `colour_by/overlay.rb:142-146` |
| 7 | Yes. `Drawing` keeps one line batch per colour for derived outlines and segments, and the overlay sets `line_width` once before drawing them. A stroke per mode is one `line_width` value | `colour_by/drawing.rb:117-120`; `colour_by/overlay.rb:51-60` |
