# P4a-03: Segment export rules and Attached zones

DATE: 2026-11-15
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-02 (the move-out offer starts from its selection bar). Owns the export minimum, leaving out Zones in no Segment with everything that
hangs on them, empty Segments, the Attached zone rule for shared Faces, the move-out offer, and a
PHX round trip of `PhAdditionalZone`.

Behavior: [Building Segments PRD](../building-segments/PRD.md), "Export rules" and "How
PhAdditionalZone reaches PHX". Paths are relative to `src/ph_composer/`.

## Steps

1. **Preflight.** `features/zones/export.rb`: refuse when no Zone is in a Segment; info finding
   naming Zones left out with counts of their Faces, Spaces and Edges; info line per empty Segment.
2. **Leave out.** Zones' Room section skips no-Segment Zones; `features/spaces/export.rb` and
   `features/thermal_bridges/export.rb` skip what belongs to them; the Python sections
   (`model_sections.py`, `space_sections.py`, `thermal_bridge_sections.py`) never see them.
3. **Shared Faces.** `features/zones/faces/export.rb`: a Surface Face whose partner Zone is left
   out refuses, naming the Face and pointing to the offer. A Face holds an Attached zone only on the
   Attached zone boundary (`faces/schema.rb`), so nothing is substituted at export.
4. **Move-out offer.** When `update_field` sets a null Segment on a Zone with Surface Faces shared
   with Segment Zones, the panel offers one confirmation that reclassifies those Faces (on both
   sides) from Surface to Attached zone, leaving their pairs (`leave_pair!`), and creates or reuses
   an Attached zone named for the Zone: one Undo step through Zones' existing Face and Attached zone
   actions. Moving the Zone back leaves them as Attached zone with a notice to re-run Solve (C4a-8).
5. **PHX test group.** Add an optional `phx` dependency group in `pyproject.toml`, pinned to a
   released PHX; tests that need it skip when it is absent.
6. **PHX round trip.** A test under `tests/python/`: export the two-Segment reference with the ADU
   moved out, convert with PHX to WUFI XML and METr JSON, read back the attached zone, its reduction
   factor and the Faces' exposure. Check whether one Attached zone shared by two Rooms reaches WUFI
   twice; record the result and, if it does, open a PHX issue (its own authorization).

## Tests (write first)

1. Preflight: no Zone in a Segment refuses; the finding counts; the empty-Segment line.
2. HBJSON: the left-out Zone, its Spaces and Edges are absent; a Surface Face partnered with it
   refuses naming the Face.
3. The move-out offer reclassifies both sides, creates or reuses the Attached zone, and Undo
   restores the Surface pair.
4. The PHX round trip above.

## Host gate

PG03: the packaged RBZ exports both reference models; the WUFI XML and METr JSON read back.

## Done when

PG03 passes and the PHX duplicate question has a recorded answer.
