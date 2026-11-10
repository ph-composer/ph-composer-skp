# SUI-07: native Delete on Volumes, Part 1 experiment

DATE: 2026-11-10
STATUS: Complete. Result: the test failed on Undo, so SUI-07 ships the fallback (Delete Volume menu item, lock kept).
AUTHOR: Claude, conductor session
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/420

## Setup

- SketchUp 26.1.188, Ruby 3.2.2, extension built from `main` at `ddf15ce2` (`make install`, RBZ verified).
- Scratch Model `_private/host/sui07/run.skp`, fresh from the blank template. One Space "Spike" with two
  Volumes, made through `ph_composer.spaces.create` from two separate Faces, then opened.
- The approach under test, as a development eval (`_private/host/sui07/spike.rb`, not shipped): a selection
  observer queues a zero-delay timer, which unlocks each selected Volume in the open Space and relocks the
  others, each write in a transparent operation as `Spaces::Protection` does.
- Native actions through background control: Edit > Delete, Edit > Undo, the Move tool and a viewport drag,
  double-clicks in the viewport, Escape, File > Save. Undo state was read from the Edit menu's item titles
  after each step; Model state through bridge reads in separate calls.

## Observations

| # | Step | Observed |
| --- | --- | --- |
| 1 | Select Volume 1 (bridge selection) | Volume unlocked; Edit menu still read "Undo Open": the unlock joined the previous step and made none of its own |
| 2 | Edit > Delete | Volume erased; the Space record dropped to one Volume; Edit menu read "Undo Erase" |
| 3 | Edit > Undo Erase, once | Volume and record back; Edit menu read "Redo Erase". The Volume came back unlocked and unselected, with `space.volume_unprotected` |
| 4 | Relock the restored Volume (`Protection.protect`), as an implementation must to clear that finding | Locked; Edit menu read a bare "Redo": **Redo Erase was discarded** |
| 5 | With "Redo Move" pending, select the other Volume | The lock toggles discarded Redo (bare "Redo") and the selection came back empty. The same selection with no Redo pending kept the selection |
| 6 | Move tool drag on a selected Volume | Moved; `space.volume_moved` raised; Edit > Undo Move restored it in one step |
| 7 | Double-click a selected Volume, then an unselected one (Select tool) | Each opened the Volume as the edit context, unlocked, the state Edit Floor Surface reaches; Escape closed it and the existing reconciler relocked it |
| 8 | File > Save with a selected, unlocked Volume; quit; reopen | Both Volumes locked after reopening, no findings, positions unchanged |

Not observed: autosave (it fires the same save callbacks, `context/TECH_STACK.md`); a physical Delete key
press (Edit > Delete is the command the key runs under the Select tool).

Pre-existing and out of scope: with a Space open, `Model#modified?` stays true after a plain save, with or
without the experiment's observer.

## Decision

The issue names Undo as the main risk and defines the fallback for a failed test. Rows 3 to 5 fail it: any
lock write is a new operation, so after an Undo it discards Redo, which native selection never does. A
deleted Volume restored by Undo must be relocked, so it could never be redone. SUI-07 therefore ships the
**Delete Volume** menu item and keeps the lock.

Option left for Ed, not measured or built: entering a Space is already an Undo step ("Undo Open"), so
unlocking every Volume on entry and relocking on exit would join steps that already exist and would not
spend Redo on selection. It changes the protection model (inside an open Space every Volume would be
unlocked, so it could be moved, deleted or double-clicked open), so it is his decision; the fallback
does not preclude it.
