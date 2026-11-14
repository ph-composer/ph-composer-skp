# Consistent entity user data: status

DATE: 2026-11-14
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Codex
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

## State

Ed requested consistent `user_data` support across all entities and clear documentation/context
on 2026-11-14. [PRD.md](PRD.md) records the confirmed scope, observed gaps, documentation
deliverables and acceptance criteria. This is an unscheduled planning packet. Implementation
is not authorized; no implementation, merge, feature acceptance or release is claimed.

## Next step

When detailed planning is requested, complete the entity inventory and resolve the PRD's storage,
copy/merge and interchange decisions against current source. Then define bounded implementation
stages and the required native cases. Obtain implementation authorization before changing code.

## Blockers and open decisions

No blocker to the feature write-up. Model/logical-entity ownership, nested schema compatibility,
split/merge behavior, additional HBJSON mappings and library-format policy remain design work.
No current API gap or authored nested object is silently deferred out of the requested scope.

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
