# Climate data: status

DATE: 2026-09-18
STATUS: Requested. Wireframes reviewed with Ed by 2026-11-16 and the PRD revised to their nine answers (W1 to W9) the same day. Ten items are open or owed before planning (PRD, "Open"); nothing is planned or authorized. The Mechanical phase's heat pump stage waits on this packet.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (no remote)

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

Put the PRD's nine open items to Ed, draw the screens still missing (entering values by hand, the Design temperatures card, an edited station), then plan the stages. Earlier next step, superseded by the Phase 4 dependency: none until the MVP packets have plans, then interview the remaining feature-local questions and
plan the peak-load entry, readiness and repair-route behavior already fixed by D9.

## Blockers

See the PRD's Dependencies section. EPW-derived monthly climates do not contain the peak-load
cases PHX currently requires for METr export; the feature must enforce D9's explicit readiness
gate. No GitHub remote, so no issue yet.

## Verification

None. Nothing is implemented.

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
