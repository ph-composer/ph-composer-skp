# Hot water piping

DATE: 2026-10-21
STATUS: Requested. Draft, not interviewed. Re-baselined against `main` at `420c783a` on 2026-10-21.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

Phius counts hot water distribution losses from the pipes themselves: length, diameter, material
and insulation. On a multifamily project this is hundreds of metres of pipe. The consultant
already has the building in SketchUp, so tracing the risers and branches as lines over the model
is the fastest measurement there is. The extension's job is to turn those lines into the
structure METr wants.

## What main and Phase 3b supply

Read on 2026-10-21 at `420c783a`. Paths are relative to `src/ph_composer/`. This replaces the
2026-09-18 port disposition. Phase 3b (thermal bridges) is scoped and interviewed, with nine stages
P3b-01 to P3b-09, none authorized; the rows marked "3b" exist only once that stage merges.

| Need | State | Where |
| --- | --- | --- |
| Catalog record kinds with the common authored fields, references, referrer handlers | Exists | `core/records/`; `context/CONTRACTS.md`, "Records and extension data". No timestamps |
| Edge entries in the export snapshot: world SI endpoints, vertex ids, Face ids, dictionaries | Exists | `export/geometry_snapshot.rb` (G-02, PR #119). A contributor filters edge entries by its own dictionary; no snapshot change |
| Entity-owned records on an Edge, the edge reference target, assign and clear by native selection | 3b, P3b-03 | [p3b-03](../../phase-03b-thermal-bridges/phases/p3b-03-edge-assignment.md); the edge tagging rules below |
| The chain rule: connected same-type edges into runs with lengths, pure Ruby | 3b, P3b-04 | `features/thermal_bridges/runs/` in the 3b [contracts](../../phase-03b-thermal-bridges/CONTRACTS.md); it moves to `core/` when piping arrives as its second user (3b STATUS, "Deferred out of this plan") |
| Coloured edges in the viewport | Partly | `derived` segments on an ordinary Colour-by entry exist (P3a-05; `context/EXTENSIBILITY.md`, "Colour-by derived geometry"). The stroke weight for thick lines is P3b-06 (H14). `ColourBy::LineEntry` was superseded; there is one line primitive |
| The edge tool, the secondary route | 3b, P3b-07 | [p3b-07](../../phase-03b-thermal-bridges/phases/p3b-07-edge-tool.md). Select then Assign is the primary route (`context/TECH_STACK.md`, "Geometry first, then action"; D3b-18). The first draft's "arm the Classify tool" named Faces' paint tool, which does not pick edges |
| An export contributor over edges with a Python section | 3b, P3b-08 | [p3b-08](../../phase-03b-thermal-bridges/phases/p3b-08-thermal-bridge-export.md), the pattern this packet's section follows |
| Inventory table, in-place drafts, subtabs nav, length and linear quantities | Exists | `html/inventory.js`, `record_edits.js`, `subtabs.js`; units `length` exists in Ruby and the panel, nominal pipe size is [units Q2](../../cross-phase/units/PRD.md) |
| The Hot Water System record | [equipment](../equipment/README.md), family 2 | Not started |
| METr | Deferred | PHX is not in the pinned wheels. [metr-export](../../unscheduled/metr-export/README.md) owns conversion and import; every METr claim below is checked there |

Handed to this packet by Phase 3b (its STATUS, "Deferred out of this plan"): whether an
identity-bearing assignment needs a Model-level edge registry (D3b-01 decided none for thermal
bridges), and moving the run builder to `core/`. Under Q1's recommendation, by connection, a pipe
assignment carries no parent reference and needs no registry; it still carries an id, as every
reference-target record does (3b D3b-22, open).

The predecessor's M1 brief (`../../ph-navigator-sketchup/planning/phases/M1_piping.md`) still
applies: its open questions are answered or carried below, and its boundary, no new
general-purpose drawing tool, is kept.

## Vocabulary

Proposed. `context/UBIQUITOUS_LANGUAGE.md` is not changed until the interview.

| Term | Meaning |
| --- | --- |
| Pipe Type | A named pipe specification: material, diameter, insulation. Model-local and reusable |
| Pipe | One drawn SketchUp edge that carries a Pipe Type |
| Pipe-Segment | honeybee-ph's `PhHvacPipeSegment`. Always qualified, under the rule that gave Building-Segment and Layer-Segment. One per Pipe at export |
| Role | What a Pipe does: Trunk, Branch, Fixture or Recirculation. honeybee-ph says fixture, METr says twig |
| Piping group | A SketchUp group that holds drawn Pipes and nothing else |

## What honeybee-ph and METr take

honeybee-ph re-read at the pinned 1.33.65 on 2026-10-21 (`honeybee_phhvac/hot_water_piping.py`,
`hot_water_system.py`). PHX was read on 2026-09-18 and is not in the pinned runtime; its rows
are checked in metr-export.

- `PhHvacPipeSegment`: `geometry` (a `LineSegment3D`, required), `diameter_mm`,
  `insulation_thickness_mm`, `insulation_conductivity` (W/(m K), no suffix),
  `insulation_reflective`, `insulation_quality` (1 None, 2 Moderate, 3 Good), `daily_period`,
  `water_temp_c`, `material`.
- `material`: 1 Copper M, 2 Copper L, 3 Copper K, 4 CPVC CTS SDR, 5 CPVC Sch 40, 6 PEX, 7 PE,
  8 PEX CTS SDR.
- `PhHvacPipeElement`: a set of segments. `PhHvacPipeBranch`: one element plus a list of fixture
  elements. `PhHvacPipeTrunk`: one element, `multiplier`, `demand_recirculation`, and a list of
  branches.
- `PhHotWaterSystem` holds `_distribution_piping`, trunks by id, and `_recirc_piping`, plain
  elements by id, plus `_number_tap_points`.
- METr's tree: trunk, branch, twig, written by PHX as `lTruncW` in the distribution block. Each
  takes name, length in m, material and a diameter enum. The enum is a nominal inch list: 3/8,
  1/2, 5/8, 3/4, 1, 1 1/4, 1 1/2, 2. PHX snaps the length-weighted diameter to the nearest
  entry, so a 22 mm pipe and a 3/4 in pipe export the same.
- METr does not take per-pipe insulation in the tree. Trunk also takes `cUoF`, the multiplier,
  and `drecW`.
- Recirculation is not a tree. METr takes one total length, one length-weighted heat loss
  coefficient in W/(m K) that PHX computes from diameter and insulation, daily recirculation
  hours, water temperature, air temperature, and an "all pipes insulated" flag.
- PHX's enum has four calculation methods: simplified individual pipes, simplified hot water
  calculator, unit method and floor method. honeybee-ph's `PhHotWaterSystem` carries no method
  field, so HBJSON cannot name one today (equipment H5). Which methods read the drawn tree and
  which need only counts is not yet checked. The interview needs that before Q5.

## Records

```
PipeType        id (ppt_), name, notes, datasheet_links, source,       (the common set)
                material, diameter_mm, insulation_thickness_mm,
                insulation_conductivity_w_mk, insulation_reflective, insulation_quality,
                color, schema_version

pipe assignment pipe_type_id, role, schema_version          (on the Edge; parent_ref only
                                                             under Q1's explicit-parent option)

Piping group    hot_water_system_id, schema_version         (on the Group)
```

Timestamps from the first draft are gone, as in equipment. `color` follows Thermal Bridge Types
(D3b-05). `water_temp_c`, `daily_period`, the trunk `multiplier` and `demand_recirculation` sit
on the Hot Water System record or the trunk run, not on the Pipe Type. They are operating
conditions, and METr holds them once per system.

## Behaviors

### Pipe Types

An inventory table on the Hot-water piping subtab of Systems (D4), with Types and Schedule as
its own subtabs in the shape D3b-17 gave Thermal Bridges: name, material, diameter, insulation
thickness, conductivity, reflective, quality, colour, used length. Add, duplicate, delete with
the Assembly delete contract (refuse in use, name a replacement, or clear).

### Draw

Pipes are drawn with SketchUp's native Line tool inside a Piping group. "New Piping group" in
the panel creates the group, links it to a Hot Water System and opens it for editing through the
session's edit context (`session/edit_context.rb`, the one `active_path=` writer), so the next
lines land inside. Membership is by parent group, the same rule Spaces follow. Lines outside a
Piping group are never Pipes, so tagging cannot leak onto envelope edges. Where a Piping group
may sit relative to Zone groups is Q13.

### Assign

Select lines, pick a Pipe Type and a role, press Assign: the primary route, one Undo step. The
edge tool from P3b-07, armed with a type and role, is the secondary route.

### The tree

METr needs to know which branches hang off which trunk and which fixtures off which branch.
Two ways to get that, and Q1 chooses:

- **By connection.** The exporter walks the lines with the 3b chain rule: Edges connect by a
  shared vertex id within one occurrence (`geometry_snapshot.rb`), so a Branch that touches a
  Trunk belongs to it and a Fixture that touches a Branch belongs to it. The user only sets
  roles. A line that touches nothing is a finding.
- **By explicit parent.** The user picks the parent in the panel for each run. The assignment
  then carries a parent reference, which is the registry question 3b handed over.

Connected lines with the same role and type form one run. Each run is one trunk, one branch or
one fixture at export, holding one Pipe-Segment per line.

### Recirculation

Lines with the Recirculation role are summed per Hot Water System. No tree. The schedule shows
the total length and the weighted heat loss coefficient PHX will compute.

### Schedule

One row per run: system, role, parent, Pipe Type, length, line count. Totals by role and system.
Click a row to select its lines.

### Colour-by mode

`Piping` mode: edges as `derived` segments with the P3b-06 stroke weight, coloured by role or by
Pipe Type. HUD legend with lengths through the readouts contract.

### Validation rows

| Finding | Severity |
| --- | --- |
| Pipe with no Pipe Type, or a deleted one | Blocks export |
| Pipe with no role | Blocks export |
| Branch that reaches no Trunk, Fixture that reaches no Branch | Blocks export under by-connection |
| Piping group with no Hot Water System | Blocks export |
| Pipe Type diameter far from any METr nominal size | Warning, names the size METr will use |
| Trunk with no branches | Warning |
| Pipe Type with insulation thickness but no conductivity | Blocks export |

### Export mapping

| PH-Composer | honeybee-ph |
| --- | --- |
| Pipe, one line | `PhHvacPipeSegment` with the type's fields and the line as `geometry` |
| Run | `PhHvacPipeElement` |
| Trunk run | `PhHvacPipeTrunk`, with `multiplier` and `demand_recirculation` |
| Branch run | `PhHvacPipeBranch` under its trunk |
| Fixture run | An element in the branch's `fixtures` |
| Recirculation lines | Elements in `PhHotWaterSystem._recirc_piping` |
| Hot Water System | `PhHotWaterSystem`, attached to the Rooms of the Zones it serves by the equipment section |

Open plan item: a translation section attaches its objects to `MODEL`, `ROOM` or `FACE`
(`sections.py`). Piping's objects belong inside equipment's translated `PhHotWaterSystem`, not
on a Room. The piping section therefore `requires` the equipment section and adds its trunks
and recirculation elements to that object before assembly attaches it, which the coordinator's
ordering allows but no shipped section does yet. Settle at planning with ducting, which has the
same shape.

## Decisions for the interview

Recommendations changed on 2026-10-21 are marked; Ed has answered none of them.

| # | Question | Recommendation |
| --- | --- | --- |
| Q1 | Tree by connection or by explicit parent? | By connection. The drawing already says it, the snapshot's shared vertex ids and 3b's chain rule compute it, findings catch the gaps, and no parent reference or registry is needed. The assignment still carries an id, since the engine requires one on every reference-target record (3b D3b-22) |
| Q2 | Draw with the native Line tool in a Piping group, or a custom Draw Pipe tool? | Native Line in a Piping group. M1's boundary was no new drawing tool, and inference snapping to the model is what makes tracing fast |
| Q3 | Is "pipe type" the specification only, with role set separately? | Yes. The same 3/4 in PEX is a branch in one place and a fixture run in another |
| Q4 | Diameter entry: free mm, or METr's nominal size list? | The nominal list, stored as `diameter_mm`. A free value METr rounds is false precision. Confirm with units Q2 |
| Q5 | Support the simplified methods, with no drawn pipes? | Yes, as a choice on the Hot Water System. A single-family model should not need a drawn tree. Equipment H5 (2026-10-21) found honeybee-ph's `PhHotWaterSystem` has no field for the method: it is added upstream first ([honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135)), and until the pinned wheel carries it only drawn pipes export |
| Q6 | The trunk multiplier: expose it? | Yes. One drawn riser times twelve identical risers is the multifamily case |
| Q7 | One Piping group per Hot Water System, or many? | Many. A group per floor or riser is how people organise. The system link is on each group |
| Q8 | Do Pipes belong to a Zone? | No. They belong to a Hot Water System, which serves Zones. Pipes cross Zone boundaries |
| Q9 | Is insulation kept on the Pipe Type though METr's tree ignores it? | Yes. The recirculation heat loss coefficient uses it and honeybee-ph carries it |
| Q10 | Are Pipe Types a library kind? | Not now. Same answer as Thermal Bridge Types (3b Q8; roadmap 5.4) |
| Q11 | Rename: Pipe-Segment qualified, role word Fixture or Twig? | Pipe-Segment. Twig on screen, matching METr, as Assemblies matched METr |
| Q12 | Where does piping live in primary navigation? | Confirmed in D4: under Systems, with Equipment, ERV ducting and Hot-water piping as peer subtabs |
| Q13 | Code. Added 2026-10-21. May a Piping group sit inside a Zone group, or only at the Model root? | Model root or a plain wrapper, never inside a Zone group. A Zone's walk treats a nested stamped Group as a container (D3a-1) and an unstamped one as geometry; keeping pipes outside Zones avoids a third rule. Pipes cross Zones anyway (Q8) |

## Non-goals

No sizing, no flow or pressure calculation, no fittings, no hydronic heating pipes, no automatic
routing.

## Acceptance shape

On a synthetic three-storey model: two Pipe Types, one riser trunk with a multiplier, three
branches, six fixture runs and a recirculation loop, all drawn with the Line tool. Schedule
lengths match hand measurement. Break one branch from its trunk and see the finding. Export,
reload the exact HBJSON in the pinned stack and find the tree on the right Hot Water System with
the right lengths, materials, diameters and the recirculation total, through the section's
`conformance` check. One Undo per assign. Save and reopen. METr's diameter enum and `lTruncW`
rows are metr-export's.

## Prior art and evidence

- Predecessor `planning/phases/M1_piping.md` (`../../ph-navigator-sketchup/`).
- honeybee-ph `honeybee_phhvac/hot_water_piping.py`, `hot_water_system.py`, re-read at 1.33.65.
- PHX `model/hvac/piping.py`, `model/enums/hvac.py`, `to_METr_JSON/metr_schemas.py`, read
  2026-09-18, not in the pinned runtime.
- honeybee-grasshopper-ph "HBPH - Create SHW Pipe" family: curves in, trunks and branches out.
- Phase 3b's [PRD](../../phase-03b-thermal-bridges/PRD.md), "Edge tagging rules", and
  [CONTRACTS](../../phase-03b-thermal-bridges/CONTRACTS.md), the edge store, target and `runs/`.
