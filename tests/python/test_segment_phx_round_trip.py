"""The PHX round trip of a Zone left out of every Building Segment (context/CONTRACTS.md, "Building Segments at
export"): the canonical HBJSON of the two-Segment reference that tests/segment_export_rules_test.rb writes, with
the ADU Zone moved out and made the Attached zone of the two walls it shares with Living and Kitchen. Converted
by the pinned PHX of the optional `phx` group, WUFI XML and METr JSON each carry one Variant, House, with the ADU
as one attached zone, though two Rooms name it, and both walls exposed to it.
Skipped without the group: `uv run --group phx pytest tests/python/test_segment_phx_round_trip.py`."""

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from test_shade_phx_round_trip import metr_components, wufi_components
from test_shade_sections import reloaded, run
from test_site_phx_round_trip import convert

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "segments" / "extraction.json"


def wufi_zones(xml: str) -> list[dict[str, str]]:
    """Each WUFI XML Zone's name, number, kind and attached-zone factor."""
    rows = []
    for block in re.findall(r"<Zone index=\"\d+\">(.*?)</Zone>", xml, re.S):
        tags = ("Name", "IdentNr", "KindZone", "KindAttachedZone", "TemperatureReductionFactorUserDefined")
        found = {tag: re.search(rf"<{tag}>([^<]*)</{tag}>", block) for tag in tags}
        rows.append({tag: match.group(1) if match else "" for tag, match in found.items()})
    return rows


def test_the_left_out_adu_reaches_wufi_xml_and_metr_json_once_as_the_attached_zone_of_both_walls() -> None:
    result = run(json.loads(FIXTURE.read_text()))
    assert result["summary"]["publishable"] is True
    model = reloaded(result)
    boundaries = [face.boundary_condition for room in model.rooms for face in room.faces]
    attached = [boundary for boundary in boundaries if type(boundary).__name__ == "PhAdditionalZone"]
    assert {(b.identifier, b.zone_name, b.temperature_reduction_factor) for b in attached} == {
        (attached[0].identifier, "ADU", 0.95)
    }
    holding = [room for room in model.rooms if any(face.boundary_condition in attached for face in room.faces)]
    assert sorted(room.display_name for room in holding) == ["Kitchen", "Living"]
    segments = {room.properties.ph.ph_bldg_segment.identifier for room in model.rooms}
    assert result["ph_composer.climate.export.site"]["building_segments"] == len(segments) == 1

    project = create_project.convert_hb_model_to_PhxProject(model)
    assert len(project.variants) == 1
    xml, metr = convert(result)

    # One attached zone for two Rooms: PHX merges a Segment's Rooms before it collects their attached zones.
    zones = wufi_zones(xml)
    assert [(row["Name"], row["KindZone"], row["KindAttachedZone"]) for row in zones] == [
        ("House", "1", "0"),
        ("ADU", "2", "1"),
    ]
    adu = zones[1]
    assert adu["TemperatureReductionFactorUserDefined"] == "0.95"
    # The House's appliances stay on the House: before 1.59.2 PHX copied every device onto each attached zone too
    # (PH-Tools/PHX#171).
    blocks = re.findall(r"<Zone index=\"\d+\">(.*?)</Zone>", xml, re.S)
    assert [len(re.findall(r"<Device index=", block)) for block in blocks] == [9, 0]
    exposed = [row for row in wufi_components(xml) if row["OuterAttachment"] == adu["IdentNr"]]
    assert [row["InnerAttachment"] for row in exposed] == ["1"]

    building = metr["lVariant"][0]["building"]
    assert [(zone["n"], zone["typeZ"]) for zone in building["lZone"]] == [("House", 1), ("ADU", 2)]
    # METr carries the attached zone but not its factor: PHX's writer leaves its default of 1.0.
    assert building["lZone"][1]["desCondZ"]["TRedUD"] == 1.0
    walls = [row for row in metr_components(metr) if row["idEC"] == building["lZone"][1]["id"]]
    assert [round(row["areaC"], 6) for row in walls] == [24.0]
