# P4-13e: the Piping pills, Colour-by and the pipe tool

DATE: 2026-11-24
STATUS: Merged to main 2026-11-25 (#580, squash `98ba249c`); offline evidence in [p4-13e-piping-view](../evidence/p4-13e-piping-view.md), host case `M13e` owed to MS3; the edge tool was not moved to `core/` (recorded in the evidence). Planned in full 2026-11-24 from [P4-13](p4-13-hot-water-piping.md), D4-13, D4-18, D4-30, D4-36 (Q2, Q6, Q11) and the [piping PRD](../hot-water-piping/PRD.md), "Pipe Types", "Assign", "Schedule" and "Colour-by mode". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M13e` runs in the MS3 sitting (D4-31) with Ed at the mouse.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-13d. Owns the screen and the viewport:

- Two pills under Hot Water on the Mechanical tab, after Tanks: `Pipe Types` and `Piping` (D4-13).
- The assign bar: Pipe Type, role and the role's values over the native selection, Make Piping group (was New Piping group; 2026-11-26), and the pipe
  tool as the secondary route (PRD, "Assign").
- The schedule table with its totals, findings and Locate.
- The Systems table's recirculation columns, moved from mechanical to piping (P4-13, "Inferred in planning").
- Two Colour-by modes, by role and by Pipe Type, with the stroke weight and a legend with lengths.

Behavior owner: the [piping PRD](../hot-water-piping/PRD.md). Load `.agents/skills/ph-composer-ui-polish/SKILL.md` and
its reference first, and read the Mechanical tab's table in [ui-baseline](../../../ui-baseline/README.md). Build from
the shipped kit patterns, with no new wireframes (D4-30). Pattern: the Thermal Bridges tab (`html/features/thermal_bridges/`
`types.js`, `assign_bar.js`, `schedule.js`, `edge_tool.js`), its Colour-by mode (P3b-06) and edge tool (P3b-07), and
the Hot Water pills (P4-07).

Paths are relative to `src/ph_composer/`.

## What the sources settle

- D4-13: Piping is a pill under Hot Water; a pill picks one table.
- `table_contributions` adds columns and actions to a named table from another module and refuses a column id the
  owner already has (`html/table_contributions.js`); D4-37 uses it for ducting's lengths on the Ventilators table.
- A Colour-by entry may carry an Edge as `entity` and its segment in `derived`, drawn with the P3b-06 stroke weight
  (`context/EXTENSIBILITY.md`, "Colour-by derived geometry"); readouts give a legend its values ("Colour-by readouts").
- The edge tool's rules (`context/EXTENSIBILITY.md`, "Viewport tools"; P3b-07): pick with `Pick.edge_path`, freeze the
  armed values at button-down, collect into a `DragSet` bounded one past the limit, call the assign action through
  `API.invoke` on release, cancel on Escape, deactivation, a suspended context and a move without `MK_LBUTTON`.

## Inferred in planning

- **Two pills, not one.** D4-13 names one Piping pill, and one pill is one table; Pipe Types and the schedule are two
  tables, as Thermal Bridges' Types and Schedule are (D3b-17). `Pipe Types` and `Piping`, in that order after Tanks.
  The UI polish review may fold them.
- **Pipe Types columns.** Tag, Material, Diameter (the nominal label), Insulation (`length_mm`), Conductivity
  (`conductivity`), Reflective, Quality, Colour, Used length (from the schedule's `types` rows, a dash until it has
  loaded), hideable Notes. New asks for the Tag; Duplicate; Delete with a replacement or clearing the pipes.
- **The Piping pill** holds the assign bar, the Piping groups (each with its System picker, link and unlink) and the
  schedule: rows by System, then group, then role, the twig rows under their branch and the branches under their trunk;
  totals by role and System; finding badges; a row click runs `runs.locate`; Refresh re-reads it (D3b-13).
- **The role values in the bar** show only for the chosen role: Multiplier and Demand recirculation for a trunk,
  Water temperature (`temperature`) and Hours a day for recirculation. Hours a day uses a new `hours_per_day`
  quantity, `h/day` and unconverted under IP, as P4-10's `kilohours` is, so the regional number format applies; it
  changes the shared unit registries, so the Design System re-sync follows.
- **The Systems table's recirculation.** Mechanical's `recirculation` field on `hot_water_systems.all`
  (`features/mechanical/hot_water/reads.rb`, `declarations/hot_water.rb`, `RECIRCULATION_DEFAULTS`) and its column in
  `html/features/mechanical/hot_water.js` are removed; piping contributes `Recirc. °C` and `Recirc. h/day` to the
  Systems table through `table_contributions`. A contribution's callbacks read the snapshot, so the values come from
  the `piping_systems` snapshot section where P4-13c registered one, and otherwise from the schedule's `systems` rows,
  fetched when the Hot Water subtab opens and on Refresh and held in the piping module; honeybee-ph's 60 and 24 show as
  defaults until a System has a recirculation pipe. The removal names nothing of piping. API minor bump with the field's
  removal in its `API::CHANGES` row. This is the third item for Ed in [P4-13](p4-13-hot-water-piping.md), with its
  alternative.
- **Colour-by.** `piping_by_role` and `piping_by_type`, one entry per pipe occurrence with the Edge as `entity` and its
  segment in `derived` at the P3b-06 stroke weight; role colours fixed (Trunk, Branch, Twig, Recirculation), type
  colours the Pipe Type's `color`; legend rows count lengths through a readout. Unassigned lines in a Piping group are
  uncoloured.
- **The pipe tool.** Armed from the bar with a type, a role and its values (the PRD's "edge tool, armed with a type and
  role"); `pipe_tool.choose`, `pipe_tool.stop` and a `pipe_tool` snapshot section. If the architecture review agrees,
  the generic part of `features/thermal_bridges/edge_tool.rb` (gesture, drag set, cancellation, hover) moves to `core/`
  and both tools call it, which P4-14's duct tool reuses and saves its size; otherwise the pipe tool follows its shape.
  The move, if made, is a second core move of shipped thermal-bridge code: that slice takes the strong lane,
  `gpt-6-astra`, and repeats the thermal-bridge tool cases `acceptance_ledger.py status --changed` names.
- **New Piping group** in the bar asks for a Hot Water System and calls `groups.create` (P4-13b), which opens it for
  the Line tool. Superseded 2026-11-26 (issue #598, P4-13b "The fallback taken"): **Make Piping group**, enabled only
  while the selection read's `make_refusal` is null, with that reason beside it otherwise, asks for a Hot Water System
  and calls `groups.make` with the selected loose lines' paths; the group is not opened.
- **Slices.** If the PR grows past one coherent review it splits along two slices, each merging whole: the pills, bar
  and Systems columns; then Colour-by and the pipe tool.

## Steps

1. **Pills and Pipe Types.** `html/features/piping/section.js` (registers the two pills on the Hot Water subtab),
   `pipe_types.js` over the kit inventory and in-place drafts.
2. **The Piping pill.** `assign_bar.js` (selection from `pipes.selected`, Assign and Clear, role values, New Piping
   group, Assign by clicking), `groups.js`, `schedule.js` with Locate and Refresh.
3. **The Systems columns.** `systems_columns.js` registering the two contributed columns; mechanical's field and
   column removed; `tests/mechanical_*` updated where they read the field.
4. **Units.** `hours_per_day` in `core/units.rb`, `html/unit_tables.js` and `tests/support/units_vectors.json`.
5. **Colour-by.** `features/piping/colour_modes.rb`: the two modes and the readout.
6. **The pipe tool.** `features/piping/pipe_tool.rb`, `html/features/piping/pipe_tool.js`, declarations, native menu
   items; the core extraction if agreed.
7. **Preview and checks.** `tools/ui-preview/host.js` and `fixtures.js` gain the piping sections, a
   `piping_checks.cjs` runs the two pills and the Systems columns at the three panel sizes through the browser-evidence
   collector; `make panel-manifest`; the runtime manifest refreshed; the Design System re-sync after the CSS and units.
8. **Documents.** `docs/PRODUCT.md` ("Draw hot water piping": groups, drawing, assigning, the schedule, Colour-by),
   `docs/AGENT_GUIDE.md` and the shipped guide (the tool route), `context/UBIQUITOUS_LANGUAGE.md` (the Mechanical tab
   row), the [ui-baseline](../../../ui-baseline/README.md) row, the packet CONTRACTS (section 3's colour modes and
   tool; section 3's `hot_water_systems.all` row without recirculation).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `html/features/thermal_bridges/` (`types.js`, `assign_bar.js`, `schedule.js`, `edge_tool.js`) | The tab's shape |
| `features/thermal_bridges/colour_modes.rb`, `edge_tool.rb` | Colour-by over Edges and the tool |
| `html/features/mechanical/hot_water.js`, `section.js`, `systems.js` | The Hot Water pill row and the Systems table |
| `html/table_contributions.js` | The contributed columns |

## Tests (write first)

1. Panel (`tests/piping_panel_test.js`): the two pills after Tanks; a Pipe Type cell edit sends `pipe_types.update`
   with `expected_values` and a refused draft is kept; the diameter offers only the eight nominal sizes; the bar shows
   Multiplier only for a trunk and Water temperature and Hours a day only for recirculation, and Assign sends
   `pipes.assign` with the selection's references and their `expected_values`; a schedule row click sends `runs.locate`;
   the Systems table shows the contributed columns and no mechanical recirculation column.
2. Units: `hours_per_day` vectors; a draft keeps its unit through a switch.
3. Colour-by (`tests/piping_colour_mode_test.rb`): one entry per pipe occurrence with its segment; role and type
   colours; legend lengths equal the schedule's totals; an unassigned line is uncoloured.
4. The pipe tool (`tests/piping_pipe_tool_test.rb`, the shape of `thermal_bridge_edge_tool_test.rb`): armed values
   frozen at button-down; a drag over 251 Edges refuses as a whole; Escape and a move without the button cancel; one
   Undo step per gesture.
5. Mechanical: `hot_water_systems.all` rows no longer carry `recirculation`; the reference test and the agent guide test
   pass.
6. `make ui-checks` runs `piping_checks.cjs` and the Mechanical script at the three panel sizes.

## Host gate (`M13e`, MS3 sitting, D4-31)

Fresh process, the installed RBZ, Ed at the mouse, the PRD's acceptance shape on the reference model with the
[piping case](../ACCEPTANCE.md#hot-water-piping-case-p4-13) (three storeys of lines): two Pipe Types; the lines drawn loose with the Line tool, selected, and Make Piping group linked to HWS-1 wraps them (was: New Piping group opens for the Line tool; 2026-11-26); one riser trunk with multiplier 12, three
branches, six twigs and a recirculation loop drawn and assigned from the bar, one Undo step each; one branch assigned
with the pipe tool; the schedule's lengths match hand measurement; break a branch from its trunk and read the finding,
whose Locate selects it; both Colour-by modes with their legend lengths; the Systems table's recirculation reads the
loop's temperature and hours; save and reopen; the panel at 1280 x 800, 420 px and 360 x 520; the UI polish review.
Record with `acceptance_case.py`.

## Out of scope

Joining trees across groups. The recirculation coefficient. A custom drawing tool (Q2). METr rows (metr-export).

## Done when

- M13e has offline evidence in `../evidence/p4-13e-piping-view.md`, with the UI polish review and the Design System
  re-sync recorded; host verification lands in `MS3`.
- `make ci` passes on both Rubies; the panel and runtime manifests are current; the installed size is recorded
  against the 85 KB estimate and the headroom left for P4-14 is stated.
