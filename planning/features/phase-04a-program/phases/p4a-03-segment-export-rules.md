# P4a-03: Segment export rules and Attached zones

DATE: 2026-11-15
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-01. Owns the export minimum, leaving out Zones in no Segment with everything that
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
   out exports its assigned Attached zone; with none, refuse naming the Face.
4. **Move-out offer.** When `set_building_segment` sets null on a Zone with Surface Faces shared
   with Segment Zones, the panel offers one confirmation that creates or reuses an Attached zone
   named for the Zone and assigns it to those Faces, as one Undo step (a compound with Zones'
   Attached zone actions).
5. **PHX round trip.** A test under `tests/python/` through the pinned stack: export the
   two-Segment reference with the ADU moved out, convert with PHX to WUFI XML and METr JSON, read
   back the attached zone, its reduction factor and the Faces' exposure. Check whether one
   Attached zone shared by two Rooms reaches WUFI twice; record the result and, if it does, open
   a PHX issue (its own authorization).

## Tests (write first)

1. Preflight: no Zone in a Segment refuses; the finding counts; the empty-Segment line.
2. HBJSON: the left-out Zone, its Spaces and Edges are absent; the shared Face carries its
   Attached zone; with none, export refuses naming it.
3. The move-out offer creates, reuses, and Undo restores.
4. The PHX round trip above.

## Host gate

PG03: the packaged RBZ exports both reference models; the WUFI XML and METr JSON read back.

## Done when

PG03 passes and the PHX duplicate question has a recorded answer.
