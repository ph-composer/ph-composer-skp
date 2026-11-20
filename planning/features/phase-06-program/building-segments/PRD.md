# Building Segments: membership, management and settings

DATE: 2026-11-15
STATUS: Scoped. Interviewed 2026-11-15 (BS-1 to BS-6 answered, below); revised the same day after an independent review. Built as Phase 4a stages P4a-01 to P4a-04; the Programs-owned settings sections arrive in P4a-06, P4a-08 and P4a-10 ([PLAN](../PLAN.md)). Authorized 2026-11-20 with the rest of Phase 4a ([STATUS](../STATUS.md)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Problem

The Building Segment is the unit PHX turns into one WUFI-Passive or METr Variant: it carries the
certification settings, the airtightness, the set points and the thermal bridges of the Zones in
it. Today a Segment is only a name and colour on a column of the Geometry view, every Zone must
name one, and Segment-level values have nowhere to live. The user needs to see which Zones form
each Segment in every Zone view, add and remove Segments there, keep a Zone out of every Segment,
and edit a Segment's values in one place.

## Vocabulary

| Term | Meaning |
| --- | --- |
| Building Segment | A Model-owned record that groups Zones into one exported honeybee-ph `BldgSegment`. A Zone belongs to **at most one** (was: exactly one) |
| Default Building Segment | The Segment every new Zone joins. Never "none" |
| No Building Segment | The state of a Zone in no Segment. Shown as a last, muted group; left out of export |
| Building Segment settings | The dialog that edits one Segment's values, assembled from sections each feature contributes |
| Segment heading row | The row that opens each Segment's group in every Zone view |

These enter `context/UBIQUITOUS_LANGUAGE.md` in P4a-01 (membership) and P4a-02 (the dialog and row).

## What exists today

- **Records.** `ph_composer.zones.building_segment` (`bsg_`): name, colour, immutable export
  identifier. Option settings name `default_segment_id`. Zone schema 2 stores a required
  `building_segment_id` (`features/zones/options/definitions.rb`; `context/CONTRACTS.md`, "Managed
  Zone field options").
- **Management.** "Manage Building Segments…" in the Geometry view's Building-Segment column menu
  edits the whole collection: add, rename, recolour, remove with a required survivor, choose the
  default (`html/features/zones/option_dialog.js`). Agents use `ph_composer.zones.options.*`.
- **Display.** Geometry shows a per-Zone chip column. Spaces has no Segment grouping on screen.
- **Export.** Rooms are grouped by Segment and share one `BldgSegment` per group
  (`python/ph_composer_translation/model_sections.py`); PHX makes one Variant per Segment.

## Behaviors

### Membership (P4a-01)

1. A Zone names one Building Segment or none. Make Zone puts a new Zone in the default Segment.
2. The Model keeps at least one Segment. Deleting the last one is refused; the Delete control says
   why before the click.
3. Deleting a Segment that holds Zones asks where they go: another Segment or No Building Segment.
   Its settings, stored as extensions on the Segment, go with it in the same Undo step; the
   confirmation names them.
4. The default can never be none. Deleting the default makes the Segment its Zones moved to the
   default, else the first remaining one.
5. Merging two Segments is Delete with "move its Zones to" the survivor (BS-4).
6. Every change is one native Undo step and an agent operation with the same rules.

### In the Zone views (P4a-02, BS-1, BS-4)

1. **Every Zone view groups Zones under Segment heading rows**: Geometry, Spaces and Programs.
   The heading takes two lines: the Segment name alone (truncated, with the full name in its
   tooltip) and a findings flag; then a "Default" tag on the default Segment and a "Single
   dwelling" tag where that is on (P4a-08). The second line is absent when neither applies. No Zone
   count or category subtitle. Each view puts its own sums in its columns (Geometry: envelope
   areas; Spaces: floor area, iCFA, volume, airflows; Programs: bedrooms, occupants, loads).
2. **Settings and Delete sit in the heading row's Actions cell**, revealed on hover as other row
   actions are. No Rename icon: the name is edited in settings.
3. **No Building Segment** is the last group, muted, shown only while it holds a Zone. Its tooltip
   says its Zones are left out of export.
4. **New Building Segment** is an icon button in each view's control row. It creates a Segment
   under a free default name ("Building Segment 2") and opens its name in place.
5. **Moving Zones**: check Zone rows, then Building Segment in the selection bar: each Segment, New
   Building Segment (created, named, and the checked Zones moved in), or No Building Segment. No
   drag and drop. The Spaces view's selection bar gains Zone rows for this.
6. The Building-Segment column (in Geometry and in Spaces) and the Manage Building Segments dialog
   go. The Level column and its dialog stay.

### Building Segment settings (P4a-02 frame; sections in later stages)

One dialog per Segment, opened from its heading row in any Zone view. Cancel and Save; Save is
one Undo step across every section. Sections, in this order:

| Section | Fields | Owner and stage |
| --- | --- | --- |
| General | Name; colour; "New Zones join this Segment" (checked and disabled on the default) | Zones, P4a-02 |
| Occupancy | Single dwelling (residential Segments only); default Program for its Zones; under Single dwelling, the dwelling's bedrooms, occupants and Equipment Set; dwelling units (read only) | Programs, P4a-08 |
| Phius certification | Building category (residential or non-residential), certification program, building use, building status, building type | Certification, P4a-04 |
| Airtightness | Test result: n50 (1/h) or q50 (m³/h·m²) and its value; wind exposure | Programs, P4a-06 |
| Comfort | Winter and summer set points, read only, from the Zones' Programs (Q4a-04) | Programs, P4a-10 |
| Planned | Floor levels (from Levels), summer ventilation, mechanical cooling and mechanical room temperature (Phase 7 mechanical), source energy and CO2 factors | Listed, disabled, with the phase in the tooltip |

The certification program list follows the pinned honeybee-ph `PhiusBuildingCertificationProgram`
enum, which stops at Phius 2021 CORE and ZERO. Mechanical cooling and mechanical room temperature,
shown in the prototype's Comfort section, move to Phase 7 mechanical, which owns the systems they
describe (C4a-5, Ed, 2026-11-15).

### Export rules (P4a-03, BS-2, BS-6)

Checked when the user exports; the Zone tables never flag them.

1. **The minimum is one Zone in one Building Segment.** With less, export refuses.
2. A Zone in no Segment is left out with its Faces, Spaces and thermal-bridge Edges. One info
   finding names those Zones and counts what went with them. Later they export as shading
   ([zone-shading](../../unscheduled/zone-shading.md)). A Face tagged as shading inside such a Zone
   still exports as a Shade (C4a-12).
3. An empty Segment is left out, with an info line in the export report.
4. A Surface Face whose partner Zone is left out refuses export and names the Face. A Face can
   hold an Attached zone only on the Attached zone boundary (`features/zones/faces/schema.rb`), so
   the fix is to reclassify it, which the offer below does.
5. **Moving a Zone out of every Segment offers to make it the Attached zone** for the Faces it
   shares with exported Zones: one confirmation names the Faces, reclassifies them from Surface to
   Attached zone (leaving their Surface pairs) and creates or reuses an Attached zone named for the
   Zone, as one Undo step (BS-6, accepted 2026-11-15). Moving the Zone back leaves them as Attached
   zone; re-running Solve restores the Surface pairs, and the move-back notice says so (C4a-8).

## How PhAdditionalZone reaches PHX (read 2026-11-15; P4a-03 tests it)

- `PhAdditionalZone` subclasses honeybee-energy's `OtherSideTemperature`: zone name, type and five
  temperature reduction factors (heating demand, plus heating load, cooling demand, cooling load and
  passive cooling, each falling back to heating demand).
- PHX maps it to a Surface exterior exposure carrying the attached zone's id number
  (`create_building._hb_ext_exposure_to_phx_enum`).
- `create_building.create_attached_zones_from_hb_room` makes one attached `PhxZone` (unheated space)
  per distinct boundary identifier **per Room**, with only the heating-demand factor.
  `PhxBuilding.add_zones` appends without merging, so one Attached zone shared by two Rooms may reach
  WUFI twice.
- The WUFI writer writes `KindAttachedZone` and `TemperatureReductionFactorUserDefined`; the METr
  zone writer writes the zone type, and no reduction factor turned up there.

## Decisions (Ed, 2026-11-15)

| Id | Answer |
| --- | --- |
| BS-1 | One Segment heading row in every Zone view; the Geometry column goes |
| BS-2 | Checked at export only; one Zone in one Segment is the minimum |
| BS-3 | Single dwelling is a Building Segment attribute, switched in its settings (supersedes Q4a-26's one-Segment rule; [Phase 4a PRD](../PRD.md#single-dwelling-p4a-08)) |
| BS-4 | Drop the Manage Building Segments dialog; colour moves into settings; merge is Delete with "move its Zones to" |
| BS-5 | Built before the Programs stages of Phase 4a, as its own PR stages |
| BS-6 | An Attached zone where one is assigned, else a refusal naming the Face; moving a Zone out offers to make it that Attached zone; review the PHX path while building |

Later UI decisions the same day: two-line heading, no Rename icon, actions in the Actions cell, no
Zone count or category subtitle.

## Records and contracts

[CONTRACTS](../CONTRACTS.md), sections 1 and 2: Zone schema 3, Segment settings as structured
extensions staged by Zones' Save, the settings-section seam and the export projection they need.

## Out of scope

Exporting Zones in no Segment as shading ([zone-shading](../../unscheduled/zone-shading.md)), summer ventilation and mechanical settings
(Phase 7), site and climate per Segment (the Climate tab sets one site for the Model; C4a-13), drag and
drop between groups.
