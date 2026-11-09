# Windows draw-then-convert: delivery plan

DATE: 2026-11-09
STATUS: In progress. Decisions W7-1 to W7-10 are recorded; stages run through the ledger in STATUS.md.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/363

The behaviour contract is [PRD.md](PRD.md); this plan is the order of work. Stage ledger in [STATUS.md](STATUS.md).

## How each stage runs

One stage, one branch, one PR, through the `pr-loop` protocol, reviewer `gpt-6.1-sol`, with a real-host check on
the head that merges. Code changes start only on Ed's go. Build-then-Place stays unchanged.

## Stages

| Stage | Scope | Depends on | Host check |
| --- | --- | --- | --- |
| S21-1 | Rectangle reading and grouping, pure: groups, bands and spans (W7-3, W7-5), the refusals including `window.convert_on_boundary` (W7-2); the `convert_review` query with host resolution and same-size Type matching (W7-6) | none | Offline; a host read of `convert_review` |
| S21-2 | Spike H1 and H3, recorded in `context/SKETCHUP_HOST_BEHAVIOR.md`; then `ConvertStep` and the `convert` action: new Types, rectangles erased, host healed, Units placed, one Undo step (W7-9) | S21-1 | Host: spike rows, one rectangle on a wall, Undo and Redo |
| S21-3 | Menu item and panel review: groups, left-out rows, Type choice, name (W7-8), Copy from (W7-7) | S21-2 | Host: the walkthrough's cases from the context menu |

## Consequence of the decisions

W7-2 always refuses a rectangle touching its host Face's edge, so spike H2 is dropped. A door on the floor line is
drawn inset and moved after Convert.
