"""The PHX round trip of the exported Site (context/CONTRACTS.md, "Translation sections and artifacts"): the
canonical HBJSON of the reference models, converted by the pinned PHX of the optional `phx` group to WUFI XML
and METr JSON, reads back the latitude, both elevations, the climate zone, the monthly rows and the four
peak-load cases. Skipped without the group: `uv run --group phx pytest tests/python/test_site_phx_round_trip.py`."""

from __future__ import annotations

import json
import re
from typing import Any

import pytest

from ph_composer_translation import stack
from test_site_sections import document, run, site_record

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")
xml_builder = pytest.importorskip("PHX.to_WUFI_XML.xml_builder")
metr_builder = pytest.importorskip("PHX.to_METr_JSON.metr_builder")

CASES = ("heat_1", "heat_2", "cool_1", "cool_2")
WUFI_CASES = ("Heating1", "Heating2", "Cooling", "Cooling2")


def phx_document(record: dict[str, Any] | None = None, annex: bool = False) -> dict[str, Any]:
    """The reference extraction with its Building Segments named without a space: PHX 1.57.5 names the Room it
    merges each segment into after the segment's display name, and a Room identifier may not hold a space
    (a PHX follow-up, recorded in owed check 6's evidence)."""
    value = document(record, annex)
    for zone in value["sections"]["ph_composer.zones.export.zones"]["records"]:
        zone["building_segment"] = zone["building_segment"].replace(" ", "_")
    return value


def convert(result: dict[str, Any]) -> tuple[str, dict[str, Any]]:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    project = create_project.convert_hb_model_to_PhxProject(model)
    return xml_builder.generate_WUFI_XML_from_object(project), metr_builder.generate_metr_json_dict(project)


def cli_loc(node: Any) -> dict[str, Any]:
    """METr's site block, wherever the project nests it."""
    if isinstance(node, dict):
        if "cliZUS" in node and "TMo" in node:
            return node
        node = list(node.values())
    if isinstance(node, list):
        for item in node:
            if found := cli_loc(item):
                return found
    return {}


def wufi(xml: str, tag: str) -> list[str]:
    return re.findall(rf"<{tag}(?: [^>]*)?>([^<]*)</{tag}>", xml)


def wufi_items(xml: str, tag: str) -> list[float]:
    block = re.search(rf"<{tag} count=\"12\">(.*?)</{tag}>", xml, re.S)
    assert block, f"WUFI XML has no {tag}"
    return [float(value) for value in re.findall(r"<Item index=\"\d+\">([^<]*)</Item>", block.group(1))]


def test_board_18_reads_back_in_wufi_xml_and_metr_json() -> None:
    record = site_record()
    climate = record["climate"]
    xml, metr = convert(run(phx_document(annex=True)))

    # Each Building Segment is its own PHX variant, and each carries the same site.
    assert wufi(xml, "Latitude") == ["40.0"] * 2 and wufi(xml, "Longitude") == ["-100.0"] * 2
    assert wufi(xml, "HeightNNBuilding") == ["500.0"] * 2
    assert wufi(xml, "HeightNNWeatherStation") == [str(climate["station_elevation_m"])] * 2
    assert wufi(xml, "ClimateZone") == [str(record["location"]["climate_zone"])] * 2
    assert xml.count("<dUTC/>") == 2, "an unset offset is written empty"
    assert wufi_items(xml, "TemperatureMonthly") == climate["monthly"]["air_c"]
    assert wufi_items(xml, "GlobalSolarRadiationMonthly") == climate["monthly"]["rad_global_kwh_m2"]
    for key, tag in zip(CASES, WUFI_CASES, strict=True):
        assert wufi(xml, f"Temperature{tag}") == [str(climate["peak_loads"][key]["air_c"])] * 2
        assert wufi(xml, f"SouthSolarRadiation{tag}") == [str(climate["peak_loads"][key]["rad_south_w_m2"])] * 2

    site = cli_loc(metr)
    assert (site["lat"], site["long"], site["hNNB"], site["hNN"]) == (
        40.0,
        -100.0,
        500.0,
        climate["station_elevation_m"],
    )
    assert (site["cliZUS"], site["dUTCB"]) == (record["location"]["climate_zone"], "NaN")
    assert site["TMo"][:12] == climate["monthly"]["air_c"]
    assert site["TMo"][12:] == [climate["peak_loads"][key]["air_c"] for key in CASES]
    assert site["sRadMo"][12:] == [climate["peak_loads"][key]["rad_south_w_m2"] for key in CASES]
    assert site["TMo"][15] == site["TMo"][14], "Cooling 2 repeats Cooling 1"


def test_a_site_alone_reads_back_its_location_over_the_default_climate() -> None:
    record = site_record()
    record.update(climate=None, provenance=None)
    record["location"]["hours_from_utc"] = -6
    xml, metr = convert(run(phx_document(record)))

    assert wufi(xml, "Latitude") == ["40.0"] and wufi(xml, "dUTC") == ["-6"]
    site = cli_loc(metr)
    assert (site["lat"], site["hNNB"], site["dUTCB"], site["hNN"]) == (40.0, 500.0, -6, 0.0)
    assert site["TMo"][12:] == [0.0] * 4
