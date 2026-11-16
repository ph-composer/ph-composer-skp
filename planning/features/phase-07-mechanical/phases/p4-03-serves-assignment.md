# P4-03: Serves, the assignment record and target

DATE: 2026-10-21
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4-02 and D4-03, D4-04 and D4-05, with Q3, V1 and V5. Owns the layer 3 half of the
feature: the Serves record on the Zone Group, its reference target, assign and clear, the
one-per-Zone rule, delete in use with replacement or clear, the Zone-copy contributor, and the
unserved-Zone and unserved-item findings. Panel closed. Zones and Spaces change nothing.

Behavior owner: the [equipment PRD](../equipment/PRD.md), "The shared shape", Records and
Behaviors. Names: [CONTRACTS](../CONTRACTS.md) sections 2 to 4. Pattern: Windows' Unit record and
`units/zone_copy.rb`; `tests/support/zone_child_fixture.rb`; the Assembly delete with replacement.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The record and store.** `serves/schema.rb` and `serves/store.rb`: `Records::EntityStore` on
   `ph_composer.equipment_serves`, `eqa_` id, the Ventilator slot as a core `Records::Reference`
   (cardinality one, nullable); later families add their slot as one line. A record whose slots
   are all empty is removed.
2. **The target.** `serves/reference_target.rb`: `ph_composer.equipment.serves` with the Zone
   reference shape plus `entity_id`; records provider over `ph_composer.zones.all` occurrences
   carrying the dictionary; `locate:` through `request.locate("ph_composer.zones.zone", ...)` then
   the store's read, refusing `target.changed` when the id differs; `references:` naming the
   slots so the engine's incoming-reference scan guards item deletes.
3. **Operations.** `serves/operations.rb` and `serves/steps.rb`: `assign` (Zone references with
   `expected_values`, a slot, an item id, `replace`), refusing `equipment.slot_filled` with the
   current item named unless `replace: true` (V1); `clear` (references and a slot, or whole
   records). Every target checked before any step is built; one proposal, one Undo step.
4. **Delete in use (D4-05).** Extend `ventilators.delete`: without replacement, refuse naming the
   Zones; with `replacement_id`, `request.retarget_references` rewrites the slot on every Serves
   record; with explicit null, clear the slot and remove emptied records; one Undo step.
5. **Zone copy (D4-04).** `serves/zone_copy.rb`: a `transition_contributor` on
   `ph_composer.zones.occurrence_independent` that re-issues the copied record's `eqa_` id through
   the identity allocator in the Zone's own proposal and changes nothing else.
6. **Reads and findings.** `serves.all` (query and snapshot section, bounded `list` beside it):
   every Zone occurrence with its record, resolved item names, and `equipment.zone_unventilated`
   (V5, non-blocking); `ventilators.all` rows gain the Zones each serves and
   `equipment.item_unserved`. `codes.rb` gains the three codes. API minor bump and change row;
   the agent guide recipe gains assign and clear with their explicit-reference shapes.
7. **Walkthrough.** Extend `ventilators_walkthrough.rb` to assign, replace, clear and delete with
   replacement, inside a nested Zone and a copied Zone.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/windows/units/records.rb`, `units/zone_copy.rb`, `units/identity_plan.rb` | Pattern for an entity-owned record and the copy contributor |
| `tests/support/zone_child_fixture.rb` | The minimal second-child shape; this stage's contributor re-issues one id per Zone |
| `features/zones/declarations/zone.rb` (`TARGET`, `locate_zone`) | The Zone locate this target delegates to |
| `features/assemblies/assembly/operations.rb` (`delete`) | Pattern for replacement and clear |

## Tests (write first)

1. Assign writes the record on the Zone Group; a second assign without `replace` refuses
   `equipment.slot_filled` naming the current item; with `replace: true` it replaces; Undo
   restores the previous slot.
2. A stale `expected_values` on one of two Zone references refuses the whole command and writes
   nothing.
3. Locked Group, shared definition and nested Zone paths refuse with Zones' `target.*` codes.
4. Clear removes a record whose last slot empties; the Zone reads as served by nothing.
5. Delete in use: refused naming the Zones; with replacement every slot rewritten in one step and
   Undo restores all; with null the slots clear and emptied records go.
6. The Zone-copy contributor re-issues the `eqa_` id and keeps the slots; `identity.conflict` on a
   colliding allocation refuses.
7. `serves.all` and `ventilators.all` carry the findings and the resolved names; a Zone omitted
   from export reads `equipment.zone_omitted` (shape only; the export consequence is P4-04's).
8. A test-only second feature's record on the same Zone Group (P4-01's fixture) is untouched by
   every Serves write.

## Host gate

Fresh process on the reference model with Zone B under a rotated wrapper: assign ERV-1 to A and
ERV-2 to B from the walkthrough; replace; clear; delete ERV-1 with ERV-2 as replacement and Undo;
copy Zone B natively and read the copy's record with its new id; save, reopen and read back.
Record each case with `acceptance_case.py`.

## Out of scope

The balance (P4-05). Export (P4-04). Any screen. Hot Water System slots (P4-06 adds its line).

## Done when

- M03 has evidence in `../evidence/p4-03-serves.md`.
- `make ci` passes on both Rubies; the API reference regenerates with no unrelated diff.
