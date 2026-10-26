# Phase 3, thermal bridges: findings from source, and the decisions that follow

DATE: 2026-10-03
STATUS: Complete 2026-10-26, archived with the packet; built as recorded in [STATUS.md](STATUS.md). Was: Scoped. Part 1 is findings read from source on `main` at `08c4807`, re-verified against `420c783a` in Part 1b on 2026-10-21. Part 2 was answered by Ed
on 2026-10-03, every row as recommended except D3b-20; see "Ed's answers". D3b-22 and D3b-23, added by the re-baseline, were answered as recommended on 2026-10-21. The interview is complete.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

The [PRD](PRD.md) was drafted on 2026-09-18 from a one-line brief, before the foundation, Phase 1
and Phase 2 existed, and it has not been interviewed. This file is the review of that PRD against
the code on `main` and against the B4 edge spike. Part 1 lists what the code, the spike and the
honeybee stack actually say. Part 2 lists the choices those facts force, each with a
recommendation. The bindings that follow from the recommendations are in
[CONTRACTS.md](CONTRACTS.md); they change when an answer differs.

These are Phase 3b's decisions, D3b-01 to D3b-23, with findings F1 to F36. Phase 3a (Spaces) has
its own [DECISIONS.md](../phase-03a-spaces/DECISIONS.md), D3a-1 to D3a-12 with its own F1 to F22;
a reference to one of those always says Phase 3a. Stages are P3b-01 to P3b-09, tracked in
[STATUS.md](STATUS.md). The ids were renumbered on 2026-10-03 when Phase 3 split into 3a and 3b
(D3-13 to D3-33 became D3b-01 to D3b-21, TF1 to TF26 became F1 to F26, P3-13 to P3-21 became
P3b-01 to P3b-09).

The answers to the PRD questions in Part 2 are the interview record. The PRD's decision table and
behavior sections and `context/UBIQUITOUS_LANGUAGE.md` were amended with them on 2026-10-03.

Paths are relative to `src/ph_composer/` unless stated. "Read from source" means the file was read,
not that the consequence was reproduced on a host or in a test.

## Part 1: findings

### Host and spike evidence

| # | Finding | Consequence |
| --- | --- | --- |
| F1 | [B4](../phase-00-foundation/evidence/spike-edge.md) measured that split, explode and native cut, copy and paste put an edge's whole dictionary on every new edge; weld, move and push-pull keep persistent ids; Undo, Redo and reopen restore everything. Its disposition 2 recommends a Model-level registry of expected edges so a scan can tell a split from a paste | The PRD's edge tagging rule 1 and Q1 say the opposite: the edge is the record and there is no separate index. See D3b-01 |
| F2 | B4 did not run: a push-pull that deletes a tagged edge, `Entities#intersect_with`, native Divide, the native Weld menu command. Nobody has run the reverse of a split: erase the crossing edge so SketchUp heals two collinear tagged halves into one edge | Which dictionary the healed edge keeps decides whether a split-then-heal changes a schedule. P3b-01 closes these on the host before any storage code |
| F3 | B4 disposition 4: an explode that lays a window sill over a tagged base edge leaves contiguous collinear tagged pieces that read as a legitimate split. [B3](../phase-00-foundation/evidence/spike-window.md) measured that a glued cutting unit leaves the host Face's loops unchanged | A window outline has no edges in the host wall unless the user draws them. The double-count case in PRD Q11 needs a rule that knows window geometry. See D3b-15 |

### Code on `main`

| # | Finding | Consequence |
| --- | --- | --- |
| F4 | `core/pick.rb` answers Face paths only and skips Edge picks explicitly (`:19`, `:39`). There is no edge or vertex pick | P3b-03 adds `Pick.edge_path` beside `face_path`. It names no feature |
| F5 | Nothing reads or writes an attribute on a `Sketchup::Edge`. `Records::EntityStore` (`core/records/entity_store.rb`) is entity-agnostic and `Dictionaries.register` only requires the `ph_composer.` prefix (`core/dictionaries.rb:11`) | The edge store needs no core change |
| F6 | The Face reference target declares its Assembly reference (`features/zones/declarations/faces.rb:14-23`, registered at `:197`) over a whole-Model walk that includes orphans and shared definitions (`features/zones/faces/reference_targets.rb:17-31`). Face records carry a `fac_` id that the schema requires (`features/zones/faces/schema.rb`) | An edge reference target follows the same shape so the engine refuses deleting a Thermal Bridge Type in use. Whether a target's records must carry an id is not yet confirmed from code. See D3b-02 |
| F7 | `Zones::Occurrences.walk_faces` skips nested Zones and cutting instances (`features/zones/zone/occurrences.rb:325-344`); `Zones::Index` caches Zones and Faces only (`features/zones/zone/index.rb`). Face selection refuses anything that is not a Face (`features/zones/faces/selection.rb:11`). `faces.host_context` answers Face paths only | No published read tells another feature which Zone holds an arbitrary native path. Re-implementing the Zone membership rules in thermal bridges would split one authority. See D3b-09 |
| F8 | Colour-by tessellates Faces and recurses into containers; an Edge entry yields no triangles and no segments, so it draws nothing (`colour_by/tessellation.rb:56-73`). Classified Faces draw fills only; the overlay draws outlines only for unclassified Faces (`colour_by/overlay.rb:48-60`). The HUD writes `label (count)` per value | The mode cannot draw today. The contract already promises "the service tessellates whatever entity an entry carries"; an Edge is the first non-Face, non-container entity. See D3b-11 and D3b-12 |
| F9 | The export `GeometrySnapshot` emits nothing for an Edge (`export/geometry_snapshot.rb:74-101`, the `else` branch). It already reads every entity's dictionaries before the type test. Edges appear only inside component definition facts (`:129`) | P3b-08 adds an `edge` entry for edges that carry a registered dictionary, under the same cutting-instance rule as Faces. The added cost is one entry per tagged edge |
| F10 | `ZoneSection.attach` runs at the `MODEL` level and gives every Room of one Building-Segment one shared honeybee-ph `BldgSegment` (`python/ph_composer_translation/model_sections.py:230-239`). The assembly attaches `MODEL`, then `ROOM`, then `FACE` (`python/ph_composer_translation/assembly.py:41-55`); no section uses `ROOM` yet | A thermal-bridge section attaches at `ROOM`, keyed by the Zone's Room, and adds to that Room's shared segment. The Zone section names nothing about thermal bridges |
| F11 | Units already carry `linear_psi` (`W/(m K)`, signed) and `length` in Ruby (`core/units.rb:24-50`), JavaScript (`html/unit_tables.js:37,56`) and field descriptors (`html/fields.js`, `LINEAR_PSI`, `LENGTH_M`) | No new quantity. The units packet needs no thermal-bridge allocation |
| F12 | `Fields.common` gives `name`, `notes`, `datasheet_links` and `source` (`core/records/authoring_fields.rb`), which also validates a hex `color`. Assemblies default a colour from a ramp (`features/assemblies/assembly/schema.rb:27,47,89`) | The Thermal Bridge Type reuses these. The PRD's `created_at` and `updated_at` go, as D2-4 removed them from every Phase 2 kind. See D3b-05 |
| F13 | The Psi-Install Type has `psi_w_mk` and no group (`features/windows/products/schema.rb:54`). Window install psi is computed per Window Type element side from the type's grid, never from Model edges (`features/windows/types/thermal.rb:107-131`, `features/windows/export_assessment.rb:246-255`) | No Model edge is a window edge today. A thermal bridge drawn around a window is invisible to Windows, and Windows is invisible to it |
| F14 | The tab row has a disabled `Thermal Bridges · Planned` button with no `data-tab`, and panes are static (`html/index.html:18-26`, `:35-39`); `panel.section` throws for a missing pane (`html/panel.js:170`) | Enabling the tab is a composition-root edit to `index.html`, which the rules permit |
| F15 | The citation lint's `PLANNING_IDS` (`Makefile:59`) matches ids such as `P1-A`, `Q12`, `D3`, `R05` and `A01`. It does not match a numbered stage such as `P3b-01`, nor `S01`, `T01` or `F1`; `D3b-01` is caught only through its `D3` prefix | P3b-01 extends the pattern to the Phase 3 stage, acceptance and finding ids, so none can leak into `src/` or `tests/`. If P3a-01 has already extended it for Spaces, P3b-01 adds only `T` and `TF` |

### honeybee-ph and PHX

Read from the vendored honeybee-ph 1.33.65 wheel and the sibling repositories. The three
honeybee-ph files cited are byte-identical between the wheel and the repository.

| # | Finding | Consequence |
| --- | --- | --- |
| F16 | `PhThermalBridge(_identifier, _geometry)`: `display_name`, `quantity` 1.0, `group_type` 15, `psi_value` 0.1, `fRsi_value` 0.75, `is_interior_pipe` False; geometry is a `LineSegment3D` or `Polyline3D` and `length` comes from it. The group enum's strings are `15-Ambient`, `16-Perimeter`, `17-FS/BC`. Nothing is range-checked (`honeybee_energy_ph/construction/thermal_bridge.py:31-143`) | The PRD's mapping holds. `fRsi_value` and `is_interior_pipe` keep their defaults |
| F17 | `BldgSegment.thermal_bridges` is a dict keyed by identifier, filled by `add_new_thermal_bridge` (`honeybee_ph/bldg_segment.py:353`, `:379-391`). The Model writes `bldg_segments` deduplicated by segment identifier, last Room wins, with no union of thermal bridges (`honeybee_ph/properties/model.py:85-88` in the wheel); Rooms carry only `ph_bldg_segment_id` | Every Room of a Building-Segment must hold the same segment object, or thermal bridges are silently dropped. F10 shows the Zone section already does this. A conformance check after reload proves it per export |
| F18 | PHX writes one METr row per thermal bridge: `n`, `typeTbZ` as the negated group, `lengthTbZ`, `psiTbZ`; no quantity and no fRsi (`PHX/to_METr_JSON/metr_schemas.py:1062-1071`). Quantity is folded into length only when `merge_thermal_bridges` reduces two or more bridges sharing group, psi and name (`PHX/model/components.py:895-929`, `PHX/model/building.py:161-176`) | Read from source, not reproduced: a lone thermal bridge with quantity 2 would reach METr at quantity 1. HBJSON is canonical and keeps quantity. The consumer check goes to [metr-export](../../features/unscheduled/metr-export/README.md). See D3b-08 |
| F19 | PHX merges a Building-Segment's Rooms by duplicating the first Room's ph properties (`PHX/from_HBJSON/cleanup.py:525,567`) | Consistent with F17: a shared segment is what PHX expects |
| F20 | PHX names group 17 `UNDERGROUND`, "in contact with ground" (`PHX/model/enums/building.py:143-154`); honeybee-ph's docstring says "floor slab / boundary condition". No writer emits a text label | The PRD's provisional key `FloorSlabBasementCeiling` is a third vocabulary. See D3b-03 |
| F21 | There is no point thermal bridge class in honeybee-ph or PHX. The only chi-value is on `PhWindowFrameElement` | D3 stands unchanged |

### Planning

| # | Finding | Consequence |
| --- | --- | --- |
| F22 | METr export is deferred (D12) and no PHX wheel is vendored | The PRD's METr acceptance rows move to metr-export, as Phase 2 moved every "Through PHX" step. This feature closes on HBJSON reloaded in the pinned honeybee stack |
| F23 | The geometry-first rule (`context/TECH_STACK.md`, "Rules for later features"): select, then act; a modal tool is secondary unless the plan records why | Assign by selection is primary. The edge tool is the secondary route, kept because Phase 4 piping and ducting reuse its shape (roadmap 3.2) |
| F24 | The validation-and-export packet owes four export-run items from R05 ([STATUS](../../features/cross-phase/validation-and-export/STATUS.md), "Owed from the Phase 2 review"). The Spaces plan allocates items 1 (the empty Room) and 2 (section-read cycles) to P3a-01 and item 3 to P3a-10, and D3a-9 leaves item 4, an optional attaching section that refuses, owed until an optional section exists | P3a-01 is the entry gate of P3b-08. Ed made the thermal-bridge section optional (D3b-20), so P3b-08 settles item 4 |
| F25 | The Spaces plan builds the Colour-by extension in P3a-05: an `Entry` may carry `derived` world-space polygons and segments that the service fills and outlines in the entry's colour (D3a-5). That is the first draw path for coloured segments | Thermal bridges need coloured, heavy segments over live Edges. They are a third user of P3a-05's `derived` segments, not a reason for a second draw path. See D3b-11 |
| F26 | Assemblies' preflight reports an incomplete Assembly as a non-blocking row (`features/assemblies/export.rb:53-58`, `blocks_export` false); the blocking row comes from the Face that uses it. The PRD's "type has no psi-value" row says only "blocks export" | An unused incomplete Thermal Bridge Type would block export under a literal reading. See D3b-21 |

## Part 1b: re-verification against `main` at `420c783a`, 2026-10-21

385 commits landed between `08c4807` and `420c783a`: Phase 3a Spaces (PRs #135 to #190), the
agent-access phase 3a1 (PRs #222 to #243), G-02 of the geometry contribution contracts (PR #119),
the Ruby readability program (PR #208 among others), security hardening, production support
(PRs #246 to #253) and developer observability. Every finding was read again from source; nothing
was reproduced. Part 1 above is kept as written at `08c4807`; this table is the current reading.
Line numbers are those of `420c783a`.

| # | Now | Current state and consequence | Evidence on `420c783a` |
| --- | --- | --- | --- |
| F1 | Holds | B4's facts are in `context/SKETCHUP_HOST_BEHAVIOR.md`, "Components, glue and edge attributes"; the registry question was answered by D3b-01 | `context/SKETCHUP_HOST_BEHAVIOR.md:137-147` |
| F2 | Holds | The spike still runs split, API weld, move, a face push-pull, window cut and window explode; native Divide, the Weld menu command, `intersect_with`, a push-pull that deletes the tagged edge and the heal are unrun | `tools/spikes/edge/edge_spike.rb:41-49` |
| F3 | Holds | No Model edge is a window edge; see F13 and F34 | |
| F4 | Holds | `Pick` answers `face_path` and `face_point` only, and its comment still says an Edge pick is skipped; Mark floor is its second user. H12 stands | `core/pick.rb:19`, `:31-42`, `:47` |
| F5 | Holds, corrected | `EntityStore.new` registers its dictionary; the registry registers every prepared dictionary. Export does not filter on that list: `GeometrySnapshot.read_dictionaries` captures every dictionary under the `ph_composer.` prefix, registered or not, so `Dictionaries.names` is the inventory of owned names and no export gate. The comment in `core/dictionaries.rb` that said otherwise is corrected by P3b-01 | `core/records/entity_store.rb:13`; `shell/registry.rb:157`; `export/geometry_snapshot.rb`, `read_dictionaries` |
| F6 | Settled | A reference target's records must carry an id: `reference_identity` refuses an entry whose `record["id"]` is not a non-empty String as `record.unreadable`, and `check_identity_removal!` names the referrer by `record.fetch("id")`. D3b-02's fallback applies: the assignment carries a `tbe_` id. What follows for copies is D3b-22 | `core/records/reference_resolution.rb:70-72`, `:77-83` |
| F7 | Changed | Still no published containment read. Zones now resolves an arbitrary native root-to-leaf path in one place: `Occurrences.occurrence_at(model, path)` walks only the collections along the path and `occurrence_for_path` answers the innermost Zone's `FaceOccurrence`, or nil for four reasons it does not distinguish (the leaf is not a Face, a cutting instance on the path, no Zone on the path, a container between the Zone and the leaf, which is the D3a-1 nested-container rule); `write_refusal(occurrence)` answers the `target.*` refusal; `host_context` is a thin read over the two. `occurrences.rb` was refactored by PR #208, so P3b-03 reads it afresh. H11 generalises `occurrence_for_path` to an Edge leaf and reports the reason instead of nil | `features/zones/zone/occurrences.rb:124`, `:184-243`; `features/zones/faces/operations.rb:87-99` |
| F8 | Superseded | P3a-05 shipped `derived` geometry: segments are tessellated into one per-colour line batch and drawn at the overlay's `LINE_WIDTH`; the Window Type operation marks are the second user. `colour_mode` takes `label:`, `entity_kind:`, `colours:`, `sort:` and `group:` and no stroke, so H14 stands. New: an `Entry#figure` (`[quantity, si_value]` pairs) is summed per legend row and shown in the display units as "label (count) figure", which is what D3b-12 asked for, in the service's own format | `colour_by/drawing.rb:101-120`; `colour_by/overlay.rb:51-60`, `:142-146`; `colour_by/legend.rb:19-41`; `shell/registry.rb:444`; `features/windows/colour_modes.rb:32-42` |
| F9 | Superseded | G-02 (PR #119) added `edge` entries to `GeometrySnapshot`: `points_m` in world metres, `vertex_ids` and `face_ids` within the Edge's container, dictionaries, under the Face rule for cutting components. H15 exists; P3b-08 adds a contributor only | `export/geometry_snapshot.rb:34-56`, `:111-116` |
| F10 | Changed | Spaces is the first `ROOM` attaching section, keyed by the Zone id that is the Room identifier, and `test_room_attachment.py` proves the hand-off. `assemble` still sets the canonical model only when every `_attach` returned complete, whatever `required_for_export` says; the finding it writes already carries `blocks_export = required_for_export`. H18 is narrowed to that one gate | `python/ph_composer_translation/space_sections.py:50-55`; `assembly.py:40-47`, `:60-80`; `tests/python/test_room_attachment.py:95` |
| F11 | Holds | `linear_psi` and `length` unchanged | `core/units.rb:49`; `html/fields.js:9`, `:19`; `html/unit_tables.js:56` |
| F12 | Holds | | `core/records/authoring_fields.rb`; `features/assemblies/assembly/schema.rb` |
| F13 | Holds | | `features/windows/products/schema.rb`; `features/windows/types/thermal.rb` |
| F14 | Changed | P3a-06 landed: the tab row is Zones, Assemblies, Window Types, Library, Export, then Thermal Bridges and Systems disabled with `data-tooltip="Planned"` and an aria-label; panes `overview`, `windows`, `assemblies`, `library`, `export`. The panel script list between the `panel-modules` markers is generated by `tools/panel_manifest.js` (`make panel-manifest`, checked by `panel-manifest-check`) | `html/index.html:24-30`, `:39-43`, `:48` |
| F15 | Changed | `PLANNING_IDS` now matches a lettered stage (`P3b-01`) and decision (`D3b-02`) through `P\d+[a-z]\d*-\d+` and `D\d+[a-z]\d*-\d+`; `F\d` matches one digit only. Planted `T01`, `S01` and `F26` pass the lint. H17 narrows to the T ids and two-digit F ids | `Makefile:81` |
| F16 to F21 | Hold | honeybee-ph is still pinned at 1.33.65; no PHX wheel | `vendor/wheels/`; `vendor/manifest.json` |
| F22 | Holds | | |
| F23 | Holds | | `context/TECH_STACK.md:592-640` |
| F24 | Changed | R05 items 1 (P3a-01), 2 (PR #122) and 3 (P3a-10 slice B) are delivered. Item 4 alone remains, with P3b-08 | [validation-and-export STATUS](../../features/cross-phase/validation-and-export/STATUS.md), "Owed from the Phase 2 review" |
| F25 | Settled | P3a-05 shipped `derived`, and D3a-5 settled one line primitive: an Edge entry carries the Edge as `entity` and its world segment in `derived`; a mode that needs a heavier stroke declares it on the mode (thermal bridges) | `context/EXTENSIBILITY.md`, "Colour-by derived geometry", "One line primitive" |
| F26 | Holds | | `features/assemblies/export.rb` |

### New since `08c4807`, not covered by F1 to F26

| # | Finding | Consequence for thermal bridges |
| --- | --- | --- |
| F27 | The agent-access phase made every registration an agent-facing surface. `query` takes `response:` and `while_busy:`; `action` takes `preconditions:` and `transitions:`; `view_command` takes `side_effects:`, `preconditions:` and a `capability:` from `read`, `view`, `model_write`, `setup`, `export`, `capture`. Every shape change bumps `API::MINOR` once and adds one `API::CHANGES` row, listed in the generated reference under "API changes". `docs/AGENT_GUIDE.md` holds one recipe per feature and `tests/agent_guide_test.rb` checks every operation it names is registered. The MCP connection serves a fixed verb table, so a feature adds no tool of its own | Each stage that adds an operation declares those keywords, bumps the API minor with a change row, and extends the agent guide. Bound in CONTRACTS section 3 and the stage documents (`shell/registry.rb:364-400`; `context/CONTRACTS.md:87-88`; `agent_access/tools.rb:119`) |
| F28 | D3a1-04 gave the foundation edit-context navigation: `ph_composer.context.open(path)` and `ph_composer.context.root`, view commands run through `EditContext.enter` so every registered boundary fires, refusing a locked entity as `target.locked`. The decision names P3b-03 as needing the same step and rejects Zones-owned navigation | `runs.locate` into a nested Zone opens the context through the foundation command; thermal bridges adds no navigation of its own (`planning/archive/phase-03a1/DECISIONS.md`, D3a1-04; `session/edit_context.rb`) |
| F29 | Mark floor (`features/spaces/mark_tool.rb`) is the newest viewport tool and the Phase 3a handoff names it as the shape to reuse: no operation of its own, one `invoke` per gesture, `Pick.face_path`, `DragSet`, `ColourBy::Lease`, a move without `MK_LBUTTON` cancels. `context/EXTENSIBILITY.md`, "Viewport tools", already names the thermal-bridge edge tool as the next user | P3b-07 adapts Mark floor rather than Classify; the rules are unchanged |
| F30 | The host kit grew bounded waits (`host_bridge.py wait-for`), a diagnostic reader (`diagnostics`), named fault controls (`fault arm|observe|restore` for `lost_reply`, `silent_runtime`, `failed_write` on a synthetic fixture) and `acceptance_case.py begin|finish`; browser checks run through `tools/ui-preview/support/browser_evidence.cjs`. AGENTS.md makes them the way a host is observed | Every host gate names them. T08's "force one run's attach to refuse" is not one of the three named faults: P3b-08 proves it offline through the Python section's test seam, or adds a named fault, and says which (`tools/hostkit/.index.md`) |
| F31 | D3a-20 landed in `tools/runtime/vendor.py`: `installed_target_bytes` 24,000,000, `installed_ceiling_bytes` 26,000,000, `installed_baseline_bytes` 23,994,083 (the Phase 3a close), `installed_growth_bytes` 1,500,000; `vendor.py --check` enforces them | T09 reads the numbers from there and resets the baseline at the phase close by a recorded decision (`tools/runtime/vendor.py:147-160`) |
| F32 | Native-acceptance case prefixes in use are `A`, `E`, `S`, `R`, `UXR`, `PS`, `DV`, `ZO`, `GH`, `SH`, `UXK`, `HGUI` and `PTAB`; a case row carries `authority`, `id`, `label`, `mode`, `native_control_required` and `paths` | `T` is free for T01 to T09 (`planning/native-acceptance/cases.json`) |
| F33 | The Spaces export contributor is the closest precedent for P3b-08's: `export_contributor(SECTION, section_version: 1, preflight:, requires: [ZONES_SECTION])` with a registered `export_preflight` query, reading the Zones section with `reader.section`; its Python section attaches at `ROOM` with a `Requirement` on the Zones section | P3b-08's Source table points at `features/spaces/export.rb` and `space_sections.py` beside the Windows pair |
| F34 | Windows publishes `units.host_extent`: a Zone Face's outline and the Window outlines on its plane, as bounding rectangles in the Face's own offsets, for `units.place` | The nearest existing read to H16, but in Face-plane offsets. H16 (world outlines per placed Unit, in metres) is still new and projects the same geometry (`features/windows/declarations/units.rb:224-245`) |
| F35 | `Preferences.unit_system` is readable in Ruby and the overlay already formats HUD readouts and legend figures with it | CONTRACTS section 7 question 6 is answered; D3b-12 needs no fallback (`shell/preferences.rb`; `colour_by/overlay.rb:68`, `:144`) |
| F37 | Added by P3b-04, measured on 26.1.188 2026-10-25. `zones.containment` and `faces.host_context` resolved each path by scanning every collection along it, so 5,000 Edge paths into Zones of 5,000 Edges cost 10.2 s and 12.2 s, and `schedule.all` 22.6 s. A per-read `Zones::ChildLookup` scans each collection once: 0.59 s and 0.77 s, `schedule.all` 1.83 s (median of five; walk 125 ms) with the 25,020 Faces unclassified, and 0.61 s, 0.79 s and 1.98 s with every Face classified. What remains is per path: building the Zone occurrence and write refusal (about 30 ms per 500 paths) and validating each published result | D3b-13 falls back to the schedule on request; the lookup ships with this stage because without it the read is unusable on request too (`_private/host/t04/measurement.json`) |
| F38 | Added by P3b-04. No Zone omission state exists on `main`: a Zone exports or its finding blocks the whole export, and nothing marks one omitted | `thermal_bridge.zone_omitted` (CONTRACTS section 6) has no case to fire on and is not registered; P3b-08 adds it only if the Zones section gains an omission state |
| F39 | Added by P3b-04. ACCEPTANCE's shared-wall case expected `interior_junction` on the two x = 5 m roof Edges, but each also bounds its Zone's Outdoors roof, and D3b-16 needs every Zone Face on the Edge to be Surface or To neighbour | The case expects `counted_twice` only; ACCEPTANCE corrected. D3b-16 is unchanged |
| F40 | Added by P3b-04. On the measurement Model (25,020 Faces) the panel snapshot costs 11.96 s without any thermal-bridge section, almost all of it Zones' own whole-Model sections | Outside this packet; recorded as a follow-up, not a thermal-bridge cost |
| F36 | The units packet measured the Zones repaint at 161 ms with every row open against a 200 ms target (PR #289, 2026-10-21). The UI baseline has no Thermal Bridges screen, only the tab row; `docs/PRODUCT.md` already describes thermal bridges as proposed | D3b-13's refresh budget is that 200 ms target. P3b-05 reads the Assemblies and Window Types rows of the baseline, not a Thermal Bridges row |

## Part 2: decisions for Ed

The PRD's eleven questions are listed first with their state. The plan decisions follow. Each row
names the stages it blocks. A stage does not start until every row it names has an answer.

### PRD questions

| Q | Question | State | Recommendation | Blocks |
| --- | --- | --- | --- | --- |
| Q1 | Does the assignment live on the edge, with no separate record? | Answered 2026-10-03; refined by D3b-01, D3b-02 | Yes | P3b-03 |
| Q2 | One psi-value per type, or an override per assignment? | Answered 2026-10-03 | Per type only | P3b-02 |
| Q3 | Point thermal bridges and chi-values | Confirmed by D3 | Linear only | none |
| Q4 | Group words: METr's or honeybee-ph's? | Answered 2026-10-03; refined by D3b-03, D3b-04 | Store honeybee-ph's, show METr's | P3b-02 |
| Q5 | Do connected same-type edges merge into one exported thermal bridge? | Answered 2026-10-03; refined by D3b-06, D3b-07 | Yes, as maximal chains | P3b-04 |
| Q6 | Is `quantity` exposed? | Answered 2026-10-03; refined by D3b-08 | Yes, default 1 | P3b-03 |
| Q7 | A shared edge between two Zones: which Zone owns it? | Answered 2026-10-03; refined by D3b-16 | The Zone group that holds it; interior and doubled edges are warnings | P3b-04 |
| Q8 | Are Thermal Bridge Types a fifth library kind? | Answered 2026-10-03 | Not now; first candidate for roadmap 5.4 | none |
| Q9 | Does a type link to its psi-value calculation report? | Answered 2026-10-03 | Yes, `datasheet_links` from `Fields.common` | P3b-02 |
| Q10 | Where is the tab? | Answered 2026-10-03; refined by D3b-17 | The reserved Thermal Bridges tab | P3b-05 |
| Q11 | May a Thermal Bridge Type sit on a window perimeter? | Answered 2026-10-03; refined by D3b-15 | No; a warning when it does | P3b-08 |

### Plan decisions

| ID | Question | Recommendation | Blocks |
| --- | --- | --- | --- |
| D3b-01 | Does thermal bridges keep B4's Model-level registry of expected edges? (F1) | No. The edge is the record, as Q1 says. A thermal-bridge assignment has no identity beyond its edge, type and quantity, so the two outcomes the registry separates are both correct here: a split keeps total length, and a pasted copy is a real second edge with the same detail. The registry earns its cost only where an assignment has identity other things point at, which is piping's parent references. Record it as piping's and ducting's decision, not a shared rule | P3b-03 |
| D3b-02 | Does an edge assignment carry an id? (F6) | No id, if the reference-target contract allows a record keyed only by its occurrence. P3b-01 reads the descriptor and `ReferenceEntry` contract and records the answer. If an id is required, use `tbe_` with the Window unit rule: reads report copies, the next thermal-bridge action re-issues ids inside its own proposal | P3b-03 |
| D3b-03 | Which words are stored for the group? (F16, F20) | honeybee-ph's enum strings, `15-Ambient`, `16-Perimeter`, `17-FS/BC`, the way Faces store `RoofCeiling` and show Roof (U2). The screen shows METr's words. P3b-05 confirmed METr's third word on its screen on 2026-10-26: "Basement floor" (beside "Ambient" and "Perimeter"), which the panel shows | P3b-02 |
| D3b-04 | May a type have no group? | No. A new type defaults to `15-Ambient`, and the field is required. This removes the PRD's "type has no group" warning row, which existed only to explain a silent fallback to Ambient | P3b-02 |
| D3b-05 | Which common fields does the type keep? (F12) | `Fields.common` (name, notes, `datasheet_links`, `source`) plus `psi_w_mk`, `group` and `color`. No `created_at` or `updated_at`, per D2-4 | P3b-02 |
| D3b-06 | What exactly is a run? (Q5) | Edges with the same Zone, type and quantity, connected where world endpoints coincide within the 0.0254 mm tolerance in `context/SKETCHUP_HOST_BEHAVIOR.md`. A run is a maximal chain that ends at a free end or at a vertex where the count of such edges is not two. A closed chain is one closed `Polyline3D`; a single edge is a `LineSegment3D`. A T of three same-type edges is three runs, because a polyline cannot branch | P3b-04 |
| D3b-07 | How are runs named and identified? | `display_name` is the type name and a counter, numbered per type across the Model in order of Building-Segment, Zone name and the run's lexicographically smallest endpoint. The identifier is `tb_` and a digest of Zone id, type id and the run's canonical endpoints. Both are derived and may change when the geometry does; nothing points at a run. Distinct names keep PHX from merging runs into one METr row (F18) | P3b-04 |
| D3b-08 | Keep `quantity` given that PHX appears to drop it for a lone bridge? (F18) | Keep it, default 1, positive. HBJSON is the canonical artifact and is correct with it; the repository never bends correct HBJSON to a consumer. Record the PHX observation in metr-export as unreproduced. The alternative, hiding quantity until METr is checked, loses a real modelling need: a detail repeated on floors that are not drawn | P3b-03 |
| D3b-09 | Who decides which Zone holds an edge? (F7) | Zones. It publishes one read, `ph_composer.zones.containment`, that answers for native paths which Zone occurrence holds each one, its Building-Segment, and the `target.*` refusal a write through that path meets. It walks only along each path, like `host_context`, so a pointer move may call it. Thermal bridges never restates the nested-Zone, wrapper-group or cutting-instance rules. This is the onion shape: Zones stays the single authority on containment and knows nothing about edges | P3b-03 |
| D3b-10 | What happens to edges reached through shared storage? | Writes refuse with the Zones `target.*` codes, as Face writes do: a ComponentInstance on the path, a locked Group, another Zone. Tags already inside a shared definition (copied there by Make Component) count once per occurrence in the schedule and the export, because each occurrence is real geometry, and the schedule marks them shared | P3b-03, P3b-04 |
| D3b-11 | How does Colour-by draw an edge? (F8, F25) | Through P3a-05's `derived` geometry, as its third user. Each `by_type` entry carries the Edge as its `entity`, so Locate, Show only this and visibility along the occurrence path keep working, and supplies the Edge's one world segment in `derived`, which P3a-05 draws in the entry's colour. Tessellation is not changed. P3b-06 adds one thing to P3a-05's contract: a stroke weight for derived segments, declared by the mode, because a thermal bridge drawn at outline weight disappears into SketchUp's own edges. The alternatives are larger: teaching the overlay to draw tessellated segments for classified entries, or a separate edge draw path built before P3a-05, which gives the overlay two ways to draw a coloured line | P3b-06 |
| D3b-12 | Does the HUD legend show lengths? | Yes, without a contract change: the mode's projection already sees every assigned edge, so each value's label carries its total length in display units, for example "Parapet, 26.0 m". The count after it stays the edge count. P3b-06 confirms Ruby can read the display-unit preference; if it cannot, the HUD shows metres and the panel legend shows display units | P3b-06 |
| D3b-13 | Is the schedule live, or scanned on request? (PRD edge tagging rule 3) | Live, as D2-3 decided for Assembly usage: a snapshot section backed by one read, measured in P3b-04 at 5,000 assigned edges in a Model of 50,000 edges. If it exceeds the refresh budget, fall back to the PRD's scan on panel open and Refresh | P3b-04 |
| D3b-14 | What bounds one assign gesture? | A limit owned by the thermal-bridge schema, starting at 250 edge occurrences like the Face limit, one over refusing the whole gesture as `gesture.too_large`. P3b-03 measures the assign cost at that size and P3b-07 rechecks it for a drag | P3b-03, P3b-07 |
| D3b-15 | How is a thermal bridge on a window perimeter caught? (Q11, F3, F13) | A warning, not a block. Thermal bridges requires `ph_composer.windows` and reads one new published Windows read, the world outline of each placed Unit. An assigned edge lying on a Unit's outline within tolerance gets `thermal_bridge.on_window_perimeter`. Cheaper alternative: drop the check and say in the Export report that window install psi is owned by Window Types. Because B3 shows a window adds no edges to its wall, the case arises only when the user draws lines around a window | P3b-08 |
| D3b-16 | Which junction findings does the schedule raise? (Q7) | Two warnings. An assigned edge whose Zone Faces are all Surface or To neighbour is an interior junction. An assigned edge coincident with an assigned edge in another Zone is counted twice. Neither blocks export | P3b-04 |
| D3b-17 | How is the tab laid out? (Q10) | The Thermal Bridges tab with two subtabs, Types and Schedule, using the shared subtabs module like Window Types, rather than the PRD's stacked tables. The assign controls sit in Types. The UI polish review in P3b-05 may revise this | P3b-05 |
| D3b-18 | Does the edge tool stay in this feature? (F23) | Yes, as P3b-07, the last authoring stage. Select then Assign is primary; the tool is the secondary route and the shape Phase 4 reuses. If cost forces a cut, P3b-07 moves to Phase 4 with piping and the exit loses nothing | P3b-07 |
| D3b-19 | Where does this plan live? | Stage documents with the Spaces stages in one phase folder, one phase tracker, feature records in the packet. Superseded the same day: Ed split Phase 3 into two flat packets, `phase-03a-spaces/` and `phase-03b-thermal-bridges/`, each with its own stages, tracker and records | none |
| D3b-20 | Is the thermal-bridge export section required for export? (F24) | Yes, as D3a-9 rules for Spaces. A run that fails to translate or to attach blocks the canonical pair. Ruby filters what is not exportable before translation, with its own findings (an edge outside every Zone, an edge of an omitted Zone), so a translation failure is a real fault. R05 item 4 therefore stays owed with validation-and-export | P3b-08 |
| D3b-21 | Does a type with no psi-value block export when nothing uses it? (F26) | No. It blocks only when an Edge is assigned to it, following the Assemblies precedent: a definition reports its own incompleteness without blocking, and the use blocks. `types.all` still shows it as not export-ready | P3b-04, P3b-08 |
| D3b-22 | Added 2026-10-21. The engine requires an id on every reference-target record (F6), so the assignment carries a `tbe_` id. Does a copied or split Edge's duplicated id need the Window-unit re-issue, which D3b-02's fallback named? | No re-issue. B4 says every split and copy carries the dictionary, id included, so duplicates are routine, not a fault. Nothing points at an assignment: runs are derived (D3b-07) and the type is the only reference, so a duplicated `tbe_` breaks no lookup. The id proves identity in a reference (`entity_id`, as `fac_` does for a Face: a path that gained or changed its record refuses `target.changed`), reads mark an id held by more than one Edge as `copied`, and no action re-issues ids and no repair operation exists. The alternative, Windows' rule (every action re-issues copies first, a `copy_id_pending` finding and a repair action), buys nothing here and adds a write to every gesture after a split | P3b-03 |
| D3b-23 | Added 2026-10-21, G-01's question. How does the run builder decide two Edges connect, now that the snapshot carries `vertex_ids` (F9)? | By a shared vertex keyed on the Edge's container path plus the vertex id, within one Zone occurrence. SketchUp merges endpoints within 0.0254 mm inside one Entities collection, so inside one container the vertex-id rule and D3b-06's tolerance rule agree, and the id is exact where a float comparison is not. The container path is part of the key because vertex ids belong to a definition: two placements of one component carry identical `vertex_ids` and must not join (the `shared_definition` case in ACCEPTANCE). World points within the tolerance are used only where no vertex can be shared: the `counted_twice` finding across Zones (D3b-16) and the window-perimeter check (D3b-15). D3b-06's semantics are unchanged; this fixes the mechanism | P3b-04 |
| D3b-24 | Added 2026-10-26 at the phase close (P3b-09 step 1, D3a-20's rule). The installed footprint is 24,541,739 bytes: under the 26,000,000 ceiling, 547,656 past the 23,994,083 baseline (budget 1,500,000), and above the 24,000,000 target. Reset the baseline? | Reset `installed_baseline_bytes` to 24,541,739, so Phase 4 is measured from the Phase 3b close; keep the target, ceiling and growth budget. The target is advisory; the ceiling and growth budget gate | P3b-09 |

## Ed's answers

Ed answered every row on 2026-10-03, one at a time. A row here supersedes the recommendation in
Part 2. The PRD and `context/UBIQUITOUS_LANGUAGE.md` were amended the same day.

| ID | Answer | Date |
| --- | --- | --- |
| Q1, D3b-01 | As recommended: the edge's dictionary is the record. No Model-level registry and no separate thermal-bridge record; the registry question goes to piping and ducting | 2026-10-03 |
| D3b-02 | As recommended: no id on the assignment; P3b-01 falls back to `tbe_` with the Window-unit copy rule only if the reference-target contract requires an id, and records why | 2026-10-03 |
| Q2 | As recommended: one psi-value per type; a different value is a different type | 2026-10-03 |
| Q4, D3b-03 | As recommended: store honeybee-ph's `15-Ambient`, `16-Perimeter`, `17-FS/BC`; show METr's words, the third confirmed on METr's screen in P3b-05 | 2026-10-03 |
| D3b-04 | As recommended: group required, new types default to `15-Ambient`; the "type has no group" warning row is removed | 2026-10-03 |
| Q9, D3b-05 | As recommended: `Fields.common` (name, notes, `datasheet_links`, `source`) plus `psi_w_mk`, `group`, `color`; no timestamps | 2026-10-03 |
| Q5, D3b-06 | As recommended: maximal chains of same Zone, type and quantity, joined within 0.0254 mm, split at free ends and junctions; loops close; a T is three runs | 2026-10-03 |
| D3b-07 | As recommended: type name plus counter, numbered by Building-Segment, Zone name and position; identifier `tb_` and a digest of Zone, type and endpoints | 2026-10-03 |
| Q6, D3b-08 | As recommended: keep `quantity`, positive, default 1; the PHX observation goes to metr-export as unreproduced | 2026-10-03 |
| D3b-09 | As recommended: Zones publishes `zones.containment`; thermal bridges never restates the membership rules | 2026-10-03 |
| D3b-10 | As recommended: writes through shared storage refuse with Zones' `target.*` codes; existing tags in shared definitions count once per occurrence, marked shared | 2026-10-03 |
| Q7, D3b-16 | As recommended: the holding Zone owns an edge; interior-junction and counted-twice are non-blocking warnings | 2026-10-03 |
| Q11, D3b-15 | As recommended (option A): thermal bridges requires Windows and reads a new `units.outlines`; an assigned edge on a Unit outline is a non-blocking warning | 2026-10-03 |
| D3b-21 | As recommended: a type with no psi-value blocks export only when an edge is assigned to it | 2026-10-03 |
| D3b-20 | **Differs from the recommendation: optional.** A run that fails to translate or attach is omitted and disclosed; the canonical pair is still written. Follow-up answered as recommended: only the failed runs are omitted, each a non-blocking finding with Locate in preflight and the report. This settles R05 item 4 in P3b-08 instead of leaving it owed | 2026-10-03 |
| D3b-13 | As recommended: live schedule; P3b-04 measures at 50,000 Edges with 5,000 assigned and falls back to scan on request only if over budget. Outcome 2026-10-25 (F37): over budget at 1.83 s, so the schedule is read on request | 2026-10-03 |
| D3b-14 | As recommended: a gesture limit owned by the thermal-bridge schema, 250 to start, measured in P3b-03 and P3b-07 | 2026-10-03 |
| D3b-11 | As recommended: entries carry the Edge as `entity` and its world segment as P3a-05 `derived`; one addition, `colour_mode(..., stroke:)`; P3b-06 waits for P3a-05 | 2026-10-03 |
| D3b-12 | As recommended: the HUD label carries total length, count after, as "Parapet, 26.0 m (12)" | 2026-10-03 |
| Q10, D3b-17 | As recommended: the Thermal Bridges tab with Types and Schedule subtabs; the assign bar in Types | 2026-10-03 |
| D3b-18 | As recommended: the edge tool stays as P3b-07, the last authoring stage | 2026-10-03 |
| Q8 | As recommended: not a library kind now; first candidate for roadmap 5.4 | 2026-10-03 |
| D3b-19 | As recommended, then superseded the same day by the split into two flat packets with ids restarted per sub-phase | 2026-10-03 |
| D3b-22 | As recommended: the `tbe_` id is not re-issued after a split or copy; reads mark an id held by more than one Edge as `copied`; no repair operation. Consequence recorded by P3b-01's host gate (T01, 2026-10-21) for D3b-01: when two collinear halves carry different records and the crossing edge between them is erased, SketchUp heals them into the edge that kept the original persistent id and drops the other record silently. The edge stays the record; a reassigned half that is later healed loses its assignment, and the live schedule shows the result. No repair exists because nothing points at the lost record | 2026-10-21 |
| D3b-23 | As recommended: runs join by a shared vertex keyed on container path plus vertex id within one Zone occurrence; the 0.0254 mm tolerance serves only the cross-Zone and window-perimeter checks. Consequence for D3b-07 (P3b-01, 2026-10-21): the run identifier digests the container path with the Zone, type and endpoints, since two coincident placements of one component are two runs and the translation refuses duplicate ids | 2026-10-21 |
| D3b-24 | Recorded at the phase close under Ed's authorization of the whole packet (2026-10-25, merge delegated); the reset is P3b-09's own step 1 | 2026-10-26 |

## PRD amendments that follow

Applied to [PRD.md](PRD.md) only after Ed answers, one change per decision. The PRD's
"Decisions for the interview" table records each answer with its date.

| From | Amendment |
| --- | --- |
| D3b-01, D3b-02 | Edge tagging rule 1: no registry and, unless P3b-01 finds one required, no assignment id. B4's registry is recorded as piping's and ducting's choice |
| D3b-03, D3b-04 | Records: `group` holds honeybee-ph's three strings, required, default `15-Ambient`. Validation rows: the "type has no group" row is removed |
| D3b-05 | Records: `created_at` and `updated_at` removed; `datasheet_links` from the common fields |
| D3b-06, D3b-07 | Runs: the chain rule, the T junction, closed loops, naming and identity |
| D3b-08 | Records: `quantity` positive, default 1. Export mapping: quantity is canonical in HBJSON; the METr consequence is metr-export's |
| D3b-09, D3b-10 | Assign: only edges a write may reach; shared definitions counted per occurrence |
| D3b-11, D3b-12 | Colour-by mode: drawn through the shared segment path; the HUD label carries total length |
| D3b-13 | Edge tagging rule 3: live schedule, with the scan on request as the measured fallback |
| D3b-15, D3b-16 | Validation rows: window perimeter, interior junction and counted-twice warnings |
| D3b-21 | Validation rows: "type has no psi-value" blocks only when assigned |
| D3b-17 | Types tab: two subtabs |
| F22 | Export mapping and Acceptance shape: METr rows point at metr-export |
| F6, D3b-22 (2026-10-21) | Records and edge tagging rule 1: the assignment carries a `tbe_` id; a duplicate after a split or copy is routine, marked `copied`, never re-issued |
| F8 (2026-10-21) | Colour-by mode: the HUD row reads "Parapet (12) 26.0 m", the service's own "label (count) figure" shape, not "Parapet, 26.0 m (12)" |

## Ledger

| Date | Event |
| --- | --- |
| 2026-10-03 | Drafted from source at `08c4807`, the B4 and B3 spikes, the vendored honeybee-ph 1.33.65 wheel and PHX. No answer recorded yet. |
| 2026-10-03 | Ed answered every row, one at a time. All as recommended except D3b-20: the thermal-bridge section is optional, and only failed runs are omitted and disclosed, which settles R05 item 4 in P3b-08. PRD and glossary amended. |
| 2026-10-03 | Phase 3 split into `phase-03a-spaces/` and `phase-03b-thermal-bridges/`; this file moved here and its ids were renumbered (see the introduction). D3b-19 superseded. |
| 2026-10-21 | Re-verified F1 to F26 against `main` at `420c783a` (Part 1b): F6 and F25 settled; F7, F10, F14, F15 and F24 changed; F8 and F9 superseded by P3a-05 and G-02; the rest hold. Added F27 to F36. Added D3b-22 (no re-issue of duplicated `tbe_` ids) and D3b-23 (runs join by vertex id), both open. CONTRACTS section 7 questions 1, 4, 5, 6 and 7 answered from code in section 8. The D3b-12 label shape corrected to the service's. No decision answered, no stage authorized. |
| 2026-10-21 | Ed answered D3b-22 and D3b-23 as recommended. The interview is complete again; no stage authorized. |
| 2026-10-25 | P3b-04 measured D3b-13 (F37): at 5,000 assigned Edges in a Model of 50,000 the schedule read costs 1.83 s against the 200 ms refresh budget, so the recorded fallback applies: `schedule.list` and `schedule.all` are read on request (the Schedule's open and Refresh), with no snapshot section. Added F37 to F40. |
| 2026-10-26 | D3b-24 recorded at the Phase 3b close: the footprint baseline reset to 24,541,739 bytes. |
