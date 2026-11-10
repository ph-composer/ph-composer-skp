# AW01 target safety, 2026-11-10

Case `AW01` (agent-workflows stage AW-01, acceptance A01-A04 of
[the packet](../../features/unscheduled/agent-workflows-2026-11/ACCEPTANCE.md)). Branch
`feat/agent-workflows-aw-01` at `c3d6d174` (PR #440), installed RBZ built from that head, SketchUp 26.1.188,
Ruby 3.2.2, macOS. Fresh process on a fresh copy of the blank template; synthetic data only.

Control: public operations through the development bridge for every product write and read; native Edit menu
Undo/Redo through System Events; development eval only for labelled fixture setup (geometry, the synthetic
legacy Zone record on a Space Group, a copied Face record, a lock, a shared-storage Group copy). Raw step
output is in the gitignored run folder.

| Assertion | Result |
| --- | --- |
| a01-wrapper-refused | Make Zone on a plain wrapper holding a Space: no menu target; preview and invoke refuse `target.wrong_hierarchy`; revision unchanged; wrapper carries no Zone record, also after reopen |
| a01-legacy-guarded | Zone record on a Space Group reads `zone.ownership_conflict` in `zones.list` and export preflight (not blocking); `spaces.delete` and `spaces.remove` refuse `target.foreign_records` naming `ph_composer.zone` at the Group's path, preview and invoke; revision unchanged; both records kept through save and reopen |
| a02-stale-null-refused | After classify, the old null Face reference refuses `target.changed` for classify, reverse and assign_assembly, preview and invoke; revision and record unchanged |
| a02-copied-record-refused | A null reference to a Face holding a copied record refuses `target.changed` before any transaction; a shared-storage copy of a Zone refuses `zones.update` with `target.shared_definition` |
| a03-locked-zone-refused | A locked Zone refuses `zones.update`, `update_field` and `update_metadata` with `target.locked`, preview and invoke, no revision change; unlocked, the rename commits |
| a04-create-receipt | `spaces.create` with two joined Faces, a wall and a missing path answers the preview's `accepted` and `left_out` (`vertical`, `not_found`) and one Volume whose `faces` follow `floor_segment_ids` |
| native-undo-redo | Native Undo/Redo of Classify Faces, Edit Zone and Create Space, and Undo of Delete Space, restore the exact record ids and names; refused writes left no Undo entry |
| save-reopen | After save and a fresh-process reopen, the finding, legacy records, Face record ids, Zone names and all three Space ids read back unchanged |

Limitations: the legacy overlap and the copied Face record are synthetic development-eval data, as a Model made
before the Make Zone refusal would hold them. The Zone copy is a shared-storage Group copy without its own
record, so it exercises the shared-definition refusal rather than a duplicated Zone id. Windows, SketchUp 2023
and the panel UI were not exercised.
