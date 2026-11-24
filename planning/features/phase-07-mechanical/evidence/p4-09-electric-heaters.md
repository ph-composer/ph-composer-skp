# P4-09 evidence: electric heaters

DATE: 2026-11-24
Register row: [M09](../ACCEPTANCE.md). Stage: [P4-09](../phases/p4-09-electric-heaters.md).
Base: `feat/phase-07-mechanical-p4-08b` at `3338f0a4` (PR #572, open at branch time); after #572 merged as `1336367e`
(identical tree), rebased onto `main`. Branch `feat/phase-07-mechanical-p4-09`.

Offline evidence only. No SketchUp process was started by this stage. The host case `M09` (in
`planning/native-acceptance/cases.json`: the Electric Heating subtab, create, coverage in percent, Serves with two
heaters on one Zone, delete with a replacement in one native Undo step, Undo and Redo, export and exact HBJSON reload,
save, fresh-process reopen and re-export, the three panel sizes) is owed to the MS3 sitting (D4-31); nothing here is
host evidence. M09 stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. The kind | `features/mechanical/electric_heaters/schema.rb`, `reads.rb` | `ph_composer.mechanical.electric_heater`, `ehr_`, schema 1: Tag, Notes, `manufacturer`, `model`, `percent_coverage` (0 to 1, required, default 1.0). Persistence is `CatalogOperations` unchanged |
| 2. Serves slot | `serves/payload.rb`, `declarations/serves.rb` | `heater_ids`, `many`, payload schema 4; `serves.assign` describes both list slots |
| 3. Declarations | `declarations/electric_heaters.rb`, `install.rb`, `shell/api.rb` | `electric_heaters.list`, `.all` and its snapshot section, `.create`, `.update`, `.duplicate`, `.delete` with `replacement_id`; API 1.95 with one `CHANGES` row |
| 4. The plan | `electric_heater_plan.rb`, `export_zones.rb` | Pure: one pair per (heater, exported Zone) under the heater's id; `ExportZones.item_findings` reads a list slot (`Zone#names?`) instead of a third copy |
| 5. Export, preflight, Locate | `electric_heater_export.rb`, `preflight.rb`, `locate.rb` | `ph_composer.mechanical.export.electric_heaters`, requiring the Zones and Ventilator sections; notes every finding; `Preflight::FAMILIES` gains it; `locate` takes `electric_heater_ids` |
| 6. Python | `mechanical_sections.py`, `contract/mechanical_records.py`, `composition.py` | `ElectricHeaterSection`: a fresh `PhHeatingDirectElectric` per pair, `add_heating_system` once per heater on a Room, result rows `electric_heaters` with each digest, `conformance` by identifier and digest per Room and no unreported heating system |
| 7. Panel | `html/features/mechanical/electric_heaters.js`, `index.html` | Electric Heating subtab (order 60), Heaters pill: Tag, Coverage (the `percent` quantity), Serves chips with the list picker, hideable identity; New asks for the Tag; delete with replacement or clearing; Locate narrowing |

Docs: `context/CONTRACTS.md` (the kind, Serves schema 4, Locate, the table, the export), `context/AGENT_INTERFACE.md`
(API 1.95), `context/UBIQUITOUS_LANGUAGE.md` (Electric Heater; the Mechanical tab row brought up to date),
`docs/AGENT_GUIDE.md` and the shipped guide ("Mechanical: electric heaters", "Mechanical: the Electric Heater export",
the list slots in "what serves each Zone"), `docs/PRODUCT.md` ("Add electric heaters"; the subtab list),
`docs/USER_DATA.md` (Electric Heater row), `docs/API_REFERENCE.md` (`make fixtures`), the packet CONTRACTS (sections
1, 2, 3 and 6). Runtime and panel manifests refreshed. Host case `M09` added to `cases.json`.

## Departures and choices

- **Inferred in planning** (the stage doc's list): the label Electric Heater, id `ehr`, section names, no
  `in_conditioned_space`, the Heaters pill and order 60, no new code and no "Zone without heater" finding, `user_data`
  carried, no Colour-by for the list slot, no report section.
- **An out-of-range coverage refuses `params.invalid`**, not `validation.failed` as first planned: the action's schema
  carries the range, so the dispatcher refuses before the engine. The stage doc and M09 say so.
- **No table note.** An unserved heater reads "Serves no Zone" in its Serves cell, as a Ventilator does; the stage doc
  was corrected.
- **Goldens.** Every extraction golden gains the empty Electric Heater section and `heater_ids: []` on each Zone
  (`make fixtures`); three Ruby tests and `tests/python/test_model_sections.py` that list sections by hand name it;
  the discovery test counts 25 record kinds.

## For Ed's judgment

- **A heater on a Zone with no Spaces.** PHX reads heating systems through each Room's Spaces
  (`from_HBJSON/create_variant.py`, `add_heating_systems_from_hb_rooms`, PHX 1.59.4), so a heater serving a Zone with
  no Space reaches the HBJSON and not PHX. D4-34 and D4-35 give Pumps and Fans a non-blocking finding for this; D4-33
  gives electric heaters none, so this stage adds none. Add one, or leave it: Ed's call.

## Tests

- `tests/mechanical_electric_heater_test.rb`: defaults (100%, no Manufacturer or Model), coverage below 0 and above 1
  refused on create and update, a taken Tag, an unknown field; a guarded edit with stale refusal, Undo and Redo;
  Duplicate with `user_data`; one heater on two Zones and two on one, assign idempotent, Clear with `item_id`, an id of
  another kind refused; delete in use refused naming both Zones, delete with a replacement already in a list (kept
  once) as one Undo step that Undo restores, with another replacement, with null.
- `tests/mechanical_electric_heater_export_test.rb`: the reference (EH-1 at 60% with `user_data` on Zones A and B,
  EH-2 at 100% on A) gives three pairs, equal per heater, no notes and no preflight rows, owning
  `tests/fixtures/mechanical/electric_heater_extraction.json`; an unserved heater, two Segments and a left-out Zone
  are notes equal to the preflight rows and never block, with `locate`; a Zone naming a missing heater blocks both; an
  unreadable heater blocks as unreadable and its Zones are not missing one; a reserved `user_data` key blocks both;
  the Locate command opens the table; the privacy allowlist.
- `tests/python/test_electric_heater_sections.py`: one `PhHeatingDirectElectric` per pair with identifier, Tag,
  coverage and `user_data`; the reload with Room A holding two heaters and Room B one, conformance passing; tampered
  coverage or digest, a lost heater and an unreported one refused; two Rooms translated unequal under one identifier
  refused on the overwritten Room; bad record values block their pair.
- `tests/python/test_electric_heaters_phx_round_trip.py` (`phx`): two `PhxHeaterElectric` devices, each once, with
  `space_heating_percent` 0.6 and 1.0, each named once in the WUFI XML.
- `tests/mechanical_electric_heater_panel_test.js`: the subtab, its pill and columns; coverage read as 60, sent as
  0.45 guarded by 0.6, a refused draft kept, 120 held unsent; New with the Tag only; the picker assigning without
  `replace`; delete with clearing; Locate narrowing.
- `tools/ui-preview/mechanical_checks.cjs`: an Electric Heating step (coverage in percent, Serves beside a Zone's
  others, New, delete with clearing) and the tab at 1280 x 800, 420 x 732 and 360 x 520; screenshots in
  [p4-09/](p4-09/).

## Gate

`make ci` on Ruby 3.2.2 (on the tree at `6182e297`, identical to the rebased `478507ec`) and on 2.7.2 (`make ci
RUBY=$(rbenv prefix 2.7.2)/bin/ruby`, at `478507ec`), each: "Ruby suite, 10 processes: 3420 runs, 47714 assertions,
0 failures, 0 errors, 1 skips"; JS 1202 pass, 0 fail; Python "426 passed, 1 skipped"; hostkit "48 runs, 268
assertions, 0 failures"; "RBZ verified: 774 files, 8890845 bytes, 27357935 bytes installed" (2.7.2: 27357929),
642,065 under the 28,000,000 ceiling (P4-08b left 27,323,946). The first 3.2.2 runs stopped on RuboCop and ESLint
line lengths in reworded comments, fixed before the passing run.

Also: `make ui-checks` all 39 scripts exit 0 (`mechanical_checks.cjs` with the Electric Heating step);
`uv run --group phx pytest tests/python`: "426 passed, 1 skipped" (`test_map_borders.py`, PH_COMPOSER_MAP_DATA
unset), the PHX round trips 18 executed, 0 skipped (1 new); `uv run tools/runtime/vendor.py --refresh-manifest`
"Runtime verified: 210 assets, 8 wheels, 23037697 bytes".

## UI polish review

Against `ph-composer-ui-polish`: the Heaters table is the shared `EquipmentTable` with no new kit part or CSS, so no
Design System re-sync is needed. Tag pinned first, export fields next, identity behind Columns; the page header's
one primary action is New Electric Heater; record forms in the shared dialog; Serves chips with the amber "Serves no
Zone"; no sideways scroll at the three panel sizes ([1280 x 800](p4-09/electric-heaters.png),
[360 x 520](p4-09/electric-heaters-360x520.png)). Host review owed to MS3.

## Review

Sonnet adversarial read before the gate: no P1 or P2, 7 P3 findings. Fixed: the browser check now deletes a heater
with clearing (its header claimed it); three comments naming only the older list slot or catalogs; tests for an
unreadable heater (blocking as unreadable, its Zones not missing one) and for the Locate command; a long line in
`docs/PRODUCT.md`. The evidence file (this one) was owed. Declined: the preview host's missing range and reference
refusals (the panel validates before sending, and the heat pump branches share the gap), and the record `id` label in
the Python contract (the sibling records share it); the 100%/100% export case is covered by 60%/100% beside the
CRUD test's two heaters at 100%.

Codex gpt-6.2-sol: CODEX_PLACEHOLDER
