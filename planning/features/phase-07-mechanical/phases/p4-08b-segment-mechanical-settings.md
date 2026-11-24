# P4-08b: Building Segment mechanical settings

DATE: 2026-11-22
STATUS: Planned in full 2026-11-24 from the stub of 2026-11-22, F30, D4-25, D4-26, D4-32 and the [Phase 6 handoff](../../../archive/phase-06-program/STATUS.md#handoff-to-phase-7-mechanical) (C4a-5). Authorized with every stage on 2026-11-23 (STATUS, "Entry gates"). Host gate runs in the MS3 sitting (D4-31).
AUTHOR: Ed May, BLDGTYP, with Claude
ISSUE: #562

Added on 2026-11-22 from the Phase 6 handoff. The finding is [DECISIONS](../DECISIONS.md#part-4-review-after-programs-2026-11-22)
F30; mechanical cooling entered is D4-26 and the summer ventilation fields are D4-32.

## Entry and scope

Requires P4-02 (the feature registers the namespace) and P4-08 (the finding compares the switch with the
blended heat pump's cooling), D4-25, D4-26, D4-31 and D4-32. Stacks on P4-08's branch while #571 is open.

Owns a Mechanical section in the Building Segment settings dialog and its export, through the shipped seam
(`context/EXTENSIBILITY.md`, "Building Segment settings"), unchanged:

- A structured extension on the Building Segment record, `ph_composer.mechanical.segment`, holding mechanical
  cooling (a switch), the mechanical room temperature and the four summer ventilation values D4-32 shows.
- A read of one Segment's values with the defaults applied, `ph_composer.mechanical.segment.get`, as Phius
  certification and Airtightness each have.
- The panel section, registered with `segmentSettingsSection`, after Comfort.
- A non-blocking finding when the switch and the Segment's blended heat pump disagree.
- An export contributor that claims the namespace on the Building Segment kind through `entity_projections`,
  one record per exported Segment, defaults included.
- A Python section at the `SEGMENT` host that sets `set_points.mechanical_cooling`, `mech_room_temp` and four
  `summer_ventilation` fields on the shared `BldgSegment` in place, and nothing else.
- A PHX round trip in the `phx` group (D4-25).

Zones owns the dialog, Save and the Segment record; this stage writes none of them. Programs owns
`set_points.winter` and `.summer`; this stage never sets them.

Pattern: Phius certification (`features/certification/`, `certification_sections.py`), a section that stores
on the Segment, reads with defaults and attaches at `SEGMENT`. Paths are relative to `src/ph_composer/`.

## What the sources settle

Read in the pinned wheel `vendor/wheels/honeybee_ph-1.33.68-py3-none-any.whl`, `honeybee_ph/bldg_segment.py`:

| honeybee-ph attribute | Default | This stage |
| --- | --- | --- |
| `BldgSegment.set_points.mechanical_cooling` | `False` | Entered: a switch, off by default (D4-26) |
| `BldgSegment.mech_room_temp` | `20.0` °C | Entered, 20 °C by default (D4-26) |
| `SummerVentilation.summer_bypass_mode` | `4-Always` | Entered (D4-32); the four `PhVentilationSummerBypassMode` values |
| `SummerVentilation.ventilation_system_ach` | `None` | Entered, blank by default (D4-32) |
| `SummerVentilation.daytime_window_ach` | `0.0` | Entered (D4-32) |
| `SummerVentilation.nighttime_window_ach` | `0.0` | Entered (D4-32) |
| `daytime_extract_system_ach`, `daytime_extract_system_fan_power_wh_m3`, `nighttime_extract_system_ach`, `nighttime_extract_system_fan_power_wh_m3`, `nighttime_extract_system_heat_fraction`, `nighttime_extract_system_control`, `nighttime_minimum_indoor_temp_C` | `0.0`, `0.0`, `0.0`, `0.0`, `0.0`, `1-TEMPERATURE_CONTROLLED`, `0.0` | Not shown and not stored; the section never sets them, so each exported Segment carries the class defaults (D4-32) |

honeybee-ph's defaults are the `SummerVentilation` class's, which a `BldgSegment` carries when nothing sets its
summer ventilation, as F30 reads the Grasshopper Building Segment component. The separate Grasshopper Create
Summer Ventilation component gives two of the omitted fields other values (0.65 Wh/m³ fan powers, 22 °C night
minimum); D4-32 names honeybee-ph's, so this stage exports the class values.

Read in PHX 1.59.4 (`from_HBJSON/create_variant.py`): the Variant's building data takes all three values, the
eleven summer ventilation fields included. Its WUFI XML and METr writers carry the mechanical room temperature
(`MechanicalRoomTemperature`, `mechRT`) and the bypass mode (`SummerHRVHumidityRecovery`, `sumHRec`); neither
writes mechanical cooling, which stays on the Variant object (its PHPP writer reads it). The round trip reads
mechanical cooling there.

## Inferred in planning

None of these is a choice of behavior the sources leave open; each follows the pattern or the code as built.

- Payload field names follow the codebase's naming: `mechanical_cooling`, `mech_room_temp_c`,
  `summer_bypass_mode` (`none`, `temperature_controlled`, `enthalpy_controlled`, `always`, mapped in Python to
  honeybee-ph's `1-None` to `4-Always`), `ventilation_system_ach`, `daytime_window_ach`, `nighttime_window_ach`.
- The section's order is 60: Comfort is 50 (`html/features/programs/occupancy.js`).
- The finding is `mechanical.segment_cooling_mismatch`, a warning that never blocks.
- The comparison reads the Segment's exported blend: cooling is in the blend when the Segment's blend exports
  with recirculation cooling `used`. A Segment with no exported blend (no heat pumps serve it, or Climate is
  incomplete) has none, so the switch on there gives the finding. Blends key by Segment name and settings by
  Segment id; the join goes through the Zones projection row, and only Segments that get a settings record are
  compared.
- The `.get` read follows certification and Airtightness, whose agent recipes read before they write.

## Steps

1. **The extension (D4-26, D4-32).** `features/mechanical/segment/settings.rb`: `NAMESPACE`, the six fields,
   their defaults (`false`, `20.0`, `always`, `null`, `0.0`, `0.0`), the bypass mode values in order, and
   `problems(payload)`: the six fields and nothing else; `mechanical_cooling` true or false;
   `mech_room_temp_c` a finite number; `summer_bypass_mode` one of its values; `ventilation_system_ach` null or
   a finite number of 0 or more; the two window rates finite numbers of 0 or more. `Records::Extension` with
   `schema_version` 1, `export_relevance` `required` and that validator. `values(payload)` and `read(request,
   id)` as certification's. Registered with `feature.extension` in the mechanical feature, with the `.get`
   query. No Zones file names it.
2. **The finding.** A pure function over plain values: each settings record's Segment, its switch, and whether
   its blend cools (`segment/cooling.rb`). One function gives the preflight's rows and the export's notes, the
   same code, section and object (the Segment id).
3. **Export (CONTRACTS section 6).** `features/mechanical/segment_export.rb`: `ph_composer.mechanical.export.segments`,
   claiming the namespace on `Zones::Options::SEGMENT_KIND` from `ph_composer.zones.export.zones`, one record
   per exported Segment record in id order: `{id, export_identifier, name, mechanical_cooling, mech_room_temp_c,
   summer_bypass_mode, ventilation_system_ach, daytime_window_ach, nighttime_window_ach}` with the defaults
   where none is stored. A legacy Zone names no Segment record and gets no record. Its `projection` is the
   records. The heat pump section gains a `projection`, each exported blend's Segment and whether it cools,
   from the same plan its records come from; the Segment section requires it and notes the finding.
4. **Preflight.** `ph_composer.mechanical.preflight` adds the Segment rows over the live Model: exported
   Segments from the Serves Zones, their stored values, and the live heat pump plan's blends.
5. **Python (F29).** `python/ph_composer_translation/mechanical_segment_sections.py`, `MechanicalSegmentSection`
   at `Attachment(SEGMENT)` keyed by the export identifier, `required_for_export = True`. `attach` sets
   `set_points.mechanical_cooling`, `mech_room_temp` and the four `summer_ventilation` fields on the one shared
   `BldgSegment` and touches no other attribute. Result fields per Segment; `conformance` reads the six values
   back from every reloaded Building Segment. Registered in `composition.py` after `SetPointSection`.
6. **The panel section (D4-30).** `html/features/mechanical/segment_settings.js`, registered with
   `segmentSettingsSection("ph_composer.mechanical.segment", {title: "Mechanical", order: 60})`: a checkbox for
   mechanical cooling, the mechanical room temperature in the unit preference's temperature unit, then a
   Summer ventilation group with the bypass mode choice and the three air change rates in 1/h, the ventilation
   system's blank allowed. It follows Airtightness's draft, validate and collect, and the unreadable-payload
   row. Added to `index.html` and the panel manifest; the runtime manifest is refreshed.
7. **Contract and documents.** API minor bump with a `CHANGES` row (the namespace, the read, the export section,
   the code and the preflight rows); `context/CONTRACTS.md` "Translation sections and artifacts" after
   certification's paragraph; `context/AGENT_INTERFACE.md`; `docs/AGENT_GUIDE.md` and the shipped guide, a
   "Mechanical settings" recipe after Airtightness; `docs/PRODUCT.md` step 3 of the Zones workflow;
   `context/UBIQUITOUS_LANGUAGE.md` a Mechanical (Building Segment settings) row; `make fixtures`.

## Source

| PH-Composer file | Disposition |
| --- | --- |
| `features/certification/`, `python/ph_composer_translation/certification_sections.py` | The pattern, unchanged |
| `features/programs/airtightness.rb`, `html/features/programs/airtightness.js` | The numeric section's validation and parsing, unchanged |
| `features/mechanical/heat_pump_export.rb`, `preflight.rb` | Gain the blend projection and the Segment rows |
| honeybee-ph `honeybee_ph/bldg_segment.py` (pinned 1.33.68) | `BldgSegment`, `SetPoints`, `SummerVentilation`, `PhVentilationSummerBypassMode` |

## Tests (write first)

1. Ruby (`tests/segment_mechanical_test.rb`): a Segment reads the defaults until saved; Save of this section
   with Phius certification changed in the same dialog is one Undo step, and Undo restores both; a partial,
   extra-field, wrong-type or out-of-range payload refuses `validation.failed` and writes nothing; the
   settings go with a deleted Segment.
2. Export: two Segments with opposite switches and different temperatures and summer ventilation, one stored
   and one with none, give one record per exported Segment with the defaults on the unset one; a Segment no
   exported Zone names exports nothing; an invalid stored payload blocks the preflight and the export. The
   golden feeds the Python tests.
3. The finding: the switch on with no heat pump blend, on with a blend that does not cool, off with a blend that
   cools give the warning, never blocking, in the preflight and as an export note; on with a cooling blend and
   off with none give nothing.
4. Python: each record reaches its `BldgSegment`; Programs' winter and summer set points (non-default) are
   unchanged; the seven omitted fields equal a fresh `SummerVentilation()`'s; a Segment with no settings reloads
   with honeybee-ph's defaults; every bypass mode Ruby offers maps to the pinned enum; an unknown mode, or a
   record naming no exported Segment, refuses; conformance reads the six values back.
5. PHX (`tests/python/test_mechanical_segment_phx_round_trip.py`): each Variant carries its Segment's mechanical
   cooling, mechanical room temperature and summer ventilation; the WUFI XML and METr JSON carry the room
   temperature and the bypass mode.
6. JS (`tests/mechanical_segment_panel_test.js`): the defaults on an empty draft, unit conversion of the room
   temperature under IP, the problems that hold Save, and what `collect` sends.
7. Browser: `tools/ui-preview/segment_rows_checks.cjs` opens a Segment's settings and finds the Mechanical
   section after Comfort, at the panel sizes it already checks.

## Host gate

Batched into the `MS3` sitting (D4-31): case `M16`, the Mechanical section's Save in one native Undo step with
the other sections, Redo, save and reopen, and export. Offline `make ci`, browser checks and the PHX round trip
pass on this stage's PR.

## Out of scope

The seven summer extract and night flush fields in the UI (D4-32). Deriving mechanical cooling from the heat
pumps (D4-26). Any change to Zones' dialog, Save or Segment record, or to Programs' set points.

## Done when

- M16 has offline evidence in `evidence/p4-08b-segment-mechanical-settings.md`; the host case is owed to MS3.
- `make ci` passes on both Rubies; the panel and runtime manifests are refreshed.
