# P4-13c: the chain rule in core, the tree and the schedule

DATE: 2026-11-24
STATUS: Planned in full 2026-11-24 from [P4-13](p4-13-hot-water-piping.md), D4-36 (Q1, Q6, Q7), D4-18 and the [piping PRD](../hot-water-piping/PRD.md), "The tree", "Recirculation", "Schedule" and "Validation rows". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M13c` runs in the MS3 sitting (D4-31). Stronger review lane: it moves a shipped feature's rule into `core/`.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-13b. Owns, panel closed:

- Phase 3b's handover "moving the run builder to `core/`" ([3b STATUS](../../../archive/phase-03b-thermal-bridges/STATUS.md),
  "Deferred out of this plan"; the [piping sub-packet STATUS](../hot-water-piping/STATUS.md), "Owed from Phase 3b"):
  this is the first piping stage that computes runs, so it moves the chain rule, with 3b's tests, before using it.
- The piping scan, runs, the tree by connection (Q1), the recirculation sum per Hot Water System (D4-18), the
  findings, the schedule read and `runs.locate`.

Behavior owner: the [piping PRD](../hot-water-piping/PRD.md), "The tree", "Recirculation", "Schedule" and
"Validation rows". Names: this document, folded into [CONTRACTS](../CONTRACTS.md) in step 8. Pattern: Phase 3b's
P3b-04 (`features/thermal_bridges/runs/`, `scan/`, the schedule read and `runs.locate`).

Review: the strong lane, `gpt-6-astra`, with the architecture rubric. The core move changes code thermal bridges ship
and is a public contract inside the repository; the tree is what the export writes.

Paths are relative to `src/ph_composer/`.

## What the sources settle

- The chain rule (`context/TECH_STACK.md`, "Edge-owned assignments", and `features/thermal_bridges/runs/chains.rb`):
  Edges join where they share a vertex keyed on the Edge's container path plus the vertex id, so two placements of
  one definition never join; a run ends at a free end and at a vertex where the count of joining Edges is not two, so a
  T of one key is three runs; a chain with no end is one closed run; order and identifiers are deterministic over
  micrometre-rounded points.
- Runs are derived, never stored; nothing points at a run.
- A full scan of a Model of 50,000 Edges with 5,000 assigned costs about two seconds, so the thermal-bridge schedule
  is asked for on opening and on Refresh, never on every refresh (D3b-13, measured in P3b-04).
- honeybee-ph's `recirc_temp` and `recirc_hours` ([P4-13](p4-13-hot-water-piping.md#what-the-sources-settle-for-every-sub-stage)):
  length-weighted means over the recirculation elements, the hours truncated by `int()`, 60.0 and 24 with none.

## Inferred in planning

- **What moves to `core/`.** Only the chain rule: `core/edge_runs.rb` (`EdgeRuns`), pure, with a generic fact
  (`path`, a grouping `key`, `vertex_ids`, `points_m`, and an opaque `item` the caller reads back) and a run (`key`,
  `container_path`, `closed`, `points_m`, `edge_paths`, `facts`, `length_m`), the canonical ordering and the point
  keys. It names no feature, Zone, psi-value or identifier prefix. Naming and identifiers stay with each caller:
  thermal bridges keep `Runs::Chains.build` as a thin adapter that groups by Zone path, type and quantity and mints
  `tb_` identifiers exactly as today. `coincidence.rb`, `findings.rb` and `schedule.rb` are about Zones and psi-values
  and stay in thermal bridges.
- **The piping run key** is the role, the Pipe Type and the role's values (P4-13b), within one Piping group occurrence
  (the container path is in every vertex key). So a trunk with two Pipe Types, or two multipliers, is two trunks.
- **A branch passing straight through a trunk tee is one branch.** The PRD joins connected lines of one role and type
  into one run, and at the tee the branch's own count of joining Edges is two.
- **Parents.** A branch's parent is the trunk run of its group that shares one of its vertices; a twig's is the branch
  run that does. None is the PRD's blocking finding (`piping.branch_unconnected`, `piping.twig_unconnected`). A twig
  touching only a trunk has no branch and is unconnected. Two or more candidates (a branch at a trunk's type change)
  take the one whose identifier sorts first, with the non-blocking `piping.parent_ambiguous` naming both; the PRD names
  no rule for it.
- **Identifiers.** A run's identifier digests the container path, role, type id, role values and canonical points
  (`pipe_` and 16 hex digits); a segment's digests its Edge path and canonical endpoints. Both are what P4-13d writes
  to honeybee-ph, which keys segments and trunks by identifier, so neither uses the assignment id that a split shares.
  Display names are the role word and a counter per Hot Water System, numbered by group path, then the run's smallest
  point ("Trunk 1", "Branch 4", "Twig 12", "Recirculation 1").
- **The recirculation sum per System** (D4-18): over every recirculation Edge in the System's groups, length in metres,
  temperature as the length-weighted mean of `water_temp_c`, hours as the floor of the length-weighted mean of
  `daily_period`, 60.0 and 24 with no recirculation pipe, `from_piping` true only when there is one. P4-13d's Python test
  holds it equal to honeybee-ph's properties after reload.
- **Totals are drawn length.** A trunk's multiplier is a column, not applied to the totals, as honeybee-ph's
  `total_length` does not apply it.
- **The findings**, each naming its run or Edge with a `locate`:

  | Code | When | Blocks export |
  | --- | --- | --- |
  | `piping.type_missing` | A pipe with no Pipe Type, or a deleted one | yes |
  | `piping.group_unlinked` | A Piping group with no Hot Water System, or a deleted one | yes |
  | `piping.branch_unconnected` | A branch run that shares no vertex with a trunk run | yes |
  | `piping.twig_unconnected` | A twig run that shares no vertex with a branch run | yes |
  | `piping.insulation_conductivity_missing` | A used Pipe Type with insulation and no conductivity (P4-13a) | yes |
  | `piping.group_in_zone` | A Piping group a Zone now holds (moved there after creation) | yes |
  | `record.unreadable` | An assignment or group record that cannot be read | yes |
  | `piping.trunk_without_branches` | A trunk run no branch touches | no |
  | `piping.parent_ambiguous` | A branch or twig touching two parents | no |
  | `piping.shared_definition` | Pipes reached through two placements of one group definition, both counted | no |

  The PRD's nominal-size warning is dropped (P4-13, "Inferred in planning").
- **The schedule** is a query, `ph_composer.piping.schedule`, bounded, with no snapshot section, asked for on opening
  the Piping pills and on Refresh (D3b-13's rule), measured in step 7. Its rows: one per run (System, group, role,
  parent, Pipe Type, length, line count, the role values, findings); totals by role and System; one `systems` row per
  System (distribution length by role, recirculation length, temperature, hours, `from_piping`); one `types` row per
  Pipe Type with its used length, which `pipe_types.all` then reports.

## Steps

1. **Move the chain rule (before anything else).** Extract `core/edge_runs.rb` from `features/thermal_bridges/runs/chains.rb`
   as above, the thermal-bridge adapter keeping its signature and output. Move the pure chain-rule tests (the U, square
   and T; one container and never across containers; two placements of one component) from
   `tests/thermal_bridge_runs_test.rb` into `tests/edge_runs_test.rb` over generic facts, and leave a thermal-bridge test
   that the adapter still gives the same runs. The goldens `tests/fixtures/thermal_bridges/extraction.json` and
   `result_fields.json` must be byte-identical; no `make fixtures` change under thermal bridges. Then run
   `uv run tools/hostkit/acceptance_ledger.py status --changed src/ph_composer/core/edge_runs.rb src/ph_composer/features/thermal_bridges/runs/chains.rb`
   and record the stale count and the cases it names in the evidence; those cases repeat in the MS3 sitting.
   `context/TECH_STACK.md`, "Edge-owned assignments", names `core/edge_runs.rb` as the chain rule's home.
2. **Scan.** `features/piping/scan/occurrences.rb`: one walk of the Model for Piping groups and their direct Edges,
   detached facts with the group record, the assignment, world endpoints in metres and vertex ids; one fact per
   occurrence through shared definitions, marked `shared`; unreadable records as rows, not raises. It opens no
   operation.
3. **Runs and the tree.** `features/piping/runs/tree.rb`, pure: `EdgeRuns` per group occurrence and key, then parents
   by shared vertex, identifiers and names as above, recirculation runs kept apart.
4. **Recirculation.** `runs/recirculation.rb`, pure: the per-System sum above.
5. **Findings.** `runs/findings.rb`: the table above.
6. **Schedule and locate.** `runs/schedule.rb` and `declarations/schedule.rb`: the `schedule` query and the
   `runs.locate` view command (`capability: "view"`, selecting a run's Edges along their paths and framing them, opening
   a nested Piping group through `ph_composer.context.open`, refusing hidden targets). `pipe_types.all` rows gain
   `used_length_m`. One `API::CHANGES` row; the recipe gains the schedule read.
7. **Measure.** The schedule read on a synthetic Model of 50,000 Edges with 2,000 pipes in twenty groups, on the proving
   host in the MS3 sitting and offline beforehand; record both. If it is over P3b-04's figure, say so in the evidence.
8. **Documents.** `context/CONTRACTS.md` (the schedule read, `runs.locate`, the codes), the packet CONTRACTS (sections 3
   and 6), `context/TECH_STACK.md` (step 1).

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/thermal_bridges/runs/chains.rb` | Moved to `core/edge_runs.rb`; a thin adapter stays |
| `features/thermal_bridges/scan/occurrences.rb`, `runs/schedule.rb`, `run_locate.rb` | The scan, schedule and locate shapes |
| `tests/thermal_bridge_runs_test.rb`, `tests/thermal_bridge_schedule_test.rb` | The chain-rule tests move; the rest stay |
| `tests/fixtures/thermal_bridges/` | Must not change |

## Tests (write first)

1. Core (`tests/edge_runs_test.rb`): 3b's chain-rule cases over generic facts; a fact's `item` comes back on its run;
   nothing in `core/edge_runs.rb` names a feature (a grep test, as the dependency tests do).
2. Thermal bridges: every existing test passes unchanged except the moved ones; the goldens are byte-identical.
3. Tree (`tests/piping_runs_test.rb`) on the acceptance model's facts: one riser trunk with multiplier 12, three
   branches, six twigs and a recirculation loop give one trunk, three branches each under it, two twigs under each
   branch and one recirculation run, with lengths equal to the hand measurement to 0.001 m; a trunk changing Pipe Type
   mid-riser is two trunks; a branch drawn through a tee is one branch; the branch broken from its trunk gives
   `piping.branch_unconnected` and nothing else; a twig on a trunk gives `piping.twig_unconnected`; a branch at a type
   change gives `piping.parent_ambiguous` and takes the first identifier; two placements of one group give two trunks
   with distinct identifiers and `piping.shared_definition`.
4. Identifiers and names are the same across two scans and after a reassignment that changes no key; a split Edge
   (two Edges, one assignment id) gives two segments with distinct identifiers.
5. Recirculation: 10 m at 60 °C and 18 h with 5 m at 50 °C and 23 h gives 15 m, 56.67 °C and 19 h (19.67 truncated,
   as `int()` does); none gives 60.0 and 24 with `from_piping` false.
6. Each finding fires on its case and on no other; the scan writes nothing and opens no operation.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M13c`, fresh process on the acceptance model, panel closed: read
`schedule` and compare with the hand measurement; break a branch from its trunk and read the finding; `runs.locate` into
a Piping group inside a wrapper; save, reopen and read the same identifiers (vertex ids of a faceless Group across
reopen, not yet measured); the measurement in step 7; and the thermal-bridge cases `acceptance_ledger.py status
--changed` names as stale after the move. Offline `make ci` passes on this sub-stage's PR.

## Out of scope

Export (P4-13d). Screens, the Systems table's columns and Colour-by (P4-13e). Joining trees across Piping groups
(P4-13, "Inferred in planning"). The recirculation heat loss coefficient (metr-export).

## Done when

- M13c has offline evidence in `../evidence/p4-13c-tree-and-schedule.md`, with the ledger's stale count and the
  measurement; host verification lands in `MS3`.
- `make ci` passes on both Rubies; the thermal-bridge goldens are unchanged; the installed size is recorded against
  the 55 KB estimate.
