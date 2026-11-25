# P4-14e: ducting export

DATE: 2026-11-24
STATUS: Merged to main 2026-11-25 (#587, squash `dc3792e8`); offline evidence in [p4-14e-ducting-export](../evidence/p4-14e-ducting-export.md), host case `M14e` owed to MS3; corrections recorded under "Recorded at implementation". Planned in full 2026-11-24 from [P4-14](p4-14-erv-ducting.md), D4-09, D4-25, D4-37 (Q4, Q6) and the [ducting PRD](../erv-ducting/PRD.md), "Export mapping". The quantity bullet was built as inferred, at the conductor's direction, and still waits on Ed's answer to P4-14's quantity inference. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M14e` runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-14d. Owns:

- The export contributor `ph_composer.ducting.export.ducting`, its preflight rows and its extraction, worked out in
  pure Ruby from the snapshot by P4-14d's functions (F35).
- The Python `DuctingSection`, which requires the ventilation section and, in `translate`, appends each Ventilator's
  `PhDuctElement`s to every (Ventilator, Zone) `PhVentilationSystem` before the ventilation section attaches them
  (D4-09).
- `conformance`, and a PHX round trip in the `phx` test group (D4-25).
- Re-verifying the ducting classes against the pinned wheel.

Behavior owner: the [ducting PRD](../erv-ducting/PRD.md), "Export mapping". Names: CONTRACTS section 4's "Ducting
section" row and section 6, made exact in step 7. Pattern: P4-13d, the first section to add to another section's
required objects (`features/piping/export.rb`, `python/ph_composer_translation/piping_sections.py`,
`contract/piping_records.py`).

Review: `gpt-6.2-sol` by the brief's rule, since the section follows P4-13d's settled shape and changes neither the
ventilation section's attach shape nor `core/`; the conductor may take `gpt-6-astra`, since this is serialization.

Paths are relative to `src/ph_composer/`.

## What the sources settle

- The snapshot holds every Edge outside a cutting component with world SI endpoints and dictionaries, and every Group
  with its dictionaries, so the contributor needs no snapshot change (P4-13d, "What the sources settle").
- The coordinator runs every `translate` before any `result_fields`, so the ventilation section's rows are taken
  after this section appends; a section with `attaches = None` puts its objects nowhere; a required section whose
  object fails keeps the canonical model unwritten (P4-13d).
- P4-04's `VentilationSection` builds one `TranslatedVentilation` per (Ventilator, served Zone) pair, each with its own
  `PhVentilationSystem` carrying identifiers derived from the Ventilator's id, and attaches it with
  `set_ventilation_system` (`python/ph_composer_translation/mechanical_sections.py`).
- The wheel and PHX facts in [P4-14](p4-14-erv-ducting.md#what-the-sources-settle-for-every-sub-stage): the adders
  append with no `duct_type` check; on reload two Rooms' systems with one identifier must have equal dictionaries;
  PHX reads each Room's ventilation systems through its Spaces, builds one device per system key and keys ducts by
  identifier; `PhxDuctElement.quantity` is 1.

## Inferred in planning

- **One extraction record per Ventilator with ducts**: `{id, ventilator_id, supply, exhaust, supply_length_m,
  exhaust_length_m}`, each element `{identifier, display_name, duct_type, segments}`, each segment `{identifier,
  display_name, points_m, diameter_m, width_m, height_m, insulation_thickness_m, insulation_conductivity,
  insulation_reflective, user_data}`. The millimetres divide by 1,000 in Ruby (F35, D4-09), so Python passes values
  through; a Round type writes its diameter and null width and height, a Rectangular type its width and height and
  honeybee-ph's 0.160 diameter, which `shape_type` then ignores. A bare Duct Type with no conductivity and no
  insulation writes 0.04, never a null, as piping's does.
- **Quantity** (P4-14, for Ed): a run of quantity N writes N elements. The first takes the run's identifier and name;
  copies 2 to N take the identifier with `-2` to `-N` and the name with "(2 of N)" to "(N of N)", and their segments'
  identifiers the same suffix. So N group copies and quantity N export alike, and `supply_length_m` and
  `exhaust_length_m` are P4-14d's lengths, quantity applied.
- **The contributor requires** `ph_composer.mechanical.export.ventilation` (its projection gives every exported Zone
  with its Serves slots, `ExportZones.read`) and the Zones section (groups a Zone holds). Ducting may name
  mechanical; mechanical gains nothing.
- **Blocking findings** are P4-14d's blocking codes; the section is not written while one holds. **Notes**: P4-14d's
  warnings, and `ducting.ventilator_unexported` when a Ventilator with ducts serves no exported Zone, so its ducts go
  nowhere.
- **`required_for_export = True`**, as piping's: a partial failure would leave one Ventilator's Rooms unequal and the
  reload refusing them.
- **Identical ducts on every (Ventilator, Zone) object**, built once per object from the same record, never one
  shared instance; elements and segments added in identifier order, so Ruby, the translated system and the reloaded
  one agree (P4-13d, "Recorded at implementation").
- **Metadata.** A duct assignment's `user_data` goes to its segment's `user_data` (each copy's too). A Ducting group's
  and a Duct Type's maps have no object of their own and are left out with `export.metadata_omitted`; rows in
  `docs/USER_DATA.md`.
- **No report section.** The schedule is the review surface.

## Steps

1. **Verify the wheel (first).** In `src/ph_composer/vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl`, confirm
   `PhDuctSegment`, `PhDuctElement` and the two `PhVentilationSystem` adders as P4-14's table has them, and that
   `PhDuctElement` still has no quantity. Cite the wheel path in the evidence. If the wheel was bumped and a quantity
   carrier exists, stop and report: the quantity bullet changes first.
2. **The extraction.** `features/ducting/export.rb`: the contributor, section version 1, `requires:` as above,
   reading the snapshot's group and edge entries through P4-14d's scan adapter and runs, `result:` rows declared
   with `Export::Privacy.fields`, `user_data_keys`. `ducting.ventilator_unexported` added to `codes.rb`.
3. **Preflight.** `ph_composer.ducting.export_preflight`: P4-14d's findings live, each with its `locate`, plus
   unreadable records as blocking rows, the same codes, sections and objects as the export's notes.
4. **Python.** `contract/ducting_records.py` (`DuctingRecord` and its parts, read strictly) and
   `ducting_sections.py`: `DuctingSection` with `requires = (Requirement(VENTILATION_SECTION_ID,
   TranslatedVentilation),)`, `attaches = None`; `translate` takes `inputs.all(...)` for the record's Ventilator,
   builds each `PhDuctSegment` (a `LineSegment3D` from the metre points) and `PhDuctElement` with its `duct_type`, and
   appends with `add_supply_duct_element` and `add_exhaust_duct_element`; a Ventilator with no ventilation object
   gives an empty object and the note. Registered in `composition.py` after the piping section.
5. **Conformance.** Per reported Ventilator and each Room whose ventilation system carries its identifier: every
   element of `supply_ducting` has `duct_type` 1 and every element of `exhaust_ducting` 2; each element's identifier,
   segment count, length to 0.001 m, shape and dimensions against the rows; `supply_ducting_total_length` and
   `exhaust_ducting_total_length` equal `supply_length_m` and `exhaust_length_m` to 0.001 m; no Room's system holds
   an element the run did not report. The ventilation section's own `conformance` still passes.
6. **PHX round trip (D4-25).** `tests/python/test_ducting_phx_round_trip.py`, `phx` group, skipped without it.
7. **Documents.** `context/CONTRACTS.md` ("Translation sections and artifacts": the second section adding to
   another's required objects), the packet CONTRACTS (section 4's ducting row made exact, section 6's section and
   codes), `docs/USER_DATA.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/piping/export.rb`, `python/ph_composer_translation/piping_sections.py`, `contract/piping_records.py` | The contributor, section and records' shape |
| `python/ph_composer_translation/mechanical_sections.py` (`VentilationSection`, `TranslatedVentilation`), `coordinator.py`, `sections.py` | The objects this section appends to; the digest timing |
| `features/mechanical/export.rb`, `export_zones.rb` | The exported Zones |
| honeybee-ph `honeybee_phhvac/ducting.py`, `ventilation.py`, `properties/model.py` (pinned 1.33.68) | The carrier classes and the reload rule |
| PHX 1.59.4 `from_HBJSON/create_variant.py`, `create_hvac.py` (`build_phx_duct`), `model/hvac/collection.py` | What the round trip asserts |

## Tests (write first)

1. Ruby (`tests/ducting_export_test.rb`): the [ERV ducting case](../ACCEPTANCE.md#erv-ducting-case-p4-14)'s facts give
   one record for ERV-1 (one supply element of two round segments, 2.500 m; one exhaust element, 1.800 m) and one for
   ERV-2 (one rectangular supply element, 2.500 m; two exhaust elements of 1.500 m from quantity 2, identifiers with
   and without `-2`), values in metres; each blocking finding keeps the section unwritten and appears in the
   preflight with the same code, section and object; a Ventilator with ducts serving no exported Zone gives
   `ducting.ventilator_unexported`; `user_data` reaches its segment. The golden `tests/fixtures/ducting/extraction.json`
   feeds the Python tests.
2. Python (`tests/python/test_ducting_sections.py`): the records append to Room A's and Room B's ventilation systems;
   the HBJSON reloads with each carrying them; in the shared case both Rooms carry DG-1's elements with equal
   identifiers and the reload does not refuse; the two total lengths equal the Ruby values; `conformance` refuses a
   Room whose element differs, a supply element with `duct_type` 2, a Room missing a reported element and a Room
   holding an unreported one.
3. A failing `translate` (test seam) gives `object.unavailable`, blocking (D4-06).
4. PHX round trip: the base case gives two ventilation devices, ERV-1's two ducts and ERV-2's three, each with its
   ventilator's id number and its diameter, width, height and insulation in PHX's millimetre properties; the shared
   case gives one device and DG-1's two ducts once; a Ventilator on a Room with no Spaces gives no device and no
   ducts.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M14e` on the installed RBZ and the reference model with the ERV ducting
case: export, reload the exact HBJSON in the pinned honeybee stack and find each run under the right Room's
ventilation system with its lengths in metres; delete ERV-2 with null and see the export refuse with
`ducting.group_unlinked` and its Locate, which opens DG-2 and selects that run's ducts; save, reopen and re-export give the same HBJSON. Offline `make ci` and the PHX
round trip pass on this sub-stage's PR.

## Out of scope

METr's duct list and `lassVU` (metr-export). Screens (P4-14f).

## Recorded at implementation (2026-11-25)

- **The snapshot read is the layer's.** Piping's export read the snapshot's group and Edge entries, decided
  `in_zone` and `shared`, captured claims per occurrence and refused unreadable records itself; none of it names
  piping. It moves to `line_groups/export_scan.rb` (`LineGroups::ExportScan.edges`), with the preflight's unreadable,
  Locate and metadata rows, and both features call it with their spec. Piping's tests and goldens are unchanged but
  for the empty ducting section every extraction golden gains.
- **Python helpers moved down.** `whole` and `bounded` move from `contract/piping_records.py` to `contract/`, and
  the result-row and length helpers from `piping_sections.py` to `conformance.py` (`result_rows`, `same_length`), so
  ducting imports nothing of piping's.
- **Notes only once ducts exist.** As piping's, a Model with no ducts writes no record, reads no Duct Type and notes
  nothing, so a Model whose served Ventilators have no ducts gains no `ducting.run_missing` notes in its export; the
  schedule still shows them.
- **`ducting.run_missing` in the export** is noted for each existing Ventilator an exported Zone names, under the
  Ventilator id, the served set read from the Ventilator section's ExportZones (export) and the live Serves read
  (preflight), so the two agree. A Ventilator serving only a left-out Zone gets `ducting.ventilator_unexported`
  instead.
- **Result fields** carry each element's insulation beside its shape and sizes, and each Ventilator's
  `system_identifier`, which conformance finds the reloaded Rooms by.
- **Locate on `ducting.group_unlinked`** opens DG-2 and selects that run's ducts, as piping's group findings do
  (conductor decision on P4-14d's question, 2026-11-25; D4-30, the shipped pattern). ACCEPTANCE's case row and
  P4-14f's host case are worded to match. For Ed.
- **The quantity bullet stands as inferred** (P4-14, "Inferred in planning"): a run of quantity N writes N elements,
  and the copies' identifiers and names differ from N pasted groups', whose runs digest their own paths; lengths and
  element counts agree. Still for Ed, with a consequence: a quantity is at most 10,000 (P4-14d), and every element is
  written once per served Room, so a large quantity multiplies the HBJSON.

## Done when

- M14e has offline evidence in `../evidence/p4-14e-ducting-export.md`, with the wheel citation.
- `make ci` passes on both Rubies; the vendor and runtime manifests are refreshed; the installed size is recorded
  against the 30 KB estimate and the headroom rule in P4-14, "Size".
