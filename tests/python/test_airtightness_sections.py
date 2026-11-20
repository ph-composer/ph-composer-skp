"""The airtightness section (context/CONTRACTS.md, "Building Segment settings"): each exported Zone's Room takes
the Infiltration flow Ruby converted from its Segment's test result, and the one `BldgSegment` its Rooms share
takes the wind exposure; a Zone whose Segment has no test result keeps its Room's own Infiltration; every wind
exposure Ruby offers maps to a value the pinned honeybee-ph enum accepts; and a record naming the wrong
Segment, an unknown wind exposure or a flow that is not greater than 0 is refused."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ph_composer_translation import stack
from ph_composer_translation.airtightness_sections import AIRTIGHTNESS_SECTION_ID, WIND_EXPOSURES
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from test_certification_sections import run

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "segments"
#: Ruby's values and defaults, written by tests/segment_airtightness_test.rb.
CHOICES = FIXTURES / "airtightness_choices.json"
#: House with an n50 result and ADU with a q50 result, written by the same test.
EXTRACTION = FIXTURES / "airtightness_extraction.json"


def rooms(result: dict[str, Any]) -> dict[str, Any]:
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    return {room.display_name: room for room in model.rooms}


def infiltration(room: Any) -> dict[str, Any] | None:
    """The Room's Infiltration as honeybee stores it, or None: with no Program, a Room has none."""
    load = room.properties.energy.infiltration
    return None if load is None else load.to_dict()  # type: ignore[no-any-return]


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return value["sections"][AIRTIGHTNESS_SECTION_ID]["records"]  # type: ignore[no-any-return]


def test_every_wind_exposure_ruby_offers_maps_to_a_value_the_pinned_honeybee_ph_enum_accepts() -> None:
    stack.load("honeybee_ph")
    exposure = stack.load("honeybee_ph.bldg_segment").PhWindExposureType
    choices = json.loads(CHOICES.read_text())
    assert set(choices["wind_exposures"]) == set(WIND_EXPOSURES)
    for value in WIND_EXPOSURES.values():
        assert exposure(value).value == value
    assert WIND_EXPOSURES[choices["defaults"]["wind_exposure"]] == exposure().value, "the default is honeybee-ph's"


def test_each_room_takes_its_segments_flow_and_the_shared_segment_its_wind_exposure() -> None:
    value = json.loads(EXTRACTION.read_text())
    flows = {row["id"]: row["flow_per_exterior_area"] for row in records(value)}

    result = run(value)

    assert result["summary"]["publishable"] is True, result["findings"]
    check(result["canonical_model"], result, SECTIONS)
    found = rooms(result)
    for room in found.values():
        assert room.properties.energy.infiltration.flow_per_exterior_area == flows[room.identifier]
    assert (
        str(found["Living"].properties.ph.ph_bldg_segment.wind_exposure_type.value)
        == WIND_EXPOSURES["one_side_moderate_screening"]
    )
    assert (
        str(found["ADU"].properties.ph.ph_bldg_segment.wind_exposure_type.value)
        == WIND_EXPOSURES["several_sides_high_screening"]
    )


def test_a_segment_with_no_test_result_keeps_the_rooms_own_infiltration() -> None:
    value = json.loads(EXTRACTION.read_text())
    empty = {**value["sections"], AIRTIGHTNESS_SECTION_ID: {"version": 1, "records": []}}
    plain = rooms(run({**value, "sections": empty}))
    house = [row for row in records(value) if row["basis"] == "n50"]
    for row in house:
        row["flow_per_exterior_area"] = None

    result = run(value)

    assert result["summary"]["publishable"] is True, result["findings"]
    check(result["canonical_model"], result, SECTIONS)
    found = rooms(result)
    assert sorted(row["id"] for row in house) == sorted(found[name].identifier for name in ("Kitchen", "Living"))
    for name in ("Kitchen", "Living"):
        assert infiltration(found[name]) == infiltration(plain[name]), name
    assert infiltration(found["ADU"]) != infiltration(plain["ADU"])


def test_a_record_for_the_wrong_segment_an_unknown_exposure_or_no_flow_withholds_the_model() -> None:
    for change in (
        {"export_identifier": "bseg_0000000000000000"},
        {"wind_exposure": "sheltered"},
        {"flow_per_exterior_area": 0},
    ):
        value = json.loads(EXTRACTION.read_text())
        records(value)[0].update(change)

        result = run(value)

        assert result["summary"]["publishable"] is False
        rows = [row for row in result["findings"] if row["section"] == AIRTIGHTNESS_SECTION_ID]
        assert [row["blocks_export"] for row in rows] == [True], (change, rows)
