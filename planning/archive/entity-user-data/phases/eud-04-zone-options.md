# EUD-04: Building Segments and Levels

STATUS: Complete
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-3, D-UD-5 ([plan](../PLAN.md#decisions-for-ed))

## Scope

Make option metadata writable on existing options. Each Zone carries a full copy of its options
as `choice_evidence` (`features/zones/zone/schema.rb`), so a metadata write must rewrite that
evidence in the same step, as `options.update` already does for values
(`features/zones/options/operations.rb`).

## Steps

1. Let a `RecordKind` declare a metadata follow-up: a callable that adds the owner's dependent
   steps to the proposal after the metadata change. The core action calls it. Options declare the
   evidence rewrite.
2. Option merge and remove: the survivor keeps its map; the result lists the removed option's
   non-empty map keys (D-UD-5). Undo restores both.
3. Adoption from evidence keeps the map (already true; test it).
4. API minor bump, `make fixtures`, agent guide line.

## Tests to write first

In `tests/zone_options_test.rb`:

- Write a Level map; every Zone's evidence and member-Face stamps carry the new copy in the same
  step; one Undo reverts both.
- Merge two Building Segments with different maps: survivor unchanged, report lists the other.
- Adopt a copied Zone into a Model without the option: the rebuilt option has the map.

## Done

As EUD-01.
