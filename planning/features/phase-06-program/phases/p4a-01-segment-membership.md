# P4a-01: Building Segment membership

DATE: 2026-11-20
STATUS: Implemented on branch `feature/phase-06-program-p4a-01` (2026-11-20; authorized 2026-11-20 with P4a-02 to P4a-12). Host gate PG01 in [ACCEPTANCE](../ACCEPTANCE.md).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires Ed's go. Owns the record and operation changes that let a Zone be in no Building Segment,
with the last-Segment and default rules. No panel change beyond what keeps today's screens
working; the heading rows and dialog are P4a-02, export is P4a-03.

Entry check (C4a-14, Ed, 2026-11-20): measure the installed size on `main` and write it to
`installed_baseline_bytes` in `tools/runtime/vendor.py`, with a comment naming C4a-14. The ceiling and
the growth allowance do not change. This is the phase's first commit.

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

## Implementation notes (2026-11-20)

- A write upgrades a schema 2 Zone, with its stamps, to schema 3 only when the record changes; a
  metadata-only write keeps the stored version.
- "First remaining" is the first Segment in the final collection's order: id order for `remove`,
  the submitted order for `manage` (sent a null `default_segment_id`) and the dialog's draft.
- Until P4a-03 leaves them out, export preflight blocks a Zone in no Segment with `reference.invalid`.
- A copied Zone that names neither a Segment nor a Level has nothing to adopt. Adoption that brings
  only Levels into a Model without a default creates the default "Building" Segment.
- The Geometry view's Building-Segment cell lists No Building Segment last, so such a Zone reads
  correctly and can be moved back; P4a-02 replaces the column.
- Follow-ups: the native "Set Building-Segment…" menu offers only Segment names, so it cannot move a
  Zone out (P4a-02's selection bar does); the Spaces read groups no-Segment Zones under key `""`
  with a null name (P4a-02's heading rows).

## Done when

PG01 passes, `make ci` is green, and the API reference and guide are regenerated.
