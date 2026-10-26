# P3b-03 evidence: edge assignment (T03)

DATE: 2026-10-25
STATUS: Host gate run on branch `feature/thermal-bridges-p3b-03` at `089db1b8` (PR #309), SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1. All seven assertions pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T03](../ACCEPTANCE.md). Offline half: `tests/thermal_bridge_assignment_test.rb` (15 runs),
`tests/zones_containment_test.rb` (4), `tests/thermal_bridge_assignment_walkthrough_test.rb` (1) and the
`Pick.edge_path` case in `tests/pick_point_test.rb`, green on Ruby 3.2.2 and 2.7.2; `make ci` green at
`089db1b8` (2,150 Ruby runs, 737 JavaScript, 246 Python, fixtures, hostkit, RBZ verified). Review: one
pre-gate Sonnet read and two Codex gpt-6-astra cycles on PR #309 with the architecture and Ruby rubrics (cycle
1: 1 P1 and 2 P2; cycle 2: 2 P2; all fixed). Host half: recorded through `tools/hostkit/acceptance_case.py` in
`_private/host/t03/T03/` (gitignored; synthetic fixture, no project data). The ledger row records a branch
commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `089db1b8`, SHA-256 `46c609f2a90ba77c963f2aacc9ffee78d64f7d7c4107dfaf0596087e913e2ac1` |
| Fixture | `_private/host/t03/T03/t03.skp` (SHA-256 `d9797c05`), a copy of `t03-reference.skp`, which `ThermalBridgeReferenceModel.build` made from `blank-template.skp` in a prep process: Zone A (5 x 4 x 3 m) and Zone B (4 x 4 x 3 m) side by side, Zone W (2 x 2 x 2 m) in a Group turned 30 degrees, the five reference types, a Window Unit on Zone A's south wall, a line at the Model root |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal (Assemblies, Zones, Windows, Spaces, ThermalBridges) |
| Controls | Bridge for setup (edit path and native selection, the split) and every public call and readback; System Events for native Undo (Cmd+Z) and Redo (Cmd+Shift+Z), and the Edit menu's Undo item read |
| Readback | `ThermalBridgeAssignmentWalkthrough.selection` through `edges.selection`, and `types.all`, one bridge call each |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Selection and assign | Zone A's three roof Edges read with their Zone and no assignment; `edges.assign` Parapet committed; all three read Parapet, quantity 1 | `1-*.json` |
| Native Undo and Redo | One Cmd+Z removed all three assignments; one Cmd+Shift+Z restored them | `2-undo.json`, `2-redo.json` |
| Zone under a turned wrapper | Zone W's four roof Edges, paths through the wrapper: assign, one Undo, one Redo, as above | `3-*.json` |
| Refusals | The Edge inside the Window Unit reads `cutting_instance`; the explicit reference refuses `target.wrong_kind`, nothing written. The root line reads `outside_zone` | `4-*.json` |
| Delete with replacement | Footing deleted with Slab edge as replacement: the type is gone and Zone B's three ground Edges name Slab edge. One native Undo restored the type and all three Edges | `5-*.json`, `5-undo-walk.txt` |
| Split | Zone A's assigned west roof Edge split at its middle: both 2.0 m pieces carry Parapet and one `tbe_` id and read `copied`; nothing re-issued | `6-*.json` |
| Save and reopen | A fresh process on `t03-saved.skp` reads every assigned group with the same types, the split piece still `copied`, and the five types | `7-reopen-read.txt` |

## Host facts recorded here

- Setting `Model#active_path` to open a Group is an Undo entry of its own ("Open"). A native Undo right after a
  script opens a context undoes the Open, not the action before it. The case read the Edit menu's Undo item and
  stepped past those entries before undoing the delete.
- Inside an open context, `Vertex#position` answers world coordinates. The reference-model helper reads Edge
  positions to name sides, so it must be called with the edit path closed; the next stage fixes the helper.

## Limits

- Delete with replacement was proven on the host for Edges in a direct Zone; the wrapped-Zone rewrite is offline
  only (`test_delete_with_a_replacement_rewrites_direct_and_nested_edges_in_one_undo_step`).
- The split is `Edge#split` in a model operation, the call T01 measured native Divide to match; no native Divide
  was repeated here.
- Delete with replacement locates each Edge with a per-step persistent-id scan, as Assembly retarget does. P3b-04
  measures assign and schedule cost at 5,000 assigned Edges.
