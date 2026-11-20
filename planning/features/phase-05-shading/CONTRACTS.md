# Shading: proposed contracts

DATE: 2026-11-19
STATUS: Scoped. Proposed bindings, built on Ed's answers in [DECISIONS](DECISIONS.md). P5s-01 confirmed sections 4 and 7 from code, tests and the SD01 host run on 2026-11-19; Move-copy array and push-pull stay owed to a later hold.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Nothing here is an existing API. When a stage lands, its bindings move to `context/CONTRACTS.md`
and `context/EXTENSIBILITY.md` and this file stops being the authority.

## 1. Feature

| Item | Value |
| --- | --- |
| Feature id | `ph_composer.shading` |
| Ruby module | `PhComposer::Shading`, in `src/ph_composer/features/shading/` |
| Requires | `ph_composer.zones` (containment, and the export sections it reads) |
| Composition root | Added to `FEATURES` in `extension.rb`, after `ThermalBridges` |
| Python section | `shade_sections.py`, listed in `composition.py` |

Shading names Zones. No Zones, Spaces, Windows or shell file names Shading.

## 2. The mark

| Item | Value |
| --- | --- |
| Dictionary | `ph_composer.shading` |
| Entity | A `Sketchup::Face`, `Sketchup::Group` or `Sketchup::ComponentInstance` |
| Record | `{"schema_version": 1}`, with optional `user_data` and `extension_data` |
| Durable id | None (D5s-07) |
| Store flags | Not `claims_entity`. The envelope-exclusion flag of section 4 |

A **Shading Face** is a Face whose own entity carries the mark or whose root path passes through a
marked Group or ComponentInstance, with no Zone and no claimed entity between that container and the
Face (D5s-17). A Face inside a claimed entity is never one. A second mark below a marked container
changes nothing.

Target reference, from the Model root like a Window Unit's:

```json
{ "entity_path": [4812, 4901] }
```

`entity_path` is the root-to-entity persistent-id path. Resolution verifies every step, never
searches by name or geometry, and refuses a stale path with the foundation's `target.*` codes.

## 3. Operations

| Name | Kind | Params | Result |
| --- | --- | --- | --- |
| `ph_composer.shading.assign` | action | `targets`: references | `assigned`, `unchanged` and `left_out` (each with its reference and, for `left_out`, a code and message) |
| `ph_composer.shading.clear` | action | `targets`: references | `cleared`, `unchanged`, `left_out` |
| `ph_composer.shading.list` | query | none | Every marked entity with its path and kind, and every shading component: `display_name`, `face_count`, `area_m2` |
| `ph_composer.shading.selection` | query | none | The native selection as references, with what each would do under assign and clear. The menu's read |
| `ph_composer.shading.export_preflight` | query | none | `Export::PREFLIGHT_RESULT` |

Both actions are one native operation and one Undo step, carry `expected_revision`, and refuse
whole only when no target can change (D5s-13). Neither creates a dictionary on an entity it leaves
out.

Codes, under the `shading` noun, registered in `codes.rb`:

| Code | Meaning |
| --- | --- |
| `shading.face_classified` | A classified Zone Face cannot be shading until its classification is cleared |
| `shading.zone_target` | The Group is a Zone or holds one |
| `shading.inherited` | Clear named a Face that is shading through a container; the message names it |
| `shading.cutting_component` | The Face is inside a cutting component |
| `shading.zone_inside` | Preflight note: a marked Group holds a Zone or a claimed entity, which stays what it is |
| `shading.geometry_invalid` | Export: the Face cannot become a Shade (degenerate, non-finite) |

A claimed entity refuses with the existing `target.wrong_kind`; a locked path with `target.locked`; a
Face behind shared storage with `target.shared_definition` (D5s-16).

## 4. The Zones seam

One foundation addition (D5s-12), named here and built in P5s-03:

| Item | Value |
| --- | --- |
| Flag | `Records::EntityStore.new(dictionary, excludes_from_envelope: true)`, beside `claims_entity`. Shading's store is the only one that sets it. The store keeps its excluding stores as `claiming` keeps claiming ones, so the check names no feature |
| Check | `Records::EntityStore.envelope_excluded?(inside)`: true when any entity in `inside` carries a record of an excluding store and none is claimed (`claimed?`). By presence, as `claimed?` reads, so a damaged mark still excludes |
| Detached twin | `Records::EntityStore.envelope_excluded_entries?(entries)`: the same rule over snapshot entries, each read through its `dictionaries` map. Export never holds a live entity |
| `inside` | The entities from the first one inside the Zone Group down to the Face, the Face included: exactly the `inside` list `Occurrences.holding` already returns. The Zone Group itself and everything above it are never passed, so a mark above a Zone never reaches its Faces (D5s-17) |

The check takes entities, not a root path. Every live call site already holds them: the Face walker
descends through each container, `holding` returns `inside`, and `resolve_face_path` resolves each step.
A persistent-id path would make each site resolve the Model a second time. The export sites hold
snapshot entries and their paths, so they use the twin, collecting the entries at each prefix of the
Face's path below the Zone's.

The inherited case: a Face inside a marked Group inside a Zone has `inside` = [Group, Face], and the
Group's mark excludes it. A claimed entity anywhere in `inside` wins, so a Face inside a Space volume
or a Window Unit is never excluded through a container above it, and a Face inside a claimed entity is
never a Shading Face (section 2).

### Which Faces a Zone owns (question 2)

The live walk (`Zones::Occurrences.walk_faces`) takes every Face at any depth inside the Zone Group,
through plain Groups and non-cutting ComponentInstances. It stops at a nested Zone Group and at a
cutting component, and does not stop at a claimed entity. The export side
(`Zones::ExportProjection.zone_faces`) files each snapshot Face under every Zone above it, so a Face in
a Zone nested in a Zone counts for both. The exclusion covers each side's own set.

### Call sites, from code at `49fbbe55`

Paths are relative to `src/ph_composer/features/`.

Four funnels carry nearly every read. P5s-03 applies the check in each funnel, to Face leaves only:
`resolve_element` (thermal bridges' Edge references) and `containment` with a non-Face leaf are unchanged; every consumer listed
under a funnel inherits it and gets its own test there.

| Funnel | Where | What P5s-03 does (proposed; P5s-03 decides) |
| --- | --- | --- |
| A. Face walk | `zones/zone/occurrences.rb` `walk_faces`, behind `scan_faces`, `Occurrences.faces` and `Zones::Index` (`faces`, `all_faces`, `faces_by_id`, `faces_with_id`) | Leaves an excluded Face out. The walk carries `inside` (or a marked flag and a claimed flag that agree with the check) |
| B. Point read | `zones/zone/occurrences.rb` `holding`, behind `occurrence_for_path`, `occurrence_at` and `containment` | Returns no Face occurrence for an excluded Face, with its own reason beside `outside_zone` |
| C. Reference resolve | `zones/zone/occurrences.rb` `resolve_face_path`, behind `face_at` and `resolve_face` | Refuses an excluded Face with `target.wrong_kind`, so no write or read by reference reaches a Shading Face |
| D. Snapshot | `zones/export.rb` `zone_faces` (Zones' projection); `zones/faces/export.rb` `zone_faces(snapshot)` | Leaves excluded entries out, through the twin. Note: the Faces section's `zone_faces` takes every snapshot Face, Zone or not; `records` keeps those with a Face record and `contexts` keeps them all |

Consumers, each inheriting from the funnel named:

| Consumer | File and method | Funnel |
| --- | --- | --- |
| `faces.list`, `faces.all` | `zones/faces/operations.rb` `list`, `all` | A |
| Suggest classification | `zones/faces/operations.rb` `auto_classify` | A |
| Classify | `zones/faces/operations.rb` `plan_classification`; `zones/faces/steps.rb` `ClassifyStep#apply` | C |
| Every other read or write of a Face by reference: Locate, metadata, Reverse, Assembly assignment, attached zones, Solve's resolves and steps, Zone steps and split-identity repair, the selection read, the Surface counterpart check in export | `zones/faces/locate.rb`, `operations.rb` (`update_metadata`, `reverse`), `steps.rb` `ReverseFaceStep`, `assembly_assignment.rb`, `attached_zone_operations.rb`, `export.rb` (`assignment_issues`); `zones/adjacency/adjacency.rb`, `adjacency_steps.rb`, `operations.rb`; `zones/zone/steps.rb`, `split_identity_repair.rb`; `zones/faces/selection.rb` | C |
| The `face.unclassified` preflight row | `zones/faces/export.rb` `preflight`, `face_findings` | A |
| The blocking `face.unclassified` in the Zones section, and each Room's `face_ids` | `zones/export.rb` `records` | D |
| The Faces section's records and projection (read by Thermal bridges' and Windows' export) | `zones/faces/export.rb` `records`, `contexts`; read in `thermal_bridges/export.rb` and `windows/export.rb` | D |
| The Zones view's unclassified and surface counts | `zones/zone/operations.rb` `zone_view`, `independence` | A |
| Face Colour-by modes (Face type, Boundary, Assembly) | `zones/faces/colour_modes.rb` `entries`, `assembly_entries` | A |
| The Classify tool's hover and click | `zones/faces/classify_tool.rb` `onMouseMove`, `collect` | B |
| The Face context menu's `classifiable?` and the selection read | `zones/faces/classify_menu.rb` `classifiable?`; `zones/faces/selection.rb` `selected` | B |
| Solve adjacencies: candidates and retirements | `zones/adjacency/adjacency.rb` `candidates`, `retirement_updates` | A |
| Face splitting during Solve | `zones/adjacency/face_split.rb`, reached only through funnel A's candidates | A |
| The Zone membership stamp writer on rename | `zones/zone/steps.rb` `UpdateZoneStep#apply` | A |
| Zone copy repair and split-identity repair | `zones/zone/repair.rb` `member_entries`; `zones/zone/split_identity_repair.rb` `apply` | A |
| Attached zone references | `zones/faces/attached_zone_operations.rb` `referencing_faces` | A |
| Assembly retarget | `zones/faces/assembly_assignment.rb` `retarget` | A |
| Thermal-bridge Edge reads of their sibling Faces | `thermal_bridges/scan/occurrences.rb` through the `faces.host_context` query (`zones/faces/operations.rb` `host_context`) | B |
| Window Unit host Faces | `windows/units/convert_hosts.rb` `zone_faces`, through `faces.list` | A |
| Spaces' offset preflight | `spaces/export.rb` `offset_findings` (live), `own_face_points` (snapshot) | A, D |
| Spaces' Create Space and Mark floor reads of a Zone Face's record | `spaces/create_faces.rb` `read`, `spaces/create_route.rb` `floor_selected?`, `spaces/scoped_reads.rb` `context_candidates`, `spaces/mark_placement.rb`, through `faces.host_context` | B |
| Windows' host reads: Convert's offer, Place's target, a Unit's sibling hosts | `windows/units/convert_route.rb` `in_zone?`, `windows/placement/tool_target.rb`, `windows/units/read_context.rb` `sibling_hosts`, `windows/units/convert_step.rb`, through `faces.host_context` (`windows/placement/host.rb` `context`) | B |

Walkers outside the funnels:

| Walker | File and method | Treatment |
| --- | --- | --- |
| Spaces' candidate Faces of a Zone | `spaces/create_faces.rb` `zone_faces` | Reads the check itself; Spaces' test in P5s-03 |
| Face-record id inventories | `zones/faces/reference_targets.rb` `walk`; `zones/adjacency/adjacency.rb` `face_id_occurrence_counts`, `endpoint_survives?`; `zones/zone/split_identity_repair.rb` `live_identity_counts` | Exempt: they find Face records by id anywhere in the Model, not a Zone's envelope |
| Restore offers | `zones/zone/repair.rb` `walk_orphans` (Groups only; it does not descend ComponentInstances) | Exempt: it reads membership stamps, which a Shading Face does not get once the stamp writer reads funnel A. A Face stamped before it was tagged keeps its stamp and is still offered: P5s-03 decides whether tagging clears the stamp or Restore skips a marked Face |
| Faces inside a Space Volume or a Window Unit | `spaces/authoring.rb`, `spaces/steps.rb`, `spaces/scan/occurrences.rb`, `spaces/weighting_factor_menu.rb`, `spaces/add_volume_menu.rb`; `windows/units/restore_*.rb`, `mutation_scope.rb`, `convert_sources.rb` | Exempt: those Faces sit in claimed entities, which the check never excludes (section 2) |
| Windows' rectangle candidates and selection shape | `windows/units/candidates.rb` `convert`, `restore`; `windows/declarations/viewport.rb` `single_face?`; `windows/units/convert_route.rb` `face_paths` | Exempt: they read loose rectangles by geometry before any host is resolved; the host read goes through funnel B |
| Make Zone candidates and shape checks | `zones/zone/make_candidates.rb` `read`; `zones/zone/operations.rb` `make_zone_shape?`; `zones/zone/steps.rb` `existing_group` | Exempt: they read a selection before any Zone exists |

## 5. Menu and Colour-by

Menu items, declared by Shading with `menu: EXTENSION_NAME` so they sit directly in the PH-Composer
menu:

| Item | Available when | Handler |
| --- | --- | --- |
| Set as Shading | The selection holds a Face, Group or ComponentInstance that `selection` says assign would change | `assign` on the selection's references |
| Clear Shading | The selection holds a marked entity | `clear` on the selection's references |

Colour-by mode `ph_composer.shading.by_component`, label "Shading", `entity_kind` `face`: one
entry per Shading Face occurrence, keyed by its component name, palette by name; legend rows carry
Face count and area in display units. Its projection reads the Model once per repaint.

## 6. Export

Ruby contributor `ph_composer.shading.export.shades`, section version 1, `requires:` the Zones
section (for Zone names) and reads the snapshot only. One record per Shading Face occurrence:

```json
{
  "identifier": "shd_3f9a…",
  "display_name": "Neighbour",
  "boundary": [[x, y, z], …],
  "holes": [[[x, y, z], …]],
  "is_detached": true
}
```

World SI metres. No `user_data` leaves: a mark's map stays in the Model with one
`export.metadata_omitted` finding, as for other entities with no object of their own.

Python `ShadeSection`: `attaches = Attachment(MODEL)`, `required_for_export = False`, builds
`honeybee.shade.Shade(identifier, Face3D(boundary, holes=holes), is_detached=True)`, sets
`display_name`, and adds each with `model.add_shade` after checking them all.

| Part | Content |
| --- | --- |
| Result fields | `shading_components`: `display_name`, `face_count`, `area_m2`; `shade_count`; `area_m2` total |
| Report | A Shading section from those fields; absent when there is none |
| Privacy | The fields above join the composed allowlist |
| Conformance | The reloaded Model's `orphaned_shades` match the fields by count, name and area, each `is_detached` |
| Preflight | Non-blocking rows only: a Face left out (`shading.cutting_component`, `shading.geometry_invalid`), an unreadable mark |

The canonical model's accounting (`rooms`, `faces`, `surface_pairs`) does not change.

## 7. Questions P5s-01 answered

Paths are relative to `src/ph_composer/`.

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 1 | Does one `Records::EntityStore` on `ph_composer.shading` read, write and remove the record on a Face, a Group and a ComponentInstance? | Yes, with one dictionary and one record shape. A read creates no dictionary, and the mark claims nothing | `tests/shading_mark_store_test.rb` |
| 2 | Which Faces are a Zone's own? | Every Face at any depth through plain Groups and non-cutting ComponentInstances, stopping at a nested Zone; section 4 | `features/zones/zone/occurrences.rb` `walk_faces`; `features/zones/export.rb` `zone_faces` |
| 3 | Does the mark survive the native edits, each with Undo, Redo, save and reopen? | Yes, as any entity dictionary: copy, cut and paste, Make Group, Make Component, Make Unique, Divide and intersect keep it (a split Face gives two marks, a pasted Face a new persistent id); explode removes a Group's mark with the Group. Undo, Redo, save and reopen keep it exactly. Move-copy array and push-pull are owed to a later hold | SD01 ([evidence](evidence/sd01-host-facts.md)); `context/SKETCHUP_HOST_BEHAVIOR.md`, "Entity dictionaries on Faces, Groups and instances" |
| 4 | Does the snapshot's Face geometry carry inner loops in a form `Face3D(boundary, holes)` takes? | Yes. `FaceCapture` reads `face.loops` in host order into `loops_m`, outer first, and the Faces section builds `Face3D(points[0], holes=points[1:] or None)`. A holed `Face3D` makes a `Shade` with `is_detached` true in the repository's Python environment (checked by hand, 2026-11-19). On the host the holed Face lists its outer loop first (SD01) | `core/face_capture.rb`; `core/face_geometry.rb` `outer_loop`, `holes`; `python/ph_composer_translation/model_sections.py`; SD01 `visibility.json` |
| 5 | Do hidden and tag-hidden Faces export? | Yes. `GeometrySnapshot.walk` captures every Face whatever its visibility (Faces inside a cutting component excepted), and neither Zones nor the export filters on it, so Shading exports them too. Confirmed on the host: SD01's hidden and tag-hidden Faces are in the snapshot | `export/geometry_snapshot.rb` `walk` |
| 6 | Does `faces.classify` with every field cleared return a Face to unclassified (F12)? | No. Clearing `face_type`, `boundary_condition` and `assembly_id` writes back a record with its id and empty values, so the Face reads as classified with no Face type (`face.type_missing`), not as unclassified. P5s-03 adds the route to remove the record (D5s-11) | `features/zones/faces/operations.rb` `patched_record` (a clear deletes the field and keeps the record), observed through `faces.classify` against the SketchUp stub; `features/zones/faces/export.rb` `face_findings` reads a present record as classified and `assignment_issues` raises `face.type_missing` |
