# Spaces UI/UX refinement 2026-11: delivery plan

DATE: 2026-11-09
STATUS: In progress. Stage ledger in [STATUS.md](STATUS.md).
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/426 (tracking)

Delivers the issues from the 2026-11-09 Spaces walkthrough with Ed through the `pr-loop` protocol.
Each issue body is its stage's scope, and its acceptance criteria are the stage's acceptance rows.
Behavior in those issues stays proposed until the ledger records it as accepted.

## Standing authorization (Ed, 2026-11-09)

> https://github.com/ph-composer/ph-composer-skp/issues/426 in whatever order you think best. New
> branch for each Issue group. Use the 'pr-loop' skill to manage the loop and review protocol. You
> are authorized to merge once CI is green and all review comments (if any) are properly addressed.
> You are authorized for any and all computer-use that you need in order to complete this work.

So the loop runs with `--merge`. Reviewer: `gpt-6.1-sol` unless the stage says strong review, then
`gpt-6-astra`.

## Rules for every stage

- One stage, one branch from `main`, one PR, one posted Codex review, one fix cycle (two at most),
  merge on green CI. Stages run one at a time, as background subagents of one conductor session.
  They share the checkout and the SketchUp host.
- Read `AGENTS.md` first. Load `ph-composer-architecture-review` for code changes,
  `ph-composer-ruby-quality` for substantive Ruby, `ph-composer-ui-polish` for any HtmlDialog screen.
- Gate: `make ci && git commit -s ... && git push`. Never `--no-verify`.
- A stage that changes SketchUp-visible behavior gets a real-host check on the head that goes to
  merge, recorded in the PR. Use the bridge plus native controls as
  [`context/NATIVE_CONTROL_CAPABILITIES.md`](../../../../context/NATIVE_CONTROL_CAPABILITIES.md)
  says: a context-menu item is reached through `app_menu` on SketchUp's Edit selection submenu,
  which runs the same handlers as a right-click. This loop is not a release claim.
- The PR says `Closes #<stage issue>` and `Part of #426`. Only the last stage closes #426.
- Ledger flips ride in the next stage's PR.

## Stages

Stages run in table order. Each merges before the next starts. `#416` renames internals that
SUI-04 and SUI-06 use, `#417` sets the availability rules SUI-05 and SUI-06 extend, and the inverse
unit conversion lands in SUI-03 for SUI-06 to reuse.

| Stage | Issues | Item | Review | Host check |
| --- | --- | --- | --- | --- |
| SUI-01 | #416 | Floor Surface wording and the Create Space dialog | sol | Menu labels, dialog text |
| SUI-02 | #417 | Context menu offers only what applies | sol | Every row of the table, root and open contexts |
| SUI-03 | #419, #421 | Space label format; unit-aware Set Ground depth (adds the inverse conversion) | sol | Label in IP and SI, new-session defaults, modal dialog |
| SUI-04 | #422 | Set Height without a click | sol | Typed height, one Undo step |
| SUI-05 | #423 | Connected Faces define Volumes; Add New Volume to Space | astra (public operation return shape) | Create and Add routes, Undo, warning, export |
| SUI-06 | #424 | Right-click editing for Spaces | sol | Every item, modal dialogs, IP and SI |
| SUI-07 | #420 | SketchUp Delete on Volumes; panel trash icon | astra (native lock lifecycle) | Part 1 experiment first, then Undo and last-Volume cases |
| SUI-08 | #418, #425 | Collapse/Expand toggle; split Table options | sol | Toolbar at the three named panel sizes |

## SUI-07 starts with an experiment

The result of #420 Part 1 decides the implementation. The conductor runs that experiment in real
SketchUp, records Undo, Move, double-click, save and autosave results on the issue, and then briefs
the stage with the chosen route: native Delete, or the Delete Volume menu item as the fallback.
