# Agent access: the four deferred slices

DATE: 2026-11-12
STATUS: Planned. Ed chose "plan, then build all" on 2026-11-12. Stages run one at a time through pr-loop, merge on green.
ISSUE: [#458](https://github.com/ph-composer/ph-composer-skp/issues/458)

## Why

The agent-workflows packet deferred four optional slices
([archive](../../archive/agent-workflows-2026-11/phases/aw-09-host-collaboration.md), D07, D08, D15-e).
Ed selected all four. Each stage is independent. All four touch `agent_access/tools.rb`, `shell/api.rb`
(one API minor version each) and [AGENT_INTERFACE](../../../context/AGENT_INTERFACE.md), so they run in
sequence from fresh main, never stacked.

## Fixed constraints

- No caller-supplied path, anywhere. Artifacts are named by a receipt (task id, capture hash).
- Replies stay within `Executor::MAX_RESULT_BYTES` (24 KiB of `structuredContent`). Both target clients
  fail a larger result. Anything larger comes in fragments through the existing `part`/`cursor` shape.
- Existing retention is the bound: captures (4 per session, 15 min), export tasks (20, 30 min),
  `OutcomeStore` (256 entries, 15 min). No new store or persistence.
- Grants: capture bytes under `capture`, export bytes under `export`, history under the caller's own
  `model_write` (it reads only that caller's outcomes).

## Stages

### S1 · R16: expected revision on `start_export`

Optional `expected_revision` in `Export::TaskContract::TASKS["start_export"]`. When it is given and the
session's revision differs, the start refuses `revision.stale` with nothing started. The check runs where
the task takes its Model read on the main thread, not only at arrival. If extraction is deferred past the
start, the check moves to the read or the task fails stale at that point. Tests: matching, stale and absent
revisions, and an edit between arrival and the read.

### S2 · Operation history

A caller-scoped list of that caller's retained change outcomes, newest first, paged by `Pages.bounded`:
sequence, idempotency key, operation name, status, effect, code, revision, recorded time and affected
references (capped, with a total). No `value`, params or payloads. Shape: the `outcome` tool with neither
`sequence` nor `idempotency_key` lists, rather than a new tool (D15-a precedent). The source is
`OutcomeStore` plus the sequencer's key map. If an entry lacks the operation name, the stage records it at
`begin`. The reply says the bound ("what this session still retains: up to 256 outcomes, 15 minutes").
Another caller's rows never appear. Tests: two callers, eviction, expiry and paging.

### S3 · Artifact bytes

- **Captures:** `ph_composer.view.capture` takes `inline: true` and also returns the PNG as an MCP `image`
  content block beside the usual `structuredContent`. That means one call and no new tool, and the image
  is the one just written, so no stale receipt. The executor carries the block outside the 24 KiB text
  budget, under its own byte cap. The stage measures that cap against both target clients (Claude Code,
  Codex) with an isolated client run (native-acceptance skill, "agent client run"). Over the cap, the
  capture refuses `capture.too_large` and suggests a smaller width and height.
- **Export file:** `export_status` gains `part: "file"` for a written task. It returns the HBJSON text in
  fragments with its SHA-256, read from the receipt's own path while the task is retained. A file whose
  hash no longer matches the receipt refuses `artifact.changed`. A task that wrote nothing refuses
  `artifact.none`.
- Tests: inline image size and digest, the cap refusal, file fragments rejoined equal to the file and its
  hash, a changed file, an expired task and another token's task.

### S4 · Overlay capture (experiment first)

`View#write_image` leaves PH-Composer's overlays out (measured on 26.1.188). The one candidate route is a
window capture by id (`screencapture -l`), which is how the host tooling already captures overlays.
Before any code, measure from inside SketchUp:

- whether macOS asks SketchUp for Screen Recording permission, which would disturb the user;
- whether the right document window can be found when two Models are open;
- what the capture shows when SketchUp is behind another app, hidden or minimized.

If any of these disturbs the user or is unreliable, keep `overlays: "not_included"` and record the measured
limit in AGENT_INTERFACE. Closing on that result counts as done. Only a clean result leads to an opt-in
`overlays: true` parameter, macOS only, with `overlays` saying which route was used.

## Acceptance

Each stage closes with `make ci`, a Codex review and its offline tests. S3 also needs the client
measurement, and S4 needs the host measurement, with evidence kept under `_private/host/` and a summary
here.

## Status

| Stage | State | PR |
| --- | --- | --- |
| S1 expected revision | Implemented on branch `feature/458-s1-export-expected-revision` (API 1.49): checked in `Export::Tasks#start` after settle and again in each reading slice; 4 tests in `tests/export_tasks_test.rb` plus the agent-tool route in `tests/export_diagnostics_test.rb` | PR pending |
| S2 operation history | Planned | |
| S3 artifact bytes | Planned | |
| S4 overlay capture | Closed by measurement 2026-11-12: an in-process window capture is refused without Screen Recording permission and brings up the system's permission flow; geometry-only kept, limit in AGENT_INTERFACE | none |
