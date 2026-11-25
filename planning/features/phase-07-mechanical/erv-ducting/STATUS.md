# ERV ducting: status

DATE: 2026-10-21
STATUS: Scoped. Interviewed 2026-11-23 (D4-37, Q1–Q9 all as recommended); planned in full 2026-11-24 as P4-14a to P4-14f ([P4-14](../phases/p4-14-erv-ducting.md)). In progress: P4-14a, the ducting feature and Duct Types, in review (#581).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

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
[phase ledger](../STATUS.md), planned in full on 2026-11-24 as six sub-stages, P4-14a to P4-14f; Phase 3b's
edge stages merged on 2026-10-26.

## Next step

P4-14a in review (#581); then P4-14b once Ed has answered the shared line-group layer ([P4-14](../phases/p4-14-erv-ducting.md),
"Inferred in planning").

## Blockers

- The Ventilator record in the equipment packet. Its family was interviewed on 2026-10-21 (V1 to
  V6); stages P4-02 to P4-04 build it.
- None from Phase 3b: its edge stages are on `main`; see hot-water-piping's STATUS. P3b-04's chain
  rule is not needed here.
- None from the edge identity spike: it passed on 2026-09-18 ([B4](../../../archive/phase-00-foundation/evidence/spike-edge.md));
  its open cases closed in P3b-01 (T01).

## Verification

P4-14a offline: [p4-14a-duct-types](../evidence/p4-14a-duct-types.md). No host evidence yet; the host cases run in MS3.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted. |
| 2026-10-21 | Phase 4 planned in detail; this packet's stage is a gate stub in the phase ledger. |
| 2026-10-21 | Re-baselined against `main` at `420c783a`: foundation and remote blockers removed, Phase 3b dependencies named, metre conversion and records corrected, Q9 added. No interview, no implementation. |
| 2026-10-26 | Phase 3b P3b-09 handoff: the edge tagging rules point at `context/TECH_STACK.md`, the edge stages are on `main`, and the edge registry question (D3b-01) is this packet's. |
| 2026-11-22 | Phase reviewed after Phase 6 Programs: the stale Phase 3b gate wording and the "Equipment is not interviewed" blocker corrected. No interview, no implementation. |
| 2026-11-24 | Planned in full as P4-14a to P4-14f from D4-37 and this PRD; register rows M14a to M14f. Two inferences for Ed: the shared line-group layer and how a run quantity exports. No implementation. |
| 2026-11-25 | P4-14a implemented on `feat/phase-07-mechanical-p4-14` and in review (#581): the `ph_composer.ducting` feature and the Duct Type kind, panel closed; host case `M14a` owed to MS3. |
