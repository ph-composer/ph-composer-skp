# Usability walkthrough fixes: delivery plan

DATE: 2026-11-07
STATUS: In progress. Stage ledger in [STATUS.md](STATUS.md).
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/373 (tracking)

Delivers the issues from the 2026-11 usability walkthrough ([SYNTHESIS.md](SYNTHESIS.md)), one
issue per stage, through the `pr-loop` protocol. The issue is the stage's scope and its
acceptance criteria are the stage's acceptance rows; the synthesis holds the decisions (D1 to D7,
accepted 2026-11-07) and the raw evidence is in [LOG.md](LOG.md) and `evidence/`.

## Standing authorization (Ed, 2026-11-07)

> Lets go ahead and /implement-loop https://github.com/ph-composer/ph-composer-skp/issues/373
> using the 'pr-loop' skill's protocol for review. You are approved to merge any PRs once CI is
> green and the reviewer's comments (if any) are resolved. Approved for any computer-use you need
> as well

So the loop runs with `--merge`. Reviewer: `gpt-6.1-sol` by default; `gpt-6-astra` for stages
marked "strong review" (export data contracts, serialization, agent security).

## Rules for every stage

- One stage, one branch, one PR, one posted Codex review, one fix cycle (two at most), merge on
  green CI. Stages now run one at a time, as background subagents of one conductor session.
- Read `AGENTS.md` first; load `ph-composer-architecture-review` for code changes,
  `ph-composer-ruby-quality` for substantive Ruby, `ph-composer-ui-polish` for any HtmlDialog
  screen. Bugs: write the reproducing test first.
- Gate: `make ci && git commit -s ... && git push`. Never `--no-verify`.
- A stage that changes SketchUp-visible behaviour gets a real-host check through the development
  bridge and native controls (computer use is approved) on the head that goes to merge; record
  it in the PR. This loop is not a release claim.
- The issue body says "Part of #373"; the PR says `Closes #<stage issue>` and `Part of #373`.
- Ledger flips ride in the next stage's PR.

## Document stages

WT-06 and WT-07 deliver a design packet, not code. Each ends with the packet merged and a note to
Ed; implementation of that feature waits for Ed's go on the packet (CLAUDE.md "planning before
building"). Their implementation stages are added to this plan when Ed approves.

## Cross-repo stage

WT-03 is in PH-Tools/PHX, a published package: keep its public interfaces stable, and follow
pr-loop's release rule (no direct push to PHX `main` until the merge's release run finishes;
confirm the version reached PyPI).

## Stages

Order follows the synthesis; groups run in order. Stages touching the same owner run one after
the other.

| Stage | Issue | Item | Kind | Notes |
| --- | --- | --- | --- | --- |
| WT-01 | #358 | S-16 Material placeholders exported as data | bug | strong review (export data) |
| WT-02 | #359 | S-17 Interior Surface pairs and honeybee validity | bug | strong review; D2; round-trip honeybee `check_all` |
| WT-03 | PH-Tools/PHX#169 | S-29 No-People default occupancy pattern | bug, PHX | published package; release rule |
| WT-04 | #354 | S-12 Delete Space fails while its Zone is open | bug | host check |
| WT-05 | #353 | S-11 Create Space on a solid double-counts iCFA | bug | host check |
| WT-06 | #352 | S-10 Spaces creation and visibility | design packet | D1; ends at Ed's review |
| WT-07 | #363 | S-21 Draw-then-convert Window Types | design packet | ends at Ed's review |
| WT-08 | #370 | S-28 Export report omits preflight warnings | bug | |
| WT-09 | #344 | S-02 Agent connection for GUI clients | enhancement | D5; strong review (security) |
| WT-10 | #346 | S-04 Export approval for agents | bug | strong review (security) |
| WT-11 | #345 | S-03 Bound token after Save As | bug | |
| WT-12 | #343 | S-01 Agent Access in the panel | enhancement | D7; UI polish skill |
| WT-13 | #347 | S-05 Agent schema and diagnostics gaps | bug | |
| WT-14 | #348 | S-06 Outcomes and refusals in SketchUp | enhancement | host check |
| WT-15 | #349 | S-07 Context menu restructure | enhancement | host check |
| WT-16 | #350 | S-08 Overlay follows SketchUp view state | bug | host check |
| WT-17 | #351 | S-09 Thermal Bridges Colour-by | enhancement | |
| WT-18 | #364 | S-22 Place tool snapping, unhosted guard | enhancement | D6; host check |
| WT-19 | #366 | S-24 Window Type builder bugs | bug | |
| WT-20 | #367 | S-25 Notices, popovers, chips, tooltips | bug | UI polish skill |
| WT-21 | #372 | S-31 Assemblies replace-and-delete and two bugs | bug | |
| WT-22 | #371 | S-30 Model default install psi | enhancement | D3 |
| WT-23 | #369 | S-27 Thermal bridge de-duplication | enhancement | D4; strong review (export data) |
| WT-24 | #355 | S-13 Spaces table | enhancement | |
| WT-25 | #356 | S-14 Zones view polish | enhancement | |
| WT-26 | #357 | S-15 Material entry | enhancement | |
| WT-27 | #360 | S-18 Assembly builder polish | enhancement | |
| WT-28 | #361 | S-19 Library sidebar and tables | enhancement | |
| WT-29 | #362 | S-20 Frames Brand and auto-name | enhancement | |
| WT-30 | #365 | S-23 Window Unit names and selection | enhancement | host check |
| WT-31 | #368 | S-26 Psi-Install editor polish | enhancement | |

When every stage has merged, archive this folder per `planning-conventions` and close #373.
