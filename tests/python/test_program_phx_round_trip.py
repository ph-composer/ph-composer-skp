"""The PHX round trip of the Program export (context/CONTRACTS.md, "Program export"): the canonical HBJSON of the
five journeys tests/program_export_test.rb writes, converted by the pinned PHX of the optional `phx` group to WUFI
XML and METr JSON, reads back per Building Segment the dwelling units, occupants and bedrooms, the lighting and
ventilation PHX takes from each Room's Program, the appliances with their quantities, and the set points, against
the values Ruby derived in the extraction. The School is non-residential, so PHX drops its devices. Skipped
without the group: `uv run --group phx pytest tests/python/test_program_phx_round_trip.py`."""

from __future__ import annotations

import json
import re
from typing import Any

import pytest

from test_certification_sections import run
from test_program_sections import extraction, records
from test_site_phx_round_trip import convert

pytest.importorskip("PHX.from_HBJSON.create_project")


def tags(block: str, tag: str) -> list[str]:
    return re.findall(rf"<{tag}(?: [^>]*)?>([^<]*)</{tag}>", block)


def wufi_variants(xml: str) -> dict[str, str]:
    variants = {}
    for block in re.findall(r"<Variant index=\"\d+\">(.*?)</Variant>", xml, re.S):
        variants[tags(block, "Name")[0]] = block
    return variants


def metr_variants(metr: dict[str, Any]) -> dict[str, str]:
    return {variant["n"]: repr(variant) for variant in metr["lVariant"]}


def metr_values(block: str, key: str) -> list[str]:
    return re.findall(rf"'{key}': ([^,}}]+)", block)


def segment_expectations(value: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Per Building Segment, what Ruby wrote: units, occupants and bedrooms over its Rooms, and its set points."""
    zones = {row["id"]: row for row in value["sections"]["ph_composer.zones.export.zones"]["records"]}
    rooms = records(value, "rooms")
    found: dict[str, dict[str, Any]] = {}
    for point in records(value, "set_points"):
        members = [room for room in rooms if zones[room["id"]]["building_segment"] == point["name"]]
        dwellings = {
            room["dwelling"]["identifier"]: room["dwelling"]["num_dwellings"] for room in members if room["dwelling"]
        }
        found[point["name"]] = {
            "units": max(sum(dwellings.values()), 1),
            "occupants": sum(room["number_people"] for room in members),
            "bedrooms": sum(room["number_bedrooms"] for room in members),
            "set_points": (point["winter_c"], point["summer_c"]),
            "devices": {
                device["identifier"]: sum(
                    other["attributes"]["quantity"]
                    for room in members
                    for other in room["devices"]
                    if other["identifier"] == device["identifier"]
                )
                for room in members
                for device in room["devices"]
            },
        }
    return found


def test_the_five_journeys_read_back_occupancy_devices_ventilation_and_set_points() -> None:
    value = extraction()
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    xml, metr = convert(result)
    wufi, metr_rows = wufi_variants(xml), metr_variants(metr)
    expected = segment_expectations(value)
    assert set(wufi) == set(metr_rows) == set(expected) == {"House", "Apartments", "School"}

    for name, want in expected.items():
        block, metr_block = wufi[name], metr_rows[name]
        assert int(tags(block, "NumberUnits")[0]) == want["units"], name
        assert int(tags(block, "OccupantQuantityUserDef")[0]) == int(want["occupants"]), name
        assert int(tags(block, "NumberBedrooms")[0]) == want["bedrooms"], name
        assert (
            float(tags(block, "IndoorTemperature")[0]),
            float(tags(block, "OverheatingTemperatureThreshold")[0]),
        ) == (want["set_points"]), name
        assert float(metr_values(metr_block, "indoorT")[0]) == want["set_points"][0], name
        assert float(metr_values(metr_block, "overhTLim")[0]) == want["set_points"][1], name
        assert int(metr_values(metr_block, "nUnits")[0]) == want["units"], name
        assert int(metr_values(metr_block, "nOcc")[0]) == int(want["occupants"]), name
        assert int(metr_values(metr_block, "nBedR")[0]) == want["bedrooms"], name

    # No journey's Segment has a blower-door result, so each carries its Programs' infiltration, 0.0003 m³/s per m²
    # of exterior area at 4 Pa, which PHX converts to q50 (create_variant.py).
    q50 = 0.0003 * (50 / 4) ** 0.65 * 3600
    for name, block in wufi.items():
        assert float(tags(block, "EnvelopeAirtightnessCoefficient")[0]) == pytest.approx(q50, abs=0.01), name

    # Journeys 1 to 3: the house's 4 occupants, and the apartments' 3 + 3 by the Phius rule over two Dwellings.
    assert int(tags(wufi["House"], "OccupantQuantityUserDef")[0]) == 4
    assert int(tags(wufi["Apartments"], "OccupantQuantityUserDef")[0]) == 6
    assert int(tags(wufi["Apartments"], "NumberUnits")[0]) == 3, "Apt 1 and Apt 2's two units"

    # Appliances: the default Set merged across the Apartments' Rooms by identifier, 1 + 2 of each; the interior
    # lighting device once; none in the non-residential School.
    devices = {name: re.findall(r"<Device index=\"\d+\">(.*?)</Device>", block, re.S) for name, block in wufi.items()}
    assert len(devices["House"]) == 9, "eight default devices and the interior lighting"
    assert len(devices["Apartments"]) == 11, "the default eight, the Laundry's two and the interior lighting"
    assert devices["School"] == []
    # The School's equipment is its Programs' watts alone: the Lab's Set is left out, so PHX adds no device Process.
    assert "Laundry" not in wufi["School"]
    quantities = sorted(int(tags(device, "Quantity")[0]) for device in devices["Apartments"])
    assert quantities == sorted([3] * 8 + [1, 1, 1]), quantities

    # Ventilation from each Room's Program: the Classroom's per person over 0.25 people/m² × 30 m², the Lab's six
    # air changes over its 60 m³, both in m³/h.
    supply = sorted(float(flow) for flow in tags(wufi["School"], "DesignVolumeFlowRateSupply"))
    assert supply == pytest.approx(sorted([0.0038 * 0.25 * 30 * 3600, 6.0 * 60.0]))
    # Lighting PHX reads per Room: the Classroom's 8 W/m² and the Lab's 10.
    assert sorted(float(power) for power in tags(wufi["School"], "InstalledLightingPower")) == [8.0, 10.0]

    # Residential lighting: each House Room's installed power is its ProgramType's Phius interior rule per m².
    house = next(row for row in records(value, "program_types") if row["name"].startswith("Residential default (House"))
    for power in tags(wufi["House"], "InstalledLightingPower"):
        assert float(power) == pytest.approx(house["lighting"]["watts_per_area"])


def test_the_interior_lighting_device_survives_whichever_room_comes_first() -> None:
    # PHX merges a Segment's Rooms; before 1.59.2 the merged Room kept only its first Room's Lighting, so the
    # Apartments lost the interior lighting device when a Room on a Program without the lighting rule came first
    # (PH-Tools/PHX#171). Reversing the Rooms puts the Laundry, on a Program with no lighting rule, first.
    result = run(extraction())
    model = json.loads(result["canonical_model"]["hbjson"])
    for rooms in (model["rooms"], list(reversed(model["rooms"]))):
        hbjson = json.dumps({**model, "rooms": rooms})
        reordered = dict(result, canonical_model=dict(result["canonical_model"], hbjson=hbjson))
        xml, _metr = convert(reordered)
        block = wufi_variants(xml)["Apartments"]
        devices = re.findall(r"<Device index=\"\d+\">(.*?)</Device>", block, re.S)
        assert len(devices) == 11, [room["display_name"] for room in rooms]


def test_utilization_patterns_read_back_the_schedule_forms() -> None:
    """The ventilation pattern from the Lab's four periods and its six days, in both files; the occupancy pattern of
    the School day from its ruleset, 8 h on 220 days (5 days over 44 weeks) of 8,760 h, as PHX's fallback reads
    every Schedule without periods."""
    xml, metr = convert(run(extraction()))
    vent = re.search(
        r"<UtilizationPatternVent index=\"\d+\">\s*<Name>Lab air</Name>(.*?)</UtilizationPatternVent>", xml, re.S
    )
    assert vent, "the Lab's ventilation pattern"
    block = vent.group(1)
    assert [float(tags(block, tag)[0]) for tag in ("OperatingDays", "OperatingWeeks")] == [6, 52]
    assert [float(tags(block, f"{period}_DOS")[0]) for period in ("Maximum", "Standard", "Basic", "Minimum")] == [
        2,
        10,
        8,
        4,
    ]
    assert [float(tags(block, f"{period}_PDF")[0]) for period in ("Maximum", "Standard", "Basic", "Minimum")] == [
        1.0,
        0.8,
        0.5,
        0.3,
    ]
    lab = next(row for row in metr["lUtilVentPH"] if row["n"] == "Lab air")
    assert (lab["OperDw"], lab["OperWy"], lab["MSBMdf"]) == (6, 52, [[2.0, 1.0], [10.0, 0.8], [8.0, 0.5], [4.0, 0.3]])

    day = re.search(
        r"<UtilizationPattern index=\"\d+\">\s*<IdentNr>\d+</IdentNr>\s*<Name>School day</Name>"
        r"(.*?)</UtilizationPattern>",
        xml,
        re.S,
    )
    assert day, "the School day's occupancy pattern"
    assert float(tags(day.group(1), "RelativeAbsenteeism")[0]) == pytest.approx(1 - 8 * 220 / 8760)
