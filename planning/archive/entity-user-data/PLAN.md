# Consistent entity user data: delivery plan

DATE: 2026-11-14
STATUS: Complete. Stages EUD-01 to EUD-10 delivered by PR #508; archived 2026-11-15. Planned from the source inventory at `68919a8c`;
Ed answered D-UD-1 to D-UD-8 "All as recommended" on 2026-11-14 and authorized implementation.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

## Outcome

A script with the panel closed reads, sets, replaces and clears `user_data` on every authored
entity through public operations, with the same guard, batch and Undo rules everywhere. Edits,
copies and save/reopen keep it. Every export and library boundary either carries it or says
plainly that it does not. [PRD.md](PRD.md) owns the requirements and acceptance rows UD-01 to UD-10.

## Inventory (UD-01)

Read at `68919a8c` on 2026-11-14 and updated to the final state of the branch in EUD-08. Paths are
relative to `src/ph_composer/`. "UD" is `user_data`. "Closed by" names the stage that closed each
gap found at `68919a8c`; "none" means the entity already met the policy. The published coverage
table is [docs/USER_DATA.md](../../../docs/USER_DATA.md), one row per entity below.

| Entity | Owner, storage, address | Schema allows UD | Read with UD | Write UD on an existing entity | HBJSON | Library | Closed by |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Model root | foundation; `ph_composer.model` ModelSettings dictionary; no address | yes | `model.detail` | `model.update_metadata` | HB Model `user_data` | n/a | EUD-06, EUD-07 |
| Material | assemblies; catalog; `mat_` | yes | `materials.list/all`, `records.*` | `records.update_metadata` | omitted, finding | `library_materials`, omitted, finding; replace keeps the local map | EUD-01 |
| Assembly | assemblies; catalog; `asm_` | yes | `assemblies.list/all`, `records.*` | `records.update_metadata` | OpaqueConstruction and reversed copy | not a library kind | EUD-01 |
| Layer | Assembly record, `layers[]`; `part_ids [lyr_]` | yes, `Records::Part` | Assembly `values.layers` (`records.list/detail`); `layers.list` rows omit it | `records.update_metadata` with `part_ids` | its material (hybrid host when divided); membrane Layer omitted, finding with `reference` | n/a | EUD-02, EUD-07, EUD-08 |
| Layer-Segment | Layer, `segments[]`; `part_ids [lyr_, seg_]` | yes, `Records::Part` | `segments.list` | `records.update_metadata` with `part_ids` | cell material when divided; otherwise omitted, finding with `reference` | n/a | EUD-02, EUD-07, EUD-08 |
| Frame, Glazing, Psi-Install Type | windows; catalog | yes | `*.list/all`, `records.*` | `records.update_metadata` | omitted, finding | `library_*`, omitted, finding; replace keeps the local map | EUD-01 |
| Window Type | windows; catalog; `wnt_` | yes | `types.list/all`, `records.*` | `records.update_metadata` | omitted, finding | not a library kind | EUD-01 |
| Window Element | Window Type, `elements[]`; `part_ids [wel_]` | yes, `Records::Part` | `types.elements.list` | `records.update_metadata` with `part_ids` | omitted, finding with `reference` | n/a | EUD-03, EUD-07, EUD-08 |
| Window Unit | windows; entity dict on a ComponentInstance; `{unit_id, entity_path}` | yes | `units.list/all/detail` | `units.update_metadata` | Aperture | n/a | none |
| Zone | zones; entity dict on a Group; `{zone_id, zone_path}` | yes | `zones.list/all` | `zones.update_metadata` | Room | n/a | none (restore discloses loss) |
| Face | zones; entity dict on a Face; `{zone_id, zone_path, entity_path, entity_id}` | yes | `faces.list/all` | `faces.update_metadata` | HB Face | n/a | none |
| Attached zone | zones; catalog; `atz_` | yes | `records.*` | `records.update_metadata` | omitted, finding | no | EUD-01, EUD-07 |
| Building Segment, Level | zones; catalog; `{collection, id}`; copied into Zone `choice_evidence` | yes | `options.list/detail/all` | `records.update_metadata`, rewriting the Zone copies in the same step | omitted, finding | no | EUD-04 |
| Space, Volume, Floor Segment | spaces; entity dicts | yes | `spaces.all/list` with fields, `volumes.list`, `floor_segments.list` | `spaces.update_metadata` | Space, SpaceVolume, SpaceFloorSegment | n/a | none |
| Space Floor | spaces; Volume's `floor_user_data`; `{floor_id, entity_path}` | yes | Volume row `floor` (`volumes.list` field) | `spaces.update_metadata` by `floor_id` | SpaceFloor `user_data` | n/a | EUD-06, EUD-07 |
| Thermal Bridge Type | thermal_bridges; catalog | yes | `types.list/all`, `records.*` | `records.update_metadata` | omitted, finding | no | EUD-01 |
| Thermal Bridge Edge assignment | thermal_bridges; entity dict on an Edge; `zone_path + entity_path + entity_id`; a `tbe_` id may repeat after a split or copy | yes | Edge rows of `edges.selection/selection_all/at/candidates` | `edges.update_metadata` by occurrence | omitted, finding: runs aggregate several Edges | n/a | EUD-05, EUD-07 |

Derived or internal, not independent authored entities: the Zone membership stamp (recovery
evidence on Faces), Zone option settings, the Windows, Spaces and Zones settings dictionaries,
Window definition, pane and definition-index stores (generated geometry), thermal-bridge runs and
schedules (calculated from Edges), the export snapshot, and library provider, connection and
agent-access state. Settings dictionaries are configuration, not building data; D-UD-1 keeps the
Model's own map separate from them.

Recovery and conversion paths that do not carry metadata, all by design and to be disclosed:
Zone restore lists `user_data` as `unrecoverable` (`zones/zone/repair.rb`); a Window Unit restored
from orphaned panes has no record left to copy (`windows/units/repairs.rb`); Unit conversion of a
plain component starts empty; Edge repair discards the record and reports up to 50 keys
(`thermal_bridges/assignment/repair.rb`).

Already preserving: catalog duplicate (`Engine#propose_duplicate`), Assembly gestures, Face
adjacency splits and split-identity repair, Window Unit swap, flip and identity repair, Spaces
identity plans, Edge reassignment, option adoption from Zone evidence, and library replace (the
kinds' `replace` callbacks drop the `user_data` param, so local maps survive).

## One policy for every lifecycle path

These rules apply to every row above and are what the stages test:

- **Edit:** a gesture that rebuilds an object keeps each surviving part's map at every depth.
- **Duplicate:** independent deep copies; new nested ids per the owner's rule; literal strings in
  maps are never treated as references.
- **Split:** every piece gets a deep copy of the source's map (the Face adjacency split rule, now
  stated for all).
- **Merge, or delete with replacement:** the survivor keeps its own map. The operation's result
  lists each removed entity whose map was not empty, with its top-level keys, as the Edge repair
  already does. Maps are never combined. Undo restores the removed entity with its map.
- **New part:** a part a gesture creates starts with no map.
- **Restore or conversion that cannot recover a map:** says so in its offer or result.

## Decisions for Ed

Ed answered every decision "All as recommended" on 2026-11-14. The stages are written to them.

| ID | Question | Recommendation | Stage |
| --- | --- | --- | --- |
| D-UD-1 | Where does the Model's own map live? | A core `ModelSettings` dictionary `ph_composer.model` holding `user_data` and `extension_data`, read by `ph_composer.model.detail` and written by `ph_composer.model.update_metadata` with the same `expected_metadata` guard. Exported to the HB Model's `user_data` beside the reserved `ph_composer` key. Feature settings dictionaries stay separate | EUD-06 |
| D-UD-2 | Where does a Space Floor's map live? | On its Volume record, as `floor_user_data`, addressed by `floor_id` through `spaces.update_metadata`. It travels with the Volume on copy and is exported to `SpaceFloor.user_data`. It is never aliased to the Volume's own map | EUD-06 |
| D-UD-3 | How are nested parts written? | One core action, `ph_composer.records.update_metadata`, for every catalog kind and its nested parts. A `RecordKind` declares its parts (`layers[]`, `layers[].segments[]`, `elements[]`) and the action addresses a part by its id path (`{kind, id, part_ids: ["lyr_…", "seg_…"]}`), never an index. Same batch, `expected_metadata`, one-step Undo and no-op rules as the entity owners. `user_data` comes off every catalog `*.update` (and the update side of `attached_zone.save` and `installs.save`), so the guarded action is the one write route for an existing record; create actions keep it. No users, so no deprecation period | EUD-01, EUD-02 |
| D-UD-4 | Schema version for nested `user_data` | Add the optional field at schema version 1. Old records stay valid without a rewrite; an older build would refuse a record that carries nested maps, which the no-users posture accepts. No migration code | EUD-02, EUD-03 |
| D-UD-5 | Merge and split | The single policy above: split copies, merge keeps the survivor and reports the removed maps, never combines. Applies to Window Element merge, option merge and Edge repair | EUD-03, EUD-04, EUD-05 |
| D-UD-6 | Which new HBJSON mappings? | Occurrence objects that are 1:1 with an HB object carry their map: Model root to Model, Space Floor to SpaceFloor, a Layer to its layer material (the hybrid host when divided), a Layer-Segment to its cell material when the Layer is divided. A single-segment Layer's Segment map, Window Elements (one Aperture per Unit), Edges (runs aggregate several Edges) and definitions turned into per-use HB objects (Material, Frame, Glazing, Psi-Install, Window Type, Thermal Bridge Type, options, Attached zone) stay local with an `export.metadata_omitted` finding. Attached zone gains that finding | EUD-07 |
| D-UD-7 | Library interchange | Keep the wire formats lossy for metadata: no format change. Library rows are the provider's data and the local map is a local annotation; replace already keeps the local map, and export already reports the omission. Document the boundary per kind | EUD-08 |
| D-UD-8 | Create-time `user_data` | Not added to creators that lack it (Zones, Faces, Spaces, Edges). Creating then calling the owner's metadata action is the documented route; the recipe shows it | EUD-08 |

## Stages

Ed named the existing branch `codex/entity-user-data`: every stage is a signed commit on that one
branch and one PR (pr-loop `--single-pr`), with a Sonnet adversarial read per stage before its
commit and one Codex review over the combined diff. `--merge` is granted: merge on green CI once
every review thread is answered. The native acceptance run (EUD-09) is the host gate and runs from
the conductor after the last review fix.

| Stage | Delivers | Acceptance | Kind |
| --- | --- | --- | --- |
| [EUD-01](phases/eud-01-catalog-metadata-action.md) | `ph_composer.records.update_metadata` for catalog kinds with `expected_metadata`; `records.list/detail` cover every catalog kind's map | UD-02, UD-04 | code |
| [EUD-02](phases/eud-02-assembly-parts.md) | `RecordKind` part declarations; `user_data` on Layers and Layer-Segments; part addressing in the action; every Assembly gesture and duplicate keeps part maps | UD-02 to UD-06 | code |
| [EUD-03](phases/eud-03-window-elements.md) | `user_data` on Window Elements; grid gestures, installs save, flip and duplicate follow the policy | UD-03 to UD-06 | code |
| [EUD-04](phases/eud-04-zone-options.md) | Building Segment and Level metadata writes through the core action, with the Zone evidence rewrite as a kind-declared follow-up; merge reports the removed map | UD-02 to UD-06 | code |
| [EUD-05](phases/eud-05-thermal-bridge-edges.md) | Edge reads carry metadata; `thermal_bridges.edges.update_metadata` by occurrence | UD-02 to UD-06 | code |
| [EUD-06](phases/eud-06-model-root-and-space-floor.md) | The Model map (D-UD-1) and the Space Floor map (D-UD-2) | UD-02 to UD-06 | code |
| [EUD-07](phases/eud-07-hbjson-mappings.md) | New HBJSON mappings and findings (D-UD-6), checked on reloaded HBJSON | UD-08 | code |
| [EUD-08](phases/eud-08-documentation.md) | Recipe, coverage table, guide, contracts, library boundary, foundation example link | UD-01, UD-09 | document |
| [EUD-09](phases/eud-09-native-acceptance.md) | Native SketchUp evidence on the final head | UD-07 | host gate |
| [EUD-10](phases/eud-10-final-review-and-archive.md) | Final gate, Codex review, merge, archive | UD-10 | closing |

EUD-01 to EUD-07 each bump the API minor version once in `shell/api.rb` with a change note and
regenerate `docs/API_REFERENCE.md` and the shipped guide with `make fixtures`. EUD-07 refreshes
the runtime manifest. The order is fixed by shared files: EUD-02 depends on EUD-01's action;
EUD-07 depends on the stored shapes from EUD-02 to EUD-06; EUD-08 documents the final API.

## Verification profile

Focused Ruby and Python tests per stage, `make ci` before every commit, a Sonnet adversarial read
per stage, the architecture review skill with the Ruby quality criteria on EUD-01 and EUD-02 (the
core contract change), and one Codex review (gpt-6.1-sol) over the combined diff. Native evidence
in EUD-09 only, on the head that goes to merge.
