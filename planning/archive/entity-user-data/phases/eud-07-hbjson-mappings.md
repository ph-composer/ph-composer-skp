# EUD-07: HBJSON mappings

STATUS: Complete
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-6 ([plan](../PLAN.md#decisions-for-ed))

## Scope

Carry the new maps where an entity has its own HB object, and report the rest.

| Entity | Destination |
| --- | --- |
| Model root | HB `Model.user_data`, beside the reserved `ph_composer` key |
| Space Floor | `SpaceFloor.user_data` |
| Layer | its layer material: the single EnergyMaterial, or the hybrid host when divided |
| Layer-Segment | its cell EnergyMaterial when its Layer is divided |
| Single-segment Layer's Segment, Window Element, Edge, every catalog definition, options, Attached zone | stays local, `export.metadata_omitted` finding (Attached zone gains one) |

## Steps

1. Ruby contributors opt in with `user_data: true` for the carried kinds and add findings for the
   rest, through `export/record_reader.rb`.
2. Python sections (`constructions.py`, the Spaces and model sections) write the maps with
   `with_user_data`, keeping the reserved-key and local-path checks.
3. `make runtime-manifest`; API minor bump if any read shape changes; `make fixtures`.

## Tests to write first

- Export, serialize and reload HBJSON in the pinned stack: each carried map is equal on the
  reloaded object; the reversed construction keeps layer maps on its shared materials.
- Each omitted kind produces exactly one finding per entity carrying a map.
- A reserved `ph_composer` key in a new map blocks the export.

## Done

As EUD-01, with Python tests and the runtime manifest refreshed.
