"""The Pump section (context/CONTRACTS.md, "Mechanical equipment") over the reference model
tests/mechanical_pump_export_test.rb writes: Zones A and B in Building Segment Main, P-1 (two heating circulation
pumps, 45 W, 5 kh, half a gain in winter, with user_data) on both and P-2 (a hot water circulation pump, 20 W, outside
the envelope, its gain named summer) on Zone A beside it. Each pair builds its own `PhSupportiveDevice` under its
pump's id; the exact HBJSON reloads with Room A holding both pumps and Room B one, and the section's conformance
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
from ph_composer_translation.mechanical_sections import PUMP_SECTION_ID, PumpSection, TranslatedPump

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "mechanical"
GOLDEN = FIXTURES / "pump_extraction.json"
#: The result fields the Ruby contributor declares, written by the same Ruby test.
RESULT_FIELDS = FIXTURES / "pump_result_fields.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
P_1 = "pmp_FIXED0000002"
P_2 = "pmp_FIXED0000003"


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(GOLDEN.read_text()))


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][PUMP_SECTION_ID]["records"])


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def devices(result: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Each reloaded Room's supportive devices by identifier."""
    return {
        room.identifier: {device.identifier: device for device in room.properties.ph_hvac.supportive_devices}
        for room in reloaded(result).rooms
    }


def test_each_pair_builds_its_own_supportive_device_under_its_pumps_id() -> None:
    built = translate(document(), SECTIONS).results[PUMP_SECTION_ID].objects
    by_pair = {key: cast(TranslatedPump, item).device for key, item in built.items()}
    first, second = by_pair[f"{P_1}_{ZONE_A}"], by_pair[f"{P_1}_{ZONE_B}"]
    assert first is not second, "one object per (pump, Zone) pair"
    assert type(first).__name__ == "PhSupportiveDevice"
    assert (
        first.identifier,
        first.display_name,
        first.device_type,
        first.quantity,
        first.in_conditioned_space,
        first.norm_energy_demand_W,
        first.annual_period_operation_khrs,
        first.ihg_utilization_factor,
        first.ihg_usage_profile,
    ) == (P_1, "P-1", 4, 2, True, 45.0, 5.0, 0.5, 2)
    assert first.user_data == {"maker_ref": "P-1-A"}
    assert first.to_dict() == second.to_dict(), "every object of one pump is equal"
    other = by_pair[f"{P_2}_{ZONE_A}"]
    assert (other.device_type, other.ihg_usage_profile, other.in_conditioned_space, other.user_data) == (
        6,
        3,
        False,
        {},
    ), "the profile P-2 names survives its type, which would seed 4"


def test_the_reference_reloads_with_each_room_holding_every_pump_that_serves_it() -> None:
    result = run(document())
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = devices(result)
    assert {room: sorted(found) for room, found in by_room.items()} == {ZONE_A: [P_1, P_2], ZONE_B: [P_1]}
    for found in by_room.values():
        one = found[P_1]
        assert (one.display_name, one.device_type, one.quantity, one.ihg_usage_profile) == ("P-1", 4, 2, 2)
        assert one.user_data == {"maker_ref": "P-1-A"}
    assert (by_room[ZONE_A][P_2].ihg_usage_profile, by_room[ZONE_A][P_2].norm_energy_demand_W) == (3, 20.0)
    rows = result[PUMP_SECTION_ID]["pumps"]
    assert [(row["identifier"], row["zone_id"], row["zone_name"]) for row in rows] == [
        (P_1, ZONE_A, "Zone A"),
        (P_1, ZONE_B, "Zone B"),
        (P_2, ZONE_A, "Zone A"),
    ]
    assert rows[0]["digest"] == rows[1]["digest"]
    assert set(rows[0]) == set(json.loads(RESULT_FIELDS.read_text())["pumps"])


def test_conformance_reads_back_each_pump_and_fails_on_a_tampered_row_a_lost_pump_or_an_unreported_one() -> None:
    result = run(document())
    model = reloaded(result)
    fields = result[PUMP_SECTION_ID]
    section = PumpSection()
    section.conformance(model, fields)
    for key, bad in (("norm_energy_demand_w", 50.0), ("ihg_usage_profile", 1), ("digest", "0" * 64)):
        tampered = copy.deepcopy(fields)
        tampered["pumps"][1][key] = bad
        with pytest.raises(ValueError, match="pump is"):
            section.conformance(model, tampered)
    lost = copy.deepcopy(fields)
    lost["pumps"][1]["identifier"] = "pmp_ZZZZZZZZZZZZ"
    with pytest.raises(ValueError, match="lost pump"):
        section.conformance(model, lost)
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {"pumps": fields["pumps"][:2]})


def test_another_sections_supportive_device_on_a_room_is_not_this_sections_to_refuse() -> None:
    result = run(document())
    model = reloaded(result)
    fan = stack.load("honeybee_phhvac.supportive_device").PhSupportiveDevice()
    fan.identifier = "fan_AAAAAAAAAAAA"
    room = next(room for room in model.rooms if room.identifier == ZONE_B)
    room.properties.ph_hvac.add_supportive_device(fan)
    PumpSection().conformance(model, result[PUMP_SECTION_ID])


def test_two_rooms_translated_unequal_under_one_identifier_fail_conformance_on_the_overwritten_room() -> None:
    value = document()
    records(value)[0]["norm_energy_demand_w"] = 30.0
    result = run(value)
    rows = result[PUMP_SECTION_ID]["pumps"]
    assert rows[0]["digest"] != rows[1]["digest"]
    by_room = devices(result)
    assert by_room[ZONE_A][P_1].norm_energy_demand_W == by_room[ZONE_B][P_1].norm_energy_demand_W, (
        "honeybee-ph keeps one supportive device for the shared identifier, hiding the difference"
    )
    with pytest.raises(ValueError, match="pump is"):
        PumpSection().conformance(reloaded(result), result[PUMP_SECTION_ID])


@pytest.mark.parametrize(
    ("key", "bad"),
    [
        ("device_type", 5),
        ("device_type", True),
        ("quantity", 0),
        ("norm_energy_demand_w", -1.0),
        ("ihg_utilization_factor", 1.5),
        ("ihg_usage_profile", None),
        ("ihg_usage_profile", 5),
        ("in_conditioned_space", "yes"),
        ("identifier", ""),
        ("user_data", []),
    ],
)
def test_a_bad_record_value_is_a_record_error_that_blocks_its_pair(key: str, bad: object) -> None:
    value = document()
    records(value)[0][key] = bad
    result = run(value)
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == PUMP_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == (
        "object.unavailable",
        records(value)[0]["id"],
        True,
    )
