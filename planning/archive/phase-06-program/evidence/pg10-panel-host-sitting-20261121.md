# PG10 panel run, host sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic five-journeys reference (sha256 `218e8347`). Bridge rows: [the bridge run](pg10-host-sitting-20261121.md).

Control: background computer-use `app_*` cannot click into the panel's HtmlDialog. Panel input was a labelled
development script event running the page's own handlers; evidence is native window pixels plus bridge reads.

| Assertion | Result | Observation |
| --- | --- | --- |
| panel-comfort-section-shown | pass | Comfort reads House 20/25 °C (agree), School 20/26 °C and Apartments 18/26 °C with the "different set points" note, matching each Segment's read |
| panel-locate-shown | pass | School's set-point Locate opened Zones / Programs with Classroom and Lab checked. Notes: it also opens School's settings dialog over the view (at its top); the checked rows sit behind the selection bar; the row reads "Apartments's Zones" |
| panel-gesture | unknown | Owed to a full-screen hold |
