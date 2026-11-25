"""The piping section (context/CONTRACTS.md, "Translation sections and artifacts") over the reference model
tests/piping_export_test.rb writes: HWS-1 serves Zones A and B with 8 tap points, and Piping group PG-1 holds the hot
water piping case, one trunk (multiplier 12) with three branches of two twigs each, and two recirculation runs. The
section adds them to both pairs' hot water systems before the hot water section attaches them; the exact HBJSON
reloads with both Rooms carrying them, the hot water digests equal, and the recirculation temperature and hours equal
to Ruby's."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import piping_sections, stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.contract.piping_records import PipingRecord
from ph_composer_translation.coordinator import translate
from ph_composer_translation.mechanical_sections import HOT_WATER_SECTION_ID, TranslatedHotWater
from ph_composer_translation.piping_sections import (
    PIPING_SECTION_ID,
    PipingSection,
    TranslatedPiping,
    add_pipes,
    pipes,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "piping"
GOLDEN = FIXTURES / "extraction.json"
#: The result fields the Ruby contributor declares, written by the same Ruby test.
RESULT_FIELDS = FIXTURES / "result_fields.json"
#: Systems of uneven recirculation runs with the temperature and hours Ruby reads for each.
VECTORS = FIXTURES / "recirculation_vectors.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
HWS_1 = "hws_FIXED0000002"


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(GOLDEN.read_text()))


def records(value: dict[str, Any], section: str = PIPING_SECTION_ID) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][section]["records"])


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def systems(result: dict[str, Any]) -> dict[str, Any]:
    return {room.identifier: room.properties.ph_hvac.hot_water_system for room in reloaded(result).rooms}


def round_trip(system: Any) -> Any:
    """The system as the canonical HBJSON writes it, keys sorted, and honeybee-ph reads it back."""
    module = stack.load("honeybee_phhvac.hot_water_system")
    return module.PhHotWaterSystem.from_dict(json.loads(json.dumps(system.to_dict(), sort_keys=True)))


def test_the_record_adds_one_tree_to_each_pairs_own_system_before_it_is_attached() -> None:
    translation = translate(document(), SECTIONS)
    built = translation.results[HOT_WATER_SECTION_ID].objects
    first, second = (cast(TranslatedHotWater, built[key]).system for key in sorted(built))
    [one], [two] = list(first.distribution_piping), list(second.distribution_piping)
    assert one is not two and one.branches[0] is not two.branches[0], "fresh pipes for every Room"
    assert (one.multiplier, one.demand_recirculation, len(one.branches)) == (12, False, 3)
    assert [branch.num_fixtures for branch in one.branches] == [2, 2, 2]
    assert len(list(first.recirc_piping)) == 2
    assert first.to_dict() == second.to_dict(), "every object of one System is equal"
    assert cast(TranslatedPiping, translation.results[PIPING_SECTION_ID].objects[HWS_1]).systems == (first, second)


def test_the_case_reloads_on_both_rooms_with_equal_digests_and_ruby_recirculation() -> None:
    value = document()
    [record] = records(value)
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = systems(result)
    assert sorted(by_room) == [ZONE_A, ZONE_B]
    for system in by_room.values():
        [trunk] = list(system.distribution_piping)
        assert (trunk.identifier, trunk.display_name) == (record["trunks"][0]["identifier"], "Trunk 1")
        assert (trunk.multiplier, trunk.demand_recirculation, round(trunk.length, 3)) == (12, False, 9.0)
        assert sorted(round(branch.length, 3) for branch in trunk.branches) == [3.0, 4.0, 4.0]
        assert sorted(round(twig.length, 3) for branch in trunk.branches for twig in branch.fixtures) == [
            1.0,
            1.0,
            1.0,
            1.0,
            1.5,
            1.5,
        ]
        segment = trunk.segments[0]
        assert (segment.material.number, segment.diameter_mm, segment.insulation_thickness_mm) == (6, 19.05, 12.7)
        assert (segment.water_temp_c, segment.daily_period) == (60.0, 24)
        assert sorted(round(element.length, 3) for element in system.recirc_piping) == [2.0, 9.0]
        assert (system.recirc_temp, system.recirc_hours) == (
            record["recirculation_temperature_c"],
            record["recirculation_hours"],
        ), "exactly Ruby's values"
        assert system.recirc_hours == 19 and round(system.recirc_temp, 2) == 54.09
        assert system.number_tap_points == 8
    rows = result[HOT_WATER_SECTION_ID]["hot_water"]
    assert rows[0]["digest"] == rows[1]["digest"]
    assert [row["room_count"] for row in result[PIPING_SECTION_ID]["systems"]] == [2]


def test_blank_tap_points_reload_as_the_twig_count() -> None:
    value = document()
    for row in records(value, HOT_WATER_SECTION_ID):
        row["number_tap_points"] = None
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert {system.number_tap_points for system in systems(result).values()} == {6}


def test_conformance_refuses_a_differing_a_missing_and_an_unreported_trunk() -> None:
    result = run(document())
    model = reloaded(result)
    fields = result[PIPING_SECTION_ID]
    section = PipingSection()
    section.conformance(model, fields)

    for key, bad in (("multiplier", 6), ("demand_recirculation", True), ("length_m", 9.5), ("twig_counts", [2, 2])):
        tampered = copy.deepcopy(fields)
        tampered["trunks"][0][key] = bad
        with pytest.raises(ValueError, match="reads back"):
            section.conformance(model, tampered)
    missing = copy.deepcopy(fields)
    missing["trunks"].append({**fields["trunks"][0], "identifier": "pipe_0000000000000000"})
    with pytest.raises(ValueError, match="lost trunk"):
        section.conformance(model, missing)
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {**fields, "trunks": []})
    with pytest.raises(ValueError, match="recirculation reads back"):
        section.conformance(model, {**fields, "systems": [{**fields["systems"][0], "recirculation_hours": 24}]})
    with pytest.raises(ValueError, match="on 2 Rooms"):
        section.conformance(model, {**fields, "systems": [{**fields["systems"][0], "room_count": 1}]})
    lost = copy.deepcopy(fields)
    lost["recirculation"].append({**fields["recirculation"][0], "identifier": "pipe_0000000000000000"})
    with pytest.raises(ValueError, match="lost recirculation element"):
        section.conformance(model, lost)
    with pytest.raises(ValueError, match="reads back"):
        section.conformance(model, {**fields, "recirculation": [{**fields["recirculation"][0], "length_m": 1.0}]})
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {**fields, "recirculation": fields["recirculation"][:1]})
    other = copy.deepcopy(fields)
    for key in ("trunks", "recirculation"):
        for row in other[key]:
            row["system_id"] = "hws_ANOTHER00001"
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, other)


def test_a_failing_translate_blocks_and_leaves_every_system_without_pipes(monkeypatch: pytest.MonkeyPatch) -> None:
    """The second Room's build fails, after the first Room's pipes are built: neither system is added to."""
    built = piping_sections.trunk
    calls: list[object] = []

    def second_fails(values: Any) -> Any:
        calls.append(values)
        if len(calls) > 1:
            raise ValueError("forced")
        return built(values)

    monkeypatch.setattr(piping_sections, "trunk", second_fails)
    translation = translate(document(), SECTIONS)
    result = cast(dict[str, Any], translation.to_document())
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == PIPING_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == ("object.unavailable", HWS_1, True)
    assert len(calls) == 2
    for item in translation.results[HOT_WATER_SECTION_ID].objects.values():
        system = cast(TranslatedHotWater, item).system
        assert not list(system.distribution_piping) and not list(system.recirc_piping)


def test_a_system_no_exported_zone_takes_gives_an_empty_object_and_no_rows() -> None:
    value = document()
    value["sections"][HOT_WATER_SECTION_ID]["records"] = []
    translation = translate(value, SECTIONS)
    assert cast(TranslatedPiping, translation.results[PIPING_SECTION_ID].objects[HWS_1]).systems == ()
    result = cast(dict[str, Any], translation.to_document())
    assert [row for row in result["findings"] if row["section"] == PIPING_SECTION_ID] == []
    assert result.get(PIPING_SECTION_ID, {"trunks": [], "recirculation": [], "systems": []}) == {
        "trunks": [],
        "recirculation": [],
        "systems": [],
    }


def test_two_translations_build_equal_hot_water_systems() -> None:
    first, second = (run(document())[HOT_WATER_SECTION_ID]["hot_water"] for _ in range(2))
    assert [row["digest"] for row in first] == [row["digest"] for row in second]


@pytest.mark.parametrize(
    ("change", "label"),
    [
        (lambda record: record["trunks"][0]["segments"][1].update(material=2), "different materials"),
        (lambda record: record["trunks"][0]["segments"][0].update(material=9), "material"),
        (lambda record: record["trunks"][0].update(multiplier=0), "multiplier"),
        (lambda record: record["recirculation"][1].update(identifier=record["recirculation"][0]["identifier"]), "run"),
        (lambda record: record["trunks"][0]["segments"][0].update(user_data={"ph_composer": 1}), "reserved"),
    ],
)
def test_a_bad_record_is_refused_and_blocks(change: Any, label: str) -> None:
    value = document()
    change(records(value)[0])
    result = run(value)
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == PIPING_SECTION_ID]
    assert (finding["code"], finding["blocks_export"]) == ("object.unavailable", True)
    assert label in finding["message"]


def test_a_pipes_user_data_rides_its_segment() -> None:
    value = document()
    twig = records(value)[0]["trunks"][0]["branches"][0]["twigs"][0]
    twig["segments"][0]["user_data"] = {"maker_ref": "PX-1"}
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    fixtures = [
        twig for branch in next(iter(systems(result)[ZONE_A].distribution_piping)).branches for twig in branch.fixtures
    ]
    assert [segment.user_data for twig in fixtures for segment in twig.segments if segment.user_data] == [
        {"maker_ref": "PX-1"}
    ]


def test_the_ruby_recirculation_read_equals_honeybee_phs_before_and_after_a_reload() -> None:
    """Ruby sums runs and their pipes in identifier order, the order a reloaded system holds them in. Added in another
    order, some of these systems read differently, so the order is what makes them equal."""
    module = stack.load("honeybee_phhvac.hot_water_system")
    differs = 0
    for raw in json.loads(VECTORS.read_text())["cases"]:
        record = PipingRecord.read(raw)
        expected = (record.recirculation_temperature_c, record.recirculation_hours)
        system = module.PhHotWaterSystem()
        add_pipes(system, *pipes(record))
        assert (system.recirc_temp, system.recirc_hours) == expected
        assert (round_trip(system).recirc_temp, round_trip(system).recirc_hours) == expected
        unsorted = module.PhHotWaterSystem()
        for element in record.recirculation:
            built = piping_sections.element(element)
            built._segments = {
                part.identifier: piping_sections.segment(part) for part in element.segments
            }  # run order, not identifier order
            unsorted.add_recirc_piping(built)
        differs += (unsorted.recirc_temp, unsorted.recirc_hours) != expected
    assert differs > 0, "the vectors must show the order mattering"


def test_each_row_has_exactly_the_fields_the_ruby_contributor_declares() -> None:
    declared = json.loads(RESULT_FIELDS.read_text())
    fields = run(document())[PIPING_SECTION_ID]
    assert sorted(fields) == sorted(declared)
    for key, rows in fields.items():
        assert rows and all(sorted(row) == sorted(declared[key]) for row in rows), key
