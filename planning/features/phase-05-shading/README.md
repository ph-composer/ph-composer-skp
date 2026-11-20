# Phase 5: shading

DATE: 2026-11-19
STATUS: In progress. Every stage authorized by Ed 2026-11-19; P5s-01 to P5s-06 merged, P5s-07 implemented; host acceptance SD01 to SD07 and Ed's check of the two files outstanding ([STATUS](STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Tag Faces and Groups as shading from the right-click menu and export them as honeybee orphaned
Shades, which PHX turns into shading components in WUFI-Passive and METr. No solar or shading
solver. Follows [Phase 4: climate](../../archive/phase-04-climate/README.md) and precedes
[Phase 6: Programs](../phase-06-program/README.md). One feature, one flat packet.

## Read order

1. [PRD.md](PRD.md): what can be tagged, the name rule, the Colour-by mode, the export and what is
   out of scope.
2. [STATUS.md](STATUS.md): the tracking ledger and what waits on Ed.
3. [DECISIONS.md](DECISIONS.md): findings F1 to F13 and Ed's answers D5s-01 to D5s-17.
4. [research/honeybee-ph-and-phx-shading.md](research/honeybee-ph-and-phx-shading.md): what PHX
   reads and what reaches the two files, at the repository's pins.
5. [CONTRACTS.md](CONTRACTS.md): the proposed feature id, mark, operations, the Zones seam and the
   export section.
6. [PLAN.md](PLAN.md) and [ACCEPTANCE.md](ACCEPTANCE.md): seven stages, SD01 to SD07 and the
   reference model.
7. The stage being worked, under [phases/](phases).

## Related, not moved here

- [Zones outside a Building Segment as shading](../unscheduled/zone-shading.md): a whole Zone as
  shading. It would reuse this packet's export section; this packet answers its SH-3 and SH-4.
- [Sun-path view](../phase-08-post-mvp/sun-path-view/README.md) and
  [window performance overlays](../phase-08-post-mvp/window-performance-overlays/README.md),
  post-MVP drafts.
