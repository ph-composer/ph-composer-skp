# AW03 inventory and candidate reads, 2026-11-10

Case `AW03` (agent-workflows stage AW-03, acceptance A06 of
[the packet](../../archive/agent-workflows-2026-11/ACCEPTANCE.md)). Run on branch
`feat/agent-workflows-aw-07` at `0d5cd927` (PR #446, squash-merged to main as `009b5915` with identical source, which contains AW-03 as merged in #442), installed RBZ built from
that head (SHA-256 `ad70209a6f95…`), SketchUp 26.1.188, Ruby 3.2.2, macOS. Fresh process on a fresh copy of the blank
template; synthetic data only.

Control: an MCP client outside SketchUp over HTTP to the real loopback listener (127.0.0.1:46110) with a read, view
and model_write token; native Edit > Undo and Redo through the SketchUp menu bar. Development eval only for the
labelled setup: the token, the fixture geometry (a root Group, a loose Face, and a wrapper turned 30 degrees and moved
10 m holding a Group and a Face) and an oracle of `Sketchup::InstancePath` world coordinates. Raw step output is in
the gitignored run folder.

| Assertion | Result |
| --- | --- |
| reads-no-side-effects | Children, Make Zone candidates, first-Space candidate Faces and thermal Edge candidates read at the root and in the wrapper with nothing selected; revision, selection and edit path unchanged |
| make-zone-root-and-wrapper | Root Group: no refusal, no open needed, Make Zone commits. Nested Group: open required; refused `target.edit_path_changed` until `context.open`, then commits |
| first-space-in-wrapper | The wrapper floor's path and world loop match the InstancePath oracle (12.0 m2); Space create commits with nothing left out |
| edge-assign-readback-clear | 12 unassigned Edges with Zone-qualified references and world end points equal to the oracle; assign, read back by path, clear and reread |
| stale-cursor-and-reference | An earlier cursor refuses `query.cursor_expired`; the pre-assign reference refuses `target.changed` |
| native-undo-redo | Native Undo of the clear brings the same assignment id and values back; Redo clears it again |
| replies-within-budget | 39 tool results, largest 15,600 bytes, all within 24,576 |

Limitations: the client's first attempt stopped on a driver bug before any write and was rerun in the same process.
Background menu control reported Undo disabled, so the menu was clicked through System Events with SketchUp fronted.
The conversion and recovery inputs A06 names are covered offline (`window_convert_review_test`,
`window_unit_actions_test`). Windows and SketchUp 2023 were not exercised.
