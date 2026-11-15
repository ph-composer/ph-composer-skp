# EUD-06: Model root and Space Floor

STATUS: Complete
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-1, D-UD-2 ([plan](../PLAN.md#decisions-for-ed))

## Scope

Give the Model its own map, and the logical Space Floor a map stored on its Volume.

## Steps

1. Model (D-UD-1): a core `ModelSettings` dictionary `ph_composer.model` with `user_data` and
   `extension_data`. `ph_composer.model.detail` reads it (absent reads as empty, without a write);
   `ph_composer.model.update_metadata` writes it with `expected_metadata`, one step, no-op rule.
   Feature settings dictionaries are untouched.
2. Space Floor (D-UD-2): optional `floor_user_data` on the Volume record
   (`features/spaces/schema.rb`). `spaces.update_metadata` accepts a Space Floor reference
   (`{floor_id, entity_path}` of its Volume) and writes that field only. Volume reads report it as
   the Floor's map, never merged with the Volume's. Volume copy and identity plans keep it.
3. API minor bump, `make fixtures`, agent guide lines.

## Tests to write first

- Model map write, stale refusal, no-op, Undo; reading a Model with no dictionary writes nothing.
- Floor map write and read; the Volume's own map is unchanged; a copied Volume has an independent
  copy.

## Done

As EUD-01.
