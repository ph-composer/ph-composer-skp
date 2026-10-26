"""A section attaching to `ROOM` receives each Room with every object naming it, and the pinned honeybee-ph
writes a Space on that Room so the canonical HBJSON reloads it whole: geometry, airflows (an explicit zero
included, unset kept as null) and `user_data` on the Space, its Volume and its Floor Segment."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, ClassVar, cast

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.contract import as_text
from ph_composer_translation.coordinator import translate
from ph_composer_translation.model_sections import TranslatedZone, ZoneSection
from ph_composer_translation.sections import ROOM, Attachment, AttachmentRefused, Inputs, Requirement, Section

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "phase_one" / "two_zones_extraction.json"
ID = "test.room_spaces"
ZONE_A = "zon_AAAAAAAAAAAA"
SQUARE = [[1.0, 1.0, 0.0], [3.0, 1.0, 0.0], [3.0, 3.0, 0.0], [1.0, 3.0, 0.0]]


@dataclass(frozen=True)
class SpaceRecord:
    identifier: str
    zone_id: str
    airflows: Mapping[str, float | None]


@dataclass(frozen=True)
class RoomSpace:
    zone_id: str
    space: Any


class RoomSpaces(Section[SpaceRecord, RoomSpace]):
    id = ID
    versions = frozenset({1})
    object_type = RoomSpace
    ZONES = Requirement(ZoneSection.id, TranslatedZone)
    requires = (ZONES,)
    attaches = Attachment(ROOM, key=lambda translated: translated.zone_id)

    def __init__(self) -> None:
        self.attached: list[tuple[str, list[str]]] = []

    def read(self, raw: Mapping[str, object]) -> SpaceRecord:
        airflows = cast(Mapping[str, float | None], raw["airflows"])
        return SpaceRecord(as_text(raw["id"], "id"), as_text(raw["zone_id"], "zone_id"), airflows)

    def translate(self, record: SpaceRecord, inputs: Inputs) -> RoomSpace:
        inputs.get(self.ZONES, record.zone_id)
        space_module = stack.load("honeybee_ph.space")
        lb_face = stack.load("ladybug_geometry.geometry3d.face")
        lb_point = stack.load("ladybug_geometry.geometry3d.pointvector")
        floor = lb_face.Face3D([lb_point.Point3D(*point) for point in SQUARE])
        segment = space_module.SpaceFloorSegment()
        segment.identifier, segment.geometry, segment.weighting_factor = f"{record.identifier}_fsg", floor, 0.6
        segment.user_data = {"note": "segment"}
        volume = space_module.SpaceVolume()
        volume.identifier, volume.avg_ceiling_height = f"{record.identifier}_vol", 2.4
        volume.floor.add_floor_segment(segment)
        volume.geometry = [floor]
        volume.user_data = {"note": "volume"}
        space = space_module.Space()
        space.identifier, space.name, space.number = record.identifier, "Kitchen", "101"
        space.user_data = {"note": "space"}
        space.add_new_volumes([volume])
        for key, value in record.airflows.items():
            setattr(space.properties.ph, key, value)
        return RoomSpace(record.zone_id, space)

    def attach(self, host: Any, objects: Sequence[RoomSpace]) -> None:
        self.attached.append((host.identifier, [item.space.identifier for item in objects]))
        for item in objects:
            item.space.host = host
            host.properties.ph.add_new_space(item.space)


def extraction(*records: dict[str, Any]) -> dict[str, Any]:
    value: dict[str, Any] = json.loads(FIXTURE.read_text())
    value["sections"].update(
        {
            "ph_composer.windows.export.window_constructions": {"version": 1, "records": []},
            "ph_composer.windows.export.apertures": {"version": 1, "records": []},
            ID: {"version": 1, "records": list(records)},
        }
    )
    return value


def test_room_attachment_hands_each_room_its_spaces_and_the_hbjson_reloads_them() -> None:
    section = RoomSpaces()
    airflows = {"_v_sup": 0.0, "_v_eta": 0.012, "_v_tran": None}
    document = extraction(
        {"id": "spc_two", "zone_id": ZONE_A, "airflows": airflows},
        {"id": "spc_one", "zone_id": ZONE_A, "airflows": airflows},
    )
    result = cast(dict[str, Any], translate(document, (*SECTIONS, section)).to_document())

    assert result["summary"]["publishable"] is True
    assert section.attached == [(ZONE_A, ["spc_one", "spc_two"])]
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    room = next(room for room in model.rooms if room.identifier == ZONE_A)
    space = room.properties.ph.spaces[0]
    assert [item.identifier for item in room.properties.ph.spaces] == ["spc_one", "spc_two"]
    assert (space.properties.ph._v_sup, space.properties.ph._v_eta, space.properties.ph._v_tran) == (0.0, 0.012, None)
    volume = space.volumes[0]
    segment = volume.floor_segments[0]
    assert (space.user_data, volume.user_data, segment.user_data) == (
        {"note": "space"},
        {"note": "volume"},
        {"note": "segment"},
    )
    assert volume.avg_ceiling_height == 2.4 and len(volume.geometry) == 1
    assert segment.weighting_factor == 0.6 and segment.geometry.area == 4.0


class RefusingSpaces(RoomSpaces):
    """Attaches every Space but `spc_refused`, which it refuses, leaving the Room without it."""

    def attach(self, host: Any, objects: Sequence[RoomSpace]) -> None:
        refused = [item for item in objects if item.space.identifier == "spc_refused"]
        super().attach(host, [item for item in objects if item not in refused])
        if refused:
            raise AttachmentRefused("refused for the test", refused)


class OptionalRefusingSpaces(RefusingSpaces):
    required_for_export: ClassVar[bool] = False


def refusal_run(section: RefusingSpaces) -> dict[str, Any]:
    airflows: dict[str, float | None] = {}
    document = extraction(
        {"id": "spc_kept", "zone_id": ZONE_A, "airflows": airflows},
        {"id": "spc_refused", "zone_id": ZONE_A, "airflows": airflows},
    )
    return cast(dict[str, Any], translate(document, (*SECTIONS, section)).to_document())


def test_an_optional_sections_refused_object_is_omitted_and_the_canonical_model_is_still_written() -> None:
    result = refusal_run(OptionalRefusingSpaces())

    unavailable = [finding for finding in result["findings"] if finding["code"] == "object.unavailable"]
    assert [(finding["object_id"], finding["blocks_export"]) for finding in unavailable] == [("spc_refused", False)]
    assert result["summary"]["publishable"] is True
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    room = next(room for room in model.rooms if room.identifier == ZONE_A)
    assert [space.identifier for space in room.properties.ph.spaces] == ["spc_kept"]


def test_a_required_sections_refused_object_still_withholds_the_canonical_model() -> None:
    result = refusal_run(RefusingSpaces())

    assert [finding["blocks_export"] for finding in result["findings"] if finding["object_id"] == "spc_refused"] == [
        True
    ]
    assert result["summary"]["publishable"] is False
    assert "canonical_model" not in result
