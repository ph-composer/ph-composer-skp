# Phase 4 contracts: Climate records, the settings file, the reader and export

DATE: 2026-11-17
STATUS: Scoped for P4c-01 to P4c-11; sections 2 to 7 implemented (P4c-01 to P4c-05), sections 2, 3, 6 and 7 amended in their stages (section 2 in P4c-06). Contract questions C4c-1 to C4c-6 settle in their stages. Not reviewed against the code by a second reader.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The data structures the [PRD](PRD.md) needs, who owns each, and the seams between them. Names here
bind the stages in [PLAN](PLAN.md). `context/CONTRACTS.md` and `context/EXTENSIBILITY.md` are
canonical for the engine rules cited; this file says how Climate uses them, and each stage folds
what it lands back into `context/`.

There are no users yet, so no migration: a schema that changes moves its version and the test
fixtures are rewritten (Ed, standing guidance). Paths are relative to `src/ph_composer/`.

Evidence labels used below: **run** means executed in this repository's `.venv` against the pinned
honeybee-ph 1.33.65 on 2026-11-17; **read** means read in that wheel's source; **PHX, read** means
read in the local PHX checkout at 1.59.1, which is not pinned and not in the `.venv`.

## 1. Feature and ownership

| Feature | Requires | Owns |
| --- | --- | --- |
| `ph_composer.climate` (new, P4c-01) | `ph_composer.zones`, for the export section only | The site, the climate and the design temperatures of a Model; climate data folders on this computer; the Phius station reader; the Climate tab; the `Site` export section |
| Foundation (`shell/`) | | The per-computer settings file (section 5); it names no feature |
| UI kit (`html/`) | | The outline map and the source cards (P4c-06, P4c-07); no domain rule |

Climate is not a Library kind and registers no library provider or kind (W6). Layout:
`features/climate/install.rb`, with `site/`, `climate/`, `folders/`, `stations/`, `export.rb`,
`codes.rb` and `declarations/`, following `features/thermal_bridges/`. Panel modules live in
`html/features/climate/`.

Domain calculations are Ruby (the limit check, completeness, edited cells, the wind-speed
prefill, distances). The panel formats and routes. The Python section builds honeybee-ph objects
from the contract record and computes nothing.

## 2. The site and the design temperatures (P4c-01)

Two `ModelSettings` dictionaries (D4c-02, amended at P4c-01): `ph_composer.climate_site` holds the
first five fields and `ph_composer.climate_design_temperatures` the last three, so each update guards
only its own fields. Every field is nullable and defaults to null; reads never write.

| Field | Type | Unit | Rule |
| --- | --- | --- | --- |
| `latitude_deg` | number or null | degrees | -90 to 90 |
| `longitude_deg` | number or null | degrees | -180 to 180 |
| `elevation_m` | number or null | m | finite |
| `climate_zone` | integer or null | | One of 1, 11 to 18, 141: the WUFI code (R7). Null is unset; 1 is the user's choice of Not defined |
| `hours_from_utc` | integer or null | h | -12 to 14. Never derived from longitude (J2) |
| `heating_99_c` | number or null | °C | The ASHRAE 99% heating dry bulb |
| `cooling_1_c` | number or null | °C | The ASHRAE 1% cooling dry bulb |
| `design_temperature_source` | string or null | | Free text, the optional source note (J5) |

Derived, never stored:

- **Site state**: `set` when latitude, longitude and elevation are all present, else `not_set`. A
  write that would leave one or two of the three present refuses `validation.failed`.
- **Design temperature state**: `not_set`, `incomplete` (one of two) or `set`; a `warning` when
  heating is at or above cooling, which still saves (J5).

Operations. Each is one Undo step, guarded by the values last read (`expected_values`), as
`ph_composer.spaces.settings.update` is.

| Name | Kind | Does |
| --- | --- | --- |
| `ph_composer.climate.site.get` | query | The five site fields and the site state |
| `ph_composer.climate.site.update` | action | Sets the five site fields together (Set Location). Result carries the limit check after the change |
| `ph_composer.climate.site.geolocation` | query | What SketchUp reports for the Model: `{ geolocated, latitude_deg, longitude_deg, hours_from_utc }`. Latitude and longitude only when `Model#georeferenced?` is true; `hours_from_utc` always null until a host run proves what Add Location writes to `TZOffset`; never an elevation. Reads only; nothing is written to SketchUp or to the Model (Q5, Q6). Shape fixed by owed check 4 (P4c-06) |
| `ph_composer.climate.site.preview_limit_check` | query | The limit check the attached station would get at a proposed site, for Set Location's warning (J7) |
| `ph_composer.climate.design_temperatures.get` | query | The two values, the note, the state and the warning |
| `ph_composer.climate.design_temperatures.update` | action | Sets any of the three; null unsets one |
| `ph_composer.climate.summary` | snapshot section | The three cards' states, for the sidebar, backed by the query `ph_composer.climate.summary.get` |
| `ph_composer.climate.site`, `ph_composer.climate.design_temperatures` | snapshot sections | The two reads above, so the Climate tab paints its cards' values and its panes without a query of its own (added in P4c-06) |

## 3. The climate record (P4c-02)

One record kind, `ph_composer.climate.climate`, id prefix `clm`, held under one fixed id as the
Zones option settings are (D4c-02). No record means no climate; Clear deletes it.

```
name                     string            the station's name, or the name typed by hand
origin                   "station" | "hand"
station_latitude_deg     number | null     null only when entered by hand without coordinates
station_longitude_deg    number | null
station_elevation_m      number            needed
daily_temp_swing_k       number | null
wind_speed_m_s           number | null
monthly                  { air_c, dewpoint_c, sky_c,
                           rad_north_kwh_m2, rad_east_kwh_m2, rad_south_kwh_m2,
                           rad_west_kwh_m2, rad_global_kwh_m2 }        each 12 of number | null
peak_loads               { heat_1, heat_2, cool_1 }                    each
                           { air_c, dewpoint_c, sky_c,
                             rad_north_w_m2, rad_east_w_m2, rad_south_w_m2,
                             rad_west_w_m2, rad_global_w_m2 }          each number | null
as_read                  null for origin "hand"; for a station, the file's own
                           { station_elevation_m, daily_temp_swing_k, monthly, peak_loads }
provenance               { dataset_name, station_name, state,      these three and
                             the checksum are null for origin "hand"
                             source_type, source_name, source_version, source_checksum,
                             conversion_method, conversion_method_version,
                             is_certification_approved,
                             monthly_data_available, peak_load_data_available,
                             assumptions }
user_data, extension_data, schema_version                              as every record
```

Rules:

- **No path.** The record holds no folder location, and `provenance` is all the Model knows of
  the file (the PRD's snapshot rule). honeybee-ph's `source_uri` is not a field of the record.
- **No ground temperatures and no second cooling case** are stored (W8). Export supplies both
  (section 7).
- **Provenance is stored, in honeybee-ph's shape** (D4c-03, Ed's ruling): the fields after
  `state` are honeybee-ph's `ClimateProvenance`, with the values of the table in section 7, and
  export passes them through. `attach_station`, `enter_values`, `save_values` and `restore_original` each write
  the values and the provenance together in one Undo step, so the source type and the list of
  edited values in `assumptions` cannot disagree with the values. `source_checksum` is the
  file's SHA-256.
- **Wind speed**: attaching a station sets it to the mean of the file's January and July values;
  hand entry leaves it null. A wind-speed change is never an edit (W8, J7).
- **Edited cells** are derived: every `monthly`, `peak_loads`, `daily_temp_swing_k` and
  `station_elevation_m` value that differs from `as_read`. A hand-entered climate has none.
- **Complete** (D4c-08): name, station elevation, daily temperature swing and wind speed present;
  all 96 monthly values present; in each of the three cases the air temperature and five
  radiation values present. A case's dewpoint and sky temperature may be null: honeybee-ph allows
  it (read) and its readiness check does not ask for them (read). An incomplete climate lists
  what is missing by row and column.
- **Stale edits refuse.** Every write is guarded by the record last read.

Operations, each one Undo step:

| Name | Kind | Does |
| --- | --- | --- |
| `ph_composer.climate.climate.get` | query | `state` (`none`, `incomplete`, `complete`), the record under `climate` (null when there is none), `missing` by row, `edited_cells` by row and column, and `limit_check` |
| `ph_composer.climate.climate.enter_values` | action | Creates a hand-entered climate (Enter Values by Hand). Saves with gaps. Refuses `target.changed` when the Model already holds one |
| `ph_composer.climate.climate.save_values` | action | Changes the values of the climate in the Model (Edit Values). Saves with gaps. A station's name and coordinates refuse `validation.failed`: Replace changes them |
| `ph_composer.climate.climate.restore_original` | action | Copies `as_read` back over the values. Refuses `climate.no_original` for a hand-entered climate |
| `ph_composer.climate.climate.clear` | action | Deletes the record. The site and the design temperatures stay (J7) |

Attach, Replace and Update from File are `ph_composer.climate.climate.attach_station` (section 6).

Amended at P4c-02, 2026-11-17. The plan had one `save_values` with two Undo names, "Enter Climate
Values" and "Edit Climate Values", but an action declares one Undo name and the dispatcher opens
the operation under it, so the create is its own action, `enter_values`. Every write is guarded by
`expected_values`, the eight editable fields (`name`, the station's coordinates and elevation, the
daily swing, the wind speed, `monthly`, `peak_loads`) as last read. The writes answer the read's
fields without the record itself, so each declaration stays small enough to describe in one agent
reply; `climate.get` reads the record back. `missing` is grouped by row (`{ row, columns }`) and
an edited cell is `{ row, column }`, the values being in the record and its `as_read` copy, so a
station with every value edited reads in 17,826 bytes against the 24,576-byte reply. The record's
`user_data` is left out of `climate.get`, since it has no size bound; `ph_composer.records.detail`
reads it. The limit check allows a nanometre of floating-point slack at each limit, so a value
exactly on it passes (Codex review of PR #513). The record is
staged whole, since `Engine#propose_update` drops a key set to null.

## 4. The Phius limit check (P4c-02)

A pure Ruby function of the site and the station; never stored (J7).

- Distance: great-circle (haversine) on a sphere of mean radius 6,371.0088 km.
- Elevation difference: the absolute difference of `elevation_m` and `station_elevation_m`.
- Limits (D4c-04): 50 miles and 400 feet, held in SI as their exact conversions, 80.4672 km and
  121.92 m. At or inside both passes. Phius states the limits in miles and feet, so IP is the
  reference; the PRD's "80 km" and "122 m" are display labels (confirmed by Ed).
- Result: `{ verdict, distance_km, elevation_difference_m, distance_ok, elevation_ok }`, where
  `verdict` is `pass`, `fail` or `not_checked`. `not_checked` carries a reason: `no_site`, or
  `no_station_coordinates` for a hand-entered climate without them (J4). With neither, the reason is
  `no_station_coordinates`: no site can repair it (settled at P4c-02).

The limits are Phius's (PRD, "Choosing a station"). The New York City exception is not modelled.

## 5. This computer: the settings file (P4c-03)

A foundation service, `shell/computer_settings.rb` (D4c-05): one JSON file for PH-Composer on this
computer, placed outside SketchUp's versioned folders so that every SketchUp version can read it,
holding one section per feature id. Climate is its
first user. The Library's setup store, the approved locations and the display preferences stay in
SketchUp's preferences where they are.

- **Location**: a `PH-Composer` folder in the user's application-support folder, outside
  SketchUp's own folders: on macOS `~/Library/Application Support/PH-Composer/settings.json`. Owed
  check 1 confirmed it on SketchUp 2026. `Diagnostics.data_root` is not it: that sits inside
  SketchUp's versioned folder.
- **macOS only for now** (E3). The Windows location is not chosen, written or tested in this
  packet. On any other platform the service reports `climate.settings_unavailable` and the
  folder commands refuse with it; that behaviour is the plan's proposal, not part of Ed's
  answer. Choosing and verifying the Windows location is future work in
  the [Windows support](../unscheduled/windows-support/README.md) packet.
- **Shape**: `{ "schema_version": 1, "sections": { "<feature id>": { ... } } }`.
- **Writes**: read the file, change one section, write beside it and rename into place, all under
  an exclusive lock on a sibling `settings.lock` (D4c-17). Two SketchUp versions may be open at
  once; the last write wins for a section and never damages another.
- **Failure**: a file that cannot be read is left as stored and reported; a write that cannot be
  made refuses and the panel never shows "saved". Same rule as `shell/preferences.rb`.
- A file written by a later schema version is left as stored: this build neither reads nor writes
  it, and reports `climate.settings_unreadable` (D4c-17).
- The service names no feature: it raises `ComputerSettings::Refused` with a reason, and Climate's
  store maps it to `climate.settings_unreadable` or `climate.settings_unavailable` (D4c-17).

Climate's section:

```
folders          [ { id, name, location } ]     location is an absolute folder path
last_dataset_id  string | null                  the folder the picker opens on (J3)
```

`ph_composer.climate.folders.list` answers each folder as `{ id, name, display_location, found }`
and the `last_dataset_id`. The display location is C4c-1's answer (D4c-16): `~/` and the rest under
the home folder, the volume's name and the rest under `/Volumes/`, otherwise `…/` and the last two
names. Never an absolute path.

Setup commands (the `setup` capability; none touches a Model or adds an Undo step):

| Name | Does |
| --- | --- |
| `ph_composer.climate.folders.add` | Opens the folder chooser through `NativeApproval` (`open_folder`), stores the folder with its own name as the dataset name, and answers the new row. The path never travels in params or logs |
| `ph_composer.climate.folders.rename` | Sets the dataset name. The panel opens the name for editing right after Add, prefilled, which is the PRD's "asks for its name" (W5) |
| `ph_composer.climate.folders.locate` | Opens the chooser and points an existing setting at a new place (J6) |
| `ph_composer.climate.folders.remove` | Removes the setting. PH-Composer never removes one itself |
| `ph_composer.climate.folders.remember_dataset` | Stores `last_dataset_id` |

The Setup view entry is `feature.menu_item(..., in_setup: true, summary:)`, registered in P4c-08
with its dialog, summary such as "1
folder, 1,007 stations" or "No climate data folder" (W5). Agent Access is the only entry today,
so this is the second user of that contract.

## 6. The station reader and what is read from disk (P4c-04)

**One built-in reader**, a pure Ruby module (`features/climate/stations/phius_station_file.rb`):
bytes in, a parsed station or a typed failure out, no SketchUp constant. No registered format
contract (W6).

- Recognised: a file named `<STATION>-mon.txt` that parses as a Phius station file. Bytes are
  read as Windows-1252 and converted to UTF-8.
- Parsed: the header (name, latitude, longitude, height above sea level, summer daily temperature
  variation), eight series rows of twelve monthly values and three design columns, and the
  January and July wind speeds. The exact labels and columns are fixed in P4c-04 from the
  structure notes in the PRD; no file content enters the repository.
- A station's **state** is the name of the folder its file sits in. Its **key** is that folder
  name and the file name, a path relative to the climate data folder.
- **Checksum**: SHA-256 of the file's bytes, the form honeybee-ph's `source_checksum` documents
  (read).
- Everything else under a folder is counted as not read, grouped by kind (extension), including
  a `-mon.txt` file that does not parse.

Queries. They read the disk and never the Model's revision; none returns a monthly value or an
absolute path (D4c-06):

| Name | Returns |
| --- | --- |
| `ph_composer.climate.folders.list` | Each folder: id, name, a display location (C4c-1), found or not found, format, station count, state count, files not read by kind |
| `ph_composer.climate.stations.list` | For one folder: each station's key, name, state, latitude, longitude and elevation, with distance, elevation difference and verdict against the Model's site |
| `ph_composer.climate.climate.source_status` | For the attached station: `found`, `changed` or `not_on_this_computer`, matched by station name and state across every folder, then by checksum (J6). `not_applicable` for a hand-entered climate |

One action writes the Model:

| Name | Does |
| --- | --- |
| `ph_composer.climate.climate.attach_station` | Params: folder id and station key. Ruby reads the file, builds the record of section 3 with `as_read`, `provenance` and the wind-speed prefill, and writes it in one Undo step. With a climate already in the Model it replaces it (Replace, and Update from File with the matched source). Refuses when the site is not set (J3), the file is gone or the file does not parse |

The station's values go from the file to the Model inside Ruby. They do not pass through the
panel, so attach works with the panel closed and an agent can drive it.

**Read time** (D4c-11, owed check 3): the list is read when the picker or the dialog opens, with
no index (W5, J1). The stage measures it in SketchUp's Ruby. A read over 0.5 s is sliced with
`DeferredWork` so the panel stays live; a cache keyed by each file's modified date is added only
if a warm read of a real-size folder still exceeds 2 s.

Amended at P4c-04, 2026-11-18. Owed check 3 measured 0.06 to 0.08 s for 1,007 station files in
SketchUp 2026's Ruby ([evidence](evidence/owed-check-3-20261118.md)), so the read is synchronous
with no cache, and bounded instead (D4c-21). The matching name is the file's stem (C4c-2, D4c-18).
A station's key is its path inside the climate data folder, and `stations.list` is paged nearest
first (D4c-20). The one action of the table above is two, `climate.attach_station` and
`climate.replace_station`, each with its own Undo name (D4c-19); Update from File is
`replace_station` with the key `source_status` gives. `folders.list` adds `format`,
`station_count`, `state_count`, `files_not_read` (`{ extension, count }`, most first, at most
20), `files_not_read_total` and `complete`, all null for a folder not found. `source_status`
answers `{ status, folder_id, station_key }` and reads `not_applicable` with no climate too.
The refusals are `climate.site_not_set`, `climate.folder_not_found`, `climate.station_not_found`
and `climate.station_unreadable`. The reader's exact rules are in `context/CONTRACTS.md`, "The
Phius station reader".

Amended at P4c-09, 2026-11-18. `stations.all` (API 1.68) answers `stations.list`'s rows for one folder
in one unbounded read, for the station picker (D4c-30). Agents page `stations.list`.

## 7. Export: the `Site` section (P4c-05)

honeybee-ph holds `Site` on each `BldgSegment`, builds a default one for every segment and always
serializes it (read). Today the translation leaves that default in place, so every exported
HBJSON already carries a `site` with honeybee-ph's defaults: latitude 40.6, longitude -73.8, hours
from UTC -4, climate zone 1, a climate named "New York" with zero values and no provenance (run).
"No `Site` is written" in the PRD therefore means "honeybee-ph's default is left in place". The
`Site` cannot be removed: a Building Segment with no `site` key fails to load with
`KeyError: 'location'` (run).

Ed's rule (E1, E2 in [DECISIONS](DECISIONS.md)) is to match honeybee-ph and its Grasshopper
components, where each part of a `Site` that is not supplied keeps honeybee-ph's default and
nothing is said about it:

| The Model has | `Location` | `Climate` | Finding |
| --- | --- | --- | --- |
| No site, no climate | honeybee-ph's default | honeybee-ph's default | None |
| A site, no climate | Written | honeybee-ph's default, no provenance | None |
| A site, an incomplete climate | Written | honeybee-ph's default, no provenance | `climate.incomplete` (J4) |
| A site, a complete climate | Written | Written, with its provenance | None for this |
| A climate, no site | honeybee-ph's default | honeybee-ph's default | `climate.site_not_set` (R2) |

**Contributor**: `ph_composer.climate.export.site`, section version 1, `requires:` the Zones
section. It emits one record:

```
{ id: "Site",
  location:  { latitude_deg, longitude_deg, elevation_m, climate_zone, hours_from_utc } | null,
  climate:   the record of section 3, values only, with cool_2 added as a copy of cool_1, | null,
  climate_left_out: null | "site_not_set" | "incomplete",
  provenance: the record's provenance, honeybee-ph's fields only, | null,
  report:    { limit_check, edited_cells, design_temperatures, design_temperature_source } }
```

`location` is null when the site is not set. `climate` and `provenance` are null when there is no
climate, when it is incomplete (J4), or when the site is not set (R2); `climate_left_out` gives
the reason in the last two cases and is null when the Model simply has no climate. C4c-4 settles
whether a record with both null is emitted or the report reads those facts another way.

**Python section**: `SiteSection` in `python/ph_composer_translation/site_sections.py`, listed in
`composition.py` after `ZoneSection`, attached at `MODEL`, `required_for_export = False`
(D4c-07). In `attach` it builds one honeybee-ph `Site` from the parts the record carries,
`Site(location, climate)` with `None` for a null part so that honeybee-ph supplies its default,
and sets it on every distinct `ph_bldg_segment` the Rooms share. With both parts null it sets
nothing. A Model holds one site, so every Building Segment gets the
same one. It does not use the `segment` attachment host the Programs packet plans; Climate lands
first.

Mapping:

| Model | honeybee-ph | Note |
| --- | --- | --- |
| `latitude_deg`, `longitude_deg`, `elevation_m` | `Location.latitude`, `.longitude`, `.site_elevation` | |
| `climate_zone` | `Location.climate_zone` | Null writes 1, Not defined, with a finding (J8) |
| `hours_from_utc` | `Location.hours_from_UTC` | Null writes `None`, with a finding. `Location` accepts and round trips `None` (run). PHX then writes not a number to METr (PHX, read) |
| `name` | `Climate.display_name` | |
| `station_elevation_m`, `daily_temp_swing_k`, `wind_speed_m_s` | `Climate.station_elevation`, `.summer_daily_temperature_swing`, `.average_wind_speed` | |
| `monthly` air, dewpoint, sky | `monthly_temps.air_temps`, `.dewpoints`, `.sky_temps` | |
| ground temperatures | `monthly_temps.ground_temps` | Not written; honeybee-ph's zeros stay (run). PHX writes METr's monthly ground row as not a number for every model (PHX, read) |
| `monthly` radiation | `monthly_radiation.north`, `.east`, `.south`, `.west`, `.glob` | kWh/m² |
| `peak_loads.heat_1`, `.heat_2`, `.cool_1` | `peak_loads.heat_load_1`, `.heat_load_2`, `.cooling_load_1` | W/m² |
| a copy of `cool_1` | `peak_loads.cooling_load_2` | J8, R5. The report says so |
| `provenance` | `Climate.provenance` | Below. Passed through as stored (D4c-03) |

Provenance (`ClimateProvenance`, read), as the record stores it and the export writes it:

| Field | Value |
| --- | --- |
| `source_type` | `phius_approved` for an unedited station; `user_defined` for an edited station or a hand-entered climate (J8) |
| `source_name` | Dataset name and station name; the typed name for a hand-entered climate |
| `source_checksum` | The file's SHA-256; null for a hand-entered climate |
| `source_uri` | Not a field of the record and never written (J8) |
| `source_version`, `conversion_method`, `conversion_method_version` | Null (J8) |
| `is_certification_approved` | Left `None`, unknown (J8) |
| `monthly_data_available`, `peak_load_data_available` | Both `True`. Once a climate carries a provenance, PHX refuses the conversion unless both are true and every monthly and peak value is finite (PHX, read; honeybee-ph's two readiness lists come back empty for this shape, run) |
| `assumptions` | `{ "ph_composer": { station_latitude_deg, station_longitude_deg, edited_values, cooling_load_2: "repeats cooling_load_1" } }`. A dict of this shape round trips (run). Export adds the `cooling_load_2` line, since the second cooling case is itself added at export; the rest is stored |

**Findings.** All are non-blocking (`blocks_export: false`): a Model exports without a climate,
as it does today. A Model with no climate, with or without a site, gives no finding (E1, E2). Codes are declared in `features/climate/codes.rb` under the noun `climate`:

| Code | When |
| --- | --- |
| `climate.site_not_set` | A climate is in the Model and the site is not set. The climate is left out and honeybee-ph's default `Site` stays (R2) |
| `climate.incomplete` | The climate has gaps. It is left out; the `Location` is still written when the site is set. The message counts what is missing (J4) |
| `climate.zone_not_set` | The site is set and its climate zone is not; written as Not defined (J8) |
| `climate.utc_offset_not_set` | The site is set and its hours from UTC is not; written empty. Informational (R6) |
| `climate.outside_phius_limits` | The attached station fails the limit check (J3) |
| `climate.not_checked` | A hand-entered climate without coordinates: "Not checked, entered by hand" (J4) |

The preflight query is `ph_composer.climate.export_preflight`, returning
`Export::PREFLIGHT_RESULT`. A finding's `locate` is a registered operation's name and params
(`export/preflight_result.rb`). Whichever of P4c-05 and P4c-06 merges second adds one that opens
the Climate tab at the card that repairs the finding, after checking what a `locate` may name.

**Result fields and conformance.** The section declares, through `Export::Privacy`, the fields
the report renders: the location, the climate's name, dataset and station names, source type,
the limit check, the edited cell list, the wind speed, the four peak-load temperatures, and the
count of Building Segments written. No field is named `path` or holds one. Conformance: in the
reloaded HBJSON every Building Segment's `site` equals the record in each part the record
carries and honeybee-ph's default in each part it does not, and Cooling 2 equals Cooling 1.

**The report's climate section** (board 18), rendered in Ruby by the contributor's `report:`:
site; dataset and station; the limit check; edited values, each with its as-read value; the three
peak-load cases and the line that Cooling 2 repeats Cooling 1; the wind speed; the design
temperatures with their source note, marked as kept in the Model and not written to the HBJSON
(J5). When the climate is left out for a reason (`climate_left_out`) the section says why. With
no climate in the Model the section shows the site, if set, and "No climate", with no remark on
what honeybee-ph supplies in its place (E1). A folder location never appears.

**PHX in tests.** PHX is not a dependency (`pyproject.toml`). The round trip uses an optional
`phx` dependency group pinned to a released PHX, added here or by the Programs packet's P4a-03,
whichever merges first (D4c-14); the tests skip without it.

Amended at P4c-05, 2026-11-18. Owed check 6 ran on PHX 1.57.5 and every row above held
([evidence](evidence/owed-check-6-20261118.md)); the `phx` group pins it (D4c-22). C4c-4 is settled
(D4c-24): the record is emitted always, and its `report` block also carries `climate` (name, origin,
dataset, station and state, or null), `missing_values`, and the design temperatures as
`design_temperatures` (`heating_99_c`, `cooling_1_c`) beside `design_temperature_source`. The result
fields are `location`, `climate` (the identity with the written `source_type` and wind speed),
`climate_written`, `climate_left_out`, `missing_values`, `peak_load_temperatures_c`, `limit_check`,
`edited_cells` (row, column, value and as read), `design_temperatures`, `design_temperature_source`,
`building_segments` and `site_digest`. Every finding's `object_id` is `Site`. The zone and offset
findings fire only with a climate in the Model; a site alone gives none (D4c-23). A design-temperature
note that reads as a file location is replaced in the report block by a line saying it stays in the
Model (D4c-25).
A climate both incomplete and without a site gives both findings, and `climate_left_out` reads
`site_not_set`. `climate.site_not_set` is the code P4c-04 declared; its description now covers both.

## 8. Units (P4c-01)

Stored values are SI and each field's key names its unit. New quantities, on both the Ruby and
the JavaScript side with shared vectors in `tests/support/units_vectors.json`:

| Quantity | SI | IP (D4c-09) | Exists today |
| --- | --- | --- | --- |
| `temperature` | °C | °F | JavaScript only |
| `temperature_difference` | K | °F difference | JavaScript only |
| `irradiation` | kWh/m² | kBtu/ft² | neither |
| `irradiance` | W/m² | Btu/h·ft² | neither |
| `wind_speed` | m/s | mph | neither |
| `distance` | km | miles | neither |
| elevation | m | ft | `length` exists; the stage confirms its IP form is decimal feet here |

Latitude and longitude are decimal degrees in both profiles.

## 9. What other features read

- **Mechanical** (the blended heat pump, D4-15 and F20 in its packet) requires
  `ph_composer.climate` and reads `ph_composer.climate.climate.get` for the twelve monthly mean
  air temperatures and `ph_composer.climate.design_temperatures.get` for the two design values
  and their state. The finding for a heat pump left out for want of them is Mechanical's (W4).
- **Sun-path view** and **window performance overlays** read the site and the monthly radiation
  the same way, when they are built.
- No feature reads Climate's dictionary or record store directly.

## Open contract questions

| Id | Question | Recommendation | Settle in |
| --- | --- | --- | --- |
| C4c-1 | Board 3 shows each folder's location. `Library::Setup.providers` strips paths from its read | **Settled at P4c-03, 2026-11-18 (D4c-16):** a display location, `~/` and the rest under the home folder, the volume's name and the rest under `/Volumes/`, otherwise `…/` and the last two names; never an absolute path, and the full path stays out of every result and log | Settled |
| C4c-2 | Is a station's matching name the file name's stem or the name in its header? | The file name's stem with the state folder: it is what the user sees in the folder and it is unique there | Settled at P4c-04 as recommended (D4c-18) |
| C4c-3 | The Setup view runs a native menu item's Ruby handler; the climate data dialog is in the panel | **Settled at P4c-08 as recommended, 2026-11-18 (D4c-27):** the handler calls `session.open_in_panel(owner, intent)`, delivered to the page as `panel.navigate` once it shows the Model; the page finds the tab from the owner | Settled |
| C4c-4 | What the report callable receives when the section wrote no `Site` | Always emit the one record, with `location` and `climate` null when not written and `climate_left_out` giving the reason, so the report and the findings read one source | Settled at P4c-05 as recommended, with the report block passed through the result (D4c-24) |
| C4c-5 | The map's projection and level of detail | An equirectangular projection scaled at the view's centre latitude, borders simplified to the size owed check 2 allows | Settled at P4c-07 as recommended (D4c-26): zoom from a 170° to a 0.5° tall view, the centre within 80° of the equator, borders 113 KB ([evidence](evidence/owed-check-2-20261118.md)) |
| C4c-6 | Is `Digest::SHA256` available in SketchUp's Ruby on the supported hosts? | Check at P4c-04's entry; it is Ruby standard library | Settled at P4c-04: it loads in SketchUp 2026's Ruby 3.2.2 ([evidence](evidence/owed-check-3-20261118.md)). SketchUp 2023 is the floor packet's |
