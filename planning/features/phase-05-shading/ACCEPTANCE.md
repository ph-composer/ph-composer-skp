# Shading: acceptance register

DATE: 2026-11-19
STATUS: Scoped. Authorized 2026-11-19 with every Shading stage ([STATUS](STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Closure gates for Phase 5. The [PRD](PRD.md), "Acceptance shape", is the behavior list. Ids use
`SD` (`SH` is taken in [`native-acceptance/cases.json`](../../native-acceptance/cases.json)).
Record each host run with `acceptance_case.py begin` and `finish` during the run, with a
source-controlled evidence summary under `evidence/`; SKP files and captures stay in `_private/`.

## Reference model

Synthetic, built by script: Zone A (a 5 x 5 x 3 m box, fully classified) holding one unclassified
overhang Face and one plain Group "Fin" of two Faces; at the root, two loose coplanar Faces sharing
an edge, a Group "Neighbour" of five Faces with a nested unnamed Group of one, a Component "Louvre"
of two Faces placed three times and tagged as instances, and one Face with a hole. Expected export: 2 + 1 + 2 + 6 + 6 + 1 =
18 Shades in five components: "Shading" (3, the loose pair and the holed Face), "Zone A Shading" (1),
"Fin" (2), "Neighbour" (6), "Louvre" (6).

| ID | Owner, stage | Required evidence | State |
| --- | --- | --- | --- |
| SD01 | Shared, P5s-01 | CONTRACTS section 7's six questions answered by focused test or host run and folded into CONTRACTS; the survival table (copy, array, paste, Make Group, Make Component, Make Unique, push-pull, Divide, intersect, explode, each with Undo, Redo, save and fresh reopen) in `context/SKETCHUP_HOST_BEHAVIOR.md`; architecture review recorded | Blocked 2026-11-19 on `2a9c5e17`: eight of ten gestures measured and folded into `context/SKETCHUP_HOST_BEHAVIOR.md`; Move-copy array and push-pull not run ([evidence](evidence/sd01-host-facts.md)) |
| SD02 | Shading, P5s-02 | Assign and clear on explicit references for a Face, a Group and a ComponentInstance, direct and nested, each one Undo step; unchanged targets report so; every refusal row of the PRD's table, a Face behind shared storage included, writes nothing and carries its code; a mixed selection applies and lists what it left out; a stale revision refuses; a panel-closed script tags and clears through registered actions only; `list` returns the reference model's five components | Not run |
| SD03 | Shading and Zones, P5s-03 | The tagged overhang Face raises no `face.unclassified`; Zone A's Room still exports closed; classify, Suggest classification, Solve adjacencies and the Classify tool leave it alone; clearing the mark brings the unclassified finding back; a classified Face refuses the tag and, after Clear classification, takes it; a Zone made inside a marked Group keeps its Faces as envelope and raises `shading.zone_inside`; every call site P5s-01 listed has a test | Not run |
| SD04 | Shading, P5s-04 | Right-click on loose Faces, on a closed Group and on a Face inside an open Group offers the right items and only those; the items appear in Extensions > PH-Composer; each choice is one Undo step; the notice and status bar name what was left out | Not run |
| SD05 | Shading and Colour-by, P5s-05 | The Shading mode colours all 18 occurrences, nested and repeated, and nothing else; the legend shows five rows with counts and areas in the display units; a hidden tag hides the drawing and keeps the legend; repaint cost at 5,000 Shading Faces recorded | Not run |
| SD06 | Shading and export, P5s-06 | The packaged RBZ exports the reference model; the HBJSON reloads with 18 orphaned Shades, the five names, `is_detached` true; conformance passes; the report's Shading section matches; a forced attach refusal leaves the Shades out with a note and still writes the pair; the pinned PHX gives five shading components per Variant with `InnerAttachment` -1 in WUFI XML and `idIC` -1 in METr JSON; save, reopen and re-export give the same HBJSON; section cost at 5,000 Shading Faces recorded | Not run |
| SD07 | Integration, P5s-07 | Both Ruby gates, coverage, browser and runtime checks, footprint; the PRD's acceptance shape from a fresh process; Ed opens the WUFI XML in WUFI-Passive and the METr JSON in METr and confirms the shading components, the holed Face included | Not run |
