# Phase 7 MS2 host sitting: M05 to M07 and the Zone views repeats

DATE: 2026-11-25
STATUS: Recorded in part. M06 and UXR-FILTER-OCC pass. M05 and M07 ran in the conductor's first full-screen hold
on 2026-11-26 and are recorded unknown on named clauses. The second hold (2026-11-26) recorded UXR-SOLVE,
UXR-FILTER, UXR-PAINT, UXR-HATCH, ZO-H1, ZO-H2, ZO-H3 and PTAB pass and UXR-COLOUR fail; ZO-O7 was begun and not
finished after SketchUp crashed, and HGUI was not run.
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
| `UXR-SOLVE` | pass (second hold, 2026-11-26) | checked-qualification, solve-surfaces, native-undo-redo |
| `UXR-FILTER` | pass (second hold, 2026-11-26) | type-show-walls, mask-persists-modes, composed-empty, clear-restores, no-write |
| `UXR-PAINT` | pass (second hold, 2026-11-26) | type-paint-drag, type-undo-redo, boundary-paint-click, assembly-paint, no-icons, narrow-menus |
| `UXR-COLOUR` | fail (second hold, 2026-11-26) | paint-selects-mode, override-survives pass; escape-retains-boundary, assembly-stop-retains fail |
| `UXR-HATCH` | pass (second hold, 2026-11-26) | hatch-with-selection-edges, service-readback |
| `ZO-H1` | pass (second hold, 2026-11-26) | manage-empty-escape, dialog-sizes, draft-add-escape-enter, modal-and-defaults, model-switch-draft, fresh-make |
| `ZO-H2` | pass (second hold, 2026-11-26) | adoption-undo-redo, chip-assignment, management-batch, used-merge, used-removal, default-replacement, fresh-reopen |
| `ZO-H3` | pass (second hold, 2026-11-26) | normal-panel-no-dev-style, custom-hue-edges-hatch, filter-composes, held-filter-rename, new-model-clear |
| `PTAB` | pass (second hold, 2026-11-26) | heading-new, create-undo-redo, depth-bubble, psi-default-choice, defaults-native-undo, narrow-layout, long-name, escape-draft |
| `ZO-O7` | begun, not finished (second hold, 2026-11-26) | no row; the 2026-10-18 fail row stands |
| `HGUI` | not run | owed |

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

## The second hold, 2026-11-26

The conductor's second full-screen hold ran MS3's line-group cases ([phase-07-ms3](phase-07-ms3.md)), then the
Zone views repeats on the recipes in the run directory's `HOLD2-REPEATS.md`. Each finished case was recorded with
`acceptance_case.py finish`; these rows were written between 11:07 and 11:40.

- Build: `main` at `75ae8020`, installed RBZ `5801c44522f735652f005e8e09ca019484b65c78550458bced34918cbf70fda0`,
  the build MS3's second-hold section records. SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1.
- Control: panel and viewport gestures by full-screen computer use from the conductor; bridge reads and labelled
  setup in separate calls; native Undo and Redo by System Events Edit-menu presses with the model window raised
  (`edit_raise.py`).
- Chains: UXR-SOLVE, UXR-FILTER, UXR-PAINT and UXR-COLOUR ran in one process on one file, each saved under its own
  name; ZO-H3 continued in ZO-H2's reopened process. The others started from fresh fixture copies.
- Changed surfaces, recorded as the recipe's decisions and named in each observation: ZO-H1's dialog clauses ran on
  Manage Levels, the same dialog component, because the Building Segments dialog no longer exists, and its default
  clause reads the heading's Default tag and the Settings checkbox; ZO-H2's `default-replacement` ran through the
  heading's Delete dialog; PTAB reads "Model value" where it read "None" and has a third control in the narrow row.

### UXR-SOLVE: pass

The check-all box gave "12 Faces selected", "2 Zones checked" and Solve enabled; unchecking one row gave 11, 1 and
Solve disabled; the panel's check state did not touch SketchUp's selection. Solve gave the two facing walls Surface,
each naming the other under October's pair id; native Undo and Redo Solve Zone Adjacency return the snapshots
before and after exactly. Evidence: `UXR-SOLVE/05-solved.json`, `06-edit.jsonl`.

### UXR-FILTER: pass

The Type menu's Show list narrowed to Walls: eight Wall paths in `filter_paths`, "12 Faces selected, 4 hidden", the
roof left plain. The mask held through Colour by Zone, Off and Boundary. Unticking Outdoors and Surface too gave
"No Zones match this filter." and an empty mask; each Clear filter restored its step. Revision and `modified`
unchanged throughout, and the Edit menu's top title the same before and after. Evidence: `UXR-FILTER/01-walls.json`,
`03-empty.json`, `05-type-cleared.json`, `06-no-write.json`.

### UXR-PAINT: pass

The Type menu's paint icon turned Colour by Face type on and armed the tool. One drag across the two front walls
classified exactly those two as Roof or ceiling ("Classified 2 Faces.", October's Faces); Undo and Redo return the
snapshots. Boundary Ground and the local Assembly each painted one click's Face only. Paint icons appear beside
Ground, Outdoors, To neighbour and the Assembly, not beside Attached zone, Surface or None. At 420 x 732 and
360 x 520 the bar and menus stay in the pane and Escape stops the tool with no write. Evidence:
`UXR-PAINT/03-paint-type.json`, `04-edit.jsonl`, `06-boundary.json`, `09-edit.jsonl`, `14-rev-end.json`.

### UXR-COLOUR: fail, 2 pass, 2 fail

- Pass: `paint-selects-mode` (each menu's paint icon switches Colour by to its mode) and `override-survives` (with
  Assembly paint active, Colour by > Face type from the Extensions menu takes over and Escape keeps Face type).
- Fail: `escape-retains-boundary`. Starting from Colour by Off, Boundary > Ground paint set Boundary condition; a
  click on empty sky left it; Escape, with the viewport or the panel key, returned to the Select tool with Colour by
  Off and the legend gone, reproduced twice. With Boundary on before painting, Escape leaves Boundary.
- Fail: `assembly-stop-retains`. With Boundary on, Assembly paint set Assembly; Escape left Boundary condition, not
  Assembly.

This build's Escape restores the Colour-by mode active before paint started instead of keeping the paint's mode.
No recorded decision for the change was found. For Ed: an intended change, which rewrites both clauses, or a
regression. Evidence: `UXR-COLOUR/02e-after-escape.json`, `02h-explicit-then-escape.json`,
`03b-assembly-escape.json`, `04b-override-escape.json`.

### UXR-HATCH: pass

With West's front wall selected, Colour by > Assembly from the Extensions menu hatches all twelve unclassified Faces
grey with West's selection edges drawn over the hatch (shots `01-hatch-selection.jpg`). The service reads
`unclassified_hatch` 1,144 (October's count), no fills, and no write. Its session revision reads 1, not the recipe's 4, which
was October's session count. Evidence: `UXR-HATCH/02-hatch-service.json`.

### ZO-H1: pass

On Manage Levels: the empty dialog's Escape writes nothing; with three rows Save and Cancel stay visible at
1280 x 800, 420 x 732 and 360 x 520, the list scrolling at 360; Add focuses the new name, a draft Escape writes
nothing and Enter saves one Level in one Undo step ("Undo Manage Zone Options"); a click on another tab leaves the
dialog open; switching Models with a draft open drops the dialog and writes nothing. A new Building Segment carries
the Default tag and its Settings checkbox is locked. Make Zone on a new Model's box gives one Zone in one default
Segment. Evidence: `ZO-H1/01-empty-escape.json`, `02-sizes-escape.json`, `04-add-enter.json`,
`05-new-segment.json`, `05-switch-return.json`, `06-first-make.json`.

### ZO-H2: pass

From the legacy fixture: Adopt, a Level chip, a rename and recolour batch, merging a used Level (its orphan stamp
included) and removing one, and deleting the default Segment with its Zones moving to the new one. For each write,
the read after Undo equals the read before and the read after Redo equals the read after, field by field. After save
and a fresh-process reopen the reads equal the saved ones. `default-replacement`'s Cancel half was not observed.
Evidence: `ZO-H2/01-adopted.json` to `06-default-replaced.json`, `edit.jsonl`, `09-reopened.json`.

### ZO-H3: pass

The panel opened normally shows no row actions forced visible. A custom-hue Level colours Zone 1 with its selection
edges, Zone 2 hatched; hiding that Level in the Show list masks Zone 1 and keeps its selection edges; renaming and
recolouring it keeps the mask; a new Model reads Colour by Off, no mask and no Zones. Evidence:
`ZO-H3/03-filter.json`, `04b-mask.json`, `05-new-model.json`, shots `02-custom-hue-edges-hatch.jpg`.

### PTAB: pass

Library > Frames and Psi-Install Types carry "+ New" in the Library heading with the action bar below. Create Frame
is one Undo step. The Depth bubble holds invalid text with its message and stores 0.12 m from "120 mm"; the
Psi-Install choice offers "Model value" and applies at once; two native Undos return both defaults. At 420 px Depth
wraps to a second row and its bubble opens inside the panel; a 59-character Psi-Install name ellipsises with both
chevrons inside; a draft Escape writes nothing. Evidence: `PTAB/edit.jsonl`, `04-depth.json`, `05-psi-default.json`,
`edit-defaults.jsonl`, `09-escape-draft.json`.

### ZO-O7: begun, not finished

`begin` ran and no `finish` followed, so there is no row; the 2026-10-18 fail row on #181 stands. From the hold log
(`ZO-O7/steps.md`):

- Legacy options adopted from the heading's Adopt. `same-model-copy-independent` was observed to pass: the paste is
  independent and Undo Paste returns the adopted read.
- `component-copy-shared`: a native Paste In Place of a wrapper Group holding Zone 1, and a labelled
  `add_instance` of its definition, were each made unique at once with a new Zone identity, so the copied-Group
  refusal the clause names could not be reached. A component placed twice read `shared_definition`, as expected.
- A labelled bridge evaluation setting `active_path` to a component placement and selecting the Zone inside it then
  crashed SketchUp 26.1.188 at 11:32:56 with `EXC_BAD_ACCESS` (`KERN_INVALID_ADDRESS`). The hold log reads the crash
  in SketchUp's notification code, called from the Ruby C function, with no PH-Composer Ruby frames above it; the
  crash file names PH-Composer only as the development bridge's thread. Unsaved state was lost. Crash log:
  `ZO-O7/crash-113259.ips`.

The rest of the case is owed to a later sitting, and how to reach the copied-Group refusal needs a recipe change.

### HGUI: not run

It rewrites this machine's library setup and drives native Save panels, so it was left for a sitting with Ed
present.

### Findings from the second hold (MS2 cases)

- UXR-COLOUR's Escape behaviour (above), for Ed.
- ZO-H1: a long Level name is clipped at the field edge without an ellipsis once the field loses focus.
- ZO-H2's `default-replacement` passed with its Cancel half not observed.

## Ready for hold

Written before the first hold. M05 and M07 have since run (above), and the Zone views cases ran in the second hold
on the recipes in `HOLD2-REPEATS.md`, not on the stubs below. No case folder held a baseline, so the conductor's `begin` started cleanly. What is staged
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

- From the second hold: ZO-O7 unfinished (the SketchUp crash, and a recipe that reaches the copied-Group refusal)
  and HGUI not run. M05's and M07's unknown clauses need a rerun, not yet assigned to a sitting.
- For Ed from the second hold: UXR-COLOUR's Escape restoring the prior Colour-by mode, an intended change or a
  regression; the ZO-O7 host crash on an `active_path` change into a component placement.
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

The second hold: no fault and no provider override in these cases. ZO-O7's process crashed and its unsaved state
was lost; its run directory keeps the `begin` baseline with no `finish`. HGUI did not run, so the machine's library
setup was not touched.
