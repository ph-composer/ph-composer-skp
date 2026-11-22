# PG11 host run, sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic journeys reference (`218e8347`), with the synthetic library file `tools/examples/library/programs.json`
added for the run and removed after (synthetic, not Phius data). Offline rows: [stage evidence](pg11-programs-tab-offline.md).

Control: background computer-use `app_*` cannot click or type in the panel's HtmlDialog, so panel input was a
labelled development script event running the page's own handlers, read back through a development callback and
native window pixels. Edit-menu Undo and Redo were pressed natively through System Events, label read first.

| Assertion | Result | Observation |
| --- | --- | --- |
| tab-sidebars-shown | pass | Three subtabs, each with its sidebar; a record opened from its row |
| library-add-shown | pass | A library Program added from the sidebar with its two Schedules, one Undo step; the row ends in a check. Note: the card keeps offering Add to file |
| cards-rule-value-shown | pass | Cards and summaries, missing-value flags, rule switch both ways, a typed value committed, each one Undo step. Keyboard Enter on a head owed to the hold |
| schedule-slot-shown | pass | A Schedule chosen in a slot; + New Schedule made and named one (two steps by design) |
| records-lifecycle-shown | pass | New, rename in place, Duplicate, Delete with a replacement moving Zones and a Segment's default, Reset on the default |
| units-widths-shown | pass | IP people/ft²; at 420 px the sidebar drops beneath the editor |
| native-undo-redo | pass | Every edit one native Undo step, Redo restores |
| panel-gesture | unknown | Owed to a full-screen hold |
| polish-review | unknown | Host shots recorded; Ed's verdict owed |
