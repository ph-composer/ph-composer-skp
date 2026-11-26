# Phase 7 MS3 host sitting, the part needing no full-screen card

DATE: 2026-11-25
STATUS: Recorded in part. M13a, M14a, T04 and T08 pass (2026-11-25). The conductor's first full-screen hold (2026-11-26) recorded M09, M11 and T09 pass and M08, M10 and M16 unknown on named clauses. After the `groups.make` fix (#600), M13c, M13d, M14d and M14e were rerun with the panel closed and pass on the fixed build (2026-11-26). M13b and M14c still carry their crash fail; with M13e, M14f and M15 they are staged for the second hold.
ISSUE: #562

Synthetic summary of the MS3 sitting (D4-31) for [Phase 7 Mechanical](../../features/phase-07-mechanical/ACCEPTANCE.md):
the cases the bridge, window captures and System Events Edit-menu presses can observe. Raw Models, HBJSON, reports,
crash logs, drivers, each case's `steps.md` and the hold recipe (`HOLD.md`) stay in gitignored
`_private/host/phase-07-ms3/`.

## Build and host

- Source: `main` at `d8759630`. `make rbz && make install && make bridge-install`; `dist/ph_composer.rbz` sha256
  `b2b6bfdf3ff575ccd2806be1fe69166a55b77c43f29319505ef2a7853d336a75`, 9,097,094 bytes (27,943,439 installed), the
  same size as MS1's `2fd51f46` and a different hash; `acceptance_run.py package` matches, 877 entries, no extras.
- SketchUp 26.1.188, Ruby 3.2.2, macOS. Each case in a fresh process from `host_bridge.py launch`, panel closed.
  HBJSON reloaded with honeybee-core 1.64.65, honeybee-energy 1.123.23, honeybee-ph 1.33.68.

## Control route

Product writes through registered actions (`PhComposer::API`), reads through the bridge in separate calls, exports
with MS1's labelled approved-location stand-in. Native Undo, Redo, Copy and Paste In Place by System Events AXPress
of the Edit menu item by its exact title, with SketchUp already frontmost after its launch and never fronted; a press
refuses when SketchUp is not frontmost or the title differs. SketchUp's own context entries ("Undo Open",
"Undo Close") are pressed first where a Locate or a path change put them on the stack. No full-screen control and no
panel or viewport gesture.

Labelled setup, never an assertion: the case lines drawn with Ruby in the open group (what the Line tool draws),
SketchUp's selection filled by Ruby (what a pick does; the product's selection reads take it as they find it), a
line moved by replacing its Edge with its record copied, wrapper Groups, hiding, Make Unique, and the Piping and
Ducting groups themselves (below).

## The defect: creating a line group crashes SketchUp

`ph_composer.piping.groups.create` (with HWS-1) and `ph_composer.ducting.groups.create` (with ERV-1), sent as
registered actions from the bridge, never answered: SketchUp 26.1.188 died with EXC_BAD_ACCESS in its own code
called from Ruby. Reproduced three times through the action (building the piping fixture, then once in each of M13b and M14c), and once with a raw-Ruby
isolate on a blank Model: in one operation, `add_group`, an attribute, then
`active_path = [group]`. Without the path change, the Group is gone after the commit ("reference to deleted
Entity"): SketchUp deletes an empty Group at commit. `LineGroups::CreateStep` adds an empty Group, writes its record
and enters it in one operation, so the edit path ends on a deleted Group. The panel's New Piping group and New
Ducting group send the same action; they were not pressed. Every case needing a group therefore ran on a group
written by labelled setup: a Group holding the case's lines, then the record the create step writes, through the
feature's own group store. A fix to the create step stales M13d, M14d and M14e.

## Results

| Case | Outcome | Assertions |
| --- | --- | --- |
| `M13a` | pass | walkthrough-registered-actions, native-undo-redo-five-steps, save-reopen-catalog-ids |
| `M14a` | pass | the same three, the Undo of the shape change bringing the 160 mm diameter back |
| `M13d` | pass (rerun on 55a1f8f7, 2026-11-26) | preflight-empty, export-reload-hot-water, branch-unconnected-refuses-locate-undo, save-reopen-reexport-same |
| `M14d` | pass (rerun on 55a1f8f7, 2026-11-26) | schedule-hand-measurement, run-missing-erv1, locate-wrapped-and-hidden, save-reopen-same-identifiers, measurement-50000-edges |
| `M14e` | pass (rerun on 55a1f8f7, 2026-11-26) | preflight-empty, export-reload-ventilation, shared-case-equal-identifiers, delete-erv2-null-refuses-locate-undo, save-reopen-reexport-same |
| `T04` | pass | hand-calculation, open-context, counted-twice-undo, outside-zone, locate-nested, measurement |
| `T08` | pass | export-readback, metadata-guard, save-reopen-reexport, outside-zone-disclosed, warnings-preflight-report, blocking-keeps-prior-pair, forced-refusal, required-refusal-withholds, snapshot-measure |
| `M13b` | fail | h1-create-empty-group-active fail; h4-assign-clear-one-undo, h4-paste-shared-refuses-until-unique, hws-delete-retargets-one-undo pass; h2-line-tool-in-group, h3-split-tee-copied-record unknown |
| `M14c` | fail | create-linked-group-active fail; assign-quantity-clear-one-undo, paste-shared-keeps-link-refuses-until-unique, erv-delete-retargets-group-and-zone-one-undo pass; line-tool-in-group unknown |
| `M13c` | pass (rerun on 55a1f8f7, 2026-11-26) | schedule-hand-measurement, branch-unconnected-floor2, locate-into-wrapped-group, save-reopen-same-identifiers, measurement-50000-edges, thermal-bridge-repeats |
| `M09` | pass (hold, 2026-11-26) | all 13 |
| `M11` | pass (hold, 2026-11-26) | all 14 |
| `T09` | pass (hold, 2026-11-26) | all 10 |
| `M08` | unknown (hold, 2026-11-26) | 12 pass; heating-cooling-data, blended-copy unknown |
| `M10` | unknown (hold, 2026-11-26) | 13 pass; save-reopen-reexport unknown (list order only) |
| `M16` | unknown (hold, 2026-11-26) | 6 pass; dialog-defaults unknown (68 °F under IP unchecked) |
| `M13e`, `M14f` | ready for hold | not begun; staged for the second hold on `groups.make` |

### Fixtures

From MS1's `reference.skp` (Zone A and Zone B in Segment Main, Spaces A1 and B1), in fresh processes:

- Piping: PT-1 and PT-2, HWS-1 (8 tap points) serving both Zones, ACCEPTANCE's piping case in PG-1 at the root.
  The schedule matches the hand measurement. The host has 18 Edges, not ACCEPTANCE's 17: the loops' shared vertex at
  (1.2,1,9) lies on Floor 3's first line, so SketchUp splits it there. Floor 3 stays one 3.000 m branch.
- Ducting: ERV-1 on Zone A and ERV-2 on Zone B (MS1 values), DT-1 and DT-2, DG-1 and DG-2 with ACCEPTANCE's four runs.
- Zone C: a third box Zone without a Space, its Faces given the reference Assembly, for M10 and M11.

### M13a and M14a

On a blank Model, panel closed, each walkthrough ran its five registered actions: create, create, edit, duplicate,
delete. Edit > Undo, five times, took back one step each, read after each, to an empty catalog. Redo five times
rebuilt it under the same ids. After save and a fresh-process reopen, `pipe_types.all` and `duct_types.all` read the
expected catalogs, `user_data` included, under the ids recorded before the save. M14a's Undo of Edit Duct Type read
DT-2 back as Round, 160 mm, with no width or height.

### M13d

`piping.export_preflight` empty. The export reloads with both Rooms' `hot_water_system` equal, with HWS-1's id. One
trunk of 9.000 m, multiplier 12, no demand recirculation, PEX 19.05 mm with 12.7 mm of insulation at 0.04,
reflective. Three branches of 4.000, 4.000 and 3.000 m, PEX 12.7 mm, uninsulated, with fixtures of 1.0 and 1.5,
1.0 and 1.5, and 1.0 and 1.0 m. Recirculation elements of 9.000 and 2.000 m. `recirc_temp` 54.09 and
`recirc_hours` 19, equal to `piping.systems`. 8 tap points. Floor 2's first line moved to start at (1.05,1,6): the
export failed with `piping.branch_unconnected`, and the preflight row's Locate opened PG-1 and selected that branch's
two Edges. Undo cleared the finding. After save and reopen, the re-export's `hot_water_system` sections are equal,
every pipe and segment identifier included. The whole files are equal once UUID-shaped values are masked.

### M14d and M14e

The ducting schedule reads ERV-1 Outdoor air 2.500 m and Exhaust air 1.800 m, and ERV-2 2.500 m and 1.500 m at
quantity 2. `ducting.ventilators` gives 2.5/1.8 and 2.5/3.0, and `duct_types.all` gives used lengths of 4.3 and
5.5 m. Clearing DG-1's Exhaust air gave `ducting.run_missing` on ERV-1 alone, not blocking; Undo restored it.
`runs.locate` into DG-1 inside a wrapper opened wrapper > DG-1 and selected the run's Edges. With the wrapper hidden
it refused `ducting.hidden` and moved nothing. Run and segment identifiers held across reopen.

The export reloads as ACCEPTANCE states. Room A has one round supply element of two segments (0.16, insulation
0.0254 at 0.04, reflective) and one 1.800 m exhaust element. Room B has one rectangular supply element (0.2 x 0.1,
0.0508 at 0.035, not reflective) and two 1.500 m exhaust elements with distinct ids. Totals are 2.5/1.8 and 2.5/3.0.
Shared case: both Rooms carry DG-1's two elements under equal ids, the reload accepts it, and
`ducting.ventilator_unexported` is reported on ERV-2. ERV-2 deleted with null: the export failed with
`ducting.group_unlinked`, and its Locate opened DG-2 and selected that run's duct (decision 7). Undo restored ERV-2.
The re-export's ventilation sections are equal.

### M13c

The schedule matches the hand measurement: one trunk with three branches of two twigs each, two recirculation runs,
and HWS-1 at 11.000 m, 54.09 °C, 19 h. Floor 2's moved line gives `piping.branch_unconnected` on that branch alone.
`runs.locate` into PG-1 inside a wrapper selects the run. The 35 identifiers hold across reopen. The thermal-bridge
repeats are T04 and T08 (below); T09 is owed to the hold, so the case stays unknown.

### M13b and M14c

H1 and its ducting twin fail: they are the crash. On a labelled group, the rest passes:

- Assign and clear: each is one native Undo step, and Undo and Redo restore it. Ducting covers type and direction,
  then quantity 2 keeping both, then clear.
- Paste: Edit > Copy and Paste In Place give two occurrences of one definition, with `*.shared_definition` on every
  run. An assign through references to the closed copy refuses `target.shared_definition`; after Make Unique it
  completes. Opening a shared copy to select its Edges makes SketchUp make it unique, so the refusal is reachable
  only through references.
- Delete with a replacement: HWS-1 to HWS-2 retargets both groups and both Zones, and ERV-1 to ERV-2 retargets the
  groups and Zone A. Each is one Undo step that restores.
- Line tool: H2, H3 and M14c's Line-tool clause need the native Line tool and the created group. They stay unknown.

### T04 and T08

These repeat the October runs with M13c, because the chain rule moved to `core/edge_runs.rb`.

- Hand calculation, open-context reads, outside-zone, nested Locate and the T08 export and reopen hold as recorded
  in October.
- Coincident Edges: Parapet on the shared x = 5 m roof Edge in both Zones now counts once, in Zone A (Parapet 1
  closed, 18.000 m; Parapet 2 12.000 m), with no finding. WT-23 (#397, 2026-11-08) replaced `counted_twice` with
  `coincident_conflict` for Edges that differ. T04's and T08's labels still say "counted twice". The two
  assertions are recorded pass under WT-23's contract; that reading is for Ed.
- Measurement at 50,040 Edges: `schedule.all` 1,928 ms (1,842 in October). The whole-panel snapshot took 31,032 ms
  against 12,064 in October. This is a measurement only; no cause is claimed.
- T08's snapshot capture took 1.53 to 1.65 s.

### Line-group measurements, 50,000 Edges

- Piping, 2,000 pipes in twenty groups: `piping.schedule` 83.7 ms, `piping.systems` 75.0 ms, `pipe_types.all`
  74.7 ms, medians of seven.
- Ducting, 200 ducts in forty groups and forty Ventilators each serving one Zone (no Spaces): `ducting.ventilators`
  15.6 ms and `duct_types.all` 13.5 ms. The schedule took 341.1 ms, most of it `mechanical.ventilators.all`
  (319.0 ms); it is read on request only.
- Every snapshot section is under the 200 ms target.

## The first hold, 2026-11-26

One full-screen hold from the conductor, 07:47 to 08:30, ran a probe and then, in order, MS2's M05 and M07
([phase-07-ms2](phase-07-ms2.md)), M09, M10, M11, M08, M16 and T09. It ended at a case boundary within its time
box; the Zone views repeats were not reached. Each case was recorded with `acceptance_case.py finish`. The cases
the `groups.create` fix will stale were left out by plan.

- Build: `main` at `d0adcba8`, installed RBZ `b2b6bfdf`, the build above; no `src/` or `tools/` change between
  `d8759630` and `d0adcba8`. SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1, a fresh process per case.
- Control: panel and viewport gestures by full-screen computer use, panel 1280 x 800 at (768, 245); bridge reads and
  labelled setup in separate calls; native Undo and Redo by System Events Edit-menu presses; exports with the
  approved-location stand-in, revoked after each; HBJSON reloaded in the pinned stack.

### The probe for the fix

Not a case and no ledger row; recorded in the hold log. It tested two assumptions a `groups.create` fix would rest
on:

- Wrapping selected loose lines in a new Group by Ruby keeps their persistent ids and attribute dictionaries, as one
  Undo step ("Make probe group"), and Undo restores the loose lines.
- The native Line tool draws into an open, labelled Piping group: a line ending on a branch Edge
  T-splits it, 18 Edges becoming 20 with three meeting at the new vertex. Undo Draw Line restores the 18.

### M09: pass

On a fresh copy of MS1's reference model:

- Electric Heating shows the Heaters pill, an empty table and + New Electric Heater. A create gives coverage 100 and
  "Serves no Zone" in amber, stored 1.0. Coverage edited to 60 stores 0.6; 120 holds the cell with "Enter a
  percentage from 0 to 100.", Escape shows 60 and the Model keeps 0.6.
- The Zone picker is grouped under MAIN. EH-1 on both Zones and EH-2 on Zone A leaves Zone A with two heaters.
  Duplicate prefills "EH-1 (copy)" with its coverage. Columns hides Manufacturer, Model and Notes, and the hidden
  set survives save and reopen.
- Export > Worth checking: no coverage finding although Zone A sums 160 percent; the copy is reported unserved, and
  its Locate filters the Heaters table to it ("1 of 3"), Clear filter restoring all rows.
- The export reloads with Room A holding EH-1 (0.6) and EH-2 (1.0) as `PhHeatingDirectElectric`, and Room B EH-1.
- Delete EH-1 with replacement EH-2 leaves EH-2 once on Zone A and on Zone B; native Undo restores both lists, Redo
  reapplies, Undo again restores. Unchecking Zone A in EH-2's picker clears it; Undo Clear Equipment puts it back.
- Save, a fresh-process reopen and re-export: `heating_systems` equal by section (p4-15 decision 3).
- At 420 x 732 and 360 x 520 the subtab row scrolls with arrows and there is no page-level sideways scroll.

### M10: unknown, 13 pass, 1 unknown

On a fresh copy of `reference-zone-c.skp` (the Zone C box without a Space):

- Pumps shows its pill, the table and + New Pump. A create gives hot water circulation (`device_type` 6), quantity 1,
  0 W, 8.76 kh. Type, Power and Operation edited in place, one guarded update each, store 4, 45 W and 5 kh. A
  negative Power holds the cell with "Power cannot be negative."; Escape restores it.
- The row's first button opens the internal heat gain values, the usage profile following the heating type.
- P-1 on Zone A and P-2 on Zones A and C leave Zone A with two pumps. Duplicate copies the values; Columns hides the
  identity columns.
- Export lists the pump on Zone C as `mechanical.zone_without_spaces`, not blocking, its Locate filtering Pumps to it,
  and the copy as `mechanical.item_unserved`. The reload gives Room A both pumps as supportive devices with their
  values, Zone C's Room the second pump, Room B none.
- Delete with a replacement keeps the replacement once on Zone A; native Undo, Redo and Undo again behave.
- Unknown: after save and a fresh-process reopen the re-export has equal Rooms and identifiers, but Room A's
  `supportive_devices` list holds the two devices in swapped order, so the section comparison reports not equal.
  Whether order alone counts as the same HBJSON is p4-15 decision 3, Ed's.
- At 420 x 732 and 360 x 520 the table scrolls inside its frame, with no page-level sideways scroll.

### M11: pass

On a fresh copy of `reference-zone-c.skp`:

- Fans shows its pill, the table and + New Fan. A create gives User-defined, quantity 1, flow 0, runtime 0 and a
  blank Power. Type Kitchen hood, flow 300 m³/h, runtime 10,950 min and 120 W store as entered; a negative Power
  is held and Escape restores it.
- The row's first button opens the electric values: in conditioned space, and Operation empty with the placeholder
  derived from the runtime (0.18 kh a year, 10,950 / 60,000).
- F-1 on Zones A and B and a Dryer F-2 on Zones A and C; Duplicate copies the values; Columns hides the identity
  columns.
- Export lists F-2 on Zone C as `zone_without_spaces`, not blocking, its Locate filtering Fans to it, and the copy as
  unserved. The reload gives Room A F-1 as a type 10 supportive device (120 W, 0.1825 kh) and both fans as exhaust
  ventilators of their classes, Room B F-1 as both objects, and Zone C's Room the dryer only.
- Delete F-1 with replacement F-2 retargets all three Zones; native Undo, Redo and Undo again behave.
- Save, a fresh-process reopen and re-export: `supportive_devices` and `exhaust_vent_devices` equal by section
  (p4-15 decision 3).
- At 420 x 732 and 360 x 520 the subtab row and the table scroll inside the pane.

### M08: unknown, 12 pass, 2 unknown

On a fresh copy of `m07-reference.skp` with a labelled, typed complete climate (design temperatures -10 and 35 °C),
saved before `begin`:

- Heat Pumps sits after Ventilation with five pills: Equipment - Outdoor, Equipment - Indoor, Units - Outdoor,
  Units - Indoor, Blended result.
- New outdoor equipment ODU-A: the 17 °F and 47 °F heating capacities are amber until entered; 5 and 7 kW read
  17.1 and 23.9 kBtu/h under IP and return under SI.
- Indoor equipment is identity only. An outdoor unit names its equipment, with quantity 2; indoor units name their
  indoor equipment and outdoor unit and are grouped under it. Two indoor units on Zone A, then one unchecked, leave
  Zone A with the other (`hp_indoor_unit_ids`).
- Deleting ODU-A while an outdoor unit names it offers only a replacement, disabled until one is chosen; with ODU-B
  the unit retargets, and one native Undo restores ODU-A and the unit's reference.
- With the climate cleared (labelled), Blended result and the Export tab say the blended heat pump is left out of the
  export, still ready to export; native Undo Clear Climate restores it.
- The export reloads with Zone A's Room holding one heat pump system for Segment Main: equal COP 1 and COP 2 (the
  blend), coverage 1.0, recirculation cooling, minimum coil temperature 12.0 °C. A labelled second Segment for Zone
  B, with an indoor unit on it, gives Room B a second heat pump system under its own identifier.
- Save, a fresh-process reopen and re-export: `heat_pump_systems` equal by section (p4-15 decision 3).
- Single native Undo presses each reverted one write: Delete outdoor equipment, Clear Climate, Assign Equipment and
  Edit Selected Zones.
- At 420 x 732 and 360 x 520 the Blended result's pills wrap and the content fits.
- Unknown, each with what was seen:
  - `heating-cooling-data`: COPs to HSPF2 keeps the COPs muted and stored, HSPF amber until entered; EER2/SEER2
    cooling data set with the cooling capacity inactive while cooling data is None; the paired indoor model chosen
    in place. IEER was not exercised.
  - `blended-copy`: the Blended result shows one block, Main, in the estimator's sections, and Copy for the
    estimator put 37 tab-separated rows on the clipboard with its toast. They were not pasted into a spreadsheet,
    and `pbpaste` shows a replacement character where "Inputs · Cooling" has a middle dot.

Operator error, recorded in the case's hold log: during labelled setup, before `begin`, a `zones.update_field` with a
nil Segment moved Zone B out of its Segment; native Undo Edit Selected Zones reverted it at once, and the Segment
was then made with `zones.create_segment`.

### M16: unknown, 6 pass, 1 unknown

On M08's model as saved at its end (Zone A in Main served by a heat pump, Zone B alone in Building Segment 2):

- Saving Main's settings (cooling on, 18.5 °C, temperature-controlled bypass, three air-change values) together with
  a Phius certification field in the same dialog is one native Undo step that returns both sections; Redo restores
  both.
- A negative daytime window rate disables Save with the field's message.
- Cooling switched on for Building Segment 2 while ODU-A's cooling data is None: Export, still ready, warns for both
  Segments that their export carries no heat pump cooling. Two native Undos restore the settings and the cooling
  data, and the warnings go.
- The export reloads with Main's set points and summer ventilation as entered and Building Segment 2 at the
  defaults; winter and summer temperatures come from the Programs. Save, reopen and re-export give the same set
  points and summer ventilation, honeybee-ph's random identifiers aside, and equal `heat_pump_systems`.
- The dialog fits the pane at 1280 x 800, 420 x 732 and 360 x 520, with a scrolling body and Cancel and Save visible.
- Unknown: `dialog-defaults` saw the Mechanical section after Comfort with cooling off, 20 °C, bypass Always, a blank
  ventilation rate and zero window rates, but not the 68 °F reading under IP.

### T09: pass

On a fresh copy of `t09-reference-base.skp`, the thermal-bridge panel run M13c repeats:

- Five Thermal Bridge Types created through the dialog, one without a psi-value. The assign bar assigned Parapet to
  two Zones' roof Edges as two runs; native Undo removed the second run alone and Redo restored it.
- SketchUp's Edit menu route (the selection's PH-Composer > Thermal bridge submenu) assigned two more types.
- Assign by clicking Edges: Balcony at quantity 2 on one Edge, after two clicks that missed the line, and Parapet on
  a rotated Zone's four roof Edges under a labelled top-down camera; Escape returned to the Select tool.
- A second Model through File > New read its own empty state; closing it left the first Model's runs and psi total
  unchanged.
- A labelled line drawn from the middle of a roof Edge split it and both pieces kept the run's record; erasing the
  line healed it, the length unchanged.
- Save and a fresh-process reopen kept types and runs. The export reloads with each run's psi-value, length,
  quantity and group. A fresh launch with no case helper loaded reads the extension registered and the same totals
  through the shipped walkthrough.

### Findings from the hold (MS3 cases)

Product observations, none blocking a clause; MS2's evidence lists those from M05 and M07:

- Finding text doubles the noun: "Building Segment Building Segment 2 has mechanical cooling switched on ..." (M16),
  as "Zone Zone B" in M05 and M07.
- SketchUp's Tags and Entity Info tray overlaps the Serves picker's Assign button near the screen's right edge; it
  was clicked at its visible edge (M10).
- At 420 px the Zones table drops the Actions column, so a Segment's settings button cannot be reached at that width
  (M16).
- The Fans Tag filter lists F-1 (copy), F-2, F-1, unsorted (M11's hold log).
- The estimator clipboard, read through `pbpaste`, shows a replacement character for the middle dot in
  "Inputs · Cooling" (M08); whether the clipboard or `pbpaste` loses it was not checked.

### Owed to the second hold

After the `groups.create` fix: M13b, M13e, M14c, M14f and M15, and MS2's eleven Zone views repeats (ZO-H1, ZO-H2,
ZO-H3, ZO-O7, PTAB, HGUI, UXR-SOLVE, UXR-FILTER, UXR-HATCH, UXR-PAINT, UXR-COLOUR). M13c, M13d, M14d and M14e were
rerun before it (below). The unknown clauses of M05, M07, M08 and M16 need a rerun, not yet assigned to a sitting;
M10's waits on p4-15 decision 3.

## The second hold's preparation, 2026-11-26

No full-screen control. After #600 replaced `groups.create` with `groups.make` (wrap selected loose lines in a new
group in one Undo step), the line-group cases the fix stales were rerun with the panel closed, and the rest staged.

- Build: `main` at `55a1f8f7`. `make rbz && make install && make bridge-install`; `dist/ph_composer.rbz` sha256
  `5801c44522f735652f005e8e09ca019484b65c78550458bced34918cbf70fda0`, 9,101,323 bytes (27,957,539 installed);
  `acceptance_run.py package` matches, 878 entries, no extras. SketchUp 26.1.188, Ruby 3.2.2, macOS. Same control
  route as above.
- M13c, M13d, M14d, M14e: pass. Each driver ran whole on the same fixtures (groups written by labelled setup, as on
  2026-11-25) in fresh processes, and every recorded output equals the earlier run's. M13c's thermal-bridge repeat
  is now complete: T04 and T08 passed in this sitting and T09 in the first hold, and the ledger screens all three
  as unchanged in source. The 50,000 Edge measurements, rerun: piping schedule 81.8 ms, systems 75.2 ms, Pipe Types
  73.1 ms; ducting Ventilators 15.5 ms, Duct Types 13.5 ms, the on-request schedule 350.8 ms (330.8 ms of it
  `mechanical.ventilators.all`).
- `groups.make`, rehearsed as development setup and recorded in no case: for both kinds it wraps Ruby-drawn loose
  lines with their persistent ids kept and the edit path unchanged, in one step, "Make Piping Group" or "Make Ducting
  Group", that native Edit > Undo and Redo restore exactly. `make_refusal` and the action refuse an Edge that bounds
  a Face (`target.wrong_kind`) and lines in an open Zone (`piping.group_in_zone`). The new Group's origin sits at
  the lines' bounds minimum, so a closed group's Edges read in local coordinates.
- Staged for the hold, with drivers rehearsed end to end on Ruby lines standing in for the Line tool: M13b and M14c
  (whole cases, their H1 assertion split into the make and its refusals), M13e and M14f (new fixtures with the
  ACCEPTANCE lines loose at the root, one run drawn natively), and M15 (a fixture with M08's climate and an ordered
  recipe; nothing of it ran). Coordinates for the changed Piping and Ducting bars and the Make dialogs were measured
  on this build.
- The eleven Zone views repeats (MS2's run directory) have complete recipes now. Since their last runs (2026-10-16
  to 2026-10-18), Building Segments moved from a dialog to heading rows (P4a-02), Faces became the Geometry subtab,
  filtered-out Faces lost their wash, and the window defaults gained a psi-value control with "Model value" in
  place of "None". The recipes run the affected clauses on the current surfaces and name each one for the
  conductor. ZO-O7's last row is a fail on #181, which #275 fixed by naming the remedies that work; a bridge check on
  2026-10-20 passed but recorded no row, so the fail stands until the hold.
- `acceptance_ledger.py status` on `55a1f8f7` also screens M09, M10, M11, M13a and M14a for recheck, through #600's
  shared paths.

## Ready for hold

Written before the first hold, which used this recipe for M08 to M11, M16 and T09 (above).

`HOLD.md` sets the panel's placement (1280 x 800 at (768, 245) on the main display) and a calibration step. It gives
coordinates for the tabs, subtabs, pills, New dialogs, the Heaters, Pumps and Fans rows with their hover actions,
popovers and the delete-with-replacement dialog, the Serves picker, the assign bars, the Export rows and the
Building Segment dialog's Mechanical section. These were measured with a development DOM probe on records authored
through registered actions. Coverage is partial for M08 (only the first pill is mapped), M16 (the Annex Segment
setup is not scripted) and the viewport points for T09 and the Line-tool clauses (one-liners, not precomputed).
M09 to M11's export clauses were rehearsed on records authored through registered actions, not as a case run, and
the HBJSON came back as expected: heaters, supportive devices and exhaust ventilators per Room.

The panel cases cannot finish Pass while the create crash stands: M13e's and M14f's New group clauses start from
it. M13b and M14c need a whole-case rerun after the fix, not a Line-tool-only run.

## Open

- The `groups.create` crash (above): fixed by #600 (`groups.make`, with tests); its host cases M13b and M14c are
  owed to the second hold.
- Ed's reading of T04 and T08 under WT-23 (labels still say counted twice), and p4-15 decision 3 (section or whole
  file) for M13d and M14e, and from the first hold for M08, M09, M11 and M16 (compared by section) and M10 (list
  order only).
- The hold's product findings (above), for issues if Ed wants them.
- The second hold (above): M13b, M13e, M14c, M14f, M15 and MS2's eleven Zone views repeats.
- ACCEPTANCE's piping case: 17 Edges as written, 18 on the host.
- The whole-panel snapshot at 50,040 Edges: 31.0 s against 12.1 s in October.

## Restoration

No fault and no provider override. Every approved location this sitting created is revoked: the MS3 export helper
revokes its own, and the four the reused T08 helper approved were revoked at the end. Older approved locations
from earlier sittings are untouched. Four crashes each left SketchUp's BugSplat Problem Report on the next launch,
dismissed with Cancel; nothing was sent. No recovered or autosave file was found. The panel's stored position is
now (768, 245), 1280 x 800, where MS2's notes cite (-1282, 292). SketchUp was quit at the end with no open document.

The first hold: no fault and no provider override. Each of its exports revoked its approved location. Both operator
errors were reverted at once by native Undo (M05 in MS2's evidence, M08 above). The hold ended at a case boundary
and SketchUp was quit.
