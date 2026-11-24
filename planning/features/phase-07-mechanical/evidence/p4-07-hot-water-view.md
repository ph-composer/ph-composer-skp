# P4-07 evidence: the Hot Water subtab (Systems, Heaters, Tanks)

DATE: 2026-11-24
Register row: [M07](../ACCEPTANCE.md). Stage: [P4-07](../phases/p4-07-hot-water-view.md).
Base: `feat/phase-07-mechanical-p4-06` at `68d21d4e` (PR #569); after #569 merged as `3ed91973` (identical tree),
rebased onto `main`. Branch `feat/phase-07-mechanical-p4-07`, PR #570.

Offline evidence only. No SketchUp process was started. The host case `M07` (in
`planning/native-acceptance/cases.json`) runs at the MS2 sitting with M05 and M06 (D4-31); nothing here is host
evidence, and M07 stays Open. The browser screenshots are a local Chrome run of the preview, not HtmlDialog or
Chromium 88 evidence.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Subtab and three pill tables | `html/features/mechanical/hot_water.js` (Systems, and the System cell the others share), `hot_water_heaters.js`, `hot_water_tanks.js` | Hot Water registers after Ventilation (order 30) with Systems, Heaters and Tanks. Each table is one `EquipmentTable` |
| Shared table | `html/features/mechanical/equipment_table.js` | The shape P4-05's Ventilators had, lifted so every family reuses it: Tag pinned first, the family's columns, Manufacturer, Model and Notes behind Columns, New (a Tag, and the parent System for a Heater or Tank), Duplicate and Delete in the shared dialog, Locate's narrowing, the guards. `ventilators.js` now builds on it; its tests pass unchanged |
| Systems | `hot_water.js` | Tag, Serves (P4-05's chips and Zone picker on slot `hot_water_system_id`), tap points (whole number of 1 or more, or blank), the Tags of the Heaters and Tanks naming it, recirculation temperature and hours read only (muted, with the source in the tooltip, while `from_piping` is false), calculation method (PHX's four, labelled), an info badge on it carrying `mechanical.method_not_exported`, and each pooling note once under the table. Delete offers clearing only while no Heater or Tank names the System |
| Heaters | `hot_water_heaters.js` | System chosen in place (one guarded update), Type, Coverage in percent (a new panel-only `percent` quantity, stored as the fraction, so drafts, guards and readback stay in it), In conditioned space, then the six efficiency columns of which only the Type's are live; the rest are read only (the kit `Inventory` gains a `readOnly` passthrough to its cell editor), so a typed edit or a paste across them is refused whole. A Type change opens the shared form dialog: it names the values that go, asks for each new one with its unit, and sends one update with the new Type, its values and nulls for the old, all guarded |
| Tanks | `hot_water_tanks.js` | System, Role, Export slot (the row's `slot`, read only; amber "No slot left" with the finding), Type, Quantity, Capacity (`volume_l`), Standby losses (W/K, Btu/(h °F)), In conditioned space, then standby fraction, storage loss rate, room and water temperatures, solar connection and solar losses |
| 2. Units | `core/units.rb`, `html/unit_tables.js`, `html/fields.js`, `tests/support/units_vectors.json` | `volume_l`: litres stored, US gallons under IP. The vector, 378.5411784 L = 100 gal, is 100 x 231 in³ x 0.0254³ m/in³, computed apart from both registries |
| 3. Colour-by | `features/mechanical/colour_modes.rb` | `by_hot_water_system`, `entity_kind` `zone`, the same projection as `by_ventilator` over the other slot; the Systems Serves header carries its toggle |
| Preflight locate | `features/mechanical/locate.rb`, `preflight.rb`, `export.rb`, `hot_water_export.rb` | P4-06 left hot water item rows without `locate`. The Locate command moves to its own module with one map from id prefix to param: `ventilator_ids`, `hot_water_system_ids`, `hot_water_heater_ids`, `hot_water_tank_ids`; each table accepts its own |
| Method finding | `hot_water/systems.rb`, `declarations/hot_water.rb`, `tests/fixtures/mechanical/hot_water_method.json` | `METHOD_EXPORTED = false` mirrors the Python check for the System rows; the Ruby golden test writes it to the fixture and `tests/python/test_hot_water_sections.py` holds it equal to what the loaded class does, so a wheel carrying the field fails until it flips |
| 4. Preview and checks | `tools/ui-preview/fixtures.js`, `host.js`, `mechanical_checks.cjs`; `make panel-manifest` | The stand-in host answers the hot water reads and actions with the guards (stale expected value, slot filled, the Type rule, a System still named) and the tank slotting |

API 1.92 with one `API::CHANGES` row. Docs: `context/CONTRACTS.md` ("Mechanical equipment": By hot water system,
Locate, the equipment tables), `context/AGENT_INTERFACE.md`, `context/UBIQUITOUS_LANGUAGE.md` (Mechanical tab,
Heater and Tank Type, Tank slot as Export slot, Recirculation, Piping calculation method), `docs/AGENT_GUIDE.md` and
the shipped guide, `docs/PRODUCT.md` ("Add hot water systems, heaters and tanks"), `docs/API_REFERENCE.md`
(`make fixtures`), the [UI baseline](../../../ui-baseline/README.md), the UI polish reference's patterns, and the
units packet's Q3 row. Runtime manifest refreshed.

## Departures and choices

- **A Type change goes through the shared form dialog**, not a bare select. The annual and inside heat pumps have no
  honeybee-ph default, and the record refuses a Type without its values, so the new values are asked for first; the
  dialog also names the values that go, as the UI polish rule asks of an edit that discards something. The panel
  holds no copy of honeybee-ph's monthly defaults.
- **The calculation method's badge needs a Ruby flag.** P4-06 raised `mechanical.method_not_exported` from Python
  only. The System rows now carry it as info while a method is set, from `HotWater::Systems::METHOD_EXPORTED`, which
  the fixture holds equal to the Python check. The preflight still does not list it.
- **One shared equipment table** rather than three copies of P4-05's Ventilators view: the brief's "reuse those
  shapes; do not fork them". `ReplacementForm`'s `allowClear` may now be a function of the record, and the kit
  `Inventory` passes `readOnly` to its cell editor (kit changes in behaviour only).
- **Heaters' and Tanks' Tags on the System row** come from the Heaters and Tanks sections in the snapshot, not from a
  new Ruby read; the counts stay Ruby's.
- **No Group by** on the hot water tables; the boards show "Group by None" only.

## Tests

| Stage doc test | Test |
| --- | --- |
| 1. A System, Heater or Tank cell sends its `.update` with `expected_values`; a refused draft is kept | `tests/mechanical_hot_water_panel_test.js` "a System, a Heater and a Tank cell edit ..." |
| 2. A Heater's variant change enables only its efficiency fields and clears the others | `mechanical_hot_water_panel_test.js` "a Heater's Type change asks for the new Type's values ..." and "a paste over an efficiency value its Type does not take sends nothing" |
| 3. Litres vectors round trip; a litres draft keeps its unit through a unit switch | `tests/units_test.js` (shared vector, published order, "a tank's litres read back from US gallons ..."), `tests/units_test.rb`; the draft in `mechanical_hot_water_panel_test.js` "capacity shows litres under SI and US gallons under IP ..." |
| 4. `by_hot_water_system` entries per served Zone | `tests/mechanical_hot_water_test.rb` `test_by_hot_water_system_gives_one_entry_per_served_zone_and_leaves_an_unserved_zone_out` |

Also: the Systems table's read-only recirculation, badge and pooling note; the export slot; the System cell; New
Heater's System and its "Create a Hot Water System first" hint; the System delete's clearing; pasted choices by label;
Serves on the hot water slot and a Locate narrowing the Tanks (`mechanical_hot_water_panel_test.js`, 11 tests);
`test_a_piping_calculation_method_is_noted_on_its_systems_row_while_set`; the hot water rows' `locate` and the Locate
command (`tests/mechanical_hot_water_export_test.rb`); the fixture tie in `tests/python/test_hot_water_sections.py`.

## Gate

Final head `1d47eaa6`: `make ci` passes on Ruby 3.2.2 and, with `RUBY` set to 2.7.2, on Ruby 2.7.2, each "Ruby suite,
10 processes: 3372 runs, 45526 assertions, 0 failures, 0 errors, 1 skips"; JavaScript 1,187 passed; Python 399 passed,
1 skipped; hostkit 48 runs; "RBZ verified: 749 files, 8825353 bytes, 27147850 bytes installed", 852,150 bytes under
the 28,000,000-byte ceiling. `uv run tools/runtime/vendor.py --check`: "Runtime verified: 204 assets, 8 wheels,
22956458 bytes". The same gate passed on both Rubies at `8ffba7fb` (the first commit, the same tree as `94447af7`
after the rebase) and at `9cbb6974`. A first 3.2.2 run failed `runtime_manifest_test` and `runtime_host_test` on four
panel files edited after the manifest refresh; refreshed, it passed.

Browser, on the final tree: `make ui-checks` (all 39 scripts under `tools/ui-preview/`) exited 0 with every script
passing; `mechanical_checks.cjs` printed "mechanical browser checks passed". Its hot water steps assert read-only
recirculation, the method badge and the pooling note, a tap points edit with its expected value, Serves on the hot
water slot, By hot water system on and off from the Systems Serves header, no clearing on DHW-1's delete, coverage
reading 85 (percent), an inactive efficiency cell read only, a Heater's Type change through the dialog (the old value
nulled after), 450 L as 118.9 gal under IP, a Role change moving a Tank to the solar slot, New Tank with its System,
and no sideways scroll on each table at 1280 x 800, 420 x 732 and 360 x 520. Screenshots:
[Systems](p4-07/hot-water-systems.png), [Systems at 420 x 732](p4-07/hot-water-systems-420x732.png),
[Heaters](p4-07/hot-water-heaters.png), [the Type change](p4-07/heater-type-change.png),
[Tanks under IP](p4-07/hot-water-tanks-ip.png), [Tanks at 360 x 520](p4-07/hot-water-tanks-360x520.png).

Design System re-sync: not run, bundle unchanged. `git diff --stat origin/main...HEAD` over the six bundled
stylesheets (`base`, `overlay`, `shell`, `table`, `zones`, `library`) is empty; the kit changes (`ReplacementForm`'s `allowClear` as a function, the `Inventory`'s `readOnly`
passthrough to its cell editor, Export grouping a cause by section, the `percent` quantity) are behaviour with no new
visual state. The feature's own `mechanical.css` gained its cell and note styles.

Not run: anything in SketchUp.

## Review

UI polish review: the `ph-composer-ui-polish` skill and its patterns reference were loaded before any panel code, and
the screens were built from the shipped kit (D4-30): the page header's New, the pill row, the kit `Inventory` with
Columns and column menus, Serves chips and the Zone picker, the shared form dialog for New, Delete and the Type change,
read-only cells muted with their source in the tooltip, amber only where the user must act (No slot left), an info
glyph for an information finding, and one muted note under the table for a group of rows. Checked in the preview at
1280 x 800, 420 x 732 and 360 x 520: no sideways scroll on any of the three tables, the Tag pinned beside Actions above
900 px, header labels elided with their tooltip, and the dialog within the pane. Changed after looking: wider
recirculation, method and loss columns so their headers read at 1280. The same rubric went to the Sonnet read and both
Codex cycles; their UI findings (paste across an inactive cell, a draft losing its field, focus after the Type
dialog, coverage in percent, a refused Type change kept) are below. The host review of these screens is part of M07 at
the MS2 sitting.

Sonnet adversarial read before the gate: no P1; 1 P2 and 10 P3. Fixed: a pasted calculation method that was not one
of the four reached the host as NaN (now read by label or value, else refused), pasted Role and Type read by label, an
unknown Type no longer throws, the System delete's clearing tested both ways, leftover assertions removed, the
pooling test renamed, New Heater with no System says "Create a Hot Water System first", and the preview host's header
says it skips the kinds' own range checks. Declined: the method note on an unserved System (the row says what the
export does with the method, served or not, and the docs say "while set"); a field's error clearing on input (the
UnitField already clears it).

Codex gpt-6.2-sol cycle 1 on `94447af7`: 3 P1, 3 P2, all fixed in `9cbb6974`
([review](https://github.com/ph-composer/ph-composer-skp/pull/570#pullrequestreview-6037143001)): a paste down the
efficiency columns skipped an electric Heater's row and wrote to the next Heater, and a draft on a value whose Type
changed elsewhere vanished with its cell (both fixed by keeping inactive cells drawn and read only, through a new
`readOnly` passthrough on the kit `Inventory`); a New form's System could be replaced by the sole one left; Coverage
was a fraction (now a percentage); the Type pill was rebuilt each repaint, losing focus; Locate silently dropped a
second kind (now `params.invalid`).

Codex gpt-6.2-sol cycle 2 on `9cbb6974`: 1 P1, 3 P2, all fixed in `1d47eaa6`
([review](https://github.com/ph-composer/ph-composer-skp/pull/570#pullrequestreview-6037392601)), which merges after
the two-cycle cap unreviewed: coverage drafts were rounded percentages (now the `percent` quantity keeps them in the
fraction); an Export group could join a Ventilator and a Hot Water System sharing a Tag into one mixed Locate (groups
now split by section); a Type change refused after the Type changed elsewhere closed and lost its values (now kept,
Change Type held); a Locate into a catalog read empty waited forever (now answers at once). Every thread has a reply.

## Host

Owed to MS2 (D4-31): case `M07` added to `planning/native-acceptance/cases.json`, with its dependency paths.
