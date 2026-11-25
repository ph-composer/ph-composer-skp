"""The PHX round trip of the piping section (context/CONTRACTS.md, "Translation sections and artifacts"): the
canonical HBJSON of the reference model tests/piping_export_test.rb writes, Zones A and B in one Building Segment, each
with its Space and both served by HWS-1 carrying the hot water piping case, converted by the pinned PHX of the optional
`phx` group. PHX reads a Room's piping through its Spaces, keys trunks and recirculation elements by identifier, and
takes the recirculation temperature and hours from the Rooms' values, so the two Rooms' one System gives its trunk,
each branch and twig, and each recirculation element once, with the multiplier, demand recirculation and the Ruby
recirculation values. A Room with no Spaces contributes no piping. Skipped without the group:
`uv run --group phx pytest tests/python/test_piping_phx_round_trip.py`."""

from __future__ import annotations

from typing import Any

import pytest

from test_piping_sections import ZONE_B, document, records, reloaded, run
from test_site_phx_round_trip import xml_builder

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

SPACES = "ph_composer.spaces.export.spaces"


def converted(value: dict[str, Any]) -> Any:
    result = run(value)
    assert result["summary"]["publishable"] is True, result["findings"]
    return create_project.convert_hb_model_to_PhxProject(reloaded(result))


def without_spaces(value: dict[str, Any], zones: set[str]) -> dict[str, Any]:
    section = value["sections"][SPACES]
    section["records"] = [row for row in section["records"] if row["zone_id"] not in zones]
    return value


def collection(project: Any) -> Any:
    [variant] = project.variants
    return variant.default_mech_collection


def test_two_rooms_one_system_give_the_tree_and_the_recirculation_once_with_ruby_values() -> None:
    value = document()
    [record] = records(value)
    mechanical = collection(converted(value))

    [trunk] = mechanical.dhw_distribution_trunks
    assert (trunk.identifier, trunk.multiplier, trunk.demand_recirculation) == (
        record["trunks"][0]["identifier"],
        12,
        False,
    )
    assert round(trunk.pipe_element.length_m, 3) == 9.0
    assert sorted(round(branch.pipe_element.length_m, 3) for branch in trunk.branches) == [3.0, 4.0, 4.0]
    assert [len(branch.fixtures) for branch in trunk.branches] == [2, 2, 2]
    twigs = [fixture.identifier for branch in trunk.branches for fixture in branch.fixtures]
    assert len(twigs) == len(set(twigs)) == 6, "each twig once"
    segment = trunk.pipe_element.segments[0]
    assert (segment.pipe_material.value, segment.diameter_m, segment.insulation_thickness_m) == (6, 0.01905, 0.0127)

    recirculation = mechanical.dhw_recirc_piping
    assert sorted(element.identifier for element in recirculation) == sorted(
        element["identifier"] for element in record["recirculation"]
    )
    params = mechanical._distribution_hw_recirculation_params
    assert (params.water_temp, params.daily_recirc_hours) == (
        record["recirculation_temperature_c"],
        record["recirculation_hours"],
    )
    assert mechanical._distribution_num_hw_tap_points == 8

    xml = xml_builder.generate_WUFI_XML_from_object(converted(document()))
    assert xml.count("<Name>Trunk 1</Name>") == 1


def test_a_room_with_no_spaces_contributes_no_piping() -> None:
    mechanical = collection(converted(without_spaces(document(), {ZONE_B})))
    assert len(mechanical.dhw_distribution_trunks) == 1, "Room A still carries the System"

    mechanical = collection(converted(without_spaces(document(), {"zon_AAAAAAAAAAAA", ZONE_B})))
    assert not mechanical.dhw_distribution_trunks and not mechanical.dhw_recirc_piping
