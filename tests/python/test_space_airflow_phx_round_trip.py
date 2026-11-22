"""The PHX round trip of the Zone airflow mode (context/CONTRACTS.md, "Translation sections and artifacts"), on
the two-Segment reference tests/segment_export_rules_test.rb writes: Living uses detailed airflows (one Space with
a supply, one blank), Kitchen is By Program.
Each Room is given a Program ventilation load here, as Programs' export will, so the round trip shows the two
modes apart: a blank Space of a detailed Zone gets 0 in PHX, never a Program share, and so is not among
WUFI-Passive's and METr's ventilation rooms; the By Program Zone's Space takes its floor share of the Room's load.
Skipped without the group: `uv run --group phx pytest tests/python/test_space_airflow_phx_round_trip.py`."""

from __future__ import annotations

import copy
import json
import re
from pathlib import Path
from typing import Any

import pytest

from ph_composer_translation import stack
from test_shade_sections import reloaded, run
from test_site_phx_round_trip import metr_builder, xml_builder
from test_space_sections import segment, space, square, volume

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "segments" / "extraction.json"
LIVING, KITCHEN = "zon_LLLLLLLLLLLL", "zon_KKKKKKKKKKKK"
#: The Program ventilation each Room carries in this test, per zone, in m3/s (360 m3/h).
ROOM_FLOW_M3S = 0.1


def wufi_spaces(xml: str) -> dict[str, tuple[float, float]]:
    """Each WUFI XML Room's name with its design supply and extract, in m3/h."""
    rows = {}
    for block in re.findall(r"<Room index=\"\d+\">(.*?)</Room>", xml, re.S):
        name = re.search(r"<Name>([^<]*)</Name>", block)
        supply = re.search(r"<DesignVolumeFlowRateSupply[^>]*>([^<]*)<", block)
        extract = re.search(r"<DesignVolumeFlowRateExhaust[^>]*>([^<]*)<", block)
        if name and supply and extract:
            rows[name.group(1)] = (float(supply.group(1)), float(extract.group(1)))
    return rows


def metr_spaces(node: Any) -> dict[str, tuple[float, float]]:
    """Each METr Room's name with its design supply and extract, wherever the project nests it."""
    found: dict[str, tuple[float, float]] = {}
    if isinstance(node, dict):
        if "dVFrSup" in node and "n" in node:
            found[node["n"]] = (float(node["dVFrSup"]), float(node["dVFrEx"]))
        node = list(node.values())
    if isinstance(node, list):
        for item in node:
            found.update(metr_spaces(item))
    return found


def test_a_blank_in_a_detailed_zone_reaches_wufi_and_metr_as_zero_and_a_by_program_space_takes_its_share() -> None:
    floor = [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)]
    rated = space("spc_one", LIVING, floor, name="Rated", number="1", v_sup_m3h=60.0)
    blank = space(
        "spc_two",
        LIVING,
        [volume("vol_b", [segment("fsg_b", [square(3, 0, 3)])], 2.5)],
        name="Blank",
        number="2",
        airflow_mode="detailed",
    )
    loft_floor = [volume("vol_c", [segment("fsg_c", [square(10, 0, 3)])], 2.5)]
    loft = space("spc_three", KITCHEN, loft_floor, name="Loft", number="3")
    document = json.loads(FIXTURE.read_text())
    records = copy.deepcopy([rated, blank, loft])
    document["sections"]["ph_composer.spaces.export.spaces"] = {"version": 2, "records": records}
    result = run(document)
    assert result["summary"]["publishable"] is True, result["findings"]
    model = reloaded(result)
    ventilation = stack.load("honeybee_energy.load.ventilation")
    for room in model.rooms:
        load = ventilation.Ventilation(f"vent_{room.identifier}", flow_per_zone=ROOM_FLOW_M3S)
        room.properties.energy.ventilation = load

    project = create_project.convert_hb_model_to_PhxProject(model)
    spaces = {space.display_name: space for zone in project.variants[0].building.zones for space in zone.spaces}
    blank_load = spaces["2-Blank"].ventilation.load
    assert (blank_load.flow_supply, blank_load.flow_extract) == (0.0, 0.0), "a blank exports 0, not a Program share"
    xml, metr = xml_builder.generate_WUFI_XML_from_object(project), metr_builder.generate_metr_json_dict(project)
    for label, rows in (("WUFI XML", wufi_spaces(xml)), ("METr JSON", metr_spaces(metr))):
        assert rows["1-Rated"] == pytest.approx((60.0, 0.0)), label
        # PHX lists only Spaces with airflow among the ventilation rooms (PhxBuilding, building.py), so the blank
        # Space is absent rather than written with a share.
        assert "2-Blank" not in rows, label
        assert rows["3-Loft"] == pytest.approx((360.0, 360.0)), f"{label}: the only Space takes the Room's whole load"
