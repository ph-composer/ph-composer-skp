"""The Spaces section: each record becomes a honeybee-ph Space on its Zone's Room, with its areas and volumes
read back from the canonical HBJSON as the Ruby metrics state them, airflows by the any-set rule, user_data
passed through, and the run's per-Zone totals checked against the reloaded model."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.coordinator import translate
from ph_composer_translation.space_sections import SPACE_SECTION_ID

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "phase_one" / "two_zones_extraction.json"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"


def square(x: float, y: float, size: float, z: float = 0.0) -> list[list[float]]:
    return [[x, y, z], [x + size, y, z], [x + size, y + size, z], [x, y + size, z]]


def prism(loop: list[list[float]], height: float) -> list[list[list[float]]]:
    top = [[x, y, z + height] for x, y, z in loop]
    sides = [[loop[i], loop[(i + 1) % 4], top[(i + 1) % 4], top[i]] for i in range(4)]
    return [loop, top, *sides]


def segment(identifier: str, loops: list[list[list[float]]], factor: float = 1.0) -> dict[str, Any]:
    return {"id": identifier, "display_name": "", "weighting_factor": factor, "net_area_factor": 1.0, "loops_m": loops}


def volume(identifier: str, segments: list[dict[str, Any]], height: float) -> dict[str, Any]:
    outer = segments[0]["loops_m"][0]
    return {
        "id": identifier,
        "display_name": "",
        "avg_ceiling_height_m": height,
        "floor_id": "flr_" + identifier,
        "floor_segments": segments,
        "geometry": prism(outer, height),
    }


def space(identifier: str, zone: str, volumes: list[dict[str, Any]], **values: Any) -> dict[str, Any]:
    return {"id": identifier, "zone_id": zone, "name": "Room", "number": "101", "volumes": volumes, **values}


def document(*records: dict[str, Any]) -> dict[str, Any]:
    value: dict[str, Any] = json.loads(FIXTURE.read_text())
    value["sections"].update(
        {
            "ph_composer.windows.export.window_constructions": {"version": 1, "records": []},
            "ph_composer.windows.export.apertures": {"version": 1, "records": []},
            SPACE_SECTION_ID: {"version": 1, "records": list(records)},
        }
    )
    return value


def run(*records: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(document(*records), SECTIONS).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def spaces_on(model: Any, zone: str) -> list[Any]:
    return list(next(room for room in model.rooms if room.identifier == zone).properties.ph.spaces)


def test_rectangles_a_two_volume_space_and_a_projected_sloped_segment_read_back_their_areas_and_volumes() -> None:
    # The sloped segment arrives projected to its mean height, so its area is its 3 by 4 m plan.
    sloped = segment("fsg_slope", [[[10, 0, 1], [13, 0, 1], [13, 4, 1], [10, 4, 1]]])
    result = run(
        space(
            "spc_one",
            ZONE_A,
            [
                volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5),
                volume("vol_b", [segment("fsg_b", [square(3, 0, 2)], 0.0)], 5.0),
            ],
        ),
        space("spc_two", ZONE_B, [volume("vol_c", [sloped], 3.0)]),
    )
    assert result["summary"]["publishable"] is True, result["findings"]
    model = reloaded(result)
    one = spaces_on(model, ZONE_A)[0]
    assert (one.floor_area, one.weighted_floor_area, one.net_volume) == pytest.approx((13.0, 9.0, 42.5))
    two = spaces_on(model, ZONE_B)[0]
    assert (two.floor_area, two.net_volume) == pytest.approx((12.0, 36.0))
    assert [item.identifier for item in one.volumes] == ["vol_a", "vol_b"]
    assert len(one.volumes[0].geometry) == 6
    zones = {row["zone_id"]: row for row in result[SPACE_SECTION_ID]["space_zone_totals"]}
    assert zones[ZONE_A]["weighted_area_m2"] == pytest.approx(9.0)


@pytest.mark.parametrize(
    ("stored", "written"),
    [
        ({"v_sup_m3h": 60.0}, (60 / 3600, 0.0, 0.0)),
        ({}, (None, None, None)),
        ({"v_sup_m3h": 0.0, "v_eta_m3h": 0.0, "v_tran_m3h": 0.0}, (0.0, 0.0, 0.0)),
    ],
)
def test_airflows_follow_the_any_set_rule_through_the_hbjson(stored: dict[str, float], written: tuple) -> None:
    result = run(space("spc_one", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)], **stored))
    ph = spaces_on(reloaded(result), ZONE_A)[0].properties.ph
    actual = (ph._v_sup, ph._v_eta, ph._v_tran)
    assert actual == pytest.approx(written) if written[0] is not None else actual == written


def test_a_space_on_a_zone_that_did_not_translate_blocks_and_a_malformed_record_costs_its_space() -> None:
    result = run(space("spc_lost", "zon_ZZZZZZZZZZZZ", []))
    codes = [(finding["code"], finding["blocks_export"]) for finding in result["findings"]]
    assert ("dependency.unavailable", True) in codes
    broken = space("spc_bad", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)], 1.5)], 2.5)])
    result = run(broken, space("spc_ok", ZONE_B, []))
    assert [finding["object_id"] for finding in result["findings"]] == ["spc_bad"]


def test_attach_puts_two_spaces_on_one_room_and_none_on_another_and_no_spaces_is_no_finding() -> None:
    result = run(space("spc_two", ZONE_A, []), space("spc_one", ZONE_A, []))
    model = reloaded(result)
    assert [item.identifier for item in spaces_on(model, ZONE_A)] == ["spc_one", "spc_two"]
    assert spaces_on(model, ZONE_B) == []
    empty = run()
    assert empty["summary"]["publishable"] is True and empty["findings"] == []


def test_user_data_passes_through_on_each_object_and_the_reserved_key_is_refused() -> None:
    record = space(
        "spc_one", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)], user_data={"client": "A"}
    )
    record["volumes"][0]["user_data"] = {"note": "volume"}
    record["volumes"][0]["floor_segments"][0]["user_data"] = {"note": "segment"}
    record["volumes"][0]["floor_user_data"] = {"note": "floor"}
    found = spaces_on(reloaded(run(record)), ZONE_A)[0]
    volume_found = found.volumes[0]
    assert (found.user_data, volume_found.user_data, volume_found.floor.user_data) == (
        {"client": "A"},
        {"note": "volume"},
        {"note": "floor"},
    )
    assert volume_found.floor_segments[0].user_data == {"note": "segment"}
    refused = copy.deepcopy(record)
    refused["user_data"] = {"ph_composer": 1}
    assert [finding["object_id"] for finding in run(refused)["findings"]] == ["spc_one"]
    refused_floor = copy.deepcopy(record)
    refused_floor["volumes"][0]["floor_user_data"] = {"ph_composer": 1}
    assert [finding["object_id"] for finding in run(refused_floor)["findings"]] == ["spc_one"]


def test_conformance_fails_when_a_reported_total_is_altered() -> None:
    result = run(space("spc_one", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)]))
    check(result["canonical_model"], result, SECTIONS)
    altered = copy.deepcopy(result)
    altered[SPACE_SECTION_ID]["space_zone_totals"][0]["net_volume_m3"] += 1
    with pytest.raises(ValueError, match="net_volume_m3"):
        check(altered["canonical_model"], altered, SECTIONS)


def test_the_same_records_write_the_same_spaces_twice() -> None:
    # Only the Spaces' own serialization: honeybee-ph seeds unrelated model defaults with random ids.
    record = space("spc_one", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)])

    def spaces(result: dict[str, Any]) -> list[Any]:
        model = json.loads(result["canonical_model"]["hbjson"])
        return [room["properties"]["ph"]["spaces"] for room in model["rooms"]]

    assert spaces(run(record)) == spaces(run(record))


def test_conformance_fails_when_totals_name_a_zone_with_no_room() -> None:
    result = run(space("spc_one", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)]))
    altered = copy.deepcopy(result)
    extra = {**altered[SPACE_SECTION_ID]["space_zone_totals"][0], "zone_id": "zon_ZZZZZZZZZZZZ"}
    altered[SPACE_SECTION_ID]["space_zone_totals"].append(extra)
    with pytest.raises(ValueError, match="no Room"):
        check(altered["canonical_model"], altered, SECTIONS)


def test_conformance_fails_when_a_building_segment_total_is_altered() -> None:
    result = run(space("spc_one", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)]))
    altered = copy.deepcopy(result)
    altered[SPACE_SECTION_ID]["space_segment_totals"][0]["net_volume_m3"] += 100
    with pytest.raises(ValueError, match="Building-Segment"):
        check(altered["canonical_model"], altered, SECTIONS)


@pytest.mark.parametrize("field", ["name", "number"])
def test_malformed_text_costs_the_space_a_finding(field: str) -> None:
    record = space("spc_bad", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)])
    record[field] = 123
    assert [finding["object_id"] for finding in run(record)["findings"]] == ["spc_bad"]
    child = space("spc_child", ZONE_A, [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)])
    child["volumes"][0]["floor_segments"][0]["display_name"] = ["Kitchen"]
    assert [finding["object_id"] for finding in run(child)["findings"]] == ["spc_child"]


def test_the_schedule_lists_each_space_with_stored_airflows_and_its_offset_flag() -> None:
    supplied = space(
        "spc_one",
        ZONE_A,
        [volume("vol_a", [segment("fsg_a", [square(0, 0, 3)])], 2.5)],
        v_sup_m3h=60.0,
        offset_from_zone=True,
    )
    inheriting = space("spc_two", ZONE_B, [volume("vol_b", [segment("fsg_b", [square(0, 0, 2)])], 3.0)])
    rows = {row["space_id"]: row for row in run(supplied, inheriting)[SPACE_SECTION_ID]["space_schedule"]}
    assert (rows["spc_one"]["v_sup_m3h"], rows["spc_one"]["v_eta_m3h"]) == (60.0, 0.0)
    assert rows["spc_one"]["offset_from_zone"] is True
    assert rows["spc_one"]["height_m"] == pytest.approx(2.5)
    assert rows["spc_one"]["floor_area_m2"] == pytest.approx(9.0)
    assert rows["spc_two"]["v_sup_m3h"] is None and rows["spc_two"]["offset_from_zone"] is False
    assert rows["spc_two"]["zone_name"]
