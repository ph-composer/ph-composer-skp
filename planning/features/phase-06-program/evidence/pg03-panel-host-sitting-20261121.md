# PG03 panel run, host sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic two-Segment reference (sha256 `70e5bd6e`). Bridge rows: [the bridge run](pg03-host-sitting-20261121.md).

Control: background computer-use `app_*` cannot click or type into the panel's HtmlDialog. Panel input was a labelled
development script event running the page's own handlers; evidence is native window pixels plus bridge reads.

| Assertion | Result | Observation |
| --- | --- | --- |
| panel-offer-shown | pass | ADU Living moved to No Building Segment from the Geometry selection bar opened "Make ADU Living an Attached zone?" (1 Face shared with Living-Kitchen). Not now wrote nothing; Make Attached zone made both Faces AttachedZone on a new Attached zone. Visual defect: the Make Attached zone button shows a trash-can icon |
| panel-offer-gesture | unknown | Owed to a full-screen hold |
| panel-move-back-notice-shown | pass | Moving back with no Attached zone Faces: no notice. After Make Attached zone: "ADU Living keeps 1 Face on an Attached zone. Run Solve adjacencies to pair the Faces it shares with other Zones again."; Faces stay AttachedZone |
| panel-move-back-notice-gesture | unknown | Owed to a full-screen hold |
