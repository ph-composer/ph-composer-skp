"""The ventilation section (context/CONTRACTS.md, "Mechanical equipment") over the reference model
tests/mechanical_export_test.rb writes: in the base case ERV-1 serves Zone A and ERV-2 Zone B, in the shared case
ERV-1 serves both. Each pair builds its own `PhVentilationSystem`, `sys_type` 1, holding a `Ventilator` with the
record's values; the exact HBJSON reloads with each Room's system, one identifier for one Ventilator across its
Rooms, and the section's conformance passes, and fails on a tampered row or an unreported system."""

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
    VENTILATION_SECTION_ID,
    TranslatedVentilation,
    VentilationSection,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "mechanical"
BASE = FIXTURES / "extraction.json"
SHARED = FIXTURES / "shared_extraction.json"
#: The result fields the Ruby contributor declares, written by the same test.
RESULT_FIELDS = FIXTURES / "result_fields.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
ERV_1 = "vnt_FIXED0000001"
ERV_2 = "vnt_FIXED0000002"


def document(path: Path = BASE) -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(path.read_text()))


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][VENTILATION_SECTION_ID]["records"])


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def systems(result: dict[str, Any]) -> dict[str, Any]:
    return {room.identifier: room.properties.ph_hvac.ventilation_system for room in reloaded(result).rooms}


def test_each_pair_builds_its_own_system_with_the_records_values_and_sys_type_one() -> None:
    value = document(SHARED)
    translation = translate(value, SECTIONS)
    built = translation.results[VENTILATION_SECTION_ID].objects
    first, second = (cast(TranslatedVentilation, built[key]).system for key in sorted(built))
    assert first is not second, "one object per (item, Zone) pair, mutable until attached"
    assert first.identifier == second.identifier == ERV_1
    assert first.ventilation_unit.identifier == second.ventilation_unit.identifier == f"{ERV_1}_unit"
    assert first.to_dict() == second.to_dict(), "every object of one Ventilator is equal"
    assert first.sys_type == 1 and first.supply_ducting == [] and first.exhaust_ducting == []


def test_the_base_case_reloads_two_distinct_ventilators_with_the_records_values() -> None:
    value = document()
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = systems(result)
    assert {room: system.identifier for room, system in by_room.items()} == {ZONE_A: ERV_1, ZONE_B: ERV_2}
    expected = {row["zone_id"]: row for row in records(value)}
    for room, system in by_room.items():
        row, unit = expected[room], system.ventilation_unit
        assert (system.sys_type, system.display_name, unit.display_name) == (
            1,
            row["display_name"],
            row["display_name"],
        )
        assert unit.identifier == row["unit_identifier"]
        assert (unit.quantity, unit.sensible_heat_recovery, unit.latent_heat_recovery, unit.electric_efficiency) == (
            row["quantity"],
            row["sensible_heat_recovery"],
            row["latent_heat_recovery"],
            row["electric_efficiency_wh_m3"],
        )
        assert (unit.frost_protection_reqd, unit.temperature_below_defrost_used, unit.in_conditioned_space) == (
            row["frost_protection_reqd"],
            row["temperature_below_defrost_used_c"],
            row["in_conditioned_space"],
        )
        assert unit.subsoil_heat_exchange_efficiency == row["subsoil_heat_exchange_efficiency"]
        assert unit.preheated_intake_temperature_c is None
    assert by_room[ZONE_B].ventilation_unit.subsoil_heat_exchange_efficiency == 0.2


def test_the_shared_case_reloads_one_system_on_both_rooms() -> None:
    result = run(document(SHARED))
    assert result["summary"]["publishable"] is True, result["findings"]
    check(result["canonical_model"], result, SECTIONS)
    by_room = systems(result)
    assert by_room[ZONE_A] is by_room[ZONE_B], "honeybee-ph reloads one system for the shared identifier"
    assert by_room[ZONE_A].ventilation_unit.sensible_heat_recovery == 0.85
    rows = result[VENTILATION_SECTION_ID]["ventilation"]
    assert [(row["zone_id"], row["zone_name"], row["system_identifier"]) for row in rows] == [
        (ZONE_A, "Zone A", ERV_1),
        (ZONE_B, "Zone B", ERV_1),
    ]


def test_conformance_fails_on_a_tampered_identifier_value_or_an_unreported_system() -> None:
    result = run(document(SHARED))
    model = reloaded(result)
    fields = result[VENTILATION_SECTION_ID]
    section = VentilationSection()
    section.conformance(model, fields)

    tampered = copy.deepcopy(fields)
    tampered["ventilation"][1]["system_identifier"] = ERV_2
    with pytest.raises(ValueError, match="ventilation system is"):
        section.conformance(model, tampered)

    split = copy.deepcopy(fields)
    for row in split["ventilation"]:
        row["system_identifier"] = row["zone_id"]
    with pytest.raises(ValueError):
        section.conformance(model, split)

    value = copy.deepcopy(fields)
    value["ventilation"][0]["sensible_heat_recovery"] = 0.5
    with pytest.raises(ValueError, match="sensible_heat_recovery"):
        section.conformance(model, value)

    unreported = {"ventilation": fields["ventilation"][:1]}
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, unreported)


def test_one_item_carrying_two_identifiers_across_its_rooms_fails_conformance() -> None:
    value = document(SHARED)
    records(value)[1]["system_identifier"] = "vnt_OTHER0000001"
    result = run(value)
    with pytest.raises(ValueError, match="more than one identifier"):
        VentilationSection().conformance(reloaded(result), result[VENTILATION_SECTION_ID])


@pytest.mark.parametrize(
    ("field", "bad"),
    [
        ("sensible_heat_recovery", 1.2),
        ("quantity", 0),
        ("frost_protection_reqd", "yes"),
        ("electric_efficiency_wh_m3", -1),
    ],
)
def test_a_bad_record_value_is_a_record_error_that_blocks_its_pair(field: str, bad: object) -> None:
    value = document()
    records(value)[0][field] = bad
    result = run(value)
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == VENTILATION_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == (
        "object.unavailable",
        records(value)[0]["id"],
        True,
    )
    assert field in finding["message"]


def test_a_ventilators_user_data_rides_on_its_unit() -> None:
    value = document()
    records(value)[0]["user_data"] = {"maker_ref": "ERV-1-A"}
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert systems(result)[ZONE_A].ventilation_unit.user_data == {"maker_ref": "ERV-1-A"}

    records(value)[0]["user_data"] = {"ph_composer": {"x": 1}}
    assert run(value)["summary"]["publishable"] is False, "the reserved key is refused"


def test_each_row_has_exactly_the_fields_the_ruby_contributor_declares() -> None:
    declared = json.loads(RESULT_FIELDS.read_text())["ventilation"]
    for path in (BASE, SHARED):
        rows = run(document(path))[VENTILATION_SECTION_ID]["ventilation"]
        assert rows and all(sorted(row) == sorted(declared) for row in rows)
