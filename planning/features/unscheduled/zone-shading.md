# Zones outside a Building Segment as shading

DATE: 2026-11-15
STATUS: Requested. Brief only; to be fleshed out before it is scheduled.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Why

A Zone may sit outside every Building Segment
([Building Segments PRD](../phase-04a-program/building-segments/PRD.md)). Until this packet lands, export leaves such
a Zone out. Ed wants it to reach WUFI-Passive and METr as shading instead: an accessory structure,
an adjoining building, a neighbouring wing that is not part of the certified envelope but shades it.

## Likely route, to verify

- Write each Face of a no-segment Zone as an orphaned honeybee `Shade` on the Model, not as a Room.
- PHX already reads orphaned Shades: `create_shades.add_hb_model_shades_to_variant` groups them by
  display name, optionally merges coplanar faces, and adds one shading component per group to
  **every** Variant. PHX makes one Variant per Building Segment
  (`create_project.sort_hb_rooms_by_bldg_segment`), so every Segment sees every shade.
- Not checked: what METr does with those components, whether WUFI treats them as shading for
  apertures only or for opaque surfaces too, and which honeybee Shade fields (transmittance
  schedule, reflectance) PHX writes.

## Open questions

| Id | Question |
| --- | --- |
| SH-1 | Does a whole Zone become shading, or only its Faces facing the certified Zones? |
| SH-2 | One shading component per Zone (named for the Zone), or merged? PHX groups by display name |
| SH-3 | Seasonal or partial transmittance (trees, pergolas): in scope, or opaque only? |
| SH-4 | Shading drawn without a Zone (a neighbour's roofline as loose geometry): the same packet or a separate one? |
| SH-5 | Does any certifier review need the shading geometry listed separately in the export report? |
