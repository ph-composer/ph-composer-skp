# Consistent entity user data: status

DATE: 2026-11-14
STATUS: In progress
AUTHOR: Ed May, BLDGTYP, with Codex
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

## State

Ed requested consistent `user_data` support across all entities and clear documentation/context
on 2026-11-14. [PRD.md](PRD.md) records the confirmed scope. On 2026-11-14 Ed asked for the packet
to be implemented through the pr-loop on the existing `codex/entity-user-data` branch, with merge
delegated on green CI once every review comment is answered. The packet had no stage plan, so
[PLAN.md](PLAN.md) and [phases/](phases) now hold the source inventory, the lifecycle policy,
decisions D-UD-1 to D-UD-8 with recommendations, and stages EUD-01 to EUD-10. No code has changed.

Loop overrides: `--single-pr` on the named branch (each stage a signed commit, one Codex review
over the combined diff) and `--merge`.

## Next step

EUD-04, then the stages in order.

| Stage | Status | Evidence |
| --- | --- | --- |
| EUD-01 | Implemented on branch | `ph_composer.records.update_metadata` (API 1.52); catalog `*.update`, installs.save update rows and `attached_zone.save` with `id` no longer take `user_data`. `tests/record_metadata_test.rb` 10 runs, 219 assertions, also on Ruby 2.7.2; `make ci` exit 0: Ruby suite 2,852 runs, 35,188 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Sonnet adversarial read: 10 findings, 8 fixed, 2 left as follow-ups (below) |
| EUD-02 | Implemented on branch | `Records::Part` and `RecordKind` `parts:` (validated at registration, part ids unique per parent, part maps JSON-checked, listed by `describe`); optional `user_data` on Assembly Layers and Layer-Segments at schema version 1; `records.update_metadata` takes `part_ids`, and entries for one record and its parts stage as one write (API 1.53). New tests in `record_metadata_test.rb` (14 runs, 312 assertions), `assembly_records_operations_test.rb` (23 runs, 397 assertions) and `registry_test.rb` (41 runs, 290 assertions), also on Ruby 2.7.2; `make ci` exit 0: Ruby suite 2,860 runs, 35,346 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Assemblies panel JS checked: it clones stored values and builds no parts, unchanged. Sonnet adversarial read: 8 findings; a stale descriptor test, a vacuous copy-independence check, an untested registration branch, part-id uniqueness (now enforced in core), an unused projected read, the contributor doc and an error message fixed; the export guide now says part maps are not exported yet (EUD-07 maps them); 3 minor notes accepted as designed |
| EUD-03 | Implemented on branch | Optional `user_data` on Window Elements, the Window Type's `elements[]` part, written by `records.update_metadata` with `part_ids` `[element id]` and read by `types.elements.list` (API 1.54); the Type's own element-id uniqueness check removed (core part validation refuses repeats). `types.grid.merge` keeps the top-left map and returns `removed_user_data` (at most 50 entries, each with at most 50 keys, through the new `Records::Metadata.discarded_keys`) and `removed_user_data_total`. New tests in `record_metadata_test.rb` (15 runs, 329 assertions), `window_records_operations_test.rb` (18 runs, 975 assertions: kind change, merge with report and Undo, split, flip, insert, remove, installs save, Duplicate, whole-array update, product replacement, report bounds, repeated ids) and `window_unit_actions_test.rb` (37 runs, 537 assertions: `new_flipped_type`), also on Ruby 2.7.2; `make ci` exit 0: Ruby suite 2,864 runs, 35,467 assertions, 0 failures; JS 876 pass, 0 fail; Python 264 passed; RuboCop 742 files, no offenses; RBZ verified. Windows panel JS checked: it sends grid gestures, installs by element id and named values only, and rebuilds no elements; unchanged. Sonnet adversarial read: 8 findings; the unbounded report list, the band-removal note in the guide, a flip test that could not see a swap, report bound and repeated-id tests, and the export sentence fixed; a panel notice for removed maps, oversized single `elements.list` rows (as EUD-02's `segments.list`) and recomputing the merge selection for the report accepted as designed |
| EUD-04 | Scoped | |
| EUD-05 | Scoped | |
| EUD-06 | Scoped | |
| EUD-07 | Scoped | |
| EUD-08 | Scoped | |
| EUD-09 | Scoped | |
| EUD-10 | Scoped | |

## Blockers and open decisions

None. Ed answered D-UD-1 to D-UD-8 as recommended on 2026-11-14.

Follow-ups from EUD-01, for EUD-08: `Engine#propose_update` still takes `user_data:` for contributor
kinds, and the foundation example's `update_parts` (`tools/examples/foundation/`) still writes
`user_data` through it; decide whether the example moves to `records.update_metadata`. Invalid JSON
in params reaches no handler over the public API: the dispatcher refuses it as `request.malformed`;
the engine's own `params.invalid` answers only a Ruby caller staging directly.

## Verification

Baseline: clean `main` at `186734ce`. The preceding investigation in this chat passed 276 focused
Ruby tests with 2,665 assertions and 52 Python tests. It covered existing metadata edits, copy
paths, export and library behavior, not universal entity support. No new native host run was made.

The packet's UD-01 through UD-10 acceptance criteria are pending. Documentation-only checks for
this write-up passed: local link/heading validation across all six changed documents and whitespace
checks. The PRD was reviewed against the current owning contracts and known source gaps. The
implementation gates have not run for a new code change.

## Ledger

| Date | Event |
| --- | --- |
| 2026-11-14 | Reviewed the existing affordance and identified public API, nested-entity and interchange boundaries at `186734ce`. |
| 2026-11-14 | Ed confirmed universal entity consistency and documentation as the feature goals; authorized the planning write-up. Created the scoped PRD and linked it from the planning indexes. |
| 2026-11-14 | Created tracking issue [#507](https://github.com/ph-composer/ph-composer-skp/issues/507). Added a current-coverage qualification to the contributor contract; runtime code is unchanged. |
| 2026-11-14 | Ed asked for implementation through the pr-loop on `codex/entity-user-data`, merge on green delegated. Wrote PLAN.md and ten stage documents from a source inventory at `68919a8c`; decisions D-UD-1 to D-UD-8 put to Ed. |
| 2026-11-14 | Ed answered D-UD-1 to D-UD-8 "All as recommended"; implementation authorized. |
| 2026-11-14 | EUD-01 implemented on `codex/entity-user-data`: the core catalog metadata action, `RecordKind` `owner_writes_metadata` for Zone options, and `user_data` removed from catalog updates. |
| 2026-11-14 | EUD-02 implemented on `codex/entity-user-data`: `RecordKind` part declarations, Assembly Layer and Layer-Segment maps, and part addressing in `records.update_metadata`. |
| 2026-11-14 | EUD-03 implemented on `codex/entity-user-data`: Window Element maps as the Window Type's `elements[]` part, and the merge report of removed maps. |
