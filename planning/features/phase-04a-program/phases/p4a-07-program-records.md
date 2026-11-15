# P4a-07: Program, Schedule and Equipment Set records

DATE: 2026-11-15
STATUS: Outline. Rewritten after the Programs tab review (gate G1). Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires G1. Adds the three catalog kinds, the built-in residential default and their library kinds. Behavior: [Phase 4a PRD](../PRD.md), "Programs tab" (to be written); names: [CONTRACTS](../CONTRACTS.md) section 5.

## Outline

1. Kinds `programs.program` (`pgm_`), `programs.schedule` (`sch_`), `programs.equipment_set` (`eqs_`, devices as parts), each with operations, reads, `user_data` and the duplicate rules.
2. The residential default as a frozen definition seeded from the pinned honeybee-ph rules and schedules (F4a-20).
3. Library kinds so library files and Connections supply them; choosing one copies it and its Schedules (Q4a-19, Q4a-22).
4. The PH-form schedule writes a honeybee ruleset; operating periods wait on F4a-13 (Q4a-08).

## Settle at G1

Field lists (eight load sections, Schedule types), Q4a-22, Q4a-23, Q4a-25.

## Host gate

PG07: a panel-closed script authors each kind; Undo/Redo; reopen.
