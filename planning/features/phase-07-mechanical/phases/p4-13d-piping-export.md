# P4-13d: piping export

DATE: 2026-11-24
STATUS: Merged to main 2026-11-24 (#579, squash `da3303f7`); offline evidence in [p4-13d-piping-export](../evidence/p4-13d-piping-export.md), host case `M13d` owed to MS3; corrections recorded under "Recorded at implementation". Planned in full 2026-11-24 from [P4-13](p4-13-hot-water-piping.md), D4-09, D4-06, D4-18, D4-25, D4-36 and the [piping PRD](../hot-water-piping/PRD.md), "Export mapping" and "Acceptance shape". Scoped. Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host case `M13d` runs in the MS3 sitting (D4-31). Stronger review lane: it adds to the Hot Water System's objects before attach (D4-09), the first section to do so.
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

## Entry and scope

Requires P4-13c. Owns:

- The export contributor `ph_composer.piping.export.piping`, its preflight rows and its extraction, worked out in pure
  Ruby from the snapshot by P4-13c's functions (F35).
- The Python `PipingSection`, which requires the hot water section and, in `translate`, adds each System's trunks and
  recirculation elements to every (System, Zone) `PhHotWaterSystem` before the hot water section attaches them (D4-09).
- `conformance`, and a PHX round trip in the `phx` test group (D4-25).
- Re-verifying, against the pinned wheel, the piping classes and the calculation-method attribute P4-06 guessed.

Behavior owner: the [piping PRD](../hot-water-piping/PRD.md), "Export mapping". Names: CONTRACTS section 4's "Piping
and ducting sections" row and section 6, extended in step 7. Pattern: the hot water section and contributor
(`features/mechanical/hot_water_export.rb`, `HotWaterSection`), and Phase 3b's P3b-08 for a contributor over snapshot
`edge` entries.

Review: the strong lane, `gpt-6-astra`, with the architecture rubric: the first section that mutates another
section's required objects.

Paths are relative to `src/ph_composer/`.

## What the sources settle

- The snapshot already holds what the contributor needs: an `edge` entry for every Edge outside a cutting component,
  with world SI endpoints, vertex ids and dictionaries, and a `group` entry for every Group with its dictionaries, so
  a Piping group's record and its Edges' assignments reach the contributor without a snapshot change
  (`export/geometry_snapshot.rb`, `GeometrySnapshot.walk`).
- The coordinator orders sections by their requirements, runs every `translate`, assembles, and only then calls each
  section's `result_fields` (`python/ph_composer_translation/coordinator.py`, `translate`). So the hot water rows'
  digest of each `PhHotWaterSystem` is taken after this section adds its pipes, and the hot water `conformance`,
  which compares each reloaded Room's system with its own row's digest, catches a Room whose pipes differ. Every
  (System, Zone) object of one System must therefore get identical pipes (CONTRACTS section 8, question 2).
- A section with `attaches = None` puts its objects nowhere (`sections.py`); its work is the mutation. A section
  `required_for_export` whose object fails keeps the canonical model from being written.
- The wheel and PHX facts in [P4-13](p4-13-hot-water-piping.md#what-the-sources-settle-for-every-sub-stage): the public
  `add_distribution_piping` and `add_recirc_piping` key by identifier; an element's segments must share a material;
  PHX keys trunks and recirculation elements by identifier across Rooms, reads them only through a Room's Spaces, and
  takes tap points from the last Room read and recirculation temperature and hours from the Rooms' set.
- At 1.33.68 `PhHotWaterSystem` has no calculation-method attribute of any name (read 2026-11-24 in
  `honeybee_phhvac/hot_water_system.py` of the vendored wheel), so P4-06's `CALC_METHOD_ATTRIBUTE =
  "piping_calc_method"` still matches nothing and `mechanical.method_not_exported` stands. honeybee_ph#135 is open
  (read 2026-11-24).

## Inferred in planning

- **One extraction record per Hot Water System with pipes**: `{id, system_id, trunks, recirculation}`, a trunk
  `{identifier, display_name, multiplier, demand_recirculation, segments, branches}`, a branch `{identifier,
  display_name, segments, twigs}`, a twig or recirculation element `{identifier, display_name, segments}`, a segment
  `{identifier, display_name, points_m, material, diameter_mm, insulation_thickness_mm, insulation_conductivity,
  insulation_reflective, insulation_quality, water_temp_c, daily_period, user_data}`. Distribution segments carry
  honeybee-ph's 60.0 and 24 (P4-13); recirculation segments their assignment's values.
- **The contributor requires** `ph_composer.mechanical.export.ventilation`, whose projection gives every exported Zone
  with its Serves slots (`ExportZones.read`), to know which Systems serve an exported Zone. Piping may name mechanical;
  mechanical gains nothing.
- **Blocking findings** are P4-13c's blocking codes; the section is not written while one holds, as a missing
  psi-value refuses the thermal-bridge section. **Notes**: P4-13c's warnings, and `piping.system_unexported` when a
  System with pipes serves no exported Zone, so its pipes go nowhere.
- **`required_for_export = True`.** P3b-08 made the thermal-bridge section optional because runs are derived (D3b-20),
  but this section changes a required object: a partial failure would leave one System's Rooms unequal, so a failure
  blocks, as D4-06 has it for equipment.
- **Identical pipes on every (System, Zone) object.** `translate` builds the System's trunks and elements once per
  hot water object, from the same record, so their dictionaries are equal; it never shares one instance between
  Rooms.
- **Metadata.** A pipe assignment's `user_data` goes to its segment's `user_data`, which honeybee-ph round-trips. A
  Piping group's and a Pipe Type's maps have no object of their own and are left out with `export.metadata_omitted`;
  rows in `docs/USER_DATA.md`.
- **Tap points.** A System whose tap points are blank exports honeybee-ph's count of its twigs; one with a value keeps
  it. Nothing here changes P4-06's field.
- **No report section.** The schedule is the review surface.

## Steps

1. **Verify the wheel (first).** In `src/ph_composer/vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl`, confirm
   `PhHvacPipeSegment`, `PhHvacPipeElement`, `PhHvacPipeBranch`, `PhHvacPipeTrunk` and the two `PhHotWaterSystem` adders
   as the table in P4-13 has them, and that no calculation-method attribute exists. Cite the wheel path in the
   evidence. If the wheel was bumped and either differs, or a method attribute exists under a name other than
   `piping_calc_method`, stop and report: P4-06's guess and D4-12's bind change first.
2. **The extraction.** `features/piping/export.rb`: the contributor, section version 1, `requires:
   [Mechanical::VentilationExport::SECTION]`, reading the snapshot's group and edge entries through P4-13c's scan adapter and tree,
   `result:` rows declared with `Export::Privacy.fields`, `user_data_keys`. `piping.system_unexported` added to
   `codes.rb`.
3. **Preflight.** `ph_composer.piping.export_preflight`: P4-13c's findings live, each with its `locate`, plus
   unreadable records as blocking rows, the same codes, sections and objects as the export's notes.
4. **Python.** `contract/piping_records.py` (`PipingRecord` and its parts, read strictly) and `piping_sections.py`:
   `PipingSection` with `requires = (Requirement(HOT_WATER_SECTION_ID, TranslatedHotWater),)`, `attaches = None`;
   `translate` takes `inputs.all(...)` for the record's System, builds `PhHvacPipeSegment` (a `LineSegment3D` from the
   metre points), elements, branches with their twigs as `fixtures`, trunks with `multiplier` and
   `demand_recirculation`, and adds them with `add_distribution_piping` and `add_recirc_piping`; a System with no hot
   water object gives an empty object and the note. Registered in `composition.py` after the hot water section.
5. **Conformance.** Per reported System and each Room whose hot water system carries its identifier: each trunk's
   identifier, multiplier, demand recirculation, drawn length to 0.001 m and branch count, each branch's twig count,
   and each recirculation element's identifier and length, against the rows; and no Room's system holds a trunk or
   recirculation element the run did not report. `recirc_temp` and `recirc_hours` read back equal to the Ruby
   `systems` values P4-13c works out.
6. **PHX round trip (D4-25).** `tests/python/test_piping_phx_round_trip.py`, `phx` group, skipped without it.
7. **Documents.** `context/CONTRACTS.md` ("Translation sections and artifacts": the first section that adds to another
   section's required objects, and why it attaches nowhere), the packet CONTRACTS (section 4's piping row made exact,
   section 6's section and codes), `docs/USER_DATA.md`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/mechanical/hot_water_export.rb`, `export.rb`, `export_zones.rb` | The hot water contributor and the exported Zones it reads |
| `python/ph_composer_translation/mechanical_sections.py` (`HotWaterSection`, `system_fields`), `sections.py`, `coordinator.py` | The object this section adds to; the digest timing |
| `features/thermal_bridges/export.rb`, `python/ph_composer_translation/thermal_bridge_sections.py` | A contributor over snapshot `edge` entries and its section |
| honeybee-ph `honeybee_phhvac/hot_water_piping.py`, `hot_water_system.py` (pinned 1.33.68) | The carrier classes |
| PHX 1.59.4 `from_HBJSON/create_variant.py` (`add_shw_piping_from_hb_rooms`), `create_shw_devices.py` | What the round trip asserts |

## Tests (write first)

1. Ruby (`tests/piping_export_test.rb`): the [piping case](../ACCEPTANCE.md#hot-water-piping-case-p4-13)'s facts give one record for HWS-1 with one trunk
   (multiplier 12), three branches, six twigs and one recirculation element, identifiers as P4-13c's, segment values
   from their Pipe Types; each blocking finding keeps the section from being written and appears in the preflight with
   the same code, section and object; a System with pipes serving no exported Zone gives `piping.system_unexported`;
   `user_data` reaches its segment. The golden `tests/fixtures/piping/extraction.json` feeds the Python tests.
2. Python (`tests/python/test_piping_sections.py`): the record adds one trunk with its branches and twigs and one
   recirculation element to both Rooms' hot water systems; the HBJSON reloads with each Room's system carrying them;
   the hot water digests of the two Rooms are equal; `recirc_temp` and `recirc_hours` equal the Ruby values,
   truncation included; a System with blank tap points reloads `number_tap_points` as its twig count; `conformance`
   refuses a Room whose trunk differs from its row, a Room missing a reported trunk and a Room holding an unreported
   one; the hot water section's own `conformance` still passes.
3. A failing `translate` (test seam) gives `object.unavailable`, blocking (D4-06).
4. PHX round trip: two Rooms with Spaces in one Segment served by HWS-1 give one trunk, each branch and twig once,
   multiplier 12 and demand recirculation as drawn, one recirculation element, recirculation temperature and hours equal
   to the Ruby values; a System on a Room with no Spaces gives no piping, as for pumps.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M13d` on the installed RBZ and the reference model with the [piping case](../ACCEPTANCE.md#hot-water-piping-case-p4-13): export, reload the
exact HBJSON in the pinned honeybee stack, and read the tree on both Rooms' Hot Water System with the right lengths,
materials, diameters, multiplier and the recirculation total; break a branch and see the export refuse with its
Locate; save, reopen and re-export give the same HBJSON. Offline `make ci` and the PHX round trip pass on this
sub-stage's PR.

## Out of scope

The simplified hot water methods (honeybee_ph#135). METr's diameter enum, its `lTruncW` rows and the recirculation
coefficient (metr-export). Screens (P4-13e).

## Recorded at implementation (2026-11-24)

- The canonical HBJSON sorts its keys, so a reloaded system sums recirculation elements and segments in identifier
  order. P4-13c's Ruby read summed in schedule and run order; it now sums in identifier order, and the Python section
  adds every keyed collection in identifier order, so Ruby, the translated system and the reloaded one agree to the
  bit. Runs of 0.1, 0.2 and 0.7 m at 24 h can read 23, as honeybee-ph does.
- The record carries `recirculation_temperature_c` and `recirculation_hours`, which conformance compares with; `id`
  equals `system_id`.
- The contributor also `requires` the Zones section (groups a Zone holds) and the hot water section (it reads the
  Systems first).
- A trunk's or branch's inner element takes the run's identifier and name, and a segment's name is its identifier, so
  no random honeybee-ph identifier reaches the HBJSON. A bare Pipe Type with no conductivity exports 0.04.
- The snapshot keeps no Group definition: a pipe is `shared` when a ComponentInstance holds it or its Edge is reached
  at two paths.
- Test 1 and M13d say "one recirculation element"; the case has two (P4-13c's correction), and the tests follow it.

## Done when

- M13d has offline evidence in `../evidence/p4-13d-piping-export.md`, with the wheel citation; host verification lands
  in `MS3`.
- `make ci` passes on both Rubies; the vendor and runtime manifests are refreshed; the installed size is recorded
  against the 35 KB estimate.
