# Windows support verification

DATE: 2026-09-30
STATUS: Requested
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

All host evidence is from macOS. `context/TECH_STACK.md` states the first release candidate is
macOS-only and Windows support is a separate gate. Several Phase 1 behaviors depend on the
platform, not only on SketchUp.

## Platform-sensitive areas

| Area | Why it can differ on Windows |
| --- | --- |
| Canonical pair commit, rename and restart recovery | File locking, rename-over-existing semantics, antivirus holds, path length and separators |
| Native Save dialog and destination cancel | Different native dialog |
| HtmlDialog panel and runtime page | Different CEF build and GPU path; focus and Escape routing |
| Keyboard and modifier gestures | Ctrl versus Cmd, Shift-click plane selection, layered Escape |
| Overlay drawing, occlusion and HUD text | Different GPU drivers and font rendering |
| Installed footprint and extension paths | Plugins folder location, user-profile paths with non-ASCII names |
| Measured tolerances and observer ordering | Should match, but are host claims until measured |

## Carried from later phases

Windows work that a later phase left out on purpose. Each is built and tested here, not in the
phase that named it.

| Item | From | What is owed |
| --- | --- | --- |
| The per-computer settings file on Windows | [Climate](../../phase-04-climate/PLAN.md#deferred-out-of-this-packet), E3, 2026-11-17 | The Climate phase builds `shell/computer_settings.rb` for macOS only; on Windows the service is unavailable and the climate data folder commands refuse. Owed: choose the Windows folder (the user's roaming application-data folder is the candidate, unverified), write the rule and its tests, and confirm on a host that the file is created, survives a restart and sits outside SketchUp's versioned folder. Then the Climate packet's folder cases CM03, CM04 and CM08 on Windows |

## Acceptance shape

On a named SketchUp build on Windows 10/11: install the RBZ; rerun the P1-A native probe; rerun
the P1-F integrated case including injected pair-commit failure and restart recovery; exercise
Classify gestures and layered Escape; confirm Pyodide boot and translation; record host, OS and
CEF versions. Divergences become host-behavior entries and fixes with regression tests. The
offline gate should gain whatever Windows-path unit coverage the run exposes as missing.

## Open questions

| # | Question |
| --- | --- |
| Q1 | Minimum Windows version and SketchUp build to support |
| Q2 | Test machine: physical, VM, or cloud; GPU requirements for overlay timing |
| Q3 | Does the Windows gate also run on the 2023 floor, or on the current build only? |
