# P5s-04: Set as Shading and Clear Shading

DATE: 2026-11-19
STATUS: Complete. Merged to main 2026-11-20 UTC (PR #530, `3a2bfaa4`). SD04 Pass 2026-11-20 on `906a102c`. Authorized 2026-11-19 with every Shading stage ([STATUS](../STATUS.md#authorization)). Not released.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#526](https://github.com/ph-composer/ph-composer-skp/issues/526)

## Entry and scope

Requires P5s-02. Owns `features/shading/declarations/menu.rb` and a long-lived selection client,
as Zones' `ZoneMenu::Client` is. No shell file changes. Paths are relative to `src/ph_composer/`. Behavior owner: the [PRD](../PRD.md). Names: [CONTRACTS](../CONTRACTS.md).

## Steps

1. Two `feature.menu_item` declarations with `menu: EXTENSION_NAME`, each `available:` from
   the `selection` query: Set as Shading when assign would change something, Clear Shading when
   the selection holds a marked entity.
2. Handlers read `selection`, then invoke `assign` or `clear` through `API.invoke` with
   the references and the read revision. They write no record themselves.
3. The outcome goes to the session notice and `Sketchup.status_text`: what was tagged, how many
   placements a shared Face covers, and what was left out with its reason.
4. `docs/`: a short "Shading surfaces" user page, linked from the documentation index.

## Tests

Availability for each selection shape (loose Faces, closed Group, Face in an open Group, Edges
only, a Zone Group, a pane Face); the handler's refusal path; a raising provider leaves the rest
of the menu built.

## Done when

SD04 passes on the host, with the menus driven natively.
