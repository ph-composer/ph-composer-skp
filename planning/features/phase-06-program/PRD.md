# Phase 4a: Programs on the Zones tab

DATE: 2026-11-15
STATUS: Scoped. Interviewed 2026-11-14 and 2026-11-15; prototype and Programs tab reviewed (Q4a-01 to Q4a-36, BS-1 to BS-6, C4a-5, C4a-7 to C4a-10). Stages P4a-01 to P4a-11 written. No stage authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

A Phius model needs every Zone's occupancy, lighting, equipment, ventilation and airtightness,
and today PH-Composer exports none of them: the consultant re-enters them in WUFI-Passive or METr.
The values come from Programs (honeybee-energy ProgramTypes), Dwellings and a few Building Segment
settings. A single-family house should need nothing but its bedroom count; apartments, common
areas and non-residential Zones need Programs, Dwellings and Equipment Sets assigned per Zone; a
detailed ventilation design needs airflows per Space.

This PRD covers everything on the **Zones tab**: the new Zones / Programs view, the changes to
Zones / Spaces, the Segment settings sections Programs owns, and the export they feed. The
Building Segment work it builds on is its own [PRD](building-segments/PRD.md). The **Programs
tab** (authoring Programs, Schedules and Equipment Sets), reviewed the same day, closes this PRD.

## Vocabulary

Enters `context/UBIQUITOUS_LANGUAGE.md` with the stage that first shows each word.

| Term | Meaning | honeybee or honeybee-ph |
| --- | --- | --- |
| Program | A named set of eight loads with their Schedules, assigned to Zones | `ProgramType` |
| Residential default | The built-in Program an unassigned Zone uses; some of its values follow Phius rules per Dwelling | honeybee-ph Set Residential Program |
| Schedule | A named fractional, activity or temperature schedule, shared by id | `ScheduleRuleset` |
| Equipment Set | A named list of appliances and Phius devices for a Dwelling | `PhEquipment` Process loads |
| Dwelling | One or more Zones counted as one dwelling unit (or several, by `units`) | People extension, `dwellings` |
| Single dwelling | A Building Segment setting: all its Zones are one Dwelling with the residential default | |
| By Program, Detailed airflows | A Zone's ventilation mode: from its Program, or from its Spaces' entered rates | `SpacePhProperties._v_*` |

## Behaviors

### Zones / Programs view (P4a-09)

A third Zone view beside Geometry and Spaces, with the same frame: Segment heading rows, the
No Building Segment group, the control row (filter, counts, New Building Segment) and a selection
bar for checked Zones ([Building Segments PRD](building-segments/PRD.md#in-the-zone-views-p4a-02-bs-1-bs-4)).

**Columns:** Name; Program; Dwelling; Bedrooms; Occupants; Equipment Set; Floor area; iCFA;
People (peak); Lighting (W); Ventilation (m³/h). Every per-area value names its basis, gross Zone
floor area or iCFA, in its header tooltip (Q4a-17).

- **Program**: a select. Unassigned Zones show their effective Program in italics: the Segment's
  default Program, else the residential default. The list holds the Model's Programs, then each
  added library source's Programs, marked "copies into this file"; choosing one copies it and its
  Schedules into the Model and assigns it in one Undo step, with a notice (Q4a-22).
- **Dwelling**: a chip naming the Dwelling (×units when more than one), or "None". Clicking it
  opens the Dwelling bubble (below). A chip in a Single dwelling Segment is locked.
- **Bedrooms, Occupants**: per Zone (Q4a-11), shown only on a Zone in a Dwelling. Occupants left
  empty use the Phius rule. Counts are per Zone and auto-totalled per Dwelling (Q4a-24); only a
  Single dwelling's Dwelling holds its own count, and then the Zone cell reads "in <Dwelling>".
- **Equipment Set**: one per Dwelling, shared by its Zones, or a Zone's own when it is not a
  Dwelling (Q4a-21). A Dwelling with none uses the Model's default Equipment Set (below). Any Zone
  in a non-residential Segment shows a dash with the reason: PHX reads the Program's equipment
  watts there.
- **People, Lighting, Ventilation**: the absolute values the export will write, from
  [CONTRACTS](CONTRACTS.md#6-derived-values-programs-ruby-p4a-08-and-p4a-09) section 6.
  **Ventilation has two sources**: the Program's flow for a By Program Zone, or the larger of its
  Spaces' entered supply and extract for a detailed Zone; the cell's tooltip names which. A value
  the Program lacks is an amber "?" naming what is missing (Q4a-25).
- **Heading row sums**: bedrooms, occupants, floor area, iCFA, people, lighting, ventilation.
  Under Single dwelling the heading row is the house row (below).
- **Findings**, an amber flag on the row they belong to: a Program with electric equipment watts
  in a residential Segment ("PHX reads only Equipment Set devices there"); an unassigned Zone in a
  non-residential Segment; a non-residential Segment with Dwellings; a residential Segment with no
  Dwelling.
- **Selection bar**: Building Segment, Program, Dwelling (one shared, one each, not a dwelling, add
  to an existing one) and Equipment Set, each applied to every checked Zone as one Undo step.
  Zones in a Single dwelling Segment cannot be checked.

### Single dwelling (P4a-08)

A setting of each Building Segment (Q4a-26 revised by BS-3), switched only in the Segment's
settings, Occupancy section, and only on a residential Segment.

1. **On:** every Zone in the Segment is one Dwelling, named for the Segment, with the residential
   default. The locked values derive from the setting and are not written to each Zone, so a Zone
   moved in joins without action. The heading row becomes the house row: its Bedrooms, Occupants
   and Equipment Set cells are the only inputs; bedrooms show an amber "?" until entered.
2. **Default:** on for every residential Segment until switched off, so a new Model's one Segment
   starts as a single dwelling (Q4a-27) and so does a Segment the user adds (C4a-7, Ed, 2026-11-15). A
   non-residential Segment is never a single dwelling.
3. **The heading shows a "Single dwelling" tag** with a lock. A locked cell, or the tag, opens a
   bubble anchored to it: "<Segment> is a single dwelling", why, and one **Open settings** button.
4. **Switching on** over per-Zone assignments in that Segment confirms first, listing what gives
   way: Program choices, extra Dwellings, per-Dwelling Equipment Sets. Per-Zone bedrooms are summed
   into the Dwelling. On a non-residential Segment the checkbox is disabled, with the reason; the
   user changes the category in the same dialog's Phius certification section first.
5. **Switching off** keeps everything it set as ordinary assignments: the Dwelling, its counts on
   the Dwelling and the residential default.

### Dwellings (P4a-08)

- **The default Equipment Set.** Like the residential default Program, the Phius single-family
  device set (honeybee-ph's eight Phius defaults: fridge-freezer, dishwasher, clothes washer,
  clothes dryer, cooktop, Phius MEL, exterior and garage lighting, F4a-20) is built in, becomes an
  ordinary editable Equipment Set in the Model on first write, and has Reset to PH-Composer default.
  A Model setting names the default Set; a Dwelling with no Set of its own uses it, so a single
  dwelling exports its appliances and MEL with nothing but its bedrooms entered.

- The Dwelling cell's bubble starts with **Dwelling of <Zone>**: a select of the Model's
  Dwellings, New dwelling and Not a dwelling, applied at once. Below it, for a Zone in a Dwelling:
  Units (editable), Zones, Bedrooms (editable when the Dwelling holds its own count), Occupants
  with an (i) explaining the Phius rule when it applies, and iCFA. No footnote.
- A Dwelling with no Zones is deleted with the last Zone that leaves it.
- Notices name the Zone when one Zone changes ("Apt 201 added to Apt 202").

### Zones / Spaces airflows (P4a-05)

The shipping view keeps its columns; no Airflow column (Ed, 2026-11-15).

1. A Zone with no Space rates is **By Program**: every airflow cell reads "By Program", with a
   tooltip saying the Zone's Program ventilation applies, split by floor area, with its schedule
   (Zones / Programs names the Program). Zone sums show a dash.
2. **Typing any rate on any Space makes its Zone detailed** (Q4a-29, Q4a-30): every Space in that
   Zone exports its own rates and every blank reads a muted 0. The first entry says so in a notice
   ("Hall and stair now uses detailed airflows: its other Space exports 0 until you enter its
   rates"). Zone sums are real.
3. **From Program** in a detailed Zone row's Actions cell clears every Space's rates in it, one
   Undo step. Clearing the last rate by hand does the same.
4. The Program's schedule applies in both modes; Room ventilation always carries the Program's
   load (Q4a-31).
5. Transfer's header tooltip: it reaches PHPP only; WUFI-Passive and METr receive supply and
   extract (F4a-27).
6. A Zone with no Spaces shows an amber "No Spaces" row and is an export warning, not an error:
   WUFI-Passive and METr open it with iCFA 0 and no ventilation rooms (F4a-28, Q4a-32).
7. The Spaces selection bar can check Zone rows, to move them between Segments.

### Segment settings sections Programs owns

Occupancy (P4a-08), Airtightness (P4a-06) and Comfort (P4a-10), as the
[Building Segments PRD](building-segments/PRD.md#building-segment-settings-p4a-02-frame-sections-in-later-stages)
lists them. Airtightness is a test result, n50 or q50, converted at export into each Zone's
Infiltration so PHX reads back the entered value (Q4a-06, F4a-09); with no test result, the
Program's Infiltration load exports.

### Export (P4a-06, P4a-10)

Per [CONTRACTS](CONTRACTS.md#7-export-mapping-p4a-03-p4a-04-p4a-06-p4a-10) section 7: each Room
carries its effective Program as a honeybee `ProgramType` with its loads and Schedules; the
honeybee-ph People extension per Dwelling; Equipment Set devices as `PhEquipment` Process loads;
infiltration from the Segment's test result; Segment set points from the Programs. Ventilation
Schedules also write honeybee-ph operating periods (C4a-10); occupancy and lighting Schedules write
them only once the honeybee-ph and PHX fix for F4a-13 ships (Q4a-08).

## Programs tab (P4a-11; reviewed 2026-11-15)

Subtabs Programs, Schedules and Equipment Sets, each the editor with one right sidebar, the
Assembly and Window Type Builders' pattern (Q4a-35): no left rail; the sidebar's source select
starts with "Programs in this file" (or Schedules, Equipment Sets), with + New, search and the
records grouped (Default and In this file; Schedules by type), and lists the added library files
after it. Choosing a record in this file opens it; a library row ends in a plus that copies it.
Schedules and Equipment Sets show only their records in this file for now. Prototype: `j4-program-cards`, `j1-vent-schedule`, `j5-program`,
`equipment-sets`.

- **Program editor** (Q4a-34): the header names the Program, its source and its users, with People,
  Lighting and Equipment as headline values. Below it, one full-width accordion card per load, in
  this order: Occupancy, Lighting, Ventilation, Electric equipment, Setpoint, Infiltration, then
  Gas equipment and Hot water under "EnergyPlus only". A closed card shows its values and schedule
  on one line, with an amber flag when a value is missing; an open card shows the load's values on
  the left and its Schedules on the right. Notes stay on their card: Ventilation's Sum of terms,
  Setpoint's "Sets the Segment", Infiltration's replacement by a Segment test result, the source
  of a value filled from a base program.
- **The residential default** (Q4a-23) is an ordinary, editable Program in each Model, listed under
  Default; Reset to PH-Composer default sits in its overflow menu. Its Phius-rule cards show the
  rule and its inputs, and can be switched to a fixed value.
- **Schedule editor**: the PH form by type. Fractional and activity: start, end, fraction while
  operating and otherwise, days per week, weeks per year, over a 24-hour strip and a week row.
  **Ventilation** (Q4a-33): four rows, high, standard, basic and minimum, each hours per day and a
  fraction of design flow, a running total that turns amber unless it is 24 h, days per week and
  weeks per year. Every Schedule lists the loads that use it. The hourly editor is planned (Q4a-07).
- **Equipment Sets**: a device grid (device, quantity, energy demand, in conditioned space,
  reference quantity) with Phius-rule devices marked. Devices are added, edited and deleted one at
  a time (Q4a-36): Edit and Delete in each row's Actions cell, a row click also edits, and **Add
  device** as the Set's primary action. Add and Edit share one form dialog laid out by the device's
  honeybee-ph type: Device (type, chosen on Add and fixed on Edit; name; quantity; in conditioned
  space; comment), Energy (reference quantity, limited to the codes the type allows; energy demand,
  or the Phius rule for a rule device), the type's own fields (a dryer's type, field utilization
  factor and, for a gas dryer, gas consumption), and PHPP only. Delete confirms. A Set is assigned
  to a Dwelling, or to a Zone that is not a dwelling (Q4a-21). The Model's default Set is listed
  under Default, with Reset to PH-Composer default in its overflow menu, as the default Program is.
- **Library Programs** copy into the Model with their Schedules when used, the same protocol as
  Materials, Frames and Glazings (Q4a-22), and arrive complete (Q4a-25).

## Decisions

[DECISIONS.md](DECISIONS.md#answered) holds every answer: the interview (Q4a-01 to Q4a-18), the
prototype and Programs tab reviews (Q4a-19 to Q4a-36) and the findings F4a-01 to F4a-29. Contract
questions C4a-2 to C4a-10 are in [CONTRACTS](CONTRACTS.md#open-contract-questions). The Building Segment
answers are in the [Building Segments PRD](building-segments/PRD.md#decisions-ed-2026-11-15).

## Out of scope

ExhaustAir (F4a-16), daylighting control, fans and internal masses, EnergyPlus simulation
settings, Space Types (Q4a-16), exporting Zones in no Segment as shading, Space rates folded into
Room ventilation for EnergyPlus (Q4a-31), mechanical cooling and mechanical room temperature
(Phase 4, C4a-5).
