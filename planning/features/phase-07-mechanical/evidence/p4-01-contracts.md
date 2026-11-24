# P4-01 evidence: equipment contracts, lint and the Pyodide seam

DATE: 2026-11-23
Register row: [M01](../ACCEPTANCE.md). Stage: [P4-01](../phases/p4-01-equipment-contracts-and-seams.md).
Base: `main` at `2c0e13c2`. Branch `feat/phase-07-mechanical-p4-01`. Pins: honeybee-ph 1.33.68 (shipped wheel and
test dependency), PHX 1.59.4 (the optional `phx` test group, not shipped).

Offline evidence only. No SketchUp process was started. The installed-build case `M01` is owed to the MS1 sitting
(D4-31); nothing here is host evidence.

## Step 0: entry check

**Pins.** `pyproject.toml` pins `honeybee-ph==1.33.68` and `phx = ["PHX==1.59.4"]`;
`src/ph_composer/vendor/manifest.json` ships `honeybee_ph-1.33.68-py3-none-any.whl`.

**Wheel re-read.** The mechanical classes P4-02 to P4-08 bind, instantiated from the dev venv's 1.33.68 and their
attributes and defaults listed. The results and the two corrections (`storage_loss_rate` in W/K; no `user_data` on
`PhHotWaterSystem`) are in [CONTRACTS section 8](../CONTRACTS.md#8-what-p4-01-found). The PRD lines that said
"verified at 1.33.65" now say 1.33.68.

**Installed size.** `make rbz rbz-check` on `main` at `2c0e13c2`:

```
RBZ verified: 708 files, 8721080 bytes, 26841808 bytes installed
```

26,841,808 bytes: 747,849 over the 26,093,959-byte baseline (`tools/runtime/vendor.py` `installed_baseline_bytes`),
inside the 2,500,000-byte growth allowance, and 1,158,192 under the 28,000,000-byte ceiling, which binds first
(F37). For comparison, `vendor.py --check` counts the runtime payload alone (191 assets, 22,815,965 bytes); the
footprint keys read the installed RBZ, as Phase 6 measured it. No gate value was changed.

## Step 1: the four contract questions

### 1. A `many` reference in a Zone payload

`tests/support/zone_payload_probe.rb` registers a test-only feature from public calls only: a catalog kind, an
extension `test.zone_payload.slots` with `$.single_id` (`one`) and `$.multiple_ids` (`many`), an assign action and a
delete action that stage through `ph_composer.zones.stage_extension`, and a Zone-keyed Colour-by mode.
`tests/zone_payload_references_test.rb`, on two Zones (one nested in a Group moved 400 in), Ruby 3.2.2:

```
7 runs, 111 assertions, 0 failures, 0 errors, 0 skips
```

The same on Ruby 2.7.2 (`$(rbenv prefix 2.7.2)/bin/ruby -Itests tests/zone_payload_references_test.rb`).

| Test | What it shows |
| --- | --- |
| `a_plain_delete_refuses_an_item_named_in_either_slot_and_deletes_one_named_nowhere` | `reference.in_use` for an item in the single slot and for one only in the list; no revision change and no Model operation; an unnamed item deletes |
| `a_delete_with_a_replacement_moves_both_slots_in_one_undo_step` | Both slots on both Zones move; one Model operation; Undo restores the payloads and the item |
| `a_replacement_delete_leaves_an_invalid_payload_as_stored_and_refuses` | A payload the installed validator refuses (an extra field) is not rebuilt by the move: the delete refuses `copy.rule_missing` and the stored envelope is unchanged. Moving it regardless fails this test |
| `a_replacement_already_in_the_list_is_held_once` | `[first, second]` with first replaced by second reads `[second]` |
| `a_copy_of_the_zone_keeps_its_payload` | A Zone Group copied with its attribute dictionaries (the stub's stand-in for a native copy, as Programs' copy test uses) and made independent has its own Zone id and the same payload; with the original's payload emptied, the copy's list alone still blocks a delete. The native gesture is a host check |
| `a_locked_zone_refuses_the_write_and_a_replacement_delete_touching_it` | `target.locked` for the assign and the replacement delete; no revision change and no Model operation; nothing moved |
| `a_zone_keyed_projection_from_the_public_read_reaches_the_entities_the_zone_mode_paints` | Question 3, below |

Mutation check: changing `Records::Extension.referenced_ids` to skip array values (so the engine no longer scans a
`many` list) fails two of the tests (the plain delete of the listed item, and the copied Zone's list blocking a
delete). The source was restored with `git checkout`.

### 2. One object per (item, Zone) pair sharing identifiers

`tests/python/test_shared_ventilator.py` adds a test-only section attaching at `ROOM`, one record per (Ventilator,
Zone) pair, which builds a new `PhVentilationSystem` and `Ventilator` for each pair with identifiers from the item id.
`tests/python/test_shared_ventilator_phx_round_trip.py` sends the same export, with one detailed Space per Zone, to
the pinned PHX. Run with the group, per test:

```
$ uv run --group phx pytest tests/python/test_shared_ventilator_phx_round_trip.py tests/python/test_shared_ventilator.py -o addopts="" -v
test_shared_ventilator_phx_round_trip.py::test_one_ventilator_serving_two_zones_is_one_phx_device_both_rooms_name PASSED
test_shared_ventilator.py::test_two_rooms_written_with_equal_identifiers_reload_onto_one_system_carrying_the_records_values PASSED
test_shared_ventilator.py::test_two_rooms_sharing_an_identifier_with_different_values_do_not_reload PASSED
3 passed
```

The round trip executed (not skipped). The whole Python suite with the group: `359 passed, 1 skipped` (the skip is
`test_map_borders.py`, `PH_COMPOSER_MAP_DATA is not set`, unrelated).

Read in `honeybee_phhvac/properties/model.py` (1.33.68), `_build_mechanical_devices_from_dict`: ventilation systems
are keyed by identifier and two that differ raise `Conflicting ventilation systems share identifier`; hot water,
heating, heat pump, supportive, exhaust and renewable systems are keyed by identifier with no check, so the last
Room's object wins. The first Python test also checks the section built two distinct system objects with one identifier. The second shows the ventilation refusal; the hot water and heat pump behavior is
read, not run, and is carried to P4-06 and P4-08 as a conformance check on the written HBJSON before reload, since the reload itself hides the difference (CONTRACTS section 6; Codex review of PR #564).

### 3. A Zone-keyed Colour-by projection from a read

The probe's `test.zone_payload.by_single` mode reads `ph_composer.zones.all` and resolves each row's
`reference.zone_path` with `PhComposer::OccurrencePath.resolve`. Its entries equal Zones' `by_zone` entries in entity,
path and world transform (colours and legend order are each mode's own) (`[[1000], [8000, 2000]]`, the nested Zone's x offset 400), carry the payload's item as the
value, and the activated service shows two legend rows. What this establishes is occurrence identity and transforms from the public read; it is not walk-free, since `zones.all` walks the Model and validates Face records and `OccurrencePath.resolve` walks from the root per row (CONTRACTS section 8, carried to P4-05). A copy of `Apt 1` that keeps its Zone id is a second occurrence: both modes give it its own entry (`[[1000], [8000, 2000], [9000]]`), and the item's legend row counts two.

### 4. `honeybee_phhvac` in the Pyodide runtime

`tools/runtime/browser_check.py --translation` gained an `hvac_seam` probe that runs in the shipped runtime page after
the translation has installed the wheels. Run on this branch with the cached Chromium 88, no SketchUp:

```
$ uv run tools/runtime/browser_check.py --translation --out <scratch>/browser_check.json
verdict: PASS
checks: chromium_88, cross_origin_isolated, two_results, no_errors, single_flight_boot, stack_not_loaded,
        translation_answers, cold_boot_within_ceiling, warm_round_trip_within_ceiling, export_translation,
        hvac_seam: all true
hvac_seam: {"package": "honeybee_phhvac", "room_ph_hvac": "RoomPhHvacProperties",
            "ventilation_system": "PhVentilationSystem", "loads": true}
cold boot 2,126 ms; warm round trips 1.7 and 0.6 ms
```

A browser pass is not host evidence (the script says so). The installed-build case is `M01` in
[`cases.json`](../../../native-acceptance/cases.json), mode `bridge`, owed to the MS1 sitting.

## Steps 2 and 3: the seam and the lint

- `stack.PACKAGES` gains `honeybee_phhvac`. `tests/python/test_imports.py` iterates the set: 30 passed. The runtime
  manifest was refreshed (`make runtime-manifest`). `html/runtime/runtime.js` keeps its own `STACK` list, which
  checks that no stack module loads at boot; `honeybee_ph` on it already covers `honeybee_phhvac`, so it is unchanged.
- `PLANNING_IDS` adds `P\d+-\d+[a-z]?` and `M\d\d`; the recipe skips SVG path data whole with a PCRE `(*SKIP)(*FAIL)`
  branch, `SVG_PATH_DATA`, since its move commands (`M12 4v16`) read as register ids. Only a quoted `d` value that
  is path data (a move to two coordinates, then path characters) is skipped. With the old
  pattern a planted `P4-01`, `P4-08b`, `M01` and `M16` all passed (F22); now each fails, planted one at a time in
  `src/ph_composer/zz_planted.rb` and removed afterwards:

```
P4-01 exit=2 :: src/ph_composer/zz_planted.rb:2:# See P4-01.
P4-08b exit=2 :: src/ph_composer/zz_planted.rb:2:# See P4-08b.
M01 exit=2 :: src/ph_composer/zz_planted.rb:2:# See M01.
M16 exit=2 :: src/ph_composer/zz_planted.rb:2:# See M16.
lint-citations: ok   (the tree, after removal)
```

  `tests/python/test_githooks.py` runs the Makefile's `lint-citations` in a scratch repository: eleven planted
  citations fail it with its message and a non-zero status (a register id followed by a date, one beside SVG path
  data, and `d = "..."` holding a register id or a planning path, included) and eight texts pass (SVG path data in
  double and single quotes and with spaces around `=`, `REVIEW F05`, prose).

## Step 5: architecture review

Applied by the stage agent with `.agents/skills/ph-composer-architecture-review/SKILL.md` and, for the test-only
payload feature, `.agents/skills/ph-composer-ruby-quality/SKILL.md`, over the corrected CONTRACTS sections 1 to 6 and
this diff.

- **One contract for built-in and outside features.** The probe is an outside feature: it registers with
  `registry.feature(..., requires: ["ph_composer.zones"])` and writes Zones only through the participant. It needs
  no branch in shell, session, export or the UI kit. The Mechanical feature's Serves follows the same route
  (section 2) and Programs already does.
- **Layering.** Serves (layer 3) reads `zones.all` and stages through Zones; the Colour-by shape uses the core
  `OccurrencePath`, which names no feature. Nothing in Zones, Spaces or Programs gains a Mechanical name.
- **References and metadata.** The `many` slots are proven, the move's shape is written down, and the one class
  without `user_data` is bound to `export.metadata_omitted`.
- **Identity across Rooms.** Equal identifiers must mean equal objects; the stack refuses or silently keeps one, so
  each export section's conformance checks it (section 6).
- **Ruby quality, the probe.** One module, one responsibility per method, the payload rule stated once in
  `problems`, the move in `retarget` and `renamed`; Ruby 2.7 syntax; every refusal declared. RuboCop clean.

Notes carried forward, none blocking: P4-03 writes its own move (no shared helper yet); P4-05 measures the
per-Zone `OccurrencePath.resolve` walk on a large Model; P4-04, P4-06 and the drawn packets keep every (item, Zone)
object of an item equal.
