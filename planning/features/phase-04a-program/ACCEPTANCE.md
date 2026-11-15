# Phase 4a acceptance register

DATE: 2026-11-15
STATUS: Scoped. PG01 to PG06 are ready; PG07 to PG12 are rewritten after the Programs tab review (G1).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The PRDs ([Phase 4a](PRD.md), [Building Segments](building-segments/PRD.md)) supply the behavior;
this register supplies one closure gate per stage. Record a source-controlled evidence summary per
stage under `evidence/` (commit, build, fixtures, checks, exact host versions, remaining limits).
SKP files and captures stay in `_private/`.

Ids use the prefix PG; the prefixes in [`native-acceptance/cases.json`](../../native-acceptance/cases.json)
are taken (read 2026-11-15). Record each host run with `acceptance_case.py begin` and `finish` so its
ledger row is a Pass.

| ID | Owner, stage | Required evidence | State |
| --- | --- | --- | --- |
| PG01 | Zones, P4a-01 | Zone schema 3 round trip; schema 2 reads unchanged; a Zone set to no Segment and back, each one Undo step; deleting the last Segment refuses `zone.option_last_segment` and writes nothing; deleting a used Segment moves its Zones to the named Segment or to none; deleting the default moves the default as the PRD says; Make Zone joins the default; options operations and `set_building_segment` through the agent API with the panel closed. Host: delete, move, Undo, Redo, save and fresh reopen | Not started |
| PG02 | Zones, Spaces, UI kit, P4a-02 | Heading rows in Geometry and Spaces (two lines, tags, sums, Actions cell); No Building Segment group; New Building Segment names and opens in place; Move from both selection bars; the settings dialog saves General and every registered section as one Undo step and refuses a section without a participant at registration; the Geometry column and Manage dialog are gone. UI polish review recorded; Ed at the mouse | Not started |
| PG03 | Zones, export, P4a-03 | Export refuses with no Zone in a Segment; a Zone in no Segment is absent from the HBJSON with its Spaces and Edges, and the finding counts them; an empty Segment is absent with its info line; a shared Face exports its Attached zone, or refuses naming the Face; the move-out offer creates or reuses the Attached zone in one Undo step. Round trip: WUFI XML and METr JSON from the pinned PHX, the Attached zone read back, and the per-Room duplicate either disproved or recorded with its effect | Not started |
| PG04 | Certification, P4a-04 | The section's values round trip, copy with the Segment and go with it on delete; export writes each to `BldgSegment.phius_certification` and PHX reads them back into the WUFI XML | Not started |
| PG05 | Spaces, P4a-05 | A Zone with no rates reads By Program and exports `None`; one entered rate makes every Space in the Zone export its rates with 0 for blanks; the notice on the first entry; From Program clears the Zone in one Undo step; Zone sums; the No Spaces warning in preflight; the agent reads per the C4a-6 answer. Ed at the mouse | Not started |
| PG06 | Programs, export, P4a-06 | The feature installs with its dependencies; the Airtightness section round trips; an entered n50 and an entered q50 each read back from the WUFI XML and METr JSON within 0.01; with no test result the Program's Infiltration (or PHX's default) exports; wind exposure reaches `BldgSegment` | Not started |
| PG07 | Programs, P4a-07 | Written after G1 | Not started |
| PG08 | Programs, P4a-08 | Written after G1 | Not started |
| PG09 | Programs, UI kit, P4a-09 | Written after G1 | Not started |
| PG10 | Programs, export, P4a-10 | Written after G1; includes a round trip of the five prototype journeys | Not started |
| PG11 | Programs, UI kit, P4a-11 | Written after G1 | Not started |
| PG12 | Integration, P4a-12 | Both offline Ruby gates, coverage, browser and runtime checks; packaged footprint against the current baseline; the integrated run from a fresh process; context, docs and glossary folded | Not started |

## Synthetic reference models

Public fixtures stay synthetic.

1. **House**: the prototype's journey 1, five Zones in one Segment with Single dwelling on, Spaces
   in each Zone (Living-Kitchen split in two, Hall and stair split in two).
2. **Apartments and common areas**: journey 3, six apartment Zones of four Spaces each, two
   corridors, lobby, stair, office, fitness room, and a Bike shed with no Spaces, used out of every
   Segment for P4a-03.
3. **Two Segments**: the House plus an ADU Segment of two Zones, both single dwellings, sharing one
   wall, used for P4a-01 to P4a-03.
