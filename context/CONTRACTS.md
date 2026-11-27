# Core contracts

These contracts govern registration, public operations and Model persistence. Code and tests
cite the owning section by name.

For contributor boundaries, see [Contributor architecture](EXTENSIBILITY.md). For the MCP
adapter, see [Agent interface](AGENT_INTERFACE.md). For the runtime and host behavior, see
[Technical architecture](TECH_STACK.md).

## Registration

One feature entrypoint, `install(registry)`, supplies versioned declarations. The composition
root (`extension.rb`) lists features explicitly; there is no dynamic loader.

| Declaration | Required shape |
| --- | --- |
| Feature | Stable namespaced id, contract version, declared feature dependencies, install entrypoint |
| Record kind | Kind id, schema version, validator, SI field descriptors, declared references, persistence adapter |
| Query, action, view command, setup command, FileExport | Namespaced id, description, input and result schemas, examples, refusal codes (`refuses`), handler |
| Action additions | Side effects, confirmation policy (only `none` today), Undo name, `transitions:` (the transitions of its own feature it emits through `request.contribute_transition`) |
| Optional terms | `preconditions:` on actions and commands, sentences a caller reads; `side_effects:` on a view command that can trigger a protection boundary; `response:` on a query that answers the whole Model, naming its bounded alternative |
| Menu item | Label, menu, availability test supplied by the owning feature, handler; or a per-session entries provider. `in_setup:` and `summary:` also list it in the Setup view ([EXTENSIBILITY](EXTENSIBILITY.md#setup-entries)) |
| Snapshot section | Owner id, query-backed projection |
| Export contributor | Owner, section name and version, `contract` callback, optional `preflight` query, result fields, `report` callback, `user_data_keys`, `requires` (sections it reads), optional `projection`, `entity_projections` (claims on another feature's entity payloads) |
| Proposal participant | Namespaced id, description, params and result schemas, examples, refusal codes, the participants it calls, handler; called only through `request.participate` by a declaration that lists it |
| Participant edges | `participants:` on a query, action or participant names each participant its handler calls |
| Reference retargeter | Name, target kind and handler; the owner requires the target owner or owns the target itself |
| Transition contributor | Name, transition, refusal codes and handler; the owner requires the feature that emits the transition, and every step it adds answers `restore` |
| Structured extension | Namespace and version, payload validator, reference and copy declarations, migrations, export relevance |
| Code | A `noun.condition` code under a noun the feature owns, and its description (see "Outcomes and codes") |

The capability an operation needs follows from its kind: a query and a preview need `read`, a view
command `view`, a setup command `setup`, an action and an outcome lookup `model_write`, and a
FileExport or export task `export`. Library loading and provider setup require `setup`.

Prefix a declaration with its feature ID. Prefix a refusal code with a noun its feature owns. A feature id, declared name, wire kind or code is at most `Registry::ID_MAX_BYTES`
(1,024 bytes, ASCII) and a longer one is `registration.schema_invalid`, so a discover row, which never
cuts an identifier, fits one agent reply (the arithmetic is in context/AGENT_INTERFACE.md, "Discover
before acting"). Registrations are staged and validated together:
duplicate ids, missing dependencies, cycles, incompatible contract majors, invalid schemas and
invalid examples each produce a `registration.*` diagnostic naming the owner and, where one is
missing, the dependency. Any diagnostic refuses the whole batch and publishes nothing; the last
registration never silently wins. Repeated install adds no duplicate observers.

A record kind's store is admitted during validation. It must answer the five methods the engine
calls, `dictionary`, `ids`, `read`, `write` and `delete`, which are checked by presence; only the
`dictionary` getter is called, once, and its answer must be a String starting with `ph_composer.`
followed by a name; that admitted answer is the name publishing registers. A getter that raises is a diagnostic. The default `ph_composer.records.<kind
id>` is not required, so a kind may keep a legacy name.

Publishing cannot leave a batch half published. It prepares everything that could fail first,
writing nothing live, and then commits by assigning into the registry's maps and appending
dictionary names and host subscriptions, none of which can refuse once validation has admitted
them. A failure while preparing is an `InternalError` with nothing published. `Registry.install`
called while another install is staging or publishing, from an `install` or a store getter, raises
`InternalError` and leaves the registry as it was.

A published declaration owns its values. Publishing replaces each value member (names, owners,
descriptions, schemas, examples, refusal lists, Undo names, side effects, snapshot params, export
result fields, `user_data_keys`, `requires`, library adapter schemas and callback schemas, and the
strings of Colour-by modes, menu items, codes, retargeters, participants and subscriptions) with a
deep-frozen copy and freezes the declaration; the owner index `owner_of` reads is built from frozen
copies too. Record kinds, descriptors, extensions and reference
targets keep frozen copies of their ids, labels, prefixes, fields, references and schemas from the
moment they are built. Behaviour (handlers, validators, stores, factories, projections, callbacks
and migrations) is kept by identity and never copied or frozen. A contributor who edits a builder it
kept after install changes nothing published. Reads that hand out schemas (`view_schema`,
`patch_schema`, `to_h`, `API.describe`) return editable detached copies. The registry's maps stay
live Hashes, so readers see an additive install on their next lookup.

The guarantee covers what the registry owns. An `install` that raises is a diagnostic and publishes
nothing, but side effects it caused outside the registry before raising are not undone.

During installation, `registry.record_descriptor(kind_id)` resolves a same-batch catalog kind or
entity target, then an already installed kind or target, returning its descriptor or nil. A feature
may copy a dependency's public occurrence schema into its declarations without reaching through
the dependency's implementation constants. This grants no storage access and does not replace the
declared dependency requirement or batch validation.

Contract versions use exact major compatibility. Until the first public release the public API
changes freely under major 1: every shape change, additive or not, bumps `API::MINOR` once and adds
one row to `API::CHANGES`, which the generated reference lists under "API changes"; `discover` and
the agent connection's `initialize` report the minor. The release gate freezes shapes; after it a
reshape is a major bump. Unknown fields in operation envelopes are rejected; record `user_data` remains intentionally extensible. Declarative schemas drive Ruby
validation, discovery and the generated `docs/API_REFERENCE.md`; there is no second hand-maintained
catalog. The shell renders declared menu placements and never branches on a feature's entities.

Translation sections are not declared through `install(registry)`. The Python translation package
lists them explicitly in `composition.py`; see "Translation sections and artifacts".

## Public interface

`PhComposer::API` is the one application interface. The panel, native menus, scripts and agents
are clients of it.

- `discover`: versions, open Model sessions, every operation's name, owner and description, and the
  common refusal sets (see "Outcomes and codes").
- `describe(name:)`: one operation's schemas, examples and refusal codes, as a detached copy.
  Schemas come only from here.
- `connect(session_id:, capabilities:)`: an explicit context for one Model session. Capabilities
  default to `read`, `view` and `model_write`; `setup` and `export` are granted explicitly.
- `query(context:, name:, params:)`: a bounded read returning values, never live SketchUp objects.
- `preview(context:, name:, params:, within: nil)`: builds and validates an action's proposal without
  writing, and returns its `proposal_digest`. With `within`, a byte budget, a larger completed preview
  answers compact: status, revision and `proposal_digest` kept, `value`, `affected` and `findings` left
  out and each one's size and SHA-256 (and count) in `detail.parts` (`shell/preview_parts.rb`).
- `preview_part(context:, name:, part:, params:, cursor:)`: one of those parts as canonical JSON text in
  fragments, the preview run again for each; the cursor binds the action, params, part, revision and
  proposal digest. Nothing is retained or held open between fragments.
- `view(context:, name:, params:)`: a view command that changes what the host shows. It writes no
  authored data and leaves no Undo entry of its own, so it takes no request; it may trigger the
  Model's own protection boundaries, which the command declares in `side_effects`.
- `setup(context:, name:, params:)`: a setup command that changes session or machine state, such
  as the libraries configured on this machine, and never the Model. No request, no Undo entry.
- `invoke(context:, name:, params:, request:)`: a validated synchronous mutation.
- `outcome(context:, request:)`: a retained mutation outcome, without rerunning it.
- `outcomes(context:, limit:, cursor:, keys:)`: this caller's own retained outcomes, newest first, one
  bounded page, each row a summary without value or params (`shell/outcome_history.rb`). `keys`, the
  caller's own names for its sequences, come back on their rows. Needs `model_write`, as `outcome` does.
- `export_file(context:, name:, params:)`: a registered synchronous FileExport, with an explicit
  `export` grant. It has no mutation sequence and opens no Model operation. Its owner performs the
  guarded file write. A FileExport or setup command that declares an `approval` needs a location
  only the user can choose. Through this interface the caller passes `location`, the id of a
  location the user approved (`ph_composer.locations.list`), or is refused with
  `access.user_required`; the panel and native menus ask the user instead.
- The export task methods (`export_preflight`, `start_export`, `export_status`, `cancel_export`,
  `latest_export`) are specified in AGENT_INTERFACE.md, "Implemented export task contract".

The context is a typed value: API major, Model session id, caller handle and capabilities.
Serialized input cannot grant capabilities. The session keeps its own frozen copy of the granted
capabilities, and the session id and caller handle are frozen when minted, so editing the Array
passed to `connect` or a returned value changes no grant or lookup. Nothing defaults to
`Sketchup.active_model` or the selection: a client that acts on the selection reads it through a
query first and then sends explicit references.

The external route is the agent listener (AGENT_INTERFACE.md, "User-controlled local access"): a
loopback MCP server whose tools each make one of these calls on the main thread, through a caller
handle `connect` issued with the token's capabilities. It adds no operation and no authority of its
own; dispatch enforces the grants as for any caller.

The `request` envelope holds exactly `sequence`, `expected_revision` and an optional
`proposal_digest` from a preview. Mutations also carry explicit targets and any feature-specific
expected values.

List queries filter by id and path, project `fields`, order by a stable key and page: default 100,
maximum 500, otherwise `query.limit_invalid`. A cursor answers only the same session, query, filter
and revision: an expired one is `query.cursor_expired`, one this query did not issue is
`params.invalid`. A value larger than a reply is read exactly in fragments (`shell/fragments.rb`): its
canonical JSON text cut into whole UTF-8 characters, each fragment with its byte offset and the whole
text's size and SHA-256, behind the same cursor binding, so a changed value refuses instead of joining two
versions. Every detail read names its value by a path into one public view (`Fragments.detail`), never an
arbitrary dictionary. Discovery and descriptions are detached copies. A query or preview that fails
unexpectedly answers `failed`, code `operation.failed`, effect `none`.

Dispatch presents nothing: it returns the outcome, and the calling client shows the message.
Internal diagnostic details go to the log; an unexpected exception's message is never returned.
An unexpected failure's outcome carries `detail.incident`, a short reference (`PHC-` and six hex
digits) naming its log record, and `detail.error_class`, the error's class name. It identifies
evidence and grants nothing. A declared refusal's own
code and structured detail are never replaced by it.

## Diagnostic log

`core/diagnostics.rb` writes one JSON line per event to the extension's log folder: 512 KiB plus
one archive, events older than seven days pruned from both at load by their timestamps. Every line carries `timestamp`,
`schema` (1, raised when a field's meaning changes), `event`, `extension_version` and `build`
(`core/build_identity.rb`: the package digest from the RBZ's `build.json`, `development` in a
source checkout, `unavailable` when the record cannot be trusted). The load record
`extension_loaded` adds the runtime `manifest` digest; `extension_load_failed` records a load or
composition failure before SketchUp reports it, and composition does not continue. When the logger
itself fails to load, `PhComposer.bootstrap_record` writes that line with the error class alone.

| Field | Accepts |
| --- | --- |
| `event`, `operation`, `stage`, `code`, `effect`, `status` | A declared name (`a-z`, digits, `_`, dotted, at most 96 characters), never request text or a record label |
| `severity` | `info`, `warning`, `error` |
| `error_class` | An exception class name; never its message |
| `frames` | At most 20 `{file, line, method}`; the file is one the extension ships, named from the folder holding the loader (`ph_composer/shell/panel.rb`, `html/panel.js`, `ph_composer_translation/entry.py`); another plugin's file or a traversal is never a frame; every dotted part of the method is a whole word in that file or a runtime marker such as `<anonymous>`, else the method is `?`; a frame in a file it does not own is left out |
| `incident`, `session`, `request`, `run_id`, `build`, `manifest` | Each in the exact form the extension generates: `PHC-` and six hex digits, a session UUID, `<session>:<label>:<n>` with the panel view's code label, `export_` and 24 hex digits, 12 hex digits (or `development`, `unavailable`) |
| `sketchup_version`, `extension_version` | A version string of at most 32 `[A-Za-z0-9_.+-]` |
| `duration_ms` | A finite number |

An unknown key or an unaccepted value raises in strict mode (the offline suite) and is dropped or
replaced by `[INVALID]` otherwise; a dropped key is echoed only when it looks like a field name. No
field takes free text, so every line fits in 8 KiB; a line that somehow would not loses its frames,
then every field but its identity. Values from a page or the runtime pass `Diagnostics.accepted`,
which keeps only accepted values; names a client supplies are kept only when declared (an agent's
tool and operation; a panel section as the registered feature that owns it; a page error class only
as one of the language's own error types, else `Error` or `NotAnError`). Panel messages log
under the session and request they served (`Diagnostics.with_context`); an export carries that
context and its `run_id` into every later timer and runtime callback. The panel reports a section
that failed to render, an uncaught error, a rejected promise and a load its Content-Security-Policy
blocked (class `SecurityPolicyViolation`, no frames) as `panel.diagnostic`, at most 20
per page load, with frames read only from stack lines after the error's own message. A runtime
failure is described by the translation package from the exception's class and traceback
(`entry.failure_report`), never its message, and keeps its stage, code, class and package frames in
`export_runtime_failed`; the outcome keeps a declared runtime
code and a fixed message. A write failure is kept as the log's health (`Diagnostics.health`) and
every line also enters a 256 KiB in-memory tail (`Diagnostics.tail`); neither is logged through the
logger. `Diagnostics.tail_window` is the tail with the number of its first line: lines remembered in a
process are numbered from 0 and never renumbered, so a reader resuming after a line can tell when the lines
after it were evicted or cleared. Developer tools read the same file or this projection, through
`Diagnostics.sanitized`, and never the logger's instance variables.

## Outcomes and codes

Every query, preview and operation answers with one envelope:

```json
{ "status": "completed", "code": "ok", "message": "...", "effect": "committed", "revision": 7,
  "value": {}, "affected": [{ "kind": "...", "id": "...", "change": "updated" }],
  "findings": [], "detail": null, "proposal_digest": null }
```

Fields are nested and named; a handler's value never merges into the envelope.

| `status` | Meaning | Allowed `effect` |
| --- | --- | --- |
| `completed` | The operation ran; a no-change edit completes with no Undo entry. Code `ok` | `committed`, `none` |
| `refused` | Rejected before any transaction: validation, stale state, wrong session, missing capability | `none` |
| `failed` | An unexpected error. `none` when it came before any operation opened | `rolled_back` (verified), `unknown`, `none` |
| `busy` | Host state prevents safe execution now; inspect state before retrying | `none` |
| `pending` | A retry of a request that is still running | `none` |
| `cancelled` | The user or caller cancelled before anything was written | `none` |

A refused mutation's message ends with "Nothing was written."; a refused read does not. A verified
rollback says that no changes were retained. `effect: unknown` means an abort ran but the
unchanged-data check failed or could not run, so the message cannot confirm that nothing changed.

Codes are stable `noun.condition` strings, one per outcome:

| Area | Codes |
| --- | --- |
| Envelope | `request.malformed`, `request.unknown_operation`, `request.api_version`, `request.capability_denied`, `request.response_too_large` (an agent tool result over the reply budget, refused rather than cut) |
| Access | `access.user_required` (the operation needs a location only the user can choose), `access.revoked` (the caller's access was revoked; nothing ran), `request.cancelled` (the user dismissed that dialog) |
| Approved locations | `location.unknown`, `location.revoked`, `location.used` (a single-use location already added its library), `location.kind_mismatch`, `location.unavailable` (no longer there as approved), `location.setup_unreadable`, `location.setup_unavailable` |
| Retry | `request.pending`, `request.sequence_conflict`, `request.outcome_unavailable`, `request.not_received` (the panel's Check status named a request the host never received; nothing ran) |
| Session | `session.unknown` (closed, reopened or never issued), `session.busy`, `session.closed`, `session.changed` (a native menu built for another Model), `session.inactive` (the panel's Model is no longer shown, or a view command asked to move the edit path of a Model SketchUp is not showing) |
| Preconditions | `revision.stale`, `proposal.changed`, `record.unreadable` |
| Proposal contributions | `proposal.foreign_write` (a participant or library callback staged a write to a kind its owner does not own, or into another change set), `proposal.contribution_replaced` (it removed or changed what an earlier contributor proposed) |
| Targets | `target.not_found`, `target.changed`, `target.ambiguous`, `target.locked`, `target.wrong_kind`, `target.wrong_hierarchy`, `target.wrong_zone`, `target.same_zone`, `target.shared_definition`, `target.edit_path_changed`, `target.foreign_records` (erasing or exploding the target would take another owner's records with it) |
| Validation | `params.invalid`, `validation.failed`, `reference.invalid`, `reference.in_use`, `geometry.invalid`, `geometry.failed`, `geometry.split_failed` |
| Extension data | `extension.unavailable`, `extension.schema_unsupported`, `extension.migration_required`, `extension.migration_failed`, `extension.invalid`, `copy.rule_missing` |
| Query | `query.limit_invalid`, `query.cursor_expired` |
| Operation | `operation.failed`, `operation.rollback_unverified`, `operation.participant_missing`, `operation.proposal_required`, `operation.query_missing`, `operation.dependency_missing`, `operation.query_cycle`, `operation.locate_missing`, `operation.participant_cycle` |
| Identity and scope | `identity.conflict`, `identity.choice_required`, `identity.choice_conflicts`, `scope.incomplete`, `selection.invalid` |
| Registration | `registration.duplicate_id`, `registration.missing_dependency`, `registration.cycle`, `registration.contract_major`, `registration.schema_invalid` |
| Translation | `payload.contract`, `section.missing_dependency`, `section.cycle`, `section.duplicate`, `section.version_unsupported`, `object.unavailable`, `dependency.unavailable` |
| Export | `export.blocked`, `export.busy`, `export.cancelled`, `export.failed`, `export.refused`, `export.model_changed`, `export.destination_changed`, `export.replace_required`, `export.privacy_undeclared`, `export.relevance_unknown`, `export.metadata_omitted` (a finding), `export.user_data_passed` (a finding: how many HBJSON objects of each type carry a user's user_data), `export.revoked` (the access that started the task was revoked before it wrote anything), `task.expired`, `task.foreign` (another caller started that task), `task.running` (a part read of a task that has not ended), `artifact.none` (a file part of a task that wrote no file), `artifact.changed` (a file part whose file no longer hashes to its receipt) |
| Library | `library.adapter_invalid`, `library.assignment_unavailable`, `library.callback_invalid`, `library.catalog_budget`, `library.catalog_stale`, `library.catalog_too_large`, `library.catalog_too_many_rows`, `library.connection_changed`, `library.connection_required`, `library.credential_store_failed`, `library.credential_store_unavailable`, `library.dependency_missing`, `library.destination_changed`, `library.destination_invalid`, `library.export_write_failed`, `library.file_malformed`, `library.file_too_large`, `library.file_unreadable`, `library.format_invalid`, `library.kind_unavailable`, `library.lifecycle_unavailable`, `library.load_timeout`, `library.local_choice_required`, `library.model_changed`, `library.provider_ambiguous`, `library.provider_failed`, `library.provider_invalid`, `library.provider_unavailable`, `library.reauthorization_required`, `library.reload_required`, `library.review_required`, `library.row_semantic_invalid`, `library.row_unavailable`, `library.schema_unsupported`, `library.selection_changed`, `library.setup_invalid`, `library.setup_too_large`, `library.setup_unavailable`, `library.setup_unreadable`, `library.source_revision_invalid`, `library.update_destination_invalid`, `library.update_destination_required`, `library.use_expired`. Catalog notes are listed in "Library providers and catalogs" |
| Runtime | `runtime.asset_refused`, `runtime.boot_timeout`, `runtime.boot_failed`, `runtime.translation_failed`, `runtime.stopped`, `runtime.closed`, `runtime.unresponsive` (a ready runtime sent nothing within the export task's silence deadline), `runtime.conformance_failed` (the canonical HBJSON did not reconcile with the result) |

Shared nouns (`request`, `session`, `revision`, `proposal`, `target`, `params`, `validation`,
`reference`, `geometry`, `query`, `operation`, `selection`, `scope`, `identity`) mean the same
thing wherever they appear; a feature uses them for those conditions. A condition only one feature
can have takes that feature's noun (for example `zone.*`, `face.*`, `adjacency.*`, `gesture.*`,
`window.*`). This table lists foundation codes, the codes of the `ph_composer.library`
foundation feature, and shared-noun codes a feature raises. A feature declares each code under its
own nouns with `feature.code(code, description:)`; registration refuses a malformed code, a repeat,
a noun another feature owns and a noun this table uses (`Declarations::FOUNDATION_CODE_NOUNS`), and `docs/API_REFERENCE.md` lists them by feature under "Feature
codes". One condition has one code from every read, refusal and preflight that reports it. Add a
foundation code here before a caller relies on it; `tests/outcome_codes_test.rb` fails when feature,
library or translation source names a code that is neither listed here nor declared.

Every operation declares `refuses:`, the codes its handler and the dependencies it calls can
answer with an outcome that is not `completed`: reads, locators, participants and retargeters
included, since their codes reach the caller unchanged. Codes a caller sees as findings on a
completed outcome are not refusals, and neither is a domain cause a step raises while the operation
applies: that answers `operation.failed` or `operation.rollback_unverified`, with the cause in
`detail.cause`. Codes dispatch answers for every operation of a kind are not
repeated: `Refusals::COMMON` (`shell/refusals.rb`) holds one set per kind (`query`, `action`,
`view_command`, `setup_command`, `file_export`) and an `approval` set that an operation declaring an
approval also answers. `refuses: []` says the operation answers nothing beyond its common sets.
Registration refuses an entry that is neither listed here nor declared by the operation's feature or
one it requires, a repeat, a common code, and a code only dispatch gives (`request.unknown_operation`
and the `approval` set). Refusal metadata always has `code`, `owner` and `description`;
foundation descriptions are null. `discover.refusal_documentation` links to this section instead
of duplicating foundation descriptions in code. `Declarations::FOUNDATION_CODES` is the checked
mirror of this table, and
`tests/outcome_codes_test.rb` keeps the two equal. `discover` publishes the common sets once as
`common_refusals`; `describe` returns an operation's own codes as `refuses` with that uniform metadata,
and the sets it answers as `common_refusal_sets`. A refusal
outside an operation's declared and common codes is a defect: dispatch reports every refusal to
`Refusals.audit`, which production leaves unset and the offline suite fails on.
Library kind local callbacks declare validated `refuses:` lists under their own owner's vocabulary.
The effective list for `ph_composer.library.copy` includes installed kinds' local read, create,
replace and assignment callbacks; `ph_composer.library.in_file` includes local read only. Discovery,
the generated reference and the offline audit share this projection, excluding duplicate and
caller-common codes. The foundation coordinates the calls without naming a receiving feature.

## Revisions, transactions and host execution

Each open Model session has a random session id and one integer revision, 1 at creation and
compared for equality only. It advances on a committed mutation, an external commit, native Undo
and Redo, and an edit-path change. Display preferences do not advance it. A whole-Model revision is
deliberately conservative: an unrelated edit may invalidate a proposal. Commit-time reference,
edit-path and value checks still run when the revision matches.

SketchUp reports an outside script's operation on a Model it is not showing, and that Model's edit-path
changes, to the shown Model's observers and never to the Model changed (`context/SKETCHUP_HOST_BEHAVIOR.md`).
A commit callback that arrives while a session is inside its own operation is that session's; no
PH-Composer operation owns any other. With one Model open, an unowned commit is that Model's. With more than
one open, it advances every open session's revision: an agent then meets a spurious `revision.stale`, never
a write on a stale read. A session whose own change's commit callback is still to come takes the first
unowned commit as that callback instead, so a late callback leaves no count behind to swallow a later
change. Only the session of the Model SketchUp names hears the commit as a host event, with its export
generation, deferred work and panel refresh; the others get the revision alone. So an edit of the shown
Model does not abort another Model's export, and an outside change to a Model during its own export is not
detected by the export. Zone names, container watching and a Colour-by drawing on the others catch up when
SketchUp next shows them (`model_activated`). Undo and Redo callbacks outside an
own operation stay with the named Model: native Undo and Redo act on the shown Model only, and their
subscribers rebaseline state that a Model which did not revert must keep.

Dispatch runs only on the host-safe execution boundary and serializes mutations. A modal tool,
Model transition or unsettled session refuses at once as `busy`; there is no durable queue of
edits, and a scheduled callback revalidates when it runs. A native gesture a commit would cancel, measured
for Move (click-move and held drag) and Scale (click-move) partway through, refuses changes alone as `busy` (`ModelSession#gesture_reason`); reads still run.
Rotate reports no state while partway, so the Rotate tool selected at all refuses changes the same way.

Validate the whole change set before opening the transaction. One operation owns one native Undo
step. Feature helpers join the caller's operation; they never open nested independent operations
or publish intermediate snapshots. On failure, abort, restore observer suppression and verify the
declared scope against its pre-image (see "Compound proposals"). No-change edits add no Undo entry.
A preview is read-only and bound to its inputs and revision; applying it repeats validation and
the same confirmation for every caller. No transaction stays open while waiting for a dialog, a
person or an agent.

## Retries

UI correlation ids are separate from mutation identity. Each client gets a caller handle per
session; its mutations carry strictly increasing integer sequence numbers, with gaps allowed. Two
clients have separate handles.

| Item | Value |
| --- | --- |
| Caller handle | Opaque random string issued per session; invalid after the session ends or a restart |
| Sequence | A sequence at or below the caller's highest accepted one is a retry, never new work |
| Retained outcomes | Up to 256 per session across all handles, oldest evicted first, each for at most 15 minutes |
| Payload binding | Canonical JSON of operation name, params, expected revision and preview digest |
| Acceptance | Refusals before acceptance (malformed envelope, unknown session or caller, revoked caller, unknown operation, missing capability, busy) consume no sequence and are not retained. Everything after acceptance, including `params.invalid` and `revision.stale`, is retained |

The same sequence and payload returns the retained outcome without another transaction; the same
sequence with a different payload is `request.sequence_conflict`, whether the first is running or
complete. A retry of a running request with the same payload answers `pending`. An expired outcome
is `request.outcome_unavailable` and never becomes new work. The store returns detached copies, so a
caller editing a returned outcome cannot change a later lookup. `outcome()` needs `model_write`.
There is no exactly-once claim across a process failure: a lost handle requires fresh discovery
and state inspection. The panel reconciles a lost reply through this same lookup under its original
sequence and never resends the action (TECH_STACK, "Panel protocol").

## Records and extension data

The record engine owns identity and validated persistence. Kind adapters declare reference fields
and target kinds and return proposed edits; they never write raw dictionaries. `user_data` is
JSON-compatible and string-keyed, values are finite, and the API boundary deep-copies. An absent
legacy mapping reads as empty without repairing the stored record.

| Operation | Identity and references | Metadata and extension payload |
| --- | --- | --- |
| Ordinary edit | Preserve identity; validate changed references | Preserve unrelated payload exactly |
| Delete | `after: nil`, reported as `deleted`; every incoming reference is checked first | Removed with the record |
| Duplicate object | New id; shared definitions stay shared | Independent metadata copy, no inferred references |
| Duplicate collection | Allocate all new ids first; remap declared internal references | Apply registered copy rules; an unknown required rule refuses the whole copy |
| Save and reopen | Preserve durable ids and path-qualified reference meaning | Retain unavailable or newer payloads without normalization |
| Read | No repair, allocation or mutation | Report understood, invalid, outdated, unsupported or unavailable separately |
| Migrate | Explicit version path; validate the result before writing | One atomic operation; failure keeps the original |
| Export | Only declared supported fields and references | Claimed payload fields only; `user_data` passes through only where its owner opts in; unknown correctness-relevant payload blocks |

A new id is a kind prefix and twelve characters. A handler's engine derives each id it stages from
the session, the revision, the declaration and a digest of the params, in staging order, skipping any
id already stored or staged (`HandlerRequest.proposal_ids`), so a preview and its invoke at one
revision stage the same ids and the next write's revision derives others. An engine built outside a
handler request, for a read or a repair check, mints random ids.

`propose_duplicate` may receive a block that transforms a detached copy of the authored values
after identity and extension-reference remapping. The returned object replaces authored values
only; reserved identity and metadata keys refuse. The engine validates the transformed schema and
references before the proposal can write. This supports regenerated nested value identities without
letting a feature replace the engine-owned record identity or metadata. Callback exceptions poison the whole proposal, including when the handler rescues them.

`extension_data` is keyed by namespace. Each value carries `schema_version`, `payload`,
`references` (JSON path, target kind, cardinality) and `export_relevance` (`required`,
`local_only` or `unknown`; absent means unknown). A current-version envelope whose payload fails
the installed validator, or whose references differ from the installed declaration, is
`invalid`: kept on unrelated edits, replaceable by valid data, and refused for copy, migration and
export as `extension.invalid`. A payload without a usable declaration blocks operations that could
invalidate its references and blocks export when its relevance is unknown. Never guess from a
payload's text. Native SketchUp copy semantics are feature-owned.

**User data shape and replacement.** Every authored object has one optional `user_data` map: the
Model, every definition, geometry record, assignment and managed option, and every declared record
part. The [user data guide](../docs/USER_DATA.md) is the one coverage table: each object's address,
read, write route, copy behavior, HBJSON mapping and library boundary. A write replaces the whole map:
an update without `user_data` leaves it, `{}` clears it and a map replaces it; nothing merges maps.
Params that are not plain JSON (a non-finite number, a key that is not a string, a Ruby object) never
reach a handler over the public API: the dispatcher refuses them as `request.malformed` before
acceptance, so the sequence stays free. A map that is JSON but not an object fails the operation's
schema as `params.invalid`. The engine's own `params.invalid` for a map that is not plain JSON
(`Records::Metadata.checked_user_data`) answers only a Ruby caller staging through the engine directly.
Creators of Zones, Faces, Spaces and Edge assignments take no `user_data`; the owner's metadata action
follows the create.

**Lifecycle policy.** One policy holds for every object and part. An edit that rebuilds an object
keeps each surviving part's map at every depth. Duplicate makes independent deep copies under the
owner's new ids and never reads a string in a map as a reference. A split copies the source's map into
every piece. A merge, or a delete that names a replacement, keeps the survivor's map, never combines
maps, and returns `removed_user_data`, each removed object or part whose map was not empty with its
top-level keys, `removed_user_data_total` and `removed_user_data_truncated`; Undo restores the removed
map. `Records::Metadata.discard_report` builds every such report, so it fits one agent reply: it lists
at most 50 entries, each with its address and `user_data_key_total`, then fills in their first 50 keys
in order while the rows stay within `REPORT_BYTES` (8 KiB); the flag is true when an entry or a key was
left out. Every catalog delete (Materials,
Assemblies, Frames, Glazings, Psi-Install Types, Window Types, Thermal Bridge Types and Attached zones)
returns the two fields whether or not it names a replacement, empty when nothing was annotated:
`Engine#propose_delete` answers them through `Records::Metadata.removed_user_data`, the record first,
then each part by `id` and `part_ids`. A new part starts without one. A restore
or conversion that cannot recover a map starts it empty. Zone restore lists `user_data` as
unrecoverable in its offer, and Edge repair reports the keys it discards; a Window Unit restored from
orphaned panes, or converted from a plain component, has no record to copy and starts empty without a
notice of its own, which the user data guide states. Deleting an object removes its map, and Undo
restores it.

**Catalog record metadata.** `ph_composer.records.update_metadata` is the one write route for the
`user_data` and extension payloads of an existing catalog record of any kind `records.list` reads
(`Engine#propose_metadata_update`); a kind's own update action edits values only, and create actions
still take `user_data`. Its batch, `expected_metadata`, refusal, one-step Undo and no-op rules are the
entity owners' below, and each target is `{kind, id}`: an unknown kind refuses `params.invalid`, a
missing record `target.not_found`. An internal kind that declares `owner_writes_metadata` (Zone
option settings) refuses `target.wrong_kind`. A kind whose owner keeps copies of its records declares
`metadata_follow_up`, a callable taking the request and the proposal: once every entry is staged, the
action calls each distinct follow-up of the kinds the batch changed, once, under the kind's owner, and
the follow-up adds the owner's dependent steps or refuses the batch. Levels declare one, which
rewrites the choice evidence of every adopted Zone and member stamp in the same Undo step (a locked
one refuses `target.locked`); a Zone awaiting adoption is left as it is. A Building Segment's evidence
carries its values only, so a write of its maps or settings changes the Segment alone and declares
no follow-up. Removing or merging
options keeps the survivor's map and reports each removed option whose map was not empty with its
top-level keys, as merging parts does. Clearing the map of a record stored without one writes nothing.

**Record parts.** A `RecordKind` may declare `parts:`, each a `Records::Part` with a label and a path
of array fields (`layers[]`, `layers[].segments[]`) whose members are objects with a required string
`id`, unique in their parent, and an optional object `user_data`; every shorter path is itself a part,
and registration refuses any other shape. The kind refuses repeated part ids within a parent and validates part maps as it
does the record's, and `describe` lists the parts. A target's `part_ids` names one part by the id path from the record down; an id path no part
matches refuses `target.not_found`. A part takes `user_data` only: its `expected_metadata` reads
`extension_data` as `{}` and `extension_payloads` refuses `params.invalid`. Entries for one record and
its parts in one batch stage as one write. Owners keep a surviving part's map through every edit, copy
it with the part, and start a new part without one. `Engine#propose_update` enforces it for any value
edit that rebuilds parts, such as `windows.types.update` with the whole `elements` array: a part that keeps
its id path keeps its stored map whether or not the values send it, a new part has none, and a sent map
that differs from the stored one refuses `params.invalid` naming this action. Only a gesture that derives
each part's map from the stored record itself (a Window grid split) passes `derived_part_maps: true`. Splitting a part copies its map into every piece;
merging parts keeps the survivor's map only, never combines maps, and reports each removed part whose map
was not empty with its top-level keys (`Records::Metadata.discarded_keys`). Assembly Layers and
Layer-Segments and Window Elements (`elements[]`) are parts. Export leaves a part's map out unless the
owner carries it to an HBJSON object of the part's own; the `export.metadata_omitted` finding names the
part in `object_id` and carries `reference`, the `{kind, id, part_ids}` this action takes
(`RecordReader#records`, or `entity_record(..., part:)` for an owner that reads its parts itself).

**Entity-owned records.** Zones, Faces, Window Units and Thermal Bridge Edge assignments store their
records on SketchUp entities, and the same rules hold for them (`Records::Metadata`, shared with the
engine). Their reads (`ph_composer.zones.list` and `.all`, `ph_composer.zones.faces.list` and
`.all`, `ph_composer.windows.units.list`, and the Edge rows of
`ph_composer.thermal_bridges.edges.selection`, `.selection_all`, `.at` and `.candidates`) report
`extension_status` beside `extension_data`, in the words a catalog read uses; a Face or Edge with no
record reports `{}`. A Unit or Edge read with `metadata` `"summary"` gives the maps' sizes in their place
(`RecordQueries.summarize`), and `windows.units.detail` and `thermal_bridges.edges.detail` read one part
of one row in fragments, so a map larger than a reply never blocks an inventory read. Each owner has one metadata action: `ph_composer.zones.update_metadata`,
`ph_composer.zones.faces.update_metadata`, `ph_composer.windows.units.update_metadata` and
`ph_composer.thermal_bridges.edges.update_metadata`. It takes a batch of occurrences, each with the
whole `user_data` map to write, payloads for installed extensions, or both, and `expected_metadata`,
the two maps as last read; any difference refuses `target.changed`. Identical entries collapse; two
entries for one occurrence that differ, or an entry naming nothing to write, refuse
`params.invalid`. Each target resolves through its owner's writable resolver and refuses with the
owner's `target.*` code; a payload follows the engine's rules (`extension.unavailable`,
`.migration_required`, `.schema_unsupported`, a failed validator as `validation.failed`) and every
record it names must resolve (`reference.invalid`) in the proposal as it stands, so a record staged earlier in
the same proposal counts; the owner then validates the whole record. Every
target is checked before any step is built, the batch writes in one step and one Undo entry, and a
batch that writes what is stored adds no step; clearing a map the record never stored is such a batch
(`Records::Metadata.updated` leaves it absent). The Window action runs the copied-identity repair
first, as every Windows action does. A Face must already have a record, and an Edge an assignment.
An Edge is named by its occurrence path, since a split or copy leaves one `tbe_` id on several
Edges; the others keep their maps. An invalid assignment takes no metadata until it is cleared or
reassigned: with a valid `tbe_` id it refuses `validation.failed`, and without one its reference's
`entity_id` is null, which the action's params refuse. Its batch takes at most 250 entries, the bound
of every Edge write.

**Model root and Space Floor.** Neither has a record of its own. The Model's maps live in the
`ph_composer.model` settings dictionary (below), read by `ph_composer.model.detail` (with `metadata`
`"summary"`, only their sizes) and `ph_composer.model.fragment` (one part by `path`, in fragments), and
written by `ph_composer.model.update_metadata`, one target with no reference under the same pre-image,
payload, Undo and no-op rules, which answers `extension_status` only. The foundation registers the
Model's maps as the reference target `ph_composer.model.metadata`, one occurrence with id `Model`, so
`Engine#incoming_references` scans its envelopes as it scans a record's, and a record a Model payload
names, installed or unavailable, refuses deletion as `reference.in_use`. As with an unreadable record, an
unreadable Model map (`record.unreadable`) or a Model envelope whose references cannot be established
(`copy.rule_missing`) refuses every identity removal until it is repaired. A Space Floor's `user_data` is its Volume's optional `floor_user_data`: reads
never report it as a Volume value but as the Volume row's `floor` (`reference` `{floor_id, entity_path}`
and `user_data`), and `ph_composer.spaces.update_metadata` writes it by that reference under the
Volume's write refusals. A Floor takes `user_data` only, as a part does; entries for a Volume and its
Floor stage as one write. Copies and Make independent keep it with the Volume. Export carries the Model's
map to the HBJSON Model's `user_data` (the foundation's `ph_composer.model.export.model` section) and the
Floor's to its honeybee-ph `SpaceFloor` (translation sections, below).

**Exporting a payload on another feature's entity.** The feature that owns an extension claims it on
an entity kind in its export contributor: `entity_projections: [{"namespace", "target_kind",
"source_section", "fields"}]`. Registration refuses a namespace the feature does not declare, a
target kind it neither owns nor requires, a source section missing from its `requires:`, an empty
field list, a key that is not a string, and a second claim on the same namespace and kind; export
sections that require each other refuse as `registration.cycle`. The entity owner's reads pass the
target kind (`entity_record(..., target_kind:)`), so a claimed envelope is validated rather than left
out: understood, its declared fields are kept; invalid, outdated, unsupported or unavailable, it blocks
with its code as an unclaimed envelope would. Only the claim's source section captures rows, once per
occurrence (`entity_record(..., path:)`, or `capture_entity` where the owner's shared reads run
elsewhere); a capture from any other section is an internal error. The claimant reads
`reader.entity_projection(namespace, target_kind)`, `{"id", "path", "payload"}` rows, and Collection
runs every section after the sections it requires. A claimed row the claimant has not read when
collection ends blocks with `export.blocked`: installing an extension does not export it. Zones
(Zone, Face) and Windows (Unit, captured in the Apertures section) are the owners today; the
development example's `example.foundation.export.face_reviews` is the worked case.

A claim's target kind may also be a catalog record kind, which is how a Building Segment setting exports
(context/EXTENSIBILITY.md, "Building Segment settings"). The Zones section reads every valid Building
Segment through `entity_record(..., target_kind:)`, and its preflight the same way, so a claimed envelope
is validated rather than left out; it captures the claimed fields only of the Segments an exported Zone
names (`capture_record`), once each in id order, and a catalog record has no occurrence, so each row's
`path` is null. A settings namespace with `export_relevance: "required"` and no claim still blocks every
export with a Segment that carries it.

## Model settings

`PhComposer::ModelSettings` provides one feature-owned dictionary, schema, effective defaults and a
proposal step for settings stored on the Model. Reads do not persist defaults. A proposal guards
the complete authored preimage, including absence, and writes the validated merged values in the
same Model operation as its other changes. Undo restores the original dictionary state. Validation
receives effective values; the authored baseline remains distinct from inherited defaults.

A feature declares its settings fields and validation, labels, affected references and step name.
Reference targets and retarget operations remain with the feature. Zones retains its existing
`ph_composer.zones_settings` dictionary and public settings declarations; Windows uses its own
dictionary and target, so introducing the primitive does not migrate saved Zone settings. The
Windows dictionary is `ph_composer.windows_settings`, holding `default_psi_install_id` (a core
reference to `ph_composer.windows.psi_install_type`, or null), `default_psi_install_w_mk` and
`default_install_depth_m`. An edge with no assignment takes the default Type when one is chosen and
otherwise `default_psi_install_w_mk`; a default Type no longer in the Model resolves to nothing, never
to that value. A field the stored dictionary does not hold reads its default, without a write.

Climate keeps two dictionaries because a proposal guards its whole dictionary and its two updates
each guard only their own fields. `ph_composer.climate_site` holds `latitude_deg`, `longitude_deg`,
`elevation_m`, `climate_zone` (the WUFI-Passive code) and `hours_from_utc`; latitude, longitude and
elevation are present together or all null. `ph_composer.climate_design_temperatures` holds
`heating_99_c`, `cooling_1_c` and `design_temperature_source`. Every field defaults to null.

The Model's climate is a record, not a setting: kind `ph_composer.climate.climate`, prefix `clm`,
held under the one fixed id `clm_AAAAAAAAAAAA`, so no record means no climate and Clear is a delete
(`features/climate/climate/schema.rb`). It holds the name, `origin` (`station` or `hand`), the
station's coordinates and elevation, the daily temperature swing, the wind speed, `monthly` (eight
rows of twelve) and `peak_loads` (`heat_1`, `heat_2`, `cool_1`), `as_read` (the station file's own
values, null for a climate typed by hand) and `provenance` in the shape of honeybee-ph's
`ClimateProvenance`, without `source_uri`. Every object in it is closed, so no file location can be
stored. Each write stages the whole record with its provenance rewritten from the values
(`Climate::Record`), so the source type (`phius_approved` until a value differs from the file,
otherwise `user_defined`) and the edited values in `assumptions` never disagree with them. The
record is staged whole rather than through `Engine#propose_update`, which would drop a key set to
null. Completeness, edited cells and the Phius limit check are derived on every read and never
stored.

`ph_composer.climate.climate.get` answers the record with `state` (`none`, `incomplete`,
`complete`), `missing`, `edited_cells` and `limit_check`, and leaves `user_data` to
`ph_composer.records.detail`. The writes are each one Undo step: `enter_values` (refused
`target.changed` when a climate exists), `save_values`, `restore_original` (refused
`climate.no_original` for a climate typed by hand), `clear`, `attach_station` (refused
`target.changed` when a climate exists) and `replace_station`, which keeps the record's `user_data`.
`save_values`, `restore_original` and `clear` guard with `expected_values`, the eight editable fields
as read, and the request's expected revision guards the rest; the station writes refuse
`climate.site_not_set` with no site. Wind speed is never an edited
cell. Climate's three snapshot sections are `ph_composer.climate.site`, `ph_composer.climate.design_temperatures`
and `ph_composer.climate.summary` (the Climate tab's cards). The codes are published in [API_REFERENCE](../docs/API_REFERENCE.md).

The foundation's `ph_composer.model` dictionary holds the Model's own `user_data` and `extension_data`
(`shell/model_metadata.rb`), both `{}` by default; it is building metadata, not a feature's
configuration, and no feature settings dictionary carries either map.

## Programs, Schedules and Equipment Sets

`ph_composer.programs` owns three catalog kinds (`features/programs/`), each with the shared name, notes,
datasheet links and source fields, whose source kind may also be `ph_composer_default`:

- **Program** (`ph_composer.programs.program`, `pgm_`): eight required load objects, `people`, `lighting`,
  `electric_equipment`, `gas_equipment`, `service_hot_water`, `infiltration`, `ventilation` and `setpoint`,
  each closed and each with an optional `source`, the base program a library value came from. Values are in the
  unit the honeybee HBJSON field uses (people/m², W/m², L/h·m², m³/s per person, per m² and per Zone, m³/s per m²
  of exterior area, 1/h, °C, %), each with its `x-unit`; a null value is still missing. People, Lighting and
  Service hot water carry `rule` (`phius_residential`, `phius_interior`, `building_america`, or null for the
  fixed value), and setting it to null and back keeps the value and the rule's inputs. A set point is a constant
  or a Schedule, never both, and two constants put heating no higher than cooling; a pair that names a
  Schedule is a cross-record check left to the export preflight's set point findings. Each Schedule reference is a core reference
  (`people.occupancy_schedule_id` and so on), and its Schedule must be of the type the slot reads: fractional,
  activity for People activity, ventilation for Ventilation, temperature for the set points
  (`Program::SLOTS`); a wrong type refuses `validation.failed`.
- **Schedule** (`ph_composer.programs.schedule`, `sch_`): `type` (`fractional`, `activity`, `temperature`,
  `ventilation`), `days_per_week` (1 to 7), `weeks_per_year` (1 to 52) and the type's form only: `start_h`
  (0 to 23), `end_h` (0 to 24) and `fraction_on` and `fraction_off`, or `watts_on` and `watts_off` (W per person)
  for activity; `value_c`; or `periods`, high, standard, basic and minimum in that order, whole hours totalling 24
  and a fraction each. An end before the start runs past midnight. A type change on update drops the old form's
  fields and fills the new form's defaults. `ScheduleProfile` draws the 24-hour profile and, for fractional and
  ventilation, the daily full-load hours and the annual ones over days_per_week × weeks_per_year operating days,
  and names the `weekdays` the operating day applies on: the first days_per_week from Monday, or every day for a
  temperature Schedule, as the export writes them (API 1.85).
- **Equipment Set** (`ph_composer.programs.equipment_set`, `eqs_`): `devices`, each a part (`devices[]`,
  `dev_` ids, its own `user_data`) of one of the fourteen honeybee-ph `PhEquipment` types. `EquipmentTypes`
  names each type's fields, the reference quantity codes and energy norms it allows and a new device's values
  (honeybee-ph's PHIUS defaults); a field the type does not carry, or a missing one, refuses. A field that means
  something only under another field's values declares `applies_when` (a clothes dryer's `gas_consumption` and
  `gas_efficiency_factor`, under `dryer_type` `gas_exhaust_air`); the device still stores it, and
  `equipment_sets.device_types` names the condition so a form can show the field only then (API 1.85). A
  device's type is fixed; add, update and delete are each one Undo step, and delete reports the device's removed map. The Set's
  own update takes no `devices`: devices change only through the device actions (`params.invalid`).

**PH-Composer's defaults.** The residential default Program (`pgm_PHCDEFAULT01`) with its six Schedules
(`sch_PHCDEFAULT01` to `06`) is one bundle, and the default Equipment Set (`eqs_PHCDEFAULT01`, eight devices)
another (`features/programs/default_program.rb`). A bundle is unwritten while its settings field is null and its
head record is not stored: the Programs reads answer its frozen records under the reserved ids with `stored`
false, and nothing is written. The first write that touches it (an edit, duplicate or delete of one of its
records, a record that comes to refer to one of its Schedules, a device change, or a settings update that makes
another record the default) writes the whole bundle in the same Undo step; from then on its records are
ordinary. The generic `ph_composer.records.*` routes see stored records only, so they answer `target.not_found`
for an unwritten default. `ph_composer.programs.reset_default` rewrites the residential Program or the default
Set from its definition, writing it under its reserved id if the Model holds none and writing back any default
Schedule the Program names that is gone; an edited Schedule stays, since others may share it, and `user_data`
stays. A reset refuses `validation.failed` when another record holds the name it would write.

**The Model's defaults.** The `ph_composer.programs.settings` dictionary holds `default_program_id` and
`default_equipment_set_id`, null for PH-Composer's own; the reserved ids are never stored, and
`ph_composer.programs.settings.get` answers the effective ids. One dictionary holds both: an update guards only
the fields it names and takes the other as it reads, so one never stales the other. A record that is the Model's
default refuses a delete without a replacement as `programs.default_in_use`; with one, the default moves to it
in the same step. An unwritten default deleted with a replacement leaves nothing to delete: the default moves and
the bundle is no longer read. The stored fields are the reference target `ph_composer.programs.settings_record`
with a retargeter per kind.

**Deletes.** A Schedule a Program names refuses a plain delete as `reference.in_use`; with a replacement of the
same type every Program slot naming it takes the replacement first. A Zone assignment or a Segment's occupancy
naming a Program or Equipment Set refuses a plain delete as `reference.in_use`; with a replacement, each payload
naming it (a Zone's `program_id` and `equipment_set_id`, a Segment's `default_program_id` and
`equipment_set_id`) takes the replacement through `ph_composer.zones.stage_extension` in the same step, and a
locked or shared Zone refuses the whole delete as any Zone write does. A Dwelling naming an Equipment Set moves
to the replacement; a Dwelling a Zone names refuses its delete as `reference.in_use`.

**Missing values.** A `programs.list` or `programs.all` row carries `missing`, a list of `{load, field}`: each
value its ProgramType would lack, worked out by the export preflight's own rule (`ExportPlan.missing_fields`), so
the Programs tab's flags and the preflight's `programs.value_missing` rows never disagree. Duplicate keeps a Program's Schedules shared and gives an Equipment Set's devices new ids, each
keeping its map.

**Library kinds.** `programs`, `schedules` and `equipment_sets` (`features/programs/library_kinds.rb`; wire rows
in [LIBRARY_FILE_FORMAT.md](../docs/LIBRARY_FILE_FORMAT.md)). Each callback calls the Programs operation its
action does, and a local read sees PH-Composer's unwritten defaults as the reads do. A Program names its
Schedules as library dependencies (below, "Library dependencies"), so a copy brings them; its source snapshot
keeps the library's record ids. A library row's missing load or value takes a new Program's, a Schedule's missing
form values its type's, and a device's missing fields its type's. An Equipment Set copy allocates device ids; a
`use_library` replacement keeps the id and `user_data` of each local device whose place the incoming device of the
same type takes, and refuses `validation.failed` rather than drop a device holding `user_data`. A Program or
Equipment Set copy may assign itself as the Model's default (`{"mode": "model_default", "expected_settings"}`,
through `update_settings`); a Schedule copies without assignment. Copying a library Program onto Zones is
`ph_composer.programs.assign_library_program` ("Occupancy", below), which joins the copy to the assignment.

## Occupancy

`ph_composer.programs` owns Dwellings, each Zone's assignment and Single dwelling per Building Segment
(`features/programs/occupancy.rb`, `assignments.rb`, `single_dwelling.rb`, `derive/occupancy.rb`).

- **Dwelling** (`ph_composer.programs.dwelling`, `dwl_`): the shared fields, `units` (integer, at least 1), and
  optional `bedrooms` and `occupants` (its own counts) and `equipment_set_id` (a core reference; absent for the
  Model's default Set). An edit to null removes one. Its own counts are set when Single dwelling is switched off; otherwise its Zones' counts sum.
- **Zone assignment**, the structured extension `ph_composer.programs.zone_assignment` on each Zone: `program_id`,
  `dwelling_id`, `equipment_set_id` (declared references, each null for none) and `bedrooms`, `occupants`. Absent,
  or every field null, the Zone is unassigned. It travels with a copied Zone, which keeps its Dwelling.
- **Segment occupancy**, `ph_composer.programs.segment` on each Building Segment: `single_dwelling` (absent reads
  true), `default_program_id`, and the house's `bedrooms`, `occupants` and `equipment_set_id` while single. Single
  dwelling applies on a residential Segment only (the certification category); then every Zone uses the Model's
  default Program and is in the house, which is no record, and its Zone assignments are ignored.

Both extensions are `required` since API 1.83: the Program export's rooms section claims them ("Program export",
below), so a payload on an exported Zone or Segment is read, and one this version does not understand blocks.
Zones never reads them. Programs writes them through Zones' proposal participant
`ph_composer.zones.stage_extension` (a namespace and whole payloads for named Zone occurrences and Segments, each
checked by the installed validator, a Zone as one Zone update step chained after any earlier write of it in the
proposal); its result gives each changed Zone as a reference entry, so an action that deletes a Dwelling its Zones
stop naming plans the delete over them. `assign_program`, `assign_dwelling` (`shared`, `each`, `none`,
`existing`; a Dwelling no Zone names afterwards is deleted, and its map reported as `removed_user_data`), `set_counts` (a Zone in a Dwelling) and
`assign_equipment_set` (Dwellings, or Zones in none) are each one Undo step, store an unwritten default they name
first, and refuse `programs.single_dwelling` for a Zone a single dwelling decides and
`programs.dwelling_across_segments` for a Dwelling whose Zones would lie in two Segments (no Segment counts as
one). The generic metadata routes may store either; the reads report it as a finding.

**A Zone payload that names records.** A feature that keeps a payload on Zone records declares each id field as a
reference: `one` for an id or null, `many` for a list of ids. The engine scans both alike, so a record any Zone's
payload names, in either form, refuses a plain delete as `reference.in_use`, and a native copy of the Zone keeps the
payload and so names the same records. A delete with a replacement is the owning feature's code, as Programs' is:
it reads the Zones through `ph_composer.zones.all`, stages each changed payload through
`ph_composer.zones.stage_extension` in the delete's proposal, and passes the returned `zone_entries` to
`propose_delete` as a `Records::ReferencePlan`, so the incoming check reads the moved payloads. It moves only a
payload whose status is `understood`; any other stays as stored. The incoming check then refuses the delete as
`copy.rule_missing` for an envelope it cannot read or an `invalid` payload. Any other (outdated, a version no
migration reaches, a newer version, or a namespace not installed) it scans through the payload's stored reference declarations, so the delete refuses as
`reference.in_use` only while that payload still names the record. A list that already
holds the replacement keeps it once. A locked Zone refuses the whole delete. `tests/zone_payload_references_test.rb`
runs each of these over a test-only feature, `tests/support/zone_payload_probe.rb`.

**A library Program on Zones.** `ph_composer.programs.assign_library_program` takes the Zones and the library row
with the choice its resolution allows (`create`, `keep_local` with the local id, `use_library` with its expected
values), as `ph_composer.library.copy` takes them without an assignment. It joins the copy to its own proposal
through `ph_composer.library.copy_into_proposal`, which copies the Program with its Schedules or reuses the local
copy, then assigns the local Program as `assign_program` does, so both are one Undo step and refuse together. The
coordinator's own assignment callback cannot write Zones: `ph_composer.library.copy` names no Zones participant,
and the library does not depend on Programs, so the feature's action joins the copy instead, as the Windows
Installs save does. A Zone of a single dwelling refuses `programs.single_dwelling` and the copy with it.

**A Segment naming an unwritten default.** Occupancy settings may name the residential default Program or the
default Equipment Set while it is unwritten. Programs' contributor to `ph_composer.zones.segment_settings_saving`
stores that bundle before Zones stages the payload, in the same Undo step, as the assign actions do; an id that names
no record is left to Zones, which refuses `reference.invalid` and writes nothing.

**Switching Single dwelling.** Zones' settings Save stages the payload; Programs' contributor to
`ph_composer.zones.segment_settings_saved` adds the side effects when `single_dwelling` itself changes on a
residential Segment. On: every Zone's assignment is cleared and each Dwelling no Zone then names is deleted;
the Save carries the house's counts, which the Occupancy section fills from the preview's summed bedrooms. Off: a
Dwelling named for the Segment takes the counts and Set the Save carries (a null stays null), every Zone joins it
with no Program of its own (the Model's default where the Segment names another), and a Dwelling only an
overridden Zone named is deleted. A house's counts come from its Segment alone; the preview sums each Dwelling's
own count, else its Zones'. A category change alone writes nothing. A contributor
may not change what Save staged (`proposal.contribution_replaced`), so the house's values live on the Segment
payload, not on a Dwelling the switch would have to link.

**Reads.** `ph_composer.programs.zones` answers one row per Zone (its assignment; effective Program, Dwelling and
Equipment Set; floor area and iCFA from Spaces; peak people, interior lighting W and ventilation m³/h with its
source; findings), one row per Segment (category, settings, whether Single dwelling applies, the house, set
points and whether its Zones' Programs agree, the switch-on preview, findings) and the Program and Equipment Set
choices; the panel reads it as the snapshot section `ph_composer.programs.occupancy`. Since API 1.82 it also
answers every Dwelling as `programs.dwellings` does (each with its Zones' floor area and iCFA), each Zone's
`dwelling_units` and `missing`, a sentence for each null people, lighting or ventilation naming what it waits for
(a Program value, the Dwelling's bedrooms, a Schedule, Spaces), and each Segment's `sums` for its heading row: the
bedrooms and occupants of the Dwellings its Zones are in, its floor area and iCFA, and its people, lighting and
ventilation summed over the Zones that have one, with `incomplete` naming each load some Zone lacks.
`ph_composer.programs.dwellings` lists every Dwelling, the houses among them with a null id. The derivations are
pure functions in `features/programs/derive/occupancy.rb`: people from the Dwelling's occupants over the presence Schedule's
mean (its daily full-load hours over 24, as honeybee-ph's `annual_average_operating_fraction`), shared by floor
area; lighting from honeybee-ph `phius_residential.lighting_interior` over the Dwelling's iCFA and units, as peak
watts over the lighting Schedule's mean × 8,760 h, shared by iCFA; other loads per
m² of floor; ventilation from the Program's four terms, or the larger of a detailed Zone's Spaces' supply and
extract. Findings: `programs.dwelling_across_segments`, `programs.single_dwelling_no_effect` (a stored true on a
non-residential Segment), `programs.residential_without_dwelling`, `programs.non_residential_dwellings`,
`programs.unassigned_zone`, `programs.equipment_watts_residential`, `programs.single_dwelling_overrides` (a
Zone of a single dwelling that keeps an assignment, which the setting overrides) and `programs.set_points_disagree`,
each a warning. A Segment row also carries its Zones' findings, one per code, for its heading. A per-person
ventilation term over people still unknown leaves the Zone's ventilation unknown. Programs' own
actions refuse a Dwelling across Segments only for the Dwelling they join, so one already across never blocks the
repair.

## Program export

Since API 1.83, `ph_composer.programs` writes everything Programs owns into the HBJSON
(`features/programs/program_export.rb`). One pure plan (`ExportPlan`, plain records in, SI values out) is worked
out once per export from the snapshot, and the preflight reads the same findings live. Four sections carry it to
the Python sections in `python/ph_composer_translation/program_sections.py`, which build honeybee objects from the
records and compute nothing beyond honeybee's and honeybee-ph's own conversions:

| Section | Records | Python |
| --- | --- | --- |
| `programs.export.rooms` | One per exported Zone: its ProgramType id, its People extension's `number_bedrooms` and `number_people`, its Dwelling (`identifier`, `num_dwellings`) or null, and its devices. Claims `programs.zone_assignment` and `programs.segment`; requires Zones, Faces, Spaces and Certification; its projection is the plan | `RoomProgramSection`, at `ROOM`: the ProgramType, the Room's own copy of its People, a `Process` per device |
| `programs.export.schedules` | Each Schedule a ProgramType names, and a constant one per set point given as a number (`<program>-heating_setpoint`) | `ScheduleSection`: a `ScheduleRuleset` with honeybee-ph's operating days, weeks and periods |
| `programs.export.program_types` | One per Program, or per Program and Dwelling where a Phius rule applies | `ProgramTypeSection`: a `ProgramType` |
| `programs.export.set_points` | One per exported Building Segment: `winter_c`, `summer_c`, and its Dwellings' counts for the report | `SetPointSection`, at `SEGMENT`: `BldgSegment.set_points` |

**ProgramTypes.** A Program whose People, Lighting or Service hot water names a Phius rule exports once per
Dwelling, as honeybee-ph's Set Residential Program builds one per dwelling group, under the id
`<program>-<dwelling>` (a single dwelling's house is named by its Segment id): people per m² of the Rooms' Floor
Face area from the Dwelling's occupants over the presence Schedule's mean; lighting per m² from honeybee-ph
`phius_residential.lighting_interior` over its iCFA and units, as peak watts over the lighting Schedule's mean ×
8,760 h, with a `PhPhiusLightingInterior` device on the Lighting, which PHX 1.59.2 and later keeps when it merges a
Segment's Rooms, whichever Room comes first (`tests/python/test_program_phx_round_trip.py`); hot water per m² from
Building America gallons a day by units and bedrooms, as Set Residential Program codes it. A Zone in no Dwelling on
such a Program is a group of its own, one unit and no occupants, as honeybee-ph works its rules over an
untagged Room. Any other Program
exports once under its own id. Ventilation is the Program's, its empty terms 0; Infiltration is the Program's,
which the airtightness section replaces on a Segment with a test result. Every load id is the ProgramType's with
the load's name.

**Schedules.** `RulesetExport` writes a Schedule's PH form: its 24-hour profile is the operating day, applied on
`days_per_week` days from Monday over the year less `52 - weeks_per_year` weeks off, one block centred on 1 August
and moved inside the year where it would run past it; every other day is the off day, at `fraction_off`,
`watts_off` or, for ventilation, the minimum period's fraction. A Schedule of every day and every week is its
operating day alone. A temperature Schedule is one constant. Every ruleset carries honeybee-ph's
`operating_days_wk` and `operating_weeks_year`; a ventilation Schedule also carries its four periods, high,
standard, basic and minimum end to end from midnight, which PHX reads as the ventilation pattern. Occupancy and
lighting Schedules carry no periods until honeybee-ph's `annual_average_operating_fraction` and PHX's use of it
are fixed, so PHX reads their hourly values.

**Rooms.** Each Room takes its own copy of its ProgramType's People, with honeybee-ph's counts and a `PhDwellings`
its Dwelling's Rooms share (`num_dwellings` its units; a Zone in no Dwelling an untagged one of 0). A Dwelling's
counts sum over its Rooms: each Zone's own while the Dwelling's count is its Zones' sum, else the Dwelling's own
count or the Phius rule's, all on its largest Room by Floor area. Its Equipment Set, or the Model's default, goes
once on that Room, each device's `quantity` its own times the units, under the identifier `<set>-<device>`: PHX
merges devices across a Segment's Rooms by identifier and sums their quantities. A Zone in no Dwelling carries
its own Set's devices. Each device is a `Process` whose watts are honeybee-ph's `annual_avg_wattage` from the
Dwelling's counts and iCFA, over honeybee's Always On (PHX reads the device in a residential Segment). A Set in a
non-residential Segment is left out: PHX takes such a Room's equipment from its Program's watts and its Process
loads' watts, so its devices would count twice. Every identifier is Ruby's, so the HBJSON is the same each run.

**Set points.** Each Segment's winter and summer set points are its Zones' Programs' heating and cooling, each a
constant or its temperature Schedule's value. Where the Zones' Programs disagree, the Segment carries its first
Zone's by id. A legacy Zone names no Segment record, so its BldgSegment keeps honeybee-ph's 20 and 25 °C.

**Findings** (`programs.export_preflight`, the same rows the export notes or stops on; each row's `locate` runs
the view command `programs.locate`, which opens the Zones tab on the Zones / Programs view with the row's Zones
checked and scrolled into view, and opens nothing else; a row with no Zones to check, a single dwelling's or a
Segment-level occupancy finding, opens that Building Segment's settings instead):

| Code | Blocks | When |
| --- | --- | --- |
| `programs.value_missing` | yes | A Program an exported Zone uses lacks a value its ProgramType needs (a per-area value, a rule's Schedule, a ventilation rate, a set point), or a Program or Equipment Set it names is gone |
| `programs.set_points_inverted` | yes | A Program's heating set point is above its cooling one, read through its temperature Schedules |
| `programs.no_floor_area` | no | A Dwelling on a Phius rule Program has no Floor Face area, so its rule loads export at 0 per m² (honeybee-ph's Set Residential Program refuses such Rooms) |
| `programs.set_points_disagree` | no | A Segment's Zones' Programs give different set points; the row names the pair exported |
| `programs.counts_missing` | no | A Dwelling on a Phius rule has no bedrooms or occupants, so it exports with none |
| `programs.rule_without_dwelling` | no | A Zone of a Segment record in no Dwelling uses a rule Program |
| `programs.equipment_set_non_residential` | no | A Zone carries an Equipment Set in a non-residential Segment; its devices are left out, the Program's equipment watts standing for them |
| `programs.text_left_out` | no | A Program, Schedule, Dwelling or Segment name, or a device name or comment, the export would write reads as a local file path: it stays in the Model and its id, type or nothing takes its place |

The occupancy reads' findings on exported Zones and Segments join the preflight as warnings. A message that would
carry a name reading as a local file path says so in its place, in the preflight and in the export's notes. Program, Schedule,
Equipment Set and Dwelling `user_data` stays in the Model with a finding; the report's Programs part lists each
Segment's set points and its Dwellings' units and counts from the Python result.

## Mechanical equipment

`ph_composer.mechanical` (`features/mechanical/`) requires Zones, Spaces, Programs and Climate, and no other feature
names it but Piping and Ducting, which require it (`tests/mechanical_dependency_test.rb` reads that from the registry). Each
equipment family is a folder of catalog kinds that name nothing they are used by; a test holds that no family folder
names Zones, Spaces, Programs, the Zone record or `serves/` (`tests/mechanical_dependency_test.rb`). Serves
(`features/mechanical/serves/`) sits above the families and names them.

- **Ventilator** (`ph_composer.mechanical.ventilator`, `vnt_`, `schema_version` 1): the shared name, notes, datasheet
  links and source; `manufacturer` and `model` (text or null, absent by default); `quantity` (integer, at least 1,
  default 1); `sensible_heat_recovery` and `latent_heat_recovery` (0 to 1, default 0); `electric_efficiency_wh_m3`
  (at least 0, Wh/m³, default 0.55); `frost_protection_reqd` (default true); `temperature_below_defrost_used_c`
  (°C, default -5); `in_conditioned_space` (default true); and two optional fields absent by default,
  `subsoil_heat_exchange_efficiency` (0 to 1 or null) and `preheated_intake_temperature_c` (°C or null). It stores no
  system type and no rated flow.

`ph_composer.mechanical.ventilators.create`, `update`, `duplicate` and `delete` are one Undo step each. Names are
unique; `update` is guarded by `expected_values` and a null removes an optional value; `duplicate` gives a new id,
the source `derived` and a copy of the `user_data`; `delete` is the engine's guarded delete. `ventilators.list` and
`ventilators.all` (also the snapshot section `ph_composer.mechanical.ventilators`) answer each record's view with
`export_ready` and `export_blockers`, empty for a Ventilator. Its `user_data` and extension payloads are written with
`ph_composer.records.update_metadata`; the export carries the `user_data` to the honeybee-ph `Ventilator`.

- **Hot water** is three flat kinds (`features/mechanical/hot_water/`), each with the shared name, notes, datasheet
  links and source, `manufacturer` and `model`, `schema_version` 1. A **Hot Water System**
  (`ph_composer.mechanical.hot_water_system`, `hws_`) adds `number_tap_points` (integer, at least 1, or absent: honeybee-ph reads 0 as unset and counts the piping instead) and
  `piping_calc_method` (1 to 4, or absent); it stores no recirculation temperature or hours, which honeybee-ph works
  out from recirculation piping. A **Hot Water Heater** (`hot_water_heater`, `hwh_`) and a **Hot Water Tank**
  (`hot_water_tank`, `hwt_`) each name their System in `hot_water_system_id`, a required declared `one` reference.
  A Heater adds `variant` (`electric` by default, `heat_pump_annual`, `heat_pump_monthly`, `heat_pump_inside`),
  `percent_coverage` (0 to 1, default 1.0), `in_conditioned_space` (default true) and its variant's efficiency
  values, each required for its variant and absent for every other: `total_system_perf_ratio`; `cop_1`,
  `ambient_temp_1_c`, `cop_2`, `ambient_temp_2_c` (a new monthly heat pump takes honeybee-ph's 2.5 at -8.333 °C and
  8.333 °C); `annual_energy_factor`. A Tank adds `role` (`storage` by default, `buffer`, `solar`) and honeybee-ph's
  tank values under their units and defaults: `tank_type` (`2-DHW ONLY`), `quantity` 1, `in_conditioned_space`
  true, `solar_connection` false, `solar_losses_w` 0, `storage_loss_rate_w_k` 0, `storage_capacity_l` 300,
  `standby_losses_w_k` 4.0, `standby_fraction` 0.3, `room_temp_c` 20 and `water_temp_c` 60.

Each hot water kind has `ph_composer.mechanical.hot_water_systems`, `hot_water_heaters` or `hot_water_tanks`
`.list`, `.all` (also its snapshot section), `create`, `update`, `duplicate` and `delete`, one Undo step each, with
the Ventilator's rules for names, guards and copies. **Tank slots** are worked out by the pure `HotWater::Slotting`
over one System's Tanks: storage Tanks fill `tank_1` then `tank_2`, a buffer Tank `tank_buffer`, a solar Tank
`tank_solar`, each role's Tanks taken by name ignoring case, then id; a Tank with no free slot of its role is unslotted. A Tank
row carries its `slot` (null when unslotted, with `mechanical.tank_unslotted`); a System row carries the Zones it
serves, `heater_count`, `tank_count` and `findings` (its recirculation is piping's `piping_systems` read, which the
Systems table shows through piping's contributed columns): `mechanical.item_unserved`,
`mechanical.zone_left_out` and `mechanical.hot_water_pooled` (info, two served Systems in one Building Segment).
`hot_water_systems.delete` without `replacement_id` refuses `reference.in_use` while a Zone, Heater or Tank names the
System; with an id, the Zones' slots move through Serves and each Heater and Tank is a guarded edit to the
replacement, in one proposal; with null the Zones' slots empty, and a Heater or Tank still naming the System refuses.
With an id or null, every other feature's record naming the System (a Piping group's `hot_water_system_id`) moves or
clears through the registered reference retargeters (`request.retarget_references`, "A definition delete handler"),
whose plan joins Serves' in the same proposal; Mechanical names none of them.

- **Heat pumps** are four flat kinds (`features/mechanical/heat_pumps/`), each with the shared name, notes, datasheet
  links and source, `manufacturer` and `model`, `schema_version` 1. An **outdoor model**
  (`ph_composer.mechanical.hp_outdoor_equipment`, `hpo_`) holds the Phius Heat Pump Performance Estimator's inputs:
  `heating_cap_17f_kw`, `heating_cap_47f_kw` and `cooling_cap_95f_kw` (kW, at least 0, absent until given);
  `heating_rating_mode` (`cop_pair` by default, or `hspf`) with `cop_17f` and `cop_47f` (default 2.5 each) or
  `hspf_value`, and `hspf_version` (`hspf2` by default, or `hspf`); `cooling_rating_mode` (`eer_seer`, `ieer` or
  null, absent by default) with `eer` and `seer` or `ieer`, and `seer_version` (`seer2` by default, or `seer`);
  every rating above 0. Each mode reads only its own values and the other's stay stored. It may name its paired
  indoor model in `paired_indoor_equipment_id`, an optional `one` reference. An **indoor model**
  (`hp_indoor_equipment`, `hpi_`) is identity only. An **outdoor unit** (`hp_outdoor_unit`, `hou_`) names its outdoor
  model in `outdoor_equipment_id` (required), with `quantity` (default 1) and `in_conditioned_space` (default false).
  An **indoor unit** (`hp_indoor_unit`, `hiu_`) names its indoor model and its outdoor unit (`indoor_equipment_id`,
  `outdoor_unit_id`, both required), with `quantity` (default 1) and `in_conditioned_space` (default true).

Each heat pump kind has `ph_composer.mechanical.heat_pumps.outdoor_equipment`, `indoor_equipment`, `outdoor_units` or
`indoor_units` `.list`, `.all` (also its snapshot section), `create`, `update`, `duplicate` and `delete`, one Undo step
each, with the Ventilator's rules for names, guards and copies; create and duplicate go through the shared
`CatalogOperations` (`features/mechanical/catalog_operations.rb`), as hot water's do. A delete without
`replacement_id` refuses `reference.in_use` while a record or a Zone names the record; with an id, every record
naming it (a unit's model, an indoor unit's outdoor unit, an outdoor model's pairing) is a guarded edit to the
replacement and every Zone's list takes it in place of the deleted one, in one proposal; with null the pairing
empties and the Zones' lists drop it, and a unit still naming the record refuses. An outdoor model's row is
`export_ready` false, with `mechanical.hp_equipment_incomplete` in `export_blockers`, while it lacks a value the blend
needs (`OutdoorEquipment.missing_inputs`: both heating capacities above 0, its heating mode's ratings and, when it
cools, its cooling capacity and ratings); rows add `unit_count` (models) or `indoor_unit_count` (outdoor units), an
indoor unit's served `zones`, and the heat pump plan's `findings` about the record.

- **Electric heaters** are one flat kind (`features/mechanical/electric_heaters/`), the **Electric Heater**
  (`ph_composer.mechanical.electric_heater`, `ehr_`, `schema_version` 1): the shared name, notes, datasheet links and
  source, `manufacturer` and `model`, and `percent_coverage`, the share of the heating load it covers (a fraction from
  0 to 1, default 1.0, honeybee-ph's). It has `ph_composer.mechanical.electric_heaters.list`, `.all` (also its
  snapshot section), `create`, `update`, `duplicate` and `delete` through `CatalogOperations`, one Undo step each, with
  the Ventilator's rules for names, guards and copies. A delete without `replacement_id` refuses `reference.in_use`
  while a Zone's `heater_ids` names it; with an id every Zone's list takes the replacement in its place (once, where
  the list holds it already), and with null the lists drop it. Rows add the served `zones` and `findings`
  (`mechanical.item_unserved`, `mechanical.zone_left_out`). Coverages are not added up or checked against each other or
  a heat pump's.

- **Pumps** are one flat kind (`features/mechanical/pumps/`), the **Pump** (`ph_composer.mechanical.pump`, `pmp_`,
  `schema_version` 1), honeybee-ph's `PhSupportiveDevice`: the shared name, notes, datasheet links and source,
  `manufacturer` and `model`, `device_type` (4 heating circulation, 6 hot water circulation, 7 hot water storage load,
  10 other; default 6), `quantity` (1), `in_conditioned_space` (true), `norm_energy_demand_w` (W, default 0, the
  Grasshopper component's), `annual_period_operation_khrs` (kilohours a year, default 8.76), `ihg_utilization_factor`
  (0 to 1, default 1.0) and `ihg_usage_profile` (1 all year, 2 winter, 3 summer, 4 none; absent by default). An absent
  profile follows the type, as honeybee-ph re-seeds it and its Grasshopper component reads a blank one:
  `Pumps.ihg_usage_profile` gives the stored profile or the type's (`DEFAULT_IHG_USAGE_PROFILE`: 4 gives 2, 6 and 7
  give 4, 10 gives 1), and rows add the type's as `ihg_usage_profile_default`. Its operations are
  `ph_composer.mechanical.pumps.*`, as the Electric Heater's over `pump_ids`.

- **Fans** are one flat kind (`features/mechanical/fans/`), the **Fan** (`ph_composer.mechanical.fan`, `fan_`,
  `schema_version` 1), honeybee-ph's exhaust ventilator with an optional electric block: the shared name, notes,
  datasheet links and source, `manufacturer` and `model`, `exhaust_type` (`kitchen_hood`, `dryer`, `user_defined`;
  default `user_defined`), `quantity` (1), `exhaust_flow_rate_m3h` (m3/h, default 0), `annual_runtime_minutes`
  (minutes a year, default 0), `norm_energy_demand_w` (W; absent by default, and absent means no supportive device),
  `in_conditioned_space` (true) and `annual_period_operation_khrs` (kilohours a year; absent by default). An absent
  operation follows the runtime: `Fans.annual_period_operation_khrs` gives the stored one or
  `annual_runtime_minutes / 60,000`, and rows add the runtime's as `annual_period_operation_khrs_default`. Its
  operations are `ph_composer.mechanical.fans.*`, as the Pump's over `fan_ids`.

**The blend.** `HeatPumps::Blend` (`features/mechanical/heat_pumps/blend.rb`) is the Phius Heat Pump Performance
Estimator's air-source arithmetic (v25.1.2), pure Ruby in its IP units: one row per outdoor model, its quantity the
sum of its outdoor units'; each row's share of cooling capacity at 95 °F and of heating capacity at 17 °F and 47 °F;
a COP pair weighted by the heating shares; an HSPF (an HSPF2 times 1.1236, to one decimal) derated for the 99%
heating design temperature and weighted by the cooling share, as the estimator does, giving one value to both COPs;
EER and SEER (EER2 times 1.0432 less 0.0018 and SEER2 times 1.047 less 0.0004, each to one decimal) weighted by the
cooling share, the weighted SEER derated for the 1% cooling design temperature by the branch the entered SEER picks;
an IEER weighted and not derated; each row's cooling COP the mean of its EER and derated SEER, or its IEER, over 3.412;
the blend's COPs the sums. The estimator's own expressions are kept, including its linear temperature terms. Fans
and pumps are left out, so the monthly mean temperatures give only the Climate Information (heating months and their
shares at or below 17 °F and 47 °F). `export` gives honeybee-ph's values: COPs at -8.333 °C and 8.333 °C, coverage 1.0,
and recirculation cooling, used when the blend cools, with the whole capacity in kW, airflow at 300 cfm per ton of
12 kBtu/h in m³/h, the weighted COP, `min_coil_temp` 12.0 °C, `single_speed` false and `flow_rate_variable` true.
`HeatPumpPlan` (`features/mechanical/heat_pump_plan.rb`) picks, for each exported Building Segment, the complete
outdoor models whose outdoor units have indoor units serving its Zones, blends them, and gives one pair per served
Zone the blend reaches, under the Segment's identifier `ph_composer_heat_pump_<12 hex of SHA-256 of its name>`. It
reads the climate as twelve monthly mean air temperatures and both design temperatures; without them every blend is
left out with `mechanical.hp_climate_missing`. Its findings: `mechanical.item_missing` (a Zone naming an indoor unit
not stored, blocking), `mechanical.hp_unit_unpaired` (an indoor unit serving no Zone, an outdoor unit with no indoor
unit serving one), `mechanical.zone_left_out`, `mechanical.item_across_segments` (on the outdoor unit),
`mechanical.hp_equipment_incomplete` (an outdoor model lacking a value, once; or a Segment whose models blend to no
heating COP) and `mechanical.hp_cooling_over_200kw` (cooling above 682 kBtu/h: exported as one system, which PHX
splits for WUFI-Passive). `ph_composer.mechanical.heat_pumps.blended` (also the snapshot section
`ph_composer.mechanical.heat_pumps_blended`) answers the climate's state, each Segment's blend and every finding with
its `object_id`. The live reads take the climate from `ph_composer.climate.climate.get` and
`ph_composer.climate.design_temperatures.get`; the export from the Site export's projection.

**Serves.** What serves a Zone is the structured extension `ph_composer.mechanical.zone_serves` (schema version 6)
on the Zone record, as Programs keeps a Zone's assignment ("Occupancy"): no record, id or reference target of its
own. Its payload holds one slot per family, `ventilator_id` (a `vnt_` id or null, a declared `one` reference to the
Ventilator kind) and, since schema version 2, `hot_water_system_id` (an `hws_` id or null, `one`), and since schema
version 3 `hp_indoor_unit_ids` (a list of `hiu_` ids, each once, `many`), and since schema version 4 `heater_ids` (a
list of `ehr_` ids, each once, `many`), and since schema version 5 `pump_ids` (a list of `pmp_` ids, each once,
`many`), and since schema version 6 `fan_ids` (a list of `fan_` ids, each once, `many`); a later family adds its slot and moves the version.
The validator takes a whole payload: every slot present, each id of its slot's kind or null, no other key. It is
`required`: the Ventilator export claims it (below), so a payload this version does not understand blocks the export.
A Zone served by nothing stores no payload or one whose every slot is empty; the reads answer both alike.

`ph_composer.mechanical.serves.assign` (targets `{reference, expected_values}`, `slot`, `item_id`, `replace`) and
`serves.clear` (targets and a `slot`, or every slot) read the Zones once through `ph_composer.zones.all`, check every
target before anything is staged (a changed slot refuses `target.changed`; an item that is not stored refuses
before staging) and hand each Zone's whole new payload to Zones' participant `ph_composer.zones.stage_extension`, so
each is one Undo step, Zones' write refusals pass through unchanged, and no mechanical code writes a Zone. A single
slot naming another item refuses `mechanical.slot_filled`, naming it, unless `replace`. Clear writes only a Zone
that stores a payload, and stages the emptied one; with `item_id` (and its `slot`) it takes only that item out of the
slot, which a list slot needs. Assign on a list slot adds the item beside those it holds and never refuses
`mechanical.slot_filled`. The payload travels with a copied Zone because it is part of the
record; the feature declares no transition contributor.

The declared references put each named item in the engine's incoming-reference scan. `ventilators.delete` without
`replacement_id` refuses `reference.in_use`, its message naming the Zones; with an id, every slot naming the item
takes the replacement, and with null each is emptied, staged through `stage_extension` in the delete's proposal and
handed to `propose_delete` as a `Records::ReferencePlan`, one Undo step. Only an understood payload is moved; any
other stays as stored, and the incoming check then reads it as "A Zone payload that names records" above says. A Zone this feature staged earlier in the same proposal
reads as staged, so the move builds from that write, and the plan projects every Zone the proposal rewrote. A Zone whose two occurrences share an id, a copy not yet
made independent, refuses the move as `target.ambiguous`. With an id or null, `ventilators.delete` also moves or
clears every other feature's record naming the Ventilator (a Ducting group's `ventilator_id`) through the registered
reference retargeters (`request.retarget_references`, "A definition delete handler"), whose plan joins Serves' in the
same proposal, as `hot_water_systems.delete` does; Mechanical names none of them. Every route through the engine, the
generic metadata routes included, refuses a slot naming no stored item as `reference.invalid`.

`serves.all` (the snapshot section `ph_composer.mechanical.serves`) and the bounded `serves.list` answer each Zone
occurrence with its `slots`, the `items` they name with their names, the stored payload's status and `findings`
(`{code, severity, message, blocks_export}`): `mechanical.zone_unventilated` (a Zone in a Building Segment with no
Ventilator, a warning), `mechanical.zone_no_hot_water` (one with no Hot Water System, a warning), `mechanical.zone_left_out` (a served Zone in no Building Segment, info; such a Zone is never
unventilated) and `mechanical.item_missing` (a slot naming an item not in the Model, which only a Zone record written
outside the engine, such as one pasted from another Model, can carry; an error that blocks export).
`ventilators.all` and `ventilators.list` rows gain `zones`, each Zone occurrence the item serves, and `findings`:
`mechanical.item_unserved` (a warning) and `mechanical.zone_left_out`. Each of these reads reads the Zones once
through `ph_composer.zones.all`. Serves rows also carry `building_segment`, the Segment's name or the name a Zone not
yet adopted carries.

**Airflow balance.** Each `ventilators.all` and `ventilators.list` row carries `balance`: `supply_m3h`,
`extract_m3h`, `imbalanced` and `missing`, worked out by the pure `Serves::Balance`
(`features/mechanical/serves/balance.rb`) over the Zones the export writes the Ventilator to: each served Zone once,
its first occurrence by path, none in no Building Segment. A Zone in Detailed airflows gives its Spaces' supply and extract sums from
`ph_composer.spaces.all`; a By Program Zone gives its Program's flow, `ventilation_m3h` on its
`ph_composer.programs.zones` row, as both supply and extract, which is what PHX writes for it; a Zone with no Spaces
exports no ventilation and adds nothing. `imbalanced` is supply and extract differing by more than a tenth of the
larger (the rule Spaces once applied per Zone, now per ventilator), compared to 6 decimal places of m³/h so a tenth
exactly is not. Both sums are null, with the reason in `missing`, while a By Program Zone's Program cannot work its
flow out, and while the Ventilator serves no Zone the export writes. Each read takes one Spaces read and one Programs
read for all its rows. A Spaces read that refuses leaves every balance null, and a Programs read that refuses leaves
null only a balance that needs a By Program flow, each with the refusal in `missing`; the Ventilators still read.

**By ventilator.** The Colour-by mode `ph_composer.mechanical.by_ventilator` (`features/mechanical/colour_modes.rb`,
`entity_kind` `zone`) gives one entry per row of `ph_composer.zones.occurrences`, which leaves Faces out, so an
unreadable Face record does not turn it off: each Zone occurrence whose slot names a Ventilator, coloured by it from
the spread ramp and labelled with its name; an unserved Zone gets no entry and stays uncoloured; a slot naming no
stored Ventilator is incomplete. The legend counts Zone occurrences. `ph_composer.mechanical.by_hot_water_system` is
the same mode over the `hot_water_system_id` slot.

**Locate.** A `ph_composer.mechanical.preflight` row about a stored item or a Zone carries `locate`, naming the view
command `ph_composer.mechanical.locate` (`features/mechanical/locate.rb`), which maps each item kind's id prefix to its
param: a Ventilator's `ventilator_ids`, a Hot Water System's `hot_water_system_ids`, a Heater's
`hot_water_heater_ids`, a Tank's `hot_water_tank_ids`, the heat pump outdoor models', outdoor units' and indoor units'
`hp_outdoor_equipment_ids`, `hp_outdoor_unit_ids` and `hp_indoor_unit_ids`, an Electric Heater's
`electric_heater_ids`, a Pump's `pump_ids` and a Fan's `fan_ids` open the Mechanical tab on that table, narrowed to them, one
kind per request (two refuse `params.invalid`, since one table shows at a time); a Zone's `zones` open the Zones tab
with them checked. Rows for an unreadable record, a metadata problem and a refused
read carry none. The panel table that shows a kind accepts its param.

**The Mechanical tab** (`html/features/mechanical/`). One page header over a subtab per system and a pill row
(`html/pill_row.js`) picking one table of it; each family registers its system and tables in
`features/mechanical/systems.js`, and the system and table last shown are remembered as the `table_view` display
preference, never in the Model. Ventilation › Ventilators is the kit `Inventory`: Tag, the exported values, Serves
(chips opening the Zone picker, `features/mechanical/serves.js`, which assigns the newly checked Zones and then
clears those left unchecked, each one Undo step, and resends with `replace` after `mechanical.slot_filled`), supply
and extract from `balance`, then Manufacturer, Model and Notes, which its Columns menu hides; the two optional values
sit behind each row's disclosure (`features/mechanical/optional_values.js`). Electric efficiency is the
`electric_efficiency` quantity, Wh/m³ stored and W/cfm under IP, in both unit registries; the export report shows it
in its display units.

Every equipment table is one `EquipmentTable` (`features/mechanical/equipment_table.js`): the kit `Inventory` with Tag
pinned first, the family's columns, then Manufacturer, Model and Notes behind the Columns menu; New in the page header
(a form asking for the Tag and, for a kind that names a parent record, that record); Duplicate and Delete as row
actions in the shared form dialog; and Locate's narrowing by Tag. Hot Water › Systems, Heaters and Tanks
(`hot_water.js`, `hot_water_heaters.js`, `hot_water_tanks.js`) are three of them. A System row shows its Serves
chips, tap points, the Tags of the Heaters and Tanks naming it, its `piping_calc_method` with an info badge carrying
`mechanical.method_not_exported`, then any columns another feature contributes to the table's section through
`table_contributions` (piping's `Recirc.` temperature and hours, read only and muted at honeybee-ph's defaults), and
beneath the table each Building Segment's `mechanical.hot_water_pooled` note once. A System's delete offers clearing
only while no Heater or Tank names it (`ReplacementForm`'s `allowClear` as a function of the record). A Heater's
System is chosen in place, one guarded update; its Type is changed in the shared form dialog, which asks for the new
Type's efficiency values and sends one update with them, nulls for the old Type's and both guarded; the other
efficiency cells stay drawn but read only (the kit `Inventory`'s `readOnly`), so a typed edit or a paste across them
is refused whole. Coverage is stored as a fraction and shown and entered as a percentage through the panel's
`percent` quantity (a `scale` of 100 in either unit system), so its drafts, guards and readback stay in the stored
fraction. A Type change refused after the Type changed elsewhere keeps its typed values and the refusal and holds
Change Type until the user cancels. A Locate that reaches a table whose catalog is read empty answers at once that the
records are gone. A Tank's export slot is the row's `slot`, read only, amber with
the `mechanical.tank_unslotted` finding when null. A Tank's capacity is the `volume_l` quantity, litres stored and US
gallons under IP, in both unit registries. `HotWater::Systems::METHOD_EXPORTED` is the Ruby mirror of whether the
pinned honeybee-ph writes a calculation method; `tests/fixtures/mechanical/hot_water_method.json` holds it equal to
the Python section's check on the loaded class.

Electric Heating › Heaters (`electric_heaters.js`) is another: Tag, coverage in percent through the same `percent`
quantity, the Serves chips with the Zone picker over the `heater_ids` list (a heater is added beside a Zone's others
and nothing is replaced; an unchecked Zone loses only this heater), then Manufacturer, Model and Notes; its delete
offers a replacement or clearing for the Zones it serves.

Pumps › Pumps (`pumps.js`) is another: Tag, Type (a choice of the four), Quantity, Power and Operation through the
`electric_power` (W) and `kilohours` (kh/yr) quantities, the same unit in SI and IP and read in the regional number
format (both unit registries carry them), In conditioned space, the Serves chips with the Zone picker over the `pump_ids` list, then
Manufacturer, Model and Notes. The utilization factor and usage profile sit behind each row's disclosure
(`optional_values.js`, which takes a choice field and a per-field default: the row action is pressed while a value
differs from its default); the profile's first choice, "From type (...)", is null and names the type's profile.

Fans › Fans (`fans.js`) is another: Tag, Type (a choice of the three), Quantity, Flow (the `airflow` quantity), Runtime
(the `annual_minutes` quantity, min/yr, the same in SI and IP), Power (`electric_power`, blank allowed and sent as
null), the Serves chips with the Zone picker over the `fan_ids` list, then Manufacturer, Model and Notes. In
conditioned space (a choice of Yes and No) and Operation (`kilohours`, blank allowed) sit behind each row's disclosure;
the Operation field's placeholder names the value the runtime gives (`optional_values.js` takes a unit field's
`placeholder(record)`).

**Ventilator export.** `ph_composer.mechanical.export.ventilation` (section version 1, `features/mechanical/export.rb`)
requires the Zones section and claims `ph_composer.mechanical.zone_serves` on the Zone record (`entity_projections`),
as Programs claims its assignment. A payload is claimed once, so this section claims it for the whole feature: its
`projection` is every Zone once with its slots (`ExportZones`, `features/mechanical/export_zones.rb`), which each
other mechanical section requires this one to read. `VentilationPlan` (`features/mechanical/ventilation_plan.rb`) works the export out
in pure Ruby over each Zone once (its first occurrence by path) and the stored Ventilators: one record per
(Ventilator, exported Zone) pair, with id `<vnt id>_<zon id>`, the Ventilator's values and `user_data`, and the
identifiers derived from its id, `system_identifier` the Ventilator id and `unit_identifier` that id with `_unit`, so
every pair of one Ventilator carries equal values. The Python section
(`python/ph_composer_translation/mechanical_sections.py`, required for export) builds each pair's own
`PhVentilationSystem`, `sys_type` 1 and no ducts, holding a `Ventilator` with the record's values and `user_data`, and
attaches it to the Zone's Room with `set_ventilation_system`; honeybee-ph reloads one system for the shared
identifiers and PHX keys one device. Its result rows (`ventilation`: the pair's ids, the Zone's name and the unit's
values) are what `conformance` reads back: each row's Room holds its system with those identifiers, `sys_type` 1 and
the unit's values, one Ventilator carries one identifier on every Room, and no Room holds a system the run did not
report. A record value out of range is a `RecordError`, so `object.unavailable` blocks the pair. The same plan answers
`ph_composer.mechanical.preflight`, after a blocking row for each unreadable Ventilator (`record.unreadable`), each
Ventilator metadata problem extraction refuses (`Export::MetadataCheck`, `user_data` passed through) and each
exported Zone whose Serves payload this version does not understand (the claim's `extension.*` code), each finding
with the code and object the export uses:
`mechanical.item_missing` blocks (the export refuses with it), `mechanical.item_unserved` and
`mechanical.zone_left_out` name a Ventilator the export leaves out or a Room it leaves out with its Zone,
`mechanical.item_across_segments` a Ventilator written to Zones in two Building Segments, each Segment's model
carrying the whole item, and `mechanical.zone_unventilated` a Zone written with no system. The export notes all but
the last, which the preflight alone reports and the run carries into the result. The report's
"Mechanical: Ventilators" section lists each exported Ventilator with the Zones it serves, its quantity and
efficiencies, from the Python result, and one line of the `mechanical.item_unserved` findings.

**Hot water export.** `ph_composer.mechanical.export.hot_water` (section version 1,
`features/mechanical/hot_water_export.rb`) requires the Zones section and the Ventilator export, whose projection
gives the Zones. `HotWaterPlan` (`features/mechanical/hot_water_plan.rb`) works it out in pure Ruby: one record per
(Hot Water System, exported Zone) pair, id `<hws id>_<zon id>`, with `system_identifier` the System id, its name, tap
points and `piping_calc_method`, each slot's Tank (or null) and the System's Heaters in name order, each Tank and
Heater under its own record's id with its values and `user_data`. A System's `user_data` is read without passing it
through, so the reader notes `export.metadata_omitted`. The Python section (`HotWaterSection`, required for export)
builds each pair's own `PhHotWaterSystem` with fresh tanks and heaters (the heater class by variant), sets
`number_tap_points`, writes no piping, and attaches it with `set_hot_water_system`; a
`piping_calc_method` counts as written only when the loaded class has the attribute and its `to_dict()` then carries
the value, and otherwise the section reports
`mechanical.method_not_exported` once per System, not blocking. Its result rows (`hot_water`) carry the pair's
ids, the Zone's name, the identifier, tap points as stored, the heater identifiers, each slot's tank identifier
and capacity, and `digest`, the SHA-256 of the system's `to_dict()` as translated, keys sorted. `conformance`
compares each reloaded Room's system with its own row, digest included, since honeybee-ph reloads two systems
sharing an identifier as the last one and would hide a difference; and no Room may hold a hot water system the run
did not report.

`ph_composer.mechanical.preflight` (`features/mechanical/preflight.rb`) is the one preflight the Ventilator export
names for the feature. It reads the Zones once and gives a blocking row for each exported Zone whose Serves payload
this version does not understand, then each family's rows from its own plan, under that family's `section`: for hot
water, a blocking row per unreadable System, Heater or Tank and per metadata problem extraction refuses (Heaters' and
Tanks' `user_data` passed through), then `mechanical.item_missing` (blocks), `mechanical.zone_no_hot_water`
(preflight only), `mechanical.item_unserved`, `mechanical.zone_left_out`, `mechanical.item_across_segments`,
`mechanical.tank_unslotted` and `mechanical.hot_water_pooled`, each once per System and Segment, its message naming
at most five Systems. A family's own read that refuses gives one blocking row under its section and leaves the
other family's rows. A Zone's row carries the Zones tab's `locate`; hot water items have none until their tables
ship.

**Heat pump export.** `ph_composer.mechanical.export.heat_pumps` (section version 1,
`features/mechanical/heat_pump_export.rb`) requires the Zones section, the Ventilator export (for the Zones) and
Climate's `ph_composer.climate.export.site`, whose `projection` gives the monthly mean air temperatures and both
design temperatures (the Site section, below). Its records are `HeatPumpPlan`'s
pairs: id `<identifier>_<zon id>`, `segment`, `system_identifier`, `display_name` `Heat pumps: <segment>` and the
blend's `export` values. It reads the outdoor models and units without passing `user_data` through, so each map is
left out with `export.metadata_omitted`. The Python section (`HeatPumpSection`, required for export) builds each
pair's own `PhHeatPumpRatedMonthly` with the blend's values and recirculation cooling, gives its four cooling
parameter sets identifiers `<identifier>_<name>`, and adds it with `add_heat_pump_system`. Its result rows
(`heat_pumps`) carry the pair's ids, the Zone's name, the Segment, the identifier, the COPs, `cooling_used`,
`capacity_kw`, `flow_rate_m3_hr`, `annual_cop` and `digest`; `conformance` compares each reloaded Room's one heat pump
with its own row, digest included, and no Room may hold a heat pump the run did not report. The preflight adds the
heat pump rows under this section: a blocking row per unreadable outdoor model or unit and per metadata problem, then
the plan's findings; an outdoor model's, an outdoor unit's or an indoor unit's row carries `locate` with
`hp_outdoor_equipment_ids`, `hp_outdoor_unit_ids` or `hp_indoor_unit_ids`. Its `projection` is each exported
blend's Segment, by name, and whether it cools, which the Segment settings export reads; the records and the
projection come from one plan per export.

**Electric Heater export.** `ph_composer.mechanical.export.electric_heaters` (section version 1,
`features/mechanical/electric_heater_export.rb`) requires the Zones section, the Ventilator export (for the Zones) and
the Spaces export, whose projection gives each exported Zone's `space_count`. Its records are `ElectricHeaterPlan`'s
pairs, pure Ruby: one per (Electric Heater, exported Zone) whose `heater_ids` names it, id `<ehr id>_<zon id>`,
`identifier` the heater's id, `display_name` its Tag, `percent_coverage` and `user_data`; a Zone holding two heaters
gives two pairs. An exported Zone naming a heater that is not stored blocks with `mechanical.item_missing`; a heater
serving no Zone, a served Zone in no Building Segment and a heater on two Segments are notes
(`mechanical.item_unserved`, `zone_left_out`, `item_across_segments`), and so is a heater serving an exported Zone
that no Space names (`mechanical.zone_without_spaces`, once per heater, as the Pump export notes it below): PHX reads
heating systems through a Room's Spaces. The Python section (`ElectricHeaterSection`, required for export) builds each
pair's own `PhHeatingDirectElectric` and adds every heater serving a Room with `add_heating_system`. Its result rows
(`electric_heaters`) carry the pair's ids, the Zone's name, the identifier, the coverage and `digest`; honeybee-ph
reloads heating systems sharing an identifier by keeping the last, so `conformance` compares each reloaded Room's
heater with its own row's digest, and no Room may hold a heating system the run did not report. The preflight adds the
heater rows under this section: a blocking row per unreadable heater and per metadata problem, then the plan's
findings, a heater's carrying `locate` with `electric_heater_ids`.

**Pump export.** `ph_composer.mechanical.export.pumps` (section version 1, `features/mechanical/pump_export.rb`)
requires the Zones section, the Ventilator export (for the Zones) and the Spaces export, whose projection gives each
exported Zone's `space_count`. Its records are `PumpPlan`'s pairs, pure Ruby: one per (Pump, exported Zone) whose
`pump_ids` names it, id `<pmp id>_<zon id>`, `identifier` the pump's id, `display_name` its Tag, its values under the
record's names with the usage profile resolved, and `user_data`. It notes and blocks as the Electric Heater export does,
`mechanical.zone_without_spaces` included, once per pump, naming each served exported Zone that no Space names
(`ExportZones.spaceless_findings`, which takes a family's slot and label so another family PHX reads through Spaces
reports the same): PHX reads supportive devices through a Room's Spaces, so such a Room carries the pump in the HBJSON
and PHX reads it only through another Room it serves in the same Building Segment. The pair is still written. The preflight counts Spaces from
`ph_composer.spaces.all` as the export does, each under the Zone it names unless it sits inside a left-out Zone, and
reads it only while an exported Zone names a pump; a refused read skips the finding and keeps the pump rows. The Python section (`PumpSection`, required
for export) builds each pair's own `PhSupportiveDevice`, setting the usage profile after the type (honeybee-ph's type
setter re-seeds it), and adds every pump serving a Room with `add_supportive_device`. Its result rows (`pumps`) carry
the pair's ids, the Zone's name, the identifier, the values and `digest`; `conformance` compares each reloaded Room's
pump with its own row's digest, and no Room may hold a supportive device under a Pump id the run did not report
(another section's supportive devices are not its to check). The preflight adds the pump rows under this section, a
pump's carrying `locate` with `pump_ids`. The export's and the preflight's Spaces reads are `ExportZones.spaced` and
`ExportZones.live_spaced`, which the Fan and Electric Heater exports call too.

**Fan export.** `ph_composer.mechanical.export.fans` (section version 1, `features/mechanical/fan_export.rb`) requires
the same sections as the Pump export. Its records are `FanPlan`'s pairs: one per (Fan, exported Zone) whose `fan_ids`
names it, id `<fan id>_<zon id>`, `identifier` the fan's id, `display_name` its Tag, its values under the record's
names, `norm_energy_demand_w` null when it has none, the operation resolved, and `user_data`. It notes and blocks as
the Pump export, `mechanical.zone_without_spaces` included. The Python section (`FanSection`, required for export)
builds each pair's own exhaust ventilator of the class its type names (`ExhaustVentKitchenHood`, `ExhaustVentDryer`,
`ExhaustVentUserDefined`), the flow divided by 3600 into m3/s, and, when the pair has power, a `PhSupportiveDevice` of
type 10 under the same identifier with the quantity, power, operation and in conditioned space (its utilization factor
and usage profile the class's); it adds them with `add_exhaust_vent_device` and `add_supportive_device`. honeybee-ph
and PHX keep the two in separate collections, so the shared identifier does not collide. Its result rows (`fans`)
carry the pair's ids, the Zone's name, the identifier, the exhaust values (flow in m3/s), the supportive device's
(null without power), `digest` and `supportive_device_digest`; `conformance` compares each reloaded Room's fan objects
with its own row, a Room may hold a supportive device under a Fan id only where its row has power, and no Room may
hold a Fan-id object the run did not report. PHX 1.59.4 does not copy an exhaust ventilator's `quantity`.

**Building Segment mechanical settings.** Each Building Segment's mechanical settings are the structured extension
`ph_composer.mechanical.segment` (schema version 1, required) on the Segment record, staged by Zones' settings Save
like every settings section (`features/mechanical/segment/settings.rb`; EXTENSIBILITY, "Building Segment
settings"): `mechanical_cooling`, `mech_room_temp_c`, `summer_bypass_mode` (`none`, `temperature_controlled`,
`enthalpy_controlled`, `always`), `ventilation_system_ach` (0 or more, or null), `daytime_window_ach` and
`nighttime_window_ach` (0 or more), all six and nothing else. A Segment with none, or one this version does not
understand, reads honeybee-ph's defaults (`false`, 20.0, `always`, null, 0.0, 0.0), which
`ph_composer.mechanical.segment.get` answers. The switch is entered, never worked out from the heat pumps.
`ph_composer.mechanical.export.segments` (section version 1, `features/mechanical/segment_export.rb`) claims the
namespace on the Building Segment kind and requires the Zones section and the heat pump export: one record per
exported Segment record in export identifier order, `{id, export_identifier, name}` and the six values, defaults
written out. Where a Segment's switch is on and its exported blend has no recirculation cooling (no blend counts as
none), or off and its blend cools, it notes `mechanical.segment_cooling_mismatch`, which never blocks; the preflight
gives the same rows under this section from the live plan. The Python section (`MechanicalSegmentSection`,
`mechanical_segment_sections.py`, required for export) attaches at `SEGMENT` and sets
`set_points.mechanical_cooling`, `mech_room_temp` and the four `summer_ventilation` values on the shared
`BldgSegment` in place; it never sets `set_points.winter` or `.summer`, which Programs writes, nor honeybee-ph's
other seven summer ventilation values, which keep their defaults. Its result rows (`building_segments`) carry the
export identifier and the six values as honeybee-ph holds them, and `conformance` reads them back from every reloaded
Building Segment. PHX 1.59.4 copies all of them to the Variant's building data; its WUFI XML and METr writers carry
the room temperature and the bypass mode and not mechanical cooling
(`tests/python/test_mechanical_segment_phx_round_trip.py`).

## Hot water piping

`ph_composer.piping` (`features/piping/`) requires Mechanical, which owns the Hot Water System its pipes export into,
and Zones, and installs after Mechanical. Nothing under `features/mechanical/` or `html/features/mechanical/` names it
(`tests/piping_dependency_test.rb`); Mechanical's own words for piping, such as `piping_calc_method`, stay. Codes are
under the noun `piping` (`features/piping/codes.rb`).

- **Pipe Type** (`ph_composer.piping.pipe_type`, `ppt_`, `schema_version` 1, `features/piping/type/`), a Model-owned
  definition stored by `DictionaryStore` in the Model dictionary `ph_composer.records.ph_composer.piping.pipe_type`:
  the shared name (shown as Tag), notes, datasheet links and source; `material` (honeybee-ph's 1 to 8: Copper M,
  Copper L, Copper K, CPVC CTS SDR, CPVC Sch 40, PEX, PE, PEX CTS SDR; default 2); `diameter_mm` (one of the eight
  nominal sizes stored as the inch size times 25.4: 9.525, 12.7, 15.875, 19.05, 25.4, 31.75, 38.1, 50.8; default
  12.7, the 1/2 in size); `insulation_thickness_mm` (at least 0, default 12.7); `insulation_conductivity_w_mk`
  (W/(m K), above 0, or absent; default 0.04); `insulation_reflective` (default true); `insulation_quality` (1 None, 2
  Moderate, 3 Good; default 1); and `color`, stored only once authored, read as a ramp colour by id until then, as a
  Thermal Bridge Type's. A pipe's role, water temperature and daily hours are not on the type. It names no Edge, group
  or run, and it is not a library kind.

`ph_composer.piping.pipe_types.create`, `update`, `duplicate` and `delete` are one Undo step each, through
Mechanical's `CatalogOperations`, as a flat equipment catalog's are: names are unique, `update` is guarded by
`expected_values` and a null removes an optional value, `duplicate` gives a new id, the source `derived` and a copy of
the `user_data`, and `delete` is the engine's guarded delete. `delete` takes `replacement_id`, another existing type
or null, which refuses `params.invalid` when it names the type itself. `pipe_types.list` and `pipe_types.all` (also
the snapshot section `ph_composer.piping.pipe_types`) answer each record's view with `display.color` (its `color`,
else its `assigned_color`: the first colour of `ColourBy::Palette::RAMP`, the shared categorical ramp, that no Pipe
Type draws in or would return to, set by `create` and `duplicate`; a null `color` returns to it),
`export_ready` and `export_blockers`: `piping.insulation_conductivity_missing` for a type with insulation above 0 mm
and no conductivity, which blocks the export only of a pipe that uses it; a bare pipe needs no conductivity. Its
`user_data` is written with `ph_composer.records.update_metadata`; the export leaves a Pipe Type's map out, since each
pipe segment carries its pipe's.

- **Piping group** (reference target `ph_composer.piping.group`, `features/piping/group/`): the record in the
  storage table on a SketchUp Group, its occurrence reference `{group_id, group_path}` (root-to-Group persistent ids).
  Membership is the direct parent: an Edge is a pipe only when its parent Group carries this record, so an Edge in a
  plain Group inside a Piping group is not one. A Piping group sits at the Model root or in plain Groups (Q13):
  `groups.link`, `groups.unlink`, `pipes.assign` and `pipes.clear` refuse `piping.group_in_zone` where
  `ph_composer.zones.containment` says a Zone holds the group, and `piping.group_nested` inside another Piping group.
  A Pipe Type or Hot Water System delete still rewrites a group a Zone holds, so no reference is left dangling.
  `groups.make` (`LineGroups::GroupOperations.make`) takes `edge_paths`, root-to-Edge paths of loose lines, and an
  existing System, and wraps the lines in a new Group in their own collection with a new record, in one Undo step;
  the lines keep their persistent ids and dictionaries and the edit path stays. The Group is named the first free
  "Piping group N" among the Piping groups (`Records::Names.numbered`). Each Face whose Edges, every loop's, are all
  among the lines (`LineGroups::Make.closed_faces`) is erased in the same step; the result gives `group_id`, `name`
  and `removed_faces`. It refuses, writing nothing:
  `target.wrong_kind` for a path naming no Edge or an Edge bounding a Face with an Edge outside the lines, `target.wrong_hierarchy` for lines in
  two collections or in a Group another feature claims, `target.edit_path_changed` for lines outside the open
  context, `piping.group_nested` inside a Piping group, `piping.group_in_zone` where a Zone holds an Edge's own path,
  the path's write refusal (a component, a locked or shared Group) and `gesture.too_large` above the pipe gesture
  limit. SketchUp deletes a Group left empty at commit, so no operation makes an empty one
  (context/SKETCHUP_HOST_BEHAVIOR.md, "Making a line group"). `pipes.selection` and `pipes.selection_all` give
  `make_refusal`, the same rule over the selection, null when every selected line's path can be made. `groups.all` and the bounded `groups.list` give every occurrence
  in path order with `values`, `pipe_count` (Edges directly inside with a pipe record), `copied`, `findings` (the two
  placement codes) and `write_refusal`, the refusal `groups.link` meets in its order: nested, the path's own (a
  component, a locked or shared step), then in a Zone. No Model-level registry lists groups or pipes (Q1).
- **Pipe** (reference target `ph_composer.piping.pipe`, `features/piping/assignment/`): the assignment on an Edge,
  occurrence reference `{group_path, entity_path, entity_id}` with `entity_path` root-to-Edge. `role` is `trunk`,
  `branch`, `twig` or `recirculation`; a trunk carries `multiplier` (integer at least 1, default 1) and
  `demand_recirculation` (default false), a recirculation pipe `water_temp_c` (0 to 100 from P4-13c, default 60) and `daily_period` (hours,
  0 to 24, default 24), a branch and a twig neither. A role's values are required for it and absent for the others;
  a value another role takes refuses `params.invalid`, and reassigning a role drops the old role's values.
  `pipes.assign` and `pipes.clear` take at most 250 explicit Edges and refuse as a whole for a stale target, an Edge
  outside a Piping group (`piping.outside_group`), a misplaced group, a locked or shared step or one Edge too many
  (`gesture.too_large`), one Undo step each. `pipes.clear` refuses `reference.in_use` while a record names a removed
  `ppe_` id no Edge the command leaves keeps, a record of another schema version included. `pipes.selection`
  (bounded), `pipes.selection_all` and its snapshot section `ph_composer.piping.pipes.selected` read the native
  selection under the active path, each Edge with its group and System, values, `copied` and `write_refusal`;
  anything not an Edge is listed as ignored. `pipe_types.delete` with `replacement_id` rewrites every pipe naming the
  type, with null nulls its `pipe_type_id`, in the delete's proposal; a stale `expected_values` refuses
  `target.changed` before any pipe is planned, and a pipe the rewrite cannot reach (outside a Piping group, locked or
  shared) refuses the whole delete as `reference.in_use`. A Hot Water System delete with an id or null moves or
  clears the Piping groups naming it through piping's retargeter
  `ph_composer.piping.groups.retarget_hot_water_system`.
- **Runs and the tree** (`features/piping/runs/`, pure Ruby over detached facts; the live walk in
  `features/piping/scan/`). Runs are derived, never stored. The core chain rule (`core/edge_runs.rb`) joins pipes of
  one group occurrence, role, Pipe Type and role values where they share a vertex (a whole float compared as its integer); a run
  ends at a free end or a vertex where its own pipes do not number two, so a branch passing a trunk tee is one branch
  and a trunk changing type or multiplier is two. A branch's parent is the trunk run of its group occurrence sharing a
  vertex with it, a twig's the branch run; of two, the one whose identifier sorts first. A tree lives in one Piping
  group. A run's `identifier` is `pipe_` and 16 hex digits of the digest of its container path, role, type, role values
  and micrometre-rounded points; a pipe's segment identifier is `pipe_seg_` and 16 hex digits of its Edge path and
  sorted endpoints, so a split Edge, which shares its assignment id, is two segments. `display_name` is the role word
  and a counter per Hot Water System and role, numbered by group path, then the run's smallest point. Schedule order
  is System, group path, role, smallest point. Lengths are drawn length; a trunk's multiplier is never applied.
- **Recirculation per Hot Water System** (`runs/recirculation.rb`): honeybee-ph's `recirc_temp` and `recirc_hours`
  copied step for step, so the values equal the export's after reload: each recirculation run is one element, its
  temperature and hours the length-weighted means of its pipes'; the System's are the length-weighted means of its
  runs', the hours truncated toward zero as `int()` does, 60.0 and 24 with no recirculation pipe (`from_piping` false).
  Segment lengths are ladybug-geometry's magnitude and every sum adds left to right, as CPython 3.11's `sum` does; runs
  add in identifier order and pipes in segment identifier order, the order a system reloaded from the canonical HBJSON,
  whose keys are sorted, holds them in. Two runs of 3.3 m and 1.7 m at 24 h give 23, as honeybee-ph does; one run of
  both gives 24; three runs of 0.1, 0.2 and 0.7 m give 23 or 24 by their identifiers, as honeybee-ph does.
- **The schedule** `ph_composer.piping.schedule` (bounded, `limit`, `cursor` and `compact`; refuses `record.unreadable` and
  `validation.failed` for an unreadable Pipe Type or Hot Water System) walks the Model once, with no snapshot section,
  and answers one page of runs, each with `hot_water_system_id` and name, `group`, `role`, `parent` and `parent_name`,
  `pipe_type_id` and name, `length_m`, `line_count`, `values`, `closed`, `edge_paths`, `shared` and `findings`; beside
  them `totals` (`by_role`, run and line counts, distribution and recirculation length), `systems` (every Hot Water
  System's `distribution_length_m` by role and its recirculation sum), `types` (every Pipe Type's `used_length_m` and
  line count) and the first 50 `unreadable` records with `unreadable_total`. Names from a user's text and finding
  messages are cut and named in `truncated`. With `compact`, a run leaves out `edge_paths` and each finding its
  `locate`, giving `edge_count` and the run's `index`, the `systems`, `types` and `unreadable` rows are left out with
  `system_count` and `type_count`, and every page fits one agent reply; `ph_composer.piping.schedule.details` pages
  those rows (`part`) and `ph_composer.piping.runs.members` one run's pipes, or one finding's. A pipe or group record that cannot be read, or fails its schema (a `water_temp_c` outside 0 to 100
  included), is an `unreadable` row (`record.unreadable`), never a raise, and blocks export.
  `ph_composer.piping.systems` answers the `systems` rows alone and is the snapshot section
  `ph_composer.piping.piping_systems`; `pipe_types.list` and `pipe_types.all` add `used_length_m`. Both walk without
  Zones' containment, so an unreadable Zone record does not refuse them.
- **Findings** on a run, each `{code, message, blocks_export, locate: {edge_paths}}`: blocking
  `piping.type_missing` (no or a deleted Pipe Type), `piping.group_unlinked` (no or a deleted System),
  `piping.group_in_zone`, `piping.insulation_conductivity_missing`, `piping.branch_unconnected` and
  `piping.twig_unconnected` (a twig touching only a trunk included); warnings `piping.trunk_without_branches`,
  `piping.parent_ambiguous` and `piping.shared_definition`.
- **`ph_composer.piping.runs.locate`** (view command) takes one run's or finding's `edge_paths` (at most 10,000, one
  group occurrence, else `params.invalid`; a path not ending at a pipe in a Piping group refuses `target.wrong_kind`),
  refuses `piping.hidden` for a hidden pipe, Group or tag, opens the group
  through `ph_composer.context.open`, selects the pipes and frames them by world points.
- **The panel's read** `ph_composer.piping.schedule.all` answers the whole schedule unbounded (`prefer` names
  `schedule`): every run, the totals, the `systems` and `types` rows and every unreadable record, uncut.
- **Colour-by modes** (`features/piping/colour_modes.rb`) `ph_composer.piping.by_role` ("Pipe role", fixed colours per
  role in role order) and `ph_composer.piping.by_type` ("Pipe Type", each type's `display.color`; a missing type is
  `Missing type`, incomplete): `entity_kind` `edge`, stroke 5 px as thermal bridges', one entry per readable pipe
  occurrence with the Edge as `entity` and its world segment in `derived`; the `figure` is the drawn length, so a
  role's legend row equals the schedule's `totals.by_role` length. A line with no assignment, or one whose record
  cannot be read, draws nothing.
- **The pipe tool** (`features/piping/pipe_tool.rb`, the thermal-bridge edge tool's shape, P3b-07's rules):
  `pipe_tool.choose` (view command) takes `pipe_type_id`, `role` and the role's values as `pipes.assign` does (another
  role's value refuses `params.invalid`; a missing type `target.not_found`), arms the tool and leases Colour by pipe
  role; `pipe_tool.stop` ends it; `pipe_tool.state` and the snapshot section `ph_composer.piping.pipe_tool` read
  `{active, pipe_type_id, role, values, gesture_limit}`. A pick reads the Edge's path by the selection's rule (an Edge
  outside a Piping group or behind a write refusal refuses the gesture with its reason); type, role, values and
  revision freeze at button-down; collection stops one past the limit; release sends one `pipes.assign` through
  `API.invoke`, one Undo step; Escape, deactivation, suspension, a lost release and an edit-path change cancel and
  write nothing. Menu items `pipe_tool.arm_menu` (re-arms with the last choice) and `pipe_tool.stop_menu` sit under
  "Hot water piping".

## ERV ducting

`ph_composer.ducting` (`features/ducting/`) requires Mechanical, which owns the Ventilator its ducts export into, and
Zones, and installs last. Nothing under Mechanical's or Piping's folders, Ruby or panel, names it, and nothing under
its own names Piping (`tests/ducting_dependency_test.rb`). Codes are under the noun `ducting`
(`features/ducting/codes.rb`).

- **Duct Type** (`ph_composer.ducting.duct_type`, `dct_`, `schema_version` 1, `features/ducting/type/`), a Model-owned
  definition stored by `DictionaryStore` in the Model dictionary `ph_composer.records.ph_composer.ducting.duct_type`:
  the shared name (shown as Tag), notes, datasheet links and source; `shape`, `round` (the default) or `rectangular`;
  the shape's dimensions in mm, above 0: `diameter_mm` for a round type (default 160) or `width_mm` and `height_mm`
  for a rectangular one (no default); `insulation_thickness_mm` (at least 0, default 25.4);
  `insulation_conductivity_w_mk` (W/(m K), above 0, or absent; default 0.04); `insulation_reflective` (default
  true); and `color`, stored only once authored, read as a ramp colour by id until then. The defaults are
  honeybee-ph's duct segment's. A shape's dimensions are required and the other shape's absent: the kind refuses
  any other stored record, and `create` and `update` refuse such values `params.invalid` before writing. An
  `update` that changes `shape` removes the old shape's dimensions in the same write and must give the new
  shape's. A duct's direction and length are not on the type. It names no Edge, group or run, and it is not a
  library kind.

`ph_composer.ducting.duct_types.create`, `update`, `duplicate` and `delete` are one Undo step each, through
Mechanical's `CatalogOperations`, with Mechanical's catalog param shapes: names are unique, `update` is guarded by
`expected_values` (a stale value refuses `target.changed` before the shape is checked) and a null removes an optional
value, `duplicate` gives a new id, the source `derived` and a copy of the `user_data`, and `delete` is the engine's
guarded delete. `delete` takes `replacement_id`, another existing type or null, which refuses `params.invalid` when
it names the type itself. `duct_types.list` and `duct_types.all` (also the snapshot section
`ph_composer.ducting.duct_types`) answer each record's view with `display.color` (as a Pipe Type's, from `color` or
`assigned_color`), `export_ready` and
`export_blockers`: `ducting.insulation_conductivity_missing` for a type with insulation above 0 mm and no
conductivity, which blocks the export only of a duct that uses it; a bare duct needs no conductivity. Its
`user_data` is written with `ph_composer.records.update_metadata` and kept in the Model.

Ducting groups and ducts stand on the foundation's line-group layer (`context/EXTENSIBILITY.md`, "Line groups") with
ducting's spec (`features/ducting/line_group.rb`), so their targets, writes, group operations, clear, type rewrite,
walk and selection rows follow Piping groups' and pipes' rules (see "Hot water piping") with these differences.

- **Ducting group** (reference target `ph_composer.ducting.group`, `features/ducting/group/`): the record in the
  storage table on a SketchUp Group, occurrence reference `{group_id, group_path}`. Membership is the direct parent;
  a Ducting group sits at the Model root or in plain Groups (Q5): `groups.link`, `groups.unlink`, `ducts.assign` and
  `ducts.clear` refuse `ducting.group_in_zone` where `ph_composer.zones.containment` says a Zone holds it, and
  `ducting.group_nested` inside another Ducting group; a Duct Type delete still rewrites a duct, and a Ventilator
  delete a group, that a Zone holds. `groups.make` takes `edge_paths` and an existing Ventilator and wraps the loose
  lines in a new group where they are drawn, in one Undo step, by piping's rule and refusals with the `ducting`
  codes; `ducts.selection` and `ducts.selection_all` give `make_refusal`. A pasted copy keeps its Ventilator. `groups.all` and the bounded `groups.list` give
  every occurrence in path order with `values` (`ventilator_id`), `duct_count`, `copied`, `findings` and
  `write_refusal`.
- **Duct** (reference target `ph_composer.ducting.duct`, `features/ducting/assignment/`): the assignment on an Edge,
  occurrence reference `{group_path, entity_path, entity_id}`. `direction` is `outdoor_air` or `exhaust_air` and
  `quantity` an integer at least 1. `ducts.assign` takes any of `duct_type_id`, `direction` and `quantity`: an Edge
  already assigned keeps what it is not given, and an Edge with none needs a type and a direction, refusing
  `params.invalid` otherwise, and takes quantity 1, so a stored duct always has a direction. `ducts.assign` and
  `ducts.clear` take at most 250 explicit Edges and refuse as a whole for a stale target, an Edge outside a Ducting
  group (`ducting.outside_group`), a misplaced group, a locked or shared step or one Edge too many
  (`gesture.too_large`), one Undo step each. `ducts.selection` (bounded), `ducts.selection_all` and its snapshot
  section `ph_composer.ducting.ducts.selected` read the native selection under the active path, each Edge with its
  group and Ventilator, values, `copied` and `write_refusal`. `duct_types.delete` with `replacement_id` rewrites
  every duct naming the type, with null nulls its `duct_type_id`, in the delete's proposal; a duct the rewrite cannot
  reach refuses the whole delete as `reference.in_use`. A Ventilator delete with an id or null moves or clears the
  Ducting groups naming it through ducting's retargeter `ph_composer.ducting.groups.retarget_ventilator`; a group
  whose record fails its schema but still names it, in its link or in a readable extension envelope, strands every
  delete as `reference.in_use` (the retargeter's refusal, which a delete with a replacement or null meets, says to
  repair a record whose link holds the id; a delete with neither, and a record that names it only in a malformed link
  or an envelope, get the engine's generic refusal), so
  `ph_composer.ducting.ventilators` lists such groups apart from the linked ones (`blocking_group_names`), from the
  same one walk as its lengths, and the Delete offers no choice while any remains. A duct's
  `quantity` is at most 10,000 (P4-14d), so a length times it stays finite; a stored record above it is unreadable.
- **Runs** (`features/ducting/runs.rb`, `findings.rb`, `schedule.rb`, pure Ruby over detached facts; the live read in
  `scan.rb` over the layer's `Scan.edges`). Runs are derived, never stored. A run is every duct of one Ducting group
  occurrence with one direction, Duct Type and quantity, whether they touch or not: the chain rule is not used, since
  only the sum matters. Its `identifier` is `duct_` and 16 hex digits of the digest of its container path, direction,
  type, quantity and each duct's sorted micrometre endpoints; a duct's segment identifier is `duct_seg_` and 16 hex
  digits of its Edge path and sorted endpoints, so a split Edge is two segments. `display_name` is the direction word
  and a counter per Ventilator and direction ("Outdoor air 1"); schedule order is Ventilator id, group path,
  direction, smallest point. A run row's `length_m` is drawn length beside its `quantity`; every total, a
  Ventilator's two lengths and a Duct Type's used length apply the quantity, as the export writes a run of quantity N
  as N elements.
- **The schedule** `ph_composer.ducting.schedule` (bounded, `limit`, `cursor` and `compact`; it refuses
  `record.unreadable` and `validation.failed` for an unreadable Duct Type or Ventilator, and Mechanical's Serves
  refusals) walks the Model once, with no snapshot section, and answers one page of runs, each with `direction`,
  `ventilator_id` and name, `group`, `duct_type_id` and name, `length_m`, `quantity`, `line_count`, `edge_paths`,
  `shared` and `findings`; beside them `totals` (`by_direction`, run and line counts, length), `ventilators` (every
  Ventilator's `outdoor_air_length_m` and `exhaust_air_length_m` and its `findings`), `types` (every Duct Type's
  `used_length_m` and line count) and the first 50 `unreadable` records with `unreadable_total`, as piping's: names
  and messages cut, `compact` leaving out the paths and lists, `ph_composer.ducting.schedule.details` paging the
  `ventilators`, `types` and `unreadable` rows and `ph_composer.ducting.runs.members` one run's ducts. A duct or group
  record that cannot be read, or fails its schema, a duct with no direction included, is an `unreadable` row
  (`record.unreadable`), never a raise, and blocks export. Which Ventilators serve a Zone it reads from
  `ph_composer.mechanical.ventilators.all`. `ph_composer.ducting.ventilators` answers the `ventilators` rows without
  findings and is the snapshot section `ph_composer.ducting.ducting_ventilators`; `duct_types.list` and
  `duct_types.all` add `used_length_m`. Both walk without Zones' containment or Mechanical's read.
- **Findings.** On a run, each `{code, message, blocks_export, locate: {edge_paths}}`: blocking
  `ducting.type_missing` (no or a deleted Duct Type), `ducting.group_unlinked` (no or a deleted Ventilator),
  `ducting.group_in_zone` and `ducting.insulation_conductivity_missing`; the warning `ducting.shared_definition`. On
  a `ventilators` row, the warning `ducting.run_missing` for a Ventilator that serves a Zone and has no Outdoor air or
  no Exhaust air run, its `locate` `{name: "ph_composer.mechanical.locate", params: {ventilator_ids}}`; a Ventilator
  serving no Zone has Mechanical's `mechanical.item_unserved` instead.
- **`ph_composer.ducting.runs.locate`** (view command), as piping's: one run's or finding's `edge_paths` in one group
  occurrence, refusing `ducting.hidden` for a hidden duct, Group or tag.
- **The panel's read** `ph_composer.ducting.schedule.all` answers the whole schedule unbounded (`prefer` names
  `schedule`): every run, the totals, the `ventilators` and `types` rows and every unreadable record, uncut.
- **Colour-by modes** (`features/ducting/colour_modes.rb`) `ph_composer.ducting.by_direction` ("Duct direction",
  fixed colours, Outdoor air then Exhaust air) and `ph_composer.ducting.by_type` ("Duct Type", each type's
  `display.color`; a missing or unset type is `Missing type`, incomplete), as piping's on the shared
  `LineGroups::ColourModes`, except that the `figure` is each duct's length times its quantity, so a direction's
  legend row equals `totals.by_direction` and a type's its `used_length_m`.
- **The Ventilators columns.** Ducting contributes `Outdoor air duct` and `Exhaust air duct` to Mechanical's
  Ventilators table through `table_contributions` (`html/features/ducting/ventilator_columns.js`), read only, from
  `ducting_ventilators`; a length of 0 shows a dash.
- **Export** `ph_composer.ducting.export.ducting` (`export.rb`, the pure `extraction.rb`; see "Translation sections and
  artifacts") and its preflight `ph_composer.ducting.export_preflight`: the export's findings, a run's with
  `runs.locate` params and a Ventilator's (`ducting.run_missing`, `ducting.ventilator_unexported`) with Mechanical's
  Locate, each unreadable record and each metadata refusal. `ducting.ventilator_unexported`, a warning, names a
  Ventilator whose Ducting groups hold ducts and which no exported Zone names, so its ducts go nowhere.

## This computer's settings file

Settings that belong to the computer and not to a Model, and that every SketchUp version must read,
live in one JSON file kept by `shell/computer_settings.rb` (placement and write rules in
[TECH_STACK](TECH_STACK.md#this-computers-settings-file)):

```
{ "schema_version": 1, "sections": { "<feature id>": { ... } } }
```

A feature owns the section under its own id and validates it on every read. `ComputerSettings.read`
answers `{}` for an absent section or file. It raises `ComputerSettings::Refused` with a `reason`:
`unavailable` (not macOS), `unreadable`, `later_version`, `too_large` or `unwritable`. Its message
never holds a path. A file that is unreadable or from a later version is left as stored: reads and
writes both refuse. The owning feature maps the reason to its own code.

Climate's section, `ph_composer.climate`, is `{ "folders": [ { "id", "name", "location" } ],
"last_dataset_id": string or null }`. `id` is `climate_folder_` and twelve alphanumerics, `name` the
dataset name (1 to 120 characters), `location` the folder's absolute path. A `last_dataset_id` naming
no listed folder reads as null. A section that fails validation reads as
`climate.settings_unreadable` and is never replaced. `location` never leaves the section: the
`ph_composer.climate.folders.*` operations answer `display_location` instead, `~/` and the rest under
the home folder, the volume's name and the rest under `/Volumes/`, and otherwise `…/` and the last
two names. The reasons map to `climate.settings_unreadable` (`unreadable`, `later_version`) and
`climate.settings_unavailable` (the rest).

## The Phius station reader

`features/climate/stations/` reads Phius station files in place, in the climate data folders this
computer's settings file lists; nothing is copied or indexed (D4c-11: a 1,007-file folder walks and
reads its headers in under 0.1 s in SketchUp 2026's Ruby, so the read is synchronous with no cache).

- **Reader** (`PhiusStationFile`, pure): bytes in, at most 64 KiB, read as Windows-1252 into UTF-8
  with an undefined byte replaced. Rows are tab-delimited and matched by their first cell, compared
  without its unit and case. The header row is the first whose cells include `Latitude`; its first
  cell is the station's name (1 to 120 characters) and `Latitude`, `Longitude`, `Height a.s.l.` and
  `Daily temperature variation summer` each take the next non-empty cell. The series rows are
  `Temperature outdoor`, `North`, `East`, `South`, `West`, `Global`, `Dewpoint` and `Sky
  temperature`, in any order, the first occurrence winning: cells 1 to 12 are the months into
  `monthly` (`air_c`, the `rad_*_kwh_m2` rows, `dewpoint_c`, `sky_c`), and cells 13 to 15 of the
  temperature and five radiation rows are Heating 1, Heating 2 and Cooling into `peak_loads`
  (`air_c`, `rad_*_w_m2`). The dewpoint and sky design cells are notes, so those peak values are
  null. The row holding `Wind speed` gives the cells after `Jan` and `Jul`. A number is plain
  decimal with an optional exponent; a comma is not a decimal separator. Name, latitude (within 90),
  longitude (within 180), height and every month and numeric design cell are needed: a missing row,
  a short row or a non-number raises `Unreadable` naming the row (`header`, the series label, `Wind
  speed` or `file`) and no value. The swing and the two winds read null when absent. Nothing is
  guessed: no default swing, wind or offset.
- **Walk** (`FolderScan`): every visible file under the folder; hidden names are skipped and links are
  not followed. A station is a `-mon.txt` file with a name before the suffix whose header reads: the
  list is read from headers, and a file whose series rows do not read is refused at attach. The series
  and wind rows are looked for after the header row only. Its `key` is its path relative to
  the folder, its `state` the name of the folder it sits in, and its matching name the file name's
  stem (C4c-2: unique in a state folder, where header names may repeat). Everything else is counted
  by lower-case extension. Past 20,000 entries (hidden ones counted as
  they are read) or 16 folders deep, or at a folder that cannot be listed, the walk stops there and
  reports `complete: false`. An extension is cut at 16 characters before counting.
- **Attach** reads only a key the walk lists, never a key joined onto the folder. The record's `name`
  is the header's name; `provenance.station_name` is the stem, `provenance.state` the state and
  `source_checksum` the SHA-256 of the bytes read. Attach and Replace are two actions because an
  action has one Undo name; both are guarded by the request's `expected_revision`, so no station
  value travels in params.
- **Station picker** reads one folder whole with `stations.all`, `stations.list`'s rows unpaged
  (`response.bounded: false`): a 1,007-station folder is 19 bounded pages, and the picker shows them
  all on one map. It holds no rule: the order, the limit check and the verdict are the host's.
- **Source status** walks every folder found, matches stem and state (a `-mon.txt` whose header no
  longer reads still matches, and reads `changed`), then compares SHA-256: `found`,
  else `changed`, else `not_on_this_computer`; `not_applicable` for a hand-entered climate or none.

### Reading the site and climate from another feature

A feature that needs the Model's climate requires `ph_composer.climate` and reads it through its
registered queries, never Climate's settings dictionaries or record store. Mechanical's blended heat
pump reads `ph_composer.climate.climate.get` for the twelve monthly mean air temperatures and
`ph_composer.climate.design_temperatures.get` for the two design temperatures and their state; a
heat pump left out for want of them is Mechanical's finding. A sun-path view or a window overlay, when built,
reads the site and the monthly radiation the same way. These reads were confirmed on SketchUp 2026
in Climate's integrated host run.

## Geometry records and occurrence references

Records are canonical JSON under registered `ph_composer.*` dictionaries. A read never creates a
dictionary. Unknown keys outside `user_data` and `extension_data` make a record unreadable at its
declared version. Entity stores resolve an explicit occurrence reference to an entity before any
access and never fall back to selection, display name, proximity or the active Model.

| Owner | Dictionary | Entity | Durable identity |
| --- | --- | --- | --- |
| Zone | `ph_composer.zone` | Zone Group | `zon_` id |
| Zone membership stamp | `ph_composer.zone_stamp` | Classified Face | Zone id plus Building-Segment and Level, as recovery data. Only Zones writes it; it is never read as Space membership |
| Face assignment | `ph_composer.face_assignment` | Face | `fac_` id |
| Attached zone | `ph_composer.records.ph_composer.face_assignment.attached_zone` (a legacy name, kept so saved Models still read) | Model | `atz_` id through the record engine |
| Thermal bridge assignment | `ph_composer.thermal_bridge` | The `Sketchup::Edge`, inside a Zone | `tbe_` id; values `thermal_bridge_type_id` (a required core reference to `ph_composer.thermal_bridges.type`) and `quantity` (above 0, default 1). A split or copy carries the id, which reads mark `copied` and nothing re-issues |
| Window unit | `ph_composer.window_unit` | The Unit's ComponentInstance | `wun_` id; values `window_type_id` (a core reference to `ph_composer.windows.window_type`) and `anchor` |
| Window definition mark | `ph_composer.window_definition` | The generated ComponentDefinition | `window_type_id`, plus optional derived `generated_size_m` (`width_m`, `height_m`) used only to repair a Unit whose Type is gone |
| Pane stamp | `ph_composer.window_pane` | Each pane Face inside the definition | None; `window_type_id` and `element_id` as recovery data for Restore |
| Space | `ph_composer.space` | The Space Group | `spc_` id; `name`, `number`, `default_height_m`, `next_volume_sequence`, and the optional airflows `v_sup_m3h`, `v_eta_m3h`, `v_tran_m3h` (absent is unset, distinct from 0) |
| Volume | `ph_composer.space_volume` | A Volume Group directly inside a Space | `vol_` id; `number`, `display_name`, optional `avg_ceiling_height_m`, `floor_id` (the logical Space Floor, `flr_`), optional `home_transform`, optional `floor_user_data` (the Space Floor's own map) |
| Floor Segment | `ph_composer.floor_segment` | A Face directly inside a Volume | `fsg_` id; `display_name`, `weighting_factor` and `net_area_factor`, each 0 to 1 |
| Spaces settings | `ph_composer.spaces_settings` | Model | None; `last_height_m`, the height new Spaces take, null until entered |
| Primary definition index | `ph_composer.window_definitions`, key `index` | Model | None; `{ "schema_version": 1, "definitions": { "wnt_...": persistent_id } }` |
| Piping group | `ph_composer.piping.group` | A Group at the Model root or in plain Groups, outside every Zone and Piping group | `ppg_` id; `hot_water_system_id` (a core reference to `ph_composer.mechanical.hot_water_system`, null while unlinked). Claims its Group. A paste carries the id, which reads mark `copied` (see "Hot water piping") |
| Pipe assignment | `ph_composer.piping` | A `Sketchup::Edge` directly inside a Piping group | `ppe_` id; `pipe_type_id` (a core reference to `ph_composer.piping.pipe_type`, null after a type delete with null), `role` and the role's values. A split or copy carries the id, which reads mark `copied` |
| Ducting group | `ph_composer.ducting.group` | A Group at the Model root or in plain Groups, outside every Zone and Ducting group | `dcg_` id; `ventilator_id` (a core reference to `ph_composer.mechanical.ventilator`, null while unlinked). Claims its Group. A paste carries the id and the Ventilator, which reads mark `copied` (see "ERV ducting") |
| Duct assignment | `ph_composer.ducting` | A `Sketchup::Edge` directly inside a Ducting group | `dce_` id; `duct_type_id` (a core reference to `ph_composer.ducting.duct_type`, null after a type delete with null), `direction` (`outdoor_air` or `exhaust_air`) and `quantity` (integer, at least 1). A split or copy carries the id, which reads mark `copied` |
| Shading mark | `ph_composer.shading` | A Face, Group or ComponentInstance, inside a Zone or not | None; `{ "schema_version": 1 }` with optional `user_data` and `extension_data`. Claims nothing; excludes from the envelope (see "The shading mark") |

The Face values include an optional `assembly_id` reference to
`ph_composer.assemblies.assembly`. An absent assignment and a dangling reference are distinct read
states. Assembly-only assignment preserves Face type, boundary condition and reciprocal Surface
pair data. Explicit targets carry their complete `expected_values`; the compound gesture refuses
all writes if any target is stale or unreachable. Assembly delete may omit replacement (ordinary
in-use refusal), name a replacement, or explicitly pass null to clear all references through the
registered referrer handlers. Definitions never name Zones or Faces.

**Interior pair Assembly.** A Surface pair is one interior element. Its two sides name no Assembly,
or both name one Assembly and exactly one side stores `assembly_reversed: true`; that side exports
the construction with its layers reversed (`ph_composer_<assembly id>_reversed`), so honeybee's
reversed-layer check passes. The Face a gesture names for its Assembly (`assign_assembly`, or
`classify` with an `assembly_id` intent) is the authored side and its counterpart is written in the
same proposal; when a gesture names both, the first is authored. Solve adjacencies settles a new pair
whose sides share one Assembly, or where only one side has one. A Face leaving its pair drops
`assembly_reversed` with `adjacency`. An Assembly is required on a Surface Face only when its
counterpart's Zone is in another Building-Segment; within one, the pair may export with no
construction, honeybee's default interior construction applies and PHX drops the pair. A pair that
breaks this rule blocks export (`face.assembly_pair_mismatch`).

A Face target uses this reference shape; a Zone target carries only `zone_id` and `zone_path`:

```json
{ "zone_id": "zon_...", "zone_path": [4812, 4820], "entity_path": [4901], "entity_id": "fac_..." }
```

`zone_path` is the root-to-Zone persistent-id path, including plain wrapper Groups. `entity_path`
starts inside the Zone and ends at the target. Persistent ids locate candidates; durable ids prove
identity. Resolution verifies every parent-child step and the Zone record and never searches by
name or geometry to repair a stale path. Mutation accepts only a unique, writable target: a path
through shared component storage, a locked Group (above the Zone or inside it) or another Zone
refuses with its `target.*` code.

Zones is the only owner of that resolution. The Face reference target declares it as its `locate:`,
and a feature that requires Zones reaches the live Face through `request.locate`, with these same
refusals (see "Handler-side dependency reads"). A reference with no `entity_id` refuses a Face that
has since gained a record (`target.changed`). A feature that holds a native path rather than a
reference, a pick or a glued instance, reads `ph_composer.zones.faces.host_context`: each path
naming a Zone Face answers its reference, its values and its `write_refusal`: the `target.*` refusal
a write to it meets from its path alone (a shared, nested or locked Zone, or locked or shared
storage on the path), or null. It scans only the collections along each path, never the whole
Model, so a viewport tool may call it on a pointer move. A duplicated Zone or Face id needs a walk,
so `write_refusal` cannot show it and the write still resolves strictly. Zone state needs every
Zone occurrence and stays in `ph_composer.zones.all`.

### The shading mark

Shading (`ph_composer.shading`, requiring Zones) keeps one record with no identity on a Face, Group or
ComponentInstance. A **Shading Face** is a Face carrying the mark, or one whose root path passes through a
marked Group or ComponentInstance with no Zone Group between that container and the Face. A claimed entity
anywhere on the Face's path, the Face included, means it is never one, however near the mark. Its target reference starts at the Model root:

```json
{ "entity_path": [4812, 4901] }
```

Resolution verifies every step by persistent id and never searches; a step that is missing, repeated or
not a container refuses the whole command (`target.not_found`, `target.ambiguous`). `shading.assign` and
`shading.clear` take up to 250 references and answer `assigned` (or `cleared`), `unchanged` and
`left_out`, each `left_out` row with its code and message. What can change is written in one step, one
Undo entry; nothing else is touched. The command refuses whole only when every target is left out, with
the first row's code and the whole result as `detail`; with only `unchanged` targets it completes with
effect `none`. Assign leaves out, in this order: an entity that is not a Face, Group or component, or is
claimed or inside a claimed entity (`target.wrong_kind`); a cutting component or anything inside one,
Window Units and their panes included (`shading.cutting_component`); a Zone Group or a container holding
one (`shading.zone_target`); a container holding a claimed entity (`target.wrong_kind`); a Zone Face with a
Face record, whatever its values (`shading.face_classified`); then a write through storage another
placement shares (`target.shared_definition`: a component placed more than once or a copied Group above
the target; a component placed once is not shared) or through a lock (`target.locked`). Clear leaves out
only an entity that is not a Face, Group or component (`target.wrong_kind`), a marked entity whose path
refuses the write (`target.shared_definition`, `target.locked`) and an unmarked entity shading through a
marked container above it (`shading.inherited`, naming that container); an unmarked Zone Group, cutting
component or claimed entity, or anything inside one, is `unchanged`, since no mark above reaches it. Reads go by presence, so an unreadable mark still marks:
assign leaves it unchanged and clear removes it. `shading.selection` answers the selected Faces, Groups and
components under the active path with what each action would do, by the same rule. It is the read behind the
Set as Shading and Clear Shading menu items (`features/shading/declarations/menu.rb`): Set as Shading is offered
on a right-click when assign would mark a selected entity, Clear Shading when one carries the mark, and both
always sit in Extensions > PH-Composer; their handler invokes assign or clear with the read's references and
revision and writes nothing itself. `shading.list` answers
every marked entity and each shading component (`display_name`, `face_count`, world `area_m2`), from
Zones' walk of its occurrences and one walk of the Model. A component is named by the nearest enclosing named Group or component (an instance's own name before its definition's), a Zone as
that container giving its name followed by " Shading", and "Shading" with none. A name the artifact guard would
read as a local file path (`Diagnostics.absolute_path?`) counts as none, so a Group's name never blocks an
export. A classified Zone Face that is shading only through a container is not a Shading Face to the list,
Colour-by or export: classification wins (`Reads.exported?`, the one rule all three apply).

The Colour-by mode `ph_composer.shading.by_component` (label "Shading", `entity_kind` `face`,
`features/shading/colour_modes.rb`) gives one entry per Shading Face occurrence by the rule `shading.list`
applies (`Inventory.shading_face?`), with its root path and world transform, keyed and labelled by the
component name, each name its own colour (`ColourBy::Palette.spread_entries`); an unmarked Face has no entry.
Each entry's figure is its world area, so a legend row reads the component's Face count and area in the
display units. A Face whose transform flattens it is `incomplete` with no area, so the mode stays on. The
projection reads what `shading.list` reads, Zones' occurrences and one walk of the Model, once per rebuild;
a committed assign or clear advances the revision and rebuilds it.

The mark's store is constructed with `excludes_from_envelope: true`. `Records::EntityStore.envelope_excluded?
(inside)` is true when an entity in `inside` (from the first entity inside the Zone Group down to the Face,
as Zones' `holding` returns it) carries an excluding store's record and none is claimed;
`envelope_excluded_entries?(entries)` applies the same rule to detached snapshot entries through their
`dictionaries` map, and `claimed_entries?(entries)` is `claimed?` over them. All read by presence and name no
feature. Zones reads them at every call site
("Zones geometry rules", "Envelope exclusion").

`ph_composer.shading.export_preflight` is the Shades section's preflight, in `Export::PREFLIGHT_RESULT`, so
every export reads it. Its notes: `shading.zone_inside` names each marked Group or component that is a Zone,
holds one, holds a claimed object or holds a cutting component such as a Window Unit, which the mark does not
reach; `shading.classified_inside` names each marked Group or component inside a Zone that holds classified
Faces, which stay envelope (assign refuses such a Group with `shading.face_classified`, naming the count), and
a container that also holds a Zone, a claimed object or a cutting component takes both notes;
`shading.geometry_invalid` and `target.ambiguous` name a Shading Face the section leaves out; and
`record.unreadable` names a mark whose text is not a JSON object with object metadata maps; any metadata map it
holds that is an object is still read, so a required envelope beside a malformed `user_data` still refuses. A
container name that reads as a local file path is left out of these notes as it is left out of component names,
since they join every export's result. A mark's
`extension_data` the left-out rules refuse, and a Shading Face whose transform is singular, are blocking rows,
as they block the export for any record or Face. Each row names its path in its message and carries
`object_id` `shd_` and a digest of that path, the id the section's note for the same condition uses, so the
export lists each condition once and two marked Groups give two rows. No row has a `locate`: Shading has no
locate command.

**Containment.** `ph_composer.zones.containment` answers, for each root-to-entity path, the Zone
occurrence holding the drawing element at its end (`zone_id`, `zone_path`, `name`, `building_segment`,
`level`), the `entity_path` from inside that Zone, and its `write_refusal`, read along the path
alone. One read over many paths, here and in `faces.host_context`, scans each collection it steps
into once (`Zones::ChildLookup`), so its cost grows with the paths asked, not with paths times
siblings. The Zone is the innermost one above the element, by the rule Face picking applies; with no
Zone, `reason` says why: `not_found` (a step missing or repeated), `not_a_drawing_element`,
`cutting_instance`, `outside_zone` or `outside_envelope` (a Face inside a Zone that has left its envelope).
`faces.host_context` stays Face-only over
the same code. A feature whose reference target stores records on other elements inside Zones
resolves its Face-shaped reference with `Zones::Occurrences.resolve_element(model, reference, noun:,
mutable:, index:)` from its `locate:`, which has no request: Zones resolves the Zone and every step and
refuses what a write meets, and the owner checks the element's kind and its own record. The
thermal-bridge Edge target (`ph_composer.thermal_bridges.edge`) does this, and refuses no duplicated
`tbe_` id. A type delete with `replacement_id` rewrites, or with null removes, every Edge naming the
type in the same step, passing them as the `reference_plan`; an Edge it cannot reach (outside every
Zone, in shared storage, locked) refuses the whole delete as `reference.in_use`.

A Window unit target is reached from the Model root, not from a Zone, because a Unit may sit
outside every Zone and still blocks deletion of its Type:

```json
{ "unit_id": "wun_...", "entity_path": [1201, 1203] }
```

`entity_path` is the root-to-instance persistent-id path. The reference target id is
`ph_composer.windows.unit`; its occurrence inventory includes Units outside Zones and every
placement of shared storage, so a pasted orphan or a repeated parent still makes a duplicate id
visible.

A Space, Volume or Floor Segment target is reached from the Model root too, as `{ "space_id" |
"volume_id" | "floor_segment_id", "entity_path" }`: a Space may sit outside every Zone. See "Space membership".
The Spaces inventories include every placement of shared storage and every record found where the
hierarchy does not put it (a Volume outside a Space, a Floor Segment not directly in a Volume).

**Space membership.** A Space's Zone is the `zone_id` core reference on its record
(`ph_composer.zones.zone`), wherever its Group sits; nothing derives it from the Group's parent or a stamp.
Reads resolve it against the Zones read (the first occurrence in path order for a repeated id, which carries
its own finding). A record with no `zone_id` reads `space.outside_zone`; one whose `zone_id` names no Zone
occurrence reads `space.zone_missing`, blocking export, with the repair `ph_composer.spaces.unhost`, which clears
the reference. Zones have no delete operation: a Zone is erased natively, so the Space survives it and the finding
offers the repair, in a later step of its own (W6-9 of the Spaces packet). `ph_composer.spaces.move_to_zone` is a
record edit in any edit context. Export keys each Space by `zone_id`.

Create Space takes Faces loose in the open edit context: the root, a plain Group or a Zone's own context
(`Spaces::CreateFaces`). It never nests: from an open Zone the Space Group is placed in the Zone's parent at the same
world position (W6-2), and a Face in a Group within a Zone is left out. `create_preview` names the Zone to preselect: the open
Zone, otherwise the first whose plan footprint holds the outlines' centroid and whose height range holds them
(`Spaces::ZoneInference`), otherwise none. `create` takes a `zone` or none. Space and Volume Groups are Untagged and no
tag is created (W6-4). A closed solid is refused (W6-7). `create` takes the Faces the preview would accept and leaves
the others out, never refusing for them alone; its result repeats the preview's `accepted` and `left_out`, and each
Volume in it (and in `volumes.create`) names the `faces` it was made from, in `floor_segment_ids` order. The panel's
review sends only the accepted Faces at the revision it read, so a changed Model refuses `revision.stale` rather than
taking a different set; a caller binds a reviewed set the same way. No strict all-or-nothing mode exists.

Erasing or exploding Spaces structure (`delete`, `remove`, `volumes.delete`, `volumes.remove`) first checks whether
another store's record sits on the Group or below it (`Records::EntityStore.check_subtree_removal!`) and refuses
`target.foreign_records` with the dictionaries and paths if one does, so a Zone record on a Space Group or on a
component inside it, a classified envelope Face or a thermal-bridge Edge is never erased with it. `create` takes
Faces from the open edit context whatever order they are named in; it refuses `space.context_required` only when
no named Face is in that context.

Copies follow one contract (W6-10). A copied Space, alone or inside a copied plain Group, takes a new id and keeps
its `zone_id`. A plain Group copied whole is first given its own storage through
`ph_composer.zones.isolate_copied_group`, by whichever copy watcher runs first (`Zones::CopiedGroups`, idempotent).
The Zones watcher passes the gesture's added containers as `copy_added` to `ph_composer.zones.make_independent`,
and the Spaces contributor rewrites `zone_id` to the new Zone id on every Space under the Zone's own added container
that named the old Zone, in the same Undo step; a Space whose Zone stayed behind keeps its reference. A multi-select
copy with no wrapping Group adds separate containers, so its Spaces keep their references. Neither watcher depends on
running before the other: each binds by record and path at apply.

**Copied Unit identities.** A native copy duplicates the Unit record, so several occurrences can
carry one `wun_` id. Reads report the copy and never repair it. The next Windows action repairs
it inside its own proposal, before anything else that action proposes, from the Windows authoring
coordinator (`Windows::Authoring`) or the Unit action itself: the occurrence first in path order keeps the id and every other copy
gets a fresh one, with `user_data` copied verbatim and structured extension data copied through
its declared rules (`copy.rule_missing` when they are unavailable). Copies behind shared parent
storage refuse as `target.shared_definition`; a locked copy refuses as `target.locked`.

**Primary definitions.** Each Window Type has at most one primary generated definition, named by
the index above. Make Unique copies the definition mark, so a mark alone cannot identify the
primary: the index and a matching mark together do. A Type rewrite changes only the primary and
leaves detached definitions alone. Ordinary mutations refuse a missing or differently stamped
primary as `window.definition_missing`. An index write checks the authored pre-image
(`target.changed`) and that each pointer names exactly one definition carrying the same Type,
inside the owning native proposal and Undo step. Reset to type is the explicit reassociation: it
regenerates the primary from the authored Type, creating a new one when the indexed primary is
missing or differently stamped, and never adopts an arbitrary matching copy.
Definition names are presentation.

### Reading shading from another feature

A feature never reads Shading's `ph_composer.shading` dictionary. A feature that walks a Zone's Faces itself
reads Zones' classification-aware test, `Zones::Occurrences.envelope_excluded?(inside)` (live, as Spaces'
candidate Faces do) or `Zones::ExportProjection.outside_envelope?` (snapshot), so a Shading Face is never one of
its Zone's Faces and the check names no feature ("Zones geometry rules", "Envelope exclusion"). Those wrap the
foundation's `Records::EntityStore.envelope_excluded?` and `envelope_excluded_entries?` and add that a classified
Face stays in the envelope unless the mark is on the Face itself; the foundation checks alone would drop a
classified Face under a marked Group ("The shading mark"; context/EXTENSIBILITY.md, the claims and envelope
exclusion paragraphs). A feature that
needs the shading components reads `ph_composer.shading.list`, which applies the one rule the Colour-by mode and
the export apply (`Reads.exported?`: classification wins). The Shades section `ph_composer.shading.export.shades`
("Translation sections and artifacts") is the only writer of orphaned Shades. PHX groups every orphaned Shade
in the Model by `display_name`, whichever section wrote it, so a later writer of shading geometry (a whole Zone
as shading, for one) shares a name only where it means one shading component. These reads, the menus, the Colour-by mode and the export were confirmed
on SketchUp 2026 in Shading's integrated host run (2026-11-20). Ed opened the PHX output in WUFI-Passive and
in METr and reported no problem; WUFI-Passive's handling of a holed Face was not observed separately.

## Managed Zone field options

Zones owns Building Segment (`ph_composer.zones.building_segment`, `bsg_`) and Level
(`ph_composer.zones.level`, `lvl_`) records. Each has a name and validated six-digit hex colour;
Segment has an immutable, collection-unique export identifier. Names compare without case after
trimming and collapsing whitespace, hyphens and underscores. Model-owned option settings hold
`default_segment_id` and source-model identity; reads never seed records.

Zone schema 3 stores a nullable `building_segment_id` and a nullable `level_id`: a Zone belongs to
at most one Building Segment, and null is No Building Segment. Make Zone, adoption, and every edit
or option rewrite that changes a managed Zone's values or evidence write schema 3, membership stamps
included; a metadata-only write keeps the stored version. Schema 2, the same shape with a required
`building_segment_id`, and version 1 remain readable. Unknown versions refuse. The `choice_evidence` capsule on Zones and membership stamps carries
versioned option definitions and source identity for native clipboard recovery: the Level record
whole, and of the Building Segment only its `id`, `schema_version`, `name`, `colour` and
`export_identifier`, so its maps and other features' settings stay on the Segment and adopting a
copied Zone brings a Segment that reads its defaults; it is detached
recovery evidence, not assignment authority; it carries null for an option the Zone does not name.
Managed read rows expose resolved presentation names/colours separately as `display`. Missing/foreign
choices require explicit destination adoption; a Zone naming neither a Segment nor a Level has
nothing to adopt, and in a Model with no option settings yet its evidence keeps the source it names;
the first option such a Zone is given creates the Model's settings and default Segment.
Option rewrites validate every Zone and stamp they write. In a managed Model, export preflight also blocks legacy Zones pending adoption. A wholly legacy Model retains its compatible export path. Export
leaves a Zone in no Building Segment out (see "Building Segments at export").

The `ph_composer.zones.options.*` operations publish collection reads, usage, guarded definition
writes, complete-draft management, read-only adoption preview and atomic adoption. Management validates the
whole final collection and default, retargets live and recovery references, and commits one native
Undo step. Name/colour changes preserve assignment and export identities. Used deletion requires an
explicit destination: a survivor, or null, which clears a Level or moves a Building Segment's Zones
to No Building Segment. The Model keeps at least one Building Segment: a draft or removal that would
leave none refuses `zone.option_last_segment`. The default is never null. Removing the default
moves it to that Segment's destination, or, when the destination is null, to the first remaining
Segment in the final collection's order (id order for `remove`); `manage` applies this when it is
sent a null `default_segment_id` while removing the current default. `manage`, `remove` and `merge`
report each removed option's `user_data` keys (`removed_user_data`) and its extension namespaces
(`removed_extensions`, the first 50 in id order, with `removed_extensions_total`): another
feature's settings on a Segment go with it in the same Undo step.
`ph_composer.zones.update_field` with `field: building_segment` and `ph_composer.zones.update`
accept null for the Segment, guarded by the values last read, as one Undo step. Stamps have a detached reference projection whose diagnostic
`id` is `zone_id`, keyed by exact root-to-member path; synthetic IDs never enter stored stamps.

Adoption inventories all stamps, including those hidden from Restore by a live Zone ID. Equivalent
legacy names require explicit survivor mapping via `target_source` or an existing destination ID.
It converts choices, Zones, stamps and defaults atomically, preserving geometry identities and
metadata. Adopted Segment export identifiers keep the legacy `bseg_` + 16-character SHA-256 name
hash; conflicting foreign export keys require a survivor and never silently re-key.

Older string writers can resolve existing unambiguous choices on managed Zones; unknown names
refuse. Before adoption, ordinary name/depth edits preserve legacy fields, but category edits and
Make requiring new defaults request adoption. Make Zone puts the new Zone in the default Segment;
Restore recovers a null Segment as null. Colour-by Building Segment shows Zones in no Segment as one
neutral row, "No Building Segment". The published descriptor names current schema 3;
owner validation handles every version without adding generic base-record migration machinery.

Zone export section 2 emits resolved names plus managed Segment ID/export key. Python supports
sections 1/2 and legacy records, groups managed Rooms by identity, and refuses conflicting exported
identifiers before attachment. Room `ph_composer` metadata retains the resolved names. Native-host
and distribution acceptance remain separate from these implemented branch contracts.

## Zones geometry rules

**Envelope exclusion.** A Face inside a Zone leaves the Zone's envelope when
`Zones::Occurrences.envelope_excluded?(inside)` holds: the Face itself, or a Group or component between
it and the Zone Group, carries the record of a store built with `excludes_from_envelope: true`, and none
of them is claimed (`Records::EntityStore.envelope_excluded?`). A classified Face (a Face record present,
readable or not) leaves only by a record on itself: a record on a container above it leaves the Face in the
envelope, so classification wins. `inside` starts inside the innermost Zone,
so a record on the Zone Group or above it never reaches the Zone's Faces. Only a Face leaves; an Edge or a
container beside it reads its Zone as before. The rule is applied in four places, and every Zones read and
write goes through one of them: the Face walk (`walk_faces`, behind `faces`, `Zones::Index`, faces.list
and faces.all, Suggest classification, the unclassified rows, the Zones view's counts, Colour-by, Solve's
candidates and cuts), the point read (`holding`, behind the Classify
tool, the selection read, `faces.host_context` and `zones.containment`, which answers `outside_envelope`),
the reference resolve (`resolve_face_path`, which refuses `face.outside_envelope` for reads and writes
alike, without saying why) and the export snapshot (`ExportProjection.zone_faces`,
`envelope_excluded?` and `outside_envelope?`, behind the Zones and Faces sections). An excluded Face that
still carries a Face record (the record on the Face itself, as a paste can leave it) stays in the Model and
leaves the export; a Surface partner pointing at it is omitted as `adjacency.unresolved`. Spaces' candidate Faces
read the foundation check themselves. Identity maintenance is not an envelope read: the stamp writer and
Zone copy repair walk every member Face (`Occurrences.member_faces`), so an excluded Face's stamp and record
stay in step with its Zone and it rejoins the envelope intact when the mark is cleared. Face-record id
inventories and Restore offers do not apply the check either.

**Clear classification.** `ph_composer.zones.faces.clear_classification` removes the records of explicit
classified Faces in one Undo step, so each reads as never classified; the Zone stamp stays. It refuses
whole with `face.surface_paired` for one side of a Surface pair (retire the pair with Classify first),
`face.aperture_host` for a Face carrying a glued cutting component, and `reference.in_use` while another
record names the Face.

**Cutting components.** A ComponentInstance whose definition cuts an opening owns its contents.
Those Faces are excluded from Zone discovery, Face inventories, classification, viewport picks
and explicit Face resolution. The shared export snapshot retains instance and record facts,
including nested instances, but excludes all descendant Faces from Zone geometry. This allows
Window export to account for Units inside foreign cutting components and refuse invalid hosts
instead of silently omitting them. Definition facts are detached once per definition and captured
in resumable work units; a contributor never walks the live Model again.

Solve reports `adjacency.glued_instances` when a proposed partial match would cut a Face with
glued instances. A full match still pairs. A wholly covered glued side may pair while its larger
counterpart is split, because that glued side is not cut. Detached cut permissions enter the
proposal digest separately from the unchanged geometry digest; the apply step checks live glue
on every cut side before the first split. Native split primitives check it again.

**Adjacency pair.** Each side of a Surface pair stores the same `pair_id` and both directed
endpoints:

```json
{ "schema_version": 1, "pair_id": "adj_...",
  "self": { "zone_id": "zon_a", "zone_path": [1], "entity_path": [11], "entity_id": "fac_a" },
  "counterpart": { "zone_id": "zon_b", "zone_path": [2], "entity_path": [22], "entity_id": "fac_b" },
  "self_geometry": { "digest": "sha256:...", "area_m2": 12.0 },
  "counterpart_geometry": { "digest": "sha256:...", "area_m2": 12.0 } }
```

The geometry digest covers the world plane, oriented normal and every outer and inner loop vertex,
in SI, with negative zero normalized and coordinates quantized to 0.001 mm. Each loop is rotated to
its lexicographically smallest vertex with its direction kept, and holes are sorted by their
canonical vertex sequence. A digest detects change; it never locates or substitutes a target.
Face area is the world-space outer-loop area minus actual inner-loop areas. Glued component
cutouts that do not create inner loops do not reduce this gross area. SDK `Face#area` is not
the source for this value.

**Solve recovery.** Explicit Solve may recover a changed stored endpoint path only when its Zone id
names exactly one live Zone and its Face id exactly one live Face occurrence, both old envelopes
agree on the pair, and every surviving endpoint is in the caller's scope. Retirement and new
pairing share one transaction. Geometry never selects an identity.

**Splits and copies.** A native split copies the whole Face dictionary to every piece, so copied
`fac_` ids and adjacency envelopes are ambiguous data, not relationships.

- A plugin-owned split keeps the existing Face id on the piece that keeps the original persistent
  id; every other piece gets a fresh id. If the original persistent id does not survive, every
  piece gets a new id and the old endpoint is retired, after incoming references are checked.
- Non-Surface core fields and `user_data` copy to the pieces; installed extension data follows its
  copy rules. Unsafe or unavailable extension data refuses the operation before any write.
- Every copied adjacency is removed before new pairs are proposed. A surviving counterpart must be
  in the declared mutation scope or the operation refuses. Geometric similarity never keeps a pair.
- Split identity repair keeps one identity, using the stored original endpoint path or an explicit
  choice when that proof is absent; a choice that conflicts with stored proof refuses. It retires
  invalid envelopes on the pieces and their counterparts and creates no pairs.
- A copied Zone is ambiguous until it is made independent. Make Zone independent
  (`ph_composer.zones.make_independent`) makes the occurrence's own Group unique when it shares its
  Faces, and each Group inside it that still shares its contents, then gives it and its members new
  ids, updates stamps and retires copied pairs, as one step; the other occurrence keeps its id, Faces
  and pairs. It refuses a Zone inside a component, a Zone inside a still-shared parent Group, member
  Faces inside a component or a locked Group, a nested Zone, a lock and an id held only once, each
  with its prerequisite; the Zones read offers it only where its plan succeeds. Identity repair (`repair_identity`) remains for scripts and refuses shared storage.
  Both derive the new Zone id from the occurrence path and each new Face id from the id it was
  copied with (not its entity path, which Make Unique replaces), so a preview's ids hold at apply.
- Limited Restore regroups only stamped Faces and their bounding edges, and stamped nested
  containers, in one parent context and recovers only the Zone id, Building-Segment, Level and a new
  default name.

**Reconciliation.** Zones keeps one state object per session. Observers only mark what changed
dirty and queue a deferred pass, which reports missing or duplicate ids, changed paths and stamps,
and stale pairs. It emits findings and cache invalidations and never solves or edits
classification. It rebinds identity in one case only: a Zone copied natively during the session is
made independent by the copy watcher, through the registered Make Zone independent action as a
host follow-up joined to the copy (D-1). A copy is an occurrence the gesture added whose id one
original holds; a duplicate already in the Model, a copy whose path crosses a ComponentInstance and
anything Undo or Redo restores are left alone. The repair joins the latest transaction; if an
unrelated operation committed before the deferred pass, undoing it takes the repair back with it, and
the watcher tells the user the copy is read only again. A plain Group copied whole is first isolated
through `ph_composer.zones.isolate_copied_group`, joined to the copy ("Space membership"). Spaces follows the
same rule for a Space Group copied alone or inside a copied plain Group (its `CopyWatch`): the Space is made
independent through Make independent with the next free number; a copy inside a component keeps its finding with
one notice, and a Space below a Zone the same gesture copied is left to that Zone's transition. The
Spaces and Zones watchers hear the copy through the session's `container_added` host event, which
reports each Group or ComponentInstance added to any container. Windows' `HostWatch` hears a pasted
Unit the same way and a moved one through `instance_modified`, and returns a Unit that has left its
Face (`units.return_to_host`, D6 of the usability walkthrough) as a follow-up joined to the gesture;
one it cannot return gets a notice in SketchUp and keeps its finding.

**Host follow-ups.** `HostFollowUp.run(session, action, params_list)` is internal; nothing registers
it where the panel or the API can reach it. It runs the registered action's handler once per params
into one proposal, so any refusal declines the whole gesture before a write. It accepts only steps
that answer `restore` and no record changes, applies them in one transparent operation, and never
aborts: on a failure the applied steps restore in reverse and the operation commits. It answers an
internal result (`completed`, `refused` with the code and message, or `failed` with whether every
step restored) for the caller's notice, not a public outcome, because storage isolation done before
the failure remains.

## Handler-side dependency reads

`request.query(name, params = {})` returns a detached registered query result in the caller's
current read or proposal phase. It keeps the same Model session, engine and revision; it does not
re-enter the public dispatcher or open an operation. The target must belong to the caller or to
one of its explicitly required features. Each nested read uses its own owner's dependencies.
Input and result schemas and plain JSON checks still apply. Unknown query names, undeclared
reads and recursive query chains refuse with `operation.query_missing`,
`operation.dependency_missing` and `operation.query_cycle`, respectively. A nested query has no
action proposal and cannot call reference retargeting. View/session state changes remain view
commands; queries never change that state.

Colour-by projections, native menu `available:` tests and `menu_entries` providers receive the
same request with no params and no proposal, built by the shell under the declaring feature's owner
(`HandlerRequest.for`). Features never build one, and none of these callbacks connects to the
public API, so drawing the overlay or opening a context menu issues no caller handle. These reads
do not pass dispatch: they are not refused while the session is busy, and a failing read raises
rather than answering an outcome. The Colour-by service turns a raising projection off with a
notice; the shell logs a raising menu test or provider and leaves out that item alone.

`request.locate(kind, reference, mutable: true, index: nil)` returns the live entity a reference target's
`locate:` resolves, as a `Records::LocatedEntity`: the entity, the collection holding it, its
parent-to-world transform and its parent path. `request.locator(kind)` returns the bound resolver,
which a step keeps and calls again on the live Model at apply, where it has no request.
`request.locate_index(kind)` returns the owner's read-phase index, or nil, for a caller locating
many references before it proposes anything. All three apply
the `query` rule: the target must belong to the caller or a feature it requires
(`operation.dependency_missing`); an unregistered kind refuses with `reference.invalid` and a target
with no resolver with `operation.locate_missing`. The owner's `target.*` refusals pass through
unchanged. A located entity is for reading geometry and gluing to; its records stay the owner's to
write (context/EXTENSIBILITY.md, "Entity-owned reference targets").

A handler request is frozen. The foundation derives a nested one with `request.with(params:,
owner:, proposal:, engine:, query_stack:)`, which shares the caller's memos; feature code passes
values to its operations as arguments and never derives a request (context/EXTENSIBILITY.md,
"Organization and dependencies").

`request.memo(key) { ... }` computes a value once per request and shares it with the nested reads
and callbacks the request makes. A memo is keyed by the current owner, so two features cannot
collide, and by the current engine, so a value read through one engine is never reused under a
projected one (a library callback's). A memo does not observe writes the request stages after
computing it. Memos end with the request.

## Compound proposals

Feature handlers do not write the Model; they add steps to an `Operations::Proposal` of detached
values: record changes, named geometry steps with explicit targets and created-entity slots, the
declared mutation scope, affected references and findings. A proposal participant is a step another
feature composes into its own action's proposal, so a cross-feature effect stays in one proposal and
one Undo step. It adds its changes to the proposal and returns a detached JSON result.

**Participants.** A feature declares one with `feature.proposal_participant(name, description:,
params:, result:, refuses:, examples:, participants: [])`, validated as an operation is. No client
calls it: discovery lists it under `participants` and `describe` returns its contract with `kind`
`participant`. An action, query or participant that calls one names it in `participants:`.
Registration refuses an edge to a participant that is not installed or in the batch, or whose owner
the caller's feature neither is nor requires (`registration.missing_dependency`), and participants
that name each other in a cycle (`registration.cycle`). An operation's published refusals are its
own, the codes of every participant it names through their own edges, and each such participant's
`participant` common set.

A handler calls `request.participate(name, params)`. The foundation checks, in order: the
participant is installed (`operation.participant_missing`); the request has an active proposal,
which a query never has (`operation.proposal_required`); the caller's feature owns or requires the
owner (`operation.dependency_missing`); the calling declaration names it in `participants`
(`operation.participant_missing`); the call is not recursive (`operation.participant_cycle`); the
params match (`params.invalid`). The first that fails is the refusal. The handler then
runs as `->(request, proposal) { value }` under the participant's owner, with an engine projected
from the caller's (`engine.projected(proposal, writable_kinds:, refusal_code:)`) that reads the
proposal's view and stages writes only to catalog kinds the owner registered; any other write
refuses with `proposal.foreign_write`. The same confinement holds however the handler writes: while
it runs, the proposal's change set refuses any record write outside those kinds, a direct
`proposal.put` included (`Records::ChangeSet#guarded`). A projection may derive a further one for the
same proposal, which is how a participant delegates to a kind owner's callback; the callback is
confined to its own owner's kinds for the length of its call. After the handler returns, every
write, step and finding proposed before the call must be unchanged, steps by identity and by
descriptor (`proposal.contribution_replaced`), and the result must match its schema or the call fails. The
caller receives a detached copy. Any failure refuses the whole proposal, so a caller that rescues
it still writes nothing, and a later successful call does not clear the refusal. The outer
dispatcher remains the only owner of the transaction, retry and outcome; a participant opens no
operation. Memos are keyed by engine and owner, so a participant's start empty; a caller's memo
computed before the call is not refreshed by what the participant stages.

Preview builds and validates the proposal without opening an operation. Invoke rebuilds it from the
same inputs and refuses if the revision, edit path, resolution or expected values changed, or if a
supplied preview digest no longer matches (`proposal.changed`). The order is fixed: request,
session, capability and revision; resolve the whole scope and refuse non-unique targets;
participants add their changes; steps validate projected records, references and geometry
feasibility; capture the scoped pre-image; then open one operation, apply the steps in order,
resolve created slots and commit. Each step validates its own writes. A step whose final references exist only
after an earlier part of it runs (Make Unique creating a copy's Faces) binds the logical change
instead: preview and digest cover its id mapping and record contents, keyed without those
references; apply rebuilds the plan from the live entities with the same mapping, refuses
`target.changed` if any record differs, and completes `affected` with the final references.

The pre-image fingerprints the declared containers: kind, persistent id, parent path,
transformation, loops and every `ph_composer.*` dictionary. Coordinates are rounded to six decimals
in SketchUp's internal unit and transformations are compared exactly. An error before the
operation is `effect: none`. After an abort, a matching fingerprint is `rolled_back`; any mismatch
or unreadable target is `unknown` with `operation.rollback_unverified`. Dispatch never attempts a
best-effort repair after an abort.

A definition delete handler calls `request.retarget_references(kind, from: old_id, to: replacement_id)`
inside an action or preview. `to: nil` requests explicit clearing. Both non-null identities must
resolve before any retargeter runs. Every matching `FeatureScope#reference_retargeter` handler
runs in declaration-name order with its own owner on the request, the caller's proposal, and
`from:`/`to:` keywords. It adds validated rewrite steps and returns a `Records::ReferencePlan`.
The foundation combines final entity occurrences belonging to each retargeter's owner, refusing
foreign target kinds or duplicate occurrence rows. The
caller passes that plan to `engine.propose_delete(..., reference_plan: plan)`. Catalog rewrites
already in the proposal are read through its change set. The engine still refuses any incoming
reference left in the final projected state. A retargeter failure marks the proposal refused;
rescuing it does not permit a partial write. The definition feature names no referrer.

**Transition contributors.** A feature that owns records inside another feature's entity joins that
owner's change to the entity without the owner naming it. The owner names a transition, a dotted
string whose prefix before the last segment is its feature id, and lists it on each action that emits
it (`transitions: [...]`). A contributor declares `feature.transition_contributor(name, transition:,
refuses: [])`; registration refuses one whose feature neither is nor requires the emitting feature
(`registration.missing_dependency`), and an action listing a transition of another feature. The
emitting handler adds its own step first, then calls `request.contribute_transition(transition,
description)`; only an action that lists the transition may. Every contributor runs in name order
under its own owner, inside the caller's proposal, with a detached copy of `description` and the same
confinement as a participant: an engine and change set that write only its owner's kinds, and every
earlier write, step and finding unchanged afterwards (`proposal.foreign_write`,
`proposal.contribution_replaced`). It returns the references it affects, each `{"kind", "id"}` of a kind
it owns. Every step it adds must answer `restore`, since a transition can run inside a host follow-up
that cannot abort; there the follow-up asks every applied step to restore, in reverse, even after one
fails. Any failure refuses the whole proposal. An emitting action's published refusals add each
contributor's `refuses` and the two guard codes. A contributor's step usually cannot hold entity
references from preview, because the owner's step replaces them; it binds logically and re-resolves at
apply, as the paragraph above describes.

`ph_composer.zones.occurrence_independent` is emitted by `ph_composer.zones.make_independent`, for
the explicit action and for the copy watcher's follow-up, after storage is isolated. Its description
is `zone_path`, `old_zone_id`, `new_zone_id`, `mapping` (every old Zone and Face id to its new one),
`revision`, `copy_added` (the containers one native copy added, by persistent id; empty for an explicit call)
and `references`, the Zone's and Faces' new records as typed `{kind, key, record}` entries
for remapping a child's own references. Windows contributes `ph_composer.windows.units.follow_zone_copy`:
every Unit inside the occurrence whose id another occurrence holds gets a new id, and copied payloads
are remapped across the copy.

`ph_composer.zones.segment_settings_saving` is emitted by every `ph_composer.zones.save_segment_settings`
after Zones staged the General values and before it stages any settings payload. Its description is
`building_segment_id` and `extension_payloads`, the payloads by namespace as the Save sent them. A section's
owner answers it to write records of its own kinds that a payload is about to name, since Zones resolves each
payload's references as it stages it (Programs stores an unwritten default there); it never writes the Segment.

`ph_composer.zones.segment_settings_saved` is emitted by `ph_composer.zones.save_segment_settings`
after Zones staged the Segment's General values and every settings payload. Its description is
`building_segment_id` and `namespaces`, the namespaces whose payload changed, sorted (empty when
none did). A settings section's owner answers it to add its own side effects in the same Undo step
(context/EXTENSIBILITY.md, "Building Segment settings").

`Records::ReferencePlan.new(entries:, removals: [])` preserves replacement and addition entries
as typed `ReferenceEntry(kind:, key:, record:)` values. A removal is a separate typed
`ReferenceRemoval(kind:, key:, before:)`, with the complete expected record, including metadata.
It never supplies a nil record or hides every occurrence of a UUID. All entry and removal
kind/key pairs must be distinct. The engine admits only registered entity reference targets and
validates both final entries and removal pre-images through their target validators. Projection
requires exactly one current occurrence at each removed kind/key and an exact full-record match;
missing, ambiguous or changed occurrences refuse. Other occurrences sharing the removed UUID
remain in the projected inventory and still participate in resolution and incoming-reference
checks. The owning feature adds the actual removal steps to the same proposal; the plan alone
does not remove entities or write dictionaries.

Nested catalog references use the same `Records::Reference` declaration, supplied separately
from fields through `RecordKind.new(..., references: [...])`. For example, key
`layers[].segments[].material_id` visits the id in each segment; cardinality describes each leaf
(`one` for a string, `many` for an array of string ids). The JSON Schema remains on the containing
`layers` field. Registration refuses unreachable paths or incompatible cardinality. Validation,
incoming scans and collection duplication follow only declared leaves. Metadata strings that
happen to equal an id are preserved. Existing top-level field references retain their shape.

## Library providers and catalogs

The binding numbers and refusal order of the `ph_composer.library` foundation feature. The
contributor contracts are in [EXTENSIBILITY.md](EXTENSIBILITY.md), "Library providers and kind
adapters"; the runtime shape is in [TECH_STACK.md](TECH_STACK.md), "The library provider seam";
the file envelope is in [LIBRARY_FILE_FORMAT.md](../docs/LIBRARY_FILE_FORMAT.md).

| Limit | Value | Over the limit |
| --- | --- | --- |
| One library file, read or written | 32 MiB | `library.file_too_large` |
| One provider's catalog, aggregate bytes | 64 MiB | `library.catalog_too_large` (file provider), `library.catalog_budget` (admission of any provider) |
| One provider's catalog, rows | 20,000 | `library.catalog_too_many_rows` (file provider and export), `library.catalog_budget` (admission) |
| Per-machine provider setup, stored | 256 KiB | `library.setup_too_large` |
| Contract, wire and fingerprint versions | 1 | `registration.*` at install |

An over-budget catalog is refused whole, never truncated. Every provider's response passes the
same admission before it is published: budget, then duplicate record ids and unsupported wire
versions withheld per library and kind, then per-row schema normalization and the adapter's
semantic check. Third-party text never passes admission; diagnostics are reduced to the fields
`code`, `kind`, `library_id`, `record_id` and `index`.

**Catalog notes.** Admission and the file reader attach notes to a published catalog instead of
failing it. Withheld libraries are listed under `unavailable` with `library.duplicate_record_id`,
`library.identity_conflict`, `library.kind_unavailable`, `library.kind_schema_missing`,
`library.kind_schema_unsupported` or `library.kind_malformed`. Skipped or trimmed rows are listed
under `warnings` with `library.row_required_invalid`, `library.row_optional_invalid`,
`library.unit_invalid`, `library.row_semantic_invalid` or `library.row_label_invalid` (the adapter's
`display_label` gave no nonblank text; row skipped), or
`library.row_optional_absent` and `library.row_fields_omitted` (row kept). `library.row_semantic_invalid`
is also an outcome-table code: admission consumes it and skips the row, while an adapter reused
outside admission may raise it as an operation refusal. Copy/review and in-file resolution declare
it because they call mapping/fingerprint and local-read paths. Library export normalizes adapter
errors to `library.adapter_invalid`. Other catalog-only notes are data, not raised operation errors.
A folder provider
skips an unreadable or invalid file with a code-only warning carrying that file's outcome code,
such as `library.file_malformed` or `library.format_invalid`. These are the notes the file
provider and admission produce; another provider may add its own `library.*` codes, which
admission passes through reduced to the note fields. A note is not an outcome.

**Generations.** A session holds one generation counter shared by every provider and kind. A
successful refresh publishes the next integer as an immutable entry, with state `loaded` or
`empty`. A failed refresh keeps the previous entry unchanged except for state `failed` and a
failure carrying its code and a fixed message; a provider exception that is not a `library.*` error becomes
`library.provider_failed`. An entry never read has generation null and state `unloaded`. Setup
changes drop the affected provider's entries in every open session. Nothing is cached to disk.

**Hosted catalogs.** A contract version 2 provider's catalog is loaded by a timer-polled load
(`library/connection/load.rb`). The load command answers `loading` at once. A complete admitted
snapshot publishes the next generation as `ready`, with or without rows, and names its `snapshot`. A
failed load leaves the published generation and rows unchanged and reads `stale` with its failure, or
`unavailable` when nothing was published; a cancelled one reads `cancelled`. A load that has not
answered after 120 seconds fails with `library.load_timeout`. A poll that finds the session closed,
the connection generation moved on or a newer load of the same catalog ends without publishing. The
load command refuses `library.connection_required` or `library.reauthorization_required` unless the
connection is connected; a refused `begin_load` also marks the catalog as a failed load. A snapshot whose source revisions do not name each row once with a positive
integer fails whole with `library.source_revision_invalid`.

**Pages.** `catalog` and `in_file` page through `shell/pages.rb` like every other list: `limit`
(default 100, maximum 500), `cursor` and `next_cursor`, with `total` on every page. Rows keep the
provider's order; a cursor is bound to the generation it was read from, and an `in_file` cursor to
the Model revision as well. A reload refuses it as `library.catalog_stale` when the caller names the
generation, and as `query.cursor_expired` otherwise; an edit refuses an `in_file` cursor as
`query.cursor_expired`.

**Copy.** `ph_composer.library.copy` runs inside the ordinary action order of "Compound
proposals". Its own checks run in this order, each refusing the whole proposal:

1. The named kind has an installed adapter (`library.kind_unavailable`), and the named provider
   is configured and serves it (`library.provider_unavailable`, `library.kind_unavailable`).
2. The supplied `generation` equals the current one (`library.catalog_stale`).
3. Exactly one row has the named library and record id (`library.row_unavailable`).
4. The adapter maps the row to valid mapped values and a lowercase SHA-256 fingerprint
   (`library.adapter_invalid`).
5. The resolver runs: exact source identity (provider kind, library id, record kind, record id)
   first, then a case-insensitive name match and mapped-value equality. Outcomes are `create`,
   `reuse`, `review_required`, `ambiguous_source` and `ambiguous_name`. A stored fingerprint of
   another version reports no comparison rather than a change.
6. The choice, which is required, must fit the outcome. A read of the resolution is `in_file` or
   a preview, never a copy that writes nothing. A supplied `local_id` that is not a reviewed candidate
   refuses first (`library.local_choice_required`); an unknown choice is `params.invalid`. `create` needs outcome `create` (`library.review_required`);
   `keep_local` and `use_library` need one reviewed candidate (`library.local_choice_required`);
   `use_library` needs the candidate's reviewed `expected_values` (`params.invalid`).
7. For a version 2 source and a `create` or `use_library` choice, the use check: the catalog must
   have been loaded under the current connection generation (`library.reload_required`); the
   provider's `authorize_use` must answer `allowed` (`library.reload_required`,
   `library.reauthorization_required`, `library.provider_unavailable`, `library.provider_invalid`
   for another answer, or a code it declares); and, measured from the start of that request, within
   5,000 ms (`library.use_expired`) with the same connection generation (`library.connection_changed`),
   destination Model (`library.model_changed`) and loaded snapshot (`library.selection_changed`).
8. The owner's callbacks run with validated params (`params.invalid`) and results
   (`library.callback_invalid`), then assignment when requested
   (`library.assignment_unavailable` when the adapter has none). A version 2 copy then repeats the
   step 7 window and identity checks, and registers them as a commit check that Dispatch runs again
   immediately before the native transaction, after every participant has staged; its `source`
   carries `source_revision` and `source_revision_schema_version`.

**Library dependencies.** A kind whose rows name records of other library kinds declares them on its
adapter (`Declarations::LibraryDependencies`: `kinds`, `list(mapped)` and `remap(mapped, ids)`,
`library/dependencies.rb`); registration refuses an undeclared or own wire kind
(`registration.missing_dependency`, `registration.schema_invalid`), and `describe` names the kinds. A row
names each such record by its wire record id in the same library; its local copy names the local
record. The Programs kinds are the shipped example: a Program names its Schedules.

- *Resolution* compares the incoming values in local terms: each dependency that already has a local
  copy from the same source (exact source identity) is named by that copy, the others by record id.
  The fingerprint stays the row's own, as its attribution stores it.
- *Copy.* A `create` or `use_library` choice copies each dependency first, in the same proposal and
  Undo step, then the row with its references remapped, and answers `dependencies`, each one's kind,
  record id, local id and outcome (`created` or `reused`). A dependency is read from the current loaded
  catalog of its kind from the same provider and library; a record that catalog does not hold, or a
  kind never loaded, refuses the whole copy as `library.dependency_missing` with its `kind`,
  `library_id`, `record_id` and `catalog_state`. It resolves as a row does: `reuse` takes the local
  record unchanged, `create` copies it (its own dependencies first) with its own attribution and use
  check, and any other outcome refuses as `library.review_required` naming it, until that record is
  replaced from the library (`use_library`, which gives it the source) or renamed. Each record is copied once per copy, however many references name it; a cycle
  refuses as `library.adapter_invalid`. `keep_local` copies nothing. A reused dependency is taken as it
  stands locally, and a row's fingerprint covers its references, not the referenced records' values, so a
  change in the library to a Schedule alone shows on that Schedule's own resolution, not its Program's.
- *Export.* A library export writes each record a written row names, and theirs in turn, even when the
  selection or `kinds` leaves it out, so the file supplies every dependency; one it cannot write (a record
  without a label) refuses the export as `library.dependency_missing`. A declared part's map
  that a row leaves out is listed among the omissions as `<path>.user_data`, such as `devices[].user_data`.

**Callback write ownership.** A create, replace or assign callback shares the caller's proposal.
Its request's engine is `engine.projected(proposal, writable_kinds:, refusal_code:)`
(`Records::ProjectedEngine`): every read (`find`, `ids`, `kind`, `view`, `resolve_reference`,
`incoming_references`, `check_identity_removal!`) answers as the proposal would leave the records,
`find` refusing as the plain engine does (`target.not_found` for a record absent there, a staged
delete included, `record.unreadable` for one that fails its kind), and a write into another change set or to a kind its owner did not register refuses at once with
`proposal.foreign_write`, as does any record write the callback stages directly into the proposal
while it runs. A local read's projection accepts no write. After the callback returns,
every write, step and finding staged before it must be unchanged; otherwise
`proposal.contribution_replaced`. Local reads get no proposal. Any
refusal inside the coordinator or a callback poisons the proposal, so a rescued error still writes
nothing. `ph_composer.library.copy_into_proposal` applies the same rules inside another feature's
action and refuses without that action's active proposal
(`operation.proposal_required`) or when its owner neither is nor requires the library
(`operation.dependency_missing`).

## Building Segments at export

Export writes only Zones in a Building Segment (`Zones::Schema.exported?`: every legacy Zone, and every
managed Zone whose `building_segment_id` is set). A Segment's name with spaces and punctuation reaches
WUFI-Passive and METr as written: converted by PHX 1.59.4, each Variant and its Zone take it
(`tests/python/test_site_phx_round_trip.py`). A name holding control characters is not covered.

- With Zones in the Model and none in a Segment, the Zones preflight and section refuse `zone.no_segment`.
- A Zone in no Building Segment is left out with everything that hangs on it. The Zones section leaves its
  record out and notes `zone.left_out` with its Face count; the Faces section leaves its Faces out; Spaces,
  Thermal bridges and Windows leave out the Spaces, assigned Edges and Window Units in it or on its Faces,
  each noting `space.zone_left_out`, `thermal_bridge.zone_left_out` or `window.zone_left_out` per Zone. Each
  preflight skips what it leaves out and gives the same row as info, so incomplete authoring inside the Zone
  (an unclassified Face, a missing Window Type or Space height, a copied Space identity) never blocks. Their
  sections drop what is inside the Zone (`Zones::ExportProjection.left_out?` on a snapshot path) before
  validating or reading it, and their preflights' metadata checks skip the Zone's contents
  (`Export::MetadataCheck.entity_records(..., skip:)` with `left_out_zones`). A Zone record or thermal-bridge
  assignment that cannot be read still blocks, as does a Zone nested in a Zone.
- Solve pairs coincident Faces whatever their boundary, so while any Zone is left out the preflight's
  Solve repair is offered unchecked, its label saying it pairs those Faces again.
  Features read the rule from the projections: a Zones row's `exported` and a Faces row's `left_out`, or
  `Zones::Schema.exported?` on a live Zone record.
- The Zones projection keeps a left-out Zone's row, so Shading still names a Shade "<Zone> Shading" there,
  stops a mark above it at the Zone, and exports a Face marked as shading inside it.
- A valid Building Segment no Zone names is noted `zone.segment_empty`; it never reaches HBJSON, which builds
  Segments from Rooms.
- A current Surface pair with one side in a left-out Zone refuses `face.partner_left_out` on the exported
  side, naming the Face; a stale one is omitted, as any stale pair is. `ph_composer.zones.faces.attached_zone.offer` names both sides of every such pair,
  and the Zone's name and any Attached zone already of that name; `create_and_assign` (or `classify`, to
  reuse it) makes them AttachedZone in one Undo step, ending each pair. Moving the Zone back leaves them so;
  Solve adjacencies pairs them again.

The Faces section is version 2: an AttachedZone Face carries `attached_zone`, its Attached zone's `id`,
`name` and `temperature_reduction_factor`, and translates to honeybee-ph `PhAdditionalZone` with zone type
"Unheated space", as honeybee-ph's Grasshopper component writes it. PHX 1.59.4 merges a Segment's Rooms
before it collects attached zones, so one Attached zone that two Rooms name reaches WUFI-Passive and METr as
one attached zone, and its Faces' exterior exposure names it; it carries no appliance devices (PHX 1.59.2 and
later), so a Segment's devices are counted once. WUFI XML carries its factor; METr JSON carries
the zone with `typeZ` 2 and PHX's default `TRedUD` of 1.0, not the factor
(`tests/python/test_segment_phx_round_trip.py`). The Attached zone's kind stays in the Model.

## Translation sections and artifacts

A translation section declares its id, the extraction versions it can read and the section ids
and object types it requires. The package's `composition.py` lists the sections; the coordinator
sorts required dependencies topologically, with stable id order for unrelated sections, and names
no feature. A missing dependency, unsupported version or cycle is a structural error before
translation. A malformed document or section contract fails the run as `payload.contract`. A
record-level failure emits an object finding; a consumer whose required object is unavailable
emits its own finding and produces no substitute. Continuing for diagnostics never permits
publishing an invalid canonical artifact.

The Honeybee Model is built by the foundation's model assembly (`assembly.py`), which also names
no feature. A section whose objects belong inside another declares `attaches = Attachment(host,
key)`, with `host` one of `MODEL`, `SEGMENT`, `ROOM` or `FACE`, and implements `attach(host, objects)`.
After every section has run, the assembly attaches the host levels in that order and calls `attach` once
per host with that host's objects, in id order. A `SEGMENT` host is the one honeybee-ph `BldgSegment` the
Rooms of an exported Building Segment share, keyed by its identifier, the Segment's `bseg_` export
identifier; it is attached after every `MODEL` section, so it already carries what those set (the `Site`),
and a section changes it in place and never replaces it. A section checks what one object's own record
shows in `translate`, so `attach` judges only what needs the host. A missing host, or a
`RecordError` from `attach`, is an `object.unavailable` finding on each of those objects;
`AttachmentRefused` names only the objects it refused. The canonical model, `{hbjson, rooms, faces,
surface_pairs}` counted from the assembled Model, is a shell field of the result document; it is
written when the Model holds a Room and no attachment of a section required for export was refused. A
section that sets `required_for_export = False` is optional: an object of it that fails to translate or
attach is left out of the Model with a non-blocking `object.unavailable` finding, and the Model holds the
rest. An optional section's `attach` checks every object before it adds any, so a refused one is never
left half-added. Each section's
`result_fields` are collected after assembly and sit under its id, `result[section_id][field]`; a
section with none has no key. After the export reloads the canonical HBJSON, each section's
`conformance(model, fields)` checks it against that section's own fields.

Spaces is the first section to attach to `ROOM`: `ph_composer.spaces.export.spaces` (Ruby
`features/spaces/export.rb`, Python `space_sections.py`) keys each honeybee-ph `Space` on its Zone
record's id, which is the Room's identifier, and is required for export. A Floor Segment leaves with
its loops projected onto its horizontal plane, so honeybee-ph's area is the plan area the metrics use,
and a Volume with its preview prism as `geometry`. Airflows follow the Zone's airflow mode, which Ruby
decides (`Spaces::Metrics.zone_modes`) and section version 2 carries on each record as `airflow_mode`:
a Zone is `by_program` until any of its Spaces stores a rate, and every Space in it then writes none of
`_v_sup`, `_v_eta`, `_v_tran`, so PHX gives it its floor share of the Room's Program ventilation; once
any Space stores one the Zone is `detailed` and every Space in it writes all three, 0 for an unset
rate, converted from m3/h to m3/s in the section and nowhere else. The section refuses a record whose
mode is missing or that stores a rate under `by_program`. The reads publish the mode on each Zone row
and a copy on each Space row; `ph_composer.spaces.clear_zone_airflows` (From Program) returns a Zone to
By Program in one Undo step. Room ventilation is never written from Space rates. A Zone exported with no
Spaces is the preflight warning `space.zone_without_spaces`, which does not block. Its result fields
total floor area, weighted area and net volume per Zone and per Building-Segment, and its
conformance checks the reloaded Rooms' Spaces against the per-Zone totals. Its `projection`, for another section
that reads each exported Zone's Spaces (Programs' areas and volumes, the Pump export), is one row per exported Zone
that holds a Space, `{zone_id, space_count, floor_area_m2, weighted_area_m2, net_volume_m3}`, the totals 0 for a
Zone whose Spaces hold no Volume.

Record maps follow the object each entity becomes. The Model's own map leaves in the foundation's section
`ph_composer.model.export.model` (Ruby `shell/model_metadata.rb`, Python `model_metadata.py`, attached at
`MODEL`): one record, `{"id": "Model", "user_data"}`, only when the map is not empty; PH-Composer writes no
reserved entry on the Model, and the Model's envelopes follow the left-out rules. A Volume record carries its Space
Floor's map as `floor_user_data`, written on the `SpaceFloor`. An Assembly Layer's map rides on its own
material, the single EnergyMaterial or, when the Layer is divided (more than one Layer-Segment, or a steel
stud spacing), the hybrid host; each Layer-Segment of a divided Layer carries its map on its cell
EnergyMaterial. Material identifiers are scoped by Assembly and Layer, so no two Layers share one, and the
reversed construction reuses the same objects. A membrane Layer, its Layer-Segment (even with a steel stud
spacing) and an undivided Layer's Layer-Segment have no material of their own
(`features/assemblies/export.rb`, extraction and preflight alike); their maps, Window Elements', Thermal Bridge Edges', Attached zones', the climate's and every
definition's (Materials, Frames, Glazings, Psi-Install Types, Window Types, Thermal Bridge Types, Building
Segments and Levels) stay in the Model with one `export.metadata_omitted` finding per entity, used or
not: the Zone section passes every valid Building Segment and Level through the boundary once
(`Zones::ExportProjection.exported_choices`), and a finding repeated by a second read is listed once. Every carried map passes the reserved-key rule, extraction and
preflight alike, and the artifact guard's local-path check.

Thermal bridges are the first optional section: `ph_composer.thermal_bridges.export.thermal_bridges` (Ruby
`features/thermal_bridges/export.rb`, Python `thermal_bridge_sections.py`) writes one record per run, built
by the same run functions as the schedule from the snapshot's assigned Edge entries, and attaches at `ROOM`,
adding each honeybee-ph `PhThermalBridge` to the Room's shared `ph_bldg_segment`. Its only `user_data` is
the declared `ph_composer.thermal_bridge_type_id`: a run joins many Edges, so no Edge's own user_data
leaves. A missing type or psi-value refuses the section; every other finding is a note, and an Edge no Zone
holds is left out with one. Its result fields list each attached run's length, psi-value, quantity and
heat loss, and its conformance finds each run on its Zone's Building-Segment in the reloaded model.

The Site section is the first to attach at `MODEL` after another section: `ph_composer.climate.export.site`
(Ruby `features/climate/export.rb`, Python `site_sections.py`) `requires:` the Zones section, so in both
languages it runs after it and attaches once the Rooms and the Building Segments they share exist; section
ids alone would order it first. It writes one record always (C4c-4): `location` (the site, or null),
`climate` (a complete climate's values with Cooling 2 added as a copy of Cooling 1, or null),
`climate_left_out` (`site_not_set`, `incomplete` or null), `provenance` (the stored provenance in
honeybee-ph's fields, with a line saying Cooling 2 repeats Cooling 1) and `report`, the report's facts,
which Python passes to the result unchanged. Ruby decides every value, an unset climate zone written as 1
(Not defined) and an unset UTC offset as null among them; Python builds `Location`, `Climate` with its
`ClimateProvenance`, and `Site(location, climate)`, a null part becoming honeybee-ph's default, and sets
that one `Site` on every distinct Building Segment. With both parts null it sets nothing. It is optional,
and all its findings are notes: a Model exports without a climate. The climate record's `user_data`
stays in the Model with an `export.metadata_omitted` finding. Its result fields carry the location, the
climate's identity, the four peak-load temperatures, the limit check, the edited values with what the
file read, the design temperatures, the count of Building Segments and a digest of the built `Site`;
conformance finds that `Site` on every reloaded Building Segment, honeybee-ph's default for each part the
record did not carry, Cooling 2 equal to Cooling 1 and no `source_uri`. Its `projection` is what another feature's
export section reads of the climate, through `reader.section` after naming the Site section in `requires:`: the
stored monthly mean air temperatures (`monthly_air_c`, twelve values in °C, null with no climate) and both design
temperatures (`heating_99_c`, `cooling_1_c`, null while not set), as stored and whatever the climate's state.
Mechanical's heat pump export reads it.

Phius certification is the first section to attach at `SEGMENT`: `ph_composer.certification.export.segments`
(Ruby `features/certification/export.rb`, Python `certification_sections.py`) writes one record per exported
Building Segment record, `{id, export_identifier, category, program, use, status, type}`, from the
Segment's `ph_composer.certification.segment` settings, which it claims on the Building Segment kind
(`entity_projections`, "Exporting a payload on another feature's entity", above), or their defaults where
it has none. The Zones section's projection names the exported Segments and their export identifiers; a
legacy Zone names no Segment record, so its `BldgSegment` keeps honeybee-ph's defaults, the same values.
Python maps each value to honeybee-ph's `PhiusCertification` enum and sets it on the shared `BldgSegment`.
It is required for export: a record with a value it does not map, or naming no exported Segment, withholds
the model. Its result fields list each Segment's export identifier and the five honeybee-ph values, and its
conformance reads them back from every reloaded Building Segment. PHX writes them to the WUFI XML
(`BuildingCategory`, `PH_CertificateCriteria`, `OccupancyTypeResidential`, `BuildingStatus`,
`BuildingType`) and the METr JSON (`tests/python/test_certification_phx_round_trip.py`).

Airtightness attaches at `ROOM`: `ph_composer.programs.export.airtightness` (Ruby `features/programs/export.rb`,
Python `airtightness_sections.py`) writes one record per exported Zone whose Building Segment stores
`ph_composer.programs.airtightness` settings, claimed on the Building Segment kind as certification's are:
`{id, building_segment_id, export_identifier, basis, value, wind_exposure, flow_per_exterior_area}`. Ruby
converts the test result (`features/programs/conversion.rb`) and Python computes nothing: it sets the Room's
honeybee `Infiltration` to that flow, in m³/s per m² at 4 Pa, when there is one, and the shared
`BldgSegment.wind_exposure_type` from each of the Segment's Rooms. A Segment with no test result writes a null
flow, so each Room keeps its Program's Infiltration, or none, and PHX's default; a Segment with no settings
writes no record. The conversion inverts the pinned PHX's (`from_HBJSON/create_variant.py`): q50 is the flow
times (50/4)^0.65 × 3600, with flow exponent 0.65 and air density 1, and n50 is q50 times the Segment's gross
envelope area over its net volume. The envelope is PHX's merged Room of the Segment (`cleanup.merge_rooms`):
every Face the Faces section writes for the Segment's Zones (`Faces::ExportProjection.segment_envelope`), less each
Surface Face whose other side is in the same Segment; a Surface Face to another Segment, an Adiabatic Face and
an Attached zone's Face stay, and a shading Face is in no Zone's Faces. The net volume is the Spaces section's
projection, each Zone's Volumes' net floor area times average clear ceiling height. PHX's merge weights each
Room's flow by its Outdoors and Ground area, which returns the one flow every Room of the Segment carries, so
that area only has to be greater than 0. Export refuses `airtightness.no_exposed_face` for a
Segment with a result and no such Face, and `airtightness.no_net_volume` for an n50 result with no Space net
volume, where PHX would write an n50 of 1.0. WUFI-Passive (`EnvelopeAirtightnessCoefficient`) and METr
(`tightEnv50`) carry q50 only; `tests/python/test_airtightness_phx_round_trip.py` reads it back from both and
PHX's own n50 from its Variant.

Shades are the first section that writes geometry outside every Room: `ph_composer.shading.export.shades` (Ruby
`features/shading/export.rb`, Python `shade_sections.py`, record `contract/shade_records.py`) `requires:` the
Zones section for its Zone names and writes one record per Shading Face occurrence, `{id, display_name,
boundary, holes}`: `id` is `shd_` and a digest of the Face's root path, so each placement of a component is its
own Shade and a re-export gives the same ids; `display_name` is the shading component's name ("The shading
mark"); `boundary` and `holes` are the snapshot's loops in world metres, outer first. A record with any other
key is an object finding. Which Faces are shading is `Reads.shading_face?` over `Reads::Container` rows built
from the snapshot entries above each Face (an instance's name falling back to its definition's, which the
snapshot carries as `native["definition_name"]`); inside a Zone, Zones' detached envelope test
(`Zones::ExportProjection.outside_envelope?`) decides the classification clause, so the section writes what
`shading.list` counts and a Face is a Room's or a Shade, never both. Python builds `Shade(id, Face3D(boundary, holes), is_detached=True)` with the
`display_name`, serializes it once in `translate` so geometry honeybee cannot write costs that record, and
attaches at `MODEL` with `model.add_shade` after checking every Shade against the Model. It is optional and
never blocks for its own reasons: a Face with fewer than three points in a loop or under 1 mm2 of area
(`shading.geometry_invalid`) and every Face sharing its path with another (`target.ambiguous`) are left out with
a note, and an unreadable mark still marks its Faces with a `record.unreadable` note. Each mark passes the
metadata boundary under its path's `shd_` id: its `user_data` stays in the Model with an
`export.metadata_omitted` note and its `extension_data` follows the left-out rules. Its result fields are
`shading_components` (`display_name`, `face_count`, `area_m2`), `shade_count` and `area_m2` over the attached
Shades, none when there are none, so a Model with no shading writes the same HBJSON and result as before the
section, bar its empty row in `sections`. Conformance finds the reported count of orphaned Shades, each
detached, and per component the reported count and area. The report's Shading section lists each component
and the totals, and is absent with none. PHX 1.59.4 writes one shading component per name in every Variant,
with `InnerAttachment` and `idIC` -1 (`tests/python/test_shade_phx_round_trip.py`).

Hot water piping is the first section that adds to another section's required objects:
`ph_composer.piping.export.piping` (Ruby `features/piping/export.rb` and the pure `runs/extraction.rb`, Python
`piping_sections.py`, record `contract/piping_records.py`). None of the four hosts is a hot water system, so it
attaches nowhere (`attaches = None`): it `requires` the hot water section and, in `translate`, adds the System's
trunks and recirculation elements to every `PhHotWaterSystem` that section built for the System, which the
assembly then attaches to their Rooms. The coordinator runs every `translate` before it assembles and collects
`result_fields` after, so the hot water rows' digests are taken with the pipes in place. Its Ruby contributor
`requires` the Zones section (which Piping groups a Zone holds), the Ventilator section (which Systems an exported
Zone names) and the hot water section (so that section reads the Systems first). It writes one record per Hot Water
System whose Piping groups hold pipes, `{id, system_id, recirculation_temperature_c, recirculation_hours, trunks,
recirculation}`: each trunk run `{identifier, display_name, multiplier, demand_recirculation, segments, branches}`,
each branch `{identifier, display_name, segments, twigs}`, each twig or recirculation element `{identifier,
display_name, segments}` and each segment `{identifier, display_name, points_m, material, diameter_mm,
insulation_thickness_mm, insulation_conductivity, insulation_reflective, insulation_quality, water_temp_c,
daily_period, user_data}`, the runs, parents, identifiers and names those of `ph_composer.piping.schedule`. A
distribution segment runs at honeybee-ph's 60 °C and 24 h, a recirculation segment at its pipe's values; a bare
Pipe Type with no conductivity gives honeybee-ph's 0.04 W/(m K). The trunk's or branch's inner element takes the
run's identifier and name, and a segment's name is its identifier, so no honeybee-ph default identifier, which is
random, reaches the HBJSON. A finding that blocks the schedule's run refuses the section; the other findings, and
`piping.system_unexported` for a System no exported Zone names, are notes. The snapshot has no Group definitions,
so a pipe is `shared` when a ComponentInstance holds it or its Edge is reached at two paths. A pipe's `user_data`
rides on its segment; a Piping group's and a Pipe Type's are left out with `export.metadata_omitted`. Python
builds every object for every hot water system before it adds any, so a record that fails leaves each system as it
was, and the section is required for export. The canonical HBJSON sorts its keys, and honeybee-ph keys trunks,
branches, fixtures, recirculation elements and segments by identifier, so a reloaded system holds them in
identifier order and sums `recirc_temp` and `recirc_hours` in that order; Python adds them in identifier order and
the Ruby recirculation read sums in it too, so the translated system, the reloaded one and Ruby agree to the bit.
Its result fields are `trunks` (identifier, multiplier, demand recirculation, drawn length, branch count and each
branch's twig count), `recirculation` (identifier and length) and `systems` (the Rooms reached and Ruby's
recirculation temperature and hours); conformance reads each back from every reloaded Room's system of that
identifier, lengths to 1 mm and hours exactly, and refuses a trunk or recirculation element the run did not report.
PHX 1.59.4 reads them through a Room's Spaces, keyed by identifier, so a System on two Rooms gives each trunk,
branch, twig and recirculation element once (`tests/python/test_piping_phx_round_trip.py`).

ERV ducting is the second: `ph_composer.ducting.export.ducting` (Ruby `features/ducting/export.rb` and the pure
`extraction.rb`, Python `ducting_sections.py`, record `contract/ducting_records.py`) `requires` the ventilation
section and, in `translate`, appends each Ventilator's duct elements to every `PhVentilationSystem` that section
built for it, through honeybee-ph's `add_supply_duct_element` and `add_exhaust_duct_element`, attaching nowhere. Its
Ruby contributor `requires` the Zones section and the Ventilator section, whose projection says which Ventilators an
exported Zone names. Both line-group features read their Edges from the snapshot through the layer's
`LineGroups::ExportScan` (`context/EXTENSIBILITY.md`, "Line groups"), which also gives their preflights' unreadable,
Locate and metadata rows. It writes one record per Ventilator whose Ducting groups hold ducts, `{id, ventilator_id,
supply, exhaust, supply_length_m, exhaust_length_m}`: each element `{identifier, display_name, duct_type, segments}`,
`duct_type` 1 for an Outdoor air run in `supply` and 2 for an Exhaust air run in `exhaust`, and each segment
`{identifier, display_name, points_m, diameter_m, width_m, height_m, insulation_thickness_m,
insulation_conductivity, insulation_reflective, user_data}`, the Duct Type's millimetres divided by 1,000 in Ruby. A
round type writes its diameter and null width and height; a rectangular type its width and height and honeybee-ph's
0.160 m diameter, which `shape_type` ignores; a bare type with no conductivity 0.04 W/(m K). The runs, identifiers
and names are `ph_composer.ducting.schedule`'s. honeybee-ph 1.33.68's `PhDuctElement` has no quantity, so a run of
quantity N is N elements: the first takes the run's identifier and name, copy k the identifier with `-k`, the name
with "(k of N)" and its segments' identifiers the same suffix, so it exports the lengths and element count N copies
of the Ducting group would, and the two lengths, each direction's, apply the quantity. A blocking finding refuses the section; the other findings,
`ducting.run_missing` for a Ventilator an exported Zone names and `ducting.ventilator_unexported` for one with ducts
that none names are notes, and a Model with no ducts notes nothing. A duct's `user_data` rides on its segment, every
copy's; a Ducting group's and a Duct Type's are left out with `export.metadata_omitted`. honeybee-ph reloads two
Rooms' ventilation systems sharing an identifier only when their dictionaries are equal, so Python builds every
system's ducts from the same record before it appends any, never sharing an instance, elements and segments in
identifier order (a system writes its elements as lists in the order appended, and segments as maps the canonical
HBJSON sorts), and the section is required for export. Its result fields are `elements` (Ventilator, identifier,
`duct_type`, segment count, length, shape, sizes and insulation) and `ventilators` (the system identifier, the Rooms reached and
Ruby's two lengths); conformance refuses a system whose `supply_ducting` or `exhaust_ducting` holds an element of the
other `duct_type`, reads each element back from every reloaded Room's system of that identifier, lengths and both
`supply_ducting_total_length` and `exhaust_ducting_total_length` to 1 mm, and refuses an element the run did not
report. PHX 1.59.4 builds one ventilation device per system key and keys ducts by identifier, each with its device's
id number, so a Ventilator on two Rooms gives its ducts once (`tests/python/test_ducting_phx_round_trip.py`).

Export reads one revision-bound `GeometrySnapshot`: one traversal recording each occurrence path
and accumulated transform, with no live SketchUp objects. Its entries are Faces, Edges (world SI
endpoints, vertex and Face ids within their container), Groups and ComponentInstances; Faces and
Edges inside a cutting component are left out. Contributors project from it and never
rescan the Model. A changed export-relevant revision discards the snapshot; selection and camera
neither enter it nor invalidate it. A contributor that reads another contributor's section names it
in `requires:`; registration refuses a section that is not registered, or whose owner is neither
the contributor's feature nor one that feature requires, with `registration.missing_dependency`.
It reads that section's registered `projection` with `reader.section(id)` while collecting, and its
result fields with `result.section(id)` in its report, which receives an `Export::ResultView`; an
undeclared read is an internal error. `result.findings` gives the findings the run reported against the
contributor's own section, its notes among them. The Zones section projects each Zone occurrence's id, path, name,
Building-Segment and `exported`; the Faces section each Zone Face's path, record, Zone and `left_out`; the
Apertures section each placed Window's world outline. A contributor discloses what it leaves out of its records, or warns about
them, with `reader.note(code, object_id, message)`: a non-blocking finding that joins the result's findings
and so the report. Such a finding carries no `locate`; the preflight row for the same condition does.
The run reads every contributor's preflight once, at the revision it exports, and each warning (a
non-blocking preflight finding) that no result finding already reports by code and object id joins
the result's findings once, without its `locate`, so the report and `summary.findings` carry what the
preflight showed. A preflight that cannot answer fails the run before translation, since a report
without its warnings is the defect this rule prevents.
Export contributors extend a composed privacy allowlist, one
optional entry per section; the report embeds their results unchanged. Exporters consume only the HBJSON artifact plus explicit
options. The HBJSON and report pair is replaced together: an injected failure leaves the previous
pair intact. A run that cannot publish writes neither file, but its figures are the ones a user needs
to clear the block, so `Export::Report.render` renders the same sections for it, titled as not created
and opening with one line saying the run wrote no model; the rule keys on `summary.publishable` and names
no section. That report travels in the refused export outcome as `value.report_html`, and the panel's
Export tab shows it in place, collapsed.
