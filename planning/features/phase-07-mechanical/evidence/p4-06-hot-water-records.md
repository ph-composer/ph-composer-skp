# P4-06 evidence: Hot Water System, Heater and Tank records and export

DATE: 2026-11-24
Register row: [M06](../ACCEPTANCE.md). Stage: [P4-06](../phases/p4-06-hot-water-records-and-export.md).
Base: `feat/phase-07-mechanical-p4-05` at `768eb228` (PR #568); after #568 merged as `c88a0d06` (identical tree),
rebased onto `main`. Branch `feat/phase-07-mechanical-p4-06`, PR #569.

Offline evidence only. No SketchUp process was started. The host case `M06` (in
`planning/native-acceptance/cases.json`: the records, the guarded System delete with its native Undo, the export and
its exact HBJSON reload, the tank overflow, pooling and calculation-method findings, and a fresh-process re-export) is
owed to the MS2 sitting after P4-07 (D4-31); nothing here is host evidence. M06 stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Three kinds | `features/mechanical/hot_water/systems.rb`, `heaters.rb`, `tanks.rb` | `hot_water_system` (`hws`), `hot_water_heater` (`hwh`), `hot_water_tank` (`hwt`), schema 1, CONTRACTS section 2's fields and honeybee-ph 1.33.68's defaults. Heater and Tank declare `hot_water_system_id` as a required `one` reference. A Heater's variant rule (D4-19) is the kind's `validate`: its own efficiency values required, every other variant's absent. A new monthly heat pump takes honeybee-ph's 2.5 / -8.333 C / 2.5 / 8.333 C |
| 2. Slotting | `hot_water/slotting.rb` | Pure: storage to `tank_1`, `tank_2`; buffer to `tank_buffer`; solar to `tank_solar`; each role's Tanks in name order ignoring case, then id; the rest unslotted. Read by the Tank rows, the preflight and the export plan |
| 3. Operations and reads | `hot_water/operations.rb`, `reads.rb`, `declarations/hot_water.rb` | For each kind: `list`, `all` (snapshot section), `create`, `update`, `duplicate`, `delete`, one Undo step each. System rows: Zones served, findings (`item_unserved`, `zone_left_out`, `hot_water_pooled` as info), `heater_count`, `tank_count`, read-only `recirculation` (60 C, 24 h, `from_piping` false). Tank rows: `slot` and `tank_unslotted`. System delete: refused `reference.in_use` while a Zone, Heater or Tank names it; `replacement_id` moves the Zones through Serves and each Heater and Tank by guarded edit, one proposal; null empties the Zones only |
| 4. Serves slot | `serves/payload.rb`, `serves/reads.rb` | `hot_water_system_id` (`one`), payload schema 2 (F34); rows gain `mechanical.zone_no_hot_water`. Assign, replace (`mechanical.slot_filled` without `replace`) and clear work unchanged |
| 5. Export | `export_zones.rb`, `hot_water_plan.rb`, `hot_water_export.rb`, `export.rb`; Python `mechanical_sections.py` (`HotWaterSection`), `contract/mechanical_records.py`, `composition.py` | One pair per (System, exported Zone), tanks and heaters under their own record ids. The Serves payload can be claimed once, so the Ventilator export keeps the claim and its new `projection` gives every Zone with its slots (`ExportZones`); the hot water section requires it. Python builds fresh objects per pair, `set_hot_water_system`, required for export, `digest` per row; `conformance` reads back identifier, tap points, heater ids, each slot's identifier and capacity, and the digest |
| 6. Preflight | `preflight.rb` | One `ph_composer.mechanical.preflight` for the feature, named by the Ventilator export only; each family's rows under its section, a refused family read one blocking row under its section |
| 7. Metadata | `docs/USER_DATA.md` | Heater and Tank `user_data` ride on their honeybee-ph objects; a System's is left out with `export.metadata_omitted` (no `user_data` on `PhHotWaterSystem`) |

API 1.91 with one `API::CHANGES` row. Docs: `context/CONTRACTS.md` ("Mechanical equipment": the kinds, slots, delete,
Serves schema 2, the claim's projection, the hot water export, the one preflight), `context/AGENT_INTERFACE.md`,
`context/UBIQUITOUS_LANGUAGE.md` (Hot Water System, Heater and Tank, Tank slot, Pooled hot water),
`docs/AGENT_GUIDE.md` ("Mechanical: hot water", "Mechanical: the hot water export") and the shipped guide,
`docs/API_REFERENCE.md` (`make fixtures`), the packet CONTRACTS. Runtime manifest refreshed.

## Departures and choices

- **Three `.list` queries.** The registry requires an `all` read to name a bounded query it prefers (P4-02's finding),
  so each kind has one; CONTRACTS section 3 names them.
- **The claim stays on the Ventilator export.** `check_entity_projections` allows one claim per namespace and kind,
  and only the claimant reads the rows, so the hot water section reads the Zones through the Ventilator export's
  `projection`, as Programs' sibling sections read its plan. Tested with no Ventilator in the Model.
- **One preflight.** The export pane runs each contributor's named preflight, so naming it twice would list each
  row twice. `VentilationExport.preflight` moved to `Preflight`, and the item findings shared by both plans moved to
  `ExportZones`.
- **Slot order is by name.** Record ids are random, so D4-07's "list order" would shuffle T1 and T2; the Tag decides,
  ignoring case.
- **`number_tap_points` at least 1**, not 0: honeybee-ph's setter reads 0 as unset and counts the piping instead.
- **`replacement_id: null`** empties the Zones' slots only. Heaters and Tanks require a System, so one still naming it
  refuses the delete; nothing cascades.
- **`mechanical.method_not_exported` comes from Python**, once per System, since only the loaded class can say. The
  method counts as written only when the class has the attribute (named `piping_calc_method`, a guess pending
  honeybee_ph#135) and its `to_dict()` then carries the value. The Ruby preflight does not list it.
- **Hot water preflight rows carry no `locate` for an item**: the Hot water view is P4-07's. A Zone's row opens the
  Zones tab.
- **No hot water report section.** The stage doc asks for none; the result rows and findings carry it.
- **Panel stand-ins** (`tests/support/mechanical_fixtures.js`, `tools/ui-preview/host.js`) and three panel test
  expectations gain `hot_water_system_id: null`, the shape the real read now answers.
- **Every whole-extraction golden** gains an empty hot water section (4 lines each), and the hand-built section lists
  in `phase_one_export`, `shading_export`, `thermal_bridge_export`, `tests/python/test_model_sections.py` and
  `test_entry.py` gain it, as P4-04 did for ventilation.

## Tests

Ruby, `tests/mechanical_hot_water_test.rb` (9 runs) and `tests/mechanical_hot_water_export_test.rb` (10 runs), both
Rubies.

| Stage doc test | Test |
| --- | --- |
| 1. Round trip; another variant's field refuses; a missing System refuses | `test_a_system_three_tanks_and_two_heaters_round_trip_with_their_defaults`, `test_a_heater_carrying_another_variants_value_or_missing_its_own_refuses`, `test_a_heater_or_tank_naming_a_missing_system_or_none_refuses_and_names_are_unique`, `test_duplicate_keeps_the_system_and_user_data_and_each_write_is_one_undo_step` |
| 2. Delete in use; replacement in one Undo step | `test_deleting_a_system_in_use_refuses_and_a_replacement_moves_zones_heaters_and_tanks_in_one_undo_step`, `test_a_system_delete_with_a_stale_guard_a_bad_replacement_or_an_unreadable_member_refuses` |
| 3. Slotting on the reference, overflow, empty | `test_slotting_by_role_on_the_reference_system_and_its_overflow` |
| 4. Section, shared identifier, conformance, PHX | `test_the_reference_exports_one_pair_per_served_zone_with_its_slots_and_heaters_and_owns_the_golden` (golden `tests/fixtures/mechanical/hot_water_extraction.json`), Python below |
| 5. Calculation method | Python below |
| 6. Pooled, unserved, across Segments | `test_two_served_systems_in_one_building_segment_carry_the_pooling_note` (and none for Zones in no Segment), `test_an_unserved_system_is_noted_alone_and_two_served_systems_in_one_segment_are_pooled`, `test_a_system_serving_zones_in_two_building_segments_is_noted_and_written_to_both` |
| 7. The Serves slot | `test_the_serves_slot_assigns_replaces_and_clears_a_hot_water_system` |
| Also | tank overflow left out, Zone left out and `zone_no_hot_water` preflight-only, missing System blocks, metadata, unreadable Tank, privacy, a Model with no Ventilators |

Python, `tests/python/test_hot_water_sections.py` (17 tests): fresh objects per pair under the records' ids; the
reference reloads with both Rooms holding T1, T2, T3, no solar tank, H-E and H-HP, 8 tap points and 60 C / 24 h;
conformance fails on a tampered slot, capacity, tap count, heater list or digest and on an unreported system; two
Rooms translated unequal under one identifier fail on the overwritten Room's digest; `piping_calc_method` gives one
non-blocking `mechanical.method_not_exported` and no field in the HBJSON, and a stand-in class that writes it
receives it; bad values block their pair; user data rides; the golden names every value the section reads.

PHX round trip, `tests/python/test_hot_water_phx_round_trip.py` (2 tests): one Variant, tanks T1, T2, T3 and heaters
H-E, H-HP each once (WUFI XML names each once, METr lists each once), 8 tap points, 60 C and 24 h; added monthly and
inside heat pumps show PHX reads `COP_1`, `ambient_temp_1`, `COP_2`, `ambient_temp_2` (monthly),
`annual_energy_factor` (inside) and `total_system_perf_ratio` (annual), `annual_COP` staying None.

## Gate

`make ci` passed at `f8100b70` (the same tree as `29c0e7a3` after the rebase) on Ruby 3.2.2 and, with
`RUBY` set to 2.7.2, on Ruby 2.7.2: Ruby suite 3,369 runs, 45,462 assertions, 0 failures, 1 skip on each; JavaScript
1,167 passed; Python 398 passed, 1 skipped; hostkit 48 runs; "RBZ verified: 744 files, 8806812 bytes, 27094342 bytes
installed", 905,658 bytes under the 28,000,000-byte ceiling. `uv run tools/runtime/vendor.py --check`: "Runtime
verified: 200 assets, 8 wheels, 22907190 bytes".

`uv run --group phx pytest -rs tests/python`: 398 passed, 1 skipped (`test_map_borders.py`, `PH_COMPOSER_MAP_DATA` not
set). Every PHX round trip executed (15 passed under `-rA`), the two hot water ones among them.

Not run: the browser checks under `tools/ui-preview/` (no panel change in this stage; the stand-in's Serves rows gain
`hot_water_system_id: null`), and anything in SketchUp.

## Review

Architecture review against `ph-composer-architecture-review` and `ph-composer-ruby-quality` during design and on the
diff: family folders name no Zones or Serves (`tests/mechanical_dependency_test.rb` covers `hot_water/`); domain rules
(variant, slotting, plan, pooling) are pure Ruby; the Python section builds objects only. Follow-up, not in scope:
`Ventilators::Operations` and `HotWater::Operations` are the same catalog CRUD over a kind and could share one module.

Sonnet adversarial read before the gate, 8 findings: a pooling note for Zones in no Building Segment on the System
rows, 0 tap points exported as unset, case-sensitive slot order, an unbounded pooled message, one family's refusal
replacing the whole preflight, no test pinning the heater and tank names across Ruby and Python, missing delete tests
(stale guard, bad replacement, unreadable Heater) and a Model with no Ventilators; all fixed before the gate. Noted,
not changed: the calculation-method attribute name is a guess until honeybee_ph#135 lands, and the "written" check now
requires `to_dict()` to carry the value.

Codex gpt-6-astra cycle 1 on `29c0e7a3`: no findings, approve
([review](https://github.com/ph-composer/ph-composer-skp/pull/569#pullrequestreview-6036392609)). No second cycle.
