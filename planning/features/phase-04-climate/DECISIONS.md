# Phase 4 decisions: Climate

DATE: 2026-11-17
STATUS: The PRD's answers (D7, D9, Q1 to Q9, W1 to W9, J1 to J8, R1 to R9) are indexed here and not restated. Planning decisions D4c-01 to D4c-15 are recorded as made by the plan. Ed answered E1 to E3 and ruled on D4c-03, D4c-04 and D4c-10 on 2026-11-17. Nothing is open for Ed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

The [PRD](PRD.md) owns every answer Ed gave. This file says which stage builds each, records the
choices the plan itself made, and lists what Ed still has to decide. Each decision is labelled UI
or Code.

## For Ed

Nothing is open. Ed's answers and rulings of 2026-11-17 are below.

## Ed's answers, 2026-11-17

Given in the stage-planning session after a review of what honeybee-ph and its Grasshopper
components do. An earlier set of picks relayed from another session the same day chose the
plan's first recommendations; Ed said these stand.

The rule behind E1, E2 and D4c-03 is Ed's: match honeybee-ph and honeybee-grasshopper-ph.

| Id | Kind | Question | Answer |
| --- | --- | --- | --- |
| E1 | Code, UI | A Model with no site and no climate: what does the export carry, and does it say so? | Match honeybee-ph. Nothing is written, honeybee-ph's default `Site` stays, and there is no finding and no remark in the report. This is what a Grasshopper model with nothing connected to the Building Segment does |
| E2 | Code | A site is set and no climate is attached. Is the `Location` written? | Yes. The `Location` is written over honeybee-ph's default `Climate`, with no provenance, as the PH Site component does with a Location and no Climate Data connected. R2 is unchanged: a climate in a Model with no site is left out |
| E3 | Scope | The Windows half of owed check 1, and the second SketchUp version | All Windows path work is deferred and broken out as future work in the [Windows support](../unscheduled/windows-support/README.md) packet. This packet builds and verifies the macOS settings file only. Acceptance runs on SketchUp 2026 only; the two-version checks move to the [2023 floor](../unscheduled/sketchup-2023-floor/README.md) packet, which is where a second version is first installed |

What the review found, on 2026-11-17:

- honeybee-ph 1.33.65 (pinned, run): `BldgSegment()` builds `Site()` and always serializes it.
  The default is latitude 40.6, longitude -73.8, site elevation `None`, climate zone 1, hours
  from UTC -4; a climate named "New York" with every monthly and peak value 0.0, a daily swing of
  8.0, a wind speed of 4.0 and no provenance; PHPP codes `US0055c-New York`.
- A Building Segment dict with no `site` key does not load: `BldgSegment.from_dict` raises
  `KeyError: 'location'` (run). The `Site` cannot be removed from the HBJSON.
- honeybee-grasshopper-ph (read in the local checkout, not pinned): the Bldg Segment component
  uses `_site or site.Site()` and says nothing. The PH Site, Location and Climate Data components
  fill each empty input with the same defaults. Neither package tests a station's distance or
  elevation difference.
- PHX 1.59.1 (read in the local checkout, not run): a climate with no provenance takes the legacy
  path and converts with no issue raised.

Noted, not a decision: the task named stage files `p4-<nn>`. That prefix is the Mechanical
packet's, so this packet uses `p4c-<nn>` (D4c-01).

## The PRD's answers, by stage

Each id links to its row in the PRD; nothing is restated here.

| Id | Kind | Subject | Stage |
| --- | --- | --- | --- |
| D7 | Scope | No datasets ship | All; P4c-04 fixtures |
| D9 | Scope | Peak loads for an EPW-derived climate | Deferred with the hourly weather file |
| [Q1 to Q9](PRD.md#decisions) | | The September interview, as revised | See W and J rows |
| [W1](PRD.md#decisions) | UI | The outline map | P4c-07, P4c-09 |
| W2 | UI | Location typed or read once from SketchUp | P4c-06 |
| W3 | UI, Scope | The cards; Phius climate data is the only climate | P4c-06; P4c-08 to P4c-11 |
| W4 | UI, Code | Design temperatures typed, not gating export | P4c-01, P4c-06 |
| W5 | UI, Code | The per-computer settings file; no index; the dataset name | P4c-03, P4c-08 |
| W6 | Code | Its own feature; one climate per Model; one reader | P4c-01, P4c-02, P4c-04 |
| W7 | UI | Climate is the first tab | P4c-06 |
| W8 | UI, Code | What a Phius file does not supply; edits | P4c-02, P4c-05, P4c-10 |
| W9 | Scope | Phase 4 | This packet |
| [J1](PRD.md#decisions) | UI, Code | Setting up the climate files | P4c-03, P4c-04, P4c-08 |
| J2 | UI, Code | Setting the site | P4c-01, P4c-06, P4c-07 |
| J3 | UI, Code | Choosing and attaching a station | P4c-02, P4c-04, P4c-08, P4c-09 |
| J4 | UI, Code | Entering values by hand | P4c-02, P4c-11 |
| J5 | UI, Code | The design temperatures | P4c-01, P4c-06 |
| J6 | UI, Code | Another computer | P4c-03, P4c-04, P4c-08, P4c-10 |
| J7 | UI, Code | Replacing and editing | P4c-02, P4c-07, P4c-09, P4c-10 |
| J8 | UI, Code | Export | P4c-05 |
| [R1](PRD.md#open-and-owed-before-planning) | UI | The panel opens on Zones | P4c-06 |
| R2 | Code | A climate with no site is left out | P4c-05 |
| R3 | Scope | No `.xls` reader | P4c-04 (counted as not read), P4c-11 (the paste) |
| R4 | UI, Code | No new-station notice | P4c-08 |
| R5 | Code | Cooling 2 equals Cooling 1 | P4c-05 |
| R6 | Code | Hours from UTC optional, finding informational | P4c-05 |
| R7 | Code | Ten climate-zone codes, stored as the WUFI code | P4c-01 |
| R8 | Scope | A custom Phius dataset is the same text file | P4c-04 |
| R9 | Code | METr's two design-temperature fields are parked | Deferred |

## Planning decisions

Made while planning the stages, 2026-11-17. Each can be overturned by Ed or by the stage's
architecture review. Three touched what the PRD says. Ed overturned D4c-03 and confirmed D4c-04
and D4c-10 the same day. The rest change no PRD answer.

| Id | Kind | Decision | Why |
| --- | --- | --- | --- |
| D4c-01 | Code | Ids: stages `P4c-nn`, decisions `D4c-nn`, contract questions `C4c-n`, acceptance rows `CMnn`, stage files `phases/p4c-nn-<title>.md` | `P4-` and `D4-` are the Mechanical packet's and `P4a-` is Programs'. `D5-1` is used and Phase 5 is now Shading, so the old roadmap number 5.1 gives no free prefix. The lettered form is the convention's own, and the citation lint already refuses it in `src/` and `tests/`. `CL` is taken by an archived packet; `CM` is free in the native case ledger and in planning |
| D4c-02 | Code | The site and the design temperatures are Model settings, each in its own `ModelSettings` dictionary (`ph_composer.climate_site` and `ph_composer.climate_design_temperatures`); the climate is one record of its own kind under a fixed id. Amended at P4c-01's entry check, 2026-11-17: the plan had one dictionary, but a settings proposal guards its whole dictionary (the preimage compare, the scope digest and the step's apply check all read every field), so two updates sharing one dictionary would each stale the other | The first are a handful of nullable scalars, which is what `ModelSettings` is for. The climate is about 240 numbers with an as-read copy; as a record it gets a schema version, `user_data`, true absence and Clear as a delete, and is not dragged through every small settings guard |
| D4c-03 | Code | Overturned by Ed, 2026-11-17: match honeybee-ph. The climate record stores a `provenance` block in the shape of honeybee-ph's `ClimateProvenance`, as the PRD's Records block says, and export passes it through. Every operation that changes the values rewrites it in the same Undo step. `source_uri` is never held | The plan had stored only the dataset, station, state and checksum and derived the rest at export, so the source type could not disagree with the values. One write per operation gives the same guarantee and keeps the Model's shape the same as honeybee-ph's |
| D4c-04 | Code | Confirmed by Ed, 2026-11-17. The limit check compares in SI against the exact conversions of Phius's limits, 80.4672 km and 121.92 m, at or inside both passing; distance is great-circle | Phius states the limits in miles and feet, so IP is the reference. The PRD's 80 km and 122 m are display labels |
| D4c-05 | Code | The settings file is a small foundation service with one section per feature id. Climate is its only user for now | The PRD calls it PH-Composer's own settings file, not Climate's. One file with sections costs nothing more than a private one and keeps the path rule in one place. No other store moves into it |
| D4c-06 | Code | Station values never pass through the panel. The station list carries location and elevation only; attach names a station and Ruby reads the file | Attach then works with the panel closed and through the agent interface, the licensed values travel no further than they must, and no path enters params, results or logs |
| D4c-07 | Code | The `Site` section attaches at `MODEL` after the Zones section, sets one `Site` on every exported Building Segment, and is optional for export. It writes the `Location` whenever the site is set and the `Climate` only when one is complete (E2). A written climate's provenance marks monthly and peak-load data available | honeybee-ph keeps `Site` per segment; a Model has one site. A `Site` that fails to build must not block an export that works without it. PHX refuses a provenance whose availability flags are not both true (read in the local checkout) |
| D4c-08 | Code | Complete means: name, station elevation, daily swing, wind speed, all 96 monthly values, and each case's air temperature and five radiation values. A case's dewpoint and sky temperature are optional | It is what honeybee-ph's readiness checks ask for (read), so "complete" and "PHX will convert it" mean the same thing |
| D4c-09 | UI | IP display: °F, kBtu/ft² for monthly radiation, Btu/h·ft² for peak radiation, mph, miles, feet. Latitude and longitude stay decimal degrees | Proposed, not checked against WUFI-Passive or METr. Ed may prefer another set; it is a table entry |
| D4c-10 | UI | Confirmed by Ed, 2026-11-17. Add Folder opens the folder chooser first, stores the folder under its own name, and opens that name for editing in the row | The chooser's path cannot travel through the panel, so the name cannot be asked before the folder is known. The user still names the dataset before doing anything else (W5) |
| D4c-11 | Code | The station list is read on demand. Over 0.5 s it is sliced so the panel stays live; a cache is added only if a warm read of a real-size folder exceeds 2 s | J1: a cache only if reading proves slow. The thresholds make "slow" a measurement |
| D4c-12 | Code | Stage order: records and operations with the panel closed, then export, then screens | Every screen then calls operations that already have tests, and Mechanical can start after P4c-02 |
| D4c-13 | UI | The tab row gains Climate first. Programs and Mechanical tabs arrive with their own phases; the disabled Systems button stays until Mechanical replaces it | W7 gives the final nine-tab order; this plan adds only its own tab |
| D4c-14 | Code | The optional `phx` test group is added by this packet's P4c-05 or the Programs packet's P4a-03, whichever merges first | Both plans need it and neither should wait on the other |
| D4c-15 | Code | The map's borders ship as a generated JavaScript module, drawn as SVG | The panel loads from a file with no network and a content policy that allows only the extension's own scripts, so data cannot be fetched. SVG is already used for the Assembly and Window drawings |
| D4c-16 | UI, Code | Settled at P4c-03, 2026-11-18, answering C4c-1. A climate data folder's display location is `~/` and the rest under the home folder, the volume's name and the rest under `/Volumes/` (`Climate Drive/Phius`), and otherwise `…/` and the folder's last two names | The recommendation covered only the home folder. A folder on an external drive is common for licensed data, and the volume's name is what the Finder shows for it. No form is an absolute path, and a folder in the user's own home never shows their account name. A folder in another account's home shows that account's name after `…/` |
| D4c-17 | Code | Made at P4c-03, 2026-11-18. The settings file service names no feature: it raises `ComputerSettings::Refused` with a reason (`unavailable`, `unreadable`, `later_version`, `too_large`, `unwritable`) and Climate maps it to its two codes. A write holds an exclusive lock on a sibling `settings.lock` for at most two seconds across re-read, change and rename. A file from a later schema version is neither read nor written | The stage doc had the service answer `climate.settings_unavailable` itself, which would make a foundation file name a feature. Re-read and rename alone leave a window where one process's stale copy erases another's section; the lock closes it, and a test with two processes fails without it. CONTRACTS called a later file "read-only", but its sections may have changed shape, so reading one could mislead; reporting it matches the stage's test list |
| D4c-18 | Code | Settled at P4c-04, 2026-11-18, answering C4c-2. A station's matching name is its file name's stem, with its state folder. The record's `name` is the header's name and `provenance.station_name` the stem; `Record.from_station` takes the stem in its source | In the private corpus no stem repeats within a state folder, while 3 header names do ([evidence](evidence/owed-check-3-20261118.md)). The header's name is the one a user knows the station by |
| D4c-19 | Code | Made at P4c-04, 2026-11-18. Attach and Replace are two actions, `climate.attach_station` ("Attach Climate Station", refused over a climate) and `climate.replace_station` ("Replace Climate Station", refused with none), each taking a folder id and a station key. Both are guarded by the request's `expected_revision` and take no `expected_values` | An action declares one Undo name and the dispatcher opens its operation under it, the wall P4c-02 met. `expected_values` would put a station's values in params, which D4c-06 rules out; dispatch refuses a stale revision for every action |
| D4c-20 | Code | Made at P4c-04, 2026-11-18. `stations.list` is paged (`Pages.bounded`, nearest first, then by key), its cursor bound to the Model's revision, so a site change expires it. A station's key is its path inside the climate data folder, and attach reads only a key the walk lists | 1,007 rows do not fit the 24 KB agent reply. Nearest first makes the guide's "attach the nearest passing station" the first page. A folder-relative path is unique even where two subtrees repeat a state's name |
| D4c-21 | Code | Made at P4c-04, 2026-11-18, after owed check 3. The walk is synchronous and bounded: 20,000 entries, 16 folders deep, files of at most 64 KiB, hidden names skipped and links not followed, `complete: false` past a bound. Files not read are counted by lower-case extension, at most 20 kinds listed beside a total | The read takes under 0.1 s for the corpus (D4c-11's first branch), but a user may point a folder at any tree. The bounds keep the main thread's worst case finite, and a link can neither loop nor leave the folder |
| D4c-22 | Code | Made at P4c-05, 2026-11-18, after owed check 6. The optional `phx` test group pins `PHX==1.57.5`, the latest release over the pinned honeybee-ph 1.33.65 | PHX 1.58.0 and later require honeybee-ph 1.33.68, which would move the shipped pin; the group is a test tool and must not ([evidence](evidence/owed-check-6-20261118.md)) |
| D4c-23 | Code | Made at P4c-05, 2026-11-18, after the Codex review of PR #516. A Model with no climate gives no finding at all, with or without a site (E1, E2, CM05): `climate.zone_not_set` and `climate.utc_offset_not_set` fire only when a climate is in the Model and the site is written | CONTRACTS section 7's findings table ties both to "the site is set", while its prose and CM05 say a site with no climate gives none. The stage first fired them for a site alone; the review held it to the accepted contract. Firing them for a site alone is one condition in `SiteRecord.findings` if Ed wants it |
| D4c-26 | UI, Code | Settled at P4c-07, 2026-11-18, answering C4c-5. The outline map is equirectangular with longitude scaled by the cosine of the view's centre latitude; the centre stays within 80° of the equator and the zoom runs from a 170° to a 0.5° tall view. A ring is the great-circle locus on the limit check's sphere. Borders are Natural Earth 5.1.2 at 1:50m (public domain), countries simplified to 0.08°, and the United States, Canada and their states and provinces to 0.02°, rounded to 0.01° and written in the encoded polyline algorithm: 113,186 bytes | Owed check 2 ([evidence](evidence/owed-check-2-20261118.md)): the decimal first draft (187 KB) fitted the 300 KB budget but left 70 KB under the installed-size ceiling of 26,000,000 bytes for the rest of the packet; the encoding leaves 137 KB. Pan and zoom frames held 60 Hz with 1,000 markers in Chrome; in SketchUp 2026's HtmlDialog with 1,000 markers, first paint 46 ms, pan frames mean 22 ms and wheel zoom mean 18 ms (CM07) |
| D4c-25 | Code | Made at P4c-05, 2026-11-18, after the Codex review of PR #516. A design-temperature note that reads as a file location stays in the Model, and the report shows a line saying so in its place | The export's artifact guard refuses any local path in the result, so such a note would block every export, with or without a climate, though design temperatures never gate export |
| D4c-24 | Code | Made at P4c-05, 2026-11-18, answering C4c-4. The section emits its one record always. Its `report` block also carries the climate's identity (name, origin, dataset, station, state) and a count of missing values, so a climate left out is named in the report with its reason; Python passes the block to the result unchanged. The result adds a SHA-256 digest of the built `Site`, which conformance compares with every reloaded Building Segment | The report reads the Python result, not the Ruby record (`Export::ResultView`), so whatever it renders must travel through the result. The digest lets conformance check all 96 monthly values and the four cases without putting them in the result |
| D4c-27 | Code | Settled at P4c-08, 2026-11-18, answering C4c-3. A menu item's handler calls `session.open_in_panel(owner, intent)`; the shell shows the panel and sends the page `panel.navigate` with the owner and the intent, now or, held with the session's notices (`PanelOutbox`), once the page has started and shows that Model. A later route replaces one waiting; a window closed before its page started drops it. The page finds the tab with `tabFor(owner)` and drops a route for another Model | A feature names no tab and the shell names no feature, as `tabFor` already lets the Export tab send the user to a gap. The Extensions menu runs the same handler with the panel closed, so the route has to wait for the page |
| D4c-28 | UI | Made at P4c-08, 2026-11-18. The Phius pane counts only folders found now: with none found it says the folder cannot be found and offers the dialog, where Locate is. Board 10 names the dataset the picker opens on: the one used last if found, else the first found holding stations, else the first found. Settings that cannot be read show their message and only Enter Values by Hand | A folder not found has no stations the picker can read (J6), and Choose Climate Data Folder would add a second folder when the user needs Locate. The dataset rule is J3's for the picker, so the pane and the picker name the same one |
| D4c-29 | UI | Made at P4c-09, 2026-11-18, entry check 2. The station picker shows the map beside the list down to 900 px; below that the map (220 px) sits above the list (240 px) and the dialog scrolls to its sticky Cancel and Attach. Below 500 px the list drops its State column, the State filter staying; at 360 px the list scrolls sideways inside itself | The list's five columns stop fitting beside the map at about 900 px. Stacking keeps both on screen without a toggle, which would hide the map that selects. The dialog never scrolls sideways (browser check at 1280, 420 and 360 px) |
| D4c-30 | Code | Made at P4c-09, 2026-11-18. `ph_composer.climate.stations.all` (API 1.68) answers one folder's stations in one unbounded read, `stations.list`'s rows unpaged, `response.bounded: false` preferring `stations.list` | The picker shows every station; paging 1,007 stations is 19 reads of about 0.1 s, each walking the folder again. The same precedent as `zones.all` and the thermal-bridge schedule's `all` |
| D4c-31 | UI | Made at P4c-10, 2026-11-18, entry check 1. With a climate attached and its card selected, the page header holds the pane's actions: Climate Data on This Computer and Edit Values (disabled with its reason until P4c-11) as secondary buttons, Replace as the one primary, and Clear alone in the More climate actions menu. Restore Original Values sits in the edited line above the values and Update from File in Where this lives, each shown only when it applies. Replace stays enabled: with no folder found, or no site, it opens a bubble that says why and offers Choose Climate Data Folder and Enter Values by Hand, or Set Location | The page-header rule: one primary, the frequent action visible, the destructive one last in the overflow; Site location already puts Set Location in the same header. Restore and Update act on a state the pane shows, so each sits beside it rather than in a menu where its state is hidden (boards 15 and 17). J6 keeps Replace enabled with no folder |
| D4c-32 | UI | Made at P4c-10, 2026-11-18, entry check 2. The monthly tables keep their twelve month columns at every size and scroll sideways inside their own bordered box, the row names held at the left; the peak loads do the same with their eight columns. The panel itself never scrolls sideways. Not transposed | The months read across as the Phius file and the boards draw them, and one layout at every size keeps an edited cell where the user saw it. At 420 px the box shows about five months; a transposed table would be 12 rows by 3 and a second layout to keep in step |

## Contract questions

C4c-1 to C4c-6 are in [CONTRACTS](CONTRACTS.md#open-contract-questions), each with a
recommendation and the stage that settles it.
