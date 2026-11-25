# User data on every object

Each object you author in PH-Composer carries `user_data`: a JSON object for your own notes, review
states, specification references or outside ids. PH-Composer stores it, copies it with the object
and keeps it through save and reopen. No calculation reads it. Step 9 of the
[API quickstart](API_QUICKSTART.md#9-attach-your-own-data-to-a-face-and-a-material) is the worked
recipe. This page lists where each object's map is read and written and what happens to it on copy
and export.

## The rules every object follows

- Put your data under one top-level key you own, such as `{"example_org": {"review_status": "checked"}}`.
  Keys are strings. Values are nested objects, arrays, strings, finite numbers, `true`, `false` or
  `null`. A key named `ph_composer` blocks any export that carries the map.
- A write sends the whole map and replaces what is stored. Read the map, change your own key and
  send the result, so other keys stay. `{}` clears the map. An update that leaves `user_data` out
  leaves it as it is.
- Each write takes `expected_metadata`: the `user_data` and `extension_data` you last read. If either
  changed since, the write refuses `target.changed` and nothing is written.
- A batch of `updates` is one Undo step and is written whole or not at all. A batch that sends what
  is already stored makes no Undo step.
- A read answers a copy. Changing the hash or object you hold changes nothing in the Model.
- A map larger than one reply reads in parts: the list's `metadata` `"summary"` gives its size, and
  the matching detail read returns it in fragments, as the [agent guide](AGENT_GUIDE.md#large-records-and-previews)
  describes.
- An edit that sends a definition's parts, such as a Window Type's whole `elements` array, keeps each
  surviving part's map by its id whether or not it sends it. A new part starts without one, and a map
  that differs from the stored one refuses `params.invalid`: write it with the core action.
- Deleting a Material, Assembly, Frame, Glazing, Psi-Install Type, Window Type, Thermal Bridge Type,
  Ventilator or Attached zone returns `removed_user_data`: the record, then each part by `part_ids`,
  whose map was not empty, with its top-level keys. The report fits one reply: the first 50 maps, each
  with its key total, and as many of their first 50 keys as fit in 8 KiB, with
  `removed_user_data_total` and `removed_user_data_truncated`, true when a map or a key was left out.
  Merges report the same way. A replacement keeps its own map, and Undo restores the removed ones.
- An older Model with no stored map reads `{}` and is not rewritten by the read.
- Over the API, params that are not plain JSON (`NaN`, `Infinity`, a key that is not a string)
  refuse `request.malformed` before any operation runs, and the sequence stays free for the
  corrected request. A map of the wrong type, such as text in place of an object, refuses
  `params.invalid`. That refusal comes after the request is accepted, so it uses up its sequence:
  send the corrected request with the next one.

`extension_data` is a separate, typed route for maintained extensions, with schema versions and
declared references. You do not need it for your own data. A record that an extension payload names,
on another record or on the Model, cannot be deleted while the payload names it.

## Coverage

"Owner action" is `update_metadata` on the object's own feature, such as
`ph_composer.zones.faces.update_metadata`. "Core action" is `ph_composer.records.update_metadata`,
which writes every definition kind by `{kind, id}` and a nested part by adding `part_ids`, the ids
from the record down. "Omitted" means the map stays in the Model and the export lists one
`export.metadata_omitted` finding for that object.

| Object | Address | Read | Write | Copies, splits and merges | HBJSON export | Library file |
| --- | --- | --- | --- | --- | --- | --- |
| Model | none, one per Model | `ph_composer.model.detail`, `ph_composer.model.fragment` | `ph_composer.model.update_metadata` | Not copied | The HBJSON Model's `user_data` | Not a library kind |
| Material | `{kind: "ph_composer.assemblies.material", id}` | `ph_composer.assemblies.materials.list`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map | Omitted | Not in the wire row; replace keeps the local map |
| Assembly | `{kind: "ph_composer.assemblies.assembly", id}` | `ph_composer.assemblies.assemblies.list`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map and every part's map | Its construction, and the reversed copy | Not a library kind |
| Layer | Assembly address with `part_ids: [layer id]` | The Assembly's `values.layers` in `ph_composer.records.list` or `ph_composer.records.detail` | Core action with `part_ids` | Edits keep it; a new Layer starts empty; Duplicate copies it under a new id | Its material, the hybrid material when divided; a membrane Layer is omitted | Not a library kind |
| Layer-Segment | Assembly address with `part_ids: [layer id, segment id]` | `ph_composer.assemblies.assemblies.segments.list` | Core action with `part_ids` | As for a Layer | Its cell material when the Layer is divided and not a membrane; otherwise omitted | Not a library kind |
| Frame, Glazing, Psi-Install Type | `{kind: "ph_composer.windows.frame", id}`, `glazing`, `psi_install_type` | `ph_composer.windows.frames.list` and its siblings, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map | Omitted | Not in the wire row; replace keeps the local map |
| Window Type | `{kind: "ph_composer.windows.window_type", id}` | `ph_composer.windows.types.list`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map and each element's map | Omitted | Not a library kind |
| Window Element | Window Type address with `part_ids: [element id]` | `ph_composer.windows.types.elements.list` | Core action with `part_ids` | Split copies the map into each piece; merge keeps the top-left element's map and lists the others' keys in `removed_user_data`; an inserted element starts empty; an update sending the whole `elements` array keeps each map | Omitted | Not a library kind |
| Window Unit | the row's `reference` | `ph_composer.windows.units.list`, `ph_composer.windows.units.detail` | Owner action; place takes `user_data` | Swap and flip keep it; a Unit restored from orphaned panes, or converted from a plain component, starts empty | Each of its Apertures | Not a library kind |
| Zone | the row's `reference` | `ph_composer.zones.list` | Owner action | Restore cannot recover it and says so in its offer | Its Room | Not a library kind |
| Face | the row's `reference` | `ph_composer.zones.faces.list` | Owner action, once the Face has a record | An adjacency split copies the map to each piece | Its Face | Not a library kind |
| Attached zone | `{kind: "ph_composer.zones.faces.attached_zone", id}` | `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map | Omitted | Not a library kind |
| Building Segment, Level | `{kind: "ph_composer.zones.building_segment", id}`, `level` | `ph_composer.zones.options.list`, `ph_composer.zones.options.detail` | Core action; for a Level it also updates each Zone's copy in the same step; create takes `user_data` | Merge and remove keep the survivor's map and list the removed options' keys in `removed_user_data` | Omitted, whether a Zone uses the option or not | Not a library kind |
| Space, Volume, Floor Segment | the row's `reference` | `ph_composer.spaces.list`, `ph_composer.spaces.volumes.list`, `ph_composer.spaces.floor_segments.list`, `ph_composer.spaces.detail` | `ph_composer.spaces.update_metadata` | Copies keep the map | Space, SpaceVolume and SpaceFloorSegment | Not a library kind |
| Space Floor | the Volume row's `floor.reference` | `ph_composer.spaces.volumes.list` with `fields` naming `floor` | `ph_composer.spaces.update_metadata` | Travels with its Volume | Its SpaceFloor | Not a library kind |
| Thermal Bridge Type | `{kind: "ph_composer.thermal_bridges.type", id}` | `ph_composer.thermal_bridges.types.list`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map | Omitted | Not a library kind |
| Thermal Bridge Edge | the Edge row's `reference` | `ph_composer.thermal_bridges.edges.selection`, `selection_all`, `at`, `candidates`, `edges.detail` | Owner action, once the Edge has an assignment | A split or copied Edge keeps a copy on each piece, written separately by path; reassigning keeps it; repair removes it and lists its keys | Omitted, since a run joins several Edges | Not a library kind |
| Shading mark | The marked entity's `entity_path` from the Model root; the mark has no id | Not returned: `ph_composer.shading.list` names marked entities without their maps | No action writes it: Set as Shading and `ph_composer.shading.assign` write the mark without a map, and an entity already marked is left unchanged | Copy, paste, cut and Make Unique carry the mark and its map with the entity; Intersect Faces gives each half a copy; Explode of a marked Group removes it | Omitted: each Shading Face is written as a Shade, and the map stays in the Model | Not a library kind |
| Program, Schedule | `{kind: "ph_composer.programs.program", id}`, `schedule` | `ph_composer.programs.programs.all`, `ph_composer.programs.schedules.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map | Omitted: a Program is written as one or more ProgramTypes and a Schedule as a ScheduleRuleset, and the map stays in the Model | Not in the wire row |
| Equipment Set, device | `{kind: "ph_composer.programs.equipment_set", id}`; a device adds `part_ids: [device id]` | `ph_composer.programs.equipment_sets.all`, `ph_composer.records.list` | Core action, with `part_ids` for a device | Duplicate copies the Set's map and gives each device a new id with its map | Omitted: each device is written as a honeybee-ph device on a Room, once per Dwelling, and its map stays in the Model | Not in the wire row; replace keeps each matching device's map |
| Dwelling | `{kind: "ph_composer.programs.dwelling", id}` | `ph_composer.programs.dwellings.all`, `ph_composer.records.list` | Core action | Duplicate copies the map; a Dwelling deleted when its last Zone leaves lists it in `removed_user_data` | Omitted: a Dwelling is written as the shared dwelling on its Rooms' People, which holds no map | Not a library kind |
| Climate | `{kind: "ph_composer.climate.climate", id: "clm_AAAAAAAAAAAA"}`, one per Model | `ph_composer.records.detail`, `ph_composer.records.list` | Core action | Editing and restoring the values keep it, and so does replacing the station; Clear deletes it with the climate, and Undo brings it back | Omitted: the climate is written as the Building Segments' `Site`, and its map stays in the Model | Not a library kind |
| Ventilator | `{kind: "ph_composer.mechanical.ventilator", id}` | `ph_composer.mechanical.ventilators.list`, `ph_composer.mechanical.ventilators.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; what serves a Zone is stored on the Zone and keeps no map of its own | Its `Ventilator` object, inside the ventilation system of every Room it serves. A Ventilator that serves no exported Zone is not written, and its map stays in the Model | Not a library kind |
| Hot Water System | `{kind: "ph_composer.mechanical.hot_water_system", id}` | `ph_composer.mechanical.hot_water_systems.list`, `ph_composer.mechanical.hot_water_systems.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map | Omitted: honeybee-ph's hot water system holds no map, so the export notes `export.metadata_omitted` and the map stays in the Model | Not a library kind |
| Heat Pump Outdoor Equipment, Indoor Equipment, Outdoor Unit, Indoor Unit | `{kind: "ph_composer.mechanical.hp_outdoor_equipment", id}`, `hp_indoor_equipment`, `hp_outdoor_unit`, `hp_indoor_unit` | `ph_composer.mechanical.heat_pumps.outdoor_equipment.list` and the other three `list` reads, their `all` reads, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; a delete with a replacement moves what names the record and keeps those records' maps | Omitted: each Building Segment exports one blended heat pump built from several records, so no record has an object of its own; the export notes `export.metadata_omitted` for those it reads and the maps stay in the Model | Not a library kind |
| Hot Water Heater, Hot Water Tank | `{kind: "ph_composer.mechanical.hot_water_heater", id}`, `hot_water_tank` | `ph_composer.mechanical.hot_water_heaters.list`, `ph_composer.mechanical.hot_water_tanks.list`, their `all` reads, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; a System's delete with a replacement moves them and keeps their maps | Its heater or tank object, inside the hot water system of every Room its System serves. One whose System serves no exported Zone, or a Tank with no free slot, is not written, and its map stays in the Model | Not a library kind |
| Pump | `{kind: "ph_composer.mechanical.pump", id}` | `ph_composer.mechanical.pumps.list`, `ph_composer.mechanical.pumps.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; a delete returns it in `removed_user_data` | Its supportive device on every Room it serves. One that serves no exported Zone is not written, and its map stays in the Model | Not a library kind |
| Fan | `{kind: "ph_composer.mechanical.fan", id}` | `ph_composer.mechanical.fans.list`, `ph_composer.mechanical.fans.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; a delete returns it in `removed_user_data` | Its exhaust ventilator on every Room it serves, and its supportive device there when it has Power. One that serves no exported Zone is not written, and its map stays in the Model | Not a library kind |
| Electric Heater | `{kind: "ph_composer.mechanical.electric_heater", id}` | `ph_composer.mechanical.electric_heaters.list`, `ph_composer.mechanical.electric_heaters.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; a delete returns it in `removed_user_data` | Its direct electric heating system on every Room it serves. One that serves no exported Zone is not written, and its map stays in the Model | Not a library kind |
| Pipe Type | `{kind: "ph_composer.piping.pipe_type", id}` | `ph_composer.piping.pipe_types.list`, `ph_composer.piping.pipe_types.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; a delete reports its keys and their count in `removed_user_data`, and Undo restores the map | Omitted: each pipe segment carries its pipe's map, not its type's | Not a library kind |
| Piping group and pipe | A Piping group or pipe reference, as `ph_composer.piping.groups.list` and `ph_composer.piping.pipes.selection` give them | Not yet; their records hold an empty map | Not yet | A pasted group or a split or copied line carries its map with the record; giving a pipe a new role or type keeps it | A pipe's map is its segment's `user_data`; a Piping group's is omitted | Not a library kind |
| Duct Type | `{kind: "ph_composer.ducting.duct_type", id}` | `ph_composer.ducting.duct_types.list`, `ph_composer.ducting.duct_types.all`, `ph_composer.records.list` | Core action; create takes `user_data` | Duplicate copies the map; a delete reports its keys and their count in `removed_user_data`, and Undo restores the map | Omitted with `export.metadata_omitted`: each duct segment carries its duct's map, not its type's | Not a library kind |
| Ducting group and duct | A Ducting group or duct reference, as `ph_composer.ducting.groups.list` and `ph_composer.ducting.ducts.selection` give them | Not yet; their records hold an empty map | Not yet | A pasted group or a split or copied line carries its map with the record; giving a duct a new type, direction or quantity keeps it | A duct's map is its segment's `user_data`, on every element a quantity above 1 writes; a Ducting group's is omitted | Not a library kind |

Definitions and Attached zones are records stored in the Model. Zones, Faces, Window Units, Spaces,
Thermal Bridge Edge assignments and shading marks are stored on their SketchUp entities, so a copy made in
SketchUp carries the map with the entity. The Model's map is stored in the Model's own settings.

Zones, Faces, Spaces and Thermal Bridge Edges take no `user_data` when you create them. Create the
object, then call its owner action. A Face takes a map once it has a record, which classifying it
or assigning an Assembly gives it. An Edge takes one once it has a Thermal Bridge Type assigned.

An `export.metadata_omitted` finding about a Layer, Layer-Segment or Window Element names the part
in `object_id` and carries `reference`, the `{kind, id, part_ids}` the core action takes. The
[agent guide](AGENT_GUIDE.md#export) explains the other export findings.

## Library files

Library files carry the provider's data only. A wire row for a Material, Frame, Glazing or
Psi-Install Type has no `user_data` or `extension_data`. Copying a row into the Model starts its
map empty, replacing a local record from the library keeps the local map, and a library export
lists each map it leaves out. See the [library file format](LIBRARY_FILE_FORMAT.md).

## Objects without a map of their own

These hold data PH-Composer derives or uses internally, so they take no `user_data`: Zone
membership stamps on Faces, Zone option settings, the Windows, Spaces and Zones settings, the
Window definitions and panes PH-Composer generates, thermal-bridge runs (calculated from Edges),
the site and design temperatures (Model settings), the Programs settings stored on Zones and
Building Segments (assignments, Single dwelling, Phius certification and airtightness), what serves
each Zone (its Ventilator, Hot Water System, heat pump indoor units, Electric Heaters, Pumps and Fans, stored on the Zone, whose map is the Zone's own), a Building Segment's mechanical settings (stored on the Segment, whose map is the Segment's own), the blended heat pump of each Building Segment (worked out from the heat pump records), pipe runs and duct runs (worked out from the Pipes and Ducts), the export snapshot, and
library provider, connection and agent-access state.

The climate data folders are kept on this computer, not in a Model: in PH-Composer's settings file,
`~/Library/Application Support/PH-Composer/settings.json`, outside SketchUp's own folders. The file
holds each folder's name and location. The location is never written to a Model, an HBJSON file or
the Export report.

The [core contracts](../context/CONTRACTS.md#records-and-extension-data) own these rules for
engineers. The [contributor architecture](../context/EXTENSIBILITY.md#metadata-and-structured-extension-data)
requires every new object a contribution adds to meet them.
