# P4-14f: the Ducting pills, the Ventilators columns and Colour-by

DATE: 2026-11-24
STATUS: Merged to main 2026-11-25 (#588, squash `4a835641`); offline evidence in [p4-14f-ducting-view](../evidence/p4-14f-ducting-view.md), host case `M14f` owed to MS3; corrections recorded under "Recorded at implementation". Planned in full 2026-11-24 from [P4-14](p4-14-erv-ducting.md), D4-13, D4-30, D4-37 (Q1, Q2, Q9) and the [ducting PRD](../erv-ducting/PRD.md), "Behaviors". Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M14f` runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-14e. Owns the screen and the viewport:

- Two pills under Ventilation on the Mechanical tab, after Ventilators: `Duct Types` and `Ducting` (D4-13).
- The assign bar: Duct Type, direction and quantity over the native selection, and New Ducting group.
- The schedule table with its totals, findings and Locate, and the line saying which ducts are drawn (Q1).
- The Ventilators table's `Outdoor air duct` and `Exhaust air duct` columns, contributed by ducting (Q9).
- Two Colour-by modes, by direction and by Duct Type, with the stroke weight and a legend with lengths.

Behavior owner: the [ducting PRD](../erv-ducting/PRD.md). Load `.agents/skills/ph-composer-ui-polish/SKILL.md` and its
reference first, and read the Mechanical tab's row in [ui-baseline](../../../ui-baseline/README.md). Build from the
shipped kit patterns, with no new wireframes (D4-30). Pattern: the Piping pills (P4-13e, `html/features/piping/`
`pipe_types.js`, `assign_bar.js`, `groups.js`, `schedule.js`, `systems_columns.js`) and piping's Colour-by modes
(`features/piping/colour_modes.rb`).

Paths are relative to `src/ph_composer/`.

## What the sources settle

- D4-13: Ducting is a pill under Ventilation; a pill picks one table.
- `table_contributions` adds columns to a named table from another module and refuses a column id the owner already
  has (`html/table_contributions.js`); piping's `systems_columns.js` contributes to `hotWater.SECTIONS.systems`.
  `html/features/mechanical/ventilators.js` returns only its view (`{ Ventilators: Ventilators }`) and its table's
  section id is `ph_composer.mechanical.ventilators`; the contribution names that table id, so ventilators.js
  exports its `SECTION` as hot_water.js exports `SECTIONS`, one line in Mechanical that names no feature.
- A Colour-by entry may carry an Edge as `entity` and its segment in `derived`, drawn at the P3b-06 stroke weight;
  readouts give a legend its values (`context/EXTENSIBILITY.md`, "Colour-by derived geometry", "Colour-by readouts").

## Inferred in planning

- **Two pills, not one**, as piping's (P4-14, "Pills, labels and columns"). The UI polish review may fold them.
- **Duct Types columns.** Tag, Shape (Round or Rectangular), Diameter, Width and Height (`length_mm`; a dash for the
  other shape's), Insulation (`length_mm`), Conductivity (`conductivity`), Reflective, Colour, Used length (from
  `duct_types.all`'s `used_length_m`), hideable Notes. A shape change in a draft asks for the new shape's dimensions
  before it sends `duct_types.update`. New asks for the Tag; Duplicate; Delete with a replacement or clearing the
  ducts.
- **The Ducting pill** opens with one line: "Draw only the two cold runs between each ventilator and the outside:
  Outdoor air and Exhaust air." Then the assign bar, the Ducting groups (each with its Ventilator picker, link and
  unlink) and the schedule: rows by Ventilator, then group, then direction; drawn length, quantity and line count per
  run; totals by direction and Ventilator, quantity applied; finding badges; a row click runs `runs.locate`; Refresh
  re-reads it (D3b-13).
- **The bar** offers the two directions as a segmented choice in the kit's pattern, the Duct Types as a select and the
  quantity as an integer cell (1 by default); Assign sends `ducts.assign` with the selection's references and their
  `expected_values`; Clear sends `ducts.clear`. New Ducting group asks for a Ventilator and calls `groups.create`.
- **The Ventilators columns** read the `ducting_ventilators` snapshot section where P4-14d registered it, otherwise the
  schedule's `ventilators` rows, fetched when the Ventilation subtab opens and on Refresh; a Ventilator with no run of
  a direction shows a dash. Their headers follow the unit preference.
- **Colour-by.** `ducting_by_direction` and `ducting_by_type`, one entry per duct occurrence with the Edge as `entity`
  and its segment in `derived`; direction colours fixed (Outdoor air and Exhaust air), type colours the Duct Type's
  `color`; legend rows count lengths through a readout, quantity applied, so they equal the schedule's totals.
  Unassigned lines in a Ducting group are uncoloured.
- **No duct tool** (P4-14).
- **No new unit quantity.** Lengths, `length_mm` and `conductivity` are shipped, so the shared unit registries do not
  change; the Design System re-sync is owed only if this stage changes kit CSS or a shared kit part.

## Steps

1. **Pills and Duct Types.** `html/features/ducting/section.js` (registers the two pills on the Ventilation subtab),
   `duct_types.js` over the kit inventory and in-place drafts.
2. **The Ducting pill.** `assign_bar.js`, `groups.js`, `schedule.js` with Locate and Refresh, `shared.js`,
   `ducting.css` only where the kit lacks a pattern.
3. **The Ventilators columns.** `ventilator_columns.js` registering the two contributed columns; `ventilators.js`
   exporting its section id.
4. **Colour-by.** `features/ducting/colour_modes.rb`: the two modes and the readout.
5. **Preview and checks.** `tools/ui-preview/host.js` and `fixtures.js` gain the ducting sections; a
   `ducting_checks.cjs` runs the two pills and the Ventilators columns at the three panel sizes through the
   browser-evidence collector; `make panel-manifest`; the runtime manifest refreshed.
6. **Documents.** `docs/PRODUCT.md` ("Draw ERV ducting": groups, drawing the two cold runs, assigning, the schedule,
   the Ventilators columns, Colour-by), `docs/AGENT_GUIDE.md` and the shipped guide, `context/UBIQUITOUS_LANGUAGE.md`
   (the Mechanical tab row), the [ui-baseline](../../../ui-baseline/README.md) row, the units packet's ducting row
   (`planning/features/cross-phase/units/STATUS.md`) as delivered, the packet CONTRACTS (section 3's colour modes).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `html/features/piping/` (`pipe_types.js`, `assign_bar.js`, `groups.js`, `schedule.js`, `systems_columns.js`, `section.js`) | The pills' shape |
| `features/piping/colour_modes.rb` | Colour-by over Edges |
| `html/features/mechanical/ventilators.js`, `section.js` | The Ventilation pill row and the Ventilators table |
| `html/table_contributions.js` | The contributed columns |

## Tests (write first)

1. Panel (`tests/ducting_panel_test.js`): the two pills after Ventilators; a Duct Type cell edit sends
   `duct_types.update` with `expected_values` and a refused draft is kept; a shape change asks for the new
   dimensions; the Ducting pill shows the cold-runs line; the bar sends `ducts.assign` with direction, type and
   quantity and the selection's references; a schedule row click sends `runs.locate`; the Ventilators table shows the
   two contributed columns with ERV-1's 2.500 and 1.800 m and ERV-2's 2.500 and 3.000 m.
2. Colour-by (`tests/ducting_colour_mode_test.rb`): one entry per duct occurrence with its segment; direction and type
   colours; legend lengths equal the schedule's totals; an unassigned line is uncoloured.
3. Mechanical: the Ventilators panel tests pass with the section id exported; nothing under the mechanical folders
   names ducting.
4. `make ui-checks` runs `ducting_checks.cjs` and the Mechanical script at the three panel sizes.

## Host gate (`M14f`, MS3 sitting, D4-31)

Fresh process, the installed RBZ, Ed at the mouse, the PRD's acceptance shape on the reference model with the
[ERV ducting case](../ACCEPTANCE.md#erv-ducting-case-p4-14): one Round and one Rectangular Duct Type; New Ducting group
linked to ERV-1 opens for the Line tool; an Outdoor air and an Exhaust air run per Ventilator drawn and assigned from
the bar, one Undo step each, ERV-2's Exhaust air at quantity 2; the schedule's lengths match hand measurement and the
Ventilators columns read them; delete ERV-2 with null and read `ducting.group_unlinked`, whose Locate opens the
group and selects that run's ducts (P4-14e, "Recorded at implementation"); both Colour-by modes with their legend lengths; save and reopen; the panel at 1280 x 800, 420 px and 360 x 520;
the UI polish review. Record with `acceptance_case.py`.

## Out of scope

A duct tool (P4-14). METr rows (metr-export).

## Recorded at implementation (2026-11-25)

- **The panel's line-group layer.** Piping's Piping pill code named no Hot Water System beyond its words, so it moves
  to `html/line_groups/` (the panel side of `line_groups/`, naming no feature): the one read (`shared.js`), the groups
  with New <group> (`groups.js`), the schedule shell with Locate, findings, totals and "Not in the schedule"
  (`schedule.js`), the assign bar's frame (`assign_bar.js`, which a feature's bar inherits) and the pill
  (`pill.js`), with `line_groups.css`. Piping's pills move onto it with their behavior unchanged; its panel test
  renames two properties (the groups' link column and form field) and its browser check finds the shared classes
  inside its own pill. Ducting's screens are its spec, its bar, its schedule's columns and totals, and Duct Types.
  So there is no `html/features/ducting/groups.js`. `tests/line_groups_test.rb` holds the panel files to the same
  no-feature rule.
- **Two smaller seams.** The Heater's Change Type form becomes Mechanical's `VariantForm` (`equipment_table.js`),
  which Duct Types' Shape change uses with the shape's sizes; `choiceCell` moves to a kit module, `choice_cell.js`, so
  the layer needs nothing of Mechanical's. Ruby: piping's Colour-by entry building moves to
  `LineGroups::ColourModes` and its `schedule.all` declaration to `LineGroups::ScheduleShapes.install_all`, both
  features calling them; `docs/API_REFERENCE.md` is unchanged for piping.
- **`ph_composer.ducting.schedule.all`** (API 1.108) is the panel's whole read, as piping's, which P4-14d left here.
- **The direction** is two `phc-setting-choice` buttons in a labelled group, Outdoor air pressed by default; the kit
  has no joined segmented control, so none was drawn (D4-30).
- **The Ventilators columns read `ducting_ventilators` only.** P4-14d registered the section, so the schedule
  fallback is not built. A length of 0 shows a dash; the schedule's By Ventilator totals show 0.
- **The legend figure applies the quantity**, so a direction's row equals `totals.by_direction` and a type's its
  `used_length_m`; a legend row's count is still its lines.
- **The bar caps the quantity at 10,000**, the host's limit, before it sends.

## Done when

- M14f has offline evidence in `../evidence/p4-14f-ducting-view.md`, with the UI polish review and, if kit CSS
  changed, the Design System re-sync recorded; host verification lands in `MS3`.
- `make ci` passes on both Rubies; the panel and runtime manifests are current; the installed size is recorded
  against the 52 KB estimate and the headroom left for P4-15 is stated.
