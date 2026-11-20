# Zones outside a Building Segment as shading

DATE: 2026-11-15, amended 2026-11-19
STATUS: Requested. Brief only; to be fleshed out before it is scheduled. SH-3 and SH-4 closed by
[Phase 5: shading](../../archive/phase-05-shading/README.md) on 2026-11-19.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Why

A Zone may sit outside every Building Segment
([Building Segments PRD](../phase-06-program/building-segments/PRD.md)). Until this packet lands, export leaves such
a Zone out. Ed wants it to reach WUFI-Passive and METr as shading instead: an accessory structure,
an adjoining building, a neighbouring wing that is not part of the certified envelope but shades it.

## Likely route, to verify

- Write each Face of a no-segment Zone as an orphaned honeybee `Shade` on the Model, not as a Room, through
  Phase 5's Shades section, `ph_composer.shading.export.shades` (context/CONTRACTS.md, "The shading mark"
  and "Translation sections and artifacts"). That section already writes one
  detached `Shade` per Face occurrence with its component name, so this packet would add records to it
  rather than a second writer.
- PHX already reads orphaned Shades: `create_shades.add_hb_model_shades_to_variant` groups them by
  display name, optionally merges coplanar faces, and adds one shading component per group to
  **every** Variant. PHX makes one Variant per Building Segment
  (`create_project.sort_hb_rooms_by_bldg_segment`), so every Segment sees every shade.
- METr carries the components as PHX writes them for WUFI-Passive, `idIC` -1
  ([Phase 5 research](../../archive/phase-05-shading/research/honeybee-ph-and-phx-shading.md)). PHX writes no
  transmittance schedule or reflectance, and Phase 5 stores none (SH-3 below).
- Ed, 2026-11-20, in WUFI-Passive: probably apertures only; opaque surfaces keep their own shading factor,
  which these components are not believed to change. Not confirmed by a calculation
  ([Phase 5 research](../../archive/phase-05-shading/research/honeybee-ph-and-phx-shading.md#answered-by-ed-in-wufi-passive-2026-11-20)).

## Open questions

| Id | Question |
| --- | --- |
| SH-1 | Does a whole Zone become shading, or only its Faces facing the certified Zones? |
| SH-2 | One shading component per Zone (named for the Zone), or merged? PHX groups by display name |
| SH-3 | Closed 2026-11-19: opaque only. Phase 5 stores and writes no transmittance, reflectance or schedule ([PRD](../../archive/phase-05-shading/PRD.md), "Export") |
| SH-4 | Closed 2026-11-19: loose geometry is Phase 5, tagged from the right-click menu (D5s-01, D5s-05 in [its decisions](../../archive/phase-05-shading/DECISIONS.md)) |
| SH-5 | Does any certifier review need the shading geometry listed separately in the export report? |
