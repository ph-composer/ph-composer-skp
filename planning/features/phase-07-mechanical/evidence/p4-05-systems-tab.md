# P4-05 evidence: the Mechanical tab and the Ventilators view

DATE: 2026-11-24
Register row: [M05](../ACCEPTANCE.md). Stage: [P4-05](../phases/p4-05-systems-tab-and-ventilators-view.md).
Base: `feat/phase-07-mechanical-p4-04` at `32be127b` (PR #567); after #567 merged as `0e5ea3bb` (identical tree),
rebased onto `main`. Branch `feat/phase-07-mechanical-p4-05`.

Gate: `make ci` on Ruby 3.2.2 passed at `3b83204f` (the same tree as `2d7d01d4` after the rebase): Ruby suite 3,348
runs, 44,622 assertions, 0 failures, 1 skip; JavaScript 1,158 passed; Python 379 passed, 1 skipped; hostkit 48 runs;
"RBZ verified: 733 files, 8777644 bytes, 27004275 bytes installed", 995,725 bytes under the 28,000,000-byte ceiling.

Offline evidence only. No SketchUp process was started. The host case `M05` (every gesture in M05 on the reference
model with Ed at the mouse, the panel at its three sizes, and the Zone views cases the ledger screens) is owed to the
MS2 sitting after P4-07 (D4-31); nothing here is host evidence. The browser screenshots are a local Chrome run of the
preview, not HtmlDialog or Chromium 88 evidence.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The pane | `html/index.html` (and the preview page, `make panel-manifest`) | The disabled Systems button is gone; `data-tab="mechanical"` sits after Thermal Bridges and before Library, with `data-pane="mechanical"` and `features/mechanical/mechanical.css` linked |
| 2. Subtabs and pill row | `html/features/mechanical/section.js`, `systems.js`; kit `html/pill_row.js`, styled in `base.css` | One page header, the shared `subtabs.js` nav labelled "Mechanical systems", and beneath it a pill row per system. Each family registers its system and tables in `systems.js` (Ventilation › Ventilators now), so the tab names no family. The system and table last shown are remembered with the existing `table_view` display preference (scopes `ph_composer.mechanical` and the system id), never in the Model. `panel.workedOn("ph_composer.mechanical", "mechanical")` |
| 3. Balance read | `features/mechanical/serves/balance.rb` (pure), `serves/reads.rb`, `declarations/ventilators.rb`, `install.rb` | `ventilators.all` and `.list` rows gain `balance` (`supply_m3h`, `extract_m3h`, `imbalanced`, `missing`). One `ph_composer.spaces.all` read and one `ph_composer.programs.zones` read per call, joined to the served Zones by occurrence path. The feature now `requires` Programs |
| 4. Ventilators table | `html/features/mechanical/ventilators.js`, `serves.js`, `optional_values.js`; kit `inventory.js`, `inventory_forms.js` | The kit `Inventory` with `tableId` `ph_composer.mechanical.ventilators`: Tag, Quantity, the two recovery fractions, electric efficiency, frost protection, defrost temperature, in conditioned space, Serves, Supply, Extract, then Manufacturer, Model and Notes. Column sort and value filters from each column's menu. The Inventory gains a Columns menu (`optionalColumns`, feature-owned `hiddenColumns`) and `defaultWidths`; `DuplicateForm` gains `datasheets: false`, since the Ventilator duplicate copies every value and takes no `copy_datasheets`. New is a form asking for the Tag; Delete is `ReplacementForm` with replacement or clearing |
| 5. Units | `core/units.rb`, `html/unit_tables.js`, `html/fields.js`, `tests/support/units_vectors.json` | `electric_efficiency`, Wh/m³ stored, W/cfm under IP, factor `60 / FT3_PER_M3` (1.699). The vector's IP value, 0.55 × 0.028316846592 × 60 = 0.934456, is computed apart from both registries. The export report's efficiency column now follows the report's display units (P4-04 showed Wh/m³ only) |
| 6. Colour-by | `features/mechanical/colour_modes.rb`; Zones' new `ph_composer.zones.occurrences` | `by_ventilator`, `entity_kind` `zone`, one entry per Zone occurrence whose slot names a Ventilator, value the Ventilator id and label its name, colours spread from the ramp; an unserved Zone has no entry; a slot naming no stored Ventilator is incomplete. A row whose path no longer resolves is skipped. The Serves header carries its palette toggle |
| 7. Preview and manifests | `tools/ui-preview/host.js`, `fixtures.js` (`?fixture=mechanical`), `mechanical_checks.cjs`; `src/ph_composer/vendor/manifest.json` | The stand-in host answers the Mechanical reads and actions with the same guards (stale expected value, `mechanical.slot_filled` without `replace`, `reference.in_use`). `uv run tools/runtime/vendor.py --refresh-manifest` then `--check`: "Runtime verified: 200 assets, 8 wheels, 22880567 bytes" |

Also carried in: the preflight rows' `locate` and the view command `ph_composer.mechanical.locate` (P4-04 left the
rows without one until this pane existed), and the deferred Codex finding of PR #564 (below).

Docs: `context/CONTRACTS.md` ("Mechanical equipment": the balance, By ventilator, Locate and the tab),
`context/EXTENSIBILITY.md` ("Colour-by modes": a mode over Zones reads `zones.occurrences`), `context/AGENT_INTERFACE.md`,
`context/UBIQUITOUS_LANGUAGE.md` (Airflow balance, Balance by ventilator, Mechanical tab, Serves, Tag),
`docs/AGENT_GUIDE.md` and the shipped guide, `docs/PRODUCT.md` ("Add Ventilators and choose the Zones they serve"),
`docs/API_REFERENCE.md` (`make fixtures`), the [UI baseline](../../../ui-baseline/README.md), and the UI polish
reference's patterns. API 1.90 with one `API::CHANGES` row.

## Departures and choices

- **The imbalance rule lives here.** The stage doc says `imbalanced` "by `Spaces::Metrics`' rule"; that rule left Spaces
  in #398 (API 1.21), when the per-Zone check was removed because balance is per ventilator. `Serves::Balance` keeps
  it: supply and extract differ by more than a tenth of the larger, strictly, so 100 / 90 is not out of balance.
  Packet CONTRACTS section 4 and the glossary now say so.
- **The balance counts what the export writes.** Each served Zone once (first occurrence by path) and no Zone in no
  Building Segment, as `VentilationPlan` does. A Zone with no Spaces adds nothing, Spaces' own rule for Segment sums.
  The sums are null, with `missing` saying why, while a By Program Zone's Program gives no flow, and also while the
  item serves no exported Zone (a dash, not 0 / 0).
- **A narrower Zones read for the Colour-by mode.** The P4-01 Codex finding (PR #564, carried here) asked that the
  shipping projection not depend on `zones.all`, which validates every Face record. Measured on this branch: with one
  Face record at `schema_version` 99 inside Zone A, `zones.all`, `serves.all`, `spaces.all` and `programs.zones` all
  refuse `validation.failed`. CONTRACTS section 8 pre-authorized a narrower read, so Zones gains
  `ph_composer.zones.occurrences` (id, reference, state, values, extension data; no Faces), and `by_ventilator` reads
  it; `tests/mechanical_balance_test.rb` holds the mode beside that Face. The Ventilators table and the balance still
  read `zones.all`, `spaces.all` and `programs.zones`, so they refuse beside such a Face, as the Zones and Spaces
  views do.
- **The walk's cost, measured in the stub (not host time).** 300 Zones at the Model root: `by_ventilator` 0.071 s and
  90,300 `persistent_id` reads, against Zones' `by_zone` 0.029 s and 300 reads, since `OccurrencePath.resolve` scans
  each level per row (quadratic at the root). Kept simple; an indexed resolve in core is the follow-up if a large
  Model is slow on the host.
- **Zones reads per Ventilators read.** Counted by wrapping `Zones.all` in a scratch test: one `ventilators.all` reads
  the Zones 4 times (Serves usage 1, `spaces.all` 1, `programs.zones` 2), up from 1 in P4-03. Sharing one read across
  sections remains the snapshot-level follow-up P4-03 recorded.
- **Serves rows gain `building_segment`,** the Segment's name or the name a Zone not yet adopted carries, so the
  picker can head an un-adopted Zone by its own name ("Old wing (not adopted)") apart from No Building Segment.
- **The picker writes in two steps.** Newly checked Zones go through `serves.assign` (never with `replace` first);
  after it lands, Zones left unchecked go through `serves.clear`. Each is one Undo step. A refusal of the assign as
  `mechanical.slot_filled` keeps the draft and turns the commit into "Replace and assign", which resends with
  `replace: true`.
- **The optional values' disclosure** is a chevron row action opening a bubble of two unit fields (D4-30, from the
  kit's single-value bubble pattern). The action is pressed while either value is set and names them in its label,
  so a closed row still shows them. Built once in `optional_values.js` for Pumps and Fans (D4-34, D4-35).
- **Two booleans are Yes / No choice cells,** and recovery stays the registry's fraction (V4), not the wireframe's
  percent. The wireframe predates D4-20; the column order follows the stage doc.
- **The agent index now gives counts, not names.** With `zones.occurrences` and `mechanical.locate` added, the shipped
  registry's compact `discover` index passes its 20 KiB budget (`Discovery::INDEX_BYTES`; the operation index alone is
  16,050 bytes), so it answers operation counts by owner and leaves the names to section `operations`, as
  `context/AGENT_INTERFACE.md` says it does past that size. `tests/agent_access_server_test.rb` asserted the names;
  it now asserts whichever the size gives. Raising the budget, or trimming the index, is a follow-up for the agent
  interface, not this stage.
- **A scroll closes an open bubble** (`overlay.js`). Playwright scrolls a cell into view after its click lands, so the
  browser check scrolls first and waits two frames; a user clicking a half-hidden Serves cell may see the same.

## Tests

| Stage doc test | Test |
| --- | --- |
| 1. `ventilators.update` with `values` and `expected_values`, a refused draft kept | `tests/mechanical_panel_test.js` "a cell edit sends ventilators.update ..." |
| 2. The picker sends `serves.assign` and offers replace on `mechanical.slot_filled` | `mechanical_panel_test.js` "the Zone picker assigns, refuses a filled Zone naming its item, replaces on request, then clears" and "a Segment heading checks every Zone in it" |
| 3. Balance: 60 / 50 imbalanced, 40 / 40, 100 / 90 not, By Program flow, shared case, null with a dash | `tests/mechanical_balance_test.rb` (pure rule and the read, including the left-out Zone); the dash in `mechanical_panel_test.js` "the balance cells ..." |
| 4. `electric_efficiency` vectors; the registries agree | `tests/units_test.rb`, `tests/units_test.js` (shared vector, published order); the panel's IP value and a draft through a switch in `mechanical_panel_test.js` |
| 5. Subtabs and pills change the table without a Model write; remembered | `mechanical_panel_test.js` "switching subtabs and pills ..." with a test-registered system of two tables |
| 6. `by_ventilator`: one entry per served occurrence, none unserved | `mechanical_balance_test.rb` (entities and transforms equal Zones' `by_zone`, a nested Zone, a copy, legend counts, beside an unreadable Face) |
| 7. Nothing outside `html/features/` names this feature | `tests/panel_layout_test.js` (the feature list is read from `html/features/`, now with `mechanical`) |

Also: the preflight `locate` rows and the command (`tests/mechanical_export_test.rb`), the report in both unit systems,
the Columns menu, a hidden column's filter cleared, the un-adopted group, Duplicate without the datasheet choice,
the optional values (`mechanical_panel_test.js`), and `tests/mechanical_dependency_test.rb` (requires Programs).

Browser, `make ui-checks UI_CHECKS="tools/ui-preview/mechanical_checks.cjs ..."` on this branch: "mechanical browser
checks passed"; the kit's other users passed in the same run (thermal bridges, inventories, Library, column filter)
and `preview_checks.cjs` ("PASS: preview on the real panel: 4 viewports ..."). The Mechanical check asserts the tab's
place, the pill, the balance cells, an in-place edit with its expected value, 0.76 W/cfm under IP, the picker's
refusal and Replace and assign, a clear, By ventilator on and off from the Serves header, the optional values, the
Columns menu, create, duplicate and delete, and no sideways scroll with the picker inside the pane at 1280 × 800,
420 × 732 and 360 × 520. Screenshots: [the table](p4-05/ventilators-1280x800.png),
[under IP](p4-05/ventilators-ip.png), [the refused picker](p4-05/zone-picker-refused.png),
[the picker at 360 × 520](p4-05/zone-picker-360x520.png), [the optional values](p4-05/optional-values.png).

## Review

Sonnet adversarial read of the diff before the gate: no P1; 6 P2 and 8 P3. Fixed: the picker's focus across its
repaint, a column hidden while its filter could not be cleared, a draft sent from a disposed optional-values bubble,
the bubble's anchor after a repaint, a Locate before the Ventilators are read, a projection row whose path no longer
resolves, the keyword shadowing `balance`, the heading's label under a search, the pill's background token, closing
after a save, the preview host's Segment names, and the missing tests it named. Declined: a copy-not-yet-independent
balance case (Spaces gives such a copy's Spaces to its first occurrence, so the case tests Spaces, not this read);
`item_missing`'s locate (its object is the Zone, which the Zones locate opens).

## Host

Owed to MS2 (D4-31): case `M05` added to `planning/native-acceptance/cases.json`. `acceptance_ledger.py status` over
this branch's changed paths screens 147 cases as affected, because `index.html` and `base.css` change; the Zone views
cases among them (`ZO-*`, `PTAB`, `HGUI`, `UXR-*`) are repeated at the same sitting, as the stage doc asks.
