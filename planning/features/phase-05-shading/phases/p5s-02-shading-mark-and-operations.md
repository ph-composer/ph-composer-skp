# P5s-02: the shading mark and its operations

DATE: 2026-11-19
STATUS: Scoped. Authorized 2026-11-19 with every Shading stage ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

## Entry and scope

Requires P5s-01. Owns the feature's registration, the store, the Shading Face read, `assign`,
`clear`, `list`, `selection` and the codes. Panel closed; no menu, no colour mode, no export.
Paths are relative to `src/ph_composer/`. Behavior owner: the [PRD](../PRD.md). Names: [CONTRACTS](../CONTRACTS.md).

## Steps

1. **Feature.** `features/shading/install.rb`, feature id `ph_composer.shading`, requiring
   Zones; one line in `extension.rb`. Layout: `mark/` (schema, store, steps), `reads.rb`
   (pure: which Faces are shading, their component names), `operations.rb`, `selection.rb`,
   `codes.rb`, `declarations/`.
2. **Store and schema.** The store of CONTRACTS section 2, with the exclusion flag P5s-01 named
   (the flag itself, in `core/records/entity_store.rb`, lands here with its tests; Zones does not
   read it until P5s-03).
3. **Eligibility.** One pure function from a resolved target to "takes the mark" or a code:
   the PRD's "What can be tagged" table, row for row. Zone and classification facts come from
   Zones' registered reads (`zones.containment`, `faces.host_context`); claimed entities from
   `EntityStore.claimed?` and `claimed_within?`.
4. **Names.** The rule of D5s-10 as a pure function over a root path's containers, tested on
   nested, unnamed, instance-named and Zone cases.
5. **Actions.** `assign` and `clear`: resolve every target strictly, apply to the eligible ones
   in one native operation, return `assigned` or `cleared`, `unchanged` and `left_out`.
   Refuse whole when every target is left out (D5s-13); a command whose targets are all `unchanged`
   completes and writes nothing.
6. **Queries.** `list` and `selection`, each one walk.
7. **Agent surface.** Descriptions, examples and refusals on every registration; the API change
   row; `docs/AGENT_GUIDE.md` gains a Shading section.

## Tests

One per row of the eligibility table; Undo and Redo of each action; mixed selection; stale
revision; unreadable mark; `user_data` survives assign on an already-marked entity.

## Done when

SD02 passes on the host with a panel-closed script.
