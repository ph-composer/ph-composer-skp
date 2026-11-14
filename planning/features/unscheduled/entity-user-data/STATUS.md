# Consistent entity user data: status

DATE: 2026-11-14
STATUS: Scoped
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

Ed answers D-UD-1 to D-UD-8 in [PLAN.md](PLAN.md#decisions-for-ed). Then EUD-01 starts.

| Stage | Status | Evidence |
| --- | --- | --- |
| EUD-01 to EUD-10 | Scoped | |

## Blockers and open decisions

D-UD-1 to D-UD-8 await Ed's answers: Model root and Space Floor storage, nested-part writes,
nested schema version, merge and split, new HBJSON mappings, library interchange and create-time
maps. Any answer that excludes an authored entity or narrows the affordance is Ed's call.

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
