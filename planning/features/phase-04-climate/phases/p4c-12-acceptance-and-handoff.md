# P4c-12: Acceptance and handoff

DATE: 2026-11-17
STATUS: Outline. Not authorized.
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

## Open

Nothing beyond the stages' own contract questions.

## Host gate

CM12 in [ACCEPTANCE](../ACCEPTANCE.md).

## Done when

CM12 passes and every register row is a Pass or carries a named, accepted limit.
