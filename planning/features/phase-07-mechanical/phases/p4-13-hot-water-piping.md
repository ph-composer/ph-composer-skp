# P4-13: hot water piping

DATE: 2026-10-21
STATUS: Requested. A gate stub: written in full after its interview.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Entry gates

P4-06 merged (the Hot Water System it exports into); Phase 3b's P3b-03 (edge records and assignment), P3b-04 (the chain rule), P3b-06 (the stroke weight), P3b-07 (the edge tool) and P3b-08 (an edge contributor and section) merged; the hot water piping interview ([its PRD](../hot-water-piping/PRD.md), Q1 to Q13); D4-09 answered.

## Owns

Roadmap 4.4 as the piping PRD scopes it: Pipe Type records, Piping groups linked to a Hot Water System, role and type assignment on edges, the tree by connection or explicit parent, the recirculation sum, the schedule, the Colour-by mode, the section that adds trunks and recirculation elements to the required hot water objects before attach (D4-09), and the Hot-water piping subtab of Systems. Planned in full as its own run of stages (types, draw and assign, tree and schedule, export, screen) inside this packet's ledger when its interview closes.

## Reuses

Phase 3b's edge store, target, chain rule (moved to `core/` here, 3b's handoff), edge tool and contributor shape; P4-06's section; the `length` quantity and units Q2 for nominal pipe sizes.

## Planned in full when

Its interview is recorded in the [equipment PRD](../equipment/PRD.md) and its decisions, if any,
are added to [DECISIONS](../DECISIONS.md). The full document then follows the shape of
[P4-06](p4-06-hot-water-records-and-export.md) and [P4-07](p4-07-hot-water-view.md): scope, steps,
source, tests first, host gate, out of scope, done condition. Its register row in
[ACCEPTANCE](../ACCEPTANCE.md) is filled in the same change. Until then this stage is not
authorized and has no steps.
