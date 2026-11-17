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

## Contract questions

C4c-1 to C4c-6 are in [CONTRACTS](CONTRACTS.md#open-contract-questions), each with a
recommendation and the stage that settles it.
