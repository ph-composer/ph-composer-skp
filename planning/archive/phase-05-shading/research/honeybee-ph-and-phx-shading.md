# What honeybee-ph and PHX expect of shading surfaces

DATE: 2026-11-19
STATUS: Complete. Research for the [shading PRD](../PRD.md); no code changed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

Read against the pins in `pyproject.toml`: honeybee-core 1.64.65 and honeybee-ph 1.33.65 (the
vendored wheels) and PHX 1.57.5 (the optional `phx` group; PHX is not shipped). The PHX files cited
below are unchanged between the `v1.57.5` tag and the local checkout at `v1.59.1`. Every behavior
marked *run* was observed in one scratch round trip on those versions: a Room and five orphaned
Shades, through `Model.to_dict`, `Model.from_dict`, `convert_hb_model_to_PhxProject`, the WUFI XML
builder and the METr JSON builder; and a second with two Building Segments and spaced names.

## The contract PHX reads

PHX reads one thing: the Model's **orphaned Shades** (`Model.orphaned_shades`, honeybee `Shade`
objects with `Face3D` geometry). `PHX/from_HBJSON/create_shades.py`:

| Step | Behavior |
| --- | --- |
| Source | `_hb_model.orphaned_shades` only. Shades attached to a Room, Face or Aperture (`outdoor_shades`) and `ShadeMesh` objects are never read |
| Grouping | Shades are grouped by `display_name`. Each group becomes one `PhxComponentOpaque`, named for the group, holding one polygon per Shade |
| Unnamed Shade | honeybee falls back to the identifier, so every unnamed Shade is its own component (*run*: `shd_c` and `shd_d` came out as two components) |
| Merge | With face merging on, coplanar touching Shades in one group merge into one polygon (*run*: two 2 m squares sharing an edge became one four-vertex polygon). `_merge_faces` is the converter's own argument, shared with the Rooms |
| Component values | `face_opacity` opaque, `exposure_exterior` exterior (`-1`), `exposure_interior` `-1`, no assembly (`-1`), wall colour on both sides |
| What marks it as shading | `PhxComponentOpaque.is_shade`: opaque and `exposure_interior == -1`. Nothing else |
| Variants | `create_project.py` adds every shade component to **every** Variant. PHX makes one Variant per Building Segment, so each Segment's file carries all of the shading (*run*: two Segments, each Variant held all three components) |
| Names | A name with spaces, a slash and a `#` passes through grouping, merge, WUFI XML and METr JSON unchanged (*run*) |

PHX reads nothing else from the Shade. `is_detached`, the energy properties (construction,
transmittance schedule) and `ShadePhProperties` (one field, `id_num`) do not reach WUFI-Passive or
METr. Shading is opaque: there is no route for a partial or seasonal transmittance.

## What reaches the two files (*run*)

WUFI XML, one `Component` per name group:

```xml
<Name>Neighbour</Name> <Type>1</Type>
<InnerAttachment>-1</InnerAttachment> <OuterAttachment>-1</OuterAttachment>
<IdentNrAssembly>-1</IdentNrAssembly> <IdentNrWindowType>-1</IdentNrWindowType>
<IdentNrPolygons count="1">…</IdentNrPolygons>
```

METr JSON, the same component: `{"n": "Neighbour", "idIC": -1, "idEC": -1, "typeC": 1,
"areaC": 8.0, "idAssC": -1}`. METr carries shading as PHX writes it for WUFI-Passive; this closes the
"not checked" line in the [zone-shading brief](../../../features/unscheduled/zone-shading.md).

## What the Grasshopper route writes

| Question | Answer | Source |
| --- | --- | --- |
| How does a user make site shading? | Ladybug Tools' own `HB Shade` component, added to the Model as orphaned Shades. honeybee-ph adds no shading-surface component of its own | `honeybee-grasshopper-core`, `HB Shade.py` |
| `is_detached` | `True` unless the user sets `attached_`. honeybee-core's own constructor default is `False` (*run*) | `HB Shade.py`, line 105 |
| Shade properties | `energy` and `ph` blocks at their defaults; `ShadePhProperties.id_num` 0 | `honeybee_ph/properties/shade.py` |
| `HBPH - Create Building Shading` | Not a tagging route. It returns Rhino geometry (punched envelope Faces and window reveals) as input for the shading-factor solvers | `shade_create_bldg_shd.py` |
| Shading factors, shading dimensions, LBT Radiance | Solvers that write per-Aperture results. Outside this packet by Ed's scope | `gh_compo_io/shading/`, `apertures/win_set_*` |

## Consequences for PH-Composer

1. The export writes honeybee `Shade` objects with `Model.add_shade`, at the `MODEL` attachment
   host. Nothing attaches to a Room, Face or Aperture.
2. Every Shade needs a `display_name`: it is the name of the component in WUFI-Passive and METr, and
   Shades sharing one become one component. Writing none gives one component per Face.
3. `is_detached: true` matches what a Grasshopper-built Model carries.
4. Nothing beyond geometry and the name is worth storing: PHX drops everything else.
5. A Face with an inner loop exports as one polygon whose vertex list bridges to the hole (*run*:
   ten vertices, the net area 32 m2 of a 36 m2 Face with a 4 m2 hole). What WUFI-Passive and METr
   do with a bridged polygon was not observed; it is an acceptance row, not a refusal.
6. A shade is double-sided to the receiving program: PHX writes no orientation-dependent value, so
   the SketchUp Face's front and back do not matter.

## Not checked

- Whether WUFI-Passive shades opaque components as well as windows with these surfaces. PHX writes
  the same component either way.
- How WUFI-Passive draws or meshes a bridged (holed) polygon.
- The upper bound on shading polygons WUFI-Passive's shading calculation handles in reasonable time.
