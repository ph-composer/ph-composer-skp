# SketchUp 2023 floor verification: status

DATE: 2026-09-30
STATUS: Requested
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## State

Carried out of Phase 1 as a separate gate on 2026-09-30. Offline Ruby 2.7.2 and Chromium 88
checks pass in `make ci`; no 2023 host run exists.

## Next step

Secure a SketchUp 2023 host, then run the acceptance shape in the PRD.

## Blockers

A 2023 host (Q2).

## Verification

None on a 2023 host.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-30 | Packet created from the Phase 1 separate-gate list. |
| 2026-11-17 | Carried from the Climate phase (Ed's answer E3; he tests on SketchUp 2026 only for now): with a second supported version installed, write a preference with `Sketchup.write_default` in one version and read it in the other, and confirm a climate data folder added in one version is listed in the other. See the Climate [PLAN](../../../archive/phase-04-climate/PLAN.md#deferred-out-of-this-packet). |
