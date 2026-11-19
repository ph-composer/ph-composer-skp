# P5s-05: the Shading Colour-by mode

DATE: 2026-11-19
STATUS: Scoped. Authorized 2026-11-19 with every Shading stage ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

## Entry and scope

Requires P5s-02. Owns `features/shading/colour_modes.rb`. Uses the Colour-by contract as it
stands ([contributor architecture](../../../../context/EXTENSIBILITY.md#colour-by-modes)). Paths are relative to `src/ph_composer/`. Behavior owner: the [PRD](../PRD.md). Names: [CONTRACTS](../CONTRACTS.md).

## Steps

1. `feature.colour_mode("ph_composer.shading.by_component", label: "Shading", entity_kind:
   "face")`: one entry per Shading Face occurrence from `reads.rb`, keyed by component name.
2. Legend rows: the name, Face count and area in the display units, through the legend figures
   the thermal-bridge mode already uses.
3. One Model walk per projection; measure the repaint at 5,000 Shading Faces against the 200 ms
   target and record it.
4. Design System re-sync if any CSS changes; none is expected.

## Tests

Entries for direct, inherited, nested and repeated placements; nothing for an unmarked Face; a
mark set or cleared invalidates the projection.

## Done when

SD05 passes on the host.
