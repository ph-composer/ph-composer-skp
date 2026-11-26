# Phase 7 MS2 host sitting: M05 to M07 and the Zone views repeats

DATE: 2026-11-25
STATUS: Recorded in part. M06 and UXR-FILTER-OCC pass. M05, M07 and the other eleven Zone views cases are ready
for a full-screen hold: background control could not click the panel or the viewport.
ISSUE: #562

Synthetic summary of the MS2 sitting (D4-31) for [Phase 7 Mechanical](../../features/phase-07-mechanical/ACCEPTANCE.md):
`M05`, `M06`, `M07` and, with `M05`, the twelve Zone views cases listed in
[p4-15](../../features/phase-07-mechanical/evidence/p4-15-acceptance.md). Raw Models, HBJSON, reports, captures,
drivers and each case's `steps.md` stay in gitignored `_private/host/phase-07-ms2/`.

## Build and host

- Source: `main` at `a2bb7957`. `make rbz && make install && make bridge-install`; `dist/ph_composer.rbz` sha256
  `2fd51f46be24d49024aed715f0a61bf094a5a9e4b404709bd54548238a1af93e`, the same bytes as MS1;
  `acceptance_run.py package` matches, 877 entries, no extras.
- SketchUp 26.1.188, Ruby 3.2.2, macOS. Each case in its own fresh process from `host_bridge.py launch`.
  HBJSON reloaded with honeybee-core 1.64.65, honeybee-energy 1.123.23, honeybee-ph 1.33.68.
- The panel's web engine, read from the host through a development DOM probe (`navigator.userAgent`):
  Chrome 137.0.7151.121 (SketchUp Pro 26.1). The Chromium 88 floor belongs to SketchUp 2023 and cannot be observed
  on this host.

## Control route

Product writes through registered actions (`PhComposer::API`), reads through the bridge in separate calls, exports
with MS1's labelled approved-location stand-in, revoked after each. Native Undo and Redo by System Events AXPress of
the Edit menu item by its exact title, SketchUp frontmost after its launch, no fronting call. Window captures by
background `app_screenshot`.

On this host the background controller refused every pointer action that the panel cases need. With SketchUp the
frontmost process, `app_click` on the PH-Composer panel's content and on its title bar was refused as a canvas (the
HtmlDialog exposes no web accessibility tree), and so was a click in the model viewport. Background
`app_menu` reported Extensions > PH-Composer > Open PH-Composer disabled; a System Events press opened the panel.
The 2026-10-26 route in the [native-control capabilities](../../../context/NATIVE_CONTROL_CAPABILITIES.md), where
background clicks reached the panel, did not reproduce. Every case built on panel or viewport gestures is
therefore left for one full-screen hold from the conductor session, with its fixture, driver and recipe staged.

## Results

| Case | Outcome | Assertions |
| --- | --- | --- |
| `M06` | pass | records-created, heater-foreign-variant-refused, delete-in-use-refused, delete-replacement-one-undo-step, export-reload-slots, tank-unslotted, hot-water-pooled, method-not-exported, save-reopen-reexport-same |
| `UXR-FILTER-OCC` | pass | distinct-paths, mask-west-pair, mask-east, clear-restores, no-model-write |
| `M05` | ready for hold | panel gestures; not begun |
| `M07` | ready for hold | panel gestures; not begun |
| `ZO-H1`, `ZO-H2`, `ZO-H3`, `ZO-O7`, `PTAB`, `HGUI`, `UXR-SOLVE`, `UXR-FILTER`, `UXR-HATCH`, `UXR-PAINT`, `UXR-COLOUR` | ready for hold | panel or viewport gestures; not begun |

### M06

On a fresh copy of MS1's reference model (Zone A and Zone B in Segment Main), panel closed:

- Registered creates gave HWS-1 (8 tap points), Tanks T1 (storage, 300 L), T2 (storage, 200 L) and T3 (buffer,
  80 L), and Heaters H-E (electric, 0.3) and H-HP (annual heat pump, 0.7, ratio 2.5), each naming HWS-1. Serves
  assigned HWS-1 to both Zones.
- An electric Heater carrying `total_system_perf_ratio` was refused `validation.failed`, nothing written.
- Deleting HWS-1 was refused `reference.in_use`, naming Zone A and Zone B. With HWS-2 as replacement the delete moved
  both Zones, both Heaters and all three Tanks to HWS-2. The Edit item read "Undo Delete Hot Water System". One
  press restored HWS-1 with every reference and left "Undo Create Hot Water System" next. Redo moved them again, and
  a second Undo restored them.
- The export completed. The exact HBJSON reloads with both Rooms' `ph_hvac.hot_water_system` holding HWS-1's
  identifier, `tank_1` T1 (300), `tank_2` T2 (200), `tank_buffer` T3 (80), no solar tank, heaters H-E and H-HP, 8 tap
  points and recirculation 60 °C over 24 h.
- T4 (storage) read slot null with `mechanical.tank_unslotted`. A plain assign of HWS-2 to Zone B was refused
  `mechanical.slot_filled`; with `replace` it committed, and both System rows carried `mechanical.hot_water_pooled`.
  HWS-1 set to `piping_calc_method` 2 carried `mechanical.method_not_exported`. The next export completed with all
  three in its report. T4's id occurs nowhere in the HBJSON, and no hot water dict has a method key.
- Saved, then reopened in a fresh process: the records read as before saving. The re-export has the same size,
  Rooms, every Room's `ph_hvac` and reloaded read-backs. The whole files differ in random honeybee-ph identifiers
  under the model's `properties`, and they are equal with UUID-shaped values masked. Recorded by section, as MS1's
  M04; p4-15 decision 3 governs both.

Copy defect noted, not blocking: the variant refusal reads "A electric heater takes no total_system_perf_ratio..",
with the wrong article and a doubled full stop. The preflight lists `mechanical.hot_water_pooled` once per System
(two identical rows for one Segment).

### UXR-FILTER-OCC

A fresh copy of the 2026-10-17 fixture, two solved six-Face Zones, plus the labelled nested and shared-component
geometry: three distinct paths, two of them ending in the same Face. By Zone fills 30 triangles. Masking the nested
and West-shared paths fills 4, and the window capture shows only those two panels coloured. Masking the East-shared
path fills 2, and only that panel shows coloured. Clearing restores 30. The post-setup fingerprint never changed.
Since WT-16 (#390, 2026-11-08) filtered-out Faces keep their plain colour instead of a wash, so the 2026-10-17 wash
counts are not repeated; the helper copy for this run drops them.

## Ready for hold

Each case folder holds a `steps.md` recipe and a driver whose first lines launch the fixture and run `begin`. The
folders hold no baseline, so the conductor's `begin` starts cleanly.

- `M05`: a fresh copy of MS1's reference model, sixteen assertions, one per clause group of its label. The tab
  order (Mechanical after Thermal Bridges, before Library) was seen in a probe capture but not recorded.
- `M07`: a fresh copy of the built fixture `m07-reference.skp` (M06's reference System on both Zones), fourteen
  assertions.
- The eleven other Zone views cases: the prior runs' fixtures, assertion ids and recipes
  ([phase 3a rerun](phase-3a-rerun-2026-10-16.md), [Ruby readability batch](ruby-readability-2026-10-17.md)), with
  the wash change noted. `ZO-O7` last recorded fail on its component-copy clause (#181).

Windows on this host: the model window 2028 x 1058 at (0, 30); the panel opens 1149 x 809 at (-1282, 292), on the
display left of the main one.

## Open

- The hold: `M05`, `M07` and eleven Zone views cases, one full-screen sitting from the conductor.
- p4-15 decision 3 (section or whole file) for `M06/save-reopen-reexport-same`, as for MS1's `M04`.
- The background-control capability: either the controller regressed since 2026-10-26 or that observation depended
  on a state not recorded. The capabilities reference should name the 2026-11-25 refusal.

## Restoration

No fault, provider override or preference change. Each approved location created was revoked after its export.
SketchUp was quit at the end with no open document. Every save used an absolute path under `_private/host/`.
