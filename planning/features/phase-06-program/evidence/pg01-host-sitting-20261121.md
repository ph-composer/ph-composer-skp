# PG01: Building Segment membership, host sitting

DATE: 2026-11-21
STATUS: Every row passes on the installed RBZ, including the native Edit-menu Undo and Redo owed since 2026-11-20.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the Phase 4a batched host sitting on branch `acceptance/phase-06-sitting` at `08a06474`, with no
computer-use card. The rows were driven by the development bridge, and the native menu presses by System Events.
Raw logs stay in `_private/host/phase06-sitting-20261121/PG01/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe`, installed with `make install`; bridge from `make bridge-install` |
| Fixture | A fresh copy of the blank synthetic template, sha256 `2ae1418dddca85afb7c271896a005d14d814df562a231633631ea3ec57121063`, the only document in a fresh process |
| Driver | `tools/examples/authoring/segment_membership_walkthrough.rb`, public API only, panel closed |
| Control | Development bridge, plus System Events pressing the Edit menu item by its full title |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG01/walkthrough | Pass | Make Zone joined the default Segment. The walkthrough then created a second Segment, moved two Zones into it and moved one Zone out of every Segment. It deleted the second Segment with its Zones moved to none, was refused deleting the last Segment (`zone.option_last_segment`, no effect) and moved one Zone back. The read back matched |
| PG01/undo-redo | Pass | Five Undo and five Redo actions sent by the bridge (`editUndo:`, `editRedo:`), one per call. These are not native presses. Each state, read in a separate call, matched |
| PG01/native-undo-redo | Pass | For each press, SketchUp was brought to the front and the document window raised. The Edit menu item read the expected "Undo" or "Redo" plus "Edit Selected Zones" or "Manage Zone Options", and it was then pressed. Five Undos covered the Zone move back, the Segment delete, the move out of every Segment, the move into the second Segment and the Segment create. Five Redos followed. Each state, read through the bridge after the press, matched: undoing the delete restored the Segment with its two Zones, and redoing it moved them to none again |
| PG01/save-reopen | Pass | Saved, quit and reopened in a fresh process, the file unmodified on open. The memberships read back unchanged. Every Face stamp read schema 3 with its Zone's Segment, before the save and after the reopen |

## Limits

- The menu presses use System Events accessibility actions, not pointer clicks on the menu bar.
- At the start of the sitting, two other documents, `pg02.skp` and `pg03.skp`, were open beside the fixture,
  probably restored after the 2026-11-20 launches were quit. The fixture was relaunched as the only document
  before the case began.
