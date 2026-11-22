# P4a-05: Detailed airflows per Zone

DATE: 2026-11-15
STATUS: Merged to main 2026-11-20 ([#543](https://github.com/ph-composer/ph-composer-skp/pull/543), squash `5db743dc`). PG05 passes on the host. Authorized 2026-11-20 with the rest of Phase 4a; packet complete 2026-11-22 ([STATUS](../STATUS.md#host-sitting)).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

## Entry and scope

Requires P4a-02 for the Zone row's Actions cell; the rule change itself needs nothing else. Moves
the airflow mode from the Space to the Zone, relabels the inherited state By Program, and adds
From Program, the first-entry notice and the No Spaces export warning. No Program records needed:
a By Program Zone exports `None` and PHX uses the Room's ventilation load (none until P4a-10).

Behavior: [Phase 4a PRD](../PRD.md), "Zones / Spaces airflows". Names: [CONTRACTS](../CONTRACTS.md)
section 4. Research: [ventilation](../research/ventilation.md). Prototype: `j1-spaces`,
`j1-spaces-cascade`, `j3-spaces`.

## Steps

1. **Rule.** `features/spaces/scan/metrics.rb`: `airflow_mode` per Zone, values `by_program` and
   `detailed` (today `inheriting`, `user_specified`); Space `airflows` 0 for blanks in a detailed
   Zone, null in a By Program Zone; Zone sums null while By Program. `reads.rb` and `summaries.rb`
   shapes; C4a-6 for the per-Space copy. The old values also live in `colour_modes.rb` and the table
   export (`features/spaces/export.rb`, whose "Zone" becomes "By Program").
2. **Export.** The Space export contract carries the Zone's mode; the Python Space section moves to
   version 2 (`space_sections.py`, today `versions = frozenset({1})`) and `airflow_rates` takes it.
3. **Action.** `ph_composer.spaces.clear_zone_airflows`, one Undo step.
4. **Panel.** `html/features/spaces/cells.js`: placeholder "By Program" or "0" by the Zone's mode;
   the By Program tooltip says "this Zone's Program ventilation, split by floor area, with its
   schedule" (Spaces does not depend on Programs, so it does not name the Program); `view.js`: Zone sums dash while By Program, From Program in a detailed Zone row's
   Actions cell, the notice when an edit switches the mode; Transfer header tooltip.
5. **No Spaces.** Spaces' preflight warning naming each Zone with no Spaces (not blocking); the
   amber row in the view.
6. **Colour-by.** `colour_modes.rb` airflow modes read the Zone's mode.
7. **Docs.** `docs/PRODUCT.md` Spaces step 5; glossary (By Program, Detailed airflows); agent
   guide; API minor bump.

## Tests (write first)

1. A Zone with no rates: every Space exports `None`. One rate on one Space: every Space exports
   three rates, 0 for blanks.
2. Clearing the last rate returns the Zone to By Program; `clear_zone_airflows` does the same in
   one Undo step.
3. Browser checks: placeholders, Zone sums, From Program, the notice, the No Spaces row.
4. Preflight: the No Spaces warning does not block.

## Host gate

PG05: Spaces gestures with Ed at the mouse; export round trip.

## Done when

PG05 passes.
