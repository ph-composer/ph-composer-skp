# AW-01 · Safe targets, ownership and creation receipts

STATUS: Merged to main (#440, `c67dfb1f`). ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication.
DEPENDS ON: latest SUI-02/05/07 source check and explicit implementation authorization.
FINDINGS: R01-R04. CONTRACTS: C01. ACCEPTANCE: A01-A04.

## Outcome

Every authoring route respects the same identity, lock and ownership rules. A request's successful
receipt accurately names the geometry it accepted and the objects it created.

## Work

1. Reproduce each finding on the new baseline. SUI-02 `f93d8b6b` already rejects directly claimed
   selected entities; reuse its `EntityStore.claimed?`. Test a plain wrapper containing a Space and
   legacy Group with both ownership records before deciding what remains. Record the chosen
   descendant/legacy rule; do not prohibit normal Face/Edge assignments.
2. Guard conversion and destructive subtree deletion through a feature-neutral claim/reference
   contract. No new cross-feature dependency from Zones to Spaces. Emit a read-only diagnostic for
   conflicting legacy ownership and refuse destructive writes until an explicit recovery is chosen.
3. Replace tolerant explicit Face mutation resolution with strict absent/present identity checks in
   classify, reverse, Assembly assignment and apply. Preserve genuine unassigned-Face authoring.
4. Align single/batch/metadata Zone edit eligibility, including the Zone's own lock, ancestors,
   shared definitions and duplicated identity.
5. Coordinate SUI-05's Space create result. Return accepted and left-out paths/reasons and created
   grouping; bind reviewed input to application. Preserve its intentional UI filtering. If that
   work already supplies the contract, record coverage and make no parallel implementation.

## Source and tests

Start at `src/ph_composer/core/records/entity_store.rb`, Zones `zone/{operations,occurrences,steps}.rb`,
`faces/{operations,assembly_assignment,steps}.rb`, Spaces `{authoring,create_faces,steps}.rb`, and
their declarations. Use `evidence/feature_probe.rb` in the review as the reproduction, not a test
that freezes bad behavior. Extend `zone_face_test.rb`, `spaces_operations_test.rb`, metadata/reference
and ownership tests with the specific missing cases. Include preview and apply-time changed-state
refusals, all-target rollback and unaffected dictionary/reference checks.

## Native gate and done

Synthetic nested, copied, locked and legacy-overlap models; native Undo/Redo and save/reopen prove
the retained identities, geometry and refs. Nothing is silently erased. Space create reports the
same accepted grouping on UI and API paths. Use the stronger review level for identity/deletion.
Complete PLAN's gates and docs-pass; update affected context rules and the ledger with actual evidence.

Do not redesign all entity storage, add generic CAD writes or fix unrelated geometry algorithms.
