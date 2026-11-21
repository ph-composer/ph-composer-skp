# P4a-11: The Programs tab

DATE: 2026-11-15
STATUS: Implemented on branch `feature/phase-06-program-p4a-11` (2026-11-20); PG11 host rows owed. Split on 2026-11-20: steps 4 and 5 moved to [P4a-11b](p4a-11b-schedule-and-equipment-set-editors.md). Authorized 2026-11-20 with the rest of Phase 4a ([STATUS](../STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires P4a-07a (records), P4a-07b (library kinds) and P4a-08 (used-by counts, the default). Owns the
Programs tab: three subtabs, each an editor with one right sidebar. Load the UI polish and
architecture review skills first.

Behavior: [Phase 4a PRD](../PRD.md#programs-tab-p4a-11-reviewed-2026-11-15). Answers: Q4a-23,
Q4a-33, Q4a-34, Q4a-35 (revised). Prototype: `j4-program-cards`, `j4-library`,
`j1-default-program`, `j1-vent-schedule`, `j5-program`, `j5-schedule`, `equipment-sets` in
[mockups](../mockups/README.md). Paths are relative to `src/ph_composer/`.

## Steps

1. **Tab and pane.** A top-level Programs tab after Zones (Climate is now first in the row; `html/index.html`, a composition-root
   edit, and the panel manifest); `html/features/programs/` for the feature's panel modules; one
   page header (`ui.pageHeader`) over the shared subtabs nav, Programs, Schedules, Equipment Sets.
2. **Right sidebar on every subtab** (Q4a-35): the shared library sidebar (`library/sidebar.js`),
   as the Assembly and Window Type Builders use it. Its source select starts with "Programs in this
   file" (Schedules, Equipment Sets), then the added library files; + New, search and grouped rows
   (Default and In this file; Schedules by type). Choosing a record opens it; a library row ends in
   a plus that copies it through the coordinator (with its Schedules), or a check when it is in this
   file. Schedules and Equipment Sets list only this file for now.
3. **Program editor** (Q4a-34): title with in-place rename, source badge, headline values (users,
   people, lighting, equipment), header actions (rename, duplicate, overflow with Delete and, on the
   default, Reset to PH-Composer default). A column of full-width accordion cards in the order
   Occupancy, Lighting, Ventilation, Electric equipment, Setpoint, Infiltration, then Gas equipment
   and Hot water under "EnergyPlus only". Closed: values and schedule on one line, amber flag when
   a value is missing. Open: values on the left, Schedules on the right (a select per schedule
   slot, filtered by type, with + New Schedule). Card notes: Sum of terms, Sets the Segment,
   Replaced by the Segment's test result, the source of a base-program value. A rule card shows its
   rule and inputs and offers "Use a fixed value" and back.
4. **Schedule editor**: the form by type (fractional and activity; temperature; ventilation's four
   periods with a running total that turns amber unless it is 24 h), days per week and weeks per
   year, the 24-hour strip and week row, full-load hours, Used by, and the hourly editor as a
   disabled button marked planned.
5. **Equipment Set editor** (Q4a-36): the device grid (device, with its type when renamed;
   quantity; energy demand; in conditioned space; reference quantity), Phius-rule devices marked.
   Edit and Delete in each row's Actions cell, revealed on hover; a row click also edits; **Add
   device** is the Set's primary action. Add and Edit share one form dialog (`formDialog`) laid
   out from the per-type field table: Device, Energy, the type's own fields (shown only when they
   apply, such as a gas dryer's gas fields), PHPP only. The type is chosen on Add and fixed on Edit.
   Delete confirms in the shared dialog, naming the Set and the dwellings using it.
6. **Record lifecycle** per the UI polish rules: New acts at once under a free name and opens the
   title for renaming; Duplicate the same; Delete confirms in the shared dialog and, when the record
   is used, asks for a replacement.
7. **Units**: every field through the unit preferences (IP shows W/ft², cfm per person, cfm/ft²,
   °F), stored SI.
8. **Docs.** `docs/PRODUCT.md` gains a Programs section; the UI polish patterns reference gains
   the accordion card; Design System re-sync if the kit changes.

## Tests (write first)

1. Browser checks: sidebar sources and rows on each subtab, open from a row, copy from a library
   with its Schedules, accordion open and close and keyboard, card summaries, missing-value flags,
   rule switch, Reset on the default, ventilation total warning, device add, edit (each type's
   fields, the gas dryer's extra fields) and delete, New,
   Duplicate, Delete with replacement, IP and SI.
2. Every edit is one registered action and one Undo step; a stale value refuses and the field
   returns to the Model's value.
3. Narrow widths: the sidebar drops beneath the editor without moving the editor down.

## Host gate

PG11: panel gestures with Ed at the mouse; UI polish review recorded.

## Done when

PG11 passes.

## Split and decisions (2026-11-20)

The stage was split because its five editors and the Ruby carry-overs are more than one reviewable PR. P4a-11
is steps 1 to 3 and 6 to 8 with tests 1 to 3 as they apply to them; the Schedule editor (step 4) and the
Equipment Set device editor (step 5) are [P4a-11b](p4a-11b-schedule-and-equipment-set-editors.md), with their
tests and the PG11b host gate. Until P4a-11b lands, the Schedules and Equipment Sets subtabs show each record's
values read only, under the same sidebar, header and lifecycle as Programs.

Decided while implementing:

- **Reads.** The tab reads the snapshot sections `ph_composer.programs.programs`, `schedules` and
  `equipment_sets`, each the collection's `all` read. A Program row carries `missing`, each value its ProgramType
  would lack as `{load, field}`, from the export preflight's own rule (`ExportPlan.missing_fields`), so the
  cards' amber flags and the preflight never disagree. API 1.84.
- **Delete with replacement** (carried from P4a-08): a Program or Equipment Set deleted with a replacement moves
  every Zone assignment (`program_id`, `equipment_set_id`) and Segment setting (`default_program_id`,
  `equipment_set_id`) naming it, through Zones' `stage_extension` participant, in the delete's Undo step; a
  locked or shared Zone refuses the whole delete. The dialog's replacement is chosen, never assumed.
- **Edits.** Each value commits as one `programs.update` of its whole load, guarded by the load as drawn, so a
  value changed meanwhile refuses and the field shows the Model's value on the next paint. **+ New Schedule**
  is two Undo steps: the Schedule's create, then the slot naming it.
- **Header actions.** Rename, Duplicate and the overflow menu sit on the editor's title row, as the prototype and
  this stage name them, not on sidebar rows.
- **Units.** Hot water flow per area (EnergyPlus only) stays in L/h per m² in both systems: the units core has
  no quantity for it yet.
- **Routing.** Programs' records are `workedOn` the Programs tab; the Zones / Programs view no longer claims them.

