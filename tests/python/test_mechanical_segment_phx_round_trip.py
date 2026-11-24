"""The PHX round trip of each Building Segment's mechanical settings (context/CONTRACTS.md, "Building Segment
settings"): the canonical HBJSON of the two-Segment extraction tests/segment_mechanical_test.rb writes, Main with every
value entered and Annex with none, converted by the pinned PHX of the optional `phx` group. Each Segment is its own
Variant, whose building data carries mechanical cooling, the mechanical room temperature and summer ventilation as
entered, or honeybee-ph's defaults; the WUFI XML and METr JSON carry the room temperature and the bypass mode (PHX
writes mechanical cooling to neither) and Programs' set points unchanged.
Skipped without the group: `uv run --group phx pytest tests/python/test_mechanical_segment_phx_round_trip.py`."""

from __future__ import annotations

import json
from typing import Any

import pytest

from test_mechanical_segment_sections import document, run
from test_site_phx_round_trip import convert, wufi

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

#: Each Variant's values, by its Segment's name: mechanical cooling, the room temperature, the bypass mode number and
#: the ventilation system, daytime window and nighttime window air changes.
EXPECTED = {
    "Main": (True, 18.5, 2, 0.3, 0.5, 1.2),
    "Annex": (False, 20.0, 4, None, 0.0, 0.0),
}


def building_data(project: Any) -> dict[str, Any]:
    return {variant.name: variant.phius_cert.ph_building_data for variant in project.variants}


def test_each_variant_carries_its_segments_mechanical_settings() -> None:
    result = run(document())
    assert result["summary"]["publishable"] is True, result["findings"]
    stack_model = json.loads(result["canonical_model"]["hbjson"])
    assert len(stack_model["properties"]["ph"]["bldg_segments"]) == 2

    project = create_project.convert_hb_model_to_PhxProject(_reloaded(result))
    found = {
        name: (
            data.setpoints.mechanical_cooling,
            data.mech_room_temp,
            data.summer_ventilation.summer_bypass_mode.value,
            data.summer_ventilation.ventilation_system_ach,
            data.summer_ventilation.daytime_window_ach,
            data.summer_ventilation.nighttime_window_ach,
        )
        for name, data in building_data(project).items()
    }
    assert found == EXPECTED
    for name, data in building_data(project).items():
        assert (data.setpoints.winter, data.setpoints.summer) == (19.0, 26.0), name

    xml, metr = convert(result)
    assert sorted(float(value) for value in wufi(xml, "MechanicalRoomTemperature")) == [18.5, 20.0]
    assert sorted(int(value) for value in wufi(xml, "SummerHRVHumidityRecovery")) == [2, 4]
    assert sorted(float(value) for value in wufi(xml, "IndoorTemperature")) == [19.0, 19.0]
    blocks = [block for variant in metr["lVariant"] for block in _with(variant, "mechRT")]
    assert sorted((block["mechRT"], block["sumHRec"]) for block in blocks) == [(18.5, 2), (20.0, 4)]


def _reloaded(result: dict[str, Any]) -> Any:
    from ph_composer_translation import stack

    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def _with(node: Any, key: str) -> list[dict[str, Any]]:
    """Every object under `node` that holds `key`."""
    if isinstance(node, dict):
        return ([node] if key in node else []) + [found for value in node.values() for found in _with(value, key)]
    if isinstance(node, list):
        return [found for item in node for found in _with(item, key)]
    return []
