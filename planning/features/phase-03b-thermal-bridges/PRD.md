# Thermal bridges

DATE: 2026-09-18
STATUS: Scoped. Interviewed 2026-10-03; answers recorded in [DECISIONS.md](DECISIONS.md) and folded in below. Corrected to the code on `main` at `420c783a` on 2026-10-21 (the assignment id and the HUD label shape).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Problem

A Phius model needs every linear thermal bridge as a length and a psi-value. Today the consultant
measures edges by hand or draws polylines in Rhino. In SketchUp the edges already exist: the
slab edge, the parapet, the balcony line are the edges of the faces the consultant has assigned.
The workflow should be three steps. Build the type once, select the edges, assign.

## Port disposition

Nothing to port from the predecessor's features. It had no thermal bridge feature and designPH
owned that data.

| Part | Disposition | Note |
| --- | --- | --- |
| Record engine, typed ids, `source` and fingerprint | Port | From the foundation transplant |
| Inventory table, inline edit, usage scan on open and Refresh | Port | The Assemblies inventory pattern |
| Classify tool | Adapt | From face-assignment. It picks faces. Picking edges is a different `PickHelper` path |
| Colour-by component and HUD legend | Adapt | It fills faces. Assigned edges draw as `derived` segments, the shared extension Spaces brings, with a heavier stroke per mode (D3b-11) |
| Thermal Bridge Type and assignment records | New | |
| Edge tagging rules | New | Shared with piping and ducting |
| Python translation to `PhThermalBridge` | New | Small. One class, one target |

## Vocabulary

Agreed in the interview on 2026-10-03 and folded into `context/UBIQUITOUS_LANGUAGE.md`.

| Term | Meaning |
| --- | --- |
| Thermal Bridge Type | A named junction detail with one psi-value. Model-local, editable, reusable |
| Thermal bridge | One assigned run of edges with a measured length. The exported thing |
| Run | A chain of connected edges with the same Zone, type and quantity, ending at a free end or a junction. A closed loop is one run. Derived at each scan, never stored |
| Group | The three-way class honeybee-ph and METr share. Stored as honeybee-ph's `15-Ambient`, `16-Perimeter`, `17-FS/BC`; shown in METr's words, the third confirmed on METr's screen in P3b-05 |

## What honeybee-ph and METr take

Verified in `honeybee_energy_ph/construction/thermal_bridge.py`, `honeybee_ph/bldg_segment.py`
and PHX `to_METr_JSON/metr_schemas.py`.

- `PhThermalBridge`: `display_name`, `quantity` (default 1.0), `group_type` (15 Ambient,
  16 Perimeter, 17 FS/BC), `psi_value` (default 0.1), `fRsi_value`, `is_interior_pipe`, and
  `geometry` as a `LineSegment3D` or `Polyline3D`. Length comes from the geometry.
- Thermal bridges live on the honeybee-ph `BldgSegment`, keyed by identifier. They do not live
  on a Room or a Face.
- METr receives `n`, `typeTbZ` (the group number, negated), `lengthTbZ` and `psiTbZ` per zone.
  `fRsi_value` and `is_interior_pipe` are not written to METr.
- There is no point thermal bridge class. A chi-value exists only on a window frame element. D3
  confirms that point thermal bridges and chi-values are wholly outside the MVP. See Q3.

## Records

```
ThermalBridgeType  id (tbt_), name, psi_w_mk, group, color, notes, datasheet_links, source,
                   schema_version

edge assignment    id (tbe_), thermal_bridge_type_id, quantity, schema_version, user_data
(on the Edge)
```

`group` is required, one of `15-Ambient`, `16-Perimeter` or `17-FS/BC`, and a new type starts at
`15-Ambient` (D3b-03, D3b-04). `psi_w_mk` may be negative and may be left empty while a type is
being entered. `quantity` is a positive number, default 1 (D3b-08). There are no timestamps
(D3b-05). The assignment is an attribute on the SketchUp edge. It carries a `tbe_` id because the
record engine requires one on anything a reference target lists (D3b-02's fallback, confirmed from
code on 2026-10-21); a split or copied edge carries the same id, which reads mark as copied and nothing re-issues (D3b-22).
There is no separate thermal bridge record and no Model-level registry of tagged edges (D3b-01).
The schedule and the export both build the list of thermal bridges by scanning edges.

## Behaviors

### Thermal Bridges tab

The reserved Thermal Bridges tab, with two subtabs, Types and Schedule (D3b-17). Types is an
inventory table like Assemblies: name, psi-value, group, colour, used length, notes, datasheet
link. Add, duplicate, delete with a replacement, inline edit. Psi-value is a unit field. A
negative psi-value is legal and common for exterior-dimension models. The assign bar sits above
the table.

### Assign

1. Select edges with the native Select tool, inside a Zone group (Select Connected takes a whole
   parapet). Pick a type and a quantity in the assign bar and press Assign, or right-click and
   choose the type under Thermal bridge. One Undo step. This is the primary route.
2. Or arm the edge tool with a type and click or drag across edges. One Undo step per gesture. This
   is the secondary route, kept because piping and ducting reuse it (D3b-18).
3. Clear removes the assignment. Reassign replaces it.

Only edges inside a Zone group are assignable, and Zones decides which Zone holds an edge
(D3b-09). The Zone gives the thermal bridge its Building-Segment at export. A write through a
shared component, a locked group or another Zone is refused, as it is for Faces. A tag already
inside a shared component definition counts once per placement and is marked shared (D3b-10). One
gesture reaches at most 250 edges; one more refuses the whole gesture (D3b-14).

### Runs

Connected edges that carry the same type and quantity, in the same Zone, export as one thermal
bridge (D3b-06). Edges connect where they share a vertex in one container (D3b-23); SketchUp merges
endpoints within 0.0254 mm inside one container, and two placements of one component never
connect. The 0.0254 mm tolerance is used only across Zones, for the counted-twice warning, and for
the window-perimeter warning. A run ends at a free
end or at a junction where three or more such edges meet, so a T is three runs. A closed loop is
one closed polyline; a single edge is a line segment. A run is named from the type plus a counter,
numbered by Building-Segment, Zone name and position, and identified by a digest of its Zone, type,
container path and endpoints (D3b-07, with the container path added by D3b-23 so two coincident
placements of one component are two runs with two identifiers). Both can change when the geometry does; nothing points at a run. The
schedule shows the same grouping so the list matches what METr will show.

### Schedule

The Schedule subtab: one row per run with Zone, Building-Segment, type, length, psi-value,
quantity, and psi times length times quantity in W/K. Totals by type and by group. Click a row to
select its edges in the model. The schedule is computed when the Schedule opens and on Refresh, not
on every panel refresh: P3b-04 measured it at about two seconds with 5,000 assigned edges in a model
of 50,000, over the refresh budget (D3b-13).

### Colour-by mode

A `Thermal bridges` mode registered with the shared Colour-by component. Assigned edges draw
thick in the type's colour. The HUD legend lists each type with its edge count and total length in
the display units, in the legend's own shape, as "Parapet (12) 26.0 m" (D3b-12, corrected
2026-10-21 to the shipped legend format). Unassigned edges draw nothing, since most edges in a
model are not thermal bridges.

### Validation rows

| Finding | Severity |
| --- | --- |
| Edge assignment points at a deleted type | Blocks export |
| Type has no psi-value and an edge is assigned to it | Blocks export. An unused incomplete type does not block (D3b-21) |
| Assigned edge is outside any Zone group | Warning. Not exported |
| Assigned edge belongs to no assigned envelope face | Warning. The likely cause is a stray line |
| Every Zone Face on the assigned edge is Surface or To neighbour | Warning. An interior junction (D3b-16) |
| Assigned edge coincides with an assigned edge in another Zone | Warning. Counted twice (D3b-16) |
| Assigned edge lies on a placed window Unit's outline | Warning. Window install psi belongs to the Window Type (Q11, D3b-15) |
| Tag inside a shared component definition | Information. Counted once per placement (D3b-10) |
| A run fails to translate or attach at export | Warning. That run is omitted and disclosed; the rest export (D3b-20) |
| Two types assigned to one edge | Cannot happen. One attribute per edge |

### Export mapping

| PH-Composer | honeybee-ph |
| --- | --- |
| Run of edges | `PhThermalBridge.geometry`, a `Polyline3D`, or a `LineSegment3D` for one edge |
| Type `name` plus counter | `display_name` |
| Type `psi_w_mk` | `psi_value` |
| Type `group` | `group_type` 15, 16 or 17 |
| Assignment `quantity` | `quantity` |
| Zone's Building-Segment | The `BldgSegment` whose `thermal_bridges` holds it |
| none | `fRsi_value`, `is_interior_pipe` left at defaults |

The thermal-bridge export section is optional (D3b-20): a run that fails is omitted with a finding
and the HBJSON and report are still written. `quantity` is written as authored; HBJSON is the
canonical artifact. Whether PHX carries a lone bridge's quantity into METr is checked in
[metr-export](../unscheduled/metr-export/README.md), as is every METr row below.

## Edge tagging rules

These apply to this packet, to hot-water-piping and to erv-ducting. They are proposals until the
spike measures them.

1. The assignment is an attribute dictionary on the `Sketchup::Edge`. No separate index keyed by
   `persistent_id`, so a copied edge carries its assignment and a deleted edge takes it away. The
   dictionary carries an id because the record engine requires one, and nothing points at that
   id (D3b-02, D3b-22). A feature whose assignments carry identity that other records point at,
   as piping's parent references do, decides for itself whether it needs B4's registry (D3b-01).
2. SketchUp splits an edge when another edge crosses it or a face is cut. B4 measured that every
   piece keeps the full dictionary, so a split is harmless and needs no repair. P3b-01 measures the
   cases B4 did not run, including the heal when the crossing edge is erased.
3. No observer watches edges. Reads scan the Model; the schedule is scanned on request, as the
   measurement in P3b-04 required (D3b-13).
4. An edge carries at most one assignment of each kind. A thermal bridge edge is envelope
   geometry. A pipe or duct edge is a loose line in its own group. The two never share an edge.

The spike ran as [B4](../../archive/phase-00-foundation/evidence/spike-edge.md) on 2026-09-18.
Its open cases (native Divide and Weld, a push-pull that removes the edge, `intersect_with`, and
the heal) close in P3b-01.

## Decisions from the interview

Ed answered on 2026-10-03. The plan decisions that refine each answer, D3b-01 to D3b-21, are in
[DECISIONS.md](DECISIONS.md) with their own answers.

| # | Question | Answer, 2026-10-03 |
| --- | --- | --- |
| Q1 | Does the assignment live on the edge, with no separate thermal bridge record? | Yes. The edge is the record, with no registry and no id of its own (D3b-01, D3b-02) |
| Q2 | One psi-value per type, or may an assignment override it? | Per type only. A second value is a second type, the same rule Window Types follow |
| Q3 | Point thermal bridges and chi-values: honeybee-ph has no carrier | Confirmed in D3: linear only for MVP. Point bridges and chi-values are not authored, assigned or exported, and are never encoded as fake 1 m linear bridges |
| Q4 | Group words: METr's or honeybee-ph's? | Stored as honeybee-ph's strings, shown in METr's words; the third word confirmed on METr's screen (D3b-03). Required, default Ambient (D3b-04) |
| Q5 | Do connected same-type edges merge into one exported thermal bridge? | Yes, as maximal chains split at junctions (D3b-06), named from the type plus a counter (D3b-07) |
| Q6 | Is `quantity` exposed? | Yes, on the assignment, default 1. Kept in HBJSON; the METr consequence is checked in metr-export (D3b-08) |
| Q7 | A shared edge between two Zones: which Zone owns it? | The Zone group that holds it. Interior junctions and edges counted twice across Zones are warnings (D3b-16) |
| Q8 | Are Thermal Bridge Types a fifth library kind? | Not now. The first candidate for roadmap 5.4 |
| Q9 | Does a type hold a link to the psi-value calculation report? | Yes, `datasheet_links` from the common fields (D3b-05) |
| Q10 | Where is the tab? | The reserved Thermal Bridges tab, with Types and Schedule subtabs (D3b-17) |
| Q11 | Window install edges: can a user assign a Thermal Bridge Type to a window perimeter? | It should not happen. Psi-Install Types own those edges, and an assigned edge on a placed Unit's outline is a warning (D3b-15) |

## Non-goals

Point thermal bridges and chi-values in any MVP surface or artifact. They may be reconsidered only
as later scope after the canonical data model has a real point-bridge carrier.

No psi-value calculation. No fRsi. No automatic junction detection. No Flixo link.

## Acceptance shape

On a synthetic two-Zone model: build the types, assign parapet runs, a slab edge and a single
balcony line; confirm the schedule lengths against hand measurement; split an assigned edge and
confirm the documented behavior; export and find the runs in the HBJSON on the right
Building-Segments. One Undo per assign. Save and reopen. The detailed register and the
hand-calculated model are in [ACCEPTANCE.md](ACCEPTANCE.md). The METr check (`typeTbZ`, length,
psi-value) waits with [metr-export](../unscheduled/metr-export/README.md).

## Prior art and evidence

- honeybee-ph `honeybee_energy_ph/construction/thermal_bridge.py`, `honeybee_ph/bldg_segment.py`.
- PHX `to_METr_JSON/metr_schemas.py`, `_PhxComponentThermalBridge`.
- honeybee-grasshopper-ph "HBPH - Create Thermal Bridges": polylines in, thermal bridges out.
- [face-assignment](../../archive/face-assignment/PRD.md): Classify tools and the Colour-by component.
- [assemblies](../../archive/assemblies/PRD.md): the inventory pattern and the usage scan rule.
