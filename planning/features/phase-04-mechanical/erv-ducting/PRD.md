# ERV ducting

DATE: 2026-10-21
STATUS: Requested. Draft, not interviewed. Re-baselined against `main` at `420c783a` on 2026-10-21.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## Problem

The ducts between an ERV and the outside wall carry outdoor-temperature air through the
conditioned space. Phius counts their heat loss from length, size and insulation, and it lowers
the effective heat recovery. The inputs are two short runs per ventilator. They are easy to
draw over the model and tedious to measure any other way on a building with forty units.

## What main and Phase 3b supply

The same table as [hot-water-piping](../hot-water-piping/PRD.md#what-main-and-phase-3b-supply),
read at the same head: the snapshot's Edge entries exist; the edge store, chain rule, stroke
weight, edge tool and edge contributor are Phase 3b stages P3b-03 to P3b-08, none authorized;
select then Assign is the primary route and the edge tool the secondary one. This packet adds:

| Need | State | Where |
| --- | --- | --- |
| The Ventilator record and its `PhVentilationSystem` at export | [equipment](../equipment/README.md), family 1 | Not started. A duct run with no Ventilator cannot export |
| Duct dimension and insulation displays | Partly | `length` exists; duct diameter, width, height and insulation thickness in inches are the units packet's [ducting row](../../cross-phase/units/STATUS.md) |
| METr | Deferred | PHX is not in the pinned wheels; `lassVU` and the duct list are [metr-export](../../unscheduled/metr-export/README.md) rows |

The predecessor's M2 brief (`../../ph-navigator-sketchup/planning/phases/M2_ducting.md`) still
applies: no duct design, no pressure drop, no routing.

## Vocabulary

Proposed. `context/UBIQUITOUS_LANGUAGE.md` is not changed until the interview.

| Term | Meaning |
| --- | --- |
| Duct Type | A named duct specification: shape, size, insulation. Model-local and reusable |
| Duct | One drawn SketchUp edge that carries a Duct Type |
| Duct-Segment | honeybee-ph's `PhDuctSegment`. Always qualified. One per Duct at export |
| Duct run | The Ducts of one direction in one Ducting group. One `PhDuctElement` at export |
| Direction | Supply or Exhaust. honeybee-ph's `duct_type` 1 and 2 |
| Ducting group | A SketchUp group that holds drawn Ducts and links to one Ventilator |

## What honeybee-ph and METr take

honeybee-ph re-read at the pinned 1.33.65 on 2026-10-21 (`honeybee_phhvac/ducting.py`,
`ventilation.py`). PHX was read on 2026-09-18 and is not in the pinned runtime.

- `PhDuctSegment`: `geometry` (a `LineSegment3D`, required), `diameter`, `height`, `width`,
  `insulation_thickness`, `insulation_conductivity`, `insulation_reflective`. The lengths are in
  metres with no suffix (defaults 0.16 diameter, 0.0254 insulation). PHX's names carry `_mm`.
  PH-Composer records carry `_mm` and the translation converts to metres, which the first draft
  did not say.
- A segment with height and width is rectangular. Otherwise it is round and uses diameter.
- `PhDuctElement`: `display_name`, `duct_type` (1 supply, 2 exhaust), and its segments.
- `PhVentilationSystem` holds `supply_ducting` and `exhaust_ducting` lists, and validates that
  each element's `duct_type` matches the list it is in.
- METr takes ducts as one model-level list in the distribution block. Each duct carries name,
  diameter, width, height, length in m, insulation thickness, conductivity, `quantity`,
  direction, shape, reflective flag, and `lassVU`, the ids of the ventilators it serves. PHX
  reduces a run of mixed segments to length-weighted values, so one run is one METr row.

## Records

```
DuctType        id (dct_), name, notes, datasheet_links, source,       (the common set)
                shape, diameter_mm, width_mm, height_mm,
                insulation_thickness_mm, insulation_conductivity_w_mk,
                insulation_reflective, color, schema_version

duct assignment duct_type_id, direction, schema_version                (on the Edge)

Ducting group   ventilator_id, schema_version                          (on the Group)
```

`shape` is `Round` or `Rectangular`. A Round type holds a diameter and blank width and height.
A Rectangular type holds the reverse. Timestamps from the first draft are gone, as in equipment.

## Behaviors

Draw, Assign, the schedule and the Colour-by mode work as in hot-water-piping, with these
differences.

- "New Ducting group" asks for the Ventilator it serves.
- Assign sets a Duct Type and a direction. There is no tree and no parent. Connection between
  lines does not matter, only the sum, so the chain rule is not needed here.
- A Ventilator's row in the Systems > Equipment subtab shows its two duct lengths, so a missing
  run is visible where the ventilator is edited. Equipment reads that through a declared
  dependency on this feature's published read, or this feature contributes a column; which, is
  Q9.
- A Ducting group may be copied with its Ventilator link intact. Forty identical units need one
  drawn pair and either forty copies or a quantity. Q4 chooses.

### Validation rows

| Finding | Severity |
| --- | --- |
| Duct with no Duct Type, or a deleted one | Blocks export |
| Duct with no direction | Blocks export |
| Ducting group with no Ventilator, or a deleted one | Blocks export |
| Ventilator with no supply run or no exhaust run | Warning. METr will assume none |
| Duct Type with insulation thickness but no conductivity | Blocks export |
| Round type with no diameter, Rectangular type missing width or height | Blocks export |

### Export mapping

| PH-Composer | honeybee-ph |
| --- | --- |
| Duct, one line | `PhDuctSegment` with the type's fields converted to metres and the line as `geometry` |
| Duct run | `PhDuctElement` with `duct_type` from direction |
| Supply run | Appended to the Ventilator's `PhVentilationSystem.supply_ducting` |
| Exhaust run | Appended to `exhaust_ducting` |

The same open plan item as piping: the ducting section `requires` the equipment section and adds
its elements to the translated `PhVentilationSystem` before assembly attaches it to the Rooms.
Settle once, for both.

## Decisions for the interview

Recommendations changed on 2026-10-21 are marked; Ed has answered none of them.

| # | Question | Recommendation |
| --- | --- | --- |
| Q1 | Which ducts are drawn: only the two cold runs between ventilator and exterior, or room-side distribution too? | Only the two cold runs. They are the ones Phius counts. Say so on the tab so nobody traces a whole distribution layout |
| Q2 | Direction words: Supply and Exhaust as honeybee-ph has them, or Outdoor air and Exhaust air? | Match METr's screen. Supply is ambiguous, since room supply air is a different duct. Check METr's words before the interview |
| Q3 | Does direction live on the line or on the Ducting group? | On the line. One group per ventilator with both runs inside is the natural drawing |
| Q4 | Repeated units: copy the group, or a quantity on the run? | Both. A copied group works with no code. A `quantity` field is one number and METr has the field |
| Q5 | Same native Line tool and group rule as piping? | Yes, including piping Q13: Ducting groups outside Zone groups |
| Q6 | Do Ducts belong to a Zone? | No. They belong to a Ventilator |
| Q7 | Are Duct Types a library kind? | Not now |
| Q8 | One primary tab for piping and ducting, two primary tabs, or peer subtabs under a Systems home? | Confirmed in D4: Systems is the primary tab, with Equipment, ERV ducting and Hot-water piping as peer subtabs |
| Q9 | Code. Added 2026-10-21. How does the Ventilator's row show its duct lengths without equipment naming ducting? | Equipment requires nothing of ducting. Ducting, which requires equipment, contributes the two length columns to the Ventilator table through the shipped table contributions contract (`html/table_contributions.js`), as the Zone views contract lets Spaces add rows to Zones |

## Non-goals

No sizing, no pressure drop, no fittings, no automatic routing, no room-side layout.

## Acceptance shape

On a synthetic model with two Ventilators: one Round and one Rectangular Duct Type, a supply and
an exhaust run per Ventilator drawn with the Line tool. Schedule lengths match hand measurement.
Delete one Ventilator and see the finding. Export, reload the exact HBJSON in the pinned stack
and find each run under the right ventilation system with its lengths in metres, through the
section's `conformance` check. One Undo per assign. Save and reopen. METr's duct list and
`lassVU` are metr-export's.

## Prior art and evidence

- Predecessor `planning/phases/M2_ducting.md` (`../../ph-navigator-sketchup/`).
- honeybee-ph `honeybee_phhvac/ducting.py`, `ventilation.py`, re-read at 1.33.65.
- PHX `model/hvac/ducting.py`, `to_METr_JSON/metr_schemas.py`, `_PhxDuctElement`, read
  2026-09-18, not in the pinned runtime.
- honeybee-grasshopper-ph "HBPH - Create Ventilation Duct".
