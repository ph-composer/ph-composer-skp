# P4a-09: The Zones / Programs view

DATE: 2026-11-15
STATUS: Implemented on branch `feature/phase-06-program-p4a-09` (2026-11-20); PG09's host rows owed. Authorized 2026-11-20 with the rest of Phase 4a ([STATUS](../STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires P4a-08 (assignments, derivations, findings), P4a-05 (detailed airflows feed the
Ventilation column) and P4a-07b (library Programs for the Program select). Owns the third Zone view:
its columns, cells, Segment heading cells, selection bar, and the Dwelling and lock bubbles. Writes
only through P4a-08's actions and the library coordinator. Load the UI polish and architecture
review skills first.

Behavior: [Phase 4a PRD](../PRD.md), "Zones / Programs view", "Single dwelling", "Dwellings".
Prototype: `j1-start`, `j1-bedrooms`, `j1-unlocked`, `j1-lock-bubble`, `j1-adu`, `j2-checked`,
`j2-dwellings`, `j3-common-areas` (and `-420`), `j4-start`, `j4-assigned` in
[mockups](../mockups/README.md). Paths are relative to `src/ph_composer/`.

## Steps

1. **Register the view** with the Zone views host (`table_views.register("ph_composer.zones", {...})`,
   `context/EXTENSIBILITY.md`, "Zone views"), id `ph_composer.programs.zones`, label "Programs",
   after Spaces, listed while the `programs.zones` snapshot section publishes. Its state consumes
   that read each snapshot.
2. **Columns and cells** (`columns`, `value`, `cell`, `widths`): Program, Dwelling, Bedrooms,
   Occupants, Equipment Set, Floor area, iCFA, People, Lighting, Ventilation, with each per-area
   basis named in its header tooltip (Q4a-17). Cells:
   - Program: a select of the Model's Programs, then each added library source's Programs under
     "copies into this file"; an unassigned Zone shows its effective Program in italics. Choosing a
     library Program calls the coordinator's use with an assignment (copy with its Schedules, then
     `programs.assign_program`), one native transaction, with a notice (Q4a-22).
   - Dwelling: a chip, or "None"; either opens the Dwelling bubble.
   - Bedrooms and Occupants: in-cell inputs on a Zone in a Dwelling; "in <Dwelling>" when the
     Dwelling holds its own count; occupants left empty show the Phius rule.
   - Equipment Set: a select on a Dwelling's Zones (shared by the Dwelling) and on Zones that are
     not dwellings (their own, Q4a-21); a dash with its reason in a non-residential Segment.
   - People, Lighting, Ventilation: the derived values; Ventilation's tooltip names its source
     (the Program, or the Spaces' detailed airflows: supply, extract, the larger shown); an amber
     "?" names a missing Program value.
3. **Segment heading cells** through P4a-02's `segmentSums` hook: the sums, and under effective
   Single dwelling the house row's inputs (bedrooms with an amber "?" until entered, occupants,
   Equipment Set) writing to the Segment's Dwelling.
4. **Locked rows** under Single dwelling: muted cells that open the lock bubble ("<Segment> is a
   single dwelling", why, Open settings), which opens the Segment's settings dialog through Zones'
   panel entry from P4a-02. Locked Zones cannot be checked.
5. **Dwelling bubble**: "Dwelling of <Zone>" select (Dwellings, New dwelling, Not a dwelling),
   applied at once; then Units (editable), Zones, Bedrooms, Occupants with an (i) for the Phius
   rule, iCFA. No footnote.
6. **Selection bar** (`check`, `selectionBar` hooks): Building Segment (the host's), Program,
   Dwelling (one shared, one each, not a dwelling, add to an existing one), Equipment Set; each
   applies to every checked Zone as one Undo step, named in a notice.
7. **Findings** as row flags from `programs.zones` (P4a-08 step 7), on the row they belong to.
8. **Units** through the unit preferences; IP shows W, cfm, ft².
9. **Docs.** `docs/PRODUCT.md` gains the Zones / Programs steps; the UI polish patterns reference
   gains the lock bubble and the Dwelling bubble.

## Tests (write first)

1. Browser checks for journeys 1 to 4 of the prototype: locked house with bedrooms, unlocking from
   settings, dwellings one each, common-area library Programs copied on choice, a non-residential
   school with flags and assignments; the Dwelling and lock bubbles; the selection bar; IP and SI.
2. Every cell edit and bar action is one registered action and one Undo step; a stale value
   refuses and the cell returns to the Model's value.
3. Choosing a library Program copies it once; a second Zone reuses the local copy.
4. Narrow widths (420 px): the table scrolls, the selection bar wraps.

## Host gate

PG09: panel gestures with Ed at the mouse on the house and apartment references; UI polish review
recorded.

## Done when

PG09 passes.

## Implementation decisions (2026-11-20)

Recorded by the stage; [STATUS](../STATUS.md) holds the ledger row.

- **A library Program on Zones is Programs' own action.** The coordinator's assignment callback cannot write a Zone:
  `ph_composer.library.copy` names no Zones participant (`operation.participant_missing`), and the library does not
  depend on Programs. `ph_composer.programs.assign_library_program` joins the copy through
  `ph_composer.library.copy_into_proposal` (the Windows Installs save's route) and then assigns as `assign_program`
  does: one Undo step, refused together. Programs now requires `ph_composer.library`. The library Program kind's
  own assignment stays the Model's default.
- **The house row writes through Zones' settings Save** (`ph_composer.zones.save_segment_settings` with only the
  `ph_composer.programs.segment` payload), as the Occupancy section does, since the house's values live on the
  Segment payload (P4a-08).
- **The read grew, Ruby still derives.** `programs.zones` adds every Dwelling, each Zone's `dwelling_units` and
  `missing` (the reason behind each amber "?", `missing_values.rb`) and each Segment's heading `sums`, with
  `incomplete` for a load some Zone lacks; API 1.82.
- **Three generic host hooks**, each in `context/EXTENSIBILITY.md`: a view's `segmentCell` (the house row's inputs),
  a heading tag's `open` (the Single dwelling tag opens the lock bubble) and the Zones tab's `segmentSettings`
  intent (the lock bubble's Open settings).
- **Library Programs load once the view shows**: each source's `programs` and `schedules` catalogs, through the
  library's own stores; a row whose local copy needs review is refused with the reason, for P4a-11's sidebar.
- **Locked counts read a dash**, as the prototype's, in the kit's locked pill; "in <Dwelling>" is for a Dwelling
  that holds its own count.
