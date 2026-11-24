"""The Fan section (context/CONTRACTS.md, "Mechanical equipment") over the reference model
tests/mechanical_fan_export_test.rb writes: Zones A and B in Building Segment Main, F-1 (two kitchen hoods, 250 m³/h for
10,950 minutes a year, 120 W, with user_data) on both and F-2 (a dryer, 100 m³/h for 6,000 minutes, with no Power) on
Zone A beside it. Each pair builds its own exhaust ventilator under its fan's id and, for F-1, a linked type 10
`PhSupportiveDevice` under the same id: one Fan record, two honeybee-ph objects with Power and one without. The exact
HBJSON reloads with Room A holding both fans and Room B one, and the section's conformance compares each reloaded Room
with its own rows' digests."""

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
from ph_composer_translation.mechanical_sections import FAN_SECTION_ID, FanSection, PumpSection, TranslatedFan

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "mechanical"
GOLDEN = FIXTURES / "fan_extraction.json"
#: The result fields the Ruby contributor declares, written by the same Ruby test.
RESULT_FIELDS = FIXTURES / "fan_result_fields.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
F_1 = "fan_FIXED0000001"
F_2 = "fan_FIXED0000002"


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(GOLDEN.read_text()))


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][FAN_SECTION_ID]["records"])


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def rooms(result: dict[str, Any]) -> dict[str, Any]:
    """Each reloaded Room's ph_hvac properties."""
    return {room.identifier: room.properties.ph_hvac for room in reloaded(result).rooms}


def by_id(objects: Any) -> dict[str, Any]:
    return {item.identifier: item for item in objects}


def test_one_fan_with_power_builds_two_objects_and_one_without_builds_one() -> None:
    built = translate(document(), SECTIONS).results[FAN_SECTION_ID].objects
    by_pair = {key: cast(TranslatedFan, item) for key, item in built.items()}
    first, second = by_pair[f"{F_1}_{ZONE_A}"], by_pair[f"{F_1}_{ZONE_B}"]
    assert first.exhaust is not second.exhaust, "one object per (fan, Zone) pair"
    exhaust = first.exhaust
    assert type(exhaust).__name__ == "ExhaustVentKitchenHood"
    assert (
        exhaust.identifier,
        exhaust.display_name,
        exhaust.quantity,
        exhaust.annual_runtime_minutes,
        exhaust.user_data,
    ) == (F_1, "F-1", 2, 10950.0, {"maker_ref": "F-1-A"})
    assert exhaust.exhaust_flow_rate_m3s == pytest.approx(250.0 / 3600)
    device, twin = first.device, second.device
    assert device is not None and twin is not None, "F-1 has Power"
    assert type(device).__name__ == "PhSupportiveDevice"
    assert (
        device.identifier,
        device.display_name,
        device.device_type,
        device.quantity,
        device.in_conditioned_space,
        device.norm_energy_demand_W,
        device.annual_period_operation_khrs,
        device.ihg_utilization_factor,
        device.ihg_usage_profile,
        device.user_data,
    ) == (F_1, "F-1", 10, 2, True, 120.0, 0.1825, 1.0, 1, {"maker_ref": "F-1-A"})
    assert exhaust.to_dict() == second.exhaust.to_dict() and device.to_dict() == twin.to_dict(), (
        "every object of one fan is equal"
    )
    dryer = by_pair[f"{F_2}_{ZONE_A}"]
    assert (type(dryer.exhaust).__name__, dryer.device) == ("ExhaustVentDryer", None), "no Power, no supportive device"


def test_the_reference_reloads_with_each_room_holding_every_fan_that_serves_it() -> None:
    result = run(document())
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = rooms(result)
    exhausts = {room: by_id(hvac.exhaust_vent_devices) for room, hvac in by_room.items()}
    devices = {room: by_id(hvac.supportive_devices) for room, hvac in by_room.items()}
    assert {room: sorted(found) for room, found in exhausts.items()} == {ZONE_A: [F_1, F_2], ZONE_B: [F_1]}
    assert {room: sorted(found) for room, found in devices.items()} == {ZONE_A: [F_1], ZONE_B: [F_1]}
    for room in (ZONE_A, ZONE_B):
        hood, power = exhausts[room][F_1], devices[room][F_1]
        assert (hood.device_class_name, hood.quantity, hood.user_data) == (
            "ExhaustVentKitchenHood",
            2,
            {"maker_ref": "F-1-A"},
        )
        assert (power.device_type, power.quantity, power.norm_energy_demand_W) == (10, 2, 120.0)
    assert exhausts[ZONE_A][F_2].device_class_name == "ExhaustVentDryer"
    rows = result[FAN_SECTION_ID]["fans"]
    assert [(row["identifier"], row["zone_id"], row["zone_name"]) for row in rows] == [
        (F_1, ZONE_A, "Zone A"),
        (F_1, ZONE_B, "Zone B"),
        (F_2, ZONE_A, "Zone A"),
    ]
    assert (
        rows[0]["digest"] == rows[1]["digest"]
        and rows[0]["supportive_device_digest"] == rows[1]["supportive_device_digest"]
    )
    assert (rows[2]["norm_energy_demand_w"], rows[2]["supportive_device_digest"]) == (None, None)
    assert set(rows[0]) == set(json.loads(RESULT_FIELDS.read_text())["fans"])


def test_conformance_reads_back_each_fan_and_fails_on_a_tampered_row_a_lost_fan_or_an_unreported_one() -> None:
    result = run(document())
    model = reloaded(result)
    fields = result[FAN_SECTION_ID]
    section = FanSection()
    section.conformance(model, fields)
    for key, bad in (
        ("exhaust_flow_rate_m3s", 1.0),
        ("norm_energy_demand_w", 50.0),
        ("digest", "0" * 64),
        ("supportive_device_digest", "0" * 64),
    ):
        tampered = copy.deepcopy(fields)
        tampered["fans"][1][key] = bad
        with pytest.raises(ValueError, match="fan is"):
            section.conformance(model, tampered)
    lost = copy.deepcopy(fields)
    lost["fans"][1]["identifier"] = "fan_ZZZZZZZZZZZZ"
    with pytest.raises(ValueError, match="lost fan"):
        section.conformance(model, lost)
    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {"fans": fields["fans"][:2]})


def test_a_room_missing_a_fans_supportive_device_fails_conformance() -> None:
    result = run(document())
    model = reloaded(result)
    room = next(room for room in model.rooms if room.identifier == ZONE_B)
    hvac = room.properties.ph_hvac
    kept = [device for device in hvac.supportive_devices if device.identifier != F_1]
    hvac.supportive_devices.clear()
    for device in kept:
        hvac.add_supportive_device(device)
    with pytest.raises(ValueError, match="fan is"):
        FanSection().conformance(model, result[FAN_SECTION_ID])


def test_an_unreported_fan_supportive_device_fails_conformance() -> None:
    result = run(document())
    model = reloaded(result)
    stray = stack.load("honeybee_phhvac.supportive_device").PhSupportiveDevice()
    stray.identifier = "fan_ZZZZZZZZZZZZ"
    room = next(room for room in model.rooms if room.identifier == ZONE_B)
    room.properties.ph_hvac.add_supportive_device(stray)
    with pytest.raises(ValueError, match="did not report"):
        FanSection().conformance(model, result[FAN_SECTION_ID])


def test_a_supportive_device_under_a_fan_without_power_fails_conformance() -> None:
    result = run(document())
    model = reloaded(result)
    stray = stack.load("honeybee_phhvac.supportive_device").PhSupportiveDevice()
    stray.identifier = F_2
    room = next(room for room in model.rooms if room.identifier == ZONE_A)
    room.properties.ph_hvac.add_supportive_device(stray)
    with pytest.raises(ValueError, match="fan is"):
        FanSection().conformance(model, result[FAN_SECTION_ID])


def test_a_pump_and_a_fan_on_one_room_are_each_their_own_sections_to_check() -> None:
    result = run(document())
    model = reloaded(result)
    PumpSection().conformance(model, {"pumps": []})
    pump = stack.load("honeybee_phhvac.supportive_device").PhSupportiveDevice()
    pump.identifier = "pmp_AAAAAAAAAAAA"
    room = next(room for room in model.rooms if room.identifier == ZONE_B)
    room.properties.ph_hvac.add_supportive_device(pump)
    FanSection().conformance(model, result[FAN_SECTION_ID])


def test_two_rooms_translated_unequal_under_one_identifier_fail_conformance_on_the_overwritten_room() -> None:
    value = document()
    records(value)[0]["exhaust_flow_rate_m3h"] = 300.0
    result = run(value)
    rows = result[FAN_SECTION_ID]["fans"]
    assert rows[0]["digest"] != rows[1]["digest"]
    with pytest.raises(ValueError, match="fan is"):
        FanSection().conformance(reloaded(result), result[FAN_SECTION_ID])


@pytest.mark.parametrize(
    ("key", "bad"),
    [
        ("exhaust_type", "range_hood"),
        ("quantity", 0),
        ("exhaust_flow_rate_m3h", -1.0),
        ("annual_runtime_minutes", -1.0),
        ("norm_energy_demand_w", -1.0),
        ("annual_period_operation_khrs", None),
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
    [finding] = [row for row in result["findings"] if row["section"] == FAN_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == (
        "object.unavailable",
        records(value)[0]["id"],
        True,
    )
