# Spaces UI/UX refinement 2026-11: stage ledger

DATE: 2026-11-09
STATUS: In progress
AUTHOR: Ed May, BLDGTYP; Claude
ISSUE: https://github.com/ph-composer/ph-composer-skp/issues/426 (tracking)

Plan: [PLAN.md](PLAN.md). States: `Scoped` · `In progress` · `Implemented on branch` ·
`Merged to main` · `Blocked` · `Deferred`. Evidence names the command output or PR it rests on.

| Stage | Issues | State | PR | Evidence |
| --- | --- | --- | --- | --- |
| SUI-01 | #416 | Merged to main | [#427](https://github.com/ph-composer/ph-composer-skp/pull/427) | `make ci` exit 0 (Ruby 2527 runs, 0 failures; JS 856 pass; Python 264 passed; fixtures up to date; RBZ verified). `make ui-checks UI_CHECKS=tools/ui-preview/spaces_checks.cjs` passed. Host check recorded in the PR |
| SUI-02 | #417 | Merged to main | [#428](https://github.com/ph-composer/ph-composer-skp/pull/428) | `make ci` exit 0 (Ruby 2541 runs, 0 failures; JS 856 pass; Python 264 passed; fixtures up to date; RBZ verified). Host check recorded in the PR |
| SUI-03 | #419, #421 | Merged to main | [#429](https://github.com/ph-composer/ph-composer-skp/pull/429) | `make ci` exit 0 (Ruby 2556 runs, 0 failures; JS 856 pass; Python 264 passed; fixtures up to date; RBZ verified). Host check recorded in the PR |
| SUI-04 | #422 | Merged to main | [#430](https://github.com/ph-composer/ph-composer-skp/pull/430) | `make ci` exit 0 (Ruby 2567 runs, 0 failures; JS 856 pass; Python 264 passed; fixtures up to date; RBZ verified). Host check recorded in the PR |
| SUI-05 | #423 | Merged to main | [#431](https://github.com/ph-composer/ph-composer-skp/pull/431) | `make ci` exit 0 (Ruby 2579 runs, 0 failures; JS 856 pass; Python 264 passed; fixtures up to date; RBZ verified). Host check recorded in the PR |
| SUI-06 | #424 | Merged to main | [#432](https://github.com/ph-composer/ph-composer-skp/pull/432) | `make ci` exit 0 (Ruby 2594 runs, 0 failures; JS 856 pass; Python 264 passed; fixtures up to date; RBZ verified). Host check recorded in the PR |
| SUI-07 | #420 | Implemented on branch | | Part 1 experiment: [evidence/sui-07-delete-experiment.md](evidence/sui-07-delete-experiment.md) (failed on Undo; fallback route). `make ci` exit 0 (Ruby 2600 runs, 0 failures; JS 859 pass; Python 264 passed; fixtures up to date; RBZ verified). Host check recorded in the PR |
| SUI-08 | #418, #425 | Scoped | | |
