"""The PHX round trip of the ducting section (context/CONTRACTS.md, "Translation sections and artifacts"): the
canonical HBJSON of the reference model tests/ducting_export_test.rb writes with ACCEPTANCE's ERV ducting case, both
Zones in one Building Segment, each with its Space, converted by the pinned PHX of the optional `phx` group. PHX reads
a Room's ventilation system through its Spaces, builds one device per system key and adds every duct element with
that device's id number, keyed by identifier. So the base case, ERV-1 on Zone A and ERV-2 on Zone B, gives two
devices with ERV-1's two ducts and ERV-2's three; the shared case, ERV-1 on both, gives one device and DG-1's two
ducts once. A Room with no Spaces contributes no device and no ducts. Skipped without the group:
`uv run --group phx pytest tests/python/test_ducting_phx_round_trip.py`."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pytest

from test_ducting_sections import BASE, ERV_1, ERV_2, SHARED, ZONE_A, ZONE_B, document, records, reloaded, run

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

SPACES = "ph_composer.spaces.export.spaces"


def converted(value: dict[str, Any]) -> Any:
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return create_project.convert_hb_model_to_PhxProject(reloaded(result))


def without_spaces(path: Path, zones: set[str]) -> dict[str, Any]:
    value = document(path)
    section = value["sections"][SPACES]
    section["records"] = [row for row in section["records"] if row["zone_id"] not in zones]
    return value


def devices_and_ducts(project: Any) -> tuple[dict[str, Any], dict[str, Any]]:
    """The ventilation devices by name and the duct elements by identifier, across the Variant's collections."""
    [variant] = project.variants
    devices = {
        device.display_name: device
        for collection in variant.mech_collections
        for device in collection.devices
        if type(device).__name__ == "PhxDeviceVentilator"
    }
    ducts = {duct.identifier: duct for collection in variant.mech_collections for duct in collection.vent_ducting}
    return devices, ducts


def test_the_base_case_gives_two_devices_with_two_and_three_ducts_sized_in_millimetres() -> None:
    value = document(BASE)
    expected = records(value)
    devices, ducts = devices_and_ducts(converted(value))
    assert sorted(devices) == ["ERV-1", "ERV-2"]
    owners = {ERV_1: devices["ERV-1"].id_num, ERV_2: devices["ERV-2"].id_num}
    for ventilator, owner in owners.items():
        record = expected[ventilator]
        mine = sorted(element["identifier"] for element in record["supply"] + record["exhaust"])
        assert sorted(name for name, duct in ducts.items() if duct.vent_unit_id == owner) == mine
    assert len(ducts) == 5, "ERV-1's two ducts and ERV-2's three"

    round_duct = ducts[expected[ERV_1]["supply"][0]["identifier"]]
    assert (round_duct.duct_type.value, len(round_duct.segments), round(round_duct.length_m, 3)) == (1, 2, 2.5)
    for segment in round_duct.segments:
        assert (round(segment.diameter_mm, 6), segment.width_mm, segment.height_mm) == (160.0, None, None)
        assert (round(segment.insulation_thickness_mm, 6), segment.insulation_conductivity_wmk) == (25.4, 0.04)
        assert segment.insulation_reflective is True
    [rectangular] = ducts[expected[ERV_2]["supply"][0]["identifier"]].segments
    assert (round(rectangular.width_mm, 6), round(rectangular.height_mm, 6)) == (200.0, 100.0)
    assert (round(rectangular.insulation_thickness_mm, 6), rectangular.insulation_conductivity_wmk) == (50.8, 0.035)
    assert rectangular.insulation_reflective is False
    exhaust = [ducts[element["identifier"]] for element in expected[ERV_2]["exhaust"]]
    assert [(duct.duct_type.value, round(duct.length_m, 3), duct.quantity) for duct in exhaust] == [(2, 1.5, 1)] * 2


def test_the_shared_case_gives_one_device_and_dg_1s_two_ducts_once() -> None:
    value = document(SHARED)
    devices, ducts = devices_and_ducts(converted(value))
    assert sorted(devices) == ["ERV-1"]
    record = records(value)[ERV_1]
    assert sorted(ducts) == sorted(element["identifier"] for element in record["supply"] + record["exhaust"])
    assert {duct.vent_unit_id for duct in ducts.values()} == {devices["ERV-1"].id_num}


def test_a_ventilator_on_a_room_with_no_spaces_gives_no_device_and_no_ducts() -> None:
    devices, ducts = devices_and_ducts(converted(without_spaces(BASE, {ZONE_B})))
    assert sorted(devices) == ["ERV-1"]
    assert {duct.vent_unit_id for duct in ducts.values()} == {devices["ERV-1"].id_num}
    assert len(ducts) == 2

    devices, ducts = devices_and_ducts(converted(without_spaces(BASE, {ZONE_A, ZONE_B})))
    assert (devices, ducts) == ({}, {})
