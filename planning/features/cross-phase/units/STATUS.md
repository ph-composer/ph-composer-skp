# Units: status

DATE: 2026-10-21
STATUS: In progress. Shared infrastructure and Assembly/Window follow-ups merged; Ruby volume/airflow merged through PR #84; feature scope remains.
AUTHOR: Ed May, BLDGTYP, with Codex
ISSUE: none (local planning draft)

## State

Code and planning audit on `main` at `7fbd8fd`, 2026-10-07; final consistency check at `da88d06`
(intervening changes are planning-only and leave the audited source unchanged). The original PRD was drafted on
2026-09-18; Ed confirmed I1 through I15 and the shared-infrastructure-only Phase 0 scope that
day. Q1/Q4 are settled. Q2/Q3 remain with piping and equipment.

The foundation is already delivered. Phase 2 also delivered U1-F3 and U1-F4; they are no longer
implementation tasks. This packet stays active for the feature-owned work below. The original audit
changed documentation only; the standalone implementation authorization is recorded below.

## Implemented and merged

Source paths below are relative to `src/ph_composer/`.

| Capability | Current implementation | Evidence |
| --- | --- | --- |
| Shared parser, formatter and quantity registry | `html/units.js`, `unit_tables.js`, `unit_numbers.js`, `length_expression.js`; 18 panel quantities, mixed-unit length expressions, regional numbers and finite/range checks | `tests/units_test.js`, `tests/support/units_vectors.json`; [P0-E evidence](../../../archive/phase-00-foundation/evidence/phase-04-panel-units.md) |
| Unit-bearing fields and dimension selectors | `html/unit_field.js`, `unit_preferences.js`; the first input/paste freezes a draft's unit profile, while clean fields repaint | `tests/unit_field_test.js`; P0-E evidence |
| Local SI/IP and per-scope formats | `shell/preferences.rb`, `html/panel.js`; `Sketchup.write_default`, separate SI/IP formats, SI first-use default, regional format supplied in snapshots | `tests/preferences_test.rb`, `tests/panel_app_test.js`; P0-E restart and no-Model-write observations |
| Table-cell drafts | `html/record_edits.js` and `inventory_grid.js`; shared parsing, frozen draft units, guarded writes and refusal retention | `tests/record_edits_units_test.js`; the first-table deferral is delivered, except saved layout |
| U1-F3: Assembly dimension drafts | `html/features/assemblies/editor.js` uses `UnitField` for thickness and segment-width editors; the owner retains request guards and pending state | `tests/assembly_builder_test.js`; [Builder evidence](../../../archive/phase-02-envelope/evidence/p2-04-assembly-builder.md), Phase 2 E04 |
| U1-F4: Window dimension form | `html/features/windows/cards.js` uses one `editQuantity`/`UnitField` path for row/column dimensions and other numeric edits | `tests/window_editor_test.js`; [Builder evidence](../../../archive/phase-02-envelope/evidence/p2-11-window-type-builder.md), Phase 2 E11 |
| Report units and SI exports | `export/task.rb` captures the preference when the task is created and passes it to `export/report.rb`; feature report contributors convert canonical values through `core/units.rb`. HBJSON remains SI | `tests/export_test.rb`, `tests/export_tasks_test.rb`; existing [Phase 2 export acceptance](../../../archive/phase-02-envelope/ACCEPTANCE.md) |

Phase 0 merged through PR #1. Phase 2 merged through PR #15 (`c687a73`, an ancestor of the
audited head). Its [acceptance register](../../../archive/phase-02-envelope/ACCEPTANCE.md) records
E03/E04/E11 as passed with qualified retained native and current checks; the individual Builder
journals contain earlier open checkpoints. Use the register and its
[consolidation](../../../archive/phase-02-envelope/evidence/p2-17-acceptance.md#register-consolidation-at-f4f6576)
for the final award, not those historical checkpoint headings.

The audit baseline carried eight Ruby report quantities. The standalone groundwork adds
`volume` and `airflow`, bringing Ruby to ten report quantities, not all 18 panel quantities. `tests/units_test.rb` filters shared vectors to the registered Ruby quantities.
Missing unused Ruby rows are not a blanket mirror defect; add them when a feature needs them.

## Standalone groundwork

Ruby `volume` and `airflow` groundwork merged through [PR #84](https://github.com/ph-composer/ph-composer-skp/pull/84)
on 2026-10-07 at `2195f54`. Ed confirmed
this extraction on 2026-10-07. [Evidence](evidence/ruby-volume-airflow.md) records source identities,
checks, review and limits. P3a-01 reuses it; no Spaces stage gate is closed by this slice.

## Items left to do

| Item | Remaining work | Owner / entry |
| --- | --- | --- |
| Saved table layout | Add persisted column order/widths through the host preference store and verify restoration/reset. Shared table resizing exists, but widths are currently in-memory and no layout preference key/API exists | [P3a-07](../../../archive/phase-03a-spaces/phases/p3a-07-spaces-view.md); D3a-11 answered 2026-10-15: the Spaces view uses whatever the shared table persists and adds no layout store of its own, so persistence, if wanted, is a shared-table change; not authorized |
| U1-F1: large Spaces table | Measured 2026-10-16 in P3a-07 slice D (`tools/ui-preview/spaces_checks.cjs`, fixture `spaceslarge`: 300 Spaces with one Volume and one Floor Segment each; desktop Chrome, Apple M1 Max): median 408 ms per unit switch with the Zones open, 786 ms with every row open, each to the first painted frame (about 1,200 rows). Decision: not optimized in P3a-07, since a unit switch is a rare deliberate act; the cost is above a responsive 100 ms, so issue [#154](https://github.com/ph-composer/ph-composer-skp/issues/154) carries the investigation, and the S07 host gate re-measures in the HtmlDialog. Diagnosed 2026-10-21 ([evidence/u1-f1-unit-switch-diagnosis.md](evidence/u1-f1-unit-switch-diagnosis.md)): one switch renders the whole panel eight times, seven of them redundant; a scratch single-render prototype measured 83 ms and 172 ms. Ed authorized F1 and F2 on 2026-10-21 against a target of under 200 ms with every row open; merged to main through PR #289 (`4516cace`): the panel owns the preference repaint and a confirmation that moves nothing renders nothing. `spaces_checks.cjs` now prints a median of 85 ms with the Zones open and 161 ms with every row open (desktop Chrome 155, Apple M1 Max). F3 not authorized | F1 and F2 merged to main (PR #289); the S07 host gate re-measures in the HtmlDialog |
| Repaint budget | Agree and record the refresh budget used by P3a-07 before deciding whether optimization is needed. That stage refers to a budget in this packet, but no numeric budget has been set here. Ed set it on 2026-10-21: under 200 ms per unit switch with every row of the 300-Space fixture open, in desktop Chrome, measured by `tools/ui-preview/spaces_checks.cjs`, which prints the median rather than asserting it | Set 2026-10-21 (#154); the HtmlDialog figure follows at S07 |
| Piping / Q2 | Confirm nominal pipe-size selection versus converted diameter; reuse length quantities for insulation/run length and add descriptors, vectors and feature-screen checks | [Hot water piping](../../phase-04-mechanical/hot-water-piping/STATUS.md); requested, interview pending |
| Ducting | Confirm duct dimension/insulation descriptors and displays; reuse registered length/airflow quantities where applicable and verify the owning screen/export boundary | [ERV ducting](../../phase-04-mechanical/erv-ducting/STATUS.md); requested, interview pending |
| Equipment / Q3 | Confirm power/energy displays and capacities; add missing volume-in-litres, capacity and ventilator-efficiency conversions as required. W/kWh unchanged and kBtu/h capacity remain proposals; ventilator electric efficiency confirmed 2026-10-21 as Wh/m³ stored, W/cfm in IP (equipment V4) | [Equipment](../../phase-04-mechanical/equipment/STATUS.md); requested, family interviews pending |
| Climate | Confirm radiation quantities and add their conversions/vectors; reuse temperature and length primitives for matching fields | [Climate data](../../phase-05-post-mvp/climate-data/STATUS.md); requested, post-MVP |

Thermal-bridge run length and psi already have generic quantities (`length`, `linear_psi`);
[Phase 3b](../../phase-03b-thermal-bridges/STATUS.md) still owns its field wiring and acceptance.
No piping, ducting, equipment, climate or Spaces feature source is implemented at the audited
head. The PRD's new-quantity table is a proposal, not a list of all-new registry rows: several
fields reuse existing quantities. Add only missing conversions, and Ruby report rows as needed.

## Next step

Ed confirmed the standalone Ruby volume/airflow extraction on 2026-10-07. Its scope is the two
report definitions and the existing shared-vector/formatting tests. It does not start P3a-01
or authorize Spaces, mechanical or climate feature implementation. Acceptance is conversion
agreement with the existing panel vectors, SI identity and SI/IP labels/rounding on both Ruby
versions, focused lint/coverage, local coherent-diff review and `make ci` on both Rubies.
There is no new host-dependent behavior; feature screen/report integration still needs its
owner's acceptance. The cross-phase packet remains active and is not archived.

Resume later feature work with the owning [Spaces entry gates](../../../archive/phase-03a-spaces/STATUS.md)
and open decisions. P3a-01 reuses these Ruby rows; saved layout and the U1-F1 measurement/decision
stay at P3a-07. Mechanical and climate choices wait for their interviews. Do not redo the
foundation transplant or the completed F3/F4 work.

## Blockers

- The remaining feature scope has open decisions and requires its own implementation authorization.
- No issue is recorded for this cross-phase packet. The remote exists; lack of a remote is not a current blocker.

## Verification

### Current execution receipt

- Delivery identity: PR #84 merged at `2195f54`, from reviewed/tested head `e4e914a`.
  The completed `codex/units` branch was removed locally and remotely after exact-tree verification.
  Planning intake `6d68801` and implementation `a961601` are retained as source provenance.
- Completed: Ruby `volume` (m³/ft³) and `airflow` (m³/h/cfm) report definitions; existing shared
  vector test extended to check SI identity, and formatting cases added for both quantities.
- Focused checks: Ruby 2.7.2 and 3.2.2 units tests passed (4 runs, 54 assertions each);
  JavaScript units passed (19 tests). Focused RuboCop initially found one alignment issue,
  corrected before the final gate.
- Review: local review of the table-only diff against the architecture rubric; factors reuse
  the existing foot constant, formatting remains on the shared path, no new public operation,
  persisted value or host lifecycle behavior. No independent review required for this trivial diff.
- Passed: Ruby coverage 97.0% (minimum 93%); `make ci` on Ruby 3.2.2 and 2.7.2, with no
  lint/test skips. [Slice evidence](evidence/ruby-volume-airflow.md) records source identities,
  final results and limits. Whitespace and local Markdown file-link checks passed.
- Delivery: [PR #84](https://github.com/ph-composer/ph-composer-skp/pull/84) merged to `main` on 2026-10-07.
  Both remote Ruby CI jobs passed on exact head `e4e914a`; all source commits and the squash
  commit carry DCO sign-offs. The added ledger cleanup passed eight focused tests, lint/format,
  mypy and ledger validation; one bounded independent review found no actionable issues.
  This authorized extraction is complete; no new host gate applies.
  Future owner decisions, feature integration and host gates remain open.
- Next action: resume through owner entry gates when authorized. Preserve this active packet;
  neither the cross-phase scope nor P3a-01 is complete.

### Retained audit evidence

Focused checks run during this audit, all passing:

| Check | Result |
| --- | --- |
| JavaScript units, unit fields, table drafts, Assembly Builder, Window editor and panel tests | 116 tests, zero failures or skips; repository memory guard and 60-second per-test timeout |
| Ruby units and preferences, pinned Ruby 3.2.2 | 11 runs, 73 assertions, zero failures/errors/skips |
| Ruby export and export tasks, pinned Ruby 3.2.2 | 33 runs, 271 assertions, zero failures/errors/skips |

Source tracing confirms report preference capture; this audit did not execute a live switch
during an export or a new SI/IP HBJSON equivalence comparison. Existing phase evidence is
retained with its original scope/provenance. No new native host, browser, Ruby 2.7, full CI,
coverage or performance gate ran for these documentation-only changes.

The predecessor's A1 to A15 remain the acceptance shape, allocated to their delivery owners.
[P0-E](../../../archive/phase-00-foundation/evidence/phase-04-panel-units.md#units-acceptance-allocation-a1-to-a15)
proves the shared subset; Phase 2 adds feature evidence. There is no consolidated PH-Composer
award for every inherited check across all future screens. Each remaining owner must record
its applicable parsing, draft, persistence, report/export and host checks, reusing unchanged
evidence where justified. Spaces performance is NOT RUN. SketchUp 2023, Windows and public
release gates remain separate.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted from the predecessor's U1 record. |
| 2026-09-18 | Ed confirmed inherited behavior and the shared-infrastructure-only Phase 0 scope. No implementation authorized. |
| 2026-09-18 | Shared portion implemented in P0-E; dimension scopes replace builder names. Table drafts/layout deferred to the first table screen. Foundation subsequently merged through PR #1. |
| 2026-10-01 | Phase 2 accepted and merged through PR #15, delivering U1-F3 and U1-F4 with their feature screens. |
| 2026-10-03 | Phase 3 planning: Ruby volume and airflow rows allocated to P3a-01; U1-F1 measurement and saved layout to P3a-07. |
| 2026-10-07 | Reconciled source/tests and archived awards: closed F3/F4 implementation work, distinguished table drafts from saved layout, and recorded remaining owners, unset repaint budget and verification limits. |
| 2026-10-07 | Ed confirmed extracting standalone Ruby volume/airflow groundwork; feature UI/layout/performance remain with their owners. |
| 2026-10-07 | Standalone Ruby volume/airflow groundwork complete on `codex/units`: both Ruby full offline gates, 97.0% Ruby coverage and local table-diff review passed; no host-dependent change or feature-stage acceptance. |
| 2026-10-07 | Published the units planning revisions and standalone groundwork as PR #84; retained the active packet and feature-owner gates. |
| 2026-10-07 | PR #84 merged at `2195f54` after both exact-head Ruby CI jobs passed. Branch removed locally/remotely after verifying its tree matches the merge; feature follow-ups remain active. |
| 2026-10-21 | U1-F1 diagnosed for #154 in [evidence/u1-f1-unit-switch-diagnosis.md](evidence/u1-f1-unit-switch-diagnosis.md): redundant panel renders, not formatting, dominate; fixes proposed, documentation only. |
| 2026-10-21 | Ed authorized F1 and F2 for #154 with a target of under 200 ms with every row open. Merged to main through PR #289 (`4516cace`) after review and both CI jobs passed: one render per unit switch, none for a confirmation that moves nothing; medians 85 ms and 161 ms on the 300-Space fixture. |
