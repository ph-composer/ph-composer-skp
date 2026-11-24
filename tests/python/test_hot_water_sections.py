"""The hot water section (context/CONTRACTS.md, "Mechanical equipment") over the reference model
tests/mechanical_hot_water_export_test.rb writes: HWS-1 serves Zones A and B with 8 tap points, storage Tanks T1 and
T2, the buffer Tank T3 and two Heaters, H-E (electric) and H-HP (annual heat pump). Each pair builds its own
`PhHotWaterSystem` with fresh tanks and heaters under the records' ids; the exact HBJSON reloads with both Rooms holding
those slots, heaters, tap points and honeybee-ph's recirculation defaults, and the section's conformance compares each
reloaded Room with its own row's digest, so two Rooms translated unequal under one identifier fail it."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.contract.mechanical_records import TANK_FIELDS, VARIANT_FIELDS
from ph_composer_translation.coordinator import translate
from ph_composer_translation.mechanical_sections import (
    CALC_METHOD_ATTRIBUTE,
    HEATER_ATTRIBUTES,
    HEATER_CLASSES,
    HOT_WATER_SECTION_ID,
    METHOD_NOT_EXPORTED,
    TANK_ATTRIBUTES,
    HotWaterSection,
    TranslatedHotWater,
    hot_water_system,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "mechanical"
GOLDEN = FIXTURES / "hot_water_extraction.json"
#: The result fields the Ruby contributor declares, written by the same Ruby test.
RESULT_FIELDS = FIXTURES / "hot_water_result_fields.json"
#: Whether the Ruby System rows say the export writes a piping calculation method, written by the same Ruby test.
METHOD = FIXTURES / "hot_water_method.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
HWS_1 = "hws_FIXED0000005"
H_E = "hwh_FIXED0000003"
H_HP = "hwh_FIXED0000004"
T1, T2, T3 = "hwt_FIXED0000007", "hwt_FIXED0000008", "hwt_FIXED0000009"


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads(GOLDEN.read_text()))


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][HOT_WATER_SECTION_ID]["records"])


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def systems(result: dict[str, Any]) -> dict[str, Any]:
    return {room.identifier: room.properties.ph_hvac.hot_water_system for room in reloaded(result).rooms}


def test_each_pair_builds_its_own_system_with_fresh_tanks_and_heaters_under_the_records_ids() -> None:
    translation = translate(document(), SECTIONS)
    built = translation.results[HOT_WATER_SECTION_ID].objects
    first, second = (cast(TranslatedHotWater, built[key]).system for key in sorted(built))
    assert first is not second and first.tank_1 is not second.tank_1, "one object per (item, Zone) pair"
    assert not {id(heater) for heater in first.heaters} & {id(heater) for heater in second.heaters}
    assert first.identifier == second.identifier == HWS_1
    assert [tank and tank.identifier for tank in first.tanks] == [T1, T2, T3, None]
    assert sorted(heater.identifier for heater in first.heaters) == [H_E, H_HP]
    assert first.to_dict() == second.to_dict(), "every object of one System is equal"
    assert not list(first.distribution_piping) and not list(first.recirc_piping), "no piping written here"


def test_the_reference_reloads_with_both_rooms_holding_the_slots_heaters_taps_and_recirculation_defaults() -> None:
    value = document()
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)

    by_room = systems(result)
    assert sorted(by_room) == [ZONE_A, ZONE_B]
    for system in by_room.values():
        assert system.identifier == HWS_1 and system.display_name == "HWS-1"
        assert [tank and tank.identifier for tank in system.tanks] == [T1, T2, T3, None]
        assert [system.tank_1.storage_capacity, system.tank_2.storage_capacity] == [300.0, 200.0]
        assert (system.tank_buffer.storage_capacity, system.tank_buffer.tank_type) == (80.0, "1-DHW AND HEATING")
        assert (system.tank_buffer.standby_losses, system.tank_2.standby_losses) == (1.5, 3.0)
        heaters = {heater.identifier: heater for heater in system.heaters}
        assert sorted(heaters) == [H_E, H_HP]
        assert type(heaters[H_E]).__name__ == "PhHvacHotWaterHeaterElectric"
        assert (heaters[H_E].percent_coverage, heaters[H_E].in_conditioned_space) == (0.3, True)
        assert type(heaters[H_HP]).__name__ == "PhHvacHotWaterHeaterHeatPump_Annual"
        assert (heaters[H_HP].percent_coverage, heaters[H_HP].total_system_perf_ratio) == (0.7, 2.5)
        assert system.number_tap_points == 8
        assert (system.recirc_temp, system.recirc_hours) == (60.0, 24), "read-only, from piping, none yet"
    rows = result[HOT_WATER_SECTION_ID]["hot_water"]
    assert [(row["zone_id"], row["zone_name"], row["system_identifier"]) for row in rows] == [
        (ZONE_A, "Zone A", HWS_1),
        (ZONE_B, "Zone B", HWS_1),
    ]
    assert rows[0]["digest"] == rows[1]["digest"]


def test_conformance_reads_back_each_slot_and_fails_on_a_tampered_row_or_an_unreported_system() -> None:
    result = run(document())
    model = reloaded(result)
    fields = result[HOT_WATER_SECTION_ID]
    section = HotWaterSection()
    section.conformance(model, fields)

    for key, bad in (
        ("tank_1_identifier", T2),
        ("tank_2_capacity_l", 250.0),
        ("number_tap_points", 6),
        ("heater_identifiers", [H_E]),
        ("digest", "0" * 64),
    ):
        tampered = copy.deepcopy(fields)
        tampered["hot_water"][1][key] = bad
        with pytest.raises(ValueError, match="hot water system is"):
            section.conformance(model, tampered)

    with pytest.raises(ValueError, match="did not report"):
        section.conformance(model, {"hot_water": fields["hot_water"][:1]})


def test_two_rooms_translated_unequal_under_one_identifier_fail_conformance_on_the_overwritten_room() -> None:
    value = document()
    records(value)[0]["tank_1"]["storage_capacity_l"] = 250.0
    result = run(value)
    rows = result[HOT_WATER_SECTION_ID]["hot_water"]
    assert rows[0]["digest"] != rows[1]["digest"]
    by_room = systems(result)
    assert by_room[ZONE_A].tank_1.storage_capacity == by_room[ZONE_B].tank_1.storage_capacity, (
        "honeybee-ph keeps one system for the shared identifier, hiding the difference"
    )
    with pytest.raises(ValueError, match="hot water system is"):
        HotWaterSection().conformance(reloaded(result), result[HOT_WATER_SECTION_ID])


def test_a_piping_calculation_method_is_left_out_with_a_finding_on_the_pinned_wheel() -> None:
    value = document()
    for record in records(value):
        record["piping_calc_method"] = 2
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    assert [(row["code"], row["object_id"], row["blocks_export"]) for row in result["findings"]] == [
        (METHOD_NOT_EXPORTED, HWS_1, False)
    ], "once per System, not per pair"
    hbjson = result["canonical_model"]["hbjson"]
    assert CALC_METHOD_ATTRIBUTE not in hbjson and "calc_method" not in hbjson
    check(result["canonical_model"], result, SECTIONS)


def test_the_system_rows_say_what_the_pinned_wheel_does_with_a_calculation_method() -> None:
    """The panel's System rows note an unexported method from a Ruby flag; this holds the flag to the loaded class,
    so a wheel that gains the field fails here until the flag flips."""
    record = HotWaterSection().read({**records(document())[0], "piping_calc_method": 1})
    _system, written = hot_water_system(record)
    assert json.loads(METHOD.read_text())["method_exported"] is written


def test_a_class_that_takes_and_writes_the_method_receives_it(monkeypatch: pytest.MonkeyPatch) -> None:
    """A stand-in for a future wheel: the field exists and `to_dict` writes it. One that only has the attribute, and
    leaves it out of the dictionary, still counts as not written."""
    module = stack.load("honeybee_phhvac.hot_water_system")

    class Silent(module.PhHotWaterSystem):  # type: ignore[misc, name-defined]
        piping_calc_method: int | None = None

    class Writes(Silent):
        def to_dict(self, abridged: bool = False, _include_properties: bool = False) -> dict[str, Any]:
            return {**super().to_dict(abridged, _include_properties), CALC_METHOD_ATTRIBUTE: self.piping_calc_method}

    record = HotWaterSection().read({**records(document())[0], "piping_calc_method": 3})
    monkeypatch.setattr(module, "PhHotWaterSystem", Silent)
    system, written = hot_water_system(record)
    assert not written and getattr(system, CALC_METHOD_ATTRIBUTE) == 3
    monkeypatch.setattr(module, "PhHotWaterSystem", Writes)
    system, written = hot_water_system(record)
    assert written and system.to_dict()[CALC_METHOD_ATTRIBUTE] == 3


@pytest.mark.parametrize(
    ("path", "bad", "label"),
    [
        (("tank_1", "standby_fraction"), 1.2, "standby_fraction"),
        (("tank_1", "tank_type"), "2-DHW only", "tank_type"),
        (("tank_2", "quantity"), 0, "quantity"),
        (("heaters", 1, "total_system_perf_ratio"), None, "total_system_perf_ratio"),
        (("heaters", 0, "cop_1"), 2.5, "takes no cop_1"),
        (("heaters", 0, "variant"), "boiler", "variant"),
        (("number_tap_points",), 0, "number_tap_points"),
        (("piping_calc_method",), 5, "piping_calc_method"),
    ],
)
def test_a_bad_record_value_is_a_record_error_that_blocks_its_pair(
    path: tuple[Any, ...], bad: object, label: str
) -> None:
    value = document()
    target: Any = records(value)[0]
    for step in path[:-1]:
        target = target[step]
    target[path[-1]] = bad
    result = run(value)
    assert result["summary"]["publishable"] is False
    [finding] = [row for row in result["findings"] if row["section"] == HOT_WATER_SECTION_ID]
    assert (finding["code"], finding["object_id"], finding["blocks_export"]) == (
        "object.unavailable",
        records(value)[0]["id"],
        True,
    )
    assert label in finding["message"]


def test_tank_and_heater_user_data_ride_on_their_objects() -> None:
    value = document()
    for record in records(value):
        record["tank_1"]["user_data"] = {"maker_ref": "T-300"}
        record["heaters"][1]["user_data"] = {"maker_ref": "HP-1"}
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    system = systems(result)[ZONE_A]
    assert system.tank_1.user_data == {"maker_ref": "T-300"}
    assert {heater.identifier: heater.user_data for heater in system.heaters} == {H_E: {}, H_HP: {"maker_ref": "HP-1"}}

    records(value)[0]["tank_1"]["user_data"] = {"ph_composer": {"x": 1}}
    assert run(value)["summary"]["publishable"] is False, "the reserved key is refused"


def test_the_golden_names_every_tank_and_heater_value_this_section_reads() -> None:
    """Ruby writes every Tank value and every Heater efficiency value, null where the variant takes none, so a name
    changed on one side fails here."""
    record = records(document())[0]
    identity = {"identifier", "display_name"}
    assert set(record["tank_1"]) == identity | set(TANK_FIELDS)
    efficiency = {key for fields in VARIANT_FIELDS.values() for key in fields}
    for heater in record["heaters"]:
        assert set(heater) == identity | {"variant", "percent_coverage", "in_conditioned_space"} | efficiency
    assert set(TANK_ATTRIBUTES) == set(TANK_FIELDS) and set(HEATER_ATTRIBUTES) == efficiency
    assert set(HEATER_CLASSES) == set(VARIANT_FIELDS)


def test_each_row_has_exactly_the_fields_the_ruby_contributor_declares() -> None:
    declared = json.loads(RESULT_FIELDS.read_text())["hot_water"]
    rows = run(document())[HOT_WATER_SECTION_ID]["hot_water"]
    assert rows and all(sorted(row) == sorted(declared) for row in rows)
