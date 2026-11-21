"""Managed and legacy Segment identity through the real HBJSON serialization boundary."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.contract import RecordError
from ph_composer_translation.coordinator import translate
from ph_composer_translation.model_sections import ZoneSection
from ph_composer_translation.window_sections import ApertureSection, WindowConstructionSection
from program_free import without_programs

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures/phase_one/two_zones_extraction.json"
ADOPTED_KEY = "bseg_" + hashlib.sha256(b"Synthetic Building").hexdigest()[:16]


def document(version: int = 2) -> dict[str, Any]:
    payload: dict[str, Any] = without_programs(json.loads(FIXTURE.read_text()))
    payload["sections"].update(
        {section.id: {"version": 1, "records": []} for section in (WindowConstructionSection(), ApertureSection())}
    )
    payload["sections"][ZoneSection.id]["version"] = version
    return payload


def rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], payload["sections"][ZoneSection.id]["records"])


def translation_result(payload: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(payload, SECTIONS).to_document())


def assign(row: dict[str, Any], segment_id: str = "bsg_000000000001", export_key: str = ADOPTED_KEY) -> None:
    row.update(building_segment_id=segment_id, building_segment_export_identifier=export_key)


def reload_model(payload: dict[str, Any]) -> tuple[dict[str, Any], Any]:
    result = translation_result(payload)
    assert result["state"] == "complete", result
    serialized = json.loads(result["canonical_model"]["hbjson"])
    model = stack.load("honeybee.model").Model.from_dict(serialized)
    return serialized, model


def test_managed_segment_rename_retains_adopted_identifier_and_room_references() -> None:
    payload = document()
    for row in rows(payload):
        assign(row)
    before, original = reload_model(payload)
    assert original.rooms[0].properties.ph.ph_bldg_segment is original.rooms[1].properties.ph.ph_bldg_segment
    for row in rows(payload):
        row["building_segment"] = "Renamed Building"
        row["level"] = "Renamed Level"
    after, renamed = reload_model(payload)
    assert len(after["properties"]["ph"]["bldg_segments"]) == 1
    assert renamed.rooms[0].properties.ph.ph_bldg_segment is renamed.rooms[1].properties.ph.ph_bldg_segment
    assert before["properties"]["ph"]["bldg_segments"][0]["identifier"] == ADOPTED_KEY
    for room, row, serialized_room in zip(renamed.rooms, rows(payload), after["rooms"], strict=True):
        segment = room.properties.ph.ph_bldg_segment
        assert segment.identifier == ADOPTED_KEY
        assert segment.display_name == "Renamed Building"
        assert serialized_room["properties"]["ph"]["ph_bldg_segment_id"] == ADOPTED_KEY
        assert room.display_name == row["name"]
        assert room.user_data["ph_composer"] == {"level": "Renamed Level", "building_segment": "Renamed Building"}


def test_same_display_name_with_distinct_managed_ids_remains_two_segments() -> None:
    payload = document()
    first, second = rows(payload)
    first["building_segment"] = second["building_segment"] = "Shared display name"
    assign(first, "bsg_000000000001", "bseg_000000000001")
    assign(second, "bsg_000000000002", "bseg_000000000002")
    serialized, model = reload_model(payload)
    assert len(serialized["properties"]["ph"]["bldg_segments"]) == 2
    segments = [room.properties.ph.ph_bldg_segment for room in model.rooms]
    assert segments[0] is not segments[1]
    assert [segment.identifier for segment in segments] == ["bseg_000000000001", "bseg_000000000002"]
    assert [segment.display_name for segment in segments] == ["Shared display name", "Shared display name"]
    for row in rows(payload):
        assign(row, "bsg_000000000001", "bseg_000000000001")
    merged, merged_model = reload_model(payload)
    assert len(merged["properties"]["ph"]["bldg_segments"]) == 1
    assert merged_model.rooms[0].properties.ph.ph_bldg_segment is merged_model.rooms[1].properties.ph.ph_bldg_segment
    assert merged_model.rooms[1].properties.ph.ph_bldg_segment.identifier == "bseg_000000000001"


@pytest.mark.parametrize("version", [1, 2])
def test_legacy_section_rows_retain_name_hash_and_shared_references(version: int) -> None:
    payload = document(version)
    first, second = rows(payload)
    second["building_segment"] = first["building_segment"]
    serialized, model = reload_model(payload)
    expected = "bseg_" + hashlib.sha256(first["building_segment"].encode("utf-8")).hexdigest()[:16]
    assert len(serialized["properties"]["ph"]["bldg_segments"]) == 1
    assert model.rooms[0].properties.ph.ph_bldg_segment.identifier == expected
    assert model.rooms[0].properties.ph.ph_bldg_segment is model.rooms[1].properties.ph.ph_bldg_segment


def test_v2_section_can_hold_legacy_and_managed_rows_without_adopting_legacy() -> None:
    payload = document()
    first, second = rows(payload)
    assign(first, export_key="bseg_managed")
    _, model = reload_model(payload)
    segments = [room.properties.ph.ph_bldg_segment for room in model.rooms]
    expected_legacy = "bseg_" + hashlib.sha256(second["building_segment"].encode("utf-8")).hexdigest()[:16]
    assert [segment.identifier for segment in segments] == ["bseg_managed", expected_legacy]
    assert segments[0] is not segments[1]


@pytest.mark.parametrize(
    "fields",
    [
        {"building_segment_id": "bsg_1"},
        {"building_segment_export_identifier": "bseg_1"},
        {"building_segment_id": None, "building_segment_export_identifier": None},
        {"building_segment_id": " ", "building_segment_export_identifier": "bseg_1"},
        {"building_segment_id": 4, "building_segment_export_identifier": "bseg_1"},
        {"building_segment_id": "bsg_1", "building_segment_export_identifier": ""},
        {"building_segment_id": "bsg_1", "building_segment_export_identifier": "bad_key"},
        {"building_segment_id": "bsg_1", "building_segment_export_identifier": "bseg_has space"},
        {"building_segment_id": "bsg_1", "building_segment_export_identifier": "bseg_" + "a" * 100},
    ],
)
def test_incomplete_or_malformed_managed_identity_refuses_row(fields: dict[str, object]) -> None:
    row = rows(document())[0]
    row.update(fields)
    with pytest.raises(RecordError, match="building_segment"):
        ZoneSection().read(row)


@pytest.mark.parametrize("conflict", ["distinct_ids", "same_id_different_key", "same_id_different_name", "legacy"])
def test_conflicting_segment_definitions_withhold_canonical_model(conflict: str) -> None:
    payload = document()
    first, second = rows(payload)
    assign(first)
    assign(second)
    if conflict == "distinct_ids":
        second["building_segment_id"] = "bsg_000000000002"
    elif conflict == "same_id_different_key":
        second["building_segment_export_identifier"] = "bseg_other"
    elif conflict == "same_id_different_name":
        second["building_segment"] = "Conflicting name"
    else:
        first["building_segment_export_identifier"] = (
            "bseg_" + hashlib.sha256(second["building_segment"].encode("utf-8")).hexdigest()[:16]
        )
        second.pop("building_segment_id")
        second.pop("building_segment_export_identifier")
    result = translation_result(payload)
    assert "canonical_model" not in result
    assert result["summary"]["publishable"] is False
    assert {finding["object_id"] for finding in result["findings"]} == {first["id"], second["id"]}
    assert all("Building Segment" in finding["message"] for finding in result["findings"])


def test_unknown_zone_section_version_refuses_before_translation() -> None:
    result = translation_result(document(3))
    assert result["failure"]["code"] == "section.version_unsupported"
    assert "canonical_model" not in result
