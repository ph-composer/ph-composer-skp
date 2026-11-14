# EUD-03: Window Elements

STATUS: Implemented on branch
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-4, D-UD-5 ([plan](../PLAN.md#decisions-for-ed))

## Scope

Optional `user_data` on Window Elements, declared as the Window Type's `elements[]` part, written
through the EUD-01 action. Every grid and product gesture follows the plan's lifecycle policy.

## Steps

1. `features/windows/types/schema.rb`: optional `user_data` on `ELEMENT`; declare the part.
   `Types.blank` creates an element without a map.
2. `features/windows/types/grid_operations.rb`: split deep-copies the source map into every child
   (already true; test it). Merge keeps the top-left survivor's map and returns each removed
   element with a non-empty map, with its top-level keys. Insert creates elements without maps.
   Kind change keeps the map.
3. `install_save.rb`, `types/operations.rb` duplicate, and `new_flipped_type` in
   `units/repairs.rb` keep maps while re-identifying elements.
4. `types.elements.list` reads include the map.
5. API minor bump, `make fixtures`, agent guide line.

## Tests to write first

- Write and read an element map by `[type_id, element_id]`.
- Split, merge (with the removed-map report), insert, kind change, installs save, duplicate and
  flipped Type each against the policy.
- `windows.types.update` with a whole `elements` array stores the element maps it sends, as
  whole-value replacement already does; the guide says so.

## Done

As EUD-01.
