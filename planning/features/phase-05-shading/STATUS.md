# Shading: tracking ledger

DATE: 2026-11-19
STATUS: Scoped. PRD, decisions, contracts, plan, acceptance and stages P5s-01 to P5s-07 written 2026-11-19; every stage authorized by Ed 2026-11-19 ([Authorization](#authorization)). P5s-01 merged to main; SD01 blocked, owing two gestures. P5s-02 implemented on branch.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

The one place Phase 5 completeness is read from. Update it in the same change as any stage's state.

## State

Ed requested the feature on 2026-11-19 and answered four scope questions the same day (D5s-01 to
D5s-06). honeybee-ph and PHX were read at the repository's pins and one round trip was run
([research](research/honeybee-ph-and-phx-shading.md)). Ed answered D5s-07 to D5s-17 one at a time the same
day, taking the recommendation each time. Issue [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)
was filed at authorization.

## Authorization

Ed authorized every Shading stage on 2026-11-19: "Use the 'pr-loop' skill protocol for all reviews. Use a new branch for each phase of the work, and cleanup all branches and worktrees as you go. You are authorized to merge all PRs once the repo CI is green and all reviewer comments are addressed and resolved."

## Stages

| Stage | State | Acceptance | PR |
| --- | --- | --- | --- |
| P5s-01 Contracts and host facts | Merged to main ([#527](https://github.com/ph-composer/ph-composer-skp/pull/527), `f06f0efd`): CONTRACTS sections 4 and 7 answered, `tests/shading_mark_store_test.rb`; SD01 recorded `blocked` on `2a9c5e17` with eight of ten gestures measured ([evidence](evidence/sd01-host-facts.md)); Move-copy array and push-pull owed to a later hold | SD01 | [#527](https://github.com/ph-composer/ph-composer-skp/pull/527) |
| P5s-02 Shading mark and operations | Implemented on branch `feat/shading-p5s-02`: `features/shading/` (mark, reads, eligibility, targets, operations, selection, inventory), the envelope-exclusion flag in `core/records/entity_store.rb`, API 1.69; `tests/shading_operations_test.rb` (15 runs), `tests/shading_reads_test.rb` (3), `tests/shading_mark_store_test.rb` (4); `make ci` green. SD02 not yet run | SD02 | |
| P5s-03 Zones seam | Scoped | SD03 | |
| P5s-04 Native menu | Scoped | SD04 | |
| P5s-05 Colour-by | Scoped | SD05 | |
| P5s-06 Export | Scoped | SD06 | |
| P5s-07 Acceptance and handoff | Scoped | SD07 | |

## Waiting on Ed

Nothing. SD07 will ask Ed to open the WUFI XML and METr JSON.

## Not in this packet

A whole Zone as shading stays in the [zone-shading brief](../unscheduled/zone-shading.md), which
would reuse P5s-06's section.
