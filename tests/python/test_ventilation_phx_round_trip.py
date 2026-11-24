"""The PHX round trip of the ventilation section (context/CONTRACTS.md, "Mechanical equipment"): the canonical
HBJSON of the reference model tests/mechanical_export_test.rb writes, both Zones in one Building Segment, each with
its detailed Space, converted by the pinned PHX of the optional `phx` group. PHX merges the Segment's Rooms into one
Variant and keys ventilation devices by identifier: the base case, ERV-1 on Zone A and ERV-2 on Zone B, gives two
devices, and the shared case, ERV-1 on both, gives one, which every Space names. Skipped without the group:
`uv run --group phx pytest tests/python/test_ventilation_phx_round_trip.py`."""

from __future__ import annotations

from typing import Any

import pytest

from test_site_phx_round_trip import metr_builder, xml_builder
from test_ventilation_sections import BASE, SHARED, document, records, reloaded, run

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")


def converted(path: Any) -> tuple[dict[str, Any], Any]:
    value = document(path)
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return value, create_project.convert_hb_model_to_PhxProject(reloaded(result))


def ventilators(variant: Any) -> list[Any]:
    devices = [device for collection in variant.mech_collections for device in collection.devices]
    return [device for device in devices if type(device).__name__ == "PhxDeviceVentilator"]


def metr_names(project: Any) -> list[str]:
    metr = metr_builder.generate_metr_json_dict(project)
    return [device["n"] for system in metr["lVariant"][0]["HVAC"]["lSystem"] for device in system["lDevice"]]


def test_the_base_case_gives_two_ventilation_devices_each_named_by_its_rooms_spaces() -> None:
    value, project = converted(BASE)

    [variant] = project.variants
    devices = {device.display_name: device for device in ventilators(variant)}
    assert sorted(devices) == ["ERV-1", "ERV-2"]
    rows = {row["display_name"]: row for row in records(value)}
    for name, device in devices.items():
        assert device.quantity == rows[name]["quantity"]
        assert device.params.sensible_heat_recovery == rows[name]["sensible_heat_recovery"]
        assert device.params.latent_heat_recovery == rows[name]["latent_heat_recovery"]
        assert device.params.electric_efficiency == rows[name]["electric_efficiency_wh_m3"]
    spaces = [space for zone in variant.building.zones for space in zone.spaces]
    assert len(spaces) == 2
    assert sorted(space.vent_unit_id_num for space in spaces) == sorted(device.id_num for device in devices.values())

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    assert xml.count("<Name>ERV-1</Name>") == 1 and xml.count("<Name>ERV-2</Name>") == 1
    assert sorted(name for name in metr_names(project) if name.startswith("ERV-")) == ["ERV-1", "ERV-2"]


def test_the_shared_case_gives_one_ventilation_device_both_rooms_name() -> None:
    _value, project = converted(SHARED)

    [variant] = project.variants
    [device] = ventilators(variant)
    assert device.display_name == "ERV-1"
    spaces = [space for zone in variant.building.zones for space in zone.spaces]
    assert len(spaces) == 2 and {space.vent_unit_id_num for space in spaces} == {device.id_num}

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    assert xml.count("<Name>ERV-1</Name>") == 1 and "<Name>ERV-2</Name>" not in xml
    assert [name for name in metr_names(project) if name.startswith("ERV-")] == ["ERV-1"]
