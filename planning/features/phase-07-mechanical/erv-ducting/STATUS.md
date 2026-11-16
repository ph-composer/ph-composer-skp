# ERV ducting: status

DATE: 2026-10-21
STATUS: Requested
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## State

PRD drafted 2026-09-18 from Ed's brief (build duct-types, draw ducts, select edge, assign
duct-type), the predecessor's `planning/phases/M2_ducting.md`, honeybee-ph's `ducting.py` and
`ventilation.py`, and PHX's METr writer. Not interviewed.

Re-baselined on 2026-10-21 against `main` at `420c783a`, alongside hot-water-piping. Changes of
substance: `PhDuctSegment` lengths are metres, so the translation converts from the records'
`_mm`; records lose their timestamps and gain `color`; the Ventilator row's duct lengths come
from a ducting contribution, not from equipment naming ducting (Q9); acceptance is an HBJSON
reload, METr rows go to metr-export. honeybee-ph fields re-read at the pinned 1.33.65.

This packet's stage is [P4-14](../phases/p4-14-erv-ducting.md) in the
[phase ledger](../STATUS.md), a gate stub until Phase 3b's edge stages merge and this interview runs.

## Next step

Interview, after hot-water-piping, since most draw and assign answers carry over, and after
equipment's Ventilators family, which this packet exports into.

## Blockers

- The Ventilator record in the equipment packet. Equipment is not interviewed.
- None from Phase 3b: its edge stages are on `main`; see hot-water-piping's STATUS. P3b-04's chain
  rule is not needed here.
- None from the edge identity spike: it passed on 2026-09-18 ([B4](../../../archive/phase-00-foundation/evidence/spike-edge.md));
  its open cases closed in P3b-01 (T01).

## Verification

None. Nothing is implemented.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted. |
| 2026-10-21 | Phase 4 planned in detail; this packet's stage is a gate stub in the phase ledger. |
| 2026-10-21 | Re-baselined against `main` at `420c783a`: foundation and remote blockers removed, Phase 3b dependencies named, metre conversion and records corrected, Q9 added. No interview, no implementation. |
| 2026-10-26 | Phase 3b P3b-09 handoff: the edge tagging rules point at `context/TECH_STACK.md`, the edge stages are on `main`, and the edge registry question (D3b-01) is this packet's. |
