# P4-14: ERV ducting

DATE: 2026-10-21
STATUS: Requested. A gate stub: written in full after its interview.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry gates

P4-04 merged (the ventilation system it exports into); P4-13's draw and assign behavior; Phase 3b's P3b-03, P3b-06, P3b-07 and P3b-08 merged (P3b-04's chain rule is not needed); the ERV ducting interview ([its PRD](../erv-ducting/PRD.md), Q1 to Q9); D4-09 answered.

## Owns

Roadmap 4.2 as the ducting PRD scopes it: Duct Type records, Ducting groups linked to a Ventilator, direction and type on edges, the schedule, the Colour-by mode, the section that appends `PhDuctElement`s to the required ventilation objects before attach with lengths converted to metres (D4-09), the ERV ducting subtab, and the two duct-length columns contributed to the Ventilators table through `table_contributions.js` (ducting Q9).

## Reuses

P4-13's draw and assign; P4-04's section; the length quantities in inches (units ducting row).

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
