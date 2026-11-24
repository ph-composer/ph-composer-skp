# Phase 4 delivery plan: mechanical

DATE: 2026-10-21
STATUS: Scoped. Stages P4-01 to P4-15 planned from the equipment shared-shape, Ventilators and hot water interviews of 2026-10-21; families 3 to 7, piping and ducting are gate stubs until their interviews; D4-01 to D4-12 answered as recommended the same day. Reviewed 2026-11-22 after Phase 6 Programs: the Phase 3b gates are met, the supply table is re-read at `8c710412`, stage P4-08b is added, and D4-21 to D4-27 are answered as recommended and bound. Ed authorized every stage on 2026-11-23 (STATUS, "Entry gates").
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Outcome and scope

On the Phase 2 two-Zone reference model with Spaces and airflows: author two Ventilators and one
Hot Water System with tanks and heaters, say which Zones each serves, read the balance by
ventilator on the Ventilator's row, and export. Reload the exact HBJSON in the pinned honeybee
stack and read back each Room's `properties.ph_hvac`: one `PhVentilationSystem` holding its
`Ventilator`, one `PhHotWaterSystem` with its tanks in their slots and its heaters, with the same
identifiers on every Room an item serves. That closes the HBJSON half of the predecessor's B4
proof (two Zones, two ventilators, distinct) that the roadmap's 4.1 names.

In this plan: roadmap 4.1 to 4.6, six equipment families (the seventh, appliances, went to Phase 6
as Equipment Sets), planned in detail for the shared shape and families 1 and 2 (interviewed
2026-10-21, the [equipment PRD](equipment/PRD.md) is the record) and as gate stubs for families 3
to 6; roadmap 4.2 and 4.4, ERV ducting and hot water piping, as gate stubs until their own
interviews run (Phase 3b's edge stages, which they reuse, merged on 2026-10-26); and the Building
Segment's mechanical settings that Phase 6 handed over (P4-08b).
The findings, decisions, bindings and register are this folder's [DECISIONS](DECISIONS.md),
[CONTRACTS](CONTRACTS.md) and [ACCEPTANCE](ACCEPTANCE.md).

Out of this plan: METr conversion and import ([metr-export](../unscheduled/metr-export/README.md)
owns every METr row; what PHX builds from this phase's HBJSON, such as one device or three for a
shared item, is proved here by round trip since D4-25), the
simplified hot water methods until [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135)
lands (hot water H5), boilers, district heat and PV (Q7), equipment library kinds (Q8, roadmap 5.4),
the Zone loads packet's occupancy and lighting (Q12, now [Phase 4a Programs](../../archive/phase-06-program/README.md)), equipment geometry (Q5), sizing, schedules,
SketchUp 2023 and Windows host proof, public distribution.

## What earlier phases supply

Paths are relative to `src/ph_composer/`. Planning baseline `main` at `420c783a`, read 2026-10-21.
Re-read on 2026-11-22 at `8c710412`, after Phase 3b, Climate, Shading and Programs:
[DECISIONS, Part 4](DECISIONS.md#part-4-review-after-programs-2026-11-22) holds what changed, and
the rows below are corrected to it.

| Existing | Reused by Phase 4 as | Still required |
| --- | --- | --- |
| `core/records/` `RecordKind`, `Catalog`, `DictionaryStore`, `EntityStore`, `ReferenceTarget`, `Fields.common`; `request.retarget_references` and `propose_delete` (Assemblies' delete with replacement) | The Ventilator and Hot Water System kinds; delete in use. Serves needs no store or target of its own (D4-21) | Nothing in the engine, unless P4-01's test of a `many` reference in a payload finds a gap |
| Zones' proposal participant `ph_composer.zones.stage_extension` (`features/zones/extension_staging.rb`), `ph_composer.zones.all` rows (`zone_id`, `zone_path`, `building_segment`, `level`), and the Zone record itself, which a native copy carries whole | Writing a Serves payload with Zones' refusals; listing Zones to serve; what a copied Zone keeps (D4-21) | Nothing in Zones |
| Spaces' `ph_composer.spaces.all` Zone rows: `airflow_mode` (`by_program` or `detailed`), supply, extract and transfer sums for a detailed Zone, null while By Program, `imbalanced` at 10 percent of the larger (F24) | The balance by ventilator on the Ventilator's row (Q11, V6) | Nothing in Spaces |
| Programs' per-Zone assignment: a structured extension on the Zone record, staged through `ph_composer.zones.stage_extension`, exported by an `entity_projections` claim (F26). `ph_composer.programs.zones` rows give each Zone's ventilation in m³/h with its source | The pattern Serves follows (D4-21): a `ph_composer.mechanical.zone_serves` payload staged through Zones. The flow the balance counts for a By Program Zone (D4-24) | Nothing in Zones or Programs. P4-01 proves a `many` reference in a payload, which Programs does not ship; the feature requires `ph_composer.programs` from P4-05 |
| Building Segment settings: `segmentSettingsSection`, a namespace on the Segment record, an `entity_projections` claim and the `SEGMENT` attachment host (`context/EXTENSIBILITY.md`, "Building Segment settings") | Mechanical cooling, the mechanical room temperature and summer ventilation (P4-08b, F30) | Nothing in Zones |
| Climate's reads `ph_composer.climate.climate.get` and `ph_composer.climate.design_temperatures.get` | The blended heat pump's monthly means and design temperatures (D4-15, F20) | The feature requires `ph_composer.climate` from P4-08 |
| `colour_by/` modes with `entity_kind: "zone"` (`features/zones/colour_modes.rb`) | `By ventilator` and `By hot water system` | Nothing |
| `export/` contributors, preflight, `Export::Privacy`; Python `Section`, `Attachment` at `MODEL`, `SEGMENT`, `ROOM` or `FACE` (F29), `result_fields`, `conformance`; the left-out Zone rule (F28); Programs' one pure export plan read by the preflight (F35) | One contributor and one Room-attaching section per family | `honeybee_phhvac` in `stack.PACKAGES` (CONTRACTS, A1); one object per (item, Zone) pair (D4-01) |
| The pinned wheel `honeybee_ph-1.33.68` ships `honeybee_phhvac` and `honeybee_energy_ph`; PHX 1.59.4 is the optional `phx` test group, not shipped (F23) | Every mechanical class the sections build; a PHX round trip per export stage (D4-25) | Nothing in the vendor manifest |
| `html/` inventory, in-place drafts, `subtabs.js`, `record_form.js`, `unit_field.js`, column menus, `table_contributions.js`; the reserved disabled Systems button in `html/index.html`, last in the shipped row (F32) | The Mechanical tab, its system subtabs and tables (D4-13) | The pane; the button becomes live and moves to sit after Thermal Bridges (CONTRACTS, A2; D4-27) |
| Ruby and panel units `airflow`, `volume`, `heat_loss_rate`, `length`, `temperature`, `power` (F31) | Airflow sums, W/K standby losses, temperatures | Electric efficiency Wh/m³ to W/cfm (V4) and litres to US gallons (CONTRACTS, A3; units Q3) |
| The registry's agent-facing keywords, `API::CHANGES`, `docs/AGENT_GUIDE.md`, bounded `list` reads | Every operation this packet registers | One API minor bump and one guide recipe per stage that adds a name |
| Phase 3b's edge stages P3b-03, P3b-04, P3b-06, P3b-07 and P3b-08, merged 2026-10-26 (F21); the snapshot's `edge` entries (G-02) | Piping and ducting | The piping and ducting interviews; the run builder's move to `core/` (P4-13) |

## Stages

Sixteen stages, one of them superseded. P4-01 to P4-07 and P4-15 have full documents under [phases/](phases) with scope,
steps, source, tests to write first, the host gate and the done condition; P4-08, P4-08b and P4-09 were
written in full before their runs (2026-11-23, 2026-11-24). P4-10 to P4-14 are gate stubs: entry gates, what the stage owns and reuses, and the interview that precedes its planning.

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| [P4-01](phases/p4-01-equipment-contracts-and-seams.md) | CONTRACTS confirmed by test; `honeybee_phhvac` through the stack seam in Pyodide; citation lint for `P4-`, `M` ids, the lettered `P4-08b` included; the architecture review | Ed's go | shared | `honeybee_phhvac` imports in the installed runtime |
| [P4-02](phases/p4-02-equipment-feature-and-ventilator-kind.md) | The feature; the Ventilator kind, operations and reads, panel closed | P4-01 | mechanical | Panel-closed script, Undo/Redo, reopen |
| [P4-03](phases/p4-03-serves-assignment.md) | The Serves payload on the Zone record, staged through Zones (D4-21): assign and clear, one per Zone, delete with replacement, the unserved-Zone finding | P4-02 | mechanical, (zones: none) | Assign in nested and copied Zones, Undo/Redo, reopen |
| [P4-04](phases/p4-04-ventilator-export.md) | The contributor, preflight, Python section, conformance, a PHX round trip; the B4 HBJSON proof | P4-03 | export, mechanical | Normal RBZ exports; exact HBJSON reloads with both Rooms' systems |
| [P4-05](phases/p4-05-systems-tab-and-ventilators-view.md) | The Mechanical tab (after Thermal Bridges), system subtabs, shared pill row, Ventilators table with Serves and balance, `By ventilator`, W/cfm | P4-04 | mechanical, UI, colour_by, units | Batched in MS2 |
| [P4-06](phases/p4-06-hot-water-records-and-export.md) | Flat Hot Water System, Heater and Tank kinds, operations, pure slotting, export section and PHX round trip | P4-03 | mechanical, export | Batched in MS2 |
| [P4-07](phases/p4-07-hot-water-view.md) | The Hot Water subtab (`Systems`, `Heaters`, `Tanks` pills), `By hot water system`, litres (`volume_l`) | P4-05, P4-06 | mechanical, UI | MS2 sitting (M05–M07) |
| [P4-08](phases/p4-08-heat-pumps.md) | Family 3: four flat Heat Pump kinds, pure Ruby per-Segment blend, five-pill subtab with `Blended result`, export section and PHX round trip | P4-07 | mechanical, export, UI | Batched in MS3 |
| [P4-08b](phases/p4-08b-segment-mechanical-settings.md) | Mechanical cooling, the mechanical room temperature and summer ventilation as a Building Segment settings section with its `SEGMENT` export (Phase 6 handoff, F30) | P4-02, P4-08; the summer ventilation interview (D4-32) | mechanical, export | Save in one Undo step with the other sections; PHX reads the values on each Variant (MS3) |
| [P4-09](phases/p4-09-electric-heaters.md) | Family 4: the Electric Heater kind, the `heater_ids` list slot, the `PhHeatingDirectElectric` export with its PHX round trip, the Electric Heating subtab | P4-07; its interview (D4-33) | mechanical, export, UI | Batched in MS3 |
| [P4-10](phases/p4-10-pumps.md) | Family 5 | P4-07; its interview | mechanical | Stub |
| [P4-11](phases/p4-11-fans.md) | Family 6: exhaust ventilator plus linked supportive device (Q6) | P4-10; its interview | mechanical | Stub |
| [P4-12](phases/p4-12-appliances.md) | Family 7 as Process loads with the Phius default set (Q12) | Superseded: [Phase 4a](../../archive/phase-06-program/README.md) owns appliances (Q4a-03) | mechanical | Superseded |
| [P4-13](phases/p4-13-hot-water-piping.md) | Roadmap 4.4, planned in detail after its interview | P4-06; the piping interview (Phase 3b's edge stages are merged) | piping | Stub |
| [P4-14](phases/p4-14-erv-ducting.md) | Roadmap 4.2, planned in detail after its interview | P4-04; P4-13's draw and assign; the ducting interview | ducting | Stub |
| [P4-15](phases/p4-15-acceptance-and-handoff.md) | Register closed; context, docs, the metr-export handoff; Phase 4 close is the MVP (D1) | all stages above | integration | Fresh-process integrated run |

```
P4-01 ── P4-02 ── P4-03 ─┬─ P4-04 ═ MS1 ── P4-05 ─┐
                         └─ P4-06 ────────────────┴─ P4-07 ═ MS2 ─┬─ P4-08 ── P4-08b ─┐
                                                                  ├─ P4-09 … P4-11 ───┤
                                                                  └─ P4-13 ── P4-14 ──┴─ P4-15 ═ MS3
```

## Milestones

- **MS1, after P4-04.** Ventilators complete as data and exported: the B4 HBJSON proof on the
  reference model, panel closed.
- **MS2, after P4-07.** Families 1 and 2 on screen. The two drawn packets have what they export
  into, and may be planned in detail once their interviews have run.
- **MS3, after P4-14.** Everything a METr model needs before its first run is authored and in
  HBJSON. P4-15 closes the phase, which is the MVP Ed set in D1.

## Order and parallel work

The default is one branch at a time in stage order. Phase 3b, which was being implemented beside
this packet when it was planned and owned several of these files, closed on 2026-10-26, and no
other phase is in progress on 2026-11-22. The rule that remains is between this phase's own
parallel stages and any later packet: no two open branches touch one of these files at once, and
whichever lands second rebases.

| File | Phase 4 stage |
| --- | --- |
| `extension.rb` (`FEATURES`, order `[Assemblies, Zones, Windows, Spaces, ThermalBridges, Shading, Climate, Certification, Programs, Mechanical]`) | P4-02 |
| `Makefile` (`PLANNING_IDS`) | P4-01 |
| `python/ph_composer_translation/stack.py`, `tests/python/test_imports.py` | P4-01 |
| `html/index.html` (the reserved button) and the generated script list | P4-05 |
| `shell/api.rb` (`API::MINOR`, `API::CHANGES`), `docs/AGENT_GUIDE.md` | every stage that adds an operation |
| `python/ph_composer_translation/composition.py` | P4-04, P4-06, every later export stage |
| `core/units.rb`, `html/unit_tables.js` | P4-05, P4-07 |
| `tools/runtime/vendor.py` footprint keys | P4-01 (measured), P4-15 |

Within this track, P4-06 can proceed beside P4-04 and P4-05 after P4-03, since it shares only
`composition.py` with P4-04 (serialise those two). Families 3 to 6 are independent of one another
after P4-07 and may run in any order their interviews allow. P4-13 and P4-14 wait on their
interviews.

Each stage is one pull request against `main`, with `Refs` the Phase 4 issue once it exists. A
stage that grows past one coherent review splits along the slices its document names; it does not
merge half a gate.

## Ownership and dependency direction

`ph_composer.mechanical` is one feature (D4-02, named by D4-22) with a layer 1 part, the family
kinds under `features/mechanical/<family>/`, and a layer 3 part, the Serves payload and its reads
under `features/mechanical/serves/`, which requires `ph_composer.zones`, `ph_composer.spaces`
(D4-10) and, for the balance of a By Program Zone, `ph_composer.programs` (D4-24). Serves is a
structured extension on the Zone record that Zones stages (D4-21), so no mechanical code writes a
Zone. Every value the export derives, the tank slots and the blended heat pump
among them, is worked out in pure Ruby and carried to Python as a value (F35).
A test holds the line from P4-02: nothing under a family folder names Zones, Spaces, Programs,
the Zone record or `serves/`. No other feature's folder names this one. Zones gains nothing: its
`stage_extension` participant and `zones.all` already answer what Serves needs. Spaces and
Programs gain no read. Piping and ducting are later features that require this one and read its
published sections (D4-09); it never names them. `core/units.rb`, `export/`, `html/` kit files and the Python
assembly gain additions that name no feature.

## Verification profile and review

Use high assurance for the Serves payload, its references and its staging (P4-03), the first mechanical translation
section and its attachment shape (P4-04), and the Hot Water System section's slotting (P4-06).
During a stage run focused tests. At its gate run `make ci` on both offline Rubies (2.7.2 and
3.2.2), refresh the vendor manifest when shipped Python or panel assets changed
(`uv run tools/runtime/vendor.py --refresh-manifest`), regenerate the panel script list
(`make panel-manifest`) and fixtures only through their owning tests (`make fixtures`), and run
the stage's host gate from a fresh process with the installed build. Each export stage adds a
PHX round trip, `tests/python/test_<section>_phx_round_trip.py`, run with `uv run --group phx
pytest tests/python` and skipped without the group, as Programs' are (D4-25). The installed size is the
gate to watch: Phase 6 closed 1,171,308 bytes under the 28,000,000 byte ceiling, so P4-01 measures
it at entry and each stage that ships Python or panel assets reads `vendor.py --check` (F37). On the host, wait with
`host_bridge.py wait-for`, read with `host_bridge.py diagnostics`, reproduce a failure with
`host_bridge.py fault` whose `restore` reports `restored: true`, and record each case with
`acceptance_case.py begin` and `finish` so the ledger row is a Pass and not an observation
(`tools/hostkit/.index.md`).

Review ladder, one review per coherent diff, given the architecture rubric. P4-03, P4-04 and
P4-06 change a payload on another feature's record, the shared translation or a slotting rule, and
get the stronger independent pass. P4-01 gets the architecture review on its confirmed bindings.
P4-05 and P4-07 apply the UI polish skill in their review. The rest get one diff-focused review.

Ed decided on 2026-11-23 (D4-31) to batch SketchUp host gates by milestone (`MS1` after P4-04, `MS2` after P4-07, `MS3` after P4-14/P4-15), while running full offline `make ci` (both Rubies, browser checks) and PHX round trips on every stage PR.

Add each stage's native cases to [`native-acceptance/cases.json`](../../native-acceptance/cases.json)
when the stage is implemented, with dependency patterns for the files it adds, and record observed
results in the ledger. Before a stage's gate run
`uv run tools/hostkit/acceptance_ledger.py status --changed <paths>` for the shared files it
changed and repeat the earlier cases that screen reports.

## Exit

Every row of [ACCEPTANCE.md](ACCEPTANCE.md) passes on the proving host, this packet records what
was delivered and what remains, each METr row is in metr-export with its owner named, and
`docs/PRODUCT.md` and the generated API reference describe what exists. Phase 4 closing is the
complete MVP Ed described in D1. Nothing here is a release, a SketchUp 2023 or Windows claim, or a
certification claim.
