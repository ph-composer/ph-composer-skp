# Climate

DATE: 2026-09-18
STATUS: Requested. Drafted 2026-09-18 as a post-MVP packet (D7 and D9 confirmed). Revised 2026-11-16 to the wireframe review of 2026-11-15 and 2026-11-16 (W1 to W9): a Climate tab, climate data read from a folder on the user's computer, one climate copied into the Model. Not planned; no stage authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

METr needs a climate. If the export carries none, the consultant sets it in METr after every
export. If the export carries one, a variant study needs no manual step. The Mechanical phase's
blended heat pump also needs the climate and two design temperatures before it can be computed
([Mechanical DECISIONS, Part 3](../phase-07-mechanical/DECISIONS.md#part-3-wireframe-review-2026-11-15),
D4-15), which is why this packet now comes first. The climate also feeds two later views, the sun
path and the window radiation overlay.

The data is the hard part. Phius licenses its climate files to each user, so PH-Composer cannot
ship them, and a full dataset is about a thousand station files, which does not belong in a Model.

## Product boundary

D7 stands. PH-Composer ships and distributes no climate datasets. A user points PH-Composer at
climate files they are entitled to use, on their own computer, or types values in. PH-Composer
reads those files where they are, never copies or shares them, and keeps in the Model only the one
climate the user attaches.

Revised 2026-11-16 (W1): the tab has a map. It is an outline drawn from public-domain borders
shipped with the extension. PH-Composer still loads no map tiles and reaches no network.

## How it works

1. The user names one or more folders of climate files on their computer. PH-Composer reads every
   recognised station file under a folder, subfolders included.
2. Each folder's location and the name the user gives it are kept in PH-Composer's own settings
   file in the user's folder on that computer, read by every SketchUp version. No list of
   stations is stored. The folder is read when the station picker opens.
3. Attaching a station copies its values into the Model with the dataset name, the station name
   and a checksum. No folder path is stored in the Model or written to any export.
4. The Model then reads in full on any computer. Only replacing the station needs the folder.

## What honeybee-ph and METr take

Verified on 2026-09-18 in `honeybee_ph/site.py` and PHX `to_METr_JSON/metr_schemas.py`, `_PhxSite`.

- `Site` holds a `Location` (`latitude`, `longitude`, `site_elevation`, `climate_zone`) and a
  `Climate`.
- `Climate` holds `station_elevation` (m), `summer_daily_temperature_swing` (K),
  `average_wind_speed` (m/s), a ground block, `monthly_temps` (air, dewpoint, sky, ground),
  `monthly_radiation` (north, east, south, west, global; twelve values each, kWh/m²), and
  `peak_loads` (two heating and two cooling cases, each with a temperature and five radiation
  values in W/m²).
- `ClimateProvenance` exists in honeybee-ph: `source_type`, `source_name`, `source_uri`,
  `source_version`, `source_checksum`, `conversion_method`, `is_certification_approved`,
  `monthly_data_available`, `peak_load_data_available`, `assumptions`.
- METr's site block takes latitude, station elevation, climate zone, daily temperature swing,
  wind speed, and the monthly arrays with the four peak-load cases appended as positions 12 to
  15. So a full snapshot reaches METr.
- honeybee-ph `Site.from_epw()` converts a caller-supplied annual EPW into monthly values and
  leaves peak-load data unavailable. That route is deferred with the Hourly weather file card (W3).

## What a Phius station file holds

Structure only, read on 2026-11-15 from PH-Navigator's importer and the row labels of one file. No
file content is in this repository, and public fixtures are synthetic files of the same shape.

- One file per station, named `<STATION>-mon.txt`, in a folder named for its state. Tab-delimited
  text in the Windows-1252 encoding.
- A header row with the station name, latitude, longitude, height above sea level and the summer
  daily temperature variation.
- Eight series rows (outdoor temperature, dewpoint, sky temperature, and north, east, south, west
  and global radiation), each with twelve monthly values and three design columns: Heating load 1,
  Heating load 2 and Cooling load.
- Scalar rows with degree-hours and the January and July wind speeds, and an albedo line.

It does not hold: a dataset name or year, a climate zone, a second cooling case, monthly ground
temperatures, one annual wind speed, or any ASHRAE design temperature.

### A private corpus for development

Ed holds a licensed Phius 2022 dataset on his own computer, outside this repository. It may be
used to develop and test this feature and must never be distributed: none of it, and no value from
it, enters the repository, a public fixture, a planning document or a published wireframe. Its
location is recorded only in the gitignored `_private/climate/MANIFEST.md`, as the repository's
rule for private test corpora requires; a test that reads it skips when it is absent, and the
public fixtures are synthetic files of the same shape.

Its layout, from folder and file names only (2026-11-16), is what a real climate data folder looks
like:

- a text-file tree, `USA/<ST>/<STATION>-mon.txt`: 1,007 stations in 50 state folders, the format
  the first version reads;
- a few stray files in that tree whose names do not end `-mon.txt` (a second copy, an edited
  copy), which a scan should count as not recognised and not as stations;
- a second tree of one `.xls` workbook per station, for the USA and also for Canada and Japan,
  which have no text-file equivalent;
- two folders of older `.xls` station workbooks.

## Vocabulary

Proposed. `context/UBIQUITOUS_LANGUAGE.md`, "Site and climate", carries the planned terms.

| Term | Meaning |
| --- | --- |
| Site location | Where the building is: latitude, longitude, elevation and climate zone. Separate from the station |
| Climate data folder | A folder on the user's computer holding climate files they are licensed to use, with a name the user gives it |
| Station | One location in a climate data folder, read from one file |
| Phius climate data | The Model's one climate: a station's values, or values typed by hand. It is what exports |
| Design temperatures | The ASHRAE 99% heating and 1% cooling dry-bulb temperatures for the site, typed by the user |
| Climate snapshot | The copy of the climate kept in the Model with its provenance. It reads without its source |

## Records

```
Model   gains  site     { latitude_deg, longitude_deg, elevation_m, climate_zone }
               climate  { name, station_elevation_m, daily_temp_swing_k, wind_speed_m_s,
                          monthly { air_c[12], dewpoint_c[12], sky_c[12],
                                    rad_north_kwh_m2[12], east, south, west, global },
                          peak_loads { heat_1, heat_2, cool_1 },
                          provenance { dataset name, station name, checksum, edited flag,
                                       ...honeybee-ph ClimateProvenance fields } }
               design_temperatures { heating_99_c, cooling_1_c }

This computer  climate data folders  [ { name, folder location } ]   in PH-Composer's settings file
```

A Model holds one site, one climate and one pair of design temperatures (W6). The climate is a
copy: the Model never needs the source again to be read. A Phius station's three peak-load cases
are the complete set; the second cooling case and the monthly ground temperatures stay empty and
are not flagged (W8). `wind_speed_m_s` is typed, prefilled with the mean of the file's January and
July values (W8).

Climate is its own feature (W6). It is not a Library kind, uses none of the Library provider
contract, and its per-computer setting is not in the Library's setup store. One built-in reader
handles Phius station files; a registered contract for further formats waits until the Hourly
weather file gives a second reader to shape it against.

## Behaviors

### The tab

- Climate is a primary tab, first in the row, before Zones (W7).
- A sidebar lists Site location, then under "Climate sources" the cards Phius climate data, Design
  temperatures and Hourly weather file. The Hourly weather file card is shown as Planned and does
  nothing in the first version (W3). Each card shows its state; the pane beside it shows the
  selected card.
- At narrow widths the sidebar becomes one select above the content.

### Site location

- Latitude, longitude, elevation and climate zone are typed in a Set Location dialog (W2).
- Read from SketchUp Geolocation fills the fields once. Nothing is written back to SketchUp, and
  nothing syncs on its own (Q5, Q6).
- Clicking the map in the dialog places the site and fills latitude and longitude (W1).
- There is no address search and no elevation or climate-zone lookup: the panel reaches no network.

### Climate data on this computer

- A dialog, opened from the Climate tab and listed in the Setup view with a one-line summary (W5).
- It lists each climate data folder with its name, its location, the format found, the number of
  stations and states, and how many files were not recognised. Add Folder, Rescan and Remove.
- Adding a folder asks for its name, prefilled from the folder's own name. That name is the
  dataset name the Model and the Export report show (W5).
- The first version recognises Phius station files only. Anything else in a folder is counted as
  not recognised (W5).
- The dialog says what is kept where: the folder's location and name on this computer; station
  files read when needed; only the attached station in a Model.

### Choosing a station

- With no climate data folder on the computer, the Phius climate data pane says so, says why
  PH-Composer ships none, and offers Choose Climate Data Folder and Enter Values by Hand.
- The picker shows every recognised station on the outline map with the site and a ring at
  Phius's distance limit, and the same stations in a list with distance, elevation difference and
  a Pass or Fail verdict. A station passes within 50 miles (80 km) and 400 feet (122 m) of the
  site; outside either it fails.
- Find Nearest sorts by distance. A Dataset choice and a State filter narrow the list; a state is
  the name of the folder a station file sits in.
- On the map: pan and zoom, click a station to select it, hover for its name, distance, elevation
  difference and verdict (W1).
- Attach copies the station into the Model. With a station already attached, the same step
  replaces it after a comparison of old and new, in one Undo step.

### An attached climate

- The pane shows the station and dataset, the limit check (distance and elevation against the
  Phius limits), monthly temperatures, monthly radiation, peak loads, the wind speed, and a
  "Where this lives" block: what the Model holds, whether the source is on this computer, and
  what the climate is ready for.
- Values may be edited after attaching. The source is then marked as edited on the tab and in the
  Export report. Replace restores the file's values (W8).
- Enter Values by Hand starts the same record with no station: the monthly table and the peak
  loads are typed or pasted (Q7, W3).
- On a computer with no climate data folder the pane reads in full from the Model. Only Replace
  needs the folder, and says so.
- When the source file is on this computer and differs from the Model's copy, a quiet "source
  changed" mark appears. Nothing updates on its own.

### Design temperatures

- Two typed values, the ASHRAE 99% heating and 1% cooling dry bulb, on their own card (W4). A
  Phius station file carries neither.
- Export does not wait on them. Without them only the Mechanical phase's blended heat pump is
  left out, with a finding (W4).

### Export

- Export writes `Site` to the HBJSON and names the source in the Export report by dataset and
  station name, never by a folder location.
- A Model with no climate exports without one, as today.

## Decisions

Roadmap decisions D7 (no datasets ship) and D9 (peak loads for an EPW-derived climate are supplied
by the user) are confirmed and stand. Q1 to Q9 are the September interview questions; the last
column says what the wireframe review did to each.

| # | Question | September recommendation | After the review, 2026-11-16 |
| --- | --- | --- | --- |
| Q1 | Confirm the narrowed climate-picker boundary in D7? | Local and user-owned inputs and manual entry are in; hosted map tiles and distributed datasets are out | Stands. An outline map is added (W1) |
| Q2 | Which dataset kinds? | User-owned monthly climate data and EPW-derived monthly data | Revised by W3: Phius station files and typed values first; EPW-derived data waits |
| Q3 | Where do datasets come from? | User-selected local files, manual entry, or an optional provider through a `climates` record kind | Revised by W5 and W6: a climate data folder on the computer; no Library kind |
| Q4 | May any Phius climate data be redistributed? | Not by PH-Composer | Stands |
| Q5 | What sets the site location? | An explicit value, with a Read from SketchUp geolocation button | Stands (W2) |
| Q6 | Does the site location write back to SketchUp? | No | Stands |
| Q7 | Manual entry of a full monthly table? | Yes, by paste | Stands (W3) |
| Q8 | EPW ground temperatures absent, or several depths | Block when absent; require an explicit depth | Deferred with the Hourly weather file |
| Q9 | How are peak loads supplied for EPW-derived climates? | D9: typed, pasted or from a user-owned dataset | Deferred with the Hourly weather file |

The wireframe review, with Ed, 2026-11-15 and 2026-11-16. The [wireframes](mockups/README.md)
illustrate these.

| # | Kind | Answer |
| --- | --- | --- |
| W1 | UI | An outline map shipped with the extension: world countries, and state and province borders for the US and Canada, from public-domain data. No web tiles. Pan and zoom, click a station to select it, hover for details, click to place the site |
| W2 | UI | Location is typed or read once from SketchUp's geolocation. No address search and no lookups |
| W3 | UI, Scope | Separate cards, as PH-Navigator has: Phius climate data and Hourly weather file. No PHI. In the first version Phius climate data is the only climate and exports, from a station or typed by hand; the Hourly weather file card is shown as Planned |
| W4 | UI, Code | Design temperatures are typed on their own card and do not gate export |
| W5 | UI, Code | The folder's location and name live in PH-Composer's own per-computer settings file, not SketchUp's preferences; no station index and no imported copy. The setup is reached from the Climate tab and the Setup view. The user types the dataset name, prefilled from the folder. Phius station files only at first |
| W6 | Code | Climate is its own feature, not a Library kind. One climate per Model. One built-in reader now |
| W7 | UI | Climate is the first primary tab, before Zones |
| W8 | UI, Code | Three peak-load cases is complete for a Phius station; the second cooling case and ground temperatures stay empty and unflagged; wind speed is typed with a prefilled mean; an attached station may be edited and is then marked as edited |
| W9 | Scope | The packet is Phase 4, ahead of Shading, Programs and Mechanical |

## Open, and owed before planning

1. Which tab the panel opens on now that Climate is first. Zones is where most work happens.
2. Whether a failing station can be attached, and what the Model and the Export report then say.
   The wireframes show the verdict and do not block.
3. To verify on a host: that SketchUp's preferences are kept per SketchUp version, which was the
   reason for a separate settings file; and where that file sits on macOS and Windows.
4. The outline map: its data source and licence confirmed, its size in the RBZ, and how it draws
   on the Chromium 88 floor.
5. Export of the empty slots: what honeybee-ph and PHX do with an empty second cooling case and an
   empty ground row. PHX pads a missing peak value with zero in METr (read from the PHX checkout,
   not reproduced).
6. The 50 mile limit is taken from PH-Navigator's code; the 400 foot limit was read in the Phius
   guidebook. Cite both from Phius before they are bound.
7. honeybee-ph's `Location` carries hours from UTC and METr writes it. Not drawn or asked.
8. Not drawn: entering values by hand, the Design temperatures card, an edited station, scanning
   in progress, a folder that has moved, a changed source file, charts, the 360 x 520 panel size.
9. What the blended heat pump reads beyond the two design temperatures. The Phius estimator also
   uses the monthly mean temperatures, which the climate holds; the Mechanical phase binds this.
10. Stations outside the USA. The private corpus has Canadian and Japanese stations only as `.xls`
    workbooks, which the first version does not read (W5), so they cannot be attached except by
    typing values in. Whether an `.xls` reader joins the first version is not asked.

## Deferred

| Item | Waits for |
| --- | --- |
| Hourly weather file: a local EPW, honeybee-ph's `Site.from_epw()`, its ground-depth choice (Q8) and typed peak loads (Q9, D9) | A later stage of this packet; the card is shown as Planned |
| PHI climate data | Not scheduled (W3) |
| A registered contract for climate formats | The second reader (W6) |
| Reading design temperatures from a file | Not scheduled (W4) |

## Non-goals

No map tiles and no network. No bundled, mirrored or redistributed climate dataset or weather
file. No certification claim about a chosen station. No station index or copy of the user's
climate files kept by PH-Composer. No hourly simulation and no hourly weather kept in the Model.
No synthetic peak-load cases.

## Dependencies

Units, for radiation, temperature and elevation rows. The Setup view's entries, for the summary
line. The export contributor and translation section contracts, for `Site`. The Mechanical phase
depends on this packet, not the reverse.

## Acceptance shape

On a synthetic model, with a synthetic climate data folder of Phius-shaped station files in state
subfolders: add the folder and see its stations, states and unrecognised files counted; set the
site by typing and by reading SketchUp's geolocation; open the picker and find the nearest
station, with a passing and a failing verdict at the stated limits; attach one; save, remove the
folder's setting and reopen, and confirm the climate reads in full with Replace unavailable;
restore the folder and replace the station in one Undo step; edit a value and see the source
marked as edited; type a climate by hand on a second model; enter and clear the design
temperatures; export and find `Site` in the HBJSON with the dataset and station named in the
report and no folder location anywhere. Open the same Model under a second SketchUp version and
find the folder still set.

## Prior art and evidence

- Predecessor `planning/phases/C1_climate-data.md`.
- PH-Navigator's Climate tab and its Phius station importer, as prior art for the layout, the
  station file's shape and the proximity verdict.
- honeybee-ph `honeybee_ph/site.py`, `honeybee_ph/_epw.py`, `docs/epw-preliminary-climate.md`.
- PHX `model/phx_site.py`, `to_METr_JSON/metr_schemas.py`.
- The [wireframes](mockups/README.md) and this packet's [STATUS](STATUS.md) ledger.
