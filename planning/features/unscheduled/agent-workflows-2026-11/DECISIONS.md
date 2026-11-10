# Decisions for implementation intake

STATUS: Recommended defaults, not accepted product decisions or authorization.
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/435 (review/planning publication only)

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

AW-01 through AW-07 can be made concrete without choosing a model vendor or a remote service.
Routine naming/helper decisions belong to coding agents within the accepted contracts. Record a
changed product/security/compatibility choice here before dependent work; do not let a generic
cleanup silently expand it. Authorizing the selected packet can accept these defaults explicitly.
