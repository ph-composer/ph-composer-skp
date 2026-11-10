# Findings and recommended corrections

Baseline: `f65ccee6`, API 1.31. Paths and lines below name source at that revision. “Reproduced”
means an assertion-backed offline host-stub probe, not native SketchUp proof. “Gap” means a missing
supported workflow; “risk” requires further measurement. P1 should precede expanded write use;
P2 blocks a material workflow; P3 is a useful follow-up. Plans use the IDs in this file.

## R01 · P1 · Conflicting container ownership permits unintended Zone removal

**Reproduced baseline defect; partially addressed concurrently.** `zones.make` accepts a Space Group,
writes its Zone record on that same Group, and starts treating its Floor Segments as Zone Faces.
`spaces.delete` then deletes the Group, including the Zone, after checking only Spaces-owned identity
removals. The probe creates a Space, makes that Group a Zone, and deletes the Space: both writes
commit and the Zone inventory becomes empty.

Evidence: `features/zones/zone/operations.rb:299-325`, `zone/steps.rb:26-42`,
`features/spaces/authoring.rb:137-143,262-280`, `spaces/steps.rb:325-334`, under `src/ph_composer/`;
[feature probe](evidence/feature_probe.rb). The governing rule is unique entity ownership and
reference-aware removals in `context/EXTENSIBILITY.md`, Entity-owned reference targets.

**Concurrent delta:** while this review ran, SUI-02 landed as `f93d8b6b`. Its shared
`Records::EntityStore.claimed?` check in Make Zone rejects a directly selected claimed entity and
claimed active-path ancestors. That closes the direct new-overlap case above. It does not recursively
inspect a selected plain wrapper or add a deletion guard for pre-existing overlapping records.
The retained receipt describes the original baseline; publication on a newer base does not claim a new-head test.

Correction: reuse the new claim mechanism, then settle and enforce the descendant/legacy-overlap
rules through feature-neutral ownership contracts. Never put Spaces names into Zones. Guard
destructive subtree removal against another owner's records/references. Preserve ordinary permitted
Face/Edge assignments. Test direct and wrapped containers, malformed claimed records, existing
overlaps, preview/apply, rollback, native Undo and save/reopen. [AW-01](../../features/unscheduled/agent-workflows-2026-11/phases/aw-01-target-safety.md).

## R02 · P1 · Some Face writes treat a stale null identity as a current target

**Reproduced defect.** Read an unassigned Face reference (`entity_id: null`), classify the Face, then
reuse the old reference with a newly read Model revision. Classify and reverse accept it. The strict
reference contract says that null must refuse when a Face has since gained a record. An agent
refreshing only the global revision can therefore write a target it did not reread.

Evidence: `features/zones/faces/operations.rb:150,197,222`, the resolver's `allow_unassigned` path in
`features/zones/zone/occurrences.rb`, and `context/CONTRACTS.md:463-479`. The copied-ID probe distinguishes
outcomes: an exact copied identity refuses; null reaches planning but the tested classify apply rolls
back. This is not evidence of a committed copied-Face edit.

Correction: use the owning strict reference resolver for every explicit-reference mutation,
including classify, reverse, Assembly assignment and apply-time checks. A genuinely unassigned Face
remains writable. Native picking should obtain a current reference first. Acceptance must cover
null-to-record transitions, exact IDs, copied/shared paths, counterpart writes and zero-change refusals.
Owner: AW-01.

## R03 · P2 · Single-Zone editing bypasses the Zone's own lock check

**Reproduced defect.** `zones.update_field` refuses a locked Zone with `target.locked`, but
`zones.update` commits a name edit on that same locked Zone. Different client routes enforce
different write eligibility. Ancestor and shared-storage checks do not substitute for the Zone's lock.

Evidence: the mutable Zone resolver and `Operations.ensure_mutable_zone!` in
`features/zones/zone/occurrences.rb` and `zone/operations.rb`; the `locked_zone_edit_variants` probe.
Correction: make the owner enforce the same own-lock, ancestor-lock, identity and shared-storage
policy in single, batch and metadata operations. Test all routes and keep native refusal/readback
evidence. Owner: AW-01.

## R04 · P2 · Space creation does not report the requested Faces it left out

**Reproduced outcome gap.** With one real Face path and one missing path, `spaces.create_preview`
reports the missing path in `left_out`; direct `spaces.create` commits from the real Face and does
not return that omission in its result/findings. A successful transaction does not tell an agent
that its input set was only partly used. This is selection filtering, not proof of a partial
transaction or failed rollback.

Evidence: `features/spaces/create_faces.rb:46-60,89-110`, `authoring.rb:25-65` and
`html/features/spaces/create_review.js:67-89,137-149`; feature probe. SUI-05 subsequently merged create/Volume changes; its archived plan is
`planning/archive/spaces-ui-refinement-2026-11/PLAN.md`.
Correction: first recheck the merged SUI-05 behavior. Make the receipt enumerate accepted/rejected paths and reasons;
bind apply to the reviewed accepted set. Preserve the accepted UI selection-filtering behavior;
offer a strict all-requested-targets mode if required by the workflow, explicitly versioned. Do not
silently redefine every existing caller. Test missing, wrong-kind, locked and disconnected candidates.
Owner: AW-01's authoring-receipt slice, after the SUI-05 recheck.

## R05 · P2 · MCP discovery drops catalogs needed for generic feature discovery

**Reproduced contract gap.** `API.discover` exposes 11 record kinds, nine reference targets, extension
namespaces, common refusal sets and task retention metadata. `AgentAccess::Tools.discover` keeps
only selected keys plus operation names; owner discovery returns only operations. `describe` can
describe a record kind if its name is already known, but the MCP route does not supply that catalog.
The generic record query explicitly tells a client to obtain its required kind from discovery.

Evidence: `shell/api.rb:155-202`, `agent_access/tools.rb:10-11,36-50,78-85`,
`shell/record_queries.rb:20`; [discovery output](evidence/discovery.json). The missing operation-key
arrays in that output are intentionally represented by `operations`, not missing operations.
Internal proposal participants need no new callable tool. Record/reference catalogs and common
refusal semantics are the consequential omission.

Correction: bounded discovery sections with descriptors reachable by known IDs, common refusal
sets and task/contract information. Retain the compact operation index. Current discovery is 13,017
bytes; Windows owner discovery is 21,742 bytes against 24,576, so add pagination before growing it.
All current individual descriptions fit; this is not a current description-size failure.
Test an outside kind/extension with no custom adapter and growth beyond one page. Owner: AW-02.

## R06 · P2 · Agents cannot independently enumerate initial geometry and eligible Edges

**Source-backed workflow gap.** Context reads expose selection and active-path entities. Zones
lists start from authored Zones; Spaces candidate Faces require an existing Space or Volume.
There is no bounded, selection-independent discovery of root/plain-wrapper floor Faces or candidate
Groups for the first Space/Zone. Explicit writes exist, but the agent must first obtain IDs from
the user, native selection or an out-of-band geometry tool.

Thermal Bridge assignment has a related hole: `edges.selection` reads selected Edges; schedule
rows expose paths of assigned Edges but not complete assignment references/expected values.
There is no public read of arbitrary candidate Edges or assignment-by-path, so an agent cannot
discover an unassigned junction or round-trip every schedule edit without changing selection.

Evidence: `shell/context_commands.rb:142-155`, Spaces candidate/read declarations, Zones Make params,
`features/thermal_bridges/assignment/selection.rb`, `runs/schedule.rb`, and [coverage](COVERAGE.md).
Correction: feature-owned candidate reads backed by shared geometry traversal/reference primitives.
Return complete refs, SI geometry, eligibility/refusal and expected values without assigning IDs or
moving selection. Page candidates and large loops/edge sets separately. Raw geometry writing is a
different product decision. Owner: AW-03.

## R07 · P2 · Several valid data structures have no budget-safe readback

**Reproduced access failures.** The executor correctly refuses results over 24 KiB. The following
results cannot be recovered merely by reducing `limit`; some have no projection or child reader:

| Fixture and read | Measured result | Missing route |
| --- | --- | --- |
| One Window Unit with accepted 30 KB `user_data`, `units.list`, ID filter, limit 1 | 30,585 bytes | No `fields`; outlines omit values/metadata |
| 10 x 10 Window Type, `types.list fields:[values]` / `[display]` | 26,041 / 106,013 bytes | No element/topology child pages; generic `fields:[elements]` is still 25,912 bytes |
| Generic `records.list fields:[]`, one record with 30 KB metadata | 30,469 bytes | `fields` filters values only, not metadata |
| One host Face with 450 holes, `units.host_extent limit:1`, no Units | 27,160 bytes | Limit covers Unit rows, not outline/hole geometry |
| 450 legacy membership stamps, `zones.list limit:1 fields:[]` | 101,578 bytes | Repeated whole `restorable` collection outside page |
| One Thermal Bridge run with 799 Edges, schedule limit 1 | 35,943 bytes | Whole `edge_paths`; no run-detail pagination/projection |
| 180 Faces, `units.glazed_area_by_face` | 36,366 bytes | Whole calculated-area table, no narrowing params |

Evidence: [envelope probe](evidence/envelope_probe.rb), [feature probe](evidence/feature_probe.rb);
`shell/record_queries.rb:57-75`, `shell/definition_lists.rb:27-38,48-73`, `shell/pages.rb:37-51`, relevant Windows,
Zones and Thermal Bridge readers listed in [coverage](COVERAGE.md). A typed Material summary can
omit metadata successfully; do not incorrectly claim all definition reads fail.

The same budget applies to action previews: `shell/dispatch.rb:150-161` bundles value, affected rows
and findings with the digest, and MCP handles preview as a read. Large compound preview detail has
no separate retrieval route. This is a source-evidenced risk, not an additional size reproduction;
test it when completing each compound workflow rather than assuming bounded lists solve it.

Correction: keep compact summaries, add bounded children/details, and permit metadata selection
and large-value retrieval without truncation. Include every envelope field in budget accounting.
Preserve a retrievable compact preview digest/summary and complete reviewed details as well.
Do not lower accepted model sizes or merely raise the MCP cap. Acceptance must read every accepted
field through the actual executor at a stable revision, with no skipped objects. Owners: AW-04,
AW-05; shared contract in CONTRACTS.

## R08 · P2 · Library catalog detail and review digests can become unreachable

**Reproduced access failures.** A catalog with one valid row and 350 rejected-row warnings exceeds
35.8 KB at limit 1 because warnings are repeated outside the page. One valid Material with a 30 KB
notes field also exceeds 30.9 KB, with no field projection. Load can complete with `value` omitted,
then neither catalog nor in-file read retrieves the result. An export preview with 180 metadata
omission rows is 31,963 bytes, preventing access to the projection digest needed for replacement.

Evidence: `library/install.rb`, `library/catalog.rb`, `library/export_projection.rb:19-48,167-177`,
`library/export_registration.rb:35-45,74-96`, `agent_access/executor.rb:120-173`; envelope probe.
Correction: page warnings/unavailable rows and comparisons separately, make catalog summaries
projectable, and always retain compact export scope/digest/destination receipts. Child pages must
bind catalog generation or export projection, not just Model revision. Owner: AW-06.

## R09 · P2 · QA and blocked-export diagnostics can be impossible to inspect

**Reproduced access and readiness gaps.** 180 unclassified Faces produce 59,074 bytes from aggregate
preflight and 58,862 bytes from the Face contributor. Neither accepts a filter/page. A synthetic
runtime result with 240 unique findings makes the in-process task 152,946 bytes; MCP status/latest
retain `export.blocked` but omit the report and findings. A blocked export writes no report file,
and current preflight does not necessarily contain runtime findings. “Read it back” has no exact-run
reader in this case.

Separately, Assembly create accepts reserved `user_data.ph_composer`; preflight does not flag it,
but extraction refuses it before translation. This is an earlier-diagnosis gap, not silent export
loss. Evidence: `shell/dispatch.rb:49-70`, `agent_access/executor.rb:120-173`,
`export/task.rb:135-146,179-195`, task history, `features/assemblies/export.rb:43-72`,
`export/record_reader.rb:188-203`, and envelope probe.

Correction: aggregate summaries with bounded current-model findings/repairs; caller-owned task
finding/report retrieval bound to the original run, including failure paths. Share inexpensive
metadata/readiness validation so preflight catches known extraction blockers. Keep translation-only
checks clearly separate. Acceptance: hundreds of unique issues, complete retrieval after a failed
run and a subsequent user edit, expiry/revocation, no artifact created for blocked runs. Owner: AW-07.

## R10 · P2 · Corrupt thermal assignment data has no semantic repair route

**Reproduced repair gap.** Malformed JSON on an Edge is reported in the schedule as unreadable and
blocks export. Selection/clear refuses `record.unreadable`; the public interface cannot remove the
bad record. Parsed-but-invalid values do have a clear route, so this finding is specifically about
unreadable storage, not all invalid assignments.

Outside-Zone assignments have a related recovery gap: the warning recommends clearing, but the
normal action requires a Zone-qualified reference and Type replacement can refuse stranded uses.
This second route is source-evidenced, not a separate malformed-JSON reproduction.

Evidence: `features/thermal_bridges/assignment/operations.rb:43-47,61-100,126-153`,
`assignment/selection.rb:41-71,85-89`, `scan/occurrences.rb:99-117`,
`runs/findings.rb:115-119`, feature probe.
Correction: a separately named previewable discard/repair operation with exact path, storage-state
digest and explicit loss disclosure. It must refuse changed bytes, locked/shared targets or foreign
data, run as one Undo step and preserve unrelated dictionaries. Avoid weakening ordinary clear to
erase unknown data. Owner: AW-07.

## R11 · P2 · Connection setup is difficult to repair or keep independently scoped

**Source-backed workflow limitation.** One fixed server entry/header file per client makes the
second Model-specific connection replace the first client's credential. Reconnect/port repair is
buried in a newly issued token's dialog; Codex configuration collisions require manual edits.
Configured and successfully contacted are different states, but the user has no end-to-end setup
check. See [connection audit](CONNECTIONS.md) for source locations and preserved security choices.
Correction: explicit saved profiles, inspectable replacement/repair, no secret redisplay and a
harmless verification path. Preserve existing entries and keep permissions visible. Owner: AW-08.

## R12 · P2 · The agent operating guide is a separate manual handoff and contains stale routes

**Directly evidenced documentation/discovery gap.** MCP serves no guide resource/topic, while the
user is instructed to supply a repository document. Handwritten docs disagree with implemented
Window extent and transport capabilities; initialize instructions select Models by file name even
though equal names are possible. See [connection audit](CONNECTIONS.md).
Correction: ship a discoverable versioned guide, bind recipes to real operations, identify a Model
by session and verified context, and reconcile proposed/current prose. Test an agent that has only
the installed connection. Owner: AW-02 and AW-10 acceptance.

## R13 · P2 · Safe timing during a user's native gesture is not established

**Unverified host risk, not a reproduced data-loss defect.** Busy state excludes active native tools
except on explicit context-navigation paths. The broad side-by-side editing claim needs native
evidence for in-progress drawing and Move gestures, not only completed edits, modals and stale
revisions. Source and boundaries are in [connection audit](CONNECTIONS.md).
Correction: measure first, then implement only the specific readiness/refusal contract needed.
Return a retryable reason without cancelling the user's tool. Keep the existing revision/replay
contracts. Owner: AW-09 experiment, followed by AW-10 acceptance.

## R14 · P3 · Visual artifacts and operation history depend on extra client tooling

**Capability limitation and optional improvement.** Capture excludes overlays/panels; images and
export bytes are delivered through local filesystem receipts. A client limited to MCP may not read
them. Recent-call diagnostics omit affected refs/revision and are not a public operation history.
This does not make existing local-client captures false or existing mutations unobservable.

Correction: bounded caller-owned artifact retrieval and a minimal session-scoped operation/incident
summary. Treat overlay capture as an experiment with a documented unsupported result if the host
cannot supply it. Do not turn diagnostic access into arbitrary files/logs or an agent conversation
store. Owner: optional, separately selectable AW-09 slices.

## R15 · P2 · Atomic library copy-and-assign has an undiscoverable parameter contract

**Directly evidenced schema gap.** `library.copy.assignment` is a bare object and its example omits
assignment. The installed kind callbacks have typed Material Layer-Segment and Frame/Glazing
targets; Psi's mode-specific target rules also rely on runtime branches. Neither `discover` nor
`describe` exposes those adapter descriptors.
An agent can copy then assign through separate operations, but cannot derive the one-Undo compound
request from the published description alone. The shared generation description also says it may
be omitted, while copy requires and fetches it.

Evidence: `library/install.rb:24-31,39-58`, `library/coordinator.rb:138-144`,
`features/assemblies/library_kind.rb:111-122`, `features/windows/library_assignment.rb:11-25,57-80`,
`shell/api.rb:158-224`. Correction: publish kind/version/assignment schemas and examples from the
registered callbacks, including unsupported assignment as explicit absence. Retain required source
generation checks and correct the prose. Prove outside adapters need no MCP-specific business
logic. Owners: discovery contract in AW-02, workflows in AW-06.

## R16 · P3 · Export cannot explicitly bind to the Model revision the agent reviewed

**Current-contract limitation, not corruption.** `start_export` accepts a location, captures its
source state when started and guards against content change during the task. It does not accept
the revision returned by an earlier preflight. A user may edit between review and start, and the
agent exports the newer state without explicitly choosing it.

Evidence: `shell/api.rb:273-277`, `export/task_contract.rb:81-91`, `export/task.rb:56-60,199-203`.
Recommendation: optional `expected_revision` checked before recovery or destination writes, with
source revision in compact task receipts. Preserve existing callers' latest-state behavior and the
existing export-generation distinction for view-only navigation. Test stale start writes nothing
and an accepted start carries its original source identity through completion. Owner: optional AW-07 slice.
