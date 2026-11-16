# Equipment

Author the mechanical and electrical equipment a Phius model needs and say which Zones each item
serves. Seven families, one packet, interviewed and delivered one family at a time. New work:
the predecessor held this as two discovery briefs, Q1 and B4.

## Read order

1. [PRD.md](PRD.md): what `main` supplies today, the shared shape every family follows, then one
   section per family with its honeybee-ph class and fields, then the decisions.
2. [STATUS.md](STATUS.md). The shared shape, Ventilators and hot water were interviewed on
   2026-10-21; the PRD's decisions table and families 1 and 2 hold Ed's answers.

## Family map

The accepted [definition/context ownership pattern](../../../archive/code-review-refactoring/ZONE_CHILD_PATTERN.md)
guides this feature. Equipment that serves Zones uses an explicit assignment relationship; it is
not a native child Group. Reusable equipment values remain independent, and a higher-level
service composes assignment/copy/delete through owner contracts. Shared-system copy policy remains
for the equipment interview; this reference authorizes no implementation or product-policy change.

| # | Family | honeybee-ph carrier | Unlocks |
| --- | --- | --- | --- |
| 1 | Ventilators | `Ventilator` in a `PhVentilationSystem` | ERV ducting; the balance by ventilator, which this packet owns (Spaces shows balance by Zone only) |
| 2 | Hot water: tanks and heaters | `PhHotWaterSystem`, `PhHvacHotWaterTank`, `PhHvacHotWaterHeater` variants | Hot water piping |
| 3 | Heat pumps | `PhHeatPumpSystem` variants with cooling parameters | |
| 4 | Electric heaters | `PhHeatingDirectElectric` | |
| 5 | Pumps | `PhSupportiveDevice` types 4, 6, 7 | |
| 6 | Fans | An exhaust ventilator, plus a linked `PhSupportiveDevice` type 10 when the electric block is filled (Q6) | |
| 7 | Appliances | `PhEquipment` family as Process loads on the Room (Q12); the Zone loads packet owns the other Room loads | |

The order is a proposal. Families 1 and 2 go first because two other packets wait on them.

## What this packet needs from elsewhere

- Nothing from Phase 3b. Equipment has no edges; it can be planned and started before thermal
  bridges; Ventilators and hot water are interviewed.
- [metr-export](../../unscheduled/metr-export/README.md) for every METr claim: PHX is not in the
  pinned runtime, so acceptance here is HBJSON reloaded in the pinned stack.
- [units](../../cross-phase/units/STATUS.md) Q3 for litres, kBtu/h capacity and W/cfm.

## Scope

In: a record per equipment item, assignment to Zones, an Equipment subtab under Systems with one
family view at a time, validation, export to HBJSON.

Out: data sheet hosting, specification status, procurement tracking, equipment sizing, load
calculations, schedules, METr conversion.
