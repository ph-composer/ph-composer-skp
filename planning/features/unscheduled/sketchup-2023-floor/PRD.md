# SketchUp 2023 floor verification

DATE: 2026-09-30
STATUS: Requested
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

`context/TECH_STACK.md` sets SketchUp 2023 as the floor because overlays use `Sketchup::Overlay`
(2023.0). Offline, the suite already runs on Ruby 2.7.2 and eslint refuses post-Chromium-88 APIs.
No 2023 host has been measured. Until one is, "supports SketchUp 2023" is an unverified claim.

## Premises to prove on a 2023 host

| Premise | Where it is stated |
| --- | --- |
| Embedded Ruby is 2.7.2 and the extension loads without error | TECH_STACK, supported environments |
| HtmlDialog's CEF is Chromium 88 or later-compatible; panel and runtime page work | TECH_STACK, UI kit rules |
| Pyodide 0.24.1 boots and the eight pinned wheels translate in the runtime HtmlDialog | P1-E A14 |
| `Sketchup::Overlay` draws fills and HUD, respects occlusion and the Overlays panel | P1-D A08 |
| Point-merge tolerance 0.0254 mm and split/Undo/reopen behavior match | SKETCHUP_HOST_BEHAVIOR; P1-A |
| Observer ordering on edit-path change (commit then `active_path_changed`) | P1-E navigation correction |

## Carried from later phases

| Item | From | What is owed |
| --- | --- | --- |
| Preferences and the settings file across two SketchUp versions | [Climate](../../phase-04-climate/PLAN.md#deferred-out-of-this-packet), E3, 2026-11-17 | With a second supported version installed beside the current one: write a preference with `Sketchup.write_default` in one and read it in the other, and confirm a climate data folder added in one is listed in the other |

## Acceptance shape

On SketchUp 2023 (macOS first): install the RBZ; rerun the P1-A native probe; rerun the P1-F
integrated two-Zone authoring/export case with nested edit path, Undo/Redo, two Models, reopen and
restart recovery; time runtime boot and Colour-by redraw at the Phase 1 fixture sizes. Record host
build, Ruby and CEF versions. Any divergence becomes a host-behavior entry and, if needed, a fix
with a regression test. Do not raise the floor without an explicit decision.

## Open questions

| # | Question |
| --- | --- |
| Q1 | Which 2023 build (2023.0 versus final 2023.1.x)? Evidence should name the exact build |
| Q2 | Is a 2023 license and machine available, or does this wait for a test environment? |
