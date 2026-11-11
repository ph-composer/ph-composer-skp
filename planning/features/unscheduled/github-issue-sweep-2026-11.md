# GitHub open-issue sweep, November 2026

DATE: 2026-11-11
STATUS: In progress
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: one per row below

Ed authorized delivery of the open repository issues through `pr-loop` on 2026-11-11: one branch
and one PR per issue, Codex review, merge on green CI once review threads are answered, and new
issues for items found along the way. Stale issues were reviewed and refined first. Each stage runs
as a fresh subagent from one conductor session; host steps that need native control run in one
batched host pass at the end.

## Decisions (Ed, 2026-11-11)

- #318 (byte-stable HBJSON): deferred, not in this sweep.
- #455 AW-02: cap identifier length at registration so one row fits the 24 KiB reply budget.
- #455 AW-07: `edges.clear` and Thermal Bridge Type delete proceed past unreadable entries and
  report them instead of refusing.
- #145: write the side-by-side design evidence now; no refactor.
- Host steps: one batched host pass after the code PRs, with SketchUp access requested once.

## Triage of the issues not in the queue

- #154: F1 and F2 merged through PR #289; only the HtmlDialog re-measure remains (host pass).
- #318: deferred by Ed.
- #458: a menu of optional slices, selected when a workflow needs one.

## Queue

| Order | Issue | Scope | State |
| --- | --- | --- | --- |
| 1 | [#437](https://github.com/ph-composer/ph-composer-skp/issues/437) | Convert to Window Type and Repair split Face identities not offered on Floor Segment Faces | Implemented on branch, PR #460 |
| 2 | [#332](https://github.com/ph-composer/ph-composer-skp/issues/332) | Libraries sidebar loading state and Cancel for a hosted load | Scoped |
| 3 | [#456](https://github.com/ph-composer/ph-composer-skp/issues/456) | Agent guide gaps; Connect writes Codex approval; per-profile contact tracking | Scoped |
| 4 | [#457](https://github.com/ph-composer/ph-composer-skp/issues/457) | Hostkit quit rebind; JS runner count guard; pushpull decision | Scoped |
| 5 | [#455](https://github.com/ph-composer/ph-composer-skp/issues/455) | Agent access code items: idempotency release, AW-01 lock, AW-07, AW-04, AW-02 | Scoped |
| 6 | [#455](https://github.com/ph-composer/ph-composer-skp/issues/455) | Review debt: one Codex review of the AW-05, AW-07, AW-08 and #453 last fixes | Scoped |
| 7 | [#317](https://github.com/ph-composer/ph-composer-skp/issues/317) | Export Faces section: index Zone ownership once per export | Scoped |
| 8 | [#438](https://github.com/ph-composer/ph-composer-skp/issues/438) | Model modified after save while a Space is open (bridge repro first) | Scoped |
| 9 | [#145](https://github.com/ph-composer/ph-composer-skp/issues/145) | Duplicate-identity design evidence (docs only) | Scoped |
| 10 | host pass | #154 HtmlDialog re-measure; #455 Rotate/Scale and `onActivePathChanged`; native checks the stages left | Scoped |
