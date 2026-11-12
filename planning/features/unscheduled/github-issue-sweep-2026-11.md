# GitHub open-issue sweep, November 2026

DATE: 2026-11-11
STATUS: Code complete and host pass run 2026-11-11; #493 merged and host-checked 2026-11-12; LH1 Cancel and two #455 measurements remain (#492)
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

All merged PRs passed `make ci` locally and both remote CI jobs (Ruby 2.7.2, 3.2.2), with a posted
Codex review (gpt-6.1-sol; gpt-6-astra for #473) and every thread answered.

| Order | Issue | Scope | State |
| --- | --- | --- | --- |
| 1 | [#437](https://github.com/ph-composer/ph-composer-skp/issues/437) | Convert to Window Type and Repair split Face identities not offered on Floor Segment Faces | Merged to main, PR #460 (`e40462fe`) |
| 2 | [#332](https://github.com/ph-composer/ph-composer-skp/issues/332) | Libraries sidebar loading state and Cancel for a hosted load | Merged to main, PR #461 (`55ebbc00`) |
| 3 | [#456](https://github.com/ph-composer/ph-composer-skp/issues/456) | Agent guide gaps; Connect writes Codex approval; per-profile contact tracking | Merged to main, PR #462 (`7133b397`); token files saved before it need one reconnect |
| 4 | [#457](https://github.com/ph-composer/ph-composer-skp/issues/457) | Hostkit quit rebind; JS runner dropped results; pushpull | Merged to main, PR #463 (`78bc5749`); hostkit has no pushpull command, the host-behavior row is the guard |
| 5 | [#455](https://github.com/ph-composer/ph-composer-skp/issues/455) | Retry safety, AW-01 lock, AW-07 | Merged to main, PR #465 (`4e9f3174`) |
| 5b | [#455](https://github.com/ph-composer/ph-composer-skp/issues/455) | AW-04 deterministic preview ids, AW-02 1,024-byte identifier cap (API 1.45) | Merged to main, PR #473 (`8e3afe60`) |
| 6 | [#455](https://github.com/ph-composer/ph-composer-skp/issues/455) | Review debt over the AW-05, AW-07, AW-08, #453, #461 and #465 last fixes | Done; filed #470, #471, #472 |
| 7 | [#317](https://github.com/ph-composer/ph-composer-skp/issues/317) | Export Faces section: index Zone ownership once per export | Merged to main, PR #466 (`ebaf21c6`); offline 60.5 s to 0.53 s at 25,020 Faces |
| 8 | [#438](https://github.com/ph-composer/ph-composer-skp/issues/438) | Model modified after save while a Space is open | Closed, host behavior: a plain group shows the same `modified?` after save (`context/SKETCHUP_HOST_BEHAVIOR.md`, `onSaveModel`) |
| 9 | [#145](https://github.com/ph-composer/ph-composer-skp/issues/145) | Duplicate-identity design evidence | Merged to main, PR #469 (`8070bc47`); recommends keeping the three separate; open for Ed's decision |
| 10 | [#492](https://github.com/ph-composer/ph-composer-skp/issues/492) | Native checks listed below | Run 2026-11-11 on main `a9d38726`: #437, #474, #468, #486, #456 pass; #154 measured (fails 200 ms); #455 Rotate/Scale measured, guard filed as #493; LH1 partial |

## Issues found and delivered during the sweep

| Issue | Found in | Scope | State |
| --- | --- | --- | --- |
| [#464](https://github.com/ph-composer/ph-composer-skp/issues/464) | #465 | `edges.assign` onto non-object stored JSON | Merged to main, PR #475 (`816b6bf0`) |
| [#467](https://github.com/ph-composer/ph-composer-skp/issues/467) | #466 | Zones and Spaces export sections scan once per object | Merged to main, PR #485 (`c896708d`); offline 27.5 s to 36 ms at 600 Spaces |
| [#468](https://github.com/ph-composer/ph-composer-skp/issues/468) | #469 | Four copy-identity divergences | Merged to main, PR #487 (`d4fef321`); three fixed, one pinned |
| [#470](https://github.com/ph-composer/ph-composer-skp/issues/470) | review debt | CodexConfig escaped alias | Merged to main, PR #476 (`ba505dd2`) |
| [#471](https://github.com/ph-composer/ph-composer-skp/issues/471) | review debt | CodexConfig string in an array | Merged to main, PR #478 (`ffb8e8a3`) |
| [#472](https://github.com/ph-composer/ph-composer-skp/issues/472) | review debt | Library retry announces the old failure | Merged to main, PR #479 (`ad2e55fc`) |
| [#474](https://github.com/ph-composer/ph-composer-skp/issues/474) | #475 | Edge read paths and the readability rule | Merged to main, PR #480 (`9047adbf`) |
| [#477](https://github.com/ph-composer/ph-composer-skp/issues/477) | #476 | CodexConfig server defined only by an escaped name | Merged to main, PR #481 (`5e0ed136`) |
| [#486](https://github.com/ph-composer/ph-composer-skp/issues/486) | #487 | Spaces copy watcher Undo warnings | Merged to main, PR #488 (`f0672104`) |
| [#482](https://github.com/ph-composer/ph-composer-skp/issues/482) | #481 | CodexConfig: backslash in a literal-string key | Open; not chased. Three fixes in a row (#470, #471, #477) each surfaced the next scanner edge, so the better fix is one small TOML tokenizer for the subset CodexConfig reads, not another patch: #491 |
| [#489](https://github.com/ph-composer/ph-composer-skp/issues/489) | packet-end review of `fe3a8914` | CodexConfig: `#` comment in a multi-line array in an inline table | Open; folded into #491 |
| [#490](https://github.com/ph-composer/ph-composer-skp/issues/490) | packet-end review of `3682e7f3` | Copy left read only with no warning after Undo/Redo of the copy then Undo of the Move | Open; P4, older code, needs native Undo |
| [#491](https://github.com/ph-composer/ph-composer-skp/issues/491) | this ledger | CodexConfig: one TOML tokenizer for the subset it reads | Open; needs Ed's go-ahead |
| [#492](https://github.com/ph-composer/ph-composer-skp/issues/492) | this ledger | Host pass checklist | Open; needs Ed at the Mac |
| [#493](https://github.com/ph-composer/ph-composer-skp/issues/493) | host pass #492 | Mid-gesture guard for Scale and Rotate | Merged to main: Scale in PR #494 (`441b287a`, API 1.46), Rotate in PR #495 (`67c87df8`, API 1.47). Rotate reports tool state 0 through a turn, so writes refuse whenever the Rotate tool is selected. Host-checked 2026-11-12 on `650ba430`: refused idle and mid-turn, the turn still finished as "Undo Rotate", commit after Select |

Commits merged after their PR's second Codex cycle, covered by the packet-end review: `fe3a8914`
(#481) and `3682e7f3` (#487); that review filed #489 and #490. `169930bb` (#480) and `34b719d2` (#463) changed only a description
or a comment.

## Host pass

Offline tests are the acceptance for every merged row; these native checks remain, tracked with the #486 recipe in #492.

- #437: right-click a Floor Segment Face and an open Space's root; neither item is offered.
- #332, #472: case LH1 (#331) with a hosted Library: loading state, Cancel, Refresh retry announces loading.
- #456: Agent Access dialog shows each profile's own client name when two profiles share a token.
- #474: the edge tool on an Edge with unreadable text: red, refusal tooltip, click refused at the status bar.
- #487, #486: native Undo for the copy watchers (recipe kept with the conductor's evidence).
- #455: Rotate and Scale mid-gesture; `onActivePathChanged` routing (measure first); outside-script attribution.
- #154: unit-switch timing in the HtmlDialog (Chromium 88).

### Host pass results (2026-11-11, main `a9d38726`, SketchUp 26.1.188)

Evidence stays in the private run folder `_private/host/hostpass-492/`; results are ticked in #492.

- #437, #474, #468 Zones, #486 A and B: pass under one full-screen hold, fresh process per Undo case.
- #456: pass by DOM read (three profiles on one token each show their own client).
- #154: every row open 311 and 303 ms against the 200 ms target (fail); Zones open 169 ms. Engine Chrome 137.
- #455: an agent write cancels Rotate and Scale mid-gesture; Rotate's partial result merges into the agent's
  Undo step. Guard extension filed as #493, delivered by PR #494 and PR #495.
- LH1 (#332, #472): loading state, Cancel in place and the retry announcement observed; Cancel stopping a load
  and the copy lock wait on a PH-Elements reconnect.
- Recipe lesson: an empty `ModelOperation.perform` block leaves no Undo entry, so a host case that needs an
  unrelated Undo step must write something.
