# Product requirements

PH-Composer gives Phius practitioners a way to author passive building models in SketchUp.
The [modeling guide](PRODUCT.md) describes the tools in the current build. The
[roadmap](../planning/ROADMAP.md) tracks planned work.

## Author and exchange a building model

- Keep building geometry, definitions and assignments in the SKP file. A practitioner can
  create and edit every supported definition locally.
- Use Honeybee face types and boundary conditions. Derive measurements from the authored
  geometry and let users inspect the source of each quantity.
- Copy library definitions into the model as editable records. Keep library setup and credentials
  on the computer that uses them. Store evidence PDFs and photos in user-managed folders.
- Validate the authored data and export HBJSON with a report. Treat the HBJSON as the input
  to downstream converters.
- Give scripts and extensions the same operations and validation rules as the interface.
  Agent access uses explicit, revocable grants.
- Keep the site, the design temperatures and one climate in the SKP file. Read Phius station
  files where the user keeps them, copy the chosen station's values into the model, or take values
  typed by hand, and write the climate as the HBJSON `Site`.

## Planned work

| Area | Requirements | Plan |
| --- | --- | --- |
| Mechanical systems | Define equipment, model duct and pipe runs, and associate them with the building systems they serve | [Mechanical](../planning/features/phase-07-mechanical/README.md) |
| METr handoff | Convert HBJSON with PHX and verify the resulting model in METr | [METr export](../planning/features/unscheduled/metr-export/README.md) |
| Hourly weather file | Derive a preliminary monthly climate from an EPW, with user-supplied peak-load data for the METr handoff | [Climate data](../planning/archive/phase-04-climate/README.md) |

The roadmap also tracks [sun-path and window performance views](../planning/ROADMAP.md#phase-8-post-mvp-was-phase-5-items-51-to-55),
additional library kinds and PV.

See the [project status](../planning/STATUS.md) for implementation and acceptance.
