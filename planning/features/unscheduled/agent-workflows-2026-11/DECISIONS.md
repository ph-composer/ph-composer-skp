# Decisions for implementation intake

STATUS: D01-D10 recommended defaults accepted 2026-11-10 under the implementation go; AW-01 to AW-07 choices recorded below.
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication

| ID | Question | Recommendation and scope |
| --- | --- | --- |
| D01 | Replace the connection architecture? | No. Keep registered Ruby operations and the local MCP verb adapter. Fix coverage and retrievability in their owners |
| D02 | How many configured connections per client? | Support named profiles and an explicit default, preserving the current entry as a migrated default. Show replacement before changing an existing binding. Choose exact UX before AW-08 writes config; no credential redisplay |
| D03 | Enlarge reply limits to fix failed reads? | No. Retain the measured 24 KiB ceiling; add compact summaries and exact detail retrieval. Measure client versions before changing the ceiling |
| D04 | How to deliver the guide? | Start with a bounded topic read using the existing tool flow. Use MCP resources only if both selected clients retrieve them reliably. One source of guide content |
| D05 | Draw arbitrary geometry? | Exclude from these implementation stages. Add candidate/geometry reads now. Later, separately select a small concrete CAD job such as floor-polygon creation or a Zone shell; no universal eval or transform API by inference |
| D06 | Partial candidate creation? | Preserve reviewed UI filtering, but always report accepted/left-out paths and created grouping; bind the accepted set to apply. Coordinate SUI-05. A strict mode may be additive, not a silent compatibility change |
| D07 | Full overlay capture and portable artifact bytes? | Artifact bytes are an optional bounded addition after exact QA retrieval. Overlay capture is an experiment first; retain geometry-only capture and explicit limits if unsupported |
| D08 | History and gesture interlocks? | Measure gestures first. Add the smallest guard justified by evidence. Optional bounded per-caller/session operation history; no conversation store or whole-model lock |
| D09 | Export exactly the reviewed state? | Add optional expected revision, preserving current behavior when absent. Choose this slice at AW-07 intake; do not represent it as an existing guarantee |
| D10 | New hosted/browser/Windows connection support? | Outside the default scope. Keep documented manual local protocol; Windows belongs to its existing platform packet. A remote/browser transport changes the security boundary and needs a separate decision |

## Accepted at intake, 2026-11-10

Ed's go (quoted in STATUS) accepts the D01-D10 recommended defaults above. Optional slices R14/A14
(AW-09 artifact/history routes) and R16/A16 (AW-07 expected export revision) are deferred by
default: each stage records them as "deferred, optional" unless its plan makes them required.

AW-01 choices, recorded before code:

| ID | Choice |
| --- | --- |
| D01-a | Descendant rule: Make Zone refuses a selection, or a Group in it, holding a claimed entity at any depth, through Group and component contents (`target.wrong_hierarchy`); a directly claimed entity or open context keeps `target.wrong_kind`. Restore regroups stamped Faces only, so it meets the direct rule; `MakeZoneStep` repeats the check at apply for both routes. Non-claiming records (Zone Face, thermal-bridge Edge, Window Unit) never block, so ordinary Face/Edge assignments are untouched. A Space inside a Zone Group from before W6-2 stays a readable legacy state |
| D01-b | Legacy overlap: a Zone record on, or inside, a claimed Group reads `zone.ownership_conflict` in `zones.list`/`zones.all` findings and export preflight, as a warning (`blocks_export: false`): export of the same Faces already works for the pre-W6-2 nested case, and blocking would strand existing Models. No automatic repair; the recovery is the user's choice (Undo, or the owning feature's own action once the foreign data is removed). A dedicated overlap repair is not in AW-01 |
| D01-c | Destructive guard: Spaces `delete`, `remove`, `volumes.delete` and `volumes.remove` refuse `target.foreign_records` while another store's record sits on the Group or below it, read by presence through every registered `EntityStore` rather than the reference-target inventories, which leave stranded records (a Zone on a component) out. Explode operations use the same at-or-below rule as erase, because exploding changes every descendant path other references use. Planned at proposal time only: every invoke re-plans, so steps need no engine access. A thermal-bridge tag stranded on an Edge outside every Zone cannot be cleared by its feature today; that is AW-07's outside-Zone repair (R10), now `ph_composer.thermal_bridges.edges.repair` (D15-d) |
| D03-a | A Zone's own lock is checked by `Occurrences.resolve_editable_zone`, which `zones.update`, `update_field`, `update_metadata` and `UpdateZoneStep` apply share; Face writes already refused it. `writable_zone!` is unchanged, so export preflight does not newly block a locked Zone. Split identity repair's own Face writes through `face_at` do not check the Zone's own lock: a follow-up outside AW-01 |
| D06-a | Space create receipt adds `accepted`, `left_out` and per-Volume `faces`. The reviewed-set precondition is the existing `expected_revision` (and `proposal_digest` from an action preview); no digest parameter and no strict all-or-nothing mode are added |

AW-02 choices, recorded before the gate:

| ID | Choice |
| --- | --- |
| D04-a | The guide is a bounded topic read through the existing `discover` tool (`section: "guide"`, `topic`), not a new tool verb and not MCP resources, which stay empty; one source, `docs/AGENT_GUIDE.md`, shipped as a fixture-checked copy. Whether both fresh clients find and use it unprompted is AW-10's client evidence |
| D03-b | Discovery pages are cut at the shared 16 KiB row budget (`Pages::MAX_PAGE_BYTES`) under the unchanged 24 KiB reply limit. The legacy `owner` page stays unpaged for existing callers; `section: "operations"` with `owner` is the paged route |
| D01-d | Foundation codes keep a null `description` in `describe`'s `refuses`; their meanings are published once, in the `refusals` section, so the existing contract does not change |

AW-03 choices, recorded before code:

| ID | Choice |
| --- | --- |
| D11-a | Inventory filtering: `context.children` lists every direct child whatever its state and filters only by `kinds`. Each row says `hidden` (its own flag or a hidden tag), `locked`, `shared` (component storage, or a Group whose definition another Group shares), `solid` and the registered `records` on it; `container` carries the same flags down the path. Hidden, locked, shared and foreign-owned objects are represented, never dropped, so a total never depends on view state |
| D11-b | Candidate refusals are what the owning action gives the candidate named alone, read through the action's own check with the candidate's context in place of the open one. A candidate at a context that is not open is not refused for that: the row says the edit path must be opened first (`open_required`, or `requires`), which `context.open` does |
| D11-c | Height from solid has no owner proof linking a solid to a Volume, so acquisition is `context.children` (`solid`, `records`) and the existing `volumes.height_from_solid_preview`, which refuses a non-solid; no new Spaces read. A Window restore host is given only when geometry proves one writable Zone Face; otherwise the row says what the user must choose |

AW-04 choices, recorded before the gate:

| ID | Choice |
| --- | --- |
| D12-a | `records.list` keeps the stored maps by default, so existing callers read what they did; the compact form is opt-in (`metadata: "summary"`). Its pages are now cut by size as every other list is, which only moves where `next_cursor` falls |
| D12-b | Exact detail is the value's canonical JSON as text fragments cut at UTF-8 character boundaries, offsets in bytes, with the whole text's size and SHA-256: an agent reads the text directly, which base64 would prevent, and a byte cut never splits a character. Fragments are at most 12 KiB escaped, leaving the 24 KiB reply room for its envelope |
| D12-c | Preview detail is stateless: `preview` with `part` runs the preview again and binds its cursor to the revision and the proposal digest; nothing is retained. Compaction applies only to a budgeted caller (`within`, the agent `preview`); the panel's preview is unchanged. A fragment of a changed preview refuses `query.cursor_expired`, documented on the tool and in the guide, not in each action's `refuses`, since only the fragment read answers it. A fragment cursor also carries the text's digest, so a preview that mints fresh ids on each run (a create) refuses its second fragment rather than joining two runs; such a part is readable only while it fits one fragment, and the compact form runs the preview a second time to mark it `stable: false`, since no later read can match its digest. Deterministic preview ids for catalog creates are a follow-up outside AW-04 |
| D12-d | Part reads exist where a valid record outgrows a reply: Assembly Layers and Layer-Segments, Window Type elements, Material and Window product uses. A Thermal Bridge Type row carries no unbounded array, so it gets none |
| D13-a | AW-05's compact forms are opt-in params (`metadata`, `geometry`, `overview`, `compact`) with today's whole reply as the default, as D12-a chose for `records.list`; the panel and `.all` reads are unchanged. `schedule.list` without `compact` still carries the first 50 Edge findings and unreadable assignments, as it documents, because the paged reads are now the complete route; each of those unreadable messages is cut at 512 characters, as `records.list` cuts its own |
| D13-b | Detail of a computed result (a Unit row, a restore offer, a convert review, a Spaces row) is a fragment read of the same row the list builds, by a path into it, through the one `Fragments.detail`; repeated geometry and collections (holes, loop points, run members, Faces, offers, findings, adoption sources) page as rows instead, since an agent reads rows one page at a time. A convert group's sources are fragments, not rows, because they are one reviewed value whose digest is its handle |
| D13-c | A Thermal Bridge run is named in `runs.members.list` by its derived `identifier`, valid only at the revision it was read; raw assignment identity stays AW-03's Edge reads. A convert group's `sources_digest` is the SHA-256 of its sources as `convert_review.detail` answers them, so it is a handle on what was reviewed while `units.convert` still takes the whole group |

AW-06 choices, recorded before the gate:

| ID | Choice |
| --- | --- |
| D14-a | One opt-in param, `compact` (boolean), on `library.load`, `catalog`, `in_file`, `export_preview` and `export_file`, the whole reply the default as D12-a and D13-a chose, so the panel's reads and the load and export results it consumes are unchanged. The setup command and the file export are outcomes the executor trims to status and revision when too large, so their compact forms are what keep generation, state, `library_id`, `written` and the counts; `catalog` and `in_file` pages are now cut by size, which only moves where `next_cursor` falls |
| D14-a2 | A compact page cuts labels and names, never an identifier: `library_id`, `record_id` and a note's `code` are the keys a detail read and a copy name, as AW-02 keeps `Discovery::IDENTIFIERS` whole. A row whose identifiers alone outgrow a reply comes alone and is refused as `request.response_too_large`, never cut silently. A compact comparison lists the first candidates, at most 20 and within 8 KiB serialized, and counts them in `candidate_total`; `in_file.detail` reads any of them. A compact export result cuts `library_name` the same way, since a caller or a replaced file can supply any length |
| D14-b | The Psi assignment target stays one object schema: `core/json_schema.rb` has no `oneOf`, and adding it to the validator for one adapter is outside this stage. The two published examples (`perimeter`, `model_default`) and the schema's `description` name each shape's keys; the handler still refuses any other key set as `params.invalid` |
| D14-c | A large compound copy is reviewed through AW-04's compact preview, unchanged. A `use_library` replacement names existing ids, so every part is `stable` and reads whole; a `create` copy names a fresh id each run (D12-c) but stays small, because its resolution has no candidates and `affected` lists references only, so its preview fits one reply and its reviewed detail is the catalog row (`catalog.detail`) at the same generation. Deterministic preview ids stay the D12-c follow-up |
| D14-d | The optional retained receipt for a lost `export_file` reply is not selected (deferred, optional). `export_file` answers `destination_state`, the SHA-256 of the bytes it wrote; after a lost reply `export_preview` with the location reports `destination.state`, and a value other than the reviewed one means a file was written there. No path, file read or retained record is added |

AW-07 choices, recorded before the gate:

| ID | Choice |
| --- | --- |
| D15-a | Bounded export QA adds no MCP tool: `export_preflight` takes `compact` and `part` (with `row`), `export_status` `compact` and `part`, `latest_export` `compact`, following `preview`'s `part`. The whole reply stays the default (D12-a), so the panel's preflight and polling are unchanged. A page's `total` counts the filter's rows and `unfiltered_total` the part's; `compact` counts the whole preflight, so a filter never changes the declared scope of a total |
| D15-b | A task keeps, when it ends, its findings, its compact result and its rendered report: a blocked run's, and a written run's HTML as rendered before the write, since that is generated diagnostic content (the file bytes stay AW-09's optional slice). A run that ended before translation answered keeps none and says `no_translation`; one that stopped after it, or whose report failed to render, `not_rendered`. Cursors bind the task id, not the revision, because the kept content never changes; the existing 20-task, 30-minute retention bounds memory |
| D15-c | Preflight metadata checks share `Export::MetadataCheck`, which `RecordReader` now calls, and each contributor's preflight names the records its section reads, with the same pass-through and claim flags. Naming them twice is the smallest honest route: running the contracts dry is the whole extraction. Windows' preflight still runs its projection through the real reader, so a Faces metadata problem can appear once more there with no object id |
| D15-d | Repair scope: stored text that is not a JSON object, anywhere, and a readable record on an Edge no Zone holds (`zones.containment` gives a reason). One Edge per invoke, named by path and the SHA-256 of the stored text; a readable record a Zone holds refuses `thermal_bridge.repair_not_needed`, so clear stays the strict route. Locked or shared paths refuse; the user unlocks or makes the storage unique. Removing a readable id runs the engine's reference check, which reads every assignment, so unreadable text elsewhere refuses `record.unreadable` first (fail closed); repair the unreadable ones first. `edges.clear` and Type delete refuse the same way today, a follow-up outside this stage |
| D15-e | R16/A16, an expected revision on `start_export`, is deferred, optional, as recorded at intake. Every task already names its `source`, so a caller can compare what a run read with what it reviewed |

AW-01 through AW-07 can be made concrete without choosing a model vendor or a remote service.
Routine naming/helper decisions belong to coding agents within the accepted contracts. Record a
changed product/security/compatibility choice here before dependent work; do not let a generic
cleanup silently expand it. Authorizing the selected packet can accept these defaults explicitly.
