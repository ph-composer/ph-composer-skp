# P4a-01: Building Segment membership

DATE: 2026-11-15
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires Ed's go. Owns the record and operation changes that let a Zone be in no Building Segment,
with the last-Segment and default rules. No panel change beyond what keeps today's screens
working; the heading rows and dialog are P4a-02, export is P4a-03.

Behavior: [Building Segments PRD](../building-segments/PRD.md), "Membership". Names:
[CONTRACTS](../CONTRACTS.md) section 1. Paths are relative to `src/ph_composer/`.

## Steps

1. **Zone schema 3.** `features/zones/` Zone kind: `building_segment_id` nullable; schema 2 reads
   as before. Read rows and snapshot shapes (`declarations/zone.rb`) allow null.
2. **Management rules.** `options/operations.rb` `manage` and `replacements`: a used Building
   Segment may map to null; a final collection with no Segment refuses
   `zone.option_last_segment` (declare in `codes.rb`); deleting the default sets it to the
   destination or the first remaining Segment. Levels unchanged.
3. **Commands.** `options/commands.rb` `remove` accepts a null destination for Segments.
4. **Assigning.** Extend `ph_composer.zones.update_field` (`declarations/selection.rb`,
   `zone/selection.rb`) so `field: building_segment` accepts null, with its guarded
   `expected_values` and one Undo step. No new action. `manage` and `remove` results add
   `removed_extensions` (CONTRACTS section 1).
5. **Make Zone and Restore Zone.** New Zones take the default; Restore recovers null as null; the
   membership stamp and `choice_evidence` carry null.
6. **Colour-by.** `colour_modes.rb` "by Building Segment" gives no-Segment Zones a neutral swatch
   labelled "No Building Segment".
7. **Contract and docs.** API minor bump with change note; `context/CONTRACTS.md` "Managed Zone
   field options" and `context/UBIQUITOUS_LANGUAGE.md` (at most one Segment, No Building Segment,
   Default Building Segment); `docs/AGENT_GUIDE.md` and the shipped guide; `make fixtures`.

## Source

| File | Disposition |
| --- | --- |
| `features/zones/options/definitions.rb`, `operations.rb`, `commands.rb`, `adoption.rb`, `registration.rb` | Change. `Options.resolve` calls `engine.find` on nil; `Adoption.needs_adoption?` rescues to true, so a no-Segment Zone would read as needing adoption; the `schema_version == 2` branches in `operations.rb` |
| `features/zones/zone/schema.rb`, `zone/operations.rb`, `zone/selection.rb` | Change: the `[1, 2].include?` version check, `evidence_matches?`, `stamp?` requiring a String, the `== 2` branch in `operations.rb` |
| `features/zones/declarations/zone.rb`, `selection.rb` | Change shapes |
| `features/zones/colour_modes.rb` | Change |
| `html/features/zones/option_dialog.js` | Keep working until P4a-02 removes it; offer No Building Segment as a destination |

## Tests (write first)

1. Schema 3 round trip; schema 2 fixture reads; an unknown version refuses.
2. `update_field` to a null Segment and back; stale expected value refuses and writes nothing.
3. Management: last Segment refuses; used Segment to null; default moves to destination, else first.
4. Make Zone joins the default; Restore keeps null.
5. Agent walkthrough with the panel closed: create a second Segment, move a Zone out, delete a
   Segment with its Zones moved to none, read back.

## Host gate

PG01 in [ACCEPTANCE](../ACCEPTANCE.md): delete, move, Undo, Redo, save and fresh-process reopen in
a real Model.

## Done when

PG01 passes, `make ci` is green, and the API reference and guide are regenerated.
