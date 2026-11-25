# P4-14c2 evidence: line-group operations consolidated

DATE: 2026-11-25
Issue: #584 (part of #562). Section: [P4-14](../phases/p4-14-erv-ducting.md), "P4-14c2: line-group operations
consolidated". Register rows: [M13b and M14c](../ACCEPTANCE.md), whose host cases run the moved code in MS3.
Base: cut from `origin/feat/phase-07-mechanical-p4-14c` at `f2eaeccc` (#583), moved onto `main` at `13bb8f88` after #583 merged (identical tree, `git diff --stat f2eaeccc origin/main` empty).

Offline evidence only. No SketchUp process was started. No host case is added: M13b and M14c already depend on
`src/ph_composer/line_groups/*` and the piping and ducting folders, so they run on this code in the MS3 sitting.

## What moved

| Part | From | To |
| --- | --- | --- |
| create, link and unlink, retarget, the containment read, check_expected, the occurrence rows | `features/piping/group/operations.rb`, `features/ducting/group/operations.rb` (both deleted) | `line_groups/group_operations.rb`, `LineGroups::GroupOperations` |
| clear, the reference check on removal, delete_type and replace_type, resolve, update, propose, plan | `features/piping/assignment/operations.rb`, `features/ducting/assignment/operations.rb` | `line_groups/edge_operations.rb`, `LineGroups::EdgeOperations` |
| The edge record's validation, the new group record, group identity and values | each feature's `group/schema.rb` and `assignment/schema.rb` | `LineGroups::Spec#validate_edge!`, `new_group`, `group_identity`, `group_values` |

`LineGroups::Spec` gains `link_kind`, `link_label`, `type_kind`, `type_key`, `type_label` and `containment`; piping
passes the Hot Water System kind, "Hot Water System", the Pipe Type kind, `pipe_type_id`, its label and
`ph_composer.zones.containment`, and ducting the Ventilator's. Each feature keeps its own `assign` (pipe roles and
their values; duct direction, quantity and the first-assignment rule) on the shared resolve, update and step, its type
operations, which `delete_type` takes as `types:`, and its declarations. Orphans the move made were removed: piping's
`Group.validate!`, `Group.identity`, `Group.scannable`, `Group::Target.each_group`, `write_refusal` and
`nested_refusal`, `Assignment.validate!`, `check_limit!` and `pipes_in`; ducting's `Group.identity`,
`Assignment.validate!`, `check_limit!` and `ducts_in`. What the tests call stays (`Group.values`, `Group.new_record`,
now over the spec, `Assignment.identity`, `Assignment.values`, `gesture_edge_limit=`, piping's selection client).
`tests/line_groups_test.rb`'s feature-name check passes over the two new files.

## The four piping gaps, test first

Each test was written first and run against the base tree (log `p4-14c2-red.log`, scratch): "9 runs, 59 assertions,
2 failures" for `tests/piping_group_test.rb` and "12 runs, 92 assertions, 2 failures" for
`tests/piping_assignment_test.rb`, each failure the gap itself.

| Gap | Test | Base result | After |
| --- | --- | --- | --- |
| The clear's reference check | `test_clear_checks_every_removed_id_against_its_referrers` | `["completed", "ok"]` where `["refused", "reference.in_use"]` was expected | pass |
| A stale Pipe Type delete's refusal | `test_a_stale_pipe_type_delete_refuses_target_changed_before_a_stranded_pipe` | `[nil, "refused", "reference.in_use"]` where `[["name"], "refused", "target.changed"]` was expected | pass |
| Group rows' placement refusal | `test_a_group_row_shows_the_placement_refusal_a_write_meets` | `Expected: "piping.group_in_zone"`, `Actual: nil` | pass |
| `groups.create` on a Model not shown | `test_create_refuses_session_inactive_for_a_model_sketchup_is_not_showing` | `["completed", "ok"]` where `["refused", "session.inactive"]` was expected | pass |

After the move, each piping, ducting, line-group and walkthrough test file passes on Ruby 3.2.2 (`piping_group_test`
"9 runs, 64 assertions, 0 failures"; `piping_assignment_test` "12 runs, 94 assertions, 0 failures"; the ducting,
line-group, Pipe and Duct Type and Ventilator files unchanged in count). No existing piping or ducting test changed;
`tests/api_test.rb` reads the new minor.

## Contract changes

- API 1.105, one `CHANGES` row naming the four. `make fixtures` changes `docs/API_REFERENCE.md` in three lines only:
  `piping.groups.create`'s precondition ("SketchUp shows this Model.") and refusals, and the change row.
- **Departure, for the record:** piping's `groups.create` also declares `record.unreadable`, which it already raised
  for an unreadable Hot Water System (ducting declared it in P4-14c). It is a documentation correction, not a behavior
  change.
- **Inherent in gap 2:** both deletes now read the type before the replacement check, so a missing type id refuses
  `target.not_found` for the id even when `replacement_id` is the same id; piping used to answer `params.invalid`
  first. Ducting already did this.
- `docs/AGENT_GUIDE.md` (and the shipped guide), `context/AGENT_INTERFACE.md`, `context/CONTRACTS.md` ("Hot water
  piping", "ERV ducting") and `context/EXTENSIBILITY.md` ("Line groups") say what moved and what piping now does.
- The shared selection read's single `write_refusal` and its order are untouched (left for Ed).

## Size

`uv run tools/runtime/vendor.py --check`: "Runtime verified: 223 assets, 8 wheels, 23168678 bytes" (unchanged).
`make rbz` on Ruby 3.2.2: base `f2eaeccc` "RBZ verified: 851 files, 9055729 bytes, 27839296 bytes installed"; after
the move, "RBZ verified: 851 files, 9051692 bytes, 27824636 bytes installed": 14,660 bytes saved against the 10 KB
aim. Final-head figures are in "Gate".

## Stale cases

`uv run tools/hostkit/acceptance_ledger.py status` with `--changed` for each of the 37 changed, added and deleted
paths before the first commit: 44 of 161 cases name one. `needs_recheck` 21 (A04, A09, R01 to R06, E15, E17, the six
UXR cases, LH1, AW02, AW10, EUD09, EUD09X), each already `needs_recheck` on the base, so no current Pass goes stale;
`historical_affected` 4 (A03, A07, A12, A16); `not_run` 19 (E01 to E05, E07 to E13, M13a to M13e, M14a, M14c), owed to
their sittings as before. Unmapped: the four `context/` and `docs/AGENT_GUIDE.md` paths. Nothing was rerun.

## Review

Sonnet adversarial read before the gate: message strings, argument order, removed callers, Ruby 2.7 syntax and the
feature-name rule verified; the four tests confirmed failing on an extracted base tree. Four findings: the delete's
new `target.not_found`-first order (recorded above, inherent in gap 2); the test-only `Group.values` and
`Group.new_record` (declined: the tests stay byte-identical, and `new_record` now delegates to the spec); the
`STRANDED_DETAIL` repeated in both modules (declined: `edge_operations.rb` loads before `group_operations.rb`, so a
reference would fail at load); two over-long documentation lines (fixed).

## Gate

- `make ci` on Ruby 3.2.2 on the first commit's tree: "Ruby suite, 10 processes: 3588 runs, 50526 assertions, 0
  failures, 0 errors, 2 skips"; JS "pass 1226", "fail 0"; Python "460 passed, 17 skipped" (the worktree's `phx` group
  unsynced then); hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 851 files, 9051922 bytes, 27825369
  bytes installed". On Ruby 2.7.2, the same tree: "Ruby suite, 10 processes: 3588 runs, 50526 assertions, 0 failures,
  0 errors, 2 skips"; JS "pass 1226"; Python "486 passed, 1 skipped"; hostkit "48 runs"; the same RBZ figures.
- Installed size: 27,825,369 bytes, 13,927 under the base's 27,839,296 (the guide and the reference grew by 733 bytes
  of documentation). 174,631 bytes are left under the 28,000,000 ceiling, 59,943 after P4-14d to P4-14f's estimates
  (114,688), above the 40 KB line.
- PHX: `uv run --group phx pytest tests/python`: "486 passed, 1 skipped" (`test_map_borders.py`,
  `PH_COMPOSER_MAP_DATA` unset); `-k phx_round_trip`: "26 passed, 461 deselected", none skipped (nothing here exports).
- Browser checks and the final head's figures: below, after review.
- Design System: not needed for this PR (no kit CSS, shared kit part or unit quantity changes). The re-sync owed
  from P4-13e is the conductor's to run from `main`.
