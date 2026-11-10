# Proposed contract changes

STATUS: C01 bound and implemented by AW-01 (API 1.34); C02 bound and implemented on the AW-02 branch (API 1.35); C03-C08 remain proposals. Baseline API 1.31.
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
- MCP `discover` arguments `section` (`AgentAccess::Discovery::SECTIONS`: `operations`, `record_kinds`,
  `reference_targets`, `extensions`, `library_kinds`, `refusals`, `contracts`, `guide`), `topic`, `limit`,
  `cursor`; page keys `section`, `registry`, `rows`, `total`, `next_cursor`, `owner`; index keys `registry`,
  `sections`, `guide`, and `operation_counts` in place of `operations` past 20 KiB. A stale-registry cursor
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

## C07 · Explicit damaged-assignment repair

Ordinary assign/clear stays strict. A dedicated repair names an Edge's native occurrence path,
expected Model revision and opaque fingerprint of the damaged or stranded assignment. Preview
explains what data is discarded. Apply checks writable storage and identity/reference consequences,
removes only this owner's assignment and uses one restorable native operation. A changed payload,
wrong/shared/locked target or unreviewed scope refuses before mutation. Never accept arbitrary
dictionary names, arbitrary eval or unbounded destructive cleanup.

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
