# PG08 panel run, host sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic two-Segment reference (sha256 `70e5bd6e`). Bridge rows: [the bridge run](pg08-host-sitting-20261121.md).

Control: background computer-use `app_*` cannot click or type into the panel's HtmlDialog. Panel input was a labelled
development script event running the page's own handlers; evidence is native window pixels plus bridge reads (one
labelled DOM probe printed the flag's accessible text).

| Assertion | Result | Observation |
| --- | --- | --- |
| panel-segment-headings-shown | pass | "Single dwelling" tag on both headings in Geometry, Spaces and Zones / Programs. ADU made non-residential: tag gone, amber flag "2 Zones: A Zone in a non-residential Building Segment has no Program of its own or from its Segment." in all three views. House's Occupancy switch off and saved: tag gone, House Dwelling holds its 5 Zones. Note: ADU's heading in Zones / Programs still shows the amber bedrooms "?" after it became non-residential |
| panel-segment-headings-gesture | unknown | Owed to a full-screen hold |
