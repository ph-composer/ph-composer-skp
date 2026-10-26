# External agent interface

DATE: 2026-09-30
STATUS: Agent access is an accepted product priority. The in-process programming interface
(`PhComposer::API`: discover, describe, connect, query, preview, invoke, outcome) merged through
PR #1 from Phase 0 P0-D with a panel-closed synthetic client. Phase 1 (PR #3, PR #6) added `view`,
the selection, reveal and camera verb; per-operation schemas and examples; bounded, filtered and
projected reads; the export task methods; and in-process grants (`read`, `view`, `model_write`,
`export`) enforced at dispatch. Phase 3a1 added the external path: a loopback MCP endpoint served
from the extension with per-user bearer tokens granted in the Agent Access dialog; the Model context
read and the edit-path commands; capability and declared terms in `describe`; and the bounded Spaces
reads with candidate Faces. Its remaining stages (write grants, artifacts, capture) are proposed
until their owning packet records them.

Users bring their own agents. PH-Composer supplies documented access to inspect, view and edit
the authored model without requiring an agent to understand private Ruby internals or operate
every control by pixels. PH-Composer does not build an agent, select an LLM, store model-provider
keys or require an AI subscription. Hand authoring remains complete without agent access.

This document extends [EXTENSIBILITY.md](EXTENSIBILITY.md). It owns external-agent contracts;
[TECH_STACK.md](TECH_STACK.md) remains authoritative for host execution and transactions.

## One application interface, several clients

Use the same public queries and validated operations for the panel, Ruby scripts and external
adapters. Feature packages own business behavior. The shell supplies discovery and dispatch;
adapters translate transport formats and carry no domain logic.

The public operation boundary must work with the HtmlDialog closed. Panel-specific request slots,
rendering, dialogs and notices are not the source of an external caller's result. Supply explicit
operation context and return a structured outcome. Keep confirmation policy separate from the
panel's presentation of it so another client can satisfy the same requirements.

Recommend a local MCP adapter as the first agent integration, backed by the same versioned JSON
contract usable by a CLI or other clients. A local companion process could isolate MCP dependencies
from SketchUp's Ruby runtime. This is a design option, not a selected runtime or packaging plan.
Do not put an MCP implementation in every feature. Generate transport schemas and reference
documentation from registered query/action definitions where practical; test their agreement.

Keep the development host bridge separate. Arbitrary Ruby evaluation remains development tooling,
excluded from the normal shipped agent interface. Third-party bridges may call public Ruby methods
for experimentation, but that does not prove lifecycle correctness or confer supported-client status.

## Discover before acting

Expose a bounded capability description with:

- Extension and API versions, supported contract versions and installed feature capabilities.
- Open model sessions and an unambiguous target identity, plus relevant model revision, active edit
  path and host readiness. A reopened document receives a new session identity.
- Available queries and actions with descriptions, input/output schemas, units, examples,
  side effects, required access and preconditions. Distinguish unavailable from unsupported actions.
- Record schemas and relationships, stable identifiers, occurrence-path meaning, supported import
  and export formats, and pointers to concise documentation.

Each operation publishes the codes it can refuse with: `describe` returns its own as `refuses` and
names the common sets it also answers as `common_refusal_sets`, which `discover` returns once as
`common_refusals`. Every `refuses` entry has `code`, `owner` and `description`. Feature descriptions
are declared text; foundation descriptions are null, and discovery's `refusal_documentation` URL
points to the public [Outcomes and codes](CONTRACTS.md#outcomes-and-codes) authority.
A client plans recovery from these lists rather than learning codes by trying.
Library copy includes the local read, create, replace and assignment refusals of installed kind
adapters; the in-file query includes their local-read refusals. The lists reflect the current
composition, so an outside kind's declared codes are discoverable without changes to the shell.

Implemented: `describe` names each operation's `capability`, read from the same table dispatch
enforces (`Declarations::CAPABILITIES`), and an action's `preview_capability` (`read`). It adds, when
declared, a view command's `side_effects` (a protection boundary it can trigger, such as a Volume
locking when the edit path leaves it), `preconditions` (sentences saying what a caller can prepare;
the handler still checks) and a query's `response`: `{"bounded": false, "prefer": <query>}` marks a
whole-Model read the panel uses and names the bounded read a client with a reply budget calls
instead. Registration refuses malformed terms and a `prefer` that names no query. `discover` adds
`schemas`: the Outcome envelope and a mutation's `request`, as JSON Schema.

Do not make a client infer action names or capabilities from private file paths or the current UI.
Reject incompatible API versions explicitly and document deprecations. New features register
their agent-visible contracts alongside their existing operations rather than editing an adapter.

## Focused reads and visual context

Provide model summaries, filtered and paginated record queries, selected field projections,
individual records, relationships and validation findings. Bound response sizes and identify
truncation. Large geometry and exported artifacts use explicit retrieval rather than appearing
in every snapshot. Pages identify their revision and require restart if their snapshot expires.

Return stable entity IDs and path-qualified occurrence references with SI unit information.
Distinguish authored values, derived values, missing inputs and unsupported data. Findings carry
stable codes, affected references and recovery information; display labels remain separate.

Implemented: every list read pages through `shell/pages.rb`. Rows come in a stable key order
(record id, or root-to-occurrence path for Zones and Faces), at most 500 per page, with
`next_cursor` and `total`. A cursor binds the Model session, the query, a digest of the filter
and the revision; reusing it against any other refuses (`params.invalid`, or
`query.cursor_expired` after a revision change). `ph_composer.zones.list` and
`ph_composer.zones.faces.list` filter by id and path and project with `fields`, which returns a
row's reference and the named values without geometry or metadata. The panel reads the complete
projections `ph_composer.zones.all` and `ph_composer.zones.faces.all`; scripts page the lists.
`ph_composer.zones.faces.host_context` answers explicit root-to-Face paths with each Face's
reference, values and the write refusal its path shows, scanning only the collections on each path,
for a caller that holds a path and needs no Face table.

`Pages.bounded` also cuts a page at the last whole row that keeps its serialized rows under 16 KB
(`Pages::MAX_PAGE_BYTES`), so a page and its envelope fit the agent reply budget; a row is never
split, and the cursor resumes after the last row sent. The Spaces reads use it:
`ph_composer.spaces.list` answers Space summaries (values, metrics, Zone and Building-Segment, and
counts of Volumes, Floor Segments and findings by code) with a `fields` projection whose default
leaves out `user_data`, `extension_data` and `extension_status`. Its `model` sums are taken over
every Space before any filter, and its `zones` and `building_segments` are the sums of the Zones and
Building-Segments its page's Spaces belong to. `spaces.volumes.list` (one Space),
`spaces.floor_segments.list` (one Space or one Volume, exactly one) and `spaces.findings.list` (the
Model or one Space, optionally by `codes`, each finding with the reference of what it is about)
answer the children; a scope reference resolves by path and then id (`target.not_found`,
`target.changed`). `spaces.all` stays whole for the panel and names `spaces.list` as its bounded
alternative. `spaces.candidate_faces.list` (one Space or one Volume) answers the Faces that carry no
record yet: a Face directly in a Volume is a Floor candidate for `spaces.floors.mark`, a Face loose
at a Space's root a candidate for `spaces.volumes.create` (which also needs the Space open). Each row
gives its path, plan area and normal (loops when `fields` asks), the operation, and the refusal that
operation would give now, from one rule the read and both actions share (`Spaces::Eligibility`).
The definition lists (`ph_composer.assemblies.materials.list` and `assemblies.list`, the Window
product and Type lists, `ph_composer.thermal_bridges.types.list`) page through
`shell/definition_lists.rb`: `Pages.bounded` by record id, an `ids` filter, and a `fields`
projection over the row's own properties that always keeps `kind`, `id` and `schema_version`.
Without `fields`, a row is the one the matching `.all` read gives. A row larger than the budget
comes alone, and asking for fewer `fields` reads past it. An unreadable record is reported in
`unreadable` beside the page and counted in `total`.
`spaces.update` and `spaces.batch_update` type `values` and `expected_values` field by field from the
record definitions, with units; null clears an optional value, and a field the referenced kind does
not take is refused.

Some reads carry derived facts so no client recomputes a domain rule. Every Window Type row's
`display.install_topology` gives each non-empty element's four edges with their classification
(`perimeter`, `shared`, `partial`) and whether an installation can be painted there, an opaque
`copy_key` that is equal on two Types exactly when an installation copy between them is accepted,
and `copy_slots`, each element's slot in that copy. Every Zone row carries `face_area_m2` and
`unclassified_face_area_m2`, the occurrence's Face area summed through its own transform, the second
over Faces with no recorded values. Both are recomputed on each read, never stored, and never
accepted by a write.

Implemented: the Model context read, `ph_composer.context.read` (and the agent `context` tool). It
answers the session (id, file name, the Model's own file path, revision, view generation, whether it
is the active Model), readiness (busy and why, and the active SketchUp tool), the edit path from the
root as persistent id, type and name per open Group or Component, the camera (eye and target in
metres, up, perspective with its field of view and the extent it spans or parallel with its height, and two-point perspective's offset and scale), and the selection in pages by
persistent id: at most 200 entities, 100 by default, and never more than 16 KB of rows
(`Pages.bounded`, which cuts at the last whole row and resumes after it). The path is the user's own document, not an approved destination, so it is shown: two
open Models with the same file name differ by it. The view generation is a second session counter
that advances on a selection or camera change (a view observer) and never with the revision; a
selection page is bound to both,
so its cursor expires (`query.cursor_expired`) when the selection changes even though the Model did
not. The read moves neither the edit path, the selection nor the camera.

Implemented: the edit path moves through two foundation view commands, so a client never assigns it
or walks geometry to reach a context. `ph_composer.context.open` takes `path`, the persistent ids of
the Groups and Components from the root, outermost first; `ph_composer.context.root` closes every one.
Both take an optional `expected_path`, the path the client last read, and refuse when it has changed
(`target.edit_path_changed`); `open` resolves every step first and refuses a missing one
(`target.not_found`), one that is locked or has a locked copy (`target.locked`, which SketchUp
would refuse too), a Live Component (`target.wrong_kind`) and an entity open now that the destination
reaches through another copy of its parent (`target.shared_definition`), and both refuse `session.busy` while the user has a tool other than Select or a
camera tool active, whose gesture a path change would end; each refusal comes before any boundary
runs, with nothing moved. They enter through
`EditContext`, so each feature's boundary runs: leaving an unprotected Volume, Spaces protects it in a
transparent step joined to the move. SketchUp records a path change that leaves a Group as an Undo
entry of its own ([host behavior](SKETCHUP_HOST_BEHAVIOR.md)); undoing it reopens the Group, and
entering a Group from the root added none on 26.1.188. Each answers the path and `changed`; a path equal to the
current one changes nothing and leaves the revision where it was, even when one of its steps has
since been locked. Spaces keeps `spaces.context.open`
and `.close` as reference-aware conveniences, and they and both `locate` commands declare their effects
in `side_effects`. [tools/examples/authoring/spaces_walkthrough.rb](../tools/examples/authoring/spaces_walkthrough.rb)
keeps native fixture setup apart from a client segment that uses only these public calls.

Implemented: `ph_composer.view.capture`, a view command under its own `capture` grant (a view
command may declare a grant other than `view`; `describe` names it). It writes a PNG of the current
view with SketchUp's `View#write_image`, at the viewport's size or a requested one up to 4096 pixels
a side and 2 MB, and answers its path, SHA-256, size, the time, and provenance: session, revision,
view generation, camera, edit path and a selection digest. The image is the Model's geometry only:
PH-Composer's overlays, tool drawing and panels are absent, which the result says as `overlays:
"not_included"`. It moves nothing. A view or revision change during the write refuses
(`capture.view_changed`). Each session keeps its four newest captures for 15 minutes in its own
temporary folder. Measured on 26.1.188 with SketchUp frontmost, behind another application, hidden and
minimized, the last also with the camera moved: each wrote the current view
([receipt](../planning/archive/phase-03a1/evidence/p3a1-16-integrated-acceptance.md)). A native modal stops
Ruby entirely, workers included, so a call made under one is never captured and the client sees its own
timeout rather than a refusal.

Support explicit selection, reveal and camera operations for visual inspection, plus viewport
capture where the host permits it. Captures identify their model session, revision, camera and
relevant selection so the agent knows what it saw. Report unsupported or obscured capture states
instead of presenting an old image as current. Never change camera or selection during a read.
Visual context complements semantic model data; it does not replace record and reference checks.

## Writes with observable outcomes

Target mutations by explicit session and entity references. Carry an expected revision or
equivalent preconditions for the affected records, geometry and edit context. Recheck on the host
at commit time. Reject stale or cross-model requests with a structured conflict and no mutation.
Do not silently resolve a reference by its display name or by whatever happens to be selected.

Use named model operations with existing validation and native Undo. Ed confirmed the default on
2026-09-18: an ordinary edit, including a batch submitted as one operation, succeeds completely
or has no effect. Validate all targets before committing, apply the changes in one native Undo
step, and roll back the whole operation if any target fails. Refuse stale requests without writing.
Failure produces a clear user warning explaining the reason and confirming that nothing changed;
return the same outcome structurally to programmatic callers, without requiring the panel to open.

A future long-running import may define a different contract explicitly in its owning plan;
partial success is never the default. Failures distinguish no writes from a completed rollback,
or a partial result only where that operation's accepted contract permits one. Never leave a model
transaction open while waiting for an LLM or a person's response.

Metadata on authored entities is written the same way: `ph_composer.zones.update_metadata`,
`ph_composer.zones.faces.update_metadata` and `ph_composer.windows.units.update_metadata` take a
batch of explicit occurrences with the metadata last read, and refuse every target or none
([CONTRACTS.md](CONTRACTS.md), "Records and extension data"). A script that reads the exported
HBJSON finds a Zone's, Face's, Window Unit's or Assembly's `user_data` on its Room, Face, Apertures
or Construction, beside PH-Composer's own `ph_composer` entry; other records' `user_data` stays in
the Model.

Provide a non-mutating proposal/preview for compound or destructive edits. It reports targets,
changed values, affected references and validation findings. A proposal binds to its inputs and
revision; applying it revalidates those preconditions. Routine edits need not acquire an extra
approval dialog just because the caller is an agent. Reuse the user's granted scope, and enforce
the same confirmation requirements for all clients when an operation needs confirmation.

Separate request correlation from duplicate-write prevention. Define a bounded idempotency
contract for mutations: scope keys to the caller/session, bind them to the request payload and
retain a retrievable outcome for a documented period. A retry after a lost response must not
create a second record or Undo entry. Report expired or uncertain outcomes; clients must inspect
state rather than retry blindly. Do not claim exactly-once execution across process crashes.
A request whose params are not plain JSON is refused before acceptance as `request.malformed`,
effect `none`: it consumes no sequence and retains no outcome, so the caller resends it corrected
under the same sequence.

Successful writes return affected references and the resulting revision, with enough information
to verify the change using a read. Validation failure is distinct from transport failure.
Query methods never repair records or change the active editing path as a side effect.

## Host lifecycle and concurrent work

Dispatch through the established host-safe execution boundary and serialize mutations. Network
callbacks must not mutate SketchUp objects directly. Preserve deferred observer behavior and
normal session invalidation. Users and multiple clients may edit between a read and a write.

Return a clear busy or unavailable outcome during conflicting modal tools, model transitions or
other unsupported host states. Do not steal focus or close a user's work to make a request succeed.
Recheck queued requests when they execute; arrival-time validation is insufficient.

Long operations return a task handle with status, progress, results and supported cancellation
semantics. A timeout does not imply cancellation or failure. Polling must work even when optional
change notifications are unavailable. Document task retention and behavior on model close or host
restart. Cancellation only rolls back work where the operation explicitly guarantees it.

### Implemented export task contract

`API.export_file(context:, name:, params:)` invokes a registered synchronous FileExport under
the explicit `export` grant. Discovery and description expose its owner, schemas and examples.
It does not consume a Model mutation sequence or create an Undo entry. A caller supplies explicit
scope and identity choices; `export_preview` returns the counts and omissions the file will hold.

### Locations only the user can choose

A setup command or FileExport may declare an approval: a file to open, a folder or a save
destination that only the user can choose. `describe` returns it as `approval` (`kind`, `title`).
The user answers it in one of two ways, and a path never travels into the API either way; the one
path that comes out is the written export pair, to the caller that started it (below).

**Now, in a native dialog.** The panel and the native menus run the operation through
`shell/native_approval.rb`. It first asks dispatch whether the call would be refused (grant, params,
a busy session, the operation's declared precondition such as a stale `expected_revision`) and opens
no dialog if so; otherwise it opens the matching SketchUp dialog, obtains consent before replacing an
existing file, and passes the chosen location to the handler outside params.
`NativeApproval.confirm_replace` owns that rule: on macOS the Save sheet's own question is the
consent, and other platforms ask once more. The HBJSON export first refuses a destination its
artifact pair would refuse (`Export::ArtifactPair.destination_problem`: no `.hbjson` extension, or
only one of the HBJSON and its Export report exists), so no question precedes a refusal. Dispatch
repeats every check after the dialog closes. A dismissed dialog returns `cancelled` with code
`request.cancelled` and changes nothing.

**Once, as an approved location.** The user approves a save destination, a library file or a library
folder in the Libraries dialog or the Libraries menu (`ph_composer.locations.approve_destination`,
`.approve_file`, `.approve_folder`, which only those native clients can run). The store
(`shell/approved_locations.rb`) keeps the path on this machine, in SketchUp's own defaults, behind an
opaque id. `ph_composer.locations.list` (`read`) returns each location's id, label, kind, dates and
whether it is still there; never a path or a file name. A label is the user's, or "Export
destination", "Library file" or "Library folder" and a number. `.rename` and `.revoke` need `setup`
and no dialog; revoking only takes access away. Approvals belong to this machine and this SketchUp
version.

Registration adds an optional `location` param to every operation whose approval is not itself an
approve command: `{ "id" }`, and for a save destination also `replace` and `expected_destination`.
Any caller holding the operation's grant (`export` for a file export, `setup` for a setup command)
passes the id; dispatch resolves it into the same answer a native dialog gives, and the handler
never sees the param. A save destination is reused until revoked. An approved file or folder is used
by one completed add, after which the configured library holds it and the id answers
`location.used`. The use is recorded before the add runs and undone if the add does not complete, so
a store that cannot record it refuses with `location.setup_unavailable` and nothing is configured. Each failure refuses with effect `none` and changes nothing: `location.unknown`,
`location.revoked`, `location.used`, `location.kind_mismatch`, `location.unavailable` (no longer
there as approved), `location.setup_unreadable`, `location.setup_unavailable`. A caller that passes
neither a native answer nor a location is refused at once with `access.user_required`, and no
dialog opens, so an unattended call cannot block SketchUp.

Replacing what an approved destination holds is consent to what the caller reviewed. The preview
(`ph_composer.library.export_preview` or `API.export_preflight`, each with `location`) reports
`destination: { exists, state }`; `state` is a SHA-256 of what is there, so a `read` caller learns
whether it changed but never its contents. A replacement needs `replace: true`, that `state` as
`expected_destination` (dispatch refuses `replace` without it as `params.invalid`) and, for a library
export, the preview's `projection_digest`. A library export writes only a `.json` file, so an
approved HBJSON destination refuses it with `library.destination_invalid`. A destination
that changed since refuses with `library.destination_changed` or `export.destination_changed`; a
replacement without consent refuses with `export.replace_required`. The native Save sheet's consent
is given against the file as it is when the user answers.

Three operations take a location today: `ph_composer.library.export_file`,
`ph_composer.library.providers.add_file` and `.providers.add_folder`; the HBJSON export task takes
one too. The path never appears in params or a log, nor in a result or outcome but one: once an HBJSON
export has written its pair, the caller that started the task reads `outcome.value.artifacts` from
`export_status` and `latest_export`, each file's path, SHA-256 and byte size from the bytes the final
verification read, to read the files with its own tools and compare the hash before parsing (a later
export to the same destination replaces them). An HBJSON write the filesystem refuses fails as
`export.failed` in fixed words. Any caller holding the grant may use any approved location (D3a1-05).
A task belongs to the caller that started it: another caller's `export_status` and `cancel_export`
refuse `task.foreign` and its `latest_export` omits the task, so a second token, or an agent asking
about a task the panel started, never sees a path. Every token store write, a revoke or a reset alike,
ends the caller handles of each token no longer live (`access.revoked` from the next call) and answers
its waiting calls as revoked; its running export checks its owner's access and the location again
just before writing and finishes `refused` with `export.revoked` (or the location's refusal), writing
nothing, while a pair already written stays `export.complete`. The dialog acknowledges a revoke with
what the token's exports and changes had done and how many waiting calls were refused.

Panel clients correlate
`file_export.invoke` and `file_export.result` by request id and Model session in a separate result
slot. This operation is separate from the longer-lived HBJSON runtime task below.

`API.export_preflight` requires `read` and returns feature-owned findings and explicit repair actions.
A caller invokes selected repairs through the ordinary `model_write` contract, then revalidates.
`API.start_export`, `export_status`, `cancel_export` and `latest_export` require the separate `export`
grant. A scripted start names an approved save destination as `location` and, to replace a pair,
the state `export_preflight(location:)` reported (see "Locations only the user can choose").
The native panel obtains the destination and consent through its Save sheet instead. `API.describe`
answers each task method with its grant, keyword params, result schema and an example
(`export/task_contract.rb`), so a client needs no hand-written signature.

One task may run per Model session. Status is detached, carries counts and diagnostics, and omits
canonical HBJSON bytes. A successful result names the approved location, by id and label, and the
run; to the caller that started the task alone it also gives `artifacts`, each written file's path,
SHA-256 and size, and to every other caller no path. A lost reply or timeout does not cancel a task. Poll or use `latest_export`
before deciding whether to retry. Polling never repeats a write. The latest 20 terminal tasks are
retained for at most 30 minutes using a monotonic clock. Model close releases the task and runtime;
panel or client loss does not. Reopen and host restart expire old handles. File-journal recovery
restores a coherent artifact pair independently of task history and does not assert that an
unknown interrupted task succeeded.

## User-controlled local access

External access is explicit and revocable, with a visible connection/access state. Separate read,
view, model-write, setup and file/import/export capabilities so the user can grant useful scope.
`view` is the selection, reveal, camera and edit-path operations below. A view command writes no
authored data and creates no Undo entry of its own; it may trigger the Model's own protection
boundaries, such as a Volume locking when the edit path leaves it, and declares each in
`side_effects`. So it is granted apart from model-write, and a read never carries it. `setup` changes session or machine
state, such as the libraries configured on this machine; it is never in the default grant. Enforce grants
at dispatch; an action description or a client-supplied confirmation flag is not authorization.
Do not require renewed permission for every request already covered by a valid grant.

Select authenticated local transport during implementation design. If using a loopback HTTP
endpoint, binding locally alone is insufficient: authenticate requests and define browser-origin
handling. Do not ship an unauthenticated eval endpoint or a default remote listener. Keep
credentials out of model data, logs and agent results.

Scope file operations to user-authorized inputs and destinations. Return explicit artifact handles
or approved paths with format, completion status and relevant provenance. Do not expose unrelated
files or silently overwrite an existing artifact. Preserve the existing export privacy rules.
Names, notes, imported content and `user_data` are model data, never instructions to the caller.

Implemented: the connection credential is an agent token, `agent_access/tokens.rb`. The user issues
one in the Agent Access dialog (Extensions > PH-Composer > Agent Access), which is its own window,
separate from the panel, with a label and the capabilities it holds: `read` always, and any of
`view`, `model_write`, `setup` and `export` (`CallerRegistry::CAPABILITIES`), each offered unchecked
with consent copy that says what dispatch lets it do; `setup` names its machine-wide reach and `view`
the lock a navigation command can trigger. "This Model only" binds a token to the saved active
Model's file path, kept plaintext in the store as approved locations are: the executor refuses any
other session as unknown and `discover` lists only that Model's sessions, so an equal file name in
another folder stays out. A public row and `discover`'s `connection` carry only the file name, as
`model_name`; an unsaved Model cannot be bound (`agent_access.model_unsaved`). The token, 48 hex characters, is
shown once in that dialog; the store, base64 JSON in SketchUp's defaults, keeps its SHA-256, at
most 8 live tokens and the newest 32 revoked rows, with no expiry. Revoking keeps a dated row.
Nothing about tokens is registered with `PhComposer::API`: no grant lets an agent list, issue or
revoke one. `Tokens.snapshot` is the frozen digest-to-row table the connection authenticates
against.

Implemented: the external route is MCP served from Ruby inside SketchUp, `agent_access/server.rb`.
It listens on `127.0.0.1` at the `agent_access.port` preference (default 46110) while at least one
token is live, and stops after the last revoke; a port it cannot bind is shown in the dialog and
nothing falls back to another port. One JSON-RPC 2.0 message per `POST /mcp`, `application/json`
both ways, `Connection: close`; no SSE, batches or `GET` stream (405). In order, before anything
runs: a request read within 5 s, headers at most 16 KiB and a body at most 1 MiB (413), `POST` to
`/mcp` (405, 404), no `Origin` header and a `Host` of `127.0.0.1:<port>` or `localhost:<port>`
(403), `Authorization: Bearer <token>` matching a live token's digest (401), `application/json`
(415), one JSON-RPC request (parse error, invalid request for a batch). Worker threads do only this
and never call Sketchup or UI; the offline stub refuses a host call off the main thread. At most 16
connections are open.

`initialize`, `ping`, `tools/list`, `resources/list` and `prompts/list` are answered on the worker
(`agent_access/mcp.rb`): `initialize` answers the client's revision when it is `2025-11-25` (Claude
Code 2.1.300) or `2025-06-18` (Codex 0.163.0), otherwise the newer, and reports
`serverInfo.version` and `_meta["ph_composer/api"]`. `tools/call` is queued for the main thread,
where a UI-timer pump (50 ms while calls wait, 100 ms idle, ending each tick with a short sleep so
the workers run) hands it to `agent_access/executor.rb`. A token may have 8 calls waiting; a ninth,
a call older than 30 s, or a pump that has not ticked for 10 s is answered `session.busy` by the
worker and never runs. Workers do run while the main thread does long Ruby work; under a native
modal no Ruby thread runs, so the client sees its own tool timeout (measured on 26.1.188).

The executor rechecks the token, validates the arguments against the tool's fixed schema, and makes
the one API call the tool names (`agent_access/tools.rb`, the allowlist). A token acts on a session
through one caller handle from `API.connect` with the token's capabilities, kept while both live.
The tools are the API verbs: `discover` (a compact index of every operation name by kind and owner,
or one owner's full entries), `describe`, `query`, `preview`, `context` and `export_preflight`, all
`read`; `invoke` and `outcome` (`model_write`); `view`; `setup`; and `export_file`, `start_export`,
`export_status`, `cancel_export` and `latest_export` (`export`). `tools/list` shows a token only the
tools its capabilities reach, and the executor refuses the rest as unknown. An agent never counts
sequences: per token and session (`agent_access/sequencer.rb`) each `invoke` takes the next integer,
and an optional `idempotency_key` (at most 64 characters) keeps the sequence it was first given, so a
repeated key goes through the retained-outcome path as the same sequence: the same request answers
its first outcome, another conflicts (`request.sequence_conflict`), and one whose outcome has expired
is `request.outcome_unavailable` and is never given a new sequence. Every `invoke` and `outcome`
result carries `sequence`, an optional field of the published Outcome schema that only this route
sets; `outcome` takes a sequence or a key. A lost reply is recovered by reading state: `outcome` for
an invoke, the setup's own read (such as `ph_composer.library.providers`) for a setup command,
`latest_export` for a started export, and the `context` read for a path change. A client's
`notifications/cancelled` is accepted and changes nothing: a call already handed to SketchUp runs to
its outcome, all or nothing, and is never reported as a rollback. A change whose outcome is over the
reply budget is never reported as refused: it keeps its status, code, effect, revision and
sequence and drops `value`, `affected` and `findings` (`detail.omitted` names them), and the caller
reads the records back. Bindings live in `AgentAccess.bindings`, not the transport, so keys and
sequences survive a listener restart on another port; a token revoked while its call waited answers
`access.revoked` and its bindings are dropped.
A result is the API's answer as `structuredContent` with one line of text in `content`: Claude Code
shows its model only `structuredContent`, and Codex shows both, so a second JSON copy would count
twice. Every Outcome, refusals included, is an ordinary result; `isError` marks an unknown tool,
arguments outside the schema, a revoked token or a result over 24 KB of `structuredContent`
(`request.response_too_large`, never truncated). Claude Code 2.1.300 saved a 60 KiB result to a file
instead of showing it, and Codex 0.163.0 kept about 10,000 tokens of a larger one. A bounded ring of
recent calls (tool, operation name, session, status, code, time; no params, value, path or token)
is flushed to the diagnostics log.

Implemented: client configuration, `agent_access/client_config.rb`. When a token is issued the
dialog shows three forms per client, with the token in them, ordered so the first keeps the token out
of the client's settings, the second sets the variable it reads and the last writes the token into the
client's settings; each title says where the token is kept. Claude Code: a `claude mcp add-json` form whose header reads `${PH_COMPOSER_TOKEN}`, expanded
when it connects (2.1.300: connected with the variable set, failed without), then the `export` line,
then `claude mcp add --transport http --scope user ph-composer <url> --header "Authorization: Bearer
<token>"`. Codex: a `[mcp_servers.ph-composer]` block for `~/.codex/config.toml` with
`bearer_token_env_var = "PH_COMPOSER_TOKEN"`, then the `export` line, then the same block with the
token inline in `http_headers`. Codex's own `codex mcp
add` and `remove` rewrite the whole config file, dropping comments and reordering tables (0.163.0),
so the block is pasted by hand. Both clients connected from these snippets alone and ran a
`discover` and a `query` headless (`claude -p`, `codex exec`) on the proving host. The
`agent_access.port` preference changes from the dialog when the port is taken, which a stopped
listener checks as well, and New token waits for a free port; each token's latest call since launch
is kept per token, apart from the recent-call ring, and shown beside it as calls finish.

Keep a bounded operation history with caller identity, action, target references, outcome and
revision for diagnosis. Avoid full payload or secret logging. Exact retention and user-visible
controls remain design choices.

### Security posture

Decided and implemented; a change to any of these is a security decision, not a refactor.

- The listener binds 127.0.0.1 only. There is no TLS: loopback traffic cannot be read without root,
  and a certificate would add handling for no gain.
- Every request carrying an `Origin` header is refused, and the `Host` must name the loopback
  address or `localhost` with the listener's port. No browser-based client can connect and no
  cross-site or rebound request reaches the endpoint; the supported clients are native processes.
- The store keeps only each token's SHA-256. PH-Composer shows the secret once, in the issuing
  dialog; a copy the user makes for a client is the user's. Tokens do not expire; revocation is
  explicit, and the most recently revoked tokens stay listed with their dates.
- The port is fixed per preference. On a computer with several accounts, another account can bind it
  while SketchUp is not listening and receive the token from an agent that connects then. The user
  documentation tells users of such a computer to revoke tokens when they finish. Binding a grant to
  a named connection is the agent connection and access-grant work's, and needs a client-side
  component neither supported client has.
- Any caller holding a grant may use any approved location. A path reaches a caller only as the
  written export pair, and only the caller that started the task.
- The Model's own file path is answered by the context read. It is the user's document, not an
  approved destination.
- The development bridge in `tools/hostkit/` never ships. Its state file, which holds its token, and
  its console log are readable by their owner only, and the release checklist in
  `docs/DEVELOPMENT.md` removes it from the build machine.

## Documentation and contributor obligations

Maintain one vendor-neutral quickstart, generated API/schema reference and synthetic examples.
Document discover, inspect, propose, apply and verify as one worked workflow, including conflict
recovery and a lost-response retry. Provide concise installation and connection diagnostics.
Client-specific configuration examples point to the same contract and state their tested versions.
An optional operating skill for users' agents should be written against working APIs when they
land; the repository architecture-review skill is for development and is not that operating guide.

For each feature, identify supported programmatic reads and writes. If an operation requires
interactive geometry picking, document that limitation and the plan for an explicit-reference
equivalent where feasible. Core data edits must not require UI scraping or arbitrary eval.

Thermal bridges need no picking. `ph_composer.thermal_bridges.types.list` and `schedule.list` are the
bounded reads (`types.all` and `schedule.all` their whole forms, for the panel), and `edges.selection`
reads the native selection as explicit Edge references with each one's Zone and write refusal.
`edges.assign` and `edges.clear` write explicit references, one Undo step each, refusing as a whole
past 250 Edges. The right-click "Thermal bridge" menu and the edge tool are pointer routes; their
explicit-reference equivalent is `edges.assign`. `runs.locate` shows a run's or a finding's Edges;
`export_preflight` lists every finding before export, against the placed Windows' outlines that
`ph_composer.windows.units.outlines` reads. [AGENT_GUIDE](../docs/AGENT_GUIDE.md), "Thermal Bridge
Types", is the recipe.

Zones exposes native split identity recovery as `ph_composer.zones.repair_split_face`. The native
Repair menu and [synthetic scripting client](../tools/examples/authoring/split_identity_walkthrough.rb)
use the same preview and invocation contract. Stored endpoint proof or an explicit retaining path
chooses the keeper; reads never repair duplicate identities. Invocation carries the reviewed
preview revision and digest. Supported payloads follow declared copy rules; unsafe data refuses
before writes. [Phase 1 evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-split-identity-recovery.md)
records the implemented scope and remaining reference/solver boundaries.

The `zones` feature exposes `ph_composer.zones.faces.attached_zone.create_and_assign` for one
atomic definition-and-assignment operation. It takes explicit Face references and record values,
with optional Face type intent and expected values, and returns the new record ID and assigned
Face IDs. The Zones / Faces inline dialog uses that public operation; scripts can preview and invoke
it with the panel closed. [Current-host evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-attached-zone-atomic.md)
records validation, exact rollback and persistence checks.

Phase 2 features, programmatic reads and writes. Each has a panel-closed walkthrough under
`tools/examples/`.

- **Assemblies** (`ph_composer.assemblies.*`). Reads: `materials.list`, `assemblies.list` (with
  thickness, U-values or the reason they are withheld, and row findings) and `export_preflight`.
  Writes: create, update, duplicate and delete for Materials and Assemblies, delete taking an
  optional replacement; one action per Builder gesture under `assemblies.layers.*` and
  `assemblies.segments.*`, each naming its Layer and Layer-Segment explicitly. Nothing requires
  picking. [Walkthrough](../tools/examples/authoring/assemblies_walkthrough.rb).
- **Face assignment** (`ph_composer.zones.faces.*`). `assign_assembly` sets or clears the
  Assembly on explicit Face references with expected values; `classify` takes the same
  `assembly_id` intent. `assembly_usage` and `assembly_choices` are reads. Deleting an Assembly
  with a replacement rewrites Face references in the same action. The Classify tool and
  `choose` are pointer routes to the same actions.
  [Walkthrough](../tools/examples/authoring/assembly_assignment_walkthrough.rb).
- **Windows** (`ph_composer.windows.*`). Reads: product, Type and Unit lists, `settings.get`,
  `units.glazed_area_by_face` and `export_preflight`. Writes: product and Type create, update,
  duplicate and delete; Type grid gestures under `types.grid.*`; per-edge installs through the
  batch `types.installs.save`; `settings.update`; and Unit `place`, `remove`, `rehost`,
  `swap_type`, `reset_to_type`, `restore` and `new_flipped_type`. `units.place` takes an explicit
  host Face reference, anchor and offsets in metres, so the Place tool's picking has an
  explicit-reference equivalent. A native copy of a Unit shares its identity until repaired:
  `units.repair_copied_identities` takes explicit Unit references and gives the copies sharing
  their identities new ones, with a preview listing each old and new id, and the
  `window.copy_id_pending` finding names it as its repair. Each Unit finding's `repair` is that
  operation's name and params for the Window, or null. Every other Windows action makes the same
  repair over every copy first, and says so in its `side_effects`.
  [Walkthrough](../tools/examples/authoring/windows_walkthrough.rb),
  [placement](../tools/examples/authoring/windows_placement_walkthrough.rb).
- **Library** (`ph_composer.library.*`). Reads: `providers`, `providers.setup_state`, `catalog`,
  `in_file` and `export_preview`. Writes: `copy`, with preview, an explicit choice and optional
  assignment, and the `copy_into_proposal` participant for a feature's own action. The setup command
  `load` reads a configured provider into the session catalog and `providers.remove` removes one,
  both under the `setup` grant. When `providers.setup_state` reports this machine's stored setup
  `unreadable`, adding or removing a provider refuses with `library.setup_unreadable` until
  `providers.reset` clears it. Adding a provider (`providers.add_file`, `providers.add_folder`) and `export_file`
  need a location only the user can choose: the panel and the Libraries menu ask for it, and any
  other caller passes the id of a location the user approved (see "Locations only the user can
  choose"). `export_preview` with `location` reports what that destination holds.
  [Walkthrough](../tools/examples/library/materials_walkthrough.rb),
  [approved locations](../tools/examples/library/approved_location_walkthrough.rb).

Discovery also lists read-only `reference_targets`; description returns their descriptor: ID, owner,
label, schema version, values schema, occurrence-reference schema and declared core references.
Every registered operation publishes specific params and result schemas and at least one worked
example. [`docs/API_REFERENCE.md`](../docs/API_REFERENCE.md) is generated from the registrations by
`make fixtures` and checked by the offline suite; [`docs/API_QUICKSTART.md`](../docs/API_QUICKSTART.md)
is the public walkthrough a synthetic client test runs as written.
Registered extensions can name `ph_composer.zones.zone` and `ph_composer.zones.faces.face`.
Contributors resolve those identities through the shared record engine while the owning features
retain entity writes. [The contract](EXTENSIBILITY.md#entity-owned-reference-targets) defines typed
proposal projections and incoming-reference handling; [native evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-entity-reference-targets.md)
records actual copy/split/Solve targets; the independent review of that work passed (see the
[Phase 1 acceptance register](../planning/archive/phase-01-faces-and-zones/ACCEPTANCE.md)).

## Delivery and acceptance

Ed confirmed the delivery split during Phase 0 planning on 2026-09-18. Phase 0 establishes the
shared programming interface and a synthetic client that discovers operations, reads records,
performs validated writes and reads back results with the panel closed. Its acceptance includes
stale-request rejection and native Undo. Phase 0 ships no external adapter and makes no claim
that users' agents can connect.

The user-facing connection belongs to a separate delivery packet, including transport, packaging
and connection/access controls. Its milestone remains to be scheduled. This split does not select
MCP or authorize implementation of either part.

Foundation design establishes the transport-independent query/action contracts and tests a
synthetic feature with the panel closed. Feature implementations carry their schemas and examples
as they land. Select and package the external adapter in an owning plan before claiming users can
connect; this document does not authorize a new server or an implementation phase.

Required evidence for the implemented interface includes:

- A synthetic client discovers a new feature, reads its data and performs a validated write using
  only public contracts. The adapter needs no feature-specific changes.
- UI, script and external calls produce equivalent domain outcomes and validation failures.
- Stale revisions, wrong sessions, revoked access and duplicate retries behave as documented.
- Two clients and a concurrent user edit cannot silently overwrite one another; lifecycle tests
  cover model close/reopen, active edit paths, modal conflicts and queued work.
- Native Undo/Redo and save/reopen preserve values, metadata and references in a fresh host.
- Long-operation timeout, cancellation and result retrieval do not misreport model or artifact state.
- A visual capture is tied to the inspected model state; unsupported capture is explicit.
- A reference adapter is exercised by at least two independently implemented clients before any
  cross-client support claim. Report exact tested clients, host versions and remaining limitations.

## Sources and open choices

Reviewed 2026-09-18:

- [Claude Bridge repository](https://github.com/lairdubois/lairdubois-claude-bridge-sketchup-extension)
  describes a development-only local HTTP Ruby evaluation server and explicitly excludes end-user
  distribution. It is useful prior art for host access, not our supported public operation contract.
- [MCP architecture](https://modelcontextprotocol.io/docs/2026-07-28/learn/architecture) describes
  discovery, tools, resources and transport separation. These support the adapter recommendation;
  they do not settle our application semantics or prove SketchUp compatibility.

Before implementation, decide the local transport/companion packaging, supported protocol versions,
access-grant UX, revision and idempotency lifetimes, task persistence, capture capabilities and
delivery owner. Do not treat the MCP recommendation as an approved dependency selection.
