# Phase 3a delivery plan: Spaces

DATE: 2026-10-15
STATUS: In progress. Stages P3a-01 to P3a-12 planned and authorized 2026-10-15, one pull request each. Re-baselined on `main` at `87bdc62` on 2026-10-15; the screen stages were restructured the same day after the UI and UX discussion (Zone views: P3a-06 to P3a-08).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#133](https://github.com/bldgtyp/ph-composer/issues/133)

## Outcome and scope

Owner-confirmed addition, 2026-10-12: [D3a-13](DECISIONS.md#confirmed-copy-decision-d3a-13)
requires independent Space children when a Zone is copied. P3a-04 binds it as a
`transition_contributor` on the Zone's independence transition, the contract Windows already
uses on `main`; S04/S12 cover host state/Undo and S10 verifies HBJSON ownership. Window Units
stay instances of their existing Type under the Windows protocol. The decisions still open are
listed in [STATUS](STATUS.md); no stage is authorized.

Re-baseline, 2026-10-15: [DECISIONS](DECISIONS.md), Part 1b, re-reads every finding on
`87bdc62`, and the foundation stages (P3a-01 to P3a-05, P3a-10) are corrected to it. The UI and
UX discussion the same day (DECISIONS, "UI and UX discussion") made Spaces a view of the Zones
tab (D3a-16) with a numeric weighting factor (D3a-17), and restructured the screen stages:
P3a-06 builds the Zone view contract and moves Faces onto it, P3a-07 is the Spaces view
(absorbing the airflow columns and the balance, which now sits on Zone rows), and P3a-08 is
Mark floor and Create Space. The [mockup](mockups/README.md) shows the accepted direction.

On the Phase 2 two-Zone reference model: draw room outlines inside a Zone, make Spaces from them,
set each floor's weighting factor (what counts toward iCFA), set heights and see the volumes in
the viewport, enter supply, extract and transfer airflows, read the balance on each Zone row, and
export. Reload the exact
HBJSON in the pinned honeybee stack and read back each `Space`, its `SpaceVolume`s, floor
segments, factors and airflow overrides.

In this plan: Spaces, roadmap 3.1, as the [PRD](PRD.md) scopes it. Thermal bridges, roadmap 3.2,
is [Phase 3b](../phase-03b-thermal-bridges/PLAN.md).

Out of this plan: METr conversion and import
(D12; every "through PHX" step waits with [metr-export](../../features/unscheduled/metr-export/README.md)),
Zone loads and schedules and their future Zone views, equipment and its assignment views, Space Types, the height drag handle (Q6), a toolbar
(zones-entry-points E1), SketchUp 2023 and Windows host proof, public distribution.

## What Phases 1 and 2 supply

Paths are relative to `src/ph_composer/`. Planning baseline `70c340f`, re-read at `87bdc62` on
2026-10-15.

| Existing | Reused by Spaces as | Still required |
| --- | --- | --- |
| `core/records/` `EntityStore`, `Identity`, `ReferenceTarget` | Storage and identity for the three entity-owned records | Three stores and targets; nothing in the engine |
| Zone record, Zone stamp store, `Zones::Occurrences` | The Zone a Space lives in, the stamp on the Space group, occurrence paths | The nested-container rule (D3a-1); Restore Zone reading Space stamps |
| `shell/` registry, dispatch, API, outcomes, retries, `request.query` | Every Spaces operation | `colour_readout` registration (D3a-5) |
| `shell/` `transition_contributor`, `request.contribute_transition`, `proposal_participant` | Space children following a Zone copy (D3a-13), as `Units::ZoneCopy` does | Nothing in the contract |
| `shell/host_follow_up.rb`; the Zones copy watcher as a worked example | Restorable transparent writes after a native gesture; the Space copy watcher (D3a-14) | Nothing for record writes; lock-state writes are question 9 in CONTRACTS section 7 |
| `core/records/metadata.rb`, the owners' `update_metadata` actions and `extension_status` | One metadata action and status for the three records (F23) | Nothing. Copy the Zones shape |
| `session/` host events, `feature_state`, `CoalescedTimer`, `pending?` and `settle` | The reconciler's triggers and state | The edit-context writer, a keyed queue and the Undo ledger (D3a-4) |
| `core/` Model settings primitive (Phase 2 G4) | The model's last-entered height (Q7) | Nothing. Copy the Windows settings shape |
| `colour_by/` service, overlay, tessellation, mode `group`, occurrence `filter` | Four Spaces modes on Floor Segment faces | Derived geometry and readouts |
| `core/pick.rb`, `core/drag_set.rb`, Classify and Place tools | Mark floor's shape | Nothing shared |
| `export/` contributors, preflight, snapshot, report hook, `registration.cycle`, `user_data` pass-through | One Spaces contributor with a schedule section | The empty-Room refusal (R05 item 1). The cycle check merged through PR #122 |
| Python `Section`, `Requirement`, `Attachment(ROOM)`, coordinator | One Spaces section attaching to the Zone's Room | Nothing in the coordinator |
| Eight pinned wheels, honeybee-ph 1.33.65 among them | `Space`, `SpaceVolume`, `SpaceFloor`, `SpaceFloorSegment` | Confirmation by running. No new wheel expected |
| `html/` table, `inventory_grid`, `record_edits`, `subtabs.js`, unit field, overlay | The Spaces view's table, range edit and paste, the view row | A fourth tree tier (H19) |
| `html/` table-first kit from Zones / Faces: header actions and Colour-by toggles, `column_menu.js`, `selection_bar.js`, `table_contributions.js`, Classify's column paint | The Spaces view's shape, Mark floor's start (D3a-7, D3a-16) | The Zone view contribution (H18), built in P3a-06 |
| `core/units.rb` and `html/unit_tables.js` `volume` and `airflow` | Display of m3, ft3, m3/h, cfm | Nothing. Ruby rows merged through PR #84 |

## Stages

Twelve stages for Spaces. Each has its own document under [phases/](phases) with scope, steps,
source, tests to write first, the host gate and the done condition.

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| [P3a-01](phases/p3a-01-contracts-and-groundwork.md) | Contracts confirmed; the Zones nested-container rule; R05 item 1 (item 2 and the Ruby units are on `main`) | Entry gates, D3a-1 | shared, zones, export | A stamped Group inside a Zone is skipped by the walk, Suggest and Solve; no regression in Zones / Faces or export |
| [P3a-02](phases/p3a-02-space-records-and-operations.md) | The three records, scan, index, metrics, findings and public operations, panel closed | P3a-01, D3a-2 | spaces | Panel-closed script, Undo/Redo, reopen |
| [P3a-03](phases/p3a-03-edit-contexts-protection-and-reconciliation.md) | The edit-context writer, the deferred-work primitive, Volume protection, exit and pre-save protection, the Spaces reconciler, recovery states | P3a-02, D3a-4 | session, spaces | The native-edit matrix in a fresh process |
| [P3a-04](phases/p3a-04-copies-and-move-space-to-zone.md) | `duplicate_identity` and Make independent; the Zone-copy contributor; the Space copy watcher (D3a-14); Move Space to Zone; Restore Zone reading Space stamps | P3a-03, D3a-3 | spaces, zones | Copy and repair; move under a rotated wrapper; one Undo each |
| [P3a-05](phases/p3a-05-colour-by-derived-geometry-and-readouts.md) | Derived geometry and readouts in the Colour-by contract; Window Type operation marks (D3a-5) | P3a-01, D3a-5 | colour_by, windows | A synthetic mode and readout draw; depth, tags and performance |
| [P3a-06](phases/p3a-06-zone-views.md) | The Zone view contract; the Zones tab renamed; Faces moved onto it unchanged; a synthetic Zone-only view | Entry gates, D3a-16 | UI kit, zones panel | Switching views keeps Zone state; Faces unchanged |
| [P3a-07](phases/p3a-07-spaces-view.md) | The Spaces view: rows, columns, editing, airflows, Zone sums and imbalance marker, selection bar, row actions, findings, Colour by weighting factor | P3a-04, P3a-06, D3a-12, D3a-18 | spaces, UI kit | Edit, paste, airflows, navigate contexts from rows |
| [P3a-08](phases/p3a-08-mark-floor-and-create-space.md) | Mark floor from the Weighting factor column menu; Create Space in the native context menu | P3a-03, P3a-07 | spaces | Gestures with Ed at the mouse |
| [P3a-09](phases/p3a-09-space-modes-preview-labels-totals.md) | Four Colour-by modes on Volumes, the volume preview, Space labels, selection totals | P3a-05, P3a-07, P3a-08 | spaces | Prisms, labels and totals in the viewport |
| [P3a-10](phases/p3a-10-spaces-export.md) | The Spaces contributor and Python section, export findings, the report schedule; R05 item 3 | P3a-04, D3a-9, D3a-10, D3a-15 | spaces, export | Normal RBZ exports; exact HBJSON reloads |
| [P3a-11](phases/p3a-11-height-from-solid.md) | Height from solid | P3a-07 | spaces | A wedge sets the height; both numbers reported |
| [P3a-12](phases/p3a-12-spaces-acceptance-and-handoff.md) | Acceptance register closed; packets, context and docs updated | all | integration | Fresh-process integrated run |

```
P3a-01 ─┬─ P3a-02 ── P3a-03 ── P3a-04 ─┬─────────────────── P3a-10 ═ M3 ─┐
        │                              └─ P3a-07 ─┬─ P3a-08 ═ M2 ─┬─ P3a-09 ┼─ P3a-12
        ├─ P3a-06 (own branch) ─────────────┘     └─ P3a-11 ──────┼────────┘
        └─ P3a-05 ────────────────────────────────────────────────┘
                          M1 = after P3a-04
```

## Milestones

- **M1, after P3a-04.** Spaces exist as data and survive the host: a panel-closed script creates,
  edits, copies, repairs and moves Spaces, and the native-edit matrix passes. No screen yet.
- **M2, after P3a-08.** Authoring is complete on screen: the Zone views, the Spaces view with
  its airflows and Zone sums, Mark floor and Create Space. This is the earliest point worth a
  hands-on pass by Ed.
- **M3, after P3a-10.** Spaces on the reference model, exported and read back.

P3a-09, P3a-11 and P3a-12 complete Phase 3a.

## Order and parallel work

The default is one branch at a time in stage order. P3a-05 touches only `colour_by/`, `shell/`
and, under D3a-5, `features/windows/`, so it can run on a second branch from P3a-01. P3a-10 needs
only records and P3a-04's findings, so it can run beside P3a-06 to P3a-08. P3a-06 needs no
Spaces record and touches only the panel, so it can run on its own branch from the entry gates.

Stages that change the same shared file and must not overlap:

| File | Stages |
| --- | --- |
| `features/zones/zone/occurrences.rb`, `export/geometry_snapshot.rb` | P3a-01 (container rule), P3a-04 (stamp reads) |
| `shell/registry.rb`, `shell/declarations.rb`, `shell/registry_validation.rb` | P3a-05 (`colour_readout`) |
| `html/index.html`, `html/features/zones/overview.js` | P3a-06 (the tab, the view contract, Faces moved onto it), P3a-07 (registers Spaces; no Zones file changes) |
| `python/ph_composer_translation/model_sections.py`, `composition.py` | P3a-01 (empty Room), P3a-10 (the section) |
| `extension.rb` | P3a-02 only |

Each stage is one pull request against `main`, with `Refs #133`, the phase issue. A
stage that grows past one coherent review splits along the slices its document names; it does not
merge half a gate.

## Ownership and dependency direction

Spaces is a layer 3 feature (D2-1): things placed on geometry.

- `ph_composer.spaces` requires `ph_composer.zones` and nothing else. It owns the three records,
  the reconciler, the Mark floor tool, the Spaces tab, the modes and readouts, and the export
  contributor and section. No file under `features/zones/`, `features/assemblies/` or
  `features/windows/` names Spaces. A dependency-direction test holds that line from P3a-02.
- Zones owns the nested-container rule and the Zone stamp. It learns that a stamped Group inside
  a Zone is a container; it never learns what the container is.
- `session/` owns the edit-context writer and the deferred-work primitive. `colour_by/` owns
  derived geometry and readouts. Both name no feature.
- Export orchestration, `shell/` and the UI kit name no feature. The Zones tab hosts views and
  names none of them (D3a-16). Balance by ventilator belongs with the equipment packet's
  Ventilation assignments (D3a-8).

## Verification profile and review

Use high assurance for record persistence, the native lifecycle (P3a-03), the re-instance in Move
Space to Zone (P3a-04) and the translation (P3a-10). During a stage run focused tests. At its gate
run `make ci` on both offline Rubies (2.7.2 and 3.2.2), refresh the vendor manifest when shipped
Python or panel assets changed (`uv run tools/runtime/vendor.py --refresh-manifest`), regenerate
fixtures only through their owning tests (`make fixtures`), and run the stage's host gate from a
fresh process with the installed build.

Review ladder, one review per coherent diff, given the architecture rubric. An ordinary stage
gets one diff-focused review. P3a-01, P3a-03, P3a-04, P3a-05, P3a-06 and P3a-10 change public
contracts, native lifecycle or serialization and get the stronger independent pass instead; P3a-06's
is the contributor contract for every later Zone view. P3a-06 to P3a-09 and P3a-11 apply the UI
polish skill in the same review.

Add each stage's native cases to [`native-acceptance/cases.json`](../../native-acceptance/cases.json)
when the stage is implemented, with dependency patterns for the files it adds, and record
observed results in the ledger. Before a stage's gate run
`uv run tools/hostkit/acceptance_ledger.py status --changed <paths>` for the shared files it
changed and repeat the earlier cases that screen reports. P3a-01 and P3a-05 change files that
Phase 1 and Phase 2 cases depend on.

## Shared with Phase 3b

Phase 3b (thermal bridges) runs on its own track. It waits for P3a-01 (P3b-03, P3b-08) and P3a-05
(P3b-06). These files are changed by both tracks and must not be changed by two open branches at
once:

| File | Phase 3a | Phase 3b |
| --- | --- | --- |
| `extension.rb` | P3a-02 | P3b-02 |
| `Makefile` (`PLANNING_IDS`) | P3a-01, if it extends the pattern | P3b-01 |
| `features/zones/zone/occurrences.rb` and the Zones declarations | P3a-01, P3a-04 | P3b-03 |
| `colour_by/overlay.rb`, `shell/registry.rb`, `shell/declarations.rb` | P3a-05 | P3b-06 |
| `html/index.html` | P3a-06 | P3b-05 |
| `export/geometry_snapshot.rb` | P3a-01, P3a-04 | P3b-08 |
| `python/ph_composer_translation/composition.py`, `assembly.py` | P3a-01, P3a-10 | P3b-08 |

## Exit

Every active row of [ACCEPTANCE.md](ACCEPTANCE.md) passes on the proving host, the
Spaces packet records what was delivered and what remains, durable rules are in `context/`, and
`docs/PRODUCT.md` and the generated API reference describe what exists.

Phase 3 closes when this plan and [Phase 3b](../phase-03b-thermal-bridges/PLAN.md) have both
exited. Nothing here is a release,
a SketchUp 2023 or Windows claim, or a certification claim.
