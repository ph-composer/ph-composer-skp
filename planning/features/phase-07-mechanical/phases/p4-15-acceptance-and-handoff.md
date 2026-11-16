# P4-15: acceptance and handoff

DATE: 2026-10-21
STATUS: Scoped
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry and scope

Requires P4-01 to P4-14. Owns the integrated run that closes Phase 4, the context and product
documentation, and the handoff of every METr row to metr-export. No new behavior. Phase 4 closing
is the MVP Ed set in D1.

Behavior owner: the three PRDs' "Acceptance shape". Register: [ACCEPTANCE](../ACCEPTANCE.md).

## Steps

1. **Offline gates.** Both Ruby full gates, coverage, browser checks, the pinned runtime and
   Chromium 88 checks, the packaged inventory and the footprint through `vendor.py --check`
   against its keys and the growth budget D3a-20 set, over the baseline Phase 3b's close recorded;
   at the phase close, reset the baseline by a recorded decision.
2. **Integrated host run.** Fresh process, normal installed RBZ, the reference model: author two
   Ventilators, the Hot Water System and one item of each later family from scratch through the
   panel; serve a nested Zone and a copied Zone; draw and assign the pipes and ducts; two Models
   open; Undo and Redo across the session; save, close, reopen; export and reload; compare with
   ACCEPTANCE's tables. Run each case through `acceptance_case.py begin` and `finish`.
3. **Register.** Consolidate M01 to M14 with their evidence links; mark each row Pass with its
   provenance, or record why not.
4. **Context.** Confirm `context/UBIQUITOUS_LANGUAGE.md` (the Systems table: Equipment, each
   family, Serves, Piping, Ducting), `CONTRACTS.md`, `TECH_STACK.md`, `EXTENSIBILITY.md` (the
   Serves record as the third Zone-occurrence child; sections that add to a required object) and
   `AGENT_INTERFACE.md` say what was built.
5. **Product docs.** `docs/PRODUCT.md` describes equipment, piping and ducting as built; the
   generated API reference, its "API changes" rows and the `docs/AGENT_GUIDE.md` recipes are
   current.
6. **Handoff.** Every METr row named in this packet (one device or three for a shared item, the
   Spaces walk for exhaust and supportive devices, `lassVU`, the diameter enum, the recirculation
   coefficient) is in metr-export with its owner; honeybee_ph#135's state is recorded; the units
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
