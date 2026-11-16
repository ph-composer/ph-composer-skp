# P4-01: equipment contracts, lint and the Pyodide seam

DATE: 2026-10-21
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires Ed's go and Phase 3b's P3b-01 merged, because both edit `Makefile`'s `PLANNING_IDS`.
Owns the confirmation of [CONTRACTS](../CONTRACTS.md) against the code by test, the two seam
edits the first mechanical section needs, the citation lint for this packet's ids, and the
architecture review of the corrected bindings. No feature code, no screen.

Behavior owner: none; this stage settles names and seams. Names: CONTRACTS sections 1 to 7.

Paths are relative to `src/ph_composer/`.

## Steps

1. **Contract questions by test.** Answer CONTRACTS section 7 and record each answer in a new
   section 8 with its evidence:
   1. A second feature's `EntityStore` dictionary on a Zone Group, through a test-only feature
      built like `tests/support/zone_child_fixture.rb` but storing on the Zone Group itself:
      `Dictionaries.register` admits it, the export attribute guard passes, Zones' reads and
      `entity_record(..., target_kind:)` ignore it, and a Zone copy carries it.
   2. One honeybee-ph object per (item, Zone) pair sharing an identifier: a Python test building
      two Rooms with equal `PhVentilationSystem` and `Ventilator` identifiers, `to_dict` and
      `from_dict`, and the reloaded Rooms' units equal (D4-01). Record what PHX's key dedup does
      as a read, not a run; its run is metr-export's.
   3. A Colour-by projection with `entity_kind: "zone"` keyed by Zone id from a read, following
      `features/zones/colour_modes.rb` `entries`.
   4. `honeybee_phhvac` imports in the installed Pyodide runtime after `honeybee_ph`, and
      `Room.properties.ph_hvac` exists: a runtime probe through `tools/runtime/`'s existing check
      shape.
2. **The stack seam (A1).** Add `honeybee_phhvac` to `stack.PACKAGES`; `tests/python/test_imports.py`
   iterates the set and keeps every translation module importable without the stack.
3. **Lint (A4).** Extend `PLANNING_IDS` so a planted `P4-01` and `M01` fail `lint-citations` in
   `src/`; `D4-01` already fails. Land after P3b-01's edit to the same line.
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
| `Makefile` (`PLANNING_IDS`), Phase 3b's P3b-01 edit | The lint pattern |

## Tests (write first)

1. The Zone-Group dictionary fixture: register, guard, Zones' reads untouched, copy carries it.
2. The two-Rooms shared-identifier reload.
3. The Zone-keyed projection shape.
4. `lint-citations` fails on planted `P4-01` and `M01`.
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
