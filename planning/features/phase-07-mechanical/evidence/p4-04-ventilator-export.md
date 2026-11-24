# P4-04 evidence: the Ventilator export

DATE: 2026-11-24
Register row: [M04](../ACCEPTANCE.md). Stage: [P4-04](../phases/p4-04-ventilator-export.md).
Base: `feat/phase-07-mechanical-p4-03` at `21ed04f1` (PR #566); after #566 merged as `c776c2e6` (identical tree),
rebased onto `main`. Branch `feat/phase-07-mechanical-p4-04`, PR #567.

Offline evidence only. No SketchUp process was started. The host case `M04` (the installed RBZ from a fresh process
on the reference model: export the base and shared cases, reload each exact HBJSON and read back both Rooms, move
Zone B to No Building Segment and export again, save, reopen and re-export) is owed to the MS1 sitting (D4-31);
nothing here is host evidence. This stage closes MS1 offline; MS1's host sitting is owed.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Contributor | `src/ph_composer/features/mechanical/export.rb` (`VentilationExport`), `ventilation_plan.rb` (`VentilationPlan`) | `ph_composer.mechanical.export.ventilation`, section version 1, `requires` the Zones section, claims `ph_composer.mechanical.zone_serves` on `Zones::REFERENCE_KIND` (`entity_projections`). The claim and the move of the namespace to `required` (`serves/payload.rb`) are one change. The pure plan takes each Zone once (first occurrence by path), with `exported` from the Zones projection, and the stored Ventilators read with `user_data`: one record per (Ventilator, exported Zone) pair, id `<vnt>_<zon>`, `system_identifier` the Ventilator id, `unit_identifier` that id with `_unit`, the unit's nine values and the Ventilator's `user_data`. A left-out Zone's slots are read from its record (`Zones::ExportProjection.zone_entry`), since the claim captures only exported Zones. Result fields declared through `Export::Privacy` (`ventilation` rows) |
| 2. Preflight | `export.rb`, `ph_composer.mechanical.preflight` | The same plan over the live Model (`Serves::State`), after a blocking row per unreadable Ventilator, per Ventilator metadata problem extraction refuses (`Export::MetadataCheck` with `user_data`) and per exported Zone whose Serves payload this version does not understand. Each finding has the code and `object_id` the export notes, so the run lists it once |
| 3. Section | `python/ph_composer_translation/mechanical_sections.py`, `contract/mechanical_records.py`, `composition.py` (appended) | `VentilationSection`: `requires` the Zone section, `Attachment(ROOM, zone_id)`, required for export. `read` range-checks every value (a `RecordError` blocks the pair as `object.unavailable`); `translate` builds a `PhVentilationSystem` (`sys_type` 1, no ducts) holding a `Ventilator` with the record's values and `user_data`, one mutable object per pair; `attach` calls `set_ventilation_system`. `conformance`: each row's Room holds its system with the row's identifiers, `sys_type` 1 and the unit's values; one item carries one identifier across its Rooms; no Room holds a system the run did not report |
| 4. Fixture | `tests/fixtures/mechanical/extraction.json` (base), `shared_extraction.json`, `result_fields.json` | Owner `tests/mechanical_export_test.rb`, added to `FIXTURE_OWNERS`. Minted Building Segment and Ventilator ids renumbered |
| 5. Report | `export.rb` `report`; `export/result_view.rb` | "Mechanical: Ventilators": one row per exported Ventilator (name, served Zones, quantity, sensible and latent recovery, electric efficiency in Wh/m³) from the Python result, and one line of this section's `mechanical.item_unserved` findings, read through the new generic `ResultView#findings` |
| 6. Agent guide | `docs/AGENT_GUIDE.md` "Mechanical: the Ventilator export", the shipped guide | The preflight and the read-back of the result rows and the HBJSON. API 1.89 with one `API::CHANGES` row |

Docs: `context/CONTRACTS.md` ("Mechanical equipment", the export paragraph; "Translation sections and artifacts",
`result.findings`), `context/AGENT_INTERFACE.md`, `docs/USER_DATA.md` (the Ventilator's map is carried to its
`Ventilator`), `docs/API_REFERENCE.md` (`make fixtures`).

## Departures and choices

- **`mechanical.zone_unventilated` is the preflight's alone.** The export notes what it leaves out or writes for an
  item (`item_unserved`, `zone_left_out`, `item_across_segments`); a Zone written with no system is reported by
  the preflight, whose warnings the run carries into the result (`export/task.rb` `unreported`). So the
  extraction of a Model with no Ventilators stays free of findings, while every such Model's preflight and export
  report now list one `mechanical.zone_unventilated` warning per Zone in a Building Segment (V5, CONTRACTS
  section 6). `tests/export_preflight_test.rb`'s helper sets that warning aside as it does Spaces' own.
- **`mechanical.item_across_segments` is raised here** (CONTRACTS section 6 and the finding cases name it for
  ERV-1); M04 does not require it.
- **No `locate`** on the preflight rows: the Mechanical pane arrives with P4-05.
- **The report's unserved line** needed a carrier: an unserved item has no translated object. `ResultView#findings`
  (a generic addition naming no feature) gives a contributor's report the findings reported against its section.
- **Electric efficiency in the report is labelled Wh/m³ under both unit systems**; the W/cfm unit (A3) arrives with
  P4-05.
- **No ducts.** honeybee-ph's Grasshopper component adds a default supply and exhaust duct, each with a fresh
  identifier, which would make two pairs of one Ventilator differ and refuse to reload (CONTRACTS section 8). The
  section writes none, as `PhVentilationSystem.balanced_hrv` does with no ducts given; P4-14 adds them to every
  pair of an item. The plain constructors are used, since `balanced_hrv` refuses a sensible recovery of 0, the
  record's default.
- **The fixture's boxes stand 1 m apart**, as the Program export's do, so no Face pairs; the reference model's
  adjacency is not what this section reads.
- **Three existing golden owners' contributor lists** (`phase_one_export`, `shading_export`,
  `thermal_bridge_export`) gain the new section, so every whole-extraction golden carries an empty
  `ph_composer.mechanical.export.ventilation` section (4 lines each in seven goldens); the hand-built section lists
  in `tests/python/test_model_sections.py` and `test_entry.py` gain `VentilationSection`.

## Tests

Ruby, `tests/mechanical_export_test.rb`: 12 runs, 199 assertions (Ruby 3.2.2 and 2.7.2).

| Stage doc test | Test |
| --- | --- |
| 1. One row per pair; none for an unserved item or a Zone in no Segment; findings | `test_the_reference_exports_one_pair_per_served_zone_and_owns_the_goldens` (base and shared cases, `item_unserved`), `test_a_cleared_zone_is_unventilated_and_its_item_unserved_and_the_export_proceeds`, `test_a_served_zone_in_no_building_segment_is_left_out_with_its_room` (Room B absent, `zone_left_out` on ERV-2, no unventilated finding), `test_an_item_serving_zones_in_two_building_segments_is_noted_and_written_to_both`, `test_a_zone_naming_a_missing_ventilator_blocks_the_export_and_the_preflight`, `test_an_unreadable_ventilator_blocks_as_unreadable_and_its_zone_is_not_missing_one`, `test_a_serves_payload_this_version_does_not_understand_blocks_the_export_and_the_preflight`, `test_a_zone_with_two_occurrences_gives_one_pair` |
| 5. Privacy allowlist; metadata guard | `test_the_privacy_allowlist_admits_only_the_declared_rows_and_the_metadata_guard_passes_user_data`, `test_a_ventilators_user_data_rides_on_its_pairs_and_a_reserved_key_blocks` (extraction and the preflight both refuse a reserved key), `test_a_required_extension_payload_on_a_ventilator_blocks_the_export_and_the_preflight` |
| 6. Report table and unserved line | `test_the_report_lists_each_ventilator_with_its_zones_and_one_line_for_those_serving_none` |

Python, `tests/python/test_ventilation_sections.py`: 11 tests.

| Stage doc test | Test |
| --- | --- |
| 2. A system per row, record values, `sys_type` 1, identifiers agree | `test_each_pair_builds_its_own_system_with_the_records_values_and_sys_type_one` (two objects, equal identifiers and `to_dict`, no ducts) |
| 3. Two Rooms reload; conformance passes; tampering fails | `test_the_base_case_reloads_two_distinct_ventilators_with_the_records_values`, `test_the_shared_case_reloads_one_system_on_both_rooms` (both through `conformance.check`), `test_conformance_fails_on_a_tampered_identifier_value_or_an_unreported_system`, `test_one_item_carrying_two_identifiers_across_its_rooms_fails_conformance` |
| 4. A recovery fraction above 1 blocks the pair | `test_a_bad_record_value_is_a_record_error_that_blocks_its_pair` (sensible 1.2, quantity 0, a non-boolean flag, a negative efficiency: `object.unavailable`, blocking, not publishable) |
| User data on the unit; result rows match the declaration | `test_a_ventilators_user_data_rides_on_its_unit`, `test_each_row_has_exactly_the_fields_the_ruby_contributor_declares` |
| 7. PHX round trip | `tests/python/test_ventilation_phx_round_trip.py`: base case two `PhxDeviceVentilator`s (ERV-1, ERV-2) with the record's quantity, recoveries and efficiency, each Space naming its Room's device, each named once in WUFI XML and METr JSON; shared case one device both Spaces name |

`uv run --group phx pytest tests/python/test_ventilation_sections.py tests/python/test_ventilation_phx_round_trip.py`:
13 passed, 0 skipped (the two PHX round trips executed).

Mutation checks (source restored after each): dropping the Zone dedupe in `exported_zones` fails
`test_a_zone_with_two_occurrences_gives_one_pair`; dropping the unreadable guard in the plan fails
`test_an_unreadable_ventilator_blocks_as_unreadable_and_its_zone_is_not_missing_one`.

## Gate

`make ci` on the code commit's tree, Ruby 2.7.2 (`make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby`) and then Ruby 3.2.2
(`.ruby-version`), both exit 0 with the same counts; the commit was rebased onto `main` with an identical base tree
(`64450fe2`):

```
Ruby syntax: 892 files OK
893 files inspected, no offenses detected
lint-citations: ok
Ruby suite, 10 processes: 3338 runs, 44441 assertions, 0 failures, 0 errors, 1 skips
379 passed, 1 skipped
Fixtures up to date
Runtime verified: 193 assets, 8 wheels, 22828192 bytes
48 runs, 268 assertions, 0 failures, 0 errors, 0 skips   (hostkit)
RBZ verified: 724 files, 8753442 bytes, 26933065 bytes installed
```

The installed size is 26,933,065 bytes, 1,066,935 under the 28,000,000-byte ceiling. The runtime manifest was
refreshed for the two new shipped Python files and `composition.py` (`uv run tools/runtime/vendor.py
--refresh-manifest`, then `--check`). A first 2.7.2 run stopped at `lint-citations` on two planning ids in test
comments; the second failed five tests (the API minor, a Zone order in the new duplicate test, and three
`tests/export_preflight_test.rb` cases now seeing `mechanical.zone_unventilated`), each fixed before the passing
runs above.

## Review

Architecture and Ruby quality rubrics applied while building: the plan is pure Ruby over plain values and the
Python section computes nothing beyond honeybee-ph's attributes; the new files sit at the feature root, so the
family folders still name no Zone (`tests/mechanical_dependency_test.rb` holds); no other feature names Mechanical.

One Sonnet adversarial read of the diff before the gate: no P1, 2 P2, 8 P3. Fixed: `mechanical.preflight` now gives
a blocking row for an exported Zone whose Serves payload this version does not understand (it had read such a Zone
as served by nothing); tests for an unreadable Ventilator, a not-understood payload and a Zone with two
occurrences; an unreadable Ventilator no longer also reads as `item_missing` on the Zones naming it; a comment on a
left-out Zone's unreadable payload; the `docs/USER_DATA.md` row says an unserved Ventilator's map stays in the
Model. Declined: a run-level test of the preflight warning merge (the foundation's
`tests/export_tasks_test.rb` covers warnings reaching the report once per code and object; this stage's tests pin
that the export and the preflight use the same code and object); a Python test of two pairs with one identifier
and different values (P4-01's `tests/python/test_shared_ventilator.py` pins honeybee-ph's refusal, and Ruby builds
every pair of an item from one record); a test of an old `local_only` envelope (no users; status ignores the
stored relevance); the Zone label differing between the export (projected name) and the preflight (stored name),
which changes no code or object id.

Codex gpt-6-astra, cycle 1 on `64450fe2` (PR #567): 1 P2, fixed in the next commit. `mechanical.preflight` did not
check the Ventilators' metadata as extraction reads it, so a reserved `user_data` key or an unclaimed `required`
extension payload passed the preflight and then blocked the export; the preflight now appends
`Export::MetadataCheck.findings` for the readable Ventilators with `user_data: true`, and two tests pin that the
preflight and extraction refuse alike.

Codex gpt-6-astra, cycle 2 on `678d21b6`: no findings, verdict approve. `make ci` on `678d21b6`, Ruby 2.7.2 and
3.2.2: 3,339 runs, 44,457 assertions, 0 failures, 1 skip; Python 379 passed, 1 skipped; RBZ 26,933,400 bytes
installed. Its residual notes: the sandbox could not run the tests itself, and M04's host case is owed to MS1.

## Native case

`M04` added to `planning/native-acceptance/cases.json` (mode `bridge`, `native_control_required: false`) with paths
for the export, the plan, the Serves payload, Zones' export, the foundation export, the Python section, record,
composition and assembly, and the runtime manifest. Owed to the MS1 sitting.
