"""The PHX round trip of the heat pump section (context/CONTRACTS.md, "Mechanical equipment"): the canonical HBJSON of
the reference model tests/mechanical_heat_pump_export_test.rb writes, Zones A and B in one Building Segment, both
served by the Segment's blended heat pump, converted by the pinned PHX of the optional `phx` group. PHX merges the
Segment's Rooms into one Variant and keys devices by identifier, so the two Rooms give one rated monthly heat pump
with the blend's COPs, its full heating coverage and its recirculation cooling. Skipped without the group:
`uv run --group phx pytest tests/python/test_heat_pumps_phx_round_trip.py`."""

from __future__ import annotations

from typing import Any

import pytest

from test_heat_pump_sections import document, records, reloaded, run
from test_site_phx_round_trip import xml_builder

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")


def converted(value: dict[str, Any]) -> Any:
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return create_project.convert_hb_model_to_PhxProject(reloaded(result))


def heat_pumps(variant: Any) -> list[Any]:
    return [
        device
        for collection in variant.mech_collections
        for device in collection.devices
        if type(device).__name__ == "PhxHeatPumpMonthly"
    ]


def test_two_rooms_of_one_segment_give_one_blended_heat_pump_in_phx() -> None:
    record = records(document())[0]
    project = converted(document())

    [variant] = project.variants
    [device] = heat_pumps(variant)
    assert device.display_name == "Heat pumps: Main"
    params = device.params
    assert (params.COP_1, params.ambient_temp_1, params.COP_2, params.ambient_temp_2) == (
        record["cop_1"],
        -8.333,
        record["cop_2"],
        8.333,
    )
    assert device.usage_profile.space_heating_percent == 1.0
    assert device.usage_profile.cooling_percent == 1.0
    recirculation = device.params_cooling.recirculation
    cooling = record["cooling"]
    assert recirculation.used is True
    assert (recirculation.capacity, recirculation.flow_rate_m3_hr, recirculation.annual_COP) == (
        cooling["capacity_kw"],
        cooling["flow_rate_m3_hr"],
        cooling["annual_cop"],
    )
    assert recirculation.min_coil_temp == 12.0

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    assert xml.count("<Name>Heat pumps: Main</Name>") == 1
    assert "<MaxRecirculationAirCoolingPower>" in xml
