# PG05 panel run, host sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic apartments reference (sha256 `0ddf6c71`). Bridge rows: [the bridge run](pg05-host-sitting-20261121.md).

Control: background computer-use `app_*` cannot click, type or scroll in the panel's HtmlDialog. Panel input was a
labelled development script event running the page's own handlers; evidence is native window pixels plus bridge
reads. Edit-menu Undo and Redo were pressed natively through System Events.

| Assertion | Result | Observation |
| --- | --- | --- |
| panel-spaces-view-shown | pass | By Program cells and dash sums; one rate on Apt 101 Living gave "Apt 101 now uses detailed airflows: its other 3 Spaces export 0 until you enter theirs." with blanks at 0; From Program confirmed ("Use Program airflows?") and cleared; Storage's amber No Spaces row. Notes: the detailed notice stayed after the clear (no native interaction to dismiss it); the amber starts at the Name column |
| panel-spaces-view-gesture | unknown | Owed to a full-screen hold |
| panel-undo-redo | pass | Edit > Undo / Redo "Clear Zone Airflows" by System Events restored and re-cleared Apt 101's rates; the first press did nothing until the document window was made focused as well as main |
