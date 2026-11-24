# P4-08b evidence: Building Segment mechanical settings

DATE: 2026-11-24
Register row: [M16](../ACCEPTANCE.md). Stage: [P4-08b](../phases/p4-08b-segment-mechanical-settings.md).
Base: `feat/phase-07-mechanical-p4-08` at `a9cae5d1` (PR #571, open at branch time); after #571 merged as `d2ba5936`
(identical tree), rebased onto `main`. Branch `feat/phase-07-mechanical-p4-08b`.

Offline evidence only. No SketchUp process was started by this stage. The host case `M16` (in
`planning/native-acceptance/cases.json`: the Mechanical section's Save in one native Undo step with another section,
Redo, the mismatch warning in the Export tab, the export's exact HBJSON reload, save, fresh-process reopen and
re-export) is owed to the MS3 sitting (D4-31); nothing here is host evidence. M16 stays Open.

## What was built

| Step | Where | Note |
| --- | --- | --- |
| 1. Extension and read | `features/mechanical/segment/settings.rb`, `declarations/segment.rb` | `ph_composer.mechanical.segment`, schema 1, `required`: `mechanical_cooling`, `mech_room_temp_c`, `summer_bypass_mode`, `ventilation_system_ach`, `daytime_window_ach`, `nighttime_window_ach`, all six and nothing else, defaults honeybee-ph 1.33.68's (`false`, 20.0, `always`, null, 0.0, 0.0). `ph_composer.mechanical.segment.get` reads one Segment with the defaults, as certification's read does |
| 2. The finding | `segment/cooling.rb`, `codes.rb` | Pure: each settings row's switch against `{Segment name => blend cools}`; `mechanical.segment_cooling_mismatch`, never blocking. No exported blend counts as no cooling |
| 3. Export | `segment_export.rb`, `heat_pump_export.rb`, `export_zones.rb` | `ph_composer.mechanical.export.segments` claims the namespace on the Segment kind, one record per exported Segment record in export identifier order, `{id, export_identifier, name}` and the six values with defaults written out; its `projection` is the records. The heat pump export gains a `projection` (each blend's Segment and whether it cools) and works its plan out once per export (`reader.projection`); the Segment section requires it and notes the finding. `ExportZones::Zone` carries `segment_id` |
| 4. Preflight | `preflight.rb`, `heat_pump_export.rb` | `SegmentExport` is the fourth family; its rows use the live plan memoized per request (`HeatPumpExport.live_plan`), shared with the heat pump rows. A Segment whose payload is not understood gives no warning (the metadata check blocks on it) |
| 5. Python | `python/ph_composer_translation/mechanical_segment_sections.py`, `composition.py` | `MechanicalSegmentSection` at `SEGMENT`, after `SetPointSection`, required for export: sets `set_points.mechanical_cooling`, `mech_room_temp` and the four `summer_ventilation` values, nothing else. Result rows `building_segments`; `conformance` reads the six back |
| 6. Panel | `html/features/mechanical/segment_settings.js`, `mechanical.css`, `index.html` | Mechanical section, order 60, after Comfort: a mechanical cooling checkbox, the room temperature in the unit preference's unit, then under a Summer ventilation line the bypass choice and the three rates in 1/h (the ventilation system's blank allowed). Airtightness's draft, validate, collect and unreadable-payload row |
| 7. Contract | `shell/api.rb` | API 1.94 with one `CHANGES` row |

Docs: `context/CONTRACTS.md` ("Building Segment mechanical settings" after the heat pump export),
`context/AGENT_INTERFACE.md`, `context/UBIQUITOUS_LANGUAGE.md` (Mechanical, Building Segment settings),
`docs/AGENT_GUIDE.md` ("Mechanical settings") and the shipped guide, `docs/PRODUCT.md` (Zones step 3),
`docs/API_REFERENCE.md` (`make fixtures`), the packet CONTRACTS (the code and the section). Runtime and panel
manifests refreshed.

## Departures and choices

- **Inferred in planning** (the stage doc's own list): the payload field names, order 60, the code name, the
  comparison rule (no exported blend is no cooling, joined through the Zones projection by Segment name), and the
  `.get` read following certification and Airtightness.
- **The seven omitted summer ventilation values** stay at the `SummerVentilation` class defaults (0.0 rates, fan
  powers and night minimum, `1-TEMPERATURE_CONTROLLED`), as D4-32 and the Building Segment component give them.
- **Mechanical cooling in PHX.** PHX 1.59.4 copies it to the Variant's building data; neither its WUFI XML nor its
  METr writer carries it (its PHPP writer does). The round trip reads it on the Variant object.
- **Record order.** By the persisted export identifier, then id, not id order alone: a fixture mints new ids on
  each run while an adopted Segment's export identifier holds, so every golden that carries the section is stable.
- **Goldens.** Every extraction golden gains the section's records (`make fixtures`); three tests that list sections
  by hand (`phase_one_export`, `shading_export`, `thermal_bridge_export`) and `tests/python/test_model_sections.py`
  name it. `mechanical_dependency_test.rb` treats `segment/` as the feature's own folder, not an equipment family,
  since it names Zones' Segment kind.

## For Ed's judgment

- **Two sets of summer ventilation defaults.** honeybee-ph's `SummerVentilation` class, which this stage exports for
  the seven values it omits (D4-32), defaults both extract fan powers to 0.0 Wh/m³ and the night ventilation minimum
  indoor temperature to 0.0 °C. honeybee_grasshopper_ph's Create Summer Ventilation component, used only when a
  Grasshopper model wires one in, defaults them to 0.65 Wh/m³ and 22 °C (`gh_compo_io/summer_ventilation.py`, read
  in the local checkout at Honeybee-PH v1.44.0, not in the pinned wheel). Whether the night minimum also governs the nighttime window air changes this stage exposes was not checked. Keep
  the class values, or export the component's: Ed's call; nothing in the code needs it now.

## Tests

- `tests/segment_mechanical_test.rb`: the values and defaults golden; defaults until saved, then Save with Phius
  certification in one Undo step, Undo taking both back; eight refused payloads writing nothing; the settings going
  with a deleted Segment; one record per exported Segment with the defaults on Annex and Spare's values left in the
  Model, owning `tests/fixtures/segments/mechanical_extraction.json` with the default Program at 19 °C and 26 °C;
  the switch against the blend (off while it cools, on with no heat pump, on with a blend that does not cool), each
  a warning in the preflight and the export notes; without the climate, only a switch on is warned and the export
  notes the same row (code, object, message); an invalid payload blocks the preflight and the export and gives no
  warning of its own.
- `tests/python/test_mechanical_segment_sections.py`: every bypass mode Ruby offers maps to the pinned enum and the
  defaults are `BldgSegment()`'s; the extraction reloads with Main's values, Annex at the defaults, Programs' 19 °C
  and 26 °C on both and the seven omitted values at `SummerVentilation()`'s; a record for no exported Segment, an
  unknown mode, a negative rate or a non-boolean switch withholds the model; conformance refuses a changed room
  temperature.
- `tests/python/test_mechanical_segment_phx_round_trip.py`: each Variant's mechanical cooling, room temperature,
  bypass and three rates; 19 °C and 26 °C set points on both; `MechanicalRoomTemperature`, `SummerHRVHumidityRecovery`
  and `IndoorTemperature` in the WUFI XML and `mechRT` and `sumHRec` in the METr JSON.
- `tests/mechanical_segment_panel_test.js`: the section's values and order against Ruby's golden; the defaults, the
  units and the Summer ventilation line; one Save carrying six values with 68 °F sent as 20 °C; the problems that
  hold Save; a typed temperature kept in its unit when the preferences change before Save; air changes in a
  decimal-comma format.
- `tools/ui-preview/segment_rows_checks.cjs`: Mechanical listed after Comfort; each number beside its unit on one
  line; the dialog fitting at 1280 x 800, 420 x 732 and 360 x 520; six values in one Save.

## Gate

`make ci` on Ruby 3.2.2 and on 2.7.2 (`make ci RUBY=$(rbenv prefix 2.7.2)/bin/ruby`), on the tree committed with
this file, each: "Ruby suite, 10 processes: 3409 runs, 47339 assertions, 0 failures, 0 errors, 1 skips"; JS 1195
pass, 0 fail; Python "416 passed, 1 skipped"; hostkit "48 runs, 268 assertions, 0 failures"; "RBZ verified: 768
files, 8879639 bytes, 27322840 bytes installed", 677,160 under the 28,000,000 ceiling (P4-08 left 27,287,391). The
first 3.2.2 run failed on two discovery tests that list the API minor and the installed extension namespaces; both
now name 1.94 and `ph_composer.mechanical.segment`.

Also: `tests/segment_mechanical_test.rb` 8 runs, 195 assertions, 0 failures on both Rubies; `make ui-checks` all 39
scripts exit 0 (`segment_rows_checks.cjs` with the Mechanical step); `uv run --group phx pytest tests/python`: all
pass, 1 skipped (`test_map_borders.py`, PH_COMPOSER_MAP_DATA unset), the PHX round trips 17 executed, 0 skipped
(1 new); `uv run tools/runtime/vendor.py --check` "Runtime verified: 209 assets, 8 wheels, 23024661 bytes".

## Review

Sonnet adversarial read before the gate: no blocking defect, 9 findings. Fixed: the section's `projection` (step 3
says so), a warning beside an unreadable payload in the preflight, a heat pump read refusal duplicated under this
section, the Summer ventilation grouping in the panel, and the missing climate-absent case with preflight and export
parity. The evidence file (this one) was owed. Declined: the Annex defaults test (no stored settings is the case
under test, and Main proves the section runs), extra keys in the Python record (Ruby's validator is the gate, as for
certification), and re-reading typed text after a unit switch with the dialog open (not reproduced then; Codex
reproduced it, below).

Codex gpt-6.2-sol cycle 1 on `87b09829` ([review](https://github.com/ph-composer/ph-composer-skp/pull/572#pullrequestreview-6039785886)):
1 P1, 2 P2, 1 P3, all fixed in the next commit. P1: a room temperature typed under IP was reread in °C when a
preferences snapshot arrived before Save; each typed value is now read as it arrives, in the unit and number format
its field was drawn with, and the draft holds numbers (JS regression test). P2: the air changes now show and read the
number format's decimal (JS test with a decimal comma). P2: the PHX round trip asserts the WUFI XML and METr values by
named Variant. P3: the stage doc now states the export identifier order, and the Ruby test asserts it before the golden
normalises.

Codex gpt-6.2-sol cycle 2 on `e595d10b` ([review](https://github.com/ph-composer/ph-composer-skp/pull/572#pullrequestreview-6039989884)):
6 P2, 2 P3; 7 fixed in the next commit, which merges after the two-cycle cap unreviewed, 1 declined. Fixed: the
shared regional number reader threw on a line separator, leaving an earlier rate in the draft (`unit_numbers.js` now
answers malformed; JS regression); a record leaving out `ventilation_system_ach` read as null (Python now refuses a
missing key; test); the bypass mapping test now holds each mode to its honeybee-ph number; the browser check measures
the dialog's scrolling body and the number-and-unit lines at every panel size; case `M16` undoes the warning edits
before its export; the order rationale names the persisted export identifier; D4-29's row states Ed's confirmation.
Declined: conformance proving a record for every managed Segment, which Ruby guarantees and tests, as certification's
section does.

