# P4-15: acceptance and handoff

DATE: 2026-10-21
STATUS: In review, offline part (2026-11-25): steps 1 and 3 to 7 done offline in [the evidence](../evidence/p4-15-acceptance.md); step 2, the integrated host run, is owed to the MS3 sitting as case `M15`. Corrected 2026-11-22 after Phase 6 Programs: P4-08b and M16, the footprint keys, six families; then D4-22 and D4-25, answered the same day. See [DECISIONS, Part 4](../DECISIONS.md#part-4-review-after-programs-2026-11-22).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-01 to P4-14 and P4-08b; P4-12 is superseded. Owns the integrated run that closes Phase 4, the context and product
documentation, and the handoff of every METr row to metr-export. No new behavior. Phase 4 closing
is the MVP Ed set in D1.

Behavior owner: the three PRDs' "Acceptance shape". Register: [ACCEPTANCE](../ACCEPTANCE.md).

## Steps

1. **Offline gates.** Both Ruby full gates, coverage, browser checks, the pinned runtime and
   Chromium 88 checks, the packaged inventory and the footprint through `vendor.py --check`
   against its keys: the 28,000,000 byte ceiling, and the growth allowance over the baseline
   Phase 6 reset to 26,093,959 at its entry (F37). The ceiling is the nearer limit. At the phase
   close, reset the baseline by a recorded decision.
2. **Integrated host run.** Fresh process, normal installed RBZ, the reference model: author two
   Ventilators, the Hot Water System and one item of each later family (heat pumps, electric
   heaters, pumps, fans) from scratch through the panel; set a Building Segment's mechanical
   settings; serve a nested Zone and a copied Zone, and leave one served Zone in no Building
   Segment; draw and assign the pipes and ducts; two Models
   open; Undo and Redo across the session; save, close, reopen; export and reload; compare with
   ACCEPTANCE's tables. Run each case through `acceptance_case.py begin` and `finish`.
3. **Register.** Consolidate M01 to M14 and M16 with their evidence links (M12 is superseded); mark each row Pass with its
   provenance, or record why not.
4. **Context.** Confirm `context/UBIQUITOUS_LANGUAGE.md` (its "Systems terminology for planned
   features" table: Equipment as the word for the records of the `ph_composer.mechanical` feature
   (D4-22), each family, Serves, Piping, Ducting, and the Space-level
   "Ventilation assignment" row, which F25 makes a Zone relation), `docs/USER_DATA.md` (a row per
   new entity, F36), `CONTRACTS.md`, `TECH_STACK.md`, `EXTENSIBILITY.md` (the
   Serves as the second feature payload on a Zone record, after Programs' assignment; sections that add to a required object) and
   `AGENT_INTERFACE.md` say what was built.
5. **Product docs.** `docs/PRODUCT.md` describes the Mechanical tab, its equipment, piping and
   ducting as built; the
   generated API reference, its "API changes" rows and the `docs/AGENT_GUIDE.md` recipes are
   current.
6. **Handoff.** The `phx` group's round trips for this phase are green and listed (D4-25). Every
   METr file and import row named in this packet (`lassVU`, the diameter enum, the recirculation
   coefficient, what METr shows for a shared item) is in metr-export with its owner; honeybee_ph#135's state is recorded; the units
   packet's Q2 and Q3 rows are closed or carried.
7. **Tracking.** Update [STATUS](../STATUS.md), `planning/STATUS.md` and the roadmap's Phase 4
   table; the roadmap records Phase 4 closing as the MVP boundary D1 set.

## Tests (write first)

None new. The gates in step 1 and the integrated run in step 2.

## Host gate

Step 2.

## Out of scope

Release, SketchUp 2023, Windows, certification claims. METr.

## Done when

- M15 has evidence in `../evidence/p4-15-acceptance.md`.
- Every row of ACCEPTANCE is Pass with provenance, or its gap is recorded in STATUS.
