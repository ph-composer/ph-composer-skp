from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace
from typing import Any, cast

import pytest

from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.constructions import ConstructionSection, TranslatedConstruction
from ph_composer_translation.contract import RecordError
from ph_composer_translation.coordinator import translate
from ph_composer_translation.material_sources import MaterialSourcesSection
from ph_composer_translation.model_sections import FaceSection, ZoneSection
from ph_composer_translation.sections import Inputs
from ph_composer_translation.space_sections import SpaceSection
from ph_composer_translation.thermal_bridge_sections import ThermalBridgeSection
from ph_composer_translation.window_sections import ApertureSection, WindowConstructionSection

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests" / "fixtures" / "phase_one" / "two_zones_extraction.json"


def load_fixture() -> dict[str, Any]:
    value = json.loads(FIXTURE.read_text())
    value["sections"].update(
        {section.id: {"version": 1, "records": []} for section in (WindowConstructionSection(), ApertureSection())}
    )
    return cast(dict[str, Any], value)


def test_normal_composition_uses_only_authored_constructions() -> None:
    result = translate(load_fixture(), SECTIONS).to_document()
    assert result["state"] == "complete"
    assert result["summary"] == {"objects": 15, "unavailable": 0, "findings": 0, "publishable": True}
    assert "canonical_model" in result


class FakeFace:
    def __init__(self, identifier: str, geometry: object, face_type: object, boundary: object) -> None:
        self.identifier = identifier
        self.geometry = geometry
        self.apertures: list[Any] = []
        self.type = face_type
        self.boundary_condition = boundary
        self.parent: FakeRoom | None = None
        self.properties = SimpleNamespace(energy=SimpleNamespace(construction=None))

    def set_adjacency(self, other: FakeFace) -> None:
        self.boundary_condition = SimpleNamespace(name="Surface", target=other.identifier)
        other.boundary_condition = SimpleNamespace(name="Surface", target=self.identifier)


class FakeRoom:
    def __init__(self, identifier: str, faces: list[FakeFace]) -> None:
        self.identifier = identifier
        self.faces = faces
        for face in faces:
            face.parent = self
        self.display_name = identifier
        self.user_data: dict[str, object] = {}
        self.properties = SimpleNamespace(
            ph=SimpleNamespace(ph_bldg_segment=SimpleNamespace(identifier="", display_name=""))
        )


class FakeModel:
    def __init__(self, identifier: str, units: str) -> None:
        self.identifier = identifier
        self.rooms: list[FakeRoom] = []
        self.units = units

    def add_rooms(self, rooms: list[FakeRoom]) -> None:
        self.rooms.extend(rooms)

    def to_dict(self) -> dict[str, object]:
        return {
            "identifier": self.identifier,
            "rooms": [room.identifier for room in self.rooms],
            "units": self.units,
        }


class FakeConstructionSection(ConstructionSection):
    def translate(self, record: Any, inputs: Inputs) -> TranslatedConstruction:
        return TranslatedConstruction(record, {"assembly_id": record.id}, (), ())

    def result_fields(self, objects: Any) -> dict[str, Any]:
        return {}


def fake_stack(name: str) -> object:
    outdoors = SimpleNamespace(name="Outdoors")
    boundaries = SimpleNamespace(outdoors=outdoors, ground=SimpleNamespace(name="Ground"), adiabatic=object())
    modules = {
        "honeybee.face": SimpleNamespace(Face=FakeFace),
        "honeybee.room": SimpleNamespace(Room=FakeRoom),
        "honeybee.facetype": SimpleNamespace(
            face_types=SimpleNamespace(wall=object(), roof_ceiling=object(), floor=object(), air_boundary=object())
        ),
        "honeybee.boundarycondition": SimpleNamespace(boundary_conditions=boundaries),
        "ladybug_geometry.geometry3d.face": SimpleNamespace(Face3D=lambda boundary, holes=None: (boundary, holes)),
        "ladybug_geometry.geometry3d.pointvector": SimpleNamespace(Point3D=lambda *point: point),
        "honeybee.model": SimpleNamespace(Model=FakeModel),
        "honeybee_energy._extend_honeybee": SimpleNamespace(),
        "honeybee_ph": SimpleNamespace(),
    }
    return modules[name]


def test_model_sections_build_rooms_then_resolve_surface_pairs(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    result = translate(
        load_fixture(),
        (
            FakeConstructionSection(),
            MaterialSourcesSection(),
            FaceSection(),
            WindowConstructionSection(),
            ApertureSection(),
            ZoneSection(),
            SpaceSection(),
            ThermalBridgeSection(),
        ),
    ).to_document()

    assert result["state"] == "complete"
    canonical = result["canonical_model"]
    assert canonical == {
        "hbjson": '{"identifier":"ph_composer_model","rooms":["zon_AAAAAAAAAAAA","zon_BBBBBBBBBBBB"],"units":"Meters"}',
        "rooms": 2,
        "faces": 12,
        "surface_pairs": 1,
    }


def test_invalid_face_vocabulary_becomes_a_record_error(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    document = load_fixture()
    document["sections"]["ph_composer.zones.faces.export.faces"]["records"][0]["face_type"] = "Ceiling"
    result = translate(
        document,
        (
            FakeConstructionSection(),
            MaterialSourcesSection(),
            FaceSection(),
            WindowConstructionSection(),
            ApertureSection(),
            ZoneSection(),
            SpaceSection(),
            ThermalBridgeSection(),
        ),
    ).to_document()

    assert result["state"] == "complete_with_findings"
    summary = result["summary"]
    findings = result["findings"]
    assert isinstance(summary, dict) and summary["unavailable"] == 1
    assert isinstance(findings, list)
    messages = [finding.get("message") for finding in findings if isinstance(finding, dict)]
    assert any("could not be built" in message for message in messages if isinstance(message, str))


@pytest.mark.parametrize("failure", ["missing", "nonreciprocal"])
def test_surface_requires_an_available_reciprocal_counterpart(monkeypatch: pytest.MonkeyPatch, failure: str) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    document = load_fixture()
    faces = document["sections"]["ph_composer.zones.faces.export.faces"]["records"]
    surfaces = [face for face in faces if face["boundary_condition"] == "Surface"]
    if failure == "missing":
        faces.remove(surfaces[1])
    else:
        surfaces[1]["adjacency"]["counterpart"]["entity_id"] = surfaces[1]["id"]

    result = translate(
        document,
        (
            FakeConstructionSection(),
            MaterialSourcesSection(),
            FaceSection(),
            WindowConstructionSection(),
            ApertureSection(),
            ZoneSection(),
            SpaceSection(),
            ThermalBridgeSection(),
        ),
    ).to_document()

    assert result["state"] == "complete_with_findings"
    summary = result["summary"]
    assert isinstance(summary, dict) and summary["publishable"] is False
    assert "canonical_model" not in result


def test_face_reader_rejects_malformed_nested_geometry() -> None:
    section = FaceSection()
    base = {
        "id": "fac_A00000000001",
        "zone_id": "zon_AAAAAAAAAAAA",
        "face_type": "Wall",
        "boundary_condition": "Outdoors",
        "assembly_id": None,
        "adjacency": None,
    }
    malformed_geometry: tuple[object, ...] = (
        None,
        {"loops_m": []},
        {"loops_m": [[0, 1]]},
        {"loops_m": [[[0, 0]]]},
    )
    for geometry in malformed_geometry:
        with pytest.raises(RecordError):
            section.read({**base, "geometry": geometry})


def omit(face: dict[str, object], code: str = "adjacency.stale") -> None:
    geometry = face["geometry"]
    assert isinstance(geometry, dict)
    face["omission"] = {
        "code": code,
        "reason": "Stored Surface geometry is stale",
        "area_m2": geometry["area_m2"],
        "zone_id": face["zone_id"],
    }


def test_explicit_and_reciprocal_omissions_preserve_inputs_and_publish_remaining_model(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    document = load_fixture()
    raw_faces = document["sections"]["ph_composer.zones.faces.export.faces"]["records"]
    surfaces = [face for face in raw_faces if face["boundary_condition"] == "Surface"]
    omit(surfaces[0])
    before = json.dumps(document, sort_keys=True)

    translation = translate(
        document,
        (
            FakeConstructionSection(),
            MaterialSourcesSection(),
            FaceSection(),
            WindowConstructionSection(),
            ApertureSection(),
            ZoneSection(),
            SpaceSection(),
            ThermalBridgeSection(),
        ),
    )
    result = cast(dict[str, Any], translation.to_document())

    assert result["state"] == "complete_with_findings"
    assert result["summary"] == {"objects": 15, "unavailable": 0, "findings": 2, "publishable": True}
    assert result["canonical_model"]["faces"] == 10
    assert result["canonical_model"]["surface_pairs"] == 0
    assert len(result["ph_composer.zones.faces.export.faces"]["surface_omissions"]) == 2
    assert {row["face_id"] for row in result["ph_composer.zones.faces.export.faces"]["surface_omissions"]} == {
        face["id"] for face in surfaces
    }
    assert {row["code"] for row in result["ph_composer.zones.faces.export.faces"]["surface_omissions"]} == {
        "adjacency.stale",
        "adjacency.counterpart_omitted",
    }
    assert all(not finding["blocks_export"] for finding in result["findings"])
    for row in result["ph_composer.zones.faces.export.faces"]["surface_omissions"]:
        assert row["zone_id"] in {face["zone_id"] for face in surfaces}
        assert row["area_m2"] == pytest.approx(12.0)
        assert row["reason"]
    assert len(translation.objects(FaceSection.id)) == 12
    assert json.dumps(document, sort_keys=True) == before


def test_retired_face_with_no_boundary_is_a_nonblocking_reported_omission(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    document = load_fixture()
    face = document["sections"]["ph_composer.zones.faces.export.faces"]["records"][0]
    omit(face, "face.boundary_unclassified")
    face.pop("boundary_condition")

    result = cast(
        dict[str, Any],
        translate(
            document,
            (
                FakeConstructionSection(),
                MaterialSourcesSection(),
                FaceSection(),
                WindowConstructionSection(),
                ApertureSection(),
                ZoneSection(),
                SpaceSection(),
                ThermalBridgeSection(),
            ),
        ).to_document(),
    )

    assert result["summary"]["publishable"] is True
    assert result["canonical_model"]["faces"] == 11
    assert result["canonical_model"]["surface_pairs"] == 1
    assert len(result["ph_composer.zones.faces.export.faces"]["surface_omissions"]) == 1
    assert result["ph_composer.zones.faces.export.faces"]["surface_omissions"][0]["face_id"] == face["id"]
    assert result["findings"][0]["object_id"] == face["id"]
    assert face["zone_id"] in result["findings"][0]["message"]


def test_omissions_do_not_hide_an_unavailable_assigned_construction() -> None:
    document = load_fixture()
    omit(document["sections"]["ph_composer.zones.faces.export.faces"]["records"][0])
    document["sections"][ConstructionSection.id]["records"] = []

    result = cast(dict[str, Any], translate(document, SECTIONS).to_document())

    assert result["summary"]["publishable"] is False
    assert "canonical_model" not in result
    assert len(result["ph_composer.zones.faces.export.faces"]["surface_omissions"]) == 1
    assert sum(finding["blocks_export"] for finding in result["findings"]) == 2


@pytest.mark.parametrize(
    "change",
    [{"area_m2": -1}, {"area_m2": True}, {"zone_id": "wrong"}, {"code": ""}, {"reason": None}],
)
def test_malformed_omission_metadata_remains_a_blocker(
    change: dict[str, object], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    document = load_fixture()
    face = document["sections"]["ph_composer.zones.faces.export.faces"]["records"][0]
    omit(face)
    face["omission"].update(change)

    result = cast(
        dict[str, Any],
        translate(
            document,
            (
                FakeConstructionSection(),
                MaterialSourcesSection(),
                FaceSection(),
                WindowConstructionSection(),
                ApertureSection(),
                ZoneSection(),
                SpaceSection(),
                ThermalBridgeSection(),
            ),
        ).to_document(),
    )

    assert result["summary"]["publishable"] is False
    assert any(finding["blocks_export"] for finding in result["findings"])


def test_missing_boundary_without_explicit_omission_remains_a_blocker(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    document = load_fixture()
    document["sections"]["ph_composer.zones.faces.export.faces"]["records"][0].pop("boundary_condition")

    result = cast(
        dict[str, Any],
        translate(
            document,
            (
                FakeConstructionSection(),
                MaterialSourcesSection(),
                FaceSection(),
                WindowConstructionSection(),
                ApertureSection(),
                ZoneSection(),
                SpaceSection(),
                ThermalBridgeSection(),
            ),
        ).to_document(),
    )

    assert result["summary"]["publishable"] is False
    assert any("boundary_condition" in finding["message"] for finding in result["findings"])


def test_omitted_face_invalid_classification_still_blocks(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("ph_composer_translation.model_sections.stack.load", fake_stack)
    document = load_fixture()
    face = document["sections"]["ph_composer.zones.faces.export.faces"]["records"][0]
    omit(face)
    face["face_type"] = "Ceiling"

    result = cast(
        dict[str, Any],
        translate(
            document,
            (
                FakeConstructionSection(),
                MaterialSourcesSection(),
                FaceSection(),
                WindowConstructionSection(),
                ApertureSection(),
                ZoneSection(),
                SpaceSection(),
                ThermalBridgeSection(),
            ),
        ).to_document(),
    )

    assert result["summary"]["publishable"] is False
    assert any("independently" in finding["message"] for finding in result["findings"])


def test_real_hbjson_reloads_with_omitted_surface_pair_and_counts_what_it_holds() -> None:
    from ph_composer_translation.conformance import check

    document = load_fixture()
    faces = document["sections"]["ph_composer.zones.faces.export.faces"]["records"]
    surface = next(face for face in faces if face["boundary_condition"] == "Surface")
    omit(surface)
    result = cast(dict[str, Any], translate(document, SECTIONS).to_document())

    assert result["summary"]["publishable"] is True
    canonical = result["canonical_model"]
    assert canonical["faces"] == 10
    assert len(result["ph_composer.zones.faces.export.faces"]["surface_omissions"]) == 2
    check(canonical)
    hbjson = json.loads(canonical["hbjson"])
    actual_ids = {face["identifier"] for room in hbjson["rooms"] for face in room["faces"]}
    assert actual_ids.isdisjoint(
        row["face_id"] for row in result["ph_composer.zones.faces.export.faces"]["surface_omissions"]
    )
    assert all(face["boundary_condition"]["type"] != "Surface" for room in hbjson["rooms"] for face in room["faces"])
    with pytest.raises(ValueError, match="Surface accounting"):
        check({**canonical, "surface_pairs": 1})


def test_a_failed_zone_costs_its_surface_partner_a_named_finding_and_withholds_the_model() -> None:
    document = load_fixture()
    faces = document["sections"]["ph_composer.zones.faces.export.faces"]["records"]
    failed = next(face for face in faces if face["boundary_condition"] == "Surface")["zone_id"]
    next(face for face in faces if face["zone_id"] == failed and face["boundary_condition"] != "Surface")[
        "assembly_id"
    ] = "asm_Absent000001"

    result = cast(dict[str, Any], translate(document, SECTIONS).to_document())

    blocking = sorted((row["code"], row["object_id"]) for row in result["findings"] if row["blocks_export"])
    partner = ({"zon_AAAAAAAAAAAA", "zon_BBBBBBBBBBBB"} - {failed}).pop()
    assert blocking == sorted([("dependency.unavailable", failed), ("object.unavailable", partner)])
    assert "canonical_model" not in result


def test_a_zone_whose_faces_are_all_omitted_is_refused_and_the_rest_reloads() -> None:
    from ph_composer_translation.conformance import check

    document = load_fixture()
    faces = document["sections"]["ph_composer.zones.faces.export.faces"]["records"]
    empty = faces[0]["zone_id"]
    for face in faces:
        if face["zone_id"] == empty:
            omit(face, "face.boundary_unassigned")
    translation = translate(document, SECTIONS)
    result = cast(dict[str, Any], translation.to_document())

    refused = [row for row in result["findings"] if row["object_id"] == empty]
    assert [(row["code"], row["blocks_export"]) for row in refused] == [("object.unavailable", True)]
    assert "no Faces left" in refused[0]["message"]
    assert empty not in translation.objects(ZoneSection.id)
    assert result["summary"]["publishable"] is False
    canonical = result["canonical_model"]
    check(canonical)
    hbjson = json.loads(canonical["hbjson"])
    assert [room["identifier"] for room in hbjson["rooms"]] == list(translation.objects(ZoneSection.id))
    assert all(room["faces"] for room in hbjson["rooms"])
