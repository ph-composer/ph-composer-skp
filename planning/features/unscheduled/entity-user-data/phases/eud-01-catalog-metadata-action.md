# EUD-01: one metadata action for catalog records

STATUS: Implemented on branch
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-3 ([plan](../PLAN.md#decisions-for-ed))

## Scope

Add `ph_composer.records.update_metadata`, a core action beside `ph_composer.records.list` and
`.detail` (`shell/record_queries.rb`). It writes `user_data`, installed extension payloads or both
on catalog records of any registered kind: Materials, Assemblies, Frames, Glazings, Psi-Install
Types, Window Types, Thermal Bridge Types and Attached zones. Building Segments and Levels join in
EUD-04, nested parts in EUD-02.

Out: entity-owned records (they keep their owners' `update_metadata` actions), nested parts,
export, documentation beyond the generated reference and the agent guide entry.

## Steps

1. Params from `SchemaShapes.metadata_updates` with reference `{kind, id}`. Each entry carries
   `expected_metadata`; `Records::Metadata.distinct_updates` and `.planned` apply unchanged.
2. Resolve every target through the engine before building any step. A kind the engine does not
   know refuses `params.invalid`; a missing record refuses `target.not_found`; a kind whose owner
   manages metadata writes elsewhere refuses until it declares how (EUD-04 adds the declaration
   for options).
3. The whole batch is one proposal, one step, one Undo entry; a batch that writes what is stored
   adds no step. Validate each record through its kind after the change.
4. Remove `user_data` from every catalog `*.update` and from the update side of
   `attached_zone.save` and `installs.save`; create actions keep it. Library `replace` callbacks
   already strip it and stay correct. Update their tests and the guide.
5. Bump the API minor version with a change note; `make fixtures`; one recipe line in
   `docs/AGENT_GUIDE.md` and the shipped guide.

## Tests to write first

In a new `tests/record_metadata_test.rb`, sized like `tests/entity_metadata_test.rb`:

- Set, replace and clear on a Material and an Assembly; reads return detached copies.
- Stale `expected_metadata` refuses `target.changed` and writes nothing, across a two-target batch.
- Invalid JSON (non-finite number, non-string key) refuses `params.invalid` before any write.
- Unicode, null, false, zero and empty containers round trip.
- A no-op batch adds no Undo step; a real batch adds exactly one.
- An Attached zone update keeps its assignments valid.

## Done

Tests pass, `make ci` passes, the architecture review skill and Ruby quality criteria have read the
diff, the generated reference lists the action, and the stage row in [STATUS](../STATUS.md) reads
`Implemented on branch` with the commands and counts.
