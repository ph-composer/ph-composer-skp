# P4a-03: Segment export rules and Attached zones

DATE: 2026-11-15
STATUS: Implemented on branch 2026-11-20 ([STATUS](../STATUS.md)); host rows owed. Authorized 2026-11-20 with the rest of Phase 4a.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires P4a-02 (the move-out offer starts from its selection bar). Owns the export minimum, leaving out Zones in no Segment with everything that
hangs on them, empty Segments, the Attached zone rule for shared Faces, the move-out offer, and a
PHX round trip of `PhAdditionalZone`.

Entry checks, added 2026-11-20:

- **The pins (C4a-11, Ed, 2026-11-20).** Choose the honeybee-ph pin for `PhEquipment` (F4a-18: `quantity`
  defaults and the custom types differ between 1.33.65 and 1.33.68), record it in `pyproject.toml` and
  the vendored wheels, and move the `phx` group to the latest PHX release over it. Rerun the Site and
  Shade PHX round trips on the new pins, and the PHX findings this packet read at 1.59.1 (F4a-09,
  F4a-10, F4a-24 to F4a-28). Record the pins in STATUS.
- Climate's closure carries a report, never reproduced, that PHX fails to convert a Building Segment
  whose name holds a space. Reproduce it with a two-Segment HBJSON before step 6; record the result
  and, if it fails, the PHX issue (its own authorization).

Behavior: [Building Segments PRD](../building-segments/PRD.md), "Export rules" and "How
PhAdditionalZone reaches PHX". Paths are relative to `src/ph_composer/`.

## Steps

1. **Preflight.** `features/zones/export.rb`: refuse when no Zone is in a Segment; info finding
   naming Zones left out with counts of their Faces, Spaces and Edges; info line per empty Segment.
2. **Leave out.** Zones' Room section skips no-Segment Zones; `features/spaces/export.rb` and
   `features/thermal_bridges/export.rb` skip what belongs to them; the Python sections
   (`model_sections.py`, `space_sections.py`, `thermal_bridge_sections.py`) never see them. Shading's export reads Zones' section rows to know
   which containers are Zones (CONTRACTS section 7): a left-out Zone stays a Zone to it, and a Face tagged as shading inside one still
   exports as a Shade (C4a-12, Ed, 2026-11-20).
3. **Shared Faces.** `features/zones/faces/export.rb`: a Surface Face whose partner Zone is left
   out refuses, naming the Face and pointing to the offer. A Face holds an Attached zone only on the
   Attached zone boundary (`faces/schema.rb`), so nothing is substituted at export.
4. **Move-out offer.** When `update_field` sets a null Segment on a Zone with Surface Faces shared
   with Segment Zones, the panel offers one confirmation that reclassifies those Faces (on both
   sides) from Surface to Attached zone, leaving their pairs (`leave_pair!`), and creates or reuses
   an Attached zone named for the Zone: one Undo step through Zones' existing Face and Attached zone
   actions. Moving the Zone back leaves them as Attached zone with a notice to re-run Solve (C4a-8).
5. **PHX test group.** Exists: Climate's P4c-05 added the `phx` group. Nothing to add here; the entry
   check above sets its pin.
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
5. Shading in a left-out Zone: a marked Face exports as a Shade named "<Zone> Shading"; a mark on a
   Group above the Zone reaches none of its Faces; the Site section's Building Segment count still
   matches the reloaded Model.

## Host gate

PG03: the packaged RBZ exports both reference models; the WUFI XML and METr JSON read back.

## Done when

PG03 passes and the PHX duplicate question has a recorded answer.
