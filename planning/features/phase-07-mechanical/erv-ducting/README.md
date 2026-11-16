# ERV ducting

Build Duct Types, draw ducts as plain SketchUp lines, select them, assign a type. Each duct run
belongs to one Ventilator and is either its outdoor-air side or its exhaust-air side. New work:
the predecessor held this as a discovery brief, M2.

## Read order

1. [`context/TECH_STACK.md`, "Edge-owned assignments"](../../../../context/TECH_STACK.md#edge-owned-assignments):
   the edge tagging rules Phase 3b built.
2. [hot-water-piping PRD](../hot-water-piping/PRD.md). This packet is its smaller sibling and
   reuses its draw and assign behavior and its table of what `main` and Phase 3b supply.
3. [PRD.md](PRD.md), then [STATUS.md](STATUS.md).

## What this packet needs from elsewhere

- The Ventilator record from [equipment](../equipment/README.md), family 1. A duct run with no
  Ventilator cannot export.
- Phase 3b's edge records, stroke weight, edge tool and edge export contributor, on `main`
  (P3b-03, P3b-06 to P3b-08), through hot-water-piping. Ducting needs no chain rule: only the sum
  of a run's lengths matters.
- [metr-export](../../unscheduled/metr-export/README.md) for the duct list and `lassVU`.

## Scope

In: Duct Type records, a Ducting group linked to a Ventilator, direction, measured length, a
schedule, a Colour-by mode, export to HBJSON.

Out: duct sizing, pressure drop, routing, room-side distribution ducts, Space airflows (those
belong to [spaces](../../../archive/phase-03a-spaces/README.md)), the Ventilator record itself
([equipment](../equipment/README.md)), METr conversion.
