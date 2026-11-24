"""The PHX round trip of the Fan section (context/CONTRACTS.md, "Mechanical equipment"): the canonical HBJSON of the
reference model tests/mechanical_fan_export_test.rb writes, Zones A and B in one Building Segment, each with its Space,
F-1 (two kitchen hoods with Power) on both and F-2 (a dryer without Power) on Zone A, converted by the pinned PHX of the
optional `phx` group. PHX merges the Segment's Rooms into one Variant and reads each Room's exhaust ventilators and
supportive devices through its Spaces, keying each by identifier. So one Fan record with Power becomes two PHX objects,
an exhaust device on the simulated Zone and a supportive device in the Variant's mechanical collection, and one without
Power becomes one. PHX 1.59.4 does not copy an exhaust ventilator's quantity (`create_hvac.build_phx_exh_vent_*`), so
the quantity is asserted on the supportive device only. A Room with no Space contributes neither: a fan on it reaches
PHX only through another Room it serves, which is what `mechanical.zone_without_spaces` says. Skipped without the
group: `uv run --group phx pytest tests/python/test_fans_phx_round_trip.py`."""

from __future__ import annotations

from typing import Any

import pytest

from test_fan_sections import F_1, F_2, ZONE_B, document, records, reloaded, run
from test_site_phx_round_trip import xml_builder

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

SPACES = "ph_composer.spaces.export.spaces"


def converted(value: dict[str, Any]) -> Any:
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return create_project.convert_hb_model_to_PhxProject(reloaded(result))


def exhausts(project: Any) -> dict[str, Any]:
    """The Variant's exhaust devices by name, from its one simulated Zone."""
    [variant] = project.variants
    [zone] = variant.zones
    found = zone.exhaust_ventilator_collection.devices
    by_name = {device.display_name: device for device in found}
    assert len(by_name) == len(found), "each fan once"
    return by_name


def supportive(project: Any) -> dict[str, Any]:
    [variant] = project.variants
    found = list(variant.default_mech_collection.supportive_devices)
    by_name = {device.display_name: device for device in found}
    assert len(by_name) == len(found), "each fan's supportive device once"
    return by_name


def without_zone_b_spaces(value: dict[str, Any]) -> dict[str, Any]:
    """The reference with Zone B's Space taken out, so Room B has no Spaces."""
    section = value["sections"][SPACES]
    section["records"] = [row for row in section["records"] if row["zone_id"] != ZONE_B]
    return value


def test_one_fan_with_power_becomes_two_phx_objects_and_one_without_becomes_one() -> None:
    project = converted(document())
    vents = exhausts(project)
    assert sorted(vents) == ["F-1", "F-2"]
    hood, dryer = vents["F-1"], vents["F-2"]
    assert type(hood).__name__ == "PhxExhaustVentilatorRangeHood"
    assert hood.params.exhaust_flow_rate_m3h == pytest.approx(250.0)
    assert hood.params.annual_runtime_minutes == 10950.0
    assert type(dryer).__name__ == "PhxExhaustVentilatorDryer"
    assert (dryer.params.exhaust_flow_rate_m3h, dryer.params.annual_runtime_minutes) == (pytest.approx(100.0), 6000.0)

    devices = supportive(project)
    assert sorted(devices) == ["F-1"], "F-2 has no Power, so no supportive device"
    power = devices["F-1"]
    assert (power.identifier, power.device_type.value, power.quantity) == (F_1, 10, 2)
    assert (
        power.params.in_conditioned_space,
        power.params.norm_energy_demand_W,
        power.params.annual_period_operation_khrs,
    ) == (True, 120.0, 0.1825)

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    assert xml.count("<Name>F-1</Name>") == 2, "the hood is one exhaust device and one supportive device"
    assert xml.count("<Name>F-2</Name>") == 1, "the dryer is one exhaust device"


def test_a_fan_on_a_room_with_spaces_and_one_without_still_reaches_phx_once() -> None:
    project = converted(without_zone_b_spaces(document()))
    assert sorted(exhausts(project)) == ["F-1", "F-2"]
    assert sorted(supportive(project)) == ["F-1"]


def test_a_fan_only_on_a_room_with_no_spaces_does_not_reach_phx() -> None:
    value = without_zone_b_spaces(document())
    for row in records(value):
        if row["item_id"] == F_2:
            row["zone_id"], row["id"] = ZONE_B, f"{F_2}_{ZONE_B}"
            row["norm_energy_demand_w"] = 30.0
    project = converted(value)
    assert sorted(exhausts(project)) == ["F-1"]
    assert sorted(supportive(project)) == ["F-1"], "neither of F-2's two objects reaches PHX"
