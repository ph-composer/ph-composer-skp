# P4-14f evidence: the Ducting pills, the Ventilators columns and Colour-by

DATE: 2026-11-25
Register row: [M14f](../ACCEPTANCE.md). Stage: [P4-14f](../phases/p4-14f-ducting-view.md), under the parent index
[P4-14](../phases/p4-14-erv-ducting.md).
Base: built on `feat/phase-07-mechanical-p4-14e` at `ea91dc7d`, moved onto `main` at `dc3792e8` after #587 merged
(identical tree); PR #588 against `main`.

Offline evidence only. No SketchUp process was started. The host case `M14f` (in
`planning/native-acceptance/cases.json`) is owed to the MS3 sitting (D4-31), with the UI polish review on the host.
M14f stays Open. With this stage every P4-14 sub-stage is implemented.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| Panel layer | `html/line_groups/` (`shared.js`, `groups.js`, `schedule.js`, `assign_bar.js`, `pill.js`, `line_groups.css`); `html/choice_cell.js` | Piping's Piping pill code, feature-neutral: the read, the groups and New <group>, the schedule shell, the bar's frame and the pill. Piping's pills moved onto it (`html/features/piping/` keeps its bar's role values and tool, its schedule's columns, tree and totals, and Pipe Types); `groups.js` gone |
| Kit seams | `features/mechanical/equipment_table.js` (`VariantForm`), `hot_water_heaters.js`, `ventilators.js` | The Heater's Change Type form generalised; Ventilators exports `SYSTEM` and `SECTION` |
| 1. Pills and Duct Types | `html/features/ducting/section.js`, `duct_types.js`, `shared.js` | Duct Types (order 20) and Ducting (order 30) after Ventilators; Duct Types on the equipment table with Shape, the shape's sizes (the other's a dash), insulation, Colour and Used length; a Shape change asks for the new sizes |
| 2. The Ducting pill | `assign_bar.js`, `schedule.js`, `ducting.css` | The cold-runs line; the bar (Duct Type, Outdoor air or Exhaust air, Quantity 1 to 10,000); the groups with their Ventilator; the schedule by Ventilator with totals by direction and by Ventilator, the missing-run note, findings and Locate |
| 3. The Ventilators columns | `ventilator_columns.js` | `Outdoor air duct` and `Exhaust air duct` from `ducting_ventilators`, unit-aware headers, a dash for none |
| 4. Colour-by | `features/ducting/colour_modes.rb`; `line_groups/colour_modes.rb`; piping's `colour_modes.rb` moved onto it | `ph_composer.ducting.by_direction` and `ph_composer.ducting.by_type`, 5 px, legend `figure` the length times the quantity |
| Panel read | `features/ducting/declarations/schedule.rb`; `line_groups/schedule_shapes.rb` (`install_all`), piping's moved onto it | `ph_composer.ducting.schedule.all`, API 1.108 |
| 5. Preview and checks | `tools/ui-preview/host.js`, `fixtures.js`, `ducting_checks.cjs`, `piping_checks.cjs` | The preview host answers the ducting sections, reads and writes; piping's check finds the shared classes in its own pill |
| 6. Documents | `docs/PRODUCT.md` ("Draw ERV ducting"), `docs/AGENT_GUIDE.md` and the shipped guide, `context/AGENT_INTERFACE.md`, `context/CONTRACTS.md`, `context/EXTENSIBILITY.md` ("Line groups"), `context/UBIQUITOUS_LANGUAGE.md`, `planning/ui-baseline/README.md`, the units packet's ducting row, the packet CONTRACTS section 3 | |
| Host case | `cases.json` `M14f`; `M13e` gains `html/line_groups/*` | Owed to MS3 |

## Recorded at implementation

See the stage doc, "Recorded at implementation": the panel layer and piping moved onto it; `VariantForm` and
`choice_cell.js`; the Ruby moves (`LineGroups::ColourModes`, `ScheduleShapes.install_all`); `schedule.all`; the
direction as two setting choices; the Ventilators columns reading the snapshot section only; the legend applying the
quantity; the bar's quantity cap. Piping's panel test changed only in two property names (`.col-link`, `form.link`)
and its browser check only in its selectors; `docs/API_REFERENCE.md` is unchanged for piping.

## Tests

- JS `tests/ducting_panel_test.js` (8): the pills after Ventilators, the Duct Types columns, an update with
  `expected_values`, a refused draft kept, the other shape's size inactive with its reason, used length and Delete's
  usage text; a Shape change asking for the new sizes and sending one guarded update; the cold-runs line, the bar's
  direction, quantity (refused at 0 and 10,001) and Assign with the selection's references, the notice and Clear on
  the assigned line only; the read once, schedule order, Locate on a row, the finding's badge and its Locate, totals
  with the quantity applied, the missing-run note, Refresh; a group's Ventilator linked and New Ducting group; the
  Ventilators columns in m and ft with a dash for none; a served Ventilator's missing-run note with no run yet; a held
  Shape change sending nothing on Enter.
- Ruby `tests/ducting_colour_mode_test.rb` (3): one entry per duct occurrence with its world segment (the group's
  move applied), direction colours, the legend lengths equal `schedule.all`'s totals by direction (5.0 and 4.8, ERV-2's
  Exhaust air at quantity 2) and the type rows `duct_types.all`'s used lengths (4.3, 5.5), a type's colour, a missing
  type incomplete, Select by row, an unassigned line uncoloured; nothing written.
- Ruby `tests/line_groups_test.rb`: the no-feature rule now also covers `html/line_groups/`.
- Updated: `tests/piping_panel_test.js` (two property names), `tests/api_test.rb` (minor 108).
- Browser `tools/ui-preview/ducting_checks.cjs`: the three pills, the Ventilators columns, a Shape change, the bar's
  direction and quantity, a group linked, New Ducting group, the schedule's finding, totals and Locate, Colour by duct
  direction, a populated group relinked moving its lengths, and every pill at the three panel sizes with the findings
  bubble in reach.

## Size

Installed RBZ 27,935,173 bytes on `e11e6dbf` (`make ci`, "RBZ verified: 877 files, 9094448 bytes, 27935173 bytes
installed"), 38,344 over P4-14e's 27,896,829 against the 52 KB estimate (53,248 bytes): 28 percent under. 64,827 bytes
are left under the 28,000,000 ceiling, about 25 KB above P4-15's 40 KB reserve. The extraction alone, measured
before any ducting code, cost about 11 KB installed. On the code head piping's former 63 KB of panel code is 41 KB of
layer (`html/line_groups/` and `choice_cell.js`) and 31 KB of piping; ducting's panel files are 21 KB.

## Review

- Sonnet adversarial read before the gate: no reproduced defect, 11 findings. Fixed: comments in the Mechanical
  folder and the layer naming a feature (and `tests/line_groups_test.rb` now holds `html/line_groups/` to the rule);
  the layer's used-length cell using Mechanical's class (now `line-group-read-only`); dead exports and fields; a
  "Missing type" tooltip on the ducting schedule; the bar's quantity capped at 10,000; tests for the finding badge
  and its Locate and Delete's usage text. Recorded: no `ducting/groups.js` and no snapshot fallback for the
  Ventilators columns (stage doc); the Design System (below); the By Ventilator totals showing 0 where the
  Ventilators table shows a dash. Declined: Delete-with-replacement and New-asks-for-Tag panel tests, which are the
  shared equipment table's and tested there.
- Codex gpt-6.2-sol cycle 1 on `e11e6dbf`: 1 P1, 4 P2, 1 P3, all fixed in the next commit. P1: Enter could send a
  Change Shape (or Change Type) the dialog held as stale after the shape changed elsewhere and Undo restored it; the
  shared `VariantForm.submit` now refuses a held, disabled or busy change, a test reproducing it first. P2: the
  schedule hid its totals with no run, so a served Ventilator's missing-run note never showed before the first duct;
  the ducting view now shows its totals while a Ventilator carries a note (piping unchanged), tested. P2: the preview
  host now moves a relinked group's lengths to its new Ventilator, and the browser check relinks DG-2 and reads them
  move. P2: this evidence file was untracked on the reviewed head; committed. P2: `choice_cell.js` joins M13e's and
  M14f's dependency paths. P3: the ACCEPTANCE row names the registered modes, `ph_composer.ducting.by_direction` and
  `ph_composer.ducting.by_type` (the stage doc's `ducting_by_*` is the short form).
- Codex gpt-6.2-sol cycle 2 on `630508f7` (the cap): 1 P1, 5 P2. Fixed in the final commit, which merges unreviewed
  after the cap and is owed one Codex review before the phase archive: P1, a new selection now shows its own quantity
  unless one was typed for the selection before it and not yet sent (a focused field no longer blocks it), tested;
  P2, typing in a held Change Shape keeps the reason it is held, tested. Declined, each shared with piping's pill and
  recorded as a follow-up for both features: a Duct Type whose only duct sits outside every Ducting group reads as
  unused, so Delete shows the plain confirmation and the host refuses `reference.in_use` with its message; Locate on a
  run of more than 10,000 lines sends more paths than `runs.locate` takes and is refused; the preview host's Assign
  changes the selected lines but not its synthetic runs; a Ventilator tagged "No Ventilator" groups with unlinked
  runs under one heading (piping's System column has the same key).

## Gate

- `make ci` on Ruby 3.2.2, chained before the code commit `e11e6dbf`: "Ruby suite, 10 processes: 3617 runs, 51078
  assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1232", "fail 0"; Python "477 passed, 18 skipped" (the
  worktree's `phx` group unsynced); hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 877 files, 9094448
  bytes, 27935173 bytes installed".
- `make ci` on Ruby 3.2.2, chained before the review-fix commit `93ff50de`: "Ruby suite, 10 processes: 3617 runs,
  51078 assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1234", "fail 0"; Python "477 passed, 18 skipped";
  hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 877 files, 9094634 bytes, 27935753 bytes installed"
  (+38,924 against the estimate; 64,247 left).
- Panel manifest: `make panel-manifest` current; runtime manifest refreshed (`vendor.py --refresh-manifest`, "Runtime
  verified: 238 assets, 8 wheels").
- Design System: not re-synced. No token, type style or existing kit part's look changed: `choice_cell.js` moves
  Mechanical's enum-pill select out unchanged, and `line_groups.css` holds piping's former rules under shared names.
  If the owner counts the line-group pill as a kit part, a re-sync from `main` is owed after merge.
