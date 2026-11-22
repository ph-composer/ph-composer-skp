# PG10: The Program export, host sitting

DATE: 2026-11-21
STATUS: Four rows pass and one fails on the installed RBZ: the PHX round trip drops the Apartments' interior lighting device. The Comfort section and Locate in the panel are still owed.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: [#538](https://github.com/ph-composer/ph-composer-skp/issues/538)

Run in the second part of the Phase 4a batched host sitting, on branch `acceptance/phase-06-sitting` at `08a06474`,
with no computer-use card. The development bridge drove the rows and read them back, and System Events pressed the
native Edit-menu items. Raw logs, the exported HBJSON and the PHX output stay in
`_private/host/phase06-sitting-20261121/PG10/`.

| | |
| --- | --- |
| Host | SketchUp 26.1.188, Ruby 3.2.2, macOS 26.7.1 |
| Build | `dist/ph_composer.rbz` from `08a06474`, sha256 `4f3f3d66d2e3efd7702fa52191b8145492230102dcbd796ccec182fcd38a4cfe` |
| Fixture | A fresh copy of the five journeys, sha256 `218e83474a8b0d410b2836ae54fdca954f2207059ccfa477b57a0081e9a5b0d7`, the only document in a fresh process |
| Reference | `tests/program_export_test.rb`'s House, Apartments and School, built through public operations on box Zones of the test's sizes, with one Space per Zone |
| Read-back | PHX 1.59.1 over honeybee-ph 1.33.68, the repository's `phx` group. The hand values are those of `tests/python/test_program_phx_round_trip.py`, applied to the drawn boxes |

| Assertion | Result | What was observed |
| --- | --- | --- |
| PG10/preflight-warnings | Pass | No blocking row. The preflight lists two `programs.set_points_disagree` rows (School 20/26 °C, Apartments 18/26 °C) and `programs.equipment_set_non_residential` for Lab, whose Locate names only Lab |
| PG10/export | Pass | The export completes with nine Rooms and three BldgSegments |
| PG10/phx-roundtrip | **Fail** | Units, occupants and bedrooms read back as the hand values in both files: House 1/4/3, Apartments 3/6/3. So do set points, q50, the School's ventilation and lighting, no School devices and the House's 9 devices. Apartments reads 10 devices, not 11: the interior lighting device is missing. See below |
| PG10/value-cleared-blocks | Pass | Clearing Classroom's people per area blocks with `programs.value_missing`, and its Locate names Classroom. The export then fails with that code and writes no file |
| PG10/native-undo-redo | Pass | Edit > Undo of the Program edit restores the value and unblocks the preflight. Edit > Redo clears it and blocks again |
| PG10/panel-comfort-section | Owed | The Comfort section was not opened. It needs background control or Ed at the mouse |
| PG10/panel-locate | Owed | Locate opening the Zones / Programs view was not driven. Only the command and its Zones were read |

## The failure

In the HBJSON the installed RBZ wrote, Apartments' Rooms come in this order: Corridor (on Common, a Program with no
lighting rule), Apt 1, Laundry, Apt 2. The offline golden has Apt 1 first. PHX 1.59.1 converts the host file to 10
Apartments devices, with no interior lighting (WUFI type 14). As a diagnostic, a copy of the same file with Apt 1
moved to the front of `rooms` converts to 11 devices, the interior lighting among them. Which Room comes first in a
Segment therefore decides whether its interior lighting device reaches WUFI-Passive. The offline round trip passes
only because of its golden's room order. This sitting does not fix it; the owner is the conductor.

## Limits

- The export approval was a labelled development stand-in for the Export tab (`ApprovedLocations.approve`), revoked
  after each export.
- Each journey Space is the Zone's floor less a 0.1 m inset, unlike the test's whole-floor Spaces. The PHX values
  checked here (counts, set points, devices, School ventilation from box floor and volume) do not depend on it.
