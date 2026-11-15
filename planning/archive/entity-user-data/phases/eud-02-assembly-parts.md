# EUD-02: Assembly Layers and Layer-Segments

STATUS: Complete
ISSUE: [#507](https://github.com/ph-composer/ph-composer-skp/issues/507)
DECISIONS: D-UD-3, D-UD-4 ([plan](../PLAN.md#decisions-for-ed))

## Scope

Give Layers and Layer-Segments an optional `user_data` map and make it writable through the
EUD-01 action by part address. Every Assembly path keeps it.

## Steps

1. `Records::RecordKind` gains an optional `parts:` declaration: name, JSON path (`layers[]`,
   `layers[].segments[]`) and id key. The engine exposes part lookup by id path. Kinds without
   parts are unchanged.
2. `features/assemblies/assembly/schema.rb`: optional `user_data` on `LAYER` and `SEGMENT`,
   validated with `Records::JsonValue`; schema version stays 1 (D-UD-4). `Schema.layer` and
   `Schema.segment` create parts without a map.
3. `ph_composer.records.update_metadata` accepts `part_ids` in its reference. An unknown part id
   refuses `target.not_found`; `expected_metadata` compares the part's own map. Parts carry no
   `extension_data` in this packet; a payload on a part refuses `params.invalid`.
4. Check every Assembly gesture in `features/assemblies/commands/` (change, layers, assembly,
   material), `duplicate_assembly_values` (new ids, maps copied) and library replace. Fix any path
   that rebuilds a part from scratch.
5. API minor bump, `make fixtures`, agent guide line.

## Tests to write first

Extend the Assembly operation tests rather than adding a framework:

- Write, read back and clear a Layer map and a Layer-Segment map by id path.
- Reorder Layers, add and remove a Layer-Segment, change thickness and Material, flip
  orientation: each surviving part keeps its map; a new part has none.
- Duplicate an Assembly: new part ids, equal and independent maps.
- An Assembly record stored without part maps reads and validates unchanged.

## Done

As EUD-01, with the architecture review on the `RecordKind` change.
