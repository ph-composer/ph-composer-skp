# Shading surfaces: PRD

DATE: 2026-11-19
STATUS: Scoped. Interviewed 2026-11-19 (Ed's request and seventeen answers, [DECISIONS](DECISIONS.md)); every stage authorized 2026-11-19 ([STATUS](STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

## Why

A Passive House model needs the surfaces that shade the building: neighbouring buildings,
overhangs, fins, parapets, site walls. WUFI-Passive and METr compute shading from opaque
components that belong to no zone. PH-Composer has no way to say "this geometry is shading", so a
user adds it by hand after export.

## What it is

The user selects Faces or Groups, right-clicks and chooses **Set as Shading**. On export each
tagged Face leaves as a honeybee orphaned `Shade`, which PHX already turns into a shading component
in WUFI-Passive and METr ([research](research/honeybee-ph-and-phx-shading.md)).

This packet tags and passes geometry along. It runs no solar, shading-factor or shading-dimension
calculation and writes nothing on any Aperture.

## Terms

| Term | Meaning |
| --- | --- |
| Shading mark | The record that says an entity is shading. It sits on a Face, a Group or a ComponentInstance and carries no values |
| Shading Face | A Face that carries the mark, or sits at any depth inside a Group or ComponentInstance that carries it |
| Shading component | The Shading Faces that export under one name. One component in WUFI-Passive and METr |

These go into `context/UBIQUITOUS_LANGUAGE.md` when the feature lands.

## Behavior

### Tag and clear

- **Set as Shading** and **Clear Shading** sit in the PH-Composer right-click menu and in
  Extensions > PH-Composer. They apply to the Faces, Groups and ComponentInstances in the native
  selection; Edges and other entities in it are ignored.
- Each choice is one Undo step, made through a registered action, so the panel-closed script route
  and an agent reach the same behavior with explicit targets.
- A mixed selection applies to what it can and names what it left out and why, in the session
  notice and the status bar. It refuses only when nothing in the selection can take the mark.
- Tagging a tagged entity and clearing an untagged one change nothing and say so.
- Clear removes the mark from the selected entity only. A Face that is shading through its Group
  stays shading; the message names the Group to clear.
- A Face behind shared storage (inside a Component placed more than once, or a copied Group not
  yet made unique) is not tagged on its own: the message says to tag the Component or Group
  instead (D5s-16).

### What can be tagged

| Target | Result |
| --- | --- |
| A loose Face, at the Model root or inside a plain Group or a Component placed once | Tagged |
| A Face behind shared storage | Refused with the foundation's `target.shared_definition`: tag the Component or Group |
| A plain Group or ComponentInstance, at the root or nested, inside a Zone or not | Tagged; every Face inside it, at any depth, is a Shading Face |
| A Face inside a Zone that has no classification | Tagged. It leaves the Zone's envelope: it is not an unclassified Face, takes no Face type, and is not part of the Room |
| A Face inside a Zone that is classified | Refused: clear its classification first (D5s-11) |
| A Group that is a Zone, or holds one at any depth | Refused. A whole Zone as shading is the [zone-shading brief](../unscheduled/zone-shading.md) |
| A Space, Volume or Floor Segment, a Window Unit, a pane Face, anything inside them | Refused: another feature owns the entity |
| A Face inside a cutting component | Refused: export does not read those Faces |
| Anything behind a locked Group or instance | Refused with the foundation's `target.locked` |

A mark never reaches through a Zone or another feature's entity. If a marked Group later comes to
hold a Zone (Make Zone inside it, or a paste), the Zone and its Faces stay envelope, the Group's
other Faces stay shading, and the preflight says so in a note (D5s-17). The same holds for a Space
or a Window Unit inside a marked Group.

### Names

PHX makes one shading component per Shade `display_name`, so the name decides how shading is
grouped in WUFI-Passive and METr. PH-Composer derives it and asks the user nothing:

1. The name of the nearest enclosing Group or ComponentInstance that has one (an instance's own
   name, otherwise its definition's name), walking outward from the Face.
2. If that container is a Zone, the name is the Zone's name followed by " Shading".
3. With no named container, the name is "Shading".

Two Groups with the same name export as one component. That is the user's lever for merging, and
renaming a Group is the lever for splitting.

### Seeing what is tagged

- A **Shading** Colour-by mode colours every Shading Face, direct or through its container, and
  leaves everything else in the no-value colour. Its legend lists each shading component with its
  Face count and area.
- The export report has a Shading section: each component's name, Face count and area, and the
  totals.
- No panel tab. The record has no values to edit.

### Copies and edits

The mark has no identity, so nothing needs repair. A copied, arrayed, split, pasted or
push-pulled entity keeps or loses the mark as SketchUp carries the attribute dictionary; the
stage-one host run measures each case and the result is recorded in
`context/SKETCHUP_HOST_BEHAVIOR.md`. Exploding a tagged Group removes the Group and its mark with
it; the Faces stop being shading unless they are tagged themselves. PH-Composer does not watch for
that.

### Export

- One optional translation section writes one honeybee `Shade` per Shading Face occurrence, with
  `is_detached: true`, the derived `display_name`, world SI geometry and no energy or PH values.
  They join the Model as orphaned Shades.
- Shading never blocks export. A Face that cannot become a Shade is left out with a note in the
  preflight and the report.
- A Face with an inner loop exports as honeybee writes a holed `Face3D`.
- PHX gives every Building Segment's file all of the Model's shading.
- Shading is opaque. No transmittance, reflectance or schedule is stored or written.

## Out of scope

- Shading factors, shading dimensions, Radiance or any other solver, and the per-Aperture values
  they write.
- A whole Zone as shading, and Zones outside every Building Segment
  ([brief](../unscheduled/zone-shading.md)). This packet answers that brief's SH-3 (opaque only)
  and SH-4 (loose geometry is this packet); SH-1, SH-2 and SH-5 stay with it. Its export would
  reuse this packet's section.
- Window shades and blinds (`PhxWindowShade`), which belong to Window Types.
- A Shading panel tab, a tagging tool with a cursor, user-typed component names.
- Sun-path and overlay views ([post-MVP](../phase-08-post-mvp/README.md)).

## Acceptance shape

1. Loose Faces, a nested Group, three placements of a Component and an overhang Face inside a Zone
   are tagged from the right-click menu; each tag is one Undo step and Redo restores it.
2. The Zone with the tagged overhang Face has no unclassified-Face finding and its Room closes as
   before.
3. Every refusal in "What can be tagged" names its reason and writes nothing.
4. The Shading Colour-by mode shows exactly the tagged geometry, nested and repeated placements
   included.
5. The exported HBJSON reloads with one orphaned Shade per Shading Face occurrence, named by the
   rule above, `is_detached` true.
6. The pinned PHX converts that HBJSON to WUFI XML and METr JSON with one shading component per
   name, `InnerAttachment` and `idIC` both -1.
7. Ed opens the WUFI XML in WUFI-Passive and the METr JSON in METr and sees the shading where it
   was drawn.
