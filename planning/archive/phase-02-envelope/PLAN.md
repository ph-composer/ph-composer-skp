# Phase 2 delivery plan

DATE: 2026-09-30
STATUS: Merged to main through PR #15 on 2026-10-01 (merge commit `c687a73`); current-host acceptance passes. Not released.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: https://github.com/bldgtyp/ph-composer/issues/14

## Outcome and scope

On the Phase 1 two-Zone model: build layered Assemblies from shared Materials, assign them to
Faces, build Window Types from Frames, Glazings and Psi-Install Types, place window units, copy
definitions in from a library file, and export a canonical HBJSON/report pair from the normal
packaged build. Reload the exact HBJSON in the pinned honeybee stack and read back the
constructions, the division grids, the apertures and the frame elements.

Out of this phase: METr conversion and import (D12; every "Through PHX" step in the PRDs waits
with [metr-export](../../features/unscheduled/metr-export/README.md)), Spaces, thermal bridges, shading,
SketchUp 2023 and Windows host proof, public distribution. The SD assembly helper, explicit door
support and reveal geometry are decided in their PRDs and deferred there.

## What Phase 1 supplies

Paths are relative to `src/ph_composer/`. This is a planning baseline at `052a7a1`.

| Existing | Reused by Phase 2 as | Still required |
| --- | --- | --- |
| `core/records/` engine, `RecordKind`, `DictionaryStore`, `Reference`, `ReferencePlan` | Storage, validation, identity, duplicate, guarded delete for six new catalog kinds | Nested reference declarations if absent; the settings primitive |
| The Attached zone kind and its delete with replacement | The worked example of a catalog kind and of `propose_delete` with a `reference_plan` | Nothing. Copy the shape |
| `shell/` registry, dispatch, API, outcomes, retries | Every new operation | `library_kind` and `library_provider` registrations; reference retargeters; possibly a handler-side read of a required feature |
| `proposal_participant`, used by `retire_pairs` | The mechanism under reference retargeters | The retargeter contract, and Zones' retargeter for the Assembly kind |
| Zones Face read, `classify`, `choose`, `locate`, selection actions, menu entries | Assembly assignment on every route | `assembly_id` in intent, `assign_assembly`, usage, the assembly colour mode |
| `colour_by/` service | The assembly mode and the Window Type mode | Nothing for Phase 2 scope (D2-6, confirmed 2026-09-30) |
| `core/pick.rb`, `core/drag_set.rb`, the Classify tool | The Place tool's shape | The picked point |
| `export/` contributors, preflight, snapshot, guard, artifact pair | Two new contributors | Rewritten Face preflight rows |
| Python `Section`, `Requirement`, coordinator, `composition.py` | Three new sections | `ZoneSection` loses its provider argument |
| Eight pinned wheels, honeybee-energy and honeybee-ph among them | Constructions, division grids, apertures, window constructions | Confirmation by running. No new wheel expected |
| `html/` table, view controls, overlay (Bubble, ActionMenu, formDialog), record form, unit field | Inventories, pickers, bubbles | Three panes, subtabs, `record_edits`, `inventory_grid`, the Builders, the sidebar |

## Stages

Seventeen stages. Each has its own document under [phases/](phases) with scope, steps, source,
tests to write first, the host gate and the done condition.

| Stage | Delivers | Depends on | Code owner | Host gate |
| --- | --- | --- | --- | --- |
| P2-01 | Contracts confirmed; the subtabs module and two UI kit ports | Entry gates | shared | Panel loads; no regression in Zones / Faces |
| P2-02 | Material and Assembly kinds, commands, thermal values, public operations | P2-01 | assemblies | Panel-closed script, Undo/Redo, reopen |
| P2-03 | Library / Materials and the Assemblies inventory | P2-02 | assemblies | Create, edit in place, duplicate, guarded delete |
| P2-04 | The Assembly Builder | P2-03 | assemblies | One Undo per gesture; both U-values |
| P2-05 | Assembly assignment, usage, the assembly Colour-by mode, delete with replacement | P2-02 | zones, with one retarget call in assemblies | Select and assign, paint, table, delete with replacement |
| P2-06 | Construction export and the real Face preflight | P2-05 | assemblies, zones | Normal RBZ exports; exact HBJSON reloads |
| P2-07 | Library seam, library file provider, Materials adapter, copy operations | P2-02 | library, assemblies | Panel-closed list, preview, apply, read back |
| P2-08 | Library sidebar, source selector, drag and drop, source review, setup | P2-07, P2-04 | library | Copy and assign by drag; Undo removes both |
| P2-09 | Export model library to file, starter library, example provider | P2-08 | library | Export, read back, reuse; outside registration |
| P2-10 | Frame, Glazing, Psi-Install Type and Window Type kinds, grid operations, thermal values | P2-01 | windows | Panel-closed script, Undo/Redo, reopen |
| P2-11 | Window Type Builder, Installs, U-Values, three Library subtabs | P2-10, P2-03 | windows | Builder gestures; Installs Save |
| P2-12 | Zones cutting-instance rules; the window unit; place, swap, re-host, rewrite, reset, restore | P2-10 | windows, zones | The native-edit matrix in a fresh process |
| P2-13 | Place tool, Schedule, the Window Type Colour-by mode | P2-12, P2-11 | windows | Place on wall and flat roof; Move-copy; resize a used type |
| P2-14 | Aperture export, window findings, net opaque area | P2-13, P2-06 | windows, zones | Normal RBZ exports; frame elements read back |
| P2-15 | Frame, Glazing and Psi-Install library kinds | P2-11, P2-08 | windows | Copy each kind from a file; assign a product by drag |
| P2-16 | [Generic connection provider and sign-in](../../features/phase-08-post-mvp/phases/p2-16-connection-provider.md) | Deferred to Phase 5 by D2-8 | library | Scope unchanged; production endpoint lacks the neutral envelope |
| P2-17 | Acceptance register closed; packets and context updated | all in scope | integration | Fresh-process integrated run |

```
P2-01 ─┬─ P2-02 ─┬─ P2-03 ── P2-04 ──────────────┐
       │         ├─ P2-05 ── P2-06 ═ M1          │
       │         └─ P2-07 ────────────── P2-08 ── P2-09 ═ M2
       └─ P2-10 ─┬─ P2-11 ───────────────┬─ P2-15 ── P2-16
                 └─ P2-12 ── P2-13 ── P2-14 ═ M3 ── P2-17
```

## Milestones

- **M1, after P2-06.** The Phase 1 gate closes: the normal packaged build exports a two-Zone model
  with authored Assemblies, and no development construction provider exists. This is the earliest
  point worth a hands-on pass by Ed.
- **M2, after P2-09.** The library seam is proven against Materials: a file, the sidebar, copy and
  reuse, export and read back, and one provider registered from outside the core.
- **M3, after P2-14.** Windows on the model, exported as Apertures.

P2-15 and P2-17 complete the phase. P2-16 is in the phase only if D2-8 says so.

## Order and parallel work

The default is one branch at a time in stage order, with P2-10 to P2-14 following P2-09. The
window track (P2-10 onward) touches no assemblies file after P2-01, so it can run on a second
branch from P2-01. Two stages change the same shared file and must not overlap:
`python/ph_composer_translation/model_sections.py` in P2-06 and P2-14, and
`features/zones/zone/occurrences.rb` in P2-05 (usage walk) and P2-12 (cutting-instance rule).

Each stage is one pull request against `main`, with `Closes` or `Refs` to the phase issue once
it exists. A stage that grows past one coherent review splits along the slices its document
names; it does not merge half a gate.

## Ownership and dependency direction

Three layers, each depending only downward (D2-1, revised by Ed 2026-10-01): definitions, then
geometry and assignment, then things placed on geometry.

- Assemblies is a definitions feature and requires nothing. It owns Material and Assembly
  records, the commands, the display thermal values, both inventories, the Builder and the
  construction contributor. No file in it names Zones or a Face.
- Zones requires assemblies. It owns the Face record and every write to `assembly_id`, the usage
  read, the assembly Colour-by mode, the Assembly retargeter and the assembly rows of the Face
  preflight. Its panel module contributes the Faces column and its row actions to the Assemblies
  inventory.
- Windows requires Zones. Its products and types are definitions and call nothing in Zones. Its
  unit, placement, Schedule, Colour-by mode and aperture contributor are the placed layer and read
  host Face state through Zones' reads. Zones never requires windows.
- The library seam owns the provider and kind adapter contracts, providers, the catalog, the copy
  coordinator and the sidebar. Each kind's adapter is a file in the feature that owns the kind.
- Export orchestration, `shell/`, `session/` and the UI kit name none of them.

## Verification profile and review

Use high assurance for record persistence, the delete transactions, the definition rewrite and
both translations. During a stage run focused tests. At its gate run `make ci` on both offline
Rubies (2.7.2 and 3.2.2), refresh the vendor manifest when shipped Python or panel assets changed
(`uv run tools/runtime/vendor.py --refresh-manifest`), regenerate fixtures only through their
owning tests (`make fixtures`), and run the stage's host gate from a fresh process with the
installed build.

Review ladder, one review per coherent diff, given the architecture rubric: an ordinary stage
gets one diff-focused review. P2-01, P2-05, P2-06, P2-07, P2-12 and P2-14 change public contracts,
serialization or native lifecycle and get the stronger independent pass instead. UI stages apply
the UI polish skill in the same review.

Add each stage's native cases to [`native-acceptance/cases.json`](../../native-acceptance/cases.json)
with dependency patterns for the files it adds, and record observed results in the ledger. Before
a stage's gate, run `uv run tools/hostkit/acceptance_ledger.py status --changed <paths>` for the
shared files it changed and repeat the Phase 1 cases that screen reports.

## Exit

Every active row of [ACCEPTANCE.md](ACCEPTANCE.md) passes on the proving host. The four feature
packets record what was delivered and what remains. Durable rules are in `context/`, and
`docs/PRODUCT.md` and the generated API reference describe what exists. Phase 3 is routed.
Nothing here is a release, a SketchUp 2023 or Windows claim, or a certification claim.
