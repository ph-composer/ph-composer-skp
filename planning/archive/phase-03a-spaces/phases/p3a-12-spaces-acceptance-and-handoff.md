# P3a-12: Spaces acceptance and handoff

DATE: 2026-10-17
STATUS: Merged to main through PR #171; the acceptance rerun and the #179 and #188 rechecks followed (PRs #186, #189, #192). Phase 3a closed 2026-10-17
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#133](https://github.com/bldgtyp/ph-composer/issues/133)

## Entry and scope

Requires P3a-01 to P3a-11. Owns no feature code. It closes the Spaces rows of the acceptance
register with one integrated run, consolidates the evidence, and brings the packets, `context/`
and `docs/` into line with what exists. It does not close Phase 3: thermal bridges is still to
come.

Register: [ACCEPTANCE](../ACCEPTANCE.md). Host procedure:
`.agents/skills/ph-composer-native-acceptance/SKILL.md`.

## Steps

1. **Offline gates.** `make ci` on Ruby 2.7.2 and 3.2.2, coverage, `make ui-checks`, the runtime
   and Chromium 88 checks. Record counts and coverage.
2. **Package.** Build the normal RBZ. Record its hash, file count and installed bytes against
   the 22 MB target and 24 MB ceiling. No new wheel is expected; say so or explain one.
3. **Reuse matrix.** For S01 to S11, decide per row whether its stage evidence still holds at the
   final commit, using `acceptance_ledger.py status --changed` against every file changed since
   that evidence. Repeat what the screen reports stale. Record retained against current evidence
   per row, as Phase 2's reuse matrix did.
4. **Integrated host run.** Fresh process, the installed RBZ, the PRD's host gate in order on a
   new copy of the reference model: draw three room outlines in a Zone, Create Space from each,
   set heights, see the prisms, draw a fourth room off to the side from inside the Zone, run
   Height from solid on the sloped room, enter airflows by range paste, read the Zone rows' sums
   and imbalance marker, move one Space to the second Zone, copy a Space and see it made
   independent, switch between the Faces and Spaces views and between Classify and Mark floor and
   confirm one tool and one pressed glyph, switch through the four
   modes and read the HUD, select two Spaces and read the totals, Undo each step, save, reopen
   inside an open Volume, export, and read back the honeybee-ph Spaces, volumes, factors and
   airflow overrides. The PRD's last clause, PHX writing the METr rooms, is excluded (F19).
5. **Restore.** Leave the host in its normal state: no fault overrides, no hotloads, no tracing.
6. **Packets.** This packet's README and [STATUS](../STATUS.md) record delivered scope and what
   remains. Apply any PRD amendment from DECISIONS not yet applied. Update `planning/STATUS.md`
   and the ROADMAP row.
7. **Context and docs.** Confirm every durable rule the stages settled is in `context/`:
   the container rule, the edit-context writer, deferred work, derived geometry and readouts,
   the Spaces records in the record table, the section in the section table. `docs/PRODUCT.md`
   moves Spaces from proposed to what exists, in the client-facing register.
   `context/UBIQUITOUS_LANGUAGE.md` matches the terms as built. Run `docs-pass`.
8. **Follow-ups filed.** The refactor candidates from D3a-3 and D3a-4, the toolbar with
   zones-entry-points, the PHX checks with metr-export, and anything a stage deferred, each as a
   row in `planning/STATUS.md` or a note in its owning packet.
9. **Thermal bridges.** Tell [Phase 3b](../../phase-03b-thermal-bridges/STATUS.md) what Spaces
   built that it reuses (the viewport-tool shape, `derived` segments in Colour-by, the container
   rule), noting any shape that differs from its CONTRACTS.

## Tests

None new. This stage reruns and consolidates.

## Host gate

Step 4.

## Out of scope

Archiving. This packet is archived as `phase-03a-spaces` when it closes, independently of Phase 3b.
Any release, SketchUp 2023 or Windows claim.

## Done when

- S12 has evidence in `evidence/p3a-12-acceptance.md` with the reuse matrix; S01 to S11 each show
  Pass with stated provenance.
- The tracking ledger shows P3a-01 to P3a-12 at `Implemented on branch` or `Merged to main`.
- `planning/STATUS.md`, `ROADMAP.md`, the Spaces packet, `context/` and `docs/` agree.
