# P4a-07: Program, Schedule and Equipment Set records

DATE: 2026-11-15
STATUS: Outline. Rewritten after the Programs tab review (gate G1). Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires G1. Adds the three catalog kinds, the built-in residential default and their library kinds. Behavior: [Phase 4a PRD](../PRD.md), "Programs tab" (to be written); names: [CONTRACTS](../CONTRACTS.md) section 5.

## Outline

1. Kinds `programs.program` (`pgm_`), `programs.schedule` (`sch_`), `programs.equipment_set` (`eqs_`, devices as parts), each with operations, reads, `user_data` and the duplicate rules.
2. The residential default: a frozen definition, seeded into each Model as an ordinary record on first need, with Reset to PH-Composer default and the `default_program_id` Model setting (CONTRACTS section 5).
3. Library kinds so library files and Connections supply them; choosing one copies it and its Schedules (Q4a-19, Q4a-22).
4. The PH-form schedule writes a honeybee ruleset; operating periods wait on F4a-13 (Q4a-08).

## Settle at G1

Answered at the review: Q4a-23 (the default is a seeded, editable record with Reset), Q4a-25 (complete library Programs; Phius-rule loads per Dwelling), Q4a-33 (the ventilation Schedule type). Still open: Q4a-22 (copy on choice) and the exact field lists.

## Host gate

PG07: a panel-closed script authors each kind; Undo/Redo; reopen.
