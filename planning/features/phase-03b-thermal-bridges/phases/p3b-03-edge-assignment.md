# P3b-03: edge assignment, Zone containment and edge picking

DATE: 2026-10-03
STATUS: Scoped. Corrected to `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b)
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Entry and scope

Requires P3b-02 and D3b-01, D3b-02, D3b-08, D3b-09, D3b-10, D3b-14 and D3b-22 (answered
2026-10-21), with PRD Q1 and Q6. P3a-01's nested-container rule, which
`zones.containment` must honor, is on `main`. Owns the assignment record on an
Edge, its reference target, assign and clear, the native-selection read, delete with replacement,
and the two shared additions every later stage relies on: Zones' containment read (H11) and
`Pick.edge_path` (H12). Panel closed; no screen and no tool.

Behavior owner: the [thermal-bridges PRD](../PRD.md), "Assign" and "Edge tagging
rules", as amended in P3b-01. Names: [CONTRACTS](../CONTRACTS.md) sections 2 to 5.
Get the stronger independent review: this stage adds an entity store, a reference target and a
read Zones publishes to other features.

Paths are relative to `src/ph_composer/`.

## Steps

1. **Zones containment (H11).** In Zones, a registered read `ph_composer.zones.containment` that
   takes root-to-entity persistent-id paths and answers, per path, the holding Zone occurrence
   (`zone_id`, `zone_path`, `building_segment`, `level`) or none with a reason
   (`outside_zone`, `cutting_instance`, `nested_container`, `not_a_drawing_element`), and the
   `write_refusal` a write through that path meets, from the path alone. Build it on what exists:
   `Zones::Occurrences.occurrence_at` already walks only the collections along a path and
   `occurrence_for_path` already picks the innermost Zone and returns nil for each of those
   reasons, for a Face leaf only; `write_refusal` already answers the refusal. Generalise the leaf
   to any drawing element and return the reason instead of nil, keep `host_context`'s Face-only
   shape over the same code, and name no Edge or thermal bridge. PR #208 refactored
   `occurrences.rb` after the plan was drafted; read it first. Fold the read into
   `context/CONTRACTS.md`, "Geometry records and occurrence references".
2. **Edge pick (H12).** `Pick.edge_path(view, x, y)` in `core/pick.rb`: the first PickHelper path
   ending in a `Sketchup::Edge`, with `face_path`'s container handling. It names no feature. Used
   by P3b-07; landed here so its tests sit with the contract.
3. **Store and target.** `assignment/store.rb`: `Records::EntityStore` on dictionary
   `ph_composer.thermal_bridge`. `assignment/schema.rb`: `id` (`tbe_`, required by the engine's
   reference scan, CONTRACTS section 8 question 1), `thermal_bridge_type_id` (a core reference,
   required) and `quantity` (exclusive minimum 0, default 1). `assignment/reference_target.rb`:
   target `ph_composer.thermal_bridges.edge` with the Face reference shape (`zone_id`, `zone_path`,
   `entity_path`, `entity_id`), a records provider that walks every container including shared
   definitions and cutting instances, `locate:` over `zones.containment`'s resolution that verifies
   every parent-child step, refuses with `target.*` codes and refuses an Edge whose record changed
   under its reference as `target.changed`, and a read-phase `locate_index:`.
4. **Assign and clear.** `assignment/operations.rb` and `steps.rb`: `edges.assign` takes explicit
   Edge references with their `expected_values` (absent when unassigned), a type id and a
   quantity; it resolves every target through the index, asks `zones.containment` once for all
   paths, refuses the whole command if any target is stale, unreachable, outside every Zone or
   behind a `write_refusal`, or if the targets exceed the schema-owned gesture limit (D3b-14,
   `gesture.too_large`), and otherwise writes one record per Edge in one proposal, a fresh `tbe_`
   on a first assignment and the existing id on a reassignment. `edges.clear` removes the
   dictionary, which is also what clearing a required reference means. Both end with
   `session.changed`, declare `preconditions` and `side_effects`, and take one `API::CHANGES` row
   with the selection read below.
5. **Selection.** `assignment/selection.rb` and the `edges.selection` query and `edges.selected`
   snapshot section: the native selection under the active path, Edges only, each as a reference
   with its containment, current assignment and write refusal. A selection holding anything else
   reports which entities were ignored; it never assigns them. A long-lived `Selection::Client`
   in the shape Zones uses serves the menu route in P3b-05.
6. **Delete with replacement.** `types.delete` with `replacement_id`, or an explicit null to
   clear, rewrites every assigned Edge occurrence through the store in the same proposal and passes
   them as the `reference_plan`. Repeated shared storage refuses the whole delete atomically, as
   Assembly delete does (`context/CONTRACTS.md`, "Geometry records and occurrence references").
7. **Copies.** Apply T01's measured outcomes and D3b-22: a split and a copy each yield
   independently tagged Edges whose assignments are already correct and share one `tbe_` id.
   Reads mark an id held by more than one Edge as `copied`; nothing re-issues it and no repair
   operation exists.
8. **Context and walkthrough.** Fold the edge tagging rules as answered into
   `context/CONTRACTS.md` (storage table row) and `context/TECH_STACK.md` (rules for edge-owned
   assignments, written for piping and ducting to reuse). Extend the walkthrough and the agent
   guide recipe to assign, clear and delete with replacement panel closed; the recipe states that
   `edges.assign` is the explicit-reference route and the tool (P3b-07) its pointer equivalent.
   Any navigation into a nested Zone's context goes through the foundation's
   `ph_composer.context.open` (D3a1-04 names this stage); add none of its own.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/zones/zone/occurrences.rb` (`occurrence_at`, `occurrence_for_path`, `write_refusal`) and `features/zones/faces/operations.rb` (`host_context`) | Extend for H11 |
| `features/spaces/create_route.rb`, `mark_placement.rb` | Pattern for a handler-side read of a Zones path read through `requires:` |
| `features/zones/faces/selection.rb` | Pattern for the selection read and client; Edges instead of Faces |
| `features/zones/declarations/faces.rb` (Face target), `features/zones/faces/reference_targets.rb` (the whole-Model provider), `features/windows/units/occurrences.rb` (`Units::TARGET`) | Pattern for the Edge target and its provider |
| `features/zones/faces/operations.rb`, `features/assemblies/assembly/operations.rb` | Pattern for assign with `expected_values` and delete with a `reference_plan` |
| `core/pick.rb` | Extend |

## Tests (write first)

1. `zones.containment`: a direct Zone, a Zone under a translated and a rotated wrapper, a path
   through a cutting instance, a path through a stamped nested container, a path outside every
   Zone, a Group leaf, a locked Group, a ComponentInstance on the path; each answers the right
   Zone or named reason and refusal; `host_context`'s rows are unchanged. It reads no Edge or
   thermal-bridge name.
2. `Pick.edge_path` returns an Edge path and skips Faces; a Face pick still returns the Face.
3. Assign to three Edges writes three records in one proposal and one Undo step; reassign replaces;
   Clear removes; Undo restores the prior state exactly, `user_data` included.
4. A stale `expected_values` on one target refuses all and writes nothing; so does an Edge outside
   every Zone, an Edge behind a ComponentInstance, and the limit plus one.
5. `edges.selection` with Edges and a Face selected returns the Edges and reports the Face ignored.
6. Delete with replacement across direct and nested Edges is one Undo step; Undo restores the type
   and every assignment; delete without replacement while in use refuses `reference.in_use`.
7. A split Edge in the stub carries the record on both pieces, both are assigned, both read as
   `copied` and neither is repaired (stub comment names the host fact from T01; D3b-22).
8. The API change row and the agent guide recipe are present; `tests/agent_guide_test.rb` passes.

## Host gate

Fresh process on the reference model, panel closed, through the bridge and native controls:
select the Zone A roof perimeter edges natively inside the Zone, read `edges.selection`, assign
Parapet, Undo, Redo; repeat inside a Zone under a rotated wrapper; attempt an Edge inside a placed
window unit and an Edge at the Model root and read each refusal; delete Footing with Slab edge as
replacement and Undo; split an assigned Edge natively and read both pieces; save and reopen.
Observe the host with the development tooling: `host_bridge.py wait-for` for deferred work, `host_bridge.py diagnostics` for what happened, `acceptance_case.py begin` and `finish` for the ledger row (`tools/hostkit/.index.md`).

## Out of scope

Runs, lengths and the schedule (P3b-04). Any screen (P3b-05). Colour-by (P3b-06). The tool (P3b-07).

## Done when

- T03 has evidence in `../evidence/p3b-03-edge-assignment.md`, with the stronger review recorded.
- `context/` carries the containment read and the edge tagging rules; `make ci` passes on both
  Rubies.
