"""The PHX round trip of one Ventilator serving two Zones, written as one honeybee-ph object per (item, Zone) pair
with shared identifiers (test_shared_ventilator.py): the pinned PHX of the optional `phx` group keys the systems
by identifier, so the Building Segment's Variant holds one ventilation device, and each Room's Spaces name it.
PHX reads a Room's ventilation through its Spaces, so each Zone here has one. Skipped without the group:
`uv run --group phx pytest tests/python/test_shared_ventilator_phx_round_trip.py`."""

from __future__ import annotations

import json
from typing import Any

import pytest

from ph_composer_translation import stack
from test_shared_ventilator import ITEM, UNIT, ZONE_A, ZONE_B, extraction, one_space_per_zone, pair, run
from test_site_phx_round_trip import metr_builder, xml_builder

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")


def ventilators(variant: Any) -> list[Any]:
    devices = [device for collection in variant.mech_collections for device in collection.devices]
    return [device for device in devices if type(device).__name__ == "PhxDeviceVentilator"]


def test_one_ventilator_serving_two_zones_is_one_phx_device_both_rooms_name() -> None:
    result = run(extraction(pair(ZONE_A), pair(ZONE_B), spaces=one_space_per_zone()))
    assert result["summary"]["publishable"] is True, result["findings"]
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))

    project = create_project.convert_hb_model_to_PhxProject(model)

    [variant] = project.variants
    [device] = ventilators(variant)
    assert device.quantity == UNIT["quantity"]
    assert device.params.sensible_heat_recovery == UNIT["sensible_heat_recovery"]
    assert device.params.electric_efficiency == UNIT["electric_efficiency"]
    spaces = [space for zone in variant.building.zones for space in zone.spaces]
    assert len(spaces) == 2
    assert {space.vent_unit_id_num for space in spaces} == {device.id_num}
    systems = {room.identifier: room.properties.ph_hvac.ventilation_system for room in model.rooms}
    assert {system.identifier for system in systems.values()} == {ITEM}

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    metr = metr_builder.generate_metr_json_dict(project)
    assert xml.count("<Name>ERV-1</Name>") == 1, "one ventilation device in WUFI XML"
    devices = [device for system in metr["lVariant"][0]["HVAC"]["lSystem"] for device in system["lDevice"]]
    assert [device["n"] for device in devices].count("ERV-1") == 1, "one ventilation device in METr JSON"
