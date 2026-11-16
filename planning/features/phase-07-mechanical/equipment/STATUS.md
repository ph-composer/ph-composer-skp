# Equipment: status

DATE: 2026-10-21
STATUS: Scoped. Shared shape, Ventilators and hot water interviewed 2026-10-21; families 3 to 7 not interviewed; stages tracked in the phase ledger; nothing authorized. Wireframes reviewed 2026-11-15: heat pumps settled (D4-14 to D4-16); Pumps, Fans and Electric Heating have their table shape and columns, their interviews otherwise open.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: none (local planning draft)

## State

PRD drafted 2026-09-18 from Ed's family list, the predecessor's `planning/phases/Q1_equipment.md`
and `B4_ventilation-units.md`, and honeybee-ph's `honeybee_phhvac` and
`honeybee_energy_ph/load` packages. Not interviewed.

Re-baselined on 2026-10-21 against `main` at `420c783a`, after Phases 0 to 3a and 3a1 merged.
The PRD's "What main supplies today" table replaces the port disposition. Changes of substance:
assignment is no longer recommended as fields on the Zone record (Q3); delete-in-use follows the
Assembly delete contract; the balance by ventilator is owned here, since Spaces shipped balance
by Zone with no grouping function; acceptance is an HBJSON reload with a `conformance` check,
METr rows go to metr-export; three questions added (Q10 to Q12). Field lists were re-read
against the pinned wheel, honeybee-ph 1.33.65.

Shared shape interviewed on 2026-10-21: Ed answered Q1 to Q12, each as recommended, with Q6
re-asked after the fan route was traced through honeybee-ph and PHX. The PRD's decisions table is
the interview record. Two findings from the trace changed the PRD: a Fan is an exhaust ventilator
with an optional electric block exported as a linked supportive device, and appliances export as
Process loads, since honeybee-ph marks the electric-equipment route for deprecation.

Ventilators interviewed the same day, V1 to V6, each as recommended: one per Zone enforced,
`sys_type` fixed at 1, two optional fields disclosed, W/cfm in IP, an unventilated Zone warns,
no stored rated flow.

Hot water interviewed the same day, H1 to H7: one system record with tank and heater children,
Electric and three heat pump heaters, a free tank list slotted at export (H3, not as recommended),
operating values on the system, the calculation method waits on a honeybee-ph field, the
Ventilator per-Zone rules, child rows for editing.

The phase was planned in detail the same day: stages P4-01 to P4-15, decisions D4-01 to D4-12
and register M01 to M15 live in the [phase packet](../STATUS.md), the one ledger. This file keeps
the interview state only.

## Next step

Ed answers D4-01 to D4-12 in the [phase DECISIONS](../DECISIONS.md); families 3 to 7 are
interviewed each before its stage (P4-08 to P4-12).

## Blockers

- The remaining family interviews (3 to 7), each before its stage.
- H5: a calculation-method field on honeybee-ph's `PhHotWaterSystem`, read by PHX, before the
  simplified hot water methods can export: [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135), filed 2026-10-21, open. Nothing in the code blocks a start: the foundation,
  record engine, inventory table, Zone views and the Room-attaching export section all exist
  (see the PRD's table).
- Two foundation touches the first stage makes: the Systems tab in `html/index.html` (D4), and
  `honeybee_phhvac` added to the translation's `stack.PACKAGES` and `tests/python/test_imports.py`.
- B4's proof, re-scoped: two Zones with two different ventilators, distinct on two Rooms when the
  exact HBJSON reloads in the pinned stack. One honeybee Room per Zone already holds, so the case
  is simpler than B4 feared. The PHX-to-METr half waits with
  [metr-export](../../unscheduled/metr-export/README.md).
- The attachment shape for an item serving several Zones (PRD, "Export"): settled at planning, not
  at the interview.
- For [metr-export](../../unscheduled/metr-export/README.md), not this packet: PHX reads exhaust
  ventilators and supportive devices through a Room's Spaces, so a Zone with no Space loses them
  in METr (PRD, family 6).

## Verification

None. Nothing is implemented. The fan and appliance routes were read in source (honeybee-ph
1.33.65, PHX `from_HBJSON`, `to_WUFI_XML`, `to_METr_JSON`), not run.

## Ledger

| Date | Event |
| --- | --- |
| 2026-09-18 | PRD drafted. |
| 2026-10-21 | Re-baselined against `main` at `420c783a`: foundation and remote blockers removed, assignment and delete recommendations changed, METr acceptance moved to metr-export, Q10 to Q12 added. |
| 2026-10-21 | Shared shape interviewed: Q1 to Q12 answered as recommended. Fans traced through PHX to WUFI and METr (exhaust ventilator plus supportive device); appliances move to the Process-load route. No implementation. |
| 2026-10-21 | Ventilators interviewed: V1 to V6 answered as recommended. PHX keys a system by identity, requires a unit and skips a Room without one. No implementation. |
| 2026-10-21 | Hot water interviewed: H1 to H7, as recommended except H3 (free tank list, slotted at export). H5 found honeybee-ph has no calculation-method field; upstream issue to file. No implementation. |
| 2026-10-21 | H5 upstream issue filed: [honeybee_ph#135](https://github.com/PH-Tools/honeybee_ph/issues/135). |
| 2026-10-21 | Phase 4 planned in detail; stages, decisions and acceptance moved to the [phase ledger](../STATUS.md). |
