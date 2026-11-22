# P4-01: equipment contracts, lint and the Pyodide seam

DATE: 2026-10-21
STATUS: Scoped. Corrected 2026-11-22 after Phase 6 Programs: the Phase 3b gate is met, an entry check is added, and D4-21, D4-22 and D4-25 bear on steps 1 and 2. See [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires Ed's go, and D4-21 and D4-22 answered, since they decide what step 1 confirms and
the names every later stage uses. Phase 3b's P3b-01, which edits the same `Makefile` line, merged
on 2026-10-26. Owns the confirmation of [CONTRACTS](../CONTRACTS.md) against the code by test, the two seam
edits the first mechanical section needs, the citation lint for this packet's ids, and the
architecture review of the corrected bindings. No feature code, no screen.

Behavior owner: none; this stage settles names and seams. Names: CONTRACTS sections 1 to 7.

Paths are relative to `src/ph_composer/`.

## Steps

0. **Entry check.** Record the pins this phase is planned on (honeybee-ph 1.33.68; PHX 1.59.4 in
   the `phx` test group) and re-read against that wheel the honeybee-ph fields P4-02 to P4-08 use,
   correcting the PRDs where 1.33.65 differed. Measure the installed size on `main` and record it
   beside the footprint keys: the 28,000,000 byte ceiling binds before the growth allowance does
   (F37).
1. **Contract questions by test.** Answer CONTRACTS section 7 and record each answer in a new
   section 8 with its evidence:
   1. A second feature's `EntityStore` dictionary on a Zone Group, through a test-only feature
      built like `tests/support/zone_child_fixture.rb` but storing on the Zone Group itself:
      `Dictionaries.register` admits it, the export attribute guard passes, Zones' reads and
      `entity_record(..., target_kind:)` ignore it, and a Zone copy carries it. If D4-21 is
      answered as recommended this question goes: Serves is then a payload staged through
      `ph_composer.zones.stage_extension`, and the test instead stages a `one` and a `many`
      reference on a Zone record and reads both back after a Zone copy.
   2. One honeybee-ph object per (item, Zone) pair sharing an identifier: a Python test building
      two Rooms with equal `PhVentilationSystem` and `Ventilator` identifiers, `to_dict` and
      `from_dict`, and the reloaded Rooms' units equal (D4-01). Record what PHX's key dedup does
      as a read, not a run; its run is metr-export's, unless D4-25 is answered as recommended,
      in which case it is a round trip in the `phx` test group here.
   3. A Colour-by projection with `entity_kind: "zone"` keyed by Zone id from a read, following
      `features/zones/colour_modes.rb` `entries`.
   4. `honeybee_phhvac` imports in the installed Pyodide runtime after `honeybee_ph`, and
      `Room.properties.ph_hvac` exists: a runtime probe through `tools/runtime/`'s existing check
      shape.
2. **The stack seam (A1).** Add `honeybee_phhvac` to `stack.PACKAGES`; `tests/python/test_imports.py`
   iterates the set and keeps every translation module importable without the stack.
3. **Lint (A4).** Extend `PLANNING_IDS` so a planted `P4-01`, `P4-08b`, `M01` and `M16` fail
   `lint-citations` in `src/`; `D4-01` already fails.
4. **Corrections.** Fold each answer into CONTRACTS sections 2 to 6 where a name or shape changes;
   where the PRD and the bindings disagree, the PRD wins and this stage records the correction.
5. **Review.** The architecture review on the corrected bindings, recorded in
   `../evidence/p4-01-contracts.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `tests/support/zone_child_fixture.rb` | Pattern for the test-only second child; this stage's fixture stores on the Zone Group |
| `python/ph_composer_translation/stack.py`, `tests/python/test_imports.py` | The one-line seam edit and its guard |
| `tests/python/test_room_attachment.py` | Pattern for the two-Rooms reload test |
| `tests/python/test_program_phx_round_trip.py` | Pattern for a PHX round trip, if D4-25 brings one here |
| `features/programs/assignments.rb`, `features/zones/extension_staging.rb` | The shipped per-Zone assignment, if D4-21 is answered as recommended |
| `Makefile` (`PLANNING_IDS`) | The lint pattern |

## Tests (write first)

1. The Zone-Group dictionary fixture: register, guard, Zones' reads untouched, copy carries it.
2. The two-Rooms shared-identifier reload.
3. The Zone-keyed projection shape.
4. `lint-citations` fails on planted `P4-01`, `P4-08b`, `M01` and `M16`.
5. `test_imports.py` still passes with `honeybee_phhvac` in `PACKAGES`.

## Host gate

The runtime probe in step 1.4 against the installed build: `honeybee_phhvac` loads through
`stack.load` and a Room gains `ph_hvac`. Record it with `acceptance_case.py begin` and `finish`.

## Out of scope

Any feature registration (P4-02). The Systems pane (P4-05).

## Done when

- M01 has evidence in `../evidence/p4-01-contracts.md`.
- CONTRACTS section 8 exists and sections 2 to 6 carry no row the tests contradicted.
- `make ci` passes on both Rubies.
