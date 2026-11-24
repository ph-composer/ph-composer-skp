"""The PHX round trip of the hot water section (context/CONTRACTS.md, "Mechanical equipment"): the canonical HBJSON
of the reference model tests/mechanical_hot_water_export_test.rb writes, Zones A and B in one Building Segment, each
with its detailed Space and both served by HWS-1, converted by the pinned PHX of the optional `phx` group. PHX merges
the Segment's Rooms into one Variant and keys tanks and heaters by identifier, so the two Rooms' one System gives its
three tanks and its heaters once, with its 8 tap points and honeybee-ph's recirculation defaults. A monthly and an
inside heat pump added to the System show which values PHX reads for each kind. Skipped without the group:
`uv run --group phx pytest tests/python/test_hot_water_phx_round_trip.py`."""

from __future__ import annotations

from typing import Any

import pytest

from test_hot_water_sections import document, records, reloaded, run
from test_site_phx_round_trip import metr_builder, xml_builder

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

MONTHLY = {
    "identifier": "hwh_FIXED0000098",
    "display_name": "H-M",
    "variant": "heat_pump_monthly",
    "percent_coverage": 0.2,
    "in_conditioned_space": False,
    "cop_1": 2.1,
    "ambient_temp_1_c": -8.333,
    "cop_2": 3.4,
    "ambient_temp_2_c": 8.333,
}
INSIDE = {
    "identifier": "hwh_FIXED0000099",
    "display_name": "H-IN",
    "variant": "heat_pump_inside",
    "percent_coverage": 0.1,
    "in_conditioned_space": True,
    "annual_energy_factor": 3.3,
}


def converted(value: dict[str, Any]) -> Any:
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return create_project.convert_hb_model_to_PhxProject(reloaded(result))


def devices(variant: Any, *kinds: str) -> dict[str, Any]:
    found = [device for collection in variant.mech_collections for device in collection.devices]
    named = [device for device in found if type(device).__name__ in kinds]
    names = [device.display_name for device in named]
    assert len(names) == len(set(names)), f"each device once: {names}"
    return {device.display_name: device for device in named}


def metr_names(project: Any) -> list[str]:
    metr = metr_builder.generate_metr_json_dict(project)
    return [device["n"] for system in metr["lVariant"][0]["HVAC"]["lSystem"] for device in system["lDevice"]]


def test_the_two_rooms_one_system_gives_its_tanks_and_heaters_once_with_its_taps_and_recirculation() -> None:
    project = converted(document())

    [variant] = project.variants
    tanks = devices(variant, "PhxHotWaterTank")
    assert sorted(tanks) == ["T1", "T2", "T3"]
    assert [tanks[name].params.storage_capacity for name in ("T1", "T2", "T3")] == [300.0, 200.0, 80.0]
    assert [tanks[name].params.standby_losses for name in ("T1", "T2", "T3")] == [4.0, 3.0, 1.5]
    heaters = devices(variant, "PhxHeaterElectric", "PhxHeatPumpAnnual")
    assert sorted(heaters) == ["H-E", "H-HP"]
    assert heaters["H-E"].usage_profile.dhw_heating_percent == 0.3
    assert (heaters["H-HP"].usage_profile.dhw_heating_percent, heaters["H-HP"].params.total_system_perf_ratio) == (
        0.7,
        2.5,
    )
    collection = variant.default_mech_collection
    assert collection._distribution_num_hw_tap_points == 8
    recirculation = collection._distribution_hw_recirculation_params
    assert (recirculation.water_temp, recirculation.daily_recirc_hours) == (60.0, 24)

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    for name in ("T1", "T2", "T3", "H-E", "H-HP"):
        assert xml.count(f"<Name>{name}</Name>") == 1, name
    names = metr_names(project)
    assert sorted(name for name in names if name in {"T1", "T2", "T3", "H-E", "H-HP"}) == [
        "H-E",
        "H-HP",
        "T1",
        "T2",
        "T3",
    ]


def test_a_monthly_and_an_inside_heat_pump_carry_the_values_phx_reads_for_each_kind() -> None:
    value = document()
    for record in records(value):
        record["heaters"] += [dict(MONTHLY), dict(INSIDE)]
    project = converted(value)

    [variant] = project.variants
    heaters = devices(variant, "PhxHeaterElectric", "PhxHeatPumpAnnual", "PhxHeatPumpMonthly", "PhxHeatPumpHotWater")
    assert sorted(heaters) == ["H-E", "H-HP", "H-IN", "H-M"]
    monthly = heaters["H-M"].params
    assert (monthly.COP_1, monthly.ambient_temp_1, monthly.COP_2, monthly.ambient_temp_2) == (2.1, -8.333, 3.4, 8.333)
    inside = heaters["H-IN"].params
    assert (inside.annual_energy_factor, inside.annual_COP, inside.total_system_perf_ratio) == (3.3, None, None)
    annual = heaters["H-HP"].params
    assert (annual.total_system_perf_ratio, annual.annual_COP) == (2.5, None)
    assert heaters["H-IN"].usage_profile.dhw_heating_percent == 0.1
