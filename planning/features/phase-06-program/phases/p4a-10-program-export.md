# P4a-10: Program export

DATE: 2026-11-15
STATUS: Implemented on branch `feature/phase-06-program-p4a-10` (2026-11-20); PG10's host rows owed to the batched sitting. Authorized 2026-11-20 with the rest of Phase 4a ([STATUS](../STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

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
   points disagree or are not constant (warning, Q4a-04), and a Program whose heating set point is above
   its cooling one once a temperature Schedule is read (blocking; P4a-07a checks two constants only).
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
   P4a-04's attachment host. What the export report shows (set points, counts per Dwelling) travels
   through the Python result and the privacy allowlist: the report reads the result, not the Ruby
   record (Climate D4c-24). A Program note, device comment or name that reads as a local file path
   stays in the Model, since the export's artifact guard refuses one (Climate D4c-25). Each preflight
   row carries a `locate` that opens the Zones or Programs tab at its record, through
   `session.open_in_panel` (Climate D4c-27).
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

## Implementation decisions (2026-11-20)

Contract: `context/CONTRACTS.md`, "Program export". Evidence: [PG10 offline](../evidence/pg10-program-export-offline.md).

- **Four sections, one plan.** `ExportPlan` (pure) works out everything once; `programs.export.rooms` claims the two
  occupancy extensions and registers the plan as its projection, and `schedules`, `program_types` and
  `set_points` read it. The Python half is four sections in `program_sections.py`, two attached nowhere (Schedules
  and ProgramTypes, taken as inputs), Rooms at `ROOM` and set points at `SEGMENT`. The stage doc's "one record per
  Room plus each Segment's set points" holds; Schedules and ProgramTypes are their own records so each honeybee
  object is built once.
- **The two occupancy extensions are `required`** and claimed; a payload this version cannot read now blocks.
- **Areas, as honeybee-ph.** Per-area rule loads divide by the Dwelling's Rooms' Floor Face area (honeybee's
  `Room.floor_area`, which Set Residential Program uses), the lighting formula takes the Spaces' iCFA. The Spaces
  export projection now carries each Zone's floor area and iCFA beside its net volume.
- **Counts on Rooms sum to the Dwelling's.** Each Zone's own count while the Dwelling's is its Zones' sum, else the
  whole count (its own, the house's or the Phius rule's) on its largest Room by Floor area, which also carries the
  devices. PHX sums `number_people` and `number_bedrooms` over a Segment's Rooms.
- **No count is not a block.** A Dwelling on a Phius rule with no bedrooms exports with none, as a warning
  (`programs.counts_missing`), so a fresh house exports as it did. A Zone in no Dwelling on a rule Program is a
  group of one unit, as Set Residential Program treats an untagged Room (`programs.rule_without_dwelling`, a
  warning); a legacy Zone, which names no Segment record, gets no note. "A Program value missing" blocks:
  `programs.value_missing`, per field, a Schedule left empty being honeybee's Always On except where a rule
  divides by its mean.
- **Hot water** follows Set Residential Program's code, shower 1.17 gallons per bedroom, not the 4.67 its
  docstring and Building America Table 11 give (F4a-20); a follow-up for honeybee-ph.
- **Process watts** are honeybee-ph's own `annual_avg_wattage` over the Dwelling's counts and iCFA (EnergyPlus
  only; PHX reads the device). No Process schedule is in the Model, so each uses honeybee's Always On.
- **A ventilation day off** runs at the minimum period's fraction; a fractional or activity day off at its
  `fraction_off` or `watts_off`.
- **Rule means.** A rule's presence and lighting means are the daily mean of the Schedule's day, as the Zones /
  Programs view derives them, not the annual mean of the exported ruleset; they differ only on a rule Schedule of
  fewer than 7 days or 52 weeks. A Dwelling with no Floor Face area exports its rule loads at 0 per m² with a
  warning (`programs.no_floor_area`), where Set Residential Program refuses: blocking would stop exports of Zones
  drawn without a Floor.
- **Set points.** Where the Zones' Programs disagree, the Segment exports its first Zone's by id, and the warning
  names the pair. A temperature Schedule is always constant in the PH form, so "not constant" cannot arise yet.
- **Identifiers** join record ids with "-" (`pgm_…-dwl_…`, `eqs_…-dev_…`), and every `PhDwellings` gets one, so the
  HBJSON is the same each run.
- **Locate.** `programs.locate` opens the Zones tab on the Zones / Programs view with the row's Zones checked
  (Zones' `onNavigate` takes `zones`), or a single dwelling's settings; Programs records are `workedOn` that tab
  until P4a-11's Programs tab.
- **User data** of Programs, Schedules, Equipment Sets and their devices, and Dwellings stays in the Model with a
  finding; none has an HBJSON object of its own that a map could follow without duplicating it per Dwelling.
- **Report.** The Programs part lists each Segment's set points and its Dwellings' units and counts, from the
  Python result.

