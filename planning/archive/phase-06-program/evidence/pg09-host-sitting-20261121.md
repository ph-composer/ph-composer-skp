# PG09 host run, sitting 2026-11-21

Installed RBZ sha256 `4f3f3d66…a4cfe` at `08a06474`, SketchUp 26.1.188. Three fresh processes on fresh copies of
the synthetic house (`fdfb756b`), apartments (`0ddf6c71`) and journeys (`218e8347`) references. Offline rows:
[stage evidence](pg09-zones-programs-view-offline.md).

Control: background computer-use `app_*` cannot click or type in the panel's HtmlDialog, so panel input was a
labelled development script event running the page's own handlers, read back through a development callback and
native window pixels. Edit-menu Undo and Redo were pressed natively through System Events, label read first. The
library is the synthetic `tools/examples/library/programs.json`, added for the run and removed after.

| Assertion | Result | Observation |
| --- | --- | --- |
| j1-house-shown | fail | Locked Zones, lock bubble, Open settings, bedrooms and occupants saved, Single dwelling off, Dwelling bubble all work. The house row's only offered Equipment Set, the built-in "Residential default devices", refuses: "equipment_set eqs_PHCDEFAULT01 does not exist"; a stored Set saves |
| j2-apartments-shown | pass | One Dwelling each, bedrooms, Program and Equipment Set from the selection bar, each one Undo step. Note: the heading keeps the house-row Bedrooms input after Single dwelling is off |
| j3-library-shown | pass | A library Program copied with its Schedules on choice, then reused by a second Zone with no second copy |
| j4-non-residential-shown | pass | School Zones read no Dwelling and no Equipment Set; set-point flags on the headings; reassignment one Undo step |
| units-widths-shown | pass | IP headers in ft² and cfm; 420 px with the bar wrapped |
| native-undo-redo | pass | Every cell edit and bar choice one native Undo step, Redo restores |
| panel-gesture | unknown | Owed to a full-screen hold |
| polish-review | unknown | Host shots recorded; Ed's verdict owed |
