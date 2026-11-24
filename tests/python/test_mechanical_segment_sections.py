"""The Building Segment mechanical settings section (context/CONTRACTS.md, "Building Segment settings"): each exported
Segment's mechanical cooling, mechanical room temperature and four summer ventilation values reach the one honeybee-ph
`BldgSegment` its Rooms share, attached at the `segment` host, and nothing else does: the winter and summer set
points Programs wrote stay, and honeybee-ph's other seven summer ventilation values keep their defaults. A Segment
with no settings reloads with honeybee-ph's defaults; a record naming no exported Segment, or holding an unknown
value, is refused."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, cast

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.coordinator import translate
from ph_composer_translation.mechanical_segment_sections import (
    BYPASS_MODES,
    MECHANICAL_SEGMENT_SECTION_ID,
    segment_values,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "segments"
#: Ruby's bypass modes and defaults, written by tests/segment_mechanical_test.rb.
CHOICES = FIXTURES / "mechanical_choices.json"
#: Main with every value entered and Annex with none, on Programs' 19 °C and 26 °C set points; the same test.
EXTRACTION = FIXTURES / "mechanical_extraction.json"
#: The seven summer ventilation values the section never sets.
OMITTED = (
    "daytime_extract_system_ach",
    "daytime_extract_system_fan_power_wh_m3",
    "nighttime_extract_system_ach",
    "nighttime_extract_system_fan_power_wh_m3",
    "nighttime_extract_system_heat_fraction",
    "nighttime_extract_system_control",
    "nighttime_minimum_indoor_temp_C",
)


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(EXTRACTION.read_text()))


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def segments(result: dict[str, Any]) -> dict[str, Any]:
    """Each reloaded Room's `BldgSegment`, by the Room's name."""
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    return {room.display_name: room.properties.ph.ph_bldg_segment for room in model.rooms}


def omitted(segment: Any) -> dict[str, object]:
    ventilation = segment.summer_ventilation.to_dict()
    return {field: ventilation[field] for field in OMITTED}


def test_every_mode_ruby_offers_maps_to_a_value_the_pinned_enum_accepts_and_the_defaults_are_honeybee_phs() -> None:
    stack.load("honeybee_ph")
    module = stack.load("honeybee_ph.bldg_segment")
    choices = json.loads(CHOICES.read_text())
    assert choices["bypass_modes"] == list(BYPASS_MODES)
    numbers = {"none": 1, "temperature_controlled": 2, "enthalpy_controlled": 3, "always": 4}
    for mode, value in BYPASS_MODES.items():
        accepted = module.PhVentilationSummerBypassMode(value)
        assert (accepted.value, accepted.number) == (value, numbers[mode]), mode
    defaults = choices["defaults"]
    expected = {**defaults, "summer_bypass_mode": BYPASS_MODES[defaults["summer_bypass_mode"]]}
    assert segment_values(module.BldgSegment()) == expected


def test_the_ruby_extraction_reloads_with_each_segments_values_and_programs_set_points_unchanged() -> None:
    result = run(document())

    assert result["summary"]["publishable"] is True, result["findings"]
    check(result["canonical_model"], result, SECTIONS)
    found = segments(result)
    assert segment_values(found["Zone A"]) == {
        "mechanical_cooling": True,
        "mech_room_temp_c": 18.5,
        "summer_bypass_mode": "2-TEMPERATURE CONTROLLED",
        "ventilation_system_ach": 0.3,
        "daytime_window_ach": 0.5,
        "nighttime_window_ach": 1.2,
    }
    module = stack.load("honeybee_ph.bldg_segment")
    assert segment_values(found["Zone B"]) == segment_values(module.BldgSegment()), "no settings, the defaults"
    for room in ("Zone A", "Zone B"):
        assert (found[room].set_points.winter, found[room].set_points.summer) == (19.0, 26.0), room
        assert omitted(found[room]) == omitted(module.BldgSegment()), room


def test_a_record_for_no_exported_segment_or_with_an_unknown_value_withholds_the_model() -> None:
    for change in (
        {"export_identifier": "bseg_0000000000000000"},
        {"summer_bypass_mode": "sometimes"},
        {"daytime_window_ach": -1.0},
        {"mechanical_cooling": "yes"},
    ):
        value = document()
        value["sections"][MECHANICAL_SEGMENT_SECTION_ID]["records"][0].update(change)

        result = run(value)

        assert result["summary"]["publishable"] is False, change
        rows = [row for row in result["findings"] if row["section"] == MECHANICAL_SEGMENT_SECTION_ID]
        assert [row["blocks_export"] for row in rows] == [True], rows


def test_a_record_leaving_out_the_ventilation_system_rate_withholds_the_model_and_null_is_accepted() -> None:
    value = document()
    del value["sections"][MECHANICAL_SEGMENT_SECTION_ID]["records"][0]["ventilation_system_ach"]
    assert run(value)["summary"]["publishable"] is False, "a missing key is not a blank rate"

    value = document()
    value["sections"][MECHANICAL_SEGMENT_SECTION_ID]["records"][0]["ventilation_system_ach"] = None
    assert run(value)["summary"]["publishable"] is True


def test_conformance_refuses_a_segment_whose_value_changed_after_assembly() -> None:
    result = run(document())
    hbjson = json.loads(result["canonical_model"]["hbjson"])
    for segment in hbjson["properties"]["ph"]["bldg_segments"]:
        segment["mech_room_temp"] = 25.0
    altered = {**result["canonical_model"], "hbjson": json.dumps(hbjson)}

    try:
        check(altered, result, SECTIONS)
    except ValueError as error:
        assert "mech_room_temp_c" in str(error)
    else:
        raise AssertionError("conformance accepted a changed mechanical room temperature")
