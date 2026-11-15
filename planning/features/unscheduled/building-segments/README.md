# Building Segments: membership, management and settings

DATE: 2026-11-15
STATUS: Scoped. Ed answered BS-1 to BS-6 on 2026-11-15; schedule before Phase 4a's implementation (BS-5). No implementation authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft; open one when Ed schedules it)

Ed raised this on 2026-11-15, after the first [Phase 4a](../../phase-04a-program/README.md) review.
The Building Segment is the unit PHX turns into one WUFI-Passive or METr Variant, and it carries
more than Program data. This packet settles how Zones join a Segment, how the user manages
Segments, and where Segment-level values are edited. The
[Phase 4a prototype](../../phase-04a-program/mockups/README.md) shows the proposal in the Programs
view (journey 3 for moving, adding and deleting; journey 1 for the dialog under Single dwelling).

## What exists today

- **A Building Segment is a managed record** (`zones.building_segment`, id prefix `bsg`) with a
  name, a colour and an export identifier. A settings record names the **default Segment**, which
  every new Zone joins (`src/ph_composer/features/zones/options/definitions.rb`).
- **Every Zone must name one.** Removing a used Segment requires a replacement Segment; a Level may
  be cleared, a Segment may not (`options/operations.rb`, `replacements`).
- **Management** is the "Manage Building Segments…" dialog in the Geometry view's Building-Segment
  column menu: add, rename, recolour, remove with a replacement (a merge), choose the default
  (`html/features/zones/option_dialog.js`). Agents use `ph_composer.zones.options.*`.
- **Display:** Geometry shows a per-Zone chip column. Spaces has no Segment grouping on screen,
  though its export totals by Segment. The Phase 4a mockup groups Zones / Programs under a Segment
  heading row.
- **Export** groups Rooms by Segment and shares one honeybee-ph `BldgSegment` per group
  (`python/ph_composer_translation/model_sections.py`). PHX makes one Variant per Segment
  (`create_project.sort_hb_rooms_by_bldg_segment`) and reads certification, site, set points and
  energy factors from it (`create_variant.py`).

## What changes (Ed, 2026-11-15)

1. **A Zone may be in no Building Segment.** Export leaves it out for now, with a finding that names
   it. Later it exports as shading ([zone-shading](../zone-shading.md)).
2. **Management stays, its rules change.** Add and delete Segments from the Zone tables; rename in settings.
   The Model always keeps at least one Segment: deleting the last one is refused, with the reason
   on the control. Deleting a used Segment asks where its Zones go: another Segment or no Segment.
   The default Segment can never be "no Segment"; deleting the default moves the default to the
   Segment its Zones went to, else the first remaining.
3. **New Zones join the default Segment**, as today.
4. **Move Zones between Segments, or out of every Segment**, from the Zone tables.
5. **Segment-level values move into one Building Segment settings dialog.** The heading row keeps
   only the name, its sums and a findings flag.

## UX (BS-1, accepted)

**One Segment heading row in every Zone view.** Membership matters in all three views: Geometry is
where a Zone's envelope and thermal bridges are counted per Segment, Spaces totals iCFA and volume
per Segment for certification, and Programs sets loads per Segment category. Grouping makes
membership visible without a column, shows an empty Segment as an empty group, and gives the
settings dialog one home: a settings icon on the heading row, the same in every view.

- The heading takes two lines. First, the Segment name alone (truncated, full name in its
  tooltip) and a findings flag. Second, a "Default" tag on the default one and a "Single dwelling" tag where it is on; the
  line is absent when neither applies.
  No Zone count or category subtitle (Ed, 2026-11-15); the category is in settings. Settings and Delete sit in the row's left Actions cell, revealed on
  hover, as row actions are in Geometry and Spaces. The view's own sums (Geometry:
  envelope areas; Spaces: iCFA, volume; Programs: bedrooms, people) sit in its columns. No Rename
  icon (Ed, 2026-11-15): the name is edited in settings, and a new Segment opens its name in place.
- **No Building Segment** is a last, muted group, shown only when it holds a Zone. Its tooltip says
  its Zones are left out of export.
- **Moving Zones:** check Zones, then Building Segment in the selection bar: each Segment, New
  Building Segment (creates one under a free default name and moves the checked Zones into it), and
  No Building Segment. No drag and drop: rows never move under the pointer, and a selection bar
  already assigns everything else.
- **New Building Segment** also sits in the view's control row, for an empty Segment.
- The Geometry view's per-Zone Building-Segment column goes; the grouping is the assignment. The
  Level column stays.

The cost: Geometry (Zone, then Faces) and Spaces (Zone, Space, Volume, Floor Segment) each gain one
tree level. For the single-family default it is one quiet row. The alternative, a Segment column
in Geometry and Spaces with grouping only in Programs, keeps those trees flatter but splits the
settings dialog across three entry points and hides empty Segments.

## The Building Segment settings dialog

One dialog, opened from the heading row in any Zone view. Fields from honeybee-ph's `BldgSegment`
(`honeybee_ph/bldg_segment.py`) and `PhiusCertification` (`phius.py`), grouped:

| Section | Fields | Notes |
| --- | --- | --- |
| General | Name, colour, "New Zones join this Segment" | The default flag moves here from the Manage dialog |
| Occupancy | Single dwelling (its only switch, BS-3; residential Segments only); default Program for its Zones; under Single dwelling, the dwelling's bedrooms, occupants and Equipment Set | A Segment naming its default Program answers the open half of Q4a-13 |
| Phius certification | Building category (residential or non-residential), certification program, building status, building type | Category is Q4a-14. The rest map to `PhiusCertification` enums, whose program list in the pinned honeybee-ph stops at Phius 2021 CORE and ZERO |
| Airtightness | Test result (n50 or q50), wind exposure | Q4a-06: converted at export into each Zone's Infiltration, which is where PHX reads it (`cleanup.merge_infiltrations`) |
| Comfort | Winter and summer set points, read only; mechanical cooling; mechanical room temperature | Set points come from the Zones' Programs (Q4a-04) |
| Derived, read only | Floor levels (from Levels), dwelling units (from Dwellings) | `num_floor_levels`, `num_dwelling_units` |
| Later | Site and climate (Phase 5.1), summer ventilation (Phase 4), source energy and CO2 factors | Listed, disabled, with the phase in the tooltip |

**Each section is a contribution.** No dialog-section seam exists today (`context/EXTENSIBILITY.md`
names three panel seams). Proposed: the Zones feature owns the Segment record and the dialog
frame; each feature registers a section and stores its values in its own record keyed by the
Segment id (Programs: category, default Program, house counts; a certification feature; envelope:
airtightness). The Segment record stays atomic, matching the onion rule.

## Export rules

Checked only when the user exports to HBJSON; the Zone tables never flag them (BS-2).

- **The minimum is one Zone in one Building Segment.** Export refuses with less.
- A Zone in no Segment is left out, with its Faces, Spaces and thermal-bridge Edges. One info
  finding names the Zones and counts what went with them.
- **An empty Segment** (no Zones) is left out, with an info line in the export report.
- A Face whose Surface counterpart is in a Zone left out exports with that Zone's Attached zone
  (`PhAdditionalZone`); with none assigned, export refuses and names the Face (BS-6, below).
- Refusals and findings appear in the Export tab's preflight like other findings.

## Files the change touches

- Records and rules: `features/zones/options/` (`definitions.rb`, `operations.rb`, `commands.rb`,
  `adoption.rb`, `registration.rb`), the Zone record's `building_segment_id` (nullable), and the
  Make Zone path that assigns the default.
- Export: `features/zones/export.rb`, `features/zones/faces/export.rb`, `features/spaces/export.rb`,
  `features/thermal_bridges/export.rb`, `python/ph_composer_translation/model_sections.py`.
- Panel: `html/features/zones/option_dialog.js`, `overview.js`, `zone_cells.js`, `zone_options.js`,
  the Spaces view, and the selection bar.
- Contract and docs: `agent_access/guide.md`, `docs/API_REFERENCE.md`, `docs/PRODUCT.md` step 2,
  `context/UBIQUITOUS_LANGUAGE.md` ("Every Zone belongs to one Building-Segment" becomes "at most
  one"), `context/EXTENSIBILITY.md` for the new section seam.

There are no users, so no migration: the Zone record's schema version moves and existing test
fixtures are rewritten.

## Single dwelling per Building Segment (BS-3)

Single dwelling becomes an attribute and control of each Building Segment, replacing Q4a-26's
Model-level switch that forced one Segment. A house and an ADU can then be one dwelling each, in
two Segments.

- The switch lives in the Segment's settings (Ed, 2026-11-15: rarely changed, and a checkbox on
  every row cluttered non-residential Segments). When on, that Segment's Zones are one dwelling,
  named for the Segment, with the residential default; its rows are locked and its heading row
  takes the bedrooms, occupants and Equipment Set.
- The heading shows a "Single dwelling" tag only where it is on. **A locked value is not a dead
  end:** clicking any locked cell, or the tag, opens a bubble anchored to it that says why, with
  one **Open settings** button (Ed, 2026-11-15: no shortcut to switch it off from the bubble). A
  new user who tries to change a Program meets the explanation and the way to settings on that
  cell. Switching it off keeps what it set.
- A new Model starts with one Segment with Single dwelling on (Q4a-27). Claude's choice, to
  confirm: a Segment the user adds starts with it off.
- Moving a Zone into a Single dwelling Segment makes it part of that dwelling; moving it out
  leaves the dwelling. Switching on over per-Zone assignments confirms first, naming what gives
  way in that Segment only.

## Attached zones and PhAdditionalZone (BS-6)

Ed's answer: a Face shared with a Zone outside every Segment exports with an Attached zone, which
PH-Composer already writes as honeybee-ph's `PhAdditionalZone`
(`honeybee_energy_ph/boundarycondition.py`). How PHX carries it, read 2026-11-15, to be checked
again while building:

- `PhAdditionalZone` subclasses honeybee-energy's `OtherSideTemperature` and carries a zone name,
  type and five temperature reduction factors (heating demand, the default, plus heating load,
  cooling demand, cooling load and passive cooling, each falling back to heating demand).
- PHX maps it to a Surface exterior exposure with the attached zone's id number
  (`create_building._hb_ext_exposure_to_phx_enum`).
- `create_building.create_attached_zones_from_hb_room` makes one attached `PhxZone` (kind
  unheated space) per distinct boundary identifier **per Room**, carrying only the heating-demand
  factor. `PhxBuilding.add_zones` appends without merging, so one Attached zone shared by two
  Rooms may reach WUFI twice. Not tested; test it before relying on it.
- The WUFI writer writes `KindAttachedZone` and `TemperatureReductionFactorUserDefined`. The METr
  zone writer writes the zone type; no reduction factor field turned up there. To verify.

Accepted 2026-11-15: moving a Zone out of every Segment offers to make it the Attached zone for
the Faces it shares with exported Zones, so the user does not assign them one by one.

## Answers (Ed, 2026-11-15)

| Id | Answer |
| --- | --- |
| BS-1 | **One Segment heading row in every Zone view.** The Geometry Building-Segment column goes |
| BS-2 | **Checked at export only.** One Zone in one Building Segment is the minimum for HBJSON export; nothing is flagged in the tables before then |
| BS-3 | **Single dwelling is a Building Segment attribute and control** (above). Supersedes Q4a-26's one-Segment rule |
| BS-4 | **Drop the Manage Building Segments dialog.** Colour moves into settings; merging is Delete with "move its Zones to" |
| BS-5 | **Before Phase 4a's implementation**, as its own PR stage |
| BS-6 | **An Attached zone** where one is assigned, else a refusal naming the Face. Moving a Zone out of every Segment offers to make it that Attached zone. Review how `PhAdditionalZone` flows through PHX while building (above) |
