# Building Segments: membership, management and settings

DATE: 2026-11-15
STATUS: Requested. Plan and prototype for review; no implementation authorized.
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
2. **Management stays, its rules change.** Add, rename and delete Segments from the Zone tables.
   The Model always keeps at least one Segment: deleting the last one is refused, with the reason
   on the control. Deleting a used Segment asks where its Zones go: another Segment or no Segment.
   The default Segment can never be "no Segment"; deleting the default moves the default to the
   Segment its Zones went to, else the first remaining.
3. **New Zones join the default Segment**, as today.
4. **Move Zones between Segments, or out of every Segment**, from the Zone tables.
5. **Segment-level values move into one Building Segment settings dialog.** The heading row keeps
   only the name, its sums and a findings flag.

## Proposed UX (Claude's recommendation)

**One Segment heading row in every Zone view.** Membership matters in all three views: Geometry is
where a Zone's envelope and thermal bridges are counted per Segment, Spaces totals iCFA and volume
per Segment for certification, and Programs sets loads per Segment category. Grouping makes
membership visible without a column, shows an empty Segment as an empty group, and gives the
settings dialog one home: a settings icon on the heading row, the same in every view.

- The heading row carries the Segment name, a "Default" tag on the default one, the Zone count,
  the view's own sums (Geometry: envelope areas; Spaces: iCFA, volume; Programs: bedrooms, people),
  a findings flag, and, on hover, Settings, Rename and Delete icons, as record rows do elsewhere.
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
| Phius certification | Building category (residential or non-residential), certification program, building status, building type | Category is Q4a-14. The rest map to `PhiusCertification` enums, whose program list in the pinned honeybee-ph stops at Phius 2021 CORE and ZERO |
| Occupancy | Default Program for its Zones; under Single dwelling, the house's bedrooms, occupants and Equipment Set | A Segment naming its default Program answers the open half of Q4a-13 |
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

- A Zone in no Segment is left out, with its Faces, Spaces and thermal-bridge Edges. One info
  finding names the Zones and counts what went with them.
- **Export refuses when no Zone is in any Segment**: there is nothing to certify.
- **An empty Segment** (no Zones) is a warning and is left out; it does not block export.
- Refusals and warnings appear in the Export tab's preflight like other findings.

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

## Open questions

| Id | Question | Recommendation |
| --- | --- | --- |
| BS-1 | One Segment heading row in every Zone view, or grouping in Programs only? | Every view (above) |
| BS-2 | "At least one Zone in a Segment" read as: export refuses when no Zone is in any Segment; an extra empty Segment is a warning. Right reading? | Yes, to confirm |
| BS-3 | Single dwelling (Q4a-26) forces one Building Segment. Keep that, or make Single dwelling a setting of each Segment, so a house and an ADU can each be one dwelling in two Segments? | Per Segment. It removes the conflict between the switch and Segment management, and the default Model (one Segment, single dwelling) looks the same |
| BS-4 | Does the "Manage Building Segments…" dialog survive? Heading rows cover add, rename and delete; the dialog still offers recolour and merge in one place | Drop it: colour moves into settings, merge is Delete with "move its Zones to" |
| BS-5 | Schedule this before Phase 4a's implementation, or inside it? 4a's Segment row, category and airtightness depend on it | Before, as its own PR stage |
| BS-6 | A Zone in a Segment shares a wall with a Zone in none (Ed's adjoining structure). What does the exported Zone's Surface Face become: Outdoors, Adiabatic, or an Attached zone boundary with a reduction factor (the garage case)? And a thermal-bridge Edge on that line: counted on the exported Zone, or dropped? Today's pairing in `model_sections.py` has not been tested against a counterpart that leaves export | Attached zone when the user has made one, else a refusal naming the Face, so nothing exports with an unpaired Surface. To decide |
