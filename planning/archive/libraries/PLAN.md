# Libraries: implementation plan

DATE: 2026-09-30
STATUS: Complete for Phase 2 on branch; current-host acceptance passes. Deferred scope retained.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: https://github.com/bldgtyp/ph-composer/issues/14

The [PRD](PRD.md) owns behavior. The [Phase 2 plan](../phase-02-envelope/PLAN.md) sequences delivery and
[CONTRACTS](../phase-02-envelope/CONTRACTS.md) binds names. This file allocates the PRD to stages and settles the
items the PRD left to its PLAN.

## Allocation

| PRD scope | Roadmap | Stage |
| --- | --- | --- |
| Provider and kind adapter contracts, registration, the library file provider, catalog generations, the resolver, the copy coordinator, the Materials adapter, attribution | 2.2 | [P2-07](../phase-02-envelope/phases/p2-07-library-seam-and-file-provider.md) |
| Sidebar sources, selector, drag and drop, source review, badges, provider setup | 2.2 | [P2-08](../phase-02-envelope/phases/p2-08-library-sidebar-and-setup.md) |
| Export model library to file, the starter library, the example provider | 2.2 | [P2-09](../phase-02-envelope/phases/p2-09-library-export-starter-example.md) |
| Frame, Glazing and Psi-Install Type adapters | 2.4 | [P2-15](../phase-02-envelope/phases/p2-15-window-library-kinds.md) |
| The generic connection, the protocol page, sign-in | 2.5 | [P2-16](../../features/phase-08-post-mvp/phases/p2-16-connection-provider.md), deferred to Phase 5 by D2-8 on 2026-10-01 |

The sidebar's shared modules and its In this file source land earlier, in
[P2-04](../phase-02-envelope/phases/p2-04-assembly-builder.md), because the Builder cannot choose a Material
without them.

## Items the PRD left to this plan

| Item | Binding |
| --- | --- |
| Operation signatures | [CONTRACTS](../phase-02-envelope/CONTRACTS.md) section 3, Library |
| Wire schemas | The kind's record fields with SI units in the key names, published in `docs/LIBRARY_FILE_FORMAT.md` (P2-07, P2-15) |
| Fingerprint canonicalization | SHA-256 of the canonical JSON of the mapped semantic fields in declared order, with a declared version starting at 1 |
| Migration dispatch | Each adapter declares the wire schema version it supports. An unsupported version is refused and never coerced. No migration exists until a second version does |
| Aggregate catalog budget | Proposed 64 MB and 20,000 rows per provider, beside the PRD's 32 MB per file. P2-07 confirms by measurement and tests the exact limits |
| "Local revision" | The Model session revision plus `expected_values` on the records a proposal touches. There is no per-record revision |
| Verb for loading a catalog and for setup | A view command, pending the architecture review in P2-07. Never an action |

## Code owner and boundaries

Feature id `ph_composer.library`, folder `src/ph_composer/library/`, registered as a foundation
feature. It names no feature and no record kind. A kind adapter is a file in the feature that
owns the kind. Provider setup is per machine and never enters the SKP.

## Verification and handoff

Acceptance rows E07 to E09, E15 and, if in scope, E16 in the [register](../phase-02-envelope/ACCEPTANCE.md). The
library file format should be read by one other provider author before it is called stable;
that review is not a Phase 2 gate and stays in STATUS.


## Final Phase 2 state

All in-scope implementation and named acceptance pass with the qualified provenance in [the final consolidation](../phase-02-envelope/evidence/p2-17-acceptance.md#final-held-classify-result-and-normal-host-restoration). Earlier checkpoints above retain their original frontier. Future/consumer/connection scope stays with its explicitly named later packets. No merge or public release is claimed.
