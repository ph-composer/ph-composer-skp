# PG12: The Phase 4a integrated run, host sitting

DATE: 2026-11-21
STATUS: Sixteen rows pass and two fail on the installed RBZ across the three reference models. Apartments is missing its interior lighting device, and an attached zone repeats the House's devices. The panel's views and dialogs are still owed (Ed at the mouse or background control).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the second part of the Phase 4a batched host sitting, on branch `acceptance/phase-06-sitting` at `08a06474`,
with no computer-use card. Case `PG12` was added to the [case ledger](../../../native-acceptance/cases.json) for this
run. Each model ran in a fresh process. Per model, one step per feature went through a public operation, and each
step was undone and redone from the native Edit menu (pressed through System Events). The state was read through the
bridge after each press and compared whole with the state before and after the step. Each model was then exported,
and its WUFI XML and METr JSON were checked against hand values, including each WUFI Zone's devices. This is the case's
second run. The first asserted no devices, and a device read after it finished found the two failures below; its
ledger row is superseded by this one. Raw logs stay in
`_private/host/phase06-sitting-20261121/PG12/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixtures | Fresh copies of the three synthetic reference models, each the only document in a fresh process: House `fdfb756b…6850fe` (the case's recorded fixture), Apartments `0ddf6c71…6093e2`, two Segments `70e5bd6e…578eb` |
| Read-back | PHX 1.59.1 over honeybee-ph 1.33.68, the repository's `phx` group |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG12/house-segments | Pass | A Segment rename is one step, undone and redone natively |
| PG12/house-settings | Pass | One Settings Save stores the certification, airtightness and occupancy payloads together. One native Undo removes all three, and Redo restores them |
| PG12/house-spaces | Pass | One Space rate is one step, undone and redone natively |
| PG12/house-programs | Pass | A new Program is one step, undone and redone natively |
| PG12/house-export-phx | Pass | Certification 1, 6, 6, 3, 3; n50 1.0; 1 unit, 4 occupants, 3 bedrooms; Living 40 / 0 m3/h, with its blank sibling absent |
| PG12/house-devices | Pass | The House zone holds the default Set's eight devices and the interior lighting, each quantity 1 |
| PG12/apartments-settings | Pass | Single dwelling off and a q50 in one Save, undone and redone natively |
| PG12/apartments-programs | Pass | Six apartments become one Dwelling each in one step, undone and redone natively |
| PG12/apartments-spaces | Pass | One Space's rates make its Zone detailed in one step, undone and redone natively |
| PG12/apartments-segments | Pass | A Zone moved out of every Segment in one step, undone and redone natively |
| PG12/apartments-export-phx | Pass | 6 units, 14 occupants, 8 bedrooms, q50 0.8. The Zones in no Segment are absent |
| PG12/apartments-devices | **Fail** | The default Set's eight devices are there at quantity 6, but the interior lighting device is missing. This HBJSON's first Apartments Room is on a Program with no lighting rule, as in PG10 |
| PG12/two-segments-segments | Pass | ADU Living moved out in one step, undone and redone natively |
| PG12/two-segments-attached-zone | Pass | The offer's Attached zone is created and assigned in one step, undone and redone natively |
| PG12/two-segments-settings | Pass | ADU's certification and q50 in one Save, undone and redone natively |
| PG12/two-segments-occupancy | Pass | House's Single dwelling off makes the House Dwelling in one Save, undone and redone natively |
| PG12/two-segments-export-phx | Pass | ADU Living is House's attached zone in both files (one 18 m2 wall). ADU reads certification 2, 8, 5, 2, 2 and q50 0.6. House reads 3 bedrooms and 4 occupants |
| PG12/two-segments-devices | **Fail** | The House zone holds its 9 devices, but the unheated attached zone ADU Living lists the same 9 again: 18 in the Variant. PHX 1.59.1 adds each Room's devices to every zone of its Variant (`from_HBJSON/create_variant.py`). Whether WUFI-Passive counts them twice was not checked |
| PG12/panel | Owed | The panel's views, the Segment settings dialog, the Programs tab and the preflight were not driven on these models. They need background control or Ed at the mouse |

## Limits

- The ledger row records the House copy as its fixture. The Apartments and two-Segment copies' hashes, which equal
  their fixtures', are in the private run logs.
- The export approval was a labelled development stand-in for the Export tab (`ApprovedLocations.approve`), revoked
  after each export.
