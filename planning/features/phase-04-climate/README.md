# Phase 4: climate

Promoted from the post-MVP phase on 2026-11-15, because the Mechanical phase's heat pump stage needs
the Model's climate. A one-feature phase: this folder is the packet. Roadmap item 5.1 keeps its id.

Set the Model's site and climate on a Climate tab. Climate data is read from a folder on the
user's own computer; the one station the user attaches is copied into the SKP with its source, so
the Model reads anywhere.

Read [PRD.md](PRD.md), then [STATUS.md](STATUS.md).

The [wireframes](mockups/README.md) were reviewed with Ed on 2026-11-15 and 2026-11-16; the PRD
was revised to their nine answers on 2026-11-16.

In: a site location; climate data folders set per computer; a station picker on an outline map;
one climate copied into the Model with its provenance; values typed by hand; typed design
temperatures; export to honeybee-ph `Site`.
Out: any bundled or redistributed climate dataset, map tiles or any network access, a copy or
index of the user's climate files, a claim that a chosen station is certification-approved, solar
analysis. Deferred: the hourly weather file (a local EPW through honeybee-ph) and PHI data.

[sun-path-view](../phase-08-post-mvp/sun-path-view/README.md) and
[window-performance-overlays](../phase-08-post-mvp/window-performance-overlays/README.md) depend on it.
