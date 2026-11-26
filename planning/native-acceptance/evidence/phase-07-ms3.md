# Phase 7 MS3 host sitting, the part needing no full-screen card

DATE: 2026-11-25
STATUS: Recorded in part. M13a, M14a, M13d, M14d, M14e, T04 and T08 pass. M13b and M14c fail: creating a Piping or
Ducting group crashes SketchUp. M13c unknown until T09. M08 to M11, M13e, M14f, M16 and T09 are staged for one
full-screen hold. M15 not run.
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
| `M13d` | pass | preflight-empty, export-reload-hot-water, branch-unconnected-refuses-locate-undo, save-reopen-reexport-same |
| `M14d` | pass | schedule-hand-measurement, run-missing-erv1, locate-wrapped-and-hidden, save-reopen-same-identifiers, measurement-50000-edges |
| `M14e` | pass | preflight-empty, export-reload-ventilation, shared-case-equal-identifiers, delete-erv2-null-refuses-locate-undo, save-reopen-reexport-same |
| `T04` | pass | hand-calculation, open-context, counted-twice-undo, outside-zone, locate-nested, measurement |
| `T08` | pass | export-readback, metadata-guard, save-reopen-reexport, outside-zone-disclosed, warnings-preflight-report, blocking-keeps-prior-pair, forced-refusal, required-refusal-withholds, snapshot-measure |
| `M13b` | fail | h1-create-empty-group-active fail; h4-assign-clear-one-undo, h4-paste-shared-refuses-until-unique, hws-delete-retargets-one-undo pass; h2-line-tool-in-group, h3-split-tee-copied-record unknown |
| `M14c` | fail | create-linked-group-active fail; assign-quantity-clear-one-undo, paste-shared-keeps-link-refuses-until-unique, erv-delete-retargets-group-and-zone-one-undo pass; line-tool-in-group unknown |
| `M13c` | unknown | schedule-hand-measurement, branch-unconnected-floor2, locate-into-wrapped-group, save-reopen-same-identifiers, measurement-50000-edges pass; thermal-bridge-repeats unknown (T09 owed) |
| `M08`, `M09`, `M10`, `M11`, `M13e`, `M14f`, `M16`, `T09` | ready for hold | not begun |

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

## Ready for hold

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

- The `groups.create` crash (above): a product defect, for a fix and a test before any line-group host case
  closes.
- Ed's reading of T04 and T08 under WT-23 (labels still say counted twice), and p4-15 decision 3 (section or whole
  file) for M13d and M14e.
- ACCEPTANCE's piping case: 17 Edges as written, 18 on the host.
- The whole-panel snapshot at 50,040 Edges: 31.0 s against 12.1 s in October.

## Restoration

No fault and no provider override. Every approved location this sitting created is revoked: the MS3 export helper
revokes its own, and the four the reused T08 helper approved were revoked at the end. Older approved locations
from earlier sittings are untouched. Four crashes each left SketchUp's BugSplat Problem Report on the next launch,
dismissed with Cancel; nothing was sent. No recovered or autosave file was found. The panel's stored position is
now (768, 245), 1280 x 800, where MS2's notes cite (-1282, 292). SketchUp was quit at the end with no open document.
