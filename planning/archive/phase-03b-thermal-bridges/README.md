# Phase 3b: thermal bridges

DATE: 2026-10-03
STATUS: Complete 2026-10-26, archived. P3b-01 to P3b-09 merged to `main` through PRs #302 and #308 to #315; T01 to T09 pass with ledger results.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

Roadmap item 3.2 from [ROADMAP.md](../../ROADMAP.md). Build Thermal Bridge Types, select edges,
assign a type. The exporter measures the edges and writes one honeybee-ph thermal bridge per
assigned run. New work: the predecessor never built it.

This packet also owns the rules for tagging a SketchUp edge, which
[hot-water-piping](../../features/phase-04-mechanical/hot-water-piping/README.md) and
[erv-ducting](../../features/phase-04-mechanical/erv-ducting/README.md) reuse.

Phase 3 is split into two independent sub-phases, each one flat packet:
[3a Spaces](../phase-03a-spaces/README.md) and 3b thermal bridges (this folder). Phase 3 ends when
both close. That is the first internal envelope-model release candidate (D1).

## Read order

1. [PRD.md](PRD.md): the type and assignment records, the edge-tagging rules, the tab, the
   Colour-by mode, validation, export mapping, and the interview's answers.
2. [STATUS.md](STATUS.md): the tracking ledger. One row per stage, the entry gates, the decisions
   and what each stage still owes. The one place completeness is read from.
3. [DECISIONS.md](DECISIONS.md): what the code, the B4 spike and the honeybee stack say (F1 to
   F26 at `08c4807`, re-read with F27 to F36 at `420c783a` in Part 1b), the PRD questions and
   plan decisions D3b-01 to D3b-23, and Ed's answers of 2026-10-03 and 2026-10-21, which are the
   interview record.
4. [PLAN.md](PLAN.md): the stages, their order, owners, gates and the files shared with Phase 3a.
5. [CONTRACTS.md](CONTRACTS.md): feature id, records, operations, seams, foundation additions H11
   to H18, findings and the export section. Re-read against code on 2026-10-21 (section 8); two
   questions stay with P3b-01.
6. [ACCEPTANCE.md](ACCEPTANCE.md): T01 to T09 and the synthetic reference model with its hand
   calculation.
7. The stage document being worked, under [phases/](phases). Each is written to be handed to a
   coding agent on its own, with this packet's CONTRACTS and the PRD.

## Stages

| Stage | Delivers |
| --- | --- |
| [P3b-01](phases/p3b-01-thermal-bridge-contracts-and-edge-host-facts.md) | The two open contract questions tested; B4's open host cases closed; citation lint for T and two-digit F ids |
| [P3b-02](phases/p3b-02-thermal-bridge-type-records.md) | The feature and the Thermal Bridge Type kind with its operations, panel closed |
| [P3b-03](phases/p3b-03-edge-assignment.md) | The Edge assignment record and target, assign and clear, Zones' containment read, the edge pick |
| [P3b-04](phases/p3b-04-runs-and-schedule.md) | Runs, lengths, the schedule read and findings |
| [P3b-05](phases/p3b-05-thermal-bridges-tab.md) | The Thermal Bridges tab and the right-click menu |
| [P3b-06](phases/p3b-06-thermal-bridge-colour-by.md) | The `by_type` Colour-by mode on Phase 3a's `derived` geometry |
| [P3b-07](phases/p3b-07-edge-tool.md) | The edge tool, the secondary route Phase 4 reuses |
| [P3b-08](phases/p3b-08-thermal-bridge-export.md) | The contributor over the snapshot's edge entries, the Python section, optional attaching sections, the window-perimeter finding |
| [P3b-09](phases/p3b-09-thermal-bridge-acceptance-and-handoff.md) | Integrated acceptance, context and the Phase 4 handoff |

## What this packet took from Phase 3a, and what landed since

Phase 3a closed on 2026-10-17 and its three gates are met: the nested-container rule that
`zones.containment` honors and R05 items 1 and 2 came with
[P3a-01](../phase-03a-spaces/phases/p3a-01-contracts-and-groundwork.md); the `derived`
geometry, the legend `figure` sums and the one-line-primitive decision came with
[P3a-05](../phase-03a-spaces/phases/p3a-05-colour-by-derived-geometry-and-readouts.md).
Since the plan was drafted, G-02 put Edge entries in the export snapshot, the agent-access phase
made every registration an agent surface and gave the foundation `context.open`, and the host kit
grew bounded waits, a diagnostic reader and fault controls. [DECISIONS](DECISIONS.md) Part 1b
lists each with its consequence. R05 item 4 (optional attaching sections) is still this packet's,
in P3b-08.

## Scope

In: Thermal Bridge Type records, assignment to edges, measured length, a schedule with totals, a
Colour-by mode, export to HBJSON for honeybee-ph.

Out: psi-value calculation, Flixo or THERM import, fRsi and condensation checks, automatic
detection of junctions, window install psi-values (those belong to Window Types), point thermal
bridges and chi-values (D3), METr conversion (deferred by D12 to
[metr-export](../../features/unscheduled/metr-export/README.md)), a library kind (roadmap 5.4).

## Rules for every stage

- The PRD owns behavior, CONTRACTS binds names, the stage document sequences the work. A stage
  that needs a behavior the PRD does not state stops and records the question in DECISIONS.
- Code and tests cite `context/` and never `planning/`, a PRD or a planning id. `make lint`
  enforces it. Durable rules a stage settles are folded into `context/` in the same change.
- Every operation a stage registers is an agent-facing surface: declare the registry's
  `preconditions`, `side_effects`, `capability`, `response` and `while_busy` keywords where they
  apply, bump `API::MINOR` once with one `API::CHANGES` row, and extend the thermal-bridge recipe
  in `docs/AGENT_GUIDE.md` (CONTRACTS section 3).
- Before designing a boundary or changing code, load
  `.agents/skills/ph-composer-architecture-review/SKILL.md`. Before changing an HtmlDialog screen,
  load `.agents/skills/ph-composer-ui-polish/SKILL.md` and read the screen's table in
  [ui-baseline](../../ui-baseline/README.md).
- Link measured host claims to current host evidence or to the Phase 0 spikes. Do not restate
  them. Observe the host with the development tooling (`host_bridge.py wait-for`, `diagnostics`,
  `fault`; `acceptance_case.py begin` and `finish`), never a sleep inside an eval.
- Tests come first and are listed in each stage. Offline tests never stand in for a host gate. A
  stage is `Implemented on branch` only after its host gate has run, following
  `.agents/skills/ph-composer-native-acceptance/SKILL.md`.
- Synthetic fixtures only. No client data, no licensed tables, no real project model.
- Every commit carries a DCO sign-off.
- When a stage changes state, update [STATUS.md](STATUS.md) in the same change.
