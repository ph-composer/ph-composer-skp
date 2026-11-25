# P4-14c evidence: Ducting groups and the duct assignment

DATE: 2026-11-25
Register row: [M14c](../ACCEPTANCE.md). Stage: [P4-14c](../phases/p4-14c-ducting-groups-and-assignment.md), under the
parent index [P4-14](../phases/p4-14-erv-ducting.md).
Base: cut from `feat/phase-07-mechanical-p4-14b` at `9e8ad1ae`, moved onto `main` at `109eb0ec` after #582 merged
(identical tree, `git diff --stat 9e8ad1ae origin/main` empty).

Offline evidence only. No SketchUp process was started. The host case `M14c` (in
`planning/native-acceptance/cases.json`: `groups.create` opening for the Line tool, run after M13b's H1 and H2;
assign, quantity and clear over a native selection, one Undo step each; a pasted group keeping ERV-1 and refusing
until made unique; the Ventilator delete's retarget beside the Zone it serves) is owed to the MS3 sitting (D4-31).
M14c stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Group record and target | `features/ducting/group/schema.rb`, `reference_target.rb`, `line_group.rb` | `ph_composer.ducting.group` on a Group, `dcg_`, `ventilator_id` (string or null, a `one` reference to the Ventilator), claims its Group; target `{group_id, group_path}` over `LineGroups::GroupTarget` with ducting's `LineGroups::Spec` |
| 2. Group operations | `group/operations.rb`, `declarations/groups.rb` | `groups.create` (an empty Group at the root through `LineGroups::CreateStep`, opened), `groups.link`, `groups.unlink` (guarded, at most 250, `ducting.group_in_zone` from `zones.containment`), `groups.all` with `duct_count`, the bounded `groups.list`, and the retargeter `ph_composer.ducting.groups.retarget_ventilator` |
| 3. Duct record and target | `assignment/schema.rb`, `reference_target.rb` | `ph_composer.ducting` on an Edge, `dce_`, `duct_type_id` (string or null), `direction` (`outdoor_air`, `exhaust_air`), `quantity` (integer >= 1); `GESTURE_EDGE_LIMIT` 250; target over `LineGroups::EdgeTarget`, refusing `ducting.outside_group` |
| 4. Assign and clear | `assignment/operations.rb`, `declarations/ducts.rb` | Every target resolved through one child index and the groups' Zone containment read once; one `LineGroups::EdgeWriteStep`; a fresh `dce_` and quantity 1 on a first assignment |
| 5. Selection | `assignment/selection.rb` | `ducts.selection` (bounded), `ducts.selection_all` and the `ducts.selected` snapshot section, over `LineGroups::Selection` |
| 6. Delete in use | `assignment/operations.rb` (`delete_type`, `replace_type`), `declarations/duct_types.rb`; `mechanical/catalog_operations.rb`, `declarations/ventilators.rb`, `declarations/hot_water.rb`, `hot_water/operations.rb` | See "Inferred beyond the stage doc" |
| 7. Declarations | `codes.rb`, `install.rb`, `shell/api.rb` | Codes `ducting.outside_group`, `ducting.group_in_zone`, `ducting.group_nested`; API 1.104 with one `CHANGES` row naming the Ventilator delete's new routing; `make fixtures` |
| 8. Documents | `context/CONTRACTS.md` ("ERV ducting", the storage table, the Ventilator delete), `context/TECH_STACK.md` ("Edge-owned assignments"), `context/EXTENSIBILITY.md` ("Line groups"), `context/AGENT_INTERFACE.md`, `docs/AGENT_GUIDE.md` and the shipped guide, `docs/USER_DATA.md`, packet CONTRACTS | |
| Host case | `tools/examples/authoring/ducting_assignment_walkthrough.rb`, its README section, `tests/ducting_assignment_walkthrough_test.rb`, `cases.json` `M14c` | |

## Inferred beyond the stage doc

- **Assign's params.** The doc says `ducts.assign` "requires" a direction, and that a reassign keeps what it is not
  given (its test reassigns with only a quantity). Both hold because `duct_type_id`, `direction` and `quantity` are
  each optional in the schema and the operation refuses `params.invalid` when an Edge with no assignment lacks a type
  or a direction, in a mixed batch too; such an Edge takes quantity 1 unless given one. An assign that changes
  nothing writes nothing. P4-14f's bar always sends all three.
- **The Ventilator delete's seam.** `ventilators.delete` now calls `request.retarget_references` when given an id or
  null and joins that plan to Serves', naming no feature, as the Hot Water System delete does. The join moved into
  one generic helper, `CatalogOperations.with_retargeted(request, plan, kind, from:, to:)`, which both deletes call;
  `HotWater::Operations.with_retargeted` is gone, and the hot water tests pass unchanged in behavior. Without the
  call, the probe test's delete with a replacement refused (`Expected: "committed"`, run against the declaration
  with the change stashed).
- **No selection client.** Piping's `Assignment::Selection::Client` has no shipped caller (its assign bar calls the
  API from the panel), so ducting has none; P4-14f's bar reads `ducts.selected`.
- **No `ducting.hidden` code yet.** The spec carries the three codes this stage raises; `LineGroups::Locate` reads
  `:hidden`, and P4-14d, which adds `runs.locate`, adds the code to the spec.
- **The probe feature** the Hot Water System delete test used moved to `tests/support/referrer_probe.rb`,
  parameterized by kind and key, and the Ventilator test uses it.
- **For Ed: a consolidation candidate.** `group/operations.rb` and `assignment/operations.rb` (about 18 KB) and the
  two declaration files (about 18 KB) follow piping's line for line apart from names, the link key, the duct values
  and the count key. Moving their spec-generic parts (link, retarget, clear, the type rewrite, resolve, the plan)
  into `line_groups/` would save roughly 10 KB installed across both features but changes piping again, which
  P4-14b's plan ruled out and this stage's ordinary review lane does not cover.

## Tests

`tests/ducting_group_test.rb` (8), `tests/ducting_assignment_test.rb` (11), `tests/ducting_assignment_walkthrough_test.rb`
(1), and one in `tests/mechanical_ventilators_test.rb` (a probe feature's record retargeted by a Ventilator delete
with an id and with null, one Undo step). The group test serves Zone A from ERV-1 and proves the replacement lands on
both the group and the Zone's slot in one Undo step. `tests/entity_references_test.rb` and
`tests/agent_access_discovery_test.rb` count the two new reference targets.

## Size

`uv run tools/runtime/vendor.py --check`: "Runtime verified: 223 assets, 8 wheels, 23168678 bytes" (unchanged; this
stage ships no wheel). Installed RBZ before the change, `make rbz` on `9e8ad1ae`: 27,786,128 bytes. Figures after it
are in "Gate".

## Stale cases

`uv run tools/hostkit/acceptance_ledger.py status` with `--changed` for each of the 48 changed and new paths of the
working tree before the first commit: 50 of 161 cases name one. By state: `needs_recheck` 21 (A04, A09, R01 to R06,
E15, E17, the six UXR cases, LH1, AW02, AW10, EUD09, EUD09X), every one already `needs_recheck` on the base with no
change named, so this stage stales no current Pass; `historical_affected` 4 (A03, A07, A12, A16); `not_run` 25 (E01
to E05, E07 to E13, M02, M03, M05 to M11, M13a, M13b, M14a, M14c), owed to their sittings as before. The unmapped
changes are the 16 `context/`, `docs/`, `planning/` and `cases.json` paths. Nothing was rerun.

## Gate

- `make ci` on Ruby 3.2.2 on the tree of `449482f0`: "Ruby suite, 10 processes: 3582 runs, 50481 assertions, 0
  failures, 0 errors, 2 skips"; JS "pass 1226", "fail 0"; Python "460 passed, 17 skipped" (the worktree's `phx`
  group unsynced); hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 851 files, 9055296 bytes, 27837718
  bytes installed".
- Installed size: 27,837,718 bytes, 51,590 over the base's 27,786,128 against the 45 KB estimate (12 percent over,
  under the 25 percent stop line). Final-head figures follow below.

## Review

Sonnet adversarial read before the gate: no blocking defect, 12 findings. Fixed: tests for `groups.list` paging, a
shared group stranding the Ventilator delete, a group with no id refusing it by path, assign through a pasted group's
shared storage, unreadable Edge and group records, a clear refusing for a referenced duct with a malformed map and for
one Edge over the limit, the mixed clear's code, the second Edge's Undo and the Ventilator's removal in the probe
test; CONTRACTS now says a Duct Type delete rewrites ducts and a Ventilator delete groups. Declined: `params.invalid`
in the `refuses` lists (it is in every action's common set, `shell/refusals.rb`); the repeated replacement check in
`delete_type` (piping's shape); a `minProperties` on assign (a no-op assign writes nothing); the missing `:hidden`
code (P4-14d's, above).

## Codex review

- Cycle 1, gpt-6.2-sol on `449482f0`: 1 P1, 4 P2, 1 P3. Fixed in the next commit: `ducts.clear` checks every removed
  `dce_` id against its referrers, a record of another schema version or a batch removing every copy of an id
  included, and counts as surviving only Edges the command leaves; a stale `expected_values` on `duct_types.delete`
  refuses `target.changed` before a stranded duct can refuse `reference.in_use`; a group row's `write_refusal` names
  its placement (nested, then in a Zone, then the path's own), as a write meets them; `groups.create` declares
  `record.unreadable`; `copied` is described as a shared id, with writability in `write_refusal`, in the schema and
  the guide. Declined: one engine reference check per cleared id (the engine has no batch removal check; piping's and
  thermal bridges' clears share it, a core follow-up, as P4-13b recorded). Piping's clear, Pipe Type delete and group
  rows have the same three gaps; they are a follow-up for Ed, not changed here.
