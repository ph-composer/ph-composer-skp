# Delivery plan

DATE: 2026-11-09
STATUS: In progress. Implementation authorized 2026-11-10 (#439); one branch and PR per stage.
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication

## Intended result

A fresh local MCP client, with the grants its user chose and no source checkout, can discover all
installed PH data kinds and operation contracts; find eligible existing geometry from an empty
selection; inspect complete model data and QA at representative scale; preview, apply and read back
an edit; recover an interrupted request; and inspect an export or a failed run. The human can keep
working, with unsafe host moments refused or clearly handed back. Every feature uses the same
registered operation boundary and native Undo rules.

## Entry and delivery rules

1. Rebase the selected stage onto the then-current integration branch in its own worktree. Compare
   the named source and probe with the latest merged feature work; close already-fixed items with
   evidence instead of reimplementing them. Preserve all unrelated work.
2. Recheck merged Spaces SUI-02/05/07; coordinate library skipped-row work and Phase 4 mechanical.
   SUI-02 `f93d8b6b` already guards direct claimed selections. Review descendant and legacy cases
   before choosing any additional ownership design. SUI-05 create-result changes are now merged;
   use the archived Spaces packet and current source, not the earlier pending-work assumption.
3. Use the architecture and Ruby rubrics during design and the one coherent-diff review. Use the
   UI skill when changing a dialog. High-risk identity, serialization, host and credential boundaries
   use the repository's stronger review level; do not stack equivalent review panels.
4. Turn retained review probes into focused normal regression tests that assert the corrected
   outcome. Review probes assert historical failure behavior and are not the future release gate.
5. Preserve supported Ruby 2.7 / Chromium 88 contracts. Keep current operation names and record
   formats unless an explicit compatibility decision is recorded. Bump API minor and generated
   reference for additive public changes. Refresh shipped manifests when assets change.
6. Run focused tests while editing, then the required coherent full gate `make ci`. Native/client
   gates in each stage are additional evidence, not substitutes. Run docs-pass for the owner,
   context, guide and ledger. Commit, publish and merge only within the implementation authorization.

## Stages

| Stage | Outcome | Findings | Dependencies | Principal owners |
| --- | --- | --- | --- | --- |
| [AW-01](phases/aw-01-target-safety.md) | Strict targets, ownership, lock and creation receipts | R01-R04 | Latest SUI overlap check | Zones, Spaces, shared record guards |
| [AW-02](phases/aw-02-discovery-and-guide.md) | Complete bounded discovery and an installed operating guide | R05, R12, R15 schema groundwork | None; preserve AW-01 conflict contracts | API, MCP, library descriptors, docs |
| [AW-03](phases/aw-03-geometry-discovery.md) | Find candidates and read assignments without user selection | R06 | AW-01, AW-02 | Context primitives, Zones, Spaces, Windows, Thermal Bridges |
| [AW-04](phases/aw-04-definition-detail.md) | Read large definitions and metadata completely | R07 definitions | AW-02 | Record queries, definition readers, Assemblies/Windows |
| [AW-05](phases/aw-05-occurrence-detail.md) | Read large occurrence, geometry and schedule data | R07 geometry | AW-03, AW-04 shared budgeting | Zones, Windows, Spaces, Thermal Bridges |
| [AW-06](phases/aw-06-library-workflows.md) | Bounded library browsing and atomic copy/assign | R08, R15 | AW-02, AW-04 | Library and kind adapters |
| [AW-07](phases/aw-07-qa-export-and-repair.md) | Complete QA, failed-run retrieval and safe corrupt-assignment repair | R09, R10; optional R16 | AW-04/AW-05; AW-06 for library QA recipe | Export, contributors, Thermal Bridges |
| [AW-08](phases/aw-08-connections.md) | Repairable, independently scoped client setup | R11 | AW-02 guide; D02 scope chosen at intake | Agent Access, client config, UI |
| [AW-09](phases/aw-09-host-collaboration.md) | Prove native coexistence; selected artifact/history improvements | R13; optional R14 | AW-01, AW-02, AW-07 for task artifacts | Host/session, capture, Agent Access |
| [AW-10](phases/aw-10-integrated-acceptance.md) | Fresh-client, all-feature evidence and handoff | All selected findings | AW-01 through AW-09 selected scope | Integration and documentation |

Use this table as the dependency graph. Default delivery is in order, one coherent change at a
time. AW-08 can proceed after AW-02 if it does not edit files simultaneously with another stage;
that is an option, not an instruction to spawn parallel agents. AW-09's native experiment can run
earlier when a safe host slot is available, without authorizing its optional implementation slices.

## Milestones and completion

- **M1, safe and discoverable:** AW-01/AW-02 accepted, code/schema/guidance agree.
- **M2, complete semantic access:** AW-03 through AW-07 accepted; every retained oversized case
  has a complete retrieval route through the executor, and first-target discovery needs no selection.
- **M3, usable alongside people:** AW-08/AW-09 selected scope and AW-10 accepted on recorded clients
  and host. Remaining optional visual/history/platform work is explicitly deferred.

This packet is complete only when its selected acceptance rows close in STATUS. Public distribution,
Windows, SketchUp 2023, future mechanical features, METr and general CAD authoring retain their
own product/platform gates. Do not hold completed local-interface improvements hostage to an
unselected new product boundary.
