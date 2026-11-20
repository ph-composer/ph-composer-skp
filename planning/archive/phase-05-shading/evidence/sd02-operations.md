# SD02: Shading mark operations on the host

DATE: 2026-11-19
HEAD: `0f14c44d` (PR #528, branch `feat/shading-p5s-02`), installed `dist/ph_composer.rbz`, SketchUp 2026, a
fresh process on a script-built fixture. Raw outputs, the driver and the fixture are in
`_private/host/sd02-20261119/` (gitignored).

Control: the development bridge called `PhComposer::API.invoke` and `query` on `ph_composer.shading.*` with the
panel never opened; native Undo and Redo were Edit-menu clicks through System Events. No viewport click or
context menu was needed.

| Assertion | Result |
| --- | --- |
| Assign and clear, one Undo step each | One assign over ten targets (loose Faces, a Face and a Group inside Zone A, a root Group, three root placements, a placement nested in a Group) committed as "Set as Shading"; native Undo removed all ten marks and Redo restored them. Clear of a nested placement, a Face and a nested Group was "Clear Shading", undone and redone the same way |
| Unchanged | Assign on two marked targets completed with effect `none`, both listed as unchanged |
| Refusals | Each alone refused with its code and wrote nothing: a Face behind shared storage `target.shared_definition`; a classified Zone Face `shading.face_classified`; a Zone and a Group holding one `shading.zone_target`; a Space, its Volume and its Floor Segment `target.wrong_kind`; a cutting component and its Face `shading.cutting_component`; a locked Group and its Face `target.locked`; an Edge `target.wrong_kind`; clear of a Face shading through "Neighbour" `shading.inherited`, naming it |
| Mixed selection | `shading.selection` over a spare Face, a marked Face, a cutting component and an Edge gave assigned, unchanged and left out, the Edge ignored; assign with those references marked the spare Face only |
| Stale revision | Refused `revision.stale`, nothing written |
| List | Five components with the reference model's counts and areas: "Shading" 3 (5.0 m2), "Zone A Shading" 1 (5.0), "Fin" 2 (6.0), "Neighbour" 6 (83.0), the Louvre component 6 (1.2) |

Limits of this run:

- The Window Unit row was covered by a cutting component, which every Window Unit is; no real Unit was placed.
- The Louvre component read "Louvre#2": earlier setup retries in the build left unused "Louvre" definitions,
  so SketchUp suffixed the new one. The name follows the definition name as the rule says.

## Rerun, 2026-11-20

Rerun on `main` at `906a102c` from the installed RBZ, same fixture and calls, panel closed
(`_private/host/batch-20261119/sd02/SD02/`). Every result matched the 2026-11-19 run: ten targets assigned in one
step, Undo and Redo of assign and clear, the unchanged and inherited rows, all twelve refusal rows, the mixed
selection, the stale revision and the five-component list. Recorded `pass`.
