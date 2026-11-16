# Phase 7: mechanical

DATE: 2026-10-21
STATUS: Scoped. Interviewed (equipment shared shape, Ventilators, hot water) and planned as P4-01 to P4-15 on 2026-10-21; families 3 to 7, piping and ducting are gate stubs until their interviews; D4-01 to D4-12 answered as recommended the same day; no stage authorized. Wireframes reviewed 2026-11-15: D4-13 to D4-20 answered in DECISIONS Part 3; bindings and stages P4-05 to P4-11 owe re-planning.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

Renumbered 2026-11-15 when Ed re-ordered the phases. Stage, decision, register and roadmap item ids keep their original prefixes (P4-, D4-, M, roadmap 4.1 to 4.6): this was Phase 4, and its documents still say so. It now follows [Phase 4: climate](../phase-04-climate/README.md), which its heat pump stage needs, [Phase 5: shading](../phase-05-shading/README.md) and [Phase 6: Programs](../phase-06-program/README.md).

Roadmap items 4.1 to 4.6 from [ROADMAP.md](../../ROADMAP.md). Author the equipment a Phius model
needs and the Zones each item serves, then draw and measure the ducts and pipes, so METr needs no
hand entry before its first run. Phase 4 closing is the complete MVP Ed set in D1.

This directory is the phase's coordinating packet (`planning/.instructions.md`). The three feature
packets inside it hold the behavior and the interview records; the coordinating files hold the
stages, the bindings, the open decisions and the one ledger.

## Read order

1. [equipment/PRD.md](equipment/PRD.md): the shared shape, seven families and the interview
   record (Q1 to Q12, V1 to V6, hot water H1 to H7). Then the
   [hot-water-piping](hot-water-piping/PRD.md) and [erv-ducting](erv-ducting/PRD.md) PRDs, not yet
   interviewed.
2. [STATUS.md](STATUS.md): the tracking ledger. One row per stage, the entry gates, the decisions
   and what each stage still owes. The one place completeness is read from.
3. [DECISIONS.md](DECISIONS.md): what the code and the stack say beyond the PRDs (F1 to F14) and
   the twelve plan decisions D4-01 to D4-12, answered as recommended on 2026-10-21. Part 3 holds
   the wireframe review of 2026-11-15 (F15 to F19, D4-13 to D4-20), which revises D4-08 and five
   interview answers; the [wireframes](mockups/README.md) illustrate it.
4. [PLAN.md](PLAN.md): the stages, their order, owners, gates and the files shared with Phase 3b.
5. [CONTRACTS.md](CONTRACTS.md): feature id, records, operations, seams, foundation additions A1
   to A5, findings and the export sections. Proposed until P4-01 confirms them against code.
6. [ACCEPTANCE.md](ACCEPTANCE.md): M01 to M15 and the synthetic reference model with its expected
   HBJSON.
7. The stage document being worked, under [phases/](phases). Each full document is written to be
   handed to a coding agent on its own, with this packet's CONTRACTS and the equipment PRD. A gate
   stub says what must happen before it can be written in full.

## Stages

| Stage | Delivers |
| --- | --- |
| [P4-01](phases/p4-01-equipment-contracts-and-seams.md) | Contracts confirmed against code; `honeybee_phhvac` through the Pyodide seam; citation lint |
| [P4-02](phases/p4-02-equipment-feature-and-ventilator-kind.md) | The feature and the Ventilator kind with its operations, panel closed |
| [P4-03](phases/p4-03-serves-assignment.md) | The Serves record on the Zone Group, its target, assign and clear, the Zone-copy contributor |
| [P4-04](phases/p4-04-ventilator-export.md) | The ventilation contributor and section; the B4 HBJSON proof |
| [P4-05](phases/p4-05-systems-tab-and-ventilators-view.md) | The Systems tab, the Equipment subtab, the Ventilators view with Serves and balance, `By ventilator` |
| [P4-06](phases/p4-06-hot-water-records-and-export.md) | The Hot Water System kind with tanks and heaters, and its section |
| [P4-07](phases/p4-07-hot-water-view.md) | The Hot water view with child rows, `By hot water system` |
| [P4-08](phases/p4-08-heat-pumps.md), [P4-09](phases/p4-09-electric-heaters.md), [P4-10](phases/p4-10-pumps.md), [P4-11](phases/p4-11-fans.md), [P4-12](phases/p4-12-appliances.md) | Families 3 to 7, each after its interview |
| [P4-13](phases/p4-13-hot-water-piping.md), [P4-14](phases/p4-14-erv-ducting.md) | The drawn packets, after Phase 3b's edge stages and their interviews |
| [P4-15](phases/p4-15-acceptance-and-handoff.md) | Integrated acceptance, context, docs, the metr-export handoff; the phase close |

## What this packet needs from elsewhere

- Phase 3b, in progress since 2026-10-21: its lint, composition-root, `index.html` and assembly
  edits land before the Phase 4 stage that touches the same file (PLAN, "Order and parallel
  work"); its edge stages P3b-03 to P3b-08 before P4-13 and P4-14.
- [metr-export](../unscheduled/metr-export/README.md) for every METr claim; acceptance here is
  HBJSON reloaded in the pinned stack.
- [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135) for the simplified hot
  water methods.
- [units](../cross-phase/units/STATUS.md) Q2 and Q3 for the new quantity rows.

## Scope

In: the seven equipment families as records with a Serves relation to Zones, the Systems tab,
Colour-by modes, findings and HBJSON export; ERV ducting and hot water piping as drawn edges with
types, schedules and export, once Phase 3b supplies the edge mechanics.

Out: METr conversion, the simplified hot water methods until upstream carries the field, boilers,
district heat and PV, equipment libraries, the Zone loads packet's loads ([Phase 4a Programs](../phase-06-program/README.md)), equipment geometry,
sizing, schedules, SketchUp 2023 and Windows proof, public distribution.

## Rules for every stage

- The PRD owns behavior, CONTRACTS binds names, the stage document sequences the work. A stage
  that needs a behavior the PRD does not state stops and records the question in DECISIONS.
- Code and tests cite `context/` and never `planning/`, a PRD or a planning id. `make lint`
  enforces it. Durable rules a stage settles are folded into `context/` in the same change.
- Before designing a boundary or changing code, load
  `.agents/skills/ph-composer-architecture-review/SKILL.md`. Before changing an HtmlDialog screen,
  load `.agents/skills/ph-composer-ui-polish/SKILL.md` and read the screen's table in
  [ui-baseline](../../ui-baseline/README.md).
- Link measured host claims to current host evidence. Do not restate them.
- Tests come first and are listed in each stage. Offline tests never stand in for a host gate. A
  stage is `Implemented on branch` only after its host gate has run, following
  `.agents/skills/ph-composer-native-acceptance/SKILL.md`.
- Synthetic fixtures only. No client data, no licensed tables, no real project model.
- Every commit carries a DCO sign-off.
- When a stage changes state, update [STATUS.md](STATUS.md) in the same change.
