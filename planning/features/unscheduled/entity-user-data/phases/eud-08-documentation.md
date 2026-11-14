# EUD-08: documentation and coverage table

STATUS: Scoped
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-7, D-UD-8 ([plan](../PLAN.md#decisions-for-ed))

## Scope

The PRD's documentation table, written against the final API. `docs/` is read by partners: plain
register, no em or en dashes.

## Steps

1. `docs/API_QUICKSTART.md`: a beginner recipe on an existing Face and a Material: read, change one
   namespace, guarded write, read back, clear; detached reads and whole-map replacement.
2. A coverage table (entity, read, write, copy, HBJSON, library) in one owning place, linked from
   `docs/.index.md`, the agent guide and `context/EXTENSIBILITY.md`.
3. `context/CONTRACTS.md` "Records and extension data": the part declaration, the core action, the
   lifecycle policy, Model and Space Floor ownership. Remove the "not yet complete" qualification
   from `context/EXTENSIBILITY.md` and add the obligation for new contributions.
4. `docs/LIBRARY_FILE_FORMAT.md`: the per-kind statement that wire rows carry no metadata and that
   replace keeps the local map (D-UD-7).
5. `tools/examples/foundation/README.md`: link to the recipe.
6. `context/UBIQUITOUS_LANGUAGE.md`, `context/TECH_STACK.md`, `context/.index.md` only where
   affected.

## Tests to write first

Run the recipe's calls against the in-process API in a test that already exercises the guide
examples, if one exists; otherwise a focused test that executes each recipe call.

## Done

`make lint-paths` and `make ci` pass; every link resolves; the inventory in [PLAN](../PLAN.md) and
the published coverage table agree.
