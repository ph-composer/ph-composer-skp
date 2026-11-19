# P5s-03: a Shading Face inside a Zone leaves its envelope

DATE: 2026-11-19
STATUS: Scoped. Not authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P5s-02 and Ed's answer to D5s-11. The only stage that edits `features/zones/`. Zones
reads the foundation check P5s-02 landed and never names Shading. Paths are relative to `src/ph_composer/`. Behavior owner: the [PRD](../PRD.md). Names: [CONTRACTS](../CONTRACTS.md).

## Steps

1. At each call site P5s-01 listed, leave out a Face the exclusion check answers for: the Faces
   export projection and `face.unclassified`, the Face reads and unclassified counts,
   `classify` and `auto_classify`, the Classify tool and `classifiable?`, Solve adjacencies
   and Face splitting, the Face Colour-by modes, the stamp writer. One helper in Zones, used by
   all of them.
2. Explicit targets: `classify` naming an excluded Face refuses with a Zones code that says the
   Face is not part of the Zone's envelope, without saying why.
3. **Clear classification** (D5s-11), if P5s-01 found `classify`'s clear intent does not do it: a
   Zones route that removes a Face record, refusing a Surface-paired Face and an Aperture host. Zones
   owns it; Shading's refusal message points to it.
4. Thermal bridges and Spaces: where either reads a Zone's Faces through Zones, confirm the
   excluded Face is gone from the answer and their findings still hold; change neither feature
   unless a test fails.
5. Fold the rule into `context/CONTRACTS.md`, "Zones geometry rules", and the flag into
   `context/EXTENSIBILITY.md` beside `claims_entity`.

## Tests

One per call site, each with the mark set and cleared; a Zone made inside a marked Group keeps
every Face (D5s-17); the Room of the reference Zone exports
closed with the overhang tagged; a Model with no shading reads and exports byte-identically to
before the stage.

## Done when

SD03 passes. Get the stronger independent review: this stage changes what a Zone's Faces are.
