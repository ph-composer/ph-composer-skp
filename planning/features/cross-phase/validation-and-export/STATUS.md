# Validation and export: status

DATE: 2026-10-15
STATUS: In progress. Phase 1 HBJSON/report scope merged to main through PR #3 and PR #6 and accepted in
the archived Phase 1 packet. Later feature scope remains.
AUTHOR: Ed May, BLDGTYP, with Codex review
ISSUE: none (local planning draft)

## State

P1-E implements preflight, explicit repairs, per-Model asynchronous tasks, bounded collection,
pinned lazy translation, cancellation, result retention and coordinated HBJSON/report replacement
and recovery. Blocking findings remain visible and write no canonical pair. Export does not save
or modify the SKP. [P1-E/F evidence](../../../archive/phase-01-faces-and-zones/evidence/p1-e-export-workflow.md) records the
exact implementation, package, native cases and independent-review corrections.

## Remaining scope and delivery boundaries

Phase 2 P2-06 real Assembly export is implemented with native reference evidence. P2-14 Window
construction/Aperture export passes current-host E14 on the normal RBZ: canonical two-Zone
reference, gross parents, per-side installs, exact g endpoints, blocking findings, net opaque areas,
pinned native comparison and clean native close/reopen. See
[E14 evidence](../../../archive/phase-02-envelope/evidence/p2-14-aperture-export.md).
Structured E06 consolidation and Phase 2 integrated acceptance are complete with the qualified
provenance in the [archived closure](../../../archive/phase-02-envelope/STATUS.md).

The normal build requires authored Assemblies; it safely refuses when none are available.
Successful Phase 1 translation acceptance uses an explicit tools-only synthetic provider, excluded
from shipping composition. Assemblies/materials authoring and later building validation belong to
their feature stages. METr export, consumer import and floor-area policy remain deferred and
unscheduled. SketchUp 2023/Windows host proof, public-distribution license review, merge and
release are separate gates. No implementation issue was requested or created.

Phase 2 delivered real constructions in
[P2-06](../../../archive/phase-02-envelope/phases/p2-06-construction-export.md) and apertures in
[P2-14](../../../archive/phase-02-envelope/phases/p2-14-aperture-export.md), merged through PR #15
on 2026-10-01. See [PLAN.md](PLAN.md) for the original allocation; later scope remains separate.

### Owed from the Phase 2 review

Added 2026-10-02 from [R05](../../../archive/phase-02-envelope-review/R05-export-layering.md)'s follow-ups.
Items 1, 2 and 4 are delivered. Item 3 is allocated to
[P3a-10](../../../archive/phase-03a-spaces/phases/p3a-10-spaces-export.md), with the Spaces contributor,
section and report schedule, and item 4 to Phase 3b's P3b-08.

1. **Defect: a Room with no Faces.** Delivered by Spaces P3a-01 on 2026-10-15
   (`feature/spaces-p3a-01`). A Zone whose Faces are all omitted is refused in `ZoneSection.translate`
   as `object.unavailable`, blocking, so the run publishes nothing and the diagnostic model reloads
   with the remaining Rooms. Refusing was chosen over omitting the Room, which would export a model
   with a Zone silently missing. The same change stops a Surface Face whose counterpart sat in the
   refused Zone from refusing its own Zone in `attach`.
   `tests/python/test_model_sections.py::test_a_zone_whose_faces_are_all_omitted_is_refused_and_the_rest_reloads`.
2. **Section-read cycles.** Delivered: registration refuses export sections that require each
   other, or themselves, as `registration.cycle` (`shell/registry_validation.rb`,
   `check_section_cycles`), merged through PR #122 with EC-03. Confirmed against `main` at
   `87bdc62` during the Spaces re-baseline on 2026-10-15.
3. **Results from runs that cannot publish.** `construction_usage` and `window_face_areas` are
   reported from runs that write no canonical pair. Decided 2026-10-15 (spaces D3a-10): a blocked
   run shows them, and the Spaces schedule, under one line saying the run wrote no model; one
   general rule in `export/report.rb`, delivered by P3a-10. Built by P3a-10 slice B on 2026-10-16
   (`feature/spaces-p3a-10b`): `Report.render` keys on `summary.publishable`, the refused outcome
   carries the report as `value.report_html`, and the Export tab shows it collapsed;
   `tests/export_tasks_test.rb` and `tests/panel_app_test.js`.
4. **An optional attaching section withholds the model.** An attaching section that is not required
   for export still withholds the canonical model when it refuses. No such section exists yet; settle
   the rule before the first one does. Allocated 2026-10-03 to Phase 3
   [P3b-08](../../phase-03b-thermal-bridges/phases/p3b-08-thermal-bridge-export.md): Ed made the
   thermal-bridge section optional, so a refused run is omitted and disclosed and the canonical model
   is still written. Delivered by P3b-08 on 2026-10-26 (`feature/thermal-bridges-p3b-08`): `assemble`
   withholds the canonical model only for a refusal from a section required for export; an optional
   section's refused object is left out with a non-blocking `object.unavailable` finding.
   `tests/python/test_room_attachment.py` holds both cases; the rule is in `context/CONTRACTS.md`,
   "Translation sections and artifacts".

## Verification

Both Ruby 3.2.2 and 2.7.2 full offline gates pass, with coverage, real-panel browser checks,
pinned native/Pyodide comparison, package inventory and fresh SketchUp 26.1.188 acceptance.
Native cases cover missing-construction refusal, successful exact HBJSON/report, warnings,
cancellation, mutation refusal, navigation tolerance, fault/restart recovery, panel/runtime/Model
loss, two Models, nested edit paths, Undo/Redo and reopen. See the evidence for fixture limits.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | Initial scoping packet drafted during the whole-project review. |
| 2026-09-18 | D2 confirmed: keep a valid HBJSON/report pair when optional METr export fails, report the failure and preserve any prior METr file. |
| 2026-09-20 | Post-Phase-0 refresh: added PLAN.md, removed completed foundation blockers and linked the shared Phase 1 stages and decisions. Planning only; feature implementation remains pending. |
| 2026-09-20 | Ed deferred METr exporter development and consumer acceptance until further feature development. Phase 1 closes on canonical HBJSON/report; return milestone unscheduled. |
| 2026-09-20 | P1-C development proof complete on the implementation branch: registered Zone/face sections produced and reloaded exact HBJSON in the pinned native Honeybee stack; P1-E user workflow and Pyodide wheels remain pending. |
| 2026-09-29 | Ed authorized P1-E: HBJSON/report always selected, blockers write no pair and remain visible, no implicit SKP save, METr deferred. |
| 2026-09-30 | Phase 2 planning: construction and aperture export allocated to P2-06 and P2-14. Packet moved under `features/cross-phase/`. |
| 2026-09-30 | P1-E implementation and P1-F current-host integrated acceptance complete on branch; independent review and final gates pass. Normal composition requires authored Assemblies. |
| 2026-10-02 | Phase 2 review: R05's four export-run follow-ups recorded as owed, one a live defect (an empty Room fails to reload). None authorized. |
| 2026-10-03 | Phase 3 planning: R05 items 1 and 2 allocated to P3a-01 and item 3 to P3a-10, with the Spaces export section. Item 4 stays owed pending D3a-9. None authorized. |
| 2026-10-26 | Phase 3b P3b-08 on branch: R05 item 4 delivered (optional attaching sections) with the first optional section, thermal bridges (`ph_composer.thermal_bridges.export.thermal_bridges`, attaching at `ROOM`). |
