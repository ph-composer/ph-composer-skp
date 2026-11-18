# P4c-06: The Climate tab, Site location and Design temperatures

DATE: 2026-11-17
STATUS: Implemented on branch `feature/climate-p4c-06`, PR #517, 2026-11-18; CM06 not yet run. Authorized with every Climate stage on 2026-11-17 ([STATUS](../STATUS.md#authorization)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#511](https://github.com/ph-composer/ph-composer-skp/issues/511)

## Entry and scope

Requires P4c-01 and owed check 4. Owns the Climate tab and its frame (page header, sidebar cards,
the narrow select), the Site location pane, the Set Location dialog with typed fields and the
read from SketchUp's geolocation, and the Design temperatures pane. The map inside Set Location
is P4c-07; the Phius climate data pane is P4c-08 onward, and until then its card shows its state
and its pane a placeholder line.

Behavior: [PRD](../PRD.md), "The tab", "Site location" and "Design temperatures". Names:
[CONTRACTS](../CONTRACTS.md) section 2. Answers: W2, W3, W4, W7, J2, J5, R1; D4c-13. Boards: 8
(`SiteEmpty`), 1 (`Main`, without its map), 13 (`DesignTemps`), 22 (`GeoUnavailable`,
provisional), 7 (`Narrow`), 23 (`Small`), and the Hourly weather file card shown as Planned.
Paths are relative to `src/ph_composer/`.

Load the UI polish skill and its patterns reference, and the architecture review skill, first.

## Entry checks

**Owed check 4.** On the host, before the read is written, and recorded under `evidence/` and in
`context/SKETCHUP_HOST_BEHAVIOR.md`:

1. In a Model never geolocated: what `ShadowInfo` reports for `Latitude`, `Longitude` and
   `TZOffset`, and what `Model#georeferenced?` answers.
2. In a Model geolocated through SketchUp's own Add Location: the same four, and whether any
   elevation is exposed (the API reference documents none).
3. Whether `TZOffset` is a whole number of hours usable as hours from UTC, and how it behaves
   for a daylight-saving location.
4. From these, fix the result shape of `site.geolocation` and redraw board 22 if the host
   differs from it. The read fills only what the check proves; it never fills elevation.

Also at entry: check the tab row with Climate added at 1280, 420 and 360 px wide
(`tools/ui-preview/support/pane_fit.cjs` `PANEL_SIZES`). The row wraps today; record how many
lines it takes with seven tabs, and note that Programs and Mechanical will add two more.

## Steps

1. **Tab.** A `climate` button first in the row and its pane in `html/index.html` (a
   composition-root edit), `make panel-manifest`. `html/panel.js` keeps `activeTab: "overview"`,
   so the panel still opens on Zones (R1); a test pins it.
2. **Frame** (`html/features/climate/section.js`, `climate.css`): one page header; a sidebar
   with Site location, then under "Climate sources" the cards Phius climate data, Design
   temperatures and Hourly weather file; each card shows its state from the `summary` snapshot
   section. The Hourly weather file card reads Planned and is not selectable. At narrow widths
   the sidebar becomes one select above the content. The selected card is remembered per session.
3. **Source cards** as a kit part (`html/source_cards.js`) if the library sidebar's rows do not
   already fit; the boards' wireframe-only classes are replaced by it. Record the pattern in the
   UI polish patterns reference.
4. **Site location pane.** Not set: the empty state with Set Location (board 8). Set: latitude,
   longitude, elevation, climate zone and hours from UTC, each unset one shown as such, and Set
   Location.
5. **Set Location dialog** (`formDialog`): the five fields, the zone as a select of the ten
   labels, Read from SketchUp Geolocation, and Set. Set is disabled until latitude, longitude
   and elevation are all present. One `site.update`, one Undo step. The dialog leaves a region
   for the map that P4c-07 fills.
6. **`site.geolocation`** (query, Ruby, `features/climate/site/geolocation.rb`): the shape the
   entry check fixed. The button fills the dialog's fields and writes nothing until Set. When
   the Model has no geolocation the dialog says so (board 22).
7. **Design temperatures pane** (board 13): two unit fields and the source note, each committed
   on blur or Enter as its own `design_temperatures.update`; the state line; the warning when
   heating is at or above cooling; a line saying they stay in the Model and what uses them.
8. **Findings route.** If P4c-05 has merged, its preflight findings gain a `locate` that opens
   this tab at the right card; if not, P4c-05 adds it. A `locate` names a registered operation
   and its params, so first check what it may name and whether a view command is needed.
9. **Units**: every field through the unit preference; stored SI.
10. **Docs.** `docs/PRODUCT.md` gains a Climate section for the site and the design
    temperatures; the Design System re-sync if the kit changed.

## Source

| File | Disposition |
| --- | --- |
| `html/features/thermal_bridges/section.js` | Pattern for a tab's section registration |
| `html/library/sidebar.js`, `html/page_header.js`, `html/overlay.js` (`formDialog`), `html/unit_field.js` | Reused |
| `html/index.html`, `tools/panel_manifest.js`, `tests/panel_app_test.js` | The tab row |
| `mockups/canvas/project/` boards 1, 7, 8, 13, 22, 23 | Structure reference only; no markup is copied into `src/` |

## Tests (write first)

1. The panel opens on Zones with Climate first in the row.
2. Card states for each `summary` value; the Planned card does nothing on click or keyboard.
3. Set Location: Set disabled on a partial site; a full site sends one `site.update`; a refusal
   keeps the dialog open with the draft; a stale value refuses and the fields return to the
   Model's values.
4. The geolocation read fills latitude and longitude and never elevation; with no geolocation
   the dialog shows the board 22 state.
5. Design temperatures: each field commits alone; clearing unsets; the warning shows and the
   value still saves; a half-typed draft is not sent by a repaint.
6. Browser checks at the three panel sizes: no horizontal overflow, the select replaces the
   sidebar, the tab row is reachable.
7. IP and SI on every field.

## Host gate

CM06 in [ACCEPTANCE](../ACCEPTANCE.md): panel gestures with Ed at the mouse; UI polish review
recorded.

## Leaves for the next stage

P4c-07 fills the dialog's map region. P4c-08 replaces the Phius pane's placeholder.

## Done when

CM06 passes, owed check 4 is recorded and board 22 matches the host.

## Departures, 2026-11-18

- **Owed check 4** ([evidence](../evidence/owed-check-4-20261118.md)): a Model never geolocated
  still carries its template's location in `ShadowInfo`, so the read gates on `Model#georeferenced?`.
  Item 2 ran through the Ruby API, not Add Location, so what Add Location writes to `TZOffset` is not
  known: `site.geolocation` keeps `hours_from_utc` in its shape and always answers null, and the
  dialog says it does not fill hours from UTC. Board 22 matches the host and is not redrawn; its
  "and hours from UTC when SketchUp has one" is not built. The native Add Location run is listed in
  the evidence for the conductor.
- **Tab row** at 1280, 420 and 360 px (`tools/ui-preview/climate_checks.cjs`): one, three and three
  lines with eight buttons (seven tabs and the disabled Systems), every tab reachable; before Climate,
  one, three and three with seven. The row wraps; it does not scroll. Programs and Mechanical will add
  two more.
- **Two snapshot sections** (`ph_composer.climate.site` and `.design_temperatures`, backed by the
  existing reads) carry the values the cards and panes paint, so the tab needs no query of its own
  (CONTRACTS section 2 amended).
- **Findings route** (step 8): a `locate` names a viewport view command run by the host, so it
  cannot open a panel tab, and none was added. Climate registers its tab with `panel.workedOn`, which
  gives each Climate export finding an Open Climate button; that button now passes the finding's code
  with the navigation, and the tab maps the code to the card that fixes it. `sections/export.js`
  names no feature.
- **Design temperatures**: the panel stamps every action with the revision it rendered, so two fields
  committed close together would refuse the second as stale. The pane sends its writes one at a time,
  each waiting for the last; each is guarded by the value its field showed when typing began.
- **Source cards** are a new kit part (`html/source_cards.js`, `source_cards.css`), recorded in the UI
  polish patterns reference: the Library sidebar is a record browser with its own store and does not fit
  a few subjects with states.
- **Climate Data on This Computer** is P4c-08's; the page header does not show it yet.
