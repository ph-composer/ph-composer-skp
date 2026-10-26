# Phase 3a acceptance register: Spaces

DATE: 2026-10-17
STATUS: Complete 2026-10-17 and archived. P3a-01 to P3a-12 merged to main (PRs #135 to #171); S01 to S11 pass with ledger results and S12's integrated run is done; the earlier cases the Spaces changes screened were rerun, and the two regressions found (#179, #188) were fixed (#187, #190) and rechecked. ZO-O7 fails on #181, a follow-up. Not released.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#133](https://github.com/bldgtyp/ph-composer/issues/133)

The [Spaces PRD](PRD.md), "Acceptance shape", supplies the detailed cases. This register
supplies the closure gates. Record a source-controlled evidence summary per stage under
`evidence/` with commit, build, fixtures, checks, exact host versions and remaining limits. Keep
SKP files and captures in `_private/`.

Ids use the prefix S, still free on 2026-10-15. `A`, `R`, `E`, `UXK`, `HGUI`, `PTAB`, `ZO`, `UXR`
and `GH` are taken in [`native-acceptance/cases.json`](../../native-acceptance/cases.json).

| ID | Owner, stage | Required evidence | State |
| --- | --- | --- | --- |
| S01 | Shared, P3a-01 | CONTRACTS section 7 answered from code; architecture review recorded. A stamped Group inside a Zone: its Faces are absent from `zones.faces.list`, Suggest, the Shift-click flood, Solve and the export snapshot, offline and on the host. A Zone with every Face omitted produces the declared outcome and the diagnostic model reloads. (The section-cycle refusal and the Ruby units are on `main` and leave this row.) The Phase 1 and Phase 2 cases the ledger screens are repeated | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md), including the native Shift-click. The screened earlier cases were rerun the same day: all pass except A09 and UXR-PAINT on the narrow layout ([#179](https://github.com/bldgtyp/ph-composer/issues/179), a P3a-06 regression) and ZO-O7 on the component path ([#181](https://github.com/bldgtyp/ph-composer/issues/181)) |
| S02 | Spaces, P3a-02 | Schema round trips for the three records; `create` from explicit Face and Zone references under a rotated wrapper; a multi-Volume Space with two heights; airflows absent, zero and set stay distinct through edit, Undo/Redo and reopen; projected area for a sloped face; every finding of CONTRACTS section 6 that needs no reconciler; `user_data` and extension payloads survive edit, Undo/Redo and reopen; stale `expected_values` and a failed batch write nothing; a panel-closed script creates a Space, marks a floor, sets a height and two airflows and reads them back through registered operations only | Pass 2026-10-15, [evidence](evidence/p3a-02-space-records.md); rerun pass 2026-10-16 with a ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md) |
| S03 | Session and spaces, P3a-03 | Fresh process, the native-edit matrix: enter and leave a Volume; exit protection when the commit arrives before the path change; switch directly between two Volumes; save from inside a Volume and reopen there; move a Volume outside its context and Restore position; draw at the Space root; Undo and Redo across automatic work with no extra Undo entry; two Models. Offline: exactly one module assigns `active_path` and a test refuses another; the stub refuses a path change inside pre-save; an idempotent pass writes nothing | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md): native Cmd+S and a 1-minute autosave leave the user in the Volume (D3a-19), and a fresh open protects it |
| S04 | Spaces and zones, P3a-04 | A native copy of a Space, and a `5x` array of one, is made independent in the gesture's Undo step with the next free numbers (D3a-14), and a cut and paste is left alone; a native copy of a Volume and of a Floor Segment each raise `space.duplicate_identity`, recorded with what the gesture delivered; Make independent clears each in one Undo step and keeps `user_data`; a Space inside a repeated component reports with no repair. Move Space to Zone under a rotated wrapper holds world position, keeps ids and records, rewrites the stamp, refuses with a Volume open, and is one Undo step. Restore Zone reads Space stamps | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md), with the rotated wrapper, repeated component, `user_data` and Restore Zone run natively on a scratch copy |
| S05 | Colour-by, P3a-05 | A synthetic mode with derived geometry and a synthetic readout register and draw with no change to the service's callers; a derived-only entry; depth, tag and hidden-ancestor behavior; the legend counts unchanged; draw cost measured at the representative size the overlay spike used. Operation marks on the Window Type mode, with `git diff` for that slice touching only `features/windows/` and its tests (D3a-5). The Phase 1 and Phase 2 Colour-by cases the ledger screens are repeated | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md) (synthetic composition): draw cost re-measured, fill p95 adding 12.87 ms; operation marks read as the exterior elevation; D3a-5 holds (slice B touches only `features/windows/` and its test) |
| S06 | Zones and UI kit, P3a-06 | The Zones tab on the host: renamed, no reserved Spaces tab; with Faces alone the view row is hidden and the screen is unchanged; with the synthetic Zone-only view installed, switching keeps the filter, expanded Zones, checked Zones and Locate and sends no action; Classify paint stops cleanly on a view switch; the active view returns after reopening the panel and the Model. The Zones / Faces cases the ledger screens are repeated. Architecture and UI polish reviews recorded | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md) (synthetic composition), with the synthetic Areas view; the Faces-alone view row offline; a focused filter blocks a view switch ([#185](https://github.com/bldgtyp/ph-composer/issues/185)) |
| S07 | Spaces and UI kit, P3a-07 | The Spaces view on the host: Zone, Space, Volume and Segment rows with no Space Floor row; in-place edit with stale-value refusal, including the weighting factor as a number from 0 to 1; range edit and paste as one Undo step; the three airflow cell states, a clear returning a Space to inheriting; Zone row sums, the imbalance marker at the D3a-12 threshold, and the dash with the inheriting count; the selection bar for checked rows; Select by through a column's value filter and the check-all box (D3a-18); Locate and context entry from rows with the open Volume closed and protected first; findings with their repairs; Colour by weighting factor from its column header. A unit switch on a 300-Space table measured (U1-F1). The UI polish review recorded | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md), except the 300-Space timing ([#154](https://github.com/bldgtyp/ph-composer/issues/154)) |
| S08 | Spaces, P3a-08 | Mark floor with Ed at the mouse, started from the Weighting factor column menu: click and drag inside a Volume at 1.0, 0 and a typed 0.6; a face outside any Volume offers Create Space; refusals on the status bar; Escape, deactivation, the pressed header glyph stopping it; one Undo step per gesture; Colour by weighting factor turned on. Create Space from SketchUp's context menu with its preview. Classify and Mark floor in turn leave one tool and one pressed glyph | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md), with native held drags at 0 and 1; the typed 0.6 was entered and joined the paint choices but was not painted with the tool |
| S09 | Spaces, P3a-09 | The four modes colour Floor Segment faces and prisms alike; By Space colours are stable across a reopen; the prism base is the projected face; labels at the reference point with the legend toggles; selection totals in SI and IP; labels and totals shown with no mode active; nothing is added to the SKP | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md); three of four Spaces share a By Space colour ([#183](https://github.com/bldgtyp/ph-composer/issues/183)) |
| S10 | Spaces and export, P3a-10 | The normal packaged RBZ exports the reference model; the exact HBJSON reloads; each `Space` is on its Zone's Room with name, number, `quantity` 1, its volumes, heights, factors and `geometry`; iCFA and net volume from the loaded objects equal the panel's; the three airflow cases read back as m3/s with explicit zeros where the any-set rule says; record `user_data` arrives on each `Space`, `SpaceVolume` and `SpaceFloorSegment` beside the reserved `ph_composer` key (D3a-15); every blocking row blocks; the off-to-the-side line and the per-Zone schedule appear in the report; the metadata guard passes | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md), with both blocking rows and an export from inside an open Volume on the host |
| S11 | Spaces, P3a-11 | Height from solid on the wedge: the height equals volume over net floor area, both numbers are reported, one Undo step; refusals for an open solid, a zero-area Volume and a wrong selection | Pass 2026-10-16, ledger result in the [rerun evidence](../../native-acceptance/evidence/phase-3a-rerun-2026-10-16.md), with the native Undo and Redo; the zero-area refusal offline; the wrong-selection refusal holds on the preview and panel route only, since the native entry is silent ([#184](https://github.com/bldgtyp/ph-composer/issues/184)) |
| S12 | Integration, P3a-12 | Both offline Ruby gates, coverage, browser and runtime checks; packaged inventory and footprint against the 22 MB target and 24 MB ceiling; the PRD's host gate from a fresh process on the reference model, with nested edit paths, two Models, Undo/Redo, save and reopen inside an open Volume, and export | Run 2026-10-16 in [evidence](evidence/p3a-12-acceptance.md): offline gates pass on both Rubies; 23,994,063 installed bytes, above the target and 5,937 bytes under the ceiling |

## Synthetic reference model

**S04/S12 addition, D3a-13 (2026-10-12):** native-copy a Zone containing Spaces with authored
Volumes/Floor Segments and Window Units. Prove independent Space-child storage/identities,
copied Zone stamps and typed internal reference remapping, unchanged original children, and
Windows' existing Type/Unit protocol. Check whole-gesture refusal/failure, one Undo/Redo, repeated
reconciliation and save/reopen. S10 must reload actual copied Spaces attached to the copied Room
from HBJSON, with distinct identifiers and matching weighted area/net volume/airflows. Counts alone are
insufficient. Evidence: [evidence](evidence/p3a-12-acceptance.md), 2026-10-16.

Extend the Phase 2 reference: adjacent boxes, Zone A 5 x 4 x 3 m and Zone B 4 x 4 x 3 m. Floor
outlines are separate faces drawn inside each Zone's edit context, never the envelope Floor (Q1).

| Space | Zone | Volumes and Floor Segments | Height | Airflows, m3/h |
| --- | --- | --- | --- | --- |
| 101 Living | A | One Volume, one 3.0 x 4.0 m segment, weighting factor 1.0 | 2.5 m | supply 60 |
| 102 Bath | A | One Volume, one 2.0 x 2.0 m segment, weighting factor 1.0 | 2.4 m | extract 40 |
| 103 Hall | A | Volume 1: one 2.0 x 2.0 m segment, weighting factor 1.0. Volume 2: one 1.0 x 2.0 m segment, weighting factor 0 | 2.5 m and 5.0 m | transfer 20 |
| 201 Loft | B | One Volume, one sloped face whose horizontal projection is 3.0 x 4.0 m, weighting factor 1.0; drawn off to the side of the Zone, from inside its edit context | From a wedge solid of 36 m3 | all unset |

Expected, by hand:

| | Weighted area (iCFA), m2 | Floor area, m2 | Net volume, m3 |
| --- | --- | --- | --- |
| 101 | 12.0 | 12.0 | 30.0 |
| 102 | 4.0 | 4.0 | 9.6 |
| 103 | 4.0 | 6.0 | 10.0 + 10.0 = 20.0 |
| Zone A | 20.0 | 22.0 | 59.6 |
| 201 | 12.0 | 12.0 | 36.0, height 3.0 m |
| Zone B | 12.0 | 12.0 | 36.0 |
| Model | 32.0 | 34.0 | 95.6 |

- Airflows. Zone A is wholly user-specified: supply 60, extract 40, transfer 20, with every unset
  rate counting as zero. Supply and extract differ by more than 10 percent, so Zone A's row carries
  the imbalance marker. Zone B holds one inheriting Space, so its airflow sums read as a dash with
  "1 inheriting" in the tooltip, and its warning is not evaluated.
- Export. 101 writes `_v_sup` 60 / 3600 = 0.016667 m3/s and explicit zeros for the other two.
  201 writes none of the three.
- Copies, for S04. A native copy of Space 102 proves automatic independence (D3a-14); a native
  copy of 103's Volume 2 and of 101's segment proves the finding and Make independent.
- Parent copy. A native copy of Zone A with its Spaces and representative cutting/glued Window
  Units for D3a-13. Window Types remain the existing definitions; copied Spaces are independent.
- A second Zone-A-sized Space group left at the model root, for `space.outside_zone`.

Keep the hand calculation beside the fixture. Compare actual identifiers and reference targets
after save, reopen and HBJSON reload; matching counts alone do not prove a round trip.

## Completion boundary

S01 to S12 close Phase 3a. Every "through PHX" check in the PRD is excluded
and stays open in [metr-export](../../features/unscheduled/metr-export/README.md). The height drag handle
(Q6) is not in any row. Thermal bridges acceptance is T01 to T09 in [its register](../phase-03b-thermal-bridges/ACCEPTANCE.md). SketchUp 2023 and
Windows remain their own gates.
