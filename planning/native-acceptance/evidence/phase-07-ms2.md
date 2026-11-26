# Phase 7 MS2 host sitting: M05 to M07 and the Zone views repeats

DATE: 2026-11-25
STATUS: Recorded in part. M06 and UXR-FILTER-OCC pass. M05 and M07 ran in the conductor's first full-screen hold
on 2026-11-26 and are recorded unknown on named clauses. The other eleven Zone views cases were not reached in that
hold and are owed to the second one.
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
| `M05` | unknown (hold, 2026-11-26) | 14 pass; by-program-flow, panel-sizes unknown |
| `M07` | unknown (hold, 2026-11-26) | 10 pass; systems-table, heater-type-change, columns-hide-identity, locate-from-export unknown |
| `ZO-H1`, `ZO-H2`, `ZO-H3`, `ZO-O7`, `PTAB`, `HGUI`, `UXR-SOLVE`, `UXR-FILTER`, `UXR-HATCH`, `UXR-PAINT`, `UXR-COLOUR` | ready for hold | not reached in the first hold; owed to the second |

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
with the wrong article and a doubled full stop. The preflight lists `mechanical.hot_water_pooled` in one row per
System.

### UXR-FILTER-OCC

A fresh copy of the 2026-10-17 fixture, two solved six-Face Zones, plus the labelled nested and shared-component
geometry: three distinct paths, two of them ending in the same Face. By Zone fills 30 triangles. Masking the nested
and West-shared paths fills 4, and the window capture shows only those two panels coloured. Masking the East-shared
path fills 2, and only that panel shows coloured. Clearing restores 30. The post-setup fingerprint never changed.
Since WT-16 (#390, 2026-11-08) filtered-out Faces keep their plain colour instead of a wash, so the 2026-10-17 wash
counts are not repeated; the helper copy for this run drops them.

## The first hold, 2026-11-26

The conductor ran M05 and M07 in one full-screen hold (07:47 to 08:30, shared with MS3's cases), recorded with
`acceptance_case.py finish` into this run directory.

- Build: `main` at `d0adcba8`, installed RBZ sha256 `b2b6bfdf3ff575ccd2806be1fe69166a55b77c43f29319505ef2a7853d336a75`,
  the MS3 build; no `src/` or `tools/` change between `d8759630` and `d0adcba8`. SketchUp 26.1.188, Ruby 3.2.2,
  macOS 26.7.1, a fresh process per case.
- Control: panel gestures by full-screen computer use, panel 1280 x 800 at (768, 245); bridge reads and labelled
  setup in separate calls; native Undo and Redo by System Events Edit-menu presses with the model window raised
  (AXRaise), the panel reopened through Extensions afterwards.

### M05: unknown, 14 pass, 2 unknown

On a fresh copy of MS1's reference model with no Ventilators:

- The tabs read Climate, Zones, Programs, Assemblies, Window Types, Thermal Bridges, Mechanical, Library, Export.
  Ventilation shows the Ventilators pill beside Duct Types and Ducting, an empty table and + New Ventilator.
- Two creates through + New Ventilator gave ERV-1 and ERV-2, read back by `ventilators.all`. ERV-1's electric
  efficiency edited in place from 0.55 to 0.45 read back 0.45. A draft on ERV-2, committed after a labelled bridge
  update of the same field, was refused "Changed in the Model. Escape to cancel and re-edit." with the draft kept;
  the Model held the bridge value, which Escape then showed.
- Duplicate prefilled "ERV-1 (copy)". Deleting ERV-1, in use on both Zones, with ERV-2 as replacement moved both
  Zones; deleting ERV-2 with Clear existing uses emptied them. Two native Undo Delete Ventilator presses restored
  ERV-2, then ERV-1 on both Zones.
- The Serves picker groups Zone A and Zone B under the MAIN Building Segment heading. With ERV-2 on Zone B, adding
  Zone B to ERV-1 gave a refusal naming ERV-2 and "ERV-2, will be replaced"; Replace and assign put ERV-1 on both.
- Balance: ERV-1 on Zone A 60 / 50, amber; ERV-2 on Zone B 40 / 40; ERV-1 on both 100 / 90.
- Units: 0.45 Wh/m³ under SI, 0.76 W/cfm under IP. A draft typed on ERV-2 was committed in SI when the IP toggle
  took focus (blur commits) and then read in W/cfm. The value kept its unit, but no draft crossed the switch as a
  draft; the assertion is recorded pass on that reading.
- The row's chevron opens the two optional values (subsoil heat exchanger, preheated intake temperature). Columns
  hides Manufacturer, Model and Notes; Tag stays.
- By ventilator: the legend counts Zones per item; Zone A and Zone B take their item's colour, and a Zone whose slot
  was cleared (labelled `serves.clear`) is uncoloured.
- Export > Worth checking: Locate on an unserved Ventilator opens Mechanical narrowed to it ("1 of 3"); Locate on an
  unventilated Zone opens Zones with that Zone checked.
- Native Undo with the model window raised: Create Ventilator, Assign Equipment and each Delete Ventilator were one
  step each, and Redo restored them. The cell edits and the duplicate were not pressed one by one.
- At 1280 x 800, 420 x 732 and 360 x 520 there is no page-level sideways scroll; the table scrolls inside its frame
  and the subtab row overflows with an arrow.
- Unknown: `by-program-flow` was not run (the labelled Program setup was not prepared within the time box), and
  `panel-sizes` leaves "picker inside the pane" unobserved: the Serves picker was not opened at 420 or 360 px.

Operator error, recorded in the case's hold log: a click on the model title bar sent the panel behind the document,
and keystrokes meant for the panel erased one Group in the viewport. Edit > Undo Erase restored it at once, and the
stack then read Undo Create Ventilator again.

### M07: unknown, 10 pass, 4 unknown

On a fresh copy of `m07-reference.skp` (M06's reference System HWS-1 on Zone A and Zone B):

- Mechanical's subtabs read Ventilation, Heat Pumps, Hot Water, Pumps, Fans, Electric Heating; Hot Water holds the
  pills Systems, Heaters, Tanks, Pipe Types, Piping.
- Deleting HWS-1 offers a replacement only, with no clearing choice, since no other System can take its place.
- Heaters carry a System select per row; coverage edited from 30 to 40 percent stores 0.4.
- Tanks carry Role and Type selects and the export slot (Tank 1, Tank 2, Buffer tank); a new fourth storage tank
  reads "No slot left" in amber. Capacity reads litres under SI and US gallons under IP (300 L, 79.3 gal); the
  units switch commits an open draft through blur, as in M05.
- The New Heater and New Tank dialogs ask a Tag and a System, HWS-1 preselected.
- By hot water system colours the served Zones with a legend count; a Zone whose System was cleared is uncoloured.
- Native Undo with the model window raised: Clear Equipment, Create Hot Water Tank and Edit Hot Water Heater each
  reverted one write, read after each; three Redos restored them.
- At 1280 x 800, 420 x 800 and 360 x 520 tabs, subtabs and pills wrap or overflow, with no page-level sideways
  scroll.
- Unknown, each with what was seen:
  - `systems-table`: the HWS-1 row with its Serves chips, tap points, heaters, tanks, calculation method and the
    read-only recirculation columns from piping, and the stale-value refusal keeping the draft. Calculation method
    2 with its info badge and the Segment pooling note (a second System on one Segment) were not set up.
  - `heater-type-change`: changing the heat pump heater to the monthly variant asks for its four values and says
    it removes the performance ratio; afterwards the ratio reads a dash and the entered COP and rating
    temperature show. The paste over an inactive cell was not tried.
  - `columns-hide-identity`: done on Tanks only, not on Systems and Heaters.
  - `locate-from-export`: the unslotted-tank finding's Locate narrows Tanks to that tank ("1 of 4"). No unserved
    System existed, so the Systems narrowing is unobserved.

### Findings from the hold (MS2 cases)

Product observations, none blocking a clause:

- Finding and refusal text doubles the noun: "Zone Zone B has no Ventilator", "Zone Zone B is served by ...".
- The Columns menu closes after each toggle, so hiding three columns takes three opens.
- A units switch commits an open cell draft through blur.
- At 420 and 360 px the Ventilators table keeps its horizontal scroll position, which hides the Tag column.
- In the Hot Water Systems table the read-only recirculation columns sit after Notes, at the far right.

## Ready for hold

Written before the first hold. M05 and M07 have since run (above); the eleven Zone views cases below are still
staged, unchanged. No case folder held a baseline, so the conductor's `begin` started cleanly. What is staged
differs by case:

- `M05` and `M07`: a driver that launches the fixture, opens the panel and runs `begin`, and a clause-level
  `steps.md` with the host facts above and no coordinates. `M05` uses a fresh copy of MS1's reference model, sixteen
  assertions, one per clause group of its label; the tab order (Mechanical after Thermal Bridges, before Library)
  was seen in a probe capture but not recorded. `M07` uses the built fixture `m07-reference.skp` (M06's reference
  System on both Zones), fourteen assertions.
- The eleven other Zone views cases: driver stubs the conductor completes (the `--target` and `--probe` text, and
  for `ZO-H3`, `UXR-FILTER`, `UXR-PAINT` and `UXR-COLOUR` the predecessor's process and saved file, since they have no
  launch of their own). Their `steps.md` points at the prior runs' fixtures, assertion ids and observations
  ([phase 3a rerun](phase-3a-rerun-2026-10-16.md), [Ruby readability batch](ruby-readability-2026-10-17.md)); those
  runs left no step-by-step recipe. The fixture sources exist. `ZO-O7` last recorded fail on its component-copy
  clause (#181).

Windows on this host: the model window 2028 x 1058 at (0, 30); the panel opens 1149 x 809 at (-1282, 292), on the
display left of the main one.

## Open

- The second hold: the eleven Zone views cases. M05's and M07's unknown clauses need a rerun, not yet assigned to a
  sitting.
- Two pass readings for Ed: M05's `electric-efficiency-units` passed with the draft committed on blur rather than
  kept as a draft across the switch, and M05's `each-write-one-undo` passed without the cell edits and the
  duplicate pressed one by one.
- p4-15 decision 3 (section or whole file) for `M06/save-reopen-reexport-same`, as for MS1's `M04`.
- The background-control capability: either the controller regressed since 2026-10-26 or that observation depended
  on a state not recorded. The capabilities reference should name the 2026-11-25 refusal.

## Restoration

No fault, provider override or preference change. Each approved location created was revoked after its export.
SketchUp was quit at the end with no open document. Every save used an absolute path under `_private/host/`.
The first hold ended at a case boundary with SketchUp quit; MS3's evidence records its restoration.
