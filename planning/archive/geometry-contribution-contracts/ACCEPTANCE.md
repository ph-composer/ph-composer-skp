# Geometry contribution acceptance

STATUS: Complete 2026-10-26. G01 to G06 pass offline on both Rubies (PR 119, `tests/geometry_snapshot_test.rb`). G07 to G13 were G-03's and went with it: Phase 3a P3a-05's `derived` segments replaced the line primitive, and thermal bridges' T06 drew Edges through them natively. G14 passes through thermal bridges T08 (runs from captured Edge topology, attached through the Python section's declared contract). G15 passes through Spaces' derived geometry (P3a-05).

| Case | Scenario | Required result |
| --- | --- | --- |
| G01 | Root Edge with registered authored dictionary | Detached entry exists with finite SI endpoints, full path and preserved allowed data |
| G02 | Nested Groups and repeated scaled/reflected component occurrences | Distinct occurrence paths, single coordinate transformation and correct adjacency |
| G03 | Coincident endpoints in separate containers | No invented topological connection; native shared vertices connect only in their occurrence scope |
| G04 | Resumable capture versus direct capture | Same entries/digest/facts, one revision, bounded cursor progression and cancellation |
| G05 | Cutting Window component and Face export | Existing opening/native-definition semantics and authored geometry goldens preserved |
| G06 | Invalid transform/degenerate Edge/data | Explicit diagnostic/refusal policy, no unreported incomplete capture |
| G07 | Outside line mode with no thermal-bridge feature | Public primitives render; shared modules need no feature branch |
| G08 | Lines and surfaces across hidden/tagged ancestors and shared paths | Declared visibility/path-mask/isolation behavior; complete legend quantities remain unchanged |
| G09 | Derived run filtered by a subset of source paths | Per-segment filtering by each entry's `path`; the `member` key keeps the legend count whole; no label-based identity guessing |
| G10 | Invalid primitive shape/style or callback failure | Named mode failure outcome before draw; other modes usable, Model untouched |
| G11 | Revision, tags, camera, mode switches and Model close | Correct cache invalidation, no leaked resources or calculation/repair during draw |
| G12 | Existing Face/Zone/Assembly/Window modes | Accepted colors, hatching, lift, isolation and selection behavior retained |
| G13 | Representative synthetic large models | Before/after traversal, preparation/draw and memory measurements; agreed budget met |
| G14 | Actual thermal-bridge export adopter | Runs use captured Edge topology and attach through declared Python contracts; owning warnings/omissions correct |
| G15 | Actual Spaces derived geometry adopter when introduced | Supported primitives meet owning plan without host/domain branches in shared service |

Use deterministic detached geometry/serialization tests for G01 to G06; native transformed/cutting
fixtures supplement them. G07 to G13 require shared-service tests and native drawing observations.
G14/G15 remain allocated adopter evidence, not a claim those features shipped here. Synthetic standalone
contributors prove shared capability independently. Record compatibility/build/host receipts and exact
benchmark fixtures. Existing offline passing tests alone do not prove a line is visible in SketchUp.
