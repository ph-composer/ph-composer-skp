# P3b-05 evidence: the Thermal Bridges tab (T05)

DATE: 2026-10-26
STATUS: Host gate run on branch `feature/thermal-bridges-p3b-05` at `028905ab` (PR #311), SketchUp 26.1.188, Ruby 3.2.2, Ed at the mouse for the native steps. All seven assertions pass. Ed accepted the screen after five changes from his review. METr's third group word, "Basement floor", replaced the plan's label in the commit after the run.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Register row [T05](../ACCEPTANCE.md).

**Offline half:**
- `tests/thermal_bridges_panel_test.js`, 13 tests: the schedule read on opening, choosing a subtab and Refresh; used length as a dash once stale; cell edits with expected values and a kept refused draft; the group word and stored string; the assign bar's reasons, values and confirmation; an invalid assignment cleared; column sort and the Group filter; Locate from the icon and a row click, the read kept current; a refused read; Delete's replacement rule; a hidden Schedule; the New form.
- `tests/thermal_bridge_menu_test.rb`, 6 tests: availability; the entries; Clear for an invalid record; the confirmations.
- `make ci` green on every pushed head, the touched Ruby suites also on 2.7.2.
- Browser: `tools/ui-preview/thermal_bridges_checks.cjs` at the three panel sizes, and the inventories, Library and Window checks.

**Review:** a pre-gate Sonnet read (13 items, all fixed) and two Codex gpt-6.1-sol cycles on PR #311 (2 P2, then 1 P2; all fixed).

**Host half:** `tools/hostkit/acceptance_case.py` in `_private/host/t05/T05/` (gitignored; synthetic fixture; Ed's own captures kept there). The ledger row records a branch commit, not `main`.

## Identity

| Item | Value |
| --- | --- |
| Installed RBZ | `dist/ph_composer.rbz` built at `028905ab`, SHA-256 `7685db92` |
| Fixture | `_private/host/t05/T05-fixture/t05.skp` (SHA-256 `5ddd125b`), a fresh copy of `t04-reference-base.skp`: the T04 reference model, five types, every Face classified, nothing assigned |
| Process | Fresh, launched by `host_bridge.py launch`, the fixture the only document; composition normal |
| Controls | **Native, by Ed at the mouse:** selection, the assign bar, the right-click menu, the Edit menu's Undo and Redo, the unit toggle, METr's screen. **Page events** in the real HtmlDialog through a tools-only probe. **Bridge** for setup and readback |
| Earlier runs | `T05-run1`: bridge only at `9015df8b`; SketchUp closed. `T05-run2`: Ed's first native pass and review at `9015df8b`, which led to the five changes |

## Results

| Assertion | Observed | Evidence |
| --- | --- | --- |
| Types inventory | Page events: New waits for a name with the hint, then created -0.03 W/mK at Ambient; an in-place edit stored; a stale edit refused with the draft and its message kept and the Model unchanged; Duplicate as "Parapet (copy)"; Delete with replacement moved three Edges to Parapet | `D-1` to `D-5` |
| Assign from the bar, native | Ed selected Zone B's roof perimeter and assigned Parapet with its confirmation. Edit read "Undo Assign Thermal Bridge"; after Undo, "Undo Open / Redo Assign Thermal Bridge", and the Edges read empty. Redo shown in run 2 | `A-*` |
| Assign from the menu, native | Right-click > PH-Composer > Thermal bridge: the types by name, then Clear thermal bridge. Slab edge and Clear each confirmed, and the Edges read empty after Clear | `B-*` |
| Schedule and Locate | Equal to the hand calculation: Parapet 1, Zone A, 14 m, 0.700 W/K; Slab edge 1, Zone W, 8 m, 0.960 W/K; total 1.660 W/K. A row click opened the turned wrapper and Zone W and selected exactly four Edges; the read stayed current. All columns fit at 1,152 px | `D-6` to `D-8` |
| Unit switch keeps a draft | Ed typed 0.2 in IP and clicked SI: stored 0.346 W/mK, the units it was typed in | `C-*` |
| METr's third group word | Read by Ed on METr's own screen: Ambient, Perimeter, Basement floor | `E-metr-groups-ed.png` |
| UI polish review | Ed accepted the screen with five changes, made in `028905ab` and seen in this run | `D-8-schedule-window.png`; run 2 |

## Changes from Ed's review

1. Assign and Clear confirm, from the bar and from the menu.
2. Used length shows a dash once the Model has changed.
3. A Locate keeps the schedule read current.
4. Refresh sits before a shorter status.
5. The Schedule's columns fit about 1,000 px, and the totals by type take the full row.

## After the run

The commit after `028905ab` changes the third group label to "Basement floor" (`html/features/thermal_bridges/shared.js`, D3b-03) and the vocabulary documents. It was checked on a fresh launch of its own build. Because `shared.js` is a T05 dependency, the ledger row for `028905ab` reads stale against that file; T09 reruns the packet's cases.

## Host facts recorded here

- While the PH-Composer window is in front, macOS points the Edit menu at the panel page, not at the Model.
- Opening and closing a Zone are Undo steps of their own, so a native Undo check reads the Edit menu first.
- Synthetic Cmd+Z through System Events did not reach the Model while the Outliner held key focus.

## Proposed screen pattern, accepted

One page header over Types and Schedule subtabs. Types has an always-present assign bar above the table, with its reason on a disabled Assign and a confirmation on each write, and column menus on the table. Schedule:
- read on request, with a short stale note and Refresh;
- a row click or its icon to Locate;
- findings behind an alert glyph, in a bubble mounted outside the table;
- totals by type, then by group;
- the Edges in no run listed beneath.

## Limits

- The Types steps were page events, not native gestures.
- A right-click reads the selection twice.
- Datasheet links show as text only.
