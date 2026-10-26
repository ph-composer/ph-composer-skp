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
