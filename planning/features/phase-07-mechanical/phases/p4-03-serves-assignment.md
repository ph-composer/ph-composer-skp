# P4-03: Serves, the assignment payload on the Zone

DATE: 2026-10-21
STATUS: In review 2026-11-23 on `feat/phase-07-mechanical-p4-03`, stacked on P4-02; offline evidence in [p4-03-serves](../evidence/p4-03-serves.md), host case `M03` owed to MS1. Re-planned 2026-11-22 to D4-21: Serves is a structured extension on the Zone record, staged through Zones, in place of the record, reference target and Zone-copy contributor first planned. See [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-02 and D4-05 and D4-21, with Q3, V1 and V5, and P4-01's answer to
[CONTRACTS](../CONTRACTS.md) section 7's first question. Owns the layer 3 half of the feature: the
Serves payload on the Zone record, its validator and declared references, assign and clear, the
one-per-Zone rule, delete in use with replacement or clear, and the unserved-Zone and
unserved-item findings. Panel closed. Zones and Spaces change nothing.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "The shared shape", Records and
Behaviors; where its Records sketch shows a record on the Zone Group, D4-21 replaces the
mechanism and keeps the behavior. Names: CONTRACTS sections 2 to 4. Pattern: Programs' Zone
assignment, `features/programs/occupancy.rb` (the extension and its validator) and
`assignments.rb` (the actions and the delete with a replacement), over Zones'
`features/zones/extension_staging.rb`.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The payload.** `serves/payload.rb`: the extension `ph_composer.mechanical.zone_serves`,
   schema version 1, registered with `feature.extension` on the Zone record. It is
   `export_relevance: "local_only"` in this stage: a `required` namespace with no claim blocks
   every export of a Zone that carries it, and the claim is P4-04's, which moves it to `required`
   in the same change (as Programs' P4a-08 and P4a-10 did). This stage declares `ventilator_id`, a `one` reference to
   `ph_composer.mechanical.ventilator`, null for none; later families add their slot as one line
   and move the schema version. The validator takes a whole payload and refuses an unknown key, a
   missing slot or an id of the wrong kind.
2. **Operations.** `serves/operations.rb`: `assign` (Zone references with `expected_values`, a
   slot, an item id, `replace`), refusing `mechanical.slot_filled` with the current item named
   unless `replace: true` (V1); `clear` (references and a slot, or every slot). Each builds the
   Zones' new payloads and hands them to `ph_composer.zones.stage_extension` in its own proposal,
   so every target is checked before anything is staged, Zones' `target.*` refusals pass through
   unchanged, and the command is one Undo step. An item id that names no stored Ventilator
   refuses before staging. A cleared Zone is staged the empty payload.
3. **Delete in use (D4-05).** Extend `ventilators.delete`: without a replacement the engine's
   scan refuses `reference.in_use`, and the action's message names the Zones; with
   `replacement_id` each payload naming the item is staged with the replacement; with an explicit
   null each is staged with the slot emptied; all in the delete's proposal, one Undo step, as
   Programs' delete of a Program a Zone names.
4. **Reads and findings.** `serves/reads.rb`, `serves.all` (query and snapshot section, bounded
   `list` beside it): every Zone occurrence with its slots, resolved item names, and
   `mechanical.zone_unventilated` (V5, non-blocking). A Zone with no payload and a Zone whose
   slots are all empty read alike, as served by nothing. The rows come from one
   `ph_composer.zones.all` read per snapshot and add no second walk: Phase 6 recorded the
   repeated Zones reads as a follow-up to fix, not to copy. `ventilators.all` rows gain the Zones
   each serves and `mechanical.item_unserved`. A slot naming an item that is not in the Model,
   which only a write through the generic metadata routes can leave, reads
   `mechanical.item_missing`. `codes.rb` gains the codes. API minor bump and change row; the agent
   guide recipe gains assign and clear with their explicit-reference shapes.
5. **Metadata (F36).** Serves keeps no `user_data` of its own: it is a payload on the Zone, whose
   map is Zones'. `docs/USER_DATA.md` says so beside the Ventilator's row.
6. **Walkthrough.** Extend `ventilators_walkthrough.rb` to assign, replace, clear and delete with
   replacement, inside a nested Zone and a copied Zone.

No step builds a reference target, an `eqa_` id or a Zone-copy contributor. The payload declares
its references, and it travels with a copied Zone because it is part of the Zone record (D4-04's
outcome, with no code here).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/programs/occupancy.rb` (`Occupancy::ZONE_EXTENSION`, `references`, `problems`) | Pattern for the extension, its declared references and its whole-payload validator |
| `features/programs/assignments.rb` | Pattern for actions that stage payloads on named Zones and for a delete that moves them to a replacement |
| `features/zones/extension_staging.rb` | The participant every write goes through; unchanged |
| `features/assemblies/assembly/operations.rb` (`delete`) | The replacement and clear contract the delete follows (D4-05) |

## Tests (write first)

1. Assign stages the payload on the Zone record; a second assign without `replace` refuses
   `mechanical.slot_filled` naming the current item; with `replace: true` it replaces; Undo
   restores the previous slot.
2. A stale `expected_values` on one of two Zone references refuses the whole command and writes
   nothing.
3. Locked Zone, shared definition and nested Zone paths refuse with Zones' `target.*` codes.
4. Clear leaves the Zone reading as served by nothing, whether it held one slot or several.
5. Delete in use: refused `reference.in_use` naming the Zones; with a replacement every slot moved
   in one step and Undo restores all; with null the slots empty.
6. A native copy of a served Zone reads the same slots as its source, with no step of this
   feature in the copy's proposal.
7. `serves.all` and `ventilators.all` carry the findings and the resolved names; a served Zone in
   no Building Segment reads `mechanical.zone_left_out` and no unserved-Zone finding (shape only;
   the export consequence is P4-04's).
8. A payload stored through Zones' own `update_metadata` action naming a Ventilator that does
   not exist reads `mechanical.item_missing`; the validator refuses a payload
   with an unknown key.
9. Programs' `zone_assignment` payload on the same Zone is untouched by every Serves write, and
   a Programs write leaves the Serves payload as it was.

## Host gate

Fresh process on the reference model with Zone B under a rotated wrapper: assign ERV-1 to A and
ERV-2 to B from the walkthrough; replace; clear; delete ERV-1 with ERV-2 as replacement and Undo;
copy Zone B natively and read the copy's slots; save, reopen and read back.
Record each case with `acceptance_case.py`.

## Out of scope

The balance (P4-05). Export (P4-04). Any screen. Hot Water System slots (P4-06 adds its line).

## Done when

- M03 has evidence in `../evidence/p4-03-serves.md`.
- `make ci` passes on both Rubies; the API reference regenerates with no unrelated diff.
