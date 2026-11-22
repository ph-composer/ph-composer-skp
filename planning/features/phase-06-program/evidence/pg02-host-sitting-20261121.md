# PG02 host run, sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic two-Segments reference (sha256 `70e5bd6e`). Offline and browser rows: [stage evidence](pg02-segment-rows-browser.md).

Control: bridge rows through public operations with the panel closed. Background computer-use `app_*` cannot click,
type or hover in the panel's HtmlDialog, so panel input was a labelled development script event running the page's
own handlers; the page was read back through a development callback registered before the panel's first show, and
captured as native window pixels. Edit-menu Undo and Redo were pressed natively through System Events, each label
read first. The refused-payload rows use the development note namespace (`tools/examples/zones/example_segment_note*`),
loaded as labelled development setup.

| Assertion | Result | Observation |
| --- | --- | --- |
| bridge-new-segment | pass | New Building Segment with a Zone moved in: one native Undo step, Redo restores |
| bridge-settings-save | pass | Rename plus a development namespace's payload: one step "Change Building Segment Settings", native Undo and Redo |
| bridge-refused-payload | pass | A blank note refuses `validation.failed`, nothing written, revision unchanged |
| bridge-locked-member | pass | A settings-only save completes past a locked member Zone; a rename with it refuses `target.locked` by design |
| bridge-transition-contributor | pass | The shipped Programs contributor to `zones.segment_settings_saved` makes the Dwelling inside the same Undo step |
| native-undo-redo | pass | Every bridge and panel edit (New, settings saves, rename, Delete, both bar moves) one native Undo step, Redo restores |
| panel-headings-shown | pass | Heading rows in Geometry, Spaces and Programs with Default and Single dwelling tags and sums. Notes: the two tags wrap to a third line in Spaces and Programs; at 360 px the headings show no name |
| panel-new-move-delete-shown | pass | New names in place, Move from both bars, Delete with a destination. Notes: the new name field can open out of view and is too narrow for the default name |
| panel-settings-dialog-shown | pass | Every section, a blank note blocks Save, a save is one Undo step, narrow layouts. Note: the problem status covers the Note row |
| panel-gesture | unknown | Owed to a full-screen hold (real hover, clicks, Return, Escape) |
| polish-review | unknown | Host shots recorded at 1280, 420 and 360; Ed's verdict owed |
