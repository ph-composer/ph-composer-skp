# EUD-09: native acceptance

STATUS: Complete
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)

## Scope

UD-07 on the head that goes to merge, after the last review fix. Follow the native acceptance
skill; synthetic fixtures only.

## Cases

1. Script, panel closed: write maps on a Material, an Assembly Layer-Segment, a Window Element, a
   Face, a Level, an Edge, a Space Floor and the Model. One Undo reverts the batch; Redo restores it.
2. Save, quit, fresh process, reopen: every map reads back equal.
3. Copy and paste a Zone with Faces, Window Units, Spaces and Edges into the same Model and into a
   second Model (adoption): copies are independent and options adopt with their maps.
4. Export: the reloaded HBJSON matches EUD-07's table.

## Mechanics

The stage subagent prepares the fixture, the bridge script and the recipe, then reports
"ready for hold". The conductor runs the full-screen steps (Undo, Redo, copy and paste) under one
hold and records ledger receipts during the run.

## Done

Every case recorded `Pass` in the native case ledger with receipts, or the failing case reported.
