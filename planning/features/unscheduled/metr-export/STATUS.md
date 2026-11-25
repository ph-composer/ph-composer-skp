# METr export: status

DATE: 2026-09-30
STATUS: Deferred
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## State

Deferred by Ed on 2026-09-20. Carried out of Phase 1 as its own packet on 2026-09-30 so the
A15 row has an owner after the Phase 1 packet is archived.

## Next step

None until Ed schedules it. Then re-scope against available features and interview Q1 to Q4.

## Owed checks from other packets

- **Thermal-bridge quantity (thermal bridges F18, D3b-08), unreproduced.** HBJSON carries each thermal
  bridge's `quantity` as authored (Phase 3b P3b-08). Read from PHX source, not run: PHX writes one METr row
  per thermal bridge with no quantity, and folds quantity into length only when `merge_thermal_bridges`
  reduces two or more bridges sharing group, psi-value and name; a lone bridge with quantity 2 would reach
  METr at quantity 1. Check it here against a real conversion before relying on METr's thermal-bridge rows.
  Run names are distinct per type (D3b-07), so PHX does not merge runs into one row.

### From Phase 7, mechanical (handed over 2026-11-25)

Phase 7 proves what PHX 1.59.4 builds from its HBJSON by a round trip per export stage (its D4-25); the METr
file and its import are this packet's. Owner of every row: this packet, when Ed schedules it; a row naming an
upstream library also needs that library's maintainer. Sources are under
[phase-07-mechanical](../../phase-07-mechanical/README.md).

| Row | What the HBJSON carries | What to check in METr | Source |
| --- | --- | --- | --- |
| Duct `lassVU` | Each (Ventilator, Zone) ventilation system carries the Ventilator's supply and exhaust duct elements; a shared Ventilator's Rooms carry equal identifiers | Each duct row's `lassVU` names its ventilator device once, for one Ventilator on one Zone and for one on several | erv-ducting PRD, "What honeybee-ph and METr take"; P4-14e evidence |
| Pipe diameter enum | A Pipe Type's diameter in mm, one of METr's eight nominal sizes (3/8 in to 2 in) | PHX snaps a run's length-weighted diameter to the nearest enum entry; check a mixed run and each of the eight sizes | hot-water-piping PRD, "What honeybee-ph and METr take"; P4-13a, P4-13d evidence |
| Recirculation heat loss coefficient | Recirculation elements with diameter and insulation; PH-Composer shows no coefficient | The length-weighted coefficient PHX computes, the temperature and hours, and the "all pipes insulated" flag METr reads | hot-water-piping PRD; phases/p4-13-hot-water-piping.md, "Inferred in planning" |
| Distribution pipe temperature and hours | Trunk, branch and twig segments at honeybee-ph's 60 °C and 24 h | Whether METr reads these or only the recirculation values | phases/p4-13-hot-water-piping.md, "Inferred in planning" |
| Shared item | One object per (item, served Zone) pair under the item's identifier (D4-01); PHX makes one device | What METr shows for one Ventilator, Hot Water System, heat pump blend, heater, pump or fan serving several Zones: one row, and which Zones it names | DECISIONS D4-01, F13; the round trips listed in the P4-15 evidence |
| Duct quantity has no carrier | A duct run of quantity N exports as N identical duct elements, copies 2 to N suffixed `-k`; neither honeybee-ph 1.33.68 nor PHX 1.59.4 carries a duct quantity | METr lists N rows of quantity 1, not one row of quantity N. Ed's decision on the export shape is owed (P4-15 evidence, "For Ed") | P4-14e evidence, "Recorded at implementation" |
| Fan exhaust quantity dropped | A Fan's exhaust ventilator carries its quantity; a linked supportive device takes it too | PHX 1.59.4 drops the exhaust ventilator's quantity (a kitchen hood of 3 gave a device of 1), so METr sees one exhaust device per Fan record. Upstream: PH-Tools/PHX | P4-11 evidence, "Departures and choices" |
| Re-export not byte-identical | Noted in P4-13d's review, not reproduced: two Python processes give canonical HBJSON differing in `team` identifiers, `bldg_segments` and list order | Compare a METr file from a re-export by content, not bytes; the hot water systems and piping were identical in P4-13d's comparison | P4-13d evidence, "Review" |
| Cooling over 200 kW | One blended heat pump per Building Segment, unsplit (D4-29); PHX splits it only for WUFI-Passive | That METr takes one system over 200 kW with no cap, as D4-29 assumed | DECISIONS F40, D4-29 |
| Piping calculation method | No field: honeybee-ph's `PhHotWaterSystem` has none until [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135) (open on 2026-11-25); PHX writes `calc_method` to METr at its default | Which method METr receives and which methods read the drawn tree | DECISIONS F14, D4-12; P4-06 evidence |

## Blockers

Ed's scheduling decision. Useful output likely needs Phase 2 Assemblies and a floor-area source.

## Verification

None. Nothing is implemented. B1 conversion evidence is prior art, not acceptance.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-20 | Ed deferred METr exporter development and consumer acceptance. |
| 2026-09-30 | Packet created from Phase 1 acceptance row A15. |
| 2026-10-26 | Thermal bridges P3b-08: the PHX quantity observation (F18) recorded here as unreproduced. |
| 2026-11-25 | Phase 7 P4-15: the mechanical METr rows handed over ("From Phase 7, mechanical"), ten rows, owner this packet. |
