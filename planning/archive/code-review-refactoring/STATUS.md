# Refactoring status

DATE: 2026-10-13
STATUS: Complete and archived 2026-10-14 (PRs 99 to 126). The geometry contribution packet moved to `planning/features/cross-phase/` with its deferred stages G-01, G-03 and G-04, which the phase 3b thermal-bridge ledger schedules.
ISSUE: none (local planning draft)

Ed accepted C1, C2, W1 and the Zone-child pattern on 2026-10-13. The same day the twelve plans were
reviewed against the baseline source and rewritten as phased implementation plans with per-packet
stage ledgers. Four technical defaults were simplified in that review and Ed accepted them the same day; they
are listed in [DECISIONS.md](DECISIONS.md) under "Deviations recorded 2026-10-13". Delivery began the same day:
issues and PRs are linked from each packet row as they open.

| Packet | Findings | Stages | State |
| --- | --- | --- | --- |
| [Export wording](../export-contract-wording/STATUS.md) | F08 | EW-01 | Complete; merged in [PR #99](https://github.com/bldgtyp/ph-composer/pull/99), archived |
| [Outcome hook](../outcome-hook-isolation/STATUS.md) | JS-02 | OH-01, OH-02 | Complete; merged in [PR #102](https://github.com/bldgtyp/ph-composer/pull/102), archived |
| [Contributor example](../contributor-example-lifecycle/STATUS.md) | JS-03, JS-04 | CE-01 to CE-03 | Complete; merged in [PR #102](https://github.com/bldgtyp/ph-composer/pull/102), archived |
| [Registration](../registration-reliability/STATUS.md) | F01, F02 | RR-01 to RR-03 | Complete; merged in [PR #105](https://github.com/bldgtyp/ph-composer/pull/105), archived |
| [Composition](../cross-feature-composition/STATUS.md) | F04 | C-01 to C-04 | Complete; merged in [PR #105](https://github.com/bldgtyp/ph-composer/pull/105), archived |
| [Windows coordinator](../windows-orchestration/STATUS.md) | RF-02 | W-01 to W-03 | Complete; merged in [PR #108](https://github.com/bldgtyp/ph-composer/pull/108), archived |
| [Panel facts](../panel-domain-ownership/STATUS.md) | JS-01, JS-05 | PD-01 to PD-04 | Complete; merged in [PR #108](https://github.com/bldgtyp/ph-composer/pull/108), archived |
| [Library contracts](../library-contracts/STATUS.md) | F05, RF-04 | LC-01 to LC-04 | Complete; merged in PR 112 ([#111](https://github.com/bldgtyp/ph-composer/issues/111)), native receipt passed, archived |
| [Entity customization](../entity-customization/STATUS.md) | RF-01, RF-03, F07 | EC-01 to EC-05 | Complete; merged in PRs 110, 122, 123, 126 ([#109](https://github.com/bldgtyp/ph-composer/issues/109)), archived |
| [Zone-child lifecycle](../zone-child-lifecycle/STATUS.md) | copied-Zone request | ZC-01 to ZC-04 | Complete; merged in PRs 114 to 117 ([#113](https://github.com/bldgtyp/ph-composer/issues/113)), native receipt passed, archived |
| [Geometry seams](../geometry-contribution-contracts/STATUS.md) | F06 | G-01 to G-04 | G-02 merged ([#118](https://github.com/bldgtyp/ph-composer/issues/118)); packet moved to `features/cross-phase/`, G-01, G-03, G-04 deferred to the phase 3b ledger |
| [Foundation purity](../foundation-purity/STATUS.md) | F03 | P-01 to P-03 | Complete; merged in PR 121 and archived |

Each packet's `STATUS.md` is its stage ledger and the entry point for `implement`. The
[review evidence](../code-review/evidence/README.md) records the unchanged baseline tests and probes.
[DELIVERY_ORDER.md](DELIVERY_ORDER.md) names dependencies and PR boundaries.

The 2026-10-13 source review found two facts the first drafts missed: a third `USER_DATA` constant
in Assemblies (export wording) and the Zones `retire_pairs` participant, called with non-JSON
arguments from the same feature (composition). Both are in their plans.
