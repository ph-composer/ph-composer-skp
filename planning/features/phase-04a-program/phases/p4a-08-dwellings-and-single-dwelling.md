# P4a-08: Dwellings, Zone assignments and Single dwelling

DATE: 2026-11-15
STATUS: Scoped (rewritten after the Programs tab review). Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-07. Owns Dwellings, the per-Zone assignment extension, the derivations in Ruby,
Single dwelling per Building Segment and the Segment settings' Occupancy section. No Zones /
Programs view (P4a-09) and no export (P4a-10).

Behavior: [Phase 4a PRD](../PRD.md), "Single dwelling" and "Dwellings". Names:
[CONTRACTS](../CONTRACTS.md) sections 2, 5 and 6. Answers: Q4a-11, Q4a-21, Q4a-24, Q4a-26 (as
revised by BS-3), Q4a-27, C4a-7. Paths are relative to `src/ph_composer/`.

## Steps

1. **Dwelling kind** `ph_composer.programs.dwelling` (`dwl_`): `name`, `units` (integer, at least
   1), `bedrooms` and `occupants` (number or null; set only by Single dwelling, Q4a-24),
   `equipment_set_id` (reference or null, Q4a-21). Operations as P4a-07's kinds.
2. **Zones' extension participant.** `ph_composer.zones.stage_extension`: Zones stages a named
   namespace's payload on Zone or Segment records after that namespace's installed validator
   accepts it. Programs requires Zones, so its actions may call it (CONTRACTS section 2). P4a-02's
   Save uses the same staging code.
3. **Zone assignment extension** `ph_composer.programs.zone_assignment`: `program_id`,
   `dwelling_id`, `equipment_set_id` (references or null), `bedrooms`, `occupants` (number or
   null). Absent reads as unassigned. Programs' actions, each one Undo step:
   - `programs.assign_program`: Zones, a Program or null (the default);
   - `programs.assign_dwelling`: Zones and one of shared (one new Dwelling), each (one per Zone),
     none, or an existing Dwelling; a Dwelling left with no Zones is deleted in the same step;
   - `programs.set_counts`: one Zone's bedrooms and occupants (per Zone, auto-totalled, Q4a-24);
   - `programs.assign_equipment_set`: a Dwelling, or Zones that are not dwellings (Q4a-21).
   Each refuses a Dwelling whose Zones would span two Segments (C4a-3).
4. **Occupancy extension** `ph_composer.programs.segment` on Segments: `single_dwelling` (default
   true when absent, C4a-7), `dwelling_id`, `default_program_id`. **Effective Single dwelling** is
   `single_dwelling` on a residential Segment (Certification's category).
5. **Switching Single dwelling** (Occupancy section, through Zones' Save). Programs registers a
   transition contributor on Zones' settings save, so the switch's side effects land in the same
   Undo step:
   - **on**: create the Segment's Dwelling, named for the Segment, or reuse its one Dwelling; sum
     the Zones' bedrooms into it; clear the Zones' Program, Dwelling, counts and Equipment Set;
     set the certification draft's category to residential;
   - **off**: write each Zone's Dwelling as the Segment's Dwelling, keeping its counts on the
     Dwelling and the default Program.
   `programs.single_dwelling_preview(segment)` lists what switching on replaces, for the
   confirmation (PRD, Single dwelling, item 4).
6. **Derivations** (`features/programs/derive/`), pure Ruby over reads: effective Program,
   Dwelling, Dwelling bedrooms and occupants (own value, else the Zones' sum; occupants with
   neither by the Phius rule, bedrooms + units), Zone people, Zone lighting (the Phius interior
   lighting rule per Dwelling, honeybee-ph `phius_residential.lighting_interior`), Zone
   ventilation (By Program from the four terms; detailed from Spaces' sums, read through Spaces'
   public query), Segment set points with their disagreement finding.
7. **Reads and findings.** `programs.zones`: one row per Zone with its assignment, effective values
   and findings; `programs.dwellings`. Findings: a Dwelling across Segments, Single dwelling on a
   non-residential Segment (it has no effect), a residential Segment with no Dwelling, a
   non-residential Segment with Dwellings, a Program with equipment watts in a residential Segment.
8. **Occupancy section** of the Segment settings: Single dwelling (residential only, with the
   reason when disabled), default Program for its Zones, and under Single dwelling the Dwelling's
   bedrooms, occupants and Equipment Set; dwelling units read only.
9. **Contract and docs.** API minor bump; agent guide recipe; glossary (Dwelling, Single dwelling).

## Tests (write first)

1. Assignment round trip; copying a Zone copies its assignment and keeps its Dwelling (C4a-2).
2. Each assign action, one Undo step; an emptied Dwelling is deleted; a Dwelling across Segments
   refuses.
3. Single dwelling on: Dwelling created, bedrooms summed, Zones cleared, category residential, one
   Undo step; off: Zones keep the Dwelling and the default Program.
4. Effective Single dwelling is off on a non-residential Segment whatever its payload says; an
   absent payload reads as on (C4a-7).
5. Derivations against hand values on the house and apartment references: occupants by the Phius
   rule, people, interior lighting, both ventilation sources.
6. Findings on their cases, both on Programs' actions and after a generic metadata write.

## Host gate

PG08: Single dwelling on and off, Undo/Redo, copying a Zone, a Dwelling across Segments refused.

## Done when

PG08 passes.
