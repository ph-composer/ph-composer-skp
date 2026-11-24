"""The heat pump section (context/CONTRACTS.md, "Mechanical equipment") over the reference model
tests/mechanical_heat_pump_export_test.rb writes: Zones A and B in Building Segment Main, both served by the Segment's
one blended heat pump. Each pair builds its own `PhHeatPumpRatedMonthly` under the Segment's identifier, with the
blend's COPs and recirculation cooling and fixed identifiers on its four cooling parameter sets; the exact HBJSON
reloads with both Rooms holding it, and the section's conformance compares each reloaded Room with its own row's
digest, so two Rooms translated unequal under one identifier fail it."""

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
    COOLING_PARAMS,
    HEAT_PUMP_SECTION_ID,
    HeatPumpSection,
    TranslatedHeatPump,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "mechanical"
GOLDEN = FIXTURES / "heat_pump_extraction.json"
#: The result fields the Ruby contributor declares, written by the same Ruby test.
RESULT_FIELDS = FIXTURES / "heat_pump_result_fields.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(GOLDEN.read_text()))


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][HEAT_PUMP_SECTION_ID]["records"])


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def heat_pumps(result: dict[str, Any]) -> dict[str, list[Any]]:
    return {room.identifier: list(room.properties.ph_hvac.heat_pump_systems) for room in reloaded(result).rooms}


def test_each_pair_builds_its_own_heat_pump_with_fixed_identifiers_throughout() -> None:
    translation = translate(document(), SECTIONS)
    built = translation.results[HEAT_PUMP_SECTION_ID].objects
    first, second = (cast(TranslatedHeatPump, built[key]).heat_pump for key in sorted(built))
    identifier = records(document())[0]["system_identifier"]
    assert first is not second, "one object per (Segment, Zone) pair"
    assert first.identifier == second.identifier == identifier
    assert first.to_dict() == second.to_dict(), "every object of one Segment is equal"
    for name in COOLING_PARAMS:
        assert getattr(first.cooling_params, name).identifier == f"{identifier}_{name}"
    again = translate(document(), SECTIONS).results[HEAT_PUMP_SECTION_ID].objects
    assert cast(TranslatedHeatPump, again[sorted(again)[0]]).heat_pump.to_dict() == first.to_dict(), (
        "two exports write equal dictionaries"
    )


def test_the_reference_reloads_with_both_rooms_holding_the_segments_blended_heat_pump() -> None:
    value = document()
    record = records(value)[0]
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = heat_pumps(result)
    assert sorted(by_room) == [ZONE_A, ZONE_B]
    for systems in by_room.values():
        [heat_pump] = systems
        assert type(heat_pump).__name__ == "PhHeatPumpRatedMonthly"
        assert (heat_pump.identifier, heat_pump.display_name) == (record["system_identifier"], "Heat pumps: Main")
        assert (record["cop_1"], record["cop_2"]) == (heat_pump.COP_1, heat_pump.COP_2)
        assert (heat_pump.ambient_temp_1, heat_pump.ambient_temp_2, heat_pump.percent_coverage) == (-8.333, 8.333, 1.0)
        recirculation = heat_pump.cooling_params.recirculation
        cooling = record["cooling"]
        assert recirculation.used is True
        assert (recirculation.capacity, recirculation.flow_rate_m3_hr, recirculation.annual_COP) == (
            cooling["capacity_kw"],
            cooling["flow_rate_m3_hr"],
            cooling["annual_cop"],
        )
        assert (recirculation.min_coil_temp, recirculation.single_speed, recirculation.flow_rate_variable) == (
            12.0,
            False,
            True,
        )
        assert heat_pump.cooling_params.percent_coverage == 1.0
        assert not heat_pump.cooling_params.ventilation.used and not heat_pump.cooling_params.panel.used
    rows = result[HEAT_PUMP_SECTION_ID]["heat_pumps"]
    assert [(row["zone_id"], row["zone_name"], row["segment"]) for row in rows] == [
        (ZONE_A, "Zone A", "Main"),
        (ZONE_B, "Zone B", "Main"),
    ]
    assert rows[0]["digest"] == rows[1]["digest"]
    assert set(rows[0]) == set(json.loads(RESULT_FIELDS.read_text())["heat_pumps"])


def test_conformance_reads_back_each_heat_pump_and_fails_on_a_tampered_row_or_an_unreported_one() -> None:
    result = run(document())
    model = reloaded(result)
    fields = result[HEAT_PUMP_SECTION_ID]
    section = HeatPumpSection()
    section.conformance(model, fields)
    for key, bad in (("cop_1", 9.9), ("capacity_kw", 1.0), ("cooling_used", False), ("digest", "0" * 64)):
        tampered = copy.deepcopy(fields)
        tampered["heat_pumps"][1][key] = bad
        with pytest.raises(ValueError, match="heat pump is"):
            section.conformance(model, tampered)
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {"heat_pumps": fields["heat_pumps"][:1]})


def test_two_rooms_translated_unequal_under_one_identifier_fail_conformance_on_the_overwritten_room() -> None:
    value = document()
    records(value)[0]["cop_1"] = 1.9
    result = run(value)
    rows = result[HEAT_PUMP_SECTION_ID]["heat_pumps"]
    assert rows[0]["digest"] != rows[1]["digest"]
    by_room = heat_pumps(result)
    assert by_room[ZONE_A][0].COP_1 == by_room[ZONE_B][0].COP_1, (
        "honeybee-ph keeps one heat pump for the shared identifier, hiding the difference"
    )
    with pytest.raises(ValueError, match="heat pump is"):
        HeatPumpSection().conformance(reloaded(result), result[HEAT_PUMP_SECTION_ID])


def test_a_blend_that_does_not_cool_writes_no_recirculation() -> None:
    value = document()
    for record in records(value):
        record["cooling"].update(used=False, capacity_kw=0.0, flow_rate_m3_hr=0.0, annual_cop=0.0)
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    for systems in heat_pumps(result).values():
        assert systems[0].cooling_params.recirculation.used is False


@pytest.mark.parametrize(
    ("path", "bad", "label"),
    [
        (("cop_1",), 0.0, "cop_1"),
        (("percent_coverage",), 1.5, "percent_coverage"),
        (("cooling", "capacity_kw"), -1.0, "capacity_kw"),
        (("cooling", "used"), "yes", "used"),
        (("segment",), "", "segment"),
    ],
)
def test_a_bad_record_value_is_a_record_error_that_blocks_its_pair(
    path: tuple[str, ...], bad: object, label: str
) -> None:
    value = document()
    target: Any = records(value)[0]
    for step in path[:-1]:
        target = target[step]
    target[path[-1]] = bad
    result = run(value)
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == HEAT_PUMP_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == (
        "object.unavailable",
        records(value)[0]["id"],
        True,
    )
    assert label in finding["message"]
