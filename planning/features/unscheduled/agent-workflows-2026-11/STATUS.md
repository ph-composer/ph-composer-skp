# Agent workflow delivery ledger

DATE: 2026-11-09
STATUS: In progress. Implementation authorized 2026-11-10; AW-01 merged to main (#440); AW-02 implemented on branch.
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
| AW-02 | Implemented on branch `feat/agent-workflows-aw-02` | A05/A12/A15 descriptor | Recheck below. API 1.35; names bound in CONTRACTS C02, choices D04-a, D03-b, D01-d. Offline: `make ci` exit 0 on `0aa93dce` (Ruby 2635 runs, 0 failures; JS 863 pass; Python 264 passed; RuboCop 708 files clean; fixtures, panel and runtime manifests, RBZ 568 files verified); no shipped panel or Python asset changed, so the runtime manifest is unchanged. New `agent_access_discovery_test` (every list section paged to the end and each row described; 40 synthetic features: index degrades to counts and every page fits 24 KiB; 600 large rows page losslessly; cursor bound to section, owner and registry; stray and edited arguments refused; sessions only in the token-filtered index; outside example `tags` adapter described from its own callback), guide golden, topic and version tests, initialize/guide route over the socket, shipped assignment examples meet their targets, callback examples checked at registration. Pre-gate Sonnet read: 10 items; fixed stray section arguments without `section`, an edited cursor past the end, fenced headings, one registry digest per page; declined foundation descriptions in `describe` (D01-d) and moving the descriptor out of `API` (shell already names `Library` for refusals). Codex review, native/MCP gate: pending |
| AW-03 | Scoped | A06 | None |
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
