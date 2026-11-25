"""The ducting section (context/CONTRACTS.md, "Translation sections and artifacts") over the reference model
tests/ducting_export_test.rb writes with ACCEPTANCE's ERV ducting case: in the base case ERV-1 serves Zone A and ERV-2
Zone B, in the shared case ERV-1 serves both. ERV-1 has one round supply element of two segments (2.500 m) and one
exhaust element (1.800 m); ERV-2 one rectangular supply element (2.500 m) and two exhaust elements of 1.500 m, its run
of quantity 2. The section appends them to each pair's ventilation system before the ventilation section attaches it;
the exact HBJSON reloads with each Room carrying them, the shared case's two Rooms with equal identifiers, and both
total lengths equal to Ruby's."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import ducting_sections, stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.coordinator import translate
from ph_composer_translation.ducting_sections import DUCTING_SECTION_ID, DuctingSection, TranslatedDucting
from ph_composer_translation.mechanical_sections import VENTILATION_SECTION_ID, TranslatedVentilation

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "ducting"
BASE = FIXTURES / "extraction.json"
SHARED = FIXTURES / "shared_extraction.json"
#: The result fields the Ruby contributor declares, written by the same Ruby test.
RESULT_FIELDS = FIXTURES / "result_fields.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
ERV_1 = "vnt_FIXED0000002"
ERV_2 = "vnt_FIXED0000003"


def document(path: Path = BASE) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text()))


def records(value: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {row["ventilator_id"]: row for row in value["sections"][DUCTING_SECTION_ID]["records"]}


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def systems(result: dict[str, Any]) -> dict[str, Any]:
    return {room.identifier: room.properties.ph_hvac.ventilation_system for room in reloaded(result).rooms}


def lengths(elements: list[Any]) -> list[float]:
    return [round(part.length, 3) for part in elements]


def test_the_records_append_to_each_pairs_own_system_before_it_is_attached() -> None:
    translation = translate(document(SHARED), SECTIONS)
    built = translation.results[VENTILATION_SECTION_ID].objects
    first, second = (cast(TranslatedVentilation, built[key]).system for key in sorted(built))
    [one], [two] = first.supply_ducting, second.supply_ducting
    assert one is not two and one.segments[0] is not two.segments[0], "fresh ducts for every Room"
    assert first.to_dict() == second.to_dict(), "every object of one Ventilator is equal"
    ducted = translation.results[DUCTING_SECTION_ID].objects
    assert cast(TranslatedDucting, ducted[ERV_1]).systems == (first, second)
    assert cast(TranslatedDucting, ducted[ERV_2]).systems == (), "ERV-2 serves no Zone in the shared case"


def test_the_base_case_reloads_each_rooms_runs_in_metres_with_ruby_lengths() -> None:
    value = document()
    expected = records(value)
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = systems(result)
    a, b = by_room[ZONE_A], by_room[ZONE_B]
    assert (a.identifier, b.identifier) == (ERV_1, ERV_2)
    [supply] = a.supply_ducting
    assert (supply.duct_type, len(supply.segments), round(supply.length, 3)) == (1, 2, 2.5)
    for part in supply.segments:
        assert (part.diameter, part.width, part.height, part.shape_type) == (0.16, None, None, 1)
        assert (part.insulation_thickness, part.insulation_conductivity, part.insulation_reflective) == (
            0.0254,
            0.04,
            True,
        )
    [exhaust] = a.exhaust_ducting
    assert (exhaust.duct_type, round(exhaust.length, 3)) == (2, 1.8)

    [rectangular] = b.supply_ducting
    [part] = rectangular.segments
    assert (part.width, part.height, part.shape_type) == (0.2, 0.1, 2)
    assert (part.insulation_thickness, part.insulation_conductivity, part.insulation_reflective) == (
        0.0508,
        0.035,
        False,
    )
    assert [element.duct_type for element in b.exhaust_ducting] == [2, 2]
    assert lengths(b.exhaust_ducting) == [1.5, 1.5]
    identifiers = [element.identifier for element in b.exhaust_ducting]
    assert identifiers[1] == f"{identifiers[0]}-2", "a quantity of 2 is two elements"
    assert [element.identifier for element in b.exhaust_ducting] == [
        element["identifier"] for element in expected[ERV_2]["exhaust"]
    ]

    for system, ventilator in ((a, ERV_1), (b, ERV_2)):
        record = expected[ventilator]
        assert system.supply_ducting_total_length == pytest.approx(record["supply_length_m"], abs=1e-9)
        assert system.exhaust_ducting_total_length == pytest.approx(record["exhaust_length_m"], abs=1e-9)
    assert [round(a.supply_ducting_total_length, 3), round(a.exhaust_ducting_total_length, 3)] == [2.5, 1.8]
    assert [round(b.supply_ducting_total_length, 3), round(b.exhaust_ducting_total_length, 3)] == [2.5, 3.0]


def test_the_shared_case_reloads_both_rooms_with_equal_identifiers() -> None:
    value = document(SHARED)
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    check(result["canonical_model"], result, SECTIONS)
    by_room = systems(result)
    a, b = by_room[ZONE_A], by_room[ZONE_B]
    assert a.identifier == b.identifier == ERV_1
    assert a.to_dict() == b.to_dict()
    record = records(value)[ERV_1]
    names = [element.identifier for element in a.supply_ducting + a.exhaust_ducting]
    assert names == [element["identifier"] for element in record["supply"] + record["exhaust"]]
    assert [row["room_count"] for row in result[DUCTING_SECTION_ID]["ventilators"]] == [2]


def test_conformance_refuses_a_differing_missing_unreported_or_misdirected_element() -> None:
    result = run(document())
    model = reloaded(result)
    fields = result[DUCTING_SECTION_ID]
    section = DuctingSection()
    section.conformance(model, fields)

    for key, bad in (
        ("segment_count", 3),
        ("length_m", 2.6),
        ("shape_type", 2),
        ("diameter_m", 0.2),
        ("insulation_conductivity", 0.05),
        ("insulation_reflective", False),
    ):
        tampered = copy.deepcopy(fields)
        tampered["elements"][0][key] = bad
        with pytest.raises(ValueError, match="reads back"):
            section.conformance(model, tampered)
    lost = copy.deepcopy(fields)
    lost["elements"].append({**fields["elements"][0], "identifier": "duct_0000000000000000"})
    with pytest.raises(ValueError, match="lost duct element"):
        section.conformance(model, lost)
    flipped = copy.deepcopy(fields)
    flipped["elements"][0]["duct_type"] = 2
    with pytest.raises(ValueError, match="lost duct element"):
        section.conformance(model, flipped)
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {**fields, "elements": fields["elements"][1:]})
    with pytest.raises(ValueError, match="duct lengths read back"):
        section.conformance(model, {**fields, "ventilators": [{**fields["ventilators"][0], "supply_length_m": 3.0}]})
    with pytest.raises(ValueError, match="on 1 Rooms"):
        section.conformance(model, {**fields, "ventilators": [{**fields["ventilators"][0], "room_count": 2}]})

    room = next(room for room in model.rooms if room.identifier == ZONE_A)
    room.properties.ph_hvac.ventilation_system.supply_ducting[0].duct_type = 2
    with pytest.raises(ValueError, match="another duct_type"):
        section.conformance(model, fields)


def test_a_room_holding_a_differing_element_is_refused() -> None:
    model = reloaded(result := run(document()))
    room = next(room for room in model.rooms if room.identifier == ZONE_B)
    room.properties.ph_hvac.ventilation_system.exhaust_ducting[1].segments[0].width = 0.3
    with pytest.raises(ValueError, match="reads back"):
        DuctingSection().conformance(model, result[DUCTING_SECTION_ID])


def test_a_failing_translate_blocks_and_leaves_every_system_without_ducts(monkeypatch: pytest.MonkeyPatch) -> None:
    """The second Room's build fails, after the first Room's ducts are built: neither system is appended to."""
    built = ducting_sections.element
    calls: list[object] = []

    def second_room_fails(values: Any) -> Any:
        calls.append(values)
        if len(calls) > 2:
            raise ValueError("forced")
        return built(values)

    monkeypatch.setattr(ducting_sections, "element", second_room_fails)
    translation = translate(document(SHARED), SECTIONS)
    result = cast(dict[str, Any], translation.to_document())
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == DUCTING_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == ("object.unavailable", ERV_1, True)
    assert len(calls) == 3
    for item in translation.results[VENTILATION_SECTION_ID].objects.values():
        system = cast(TranslatedVentilation, item).system
        assert not system.supply_ducting and not system.exhaust_ducting


def test_two_translations_build_equal_ventilation_systems() -> None:
    first, second = (systems(run(document())) for _ in range(2))
    assert {key: system.to_dict() for key, system in first.items()} == {
        key: system.to_dict() for key, system in second.items()
    }


@pytest.mark.parametrize(
    ("change", "label"),
    [
        (lambda record: record["supply"][0].update(duct_type=2), "duct_type must be 1"),
        (lambda record: record["exhaust"][0]["segments"][0].update(height_m=0.1), "width and a height"),
        (lambda record: record["supply"][0]["segments"][0].update(diameter_m=0), "diameter_m"),
        (lambda record: record["exhaust"][0].update(identifier=record["supply"][0]["identifier"]), "element"),
        (lambda record: record["supply"][0]["segments"][0].update(user_data={"ph_composer": 1}), "reserved"),
    ],
)
def test_a_bad_record_is_refused_and_blocks(change: Any, label: str) -> None:
    value = document()
    change(records(value)[ERV_1])
    result = run(value)
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == DUCTING_SECTION_ID]
    assert (finding["code"], finding["blocks_export"]) == ("object.unavailable", True)
    assert label in finding["message"]


def test_a_rectangular_and_a_round_segment_in_one_element_are_refused() -> None:
    value = document()
    record = records(value)[ERV_1]
    record["supply"][0]["segments"][0].update(width_m=0.2, height_m=0.1)
    result = run(value)
    [finding] = [row for row in result["findings"] if row["section"] == DUCTING_SECTION_ID]
    assert "joins round and rectangular" in finding["message"]


def test_a_ducts_user_data_rides_its_segment_on_every_copy() -> None:
    value = document()
    for element in records(value)[ERV_2]["exhaust"]:
        element["segments"][0]["user_data"] = {"maker_ref": "DX-1"}
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    data = [element.segments[0].user_data for element in systems(result)[ZONE_B].exhaust_ducting]
    assert data == [{"maker_ref": "DX-1"}] * 2


def test_each_row_has_exactly_the_fields_the_ruby_contributor_declares() -> None:
    declared = json.loads(RESULT_FIELDS.read_text())
    fields = run(document())[DUCTING_SECTION_ID]
    assert sorted(fields) == sorted(declared)
    for key, rows in fields.items():
        assert rows and all(sorted(row) == sorted(declared[key]) for row in rows), key
