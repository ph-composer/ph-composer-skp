# Consistent entity user data

DATE: 2026-11-14
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Codex
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

## Problem and intended outcome

A user writing a small script should be able to attach a review status, specification reference,
external identifier or other JSON data to any authored entity, then edit, copy and save the model
without losing that data. They should not have to register an extension, modify core schemas or
write SketchUp dictionaries directly.

PH-Composer already has `user_data` and a separate structured `extension_data` contract. The
remaining problem is consistent coverage and a clear entry point. Storage support alone is not
enough: the user must be able to discover, read and update the data through supported operations.
An existing entity must not be excluded merely because its feature uses a different store or
keeps it inside another record.

Ed confirmed two requirements on 2026-11-14:

1. Apply the same affordance across all entities, with no unaccounted-for gaps.
2. Document and demonstrate the pattern clearly in user documentation and engineering context.

This PRD records those requirements. It does not authorize implementation or prescribe a new
generic metadata service. The [status](STATUS.md) owns progress.

## Current evidence

Reviewed against `main` at `186734ce` on 2026-11-14. These are starting observations, not a
completed inventory or acceptance of this feature.

| Area | Observed behavior | Owning source |
| --- | --- | --- |
| Record foundation | Optional mapping, plain JSON validation, detached reads, whole-map replacement and recursive copy preservation already exist | [RecordKind](../../../../src/ph_composer/core/records/record_kind.rb), [Engine](../../../../src/ph_composer/core/records/engine.rb), [Metadata](../../../../src/ph_composer/core/records/metadata.rb) |
| Model-owned definitions | Materials, Assemblies, window products and Types, Attached zones and Thermal Bridge Types use the shared record system; audit every public route rather than infer coverage from storage | [Feature registration](../../../../src/ph_composer/features), [definition pattern](../../../../context/TECH_STACK.md#a-definition-record-end-to-end) |
| Zones, Faces and Window Units | Owner metadata actions already exist, with expected metadata and transactional batches | [Entity metadata tests](../../../../tests/entity_metadata_test.rb) |
| Spaces, Volumes and Floor Segments | Shared metadata rules and a public metadata action already exist | [Spaces authoring](../../../../src/ph_composer/features/spaces/authoring.rb), [schema](../../../../src/ph_composer/features/spaces/schema.rb) |
| Thermal Bridge Edge assignments | Records accept metadata and reassignment preserves it; normal public reads omit the maps and there is no equivalent metadata update action | [Assignment declarations](../../../../src/ph_composer/features/thermal_bridges/declarations/assignment.rb), [operations](../../../../src/ph_composer/features/thermal_bridges/assignment/operations.rb) |
| Building Segments and Levels | Create accepts `user_data`, reads expose it, but the existing-option update does not accept it | [Option commands](../../../../src/ph_composer/features/zones/options/commands.rb) |
| Assembly Layers and Layer-Segments | Authored nested objects with identities; their closed schemas have no `user_data` | [Assembly schema](../../../../src/ph_composer/features/assemblies/assembly/schema.rb) |
| Window Elements | Authored nested objects with identities; their closed schema has no `user_data` | [Window Type schema](../../../../src/ph_composer/features/windows/types/schema.rb) |
| Model root and logical entities | Model-level settings are not a universal Model metadata API. A Space Floor has an identity on its Volume but no independent stored record. Both need an explicit ownership decision | [ModelSettings](../../../../src/ph_composer/core/model_settings.rb), [Spaces schema](../../../../src/ph_composer/features/spaces/schema.rb), [terminology](../../../../context/UBIQUITOUS_LANGUAGE.md) |
| HBJSON | Pass-through exists for Zones, Faces, Window Units, Assemblies, Spaces, Volumes and Floor Segments; other data may remain local with a finding | [Export guide](../../../../docs/AGENT_GUIDE.md#export), [record reader](../../../../src/ph_composer/export/record_reader.rb) |
| Library interchange | Built-in wire schemas omit local metadata. Export reports omissions; admission trims undeclared fields. Updating an existing local definition preserves its local metadata | [File format](../../../../docs/LIBRARY_FILE_FORMAT.md), [export projection](../../../../src/ph_composer/library/export_projection.rb), [admission](../../../../src/ph_composer/library/library_file.rb), [replacement tests](../../../../tests/library_coordinator_test.rb) |

The initial review ran 276 focused Ruby tests (2,665 assertions) and 52 Python tests successfully,
including metadata edits, supported copies and reloaded Honeybee objects. These checks establish
the existing behavior only. No new native SketchUp acceptance was run for this packet.

## Entity scope and completeness

The inventory must cover the authored Model root, every definition, geometry-owned record,
assignment, managed option and nested authored part. Include the kinds above and anything found
by tracing composition, record registrations, reference targets, entity stores, nested schemas
and public operations. Do not treat registered record kinds as the whole inventory.

For each entity kind record:

- Its owner, durable identity or parent-qualified address, and authoritative storage.
- The public read and metadata-write route, including creation and an already-existing entity.
- Edit, duplication, split, merge, conversion, rehosting, recovery and deletion behavior, wherever
  those operations apply.
- Undo/Redo and save/reopen coverage, plus supported cross-Model copy/adoption behavior.
- HBJSON and library mapping or an explicit omission/unsupported-format rule.
- Concrete tests and native evidence; use `not applicable` only with a reason.

Include Model metadata in the target scope without creating a second source of building data.
Decide the storage and addressing of a logical Space Floor explicitly; its identity is not a
reason to silently alias its metadata to the Volume's mapping.

Derived schedules, calculated thermal-bridge runs, generated geometry, caches, transport
envelopes and internal recovery/settings records are not automatically independent authored
entities. List relevant cases and explain their owner or exclusion. Recovery records must still
carry the authored metadata their documented recovery operation promises. Reclassification must
not be used to avoid supporting a user-authored entity.

Future feature contributions must apply the same contract to new entities, including mechanical
and climate entities when those features are implemented. This packet does not implement those
features. Their eventual acceptance must include metadata coverage.

## Required behavior

### A simple mapping without extension registration

Every in-scope entity exposes an optional string-keyed JSON object named `user_data`. Nested
objects and arrays, strings, finite numbers, booleans and JSON null are supported. Invalid JSON
values, cycles and non-string keys are refused before any write. A missing legacy mapping reads
as empty without writing or repairing the model.

Recommend a contributor-owned top-level key, such as:

```json
{"user_data": {"example_org": {"review_status": "needs_site_check", "detail": "A-503/7"}}}
```

The key requires no registration. Core calculations do not interpret this data. Keep
`extension_data` as the existing optional route for typed payloads, migrations and declared
references; using `user_data` must not require learning that machinery.

### Public reads and writes

Users must be able to discover, read, set, replace and clear the mapping on existing entities
through the supported Ruby API and its existing client adapters. Nested parts are addressed by
their identity within their owner, not an array index that changes on reorder.

Reuse the current whole-map replacement rule: omitting the map leaves it unchanged, `{}` clears
it, and sending a map replaces it. A script reads the current map, changes its own namespace,
then submits the complete map. Do not introduce an implicit recursive merge or silently erase
other namespaces. Reads and submitted values remain detached from persisted state.

Keep writes within the owner's operation and validation rules. Provide revision/preimage guards,
respect locked or shared storage, preserve active edit paths, and make a batch atomic. A stale,
invalid or unavailable target writes nothing; a no-op creates no Undo step. Prefer existing
helpers and owner operations over a second write path. Existing public operations and metadata
clients remain compatible.

### Lifecycle and compatibility

Ordinary domain edits and UI saves preserve unrelated metadata at every depth. This includes
editors that rebuild an Assembly's layers or a Window Type's elements, reference retargeting,
library replacement and feature-specific normalization. A new nested field is not complete if
an existing edit path reconstructs the object and drops it.

Supported duplication produces independent deep copies. Do not infer references from strings
inside `user_data`, remap an external identifier, or change a kind's existing identity/shared
definition rules. Parent duplication must preserve each nested part's mapping while allocating
new identities according to the owning feature's contract.

Define split and merge behavior before implementing it. A split needs an explicit metadata
inheritance rule. Combining entities with different mappings must not silently choose one or
invent a merge of arbitrary data. A conversion, replacement or recovery that cannot preserve
all data must disclose its limit and offer the existing cancellation/Undo route as applicable.
Deletion removes the metadata with its entity and Undo restores it.

Save/reopen and supported native copy/adoption paths preserve the JSON value, including Unicode,
null, false, zero and empty containers. Keep unavailable structured extension payloads intact.
Older SKPs remain readable without eager rewrites. Assess schema versions and older-build
behavior for newly supported nested data; do not assume additive fields are compatible with
closed schemas.

### Serialization and export

Local persistence and interchange are separate contracts. Every inventory row must state its
behavior at each supported boundary; no row may inherit an accidental omission.

Preserve the established HBJSON pass-through and reserved namespace/privacy checks. Where an
authored entity has its own supported destination object, the target is to carry its mapping
with that object. Where translation combines several entities or produces several objects,
specify the mapping and collision policy first. Do not arbitrarily promote one Edge's metadata
to an aggregated thermal-bridge run or overwrite Unit metadata with Window Element metadata.

Library files are currently intentionally lossy for metadata. Evaluate a compatible,
versioned `user_data` round trip for every supported library kind as part of this feature's
format decision. Record the recommendation and consumer/version implications before changing
the wire format. If a boundary remains lossy, name it in the guide and return an actionable
omission finding. This is not an exception to local entity support, and it cannot be advertised
as lossless serialization. Do not add export support to downstream formats that cannot carry
the data or weaken the existing artifact checks.

## Documentation deliverables

Documentation is part of acceptance, with examples checked against the actual public API.

| Surface | Required change |
| --- | --- |
| [API quickstart](../../../../docs/API_QUICKSTART.md) and a short user-data guide if needed | A beginner recipe on an existing Face or Material: discover/read, change one namespace, guarded write, read back, clear; explain detached views and whole-map replacement. No custom feature registration or raw dictionary writes |
| [Documentation index](../../../../docs/.index.md) | An obvious route to the recipe and its coverage/export table |
| [Agent guide](../../../../docs/AGENT_GUIDE.md) and generated [API reference](../../../../docs/API_REFERENCE.md) | Actual operation names, nested addressing, guards, large-map reads, examples and honest export limits; regenerate from declarations rather than hand-edit generated schemas |
| [Contributor architecture](../../../../context/EXTENSIBILITY.md#metadata-and-structured-extension-data) | Universal entity requirement, small-script entry point, distinction from structured extension data, and an obligation for new contributions |
| [Core contracts](../../../../context/CONTRACTS.md#records-and-extension-data) | One owner for value shape, replacement, copy, lifecycle and compatibility rules; explicit nested/root ownership and split/merge behavior |
| [Technical architecture](../../../../context/TECH_STACK.md), [terminology](../../../../context/UBIQUITOUS_LANGUAGE.md) and [context index](../../../../context/.index.md) | Storage/export ownership and links only where affected; name authored versus derived objects consistently |
| [Library format](../../../../docs/LIBRARY_FILE_FORMAT.md) and export documentation | Exact preserved/omitted fields and applicable versions after the format decision |
| [Foundation example](../../../../tools/examples/foundation/README.md) | Link to the small recipe; keep the maintained-extension example as the next step |

Publish an entity coverage table with the supported operations and interchange behavior. Until
the work lands, describe the current gaps honestly rather than presenting this PRD as an
available capability. Avoid duplicating the full contract in every guide.

## Design decisions to settle during implementation planning

The universal local affordance and documentation requirements are confirmed. These remaining
choices do not block writing this feature packet:

| Decision | Direction to evaluate |
| --- | --- |
| Model root and logical Space Floor ownership | Define one authoritative mapping and stable public address for each; reuse the existing storage/operation mechanisms where adequate |
| Nested editing and schema compatibility | Extend the owner contract and preserve old records; determine version behavior before changing closed schemas or editors |
| Split, merge and conversion | Adopt consistent preservation rules that respect existing identity behavior; resolve conflicting mappings explicitly |
| New HBJSON mappings and nested/placed collisions | Trace real destination objects and choose mapping rules without conflating definition and occurrence metadata |
| Library interchange | Prefer a versioned optional mapping if consumers can preserve it; otherwise seek an explicit boundary decision and document omissions |

Make routine API and storage choices within these requirements when implementation planning is
authorized. Any proposal to exclude an authored entity or narrow the confirmed affordance needs
Ed's decision. Detailed stage/PR sequencing belongs in a later plan.

## Acceptance

| ID | Required evidence |
| --- | --- |
| UD-01 | A complete inventory reconciles domain terms, registrations, entity stores and nested schemas. Every authored entity has an owner, address, read/write route and lifecycle/interchange disposition; exclusions have reasons |
| UD-02 | Public API examples work for a definition, geometry entity, assignment, option, nested part and Model root, with panel closed and no raw storage access or extension registration |
| UD-03 | Across all in-scope kinds, round trips preserve nested JSON, Unicode, null, false, zero and empty containers; missing legacy mappings remain valid and reads cause no write |
| UD-04 | Invalid input, stale reads, locked/shared targets, conflicting batches and no-op writes follow existing refusal/transaction rules; failure leaves every target unchanged |
| UD-05 | Ordinary edits, UI saves, reorder, retargeting and library replacement retain metadata at every authored depth. Tests exercise real rebuild/normalization paths |
| UD-06 | Duplication and supported split/merge/conversion paths meet the chosen policy; metadata copies are independent and literal identifiers are not remapped. Parent and occurrence behavior remains correct |
| UD-07 | Native SketchUp evidence covers affected storage/lifecycle boundaries: one-step Undo/Redo, save and fresh-process reopen, copy/paste and applicable adoption/repair. Synthetic fixtures only; stub tests do not substitute |
| UD-08 | Actual serialized/reloaded HBJSON preserves every promised mapping. Aggregate and collision cases follow the decided rule. Library round trips or explicit omissions match the versioned contract, with existing artifact guards intact |
| UD-09 | The small scripting recipe and contributor example run against supported operations; documentation/context/indexes agree with the final inventory and operation discovery |
| UD-10 | Focused tests, coherent architecture/Ruby review and repository-required final gates pass, including `make ci`; refresh generated API artifacts and runtime manifests when affected. No gap is marked accepted without its evidence |

Use shared contract tests where they exercise meaningful behavior, plus owner-specific tests for
copy, rebuild, geometry and serialization boundaries. Do not create a second test framework or
one test per trivial accessor. Reuse applicable native evidence only after checking source and
fixture relevance; record tested hosts separately from platform-support claims.

## Non-goals

A general metadata editing UI, a new plugin loader, arbitrary Ruby/Python objects in metadata,
automatic interpretation as calculation inputs, implicit reference discovery, and implementation
of future mechanical or climate features are outside this packet. Structured extension data
retains its existing contract. No new downstream certification or format-support claim is made.

## Prior art

The initiating example is Honeybee's optional per-object dictionary and its copy/serialization
behavior: [_Base](https://github.com/ladybug-tools/honeybee-core/blob/0bfdfc26d01fc1a1f42c32661dfe7fedc414900c/honeybee/_base.py)
and [Aperture](https://github.com/ladybug-tools/honeybee-core/blob/0bfdfc26d01fc1a1f42c32661dfe7fedc414900c/honeybee/aperture.py).
PH-Composer keeps its existing deep-copy and transactional-write guarantees.
