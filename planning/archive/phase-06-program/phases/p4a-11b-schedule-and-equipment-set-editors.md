# P4a-11b: The Schedule and Equipment Set editors

DATE: 2026-11-20
STATUS: Merged to main 2026-11-21 ([#551](https://github.com/ph-composer/ph-composer-skp/pull/551), squash `182f2f63`). PG11b passes on the host; Ed approved its host UI polish 2026-11-22. Split from P4a-11 on 2026-11-20. Authorized 2026-11-20 with the rest of Phase 4a; packet complete 2026-11-22 ([STATUS](../STATUS.md#host-sitting)).
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

## Decided while implementing (2026-11-21)

- **Ventilation hours.** The record refuses periods that do not total 24 h, so the four periods are held as one
  draft while they do not: the inputs and the total turn amber, the page refuses to move on, and one
  `schedules.update` of `periods`, guarded by the periods as the draft began, goes once the hours total 24. A
  fraction typed meanwhile joins the draft. Escape in a period restores the Model's periods. Every other field is
  one update of that field.
- **Strip and week row.** Both draw the row's `profile`, the same `ScheduleProfile` the `schedules.profile` query
  answers, so a paint sends no request and the strip always shows the Model's values, never a draft. The week row
  reads the profile's new `weekdays`, the export's own rule (first days_per_week from Monday, every day for a
  temperature Schedule), moved into `ScheduleProfile` so the two never disagree. API 1.85.
- **Temperature.** One value, every day: no days per week or weeks per year, which the export ignores for it.
- **Whole numbers.** Hours, days per week and weeks per year refuse a fraction or a value out of range at the field,
  with the range in the notice, before any request.
- **Gas dryer fields.** `EquipmentTypes` declares `applies_when` on a clothes dryer's `gas_consumption` and
  `gas_efficiency_factor` (`dryer_type` `gas_exhaust_air`), and `device_types` carries it, so the dialog shows a field
  by the catalog's condition rather than a branch of its own. The device still stores both. API 1.85.
- **Device dialog.** Built on `record_form.js` with its own request, settled from the page's render and counted in
  the page's busy state. Add sends the whole device; Edit sends only the values changed, guarded by them as the
  dialog opened. Field words (labels, units, choice labels, the Phius rule each rule device follows) are the
  view's; which fields a type carries and what they allow are the catalog's. Energy demand, the dryer's CEF and the
  gas fields stay in kWh and lb/kWh in both systems (the units core has no energy quantity); a clothes washer's
  capacity follows the volume unit.
- **Delete names Dwellings.** The confirmation names the Dwellings whose Set this is (their own, or the Model's
  default for one without), from the occupancy read.
- **Header action.** A record page body may give `headerAction`, set between the icon tools and the overflow menu, as
  the page-header rule orders them; the Equipment Set editor gives **Add device**.
- **Kit.** No shared kit part or kit stylesheet changed: the device grid is the kit table, the dialog the kit form
  dialog. Styles are in `features/programs/programs.css`.

Follow-ups: the Schedules subtab's **+ New Schedule** makes a fractional Schedule only, and the editor has no type
choice (Ruby's update already swaps the form on a type change); a focused field holds a subtab switch until it
loses focus, as `subtabs.js` rules for every tab.
