# P4a-10: Program export

DATE: 2026-11-15
STATUS: Scoped (rewritten after the Programs tab review). Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4a-08, which brings P4a-05's airflows and P4a-06's airtightness. Writes everything
Programs owns into the HBJSON and adds the read-only Comfort section. Ruby derives every value
(AGENTS.md: domain calculations in Ruby); the Python section builds honeybee objects from the
contract record and computes nothing of its own beyond honeybee's own conversions.

Names: [CONTRACTS](../CONTRACTS.md) sections 6 and 7. Research:
[PH stack](../research/ph-stack-consumption.md), [loads and schedules](../research/loads-and-schedules.md),
[ventilation](../research/ventilation.md). Answers: Q4a-04, Q4a-07, Q4a-08, Q4a-11, Q4a-21,
Q4a-25, Q4a-31, Q4a-33. Paths are relative to `src/ph_composer/`.

## Steps

1. **Contributor** (`features/programs/export.rb`): one contract record per exported Room with its
   effective Program's loads, already resolved per Dwelling, the Schedules they use, the Room's
   People extension values and its Process devices; plus each exported Segment's set points.
   Preflight rows: a Program value missing (blocking), Zones in one Segment whose Programs' set
   points disagree or are not constant (warning, Q4a-04).
2. **Per-Dwelling Programs.** A Program with a Phius rule exports one honeybee `ProgramType` per
   Dwelling group, as honeybee-ph's Set Residential Program does (F4a-20): people per area from the
   Dwelling's occupants over the presence schedule's mean and the group's floor area; lighting
   watts per area from the Phius interior formula (honeybee-ph `phius_residential`) with its
   `PhPhiusLightingInterior` device; hot water by bedrooms. A Program without rules exports once.
3. **Schedules** as honeybee `ScheduleRuleset`s from the PH form: the operating window as the day
   profile, weekday rules for days per week (5: Monday to Friday; 6: to Saturday), and weeks per
   year as an off rule over a contiguous date range (C4a-9). Temperature Schedules as constant
   rulesets. Ventilation Schedules also write honeybee-ph's operating periods (C4a-10).
4. **People extension** per Room (F4a-19): the shared `PhDwellings` object per Dwelling with its
   units, and `number_bedrooms` and `number_people` from the Zone's counts (per Zone, Q4a-24); a
   Dwelling's own counts under Single dwelling go on its largest Room. Never `Room.zone`.
5. **Equipment Sets** as honeybee-ph `PhEquipment` Process loads (F4a-17), using the pin P4a-07
   chose: a Dwelling's Set, or the Model's default Set, once per Dwelling on its largest Room, each
   device's `quantity` its own times the Dwelling's units, since PHX merges devices across Rooms by
   identifier and sums `quantity`; a non-dwelling Zone's own Set on that Zone's Room, so two such
   Zones sharing a Set each carry its devices (Q4a-21). In a
   non-residential Segment, PHX reads the Program's equipment watts and drops devices; preflight
   warns when a Set is assigned there.
6. **Ventilation and infiltration.** The Room's honeybee `Ventilation` is its Program's, unchanged
   (Q4a-31); Space rates stay on the Spaces (P4a-05). Infiltration is the Program's unless the
   Segment has a test result (P4a-06).
7. **Set points.** Each `BldgSegment.set_points` winter and summer from its Zones' effective
   Programs (Q4a-04); the Comfort section shows them read only.
8. **Python section** (`python/ph_composer_translation/program_sections.py`), attaching to `ROOM`,
   requiring the Zones and Spaces sections, and a `segment` section for set points through
   P4a-04's attachment host.
9. **Round trip.** Through the `phx` test group: export the five prototype journeys, convert to
   WUFI XML and METr JSON, and read back per Zone: occupancy and its utilization pattern, lighting,
   equipment and appliance devices, ventilation flows and pattern, set points, dwellings and
   bedrooms. Compare with the Ruby derivations.
10. **Docs.** The agent guide's export section; the user data guide rows for Programs, Schedules,
    Equipment Sets and Dwellings (whether each `user_data` map reaches HBJSON); glossary.

## Decided (Ed, 2026-11-15)

| Id | Decision |
| --- | --- |
| C4a-9 | Weeks per year below 52: the weeks off are one contiguous block centred on 1 August (a school year), so EnergyPlus sees a summer closure. PHX's fallback ignores it until the F4a-13 fix writes occupancy and lighting operating periods |
| C4a-10 | Ventilation Schedules write honeybee-ph operating periods now: F4a-13 affects only occupancy and lighting, and without periods PHX builds the ventilation pattern from a histogram that mixes in per-person flow. Occupancy and lighting stay rulesets only until the fix (Q4a-08) |

## Tests (write first)

1. Contract records for each journey match hand values (people, lighting, hot water per Dwelling).
2. Rulesets: a 5-day, 44-week Schedule gives the expected weekday rules and date range; a
   ventilation Schedule carries the four named periods.
3. HBJSON reloads in the pinned stack: one `ProgramType` per Dwelling group for a rule Program, one
   for a plain Program; People extension and Process devices on the right Rooms; set points on the
   Segment.
4. The PHX round trip above.

## Host gate

PG10: the packaged RBZ exports the five journeys; the round trip reads them back.

## Done when

PG10 passes.
