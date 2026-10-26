# Core contracts

The binding mechanics of the foundation: how capabilities register, how every client calls the
public interface, what an outcome says, how revisions, transactions and retries behave, how
records and extension data survive edits, how geometry targets are named, how Zones keep
adjacency and identity honest, how library catalogs admit and copy records, and how translation
sections compose. Code and tests cite these
sections by name.

The policies these mechanics serve are in [EXTENSIBILITY.md](EXTENSIBILITY.md) (contributors,
metadata, copy rules), [AGENT_INTERFACE.md](AGENT_INTERFACE.md) (external clients, writes, the
export task, host lifecycle) and [TECH_STACK.md](TECH_STACK.md) (runtime, panel, export). This file
was consolidated on 2026-09-30 from the archived Phase 0 and Phase 1 contract designs, and extended
on 2026-10-01 with Phase 2's Window Unit storage and library mechanics. The archived designs remain
in `planning/archive/` as the record of how each rule was reached.

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
| Menu item | Label, menu, availability test supplied by the owning feature, handler; or a per-session entries provider |
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
FileExport or export task `export`. Library loading and provider setup are setup commands; this
replaces the archived Phase 2 choice of view commands for them (refactor R03, 2026-10-01).

Every declared name starts with its feature's id; a code instead starts with a noun only that
feature declares. Registrations are staged and validated together:
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
- `preview(context:, name:, params:)`: builds and validates an action's proposal without writing,
  and returns its `proposal_digest`.
- `view(context:, name:, params:)`: a view command that changes what the host shows. It writes no
  authored data and leaves no Undo entry of its own, so it takes no request; it may trigger the
  Model's own protection boundaries, which the command declares in `side_effects`.
- `setup(context:, name:, params:)`: a setup command that changes session or machine state, such
  as the libraries configured on this machine, and never the Model. No request, no Undo entry.
- `invoke(context:, name:, params:, request:)`: a validated synchronous mutation.
- `outcome(context:, request:)`: a retained mutation outcome, without rerunning it.
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
`params.invalid`. Discovery and descriptions are detached copies. A query or preview that fails
unexpectedly answers `failed`, code `operation.failed`, effect `none`.

Dispatch presents nothing: it returns the outcome, and the calling client shows the message.
Internal diagnostic details go to the log; an unexpected exception's message is never returned.
An unexpected failure's outcome carries `detail.incident`, a short reference (`PHC-` and six hex
digits) naming its log record. It identifies evidence and grants nothing. A declared refusal's own
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
| Session | `session.unknown` (closed, reopened or never issued), `session.busy`, `session.closed`, `session.changed` (a native menu built for another Model), `session.inactive` (the panel's Model is no longer shown, or a return to the root was asked of a Model SketchUp is not showing) |
| Preconditions | `revision.stale`, `proposal.changed`, `record.unreadable` |
| Proposal contributions | `proposal.foreign_write` (a participant or library callback staged a write to a kind its owner does not own, or into another change set), `proposal.contribution_replaced` (it removed or changed what an earlier contributor proposed) |
| Targets | `target.not_found`, `target.changed`, `target.ambiguous`, `target.locked`, `target.wrong_kind`, `target.wrong_hierarchy`, `target.wrong_zone`, `target.same_zone`, `target.shared_definition`, `target.edit_path_changed` |
| Validation | `params.invalid`, `validation.failed`, `reference.invalid`, `reference.in_use`, `geometry.invalid`, `geometry.failed`, `geometry.split_failed` |
| Extension data | `extension.unavailable`, `extension.schema_unsupported`, `extension.migration_required`, `extension.migration_failed`, `extension.invalid`, `copy.rule_missing` |
| Query | `query.limit_invalid`, `query.cursor_expired` |
| Operation | `operation.failed`, `operation.rollback_unverified`, `operation.participant_missing`, `operation.proposal_required`, `operation.query_missing`, `operation.dependency_missing`, `operation.query_cycle`, `operation.locate_missing`, `operation.participant_cycle` |
| Identity and scope | `identity.conflict`, `identity.choice_required`, `identity.choice_conflicts`, `scope.incomplete`, `selection.invalid` |
| Registration | `registration.duplicate_id`, `registration.missing_dependency`, `registration.cycle`, `registration.contract_major`, `registration.schema_invalid` |
| Translation | `payload.contract`, `section.missing_dependency`, `section.cycle`, `section.duplicate`, `section.version_unsupported`, `object.unavailable`, `dependency.unavailable` |
| Export | `export.blocked`, `export.busy`, `export.cancelled`, `export.failed`, `export.refused`, `export.model_changed`, `export.destination_changed`, `export.replace_required`, `export.privacy_undeclared`, `export.relevance_unknown`, `export.metadata_omitted` (a finding), `export.user_data_passed` (a finding: how many HBJSON objects of each type carry a user's user_data), `export.revoked` (the access that started the task was revoked before it wrote anything), `task.expired`, `task.foreign` (another caller started that task) |
| Library | `library.adapter_invalid`, `library.assignment_unavailable`, `library.callback_invalid`, `library.catalog_budget`, `library.catalog_stale`, `library.catalog_too_large`, `library.catalog_too_many_rows`, `library.destination_changed`, `library.destination_invalid`, `library.export_write_failed`, `library.file_malformed`, `library.file_too_large`, `library.file_unreadable`, `library.format_invalid`, `library.kind_unavailable`, `library.local_choice_required`, `library.provider_ambiguous`, `library.provider_failed`, `library.provider_invalid`, `library.provider_unavailable`, `library.review_required`, `library.row_semantic_invalid`, `library.row_unavailable`, `library.schema_unsupported`, `library.setup_invalid`, `library.setup_too_large`, `library.setup_unavailable`, `library.setup_unreadable`, `library.update_destination_invalid`, `library.update_destination_required`. Catalog notes are listed in "Library providers and catalogs" |
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

Dispatch runs only on the host-safe execution boundary and serializes mutations. A modal tool,
Model transition or unsettled session refuses at once as `busy`; there is no durable queue of
edits, and a scheduled callback revalidates when it runs.

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
| Acceptance | Refusals before acceptance (malformed envelope, unknown session or caller, unknown operation, missing capability, busy) consume no sequence and are not retained. Everything after acceptance, including `params.invalid` and `revision.stale`, is retained |

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

**Entity-owned records.** Zones, Faces and Window Units store their records on SketchUp entities,
and the same rules hold for them (`Records::Metadata`, shared with the engine). Their reads
(`ph_composer.zones.list` and `.all`, `ph_composer.zones.faces.list` and `.all`,
`ph_composer.windows.units.list`) report `extension_status` beside `extension_data`, in the words a
catalog read uses; a Face with no record reports `{}`. Each owner has one metadata action:
`ph_composer.zones.update_metadata`, `ph_composer.zones.faces.update_metadata` and
`ph_composer.windows.units.update_metadata`. It takes a batch of occurrences, each with the whole
`user_data` map to write, payloads for installed extensions, or both, and `expected_metadata`, the
two maps as last read; any difference refuses `target.changed`. Identical entries collapse; two
entries for one occurrence that differ, or an entry naming nothing to write, refuse `params.invalid`.
Each target resolves through its owner's writable resolver and refuses with the owner's `target.*`
code; a payload follows the engine's rules (`extension.unavailable`, `.migration_required`,
`.schema_unsupported`, a failed validator as `validation.failed`) and every record it names must
resolve (`reference.invalid`); the owner then validates the whole record. Every target is checked
before any step is built, the batch writes in one step and one Undo entry, and a batch that writes
what is stored adds no step. The Window action runs the copied-identity repair first, as every
Windows action does. A Face must already have a record.

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
reference to `ph_composer.windows.psi_install_type`, or null) and `default_install_depth_m`.

## Geometry records and occurrence references

Records are canonical JSON under registered `ph_composer.*` dictionaries. A read never creates a
dictionary. Unknown keys outside `user_data` and `extension_data` make a record unreadable at its
declared version. Entity stores resolve an explicit occurrence reference to an entity before any
access and never fall back to selection, display name, proximity or the active Model.

| Owner | Dictionary | Entity | Durable identity |
| --- | --- | --- | --- |
| Zone | `ph_composer.zone` | Zone Group | `zon_` id |
| Zone membership stamp | `ph_composer.zone_stamp` | Classified Face, and a nested container Group such as a Space | Zone id plus Building-Segment and Level, as recovery data. Only Zones writes it; a feature that creates a container in a Zone has Zones stamp it through the participant below |
| Face assignment | `ph_composer.face_assignment` | Face | `fac_` id |
| Attached zone | `ph_composer.records.ph_composer.face_assignment.attached_zone` (a legacy name, kept so saved Models still read) | Model | `atz_` id through the record engine |
| Thermal bridge assignment | `ph_composer.thermal_bridge` | The `Sketchup::Edge`, inside a Zone | `tbe_` id; values `thermal_bridge_type_id` (a required core reference to `ph_composer.thermal_bridges.type`) and `quantity` (above 0, default 1). A split or copy carries the id, which reads mark `copied` and nothing re-issues |
| Window unit | `ph_composer.window_unit` | The Unit's ComponentInstance | `wun_` id; values `window_type_id` (a core reference to `ph_composer.windows.window_type`) and `anchor` |
| Window definition mark | `ph_composer.window_definition` | The generated ComponentDefinition | `window_type_id`, plus optional derived `generated_size_m` (`width_m`, `height_m`) used only to repair a Unit whose Type is gone |
| Pane stamp | `ph_composer.window_pane` | Each pane Face inside the definition | None; `window_type_id` and `element_id` as recovery data for Restore |
| Space | `ph_composer.space` | The Space Group | `spc_` id; `name`, `number`, `default_height_m`, `next_volume_sequence`, and the optional airflows `v_sup_m3h`, `v_eta_m3h`, `v_tran_m3h` (absent is unset, distinct from 0) |
| Volume | `ph_composer.space_volume` | A Volume Group directly inside a Space | `vol_` id; `number`, `display_name`, optional `avg_ceiling_height_m`, `floor_id` (the logical Space Floor, `flr_`), optional `home_transform` |
| Floor Segment | `ph_composer.floor_segment` | A Face directly inside a Volume | `fsg_` id; `display_name`, `weighting_factor` and `net_area_factor`, each 0 to 1 |
| Spaces settings | `ph_composer.spaces_settings` | Model | None; `last_height_m`, the height new Spaces take, null until entered |
| Primary definition index | `ph_composer.window_definitions`, key `index` | Model | None; `{ "schema_version": 1, "definitions": { "wnt_...": persistent_id } }` |

The Face values include an optional `assembly_id` reference to
`ph_composer.assemblies.assembly`. An absent assignment and a dangling reference are distinct read
states. Assembly-only assignment preserves Face type, boundary condition and reciprocal Surface
pair data. Explicit targets carry their complete `expected_values`; the compound gesture refuses
all writes if any target is stale or unreachable. Assembly delete may omit replacement (ordinary
in-use refusal), name a replacement, or explicitly pass null to clear all references through the
registered referrer handlers. Definitions never name Zones or Faces.

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

**Containment.** `ph_composer.zones.containment` answers, for each root-to-entity path, the Zone
occurrence holding the drawing element at its end (`zone_id`, `zone_path`, `name`, `building_segment`,
`level`), the `entity_path` from inside that Zone, and its `write_refusal`, read along the path
alone. One read over many paths, here and in `faces.host_context`, scans each collection it steps
into once (`Zones::ChildLookup`), so its cost grows with the paths asked, not with paths times
siblings. The Zone is the innermost one above the element, by the rule Face picking applies; with no
Zone, `reason` says why: `not_found` (a step missing or repeated), `not_a_drawing_element`,
`cutting_instance`, `outside_zone` or `nested_container`. `faces.host_context` stays Face-only over
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
"volume_id" | "floor_segment_id", "entity_path" }`: a Space may sit outside every Zone, and its Zone
is whichever Zone Group its path passes through last, read from the Zones read, never from its stamp.
The Spaces inventories include every placement of shared storage and every record found where the
hierarchy does not put it (a Volume outside a Space, a Floor Segment not directly in a Volume).

**Stamping a container.** `ph_composer.zones.stamp_container` is a proposal participant: an action
of a feature requiring Zones whose own earlier step creates a Group inside a Zone occurrence leaves
the Group's root-to-Group path in a proposal slot as `{ "entity_path" => [...] }` and names the slot
and the Zone; Zones' step stamps the Group in the same Undo step, refusing with the Zone's `target.*`
codes, a lock or shared storage on the Group's path, and a Group inside another container. A Zone edit rewrites the stamps of its containers as it does its Faces'.

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

## Managed Zone field options

Zones owns Building Segment (`ph_composer.zones.building_segment`, `bsg_`) and Level
(`ph_composer.zones.level`, `lvl_`) records. Each has a name and validated six-digit hex colour;
Segment has an immutable, collection-unique export identifier. Names compare without case after
trimming and collapsing whitespace, hyphens and underscores. Model-owned option settings hold
`default_segment_id` and source-model identity; reads never seed records.

Zone schema 2 stores `building_segment_id` and nullable `level_id`. Version 1 remains readable.
Unknown versions refuse. The `choice_evidence` capsule on Zones and membership stamps carries
versioned option definitions and source identity for native clipboard recovery; it is detached
recovery evidence, not assignment authority. V2 read rows expose resolved presentation names/colours
separately as `display`. Missing/foreign choices require explicit destination adoption. In a managed Model, export preflight also blocks legacy Zones pending adoption. A wholly legacy Model retains its compatible export path.

The `ph_composer.zones.options.*` operations publish collection reads, usage, guarded definition
writes, complete-draft management, read-only adoption preview and atomic adoption. Management validates the
whole final collection and default, retargets live and recovery references, and commits one native
Undo step. Name/colour changes preserve assignment and export identities. Used deletion requires a
survivor, or explicit null Level clearing. Stamps have a detached reference projection whose diagnostic
`id` is `zone_id`, keyed by exact root-to-member path; synthetic IDs never enter stored stamps.

Adoption inventories all stamps, including those hidden from Restore by a live Zone ID. Equivalent
legacy names require explicit survivor mapping via `target_source` or an existing destination ID.
It converts choices, Zones, stamps and defaults atomically, preserving geometry identities and
metadata. Adopted Segment export identifiers keep the legacy `bseg_` + 16-character SHA-256 name
hash; conflicting foreign export keys require a survivor and never silently re-key.

Older string writers can resolve existing unambiguous choices on managed Zones; unknown names
refuse. Before adoption, ordinary name/depth edits preserve legacy fields, but category edits and
Make requiring new defaults request adoption. The published descriptor names current schema 2;
owner validation handles both versions without adding generic base-record migration machinery.

Zone export section 2 emits resolved names plus managed Segment ID/export key. Python supports
sections 1/2 and legacy records, groups managed Rooms by identity, and refuses conflicting exported
identifiers before attachment. Room `ph_composer` metadata retains the resolved names. Native-host
and distribution acceptance remain separate from these implemented branch contracts.

## Zones geometry rules

**Cutting components.** A ComponentInstance whose definition cuts an opening owns its contents.
Those Faces are excluded from Zone discovery, Face inventories, classification, viewport picks
and explicit Face resolution. The shared export snapshot retains instance and record facts,
including nested instances, but excludes all descendant Faces from Zone geometry. This allows
Window export to account for Units inside foreign cutting components and refuse invalid hosts
instead of silently omitting them. Definition facts are detached once per definition and captured
in resumable work units; a contributor never walks the live Model again.

**Nested containers.** A Group inside a Zone that carries a Zone stamp (`ph_composer.zone_stamp`)
is a nested authoring container: whatever stamped it owns its contents, and none of its Faces is a
Zone Face. Zone discovery, Face inventories, Suggest, the Shift-click flood, Solve, viewport picks
and explicit Face resolution skip it, and a Face path through one refuses as
`target.wrong_hierarchy`. Presence of the stamp decides, whichever Zone it names and whether or not
it reads, so a mismatched stamp is the stamping feature's finding and not Zones'. Only Groups
qualify: a stamped Face is a classified Zone Face, a Zone nested in a Zone keeps its own refusal and
cutting components keep theirs. The shared export snapshot still captures the container's Faces,
for the feature that stamped it; the Zones export leaves them out of the Zone's Faces, gives them no
owning Zone, reads nothing stored on them and does not export a Face record left on one; a Surface
pair whose counterpart sits in a container exports as unresolved. Zones reads only the stamp it owns and never learns what the container is.
Zones keeps the stamp current as it keeps its Faces' stamps: editing the Zone, Make Zone independent
and repairing a copied Zone's identity rewrite every container's stamp, and refuse first when a
container is locked or sits below a component, a locked Group or, for the repair, a Group the copy
still shares. Restore Zone recovers a stamped container as a member, regrouping it whole with the
Zone's stamped Faces; a Group whose stamp does not read stays opaque and is not offered, a live Zone
is never a member whatever stamp it still carries, and a locked member or one holding a live Zone
refuses the restore.
Spaces is the first feature to stamp one.

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
the watcher tells the user the copy is read only again. Spaces follows the same rule for a Space Group
copied on its own (its `CopyWatch`): the Space is made independent through Make independent with the
next free number; a copy inside a component keeps its finding with one notice, and a copied plain
Group holding a Space is left to its finding, since it may be a Zone whose copy Zones handles. The
Spaces and Zones watchers hear the copy through the session's `container_added` host event, which
reports each Group or ComponentInstance added to any container.

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
`revision` and `references`, the Zone's and Faces' new records as typed `{kind, key, record}` entries
for remapping a child's own references. Windows contributes `ph_composer.windows.units.follow_zone_copy`:
every Unit inside the occurrence whose id another occurrence holds gets a new id, and copied payloads
are remapped across the copy.

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
7. The owner's callbacks run with validated params (`params.invalid`) and results
   (`library.callback_invalid`), then assignment when requested
   (`library.assignment_unavailable` when the adapter has none).

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
key)`, with `host` one of `MODEL`, `ROOM` or `FACE`, and implements `attach(host, objects)`. After
every section has run, the assembly attaches the host levels outermost first and calls `attach` once
per host with that host's objects, in id order. A section checks what one object's own record
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
and a Volume with its preview prism as `geometry`. Airflows follow the any-set rule in the section
alone: a Space with no rate stored writes none of `_v_sup`, `_v_eta`, `_v_tran`; one with any writes
all three, 0 for an unset rate, converted from m3/h to m3/s there and nowhere else. Its result fields
total floor area, weighted area and net volume per Zone and per Building-Segment, and its
conformance checks the reloaded Rooms' Spaces against the per-Zone totals.

Thermal bridges are the first optional section: `ph_composer.thermal_bridges.export.thermal_bridges` (Ruby
`features/thermal_bridges/export.rb`, Python `thermal_bridge_sections.py`) writes one record per run, built
by the same run functions as the schedule from the snapshot's assigned Edge entries, and attaches at `ROOM`,
adding each honeybee-ph `PhThermalBridge` to the Room's shared `ph_bldg_segment`. Its only `user_data` is
the declared `ph_composer.thermal_bridge_type_id`: a run joins many Edges, so no Edge's own user_data
leaves. A missing type or psi-value refuses the section; every other finding is a note, and an Edge no Zone
holds is left out with one. Its result fields list each attached run's length, psi-value, quantity and
heat loss, and its conformance finds each run on its Zone's Building-Segment in the reloaded model.

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
undeclared read is an internal error. The Zones section projects each Zone occurrence's id, path, name and
Building-Segment; the Faces section each Zone Face's path, record and Zone; the Apertures section each
placed Window's world outline. A contributor discloses what it leaves out of its records, or warns about
them, with `reader.note(code, object_id, message)`: a non-blocking finding that joins the result's findings
and so the report. Such a finding carries no `locate`; the preflight row for the same condition does.
Export contributors extend a composed privacy allowlist, one
optional entry per section; the report embeds their results unchanged. Exporters consume only the HBJSON artifact plus explicit
options. The HBJSON and report pair is replaced together: an injected failure leaves the previous
pair intact. A run that cannot publish writes neither file, but its figures are the ones a user needs
to clear the block, so `Export::Report.render` renders the same sections for it, titled as not created
and opening with one line saying the run wrote no model; the rule keys on `summary.publishable` and names
no section. That report travels in the refused export outcome as `value.report_html`, and the panel's
Export tab shows it in place, collapsed.
