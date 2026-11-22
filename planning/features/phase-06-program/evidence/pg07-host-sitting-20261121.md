# PG07: Program, Schedule and Equipment Set records, host sitting

DATE: 2026-11-21
STATUS: Every row passes on the installed RBZ: the panel-closed walkthrough, native Edit-menu Undo and Redo of each step, and save and fresh-process reopen.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the Phase 4a batched host sitting on branch `acceptance/phase-06-sitting` at `08a06474`, with no
computer-use card. The rows were driven by the development bridge, and the native menu presses by System Events.
Raw logs stay in `_private/host/phase06-sitting-20261121/PG07/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the blank synthetic template, sha256 `2ae1418dddca85afb7c271896a005d14d814df562a231633631ea3ec57121063`, the only document in a fresh process |
| Driver | `tools/examples/programs/program_records_walkthrough.rb`, registered operations only, panel closed |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG07/walkthrough | Pass | The residential default Program, its six Schedules and the default Equipment Set read unwritten. The walkthrough then made seven writes: a Schedule, a Program, an edit of the default (written with its Schedules in one step), a device on the default Set, the new Program made the default, a delete of the residential default and its reset. Each write committed, and the verify passed |
| PG07/native-undo-redo | Pass | Seven Edit > Undo presses through System Events, newest first. Each read the expected step before the press: Reset to PH-Composer Default, Delete Program, Change Programs Defaults, Add Device, Edit Program, Create Program and Create Schedule. Every press changed the records, and after the seventh they matched the start, with the default unwritten again. Seven Redo presses then restored each state in turn, and the verify passed |
| PG07/save-reopen | Pass | Saved, quit and reopened in a fresh process, the file unmodified on open. The records read the same, and the verify passed |
