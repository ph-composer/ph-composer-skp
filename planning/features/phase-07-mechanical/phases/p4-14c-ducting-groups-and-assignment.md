# P4-14c: Ducting groups and the duct assignment

DATE: 2026-11-24
STATUS: In review 2026-11-25 on `feat/phase-07-mechanical-p4-14c`, on `main`; offline evidence in [p4-14c-ducting-groups-and-assignment](../evidence/p4-14c-ducting-groups-and-assignment.md), host case `M14c` owed to MS3. Planned in full 2026-11-24 from [P4-14](p4-14-erv-ducting.md), D4-37 (Q2, Q3, Q4, Q5, Q6) and the [ducting PRD](../erv-ducting/PRD.md), "Behaviors". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M14c` runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-14b (or, if Ed chose the copy, P4-14a alone, with piping's files as the pattern for each part). Owns,
panel closed:

- The Ducting group: an entity-owned record on a SketchUp Group linking it to one Ventilator, created by
  `groups.create`, which also opens it for drawing with the native Line tool (Q5).
- The duct assignment: an entity-owned record on an Edge with its Duct Type, direction and quantity, its reference
  target, `ducts.assign`, `ducts.clear`, the selection read, and delete in use for Duct Types and for Ventilators a
  group names.
- The generic referrer seam on Mechanical's Ventilator delete.

Behavior owner: the [ducting PRD](../erv-ducting/PRD.md), "Behaviors", and the edge rules in `context/TECH_STACK.md`,
"Edge-owned assignments". Names: this document, folded into [CONTRACTS](../CONTRACTS.md) in step 8. Pattern: P4-13b
(`features/piping/group/`, `assignment/`, `declarations/groups.rb`, `declarations/pipes.rb`) over P4-14b's layer.

Paths are relative to `src/ph_composer/`.

## What the sources settle

- The Edge rules, the shared-storage rule for a pasted Group and the active-path rule are as P4-13b cites them
  ([P4-13b](p4-13b-piping-groups-and-assignment.md), "What the sources settle").
- Mechanical's `ventilators.delete` (`features/mechanical/ventilators/operations.rb`) takes a `reference_plan` from
  its declaration, which builds it from Serves alone; it does not call `request.retarget_references`, so another
  feature's record naming a Ventilator refuses the delete with a replacement or null, as the Hot Water System delete
  did before P4-13b ([P4-13b](p4-13b-piping-groups-and-assignment.md), "Inferred in implementation").

## Inferred in planning

- **Ducting group record.** Dictionary `ph_composer.ducting.group` on the Group: `id` (`dcg_`), `ventilator_id` (a
  declared `one` reference to `ph_composer.mechanical.ventilator`, nullable: null is the PRD's blocking "Ducting group
  with no Ventilator"), `user_data`, schema version 1. A copy shares the id, read as `copied`, and keeps its link (Q4).
- **Membership is the direct parent**, and a Ducting group sits at the Model root or in plain wrapper Groups, never in
  a Zone Group (`ducting.group_in_zone`) nor in another Ducting group (`ducting.group_nested`), as piping's (Q5).
- **`groups.create`** adds an empty Group at the root with the given Ventilator and opens it, in one Undo step; it
  rests on P4-13b's unmeasured H1 and H2 (P4-14, "Host cases owed to MS3"). `groups.link` sets or replaces the
  Ventilator with `expected_values`; `groups.unlink` sets it to null.
- **Duct assignment record.** Dictionary `ph_composer.ducting` on the Edge: `id` (`dce_`), `duct_type_id` (a declared
  `one` reference to `ph_composer.ducting.duct_type`, nullable: null is the PRD's blocking "Duct with no Duct
  Type"), `direction` (`outdoor_air` or `exhaust_air`, required, Q2, Q3), `quantity` (integer >= 1, default 1, Q4),
  `user_data`, schema version 1.
- **A duct with no direction** cannot be written: `ducts.assign` requires one, and Clear removes the whole record. The
  PRD's "Duct with no direction" is therefore an unreadable record, reported by P4-14d as `record.unreadable`, as
  piping's role is.
- **A reassign keeps what it is not given.** A reassign with only a new type keeps the direction and quantity; a
  first assignment takes quantity 1.
- **The gesture limit** is 250 Edges, as for pipes; one over refuses the whole command `gesture.too_large`.
- **Delete in use.** `duct_types.delete` refuses `reference.in_use` while an Edge names the type, rewrites every
  occurrence with `replacement_id`, or nulls `duct_type_id` with null, in one proposal, refusing atomically through
  shared storage. `ventilators.delete` calls `request.retarget_references(VENTILATOR_KIND, from:, to:)` when given a
  replacement or null and joins that plan to Serves', in the shape of `Mechanical::HotWater::Operations.with_retargeted`,
  naming no feature; ducting registers `ph_composer.ducting.groups.retarget_ventilator`, which retargets or unlinks
  every Ducting group occurrence. A plain delete still refuses `reference.in_use` naming the group.
- **The reference targets** `ph_composer.ducting.group` and `ph_composer.ducting.duct` take P4-14b's group and Edge
  paths with Ducting's spec; an Edge whose parent is not a Ducting group refuses `ducting.outside_group`.
- **Selection.** `ducts.selection` and the `ducts.selected` snapshot section: the native selection under the active
  path, Edges only, each as a reference with its group, Ventilator, current assignment and write refusal; anything
  else ignored. P4-14f's bar reads it.

## Inferred in implementation

- **Assign's params.** `duct_type_id`, `direction` and `quantity` are each optional; an Edge with no assignment needs
  a type and a direction (`params.invalid` otherwise) and takes quantity 1, and an assigned Edge keeps what it is not
  given, so both "requires a direction" and the quantity-only reassign above hold.
- **One retarget join for both deletes.** The Ventilator delete and the Hot Water System delete call one generic
  `CatalogOperations.with_retargeted`; `HotWater::Operations.with_retargeted` is gone.
- **No selection client and no `ducting.hidden` yet**: piping's client has no shipped caller, and the hidden code is
  Locate's, which P4-14d adds.
- The evidence names a consolidation candidate for Ed: ducting's operations and declarations twin piping's.

## Steps

1. **Group record and target.** `features/ducting/group/schema.rb` (the record on `Records::EntityStore`),
   `reference_target.rb` over `LineGroups::GroupTarget`.
2. **Group operations.** `group/operations.rb`: `groups.create`, `groups.link`, `groups.unlink`, `groups.all` (every
   occurrence with its Ventilator, duct count, `copied` and placement findings) and a bounded `groups.list`.
3. **Assignment record and target.** `features/ducting/assignment/schema.rb`, `reference_target.rb` over
   `LineGroups::EdgeTarget`, `GESTURE_EDGE_LIMIT` 250.
4. **Assign and clear.** `assignment/operations.rb`: `ducts.assign` over explicit Edge references with
   `expected_values` (absent when unassigned), a type id, a direction and a quantity, refusing as a whole for a stale
   target, an Edge outside a Ducting group, a group a Zone holds, a write refusal or the limit; one record per Edge in
   one proposal. `ducts.clear` removes the dictionary. Both end with `session.changed` and declare `preconditions`
   and `side_effects`.
5. **Selection.** `assignment/selection.rb` over `LineGroups::Selection`.
6. **Delete in use.** `duct_types.delete` gains the in-use refusal and the Edge rewrite; `ventilators.delete` gains the
   generic call above, with `tests/mechanical_ventilators_test.rb` proving it
   with a probe feature, as P4-13b proved the Hot Water System's.
7. **Declarations.** `declarations/groups.rb`, `declarations/ducts.rb`, codes `ducting.outside_group`,
   `ducting.group_in_zone`, `ducting.group_nested`. API minor bump, one `API::CHANGES` row (and a line for the
   Ventilator delete's new routing), the recipe extended, `make fixtures`.
8. **Documents.** `context/CONTRACTS.md` (storage rows for the two entity records and their targets; the Ventilator
   delete's retargeting), `context/TECH_STACK.md`, "Edge-owned assignments" (ducting's Edges follow piping's bullet),
   the packet CONTRACTS, `context/AGENT_INTERFACE.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/piping/group/`, `assignment/`, `declarations/groups.rb`, `declarations/pipes.rb` | The shape of each file |
| `line_groups/` (P4-14b) | The targets, steps, walk and selection |
| `features/mechanical/ventilators/operations.rb`, `declarations/ventilators.rb`, `hot_water/operations.rb` | The delete seam and its pattern |
| `features/zones/` `zones.containment` | The Q5 refusal |

## Tests (write first)

1. Groups (`tests/ducting_group_test.rb`): `groups.create` adds one Group at the root with a `dcg_` record naming
   ERV-1 and opens it, one Undo step; `groups.link` with stale `expected_values` refuses; a group inside a Zone Group
   refuses `ducting.group_in_zone`, inside a Ducting group `ducting.group_nested`; a copied group reads `copied` and
   keeps ERV-1; deleting ERV-1 while a group names it refuses `reference.in_use`; with ERV-2 as replacement the group
   names ERV-2 and Zone A's Serves slot names ERV-2, one Undo step that Undo restores; with null the group is
   unlinked.
2. Mechanical: the Ventilator delete retargets a probe feature's record through the foundation and names no feature;
   its existing delete tests pass unchanged.
3. Assignment (`tests/ducting_assignment_test.rb`): assign two Edges in a Ducting group as Outdoor air with DT-1, one
   Undo step; reassign one with quantity 2 and its type and direction stay; a missing direction, a direction outside
   the two, a quantity of 0 or 1.5 refuse `params.invalid`; an Edge outside any Ducting group, one in a plain Group
   inside one and one behind a locked group refuse, writing nothing; 251 Edges refuse `gesture.too_large`; clear
   removes the record; a split Edge reads two ducts with one id, marked `copied`.
4. Delete in use: deleting a Duct Type an Edge names refuses; with a replacement every Edge names it; with null every
   `duct_type_id` is null; each one Undo step; through two placements of one group the delete refuses atomically.
5. Selection: two Edges and a Face give the Face as ignored and each Edge's group, Ventilator and assignment.
6. The walkthrough (`tests/ducting_assignment_walkthrough_test.rb`, the shape of piping's): create a group, draw two
   lines through the stub host, assign, clear, Undo, Redo, reopen.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M14c`, panel closed, on the installed RBZ: `groups.create` linked to
ERV-1 opens for the Line tool and the lines drawn land in it (resting on M13b's H1 and H2, run first in the sitting);
assign and clear over a native selection, one Undo step each; a pasted Ducting group shares storage, keeps ERV-1, and
its assign refuses until made unique; deleting ERV-1 with a replacement retargets the group in one Undo step. Record
with `acceptance_case.py begin` and `finish`. Offline `make ci` passes on this sub-stage's PR.

## Out of scope

Runs, findings and the schedule (P4-14d). Export (P4-14e). The assign bar, New Ducting group and Colour-by (P4-14f).
Ducts inside Zone Groups (Q5). An edge registry.

## Done when

- M14c has offline evidence in `../evidence/p4-14c-ducting-groups-and-assignment.md`; host verification lands in
  `MS3`.
- `make ci` passes on both Rubies; the installed size is recorded against the 45 KB estimate and the headroom rule
  in P4-14, "Size".
