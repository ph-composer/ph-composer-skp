# Windows draw-then-convert: stage ledger

DATE: 2026-11-09
STATUS: In progress; S21-1 merged, S21-2 on branch, S21-3 to follow.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/363

Plan: [PLAN.md](PLAN.md). States: `Scoped` · `In progress` · `Implemented on branch` · `Merged to main` · `Blocked` · `Deferred`.

| Stage | State | PR | Evidence |
| --- | --- | --- | --- |
| S21-1 | Merged to main | [#406](https://github.com/ph-composer/ph-composer-skp/pull/406) | `make ci` green. New: `tests/window_convert_rectangles_test.rb` (9), `tests/window_convert_review_test.rb` (26). Host read on SketchUp 2026 through the bridge, `07_Export_Test.skp`, in an aborted operation: a rectangle drawn on a Zone wall (hole in the host) answers one group with `entity_path` the wall and its size in `columns_m`, `rows_m`; a coplanar rectangle at the Model root answers the same host; a rectangle drawn from the floor line is left out as `window.convert_on_boundary`; one over a Window already placed is left out as `window.overlap`. Model unmodified after. |
| S21-2 | Implemented on branch | [#407](https://github.com/ph-composer/ph-composer-skp/pull/407) | `make ci` green. New: `ph_composer.windows.units.convert` (API 1.25), `tests/window_convert_test.rb` (17). Spike H1 and H3 recorded in `context/SKETCHUP_HOST_BEHAVIOR.md`. Host check on SketchUp 26.1.188 through the bridge, `07_Export_Test.skp`: two rectangles drawn inside Zone wall 20132 with `add_face` (both carrying the wall's Face record id), one reviewed and converted through the API: Type `Window 36.0 x 48.0` at 0.9144 by 1.2192 m, one Unit, wall kept its persistent id with its one healed hole gone and the other left. `Sketchup.undo` restored the rectangle and removed the Type, Unit and definition; `Sketchup.redo` converted again; the model ended unmodified. Native Rectangle tool and the Edit menu were not driven (Undo is disabled in the background). |
| S21-3 | Scoped | | |
