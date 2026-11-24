# P4-13b: Piping groups and the pipe assignment

DATE: 2026-11-24
STATUS: Merged to main 2026-11-24 (#577, squash `2f360b5b`); offline evidence in [p4-13b-piping-groups-and-assignment](../evidence/p4-13b-piping-groups-and-assignment.md), host case `M13b` owed to MS3. Planned in full 2026-11-24 from [P4-13](p4-13-hot-water-piping.md), D4-36 (Q1, Q2, Q3, Q6, Q7, Q8, Q13), D4-18 and the [piping PRD](../hot-water-piping/PRD.md), "Draw" and "Assign". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M13b` runs in the MS3 sitting (D4-31), and carries the Line tool cases nothing has measured.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-13a. Owns, panel closed:

- The Piping group: an entity-owned record on a SketchUp Group linking it to one Hot Water System (Q7: many groups
  per System), created by `groups.create`, which also opens it for drawing (Q2).
- The pipe assignment: an entity-owned record on an Edge with its Pipe Type, its role and the role's values, its
  reference target, `pipes.assign`, `pipes.clear`, the selection read, and delete in use for Pipe Types and for
  Hot Water Systems a group names.
- Phase 3b's registry handover, answered: no Model-level edge registry (Q1), as D3b-01 decided for thermal bridges.

Behavior owner: the [piping PRD](../hot-water-piping/PRD.md), "Draw" and "Assign", and the edge rules in
`context/TECH_STACK.md`, "Edge-owned assignments", which this feature follows. Names: this document, folded into
[CONTRACTS](../CONTRACTS.md) in step 8. Pattern: Phase 3b's P3b-03 (`features/thermal_bridges/assignment/`) for the
Edge store, target, assign, clear, selection and delete with replacement.

Paths are relative to `src/ph_composer/`.

## What the sources settle

- An Edge record is an attribute dictionary written through `Records::EntityStore`; it carries an id because the
  engine's reference scan needs one; split, copy and paste put the whole dictionary on each piece, so one id on several
  Edges is routine and nothing re-issues it; writes refuse through shared storage, a locked Group and another Zone;
  every assign or clear is one command over explicit references bounded by a schema-owned limit (250 for thermal
  bridges); no observer watches Edges (`context/TECH_STACK.md`, "Edge-owned assignments").
- A pasted Group carries its dictionary on a new persistent id and shares storage with its source; Make Group keeps the
  wrapped entities' ids and dictionaries (`context/SKETCHUP_HOST_BEHAVIOR.md`, "Entity dictionaries on Faces, Groups
  and instances", SD01).
- `session/edit_context.rb` is the one `active_path=` writer; `EditContext.enter` runs every registered boundary
  first (`context/TECH_STACK.md`, "Treat the active editing path as data").
- A Group nested in a Zone Group is a container when stamped and geometry when not (D3a-1); Q13 keeps Piping groups out
  of Zone Groups so neither rule applies. `ph_composer.zones.containment` answers, per path, the holding Zone or none
  with a reason, and the write refusal (P3b-03).

## Inferred in planning

- **Piping group record.** Dictionary `ph_composer.piping.group` on the Group: `id` (`ppg_`, for the reference scan),
  `hot_water_system_id` (a declared `one` reference to `ph_composer.mechanical.hot_water_system`, nullable: null is the
  PRD's blocking "Piping group with no Hot Water System"), `user_data`, schema version 1. A copy shares the id, read
  as `copied`, as Edge records are.
- **Membership is the direct parent.** An Edge is a Pipe only when its parent container is a Piping group (PRD:
  "Membership is by parent group, the same rule Spaces follow"). An Edge in a plain Group inside a Piping group is not
  a Pipe; assign refuses it.
- **Where a group may sit (Q13).** At the Model root or inside plain wrapper Groups. `groups.create` and
  `pipes.assign` refuse `piping.group_in_zone` for a group that `zones.containment` says a Zone holds, and
  `piping.group_nested` for a Piping group inside another.
- **`groups.create`** adds an empty Group at the Model root, writes its record with the given System and opens it
  through `EditContext.enter`, in one Undo step. Whether an empty Group survives the commit and opens is not measured
  (Host gate, H1); the design rests on it. If it fails on the host, this sub-stage stops and records it, and the
  route becomes "Make Piping group" over selected loose lines, the Make Zone shape, which keeps the wrapped Edges' ids
  and dictionaries (SD01).
- **`groups.link`** sets or replaces the System on explicit group references with `expected_values`; `groups.unlink`
  sets it to null.
- **Pipe assignment record.** Dictionary `ph_composer.piping` on the Edge: `id` (`ppe_`), `pipe_type_id` (a declared
  `one` reference to `ph_composer.piping.pipe_type`, nullable: null is the PRD's blocking "Pipe with no Pipe Type"),
  `role` (`trunk`, `branch`, `twig`, `recirculation`, required), the role values, `user_data`, schema version 1.
- **The role values** (the cross-stage inference in P4-13): a `trunk` carries `multiplier` (integer >= 1, default 1)
  and `demand_recirculation` (boolean, default false); a `recirculation` pipe carries `water_temp_c` (number, default
  60.0) and `daily_period` (hours a day, 0 to 24, default 24); a `branch` and a `twig` carry neither. A role's values
  are required for it and absent for the others, as D4-19 binds a heater's variant. Reassigning a role drops values the
  new role does not take. *If Ed answers otherwise, this bullet, step 3's schema line and one M13b clause change.*
- **A pipe with no role** cannot be written: `pipes.assign` requires one, and Clear removes the whole record. The PRD's
  "Pipe with no role" finding is therefore an unreadable record, reported by P4-13c's scan as `record.unreadable`.
- **The gesture limit** is 250 Edges, as for thermal bridges, owned by the assignment schema; one over refuses the
  whole command `gesture.too_large`.
- **Delete in use.** `pipe_types.delete` refuses `reference.in_use` while an Edge names the type, or rewrites every
  assigned Edge occurrence through the store with `replacement_id`, or nulls `pipe_type_id` with null, in one proposal,
  refusing atomically through shared storage, as P3b-03's `types.delete` does. Deleting a Hot Water System a Piping
  group names refuses `reference.in_use` through the engine's reference scan, and with `replacement_id` retargets the
  group through the engine's `reference_plan`. Mechanical's delete must not name piping; the test proves the engine
  carries it. If mechanical's delete does not route foreign referrers through the engine, this sub-stage stops and
  records it rather than adding a piping branch to mechanical.
- **The reference target** `ph_composer.piping.pipe` takes `group_path` and `entity_path` (root to Edge) and
  `entity_id`; `locate:` walks the path verifying each parent-child step, refuses `target.*` as P3b-03's does, refuses an
  Edge whose parent is not a Piping group (`piping.outside_group`) and one whose record changed under its reference
  (`target.changed`).
- **Selection.** `pipes.selection` and the `pipes.selected` snapshot section: the native selection under the active
  path, Edges only, each as a reference with its group, System, current assignment and write refusal; anything else is
  reported as ignored. A long-lived selection client in the shape thermal bridges use serves P4-13e's assign bar.

## Inferred in implementation

- **The Hot Water System delete did not route foreign referrers (for Ed).** The stop condition above was met:
  Mechanical's System delete rewrote only Zones, Heaters and Tanks, so with a Piping group naming System A,
  `hot_water_systems.delete` refused `reference.in_use` with a `replacement_id`, and with null, as without one
  (probe run 2026-11-24). The stage stopped and reported. The conductor chose the generic seam: the System delete now
  calls `request.retarget_references` (the documented definition-delete contract that Assemblies, Programs and Windows
  use) when given an id or null and joins that plan to Serves', naming no feature; piping registers the retargeter
  `ph_composer.piping.groups.retarget_hot_water_system`. `tests/mechanical_hot_water_test.rb` proves it with a probe
  feature, `tests/piping_group_test.rb` with a Piping group. No piping branch is in Mechanical.
- **Stores.** Each record's `EntityStore` sits in its `schema.rb`, as thermal bridges' does, so there is no
  `store.rb`.
- **A same-role reassign keeps its values.** Reassigning a trunk with only a new type keeps its `multiplier`; the
  defaults apply on a first assignment or a role change.
- **No repair route.** An Edge or group whose stored text is not a JSON object refuses every write
  (`record.unreadable`); unreadable text names nothing, so deletes pass over it, as thermal bridges' do.
- **`groups.create`** does not check that the Model is shown or that no tool is active, as `ph_composer.context.open`
  does; H1 measures the path change inside the operation.

## Steps

1. **Piping group store and target.** `features/piping/group/schema.rb`, `store.rb`, `reference_target.rb`: the record
   above on `Records::EntityStore`, the target `ph_composer.piping.group` resolving a Group by path.
2. **Group operations.** `group/operations.rb`: `groups.create` (System id, opens the group through
   `EditContext.enter`), `groups.link`, `groups.unlink`, `groups.all` (every Piping group occurrence with its System,
   pipe count, `copied` and placement findings) and a bounded `groups.list`.
3. **Assignment store and target.** `features/piping/assignment/schema.rb`, `store.rb`, `reference_target.rb`: the
   record above, the role values validated per role, `GESTURE_EDGE_LIMIT` 250.
4. **Assign and clear.** `assignment/operations.rb`, `steps.rb`: `pipes.assign` over explicit Edge references with
   `expected_values` (absent when unassigned), a type id, a role and the role's values; resolves every target through
   one index, asks `zones.containment` once for the groups' paths, refuses the whole command if any target is stale,
   outside a Piping group, in a group a Zone holds, behind a write refusal or over the limit; writes one record per Edge
   in one proposal, a fresh `ppe_` on a first assignment and the existing id on a reassignment. `pipes.clear` removes
   the dictionary. Both end with `session.changed` and declare `preconditions` and `side_effects`.
5. **Selection.** `assignment/selection.rb`: `pipes.selection`, `pipes.selected` and its client.
6. **Delete in use.** `pipe_types.delete` gains the in-use refusal and the Edge rewrite (`reference_plan`); the Hot
   Water System's delete is exercised through the engine as above.
7. **Declarations.** `declarations/groups.rb`, `declarations/pipes.rb`, codes `piping.outside_group`,
   `piping.group_in_zone`, `piping.group_nested`. API minor bump, one `API::CHANGES` row, the recipe extended, `make
   fixtures`.
8. **Documents.** `context/CONTRACTS.md` (storage table rows for the two entity records and their targets),
   `context/TECH_STACK.md`, "Edge-owned assignments" (a bullet: piping's Edges live in Piping groups outside Zones, so
   Zones does not hold them and containment is read only to refuse a group a Zone holds), the packet CONTRACTS,
   `context/AGENT_INTERFACE.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/thermal_bridges/assignment/` (`schema.rb`, `reference_target.rb`, `operations.rb`, `steps.rb`, `selection.rb`) | The Edge store, target, assign and clear, selection and its client |
| `features/thermal_bridges/declarations/assignment.rb`, `types.rb` | Declarations; delete with replacement over Edges |
| `features/zones/` `zones.containment` | The Q13 refusal |
| `session/edit_context.rb` | Opening the new group |
| `features/shading/` (the Shading mark on a Group) | An entity-owned record on a Group, measured in SD01 |

## Tests (write first)

1. Groups (`tests/piping_group_test.rb`): `groups.create` adds one Group at the root with a `ppg_` record naming the
   System and opens it, in one Undo step that Undo removes; `groups.link` with stale `expected_values` refuses; a
   group inside a Zone Group refuses `piping.group_in_zone` and one inside a Piping group `piping.group_nested`; a
   copied group reads `copied`; deleting a System a group names refuses `reference.in_use`, and with a replacement
   retargets the group in one Undo step that Undo restores.
2. Assignment (`tests/piping_assignment_test.rb`): assign three Edges in a Piping group as a trunk with multiplier 12,
   one Undo step; reassign one as recirculation with 55 °C and 18 h, and its trunk values are gone; a trunk with a
   `water_temp_c`, a branch with a `multiplier` and a recirculation pipe with `daily_period` 25 refuse `params.invalid`;
   an Edge outside any Piping group, one in a plain Group inside a Piping group and one behind a locked group refuse,
   writing nothing; 251 Edges refuse `gesture.too_large`; clear removes the record; a split Edge reads two pipes with
   one id, marked `copied`.
3. Delete in use: deleting a Pipe Type an Edge names refuses `reference.in_use`; with a replacement every Edge names it,
   with null every `pipe_type_id` is null, each one Undo step; through two placements of one group definition the delete
   refuses atomically.
4. Selection: a selection of two Edges and a Face reports the Face as ignored and each Edge's group, System and
   assignment.
5. The walkthrough (`tests/piping_assignment_walkthrough_test.rb`, the shape of
   `thermal_bridge_assignment_walkthrough_test.rb`): create a group, draw three lines through the stub host, assign,
   clear, Undo, Redo, reopen.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M13b`, panel closed, on the installed RBZ. It runs the host cases no
evidence covers yet, and the design above rests on them:

- H1. `groups.create` on the root: the empty Group survives the operation's commit, is the active path afterwards,
  and survives Undo, Redo, save and reopen once lines are in it.
- H2. The native Line tool, drawing in that open group, puts its Edges in the group's entities.
- H3. A line started on the middle of a loose Edge in the faceless group splits that Edge and shares the new vertex
  (one vertex id at the tee), and two crossing loose lines split each other; a tagged Edge split this way puts its
  dictionary on both halves (T01 measured this for an Edge on a Face only).
- H4. Assign and clear over a native selection, one Undo step each; a pasted Piping group shares storage and its
  assign refuses until made unique.

Record with `acceptance_case.py begin` and `finish`. Offline `make ci` passes on this sub-stage's PR.

## Out of scope

Runs, the tree, findings and the schedule (P4-13c). Export (P4-13d). The assign bar, New Piping group button, pipe
tool and Colour-by (P4-13e). An edge registry (Q1). Pipes inside Zone Groups (Q13).

## Done when

- M13b has offline evidence in `../evidence/p4-13b-piping-groups-and-assignment.md`; host verification, H1 to H4
  included, lands in `MS3`.
- `make ci` passes on both Rubies; the installed size is recorded against the 75 KB estimate.
