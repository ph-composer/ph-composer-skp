"""The Electric Heater section (context/CONTRACTS.md, "Mechanical equipment") over the reference model
tests/mechanical_electric_heater_export_test.rb writes: Zones A and B in Building Segment Main, EH-1 (60%, with
user_data) on both and EH-2 (100%) on Zone A beside it. Each pair builds its own `PhHeatingDirectElectric` under its
heater's id; the exact HBJSON reloads with Room A holding both heaters and Room B one, and the section's conformance
compares each reloaded Room with its own rows' digests, so two Rooms translated unequal under one identifier fail
it."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.coordinator import translate
from ph_composer_translation.mechanical_sections import (
    ELECTRIC_HEATER_SECTION_ID,
    ElectricHeaterSection,
    TranslatedElectricHeater,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "mechanical"
GOLDEN = FIXTURES / "electric_heater_extraction.json"
#: The result fields the Ruby contributor declares, written by the same Ruby test.
RESULT_FIELDS = FIXTURES / "electric_heater_result_fields.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
EH_1 = "ehr_FIXED0000001"
EH_2 = "ehr_FIXED0000002"


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(GOLDEN.read_text()))


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][ELECTRIC_HEATER_SECTION_ID]["records"])


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def heating(result: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Each reloaded Room's heating systems by identifier."""
    return {
        room.identifier: {system.identifier: system for system in room.properties.ph_hvac.heating_systems}
        for room in reloaded(result).rooms
    }


def test_each_pair_builds_its_own_heater_under_its_heaters_id() -> None:
    built = translate(document(), SECTIONS).results[ELECTRIC_HEATER_SECTION_ID].objects
    by_pair = {key: cast(TranslatedElectricHeater, item).heater for key, item in built.items()}
    first, second = by_pair[f"{EH_1}_{ZONE_A}"], by_pair[f"{EH_1}_{ZONE_B}"]
    assert first is not second, "one object per (heater, Zone) pair"
    assert type(first).__name__ == "PhHeatingDirectElectric"
    assert (first.identifier, first.display_name, first.percent_coverage) == (EH_1, "EH-1", 0.6)
    assert first.user_data == {"maker_ref": "EH-1-A"}
    assert first.to_dict() == second.to_dict(), "every object of one heater is equal"
    assert by_pair[f"{EH_2}_{ZONE_A}"].user_data == {}


def test_the_reference_reloads_with_each_room_holding_every_heater_that_serves_it() -> None:
    result = run(document())
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = heating(result)
    assert {room: sorted(systems) for room, systems in by_room.items()} == {
        ZONE_A: [EH_1, EH_2],
        ZONE_B: [EH_1],
    }
    for systems in by_room.values():
        one = systems[EH_1]
        assert (type(one).__name__, one.display_name, one.percent_coverage) == ("PhHeatingDirectElectric", "EH-1", 0.6)
        assert one.user_data == {"maker_ref": "EH-1-A"}
    assert by_room[ZONE_A][EH_2].percent_coverage == 1.0
    rows = result[ELECTRIC_HEATER_SECTION_ID]["electric_heaters"]
    assert [(row["identifier"], row["zone_id"], row["zone_name"]) for row in rows] == [
        (EH_1, ZONE_A, "Zone A"),
        (EH_1, ZONE_B, "Zone B"),
        (EH_2, ZONE_A, "Zone A"),
    ]
    assert rows[0]["digest"] == rows[1]["digest"]
    assert set(rows[0]) == set(json.loads(RESULT_FIELDS.read_text())["electric_heaters"])


def test_conformance_reads_back_each_heater_and_fails_on_a_tampered_row_a_lost_heater_or_an_unreported_one() -> None:
    result = run(document())
    model = reloaded(result)
    fields = result[ELECTRIC_HEATER_SECTION_ID]
    section = ElectricHeaterSection()
    section.conformance(model, fields)
    for key, bad in (("percent_coverage", 0.5), ("digest", "0" * 64)):
        tampered = copy.deepcopy(fields)
        tampered["electric_heaters"][1][key] = bad
        with pytest.raises(ValueError, match="electric heater is"):
            section.conformance(model, tampered)
    lost = copy.deepcopy(fields)
    lost["electric_heaters"][1]["identifier"] = "ehr_ZZZZZZZZZZZZ"
    with pytest.raises(ValueError, match="lost electric heater"):
        section.conformance(model, lost)
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {"electric_heaters": fields["electric_heaters"][:2]})


def test_another_sections_heating_system_on_a_room_is_not_this_sections_to_refuse() -> None:
    result = run(document())
    model = reloaded(result)
    boiler = stack.load("honeybee_phhvac.heating").PhHeatingFossilBoiler()
    boiler.identifier = "boiler_1"
    room = next(room for room in model.rooms if room.identifier == ZONE_B)
    room.properties.ph_hvac.add_heating_system(boiler)
    ElectricHeaterSection().conformance(model, result[ELECTRIC_HEATER_SECTION_ID])


def test_two_rooms_translated_unequal_under_one_identifier_fail_conformance_on_the_overwritten_room() -> None:
    value = document()
    records(value)[0]["percent_coverage"] = 0.4
    result = run(value)
    rows = result[ELECTRIC_HEATER_SECTION_ID]["electric_heaters"]
    assert rows[0]["digest"] != rows[1]["digest"]
    by_room = heating(result)
    assert by_room[ZONE_A][EH_1].percent_coverage == by_room[ZONE_B][EH_1].percent_coverage, (
        "honeybee-ph keeps one heating system for the shared identifier, hiding the difference"
    )
    with pytest.raises(ValueError, match="electric heater is"):
        ElectricHeaterSection().conformance(reloaded(result), result[ELECTRIC_HEATER_SECTION_ID])


@pytest.mark.parametrize(
    ("key", "bad"),
    [("percent_coverage", 1.5), ("percent_coverage", "all"), ("identifier", ""), ("user_data", [])],
)
def test_a_bad_record_value_is_a_record_error_that_blocks_its_pair(key: str, bad: object) -> None:
    value = document()
    records(value)[0][key] = bad
    result = run(value)
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == ELECTRIC_HEATER_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == (
        "object.unavailable",
        records(value)[0]["id"],
        True,
    )
