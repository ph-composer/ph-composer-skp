# Brand and public documentation: status

DATE: 2026-11-25
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft; open one when Ed authorizes the first stage)

## Current state

- Brand direction chosen on 2026-11-25: BR-D1 to BR-D12 in [DECISIONS.md](DECISIONS.md).
- Plan drafted the same day: BR-01 to BR-09 in [PLAN.md](PLAN.md).
- The mark generator and the canvas source are saved under [mockups/](mockups/README.md).
- Nothing is implemented. No shipped file has changed.

## Next step

Ed answers the four questions at the end of [PLAN.md](PLAN.md#what-ed-needs-to-decide-before-br-01)
and authorizes BR-01.

## Stages

| Stage | Title | State |
| --- | --- | --- |
| BR-01 | Asset kit | Scoped |
| BR-02 | Icons in SketchUp | Scoped |
| BR-03 | Panel recolour | Scoped |
| BR-04 | Design System update | Scoped |
| BR-05 | Site scaffold and landing page | Scoped |
| BR-06 | Beta documentation set | Scoped |
| BR-07 | Full documentation suite | Requested |
| BR-08 | Links from PH-Tools | Scoped |
| BR-09 | Video tutorial | Requested |

## Verification so far

- `lift_mark.py` passes `ruff check` and `ruff format --check`, and its output was rendered and
  compared by eye with the boards.
- The canvas boards were checked as rendered marks, not as assembled boards, during the session.
- The in-app boards are mock-ups. No colour or icon has been tried in SketchUp.

## Blockers

None. The open questions in [DECISIONS.md](DECISIONS.md#open) gate individual stages, as PLAN.md
notes under each.
