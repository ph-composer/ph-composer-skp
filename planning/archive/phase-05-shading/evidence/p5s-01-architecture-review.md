# P5s-01 evidence: architecture review of the corrected contracts

DATE: 2026-11-19
STATUS: Complete. Design review of [CONTRACTS](../CONTRACTS.md) as corrected in P5s-01, against `context/EXTENSIBILITY.md` and `context/CODING_STANDARDS.md`, with the `ph-composer-architecture-review` skill. No blocking finding.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

## Contribution contract and owner

The one foundation addition is a store flag, `excludes_from_envelope`, beside `claims_entity` in
`Records::EntityStore`, with one class-level check. It follows the precedent `claimed?` set: the store keeps
its flagged stores, the check reads records by presence and names no feature. Zones reads the check and never
names Shading; Shading constructs its store with the flag and never edits Zones. This keeps the dependency
direction CONTRACTS section 1 states (Shading requires Zones, not the reverse).

## One contributor task, traced

A later feature that wants some geometry out of a Zone's envelope (the [zone-shading brief](../../../features/unscheduled/zone-shading.md),
or construction-only geometry) constructs its own store with the flag and writes its record. It changes no Zones
file, no shell, no export orchestration: the four funnels already read the check. It must learn the store's
two flags and the rule that a claimed entity wins. That is the smallest surface the seam can have.

## Findings and recommendations for P5s-02 and P5s-03

| # | Finding | Recommendation |
| --- | --- | --- |
| 1 | The check has two input forms, live entities and snapshot entries. Two implementations of one rule can drift | Write the rule once over "which dictionaries does each step carry", with two thin adapters, and test that a live path and its snapshot entries give the same answer |
| 2 | Funnel A (`walk_faces`) cannot prune at a marked container, because a claimed entity below it keeps its Faces in the envelope (D5s-17) | Carry the inside list, or a marked flag and a claimed flag, down the walk; test a Space-like claimed Group inside a marked Group inside a Zone |
| 3 | Funnel C's refusal code and funnel B's new reason are proposals, not decisions | P5s-03 picks them; `target.wrong_kind` keeps the code list unchanged |
| 4 | Spaces' Create Space reads a Zone Face through `faces.host_context` (funnel B). Once a marked Face reads as no Zone Face, Create Space on it would refuse as outside a Zone | P5s-03 confirms that refusal is the intended one, or names a Shading-specific message; one Spaces test either way |
| 5 | The live walk stops at a nested Zone; the export projection files a Face under every enclosing Zone. Pre-existing, not introduced here | Follow-up outside this packet; the exclusion applies to each side's own set |
| 6 | SD01 shows a pasted loose Face takes a new persistent id and an intersect gives two marks. Both are consistent with D5s-07 (no durable id) and D5s-08 (identifier from the occurrence path) | No change. The PRD's "Copies and edits" now says so |

## Readability

Section 4 lists consumers by funnel, so a reader finds the four edit points before the twenty consumers, and
each consumer row names the funnel its P5s-03 test exercises. Exempt walkers carry a one-line reason.

## Not reviewed

Implementation: none exists in this stage. The store flag, the check and its tests land in P5s-02; the Zones funnels read it from P5s-03.
