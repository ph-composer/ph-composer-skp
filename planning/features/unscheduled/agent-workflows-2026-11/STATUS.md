# Agent workflow delivery ledger

DATE: 2026-11-09
STATUS: In progress. Implementation authorized 2026-11-10; AW-01 (#440) and AW-02 (#441) merged to main; AW-03 implemented on branch.
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/439 (implementation); #435 tracked the review/planning publication
BASELINE: `f65ccee62b0a3994a46001d55f7aefd1a69f0faf`, API 1.31.

This is the only implementation progress ledger for the packet. The review's finding register is
evidence/rationale, not a competing implementation tracker.

## Entry gates

| Gate | State |
| --- | --- |
| Comprehensive review and phase-planning request | Authorized by Ed, 2026-11-09; completed locally in a new worktree |
| Implementation authorization | Given by Ed 2026-11-10 (implement-loop; merge on green delegated; computer use authorized) |
| Review/planning publication | Authorized 2026-11-10; #435 tracked publication only and is closed; #439 tracks implementation |
| Implementation intake / branch and delivery workflow | pr-loop, one branch and PR per stage, Codex review, merge on green; issue #439, PRs say `Part of #439` |
| Rebase and overlap screen | Documentation advanced to `6d06ff49`; SUI-01 through SUI-08 merged. Recheck baseline findings against their changes at stage intake |
| Product/security choices | D01-D10 defaults accepted 2026-11-10; R14/A14 and R16/A16 deferred, optional; AW-01 choices D01-a to D06-a in DECISIONS |
| Native host coordination | Conductor holds the SketchUp/Finder grant; each stage runs its host gate once on its merge head |

## Stages

| Stage | State | Required cases | Implementation/review/offline/native/client evidence |
| --- | --- | --- | --- |
| AW-01 | Merged to main (#440, `c67dfb1f`) | A01-A04 | Recheck above. Offline: `make ci` exit 0 (Ruby 2615 runs, 0 failures; JS 863 pass; Python 264 passed; RuboCop 704 files clean; fixtures, manifests, runtime and RBZ verified). New tests in `zone_face`, `zone_menu`, `zone_repair`, `entity_store_claims`, `spaces_operations`. Pre-gate Sonnet read: 13 items, fixed (own lock moved out of export preflight, Restore wording, apply-time and order tests), rest answered in DECISIONS. Codex review 1 (gpt-6-astra, PR #440): P1 stranded Zone record on a component escaped the removal guard, fixed by reading every entity store by presence; P2 create took its context from the first named path, fixed to the open context. Codex review 2 on `c3d6d174`: no findings. Native: ledger case `AW01` recorded pass on `c3d6d174` (installed RBZ from that head, SketchUp 26.1.188, fresh process), 8 of 8 assertions, [evidence](../../../native-acceptance/evidence/aw01-target-safety-2026-11-10.md): wrapper refusal, legacy finding and `target.foreign_records` guard, stale and copied null identities, locked Zone edits, create receipt, native Undo/Redo, save and reopen. A01-A04 closed for AW-01's scope |
| AW-02 | Merged to main (#441, `5818522d`) | A05/A12/A15 descriptor | Recheck below. API 1.35; names bound in CONTRACTS C02, choices D04-a, D03-b, D01-d. Offline: `make ci` exit 0 on `0aa93dce` (Ruby 2635 runs, 0 failures; JS 863 pass; Python 264 passed; RuboCop 708 files clean; fixtures, panel and runtime manifests, RBZ 568 files verified); no shipped panel or Python asset changed, so the runtime manifest is unchanged. New `agent_access_discovery_test` (every list section paged to the end and each row described; 40 synthetic features: index degrades to counts and every page fits 24 KiB; 600 large rows page losslessly; cursor bound to section, owner and registry; stray and edited arguments refused; sessions only in the token-filtered index; outside example `tags` adapter described from its own callback), guide golden, topic and version tests, initialize/guide route over the socket, shipped assignment examples meet their targets, callback examples checked at registration. Pre-gate Sonnet read: 10 items; fixed stray section arguments without `section`, an edited cursor past the end, fenced headings, one registry digest per page; declined foundation descriptions in `describe` (D01-d), moving the descriptor out of `API` (shell already names `Library` for refusals), guide links a connection-only agent cannot follow (they serve docs readers), a hard load failure if `guide.md` were missing (the RBZ ships it; a fallback would hide a packaging fault) and the degraded index dropping `operations` (named in its `next`). Codex review 1 (gpt-6.1-sol, PR #441, `c05128bd`): 5 P2, 1 P3, all fixed in `744c20fb` (index bounded past 400 features with a `features` section; oversized rows cut; callback examples checked only against valid params; reachability test calls `describe`; guide names every `user_data` pass-through kind; `unsupported` meaning covers an unmigratable older version). Codex review 2 on `744c20fb`: 1 P1, 2 P2, fixed in `5c93488b` (long lists cut; identifiers never cut; examples checked as plain JSON). Sonnet read of the final fix: added a multibyte cut test, a finite-number assertion and neutral `next` wording; declined: identifiers have no registration length limit, so one near the 24 KiB budget still overflows a row (follow-up, a registration contract change), and the index's 4 KiB headroom covers `connection`. `5c93488b` not Codex-reviewed. Native/MCP: ledger case `AW02` recorded pass on `5c93488b` (installed RBZ from that head, SketchUp 26.1.188, fresh process), 6 of 6 assertions, [evidence](../../../native-acceptance/evidence/aw02-discovery-guide-2026-11-10.md): initialize and the index name the guide, all 15 topics read over the real listener, every section and library-kind descriptor, 241 operations paged, 32 replies within 24 KiB, revoked token refused. A05 and the A15 descriptor part closed; A12 installed route proved, its two fresh-client runs are AW-10's |
| AW-03 | Implemented on branch `feat/agent-workflows-aw-03` | A06 | Recheck below. API 1.36; names bound in CONTRACTS C04, choices D11-a to D11-c. Offline: `make ci` exit 0 on `be9af18c` before the rebase onto `5818522d` (Ruby 2706 runs, 0 failures, 0 errors; JS 863 pass; Python 264 passed; RuboCop 715 files clean; runtime 150 assets verified, RBZ 573 files verified); no shipped panel or Python asset changed, so the runtime manifest is unchanged. New `context_children_test`, `zones_make_candidates_test`; extended `spaces_candidate_faces_test`, `thermal_bridge_assignment_test`, `window_convert_review_test`, `window_unit_actions_test`, `entity_store_claims_test`: root and quarter-turned wrappers with world coordinates checked once-transformed, hidden, locked, shared, claimed and solid rows, unassigned Edge assigned, read back by path, cleared and reread, schedule `edge_paths` read through `edges.at`, unreadable and non-object records as rows, expired cursors, 600-child and 400-Edge reads paged within 24 KiB, no read side effects (EntityScope capture, selection, edit path, revision). Pre-gate Sonnet read: 17 items; fixed an empty page refusing through `zones.containment`, a non-object Edge record failing the page, a locked wrapper offered as openable (now `ContextCommands.open_refusal`), undeclared `geometry.invalid`, missing `hidden` on feature rows, restore wording, and test gaps; declined: a Model-wide unreadable Zone record refusing `make_candidates` (Make Zone refuses the same), the Zones walk per page (the action's own rule), one restore row per Type with mixed panes reading `needs: selection` and large restore sets (AW-05), named-alone Face refusals (D11-b), raw root-composed transforms for shared definitions (the host-behaviour compensation), and `prepare` building the whole slice. Codex review 1 (gpt-6.1-sol, PR #442, `613cd7d0`): 2 P2, fixed in `92f85004` (a
restore host is offered only when `Placement::Hosts.writable` resolves it, so a duplicated Zone identity reads `needs:
host`; names over 256 characters cut and named in `truncated`). Codex review 2 on `92f85004`: 1 P2, fixed in the next
commit (Zone labels in Edge path rows cut the same way, reference kept whole). Native/MCP: case `AW03` not run. The
driver is ready (`_private/host/aw03/run.sh`: labelled setup of a read/view/model_write token and native fixture
geometry with an InstancePath oracle, then the MCP client: empty selection, root and 30-degree nested wrapper Make Zone,
first Space in the wrapper, unassigned Edge assigned, read back by path, cleared and reread, stale cursor and stale
reference, no read side effects, every reply within 24 KiB; native Undo/Redo between phases). Missing prerequisite: an
unlocked macOS screen. Two `host_bridge.py launch` attempts on the installed RBZ from `613cd7d0` timed out with no
bridge because SketchUp 2026 loads no Ruby extension until it is activated, and computer use refused every action
with "The screen is locked". A06's native rows stay open |
| AW-04 | Scoped | A07a | None |
| AW-05 | Scoped | A07b | None |
| AW-06 | Scoped | A08/A15 | None |
| AW-07 | Scoped | A09/A10; A16 optional | None |
| AW-08 | Scoped | A11 | None |
| AW-09 | Scoped | A13; A14 optional slices | None |
| AW-10 | Scoped | A17 and selected register | None |

Ed's go, 2026-11-10: "New branch for each phase of the work. Use the 'pr-loop' skill to manage the loop
and review protocol. You are authorized to merge once CI is green and all review comments (if any) are
properly addressed. You are authorized for any and all computer-use that you need in order to complete
this work."

## AW-01 stage-entry recheck (main `a991c720`, API 1.33)

`rbenv exec ruby -Itests planning/code-review/agent-workflows-2026-11/evidence/feature_probe.rb -n
"/space_group|plain_wrapper|copied_face|null_id|locked_zone|create_accepts/"`: 6 runs, 1 failure, 1 error,
read as follows (the probe asserts baseline behaviour, so a failure means the finding changed):

| Finding | Probe result on main | Entry state |
| --- | --- | --- |
| R01 direct | `test_space_group_also_becomes_zone` fails: Make Zone on a Space Group refuses `target.wrong_kind` | Closed by SUI-02 `f93d8b6b`; no new work |
| R01 wrapper | `test_plain_wrapper_can_put_a_space_inside_a_zone` passes: Make Zone on a wrapper holding a Space commits | Open |
| R01 deletion | No guard in Spaces delete/remove for another owner's records (source read) | Open |
| R02 | `test_null_id_reuses_stale_unassigned_face` passes: classify and reverse commit through a stale null id; `test_copied_face_null_id_bypasses_guard` reaches `failed/rolled_back` | Open |
| R03 | `test_locked_zone_edit_variants` passes: `zones.update` commits on a locked Zone | Open |
| R04 | `test_create_accepts_subset` errors at the old `floor_segment_ids` field: SUI-05 changed the result to `volumes`, still with no `left_out` | Open; SUI-05 shape kept |

## AW-02 stage-entry recheck (main `c67dfb1f`, API 1.34)

Measured with the offline stub at the AW-01 head before any change (the review's discovery probe writes into
the evidence folder, so the same reads ran from a scratch test):

| Finding | Measured on the AW-01 head | Entry state |
| --- | --- | --- |
| R05 | MCP `discover` index 12,993 bytes with keys `api`, `extension`, `capabilities`, `sessions`, `features`, `schemas`, `operations`; `record_kinds` (11), `reference_targets` (9), `extensions`, `common_refusals`, `tasks` and `contract_versions` only in process; Windows owner page 21,682 bytes against 24,576 | Open |
| R12 | `resources/list` and `prompts/list` empty; `initialize` instructions select the session by file name; the guide reached a client only as a repository file | Open |
| R15 | `library.copy.assignment` a bare object; no adapter descriptor in `discover` or `describe`; copy's `generation` described as omittable while its schema already required it | Open; schema groundwork here, workflows AW-06 |

## AW-03 stage-entry recheck (AW-02 head `380f147c`, API 1.35)

Measured with the offline stub from a scratch test before any change: a root Group holding one Face, nothing
selected.

| Finding | Measured on the AW-02 head | Entry state |
| --- | --- | --- |
| R06 Zones | `zones.list` answers `make_zone: null` and `total: 0`; no read lists Groups Make Zone could take | Open |
| R06 Spaces | `spaces.candidate_faces.list` with neither `space` nor `volume` refuses `params.invalid`; no first-Space route | Open |
| R06 Thermal Bridges | `edges.selection` answers `total: 0`; the only Edge reads registered are `edges.selection` and `selection_all` | Open |
| R06 inventory | No registered query enumerates children or candidates at a path (`child`, `candidate`, `inventory` match only `spaces.candidate_faces.list`) | Open |

## AW-04 stage-entry recheck (AW-03 head `3a768fbc`, API 1.36)

`rbenv exec ruby -Itests planning/code-review/agent-workflows-2026-11/evidence/envelope_probe.rb -n
"/window_type_children|cannot_project_away_metadata/"`: 2 runs, 0 failures; the baseline sizes are unchanged.

| Finding | Measured on the AW-03 head | Entry state |
| --- | --- | --- |
| R07 metadata | `records.list` with `fields: []`, one Material with 30 KB `user_data`: 30,469 bytes, `request.response_too_large`; the typed `materials.list fields:[values]` 1,243 bytes | Open |
| R07 Window Type | 10 x 10 Type, `types.list fields:[values]` 26,041 bytes, `[display]` 106,013; generic `records.list fields:[elements]` 25,912 | Open |
| R07 uses and Layers | No part read registered for Assembly Layers, Layer-Segments, Type elements or a row's `uses` (source read of `assemblies/declarations`, `windows/declarations`) | Open |
| R07 compound preview | Source evidence: `Dispatch#proposal_preview` bundles value, affected and findings with the digest, and the MCP `preview` tool is a read, so an oversized preview is refused whole and its digest lost | Open; proved with an oversized fixture in AW-04 |

