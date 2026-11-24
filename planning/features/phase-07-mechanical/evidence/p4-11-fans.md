# P4-11 evidence: fans

DATE: 2026-11-24
Register row: [M11](../ACCEPTANCE.md). Stage: [P4-11](../phases/p4-11-fans.md).
Base: branched from `feat/phase-07-mechanical-p4-10` at `df603554` (PR #574, open at branch time). Branch
`feat/phase-07-mechanical-p4-11`.

Offline evidence only. No SketchUp process was started by this stage. The host case `M11` (in
`planning/native-acceptance/cases.json`: the Fans subtab, create, type, flow, runtime and Power in place, the electric
values disclosure with the operation following the runtime, Serves with two fans on one Zone, a fan on a Zone with no
Space and its Export-tab warning, delete with a replacement in one native Undo step, Undo and Redo, export and exact
HBJSON reload with the linked supportive device, save, fresh-process reopen and re-export, the three panel sizes) is
owed to the MS3 sitting (D4-31); nothing here is host evidence. M11 stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 0. Stage doc | `phases/p4-11-fans.md`, ACCEPTANCE M11 | Written in full from the stub, D4-35 and the pinned wheel, its own commit `d67695f1` (`make ci-docs`) |
| 1. The kind | `features/mechanical/fans/schema.rb`, `reads.rb` | `ph_composer.mechanical.fan`, `fan_`, schema 1: Tag, Notes, `manufacturer`, `model`, `exhaust_type` (`kitchen_hood`, `dryer`, `user_defined`; `user_defined`), `quantity` (1), `exhaust_flow_rate_m3h` (0), `annual_runtime_minutes` (0), `norm_energy_demand_w` (absent: no supportive device), `in_conditioned_space` (true), `annual_period_operation_khrs` (absent: follows the runtime). `Fans.annual_period_operation_khrs` resolves it as minutes over 60,000; rows add `annual_period_operation_khrs_default` |
| 2. Serves slot | `serves/payload.rb`, `declarations/serves.rb` | `fan_ids`, `many`, payload schema 6 |
| 3. Declarations | `declarations/fans.rb`, `install.rb`, `shell/api.rb` | `fans.list`, `.all` and its snapshot section, `.create`, `.update`, `.duplicate`, `.delete` with `replacement_id`; API 1.97 with one `CHANGES` row |
| 4. The plan | `fan_plan.rb` | Pure: one pair per (fan, exported Zone) under the fan's id, Power null when blank, the operation resolved; the shared item findings; `mechanical.item_missing` blocking |
| 5. Shared Spaces reads | `export_zones.rb`, `pump_export.rb` | `ExportZones.spaced(reader)` and `ExportZones.live_spaced(request, zones, references, slot)`, lifted out of `PumpExport` (which now calls them) so the Fan export reuses them; `mechanical.zone_without_spaces` from P4-10's `ExportZones.spaceless_findings` with the slot `fan_ids` and the label Fan |
| 6. Export, preflight, Locate | `fan_export.rb`, `preflight.rb`, `locate.rb`, `codes.rb` | `ph_composer.mechanical.export.fans`, requiring Zones, the Ventilator export and Spaces; `locate` takes `fan_ids` |
| 7. Python | `mechanical_sections.py`, `contract/mechanical_records.py`, `composition.py` | `FanSection`: a fresh exhaust ventilator of the type's class per pair (flow / 3600 into m³/s) and, with Power, a fresh type 10 `PhSupportiveDevice` under the same id; `add_exhaust_vent_device` and `add_supportive_device`; rows `fans` with both digests; `conformance` per Room by identifier, a Fan-id supportive device only where the row has Power, and no unreported Fan-id object |
| 8. Panel | `html/features/mechanical/fans.js`, `optional_values.js`, `index.html`, unit registries | Fans subtab (order 50), Fans pill: Tag, Type, Quantity, Flow (airflow), Runtime (new `annual_minutes` quantity, min/yr in both systems), Power (W, blank allowed), Serves chips with the list picker, hideable identity; In conditioned space and Operation behind each row's arrow, the empty Operation showing "From runtime (...)" (`optional_values.js` gains a unit field's `placeholder`); the arrow's label says the values export only with Power when Power is blank |

Docs: `context/CONTRACTS.md` (the kind, Serves schema 6, Locate, the table, the Fan export, the shared Spaces reads),
`context/AGENT_INTERFACE.md` (API 1.97), `context/UBIQUITOUS_LANGUAGE.md` (Fan; the Mechanical tab row),
`docs/AGENT_GUIDE.md` and the shipped guide ("Mechanical: fans", "Mechanical: the Fan export", the list slots),
`docs/PRODUCT.md` ("Add fans"; the subtab list), `docs/USER_DATA.md` (Fan row), `docs/API_REFERENCE.md`
(`make fixtures`), the packet CONTRACTS (sections 2, 3 and 6), PLAN, README, STATUS, the equipment STATUS. Runtime and
panel manifests refreshed. Host case `M11` added to `cases.json`.

## Departures and choices

- **Inferred in planning** (the stage doc's list): `exhaust_type` names and default, flow in m³/h written as m³/s,
  runtime in minutes in a new `annual_minutes` quantity, Power absent on create (0 W is filled), the operation stored as
  an override, the linked device sharing the fan's id and quantity with the class's IHG values, the Fan label and
  `fan` prefix, the finding through the lifted Spaces reads, Fan-id conformance scoping, the Fans pill at order 50.
- **For Ed:** the linked supportive device takes the fan's quantity, so a record of three hoods draws three times its
  Power; PHX 1.59.4 drops the exhaust ventilator's quantity (probe on 2026-11-24: a kitchen hood of quantity 3 gave a
  PHX device of quantity 1), so WUFI-Passive and METr see one exhaust device per fan record whatever its quantity.
  Nothing compensates for it.
- **Goldens.** Every extraction golden gains the empty Fan section (`make fixtures`); three Ruby tests and
  `tests/python/test_model_sections.py` that list sections by hand name it; the discovery test counts 27 record kinds.
- **Design System:** re-synced from `main@3a1483bd` (#574) as artifact version 37: the Table card gains P4-10's
  `electric_power` (W) and `kilohours` (kh/yr) quantities; `bundle.css` unchanged (none of its eight stylesheets
  changed since `main@d2ba5936`); tokens unchanged. This stage's `annual_minutes` quantity is owed to the sync after
  #575 merges.

## PHX trace and round trip

Read in PHX 1.59.4 (`from_HBJSON/create_variant.py`, `add_exhaust_vent_devices_from_hb_rooms`): PHX walks each Room's
Spaces, adds each exhaust ventilator once by key to every simulated Zone and builds it with
`create_hvac.build_phx_exhaust_vent_device` (display name, flow times 3600, runtime; not quantity). Proved by
`tests/python/test_fans_phx_round_trip.py`: the reference's four pairs give three exhaust devices on the Zone, each once
(a range hood with 250 m³/h and 10,950 min, a dryer with 100 m³/h and 6,000 min, a user-defined exhaust), and two
supportive devices, the hood's (type 10, quantity 2, 120 W, 0.1825 kh) and F-3's with its named 2.5 kh; WUFI XML names
F-1 twice (exhaust and supportive device) and F-2 once. One record becomes two objects with Power and one without.
With Zone B's Space removed, every fan still reaches PHX once through Room A; a powered fan only on the Room with no
Spaces gives neither object.

## Tests

- `tests/mechanical_fan_test.rb`: defaults, seven out-of-range values refused on create and update, a taken Tag; the
  operation following the runtime, an override surviving a runtime change and null returning to it, a blank Power
  removing the value; guarded edit with stale refusal, Undo and Redo; Duplicate with `user_data`; two Zones and two
  fans on one, Clear with `item_id`, an id of another kind; delete in use, with a replacement (kept once) as one Undo
  step that Undo restores, with null.
- `tests/mechanical_fan_export_test.rb`: the reference (F-1 on A and B with Power and `user_data`, F-2 on A without,
  F-3 on A with Power and a named operation) gives four pairs, equal per fan, F-2's Power null, F-3's 2.5 kh, no notes and no preflight rows, owning
  `tests/fixtures/mechanical/fan_extraction.json`; a fan on a Zone with no Space noted and still written, the same in
  the preflight; an unserved fan, two Segments and a left-out Zone; a missing fan blocks; an unreadable fan blocks as
  unreadable; a reserved `user_data` key; Locate; the privacy allowlist. `tests/mechanical_pump_export_test.rb` runs
  unchanged through the lifted reads.
- `tests/python/test_fan_sections.py`: one exhaust ventilator per pair of the type's class with every value, plus a type
  10 supportive device with Power and none without; the reload and conformance; tampered rows, a lost fan, a missing
  supportive device, an unreported Fan-id supportive device, a supportive device on a fan without Power and an
  unreported row refused; a Pump's device on the same Room passing both sections; unequal pairs under one identifier
  refused; nine bad record values block their pair.
- `tests/python/test_fans_phx_round_trip.py` (`phx`): the three cases above.
- `tests/mechanical_fan_panel_test.js`: the subtab, pill and columns; a type change and a flow edit guarded, negative
  flow, runtime and power and quantity 0 held, a blank Power sent as null; the disclosure (pressed states, the
  unpowered label, Yes and No with no blank, the "From runtime" placeholder following the runtime, an override and a
  blank sent as null); New with the Tag only; the picker; delete with clearing; Locate.
- `tools/ui-preview/mechanical_checks.cjs`: a Fans step (a type in place, a blank Power, the electric values, Serves
  beside a Zone's others, New, delete with clearing) and the tab at 1280 x 800, 420 x 732 and 360 x 520; screenshots in
  [p4-11/](p4-11/).

## Review

Sonnet adversarial read before the gate (stage doc, M11, the three rubrics): no P1; 16 findings. Fixed: two
conformance tests the stage doc names (a missing supportive device, an unreported Fan-id supportive device), the dead
`:empty` branch in the export test, F-2's `in_conditioned_space` asserted, a non-boolean refused in Ruby, F-1's WUFI XML
count, the arrow's label when Power is blank, `annual_minutes` precision 1, the panel test's message pinned and
quantity 0 held, the quantity note in PRODUCT, the PHX-only wording in the Agent Guide, a long line; this file.
Declined: a JS test of delete with a replacement (the shared `EquipmentTable` form, covered by its own tests); an
identifier check in `FanRecord.read` (Ruby makes the identifier the item id, as for Pumps); one Spaces read shared by
the Pump and Fan preflight rows (correct as is; the read is cheap).

Codex gpt-6.2-sol cycle 1 on `2d1c817f` (PR #575): 3 P2, all test gaps, all fixed in the next commit: a powered fan
only on a Room with no Spaces reaches neither PHX collection; a user-defined fan at 0 W with a named 0 kh keeps both
zeros through the reload (and the Ruby kind keeps them); the preflight matches the export notes after a Zone leaves its
Building Segment.

Codex gpt-6.2-sol cycle 2 on `617ab538`: 2 P2, both fixed in the next commit, which merges after the two-cycle cap
unreviewed: the Operation field's value-when-blank is now its accessible description too (a hidden hint named by
`aria-describedby` beside the error), not only its placeholder; the Ruby reference gains F-3, a powered user-defined
fan with a named operation, so the override is proved from Ruby through the HBJSON reload and PHX.

UI polish (rubric `.agents/skills/ph-composer-ui-polish/SKILL.md`): the table reuses `EquipmentTable` and the
Mechanical disclosure with no new kit part; columns carry their unit once in the header; a blank Power shows the
kit's dash; the disclosure's choice has no blank because the value is required; the 360 x 520 view scrolls inside the
table, not sideways.

## Gate

`make ci` on Ruby 2.7.2 (`make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby`) on the code tree of the stage commit: "Ruby
suite, 10 processes: 3450 runs, 48656 assertions, 0 failures, 0 errors, 1 skips"; JavaScript 1214 of 1214 pass; Python
"465 passed, 1 skipped" (the skip is `test_map_borders.py`, `PH_COMPOSER_MAP_DATA` unset); hostkit 48 runs; `ty`
clean; "RBZ verified: 786 files, 8922073 bytes, 27461199 bytes installed", 538,801 under the 28,000,000 ceiling
(P4-10 left 27,412,194). `make ci` on Ruby 3.2.2 is chained into the stage commit. The first 2.7.2 runs stopped on
the shipped guide and the runtime manifest (stale after the review fixes) and on `ty` (an optional device not narrowed
in a test); each was fixed and the gate rerun.

Browser checks: `make ui-checks` ran all 39 scripts in `tools/ui-preview/`, exit 0 (the target fails on any script),
39 of 39, on the tree before the last `ty` fix (a test-only change).

PHX round trips: `uv run --group phx pytest tests/python -k phx_round_trip`: 24 passed, 0 skipped (3 of them the
fans'); the whole Python suite under the `phx` group: 465 passed, 1 skipped (the map data skip above).

Final head (after both review cycles): `make ci` on Ruby 2.7.2: "Ruby suite, 10 processes: 3450 runs, 48687
assertions, 0 failures, 0 errors, 1 skips"; JavaScript 1214 of 1214; Python "466 passed, 1 skipped"; "RBZ verified: 786
files, 8922210 bytes, 27461724 bytes installed", 538,276 under the ceiling; and on Ruby 3.2.2 chained into the final
commit. `make ui-checks UI_CHECKS=tools/ui-preview/mechanical_checks.cjs` passes on the final panel code (the other 38
scripts ran at `d1c69b7b`; the review fixes touched only `optional_values.js` and Fan tests). PHX round trips 24
executed, 0 skipped.
