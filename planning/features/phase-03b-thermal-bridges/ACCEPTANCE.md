# Phase 3 acceptance register: thermal bridges

DATE: 2026-10-03
STATUS: In progress. T01 passes (2026-10-21, merged); T02 passes (2026-10-25, merged); T03 passes (2026-10-25, merged); T04 to T09 open. Re-read against `main` at `420c783a` on 2026-10-21.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

The [PRD](PRD.md), "Acceptance shape", supplies the detailed cases. This register supplies the
closure gates for Phase 3b; Phase 3a's [Spaces register](../../archive/phase-03a-spaces/ACCEPTANCE.md)
holds S01 to S12. Record a source-controlled evidence summary per stage under this folder's
`evidence/` with commit, build, fixtures, checks, exact host versions and remaining limits.
Keep SKP files and captures in `_private/`.

Ids use the prefix T. `A`, `E`, `S`, `R`, `UXR`, `PS`, `DV`, `ZO`, `GH`, `SH`, `UXK`, `HGUI` and
`PTAB` are taken in [`native-acceptance/cases.json`](../../native-acceptance/cases.json) (read
2026-10-21). A case row carries `authority`, `id`, `label`, `mode`, `native_control_required` and
`paths`; record each run with `acceptance_case.py begin` and `finish` so the ledger row is a Pass.

| ID | Owner, stage | Required evidence | State |
| --- | --- | --- | --- |
| T01 | Shared, P3b-01 | CONTRACTS section 7's two remaining questions answered by focused test and added to section 8; the D3b-22 and D3b-23 answers folded into section 2 and `runs/`; architecture review recorded; `PLANNING_IDS` refuses a planted `T01` and `F26` in `src/` (`P3b-01` and `D3b-02` already fail). Host: B4's open cases on a tagged edge, each with Undo, Redo, save and fresh-process reopen: native Divide, native Weld, a push-pull that deletes the edge, `intersect_with` across it, and erasing the crossing edge so two tagged halves heal into one. The result table is folded into `context/SKETCHUP_HOST_BEHAVIOR.md` | Pass 2026-10-21 on 26.1.188 at `bec31a4c` (PR #302, merged as `91366643`): [evidence](evidence/p3b-01-edge-host-facts.md); offline half on both Rubies; architecture review by Codex gpt-6-astra, two cycles |
| T02 | Thermal bridges, P3b-02 | Schema round trip for the type; a negative psi stores and reads back; the group refuses a value outside the three strings; default group and colour on create; guarded delete refuses while in use (from P3b-03 on); `user_data` and extension payloads survive edit, Duplicate, Undo/Redo and reopen; a panel-closed script creates, edits and duplicates a type through registered actions only | Pass 2026-10-25 on 26.1.188 at `6a805df1` (PR #308, merged as `b4b6d08c`): [evidence](evidence/p3b-02-type-records.md) |
| T03 | Thermal bridges and zones, P3b-03 | Assign and Clear on explicit references and on the native selection, each one Undo step; reassign replaces; a stale `expected_values` and an unreachable Edge each refuse the whole command and write nothing; refusals through a ComponentInstance, a locked Group and a nested Zone path carry Zones' `target.*` codes; the gesture ceiling and one over; `zones.containment` answers direct, wrapped, rotated-wrapper, cutting-instance and outside-every-Zone paths; delete with replacement rewrites every assigned Edge, direct and nested, in one Undo step, and Undo restores the type and every assignment; a split, a copy and a cut-and-paste of an assigned Edge read as T01 measured | Pass 2026-10-25 on 26.1.188 at `089db1b8` (PR #309, merged as `96d09161`): [evidence](evidence/p3b-03-edge-assignment.md) |
| T04 | Thermal bridges, P3b-04 | Runs on the reference model equal the hand calculation below to 0.001 m and 0.001 W/K; a T of three same-type edges is three runs; a closed loop is one closed run; different quantities split a run; two coincident Edges in different Zones do not join (D3b-23) and raise `counted_twice`; every finding row of CONTRACTS section 6 that needs no Windows read appears on its case; schedule cost measured at 5,000 assigned Edges in a Model of 50,000 Edges and recorded against D3b-13's 200 ms repaint target; `runs.locate` selects and zooms into a nested Zone | Open |
| T05 | Thermal bridges and UI kit, P3b-05 | The Thermal Bridges tab on the host: create, in-place edit with stale-value refusal, duplicate, guarded delete and delete with replacement in the Types inventory; assign and clear from the panel and from the right-click menu on a selection of Edges; the Schedule with totals by type and group, Locate from a row; unit switch keeps drafts; METr's third group word checked on its screen (D3b-03). The UI polish review recorded | Open |
| T06 | Colour-by and thermal bridges, P3b-06 | The `by_type` mode draws assigned Edges thick in type colour, direct and nested, depth-tested; nothing for unassigned Edges; a hidden tag and a hidden ancestor hide the drawing and keep the legend; the HUD row reads "label (count) figure" with each type's total length in the display units; Show only this and Locate from the legend; draw cost at 5,000 assigned Edges recorded. The Phase 1, Phase 2 and S05 Colour-by cases the ledger screens are repeated | Open |
| T07 | Thermal bridges, P3b-07 | The edge tool with Ed at the mouse: hover highlight, click and drag across Edges, one Undo step per gesture; a type change mid-drag does not change the gesture; refusals on the status bar and in the session notice; Escape, deactivation, a Model switch and a raised callback each leave nothing written; the gesture ceiling and one over | Open |
| T08 | Thermal bridges and export, P3b-08 | The snapshot's existing `edge` entries measured on the 50,000 Edge Model; the normal packaged RBZ exports the reference model; the exact HBJSON reloads; `properties.ph.bldg_segments` holds one segment per Building-Segment carrying exactly the expected runs, with identifier, `display_name`, geometry type, length, psi, group and quantity read back from the loaded objects; the off-model and outside-Zone tags are absent and disclosed; each blocking row blocks and each warning row appears in preflight and the report; the window-perimeter warning on its case; a run whose attach is forced to refuse (through the Python section's test seam or a named fault P3b-08 adds, since none of `lost_reply`, `silent_runtime` and `failed_write` reaches the translation) is omitted with a non-blocking `object.unavailable` finding, the other runs export and the pair is written (D3b-20); a required section's refusal still withholds the model; the metadata guard passes; save, reopen and re-export give the same HBJSON | Open |
| T09 | Integration, P3b-09 | Both offline Ruby gates, coverage, browser and runtime checks; packaged inventory and footprint through `vendor.py --check` against its `installed_target_bytes` (24,000,000), `installed_ceiling_bytes` (26,000,000) and `installed_growth_bytes` (1,500,000) over `installed_baseline_bytes` (23,994,083, the Phase 3a close; D3a-20); the PRD's acceptance shape from a fresh process on the reference model with nested edit paths, two Models, Undo/Redo, save and reopen, and export; the edge tagging rules folded into `context/` for piping and ducting | Open |

## Synthetic reference model

Extend the Phase 2 reference: adjacent boxes, Zone A 5 x 4 x 3 m spanning x 0 to 5 m and Zone B
4 x 4 x 3 m spanning x 5 to 9 m, both y 0 to 4 m, one Building-Segment, the shared wall at
x = 5 m. Each Zone group holds its own edges, so the shared wall's edges exist once in each Zone.

### Types

| Type | psi, W/(m K) | Group | Note |
| --- | --- | --- | --- |
| Parapet | 0.050 | `15-Ambient` | |
| Slab edge | 0.120 | `16-Perimeter` | |
| Footing | -0.020 | `17-FS/BC` | A negative psi-value, legal for exterior-dimension models |
| Balcony | 0.250 | `15-Ambient` | Assigned with quantity 2 |
| Draft | none | `15-Ambient` | Unused and incomplete; must not block export (D3b-21) |

### Assignments and expected runs

| Run | Zone | Edges | Shape | Length, m | Quantity | psi x L x n, W/K |
| --- | --- | --- | --- | --- | --- | --- |
| Parapet 1 | A | Roof south, west and north edges, (5,0,3) to (0,0,3) to (0,4,3) to (5,4,3) | Open `Polyline3D`, 4 points | 14.000 | 1 | 0.700 |
| Parapet 2 | B | Roof south, east and north edges | Open `Polyline3D`, 4 points | 12.000 | 1 | 0.600 |
| Slab edge 1 | A | Ground south, west and north edges | Open `Polyline3D`, 4 points | 14.000 | 1 | 1.680 |
| Footing 1 | B | Ground south, east and north edges | Open `Polyline3D`, 4 points | 12.000 | 1 | -0.240 |
| Balcony 1 | B | One line across the south wall at z = 1.5 m, (5,0,1.5) to (9,0,1.5), drawn before classification so it splits the wall into two classified Faces. Zone B's south wall carries no window Unit, so the split strands no glued Unit (B3) | `LineSegment3D` | 4.000 | 2 | 2.000 |

Expected totals, by hand:

| By | Value |
| --- | --- |
| Parapet | 26.000 m, 1.300 W/K |
| Slab edge | 14.000 m, 1.680 W/K |
| Footing | 12.000 m, -0.240 W/K |
| Balcony | 4.000 m at quantity 2, 2.000 W/K |
| Group `15-Ambient` | 3.300 W/K |
| Group `16-Perimeter` | 1.680 W/K |
| Group `17-FS/BC` | -0.240 W/K |
| Model | 5 runs, 4.740 W/K |

The roof edges at x = 5 m are not assigned, so each parapet run ends at the shared wall and Zone A
and Zone B each hold one open run. Run names follow D3b-07 and are fixed once it is answered.

### Finding cases

Each is added by its stage's test or host gate, not left in the base fixture, so the base export
stays clean.

| Case | Expected |
| --- | --- |
| Assign Parapet to the roof edge at x = 5 m in both Zones | `thermal_bridge.counted_twice` on both, `thermal_bridge.interior_junction` on both. Parapet 1 becomes a closed run of 18.000 m and Parapet 2 one of 16.000 m |
| Copy the Balcony line to the Model root | `thermal_bridge.outside_zone`; not exported |
| A loose line on Zone A's south wall along the sill of its fixed window unit, assigned Slab edge | `thermal_bridge.no_envelope_face`; `thermal_bridge.on_window_perimeter` |
| Delete the Footing type with Slab edge as replacement | Footing 1's Edges name Slab edge; one Undo step restores both |
| Clear Parapet's psi-value | `thermal_bridge.psi_missing` blocks export |
| Force one run's attach to refuse (test fault) | That run omitted with a non-blocking `object.unavailable`; the other four export |
| Split one Parapet 1 Edge with a crossing line, then erase the line | Parapet 1 is unchanged in length and stays one run, if T01 shows the healed edge keeps the dictionary |
| Make Component from the Balcony line and place it twice in Zone B | Two runs, `thermal_bridge.shared_definition` on each |
| Split one Parapet 1 Edge, then read both pieces' assignments | Both carry the same `tbe_` id and read as `copied`; the schedule is unchanged; no finding and no repair (D3b-22) |

Keep the hand calculation beside the fixture. Compare actual identifiers and reference targets
after save, reopen and HBJSON reload; matching counts alone do not prove a round trip.

## Completion boundary

T01 to T09 close Phase 3b. Every METr check in the PRD, and the PHX
treatment of `quantity` (F18), is excluded and stays open in
[metr-export](../unscheduled/metr-export/README.md). Point thermal bridges are out by D3.
SketchUp 2023 and Windows remain their own gates.
