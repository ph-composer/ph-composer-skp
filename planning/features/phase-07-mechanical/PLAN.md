# Phase 4 delivery plan: mechanical

DATE: 2026-10-21
STATUS: Scoped. Stages P4-01 to P4-15 planned from the equipment shared-shape, Ventilators and hot water interviews of 2026-10-21; families 3 to 7, piping and ducting are gate stubs until their interviews; D4-01 to D4-12 answered as recommended the same day; none authorized.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Outcome and scope

On the Phase 2 two-Zone reference model with Spaces and airflows: author two Ventilators and one
Hot Water System with tanks and heaters, say which Zones each serves, read the balance by
ventilator on the Ventilator's row, and export. Reload the exact HBJSON in the pinned honeybee
stack and read back each Room's `properties.ph_hvac`: one `PhVentilationSystem` holding its
`Ventilator`, one `PhHotWaterSystem` with its tanks in their slots and its heaters, with the same
identifiers on every Room an item serves. That closes the HBJSON half of the predecessor's B4
proof (two Zones, two ventilators, distinct) that the roadmap's 4.1 names.

In this plan: roadmap 4.1 to 4.6, the seven equipment families, planned in detail for the shared
shape and families 1 and 2 (interviewed 2026-10-21, the [equipment PRD](equipment/PRD.md) is the
record) and as gate stubs for families 3 to 7; and roadmap 4.2 and 4.4, ERV ducting and hot water
piping, as gate stubs until Phase 3b lands the edge stages they reuse and their own interviews run.
The findings, decisions, bindings and register are this folder's [DECISIONS](DECISIONS.md),
[CONTRACTS](CONTRACTS.md) and [ACCEPTANCE](ACCEPTANCE.md).

Out of this plan: METr conversion and import ([metr-export](../unscheduled/metr-export/README.md)
owns every METr row, including whether PHX writes one device or three for a shared item), the
simplified hot water methods until [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135)
lands (hot water H5), boilers, district heat and PV (Q7), equipment library kinds (Q8, roadmap 5.4),
the Zone loads packet's occupancy and lighting (Q12, now [Phase 4a Programs](../phase-06-program/README.md)), equipment geometry (Q5), sizing, schedules,
SketchUp 2023 and Windows host proof, public distribution.

## What earlier phases supply

Paths are relative to `src/ph_composer/`. Planning baseline `main` at `420c783a`, read 2026-10-21.

| Existing | Reused by Phase 4 as | Still required |
| --- | --- | --- |
| `core/records/` `RecordKind`, `Catalog`, `DictionaryStore`, `EntityStore`, `ReferenceTarget`, `Fields.common`; `request.retarget_references` and `propose_delete` (Assemblies' delete with replacement) | The Ventilator and Hot Water System kinds; the Serves record on the Zone Group; delete in use | Nothing in the engine |
| Zones' Zone reference target with `locate:` (`features/zones/declarations/zone.rb`), `ph_composer.zones.all` rows (`zone_id`, `zone_path`, `building_segment`, `level`), the `occurrence_independent` transition and `transition_contributor` (Windows `units/zone_copy.rb`, Spaces `zone_copy.rb`, `tests/support/zone_child_fixture.rb`) | Resolving the Zone Group a Serves record sits on; listing Zones to serve; what a copied Zone keeps | Nothing in Zones; P4-01 confirms a second feature's dictionary on the Zone Group by test |
| Spaces' `ph_composer.spaces.all` Zone rows: supply, extract and transfer sums over user-specified Spaces, null while any inherits, `imbalanced` at 10 percent of the larger | The balance by ventilator on the Ventilator's row (Q11, V6) | Nothing in Spaces |
| `colour_by/` modes with `entity_kind: "zone"` (`features/zones/colour_modes.rb`) | `By ventilator` and `By hot water system` | Nothing |
| `export/` contributors, preflight, `Export::Privacy`; Python `Section`, `Attachment(ROOM)` with Spaces as its first user (`space_sections.py`), `result_fields`, `conformance` | One contributor and one Room-attaching section per family | `honeybee_phhvac` in `stack.PACKAGES` (CONTRACTS, A1); one object per (item, Zone) pair (D4-01) |
| The pinned wheel `honeybee_ph-1.33.65` ships `honeybee_phhvac` and `honeybee_energy_ph` | Every mechanical class the sections build | Nothing in the vendor manifest |
| `html/` inventory, in-place drafts, `subtabs.js`, `record_form.js`, `unit_field.js`, column menus, `table_contributions.js`; the reserved disabled Systems button in `html/index.html` | The Systems tab, the Equipment subtab and the family views | The pane; the button becomes live (CONTRACTS, A2) |
| Ruby units `airflow`, `volume`, `heat_loss_rate`, `length`; panel: 18 quantities | Airflow sums, W/K standby losses | Electric efficiency Wh/m³ to W/cfm (V4), litres to US gallons, temperature where absent (CONTRACTS, A3; units Q3) |
| The registry's agent-facing keywords, `API::CHANGES`, `docs/AGENT_GUIDE.md`, bounded `list` reads | Every operation this packet registers | One API minor bump and one guide recipe per stage that adds a name |
| Phase 3b's edge stages P3b-03, P3b-04, P3b-06, P3b-07 and P3b-08, scoped and not authorized; the snapshot's `edge` entries (G-02) exist | Piping and ducting | Those stages merged, then the piping and ducting interviews |

## Stages

Fifteen stages. P4-01 to P4-07 and P4-15 have full documents under [phases/](phases) with scope,
steps, source, tests to write first, the host gate and the done condition. P4-08 to P4-14 are gate
stubs: entry gates, what the stage owns and reuses, and the interview that precedes its planning.

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| [P4-01](phases/p4-01-equipment-contracts-and-seams.md) | CONTRACTS confirmed by test; `honeybee_phhvac` through the stack seam in Pyodide; citation lint for `P4-`, `M` ids; the architecture review | Ed's go; P3b-01 merged (the shared lint line) | shared | `honeybee_phhvac` imports in the installed runtime |
| [P4-02](phases/p4-02-equipment-feature-and-ventilator-kind.md) | The feature; the Ventilator kind, operations and reads, panel closed | P4-01 | equipment | Panel-closed script, Undo/Redo, reopen |
| [P4-03](phases/p4-03-serves-assignment.md) | The Serves record on the Zone Group, its target, assign and clear, one per Zone, delete with replacement, the Zone-copy contributor, the unserved-Zone finding | P4-02 | equipment, (zones: none) | Assign in nested and copied Zones, Undo/Redo, reopen |
| [P4-04](phases/p4-04-ventilator-export.md) | The contributor, preflight, Python section, conformance; the B4 HBJSON proof | P4-03 | export, equipment | Normal RBZ exports; exact HBJSON reloads with both Rooms' systems |
| [P4-05](phases/p4-05-systems-tab-and-ventilators-view.md) | The Systems tab, the Equipment subtab, the family selector, the Ventilators table with Serves and balance, `By ventilator`, the W/cfm quantity | P4-04 | equipment, UI, colour_by, units | Panel gestures with Ed |
| [P4-06](phases/p4-06-hot-water-records-and-export.md) | The Hot Water System kind with tank and heater children, operations, the system values, its section with tank slotting | P4-03 | equipment, export | Panel-closed script; exact HBJSON reloads with slots and heaters |
| [P4-07](phases/p4-07-hot-water-view.md) | The Hot water family view: system rows, tank and heater child rows, `By hot water system`, litres | P4-05, P4-06 | equipment, UI | Panel gestures with Ed |
| [P4-08](phases/p4-08-heat-pumps.md) | Family 3: records, section, view | P4-07; the heat pumps interview | equipment | Stub |
| [P4-09](phases/p4-09-electric-heaters.md) | Family 4 | P4-07; its interview | equipment | Stub |
| [P4-10](phases/p4-10-pumps.md) | Family 5 | P4-07; its interview | equipment | Stub |
| [P4-11](phases/p4-11-fans.md) | Family 6: exhaust ventilator plus linked supportive device (Q6) | P4-10; its interview | equipment | Stub |
| [P4-12](phases/p4-12-appliances.md) | Family 7 as Process loads with the Phius default set (Q12) | Superseded: [Phase 4a](../phase-06-program/README.md) owns appliances (Q4a-03) | equipment | Superseded |
| [P4-13](phases/p4-13-hot-water-piping.md) | Roadmap 4.4, planned in detail after its interview | P4-06; P3b-03, P3b-04, P3b-06, P3b-07, P3b-08 merged; the piping interview | piping | Stub |
| [P4-14](phases/p4-14-erv-ducting.md) | Roadmap 4.2, planned in detail after its interview | P4-04; P4-13's draw and assign; P3b-03, P3b-06, P3b-07, P3b-08 merged; the ducting interview | ducting | Stub |
| [P4-15](phases/p4-15-acceptance-and-handoff.md) | Register closed; context, docs, the metr-export handoff; Phase 4 close is the MVP (D1) | all stages above | integration | Fresh-process integrated run |

```
P4-01 ── P4-02 ── P4-03 ─┬─ P4-04 ═ MS1 ── P4-05 ─┐
                         └─ P4-06 ────────────────┴─ P4-07 ═ MS2 ─┬─ P4-08 … P4-12 ─┐
                                                                  ├─ P4-13 ── P4-14 ─┼─ P4-15 ═ MS3
                                            (P3b-03 … P3b-08) ────┘                  │
```

## Milestones

- **MS1, after P4-04.** Ventilators complete as data and exported: the B4 HBJSON proof on the
  reference model, panel closed.
- **MS2, after P4-07.** Families 1 and 2 on screen. The two drawn packets have what they export
  into, and may be planned in detail once Phase 3b's edge stages have merged.
- **MS3, after P4-14.** Everything a METr model needs before its first run is authored and in
  HBJSON. P4-15 closes the phase, which is the MVP Ed set in D1.

## Order and parallel work

The default is one branch at a time in stage order. Phase 3b is being implemented beside this
packet from 2026-10-21 (its P3b-01 is in progress on `feature/thermal-bridges-p3b-01`), and it is
the current owner of several shared files. The rule is coordination, not ordering: no two open
branches touch one of these files at once, whichever lands second rebases, and the `FEATURES`
order in each packet's CONTRACTS is corrected on landing. The one true ordering gate is the
`Makefile` line both packets' first stages edit: P3b-01's lands before P4-01's.

| File | Phase 4 stage | Other current owner |
| --- | --- | --- |
| `extension.rb` (`FEATURES`, order `[Assemblies, Zones, Windows, Spaces, ThermalBridges, Equipment]`) | P4-02 | P3b-02 |
| `Makefile` (`PLANNING_IDS`) | P4-01 | P3b-01 |
| `python/ph_composer_translation/stack.py`, `tests/python/test_imports.py` | P4-01 | none |
| `html/index.html` (the two reserved buttons) and the generated script list | P4-05 | P3b-05 |
| `shell/api.rb` (`API::MINOR`, `API::CHANGES`), `docs/AGENT_GUIDE.md` | every stage that adds an operation | every 3b stage that does |
| `python/ph_composer_translation/composition.py`, `assembly.py` | P4-04 | P3b-08 (H18) |
| `core/units.rb`, `html/unit_tables.js` | P4-05, P4-07 | none |
| `tools/runtime/vendor.py` footprint keys | P4-15 | P3b-09 |

Within this track, P4-06 can proceed beside P4-04 and P4-05 after P4-03, since it shares only
`composition.py` with P4-04 (serialise those two). Families 3 to 7 are independent of one another
after P4-07 and may run in any order their interviews allow. P4-13 and P4-14 wait on Phase 3b.

Each stage is one pull request against `main`, with `Refs` the Phase 4 issue once it exists. A
stage that grows past one coherent review splits along the slices its document names; it does not
merge half a gate.

## Ownership and dependency direction

`ph_composer.equipment` is one feature (D4-02) with a layer 1 part, the family kinds under
`features/equipment/<family>/`, and a layer 3 part, the Serves record and its reads under
`features/equipment/serves/`, which requires `ph_composer.zones` and `ph_composer.spaces` (D4-10).
A test holds the line from P4-02: nothing under a family folder names Zones, Spaces, the Zone
Group or `serves/`. Nothing under `features/zones/`, `features/spaces/`, `features/windows/`,
`features/assemblies/` or `features/thermal_bridges/` names equipment. Zones gains no read: the
Zone target's `locate:` and `zones.all` already answer what Serves needs. Spaces gains no read.
Piping and ducting are later features that require equipment and read its published sections
(D4-09); equipment never names them. `core/units.rb`, `export/`, `html/` kit files and the Python
assembly gain additions that name no feature.

## Verification profile and review

Use high assurance for the Serves record and target (P4-03), the first mechanical translation
section and its attachment shape (P4-04), and the Hot Water System section's slotting (P4-06).
During a stage run focused tests. At its gate run `make ci` on both offline Rubies (2.7.2 and
3.2.2), refresh the vendor manifest when shipped Python or panel assets changed
(`uv run tools/runtime/vendor.py --refresh-manifest`), regenerate the panel script list
(`make panel-manifest`) and fixtures only through their owning tests (`make fixtures`), and run
the stage's host gate from a fresh process with the installed build. On the host, wait with
`host_bridge.py wait-for`, read with `host_bridge.py diagnostics`, reproduce a failure with
`host_bridge.py fault` whose `restore` reports `restored: true`, and record each case with
`acceptance_case.py begin` and `finish` so the ledger row is a Pass and not an observation
(`tools/hostkit/.index.md`).

Review ladder, one review per coherent diff, given the architecture rubric. P4-03, P4-04 and
P4-06 change a record on another feature's entity, the shared translation or a slotting rule, and
get the stronger independent pass. P4-01 gets the architecture review on its confirmed bindings.
P4-05 and P4-07 apply the UI polish skill in their review. The rest get one diff-focused review.

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
