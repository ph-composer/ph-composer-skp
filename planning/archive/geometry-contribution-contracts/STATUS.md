# Geometry contribution contracts status

DATE: 2026-10-13
STATUS: Complete 2026-10-26. G-02 merged to main (PR 119); G-01 answered by thermal bridges P3b-01 and closed with G-04; G-03 superseded by Phase 3a P3a-05; G-04 closed by thermal bridges P3b-06 (native drawing) and P3b-08 (export and measurement), recorded in P3b-09.
ISSUE: [#118](https://github.com/ph-composer/ph-composer-skp/issues/118)

The phased plan is the `## Stages` section of [PLAN.md](PLAN.md); there is no `phases/` folder.
Acceptance rows are in [ACCEPTANCE.md](ACCEPTANCE.md).

| Stage | Scope | State | Evidence |
| --- | --- | --- | --- |
| G-01 | Confirm Edge facts, segment filtering, `member` counting and line width with the thermal-bridge packet | Answered by thermal bridges P3b-01 on 2026-10-21 ([D3b-23](../phase-03b-thermal-bridges/DECISIONS.md), answered): `vertex_ids` and `face_ids`, keyed with the Edge's container path, are enough for run formation; an Edge entry carries its path, so visibility is the Colour-by service's own path walk and needs no fact; filtering is per entry, one Edge each, and the legend counts entries, so no `member` key; the line width is a per-mode `stroke:` (H14, P3b-06). Closed 2026-10-26 with G-04 | [phase 3b CONTRACTS](../phase-03b-thermal-bridges/CONTRACTS.md), sections 1 and 5 |
| G-02 | Stub `Vertex` persistent id; `EdgeGeometry` and Edge entries in `GeometrySnapshot.walk`; snapshot goldens | Merged to main (PR 119) | `tests/geometry_snapshot_test.rb` (7 new, incl. shared vertices across repeated occurrences): root Edge with data and SI endpoints; nested, scaled and reflected transforms once; separate containers share no vertex; cutting component Edges absent; cursor equals direct capture; singular transform `geometry.invalid`. `make fixtures` changed no golden; export collection and phase-one export suites unchanged |
| G-03 | `ColourBy::LineEntry`, service branch, overlay line pass | Superseded 2026-10-15 by Phase 3a P3a-05: coloured lines are `derived` segments (`context/EXTENSIBILITY.md`, "Colour-by derived geometry"); no `LineEntry` | none |
| G-04 | Thermal-bridge adoption, measurement, native drawing and export proof | Complete 2026-10-26: native drawing proved in P3b-06, export and measurement in P3b-08, closed in P3b-09 ([T09](../phase-03b-thermal-bridges/evidence/p3b-09-acceptance.md)) | [T06](../phase-03b-thermal-bridges/evidence/p3b-06-colour-by.md); [T08](../phase-03b-thermal-bridges/evidence/p3b-08-thermal-bridge-export.md): the contributor reads the snapshot's Edge entries (runs from captured topology, attached through the Python section's declared contract); `GeometrySnapshot.capture` 1,708 ms median at 76,959 entries, 51,818 of them Edges |

Reviewed against source on 2026-10-13: the definition-local Edge facts in `definition_entity` are the
precedent for the Edge shape; per-segment filtering with a `member` key replaces the open mask
question.
| 2026-10-26 | Thermal bridges P3b-09 closed G-01 and G-04 with their receipts (T06, T08, T09). The packet is complete; #118 closes with the P3b-09 pull request. |
