# Technical working context

**DATE:** 2026-09-30

The durable starting point for work in this repository. It carries the implementation rules the
predecessor, PH-Navigator for SketchUp, learned at cost between 2026-09-06 and 2026-09-17, with
every designPH rule removed, and adds the rules for the two seams this project introduces. The
SketchUp facts behind these rules, with what pins each one, are in
[`SKETCHUP_HOST_BEHAVIOR.md`](SKETCHUP_HOST_BEHAVIOR.md). Where a rule cites evidence, the evidence
is in the predecessor's archive at `../../../ph-navigator-sketchup/planning/archive/`.

The Phase 0 foundation merged through PR #1: sessions, revisions, record transactions and the
public operation contract, panel/UI kit and shared Units, the runtime shell and export contracts.
Phase 1 merged through PR #3 and PR #6 on 2026-09-30. The build registers one building feature,
`zones` (`src/ph_composer/features/zones/`), which owns Zones, their Faces and the adjacency between
them, plus two foundation capabilities, `RecordQueries` and `ColourBy`, and the export run to
canonical HBJSON and its report. No exporter beyond HBJSON ships. The archived
[Phase 0](../planning/archive/phase-00-foundation/README.md) and
[Phase 1](../planning/archive/phase-01-faces-and-zones/README.md) packets record implementation and host evidence.
That overview records the merged Phase 1 baseline. The owning Phase 2 packets record subsequent
implementation and acceptance; the library section below describes the current file-provider
implementation. Proposed capabilities remain requirements until their owning packets land.

[EXTENSIBILITY.md](EXTENSIBILITY.md) owns the accepted contributor architecture, including the
separation of pure Ruby domain behavior from SketchUp adapters, public scripting, metadata and
registered extension data. `PhComposer::API` implements the public operations; each registered
operation's schemas and example are in the generated [`docs/API_REFERENCE.md`](../docs/API_REFERENCE.md).

[AGENT_INTERFACE.md](AGENT_INTERFACE.md) governs external clients of those public operations.
Their results and confirmation handling must work without an open panel. The development eval
bridge remains separate from the proposed shipped agent interface.

## Proposed scope versus implemented contracts

The product direction is in [`../docs/PRD.md`](../docs/PRD.md). Three technical decisions are
settled from the predecessor and carry over: SKP-owned definition records exist and their
attribute-dictionary layout is the record-kind pattern (`Records::RecordKind`, CONTRACTS.md,
"Records and extension data"); the local calculation path is a
Ruby thermal module for the panel with a Python recomputation at export; the panel is plain
JavaScript and SVG on a shipped `workspace` toolkit, not React, with no local database. Optional
external evidence is reserved in the records and hidden until its own feature. HBJSON and report
export do not admit arbitrary local paths or attachment bytes.

## Supported and proving environments

- **SketchUp 2023 is the compatibility floor**, because window overlays use `Sketchup::Overlay`, a
  2023.0 API. SketchUp 2023 embeds Ruby 2.7.2, so Ruby 2.7 is the source floor. No 2023 host has
  been measured; the floor's own host proof is a pending gate.
- **SketchUp Pro 2026.1 build 26.1.188** with embedded Ruby 3.2.2 is the current macOS proving host.
- **The offline suite runs on both ends of that span.** Ruby 3 stopped splitting a bare trailing
  hash between a positional parameter and keywords, and the predecessor's first run on 2.7.2
  produced 559 errors that no amount of 3.2.2 runs could surface. CI runs `make ci` as one job per
  version, and the test helper refuses anything outside 2.7 to 3.2.
- **Pyodide and the wheel versions in `vendor/manifest.json`** are pinned runtime inputs, not
  loose development dependencies. The shipped payload is Pyodide 0.24.1 and eight honeybee-stack
  wheels for HBJSON translation. PHX and whatever its METr writer needs are added when the deferred
  METr exporter resumes (see [the exporter seam](#the-exporter-seam)).
- **The first release candidate is macOS-only.** Windows support is its own gate.

## Namespace

The name checks closed on 2026-09-18. D8 confirms the following working development namespace; it
does not settle the final public name or organization. The Ruby
module is `PhComposer`, the attribute dictionaries are prefixed `ph_composer`, and the RBZ
is `ph_composer.rbz`. Treat these as the working implementation namespace; changing the public
name later requires an explicit migration decision rather than a partial rename.

## SketchUp Model and transaction rules

The Volume, Space and reconciler rules in this section and in the failure signatures below are the
predecessor's, measured there and carried over for the Spaces feature. The two pieces they rest on
are in `session/` and name no feature: `EditContext`, the one writer of `model.active_path`, and
`DeferredWork`, the keyed coalesced pass. The Spaces reconciler that composes them is
`features/spaces/context/`: `Protection` (a Volume's own lock, written in a transparent operation
that never aborts, and the EditContext boundary), `Reconciler` (the Volume last seen on the path, the
queued exit protection, and the save rules below) and `Navigation` (the edit-context commands and
Restore position). A Volume's own lock is protection, not a user's lock, so Spaces' own writes go
through it; a lock on the Space or above refuses. The reconciler does not rename Groups from their
records: a native rename of a Space Group stands until the next Spaces write to it.

### Observers report; deferred work mutates

SketchUp observers can fire more than once for one user action and can fire while the source
transaction is still being settled. An observer callback records the smallest useful fact, queues
one deferred reconciliation pass, and returns. It never changes hierarchy, attributes, selection or
lock state inside the callback.

Coalesce repeated callbacks for the same transaction. A deferred pass must be idempotent: no write,
no Undo entry, and no panel churn when current state already matches the contract.

`session/deferred_work.rb` is the coalesced pass: an observer queues a keyed job and returns, a
second job under the same key merges through the caller's block, and one zero-delay pass runs every
job. A feature keeps one in its state object and forwards `pending?`, `settle` and `detach`, so a
queued pass makes reads and writes wait (`ModelSession#busy_reason`) and a closing Model drops it.
Queue a job only for work that may write: a pass that would find nothing to do should not make the
session busy. The predecessor's `UndoLedger` is not carried over: it tracked a Volume the TFA
transition created and entered automatically, and the explicit mark removed that transition.
`session/host_observers.rb` only translates SketchUp callbacks into session host events (an opened
file is `model_opened`, reported even to a session created before the file loaded), and
`session/container_watch.rb` adds one: `container_added`, with the Group or ComponentInstance added to
any container, observed through one EntitiesObserver per container and found again after each commit,
Undo, Redo and activation. Zones' name preservation and copy watcher and the Spaces copy watcher all
hear additions through it, and each keeps its own `DeferredWork` pass and policy.
Each feature subscribes in its `install`, subscribers run in install order, and a feature subscribes
once per process so a reloaded `install` does not subscribe twice.

### Per-Model state lives on the session

Every open Model has one `ModelSession`, created and dropped by the `Sessions` registry, which is
the only code that keys anything by `model.object_id`. The session carries a random session id, the
whole-Model revision, issued caller handles, retained mutation outcomes, the refresh timer and
observers, and names no feature. A session lasts while its Model is open; activating another Model
does not end it, and reopening a file creates a new one. A feature keeps its per-Model state
in one state object, `session.feature_state(:name) { ... }`. A module never holds a Model-keyed
hash. The session detaches and settles every state object that responds to `detach` or `settle`,
so a new feature adds no line to the session.

### Join the user's Undo step

Automatic work caused by a SketchUp action uses a transparent operation so it joins the source
Undo step. Direct panel or toolbar commits use named one-step Model operations. Confirm the active
editing path again immediately before commit, because the user can change context between the
event and the deferred work.

Transparent work never aborts: aborting it undoes the source step it joined (measured,
`SKETCHUP_HOST_BEHAVIOR.md`). Zone name restoration, which writes only a native name, commits
directly. Work that writes records runs through `HostFollowUp`, whose steps each answer `restore`:
on a failure they write back what they wrote and the operation commits. The copy watcher
(`features/zones/zone/copy_watch.rb`, which makes a fresh native copy of a Zone independent) is its
first user.

Zone names read from the native Group name, including export's detached snapshot. The schema-v1
stored name is a compatibility fallback. Native valid renames cause no mirror transaction. Clearing
an observed Zone name restores its last valid name in deferred transparent work. The restoration
must commit rather than abort on failure: aborting a transparent operation can also abort the user's
source operation. Native clipboard copies are observed when their authored dictionary arrives;
Ruby `Group#copy` is not assumed to copy instance attributes. Evidence and current-host scope are in
`planning/archive/phase-01-ux-followups/README.md`.

Zones / Faces settings are Model records, reached through registered reads and actions. Automatic
Suggest on Make defaults on, with roof/floor tilt thresholds of 60/130 degrees. Make and Suggest
share one proposal, transaction and Undo step. A settings edit has its own named Undo step.

Observer suppression must span commit, abort, Undo and Redo paths. Suppression is not a reason to
skip explicit recovery. Leaving it set after an exception makes later edits appear randomly dead.

Ed confirmed on 2026-09-18 that ordinary edits and batches submitted as one operation are
all-or-nothing: validate every target, commit in one native Undo step, and roll back the whole
operation if any target fails. Stale requests write nothing. Show a clear failure warning with
the reason and confirmation that nothing changed. Panel and programmatic callers share this
contract; structured failures must work with the panel closed. Any later exception for a long
operation requires an explicit accepted contract in its owning plan.

`onPreSaveModel` is the bounded synchronous exception. SketchUp provides no cancellable save
boundary, and an autosave fires the same callbacks, so a save must leave the user where they are.
Inside that callback the host reports an empty `active_path` while the edit context is still open,
and restores the context after the save unless a Group on the path is locked. The reconciler settles
pending protection of Volumes already left, so the file holds them protected, and leaves the open
Volume unlocked and the path alone: a path set there makes SketchUp serialize the reopened context in
world coordinates. A file saved inside a Volume therefore stores it unlocked, and the reconciler
protects every unlocked Volume off the path when the Model's session is created or its file opened
(`model_opened`: the host can create the session before the file has loaded). The offline stub
refuses a path change inside `onPreSaveModel`. On exit, the host can deliver `onTransactionCommit` before `onActivePathChanged`
with the path already outside the Volume; either callback must queue the exit protection.

### Treat the active editing path as data

The active path carries authoring intent. Before switching directly from one Volume to another,
close and reconcile the current Volume using the previous path. Looking only at the new path
produces false `volume_moved` findings and leaves protection stale. One module is the only place
the extension assigns `model.active_path`, `session/edit_context.rb`; a test refuses any other
assignment. `EditContext.enter` runs every registered boundary with the path being left and the
path being entered before it changes the path, and `EditContext.close` runs them without a path
change, which is what a save needs. A feature registers its boundary by name in `install`; the
Spaces boundary protects the Volume being left. That boundary is what export, save and every
navigation command share.

Selecting another Volume or the Space from the panel closes and protects the current Volume
before selection, because SketchUp cannot select outside the open context. Derive open state from
the complete occurrence path, never from selection or table expansion. Row commands carry the
issuing Model session to reject delayed cross-Model clicks.

Transforms accumulate from Model root to the entity exactly once. This must remain true for direct
Groups, nested Groups and repeated component placements. A visually correct direct case does not
prove nested geometry.

SketchUp cut and paste can replace a `persistent_id`. PH-Composer's durable UUID therefore
survives the operation when the object is still logically the same, while placement references
remain path-qualified. Session `entityID` is never durable identity.

## Envelope: what PH-Composer owns that the predecessor did not

The predecessor read envelope classification, TFA and shading from designPH and never wrote them.
PH-Composer owns all of it, in its own attribute namespace, through its own tools. The unit
that owns a face is the Zone, one Group per honeybee Room, with Spaces inside it. Closure is a
consumer-specific validation rule, not a requirement for creating or exporting every Zone. The
rules are the zones-and-adjacency packet's to settle
(`../planning/archive/phase-01-zones-and-adjacency/PRD.md`); Phase 1 implemented them. The durable
constraints:

- One feature, `zones`, owns this whole lifecycle: Zone containment, Face identity, Zone stamps,
  Surface endpoints and the split and copy transitions between them. They change together, so a
  second feature reaching into any of them would need to learn all of them.
- Classification is a record on the face in PH-Composer's dictionary, carrying face type,
  boundary condition and the assigned assembly's record id. The face's geometry is SketchUp's.
- A face is identified by its persistent id plus its occurrence path, never by `entityID`.
  Repeated components expose one face through many occurrences, and a classification stored on
  the shared child is shared by every occurrence. Independent classification requires explicit
  parent uniqueness, and PH-Composer never makes a parent unique automatically.
- Back faces, coplanar overlaps and faces inside nested edit contexts are the cases a happy path
  at Model root does not cover. Test them before claiming face assignment works.
- A Group inside a Zone that carries a Zone stamp is a nested authoring container. The feature
  that stamped it owns what it holds, so none of its Faces is a Zone Face: the Face walk, Suggest,
  the Shift-click flood, Solve and the Zone's export ownership all skip it, and a Face path through
  one refuses as `target.wrong_hierarchy`. Zones reads only the stamp it owns and names no feature.
  A stamped Face is still a classified Zone Face; the rule applies to Groups only. Rule and
  reasoning: `CONTRACTS.md`, "Zones geometry rules".
- Floor Segments are floor faces the user classifies as iCFA. There is no reduction factor.
- Face occurrence resolution walks the Model. A read phase with no write before its last resolve
  (a query, target resolution before a proposal, `ClassifyStep`) shares one `Zones::Index`, which
  walks once and is valid only while the Model is unchanged; a step that mutates and then reads its
  own result walks the live Model. Per-target walks measured O(targets x Model Faces) on the host
  ([gesture cost evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-d-gesture-cost.md)).
- A Classify gesture affects at most `GESTURE_FACE_LIMIT` (250) Face occurrences, reciprocal
  counterparts included and deduplicated; one over refuses the whole gesture as
  `gesture.too_large`. The ceiling bounds the blast radius, not elapsed time. Suggest
  classification for one Zone is a named batch and carries no ceiling.

### Edge-owned assignments

Thermal bridges were the first feature to store a record on a `Sketchup::Edge`; hot-water piping
and ERV ducting reuse these rules.

- The record is an attribute dictionary on the Edge, written through `Records::EntityStore`. No
  Model-level registry lists tagged Edges, so a copied Edge carries its record and an erased one
  takes it away. A feature whose records other records point at decides for itself whether it needs
  a registry.
- The record carries an id because the engine's reference scan requires one. Every split, copy and
  paste puts the whole dictionary on each piece (`SKETCHUP_HOST_BEHAVIOR.md`), so one id held by
  several Edges is routine: reads mark it copied, nothing re-issues it, and the resolver proves an
  occurrence by its path and the record id on that path, never by refusing the duplicate. A heal of
  two differently tagged halves keeps one record and drops the other silently; a rescan is the only
  reader of that loss.
- Zones decides which Zone holds an Edge. A feature reads `ph_composer.zones.containment` for native
  paths it holds (a selection, a pick), and its reference target's `locate:` calls
  `Zones::Occurrences.resolve_element`, the same resolution with Zones' `target.*` refusals, because a
  `locate:` runs at apply with no request. The feature never restates the nested-Zone, wrapper,
  stamped-container or cutting-instance rules.
- Writes refuse through shared storage, a locked Group and another Zone, as Face writes do. Every
  assign or clear is one command over explicit references, bounded by a limit the feature's schema
  owns (250 Edges for thermal bridges), refusing as a whole.
- No observer watches Edges. Reads scan the Model when asked. The thermal-bridge schedule is one such
  read and registers no snapshot section: at 5,000 assigned Edges in a Model of 50,000 it costs about
  two seconds, so the panel asks for it on opening the Schedule and on Refresh, never on every refresh
  (D3b-13, measured in P3b-04).
- Runs are derived, never stored. The pure builder (`features/thermal_bridges/runs/`) joins Edges of
  one Zone occurrence, type and quantity where they share a vertex, keyed on the Edge's container path
  plus the vertex id, so two placements of one component never join; a run ends at a free end or a
  vertex where the count of joining Edges is not two. The same function serves the live read and the
  export, which feeds it the snapshot's `edge` entries.
- An Edge carries at most one assignment of each kind; a thermal bridge Edge is envelope geometry
  and a pipe or duct is a loose line in its own Group, so the two never share an Edge.

## Pyodide and Export boundary

The embedded runtime is served from a token-qualified loopback HTTP origin. `file://` and an
unqualified loopback URL are not valid shortcuts. The manifest controls the allow-list, MIME type,
hash, source URL, version and installed size of every runtime asset. The runtime runs in its own
page, `html/runtime/`, which `runtime/runtime_host.rb` opens on that origin for one Model session;
the panel never loads Pyodide, and nothing starts the runtime when the extension loads or the panel
opens. The server's token authorizes loading runtime assets and nothing else; it is not an agent
credential.

The agent listener is a second loopback server (`agent_access/server.rb`), separate from the asset
server and never sharing its token: it binds a fixed, configurable port while an agent token is
live, answers MCP over `POST /mcp`, and runs tool calls on the main thread through a UI-timer pump,
as the asset server's pump lets its own workers run (AGENT_INTERFACE.md, "User-controlled local
access").

A feature adds export coverage with `feature.export_contributor(name, section_version:, result:,
report:, preflight:, requires:, projection:)` in its `install`, whose block returns the section's records, and a Python `Section` with
the same id listed in `python/ph_composer_translation/composition.py`. The block reads through
`Export::RecordReader`, which exports only declared values and named extension fields, passes
`user_data` through where the owner asks (`user_data: true`: Zones, Faces, Window Units onto their
Apertures, and Assemblies onto their Constructions, as Honeybee carries it) and leaves it out with a
finding elsewhere, leaves `local_only` data out with a finding, and blocks on data whose export relevance is
unknown or required but unexported. When the translator adds result fields for the feature, the
contributor declares them in `result` and renders them in `report`; they arrive under the section's
id. A feature whose translated objects sit inside another feature's, as Apertures sit in Faces,
declares a Python `Attachment` instead of being imported by the host's section. The extraction
carries every section under `sections`; `export/` knows no feature. The development example
(`tools/examples/foundation/`, with `example_doors.py` for an attachment) is the working pattern.

Export preflight is a declared query owned by the same feature as its contributor. It returns
findings and optional registered repair actions. The shell runs only selected repairs before the
read-only task and repeats preflight afterward. Sections may produce nonblocking findings through
the generic Python section hook; feature omission rules remain in their sections.

Collection resumes a detached geometry traversal in slices of at most 100 entities with an 8 ms
budget. One native Face capture and one contributor callback are indivisible. The task checks a
separate export content generation during collection, on translation return and before canonical
commit. Camera, selection and edit-path navigation do not invalidate it; content commits and
Undo/Redo do. SketchUp 26.1's navigation-only commit and the preceding content-commit ordering
are measured in [P1-E evidence](../planning/archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md).

The HBJSON and its report are written as one pair or not at all (`export/artifact_pair.rb`). Both
are staged beside the destination and verified, a journal records the plan, the previous pair moves
aside and the new pair is renamed into place; the next run to the same destination rolls back an
interrupted one from the journal. Blocking findings write no canonical files, HBJSON and report are
always selected together, and Export never saves the SKP (P1-Q4, confirmed 2026-09-29).

The runtime installs only manifest-pinned local wheels on explicit export. There is no pip resolver,
external download or system-Python fallback. The shipping composition supplies authored
Assembly constructions and Window Apertures through their feature contributors. Missing or
incomplete assigned definitions block normal export. The separately composed synthetic provider
exists only in historical development acceptance and is never a shipping fallback.

The privacy allowlist is the shell's fields plus every contributor's declaration under its section
id, composed on each check, so a result field no declaration names fails the export at `checking`. The report embeds
the translator's result document unchanged.

The canonical HBJSON is a string in that document, so the allowlist cannot see inside it. The
guard (`export/hbjson_metadata.rb`, called from `Export::Privacy.validate!`) parses a copy: under a
top-level `user_data` key that begins a declared key, only the dotted leaf keys export contributors
declare with `user_data_keys:` may appear (`zones` declares `ph_composer.level` and
`ph_composer.building_segment`, which its translation writes on each Room; empty maps are allowed);
any other top-level key is a user's own passed-through data (Ed, 2026-10-13); `extension_data`, usernames and path keys refuse at
any depth; every string passes the local-path check on its own. A refusal is
`export.privacy_undeclared`. The bytes written are always the translator's, never re-serialized
(Ed, R-D2, 2026-09-30).

Ed confirmed explicit translation-section dependencies on 2026-09-18. Each section declares the
typed results it needs from other sections. The coordinator orders execution and supplies those
results without feature-specific logic. Missing or circular dependencies produce explicit errors.
If a required result fails, dependent output receives an explicit finding rather than a substitute.
The existing record-level and contract-level failure policy still applies. Phase 0 proved the
contract with synthetic sections; Phase 1 composes the real `FaceSection` and `ZoneSection`, and
later building sections land with their owning features. A
section declares typed `Requirement`s; missing, mistyped, duplicate and cyclic requirements stop the
run before any record is read, and a record whose required object did not translate gets a
`dependency.unavailable` finding and no object.

`Inputs.get(requirement, id)` reads one declared typed object; `Inputs.all(requirement)` reads
the declared section's translated objects as a detached mapping. Both reject undeclared
dependencies. Window export adds construction and Aperture sections through the same contract;
Apertures declare an attachment to their gross parent Faces, and the model assembly joins them, so
Zone translation names nothing attached to its Faces. Neither joins raw extraction dictionaries or
changes the coordinator for a specific feature.

The translation package reads the extraction into typed records in `contract/` and never reads a
section by key after that. Every section follows one failure policy. A defect that leaves the
document or a section unreadable fails the export as `payload.contract`. A defect in one field of
one record costs only that record: translation reports it as a finding on that object and the rest
of the Model translates. honeybee and ladybug are imported only through one module, on first use
through `stack.load`, so every module of the package imports without the stack.

After changing the shipped Python package or panel assets, refresh the manifest before CI:

```sh
uv run tools/runtime/vendor.py --refresh-manifest
make ci
```

The HBJSON artifact is carried unchanged into every downstream gate. SketchUp produces the
artifact; it does not decide where the artifact goes afterward.

The export task's watchdog bounds a silent runtime from Ruby, because a page that never answers
cannot report its own timeout (`export/task.rb`). Before `runtime.ready` it waits the manifest's
`boot_deadline_ms` plus 15 seconds, then fails with `runtime.boot_timeout`; once ready, a
translation that sends nothing for 300 seconds fails with `runtime.unresponsive`. Both stop the
runtime, write nothing and report effect `none`; a later answer applies nothing. Cancel stays
available while translating. These are starting defaults until the proving host measures them.

## The exporter seam

HBJSON is the canonical interchange. An exporter is a second consumer of it that writes another
format. It runs after the HBJSON translation, inside the same Pyodide runtime, and reads only the
HBJSON document and the user's export choices. It never reads the export contract or the Model.

The METr exporter is the first. It calls PHX to build a PHX project from HBJSON and PHX's WUFI
writer to produce the METr model. Two facts gate it:

- [Phase 0 B1](../planning/archive/phase-00-foundation/evidence/spike-phx.md) proved PHX 1.57.1
  conversion with nine pinned wheels installed without dependency resolution. The METr path
  does not import the omitted dependencies. D12 defers METr integration and actual import until
  further feature development. Phase 1 selects its HBJSON translation payload independently;
  upstream dependency cleanup is not a prerequisite for the proven PHX route.
- The payload budget. The predecessor shipped 20 MB. The manifest records the installed size of
  every asset and CI enforces the budget; the METr exporter's cost is measured before it is
  accepted.

An exporter registers in `python/ph_composer_translation/composition.py`: a name, the format it
writes, a file suffix, the options it accepts and a `run(hbjson, options)` that returns its output
and findings. It receives a copy of the options and nothing else. No exporter is registered yet
(`EXPORTERS` is empty); the Export report will list every exporter that ran and what each omitted. A third exporter adds one registration and no change to
`export/`, the translation package or any feature.

## The library provider seam

The implemented library foundation supplies the file/folder provider, session catalogs, resolution
and guarded copy. Materials supplies its own kind adapter. The model owns each editable copy;
no provider is required or privileged. No provider address is a shipped default.

A registered provider factory is called with the published registry and returns configured
provider instances. Each
instance answers `id`, `provider_kind`, `label`, `kinds`, `list(kind)` and `freshness`. It receives
neither a Model nor a handler request. A list returns an immutable `Library::Provider::Batch` with
complete row snapshots, structured warnings and unavailable-kind identities. Provider metadata
contains configured ids and labels. Private paths stay in per-machine `Library::Setup`, stored as
one base64 JSON value in SketchUp defaults, and inside the provider that reads them. Provider
exceptions become code-only public failures; their text and causes do not enter results.

The file provider reads the neutral envelope in [LIBRARY_FILE_FORMAT.md](../docs/LIBRARY_FILE_FORMAT.md).
It loads a single file or the immediate JSON files of a folder, with implemented bounds of 32 MiB
per file, 64 MiB aggregate and 20,000 rows. Exact-limit and one-above offline checks cover these
bounds; host budget measurement remains required. Admission validates wire schemas and omits
undeclared fields before publishing a generation. Duplicate record ids withhold the affected
library and kind rather than selecting a winner.

Catalogs live only on the ModelSession, keyed by configured provider and wire kind. A successful
refresh publishes an immutable generation. Failure retains the prior generation with failure state
and age. Setup changes invalidate the affected provider ids across open sessions, including removal
and re-addition. Public reads never copy records or open a dialog. The providers query is
`ph_composer.library.providers`; its snapshot section has the distinct global id
`ph_composer.library.provider_catalogs`.

Kind owners register pure wire mapping, reverse mapping and versioned fingerprints, plus schema-
validated callbacks for local projection, create, replacement and optional assignment. The neutral
coordinator names no feature or assignment field. Local projection is read-only, but can see staged
records through its owner-bound projected engine. Mutation callbacks share the caller's proposal;
input, result or ownership failures poison that proposal even if contributor code rescues them.
Trusted Ruby callbacks still obey the normal host-write contract; this is not a Ruby sandbox.

Resolution checks exact source identity before canonical local names and mapped values. Reviewed
replacement retains the local id and references, preserves metadata and unavailable extension
payloads, and requires the reviewed raw authored fields as guards. Copy plus assignment commits as
one native transaction. Preview and invoke recheck session revision and catalog generation. Their
first gesture timestamp is stable within that revision and excluded from semantic fingerprints.
The owning feature supplies one source-attribution report line per copied record without changing
HBJSON. The [panel-closed example](../tools/examples/library/materials_walkthrough.rb) exercises
load, preview, copy, retry and read-back.

The connection provider remains proposed. Its HTTPS transport, grants, credential storage and
asynchronous reconfiguration/disposal guards belong to the
[libraries packet](../planning/archive/libraries/PRD.md). The file provider's
implementation does not establish those host contracts.

## Errors

Every extension exception descends from one `Error` and is either a `UserError`, whose message is
written for the user and may be shown verbatim, or an `InternalError`, whose message is for the
log while the user sees a generic line. Feature code raises the most specific class once and never
rescues one class to re-raise another. A `rescue StandardError` belongs only at a boundary that
turns an exception into a message or a verdict: the panel callback, the command and context-menu
dispatcher, an observer callback, a task tick, or the Export run. Input coercion goes through
`Coerce`, which raises a `UserError` naming the field.

## Help & Diagnostics

`shell/support_dialog.rb` owns a small HtmlDialog of its own (`html/support/`), opened from
Extensions > PH-Composer > Help and Diagnostics… (SketchUp strips `&` from menu titles), from the
panel footer, or from Get help on a failure
notice that carries `detail.incident` (`panel.support`). It needs no Model, no panel and no Python.
If its page cannot be built or does not report ready within five seconds, a native message box gives
the version, build, log folder and help address. It reads build, manifest and log health when it
opens and never writes the Model.

`shell/support_report.rb` builds one plain-text capture: a header (report format 1, capture time,
version, build and commit, manifest, host, supported-host verdict, log health, the selected
incident, the included event range or the reason there is none, and what is never included),
then at most 256 KiB of the newest log lines, each rebuilt by `Diagnostics.sanitized` from the
fields and values the log accepts, each frame checked on its own. A read failure falls back to this
session's in-memory lines and says so; this session's lines that never reached the file are merged
in by time whatever the log's current health, and the merged history is bounded again. Lines that are not readable records are counted in the header,
never silently dropped. The capture is kept under its id: the page previews it, Copy copies the previewed text, and
Save writes the same capture's bytes through a temporary file renamed into place; a capture
replaced by Refresh is refused. Report a problem opens the public issue page only after the page
says the issue is public. Clear diagnostic history deletes the log and its archive and keeps saved
reports; a file it cannot delete is reported as not cleared and becomes the log's last storage
error, and clearing never reports a failing log as writing again. Any failed request whose outcome
carries `detail.incident` gets a notice with Get help unless its answer raised one of its own. Reopen panel closes and reopens the panel window; Reset display preferences writes each
display preference's default (`Preferences.reset_display`) and leaves libraries, approved
locations and agent tokens alone.

## Panel protocol

Implemented in P0-E and extended in Phase 1. `shell/panel_messages.rb` declares every message
between the page and Ruby, with the payload keys each carries: `panel.ready`, `panel.diagnostic`,
`panel.support`, `panel.undo`, `panel.redo` (the platform Undo and Redo shortcuts in the panel, stepping
SketchUp's own Undo for the shown Model unless a text field being edited has focus), `panel.focus` (the
panel's window gained focus; since closing the active document fires no callback, the host then brings the
panel to the active Model, or to a snapshot of no Model, as it also does on any request once no Model is
active), `action.invoke`, `action.status`, `view.invoke`, `setup.invoke`, `query.invoke`, `file_export.invoke`, `preferences.set` and the shell's Export command (`export.start`,
`export.preflight`, `export.status`, `export.cancel`, `export.latest`) inbound; `panel.snapshot`,
`action.result`, `view.result`, `setup.result`, `query.result`, `file_export.result`,
`preferences.result`, `export.result`, `panel.notice` and `panel.failure` outbound. Ruby refuses an inbound type or payload key the table does not declare and answers with
`panel.failure`; it refuses to publish an undeclared outbound key. `tests/panel_messages_test.rb`
reads the page sources and fails when the page sends or handles a type the table does not declare.

A `run` request unanswered after 20 seconds (`html/request.js`, a starting default) stays pending
and raises a warning. For an action the warning offers Check status, which sends `action.status`
with the original request id (a transport may add `expected_revision`; status ignores it).
`shell/panel_requests.rb` keeps the shown page's last 64 action request ids per session with their
sequence and forgets them all when a page reports ready, since a new page numbers its ids from the
start. Ruby publishes a snapshot, then answers that request's own `action.result`: the retained
outcome (CONTRACTS, "Retries"); `request.outcome_unavailable` with effect `unknown` once it has
expired, or for a missing id after any id was dropped to keep the map bounded; or
`request.not_received` with effect `none` for an id this page never sent while every id is held.
Page messages arrive in order, so such an id was never received. Nothing is sent again. Any other
request offers only Stop waiting: the channel answers it itself as failed with effect `unknown`
(`request.abandoned`, a page-only code), which its owner consumes like any result, so a form
settles; the host's late answer is ignored. These ways out sit in their own
bar, one row per unanswered request, apart from the single notice slot, so no other notice and no
dismissal removes them; each acts only on the request that raised it and goes when that request
settles. The bar shows inside an open modal form, where the page behind cannot be reached.

Features add no transport types. A feature's panel request is `action.invoke` naming a registered
action, a viewport-state request is `view.invoke` naming a registered view command, a session- or
machine-state request is `setup.invoke` naming a registered setup command, and its
panel data is a registered snapshot section ([CONTRACTS.md](CONTRACTS.md), "Registration" and "Public interface").

## Panel

The panel is one client of `PhComposer::API`, not the owner of any Model behavior ([CONTRACTS.md](CONTRACTS.md), "Public interface").
`shell/panel.rb` owns the dialog and nothing else a feature reaches:

- It shows the active Model. For each session it shows it connects once with its own caller
  handle and gives the panel's mutations their own sequence numbers (CONTRACTS.md, "Retries"). The
  page's request ids only correlate a result with the view that asked.
- `action.invoke` carries the session the page showed and the revision it last rendered. An action
  for a session the panel no longer shows is refused as `session.inactive` with nothing written.
  The result is published after the authoritative snapshot (CONTRACTS.md, "Revisions, transactions
  and host execution").
- The page loads from the shipped file with `set_file`. The message callback is bound to its
  dialog, so a closed page's late message is ignored. The panel refreshes the shown Model's
  snapshot after committed changes, Undo, Redo, an edit-path change and activation, through the
  session's coalesced timer.
- Every shipped page (the panel, Agent Access, Help & Diagnostics, the runtime page and the offline
  help) declares a `Content-Security-Policy` meta, with `tests/page_csp_test.js` holding each page to its
  policy: no inline script or event handler, and only the extension's own files. The panel and its two
  dialogs reach no network; the runtime page reaches only its own loopback asset server and allows
  `'unsafe-eval'` for Pyodide on the Chromium 88 floor. A page starts from `html/boot.js`, which names the
  entry module on `<body data-phc-entry>`. Inline styles are allowed on the panel, because a blocked
  run's report shows in a `srcdoc` frame that inherits the panel's policy, and on the generated help
  page; nowhere else. The panel reports a blocked load as `panel_csp_violation`. Ruby's
  `execute_script` runs under the policy; a script element it creates is held to it like any other
  (host gate in [SKETCHUP_HOST_BEHAVIOR.md](SKETCHUP_HOST_BEHAVIOR.md)).
- A session notice reaches the open panel if it shows that session and otherwise waits, bounded,
  for the panel to show it. Nothing a programmatic caller does opens or raises the panel; only the
  Extensions menu command does.
- A development composition entry may add a script the page runs after the kit starts
  (`Panel.add_development_script`). Shipping features declare their modules under
  `html/features/<feature>/` ([EXTENSIBILITY.md](EXTENSIBILITY.md), "Organization and dependencies").

The page:

1. `html/panel.js` keeps one state: the last snapshot, the active tab, the latest correlated action
   result and one notice. The display preferences the host has not yet confirmed are the page's own
   bookkeeping beside it, not shown state.
2. `receive(envelope)` folds each message into that state; a result or notice for another session
   is not painted, and a snapshot for another Model drops the previous Model's result and notice.
3. A message that changes the state or the display profile re-renders each registered section once
   with `render(root, state, send)`, after the notice, unit toggle and tabs; one that changes neither (a
   confirmed preference, a result for another session) renders nothing. A section that throws is logged
   and the others still paint. Tab changes only toggle panes and send nothing. The panel is the one
   owner of the repaint a display preference change needs: a section does not subscribe to the
   preference store to repaint the panel, and only components that patch their own nodes (record edits,
   unit fields) subscribe.
4. `panel.section(name, render, { pane })` registers a section. A section whose mount node is not in
   the page is created in its pane, so a feature adds one without editing `index.html`. A section
   owns its local drafts and resets them when `state.session` changes, and patches its nodes
   rather than re-parenting them: moving a focused input takes the user's focus. A unit field
   commits on blur only while its input is still in the page, and a disposed field never commits,
   so a repaint or a Model switch cannot send a half-typed draft.
   `panel.navigate(tab, intent)` opens another tab from a control: it goes through the same
   navigation guards as a tab click, then calls `onNavigate(root, intent)` on each section of that
   pane that passed one to `panel.section`, such as the Library opening at one kind.
5. A refusal or failure stays on screen as a warning or error notice until dismissed; information
   fades on the next interaction. Notices float over the panes and never reflow them.

Each panel file is one `PhComposerUI.define(name, dependencies, factory)` call, named by its path
under `html/`. `PhComposerUI.start()` builds the modules in dependency order and throws on a missing
or cyclic dependency. The script lists of `index.html` and the development preview are generated
from those declarations (`make panel-manifest`), and `make ci` fails while either is stale.

Every correlated panel action goes through `html/request.js`: `request.channel(session, send,
label)`; `run(action, params, { onDone, onFail })` is single flight and pending before the message
leaves, and `consume(state)` settles the action-result slot for that request once; `send` never
refuses, for views that keep several requests in flight. Record forms are `record_form.js` specs,
snapshot reads go through `snapshot.js`, and unit descriptors for stored fields are `fields.js`. The
record table and inventory controls (`table.js`, `table.css`, `view_controls.js`) arrived with the
Zones / Faces screen, ported from the predecessor and trimmed to what it uses; neither names a feature.
Inline cell drafts (the predecessor's `record_edits`) arrive with the first screen that edits
record cells in place.

**Browser floor: Chromium 88**, the engine SketchUp 2022 was measured on and the one assumed for
the 2023 floor. Syntax is ES2020. Runtime APIs that arrived after Chromium 88 are refused by
eslint. The 2023 host's CEF version is confirmed when a 2023 host is available.

## Display units

- All persistence, every library file and wire format, and all calculation are SI, as in
  honeybee-ph and PH-Navigator web. IP is a conversion for user-facing display and entry only.
- Stored fields stay in their canonical SI unit, named by the field. The SI/IP display preference
  changes presentation and the unit assumed for unsuffixed input only; it never dirties the SKP,
  adds an Undo step or touches `UnitsOptions`.
- Every panel number is parsed and formatted through `html/units.js`. Do not add a second parser or
  unit table. The length grammar, regional number formats and per-quantity factors are the
  predecessor's U1 contracts C1 to C5 (`../../../ph-navigator-sketchup/planning/archive/units/PLAN.md`).
- The first keystroke or paste fixes a draft's starting profile, so a switch never reinterprets
  text already typed.
- The preference lives in `Sketchup.write_default` (`shell/preferences.rb`), never in page storage.
  A dimension scope's formats are one base64 JSON value, because SketchUp 26.1 reads back a stored
  string containing a double quote as nil. A dimension scope is a dotted name under its feature's
  id; a scope never chosen takes the system default (mm in SI, decimal inches in IP).
- A preference write succeeds only when `write_default` returns true and the value reads back;
  otherwise the panel shows the refusal, never "saved". A stored map this version cannot read,
  damaged or written by a later version, refuses the change and is left as stored. Changing one
  scope keeps every other stored entry, recognized or not. Colour-by stays on when its choice
  cannot be remembered; the failure is logged.
- Ruby never formats a unit-bearing value for the panel. It sends message parts with canonical
  values and the panel formats them. The Export report captures the preference once when the run
  starts; HBJSON stays SI. Ruby report quantities include `volume` (canonical m³, displayed as
  ft³ in IP, two decimals) and `airflow` (canonical m³/h, displayed as cfm in IP, one decimal),
  agreeing with the panel through `tests/support/units_vectors.json`.

## Rules for later features

What a new feature owns and where each rule is enforced. The predecessor's restructuring made
these true of every feature it had, so a new one that follows them needs no change to `shell/`,
`session/` or another feature's folder. A composition-root registration is permitted.

- **One folder.** `features/<name>/`, listed by hand in the composition root's `FEATURES`. Outside
  that registration, shared orchestration names no feature, and features name no other feature's
  internals. A capability the foundation itself provides and no feature owns (`RecordQueries`,
  `ColourBy`) registers through `FOUNDATION_FEATURES` with the same `install` interface.
- **One `install`.** Every registration happens there: record kinds, queries, actions, snapshot
  sections, host-event subscriptions, the export contributor. There are no feature flags and no
  inbound panel handlers: a feature that is not composed is absent, and the panel reaches a
  feature only through its registered actions and sections.
- **One namespace.** Every declared name starts with the feature's id (`<feature>.<verb>`),
  defined in `install` with its parameter and result schemas and confirmation policy.
- **Per-Model state** is one object from `session.feature_state(:name)`.
- **Host events** arrive by subscription from `install`; observers are for external geometry
  changes only. Plugin-owned data changes through direct Model operations.
- **`core/`** holds what more than one feature needs and no feature owns: the record engine,
  dictionaries, JSON and geometry primitives, units, model operations.
- **Value objects at the boundaries.** A record is normalized by its schema on the way in and
  projected to named keys on the way out.
- **Two languages, one contract.** Anything Ruby sends to the shipped Python is pinned by a
  fixture both sides read, so a key renamed on one side fails on the other.
- **The panel** is a module graph. A feature's section registers itself with `panel.section`,
  reads its snapshot section through `snapshot.js` and sends correlated actions through
  `request.js`. Cross-feature navigation is designed with the first feature that needs it.
- **Geometry first, then action.** The default interaction is: the user selects geometry, then
  chooses the action, which applies to that selection (a right-click item, a panel action). Each
  attribute (face type, boundary condition, Assembly, Zone fields) is set on its own. A modal
  action-first tool (paint, place) is a secondary route, and it becomes the primary one only when a
  feature's plan records why its UX is demonstrably better. Ed confirmed this rule on 2026-09-30
  ([Phase 1 UX follow-ups](../planning/archive/phase-01-ux-followups/README.md)).

## Durable delivery rules

- A mutation ends with `session.changed(:feature)`. Nothing else rebaselines the reconciler or
  refreshes the panel, and feature code never references `Panel`; background failures reach the
  user through `session.notice`.
- A notice never opens the panel: it shows in an open panel that shows its Model and otherwise
  waits for the panel to show that Model. State a user must act on belongs in the snapshot, where
  the panel shows it whenever it opens.
- A user-triggered operation is an action, defined in the feature's `install`. Toolbar, menu,
  context menu and panel buttons all run actions through `Actions.run`, which owns coercion,
  confirmation, error mapping and the post-action `session.changed`, and answers every run with one
  `Outcome`. Business methods contain no `UI` calls.
- Data the panel needs on demand rather than on every Model change is a read-only action the
  panel calls. Never `Panel.publish` from an action body: the message is lost when the panel is
  closed or reloads, and it puts transport in feature code.
- A validation rule is one row in a rules table with a severity, and the Export gate blocks on
  blocking findings only. Never add a second data scan for a new panel or report.
- Add a field as one line in the entity's schema, typed. Optional fields need no migration when an
  older Model can represent absence; introduce a migration only when a stored meaning changes.
- Test direct and nested placements, repeated definitions, Undo/Redo, save and reopen,
  active-path export, and error recovery. A happy path at Model root is not enough.

### A definition record, end to end

Attached zones are the implemented definition-record example
(`features/zones/faces/attached_zone.rb` and its declarations). Materials and Assemblies follow
this foundation when their feature lands.

- **Storage.** `Records::RecordKind` defaults to `DictionaryStore`, one Model dictionary named
  `ph_composer.records.<kind id>`, one JSON string per id. Registration adds the dictionary to
  the export attribute guard. Reads reject invalid JSON, unknown fields and a different exact
  `schema_version`; they never repair a record.
- **Schema.** `Records::Field` carries a JSON Schema, including nested object/array shapes, and
  whether the field is required. `Records::Reference` declares typed ids. Top-level references
  can be fields; nested references are supplied with `RecordKind`'s `references:` argument,
  using a dotted key and `[]` for array traversal. Registration checks the path against the
  values schema. Ids use a kind prefix and twelve random alphanumeric characters. There is no
  automatic common name/notes/source/timestamp field set or per-kind migration machinery.
- **Metadata.** `user_data` and `extension_data` are reserved engine fields. Ordinary edits
  preserve unrelated metadata and unavailable extension payloads. Provenance is an optional
  feature-declared field, validated by that feature; the foundation does not interpret it.
- **Commands and Undo.** A registered action reads through its request's engine and proposes
  creates, updates or deletes into `Operations::Proposal`. Dispatch validates the proposal and
  opens its one native operation. Updates carry `expected_values` keyed by stored field name;
  a mismatch refuses the whole proposal. A definition owner calls
  `request.retarget_references(kind, from:, to:)` without naming its referrers. Registered
  referrers add steps to that same proposal and return typed final entity occurrences for the
  incoming-reference check. Any refusal poisons the whole proposal even if a caller rescues it.
- **Panel.** Shared table, view controls and anchored bubbles present detached snapshots.
  `record_edits` is configured with an action and field list, sends `values` and
  `expected_values`, and preserves refused drafts. It confirms an edit against both its
  correlated outcome and the authoritative snapshot. An owner opts into `cancelControl`, a visible
  Cancel on a draft that needs one, and `refusalText(outcome)`, its own words for a refusal.
  Peer subtabs share one navigation module.
- **Export.** A feature declares its versioned extraction contributor and the metadata keys it
  permits in HBJSON. Its Python section is explicitly composed with declared requirements.
  Export reads the authored records; it never repairs or substitutes for missing definitions.

### UI kit conventions carried over

- `ui.pageHeader({ title, count, actions, primary })` for the header every pane opens with: title,
  muted count, secondary actions, then the one filled primary action at the right, and no caption.
  `--page-gutter` in `base.css` is the one horizontal inset; a screen does not style its own heading
  or set its own page padding.
  `setTitle` renames it in place. A session that covers a work surface uses the same header, with
  Cancel as its action and Save as its primary.
- `Subtabs` reports a refused tab by name (`refused(reason, nextId)`) and a click on the shown tab
  (`reselected(id)`), so an owner whose surface is covered can leave that session the way its Cancel
  does. A focused field in the shown surface holds a switch, except a search field, checkbox or radio,
  whose value already applies.
- One floating notice, the panel's (`panel.notify`). A feature view does not build its own. An
  information notice fades on the next interaction and never blocks the control beneath it.
  `panel.notify(message, tone, action)` may carry `{ label, run }`, the way out on the notice itself
  (cancel the held draft); `panel.withdraw(message)` takes it down once it no longer holds, such as a
  refused tab change that has since gone through, and leaves a newer notice alone.
  `panel.outcomeText(translate, { owner })` lets a view restate a refused or failed outcome of its own
  request and returns a disposer; the host's message and code stay the contract. Each translator gets a detached copy and answers a string or null; one that throws or
  answers anything else is skipped and logged under its owner, so the result is always recorded and
  its requester settles.
- No refusal leaves a screen behind an invisible draft. A refused choice that wrote nothing returns
  to the Model's value and keeps its reason; a draft that is held (refused typed text, a conflict)
  shows a visible Cancel, and a guard notice blocked by it offers that Cancel too
  (`planning/archive/copied-zone-edit-refusal/`, D-4). A bulk change with any read-only target is
  refused whole, never narrowed to the writable part of the checked set (D-5).
- `RecordForm.required(label, control)` marks a field a record form waits for, and a disabled Create
  says why in the form's status line. New acts at once where the record draws something to work on;
  a record that is only numbers keeps a form.
- `panel.workedOn(prefix, tab)` and `panel.tabFor(owner)`, so a foundation screen such as Export can
  send the user to the tab a gap is looked into without naming a feature.
- A table action may start a group (`starts: true`), set apart by a hairline, for actions that act on
  something other than the row's record.
- One work surface per pane. A pane may place an inspector beside it for what the current tool or
  selection needs (`panel.section` with `region: "inspector"`), or carry those controls in a selection
  bar that floats over the bottom of the work surface (`selection_bar.js`), as Zones / Faces does. Do
  not stack a second job under the work surface.
- A table column may declare header actions (`options.headerActions(field)`): a column menu
  (`column_menu.js`) for sort and value filters, and a Colour-by toggle (`sections/colour_by.js`
  `HeaderToggle`) bound to a mode or to a group modes declare. Header and row icons may show only on
  hover or focus; a state (a pressed toggle, an active filter, a checked box) stays visible at rest.
- `ui.ViewControls` for filtering, ordering (with a sort-direction toggle, or from column menus with
  `columnSort: true`) and grouping; filtering hides rows and never drops
  records, so drafts and expansion survive.
- `ui.Bubble` for non-modal editors anchored to a control: shared surface and pointer, viewport
  positioning, one active bubble, Escape and outside-click dismissal, focus return.
- `ui.actionRow(cancel, primary, destructive)` for confirmation rows. Cancel on the left with an x;
  the primary action on the right with a check, or a trash icon and red treatment for deletion.
  Action-specific text (Apply, Create, Delete), never OK.
- App hover, focus and selection use the primary blue `--interaction-highlight` tokens. SVG drawing
  selection and drop targets use separate red `--drawing-highlight` tokens. Both token sets are
  defined once on `:root` in `base.css`; screen stylesheets use the tokens and never restate them.
- Reserve header action height before conditional buttons appear. Hover bubbles wait 450 ms and
  leaving cancels the pending open; clicks open immediately.
- Inline pending feedback stays out of row flow, because measured transient text changed row
  height and shifted layout.
- After installing frontend changes, reopen the HtmlDialog. Installation alone does not prove that
  an already open panel is running the new assets.

Before changing or reviewing an HtmlDialog screen, load the UI polish skill named in `AGENTS.md`.

## Fresh-process host loop

An install is preparation, not host validation. Loader metadata, Ruby constants, toolbar state,
the panel document and the Pyodide worker can all survive a partial reload. For an acceptance run:

1. Run `make ci`.
2. Run `make rbz`, `make rbz-check` and `make install`.
3. Quit every SketchUp process and relaunch the supported host.
4. Open the intended Model and confirm the exact Model path, extension version and active path.
5. Run the user workflow, including Undo, save, close, reopen and recovery cases.
6. Export the HBJSON and report pair, and the METr model when the exporter is in scope, and
   reconcile Model storage, panel state and artifacts.
7. Keep Model copies, paths, screenshots, raw attributes and artifacts under `_private/`.

Steps 3 to 6 run from a terminal through the development host bridge; a person at the console is
the exception.

## Common failure signatures

| Symptom | Likely cause | First action |
| --- | --- | --- |
| Old version, toolbar or behavior after `make install` | SketchUp retained the prior loader, constants, command objects or panel | Quit every SketchUp process and relaunch; confirm the version before retesting |
| `conformance_failed` after a Python change | Shipped Python changed without matching manifest hashes | Refresh the manifest, run the native Python tests and linters, then inspect the cause |
| `volume_moved` after switching editing context | The new active path was read before closing the previous Volume | Preserve the previous path and run the boundary reconciliation first |
| Nested output is translated or offset twice | Parent and child transforms were both applied at more than one layer | Trace one root-to-leaf path and prove each transform is accumulated once |
| The runtime refuses to start (`RuntimeManifest::Invalid` naming a file) or `make ci` fails `runtime-check` after an `html/` or `python/` edit | Manifest hashes no longer match the shipped assets | `make panel-manifest`, then `make runtime-manifest`, then `make ci` |
| Offline tests pass but the feature fails in SketchUp | Stub behavior, host lifecycle, CEF or Pyodide differs from the offline environment | Run the numbered real-host gate in a fresh process through the bridge |
| Every Volume reads `volume_moved` after reopening a saved file | The active path was changed inside `onPreSaveModel` | Never change the path or lock the open Volume during a save |
| A Volume stays unlocked after Escape | The commit callback arrived before the path-change callback and the baseline was rebaselined to nil | Queue the exit protection from the baseline in both callbacks |
| A panel row click does nothing from inside a Volume | SketchUp cannot select outside the open context | Close and protect the current Volume before selecting |
| The bridge `eval` returns but the deferred work has not run | UI timers cannot fire while the eval blocks the main thread | Read state in a later call |
| A Redo keystroke through System Events does nothing | The keystroke reached the panel dialog, which has no redo | Raise the document window by title, then send the keystroke; or `Sketchup.redo` |
