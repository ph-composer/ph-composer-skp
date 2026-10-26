# P3b-01 evidence: edge host facts (T01)

DATE: 2026-10-21
STATUS: Host gate run on branch `feature/thermal-bridges-p3b-01` at `bec31a4c` (PR #302), SketchUp 26.1.188, Ruby 3.2.2, macOS. Reopen results below.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T01](../ACCEPTANCE.md). Offline half: `tests/edge_record_contract_test.rb` (2 runs, 17
assertions on Ruby 3.2.2 and 2.7.2), `make lint-citations` with planted `T01` and `F26` refused,
`make ci` green at `bec31a4c`; the architecture review ran as two Codex gpt-6-astra cycles on PR #302
(all six findings fixed). Host half: the five cases B4 left open, recorded through
`tools/hostkit/acceptance_case.py` in `_private/host/t01/T01/` (gitignored; synthetic fixture, no
project data). The ledger row records a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `bec31a4c`, SHA-256 `530cc87a75ee57b5f6cf7276e2703425d6c8e963d374f41326e2f4ce88324bb6`, 24,312,689 bytes installed |
| Fixture | `_private/host/t01/T01/t01.skp`, a fresh copy of `blank-template.skp`; the B4 fixture built in it by `EdgeSpike.setup` (development eval, labelled) |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal (Assemblies, Zones, Windows, Spaces) |
| Controls | Bridge for scripted operations and every readback; System Events for native Undo and Redo (Edit menu items, Cmd+Z); the native computer-use controller, full-screen, for the two context-menu commands |
| Readback | `EdgeSpike.scan` per step: per assignment, each edge's persistent id, world endpoints, length, face count and full dictionary |

## Results

Baseline: the south base edge `asg_wall_base` is pid 48889 from (5000, 0, 0) to (0, 0, 0); the south-west
corner `asg_wall_corner` is pid 48905; `asg_run` is pids 48914, 48917, 48919.

| Case | Step | Observed | Scan |
| --- | --- | --- | --- |
| Crossing, then heal, same record | A line drawn up the south wall from (2500, 0, 0) | Base edge split: 48889 keeps (5000..2500), new pid 48939 takes (2500..0); both halves carry the full dictionary | `heal-same-1-crossing.json` |
| | Erase the crossing line | Healed: one edge, pid 48889, (5000..0), full dictionary; the scan equals the baseline exactly | `heal-same-2-heal.json` |
| | Native Undo, Redo | Undo restores the two halves (same pids); Redo heals again; two more Undos return the baseline scan | `heal-same-3-undo-heal.json`, `-4-redo-heal.json`, `-5-back.json` |
| Crossing, retag one half, heal | Retag the east half (pid 48889) as `asg_wall_base_b` | Two records on two halves | `heal-diff-2-retag.json` |
| | Erase the crossing line | Healed into pid 48889 with the `asg_wall_base_b` dictionary whole; the `asg_wall_base` record on the west half is gone, silently | `heal-diff-3-heal.json` |
| | Native Undo, Redo | Undo restores both halves and both records; Redo loses the west record again; three Undos return the baseline | `heal-diff-4-undo-heal.json`, `-5-redo-heal.json`, `-6-back.json` |
| `intersect_with` | A blade face in its own Group intersected into the zone's entities, Group erased | Base edge split at (2500, 0, 0): 48889 and new pid 48964, both with the full dictionary; the corner edge untouched | `intersect-1-intersect.json` |
| | Native Undo, Redo | Undo restores the baseline scan; Redo splits again; Undo returns the baseline | `intersect-2-undo.json`, `-3-redo.json`, `-4-back.json` |
| Push-pull that deletes the edge | Roof pushed down 3000 mm onto the floor | Base and corner records both `lost`: the edges are gone with their dictionaries; the loose lines, the run and the component edges are unchanged | `collapse-1-collapse.json` |
| | Native Undo, Redo | Undo restores the baseline scan, ids and dictionaries included; Redo removes them again; Undo returns the baseline | `collapse-2-undo.json`, `-3-redo.json`, `-4-back.json` |
| Native Divide, 2 segments | Context menu on the base edge inside the open Group | Split like `Edge#split`: 48889 keeps (5000..2500), new pid 48965 takes (2500..0), both with the full dictionary | `divide-1-divide.json` |
| | Native Undo, Redo | Edit > Undo Divide Edges restores one edge 48889 (5000..0); Redo splits again | `divide-2-undo.json`, `-3-redo.json` |
| Native Weld Edges | Context menu on the selected three-edge chain | Pids 48914, 48917, 48919 and their dictionaries unchanged; the three edges now share one `Sketchup::Curve` of 3 edges | `weld-1-weld.json` |
| | Native Undo, Redo | Undo: no curve, same pids and dictionaries; Redo: the curve is back | `weld-2-undo.json`, `-3-redo.json` |
| Unwind | Five Edit > Undo steps after the Weld copy | The scan equals the baseline after "Undo Divide Edges" | `unwind-1.json` to `unwind-5.json` |

## Reopen

Each saved copy opened in a fresh process (`t01-reopen.sh`), the spike loaded, the scan compared with the scan
taken before `save_copy`; `reopen-summary.txt` holds the six comparisons.

| Copy | State saved | Reopen equals the pre-save scan |
| --- | --- | --- |
| `heal-same.skp` | healed, one edge 48889 | yes |
| `heal-diff.skp` | healed into 48889 with the `_b` record, the other lost | yes |
| `intersect.skp` | base edge split 48889 and 48964 | yes |
| `collapse.skp` | base and corner edges gone | yes |
| `divide.skp` | base edge split 48889 and 48965 | yes |
| `weld.skp` | three edges in one Curve | yes; the Curve of 3 edges is there after reopen (`weld-reopen-curve.json`) |

## Consequences folded

- `context/SKETCHUP_HOST_BEHAVIOR.md`, "Components, glue and edge attributes": the five results as one table.
- [DECISIONS](../DECISIONS.md) D3b-22's answer row carries the heal consequence for D3b-01: a heal across
  two differing records keeps the one on the edge that kept the original persistent id and drops the other
  without notice. The edge stays the record; nothing points at the lost one, so no repair exists.
- Nothing in the results changes a binding: every split route multiplies the dictionary (B4 holds), a
  deleted edge takes its record away, and Undo, Redo and reopen need no feature code.

## Limits

- The spike's tags are synthetic dictionaries, not the thermal-bridge record; the record engine's
  behaviour on the host is P3b-03's gate.
- One stray Undo: after typing the segment count, the first Cmd+Z undid a "Close" entry rather than the
  Divide; the Divide's Undo and Redo were then driven through the Edit menu items by name. Recorded, not a
  product fact.
- Measured on 26.1.188 on macOS only; SketchUp 2023 and Windows remain their own gates.
- The ledger row (`planning/native-acceptance/results.jsonl`, T01) was recorded against the baseline captured
  at `begin`, before the host facts were folded into `context/SKETCHUP_HOST_BEHAVIOR.md`. That document is the
  case's output, not an input, so the case's dependency list in `cases.json` was narrowed to the spike, the
  entity store and the test; the ledger's rule for a narrowed list keeps the row current.
