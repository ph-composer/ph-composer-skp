# P3b-07 evidence: the edge tool (T07)

DATE: 2026-10-26
STATUS: Host gate run with Ed at the mouse on branch `feature/thermal-bridges-p3b-07` at `a0a765a6` (PR #313), SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1. All eleven assertions pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T07](../ACCEPTANCE.md). Offline half: `tests/thermal_bridge_edge_tool_test.rb` (21 runs: one
`edges.assign` per gesture with the type, quantity and colour frozen at button-down; Escape, deactivation,
suspension, a non-Escape cancel, a raised callback, a lost release, a Model switch and an edit-path change each
writing nothing; the limit plus one; the root and component refusals on the status bar and in the notice; a stale
revision; a deleted type; hover without a Model walk; the drawing; the view commands and the Colour-by lease; the
menu items, their separator and labels), the edge tool cases in `tests/thermal_bridges_panel_test.js`, and the armed
bar at the three panel sizes in `tools/ui-preview/thermal_bridges_checks.cjs`; `make ci` green at `a0a765a6`.
Review (ordinary, UI): one pre-gate Sonnet read (nine items, fixed before the PR) and two Codex gpt-6.1-sol cycles
on PR #313 (cycle 1: 1 P2, a type name holding "|" lost from the menu's dropdown; cycle 2: 1 P2, a generated label
that could repeat a real name; both fixed). Host half: recorded through `tools/hostkit/acceptance_case.py` in
`_private/host/t07/T07/` (gitignored; synthetic fixture, no project data). The ledger row records a branch commit,
not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `a0a765a6`, SHA-256 `3a531ea22f8cf7c029f351470d0f23361da3515292a1270a1e2708d2cc33b74d` |
| Fixture | `_private/host/t07/T07/t07.skp` (SHA-256 `5ddd125b`), a copy of the T04 reference base: Zones A, B and W, five types, a Window Unit on Zone A's south wall, a line at the Model root, every Face classified, nothing assigned |
| Measurement Model | A copy of `_private/host/t06/measure.skp`: 50,040 Edges, 5,000 assigned |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal; the measurement in its own fresh process |
| Controls | Ed at the mouse for every gesture, panel click and Edit menu read; the bridge for setup, two labelled bridge items (the mid-drag type change and the raised callback) and readbacks in their own calls |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Hover highlight | Armed with Parapet from the bar: the hovered roof Edge draws thick in Parapet's colour with "Assign Parapet"; the root line draws red with "That Edge cannot take a thermal bridge: it is not inside a Zone." The button stays pressed with focus in SketchUp | `2-hover-*.webp` |
| Click, one Undo each | Three clicks, "Assigned Parapet to 1 Edge." each; Edit read "Undo Assign Thermal Bridge"; one Undo cleared only the last | `3-readback.json`, `3-edit-menu-ed.webp` |
| Drag, one Undo | One drag over Zone B's three roof Edges: "Assigned Parapet to 3 Edges."; one Undo cleared all three | `4-readback.json` |
| Type change mid-drag | The bridge re-armed the tool with Slab edge 2 s into a held gesture; the release wrote Parapet on both Edges, and the tool kept Slab edge for the next | `5-readback.json` |
| Escape mid-drag | "The edge tool gesture was cancelled. Nothing was written."; no revision; the tool ended, Colour by off as before, the panel released | `6-readback.json` |
| Model switch | File > New with the tool running: the untitled Model's session has its own unarmed tool; back in t07 the tool was still armed and its next click wrote | `8-sessions.json` |
| Raised callback | A labelled fault made the highlight raise once inside the tool's `draw` rescue: "The edge tool could not complete that. Nothing was written." (error); diagnostics logged `edge_tool` failed at `edge_tool.rb:169 draw`; nothing written; restored | `9-diagnostics.json` |
| Refusals | The root line ("it is not inside a Zone") and the Window Unit's edge ("a cutting component holds it"), each with "Nothing was written." on the status bar and as a warning notice | `7-*.webp` |
| Gesture limit | A drag along 300 dense Edges: "One command changes at most 250 Edges; this one has 251. Nothing was written."; shorter drags of 7 and 83 Edges each assigned | `10-readback.json` |
| Stop gives the mode back | Stop ended the tool into the Select tool and Colour by went back to off | `12-readback.json` |
| Cost | See below | `11-assign-cost.json`, `13-hover-cost.json` |

## Cost (step 4)

| Measure | Value |
| --- | --- |
| One `edges.assign` at the limit, 250 Edges, committed | 184.9 ms |
| 251 Edges, refused as `gesture.too_large` before any resolution | 11.2 ms |
| Per newly hovered Edge, `zones.containment` read cold, 7,506-entity Zone on the 50,040-Edge Model (200 Edges) | median 1.29 ms, p95 3.69 ms, max 7.67 ms |

The per-path containment read stays inside a frame on the largest Zone measured, so the tool keeps it uncached
beyond one revision and edit context. The 250 ceiling (D3b-14) holds: a gesture at it commits in under 200 ms.

## Host facts recorded here

- A Window Unit is a cutting component, so an Edge inside it refuses with Zones' `cutting_instance` reason before
  any write refusal is read; the offline fixture's plain component refuses as shared storage instead.
- The kit styles a pressed text button only on hover and focus. On the host the arm button lost its pressed look as
  soon as focus moved to SketchUp (run 1); the feature stylesheet now marks it at rest. A kit-level at-rest
  pressed style for text buttons is a follow-up.

## Limits

- A release after a Model switch in the middle of a gesture is covered offline only; the native switch was made
  with the tool armed between gestures.
- The mid-drag type change and the raised callback are bridge items standing in for a panel change and a defect;
  both are labelled in the run's `steps.md`.
- No custom cursor; the tool shows its state on the pressed button and the status bar.
