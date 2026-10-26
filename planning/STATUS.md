# Planning Status

DATE: 2026-10-21
STATUS: Active index of tracked planning work.
AUTHOR: Ed May, BLDGTYP

Master index. Every active item gets a row; archived items move to
`archive/README.md`.

The order the work is planned in is in [ROADMAP.md](ROADMAP.md).

Phase 0, its four completed investigations, Phase 1, Phase 2, Phase 3a (Spaces), the Ruby readability
program, production support and developer observability are in [the archive](archive/README.md).
Feature packets are grouped in phase directories under `features/`; the Phase column below is
the roadmap phase, `cross` spans phases, `none` is unscheduled and `n/a` is not a feature packet.
The remote exists. Historical `none (no remote)` issue cells below mean no issue was recorded;
reconcile them at each packet's intake rather than treating the old reason as a current blocker.

## Active work

| Phase | Item | Kind | State | Issue | Pointer |
| ----- | ---- | ---- | ----- | ----- | ------- |
| none | GitHub organization and SketchUp repository migration | workflow | Implemented and native-verified 2026-10-25; merge tracked in PR #306 | [#305](https://github.com/ph-composer/ph-composer-skp/issues/305) | [migration plan](features/unscheduled/github-organization-migration.md) |
| 3b | Thermal bridges | feature | In progress; interviewed 2026-10-03; planned as P3b-01 to P3b-09; re-baselined on `main` at `420c783a` 2026-10-21, D3b-22 and D3b-23 answered; P3b-01 merged to main 2026-10-22 (PR #302, T01 pass); P3b-02 to P3b-09 authorized 2026-10-25 as one PR each; P3b-02 merged to main 2026-10-25 (PR #308, T02 pass); P3b-03 merged to main 2026-10-25 (PR #309, T03 pass); P3b-04 merged to main 2026-10-26 (PR #310, T04 pass); P3b-05 merged to main 2026-10-26 (PR #311, T05 pass); P3b-06 merged to main 2026-10-26 (PR #312, T06 pass); P3b-07 implemented on branch (PR #313, T07 pass) | [#301](https://github.com/ph-composer/ph-composer-skp/issues/301) | [features/phase-03b-thermal-bridges/](features/phase-03b-thermal-bridges/README.md); tracked in its [ledger](features/phase-03b-thermal-bridges/STATUS.md); owns the edge tagging rules |
| 4 | Mechanical, coordinating packet | phase | Scoped; planned 2026-10-21 as P4-01 to P4-15, D4-01 to D4-12 answered as recommended, none authorized | none (local planning draft) | [features/phase-04-mechanical/](features/phase-04-mechanical/README.md); tracked in its [ledger](features/phase-04-mechanical/STATUS.md) |
| 4 | Hot water piping | feature | Requested, PRD drafted; re-baselined against `main` 2026-10-21 | none (local planning draft) | [features/phase-04-mechanical/hot-water-piping/](features/phase-04-mechanical/hot-water-piping/README.md) |
| 4 | ERV ducting | feature | Requested, PRD drafted; re-baselined against `main` 2026-10-21 | none (local planning draft) | [features/phase-04-mechanical/erv-ducting/](features/phase-04-mechanical/erv-ducting/README.md) |
| 4 | Equipment (seven families) | feature | Scoped; shared shape (Q1 to Q12), Ventilators (V1 to V6) and hot water (H1 to H7) interviewed 2026-10-21, families 3 to 7 not; re-baselined against `main` the same day | none (local planning draft) | [features/phase-04-mechanical/equipment/](features/phase-04-mechanical/equipment/README.md) |
| 5 | Climate data | feature, post-MVP | Requested, PRD drafted | none (no remote) | [features/phase-05-post-mvp/climate-data/](features/phase-05-post-mvp/climate-data/README.md) |
| 5 | Sun-path view | feature, post-MVP | Requested, PRD drafted | none (no remote) | [features/phase-05-post-mvp/sun-path-view/](features/phase-05-post-mvp/sun-path-view/README.md) |
| 5 | Window performance overlays | feature, post-MVP | Requested, PRD drafted | none (no remote) | [features/phase-05-post-mvp/window-performance-overlays/](features/phase-05-post-mvp/window-performance-overlays/README.md) |
| cross | Validation and export | feature | In progress; Phase 1 HBJSON/report scope merged to main; later feature scope remains | none (local planning draft) | [features/cross-phase/validation-and-export/](features/cross-phase/validation-and-export/README.md); [evidence](archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md); authored Assemblies required in normal composition |
| cross | Units: SI and IP display | feature | In progress; shared infrastructure and Assembly/Window follow-ups merged | none (local planning draft) | [features/cross-phase/units/](features/cross-phase/units/README.md); audited 2026-10-07; Ruby volume/airflow groundwork merged through PR #84; Spaces integration/layout/performance and later feature quantities remain; U1-F1 repaint fix (F1, F2) merged to main 2026-10-21 (PR #289) for [#154](https://github.com/ph-composer/ph-composer-skp/issues/154), 161 ms with every row open against a 200 ms target |
| cross | Geometry contribution contracts | refactoring | In progress; G-02 (Edge entries in the export snapshot) merged in PR 119; G-01, G-03 and G-04 deferred to the phase 3b thermal-bridge ledger | [#118](https://github.com/ph-composer/ph-composer-skp/issues/118) | [features/cross-phase/geometry-contribution-contracts/](features/cross-phase/geometry-contribution-contracts/STATUS.md); origin: [archived code review](archive/code-review/README.md) |
| none | Make Zone entry points | feature | Requested; toolbar button and Classify-tool inline offer, carried from zones-and-adjacency | none (local planning draft) | [features/unscheduled/zones-entry-points/](features/unscheduled/zones-entry-points/README.md) |
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
