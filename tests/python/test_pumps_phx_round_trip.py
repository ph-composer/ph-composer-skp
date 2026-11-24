"""The PHX round trip of the Pump section (context/CONTRACTS.md, "Mechanical equipment"): the canonical HBJSON of the
reference model tests/mechanical_pump_export_test.rb writes, Zones A and B in one Building Segment, each with its
Space, P-1 on both and P-2 on Zone A, converted by the pinned PHX of the optional `phx` group. PHX merges the
Segment's Rooms into one Variant, reads each Room's supportive devices through its Spaces and keys devices by
identifier, so the three pairs give two supportive devices, each once, with every value as the record has it. A Room
with no Space contributes no device: a pump on it reaches PHX only through another Room it serves, which is what
`mechanical.zone_without_spaces` says. Skipped without the group:
`uv run --group phx pytest tests/python/test_pumps_phx_round_trip.py`."""

from __future__ import annotations

from typing import Any

import pytest

from test_pump_sections import P_1, P_2, ZONE_B, document, records, reloaded, run
from test_site_phx_round_trip import xml_builder

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

SPACES = "ph_composer.spaces.export.spaces"


def converted(value: dict[str, Any]) -> Any:
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return create_project.convert_hb_model_to_PhxProject(reloaded(result))


def pumps(project: Any) -> dict[str, Any]:
    [variant] = project.variants
    found = [device for device in variant.default_mech_collection.supportive_devices]
    by_name = {device.display_name: device for device in found}
    assert len(by_name) == len(found), "each pump once"
    return by_name


def without_zone_b_spaces(value: dict[str, Any]) -> dict[str, Any]:
    """The reference with Zone B's Space taken out, so Room B has no Spaces."""
    section = value["sections"][SPACES]
    section["records"] = [row for row in section["records"] if row["zone_id"] != ZONE_B]
    return value


def test_three_pairs_on_two_rooms_give_two_supportive_devices_each_once_with_their_values() -> None:
    project = converted(document())
    devices = pumps(project)
    assert sorted(devices) == ["P-1", "P-2"]
    one, two = devices["P-1"], devices["P-2"]
    assert (one.identifier, one.device_type.value, one.quantity) == (P_1, 4, 2), "no merge summed its quantity"
    assert (
        one.params.in_conditioned_space,
        one.params.norm_energy_demand_W,
        one.params.annual_period_operation_khrs,
        one.params.ihg_utilization_factor,
        one.params.ihg_usage_profile,
    ) == (True, 45.0, 5.0, 0.5, 2)
    assert (two.identifier, two.device_type.value, two.quantity) == (P_2, 6, 1)
    assert (
        two.params.in_conditioned_space,
        two.params.norm_energy_demand_W,
        two.params.annual_period_operation_khrs,
        two.params.ihg_usage_profile,
    ) == (False, 20.0, 8.76, 3)

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    assert xml.count("<Name>P-1</Name>") == 1 and xml.count("<Name>P-2</Name>") == 1


def test_a_pump_on_a_room_with_spaces_and_one_without_still_reaches_phx_once() -> None:
    devices = pumps(converted(without_zone_b_spaces(document())))
    assert sorted(devices) == ["P-1", "P-2"]
    assert devices["P-1"].quantity == 2


def test_a_pump_only_on_a_room_with_no_spaces_does_not_reach_phx() -> None:
    value = without_zone_b_spaces(document())
    pairs = records(value)
    for row in pairs:
        if row["item_id"] == P_2:
            row["zone_id"], row["id"] = ZONE_B, f"{P_2}_{ZONE_B}"
    assert sorted(pumps(converted(value))) == ["P-1"]
