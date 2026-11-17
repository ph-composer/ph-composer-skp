# Climate data: status

DATE: 2026-09-18
STATUS: Scoped (2026-11-17). The PRD is settled (W1 to W9, J1 to J8, R1 to R9) and the stages are planned: P4c-01 to P4c-11 ready to authorize, P4c-12 the closing outline. No stage authorized. Ed answered E1 to E3 and ruled on D4c-03, D4c-04 and D4c-10 on 2026-11-17. Nothing is open for Ed. The Mechanical phase's heat pump stage waits on P4c-02.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft; one issue per stage group when Ed authorizes)

## State

Post-MVP by Ed's request of 2026-09-18. PRD drafted the same day from the predecessor's
`planning/phases/C1_climate-data.md`, adapted for the pivot away from designPH and PHPP. D7 is
confirmed: no datasets ship; user-owned climate files, manual entry and public EPWs are permitted;
honeybee-ph owns EPW-to-monthly conversion. D9 is confirmed: the derived monthly climate supports
preliminary work, and user-supplied peak loads gate climate-bearing METr export. Remaining feature
questions are not interviewed.

## Proposed 2026-11-15, answered by 2026-11-16

All nine questions are answered in the [wireframes' README](mockups/README.md) and the ledger below, and the PRD was revised to them on 2026-11-16. The list that follows is what that revision changed.

Ed asked on 2026-11-15 for a Climate tab that works like PH-Navigator's, with climate data loaded
from a folder on the user's own computer and kept out of the Model apart from the chosen station.
The [wireframes](mockups/README.md) propose it and list nine questions. Nothing in the PRD is
changed yet. A review would revise:

- the non-goal "No map tiles in the first scope" and the boundary line "does not host a climate
  map": an outline map shipped with the extension is proposed, still with no network;
- the Behaviors' "A Climate section": a primary Climate tab is proposed;
- Q2 and Q3: a Phius station folder becomes a named source, configured per computer;
- a new input, the ASHRAE 99% heating and 1% cooling dry bulb, which Phase 4's blended heat pump
  needs ([Phase 4 DECISIONS, Part 3](../phase-07-mechanical/DECISIONS.md#part-3-wireframe-review-2026-11-15), D4-15);
- this packet's place. Settled 2026-11-15: promoted to Phase 4, ahead of Mechanical (now Phase 7).

D7 (no datasets ship) and the snapshot rule stand, and the proposal depends on both.

## Next step

The stages are planned (2026-11-17): [PLAN](PLAN.md), [CONTRACTS](CONTRACTS.md), [DECISIONS](DECISIONS.md),
[ACCEPTANCE](ACCEPTANCE.md) and [phases/](phases). Next: Ed
authorizes stages one at a time, starting with P4c-01. Implementation needs that separate
authorization.

## Blockers

- Windows and a second SketchUp version are out of this packet (E3): the settings file is built
  and verified on macOS in SketchUp 2026 only.
- The six owed checks are entry checks of P4c-03 to P4c-07 and P4c-11 ([PLAN](PLAN.md#owed-checks-each-an-entry-check)).
- The hourly weather file and its D9 peak-load gate are deferred, so nothing here waits on them.
- No GitHub issue yet; one per stage group when Ed authorizes.

## Verification

Nothing is implemented. Planning claims about honeybee-ph were checked against the pinned wheel
(1.33.65): read in its source, and run for the default `Site`, a `None` hours from UTC, and a
synthetic `Site` with a provenance, both readiness lists empty, through a `BldgSegment` round trip.
PHX claims were read in the local checkout at 1.59.1, not pinned and not run; owed check 6 runs
them. `make lint-paths lint-citations` pass on the packet.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted as a post-MVP packet. |
| 2026-09-18 | D7 confirmed. Verified that the PH monthly converter is honeybee-ph `Site.from_epw()`, not PH-Navigator-Web. The plan now ships no datasets, supports user-owned files and local EPWs, and records the peak-load gap as D9. |
| 2026-09-18 | D9 confirmed: EPW-derived monthly data supports preliminary work; METr climate export requires user-supplied peak-load cases and never synthetic values. |
| 2026-11-15 | Climate tab wireframes drawn at Ed's request: a per-computer climate data folder, a station picker on an outline map, and the chosen station copied into the Model. Nine questions open; the PRD is unchanged. Phase 4's heat pump stage (D4-15) now waits on this packet. |
| 2026-11-15 | Ed promoted the packet from `phase-05-post-mvp/climate-data/` to `phase-04-climate/`: Climate is built before Mechanical. The PRD's "Post-MVP" wording predates the move. |
| 2026-11-15 | Ed settled the data folder: its location and name live in PH-Composer's own per-computer settings file (not SketchUp's preferences, no station index, no imported copy); the setup is reached from the Climate tab and the Setup view; the user types the dataset name, prefilled from the folder; Phius station files only at first. To verify on a host before planning: that SketchUp's preferences are per version, which was the reason given, and where the settings file sits on macOS and Windows. Library locations stay where they are. |
| 2026-11-16 | Ed settled the map: an outline map shipped with the extension (world countries, US and Canadian states and provinces, public-domain data), no web tiles, with pan and zoom, click to select, hover details and a click-to-place site pin. Owed at planning: the data source and its licence confirmed, its size in the RBZ, and how it draws on the Chromium 88 floor. |
| 2026-11-16 | Ed settled the sources: separate cards for Phius climate data and an Hourly weather file, no PHI; in the first version Phius climate data (a station from the folder, or values typed by hand) is the only climate and exports, and the Hourly weather file card is shown as Planned. Design temperatures are typed and do not gate export. The PRD's EPW route and its D9 peak-load entry wait for the Hourly weather file card. |
| 2026-11-16 | Ed settled a Phius station's gaps: three peak-load cases is complete and Cooling 2 stays empty; ground temperatures stay empty and unflagged; average wind speed is typed, prefilled with the January and July mean; values may be edited after attaching and the source is then marked edited. Owed at planning: what honeybee-ph and PHX do with an empty Cooling 2 and an empty ground row at export (PHX pads a missing peak value with zero in METr, read from the PHX checkout, not reproduced). |
| 2026-11-16 | Ed settled the tab's position: Climate is the first primary tab, before Zones. Open: which tab the panel opens on, and the nine-tab row at the 420 px and 360 px panel widths. The Mechanical wireframes' tab rows predate this and show neither Climate nor Programs. |
| 2026-11-16 | Ed settled the code shape: Climate is its own feature, not a Library kind; a Model holds one site and one Phius climate; one built-in Phius reader now, with a format contract deferred until a second reader exists. All nine wireframe questions are now answered. The PRD is not yet revised. |
| 2026-11-16 | PRD revised to the wireframe review: a Climate tab, climate data folders per computer, a station picker on an outline map, one climate per Model, typed design temperatures, the hourly weather file and PHI deferred. Q1 to Q9 kept with what the review did to each; W1 to W9 added; nine items listed as open or owed before planning. |
| 2026-11-16 | Recorded the private development corpus: Ed's licensed Phius 2022 dataset, held outside the repository, located only in gitignored `_private/climate/MANIFEST.md`, never to be distributed. Its layout (from names only) is in the PRD. It shows a second, `.xls` format that alone covers Canada and Japan; added as open item 10. |
| 2026-11-17 | First journey walked with Ed (J1, setting up the climate files): read in place and never copied, new files show by themselves, no Rescan, the settings file outside SketchUp's versioned folders, files not read reported by kind, a cache only if reading proves slow. Board 3 updated. Open items 11 (a notice of new stations) and 12 (measure the read time, including a cloud-synced folder) added. The remaining journeys move to a new thread. |
| 2026-11-17 | Second journey walked with Ed (J2, setting the site): the site is set by latitude, longitude and elevation; climate zone is the ten integer codes the honeybee-ph Grasshopper component allows, with no moisture letter; hours from UTC is a typed field; Read from SketchUp Geolocation fills latitude and longitude, and hours from UTC if the host supplies an offset, never elevation. Board 1 redrawn with the map inside Set Location, board 8 added for the site not set, and the zone corrected on boards 2, 5 and 6. Open item 7 narrowed; items 13 (a host measurement of SketchUp's geolocation) and 14 (confirm the zone codes against METr) added. |
| 2026-11-17 | Third journey walked with Ed (J3, choosing and attaching a station): the site comes first; the picker opens sorted by distance on one dataset at a time; a failing station can be attached and is reported as outside the Phius limits; the Model keeps the station's coordinates. Boards 9 to 11 added. Open items 2 and 6 settled (both limits cited from the Phius guidebook); item 12 half measured (0.15 s for the private corpus in Python). |
| 2026-11-17 | Fourth journey walked with Ed (J4, entering values by hand): one grid in the order of a Phius climate file, filled by one paste or typed; it saves with gaps and is marked Incomplete; coordinates are optional and the limit check reads Not checked without them; the same editor serves Edit Values. Board 12 added. Open items 15 (a custom dataset's format) and 16 (confirm the paste on real copies) added. |
| 2026-11-17 | Fifth journey walked with Ed (J5, the design temperatures): typed in the card's pane with an optional source note; Not set, Incomplete or Set; kept in the Model only, with nothing written to METr in the first version. Board 13 added. Open item 17 added (the two METr design-temperature fields PHX writes fixed values to). |
| 2026-11-17 | Sixth journey walked with Ed (J6, another computer): the Model reads in full with no notice; the source is matched by station name, state and checksum across every folder, not by dataset name; Replace stays enabled and explains when there is no folder; a folder not found keeps its setting and offers Locate and Remove. Board 6 corrected and board 14 added. |
| 2026-11-17 | Seventh journey walked with Ed (J7, replacing and editing): the Model keeps the as-read values so edited cells are marked, listed in the Export report and restorable anywhere; Replace shows a summary comparison and is one Undo step; a changed source file offers Update from File; the verdict is recomputed on a site change and Set Location warns first. Boards 15 to 17 added. |
| 2026-11-17 | Eighth and last journey walked with Ed (J8, export): Cooling 2 repeats Cooling 1, because honeybee-ph cannot leave it empty and would write zeros (run in the pinned 1.33.65); unset climate zone and UTC offset export unset with findings; an edited station and a hand-entered climate export as user-defined; coordinates and edits travel in the provenance's assumptions. Board 18 added. Open item 5 settled, item 7 narrowed. Item 18 added (export with a climate and no site). Eighteen items are listed; 2, 5 and 6 are settled. |
| 2026-11-17 | Ed answered the open items one at a time (R1 to R9): the panel opens on Zones; a climate with no site is left out of export; no `.xls` reader and no new-station notice in the first version; Cooling 2 equals Cooling 1 in WUFI and METr; hours from UTC is not used by METr as far as Ed knows; the ten zone codes are the full set and the Model stores the WUFI code; a custom Phius dataset comes as the same text and `.xls` files; METr's two design-temperature fields are parked. Six measurements and confirmations remain as stage entry checks. Boards 19 to 23 added. Ed asked for the stage planning next. |
| 2026-11-17 | Stages planned: the coordinating packet and twelve stage documents, P4c-01 to P4c-12, with each owed check an entry check of a named stage. Ids use `P4c-`, `D4c-`, `C4c-` and `CM` because `P4-` and `D4-` are the Mechanical packet's. Found while planning: honeybee-ph serializes a default `Site` on every Building Segment, so an export with no climate already carries a placeholder (E1). Three items open for Ed. Nothing authorized. |
| 2026-11-17 | Ed answered E1 to E3 and ruled on two planning decisions, after a review of honeybee-ph 1.33.65 (run) and the Grasshopper components (read). His rule: match honeybee-ph and honeybee-grasshopper-ph. E1: a Model with no site and no climate writes nothing, honeybee-ph's default `Site` stays, with no finding and no remark. E2: a site with no climate is written as its `Location` over honeybee-ph's default `Climate`. E3: all Windows path work is deferred to the Windows support packet, and acceptance runs on SketchUp 2026 only, so the two-version checks move to the 2023 floor packet. D4c-03 overturned: the record stores provenance in honeybee-ph's shape and export passes it through. D4c-04 confirmed: the exact conversions of 50 miles and 400 feet. Found: a Building Segment with no `site` key does not load. D4c-10 confirmed: Add Folder opens the chooser first, then the name. An earlier set of picks relayed from another session chose the first recommendations; Ed said these stand. Nothing authorized. |
