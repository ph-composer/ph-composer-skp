# Decisions for implementation intake

STATUS: D01-D10 recommended defaults accepted 2026-11-10 under the implementation go; AW-01 choices recorded below.
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
| D01-c | Destructive guard: Spaces `delete`, `remove`, `volumes.delete` and `volumes.remove` refuse `target.foreign_records` while another owner's entity-owned record sits on the Group or below it. Explode operations use the same at-or-below rule as erase, because exploding changes every descendant path other references use. Planned at proposal time only: every invoke re-plans, so steps need no engine access. A thermal-bridge tag stranded on an Edge outside every Zone cannot be cleared by its feature today; that is AW-07's outside-Zone repair (R10), and native Delete stays the user's own choice meanwhile |
| D03-a | A Zone's own lock is checked by `Occurrences.resolve_editable_zone`, which `zones.update`, `update_field`, `update_metadata` and `UpdateZoneStep` apply share; Face writes already refused it. `writable_zone!` is unchanged, so export preflight does not newly block a locked Zone. Split identity repair's own Face writes through `face_at` do not check the Zone's own lock: a follow-up outside AW-01 |
| D06-a | Space create receipt adds `accepted`, `left_out` and per-Volume `faces`. The reviewed-set precondition is the existing `expected_revision` (and `proposal_digest` from an action preview); no digest parameter and no strict all-or-nothing mode are added |

AW-01 through AW-07 can be made concrete without choosing a model vendor or a remote service.
Routine naming/helper decisions belong to coding agents within the accepted contracts. Record a
changed product/security/compatibility choice here before dependent work; do not let a generic
cleanup silently expand it. Authorizing the selected packet can accept these defaults explicitly.
