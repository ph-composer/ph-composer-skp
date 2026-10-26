# Phase 3b delivery plan: thermal bridges

DATE: 2026-10-03
STATUS: In progress. Stages P3b-01 to P3b-09 planned; interview complete 2026-10-03; re-baselined on `main` at `420c783a` on 2026-10-21, D3b-22 and D3b-23 answered the same day; P3b-01 merged 2026-10-22; P3b-02 to P3b-09 authorized 2026-10-25.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Outcome and scope

On the Phase 2 two-Zone reference model: build Thermal Bridge Types, select edges and assign them,
read runs, lengths and psi times length in a schedule, see the assigned edges in the viewport, and
export. Reload the exact HBJSON in the pinned honeybee stack and read back each run as a
honeybee-ph `PhThermalBridge` on its Building-Segment.

Re-baseline, 2026-10-21: [DECISIONS](DECISIONS.md), Part 1b, re-reads every finding on
`420c783a` (385 commits after the plan was drafted: Phase 3a, agent access 3a1, G-02, production
support and developer observability), and every stage below is corrected to it. Two decisions were
added, D3b-22 and D3b-23, and answered as recommended the same day; nothing else changed hands.

In this plan: thermal bridges, roadmap 3.2, as the [PRD](PRD.md) scopes it after the interview
of 2026-10-03. The findings, decisions, bindings and register are this folder's
[DECISIONS](DECISIONS.md), [CONTRACTS](CONTRACTS.md) and [ACCEPTANCE](ACCEPTANCE.md). Spaces,
roadmap 3.1, is [Phase 3a](../../archive/phase-03a-spaces/PLAN.md).

Out of this plan: METr conversion and import (D12; the METr rows and PHX's handling of `quantity`
wait with [metr-export](../unscheduled/metr-export/README.md)), point thermal bridges and
chi-values (D3), psi-value calculation, fRsi, automatic junction detection, a library kind for
Thermal Bridge Types (roadmap 5.4), a toolbar, SketchUp 2023 and Windows host proof, public
distribution.

## What earlier phases supply

Paths are relative to `src/ph_composer/`. Planning baseline `08c4807`, re-read at `420c783a` on
2026-10-21.

| Existing | Reused by thermal bridges as | Still required |
| --- | --- | --- |
| `core/records/` `RecordKind`, `EntityStore`, `ReferenceTarget`, `Fields.common`; the engine requires an id on every reference-target record | The type kind, the edge store, the edge target with a `tbe_` id | Nothing in the engine; the copy rule for a duplicated id is D3b-22 |
| Zones' path resolution (`Occurrences.occurrence_at`, `occurrence_for_path`, `write_refusal`), `faces.host_context`, `target.*` refusals | Which Zone holds an edge, whether it bounds an envelope Face | `zones.containment`: the same resolution for an Edge leaf, with the reason instead of nil (H11) |
| `core/pick.rb`, `core/drag_set.rb`, `ColourBy::Lease`, Spaces' Mark floor tool | The edge tool's shape | `Pick.edge_path` (H12) |
| `colour_by/` service with `derived` segments (P3a-05), per-colour line batches, legend `figure` sums in display units | The `by_type` mode and its HUD lengths | A stroke weight per mode for `derived` segments (H14) |
| `export/` contributors, preflight, the snapshot's `edge` entries (G-02) | One contributor and its preflight over the existing entries | Nothing in the snapshot (H15 done) |
| Python `Section`, `Attachment(ROOM)` with Spaces as its first user, `required_for_export`, shared `BldgSegment` per Building-Segment | One optional attaching section | `assemble` no longer withholds the model for an optional section's refusal (H18) |
| Windows Unit geometry; `units.host_extent` | The window-perimeter warning | `units.outlines` in world metres (H16) |
| `html/` inventory, subtabs, record edits, column menus, unit fields (`linear_psi`, `length`), the generated panel script list | The Thermal Bridges tab | The pane in `index.html`; the disabled tab becomes a live one |
| Foundation `ph_composer.context.open` and `context.root` (3a1) | Locate into a nested Zone | Nothing |
| The registry's agent-facing keywords, `API::CHANGES`, `docs/AGENT_GUIDE.md` | Every operation this packet registers | One API minor bump and one guide recipe per stage that adds a name |

## Stages

Nine stages. Each has its own document under [phases/](phases) with scope, steps, source, tests to
write first, the host gate and the done condition.

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| [P3b-01](phases/p3b-01-thermal-bridge-contracts-and-edge-host-facts.md) | The two contract questions still open confirmed by test; B4's open edge cases closed on the host; citation lint for the T and two-digit F ids | Ed's go | shared | Divide, Weld, push-pull removal, intersect and heal on a tagged edge, each with Undo, Redo and reopen |
| [P3b-02](phases/p3b-02-thermal-bridge-type-records.md) | The feature; the Thermal Bridge Type kind, operations and reads | P3b-01 | thermal_bridges | Panel-closed script, Undo/Redo, reopen |
| [P3b-03](phases/p3b-03-edge-assignment.md) | Edge assignment record and target; assign, clear, selection; delete with replacement; `zones.containment`; `Pick.edge_path` | P3b-02 | thermal_bridges, zones, core | Assign by native selection, nested and refused paths, split, reopen |
| [P3b-04](phases/p3b-04-runs-and-schedule.md) | Runs, lengths, the schedule read, findings, `runs.locate` | P3b-03 | thermal_bridges | Schedule equals the hand calculation; 50,000 Edge measurement |
| [P3b-05](phases/p3b-05-thermal-bridges-tab.md) | The Thermal Bridges tab, assign bar, Schedule, right-click menu | P3b-04 | thermal_bridges, UI | Panel and menu gestures with Ed |
| [P3b-06](phases/p3b-06-thermal-bridge-colour-by.md) | A stroke weight for `derived` segments, the `by_type` mode | P3b-04 | colour_by, thermal_bridges | Thick coloured edges, depth, tags, HUD lengths |
| [P3b-07](phases/p3b-07-edge-tool.md) | The edge tool, the secondary route | P3b-05, P3b-06 | thermal_bridges | Click and drag with Ed; every cancel route |
| [P3b-08](phases/p3b-08-thermal-bridge-export.md) | Contributor over the snapshot's edge entries, preflight, Python section, optional attaching sections (R05 item 4), conformance, the window-perimeter finding | P3b-04 | export, thermal_bridges, windows | Normal RBZ exports; exact HBJSON reloads with the runs on their segment |
| [P3b-09](phases/p3b-09-thermal-bridge-acceptance-and-handoff.md) | Register closed; context, docs and the Phase 4 handoff | all stages above | integration | Fresh-process integrated run |

```
P3b-01 ── P3b-02 ── P3b-03 ── P3b-04 ═ T-M1 ─┬─ P3b-05 ═ T-M2 ─┬─ P3b-07 ─┐
                                             ├─ P3b-06 ─────────┘          ├─ P3b-09
                                             └─ P3b-08 ═ T-M3 ─────────────┘
```

The Phase 3a gates (P3a-01 before P3b-03 and P3b-08, P3a-05 before P3b-06) closed with Phase 3a
on 2026-10-17.

## Milestones

- **T-M1, after P3b-04.** Thermal bridges complete as data: types, assignments, runs and findings
  through the public API, panel closed, host-proven.
- **T-M2, after P3b-05.** Authoring on screen. The earliest point worth a hands-on pass by Ed.
- **T-M3, after P3b-08.** Exported to HBJSON and read back on the reference model.

## Order and parallel work

The default is one branch at a time in stage order. Phase 3a is closed and every decision is
answered, so this track has no external gate left but Ed's go. Within this
track, P3b-05, P3b-06 and P3b-08 can proceed in parallel after P3b-04.

No other feature packet is being implemented beside this one on 2026-10-21. The cross-phase
packets still open (units, validation-and-export) and any follow-up issue work may touch these
shared files, which must not be changed by two open branches at once:

| File | Phase 3b stage | Other current owner |
| --- | --- | --- |
| `extension.rb` | P3b-02 | none |
| `Makefile` (`PLANNING_IDS`) | P3b-01 | none |
| `features/zones/zone/occurrences.rb` and the Zones declarations | P3b-03 | Zones bug fixes; refactored last by PR #208 |
| `colour_by/overlay.rb`, `colour_by/drawing.rb`, `shell/registry.rb`, `shell/declarations.rb` | P3b-06 | none |
| `html/index.html` and the generated script list | P3b-05 | open panel follow-ups may touch it |
| `shell/api.rb` (`API::MINOR`, `API::CHANGES`), `docs/AGENT_GUIDE.md` | every stage that adds an operation | open agent-access follow-ups may touch them |
| `python/ph_composer_translation/composition.py`, `assembly.py` | P3b-08 | none |
| `tools/runtime/vendor.py` footprint keys | P3b-09 | none |

Each stage is one pull request against `main`, with `Refs [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)`. A
stage that grows past one coherent review splits along the slices its document names; it does not
merge half a gate.

## Ownership and dependency direction

`ph_composer.thermal_bridges` is layer 3 and requires `ph_composer.zones`, and
`ph_composer.windows` for the window-perimeter warning (D3b-15). Its Thermal Bridge Type is a
layer 1 definition inside the feature, held apart by a test, as Windows keeps its types beside its
Units. Zones gains one read, `zones.containment`, that names no Edge; Windows gains one read,
`units.outlines`, that names no thermal bridge; `core/pick.rb`, `colour_by/`, `export/` and the
Python assembly gain additions that name no feature. No file outside `features/thermal_bridges/`,
`html/features/thermal_bridges/` and the Python section names thermal bridges. Spaces and thermal
bridges are peers and neither requires the other.

## Verification profile and review

Use high assurance for the edge store and reference target (P3b-03), the Colour-by contract change
(P3b-06), and the assembly and translation changes (P3b-08). During a stage run focused
tests. At its gate run `make ci` on both offline Rubies (2.7.2 and 3.2.2), refresh the vendor
manifest when shipped Python or panel assets changed
(`uv run tools/runtime/vendor.py --refresh-manifest`), regenerate the panel script list
(`make panel-manifest`) and fixtures only through their owning tests (`make fixtures`), and run
the stage's host gate from a fresh process with the installed build. On the host, wait with
`host_bridge.py wait-for`, read with `host_bridge.py diagnostics`, reproduce a failure with
`host_bridge.py fault` whose `restore` reports `restored: true`, and record each case with
`acceptance_case.py begin` and `finish` so the ledger row is a Pass and not an observation
(`tools/hostkit/.index.md`).

Review ladder, one review per coherent diff, given the architecture rubric. P3b-03, P3b-06 and
P3b-08 change a published read, a contribution contract or the shared translation, and get the
stronger independent pass. P3b-01 gets the architecture review on its corrected
bindings. P3b-05 and P3b-07 apply the UI polish skill in their review. The rest get one
diff-focused review.

Add each stage's native cases to [`native-acceptance/cases.json`](../../native-acceptance/cases.json)
when the stage is implemented, with dependency patterns for the files it adds, and record observed
results in the ledger. Before a stage's gate run
`uv run tools/hostkit/acceptance_ledger.py status --changed <paths>` for the shared files it
changed and repeat the earlier cases that screen reports.

## Exit

Every row of [ACCEPTANCE.md](ACCEPTANCE.md) passes on the proving host, this packet records what
was delivered and what remains, the edge tagging rules are in `context/` for piping and ducting,
the Phase 4 packets point at them, and `docs/PRODUCT.md` and the generated API reference describe
what exists. Phase 3 closes when this plan and [Phase 3a](../../archive/phase-03a-spaces/PLAN.md) have both
exited. Nothing here is a release, a SketchUp 2023 or Windows claim, or a certification claim.
