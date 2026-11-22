# PG07b: Program library kinds, host sitting

DATE: 2026-11-21
STATUS: Both rows pass on the installed RBZ: a copy from a library file with its Schedules and a reusing second copy, and native Edit-menu Undo and Redo of the copy.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the Phase 4a batched host sitting on branch `acceptance/phase-06-sitting` at `08a06474`, with no
computer-use card. The rows were driven by the development bridge, and the native menu presses by System Events.
Raw logs stay in `_private/host/phase06-sitting-20261121/PG07b/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the blank synthetic template, sha256 `2ae1418dddca85afb7c271896a005d14d814df562a231633631ea3ec57121063`, the only document in a fresh process |
| Driver | `tools/examples/library/programs_walkthrough.rb` with the synthetic `tools/examples/library/programs.json`, public API only, panel closed |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG07b/walkthrough | Pass | The file loaded as the Schedules and Programs catalogs. The library Program copied with its two Schedules and became the Model's default in one operation. A second copy reused the Program and both Schedules, with no effect. The walkthrough removed its file provider afterwards; SketchUp's stored provider setup read after the quit no longer lists it |
| PG07b/native-undo-redo | Pass | The Edit menu read "Undo Copy Library Record", since the reusing second copy added no Undo step. One press through System Events removed the copied Program, its two Schedules and the residential default the copy had written, and the residential default was the Model's default again. Edit > Redo restored the copy exactly |

## Limits

- As the offline row expects, the copy first wrote the residential default Program and its six Schedules, then
  the library Program and its two Schedules. One Undo reverts all of it in one step.
