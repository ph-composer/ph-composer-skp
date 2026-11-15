# Phase 4a: Programs

DATE: 2026-11-14
STATUS: Scoped for the Zones tab (2026-11-15): PRD, contracts, plan and stages written; the Programs tab is specified after its review. No stage authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Make Programs first-class in PH-Composer: author honeybee-energy ProgramTypes, with their loads and
schedules, assign them to Zones, and export them in canonical HBJSON so WUFI-Passive, METr and
PHPP receive occupancy, lighting, equipment, ventilation and airtightness without hand entry.

Ed proposed this on 2026-11-14 as the next chunk of work, ahead of the Phase 4 mechanical stages.
It is the "Zone loads packet" that [Phase 4](../phase-04-mechanical/README.md) defers to: equipment
Q12 left occupancy, lighting and the non-appliance Room loads to it, and Spaces already shows a
dash where a Zone's ventilation load should be inherited. Its place on the roadmap is Q4a-01.

## Scope

From Ed's request and the 2026-11-14 interview ([answers](DECISIONS.md#answered)):

- **Program**, matching honeybee-energy's ProgramType with all eight slots fully editable:
  occupancy (People), lighting, electric equipment, gas equipment, hot water, infiltration,
  ventilation (four terms, method fixed to Sum) and setpoint (Q4a-02, Q4a-15). Zones choose a
  Program and do not override its loads (Q4a-12).
- **Schedules** as their own record kind, shared by id (Q4a-09). Authored in a PH form (hours,
  fraction, days per week, weeks per year) that writes a honeybee ruleset with real weekday rules
  and operating days (Q4a-07). An OpenStudio-style hourly editor is deferred but planned for.
- **Equipment Sets**: honeybee-ph `PhEquipment` devices (appliances, Phius MEL and lighting,
  custom annual loads) assigned to Zones, exported as honeybee-ph Process loads (Q4a-03, F4a-17).
  This absorbs Phase 4's appliances (P4-12).
- **Dwellings**: a Dwelling record with a unit count that Zones reference, plus bedrooms and
  occupants per Zone, written to honeybee-ph's People extension (Q4a-11, F4a-19).
- **A built-in default residential Program** for unassigned Zones, built from honeybee-ph's
  Set Residential Program rules and schedules (Q4a-13, F4a-20). Some of its values are derived
  per dwelling group at export.
- **On the Building Segment**: the Phius category (Q4a-14), an airtightness test result (n50 or
  q50) converted into each Zone's Infiltration (Q4a-06), and set points written from the Zones'
  Program setpoints (Q4a-04).
- **A Program tab** with a section per load, for creating, editing and duplicating Programs,
  Schedules and Equipment Sets.
- **A Zones/Programs page** for assigning Programs, Equipment Sets and Dwellings to Zones, with
  each Zone's counts and the absolute equivalent of every per-area value; every per-area value
  names its basis (Q4a-17).
- **Starter library**: the residential default from the pinned honeybee-ph wheel, built in; Phius
  Multifamily and Non-Residential programs as library files in the planned ph-composer-standards
  repository, added through Library setup (Q4a-10, Q4a-19).
- **A Single dwelling switch** on each Building Segment: its Zones one dwelling with the
  residential default, their rows locked, bedrooms entered once (Q4a-26, revised by
  [BS-3](building-segments/PRD.md#decisions-ed-2026-11-15)).
- **Export**: Program, load and schedule objects in the HBJSON, plus the honeybee-ph extension
  fields PHX reads.

The plan is to prototype the GUI first and work back to the records, operations and exporter.

Out until decided otherwise: ExhaustAir (F4a-16), daylighting control, fans and internal masses,
EnergyPlus simulation settings, Space Types (Q4a-16), and writing honeybee-ph operating periods
until the cross-repo fix for F4a-13 ships (Q4a-08).

## Read order

1. [PRD.md](PRD.md): the Zones tab behaviour this phase builds, and
   [building-segments/PRD.md](building-segments/PRD.md), the Building Segment work it stands on.
   The [GUI prototype](mockups/README.md) shows both.
2. [CONTRACTS.md](CONTRACTS.md): records, ownership, seams and export mapping, with open contract
   questions C4a-2, C4a-3, C4a-4, C4a-6, C4a-9 and C4a-10, which settle in their stages.
3. [PLAN.md](PLAN.md), the stages under [phases/](phases), and [ACCEPTANCE.md](ACCEPTANCE.md).
4. [DECISIONS.md](DECISIONS.md): findings F4a-01 to F4a-29 and questions Q4a-01 to Q4a-32 with
   every answer.
5. [research/honeybee-energy-programs.md](research/honeybee-energy-programs.md): the ProgramType,
   Room inheritance and overrides, Model emission, the program library, and the Honeybee
   Grasshopper affordances a Program tab should match.
6. [research/loads-and-schedules.md](research/loads-and-schedules.md): every load and schedule class,
   field by field, with units, validation and HBJSON dicts.
7. [research/ph-stack-consumption.md](research/ph-stack-consumption.md): what honeybee-ph adds and
   what PHX reads for each load, into which WUFI, METr and PHPP fields.
8. [research/ph-composer-current-state.md](research/ph-composer-current-state.md): what exists today
   and the record, assignment, export, UI and library seams to build on.
9. [research/ventilation.md](research/ventilation.md): Zone ventilation and Space airflows across
   honeybee-ph, the Grasshopper path, PHX and its writers (F4a-24 to F4a-29, Q4a-29 to Q4a-32).
10. [STATUS.md](STATUS.md): the ledger.

## Next

1. P4a-01 to P4a-11 are ready; each needs Ed's go.
2. Separately: the honeybee-ph and PHX fix for F4a-13 (Q4a-08), in those repositories, starting
   with a reproducing test in each.
