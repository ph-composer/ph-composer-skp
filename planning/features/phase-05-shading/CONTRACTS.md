# Shading: proposed contracts

DATE: 2026-11-19
STATUS: Scoped. Proposed bindings, built on Ed's answers in [DECISIONS](DECISIONS.md); P5s-01 confirms each against code and the host before any later stage reads them.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

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

One foundation addition, named in P5s-01 (D5s-12): a flag on `Records::EntityStore` meaning "an
entity marked here, or inside a container marked here, is not part of a Zone's envelope", with
one class-level check Zones reads. It names no feature. The check answers for a mark on the Face or
on a container inside the Zone, never for one above the Zone (D5s-17).

Zones reads it everywhere it enumerates a Zone's Faces. P5s-01 lists the call sites from code; the
ones known from the contracts are:

- the Faces export projection and its `face.unclassified` preflight row;
- `faces.list`, `faces.all` and the unclassified counts the Zones view shows;
- `classify` and `auto_classify` (Suggest classification), which leave a Shading Face out;
- the Classify tool's hover and gesture, and the Face context menu's `classifiable?`;
- Solve adjacencies and Face splitting;
- the Face Colour-by modes (Face type, Boundary, Assembly);
- the Zone membership stamp writer;
- thermal-bridge run findings that read an Edge's sibling Faces, and Spaces' reads of Zone Faces.

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

## 7. Open, for P5s-01

1. Does `Records::EntityStore` read and write on a ComponentInstance and a Group with one
   dictionary and one schema, as it does on a Face?
2. Which Faces does Zones treat as a Zone's own: only those directly in the Zone Group, or those in
   nested plain Groups too? Section 4 exempts exactly that set.
3. Host: does the mark survive copy, Move-copy array, paste, Make Group, Make Component, Make
   Unique, push-pull, Divide of a bounding Edge, intersect, and explode of a marked Group, each
   with Undo, Redo, save and reopen?
4. Does the snapshot's Face geometry carry inner loops in a form `Face3D(boundary, holes)` takes
   directly, as the Zone Face projection uses it?
5. Do hidden and tag-hidden Faces export? Shading follows whatever the Faces section does.
6. Does `faces.classify` with every field cleared return a Face to unclassified (F12)? If not,
   P5s-03 adds it (D5s-11).
