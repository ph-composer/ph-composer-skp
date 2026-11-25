# P4-13: hot water piping

DATE: 2026-10-21
STATUS: Implemented on branch 2026-11-24: P4-13a to P4-13d merged (#576 to #579), P4-13e in review; host cases M13a to M13e owed to MS3, M13 not Pass. Planned in full 2026-11-24 as five sub-stages, P4-13a to P4-13e, each one pull request, from this stub, the [piping PRD](../hot-water-piping/PRD.md), D4-09, D4-13, D4-18, D4-25, D4-30, D4-31 and D4-36 (Q1 to Q13 all as recommended). This file is their parent index: the entry gates, what the sub-stages share and the inferences that cross them. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host cases run in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry gates

P4-06 merged (the Hot Water System it exports into); Phase 3b's P3b-03 (edge records and assignment), P3b-04 (the chain rule), P3b-06 (the stroke weight), P3b-07 (the edge tool) and P3b-08 (an edge contributor and section) merged, all met on 2026-10-26; the hot water piping interview ([its PRD](../hot-water-piping/PRD.md), Q1 to Q13), met 2026-11-23 (D4-36); D4-09 answered. P4-13a stacks on P4-11 (#575) while that is open.

## Owns

Roadmap 4.4 as the piping PRD scopes it: Pipe Type records, Piping groups linked to a Hot Water System, role and type assignment on edges, the tree by connection, the recirculation sum, the schedule, the Colour-by modes, the section that adds trunks and recirculation elements to the required hot water objects before attach (D4-09), and the Piping pills under Hot Water on the Mechanical tab (D4-13). It also owns Phase 3b's two handovers: the run builder's move to `core/` (P4-13c) and the edge registry question, answered "none" by Q1 (P4-13b).

## Sub-stages

Each is one pull request with its own document, written to be handed to a coding agent with this packet's CONTRACTS and the piping PRD. They run in order: each needs the one before it. Size is the estimated growth of the installed RBZ, read from the analogous Phase 3b folders (thermal bridges ship about 204 KB of Ruby, 54 KB of panel and 8 KB of Python).

| Sub-stage | Delivers | Review lane | Host case, owed to MS3 | Size estimate |
| --- | --- | --- | --- | --- |
| [P4-13a](p4-13a-pipe-types.md) | The `ph_composer.piping` feature and the Pipe Type kind with its operations, panel closed; `PLANNING_IDS` learns `M13a` | ordinary, `gpt-6.2-sol` | `M13a` | 30 KB |
| [P4-13b](p4-13b-piping-groups-and-assignment.md) | Piping groups linked to a Hot Water System, the pipe assignment on an Edge (role, type, role values), assign, clear, selection, delete in use | ordinary, `gpt-6.2-sol` | `M13b`, with the unmeasured Line tool cases | 75 KB |
| [P4-13c](p4-13c-tree-and-schedule.md) | The chain rule moved to `core/` with Phase 3b's tests; runs, the tree by connection, the recirculation sum per System, findings, the schedule read and `runs.locate` | strong, `gpt-6-astra` | `M13c` | 55 KB (the move itself about 0) |
| [P4-13d](p4-13d-piping-export.md) | The piping contributor and Python section adding trunks and recirculation elements to every (System, Zone) object before attach (D4-09), conformance and a PHX round trip (D4-25) | strong, `gpt-6-astra` | `M13d` | 35 KB |
| [P4-13e](p4-13e-piping-view.md) | The Pipe Types and Piping pills under Hot Water, the assign bar and New Piping group, the Systems table's recirculation columns, the two Colour-by modes and the pipe tool | ordinary, UI, `gpt-6.2-sol`; `gpt-6-astra` for the edge tool's move to `core/` if that slice is taken | `M13e` | 85 KB |

Their register rows are M13a to M13e in [ACCEPTANCE](../ACCEPTANCE.md), and the geometry they test against is its [hot water piping case](../ACCEPTANCE.md#hot-water-piping-case-p4-13); their ledger rows are in [STATUS](../STATUS.md).

## Size

The installed size on P4-11's head is 27,461,724 bytes, 538,276 under the 28,000,000 byte ceiling. P4-13 as estimated takes about 280 KB, leaving about 258 KB for P4-14 (ERV ducting, the second edge feature, which would cost about as much if it shared nothing) and P4-15. That is a risk to the ceiling. Two choices in these documents reduce it: the chain rule moves to `core/` rather than being copied (P4-13c), and P4-13e extracts the edge tool's generic part to `core/` if the architecture review agrees, so ducting reuses both. Each sub-stage that ships Ruby, Python or panel assets reads `uv run tools/runtime/vendor.py --check` and records the installed size in its evidence; one that lands more than 25 percent over its estimate stops and reports before merging, so P4-14 can be re-planned against what is left.

## What the sources settle, for every sub-stage

Read in the pinned wheel `src/ph_composer/vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl` on 2026-11-24:

| Source | What it says | Consequence |
| --- | --- | --- |
| `honeybee_phhvac/hot_water_piping.py`, `PhHvacPipeSegment` | `geometry` (a `LineSegment3D`), `diameter_mm` (12.7), `insulation_thickness_mm` (12.7), `insulation_conductivity` (0.04), `insulation_reflective` (True), `insulation_quality` (1 to 3, default 1), `daily_period` (24), `water_temp_c` (60.0), `material` (1 to 8, default 2, Copper L); `user_data` from `_PhHVACBase` | A Pipe Type carries the specification; temperature and period are operating values, never on the type (PRD, "Records") |
| Same file, `PhHvacPipeElement`, `PhHvacPipeBranch`, `PhHvacPipeTrunk` | An element keys its segments by identifier; `material_name` raises when its segments differ in material. A branch holds one element and a list of fixture elements (`twigs` is its alias); a trunk holds one element, `multiplier` (1), `demand_recirculation` (False) and a list of branches | One run is one element, so a run must be one Pipe Type. Segment identifiers must be unique within an element and derived from geometry, since one assignment id sits on several Edges after a split |
| `honeybee_phhvac/hot_water_system.py`, `PhHotWaterSystem` | `add_distribution_piping` (trunks, keyed by identifier), `add_recirc_piping` (elements, keyed by identifier); `recirc_temp` is the length-weighted mean of the recirculation elements' `water_temp_c` (60.0 with none), `recirc_hours` the `int()` of the length-weighted mean of their `daily_period` (24 with none); an unset `number_tap_points` counts the fixtures | The piping section uses only the public adders. The Ruby recirculation read must equal both properties, truncation included. A System with tap points left blank exports its twig count |
| Same class | No calculation-method attribute of any name, and no `user_data` | P4-06's guessed `piping_calc_method` still finds nothing (honeybee_ph#135); P4-13d re-verifies |

Read in PHX 1.59.4 (checkout at tag `v1.59.4`, `a26d345d`; the `phx` test group, not shipped): `from_HBJSON/create_variant.py`, `add_shw_piping_from_hb_rooms`, walks each Room's Spaces and, through each Space's host Room, adds that Room's trunks and recirculation elements to the Variant's mechanical collection, which keys both by identifier (`model/hvac/collection.py`), so equal identifiers on two Rooms give one trunk; it sets tap points from the last Room read and the recirculation temperature and hours from the set of Rooms' values, falling back to 60 °C and 24 h when they disagree. A Room with no Spaces contributes no piping. `from_HBJSON/create_shw_devices.py` copies every segment value, `daily_period` and `water_temp_c` of distribution pipes included, and the trunk's `multiplier` and `demand_recirculation`. `to_METr_JSON/metr_schemas.py` snaps a diameter to the nearest of eight nominal inch sizes (3/8 to 2 in) by `diameter_mm / 25.4`.

The Grasshopper components (`honeybee_grasshopper_ph`, `gh_compo_io/shw/create_pipe_trunks.py`, `create_pipe_branches.py`, `create_pipe_fixtures.py`, `create_recirc_pipes.py`, read in the local checkout at `8967c64`; not vendored) corroborate the record shape: each recirculation pipe takes its own `daily_period` and `water_temp_c` (24, 60), each trunk its own `multiplier` and `demand_recirculation`.

## Inferred in planning, across the sub-stages

Each follows the stub, D4-36, the PRD and D4-18, Phase 3b's pattern, honeybee-ph or PHX. The first three have consequences Ed should see; the rest change no result.

- **A tree lives in one Piping group.** The PRD's by-connection rule joins Edges "by a shared vertex id within one occurrence", and vertex ids belong to their container (`context/TECH_STACK.md`, "Edge-owned assignments"; the snapshot's `edge` entries). So a branch drawn in a floor group cannot reach a trunk drawn in a riser group: it raises the blocking "branch reaches no trunk". Q7's "many groups per System" still holds for separate trees and for recirculation, which needs no tree. *For Ed:* a riser group plus per-floor branch groups does not export; joining trees across groups by endpoint position would be new mechanics and a new decision.
- **Recirculation temperature and hours, and the trunk's multiplier and demand recirculation, are on the pipe assignment.** D4-18 reads recirculation temperature and hours from the recirculation pipes; the PRD keeps them off the Pipe Type and puts them "on the Hot Water System record or the trunk run"; D4-18 took them off the System and runs are derived, never stored. A Pipe is one Edge, so the only record left is its assignment. A recirculation assignment carries `water_temp_c` (60) and `daily_period` (24); a trunk assignment carries `multiplier` (1) and `demand_recirculation` (false); each is absent for the other roles, as a Hot Water Heater's variant fields are (D4-19). Both trunk values join the run key, as thermal-bridge `quantity` does, so two values on one chain give two trunks. *For Ed:* a recirculation loop drawn as one chain can carry one temperature per Edge; the Systems row shows their length-weighted mean. If Ed wants them per Piping group or per System instead, one step in P4-13b, one schema line and one M13b clause change.
- **The Systems table's recirculation moves from mechanical to piping.** P4-07's read-only Recirculation column reads `recirculation` from `hot_water_systems.all`, which is constant until piping exists, and mechanical may not name piping. P4-13e removes that field from the mechanical read (CONTRACTS section 3's `hot_water_systems.all` row) and its column, and piping contributes `Recirc. °C` and `Recirc. h/day` to the Systems table through `table_contributions`, as D4-37 does for ducting lengths. *For Ed:* this removes a shipped API field, and M07's Systems clause, whose MS2 host case has not run, then reads piping's columns. The alternative keeps the field: mechanical owns a seam, a recirculation provider any feature may register and mechanical reads without naming it, and piping fills it. Between P4-13d and P4-13e the Systems row still reads the defaults while the export carries the pipes' values. The contributed columns read values from the snapshot, so P4-13c's measurement decides whether piping's per-System rows are a snapshot section or are fetched with the schedule (P4-13e).
- **The feature** is `ph_composer.piping` (Ruby `Piping`, `features/piping/`, `html/features/piping/`, `python/ph_composer_translation/piping_sections.py`), last in `FEATURES` after Mechanical, requiring `ph_composer.mechanical` (the Hot Water System kind and its export section, D4-09; PLAN, "Ownership and dependency direction") and `ph_composer.zones` (containment, Q13). Mechanical never names it.
- **The role word stored is `twig`**, shown as Twig (Q11), mapped to honeybee-ph's `fixtures` at export; the other roles are `trunk`, `branch` and `recirculation`.
- **Distribution pipes export honeybee-ph's defaults**, 60 °C and 24 h, for `water_temp_c` and `daily_period`: neither the PRD nor D4-36 gives them a home, PHX copies them into its segments, and what WUFI or METr does with them is metr-export's. Open there, not here.
- **The recirculation heat loss coefficient is not shown.** The PRD's schedule names it, but it is PHX's iterative calculation (`model/hvac/piping.py`) and the piping README sends "the recirculation coefficient" to metr-export. The schedule shows the recirculation length, temperature and hours.
- **The diameter is one of the eight nominal sizes, stored in millimetres as the inch size times 25.4** (9.525 to 50.8), which PHX maps back exactly (Q4, units Q2). The PRD's warning for a diameter far from a nominal size cannot fire and is dropped; any other value refuses `params.invalid`.
- **A Piping group copy is shared storage.** A pasted Group shares its definition with the source (`context/SKETCHUP_HOST_BEHAVIOR.md`, "Entity dictionaries on Faces, Groups and instances"), so each occurrence's pipes count, with distinct run identifiers since they digest the container path, and an assignment write through either refuses until one is made unique, as Phase 3b's shared Edges do. The trunk multiplier is the intended way to repeat a riser (Q6).

## Host cases owed to MS3

Measured and cited, not owed: an Edge's dictionary survives split, copy and paste, weld, Undo, Redo and reopen ([B4, T01](../../../../context/SKETCHUP_HOST_BEHAVIOR.md#components-glue-and-edge-attributes)); a heal of two differently tagged halves keeps one record (T01); endpoints in one Entities collection merge within 0.0254 mm (P1-A, "Zone grouping and face topology"); a pasted Group carries its dictionary and shares storage (SD01).

Not measured, owed to MS3, each in the sub-stage that rests on it: an empty Group created by an operation survives the commit and opens for editing (P4-13b); the native Line tool, drawing in an open Piping group, puts its Edges in that group (P4-13b); a line started on the middle of a loose Edge in a faceless Group splits that Edge and shares the new vertex, and two crossing loose lines split each other (P4-13b; T01's splits were on a Face); vertex ids of a faceless Group survive save and reopen so runs and identifiers read the same (P4-13c).

## Planned in full when

Done 2026-11-24. The interview is recorded in the [piping PRD](../hot-water-piping/PRD.md) and [DECISIONS, Part 5](../DECISIONS.md#part-5-kickoff-review-and-remaining-interviews-2026-11-23) (D4-36).
