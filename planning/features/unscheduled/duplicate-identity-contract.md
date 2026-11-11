# Duplicate-identity repair: Zones, Windows and Spaces side by side

DATE: 2026-11-11
STATUS: Scoped; design evidence only, no refactor authorized. Awaiting Ed's adopt or keep decision on #145.
AUTHOR: Claude (pr-loop stage worker), for Ed May
ISSUE: [#145](https://github.com/ph-composer/ph-composer-skp/issues/145)

## Recommendation

**Keep separate.** Do not build a foundation `duplicate_identity` contract with the keeper rule as a
parameter. Read on `main` today, the six keeper rules, three finding shapes and three binding strategies
(two of them after Make Unique) differ for domain reasons, and a contract shaped around them either hides those rules behind a
parameter or shrinks to helpers that take the mapping as input. Those helpers are worth having, but they
are a small mechanics refactor (net under 50 lines; its value is one ambiguity policy and one
restore policy), not a contract; an optional packet for them is
outlined at the end. The test applied throughout is the issue's own: a helper that *takes* the mapping,
the keeper set or the captured records hides nothing; anything that *chooses* the keeper or shapes the
finding does.

Four divergences surfaced that matter more than the line count (ambiguity policy, restore failure
policy, Undo bookkeeping, the Windows `ZoneCopy` keeper). Each feature tests its own side; the
counterpart cases are untested. They are listed under "Divergences" and filed as
[#468](https://github.com/ph-composer/ph-composer-skp/issues/468) for a test-first look, independent of
this decision.

Paths below are relative to `src/ph_composer/features/` unless they start with `core/`, `shell/`,
`session/`, `context/` or `tests/`. Line numbers are `main` at `78bc5749`.

## What changed since the issue was written

- #139 and #143 are closed. Both copy watchers now run on `session/deferred_work.rb` and hear copies
  through the `container_added` host event (`zones/zone/copy_watch.rb:37-41`, `:46`;
`spaces/copy_watch.rb:34-38`, `:43`).
  The issue's "copy watchers over `HostFollowUp`" is therefore one shape in two files, not two
  infrastructures.
- `Zones::CopiedGroups` (`zones/zone/copied_groups.rb:10-40`) is already shared: both watchers isolate a
  copied plain Group through it before repairing (`zones/zone/copy_watch.rb:160`, `spaces/copy_watch.rb:137`).
- Windows has no copy watcher. `Units::HostWatch` returns a moved Unit to its Face
  (`windows/units/host_watch.rb:8-20`); a copied Unit is repaired lazily by the next Windows action
  (`windows/authoring.rb:5-15`, `Units::Mutation.prepare`).

## Side by side

### Finding shape

| Feature | Shape | Source |
| --- | --- | --- |
| Zones | Row `state` `"ambiguous"` (or `"shared_definition"`, reported first), plus an `independence` object `{available, code, reason, retired_pairs}` computed by running the real plan, nil when the state is `"found"` | `zones/zone/operations.rb:209-211`, `:295-306`, `:321-331`, `:420-429` |
| Windows | Finding code `window.copy_id_pending` with a `repair` map naming `units.repair_copied_identities`; export issue of the same code | `windows/units/state.rb:16-21`, `:33`, `:55`; `windows/export_assessment.rb:138` |
| Spaces | Finding `space.duplicate_identity` with `blocks_export: true` and `repair: "make_independent"`; `repair` is omitted and the message changes when the repair is an ancestor's or storage above is shared; export refuses through `unique!` | `spaces/scan/findings.rb:8-16`, `:84-94`; `spaces/export.rb:281-290` |
| Thermal bridges (not a repairer) | Copies keep the `tbe_` id; reads mark `copied`, nothing re-issues | `context/CONTRACTS.md:437` |

The three consumers differ: Zones gates a row action on a live plan, Windows feeds a repair menu from a
code table, Spaces feeds export preflight. Only the grouping step (`group_by id, count > 1`) is common,
and it is one line each.

### Keeper rule (who keeps the id)

| # | Route | Rule | Source |
| --- | --- | --- | --- |
| 1 | Zones `repair_identity`, `make_independent` | The caller names the copy by path; it and every Face in it take new ids derived from the path and the copied id; everything outside keeps | `zones/zone/repair.rb:16-24`, `:38-59`; `zones/zone/operations.rb:43-73` |
| 2 | Zones copy watcher | An id held by exactly one original and by added occurrences: the added ones are the copies; a path through a component is dropped | `zones/zone/copy_watch.rb:136-153` |
| 3 | Zones `SplitIdentityRepair` | The stored Surface endpoint proves the keeper; otherwise the user chooses; a choice that contradicts proof refuses | `zones/zone/split_identity_repair.rb:186-216` |
| 4 | Windows `IdentityPlan` (every Windows action, and `repair_copied_identities`) | First occurrence by path keeps; `only` limits to named ids | `windows/units/identity_plan.rb:15-44` (keeper at `:25`) |
| 5 | Windows `ZoneCopy` (transition) | Every Unit inside whose id is held outside is renamed; no keeper inside | `windows/units/zone_copy.rb:40-66` (rule at `:46`) |
| 6 | Spaces `IdentityPlan` (explicit, watcher and transition) | The named target is always renamed; inside the scope an id held outside is renamed, an id held only inside keeps one holder, the first by path that is not the target | `spaces/identity/plan.rb:28-60`, `:84-90` |

A `keeper:` lambda over `(group_of_same_id, scope)` can express rules 4, 5 and 6, and rule 2 as an input
filter. It cannot express rule 3 (proof from a stored adjacency envelope, a user choice, a conflict
refusal) and only covers rule 1 by special-casing: Zones renames every Face in the copy whatever
its id count (`zones/zone/repair.rb:176-187`), derives ids from the path rather than an allocator
(`:40-41`, `:55-56`), rewrites stamps and retires copied Surface pairs (`:189-211`). Those are the rules
the contract would hide.

### Binding after Make Unique

| Strategy | Used by | Source |
| --- | --- | --- |
| By reference and pre-image; no Make Unique precedes | Zones `RepairIdentityStep`, Zones `SplitIdentityRepair::Step` (plus a global id count), Windows `IdentityStep` | `zones/zone/steps.rb:143-177`; `zones/zone/split_identity_repair.rb:289-322`; `windows/units/identity_step.rb:34-45` |
| By path and pre-image, after the Zone's own isolation | Spaces `ZoneReferenceStep` | `spaces/steps.rb:97-110` |
| Rebuild the plan from the isolated occurrence with the previewed mapping; compare the record and the sorted Face contents | Zones `MakeIndependentStep` | `zones/zone/steps.rb:228-232`, `:243-262` |
| Counts per id (or per kind and id) plus an ordinal in path order; refuse `target.changed` when counts or pre-images differ | Windows `ZoneCopyStep`, Spaces `IdentityStep` | `windows/units/zone_copy.rb:106-114`, `:133-151`; `spaces/identity/step.rb:26-30`, `:54-65` |

The ordinal binding is the real duplicate: the same algorithm in two files, keyed by `id` in Windows and
by `[kind, id]` in Spaces. It has two adopters, not three.

### Payload remapping and ambiguity

| Route | Mapping | Ambiguity | Source |
| --- | --- | --- | --- |
| Zones identity repair | Full old-to-new map for the Zone and every Face; typed `ReferencePlan` of new records | A Face id occurring twice in the Zone refuses `target.ambiguous` before planning | `zones/zone/repair.rb:51-53`, `:74-101`, `:199-211` |
| Zones split repair | `{old_id => id}` per piece, plan of every piece | Keeper chosen first, so none remains | `zones/zone/split_identity_repair.rb:104-116` |
| Windows `IdentityPlan` | Own id only, filtered by `mapping_kind` | n/a | `windows/units/identity_plan.rb:46-65` |
| Windows `ZoneCopy` | Zone's mapping plus every Unit id held once in the copy | An id two copied Units share is left out of the mapping, by stated design; a payload naming it keeps the old id | `windows/units/zone_copy.rb:68-76` |
| Spaces `IdentityPlan` | Parent mapping plus every renamed id held once in the copy | `check_copy_rules!` then `refuse_ambiguous!`: a payload naming an id several copied records share refuses `reference.invalid` | `spaces/identity/plan.rb:109-145` |

All five call `core/records/extension.rb:173-188` (`Records::Extension.copy_data`). Windows `ZoneCopy`
and Spaces build the shared mapping, the parent `ReferencePlan` and the per-row call almost line for line
(`windows/units/zone_copy.rb:71-95`, `spaces/identity/plan.rb:112-135`), and both deserialize the
transition's `references` the same way (`windows/units/zone_copy.rb:77-80`, `spaces/zone_copy.rb:32-36`).

### Pre-image capture and restore

| Step | Captures | On a failing write | Source |
| --- | --- | --- | --- |
| Zones `MakeIndependentStep` | `Captured(store, entity, record)` for the Zone, every Face record and stamp | Stops at the first exception | `zones/zone/steps.rb:192`, `:264-272`, `:276-295` |
| Windows `IdentityStep`, `ZoneCopyStep` | `[entity, record]` pairs | `Units.restore_all` attempts every one, raises once at the end | `windows/units/identity_step.rb:43-51`; `windows/units/zone_copy.rb:149-156`; `windows/units/records.rb:34-47` |
| Spaces `IdentityStep` | `Captured(store, entity, record, name)` | Stops at the first exception | `spaces/identity/step.rb:16`, `:66-86` |
| Spaces `ZoneReferenceStep` | The one entity, with the plan-time `before` | n/a | `spaces/steps.rb:108-114` |
| Zones `RepairIdentityStep`, `SplitIdentityRepair::Step` | Nothing; no `restore`, because neither runs as a host follow-up | n/a | `zones/zone/steps.rb:121-178`; `zones/zone/split_identity_repair.rb:261-323` |
| Zones `IsolateCopiedGroupStep` | Nothing; isolation stays | n/a | `zones/zone/steps.rb:97-116` |

`HostFollowUp` already asks every step to restore in reverse even after one fails
(`shell/host_follow_up.rb:83-93`); inside one step the policy differs.

### Copy watchers

Zones `CopyWatch::State` and Spaces `CopyWatch::State` share their structure: `feature_state`, three
host events, a `DeferredWork` keyed `:added`, the same "one original plus added occurrences" rule, a run
of `CopiedGroups.isolate` then `HostFollowUp.run` then `changed`, `remember` and `announce`, and the same
Undo warning (`zones/zone/copy_watch.rb:33-174` against `spaces/copy_watch.rb:30-176`; `copies` at
`zones/zone/copy_watch.rb:136-141` and `spaces/copy_watch.rb:126-131` share the same grouping logic, and
Zones then drops component paths). They differ in:

- a re-entrancy guard: Zones holds `@running` (`zones/zone/copy_watch.rb:47`, `:53`, `:59`, `:79`,
  `:159`, `:173`); Spaces has none;
- the queue merge, `queued + more` against `queued | more` (`zones/zone/copy_watch.rb:109`,
  `spaces/copy_watch.rb:59`);
- Undo bookkeeping (see Divergences);
- eligibility: Zones drops component paths silently (`zones/zone/copy_watch.rb:140`, `:143-153`); Spaces settles the Zones pass
  first, drops Spaces under a copied Zone and announces shared ones (`spaces/copy_watch.rb:133-160`,
  `:178-182`);
- every notice string.

A shared skeleton has two adopters. Windows would not adopt it: its repair rides the next action.

### Line counts (identity repair only)

| Feature | Ranges counted | Lines |
| --- | --- | --- |
| Zones (`zones/zone/`) | `repair.rb` lines 13-211 (199); `steps.rb` lines 94-305 (212); `split_identity_repair.rb` (326); `copy_watch.rb` (231); `copied_groups.rb` (42); `operations.rb` lines 43-104, 209-211, 321-331, 420-429 (86) | 1,096 |
| Windows (`windows/units/`) | `identity_plan.rb` (70); `identity_step.rb` (91); `zone_copy.rb` (160); `repairs.rb` lines 26-44 (19); `state.rb` code row and check (3) | 343 |
| Spaces (`spaces/`) | `identity/plan.rb` (149); `identity/step.rb` (134); `zone_copy.rb` (77); `copy_watch.rb` (210); `steps.rb` lines 76-115 (40); `authoring.rb` lines 212-229 (18); `scan/findings.rb` lines 81-94 (14); `export.rb` lines 281-290 (10) | 652 |
| Total | | about 2,090 |

Excluded: Zones Restore and orphans (`zones/zone/repair.rb:213-329`), Windows `HostWatch` and its export
issue line, the native menus
(`zones/zone/independence_menu.rb`, `split_identity_menu.rb`). Dedicated tests: about 2,850 lines in nine
files (`tests/zone_repair_test.rb` 940 including Restore, `zone_split_identity_repair_test.rb` 431,
`window_zone_copy_test.rb` 385, `spaces_identity_test.rb` 297, `zone_copy_watch_test.rb` 285,
`spaces_copy_watch_test.rb` 191, `spaces_zone_copy_test.rb` 169, `window_unit_identity_plan_test.rb` 98,
`window_unit_identity_step_test.rb` 61).

## Shared and per-feature mechanics

| Mechanic | Shared? | Adopters | Hides a rule if extracted? |
| --- | --- | --- | --- |
| Group occurrences by id, count above one | Yes, trivial | All three | No, but saves about one line each |
| Finding shape and its consumer | No | Each its own | Yes: action gating, repair menu, export blocking |
| Keeper rule | No (six rules) | Each its own | Yes |
| Id allocation and collision refusal | Yes (`identity.conflict` or `target.ambiguous` after `derived`/`allocator`) | All three | No, if the caller passes prefix and taken set |
| Extension remap with typed `ReferencePlan` | Yes | Windows `ZoneCopy`, Spaces near-identical; Zones and Windows `IdentityPlan` partly | No, if mapping and ambiguity policy are inputs; one policy must be chosen |
| Transition `references` deserialization | Yes | Windows, Spaces | No |
| Ordinal binding after Make Unique | Yes | Windows `ZoneCopyStep`, Spaces `IdentityStep` | No |
| Plan rebuild binding | No | Zones `MakeIndependentStep` | n/a |
| Captured-record restore | Yes | Zones, Windows, Spaces | No, if the failure policy is fixed once |
| Storage isolation (Make Unique plus nested Groups) | Partly | Zones skips nested Zones (`zones/zone/steps.rb:212-219`), Spaces does not (`spaces/identity/step.rb:118-121`) | Yes: which Groups count as owned is feature knowledge |
| Copy watcher skeleton | Yes | Zones, Spaces | Partly: eligibility, Undo policy and notices stay hooks |
| Domain rewrites (stamps, pair retirement, `number`, `floor_id`, `zone_id`) | No | Each its own | Yes |

## Sketch: a foundation `duplicate_identity` contract

Evidence, not an API. The shape the issue proposed, written out to see what it absorbs:

```ruby
module PhComposer
  module DuplicateIdentity
    # Finding: {code:, kind:, id:, paths:, repair: {name:, params:} | nil}
    def self.groups(occurrences, key:) end                      # => {id => [occurrence, ...]}
    # keeper: ->(group, scope) { occurrence | nil }
    def self.plan(inside:, held_outside:, keeper:, allocate:, prefix:, taken:) end  # => [Row(kind, ordinal, before, after)]
    def self.remap_payloads(rows, catalog:, engine:, parent: nil, label:, ambiguous: :refuse) end
    class OrdinalBinding                                         # counts per [kind, id] + ordinal
      def initialize(inside, rows) end
      def resolve(live_inside) end                               # raises target.changed
    end
    class CapturedRecords                                        # capture(store, entity); restore attempts all
      def capture(store, entity, name: nil) end
      def restore end
    end
  end
  class CopyWatchState                                           # session/: DeferredWork, Undo notice, run frame
    # hooks: ids_in(entity), occurrences, eligible(copies, added), params(copies), remember(value), announce(result)
  end
end
```

| Call site | Absorbed | Not absorbed |
| --- | --- | --- |
| Windows `IdentityPlan.build` | `groups`, `plan` with first-by-path keeper, `remap_payloads` | shared-storage and lock refusals, `only` |
| Windows `ZoneCopy.updates`, `copy_extensions`, `ZoneCopyStep` | `plan`, `remap_payloads`, `OrdinalBinding`, `CapturedRecords` | lock refusal, `Units.validate!` |
| Spaces `IdentityPlan`, `IdentityStep` | `plan` with one-keeper rule, `remap_payloads`, `OrdinalBinding`, `CapturedRecords` | target refusals, `number`, `floor_id`, `zone_id` remap, Space naming, isolation |
| Zones `Repair.identity_plan`, `MakeIndependentStep` | `remap_payloads`, `CapturedRecords` | path-derived ids, every Face renamed, stamps, pair retirement, plan-rebuild binding, independence refusals, nested-Zone isolation rule |
| Zones `SplitIdentityRepair` | `remap_payloads` at most | keeper proof and choice, reciprocal retirement, scope check, global counts |
| Zones and Spaces `CopyWatch` | `CopyWatchState` frame | eligibility, notices, Undo policy (must be chosen once) |
| Findings (all three) | `groups` | every consumer |

## Estimate

Estimates from the ranges above, not measured.

| Option | Feature lines removed | Foundation lines added | Net code | Tests |
| --- | --- | --- | --- | --- |
| Full contract (sketch above) | about 525 (watchers about 250, plan rows about 90, remap about 70, binding about 40, restore about 30, allocation about 20, findings and deserialization about 25) | about 350 | about minus 175 code | about plus 400 (new helper tests; feature suites kept) |
| Helpers only (packet below) | about 150 (remap about 70, binding about 40, restore about 30, deserialization about 8) | about 110 | about minus 40 code | about plus 150 (same basis) |

Either way the feature test suites keep their size: they assert keeper rules, refusals and notices,
which stay per feature. The test footprint therefore grows by the helper tests; neither option removes
tests.

## Risks

- **Hiding keeper rules.** Under the full contract, rules 4 to 6 become lambdas passed to `plan`, and rule
  2 an input filter. A
  newcomer reading Spaces would then find its keeper rule in a lambda and its meaning in core, which
  fails the architecture rubric's question "Does the abstraction reduce what a reader must know?"
  (`.agents/skills/ph-composer-architecture-review/SKILL.md`). Zones and split repair would still not fit, so the contract would have one full
  adopter pair and two partial ones.
- **Coupling.** Zones' plan is already the input to two contributors through
  `ph_composer.zones.occurrence_independent` (`zones/zone/operations.rb:64-70`). A shared `plan` would
  add a second coupling path: a change to the keeper machinery for Spaces would rerun the Windows and
  Zones copy suites. Today each owns its plan and the transition description is the only contract.
- **Policy convergence by accident.** Extracting `remap_payloads` and `CapturedRecords` forces one
  ambiguity policy and one restore policy. That is the main benefit and the main risk: the choice must be
  made on evidence (below), not by whichever file is moved first.
- **Watcher skeleton for two.** A base with six hooks for two watchers, with Windows explicitly not a
  user, is close to the "framework for a hypothetical contributor" the architecture rubric warns
  against. A third entity-record feature (Phase 4 equipment, or thermal bridges if they start
  re-issuing) changes that.

## Divergences (counterpart cases untested)

None is called a bug: no round trip has been run for the uncovered side. Each feature tests its own
policy; what is missing is the counterpart case in the other features.

1. **Ambiguous payload references.** Windows `ZoneCopy` leaves out of the shared mapping an id two
   copied Units share (`windows/units/zone_copy.rb:72-76`); each Unit's own id is still remapped
   (`:90`), so only a payload naming a *different* Unit's shared id keeps the old id. Spaces refuses that
   case `reference.invalid`, also excluding the record's own id (`spaces/identity/plan.rb:137-145`);
   Zones refuses earlier, on any duplicated Face id (`zones/zone/repair.rb:51-53`). The unmapped Windows
   reference is still resolved by `copy_data` (`core/records/extension.rb:180-185`), which refuses when
   it names no record or several (`core/records/reference_resolution.rb:16-23`), so the old id survives
   only when exactly one holder resolves, and then names that Unit, outside the copy. Covered: Spaces
   refusal (`tests/spaces_identity_test.rb:189-201`), Windows self-reference
   (`tests/window_zone_copy_test.rb:154`). Missing: a Windows payload naming a sibling's shared id with
   one and with two outside holders.
2. **Restore after a failing write.** Windows attempts every record (`windows/units/records.rb:34-47`);
   Zones and Spaces stop at the first exception (`zones/zone/steps.rb:265-272`,
   `spaces/identity/step.rb:77-86`), which could leave later captured records unwritten while
   `HostFollowUp` reports the step as failed to restore. Covered: Windows continues after a failed
   write (`tests/window_zone_copy_test.rb:188-205`). Missing: the same injected failure in Zones
   `MakeIndependentStep#restore` and Spaces `IdentityStep#restore` (`tests/spaces_identity_test.rb:243`
   covers a successful restore only).
3. **Undo bookkeeping.** After one warning Zones clears every remembered repair
   (`zones/zone/copy_watch.rb:61-66`); Spaces drops only copies no longer in the Model and keeps the
   rest, so a later Undo of an earlier batch still warns (`spaces/copy_watch.rb:72-76`, reason at
   `:73-74`). Covered: Spaces earlier-batch Undo (`tests/spaces_copy_watch_test.rb:136-148`), Zones
   single warning (`tests/zone_copy_watch_test.rb:63`). Missing: the Zones earlier-batch case.
4. **Windows `ZoneCopy` keeper.** Two Units inside a copied Zone sharing an id held nowhere outside both
   keep it (`windows/units/zone_copy.rb:46`); Spaces keeps one (`spaces/identity/plan.rb:84-90`). The
   duplicate stays, with its `window.copy_id_pending` export issue (`windows/export_assessment.rb:138`),
   until the next Windows action repairs it first-by-path (`windows/authoring.rb:5-15`). Missing: a
   Windows transition test for that case.

## Optional packet: shared copy-repair mechanics

Only if Ed wants the mechanics converged. Not a `duplicate_identity` contract; each helper takes the
mapping, the keeper set or the captured records as input.

| Stage | Scope | Acceptance |
| --- | --- | --- |
| 1 | The missing counterpart tests for divergences 1 to 4 (#468), beside the existing ones cited above; Ed picks the policy for each | One failing or passing test per divergence; decision recorded |
| 2 | `core/records/copy_remap.rb`: mapping from renamed rows, parent `ReferencePlan` from a transition description, per-row `copy_data`, the chosen ambiguity policy. Adopted by Windows `ZoneCopy` and Spaces `IdentityPlan`; Windows `IdentityPlan` if it fits without `mapping_kind` special-casing | Existing Windows and Spaces copy suites pass unchanged; one helper test per policy branch |
| 3 | `core/records/ordinal_binding.rb` (counts per key plus ordinal, `target.changed`). Adopted by Windows `ZoneCopyStep` and Spaces `IdentityStep` | Same suites pass; one helper test for count change and pre-image change |
| 4 | `core/records/captured_records.rb` with the chosen restore policy. Adopted by Zones `MakeIndependentStep`, Spaces `IdentityStep`, Windows identity steps (through `Units.restore_all` or replacing it) | Restore tests for a mid-way failure |
| Deferred | Copy watcher skeleton in `session/`, when a third watcher exists; fold divergence 3's decision into both watchers directly before then | n/a |

Rubric: `.agents/skills/ph-composer-architecture-review/SKILL.md` and
`.agents/skills/ph-composer-ruby-quality/SKILL.md`. Host gate required for stages 3 and 4: they change
binding after Make Unique and restore inside `HostFollowUp`, so native copy, injected fault and restore
(`host_bridge.py fault`), and Undo and Redo acceptance run on the merged head. This documentation PR
needs no host run.
