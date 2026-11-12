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

As built (API 1.50): the listing is a public read, `API.outcomes(context:, limit:, cursor:, keys:)`
(`shell/outcome_history.rb`, through `Dispatch#outcomes` with the `outcome` grant), so a Ruby script lists
its own changes too; the agent tool passes the binding's key map (`Sequencer#keys_by_sequence`) as data, so
the page is sized with every row's key already on it rather than decorated after the 16 KiB cut. The cursor
binds the caller (in the filter digest) and its highest accepted sequence, not the Model revision: a refused-after-acceptance change adds
a row without moving the revision, and a panel edit moves the revision without touching the caller's rows.
Eviction and expiry drop the oldest rows, which sit at the tail of a newest-first list, so they only shorten
it. A running change is not listed (dispatch is serial on the main thread, so a list never meets one). The
entry records its operation name and a UTC time at `begin`; the monotonic clock stays the expiry clock.

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

As built (API 1.51):

- **Client measurement** (2026-11-12, no SketchUp; a throwaway stub MCP server returning a text block, a PNG
  `image` block and `structuredContent`; each image's top half a solid colour the model had to name):
  Claude Code 2.1.317 (`claude -p --restricted --strict-mcp-config --tools Read`, only the stub's tool
  called) and Codex 0.167.1 (`codex exec`, scratch `CODEX_HOME` holding only `auth.json`) named every colour
  at 100 KB, 500 KB, 1 MB and 2 MB over stdio and at 2, 3 and 5 MB (6.8 MB of base64) over HTTP. Codex
  refused every call under `approval: never` until `default_tools_approval_mode="approve"` was set for the
  server. Neither client failed, so the measured ceiling is above 5 MB. Cost: Claude about $0.19 for the two
  runs, Codex about 32k tokens. Raw output in `_private/agent-client/s3-image-cap-2026-11-12/`, not
  `_private/host/`, since no host ran.
- **Cap:** `InlineImage::MAX_BYTES`, 2 MiB decoded, the capture's existing limit, now defined by it: every
  capture can go inline, with a margin over two to the measured 5 MB. So `inline` adds no second size rule;
  `capture.too_large` now names a smaller `width` and `height` in its message and `detail`.
- **Shape departure:** the image rides in the result's value as `inline_image` (`mime_type`, base64
  `data`; `shell/inline_image.rb`), and the executor moves any completed value's `inline_image` into the MCP
  `image` block before measuring the 24 KiB budget, refusing one over the cap as
  `request.response_too_large`. A handler returns only its value, so this is the one place it can put the
  image without changing dispatch, and the executor names no operation: any view command or query may
  declare the key. A Ruby caller gets the base64 in the value.
- **File part departure:** the HBJSON travels as one JSON string in fragments (`Fragments.read`, as the
  `report` part does), so the fragment `sha256` is of the encoded text, and the receipt's `sha256` and
  `bytes` ride beside it as `file`; the parsed string's UTF-8 bytes hash to them (`export/written_file.rb`,
  out of `Task`, which was at its length limit). Each fragment reads and hashes the file again, since
  nothing is kept between fragments and the packet allows no new store: about 11 ms per fragment for a
  4.7 MB file, offline. No size cap: a large model costs many calls, not a large reply. Something other
  than a regular file at the path, a different hash or bytes that are not UTF-8 refuse `artifact.changed`.
  A blocked, failed or cancelled task has no receipt and refuses `artifact.none`.

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
| S1 expected revision | Merged to main 2026-11-12 (API 1.49): checked in `Export::Tasks#start` after settle and again in each reading slice; 4 tests in `tests/export_tasks_test.rb` plus the agent-tool route in `tests/export_diagnostics_test.rb`; `make ci` green (2824 Ruby runs, 876 JS, 264 Python) | [#501](https://github.com/ph-composer/ph-composer-skp/pull/501) |
| S2 operation history | Merged to main 2026-11-12 (API 1.50): `make ci` green, 11 tests in `tests/agent_access_outcome_history_test.rb`; Codex review (gpt-6.1-sol) 2 P2 fixed | [#502](https://github.com/ph-composer/ph-composer-skp/pull/502) |
| S3 artifact bytes | Implemented on branch `feature/458-s3-artifact-bytes` (API 1.51): client measurement above; `make ci` green (2842 Ruby runs, 876 JS, 264 Python); 3 tests in `tests/capture_command_test.rb`, 2 in `tests/export_tasks_test.rb`, the agent route's `artifact.none` in `tests/export_diagnostics_test.rb` | |
| S4 overlay capture | Closed by measurement 2026-11-12: an in-process window capture is refused without Screen Recording permission and brings up the system's permission flow; geometry-only kept, limit in AGENT_INTERFACE | none |
