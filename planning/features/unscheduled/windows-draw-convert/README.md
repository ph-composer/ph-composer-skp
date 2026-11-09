# Windows: draw a rectangle, convert it to a Window Type

DATE: 2026-11-07
STATUS: Scoped. Design packet delivered by walkthrough stage WT-07; waiting for Ed's decisions on
W7-1 to W7-10. No implementation is authorized.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/363

Read [PRD.md](PRD.md): the request, what the Windows feature already gives it, the proposed
Convert route, the decisions for Ed, the host facts to measure first, and the stages that follow
his go.

Origin: the 2026-11 usability walkthrough, synthesis item S-21, raw entry W-095
([SYNTHESIS.md](../../../archive/usability-walkthrough-2026-11/SYNTHESIS.md)). Delivery runs through the
walkthrough plan ([PLAN.md](../../../archive/usability-walkthrough-2026-11/PLAN.md)): its implementation
stages are added there when Ed approves this packet.

Decided by Ed, 2026-11-09 (W7-1 to W7-10), in the table of `PRD.md`:

- As recommended: W7-1 both places; W7-3 refuse rotated rectangles; W7-4 the frame outer size; W7-5 group by shared Edges; W7-6 preselect a same-size Type; W7-7 blank elements with an optional Copy from; W7-8 named by size; W7-9 one Undo restores everything; W7-10 convert before classification.
- Different from the recommendation: **W7-2** a rectangle touching its host Face's boundary is always refused; the user draws it inset and moves the Unit after.

Next step: implementation waits for Ed's go on stages S21-1 to S21-3 and host spike H1 to H3, with W7-2's refusal in place of spike H2.
