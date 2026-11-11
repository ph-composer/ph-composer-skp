# Agent workflows and application access review

DATE: 2026-11-09
STATUS: Review complete; archived 2026-11-11. Recommendations and implementation plans only; no shipping changes. Every finding is fixed or deferred by the [implementation packet](../agent-workflows-2026-11/README.md) (#439).
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/435 (review/planning publication only)
BASELINE: `f65ccee62b0a3994a46001d55f7aefd1a69f0faf`, fetched `origin/main`, API 1.31.
BRANCH: `codex/agent-access-review`, isolated worktree.

PH-Composer already has the right foundation for users working alongside agents. The local MCP
endpoint dispatches into the same registered operations as the panel, with explicit sessions,
capability grants, previews, revision checks, replayable writes and native Undo. The next investment
should complete that interface and its safety checks. A replacement agent framework or built-in
LLM would add work without addressing the gaps found here.

The principal problems are unsafe combinations of otherwise valid operations, incomplete geometry
discovery, results that valid models can make impossible to retrieve over MCP, and connection and
instruction handoff that still assumes a technically involved user. Definition editing is much more
complete than initial geometry discovery and large-model QA.

## Read this review

1. [Findings](FINDINGS.md): ranked observations, source evidence and corrections.
2. [Feature and data coverage](COVERAGE.md): reads, authoring, relationships, QA and remaining gaps.
3. [Connection and collaboration](CONNECTIONS.md): setup, host lifecycle, visual context and scope.
4. [Evidence](evidence/README.md): reproducible probes, passing checks and limitations.
5. [Implementation packet](../agent-workflows-2026-11/README.md): ordered stages,
   proposed contracts, acceptance cases and the sole future-delivery ledger.

## Scope and findings in context

The inventory contains **240 callable registrations**: 77 queries, 114 actions, 31 view commands,
17 setup commands and one file export, plus one internal proposal participant. It covers five
domain features and seven foundation registrations, 11 catalog record kinds and nine entity
reference targets. Export task methods are additional API verbs, not part of that 240.
The [machine-readable inventory](evidence/discovery.json) lists every registered operation and owner.

Reviewed: Zones, Faces, adjacency, Building-Segments and Levels; Materials and Assemblies; Window
products, Types, grids, installs and Units; Spaces, Volumes and Floor Segments; Thermal Bridge Types,
Edge assignments and schedules; optional libraries; metadata and extension data; validation and
export; Colour-by, context/navigation/capture; token lifecycle, MCP dispatch, setup and documentation.
Mechanical equipment, piping, ducting, climate and METr conversion are planned product features,
not implemented features with missing agent adapters. Their existing packets retain ownership.

Three safety defects deserve first attention: overlapping Space/Zone ownership can remove Zone data;
stale null Face identities can pass some writes; and single-Zone writes do not enforce the same
own-lock check as batch writes. The first two need correction before broad autonomous model editing.
The remaining findings mostly complete discoverability, readback, repair and collaboration.
SUI-02 landed during this audit and closes the direct new Space-to-Zone claim case; R01 records
that mitigation and the remaining descendant/legacy checks. Recheck every fix against current source.

Useful contracts to preserve:

- Feature declarations supply operation schemas, units, examples and refusals. All current
  operation descriptions fit the transport budget; the largest measured one is 15,392 bytes.
- Explicit operations already cover Assembly construction, face assignment, Window placement,
  Window grid/install edits, Spaces authoring and Thermal Bridge assignment. Do not mistake the
  presence of pointer tools for an absence of programmatic equivalents.
- External tokens are scoped and revocable. The executor rechecks grants and target sessions on
  the host thread. Lost mutation replies can be recovered without repeating a write.
- Reads do not need an open panel. Generated API documentation and synthetic clients already exist.
- Export uses approved destinations and caller-owned task/artifact receipts. Capture includes
  revision and camera provenance and honestly declares that overlays are excluded.

## Method and limits

The main reviewer audited discovery, transport, setup, lifecycle, documentation and integration.
Two bounded read-only reviewers covered geometry/Spaces/Thermal Bridges and envelope/library/export.
Consequential findings were checked against the owning source and retained synthetic probes. This
is a feature/access review, not a complete audit of every geometry or thermal algorithm.

The primary checkout was left on the other agent's feature branch. No host was installed, reloaded,
launched or changed; no real client configuration, credentials or client model was accessed. Native
claims below refer only to linked historical receipts. A stub reproduction establishes code behavior,
not native lifecycle acceptance. No current-client connection, SketchUp 2023 or Windows proof is claimed.

The earlier [agent review](../agent-access-review/README.md) and
[Phase 3a1](../phase-03a1/STATUS.md) are completed history. This review does not reopen their
closed transport work. It identifies remaining gaps against the later baseline, including new feature
coverage and limits that ordinary happy-path tests miss.

The repository's `planning/.instructions.md` refers to `planning-conventions`, but that skill was
not available in the supplied catalog or local skill roots. This packet follows the repository's
explicit folder/status rules and existing packet shapes. Issue #435 tracks the separately authorized documentation publication on 2026-11-10.

## Publication update, 2026-11-10

The documentation branch was advanced to `6d06ff498e68a485ff250fd1bb019cb58d520549` before
publication. All eight Spaces UI stages are now merged and their packet is
[archived](../spaces-ui-refinement-2026-11/STATUS.md). This update preserves that work
and the primary checkout's unrelated staged edit. Source line citations, inventory counts, test logs
and reproduction outcomes in this review still describe `f65ccee6`; they were not regenerated
against the publication base. In particular, recheck R01/R04 and the added Space/Volume operations
before implementing AW-01/AW-03. Implementation remains unauthorized.
