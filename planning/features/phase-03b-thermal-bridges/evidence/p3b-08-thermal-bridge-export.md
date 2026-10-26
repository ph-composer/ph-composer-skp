# P3b-08 evidence: thermal-bridge export (T08)

DATE: 2026-10-26
STATUS: Host gate run on branch `feature/thermal-bridges-p3b-08` at `26188c6e` (PR #314), SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1. All nine assertions pass.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T08](../ACCEPTANCE.md). Offline half: `tests/thermal_bridge_export_test.rb` (the reference
extraction against the hand calculation and the shared golden, the export and the schedule building the same
runs, only tagged Edges, an Edge outside every Zone and one in a container a Zone holds left out with their
notes, a missing type or psi-value and an invalid or unreadable assignment blocking, warnings as notes beside
exported runs, the metadata guard, the outline paging loop and a Windows refusal, the report),
`tests/python/test_thermal_bridge_sections.py` (five runs on one Building-Segment shared by two Rooms after
reload, a closed run, a refused run left out through `export_json` with conformance, a required section's
refusal withholding the model, two Building-Segments, an unreadable run, conformance refusals, the result-field
contract), `tests/python/test_room_attachment.py` (the optional-attachment rule both ways), the window-perimeter
rule in `tests/thermal_bridge_runs_test.rb`, `units.outlines` in `tests/window_unit_actions_test.rb` and the
Apertures outlines in `tests/window_export_test.rb`. `make ci` green at `26188c6e`. Review (strong): one pre-gate Sonnet read (no high; three medium fixed before the PR) and two Codex gpt-6-astra cycles on PR #314 (cycle 1: 1 P2, `units.outlines` declaring an `ids` filter it ignored, and 1 P3, Zone ownership read from Zones' internals rather than its projection, both fixed in `26188c6e`; cycle 2: no findings). Host half: recorded through
`tools/hostkit/acceptance_case.py` in `_private/host/t08/T08/` (gitignored; synthetic fixture, no project data),
driven by `_private/host/t08/t08-run.sh`. The ledger row records a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `26188c6e`, SHA-256 `fc8bf4970db62e70844f6e6c75d16f0bea817e260d2e034efceb10b14ae39fb8`; the run's diagnostics name build commit `26188c6e` |
| Fixture | `_private/host/t08/T08/t08.skp` (SHA-256 `ca4c148e`), a copy of `t08-reference-assigned.skp`: the T04 reference base (Zones A, B and W, five types, a Window Unit on Zone A's south wall, the Balcony line, a line at the Model root) with one complete Assembly on all 19 Zone Faces and the five runs assigned through `edges.assign` |
| Measurement Model | A copy of `_private/host/t04/measure-classified.skp`: 50,040 Edges in ten Zones, 5,000 assigned, every Face classified |
| Processes | Three fresh launches through `host_bridge.py launch`: the fixture; the Model the first saved; the measurement Model |
| Controls | The bridge for every call and readback, one per call; no native gesture is asserted. Export destinations are approved through `ApprovedLocations.approve`, standing in for the native save dialog, and replaced with the `expected_destination` state the preflight reports. Driver: `_private/host/t08/t08-run.sh` |
| Reload | `_private/host/t08/readback.py` in the repository `.venv`, whose honeybee-core 1.64.65, honeybee-energy 1.123.23, honeybee-ph 1.33.65 and ladybug-geometry 1.35.3 are the vendored wheels' versions |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Export and readback | One Building-Segment shared by the three Rooms carries exactly the five runs: Parapet 1 14.000 m and Parapet 2 12.000 m (`Polyline3D`, 4 points, psi 0.05, `15-Ambient`), Slab edge 1 14.000 m (psi 0.12, `16-Perimeter`), Footing 1 12.000 m (psi -0.02, `17-FS/BC`), Balcony 1 4.000 m (`LineSegment3D`, psi 0.25, quantity 2); identifiers equal the schedule's; conformance passes on the reloaded bytes | `reference-readback.json` |
| Metadata guard | The pair is written with each bridge's `user_data` holding only `ph_composer.thermal_bridge_type_id`, the declared key | `reference-readback.json` |
| Save, reopen, re-export | `thermal_bridges` byte-identical; the whole HBJSON equal after normalizing only honeybee-ph's generated default UUIDs and unordered Energy collections, as P1-E and P2-14 compared | `reopen-compare.json` |
| Outside a Zone | The root line's copied record: preflight `outside_zone`, non-blocking, locating the Edge; in the export's findings and report; no run in the HBJSON | `warnings-preflight.json`, `warnings-readback.json` |
| Warnings | `counted_twice` on both Parapet runs (now closed, 18.000 and 16.000 m), `no_envelope_face` and `on_window_perimeter` on the sill line, `outside_zone`; none blocks; the same codes in the report; six runs exported; conformance passes | `warnings-*.json` |
| Blocking keeps the prior pair | A cleared Parapet psi-value blocks in preflight (`psi_missing` x2); the export fails as `thermal_bridge.psi_missing`; the prior pair's SHA-256 and sizes are unchanged | `warnings-before-block-pair.json`, `warnings-after-block-pair.json` |
| Forced refusal | Offline seam, pinned stack, packaged `export_json` with conformance: the refused run is left out with one non-blocking `object.unavailable`; the other four export | `offline-refusal.txt` |
| Required refusal | Offline: the same refusal from a required section blocks and withholds the canonical model | `offline-refusal.txt` |
| Snapshot measurement | See below | `measure.json` |

## G-04 measurement

| Read | Result |
| --- | --- |
| `GeometrySnapshot.capture`, 76,959 entries (51,818 Edge entries, 5,000 tagged, 25,130 Faces) | 1,784, 1,708, 1,647 ms |
| Thermal-bridge contributor, its own work over that snapshot | Zones projection 187 ms; 5,000 facts 82 ms; 1,250 runs and findings 278 ms |

The contributor reads the snapshot's Edge entries the capture already holds, so the stage adds no Model walk.
A full collection on this Model did not finish in a dry run: the Zones Faces section looks up each Face's Zone
by scanning the snapshot (`Zones::ExportProjection.zone_owner` per Face, about 25,000 x 77,000), still running at
five minutes. That is the Zones section's cost on any export of this size, before and after this stage; the
thermal-bridge contributor no longer has it (pre-gate finding). Recorded as a follow-up.

## The forced refusal

T08's refusal rows reuse the Python section's test seam, run through the packaged `export_json` entry point with
the pinned stack, not a named host fault. The development faults `lost_reply`, `silent_runtime` and
`failed_write` do not reach the translation, and the only refusal the section makes, a Building-Segment already
holding a run's identifier, cannot be arranged through the product.

## Limits

- Result-document findings carry no `locate`; the preflight rows do.
- The snapshot keeps no Group definition, so a copied Group whose storage two Groups still share reads as
  unshared in the export, where the live schedule reports `shared_definition`.
- A tagged Edge inside a cutting component is in the live schedule (`outside_zone`, `cutting_instance`) but not in
  the snapshot, so the export says nothing of it.
- The live outline read and the export's come from Windows' two placements of a Unit (`ReadContext#polygon` and
  `ExportAssessment`); they agree on the reference model.
