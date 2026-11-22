# PG06 panel run, host sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic two-Segment reference (sha256 `70e5bd6e`). Bridge rows: [the bridge run](pg06-host-sitting-20261121.md).

Control: background computer-use `app_*` cannot click or type into the panel's HtmlDialog. Panel input was a labelled
development script event running the page's own handlers; evidence is native window pixels plus bridge reads.

| Assertion | Result | Observation |
| --- | --- | --- |
| dialog-section-shown | pass | New Segment: n50, blank result (1/h), "Several sides exposed, no screening". q50 shows m³/h·m². 0 and -1 hold Save with "Airtightness: Enter a test result greater than 0, or leave it blank."; nothing written. 0.6 with high screening saved and read back. Visual defect: the Test result row stacks select, field and unit vertically, the unit alone under the field |
| dialog-section-gesture | unknown | Owed to a full-screen hold: background clicks and keys do not reach the web view |
