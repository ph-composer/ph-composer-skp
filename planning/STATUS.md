# Planning Status

DATE: 2026-10-21
STATUS: Active index of tracked planning work.
AUTHOR: Ed May, BLDGTYP

Master index. Every active item gets a row; archived items move to
`archive/README.md`.

The order the work is planned in is in [ROADMAP.md](ROADMAP.md).

Phase 0, its four completed investigations, Phase 1, Phase 2, Phase 3a (Spaces), Phase 3b (thermal bridges), Phase 4 (Climate, whose host gate stays an active row below), Phase 5 (Shading, whose open items stay an active row below), Phase 6 (Programs, whose deferred follow-ups stay an active row below), the Ruby readability
program, production support, developer observability and agent workflow completeness are in [the archive](archive/README.md).
Feature packets are grouped in phase directories under `features/`; the Phase column below is
the roadmap phase as re-ordered on 2026-11-15 (ids keep their older prefixes), `cross` spans phases, `none` is unscheduled and `n/a` is not a feature packet.
The remote exists. Historical `none (no remote)` issue cells below mean no issue was recorded;
reconcile them at each packet's intake rather than treating the old reason as a current blocker.

## Active work

| Phase | Item | Kind | State | Issue | Pointer |
| ----- | ---- | ---- | ----- | ----- | ------- |
| none | GitHub open-issue sweep, November 2026 | workflow | Code complete 2026-11-11: 19 PRs merged (the #493 Scale and Rotate guard added PR #494 and PR #495, Rotate host-checked 2026-11-12), #438 closed as host behavior; host pass run 2026-11-11; 2026-11-12: #491 merged (PR #496), LH1 passed, #455 fixed by PR #498 (merged); #492 closed, every row pass; #490 (PR #499) and #497 (PR #500) merged; every sweep issue closed | [#492](https://github.com/ph-composer/ph-composer-skp/issues/492) (host pass, closed) | [github-issue-sweep-2026-11](features/unscheduled/github-issue-sweep-2026-11.md) |
| none | GitHub organization and SketchUp repository migration | workflow | Implemented and native-verified 2026-10-25; merge tracked in PR #306 | [#305](https://github.com/ph-composer/ph-composer-skp/issues/305) | [migration plan](features/unscheduled/github-organization-migration.md) |
| 6 | Programs: ProgramTypes, loads and schedules on Zones (the Zone loads packet) | feature | Complete 2026-11-22 and archived: P4a-01 to P4a-12 merged to main (PRs [#539](https://github.com/ph-composer/ph-composer-skp/pull/539) to [#552](https://github.com/ph-composer/ph-composer-skp/pull/552)); the host sitting of 2026-11-21 ([#553](https://github.com/ph-composer/ph-composer-skp/pull/553)) and its fixes, [#554](https://github.com/ph-composer/ph-composer-skp/pull/554) (PG09), [#555](https://github.com/ph-composer/ph-composer-skp/pull/555) (eleven visual defects), [#556](https://github.com/ph-composer/ph-composer-skp/pull/556) (PHX 1.59.3, PH-Tools/PHX#171) and [#557](https://github.com/ph-composer/ph-composer-skp/pull/557) (PHX 1.59.4, PH-Tools/PHX#175), last `e0be139d`; PG01 to PG12 pass on the host; Ed approved the host UI polish for PG02, PG09, PG11 and PG11b on 2026-11-22; not released. Deferred follow-ups, each its own authorization: the F4a-13 honeybee-ph and PHX fix, the METr attached-zone reduction factor and the rest in its STATUS. Includes Building Segments and absorbs Phase 4 appliances (Q4a-03) | [#538](https://github.com/ph-composer/ph-composer-skp/issues/538) | [archive/phase-06-program/](archive/phase-06-program/README.md); final state in its [host sitting](archive/phase-06-program/STATUS.md#host-sitting), deferred items in its [follow-ups](archive/phase-06-program/STATUS.md#follow-ups) |
| 7 | Mechanical, coordinating packet | phase | In progress: Ed authorized every stage on 2026-11-23 (pr-loop, merge on green); host gates batched by milestone (MS1, MS2, MS3), Ed not at the Mac; P4-01 (#564), P4-02 (#565), P4-03 (#566), P4-04 (#567) and P4-05 (#568) merged; MS1 offline complete, host cases M01 to M04 owed to the MS1 sitting; P4-05 merged (#568; host case M05 owed to MS2); P4-06 merged (#569; host case M06 owed to MS2); P4-07 merged (#570: the Hot Water subtab, which closes MS2 offline; host case M07 owed to the MS2 sitting); P4-08 merged (#571: heat pumps, the per-Segment blend and its export; host case M08 owed to MS3); P4-08b merged (#572: the Building Segment's mechanical settings; host case M16 owed to MS3); P4-09 merged (#573: electric heaters; host case M09 owed to MS3); P4-10 merged (#574: pumps; host case M10 owed to MS3); P4-11 merged (#575: fans; host case M11 owed to MS3); piping and ducting merged (#576 to #588), which completes the implementation; the post-cap review fixes merged (#590); P4-15's offline part, acceptance and handoff, in review: register consolidated, docs confirmed, METr rows handed to metr-export, every host case (M15 among them) owed to its sitting, so the phase is not complete | [#562](https://github.com/ph-composer/ph-composer-skp/issues/562) | [features/phase-07-mechanical/](features/phase-07-mechanical/README.md); tracked in its [ledger](features/phase-07-mechanical/STATUS.md) |
| 7 | Hot water piping | feature | Merged to main, host cases owed to MS3; interviewed 2026-11-23 (D4-36, Q1–Q13 all as recommended); Phase 3b's edge stages merged 2026-10-26; planned in full 2026-11-24 as P4-13a to P4-13e; P4-13a, the piping feature and Pipe Types, merged (#576; host case M13a owed to MS3); P4-13b, Piping groups and the pipe assignment, merged (#577; host case M13b owed to MS3); P4-13c, the chain rule in core, the tree and the schedule, merged (#578; host case M13c owed to MS3); P4-13d, the piping export, merged (#579; host case M13d owed to MS3); P4-13e, the Piping pills, Colour-by and the pipe tool, merged (#580; host case M13e owed to MS3) | [#562](https://github.com/ph-composer/ph-composer-skp/issues/562) | [features/phase-07-mechanical/hot-water-piping/](features/phase-07-mechanical/hot-water-piping/README.md) |
| 7 | ERV ducting | feature | Merged to main, host cases owed to MS3; interviewed 2026-11-23 (D4-37, Q1–Q9 all as recommended); Phase 3b's edge stages merged 2026-10-26; planned in full 2026-11-24 as P4-14a to P4-14f, two inferences for Ed (the shared line-group layer, the run quantity); P4-14a, the ducting feature and Duct Types, merged (#581; host case M14a owed to MS3); P4-14b, the shared line-group layer, merged (#582); P4-14c, Ducting groups and the duct assignment, merged (#583; host case M14c owed to MS3); P4-14c2, the line-group operations consolidated (#584), merged (#585); P4-14d, duct runs and the schedule, merged (#586; host case M14d owed to MS3); P4-14e, the ducting export, merged (#587; host case M14e owed to MS3); P4-14f, the Ducting pills, the Ventilators columns and Colour-by, merged (#588; host case M14f owed to MS3), the last ducting sub-stage | [#562](https://github.com/ph-composer/ph-composer-skp/issues/562) | [features/phase-07-mechanical/erv-ducting/](features/phase-07-mechanical/erv-ducting/README.md) |
| 7 | Equipment (six families; appliances built in Phase 6 as Equipment Sets) | feature | Merged to main, host cases owed to MS1, MS2 and MS3; all six families interviewed (shared shape, Ventilators and hot water 2026-10-21; heat pumps 2026-11-15/2026-11-23; Electric heaters, Pumps and Fans 2026-11-23) and implemented by P4-01 to P4-11 and P4-08b (#564 to #575) | [#562](https://github.com/ph-composer/ph-composer-skp/issues/562) | [features/phase-07-mechanical/equipment/](features/phase-07-mechanical/equipment/README.md) |
| 8 | Libraries: generic connection seam (P2-16, roadmap 2.5) | feature | Merged to main 2026-11-02 ([PR #329](https://github.com/ph-composer/ph-composer-skp/pull/329), `5df489e5`); un-deferred by D5-1; host gate passed 2026-11-03 (case LH1 run 2, all sixteen assertions; [evidence](native-acceptance/evidence/lh1-hosted-library-2026-11-03-run2.md)) | [#328](https://github.com/ph-composer/ph-composer-skp/issues/328) | [p2-16](features/phase-08-post-mvp/phases/p2-16-connection-provider.md) |
| none | Libraries view: rows a load left out | feature | Implemented on branch `feature/library-skipped-rows`; host case pending, runs with PH-Elements #137 stage 5 | [#379](https://github.com/ph-composer/ph-composer-skp/issues/379) | [library-skipped-rows](features/unscheduled/library-skipped-rows.md) |
| 4 | Climate: Ed's verification pass and rechecks | host gate | Complete 2026-11-18 and archived: P4c-01 to P4c-12 merged to main (PRs #512 to #523), the review fixes in PR #524 (merged 2026-11-19 UTC as `73ef7ba9`); host acceptance not complete: CM06 to CM12 wait on Ed's verification pass, CM04 to CM12 read `needs_recheck` (Ed decides what is rerun), SketchUp's Add Location not run; not released | [#511](https://github.com/ph-composer/ph-composer-skp/issues/511) | [archive/phase-04-climate/](archive/phase-04-climate/README.md); open items in its [closure](archive/phase-04-climate/STATUS.md#closure-2026-11-18) |
| 5 | Shading: three follow-ups | follow-ups | Complete 2026-11-20 and archived: P5s-01 to P5s-07 merged to main (PRs #527 to #533, last `906a102c`); SD01 to SD07 pass on `906a102c`; not released. Ed confirmed the two conductor extensions (D5s-11a and the Window Unit refusal row) on 2026-11-20. The three host-pass follow-ups are fixed by [#536](https://github.com/ph-composer/ph-composer-skp/pull/536): the Colour-by rebuild plus refresh at 5,000 Shading Faces is now about 190 ms at the median (163 + 27), under the 200 ms target there, though 6 of 21 measured pairs exceed 200 ms (worst about 224 ms); a display-units change repaints the legend at once; the Classify tool says a Face outside its Zone's envelope is not part of it. Checked on the host on `63730e18` under background control and on `e25886b6` under a full-screen hold (panel units toggle, Reset display preferences, Classify tooltips) ([evidence](archive/phase-05-shading/evidence/followups-colour-by-timing.md)) | [#526](https://github.com/ph-composer/ph-composer-skp/issues/526) | [archive/phase-05-shading/](archive/phase-05-shading/README.md); open items in its [closure](archive/phase-05-shading/STATUS.md#closure-2026-11-20) |
| 8 | Sun-path view | feature, post-MVP | Requested, PRD drafted | none (no remote) | [features/phase-08-post-mvp/sun-path-view/](features/phase-08-post-mvp/sun-path-view/README.md) |
| 8 | Window performance overlays | feature, post-MVP | Requested, PRD drafted | none (no remote) | [features/phase-08-post-mvp/window-performance-overlays/](features/phase-08-post-mvp/window-performance-overlays/README.md) |
| cross | Validation and export | feature | In progress; Phase 1 HBJSON/report scope merged to main; later feature scope remains | none (local planning draft) | [features/cross-phase/validation-and-export/](features/cross-phase/validation-and-export/README.md); [evidence](archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md); authored Assemblies required in normal composition |
| cross | Units: SI and IP display | feature | In progress; shared infrastructure and Assembly/Window follow-ups merged | none (local planning draft) | [features/cross-phase/units/](features/cross-phase/units/README.md); audited 2026-10-07; Ruby volume/airflow groundwork merged through PR #84; Spaces integration/layout/performance and later feature quantities remain; U1-F1 repaint fix (F1, F2) merged to main 2026-10-21 (PR #289) for [#154](https://github.com/ph-composer/ph-composer-skp/issues/154), 161 ms with every row open against a 200 ms target; host 169 ms Zones open and 311 ms every row open, accepted by Ed and #154 closed 2026-11-12 |
| none | Make Zone entry points | feature | Requested; toolbar button and Classify-tool inline offer, carried from zones-and-adjacency | none (local planning draft) | [features/unscheduled/zones-entry-points/](features/unscheduled/zones-entry-points/README.md) |
| none | ph-composer-standards repository: one home for starter and standards library files | workflow | Scoped 2026-11-15: PRD and stages S1 to S4; S3 waits on Phase 4a P4a-07; repository needs Ed's go | none (local planning draft) | [features/unscheduled/ph-composer-standards/](features/unscheduled/ph-composer-standards/README.md) |
| none | Brand and public documentation: mark, palette, type, in-app colour rule, site and docs suite | workflow | Scoped 2026-11-25: brand direction decided (BR-D1 to BR-D12) and stages BR-01 to BR-09 drafted; nothing implemented, no stage authorized | none (local planning draft) | [features/unscheduled/brand-and-docs/](features/unscheduled/brand-and-docs/README.md) |
| none | Zones outside every Building Segment exported as shading | feature | Requested; brief only (2026-11-15); SH-3 and SH-4 closed by Phase 5 (2026-11-19) | none (local planning draft) | [features/unscheduled/zone-shading.md](features/unscheduled/zone-shading.md) |
| none | METr export | feature | Deferred; return milestone unscheduled | none (local planning draft) | [features/unscheduled/metr-export/](features/unscheduled/metr-export/README.md); Phase 1 row A15; Ed deferred until further feature development on 2026-09-20 |
| none | SketchUp 2023 floor verification | feature, host gate | Requested | none (local planning draft) | [features/unscheduled/sketchup-2023-floor/](features/unscheduled/sketchup-2023-floor/README.md); no 2023 host run yet |
| none | Windows support verification | feature, host gate | Requested | none (local planning draft) | [features/unscheduled/windows-support/](features/unscheduled/windows-support/README.md); first release candidate is macOS-only |
| none | Legend hover-to-highlight | feature | Requested | none (local planning draft) | [features/unscheduled/legend-hover-highlight/](features/unscheduled/legend-hover-highlight/README.md); fourth Q18 legend affordance, deferred from Phase 1 D7 on cost |
| none | Panel keyboard focus and announcements | feature | Requested; seven items carried from the UI and UX refinement on 2026-10-03 | none (local planning draft) | [features/unscheduled/panel-keyboard-focus/](features/unscheduled/panel-keyboard-focus/README.md) |
| n/a | GitHub issue delivery queue | workflow | Complete; all eleven issues closed, review and CI passed, branches cleaned; no manual steps | [receipt](archive/github-issue-sweep.md) | [archive/github-issue-sweep.md](archive/github-issue-sweep.md) |
| n/a | A copied Zone cannot be edited and the refusal locks Zones / Faces | bug | Complete 2026-10-12 on `fix/copied-zone-edit-refusal`, archived; merges with PR #97 after review and CI | [PR #97](https://github.com/ph-composer/ph-composer-skp/pull/97) | [archive/copied-zone-edit-refusal/](archive/copied-zone-edit-refusal/README.md) |
| n/a | Native acceptance tooling | workflow | Implemented; historical evidence indexed, observed-result validation and dependency screening | none (local tooling work) | [native-acceptance/](native-acceptance/README.md); tools and skills remain development-only |
| n/a | UI baseline from the predecessor's six screens | reference | Scoped | none (no remote) | [ui-baseline/](ui-baseline/README.md) |
| n/a | PHX dependency packaging | external follow-up | Deferred; Phase 0 runtime route proved | [PH-Tools/PHX#157](https://github.com/PH-Tools/PHX/issues/157) | [B1 disposition](archive/phase-00-foundation/evidence/spike-phx.md); METr integration deferred; retain pinned-wheel evidence for resumption |
| n/a | Cross-cutting decisions | decision register | D1-D12 confirmed; contributor architecture and external-agent priority recorded | none (no remote) | [DECISIONS.md](DECISIONS.md); [contributor architecture](../context/EXTENSIBILITY.md); [agent interface](../context/AGENT_INTERFACE.md) |

States: `Requested` · `Scoped` · `In progress` · `Blocked` · `In review` ·
`Implemented on branch` · `Merged to main` · `Complete` · `Deferred` ·
`Superseded`


## Recently merged

One shared deep-freeze helper [merged through PR #83](https://github.com/ph-composer/ph-composer-skp/pull/83)
on 2026-10-07 as `7fbd8fd` and is [archived](archive/shared-deep-freeze.md). All ten settings and
registry copy-then-freeze call sites use `DeepCopy.frozen`; both private helpers are removed.
Coverage, bounded review and local/remote `make ci` on Ruby 2.7.2 and 3.2.2 passed. Not released.

UI and UX refinements are [complete and archived](archive/ui-ux-refinements.md#current-native-acceptance).
Implementation merged through PR #79/#80, Design System sync is complete, and all six bounded
current-host cases passed on 2026-10-07; [native evidence](native-acceptance/evidence/ui-ux-refinements-2026-10-07.md).
Release and platform gates remain separate.

Zones / Faces table-first layout merged to main on 2026-10-04 through
[PR #73](https://github.com/ph-composer/ph-composer-skp/pull/73) (merge commit `5ef2d7d`), host-accepted and
[archived](archive/zones-table-first/README.md); the bug it superseded is
[archived](archive/locate-outside-zone-selection.md). Its follow-ups merged the same day: PR #74, PR #75 and PR #76.

Agent-authorized file access merged to main on 2026-10-03 through
[PR #70](https://github.com/ph-composer/ph-composer-skp/pull/70) (merge commit `e0b61f3`), issue
[#36](https://github.com/ph-composer/ph-composer-skp/issues/36) closed, and is
[archived](archive/agent-authorized-file-access/README.md). Agents can now export and add libraries
through locations the user approved; binding an approval to a named connection waits for the
unscheduled agent connection and access-grant packet. That packet also owns the listener's port-squatting
fix; the options are recorded in the archived
[SH-05](archive/security-hardening/phases/sh-05-listener-binding.md).

Phase 2 envelope is [accepted and archived](archive/phase-02-envelope/STATUS.md), issue
[#14](https://github.com/ph-composer/ph-composer-skp/issues/14) closed. [PR #15](https://github.com/ph-composer/ph-composer-skp/pull/15)
merged to main on 2026-10-01 as merge commit `c687a73`. E01–E15/E17 pass with stated provenance; E16 is
Phase 5. The archive records acceptance, not release or platform support. The independent review's
eleven findings were each merged on their own branch by 2026-10-02 and
[archived](archive/phase-02-envelope-review/README.md). Phase 3 remains
the next planned feature scope and requires its own implementation authorization.

Managed Zone options completed on `codex/zone-field-options` on 2026-10-05; offline, review and
current-host acceptance passed, including Ed’s final normal-panel visual confirmation.
[Archived packet](archive/zone-field-options/STATUS.md); [PR #80](https://github.com/ph-composer/ph-composer-skp/pull/80)
merged at `81f5426` after the inline corrections and dual-Ruby GitHub CI passed. The private Design
System reading aid was synchronized to `main@4f51621` on 2026-10-05, with current styles and fifteen
static component renditions; see the [sync receipt](archive/ui-ux-refinements.md#design-system-sync-receipt).
