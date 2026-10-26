# P3b-05: the Thermal Bridges tab

DATE: 2026-10-03
STATUS: In progress on `feature/thermal-bridges-p3b-05`. Corrected to `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b)
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Entry and scope

Requires P3b-04 and D3b-17, with PRD Q10. Owns the panel: the Thermal Bridges tab with its Types
and Schedule subtabs, the assign bar, and the right-click menu on a selection of Edges. Every
control calls an operation P3b-02 to P3b-04 registered; the panel computes nothing. After this
stage authoring is complete on screen: milestone T-M2, the first point worth a hands-on pass by
Ed.

Behavior owner: the [thermal-bridges PRD](../PRD.md), "Types tab", "Assign" and
"Schedule". Load `.agents/skills/ph-composer-ui-polish/SKILL.md` first. The
[UI baseline](../../../ui-baseline/README.md) has no Thermal Bridges screen, only the tab row;
read its Assemblies and Window Types rows, whose inventory and subtab patterns this tab follows.

Paths are relative to `src/ph_composer/`.

## Steps

1. **The pane.** Enable the reserved tab in `html/index.html`: the disabled "Thermal Bridges"
   button (`data-tooltip="Planned"`, an aria-label) becomes `data-tab="thermal_bridges"` beside
   Zones, Assemblies, Window Types, Library and Export, with a `data-pane="thermal_bridges"`
   among the panes. This is the composition-root edit the rules permit. The panel script list
   between the `panel-modules` markers is generated: add the new modules and run
   `make panel-manifest` (`panel-manifest-check` is in the gate).
2. **Types subtab.** `html/features/thermal_bridges/types.js` on `html/inventory.js`: name,
   psi-value (`LINEAR_PSI` field, signed), group (a chip showing METr's word, storing honeybee-ph's
   string), colour swatch through `inventory_forms.js`, used length (`LENGTH_M`), notes and a
   datasheet link. Add, duplicate, delete with the `ReplacementForm`, in-place and range edits
   through `record_edits` and `inventory_grid`, column sort and value filters through
   `column_menu.js`, and a `tableId` so `table_contributions.js` can add columns later. Group
   words: confirm METr's third word on its screen and record it (D3b-03).
3. **Assign bar.** In the Types subtab: the current selection's count from `edges.selected`, how
   many are assignable and why the rest are not, a type picker, a quantity field, Assign and Clear.
   Assign with nothing assignable is disabled with its reason.
4. **Schedule subtab.** `schedule.js`: one row per run with Zone, Building-Segment, type, length,
   psi, quantity and W/K; findings on their rows with their repair; totals by type and by group;
   a row click calls `runs.locate`. Grouping and filtering through `ui.ViewControls` never change
   the Model.
5. **Right-click menu.** `assign_menu` through `feature.menu_entries`: "Thermal bridge" with one
   item per type and Clear, available only when the selection holds an assignable Edge. Each item
   invokes `edges.assign` through the selection client with the read revision.
6. **Preview and manifests.** A preview fixture in `tools/ui-preview/host.js`'s snapshot section
   map and a `thermal_bridges_checks.cjs` under `tools/ui-preview/` through the shared
   `support/browser_evidence.cjs` collector, declaring with `expect` any error it provokes;
   regenerate the panel manifest and the vendor manifest.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `html/features/windows/section.js`, `inventory.js`, `schedule.js` | Pattern for a pane with subtabs, an inventory and a schedule |
| `html/features/zones/assembly_assignment.js`, `classify.js` | Pattern for acting on the native selection from the panel |
| `features/zones/faces/classify_menu.rb` | Pattern for the right-click submenu |

## Tests (write first)

1. The Types table sends `types.update` with `values` and `expected_values` and keeps a refused
   draft.
2. The group chip shows METr's word and sends honeybee-ph's string.
3. The assign bar disables Assign with a reason when nothing selected is assignable.
4. A schedule row click sends `runs.locate` with that run's params.
5. The panel layout test: nothing outside `html/features/` names thermal bridges.
6. Menu availability is false with only Faces selected and true with one assignable Edge.

## Host gate

Fresh process, Ed at the mouse for the gesture checks: create, edit, duplicate and delete with
replacement in Types; select the roof perimeter natively and assign from the bar and from the
right-click menu; switch display units with a draft open; Locate from the Schedule into a nested
Zone; the UI polish review with native window captures (by window id, never a full-screen
capture). Observe the host with the development tooling: `host_bridge.py wait-for` for deferred work, `host_bridge.py diagnostics` for what happened, `acceptance_case.py begin` and `finish` for the ledger row (`tools/hostkit/.index.md`).

## Implementation notes

Recorded 2026-10-26 while building the stage; the screen is proposed until Ed accepts it at the host gate.

- **One schedule read, two subtabs.** `html/features/thermal_bridges/shared.js` `ScheduleRead` issues
  `schedule.all` through `query.invoke` when the tab is opened or Schedule is chosen and the last read is
  missing or older than the Model, and on Refresh; never on a panel refresh (D3b-13). Types' Used length
  is that read's `totals.by_type`, shown muted with a tooltip once the Model has changed since.
- **Assign bar.** An always-present row above the Types table (`assign_bar.js`), so selecting never moves
  the table. It counts `edges.selected`, assigns only the Edges a write can reach (`reference` and no
  `write_refusal`, the rule `Assignment::Selection.assignable?` names for the menu); Clear also takes an
  invalid assignment that reads with no values, and puts the reason
  beside a disabled Assign with `ui.reasonButton`. The menu's selection client takes the same subset. One
  native selection lives in one context, so a mixed selection is rare; the bar still says which Edges it
  would leave.
- **Right-click menu.** `declarations/menu.rb`: "Thermal bridge" with one item per type by name and,
  when a selected Edge holds an assignment, Clear thermal bridge; offered only with an assignable Edge.
  Each item runs the existing selection client, quantity 1. The availability test and the entries each read
  the selection, so a right-click reads it twice (accepted: at most 250 Edges). Menu entries are not API
  surface, so the API minor stays 12.
- **Forms.** A type is only numbers, so New and Duplicate use the shared form dialog. Duplicate is the
  Materials form moved into the kit as `inventory_forms.js` `DuplicateForm`. Delete is `ReplacementForm`
  with Clear existing uses; it asks for a replacement unless a current read shows the type unused.
- **Datasheet.** Shown as the first link's text with every link in the tooltip, not editable or opened:
  following a link would navigate the panel, and no panel screen edits `datasheet_links` yet.
- **Ordering and filters.** The kit `Inventory` takes an opt-in `columnMenus` ({ sort, filter }) that
  wires `column_menu.js` as Zones / Faces does: Sort A to Z and Z to A on Name, psi-value, Group, Used
  length and Notes, and a Show checklist on Group in METr's words. Order by and its direction give way to
  the column menus there; other inventories are unchanged. Group by stays.
- **Locate.** A click on a run's row locates it, as the PRD asks; the row's Locate icon is the keyboard
  route, and the findings glyph keeps its own click. A hidden Schedule does not repaint; it paints its
  last read when shown. Findings sit behind an alert glyph
  that opens a bubble with each message and its own Locate; Edges in no run and unreadable assignments
  collect under "Not in the schedule".
- **Kit fix.** `library/library.css` made every inventory's Name header static, so it scrolled away under
  the sticky header row and its resize handle overhung the pane by 4 px (Assemblies too). The header now
  stays sticky to the top only.

## Out of scope

The Colour-by mode (P3b-06). The tool (P3b-07). Export rows in the Export tab (P3b-08).

## Done when

- T05 has evidence in `../evidence/p3b-05-thermal-bridges-tab.md`, with the UI polish review.
- `make ci` and `make ui-checks` pass.
