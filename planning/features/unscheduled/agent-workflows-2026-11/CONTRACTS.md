# Proposed contract changes

STATUS: C01 bound and implemented by AW-01 (API 1.34); C02 bound and implemented by AW-02 (API 1.35); C04 bound and implemented by AW-03 (API 1.36); C03 definition part bound by AW-04 (API 1.37); C03 occurrence part bound by AW-05 (API 1.38); C05 bound by AW-06 (API 1.39); C06 and C07 bound on the AW-07 branch (API 1.40); C08 remains a proposal. Baseline API 1.31.
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication

The durable authorities remain `context/CONTRACTS.md`, `AGENT_INTERFACE.md`, `EXTENSIBILITY.md`
and `TECH_STACK.md`. This file defines this packet's proposed deltas and avoids restating those rules.
Exact new operation names are bound at the owning stage and recorded here before code.

## C01 · Target identity and ownership

A null Face identity asserts the absence of an authored Face record at that occurrence. It is not
a wildcard. Single, batch and metadata writes use the owner's same writable resolver, including
the target's own lock and its ancestors. Proposal apply repeats relevant checks.

Reuse SUI-02's claiming-store mechanism. Define which claimed descendants prevent conversion of a
plain wrapper, and how deletion protects a subtree carrying another owner's record/reference.
Read malformed claimed records as occupied for eligibility, without repairing or erasing them.
Do not prohibit legitimate Face/Edge coexisting assignments or create reverse feature dependencies.
Legacy conflicting data gets a read-only diagnostic and a defined repair/refusal, not silent deletion.

Space creation's receipt identifies accepted and rejected source paths, reasons and resulting
Space/Volume grouping. A reviewed accepted set has a digest or equivalent explicit precondition.
The UI's intentional filtering stays explicit. Any new strict mode is additive and documented.

**Bound at AW-01 (API 1.34).** No new operation. New names:

- `Records::EntityStore.claimed_within?(entities)`: the recursive claim check.
- `Records::EntityStore.check_subtree_removal!(entity, path, owned:)`, refusing the new foundation code
  `target.foreign_records` with detail `total` and up to 20 `records` (`dictionary`, `key`, `path`). It reads
  every registered entity store by presence, so stranded records (a Zone on a component) count.
- Zones finding `zone.ownership_conflict` (reference `zone_id`, `entity_path`), in Zones overview findings
  and export preflight, `blocks_export: false`.
- `ph_composer.spaces.create` result fields `accepted` and `left_out` (the preview's shapes), and `faces`
  on each Volume of `create` and `volumes.create`.
- Spaces `delete`, `remove`, `volumes.delete`, `volumes.remove` declare `target.foreign_records`.

Strict null identity and the Zone own-lock rule add no name: they make existing resolvers enforce the
documented contract (context/CONTRACTS.md, "Geometry records and occurrence references").

## C02 · Bounded discovery and guide

Keep existing MCP verbs and feature-neutral dispatch. Add bounded discovery sections for operations,
record kinds, reference targets, extension descriptors, library kind adapters, common refusal sets,
contract versions and task retention. A section cursor binds the installed registry/API identity;
session lists remain grant-filtered. Do not expose private handlers, provider credentials or addresses.

`describe` should reach a discovered descriptor. Extension payload schemas come from installed
declarations; unavailable namespaces report their preserved/unavailable status, not invented schema.
Library descriptors expose optional assignment schema/examples and unsupported assignment explicitly.
No participant becomes a directly callable external operation.

The operating guide is packaged with the build, versioned with its API, reachable through a small
topic read or proven MCP resource path, and linked from discovery/initialize. It is documentation,
not Model-provided instructions. Model names, notes and provider prose remain untrusted data.

**Bound at AW-02 (API 1.35).** No new MCP tool and no new registered operation. New names:

- `API.discover` key `library_kinds`: rows `name`, `owner`, `wire_kind`, `wire_version`, `record_kind`,
  `assignment_supported`. `API.describe` answers a library kind by its registered name
  (`Library::KindDescriptor.call`, `kind: "library_kind"`, with `wire_schema`, `copy` and `assignment`:
  `supported`, `target`, `examples`, `refuses`, or `supported: false` with `library.assignment_unavailable`)
  and an extension by namespace (`Records::Extension#descriptor`, `kind: "extension"`, with
  `payload_schema: null` and `statuses` from `Records::Extension::STATUS_MEANINGS`).
- `Declarations::LibraryCallback#examples`, optional, each checked against the callback's params at
  registration; the assign callback's targets are the published assignment examples.
- `Refusals::MEANINGS`: one line per code of every common set.
- MCP `discover` arguments `section` (`AgentAccess::Discovery::SECTIONS`: `operations`, `features`, `record_kinds`,
  `reference_targets`, `extensions`, `library_kinds`, `refusals`, `contracts`, `guide`), `topic`, `limit`,
  `cursor`; page keys `section`, `registry`, `rows`, `total`, `next_cursor`, `owner`; index keys `registry`,
  `sections`, `guide`, and `operation_counts` in place of `operations` past 20 KiB, then neither `features`
nor counts; a row's prose or list over 1 KiB is cut and named in the row's `truncated`, identifiers
(`Discovery::IDENTIFIERS`) never. A stale-registry cursor
  refuses `query.cursor_expired`; a foreign or edited one `params.invalid`.
- `AgentAccess::Guide` over `agent_access/guide.md` (the shipped copy of `docs/AGENT_GUIDE.md`): topic ids
  are slugged second-level headings and `<parent>.<child>` for third-level ones, plus `overview`;
  `initialize` `_meta["ph_composer/guide"]` gives `api`, `extension`, `digest`, `topics` and `read`.

## C03 · Complete retrieval under a transport budget

Every advertised agent read has a compact form whose **entire serialized result**, including
Outcome, cursor, totals, unreadable rows and diagnostics, fits the 24 KiB executor budget. Keep
headroom rather than spending every byte on rows. Preserve current whole panel queries and existing
callers; introduce additive projections or new compact/detail routes with explicit versioning.

A valid single object may be larger than a reply. Summary pages therefore cannot be its only
reader. Add owner-specific child pages (elements, install topology, run members, geometry rings,
restore offers, usage refs) and a narrow detail contract for arbitrary already-public metadata.
For one large scalar, allow revision-bound chunks with encoding/offset/total/digest sufficient for
exact reconstruction. The detail reader resolves only an authorized public projection, never an
arbitrary SketchUp dictionary or file path. Prefer a small shared paging/fragment helper, not a
new general query language.

Every enumeration exposes total and a continuation or an explicit unreadable/unsupported record;
no silent tail loss. Chunks from a changed source refuse rather than combine. Model cursors bind
session/query/filter/revision; catalog cursors also bind provider generation, and comparison reads
bind both; retained task detail binds the task/run/source snapshot. No read repairs data.

Compound previews also need a compact digest/summary and complete detail retrieval tied to the
same inputs/revision/proposal digest. Do not lose the digest to oversized affected/findings arrays
or imply that a user reviewed omitted destructive consequences. No transaction stays open while
detail is read; apply revalidates the original proposal as today.

**Bound at AW-04 (API 1.37), definition and metadata part.** Every new read is a query (capability `read`) that
changes nothing; AW-05 reuses the helper for occurrence data. New names:

- `Fragments` (`shell/fragments.rb`), the shared helper: `Fragments.read(request, query, value, revision:)` cuts the
  canonical JSON text of one value (`CanonicalJson`) into UTF-8 fragments, each at most `Fragments::MAX_TEXT_BYTES`
  (12 KiB) once escaped as a JSON string and never split inside a character, answering `fragment` (`encoding`
  `"json"`, `offset` and `bytes` in UTF-8 bytes, `total_bytes`, `sha256` of the whole text, `text`) and `next_cursor`
  through `Pages.token`, so a cursor binds session, query, filter and revision, carries the text's digest, and
  refuses `query.cursor_expired` after any change. `Fragments.summary(value)` gives `bytes` and `sha256`. `Pages::REPLY_BYTES` (24 KiB) is the one
  reply budget; `AgentAccess::Executor::MAX_RESULT_BYTES` is it.
- `ph_composer.records.list` pages by bytes (`Pages.bounded`, an unreadable row weighed too) and takes `metadata`:
  `full` (default, the rows as before) or `summary`, which leaves out `user_data`, `extension_data` and
  `extension_status` and adds `metadata` (`user_data`: `keys`, `bytes`, `sha256`; `extension_data`: `namespaces`,
  `bytes`, `sha256` and `statuses`, the count of envelopes per status) and `value_bytes` (each stored value's
  canonical size), so a summary row stays bounded however many keys or namespaces a record holds.
- `ph_composer.records.detail`: params `kind`, `id`, `path` (1 to 32 keys and indexes into the record's public view,
  starting at `values`, `user_data`, `extension_data` or `extension_status`), `cursor`. Result `kind`, `id`,
  `type` (JSON type), `fragment`, `next_cursor`; the path is not echoed, since a long key would crowd the reply. A path naming nothing refuses `target.not_found`, so an absent key
  differs from a stored `null` or `false`.
- `ph_composer.assemblies.assemblies.layers.list` (`assembly_id`) and `ph_composer.assemblies.assemblies.segments.list`
  (`assembly_id`, optional `layer_id`): one row per Layer (index, thickness, membrane, air-barrier face, segment count)
  or per Layer-Segment (Layer, index, stored segment, Material name, `flags` from `Thermal.segment_flags`). In every
  part row a name over `OccurrencePath::NAME_CHARACTERS` is cut and named in `truncated` (`element.name` for a Window
  element), and `records.detail` reads it whole.
- `ph_composer.windows.types.elements.list` (`type_id`): `type`, the Type's derived summary from the row
  `windows.types.list` builds (dimensions, `complete`, `copy_key`, `thermal` totals without `elements`, the findings
  with no element), and one row per stored element: `index`, `element`, its `thermal` result and `install_edges`
  (null for an empty element), `copy_slot` and its `findings`; the rows get the page budget the summary leaves.
- `ph_composer.assemblies.materials.uses.list` (`material_id`) and `ph_composer.windows.<collection>.uses.list`
  (`id`; `frames`, `glazings`, `psi_install_types`): the row's `uses` a page at a time, with `unreadable`, the
  count of owners (Assemblies or Window Types) that cannot be read.
- MCP `preview` over the reply budget answers the outcome with `value` null, `affected` and `findings` empty, and
  `detail` `parts` (`value`, `affected`, `findings`: `bytes`, `sha256`, `stable`, and `count` for a list; `stable` is
  false when a second run of the preview answered that part differently, as a create naming new ids does), keeping status,
  revision and `proposal_digest`. MCP `preview` with `part` (and `cursor`) calls `API.preview_part`, which reruns the
  preview and answers `part`, `proposal_digest` and that part's `fragment`; its cursor binds the action, params,
  part, revision and proposal digest. Nothing is retained or held open between fragments.

**Bound at AW-05 (API 1.38), occurrence, geometry and schedule part.** Every new read is a query (capability `read`)
that changes nothing; each pages through `Pages.bounded` bound to the revision, or answers fragments through
`Fragments`. Each existing whole read (`zones.all`, `units.all`, `glazed_area_by_face`, `assembly_usage`,
`adoption_preview`, `schedule.all`) is unchanged, and each new param is optional with the old behaviour as default.
New names:

- `Fragments.detail(request, query, view, path, parts:)`, `Fragments.at`, `Fragments.json_type`,
  `Fragments.path_param`, `Fragments::TYPE` (moved from `records.detail`, which now calls them):
  one value at a `path` into a public view, answered `type`, `fragment`, `next_cursor`.
  `RecordQueries.summarize(view, values)`: the `metadata` summary row, shared by `units.list`.
- `ph_composer.windows.units.list` params `fields` (`window_type_id`, `anchor`) and `metadata` (`full` | `summary`:
  no metadata maps, `metadata` and `value_bytes` as `records.list`, the native `name` cut at 256 and named in
  `truncated`); pages cut by size. `ph_composer.windows.units.detail` params `unit` (reference), `path` (from
  `name`, `values`, `user_data`, `extension_data`, `extension_status`, `host`, `findings`), `cursor`; result
  `unit_id`, `type`, `fragment`, `next_cursor`; the reference resolves as Unit actions resolve it.
- `ph_composer.windows.units.host_extent` param `geometry` (`full` | `summary`: `outline_points` and `hole_count`
  in place of `outline_m` and `holes`). `ph_composer.windows.units.host_extent.holes` (`host`): rows `index`,
  the bounding rectangle, `point_count`. `ph_composer.windows.units.host_extent.points` (`host`, optional `hole`):
  rows `index`, `x_m`, `y_m` of the outer loop or that hole.
- `ph_composer.windows.units.face_areas.list` (`zone_ids`, `zone_paths`): `glazed_area_by_face`'s Face rows in Zone
  and Face path order, with `unhosted_unit_total`. `ph_composer.windows.units.unhosted.list`: its
  `unhosted_units`.
- `ph_composer.windows.units.convert_review` param `compact`: groups without `sources` (`source_count`,
  `sources_digest`), left-out rows without `paths` (`path_count`, `first_path`).
  `ph_composer.windows.units.convert_review.detail` (`paths`, `path` from `groups` or `left_out`, `cursor`).
- `ph_composer.zones.list` param `overview` (`full` | `summary`: no `make_zone`, `restorable` or `findings`;
  `make_zone_entity_count`, `restorable_total`, `finding_total`).
  `ph_composer.zones.restorable.list`: offers by `zone_id` without `entity_ids` and `choice_record`, labels cut.
  `ph_composer.zones.restorable.detail` (`zone_id`, `path`, `cursor`). `ph_composer.zones.findings.list`.
  `ph_composer.zones.options.adoption_sources.list`: `required`, `suggested_segment`, sources by `key` with
  `cluster`, names cut; `ph_composer.zones.options.adoption_sources.detail` (`key`, `path`, `cursor`).
  `ph_composer.zones.faces.assembly_usage.list` (rows without `faces`) and
  `ph_composer.zones.faces.assembly_usage.faces` (`assembly_id`).
- `ph_composer.thermal_bridges.schedule.list` param `compact`: runs without `points_m` and `edge_paths`
  (`index`, `edge_count`, `point_count`, labels cut), findings without `locate` (`edge_count`, message cut at 512),
  totals without `by_type` (`type_count`), no `edge_findings` or `unreadable` (their totals stay).
  `ph_composer.thermal_bridges.schedule.by_type.list`. `ph_composer.thermal_bridges.runs.members.list`
  (`identifier`, optional `index` and `finding`; two runs sharing the identifier without `index` refuse
  `target.ambiguous`): rows `index`, `path`, `points_m` (the Edge's two world end points). `ph_composer.thermal_bridges.
  schedule.edge_findings.list` and `schedule.unreadable.list` (message cut at 512), by path.
- `ph_composer.spaces.detail` (exactly one of `space`, `volume`, `floor_segment`, then `path`, `cursor`): one part of
  the row `spaces.all` builds, a Floor Segment's with `loops_m`.

## C04 · Geometry candidate and assignment reads

Add a bounded read of native children at an explicit root/container path, carrying persistent path,
kind/name and registered ownership. Owner-specific candidate/detail reads return geometry in SI,
eligibility/refusal and complete occurrence references/expected values where authored data exists.
Use the same eligibility/resolution functions as the corresponding actions. Start with Make Zone,
first Space/Volume, thermal Edges and existing Window convert/restore input acquisition.

Candidate reads must not move selection/edit path, mint identities, unlock geometry or make a
definition independent. Hidden/locked/shared/foreign-owned cases are represented or explicitly
filtered by a declared option. World transforms apply exactly once. Large loops and topology use
C03 detail. Native shape creation and general transformations are excluded.

**Bound at AW-03 (API 1.36).** Six new queries, all reads (capability `read`); no new action. Every one takes an
explicit root-to-container `path` or explicit paths, pages by persistent id under `Pages::MAX_PAGE_BYTES`, binds its
cursor to the revision and its filter, and never moves the selection, the edit path or the camera, mints an id or
writes a dictionary. New names:

- `ph_composer.context.children` (foundation): params `path` (default `[]`, the root), `kinds` (subset of `group`,
  `component`, `face`, `edge`, `other`), `limit`, `cursor`. Result `container` (`path`, and `locked`, `hidden`,
  `shared` carried down the path), `children` (`path`, `persistent_id`, `kind`, `type`, `name`, `definition_name`,
  `hidden`, `locked`, `shared`, `solid`, `child_count`, `records`: `dictionary`, `key`, `claims`), `next_cursor`,
  `total`. A name over `OccurrencePath::NAME_CHARACTERS` (256) characters is cut and named in the row's `truncated`,
  here and in `zones.make_candidates`; in `edges.at` and `edges.candidates` the Zone's name, Building-Segment and
  Level are cut the same way and named `zone.name` and so on. A step that is missing or repeated refuses `target.not_found`; one that is not a Group or component
  `target.wrong_kind`. Filtering choice D11-a.
- `Records::EntityStore.records_on(entity)`: the registered stores marking one entity, by presence.
- `OccurrencePath.resolve(model, path)` (core): the read-only walk of a root-to-container path through Groups and
  components, with the root-composed transform and the carried lock, visibility and shared-storage flags.
- `Pages.bounded(..., prepare:)`: builds the sliced rows before the byte cut, so a page computes only its own rows.
- `ph_composer.zones.make_candidates`: params `parent_path` (default `[]`), `limit`, `cursor`. Rows: each Group
  directly in that context with `path`, `name`, `hidden`, `make_zone` (`parent_path`, `entity_ids`) and `refusal`
  (Make Zone's own check after its edit-path check, `Zones.make_refusal`, plus `ContextCommands.open_refusal` for a
  context that is not open); beside them `open_required`, `loose_faces` and `loose_edges`.
- `ph_composer.spaces.candidate_faces.list` param `context` (a root-to-container path), beside `space` and `volume`:
  Faces loose there, `candidate: "space"`, `operation: "ph_composer.spaces.create"`, the refusal Create Space gives
  that Face named alone with that context open (`CreateFaces.read` with `context:`).
- `ph_composer.thermal_bridges.edges.at`: params `paths` (1 to 250 root-to-Edge paths). `ph_composer.thermal_bridges.
  edges.candidates`: params `path`, `assigned` (`any`, `assigned`, `unassigned`), `limit`, `cursor`, the Edges
  directly in that container. Both answer `edges.selection`'s rows plus `endpoints_m`; a path that names no Edge reads
  `reason` `not_found` or `not_an_edge`.
- `ph_composer.windows.units.convert_candidates`: params `path`, `limit`, `cursor`: the rectangles (four square
  corners, no hole) loose in that container, each `path`, `outline_m`, `refusal` (Convert's own source read), for
  `units.convert_review`. `ph_composer.windows.units.restore_candidates`: params `path`, `limit`, `cursor`: one row per
  Window Type stamped on loose pane Faces there (`type_id`, `pane_paths`, `element_ids`), with `host` when exactly
  one Zone Face holds every pane on its plane and inside its outline and resolves for writing through
  `Placement::Hosts.writable`, as `units.restore` resolves it, else `host: null` and `needs`
  (`host` or `selection`, the latter when the panes of more than one Window of that Type are mixed).

## C05 · Library catalog and compound copy

Catalog summaries, normalized source snapshots, in-file comparisons and warnings/unavailable rows
have distinct bounded retrieval. Stable source identity, generation and existing copy choices stay
the authority. An atomic copy/assign publishes the adapter's target schema and examples, not an
untyped undocumented hash. Required generation remains required.

Export preview always offers a compact scope/count/projection digest/destination receipt. Omissions
are paged against that same projection. Selecting fewer records is not a recovery for an all-scope
export. A post-write hash/size/library identity receipt is optional; it must not widen file approval.
Load and export outcomes retain compact state/identity/counts even when detailed warnings or omissions
need a later page; completion must not be inferable only from a generic omitted-value message.

**Bound at AW-06 (API 1.39).** Every new read is a query (capability `read`) that changes nothing. Each existing
whole reply is unchanged; `compact` (boolean, default false) is the one opt-in param of this stage (D14-a). New names:

- `compact` on `ph_composer.library.load`, `library.catalog`, `library.in_file`: the catalog summary leaves out
  `warnings` and `unavailable` and gives `warning_total` and `unavailable_total`; a compact catalog row leaves out
  `snapshot` and gives `snapshot_summary` (`bytes`, `sha256` of its canonical JSON, `Fragments.summary`), with
  `display_label` and `library_name` cut at `OccurrencePath::NAME_CHARACTERS` and named in `truncated`; a compact
  `in_file` candidate leaves out `differences` and `expected_values` and gives `difference_fields` (the field names)
  and `expected_values_summary`, its label cut the same way, and a compact resolution lists the first candidates, at
  most 20 and within 8 KiB, beside `candidate_total`. `catalog` and `in_file` pages are now cut by size
  (`Pages.bounded`) in both forms.
- `ph_composer.library.warnings.list` and `ph_composer.library.unavailable.list` (`provider_id`, `kind`, optional
  `generation`, `limit`, `cursor`): a catalog's notes in order, `total`, cursor bound to the generation.
- `ph_composer.library.catalog.detail` (`provider_id`, `kind`, optional `generation`, `library_id`, `record_id`,
  `path` from `snapshot`, `display_label` or `library_name`, `cursor`): result `generation`, `type`, `fragment`,
  `next_cursor`, through `Fragments.detail`, bound to the generation. `ph_composer.library.in_file.detail`: the same
  params with `path` also from `resolution`, the row `in_file` builds, bound to the generation and the Model revision.
  A row named by no or two rows refuses `library.row_unavailable`, as copy does.
- `export_preview` answers `scope` in both forms. `compact` on `ph_composer.library.export_preview`: `omissions`
  left out, `omission_total` given beside `kinds`, `scope`, `projection_digest`, `revision` and `destination`. `ph_composer.library.export_preview.omissions`
  (`scope`, `kinds`, `records`, optional `projection_digest`, `limit`, `cursor`): the projection's omission rows,
  `total`, `projection_digest`, `revision`, cursor bound to the Model revision and the projection digest; a
  `projection_digest` that is not the current projection's refuses `revision.stale`.
- `compact` on `ph_composer.library.export_file`: `omissions` left out, `omission_total`, `projection_digest` and
  `revision` given, `library_name` cut at 256 characters and named in `truncated`. Both forms add `destination_state`, the SHA-256 the destination holds after the write, which
  `export_preview` with the location reports as `destination.state`.

R15 adds no name: AW-02's descriptor already publishes each adapter's `assignment.target` and examples from its
own callback. The Psi target stays one object schema (`core/json_schema.rb` has no `oneOf`), its two shapes given
by the two examples and the schema's `description` (D14-b).

## C06 · QA and retained outcomes

Separate compact readiness/counts/destination from finding and repair detail. Filtering by owner,
code/severity/target must not change the explicitly declared scope of totals. Reuse contributor
semantics; a common paginator can project existing outputs without moving domain rules into MCP.

Retained task findings and generated report content are retrieved for the caller's exact run,
including blocked/failed runs with no file. An early failure that generated no report says so.
Every compact receipt names its task/run and captured source identity; this is required independently
of the optional start precondition. Keep existing owner, revocation, close/restart and retention
rules. Polling stays compact. Failure-detail retrieval must not rerun export or replace the original
evidence with current-model findings. Share known cheap preflight/extraction validation while stating
which translation checks necessarily run later.

An optional expected revision on start preserves latest-state behavior when omitted. When supplied,
refuse stale input before filesystem recovery or writes. Preserve the existing navigation-versus-content
distinction. Retrieval of generated diagnostic report content is required; portable retrieval of the
written artifact file bytes in C08 is a separate optional capability.

**Bound at AW-07 (API 1.40).** No new MCP tool and no new foundation code beyond `task.running`. Each new param is
optional and the whole reply stays the default (D15-a). New names:

- `export_preflight` (API, MCP tool) params `compact`, `part` (`findings` | `repairs`), `owner`, `codes`,
  `blocks_export`, `object_id`, `row`, `limit`, `cursor`. `compact` answers `ready`, `totals` (`findings`, `blocking`,
  `warnings`, `repairs`), `by_owner` (`owner`, `findings`, `blocking`, `repairs`), `by_code` (`code`, `owner`,
  `findings`, `blocking`) and `destination`, in place of `findings` and `repairs`. `part` answers one page of that list
  (`Export::DiagnosticPages`), each row with its `row` key (`[contributor place, index]`) and `owner`, a `message`
  over 512 characters cut, a `locate` or repair `params` over 1 KiB given as `locate_summary` or `params_summary`
  (`Fragments.summary`), each cut named in `truncated`; beside them `total` (rows matching the filter) and
  `unfiltered_total` (the part's rows), the cursor bound to the Model revision. `part` with `row` answers that whole
  row's canonical JSON in `fragment`s.
- `export_status` params `compact`, `part` (`findings` | `report` | `result`), `codes`, `blocks_export`, `object_id`,
  `row`, `limit`, `cursor`; `latest_export` param `compact`. Every task snapshot adds `source` (`revision`,
  `export_generation`, captured at start) and `diagnostics` (null until the task ends: `findings`, `blocking`,
  `report` and `result` as `Fragments.summary` or null, `report_absent` null or why: `no_translation`,
  `not_rendered`). `compact` leaves `outcome.findings`, `outcome.value.result` and `outcome.value.report_html` out.
  `part` reads what the task retained when it ended (`Export::Task#diagnostic`), never the Model: `findings` pages
  as the preflight part does, `report` (the generated report HTML, of a written or a blocked run) and `result` (the
  compact translation result) answer `fragment`s; the cursor binds the task, not the Model revision. A part of a task
  that has not ended refuses `task.running`; `task.expired` and `task.foreign` stay as they were.
- `AgentAccess::Executor` keeps `source` and `diagnostics` in an export receipt trimmed to the reply budget.
- `Export::MetadataCheck.problems` (the metadata rules `Export::RecordReader` applies, shared) and
  `Export::MetadataCheck.findings`: every metadata blocker of the records a contributor's preflight names, as
  blocking preflight rows with the codes extraction raises (`export.blocked` for a reserved `user_data` key,
  `extension.unavailable`, `extension.invalid`, `extension.schema_unsupported`, `export.relevance_unknown`).

## C07 · Explicit damaged-assignment repair

Ordinary assign/clear stays strict. A dedicated repair names an Edge's native occurrence path,
expected Model revision and opaque fingerprint of the damaged or stranded assignment. Preview
explains what data is discarded. Apply checks writable storage and identity/reference consequences,
removes only this owner's assignment and uses one restorable native operation. A changed payload,
wrong/shared/locked target or unreviewed scope refuses before mutation. Never accept arbitrary
dictionary names, arbitrary eval or unbounded destructive cleanup.

**Bound at AW-07 (API 1.40).** New names:

- `ph_composer.thermal_bridges.edges.repair_candidates` (query, `read`): params `limit`, `cursor`. One row per Edge
  whose stored assignment ordinary clear cannot reach: `path` (root to Edge), `condition` (`unreadable`, not valid
  JSON; `stranded`, readable but held by no Zone), `containment` (why no Zone holds it, as `zones.containment`
  reads it, or null), `fingerprint` (SHA-256 of the stored text), `bytes`, `record` (`id`,
  `thermal_bridge_type_id`, `quantity` when readable, else null), `write_refusal` (`target.locked` or
  `target.shared_definition` from the path, or null). Pages by path, bound to the revision.
- `ph_composer.thermal_bridges.edges.repair` (action, `model_write`): params `path`, `fingerprint`. Removes that one
  Edge's `ph_composer.thermal_bridge` record and nothing else, as one Undo step. Result `path`, `condition`,
  `containment`, `stored` (`bytes`, `sha256`, `readable`, `valid`, `excerpt` cut at 256 characters), `discarded`
  (`id`, `thermal_bridge_type_id`, `quantity`, `user_data_keys`, `extension_namespaces`, or null for unreadable
  text). Refuses `target.not_found`, `target.wrong_kind`, `target.locked`, `target.shared_definition`,
  `target.changed` (other stored text), `reference.in_use`, and `thermal_bridge.repair_not_needed` for a readable
  record a Zone holds, which `edges.clear` serves. Apply re-reads the text and refuses `target.changed` before
  writing.
- The unreadable preflight row, the `thermal_bridge.outside_zone` finding and the Type delete's stranded route name
  `edges.repair_candidates` and `edges.repair`.

## C08 · Client and host cooperation

A saved connection profile identifies client, endpoint, credential binding and Model/grants without
returning the secret. Connecting a second profile does not silently replace the first. Config edits
preserve unrelated bytes/settings, check for concurrent changes and offer a manual route when the
format is unrecognized. Reconnect may reuse only a still-live credential the app already stores.

Configured, contacted and verified are distinct states. Verify with harmless discovery/context,
not a test mutation. Host-gesture readiness is defined from AW-09 measurements before implementing
a guard. A refusal never stops a person's tool or steals focus. Existing stale/replay behavior stays.

Optional artifact retrieval is caller/run-scoped and bounded, hashes the original content, and
observes expiry/revocation. Optional history returns operation, affected refs, source/result revisions
and outcome identity, never full params/secrets or another Model's events. Overlay capture must
declare its actual content and provenance; inability is an explicit result, not an old image.
