# P3b-09: thermal-bridge acceptance and handoff

DATE: 2026-10-03
STATUS: Scoped. Corrected to `main` at `420c783a` on 2026-10-21 (DECISIONS Part 1b)
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#301](https://github.com/ph-composer/ph-composer-skp/issues/301)

## Entry and scope

Requires P3b-01 to P3b-08. Owns the integrated run that closes the
Phase 3b, the context and product documentation, and the handoff of the edge
tagging rules to Phase 4. No new behavior.

Behavior owner: the [thermal-bridges PRD](../PRD.md), "Acceptance shape".
Register: [thermal-bridges ACCEPTANCE](../ACCEPTANCE.md).

## Steps

1. **Offline gates.** Both Ruby full gates, coverage, browser checks, the pinned runtime and
   Chromium 88 checks, the packaged inventory and the footprint through `vendor.py --check`
   against its keys: `installed_target_bytes` 24,000,000, `installed_ceiling_bytes` 26,000,000
   and `installed_growth_bytes` 1,500,000 over `installed_baseline_bytes` 23,994,083, the Phase 3a
   close (D3a-20); at the phase close, reset the baseline by a recorded decision.
2. **Integrated host run.** Fresh process, normal installed RBZ, the reference model: author the
   five types and runs from scratch through the panel, the menu and (if kept) the tool, inside a
   Zone under a rotated wrapper; two Models open; Undo and Redo across the session; save, close,
   reopen; export and reload; compare with ACCEPTANCE's tables. Run each case through
   `acceptance_case.py begin` and `finish`, wait with `host_bridge.py wait-for`, read with
   `diagnostics`. Restore normal composition and record it as its own observed result.
3. **Register.** Consolidate T01 to T08 with their evidence links; mark each row Pass with its
   provenance, or record why not.
4. **Context.** Confirm `context/UBIQUITOUS_LANGUAGE.md`, `CONTRACTS.md`, `TECH_STACK.md`,
   `EXTENSIBILITY.md`, `SKETCHUP_HOST_BEHAVIOR.md` and `AGENT_INTERFACE.md` (the per-feature
   list of programmatic reads and writes, with the tool's explicit-reference equivalent) say what
   was built. The edge tagging rules in `context/` are written so piping and ducting can follow
   them without reading this packet.
5. **Product docs.** `docs/PRODUCT.md` describes thermal bridges as built (its paragraph today
   says proposed); the generated API reference, its "API changes" rows and the
   `docs/AGENT_GUIDE.md` recipe are current.
6. **Handoff.** Update the hot-water-piping and erv-ducting packets' dispositions to point at the
   `context/` rules and at the edge tool, and record B4's registry question (D3b-01) as theirs.
   Add the PHX quantity check to metr-export if P3b-08 did not. Close G-01 and G-04 in the
   geometry-contribution-contracts packet with their receipts, which lets that packet and
   [#118](https://github.com/ph-composer/ph-composer-skp/issues/118) close.
7. **Tracking.** Update [STATUS](../STATUS.md), `planning/STATUS.md` and the roadmap's 3.2
   row.

## Tests (write first)

None new. The gates in step 1 and the integrated run in step 2.

## Host gate

Step 2.

## Out of scope

Release, SketchUp 2023, Windows, certification claims. METr.

## Done when

- T09 passes; every T row has evidence or a recorded reason.
- [STATUS](../STATUS.md) shows Phase 3b complete.
