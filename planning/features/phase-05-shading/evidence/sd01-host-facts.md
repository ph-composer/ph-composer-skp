# P5s-01 evidence: Shading mark host facts (SD01)

DATE: 2026-11-19
STATUS: Host run on branch `feat/shading-p5s-01` at `2a9c5e17`, SketchUp 26.1.188, Ruby 3.2.2, macOS. Eight of ten gestures recorded; Move-copy array and push-pull blocked, owed to a later hold.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Register row [SD01](../ACCEPTANCE.md). Offline half: `tests/shading_mark_store_test.rb` and the code reads
behind [CONTRACTS](../CONTRACTS.md) sections 4 and 7. Host half: recorded through
`tools/hostkit/acceptance_case.py` in `_private/host/sd01-20261119/SD01/` (gitignored; synthetic fixture, no
project data). The ledger row records a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `2a9c5e17`, SHA-256 `83bdd81f8a3a5952d4e03e1c8ecc5bd41648ce5b19832789703dc93b4797d700` |
| Fixture | `sd01.skp`, SHA-256 `62ba98b0...`, built by `ShadingSpike.setup` (development eval, labelled) in a copy of the blank template with its scale figure erased |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document |
| Controls | Bridge for selection, scans and saved copies; System Events for the Edit-menu gestures, Cmd+C and Cmd+X, and Edit > Undo and Redo by menu item |
| Readback | `ShadingSpike.scan` after every step: per island, every marked entity (kind, persistent id, root path, raw mark, definition and placement count) and the count of Shading Face occurrences |

The recorder was checked against what `setup` built by its own bookkeeping (counts by construction and the
marked persistent ids): all twelve islands read "ok" in the build process and on the reopened fixture, and an
added unmarked placement read as expected.

## The mark (`ph_composer.shading`) under native edits

Every gesture below was one native operation (two for cut and paste). In every case native Undo restored the
baseline scan exactly, Redo matched the gesture's scan, the copy saved after Redo reopened in a fresh process
with the same scan, and a final Undo returned the baseline.

| Gesture | Observed |
| --- | --- |
| Copy, Edit > Paste In Place | The pasted Group and ComponentInstance carry the mark on new persistent ids and share storage with the originals (two placements of one definition). The pasted loose Face merged with the original: one Face remains, on a new persistent id, carrying the mark |
| Cut, Edit > Paste In Place | All three targets return on new persistent ids, each with its mark; nothing gained or lost |
| Make Group (Face, its Edges, the marked Group and instance) | The new Group carries no mark; each mark stays on its own entity, same persistent id, now inside it |
| Make Component (same selection) | The new definition and instance carry no mark; each mark stays on its own entity inside it |
| Make Unique on one of two placements | The instance keeps its persistent id and mark and moves to a new definition; that definition's copy of the one marked definition Face carries the mark on a new persistent id; the other placement keeps the original definition and its marked Face |
| Divide of a bounding Edge, 2 segments | The marked Face keeps its persistent id, mark, area and single loop. The scan reads Faces and containers only, so it equals the baseline at every step; the Edit menu read "Undo Divide Edges" after the gesture |
| Intersect Faces > With Model across the Face | The marked Face splits in two: the original persistent id on one half, a new one on the other, both carrying the mark |
| Explode of the marked Group | The Group and its mark are gone; its Faces become loose and unmarked (10 to 3 Shading Faces on the island) |
| Move-copy array | Not run (blocked: needs a full-screen hold) |
| Push-pull | Not run (blocked: needs a full-screen hold) |

A mark on a Face inside a definition placed twice is read once per placement (the `shared` island): each
marked definition Face gives two Shading Face occurrences, four for the island's two Faces.

## Visibility and loops (CONTRACTS questions 4 and 5)

The holed Face reports two loops with the outer loop first, and the export snapshot captures both. A hidden
Face and a Face on a hidden tag are both in the export snapshot.

## Notes from the run

- The recipe placed the copy with a viewport click; the conductor used Paste In Place instead, which is what
  produced the loose-Face merge.
- A first Divide attempt opened the wrong submenu; its scans are kept apart and are not evidence.
