# P4c-12: Acceptance and handoff

DATE: 2026-11-17
STATUS: In progress on branch `feature/climate-p4c-12` (2026-11-18). Authorized 2026-11-17 with every Climate stage (packet STATUS, Authorization).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires every stage above. Closes the register, runs the PRD's acceptance shape end to end, and
folds what landed into `context/` and `docs/`. No new behavior.

## Outline

1. Both offline Ruby gates, coverage, browser and runtime checks; the packaged footprint against
   the baseline, with the map's share stated.
2. **The integrated run** from a fresh process, on a synthetic Model with the synthetic climate
   data folder, in the order of the PRD's acceptance shape: add the folder and read its counts;
   set the site by typing, by a click on the map, and from SketchUp's geolocation with the
   elevation typed; open the picker, find the nearest station, see a passing and a failing
   verdict; attach; save, remove the folder's setting, reopen, and confirm the climate reads in
   full and Replace asks for a folder; restore the folder and replace the station in one Undo
   step; edit a value and see the mark; type a climate by hand on a second Model; enter and
   clear the design temperatures; export, and find `Site` in the HBJSON, the dataset and station
   in the report, and no folder location anywhere.
3. **A second SketchUp version** is not run: Ed tests on SketchUp 2026 only for now (E3). The
   two-version checks are carried to the 2023 floor packet.
4. `context/CONTRACTS.md`, `context/EXTENSIBILITY.md` (the settings file, the map kit part, the
   second Setup entry), `context/TECH_STACK.md`, `context/SKETCHUP_HOST_BEHAVIOR.md` (owed checks
   1, 3 and 4) and `context/UBIQUITOUS_LANGUAGE.md` ("Site and climate" with no "planned" left on
   what shipped) brought up to date; `docs/PRODUCT.md`, the agent guide and the user data guide.
5. Planning: the roadmap row, the master status row and this packet's ledger; the PRD's status
   line; the wireframes' README marked as built from.
6. **Handoff to Mechanical**: confirm `climate.get` and `design_temperatures.get` give the heat
   pump stage the twelve monthly means and the two design temperatures with their state
   (CONTRACTS section 9), and record in the Mechanical packet that its entry gate is met.
7. Carry forward what did not close: confirm the Windows settings-file item is in the Windows
   support packet and the two-version checks are in the 2023 floor packet (both recorded there
   on 2026-11-17); the Deferred table unchanged.

## Steps

Written out from the outline on 2026-11-18. No step adds behavior; a defect found on the way is
fixed only if a register row fails on it, and is otherwise recorded for Ed.

1. **Offline gates.** `make ci` on Ruby 3.2.2 and on Ruby 2.7.2, `make coverage` at the Makefile's
   thresholds, `make ui-checks` (every browser check in `tools/ui-preview/`) and
   `make runtime-browser-check`, all on the final head. Record the counts in the packet STATUS.
2. **Footprint.** The installed size from `make rbz install` on the final head against the
   D4c-33 ceiling (28,000,000 bytes) and the growth gate (baseline 24,541,739 plus 2,500,000), with
   the map's share: the bytes of `html/map_borders.js` and the other map files installed.
3. **CM12 case.** Add `CM12` to `planning/native-acceptance/cases.json` with the dependency paths of
   the integrated run, and write [`evidence/cm12-recipe.md`](../evidence/cm12-recipe.md): part A
   through the bridge, part B the native steps for the conductor's hold, part C Ed's pass.
4. **The integrated run, part A.** After the last review fix, on the installed build of the final
   head, from a fresh SketchUp process, on fresh copies of the blank template and a copy of
   the synthetic folder `tests/fixtures/climate/folder/`, in the order of the PRD's acceptance shape
   (outline step 2). Steps that need a real click, SketchUp's own location dialog, the system
   clipboard or native Undo go to part B; part A drives the same panel through scripted DOM
   events in the real HtmlDialog and says so.
5. **The CM01, CM02 and CM03 rechecks.** Their rows read `needs_recheck` after later stages. Each runs
   its own recipe in its own fresh Model inside the same run: the walkthroughs, save and fresh
   reopen, and CM03's settings-file steps through the bridge in part A; their Edit menu Undo and Redo
   and CM03's real folder chooser in part B. Each row is recorded with `acceptance_case.py finish`.
6. **Context and docs** (outline step 4): fold what shipped into `context/CONTRACTS.md`,
   `context/EXTENSIBILITY.md`, `context/TECH_STACK.md`, `context/SKETCHUP_HOST_BEHAVIOR.md`
   (owed check 3 added; checks 1 and 4 are already there) and `context/UBIQUITOUS_LANGUAGE.md`
   ("Site and climate" its own section, the deferred terms still marked planned); `docs/PRODUCT.md`,
   the agent guide with its shipped copy, `docs/USER_DATA.md` and `docs/HELP.md`.
7. **Planning** (outline step 5): the roadmap row, the master status row, this packet's ledger and
   STATUS header, the PRD's status line, the wireframes' README marked as built from.
8. **Handoff to Mechanical** (outline step 6): read `ph_composer.climate.climate.get` and
   `ph_composer.climate.design_temperatures.get` on the host, with a complete and an incomplete
   climate, and confirm the twelve monthly mean air temperatures and the two design temperatures
   with their state (CONTRACTS section 9). Only if that holds, record the entry gate met in
   `planning/features/phase-07-mechanical/STATUS.md`; authorize nothing there.
9. **Carry forward** (outline step 7): confirm the Windows settings-file item in the Windows support
   packet and the two-version checks in the 2023 floor packet; leave the Deferred table unchanged.
10. **Before archive.** List in the packet STATUS the commits that merged unreviewed under the
    two-cycle cap, for one Codex review before the archive PR. The archive itself is the conductor's,
    after this stage merges.

## Open

Nothing beyond the stages' own contract questions.

## Host gate

CM12 in [ACCEPTANCE](../ACCEPTANCE.md).

## Done when

CM12 passes and every register row is a Pass or carries a named, accepted limit.
