# P3b-05 evidence: the Thermal Bridges tab (T05)

DATE: 2026-10-26
STATUS: Host gate in progress on branch `feature/thermal-bridges-p3b-05` at `9015df8b` (PR #311), SketchUp 26.1.188, Ruby 3.2.2. The bridge-driven half passes; the native gestures, METr's third group word and the UI polish review wait on Ed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T05](../ACCEPTANCE.md). Offline half: `tests/thermal_bridges_panel_test.js` (13: the schedule
read once on opening and muted when stale, a cell edit with its expected value and a kept refused draft, the
group word and stored string, the assign bar's reasons, Assign and Clear with their values, an invalid
assignment cleared, column sort and the Group filter, Locate from the icon and from a row click, a refused
read, Delete's replacement rule, a hidden Schedule, the New form) and `tests/thermal_bridge_menu_test.rb` (6:
availability with Faces only, with an assignable Edge, outside a Zone and over the gesture limit; the entries;
Clear for an invalid record). `make ci` green at `9015df8b` (Ruby 3.2.2: 2,224 runs; 750 JS tests); the touched
Ruby suites also on 2.7.2. Browser: `tools/ui-preview/thermal_bridges_checks.cjs` at the three panel sizes, and
the inventories, Library and Window checks. Review: one pre-gate Sonnet read (13 items, all fixed) and two
Codex gpt-6.1-sol cycles on PR #311 (cycle 1: 2 P2, fixed in `69b57a5a`; cycle 2: 1 P2, fixed in `9015df8b`).
Host half: `tools/hostkit/acceptance_case.py` in `_private/host/t05/T05/` (gitignored; synthetic fixture). The
ledger row will record a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `9015df8b`, SHA-256 `58ea960165ecb4ac9abc64f49384995deb24373e80ce19ca8b89e28d8154e510` |
| Fixture | `_private/host/t05/T05-fixture/t05.skp` (SHA-256 `5ddd125b`), a fresh copy of `t04-reference-base.skp`: the T04 reference model, five types, every Face classified, nothing assigned |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal |
| Controls | Bridge for setup and readback; page events in the real HtmlDialog through a tools-only probe (`probe.rb` in the run folder); native gestures by Ed |
| Display units | The host's own setting, IP; SI for the Types steps, restored to IP |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Types inventory | Bridge-driven page events: New with Create waiting for a name, -0.03 W/mK created at 15-Ambient; an in-place psi edit stored; a stale edit refused with the draft and its message kept and the Model unchanged; Duplicate as "Parapet (copy)"; Delete with replacement moved three Edges to Parapet | `steps.md` 2 to 4, 6, 8 |
| Schedule and Locate | Two runs equal to the hand calculation (Parapet 1, Zone A, 14 m, 0.700 W/K; Slab edge 1, Zone W, 8 m, 0.960 W/K; groups and total); a row click opened the turned wrapper and Zone W and selected exactly its four Edges | `steps.md` 9, 10; `4-locate-zone-w.png` |
| Unit switch keeps a draft | Page event: the draft kept its starting units through SI to IP while a clean cell reformatted; Escape restored the Model value. Native toggle by Ed: pending | `steps.md` 5 |
| Assign from the bar, native selection | Bridge selection and the bar's Assign wrote all selected Edges. Native selection by Ed: pending | `steps.md` 7, 9 |
| Assign from the right-click menu | Menu test on a live selection: available, the six types by name, then Clear. Native right-click by Ed: pending | `steps.md` 11 |
| METr's third group word | Pending: read on METr's screen by Ed; the panel shows "Floor slab / basement ceiling" | |
| UI polish review | Pending: native window captures reviewed by Ed | |

## Proposed screen pattern

Recorded here until Ed accepts it, then in the ui-polish `references/patterns.md`: one page header over Types
and Schedule subtabs; an always-present assign bar above the Types table, its reason on a disabled Assign;
column menus on the Types table; the Schedule read on request with a stale note and Refresh, a row click or
its icon to Locate, findings behind an alert glyph in a bubble mounted outside the table, totals by type and
group, and the Edges in no run listed beneath.

## Limits

- The Types, unit-switch and assign steps above are page events driven through the bridge in the real
  HtmlDialog, not native gestures; the native ones are Ed's rows.
- A right-click reads the selection twice (availability and entries).
- Datasheet links are shown as text only.
