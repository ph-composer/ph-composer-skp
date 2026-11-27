"""The PHX round trip of the Electric Heater section (context/CONTRACTS.md, "Mechanical equipment"): the canonical
HBJSON of the reference model tests/mechanical_electric_heater_export_test.rb writes, Zones A and B in one Building
Segment, each with its Space, EH-1 on both and EH-2 on Zone A, converted by the pinned PHX of the optional `phx`
group. PHX merges the Segment's Rooms into one Variant, reads each Room's heating systems through its Spaces and keys
devices by identifier, so the three pairs give two direct electric heaters, each once, with its coverage as its
space heating share. A Room with no Space contributes no device: a heater on it reaches PHX only through another Room
it serves, which is what `mechanical.zone_without_spaces` says. Skipped without the group:
`uv run --group phx pytest tests/python/test_electric_heaters_phx_round_trip.py`."""

from __future__ import annotations

from typing import Any

import pytest

from test_electric_heater_sections import EH_2, ZONE_B, document, heating, records, reloaded, run
from test_site_phx_round_trip import xml_builder

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

SPACES = "ph_composer.spaces.export.spaces"


def converted(value: dict[str, Any]) -> Any:
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return create_project.convert_hb_model_to_PhxProject(reloaded(result))


def electric_heaters(variant: Any) -> list[Any]:
    return [
        device
        for collection in variant.mech_collections
        for device in collection.devices
        if type(device).__name__ == "PhxHeaterElectric"
    ]


def test_three_pairs_on_two_rooms_give_two_electric_heaters_each_once_in_phx() -> None:
    project = converted(document())

    [variant] = project.variants
    devices = {device.display_name: device for device in electric_heaters(variant)}
    assert len(electric_heaters(variant)) == 2
    assert sorted(devices) == ["EH-1", "EH-2"]
    assert devices["EH-1"].usage_profile.space_heating_percent == 0.6
    assert devices["EH-2"].usage_profile.space_heating_percent == 1.0

    xml = xml_builder.generate_WUFI_XML_from_object(project)
    assert xml.count("<Name>EH-1</Name>") == 1 and xml.count("<Name>EH-2</Name>") == 1


def test_a_heater_only_on_a_room_with_no_spaces_does_not_reach_phx() -> None:
    value = document()
    section = value["sections"][SPACES]
    section["records"] = [row for row in section["records"] if row["zone_id"] != ZONE_B]
    for row in records(value):
        if row["item_id"] == EH_2:
            row["zone_id"], row["id"] = ZONE_B, f"{EH_2}_{ZONE_B}"
    assert sum(EH_2 in systems for systems in heating(run(value)).values()) == 1, "the HBJSON still carries it"
    [variant] = converted(value).variants
    assert sorted(device.display_name for device in electric_heaters(variant)) == ["EH-1"]
