# P4-14e evidence: ducting export

DATE: 2026-11-25
Register row: [M14e](../ACCEPTANCE.md). Stage: [P4-14e](../phases/p4-14e-ducting-export.md), under the parent index
[P4-14](../phases/p4-14-erv-ducting.md).
Base: built on `feat/phase-07-mechanical-p4-14d` at `11007ffb`, rebased onto `main` at `1b05db9c` after #586 merged
(identical tree); PR #587 against `main`.

Offline evidence only. No SketchUp process was started. The host case `M14e` (in
`planning/native-acceptance/cases.json`: export, reload the exact HBJSON and read both Rooms' ventilation systems, the
shared case's equal identifiers, a deleted ERV-2 refusing with its Locate, save, reopen and re-export) is owed to the
MS3 sitting (D4-31). M14e stays Open.

## The wheel (step 1)

Read in `src/ph_composer/vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl` on 2026-11-25, unchanged since P4-14's
table:

- `honeybee_phhvac/ducting.py`: `PhDuctSegment(_geom, _insul_thickness=0.0254, _insul_conductivity=0.04,
  _insul_refl=True, _diameter=0.160, _height=None, _width=None)`, height before width, so the section passes keywords;
  `shape_type` is 2 only when both height and width are set. `PhDuctElement(_display_name=None, _duct_type=1)` keys
  segments by identifier, `add_segment` raises a bare `Exception` joining round and rectangular segments, and it has
  no quantity of any name. `to_dict` writes segments as a map keyed by identifier.
- `honeybee_phhvac/ventilation.py`: `add_supply_duct_element` and `add_exhaust_duct_element` append to the lists
  `supply_ducting` and `exhaust_ducting` with no `duct_type` check; `to_dict` writes both as lists;
  `supply_ducting_total_length` and `exhaust_ducting_total_length` sum the elements' lengths.
- `honeybee_phhvac/properties/model.py`: on reload, two Rooms' ventilation systems sharing an identifier must have
  equal `to_dict()`, or the load raises "Conflicting ventilation systems share identifier".
- PHX 1.59.4 (the `phx` group in the worktree's `.venv`): `from_HBJSON/create_variant.py` builds one device per system
  key and adds every element of both lists through `create_hvac.build_phx_duct` with that device's `id_num`;
  `model/hvac/collection.py` `add_vent_ducting` keys by identifier; `PhxDuctElement.quantity` is always 1.

No quantity carrier exists, so the quantity bullet stands as inferred (below).

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 2. Extraction | `features/ducting/export.rb` (`ExportProjection`), `extraction.rb` (`Extraction`), `codes.rb`; the layer's `line_groups/export_scan.rb` | Section version 1, `requires` the Zones and Ventilator sections; ducts from the snapshot through `LineGroups::ExportScan.edges`; one record per Ventilator with ducts, in metres; a run of quantity N as N elements; `ducting.ventilator_unexported` |
| 3. Preflight | `ph_composer.ducting.export_preflight` | The run findings with `runs.locate` params, `ducting.run_missing` and `ducting.ventilator_unexported` with Mechanical's Locate, unreadable group and duct records, metadata refusals |
| 4. Python | `contract/ducting_records.py`, `ducting_sections.py`, `composition.py` | `DuctingSection`, `requires` the ventilation section, `attaches = None`; builds every pair's ducts, then appends, in identifier order |
| 5. Conformance | `DuctingSection.conformance` | Every system's lists hold only their `duct_type`; per Ventilator the Rooms reached and both total lengths to 1 mm; per element its list, segment count, length to 1 mm, shape, sizes and insulation; no unreported element |
| 6. PHX round trip | `tests/python/test_ducting_phx_round_trip.py` | Base: two devices, ERV-1's two ducts and ERV-2's three, each with its device's id number and its millimetre sizes and insulation; shared: one device and DG-1's two ducts once; a Room with no Spaces gives no device and no ducts |
| 7. Documents | `context/CONTRACTS.md` ("ERV ducting", "Translation sections and artifacts"), `context/EXTENSIBILITY.md` ("Line groups", `ExportScan`), the packet CONTRACTS (sections 4 and 6), `docs/USER_DATA.md`, `docs/AGENT_GUIDE.md` and the shipped guide, `context/AGENT_INTERFACE.md`, `context/UBIQUITOUS_LANGUAGE.md` (Duct run), API 1.107 | |
| Host case | `cases.json` `M14e` | Owed to MS3 |

## Recorded at implementation

See the stage doc, "Recorded at implementation": the snapshot read moved to the layer with piping on it; the Python
helpers moved down; notes only once ducts exist; `ducting.run_missing` on Ventilators an exported Zone names; the
result fields; the conductor's Locate decision; the quantity bullet as inferred.

*For Ed:*

- The run quantity is built as P4-14 inferred: N elements, copies 2 to N suffixed `-k` and "(k of N)". METr will show
  N duct rows of quantity 1. A quantity is at most 10,000 and each element is written once per served Room, so a large
  quantity multiplies the HBJSON (the Sonnet review's unbounded-output finding, recorded rather than capped).
- `ducting.group_unlinked`'s Locate opens the group and selects that run's ducts (conductor decision on P4-14d's
  question); ACCEPTANCE's case row and P4-14f's host case now say so.

## Tests

- Ruby `tests/ducting_export_test.rb` (12): the case's two records in metres with the schedule's identifiers, round
  and rectangular segment values, the quantity copies, and the shared case's `ducting.ventilator_unexported` equal to
  the preflight's row (owns `tests/fixtures/ducting/extraction.json`, `shared_extraction.json` and
  `result_fields.json`); each of the five blocking codes refuses the section and appears in the preflight, blocking,
  with its run or no object, a Locate and the export's message; deleting ERV-2 with null and the Locate; the warnings
  (`ducting.run_missing`, `ducting.shared_definition`) equal to the preflight's rows by code, object and message; a bare
  type's 0.04; user_data on every copy's segment, a group's and a type's omitted, a reserved key blocking; a Model
  with no ducts; the privacy allowlist.
- Python `tests/python/test_ducting_sections.py` (11 functions, 15 cases): fresh ducts on each pair's system before attach, equal
  dictionaries; the base case reloaded on both Rooms with Ruby's lengths; the shared case's equal identifiers;
  conformance refusing a differing, missing, unreported or misdirected element, wrong lengths or Room count, and a
  differing reloaded segment; a forced failure on the second Room's build blocks and leaves both systems without
  ducts; determinism; bad records; user_data on every copy; the declared fields.
- PHX `tests/python/test_ducting_phx_round_trip.py`: three tests.
- Piping's tests are unchanged; `tests/thermal_bridge_export_test.rb`, `shading_export_test.rb`,
  `phase_one_export_test.rb`, `tests/python/test_model_sections.py` and `test_entry.py` name the new section, and
  every other extraction golden gains only the empty `ph_composer.ducting.export.ducting` section.

## Review

- Sonnet adversarial read before the gate: 8 findings, no high. Fixed: the runtime manifest refreshed; conformance
  raised `IndexError` for a segmentless reloaded element (now a `ValueError` naming it); conformance now reads each
  element's insulation too; the guide, CONTRACTS and the extraction comment overclaimed that a quantity of N exports
  "exactly" as N group copies (identifiers and names differ; lengths and element counts agree); the blocking tests
  now hold the export's message to a preflight row's, and the shared case's note to its row; the bare `Exception`
  from `add_segment` is documented as unreachable. Recorded for Ed: unbounded output from a large quantity (no cap
  added; the stage doc assigns none). Declined: reading back segment endpoints and `user_data` in conformance (the
  stage doc's list; honeybee-ph's reload equality already refuses Rooms that differ). The evidence finding is this
  file.
- Codex gpt-6-astra cycle 1 on `632e1f97`: 1 P3, this evidence file missing from the commit, fixed by the docs commit
  that adds it. No code change, so no second cycle.

## Gate

Code head `632e1f97` (the code commit, `a2716c5e` before the rebase, identical tree):

- `make ci` on Ruby 3.2.2, chained before the commit: "Ruby suite, 10 processes: 3614 runs, 51032 assertions, 0
  failures, 0 errors, 2 skips"; JS "pass 1226", "fail 0"; Python "506 passed, 1 skipped"; hostkit "48 runs, 268
  assertions, 0 failures"; "RBZ verified: 862 files, 9077333 bytes, 27896829 bytes installed".
- `make ci` on Ruby 2.7.2 on the same tree, with this file and the ledger edits uncommitted: "Ruby suite, 10 processes:
  3614 runs, 51032 assertions, 0 failures, 0 errors, 2 skips"; JS "pass 1226", "fail 0"; Python "506 passed, 1
  skipped"; hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 862 files, 9077327 bytes, 27896823 bytes
  installed" (6 bytes under 3.2.2's build).
- Installed size: 27,896,829 bytes, 37,323 over P4-14d's 27,859,506 against the 30 KB estimate (21 percent over,
  inside the 25 percent stop line); 103,171 under the 28,000,000 ceiling, 49,923 after P4-14f's 52 KB estimate, above
  the 40 KB line. `uv run tools/runtime/vendor.py --check`: "Runtime verified: 225 assets, 8 wheels, 23187990 bytes".
- Browser checks: `make ui-checks` on `632e1f97`: 40 of 40 scripts pass, exit 0, none skipped (no panel change).
- PHX: `uv run --group phx pytest tests/python` on `632e1f97`: 506 passed, 1 skipped (`test_map_borders.py`,
  `PH_COMPOSER_MAP_DATA` unset); `-k phx_round_trip`: 29 passed, 0 skipped (26 before, and this stage's three).
- Panel manifest: `make panel-manifest` "0 of 4 pages rewritten" (no panel file changed).
- Design System: not needed. No kit CSS, shared kit part or unit quantity changed; the re-sync owed from P4-13e was
  done before P4-14d (its evidence).
