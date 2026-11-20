# PG01: Building Segment membership, bridge rows

DATE: 2026-11-20
STATUS: Bridge rows pass; the native Edit-menu Undo and Redo row is owed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run by the P4a-01 stage on PR [#539](https://github.com/ph-composer/ph-composer-skp/pull/539) head
`53c72dbc`, a branch commit, with SketchUp in the background and no computer-use card. Raw logs stay in
`_private/host/pg01-20261120/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS |
| Build | `dist/ph_composer.rbz` from `53c72dbc`, installed with `make install`; bridge from `make bridge-install` |
| Fixture | A fresh copy of the blank synthetic template; no project data |
| Driver | `tools/examples/authoring/segment_membership_walkthrough.rb`, public API only, panel closed |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG01/walkthrough | Pass | Make Zone joined the default Segment. A second Segment was created, two Zones moved into it, one Zone moved out of every Segment, the second Segment deleted with its Zones moved to none, the last Segment's deletion refused `zone.option_last_segment` with no effect, and one Zone moved back. The read back matched |
| PG01/undo-redo | Pass | Five Undo and five Redo actions sent by the bridge (`editUndo:`, `editRedo:`), one per call. Before each, the Edit menu read the expected step name ("Edit Selected Zones" or "Manage Zone Options"). Each state, read in a separate call, matched |
| PG01/native-undo-redo | Owed | The Edit menu clicked by a native controller needs a computer-use card; it runs in the conductor's batched sitting on the final head |
| PG01/save-reopen | Pass | Saved, quit and reopened in a fresh process; the memberships read back unchanged. Every Face stamp read schema 3 with its Zone's Segment, before the save and after the reopen |
