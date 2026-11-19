# P5s-01: contracts and host facts

DATE: 2026-11-19
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires Ed's answers to D5s-07 and D5s-12. Answers what the plan could not read from documents,
names the one foundation addition and corrects CONTRACTS. Ships no user-visible behavior. Paths are relative to `src/ph_composer/`. Behavior owner: the [PRD](../PRD.md). Names: [CONTRACTS](../CONTRACTS.md).

## Steps

1. **Store on three entity kinds.** By focused test against the SketchUp stub: one
   `Records::EntityStore` on `ph_composer.shading` reads, writes and removes the record on a
   Face, a Group and a ComponentInstance, and a read creates no dictionary.
2. **Zone Faces.** Read `features/zones/` and list every place a Zone's Faces are enumerated,
   with file and method, and which Faces count (direct children only, or nested plain Groups too).
   Replace the list in CONTRACTS section 4 with it.
3. **The exclusion flag.** Name the `EntityStore` flag and its class-level check (D5s-12), with
   the inherited case: a Face inside a marked Group. Decide whether the check takes an entity or a
   root path, from what the call sites of step 2 hold. Write it into CONTRACTS section 4. Do not
   build it.
4. **Clear classification.** Whether `faces.classify` with every field cleared returns a Face to
   unclassified (F12).
4a. **Snapshot geometry.** Confirm the Face entry's loops and how the Zone Face projection turns
   them into a holed `Face3D`; confirm hidden and tag-hidden Faces follow the Faces section.
5. **Host run (SD01).** On the pinned SketchUp build, mark a Face, a Group and a ComponentInstance
   by script and run: copy, Move-copy array, cut and paste, Make Group, Make Component, Make
   Unique (and a Face mark attempted behind shared storage, D5s-16), push-pull, Divide of a bounding Edge, intersect across the Face, explode of a marked
   Group. Each with Undo, Redo, save and fresh-process reopen. Record the table in
   `context/SKETCHUP_HOST_BEHAVIOR.md` and correct the PRD's "Copies and edits" to it.
6. **Review.** Architecture review of CONTRACTS as corrected; record it in the evidence file.

## Done when

CONTRACTS section 7 has no open row, section 4 lists call sites from code, and SD01 is recorded.
