# Hot water piping

Build Pipe Types, draw pipes as plain SketchUp lines, select them, assign a type and a role. The
exporter measures the lines and builds the honeybee-ph trunk, branch and fixture tree plus the
recirculation loop. New work: the predecessor held this as a 55-line discovery brief, M1.

## Read order

1. [`context/TECH_STACK.md`, "Edge-owned assignments"](../../../../context/TECH_STACK.md#edge-owned-assignments):
   the edge tagging rules, measured and built by Phase 3b. This packet follows them.
2. [PRD.md](PRD.md): what `main` and Phase 3b supply, then the behavior and the decisions.
3. [STATUS.md](STATUS.md).

## What this packet needs from elsewhere

- Phase 3b's edge records and assignment, the chain rule, the stroke weight, the edge tool and an edge
  export contributor with an optional Python section, all on `main` (P3b-03 to P3b-08). The edge tool
  (`features/thermal_bridges/edge_tool.rb`) is the pattern for a pointer route whose
  explicit-reference equivalent is the feature's own assign action.
- The Hot Water System record from [equipment](../equipment/README.md), family 2.
- [metr-export](../../unscheduled/metr-export/README.md) for the diameter enum, the tree rows and
  the recirculation coefficient; acceptance here is HBJSON reloaded in the pinned stack.
- [units](../../cross-phase/units/STATUS.md) Q2 for nominal pipe sizes.

## Scope

In: Pipe Type records, a Piping group for drawn lines, role and type assignment, measured
lengths, the distribution tree, the recirculation loop, a schedule, a Colour-by mode, export to
HBJSON.

Out: hydraulic sizing, fittings, heating and cooling hydronic piping, tanks and heaters (those
belong to [equipment](../equipment/README.md)), a custom pipe drawing tool, METr conversion.
