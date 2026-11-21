"""The Program sections (context/CONTRACTS.md, "Program export") over the five journeys tests/program_export_test.rb
writes: the HBJSON reloads in the pinned stack with one ProgramType per Dwelling for the residential default and one
for a Program with no rule, each Room's People extension and its devices where Ruby put them, each Schedule's
weekday rules, weeks off and ventilation periods, and each Building Segment's set points."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from ph_composer_translation import stack
from test_certification_sections import run

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "programs" / "extraction.json"
#: The result fields each Ruby contributor declares, written by tests/program_export_test.rb.
RESULT_FIELDS = FIXTURE.with_name("result_fields.json")
DEFAULT_PROGRAM = "pgm_PHCDEFAULT01"


def extraction() -> dict[str, Any]:
    return json.loads(FIXTURE.read_text())


def model(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def rooms(result: dict[str, Any]) -> dict[str, Any]:
    return {room.display_name: room for room in model(result).rooms}


def records(value: dict[str, Any], section: str) -> list[dict[str, Any]]:
    return value["sections"][f"ph_composer.programs.export.{section}"]["records"]


def test_the_journeys_reload_with_a_program_type_per_dwelling_and_one_for_a_plain_program() -> None:
    result = run(extraction())
    assert result["summary"]["publishable"] is True, result["findings"]
    by_name = rooms(result)
    types = {name: room.properties.energy.program_type.identifier for name, room in by_name.items()}

    assert len({types[name] for name in ("Living", "Kitchen", "Bedroom")}) == 1, "the house is one Dwelling"
    assert types["Apt 1"] != types["Apt 2"], "each apartment is its own Dwelling"
    assert all(types[name].startswith(f"{DEFAULT_PROGRAM}-") for name in ("Living", "Apt 1", "Apt 2"))
    assert types["Corridor"] == types["Laundry"], "a Program with no rule exports once"
    assert "-" not in types["Corridor"]
    house = by_name["Living"].properties.energy.program_type
    assert house.lighting.properties.ph.ph_equipment.equipment_type == "PhPhiusLightingInterior"
    assert by_name["Corridor"].properties.energy.program_type.lighting.properties.ph.ph_equipment is None


def test_each_room_carries_its_counts_dwelling_and_devices() -> None:
    value = extraction()
    by_name = rooms(run(value))
    people = {name: room.properties.energy.people.properties.ph for name, room in by_name.items()}

    assert (people["Living"].number_bedrooms, people["Living"].number_people) == (3, 4.0), "on the largest Room"
    assert (people["Kitchen"].number_bedrooms, people["Kitchen"].number_people) == (0, 0.0)
    assert people["Living"].dwellings.identifier == people["Kitchen"].dwellings.identifier, "one shared Dwelling"
    assert people["Apt 2"].dwellings.num_dwellings == 2
    assert people["Corridor"].dwellings.num_dwellings == 0, "untagged, as PHX reads a Room in no Dwelling"

    def devices(name: str) -> list[tuple[str, int]]:
        loads = by_name[name].properties.energy.process_loads
        return sorted(
            (load.properties.ph.ph_equipment.equipment_type, load.properties.ph.ph_equipment.quantity) for load in loads
        )

    assert len(devices("Living")) == 8 and devices("Kitchen") == []
    assert {quantity for _type, quantity in devices("Apt 2")} == {2}, "the default Set times two units"
    assert devices("Laundry") == [("PhClothesDryer", 1), ("PhClothesWasher", 1)]
    assert devices("Lab") == [], "a Set in a non-residential Segment is left out: the Program's watts stand for it"
    # The People extension's identifiers are Ruby's, so the HBJSON is the same each run.
    rows = {row["id"]: row for row in records(value, "rooms")}
    for name, room in by_name.items():
        dwelling = rows[room.identifier]["dwelling"]
        if dwelling:
            assert people[name].dwellings.identifier == dwelling["identifier"]


def test_schedules_carry_their_weekday_rules_weeks_off_and_ventilation_periods() -> None:
    schedules = {schedule.display_name: schedule for schedule in model(run(extraction())).properties.energy.schedules}

    day = schedules["School day"]
    assert len(day.schedule_rules) == 2, "the year either side of the summer weeks off"
    first = day.schedule_rules[0]
    assert (first.apply_monday, first.apply_friday, first.apply_saturday, first.apply_sunday) == (
        True,
        True,
        False,
        False,
    )
    assert (first.end_date.month, first.end_date.day) == (7, 3)
    assert (day.schedule_rules[1].start_date.month, day.schedule_rules[1].start_date.day) == (8, 29)
    assert day.default_day_schedule.values == (0.0,), "a day off is off all day"
    assert (day.properties.ph.operating_days_wk, day.properties.ph.operating_weeks_year) == (5, 44)
    assert list(day.properties.ph.daily_operating_periods) == [], "occupancy and lighting carry no periods"

    air = schedules["Lab air"]
    periods = [
        (period.name, period.start_hour, period.end_hour) for period in air.properties.ph.daily_operating_periods
    ]
    assert periods == [("high", 0, 2), ("standard", 2, 12), ("basic", 12, 20), ("minimum", 20, 24)]


def test_each_segment_takes_its_set_points() -> None:
    by_name = rooms(run(extraction()))
    points = {
        name: (
            room.properties.ph.ph_bldg_segment.set_points.winter,
            room.properties.ph.ph_bldg_segment.set_points.summer,
        )
        for name, room in by_name.items()
    }
    assert points["Living"] == (20.0, 25.0)
    assert points["Lab"] == points["Classroom"] == (20.0, 26.0), "the School carries its first Zone's pair"


def test_an_unknown_device_class_refuses_its_room_and_names_the_class() -> None:
    value = extraction()
    room = next(row for row in records(value, "rooms") if row["devices"])
    room["devices"][0]["class"] = "PhToaster"
    result = run(value)
    assert result["summary"]["publishable"] is False
    assert any("PhToaster" in str(finding) for finding in result["findings"])


def test_every_result_row_holds_exactly_the_fields_ruby_declares() -> None:
    result = run(extraction())
    for section, fields in json.loads(RESULT_FIELDS.read_text()).items():
        for field, keys in fields.items():
            rows = result[section][field]
            assert rows, f"{section} {field} has rows"
            assert all(sorted(row) == sorted(keys) for row in rows), f"{section} {field}"


def test_a_fractional_bedroom_count_reaches_the_people_extension_as_entered() -> None:
    value = extraction()
    room = next(row for row in records(value, "rooms") if row["number_bedrooms"] > 0)
    room["number_bedrooms"] = 1.5
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    reloaded = {room.identifier: room for room in model(result).rooms}[room["id"]]
    assert reloaded.properties.energy.people.properties.ph.number_bedrooms == 1.5
    rows = {row["zone_id"]: row for row in result["ph_composer.programs.export.rooms"]["rooms"]}
    assert rows[room["id"]]["number_bedrooms"] == 1.5
