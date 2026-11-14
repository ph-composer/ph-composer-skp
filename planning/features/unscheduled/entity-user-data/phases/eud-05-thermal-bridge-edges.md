# EUD-05: Thermal Bridge Edge assignments

STATUS: Scoped
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-5 ([plan](../PLAN.md#decisions-for-ed))

## Scope

Edge assignment records already accept and keep metadata. Expose it in reads and add the owner's
metadata action, addressed by occurrence because one `tbe_` id can repeat after a split or copy.

## Steps

1. `features/thermal_bridges/declarations/assignment.rb`: rows report `user_data`,
   `extension_data` and `extension_status` as the Zone and Face reads do, within the same bounded
   read limits.
2. Add `ph_composer.thermal_bridges.edges.update_metadata` with
   `SchemaShapes.metadata_updates` over the Edge occurrence reference, resolved through the
   owner's writable resolver, and the same batch, guard and Undo rules as
   `ph_composer.zones.faces.update_metadata`. An Edge without an assignment refuses.
3. `assign` and reassignment keep the map (already true); `clear` deletes it with the record;
   `edges.repair` keeps reporting discarded keys.
4. API minor bump, `make fixtures`, agent guide line.

## Tests to write first

In the thermal-bridge assignment tests:

- Write, read and clear the map on one occurrence; a second occurrence sharing the `tbe_` id is
  untouched.
- Stale pre-image, unassigned Edge and conflicting batch entries refuse and write nothing.
- Reassign keeps the map; clear then Undo restores it.

## Done

As EUD-01.
