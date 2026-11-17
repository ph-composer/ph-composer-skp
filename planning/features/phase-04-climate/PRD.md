# Climate

DATE: 2026-09-18
STATUS: Requested. Drafted 2026-09-18 as a post-MVP packet (D7 and D9 confirmed). All eight journeys (J1 to J8) walked by 2026-11-17. Revised 2026-11-16 to the wireframe review of 2026-11-15 and 2026-11-16 (W1 to W9): a Climate tab, climate data read from a folder on the user's computer, one climate copied into the Model. Not planned; no stage authorized.
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

Confirmed in the first journey walkthrough, 2026-11-17 (J1): the files stay where the user keeps
them and are never copied into a PH-Composer folder. A file added or changed in a folder, or a
whole new folder for a new year, shows the next time the picker opens, with nothing to import. The
settings file is the only thing PH-Composer keeps, and it sits outside SketchUp's own folders: an
extension's folder under SketchUp's Plugins is per SketchUp version and may be replaced when the
extension is reinstalled, so it is no home for a user's setting or data.

## What honeybee-ph and METr take

Verified on 2026-09-18 in `honeybee_ph/site.py` and PHX `to_METr_JSON/metr_schemas.py`, `_PhxSite`.

- `Site` holds a `Location` (`latitude`, `longitude`, `site_elevation`, `climate_zone`,
  `hours_from_UTC`) and a `Climate`.
- `climate_zone` is an integer code, verified 2026-11-17 in the pinned honeybee-ph 1.33.65. The
  honeybee-ph Grasshopper component allows ten codes (1 Not defined; 11 to 18 for US zones 1 to 8;
  141 for 4C), and PHX passes the integer to WUFI and METr unchanged; both read from local
  checkouts, not pinned. No moisture letter is carried. `hours_from_UTC` is a required integer
  that PHX writes to METr; what METr does with it is not verified.
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
  copy), which are counted as not read and not shown as second stations;
- a second tree of one `.xls` workbook per station, for the USA and also for Canada and Japan,
  which have no text-file equivalent;
- two folders of older `.xls` station workbooks.

## Vocabulary

Proposed. `context/UBIQUITOUS_LANGUAGE.md`, "Site and climate", carries the planned terms.

| Term | Meaning |
| --- | --- |
| Site location | Where the building is: latitude, longitude, elevation, climate zone and hours from UTC. Separate from the station |
| Climate data folder | A folder on the user's computer holding climate files they are licensed to use, with a name the user gives it |
| Station | One location in a climate data folder, read from one file |
| Phius climate data | The Model's one climate: a station's values, or values typed by hand. It is what exports |
| Design temperatures | The ASHRAE 99% heating and 1% cooling dry-bulb temperatures for the site, typed by the user |
| Climate snapshot | The copy of the climate kept in the Model with its provenance. It reads without its source |

## Records

```
Model   gains  site     { latitude_deg, longitude_deg, elevation_m, climate_zone, hours_from_utc }
               climate  { name, station_latitude_deg, station_longitude_deg, station_elevation_m,
                          daily_temp_swing_k, wind_speed_m_s,
                          monthly { air_c[12], dewpoint_c[12], sky_c[12],
                                    rad_north_kwh_m2[12], east, south, west, global },
                          peak_loads { heat_1, heat_2, cool_1 }, each with a temperature, five
                                     radiation values, a dewpoint and a sky temperature,
                          as_read { the same values, as read from the station file },
                          provenance { dataset name, station name, checksum,
                                       ...honeybee-ph ClimateProvenance fields } }
               design_temperatures { heating_99_c, cooling_1_c, source note }

This computer  climate data folders  [ { name, folder location } ]   in PH-Composer's settings file
               last dataset used                                        in the same file
```

A Model holds one site, one climate and one pair of design temperatures (W6). A site is set when
it has a latitude, a longitude and an elevation; `climate_zone` and `hours_from_utc` may be unset
(J2). `climate_zone` is one of the ten codes the honeybee-ph Grasshopper component allows; whether
the Model stores the code (15) or the zone (5) is a planning decision. The climate is a
copy: the Model never needs the source again to be read. A Phius station's three peak-load cases
are the complete set; the second cooling case and the monthly ground temperatures stay empty and
are not flagged (W8). The station's latitude and longitude are kept so the limit check can be
shown without the folder; honeybee-ph's `Climate` has no field for them (verified in the pinned
1.33.65), so they are the Model's own and where they export is a planning question (J3).
`wind_speed_m_s` is typed, prefilled with the mean of the file's January and
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

- A new Model has no site. The Site location card reads Not set and its pane offers Set Location
  (J2).
- Latitude, longitude, elevation, climate zone and hours from UTC are typed in a Set Location
  dialog (W2, J2). The dialog holds the outline map; clicking it places the site and fills
  latitude and longitude (W1).
- Latitude, longitude and elevation are needed before the site is set: the station check uses
  all three. Climate zone and hours from UTC are for export and may be left unset; export reports
  an unset one (J2).
- Climate zone is chosen from Not defined, 1, 2, 3, 4, 4C, 5, 6, 7 and 8. There is no moisture
  letter, because the export cannot carry one (J2).
- Hours from UTC is typed. It is never guessed from the longitude (J2).
- Read from SketchUp Geolocation fills latitude and longitude once, and hours from UTC if the
  host supplies a usable offset (open item 13). It does not fill elevation: SketchUp's API
  reference documents none. Nothing is written back to SketchUp, and nothing syncs on its own (Q5, Q6).
- There is no address search and no elevation or climate-zone lookup: the panel reaches no network.

### Climate data on this computer

- A dialog, opened from the Climate tab and listed in the Setup view with a one-line summary (W5).
- It lists each climate data folder with its name, its location, the format found, the number of
  stations and states, and the files it did not read, grouped by kind (for example "1,150 Excel
  files, 4 other") so a folder that also holds other formats does not read as a failure. Add
  Folder and Remove. There is no Rescan: the counts are read when the dialog opens (J1).
- A setting whose folder cannot be found says so, with Locate to point it at the new place once
  and Remove. PH-Composer never removes a setting itself: the folder may be on a drive that is
  not connected. Its stations are left out of the picker meanwhile. Models are unaffected (J6).
- Adding a folder asks for its name, prefilled from the folder's own name. That name is the
  dataset name the Model and the Export report show (W5).
- The first version recognises Phius station files only. Anything else in a folder is counted as
  not recognised (W5).
- The dialog says what is kept where: the folder's location and name on this computer; station
  files read when needed; only the attached station in a Model.

### Choosing a station

- With no climate data folder on the computer, the Phius climate data pane says so, says why
  PH-Composer ships none, and offers Choose Climate Data Folder and Enter Values by Hand.
- With no site set, the pane asks for the site first and offers Set Location; the picker does
  not open without one. Enter Values by Hand does not need the site (J3).
- With a folder and a site and nothing attached, the pane names the dataset and its station
  count and offers Choose Station and Enter Values by Hand (J3).
- The picker shows every recognised station on the outline map with the site and a ring at
  Phius's distance limit, and the same stations in a list with distance, elevation difference and
  a Pass or Fail verdict. A station passes within 50 miles (80 km) and 400 feet (122 m) of the
  site; outside either it fails. Both limits are Phius's (Certification Guidebook 2024, section
  1.4.4.2, read in BLDGTYP's rules corpus on 2026-11-17).
- The picker opens sorted by distance, with the map framed on the 50 mile ring and State set to
  All (J3).
- Find Nearest returns to that view. A State filter narrows the list; a state is the name of the
  folder a station file sits in.
- The picker shows one dataset at a time. It opens on the dataset the attached station came
  from, else the one last used on this computer; Dataset changes it (J3).
- A failing station can be attached, with no confirm step. The picker says before Attach that it
  is outside the Phius limits, and the card, the pane and the Export report then show it so.
  Phius asks for a custom dataset beyond the limits and names exceptions, so PH-Composer reports
  and does not block (J3).
- On the map: pan and zoom, click a station to select it, hover for its name, distance, elevation
  difference and verdict (W1).
- Attach copies the station into the Model. With a station already attached, the picker shows
  the current and the new station side by side (dataset, distance, elevation difference and
  verdict) and says when edited values will be lost; Attach becomes Replace, in one Undo step
  (J7).

### An attached climate

- The pane shows the station and dataset, the limit check (distance and elevation against the
  Phius limits), monthly temperatures, monthly radiation, peak loads, the wind speed, and a
  "Where this lives" block: what the Model holds, whether the source is on this computer, and
  what the climate is ready for.
- Values may be edited after attaching. The source is then marked as edited on the tab and in the
  Export report. Replace restores the file's values (W8).
- The Model keeps the values as read from the file beside the edited ones. Edited cells are
  marked on the pane, the Export report lists them, and Restore Original Values works on any
  computer. Wind speed never counts as an edit, and a hand-entered climate has no edited mark
  (J7).
- The limit check is never stored. It is worked out from the site and the station each time, so
  a site change re-evaluates it. Set Location shows the attached station and its ring on the map
  and says before Set when the change would make the station fail (J7).
- Clear removes the climate in one Undo step with no confirm. The site and the design
  temperatures stay (J7).
- Enter Values by Hand starts the same record with no station (Q7, W3). Its editor is one grid in
  the order of a Phius climate file: eight series rows (outdoor temperature, north, east, south,
  west, global, dewpoint, sky), twelve months, then Heating 1, Heating 2 and Cooling. One paste
  from a Phius workbook fills it, and any cell can be typed (J4).
- Above the grid: a name and the station elevation, both needed; the daily temperature swing and
  the average wind speed, typed with no prefill; and an optional latitude and longitude. With
  coordinates the Phius limit check runs as for a station; without them it reads "Not checked,
  entered by hand", on the tab and in the Export report (J4).
- A hand-entered climate saves with gaps. It is then marked Incomplete on its card, the pane
  lists what is missing, and export leaves the climate out with a finding until it is complete
  (J4).
- The same editor opens for Edit Values on an attached station (J4; the edited mark is W8).
- On a computer with no climate data folder the pane reads in full from the Model, with no
  notice and nothing held back at export. Edit Values, Clear and the design temperatures work on
  the Model's copy. Replace stays enabled; with no folder it explains and offers Choose Climate
  Data Folder and Enter Values by Hand (J6).
- The source of an attached station is looked for by station name and state in every climate
  data folder on the computer, whatever the folder is named. The same checksum reads Source
  found; a different one, Source changed; none, Not on this computer (J6).
- When the source file is on this computer and differs from the Model's copy, a quiet "source
  changed" mark appears, with an Update from File action that is Replace with the same station.
  Nothing updates on its own (J7).

### Design temperatures

- Two typed values, the ASHRAE 99% heating and 1% cooling dry bulb, on their own card (W4). A
  Phius station file carries neither.
- They are typed in the card's pane, not a dialog. Each saves as it is committed and is its own
  Undo step; clearing a field unsets it. The unit toggle applies, and the Model stores °C (J5).
- An optional source note, free text, is kept with them and repeated in the Export report (J5).
- The card reads Not set, Incomplete when one of the two is typed, or Set. A heating value at or
  above the cooling value shows a warning and still saves (J5).
- They stay in the Model. honeybee-ph has no field for them (verified in the pinned 1.33.65) and
  nothing is written to METr in the first version (J5).
- Export does not wait on them. Without them only the Mechanical phase's blended heat pump is
  left out, with a finding (W4).

### Export

- Export writes `Site` to the HBJSON and names the source in the Export report by dataset and
  station name, never by a folder location.
- The Export report's climate section gives the site, the dataset and station, the limit check,
  any edited values, the peak-load cases, the wind speed, and the design temperatures with their
  source note (J8).
- Cooling 2 is written as a repeat of Cooling 1, and the report says so. honeybee-ph always
  carries four peak-load cases and would otherwise write 0 °C and zero radiation (run on a
  synthetic climate in the pinned 1.33.65, 2026-11-17); its Grasshopper Phius-file component
  repeats the cooling case the same way (read in the local checkout). This is the file's own
  cooling case, not a synthetic one. The tab still shows Cooling 2 as not part of a Phius file
  (W8, J8).
- The ground row needs nothing: PHX writes METr's monthly ground temperatures as not a number for
  every model (read in the PHX checkout, not run) (J8).
- An unset climate zone is written as Not defined and an unset hours from UTC as empty, each
  with a finding in the report. No guessed value is written (J8).
- Provenance, in honeybee-ph's `ClimateProvenance`: an unedited station is `phius_approved`; an
  edited station and a hand-entered climate are `user_defined`. The source name gives the dataset
  and station, and the checksum is the file's. The station's coordinates and the list of edited
  values go in its assumptions. `source_uri` is never written, and `is_certification_approved`
  stays unknown (J8).
- An incomplete climate is left out with a finding (J4). The design temperatures are reported
  and not written to the HBJSON (J5).
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

The journey walkthroughs. One journey at a time, with Ed.

| # | Journey | Kind | Answer |
| --- | --- | --- | --- |
| J1 | A new user points PH-Composer at the climate files on their computer, 2026-11-17 | UI, Code | Done from the Climate tab's empty state, or the Climate Data on This Computer dialog, or the Setup view: choose a folder, name it, see what was found. Set once per computer, for every Model. Files are read in place and never copied; new and changed files show the next time the picker opens; no Rescan. The settings file sits in a PH-Composer folder under the user's application-support folder, outside SketchUp's versioned folders. Files not read are reported by kind. A cache of what was read, refreshed by each file's modified date and never managed by the user, is added only if reading proves slow |
| J2 | Setting the site location, 2026-11-17 | UI, Code | A new Model has no site; the card reads Not set. Set Location holds the map: click to place, or type. Latitude, longitude and elevation are needed to set the site; climate zone and hours from UTC are for export and may be unset. Climate zone is the ten integer codes the honeybee-ph Grasshopper component allows (Not defined, 1 to 8, 4C), with no moisture letter. Hours from UTC is a typed field, never guessed from longitude. Read from SketchUp Geolocation fills latitude and longitude, and hours from UTC if the host supplies an offset (open item 13); it does not fill elevation. The pane's "Set by" line is dropped: no field records it. What a site change does to an attached station's verdict is left to J7 |
| J3 | Choosing and attaching a station, 2026-11-17 | UI, Code | The site comes first: with none, the Phius climate data pane asks for it and the picker does not open. The picker opens sorted by distance, framed on the 50 mile ring, on one dataset at a time (the attached station's, else the last used on this computer). A failing station can be attached with no confirm; the picker, the card, the pane and the Export report say it is outside the Phius limits. The Model keeps the station's latitude and longitude so the check shows without the folder. Both limits are cited from the Phius guidebook |
| J4 | Entering values by hand, 2026-11-17 | UI, Code | One grid in the order of a Phius climate file (eight series rows, twelve months, three design columns), filled by one paste from a Phius workbook or typed. It saves with gaps and is marked Incomplete; export leaves an incomplete climate out, with a finding. Name and station elevation are needed; latitude and longitude are optional, and without them the limit check reads "Not checked, entered by hand". Wind speed has no prefill. The same editor serves Edit Values on an attached station |
| J5 | The design temperatures, 2026-11-17 | UI, Code | Typed in the card's pane, each field saved as it is committed, with an optional source note the Export report repeats. Not set, Incomplete or Set; a heating value at or above the cooling value warns and still saves. Stored in °C, shown by the unit toggle. Model only for now: nothing goes to METr, and the two METr fields PHX writes fixed values to are an open item |
| J6 | Opening the Model on another computer, 2026-11-17 | UI, Code | The Model reads in full with no notice; only "Where this lives" says the source is not on this computer. Edit Values and Clear need no folder. Replace stays enabled and, with no folder, explains and offers the empty state's two choices. The source is matched by station name and state plus checksum across every folder on the computer, not by the dataset's name. A folder that cannot be found keeps its setting and offers Locate and Remove |
| J7 | Replacing and editing an attached station, 2026-11-17 | UI, Code | The Model keeps the as-read values beside the edited ones: edited cells are marked, the Export report lists them, and Restore Original Values works anywhere. Replace shows a summary of the current and the new station and warns when edits will be lost; one Undo step. A changed source file shows a quiet mark and Update from File. The verdict is never stored: a site change re-evaluates it, and Set Location shows the attached station and warns before a change that would make it fail. Clear is one Undo step with no confirm |
| J8 | Export, 2026-11-17 | UI, Code | The report's climate section names site, dataset and station, limit check, edits, peak loads, wind speed and design temperatures. Cooling 2 repeats Cooling 1, since honeybee-ph cannot leave it empty and would write zeros. An unset climate zone exports as Not defined and an unset UTC offset as empty, each with a finding. An unedited station is `phius_approved`; an edited station and a hand-entered climate are `user_defined`. Station coordinates and edits travel in the provenance's assumptions. No folder location and no `source_uri` are written |

Every journey listed on 2026-11-17 is walked.

## Open, and owed before planning

1. Which tab the panel opens on now that Climate is first. Zones is where most work happens.
2. Settled by J3: a failing station can be attached, and is reported as outside the Phius limits.
3. To verify on a host: that SketchUp's preferences are kept per SketchUp version, which was the
   reason for a separate settings file; and where that file sits on macOS and Windows.
4. The outline map: its data source and licence confirmed, its size in the RBZ, and how it draws
   on the Chromium 88 floor.
5. Settled by J8: Cooling 2 repeats Cooling 1 at export and the ground row needs nothing. Still
   to confirm in METr or with Phius: that a repeated cooling case is what a Phius dataset should
   give, and PHX's handling end to end, which was read and not run.
6. Settled by J3: both limits are cited from the Phius Certification Guidebook 2024, section
   1.4.4.2. The same section names a New York City exception, which PH-Composer does not model.
7. Hours from UTC is settled as a typed field (J2). Still to verify: what METr does with the
   value, and that PHX writes a zero offset (read in the PHX checkout: a zero is written as not a
   number; not reproduced). An unset offset exports empty, with a finding (J8); honeybee-ph
   round-trips an empty offset (run in the pinned 1.33.65).
8. Not drawn: Read from SketchUp Geolocation when the Model has no geolocation, an attached
   station that fails, the pane of a hand-entered or incomplete climate, Set Location with a station attached, the Export tab's own layout
   around the report's climate section, scanning in progress, charts, the 360 x 520 panel size.
9. What the blended heat pump reads beyond the two design temperatures. The Phius estimator also
   uses the monthly mean temperatures, which the climate holds; the Mechanical phase binds this.
10. Stations outside the USA. The private corpus has Canadian and Japanese stations only as `.xls`
    workbooks, which the first version does not read (W5), so they cannot be attached except by
    typing values in. Whether an `.xls` reader joins the first version is not asked.
11. Whether the user is told about new stations, for example "12 stations added since you last
    looked". It needs a count remembered per folder. New files appear either way (J1).
12. To measure before planning: how long reading a full dataset takes when the picker opens.
    Measured 2026-11-17: the private corpus's 1,007 station files, 1.2 MB, read in 0.15 s in
    Python with the files already on disk. Still to measure: Ruby inside SketchUp, and a
    cloud-synced folder whose files are not downloaded.
13. To measure on a host (J2): what SketchUp reports for latitude and longitude in a Model with
    no geolocation, whether `Model#georeferenced?` tells the two apart, whether its `TZOffset` is
    a usable hours-from-UTC, and whether a geolocated Model exposes an elevation. SketchUp's API reference lists `Latitude`, `Longitude`
    and `TZOffset` on `ShadowInfo` and documents no defaults and no elevation (read 2026-11-17).
14. Confirm the ten climate-zone codes against METr or WUFI-Passive. The list was read in the
    honeybee-ph Grasshopper component; honeybee-ph and PHX take any integer.
15. A custom dataset bought from Phius: confirm the format Phius delivers it in. If it is a
    station file, it goes in a climate data folder and needs no typing.
16. The paste: confirm on real copies from a Phius `.xls` workbook and a text file that one
    block fills the grid. In the private corpus's text files all eight series rows carry the
    three design columns (200 files checked for presence only, 2026-11-17). One workbook was read
    for cell types only: its row labels and order were not seen, and two of its series rows held
    twelve values.
17. METr's site block has `hDesDryT` and `cDesDryT`, to which PHX writes 0.0 and 24.0 (read in
    the PHX checkout, 2026-11-17). Verify whether they are the ASHRAE design dry bulbs and what
    METr does with them before any export of the typed values is planned (J5).
18. Export with a climate and no site. Hand entry does not need the site (J3), and honeybee-ph's
    `Location` defaults to a latitude and longitude of its own. Decide whether the climate is
    left out with a finding, as an incomplete one is.

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
site by typing, by clicking the map, and by reading SketchUp's geolocation and typing the elevation; open the picker and find the nearest
station, with a passing and a failing verdict at the stated limits; attach one; save, remove the
folder's setting and reopen, and confirm the climate reads in full and Replace asks for a folder;
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
