# PG11b host run, sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Fresh process on a fresh copy of the
synthetic journeys reference (`218e8347`). Offline rows: [stage evidence](pg11b-schedule-and-equipment-set-editors-offline.md).

Control: background computer-use `app_*` cannot click or type in the panel's HtmlDialog, so panel input was a
labelled development script event running the page's own handlers, read back through a development callback and
native window pixels. Edit-menu Undo and Redo were pressed natively through System Events, label read first.

| Assertion | Result | Observation |
| --- | --- | --- |
| schedule-editors-shown | pass | Fractional, activity and temperature Schedules edited field by field, the strip following a saved end hour; a fraction of days refused (the week row was shown, not changed) |
| ventilation-total-shown | pass | Amber until 24 h with nothing written, the subtab switch refused, Escape restoring, then one update of the periods |
| devices-shown | pass | A gas dryer's gas fields only for a gas dryer; add, edit from Edit and from a row click, delete naming the Set and its Dwellings |
| units-widths-shown | pass | °F and ft³ in IP; 420 and 360 px fit |
| native-undo-redo | pass | Every edit one native Undo step, Redo restores |
| panel-gesture | unknown | Owed to a full-screen hold |
| polish-review | unknown | Host shots recorded; Ed's verdict owed |
