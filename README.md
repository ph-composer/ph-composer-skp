# PH-Composer for SketchUp

PH-Composer is a free, open-source SketchUp extension for authoring Phius passive building models.
The SKP file holds the geometry, definitions and assignments. You can enter everything by hand or
copy definitions from a library into the model. Export writes HBJSON and a companion report.

## Build a model

- Group envelope geometry into Zones. Classify Faces, solve adjacencies and assign Assemblies.
- Build opaque Assemblies from Materials. Define Window Types and place them on envelope Faces.
- Assign psi-values to edges and review thermal bridge runs in the Schedule.
- Add Spaces, mark iCFA and enter ventilation rates.
- Run Export preflight, resolve blocking findings and write the HBJSON and report.

[Modeling guide](docs/PRODUCT.md) · [Installation and troubleshooting](docs/HELP.md) ·
[Documentation](docs/.index.md)

PH-Composer is in development. The team tests on SketchUp 2026 for macOS. The
[project status](planning/STATUS.md) records feature and platform acceptance. Check
[GitHub Releases](https://github.com/ph-composer/ph-composer-skp/releases) for published builds.

## Contribute

Start with the [development guide](docs/DEVELOPMENT.md) and the [engineering context](context/.index.md).
Coding agents start at [AGENTS.md](AGENTS.md). Sign off each commit under the
[Developer Certificate of Origin](docs/DCO.md). Use the [security policy](docs/SECURITY.md) for
vulnerability reporting.

PH-Composer is licensed under [AGPL-3.0-or-later](LICENSE). See [Licensing](docs/LICENSING.md)
for third-party components, library data and contributions.

Started by [BLDGTYP, LLC](https://www.bldgtyp.com).
