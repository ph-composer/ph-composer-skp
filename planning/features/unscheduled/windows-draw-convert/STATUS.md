# Windows draw-then-convert: stage ledger

DATE: 2026-11-09
STATUS: In progress; S21-1 on branch, S21-2 and S21-3 to follow.
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/363

Plan: [PLAN.md](PLAN.md). States: `Scoped` · `In progress` · `Implemented on branch` · `Merged to main` · `Blocked` · `Deferred`.

| Stage | State | PR | Evidence |
| --- | --- | --- | --- |
| S21-1 | Implemented on branch | [#406](https://github.com/ph-composer/ph-composer-skp/pull/406) | `make ci` green. New: `tests/window_convert_rectangles_test.rb` (9), `tests/window_convert_review_test.rb` (26). Host read on SketchUp 2026 through the bridge, `07_Export_Test.skp`, in an aborted operation: a rectangle drawn on a Zone wall (hole in the host) answers one group with `entity_path` the wall and its size in `columns_m`, `rows_m`; a coplanar rectangle at the Model root answers the same host; a rectangle drawn from the floor line is left out as `window.convert_on_boundary`; one over a Window already placed is left out as `window.overlap`. Model unmodified after. |
| S21-2 | Scoped | | |
| S21-3 | Scoped | | |
