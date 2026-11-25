# P4-13d evidence: piping export

DATE: 2026-11-24
Register row: [M13d](../ACCEPTANCE.md). Stage: [P4-13d](../phases/p4-13d-piping-export.md), under the parent index
[P4-13](../phases/p4-13-hot-water-piping.md).
Base: built on `feat/phase-07-mechanical-p4-13c` at `16d701ef`, rebased onto `main` at `4331c16c` after #578 merged
(identical tree).

Offline evidence only. No SketchUp process was started. The host case `M13d` (in
`planning/native-acceptance/cases.json`: export, reload the exact HBJSON and read both Rooms' tree and recirculation, a
broken branch refusing with its Locate, save, reopen and re-export) is owed to the MS3 sitting (D4-31). M13d stays
Open.

## The wheel (step 1)

Read in `src/ph_composer/vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl` on 2026-11-24, unchanged since P4-13's
table:

- `honeybee_phhvac/hot_water_piping.py`: `PhHvacPipeSegment(_geom, _diameter_mm=12.7, _insul_thickness_mm=12.7,
  _insul_conductivity=0.04, _insul_refl=True, _insul_quality=1, _daily_period=24, _water_temp_c=60.0, _material=2)`;
  `PhHvacPipeElement` keys segments by identifier and raises from `material_name` when they differ; `PhHvacPipeBranch`
  holds `pipe_element` and the list `fixtures` (`twigs` its alias); `PhHvacPipeTrunk` holds `pipe_element`,
  `multiplier` (1), `demand_recirculation` (False) and the list `branches`. Every class takes a `uuid4` identifier and
  its display name from it at construction, the inner `pipe_element` of a trunk or branch included. `to_dict` writes
  branches, fixtures and segments as maps keyed by identifier.
- `honeybee_phhvac/hot_water_system.py`: `add_distribution_piping` and `add_recirc_piping` key by identifier;
  `recirc_temp` and `recirc_hours` sum the recirculation elements in dictionary order, the hours through `int()`; an
  unset `number_tap_points` counts the trunks' fixtures. No attribute of any name for a calculation method (grep for
  `calc` and `method` finds only docstrings), so P4-06's `CALC_METHOD_ATTRIBUTE = "piping_calc_method"` still matches
  nothing and `mechanical.method_not_exported` stands; honeybee_ph#135 is open.
- PHX 1.59.4 (the `phx` group in `.venv`): `add_shw_piping_from_hb_rooms` reads each Room's Spaces' host Rooms, keys
  trunks and recirculation elements by identifier, and sets the recirculation temperature and hours from the set of
  the Rooms' values.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 2. Extraction | `features/piping/export.rb` (`ExportProjection`), `runs/extraction.rb` (`Runs::Extraction`), `codes.rb` | Section version 1, `requires` the Zones, Ventilator and hot water sections; facts from the snapshot's Piping group and pipe entries; one record per System with pipes, trunks with branches and twigs, recirculation elements, Ruby's recirculation temperature and hours; `piping.system_unexported` |
| 3. Preflight | `ph_composer.piping.export_preflight` | The run findings with `runs.locate` params, unreadable group and pipe records, `piping.system_unexported` with Mechanical's Locate, metadata problems |
| 4. Python | `contract/piping_records.py`, `piping_sections.py`, `composition.py` | `PipingSection`, `requires` the hot water section, `attaches = None`; builds everything for every pair's system, then adds, in identifier order |
| 5. Conformance | `PipingSection.conformance` | Trunks (identifier, multiplier, demand recirculation, length to 1 mm, branch count, twig counts), recirculation elements (identifier, length), Rooms reached and Ruby's temperature and hours (hours exact), and no unreported trunk or element per System |
| 6. PHX round trip | `tests/python/test_piping_phx_round_trip.py` | Two Rooms give the trunk, each branch and twig and each recirculation element once, multiplier 12, recirculation equal to Ruby's, 8 tap points, the trunk once in the WUFI XML; a Room with no Spaces gives no piping |
| 7. Documents | `context/CONTRACTS.md` ("Translation sections and artifacts"; the recirculation order under "Hot water piping"), the packet CONTRACTS (sections 4 and 6), `docs/USER_DATA.md`, `docs/AGENT_GUIDE.md` and the shipped guide, `context/AGENT_INTERFACE.md`, API 1.101 | |
| Host case | `cases.json` `M13d` | Owed to MS3 |

## Recorded at implementation

- **The order of the sums changed (P4-13c's read).** The canonical HBJSON is written with `sort_keys=True`
  (`assembly.py`), so a reloaded system holds recirculation elements and segments in identifier order, and float
  addition depends on order: of 2,000 random systems of two to four elements, 540 read differently before and after a
  sorted reload (scratch check on the pinned wheel). P4-13c summed in schedule order and run order. The Ruby read now
  sums runs by identifier and pipes by segment identifier, and Python adds every keyed collection in identifier order,
  so the translated system (whose digest the hot water section records), the reloaded one and Ruby agree to the bit.
  `tests/fixtures/piping/recirculation_vectors.json` (24 systems Ruby writes) holds it in
  `test_the_ruby_recirculation_read_equals_honeybee_phs_before_and_after_a_reload`, which also shows some of them read
  differently in run order. One consequence: P4-13c's "runs of 0.1, 0.2 and 0.7 m at 24 h give 24" now gives 23 for that
  test's identifiers, as honeybee-ph does after reload (`tests/piping_runs_test.rb`); the split 3.3 m and 1.7 m case
  still gives 23. Matched, not compensated.
- **Recirculation values in the record.** The stage doc's record shape has no recirculation values, but conformance
  compares with Ruby's; the record carries `recirculation_temperature_c` and `recirculation_hours` from
  `Runs::Recirculation`.
- **No random identifier reaches the HBJSON.** A trunk's or branch's inner `pipe_element` takes the run's identifier and
  name; a segment's display name is its identifier, honeybee-ph's own default.
- **A bare Pipe Type with no conductivity** exports honeybee-ph's 0.04 W/(m K), never a null.
- **`requires` adds the Zones and hot water sections.** Zones for which groups a Zone holds; hot water so it reads the
  Systems first and names their `export.metadata_omitted`.
- **`shared` from the snapshot.** The snapshot keeps no Group definition, so a pipe is shared when a ComponentInstance
  holds it or its Edge is reached at two paths; a pasted Piping group gives the same notes as the live preflight
  (`test_a_pasted_piping_group_exports_both_placements_under_distinct_identifiers_noted_as_shared`).
- **An unexported System still writes its record**, with no hot water object to add to; Python gives an empty object
  and no rows. A Model with no pipes reads no Pipe Type.
- **A record id is its System's id.** `id` and `system_id` are equal.

## Tests

- Ruby `tests/piping_export_test.rb`: the case's record with the schedule's identifiers, segment values and
  recirculation (owns `tests/fixtures/piping/extraction.json` and `result_fields.json`); each of the seven blocking
  codes refuses the section and appears in the preflight, blocking, with its run or no object and a Locate; the
  warnings (`piping.parent_ambiguous`, `piping.trunk_without_branches`) equal the preflight's rows by code, object
  and message; `piping.system_unexported`; user_data on a segment, a group's and a type's omitted, a reserved key
  blocking; a pasted group; a bare type's conductivity; the recirculation vectors; the privacy allowlist.
- Python `tests/python/test_piping_sections.py`: fresh pipes on each pair's system before attach, equal dictionaries;
  the reload on both Rooms with equal hot water digests and Ruby's recirculation exactly; blank tap points read 6;
  conformance refusing a differing, missing or unreported trunk or element, a wrong Room count and another System's
  rows; a forced failure on the second Room's build blocks and leaves both systems without pipes; bad records; a
  segment's user_data; the vectors; the declared fields.
- PHX `tests/python/test_piping_phx_round_trip.py`: two tests.
- Every other extraction golden gains only the empty `ph_composer.piping.export.piping` section.

## Review

- Sonnet adversarial read before the gate: 14 findings. Fixed: the `shared` check scanned every component path per
  pipe (now a path lookup); the forced-failure test failed on the first build, so it could not see a half-added
  system (now the second Room's build fails); untested conformance branches, the empty-object case, warnings against
  the preflight's rows, blocking rows' objects and a twice-translated determinism check gained tests; an Edge outside
  every Piping group with a malformed record blocked the export but not the preflight (no longer read); a Model with
  no pipes read every Pipe Type (no longer); conformance accepted another System's trunk (now keyed by System);
  `OverflowError` escaped `translate`; `user_data` was shallow-copied across Rooms; a finding named its run twice; the
  preflight walked the Model three times (now once, `Scan.call(walked:)`). Declined: a `target_kind` on the Pipe Type
  metadata check (the code passes none); an unreadable Piping group nested in another labelled a pipe (writes refuse
  nesting); unpaged `edge_paths` in a finding's Locate (the thermal-bridge precedent, and `runs.members` pages a run).
  It also noted, pre-existing and outside this stage, that two Python processes give canonical HBJSON differing in
  `team` identifiers, `bldg_segments` and list order, so a whole-file byte comparison on re-export cannot hold; the
  hot water systems and piping are identical (M13d's "same HBJSON" compares those).
- Codex gpt-6-astra cycle 1 on `ec10578e`: 1 P1, 1 P2, both fixed in `8304dac6`: claimed extension payloads on pipes
  and Piping groups were not captured for their claimant (the reads now pass the occurrence path; test added, which
  fails without it), and a recirculation mean a float's width above 100 C refused the export (now any finite number;
  the vectors gain such a System). Cycle 2 on `8304dac6`: no findings, approve.

## Gate

Final head `8304dac6`, after both review cycles:

- `make ci` on Ruby 3.2.2 and on 2.7.2: "Ruby suite, 10 processes: 3525 runs, 50060 assertions, 0 failures, 0 errors,
  1 skips" each; JS 1214 pass, 0 fail; Python 486 passed, 1 skipped; hostkit 48 runs; "RBZ verified: 817 files,
  8992321 bytes, 27662666 bytes installed".
- Installed size: 27,662,666 bytes, 44,117 over P4-13c's 27,618,549 against the 35 KB estimate (23 percent over,
  inside the 25 percent stop line); 337,334 under the 28,000,000 ceiling.
- Browser checks: `make ui-checks` on `8304dac6`: 39 of 39 scripts pass, exit 0, none skipped (no panel change).
- PHX: `uv run --group phx pytest tests/python` on `8304dac6`: 486 passed, 1 skipped (`test_map_borders.py`,
  `PH_COMPOSER_MAP_DATA` unset); `-k phx_round_trip`: 26 passed, 0 skipped (24 before, and this stage's two).
- Design System: not needed; no kit CSS, shared kit part or unit quantity changed.
