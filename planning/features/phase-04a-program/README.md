# Phase 4a: Programs

DATE: 2026-11-14
STATUS: Requested. Research complete 2026-11-14; interview next, then a UI prototype. No stage authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Make Programs first-class in PH-Composer: author honeybee-energy ProgramTypes, with their loads and
schedules, assign them to Zones, and export them in canonical HBJSON so WUFI-Passive, METr and
PHPP receive occupancy, lighting, equipment, ventilation and airtightness without hand entry.

Ed proposed this on 2026-11-14 as the next chunk of work, ahead of the Phase 4 mechanical stages.
It is the "Zone loads packet" that [Phase 4](../phase-04-mechanical/README.md) defers to: equipment
Q12 left occupancy, lighting and the non-appliance Room loads to it, and Spaces already shows a
dash where a Zone's ventilation load should be inherited. Its place on the roadmap is Q4a-01.

## Provisional scope

From Ed's request, to be confirmed by the interview:

- **Program and its loads**, matching honeybee-energy's ProgramType: occupancy (People), lighting,
  ventilation, electric equipment, hot water, process loads and infiltration, each with its
  schedule. Process is Room-only in honeybee (F4a-02, Q4a-03); gas equipment and setpoint are the
  two ProgramType slots Ed did not list (Q4a-02).
- **Schedules** as their own definitions, shared across loads and Programs (Q4a-09).
- **A Program tab** with a section per load, for creating, editing and duplicating Programs and
  Schedules.
- **A Zones/Programs page** for assigning Programs to Zones and managing per-Zone values. The
  Zone views contract already admits a view with no child rows for this.
- **Export**: Program, load and schedule objects in the HBJSON, plus the honeybee-ph extension
  fields PHX reads.

The UI and UX are undecided. The plan is to prototype the GUI first and work back to the records,
operations and exporter.

Out until decided otherwise: ExhaustAir (F4a-16), daylighting control, fans and internal masses,
EnergyPlus simulation settings, equipment and appliances (Phase 4), Space Types.

## Read order

1. [DECISIONS.md](DECISIONS.md): findings F4a-01 to F4a-16 and the interview questions Q4a-01 to
   Q4a-18. Start here.
2. [research/honeybee-energy-programs.md](research/honeybee-energy-programs.md): the ProgramType,
   Room inheritance and overrides, Model emission, the program library, and the Honeybee
   Grasshopper affordances a Program tab should match.
3. [research/loads-and-schedules.md](research/loads-and-schedules.md): every load and schedule class,
   field by field, with units, validation and HBJSON dicts.
4. [research/ph-stack-consumption.md](research/ph-stack-consumption.md): what honeybee-ph adds and
   what PHX reads for each load, into which WUFI, METr and PHPP fields.
5. [research/ph-composer-current-state.md](research/ph-composer-current-state.md): what exists today
   and the record, assignment, export, UI and library seams to build on.
6. [STATUS.md](STATUS.md): the ledger.

## Next

1. Interview: answer Q4a-01 to Q4a-18, or the subset the prototype depends on (Q4a-02, Q4a-03,
   Q4a-06, Q4a-07, Q4a-09, Q4a-11, Q4a-12, Q4a-13, Q4a-17).
2. UI prototype of the Program tab and the Zones/Programs page in the UI preview, with the
   `ph-composer-ui-polish` skill.
3. PRD, contracts and stages, worked back from the accepted prototype. Implementation needs
   separate authorization.
