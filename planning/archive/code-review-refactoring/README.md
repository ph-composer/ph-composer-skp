# Architecture refactoring plans

DATE: 2026-10-13
STATUS: Complete and archived 2026-10-14. Eleven of twelve packets delivered and archived (PRs 99 to 126); the geometry contribution packet moved to `planning/archive/geometry-contribution-contracts/` with G-02 delivered and G-01, G-03 and G-04 deferred to the phase 3b ledger.
ISSUE: none (local planning draft)
BASELINE: `cfe01a6aad99a0e09d5ecf0de5659c606d7ba4f9`

Start with the accepted [Zone-child pattern](ZONE_CHILD_PATTERN.md) and the source-backed
[Windows rationale](../code-review/WINDOWS_BOUNDARY.md). Reusable values stay independent of their placement;
authoring coordinators compose owner operations and native adapters.

Each packet holds three files. `PLAN.md` is the phased plan a coding agent executes from: a table of
what the source does at the baseline, the target design with concrete Ruby or JavaScript shapes, one
`### Stage` section per stage with files, tests and commands, and a decisions table that separates
what the agent decides from what goes to Ed. `STATUS.md` is the stage ledger; it says the phases live
in `PLAN.md` under `## Stages` and there is no `phases/` folder, which is what to tell `implement`
when it asks where the phases are. `ACCEPTANCE.md` holds the observable checks; its case ids are
stable, and rows a later simplification made moot are marked withdrawn rather than renumbered.

## Packets and readiness

| Packet | Findings | Readiness | Documents |
| --- | --- | --- | --- |
| Export contract wording | F08 | Complete; merged 2026-10-13 ([PR #99](https://github.com/bldgtyp/ph-composer/pull/99)) | archived at [planning/archive/export-contract-wording](../export-contract-wording/PLAN.md) |
| Outcome hook isolation | JS-02 | Complete; merged 2026-10-13 ([PR #102](https://github.com/bldgtyp/ph-composer/pull/102)) | archived at [planning/archive/outcome-hook-isolation](../outcome-hook-isolation/PLAN.md) |
| Contributor example lifecycle | JS-03, JS-04 | Complete; merged 2026-10-13 ([PR #102](https://github.com/bldgtyp/ph-composer/pull/102)) | archived at [planning/archive/contributor-example-lifecycle](../contributor-example-lifecycle/PLAN.md) |
| Registration reliability | F01, F02 | Complete; merged 2026-10-13 ([PR #105](https://github.com/bldgtyp/ph-composer/pull/105)) | archived at [planning/archive/registration-reliability](../registration-reliability/PLAN.md) |
| Cross-feature composition | F04 | Complete; merged 2026-10-13 ([PR #105](https://github.com/bldgtyp/ph-composer/pull/105)) | archived at [planning/archive/cross-feature-composition](../cross-feature-composition/PLAN.md) |
| Windows orchestration | RF-02 | Complete; merged 2026-10-13 ([PR #108](https://github.com/bldgtyp/ph-composer/pull/108)) | archived at [planning/archive/windows-orchestration](../windows-orchestration/PLAN.md) |
| Panel domain ownership | JS-01, JS-05 | Complete; merged 2026-10-13 ([PR #108](https://github.com/bldgtyp/ph-composer/pull/108)) | archived at [planning/archive/panel-domain-ownership](../panel-domain-ownership/PLAN.md) |
| Library contracts | F05, RF-04 | Complete; merged ([PR #112](https://github.com/bldgtyp/ph-composer/pull/112)) and archived | [plan](../library-contracts/PLAN.md), [status](../library-contracts/STATUS.md), [acceptance](../library-contracts/ACCEPTANCE.md) |
| Entity customization | RF-01, RF-03, F07 | Complete; merged (PRs #110, #122, #123, #126) and archived | archived at [planning/archive/entity-customization](../entity-customization/PLAN.md) |
| Zone-child lifecycle | copied-Zone Windows request, shared pattern | Complete; merged (PRs #114 to #117) and archived | [plan](../zone-child-lifecycle/PLAN.md), [status](../zone-child-lifecycle/STATUS.md), [acceptance](../zone-child-lifecycle/ACCEPTANCE.md) |
| Geometry contribution contracts | F06 | G-02 merged ([PR #119](https://github.com/bldgtyp/ph-composer/pull/119)); G-01, G-03, G-04 wait for the thermal-bridge adopter | [plan](../geometry-contribution-contracts/PLAN.md), [status](../geometry-contribution-contracts/STATUS.md), [acceptance](../geometry-contribution-contracts/ACCEPTANCE.md) |
| Foundation purity | F03 | Complete; archived after PR 121 | [plan](../foundation-purity/PLAN.md), [status](../foundation-purity/STATUS.md), [acceptance](../foundation-purity/ACCEPTANCE.md) |

[Delivery order](DELIVERY_ORDER.md) records dependencies and PR boundaries. [Decisions](DECISIONS.md)
records Ed's accepted direction, the technical defaults, the deviations the 2026-10-13 source review
introduced, and the questions still open. [Status](STATUS.md) is the program ledger.

## Handing a packet to a coding agent

Give the agent the packet folder. It reads `STATUS.md`, then `PLAN.md`, and implements the first
stage whose state is `Scoped`. One stage is one reviewable change. Before starting a stage the
agent confirms the dependency named in the plan's header has landed. A stage that names a document
deliverable (ZC-01, G-01, EC-03) ends with the document and a note to Ed, not with code.

Each plan's "Verified at the baseline" table was checked against `cfe01a6` on 2026-10-13. A later
head may have moved a method; the table names files and methods rather than line numbers so the
agent can re-find them. Planning points at code; code never cites planning.
