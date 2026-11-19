# Phase 4: climate

Promoted from the post-MVP phase on 2026-11-15, because the Mechanical phase's heat pump stage needs
the Model's climate. A one-feature phase: this folder is the packet. Roadmap item 5.1 keeps its id.

Set the Model's site and climate on a Climate tab. Climate data is read from a folder on the
user's own computer; the one station the user attaches is copied into the SKP with its source, so
the Model reads anywhere.

Read [PRD.md](PRD.md) for the behavior, [PLAN.md](PLAN.md) for the twelve stages (P4c-01 to
P4c-12) under [phases/](phases), [CONTRACTS.md](CONTRACTS.md) for the records and seams,
[DECISIONS.md](DECISIONS.md) for the answers and Ed's rulings of 2026-11-17,
[ACCEPTANCE.md](ACCEPTANCE.md) for each stage's gate, then [STATUS.md](STATUS.md). Planned
2026-11-17; Ed authorized every stage the same day, tracked in
[#511](https://github.com/ph-composer/ph-composer-skp/issues/511).

Stage and decision ids here are `P4c-` and `D4c-`. `P4-` and `D4-` belong to the
[Mechanical packet](../../features/phase-07-mechanical/README.md), which kept its ids when the phases were
re-ordered.

Complete and archived 2026-11-18: all twelve stages merged to main (PRs #512 to #523); the review
fixes in PR #524, `73ef7ba9`. Host acceptance is not complete: Ed's verification pass and the rechecks are
listed in the [STATUS](STATUS.md#closure-2026-11-18). Not released.

The [wireframes](mockups/README.md) were reviewed with Ed on 2026-11-15 and 2026-11-16; the PRD
was revised to their nine answers on 2026-11-16.

In: a site location; climate data folders set per computer; a station picker on an outline map;
one climate copied into the Model with its provenance; values typed by hand; typed design
temperatures; export to honeybee-ph `Site`.
Out: any bundled or redistributed climate dataset, map tiles or any network access, a copy or
index of the user's climate files, a claim that a chosen station is certification-approved, solar
analysis. Deferred: the hourly weather file (a local EPW through honeybee-ph) and PHI data.

[sun-path-view](../../features/phase-08-post-mvp/sun-path-view/README.md) and
[window-performance-overlays](../../features/phase-08-post-mvp/window-performance-overlays/README.md) depend on it.
