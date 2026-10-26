# Phase 3a: Spaces

DATE: 2026-10-17
STATUS: Complete 2026-10-17 and archived. P3a-01 to P3a-12 merged to main (PRs #135 to #171); S01 to S11 pass with ledger results and S12's integrated run is done; the earlier cases the Spaces changes screened were rerun, and the two regressions found (#179, #188) were fixed (#187, #190) and rechecked. ZO-O7 fails on #181, a follow-up. Not released.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#133](https://github.com/bldgtyp/ph-composer/issues/133)

Roadmap item 3.1 from [ROADMAP.md](../../ROADMAP.md). Spaces finishes the room-by-room half of
the model that the predecessor started: floor area toward iCFA, net volume, and per-Space
ventilation airflows, authored against the geometry and visible in it. It depends on
[zones-and-adjacency](../phase-01-zones-and-adjacency/README.md) for the Zone a Space
lives in and on [face-assignment](../face-assignment/README.md) for the Colour-by
service. Mark floor is this packet's own tool, a sibling of Classify.

Phase 3 is split into two independent sub-phases, each one flat packet:
3a Spaces (this folder) and [3b thermal bridges](../phase-03b-thermal-bridges/README.md). Phase 3
ends when both close: a model carries its Spaces and its thermal bridges and matches what a
designPH export gave. That is the first internal envelope-model release candidate (D1).

This folder holds the feature's PRD and the coordinating files that sequence the work and bind it
to the code on `main`. Planned at `70c340f`; re-read against `87bdc62` on 2026-10-15
([DECISIONS](DECISIONS.md), Part 1b). The foundation stages are corrected to `87bdc62`. The UI
and UX discussion the same day made Spaces a view of the Zones tab, beside Faces, and the screen
stages were restructured around it ([DECISIONS](DECISIONS.md), "UI and UX discussion";
[mockups](mockups/README.md)).

## Read order

1. [PRD.md](PRD.md): where a Space sits, the records, floor marking, volume as a height with a
   preview and a from-solid helper, airflows, the Spaces view, the Colour-by modes, labels and
   selection totals, validation, export mapping, the port disposition, and twenty-four recorded
   decisions.
2. [STATUS.md](STATUS.md): the tracking ledger. One row per stage, the entry gates, the open
   decisions and what each stage still owes.
3. [DECISIONS.md](DECISIONS.md): what the merged foundation changed in the PRD (F1 to F22, re-read
   on `87bdc62` with F23 to F27 added in Part 1b), Ed's answers to D3a-1 to D3a-18, and the record
   of the UI and UX discussion.
4. [PLAN.md](PLAN.md): the stages, their order, owners and gates.
5. [CONTRACTS.md](CONTRACTS.md): feature id, records, operation names, cross-feature seams and
   foundation additions H1 to H10, H18 and H19. Proposed until P3a-01 confirms them against code.
6. [ACCEPTANCE.md](ACCEPTANCE.md): S01 to S12 and the synthetic reference model.
7. [mockups/](mockups/README.md): the accepted Zone views direction, as images and a static page.
8. The stage document being worked, under [phases/](phases). Each is written to be handed to a
   coding agent on its own, with this packet's CONTRACTS and the PRD.

## Scope

In: Space, Volume and Floor Segment records mapped to honeybee-ph; Create Space and Mark floor;
weighted area (iCFA); average clear ceiling height, volume preview and Height from solid; supply,
extract and transfer airflows; the Zone view contract and the Spaces view of the Zones tab; four
Colour-by modes, Space labels and selection totals.

Out: loads, schedules, equipment and their future Zone views, Space Types, LayOut, CSV, PHPP.

[validation-and-export](../../features/cross-phase/validation-and-export/README.md) and
[units](../../features/cross-phase/units/README.md) span phases and stay in `cross-phase/`. Their Phase 3a
allocations are in their own STATUS files and in the stages that touch them (P3a-01, P3a-07,
P3a-10).

## What Phase 3b needs from this packet

Thermal bridges runs on its own track, but three of its stages wait for stages here:
[P3b-03](../phase-03b-thermal-bridges/phases/p3b-03-edge-assignment.md) and
[P3b-08](../phase-03b-thermal-bridges/phases/p3b-08-thermal-bridge-export.md) need P3a-01 (the
nested-container rule and R05 item 1; item 2 is already on `main`), and
[P3b-06](../phase-03b-thermal-bridges/phases/p3b-06-thermal-bridge-colour-by.md) needs P3a-05 (the
`derived` geometry it draws edges with). The files both tracks change are listed in
[PLAN.md](PLAN.md), "Order and parallel work".

## Carried in

- **From Phase 2 planning (D2-6).** A derived-geometry extension to the Colour-by contract, wanted
  by Spaces (spaces Q22) and by the Window Type mode's operation marks. It is designed once, in
  [P3a-05](phases/p3a-05-colour-by-derived-geometry-and-readouts.md), against both users, and
  thermal bridges is its third user. Whether the marks themselves are built there is decision
  D3a-5, which now also settles Phase 3b's competing `LineEntry` proposal (G-03). Phase 2 adds Assembly and Window modes without implementing this extension; see the
  [accepted decision](../phase-02-envelope/DECISIONS.md) and the Colour-by contract in
  `context/EXTENSIBILITY.md`.
- **From the Phase 2 review (R05).** Four export-run items recorded in
  [validation and export](../../features/cross-phase/validation-and-export/STATUS.md), "Owed from the Phase 2
  review". Item 1 is allocated to [P3a-01](phases/p3a-01-contracts-and-groundwork.md), so it is
  settled before the first Spaces export section. Item 2, the section-cycle refusal, merged through
  PR #122. Item 3 is allocated to
  [P3a-10](phases/p3a-10-spaces-export.md). Item 4 moved to Phase 3b's P3b-08 when Ed made the
  thermal-bridge section the first optional attaching section (D3b-20).

## Rules for every stage

Confirmed copy behavior, 2026-10-12: [D3a-13](DECISIONS.md#confirmed-copy-decision-d3a-13)
requires Spaces included in a Zone copy to become independent authored instances. P3a-04 owns
the participation binding; S04/S12 prove the host state and S10 verifies HBJSON ownership.
Windows remain new instances of their existing Type under their protocol. The contract it uses,
`transition_contributor` on the Zone's independence transition, is on `main` with Windows as its
first adopter. The other decisions and all implementation gates remain open.

- The PRD owns behavior, CONTRACTS binds names, the stage document sequences the work. A stage
  that needs a behavior the PRD does not state stops and records the question in DECISIONS.
- Code and tests cite `context/` and never `planning/`, a PRD or a planning id. `make lint`
  enforces it. Durable rules a stage settles are folded into `context/` in the same change.
- Before designing a boundary or changing code, load
  `.agents/skills/ph-composer-architecture-review/SKILL.md`. Before changing an HtmlDialog screen,
  load `.agents/skills/ph-composer-ui-polish/SKILL.md` and read the screen's table in
  [ui-baseline](../../ui-baseline/README.md).
- Port from the predecessor at `f358ebf`. Its HEAD (`1fae5d3`) has an identical `src/` tree. A
  later predecessor fix enters only as an explicit change to the PRD's disposition table.
- Link measured host claims to the predecessor's evidence under
  `../ph-navigator-sketchup/planning/archive/` or to current host evidence. Do not restate them.
- Tests come first and are listed in each stage. Offline tests never stand in for a host gate. A
  stage is `Implemented on branch` only after its host gate has run, following
  `.agents/skills/ph-composer-native-acceptance/SKILL.md`.
- Synthetic fixtures only. No client data, no licensed tables, no real project model.
- Every commit carries a DCO sign-off.
- When a stage changes state, update [STATUS.md](STATUS.md) in the same change. It is the one
  place completeness is read from.
