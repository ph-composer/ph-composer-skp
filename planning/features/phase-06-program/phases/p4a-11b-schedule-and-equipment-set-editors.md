# P4a-11b: The Schedule and Equipment Set editors

DATE: 2026-11-20
STATUS: Scoped. Split from P4a-11 on 2026-11-20 and authorized with it ([STATUS](../STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires P4a-11 (the Programs tab, its three subtabs and their sidebars, the record lifecycle and the Program
editor, [stage doc](p4a-11-programs-tab.md#split-and-decisions-2026-11-20)). Owns the two editors P4a-11 left
read only: steps 4 and 5 of that stage, with their tests. Load the UI polish and architecture review skills first.

Behavior: [Phase 4a PRD](../PRD.md#programs-tab-p4a-11-reviewed-2026-11-15), "Schedule editor" and "Equipment
Sets". Answers: Q4a-33, Q4a-36. Prototype: `j5-schedule`, `j1-vent-schedule`, `equipment-sets`, `device-edit`,
`device-add` in [mockups](../mockups/README.md). Paths are relative to `src/ph_composer/`.

## Steps

1. **Schedule editor** (`html/features/programs/record_bodies.js` gives way to its own module): the form by
   type, fractional and activity (start, end, fraction or watts while operating and otherwise), temperature
   (one value), ventilation's four periods (hours and fraction each, with a running total that turns amber
   unless it is 24 h), days per week and weeks per year; the 24-hour strip and the week row from
   `ph_composer.programs.schedules.profile`; full-load hours; Used by; the hourly editor as a disabled button
   marked planned. Each field one guarded `schedules.update`, as the Program editor's are.
2. **Equipment Set editor** (Q4a-36): the device grid (device, with its type when renamed; quantity; energy
   demand; in conditioned space; reference quantity), Phius-rule devices marked. Edit and Delete in each row's
   Actions cell, revealed on hover; a row click also edits; **Add device** is the Set's primary action. Add and
   Edit share one `formDialog` laid out from `equipment_sets.device_types`: Device, Energy, the type's own fields
   (shown only when they apply, such as a gas dryer's gas fields), PHPP only. The type is chosen on Add and fixed
   on Edit. Delete confirms in the shared dialog, naming the Set and the Dwellings using it.
3. **Units**: every field through the unit preferences, stored SI.
4. **Docs.** `docs/PRODUCT.md`'s Programs section loses its "read only for now" line; the UI polish patterns
   reference gains the device dialog if the kit changes.

## Tests (write first)

1. Browser checks: each Schedule type's form, the ventilation total warning, the strip and week row; device add,
   edit (each type's fields, the gas dryer's extra fields) and delete; IP and SI.
2. Every edit is one registered action and one Undo step; a stale value refuses and the field returns to the
   Model's value.
3. Narrow widths: the device grid and the Schedule form at 420 and 360 px.

## Host gate

PG11b: panel gestures with Ed at the mouse; UI polish review recorded.

## Done when

PG11b passes.
