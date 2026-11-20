# P5s-07: acceptance and handoff

DATE: 2026-11-19
STATUS: Complete. Merged to main 2026-11-20 UTC (PR #533, `906a102c`). SD07 Pass 2026-11-20 on `906a102c`: Ed checked both files ("WUFI looks right", "looks ok in METr"); the research note's three "Not checked" lines were not answered separately ([STATUS](../STATUS.md#closure-2026-11-20)). Authorized 2026-11-19 with every Shading stage ([STATUS](../STATUS.md#authorization)). Not released.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

## Entry and scope

Requires P5s-01 to P5s-06 merged. No new behavior.

## Steps

1. Both Ruby gates, coverage, browser and runtime checks, `vendor.py --check` footprint.
2. The PRD's acceptance shape from a fresh process on the reference model: tag from the menus,
   Undo and Redo, a second Model, save and reopen, Colour-by, export, reload.
3. Convert the export with PHX. Ed opens the WUFI XML in WUFI-Passive and the METr JSON in METr and
   confirms each shading component, the holed Face included (D5s-14). The three "not checked"
   lines in the [research note](../research/honeybee-ph-and-phx-shading.md) are answered here.
4. Docs pass: `context/` carries every binding; `docs/USER_DATA.md` has the mark's row;
   `docs/AGENT_GUIDE.md` the operations; the ROADMAP and master STATUS rows are current.
5. Amend the [zone-shading brief](../../../features/unscheduled/zone-shading.md): its route now names this
   section, and SH-3 and SH-4 are closed.
6. Archive the packet to `planning/archive/phase-05-shading/` when Ed accepts. Done 2026-11-20.

## Done when

SD07 passes and Ed has accepted the two files.
