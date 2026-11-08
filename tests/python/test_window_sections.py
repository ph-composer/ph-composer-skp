"""Synthetic Window extraction round trips through the exact pinned Honeybee/PH stack."""

from __future__ import annotations

import copy
import json
import re
from pathlib import Path
from typing import Any

import pytest

from ph_composer_translation import stack
from ph_composer_translation.conformance import check
from ph_composer_translation.contract import RecordError
from ph_composer_translation.contract.window_records import SIDES, WindowConstructionRecord
from ph_composer_translation.coordinator import translate
from ph_composer_translation.entry import export_json
from ph_composer_translation.model_sections import FaceSection, ZoneSection
from ph_composer_translation.sections import Inputs, Requirement
from ph_composer_translation.window_sections import (
    APERTURE_SECTION_ID,
    WINDOW_CONSTRUCTION_SECTION_ID,
    ApertureSection,
    WindowConstructionSection,
)

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/fixtures/windows/aperture_export_section.json"
LEGACY = ROOT / "tests/fixtures/phase_one/two_zones_extraction.json"


def windows() -> dict[str, Any]:
    return json.loads(FIXTURE.read_text())


def document() -> dict[str, Any]:
    value = json.loads(LEGACY.read_text())
    value["sections"].update(windows()["sections"])
    assembly = value["sections"]["ph_composer.assemblies.export.constructions"]["records"][0]["id"]
    value["sections"][FaceSection.id]["records"] = [
        {
            "id": "face_wall",
            "zone_id": "zone_A",
            "face_type": "Wall",
            "boundary_condition": "Outdoors",
            "assembly_id": assembly,
            "geometry": {"loops_m": [[[0, 0, 0], [4, 0, 0], [4, 0, 3], [0, 0, 3]]], "area_m2": 12},
            "adjacency": None,
        }
    ]
    value["sections"][ZoneSection.id]["records"] = [
        {
            "id": "zone_A",
            "name": "Synthetic Zone",
            "building_segment": "Synthetic Building",
            "level": None,
            "face_ids": ["face_wall"],
        }
    ]
    return value


def result(value: dict[str, Any]) -> dict[str, Any]:
    return json.loads(export_json(json.dumps(value)))


def model(output: dict[str, Any]) -> Any:
    return stack.load("honeybee.model").Model.from_dict(json.loads(output["canonical_model"]["hbjson"]))


def withheld(output: dict[str, Any], *aperture_ids: str) -> bool:
    """Whether the run cannot publish and any diagnostic canonical model leaves the refused Apertures out."""
    if output["summary"]["publishable"]:
        return False
    if "canonical_model" not in output:
        return True
    hbjson = json.loads(output["canonical_model"]["hbjson"])
    emitted = {
        ap["identifier"] for room in hbjson["rooms"] for face in room["faces"] for ap in face.get("apertures", [])
    }
    return emitted.isdisjoint(aperture_ids)


def test_full_property_and_reference_roundtrip_with_exact_endpoints() -> None:
    value = document()
    output = result(value)
    assert output["summary"]["publishable"] is True
    loaded = model(output)
    face = loaded.rooms[0].faces[0]
    raw_constructions = {row["id"]: row for row in value["sections"][WINDOW_CONSTRUCTION_SECTION_ID]["records"]}
    assert len(face.apertures) == 5
    assert len({ap.properties.energy.construction.identifier for ap in face.apertures}) == 4
    for aperture, source in zip(face.apertures, value["sections"][APERTURE_SECTION_ID]["records"], strict=True):
        authored = raw_constructions[source["construction_id"]]
        construction = aperture.properties.energy.construction
        assert aperture.parent.identifier == source["host_face_id"]
        assert aperture.parent.parent.identifier == source["zone_id"]
        assert aperture.identifier == source["id"]
        assert aperture.is_operable == source["is_operable"]
        assert {tuple(point) for point in aperture.geometry.boundary} == {tuple(p) for p in source["polygon_m"]}
        assert construction.materials[0].u_factor == authored["uw_w_m2k"]
        assert construction.materials[0].shgc == authored["glazing"]["g_value"]
        assert construction.materials[0].vt == 0.6
        assert construction.properties.ph.ph_glazing.u_factor == authored["glazing"]["ug_w_m2k"]
        assert construction.properties.ph.ph_glazing.g_value == authored["glazing"]["g_value"]
        for name in SIDES:
            side = getattr(construction.properties.ph.ph_frame, name)
            expected = authored["sides"][name]
            assert (side.width, side.u_factor, side.psi_glazing, side.psi_install) == (
                expected["frame"]["width_m"],
                expected["frame"]["uf_w_m2k"],
                expected["frame"]["psi_g_w_mk"],
                expected["psi_install_w_mk"],
            )
        assert aperture.properties.ph.install_types.to_dict() == {}
        assert aperture.properties.ph.variant_type == source["variant_type"]
        assert aperture.properties.ph.install_depth == source["install_depth_m"]
        assert aperture.properties.ph.shading_dimensions is None
    assert output[APERTURE_SECTION_ID]["window_face_areas"] == [
        {
            "face_id": "face_wall",
            "zone_id": "zone_A",
            "gross_area_m2": 12,
            "glazed_area_m2": 3.125,
            "net_area_m2": 8.875,
        }
    ]
    assert sorted(row["g_value"] for row in output[APERTURE_SECTION_ID]["window_schema_exceptions"]) == [0, 1]


def test_signature_includes_size_dependent_uw_and_ignores_presentation() -> None:
    value = windows()
    rows = value["sections"][WINDOW_CONSTRUCTION_SECTION_ID]["records"]
    rows[2]["name"] = "Renamed Type"
    rows[2]["glazing"]["name"] = "Renamed glazing"
    for side in rows[2]["sides"].values():
        side["frame"]["name"] = "Renamed frame"
        side["install_name"] = "Renamed install"
    value["sections"][FaceSection.id] = {"version": 1, "records": []}
    translated = translate(value, (FaceSection(), WindowConstructionSection(), ApertureSection()))
    objects = translated.objects(WINDOW_CONSTRUCTION_SECTION_ID)
    first, large, equal = [objects[row["id"]].construction for row in rows[:3]]  # ty: ignore[unresolved-attribute]
    assert first.identifier == equal.identifier
    assert first.identifier != large.identifier
    assert first.materials[0].u_factor == rows[0]["uw_w_m2k"]
    assert large.materials[0].u_factor == rows[1]["uw_w_m2k"]
    assert first.materials[0].u_factor > large.materials[0].u_factor


def test_the_model_default_value_exports_its_psi_and_lists_by_name() -> None:
    value = document()
    source = value["sections"][WINDOW_CONSTRUCTION_SECTION_ID]["records"][0]["sides"]["top"]
    source.update(install_id="wst_ModelDefaults", install_name="Model default", psi_install_w_mk=0.04)
    output = result(value)
    names = {name for row in output[APERTURE_SECTION_ID]["window_usage"] for name in row["install_names"]}
    assert "Model default" in names


def test_shared_edge_zero_and_mulled_unit_count_without_empty_aperture() -> None:
    value = document()
    source = value["sections"][WINDOW_CONSTRUCTION_SECTION_ID]["records"][0]["sides"]["right"]
    source.update(install_id=None, install_name=None, psi_install_w_mk=0)
    apertures = value["sections"][APERTURE_SECTION_ID]["records"]
    apertures[2]["unit_id"] = apertures[0]["unit_id"]
    apertures[2]["element_id"] = "second_glazed_cell"
    output = result(value)
    assert len(model(output).rooms[0].faces[0].apertures) == 5
    usage = next(row for row in output[APERTURE_SECTION_ID]["window_usage"] if row["type_id"] == "type_small")
    assert usage["unit_count"] == 1
    assert usage["aperture_count"] == 2
    first = model(output).rooms[0].faces[0].apertures[0]
    assert first.properties.energy.construction.properties.ph.ph_frame.right.psi_install == 0


def test_roof_cell_preserves_world_geometry_operability_and_depth() -> None:
    value = document()
    face = value["sections"][FaceSection.id]["records"][0]
    face["face_type"] = "RoofCeiling"
    face["geometry"]["loops_m"] = [[[0, 0, 3], [4, 0, 3], [4, 3, 3], [0, 3, 3]]]
    for aperture in value["sections"][APERTURE_SECTION_ID]["records"]:
        aperture["polygon_m"] = [[x, z, 3] for x, _y, z in aperture["polygon_m"]]
        aperture["is_operable"] = True
        aperture["install_depth_m"] = 0.25
    loaded = model(result(value))
    assert loaded.rooms[0].faces[0].type.name == "RoofCeiling"
    assert all(ap.is_operable and ap.properties.ph.install_depth == 0.25 for ap in loaded.rooms[0].faces[0].apertures)


@pytest.mark.parametrize("field,value", [("host_face_id", "missing"), ("zone_id", "missing_zone")])
def test_orphan_or_wrong_parent_is_blocked_with_valid_zone(field: str, value: str) -> None:
    payload = document()
    payload["sections"][APERTURE_SECTION_ID]["records"][0][field] = value
    output = result(payload)
    assert withheld(output, "ap_0")
    assert [row["object_id"] for row in output["findings"] if row["blocks_export"]] == ["ap_0"]


def test_wrong_face_zone_membership_with_another_valid_zone_diagnoses_aperture() -> None:
    payload = document()
    payload["sections"][APERTURE_SECTION_ID]["records"][0]["zone_id"] = "zone_B"
    zone = copy.deepcopy(payload["sections"][ZoneSection.id]["records"][0])
    zone.update(id="zone_B", face_ids=["face_missing"])
    payload["sections"][ZoneSection.id]["records"].append(zone)
    output = result(payload)
    assert withheld(output, "ap_0")
    assert any(
        row["object_id"] == "ap_0" and "not a Face of Zone zone_B" in row["message"] for row in output["findings"]
    )
    assert not any(row["object_id"] in {"ap_1", "ap_2"} for row in output["findings"]), "one defect costs one Aperture"


def test_no_valid_zone_never_produces_usable_artifact() -> None:
    payload = document()
    payload["sections"][ZoneSection.id]["records"][0]["face_ids"] = ["missing"]
    output = result(payload)
    assert not output["summary"]["publishable"]
    assert "canonical_model" not in output
    assert any(row["object_id"] == "zone_A" for row in output["findings"])
    payload["sections"][ZoneSection.id]["records"] = []
    assert "canonical_model" not in result(payload)


@pytest.mark.parametrize("failure", ["outside", "off_plane", "overlap", "hole", "ground", "omitted"])
def test_invalid_host_geometry_or_classification_is_refused(failure: str) -> None:
    payload = document()
    apertures = payload["sections"][APERTURE_SECTION_ID]["records"]
    face = payload["sections"][FaceSection.id]["records"][0]
    if failure == "outside":
        apertures[0]["polygon_m"][0][0] = -1
    elif failure == "off_plane":
        for point in apertures[0]["polygon_m"]:
            point[1] = 0.1
    elif failure == "overlap":
        apertures[1]["polygon_m"] = copy.deepcopy(apertures[0]["polygon_m"])
    elif failure == "hole":
        face["geometry"]["loops_m"].append([[0.1, 0, 0.4], [0.8, 0, 0.4], [0.8, 0, 1.6], [0.1, 0, 1.6]])
    elif failure == "ground":
        face["boundary_condition"] = "Ground"
    else:
        face["omission"] = {"code": "adjacency.stale", "reason": "Synthetic stale", "area_m2": 12, "zone_id": "zone_A"}
    output = result(payload)
    assert withheld(output, *(row["id"] for row in apertures))


@pytest.mark.parametrize("g", [-0.01, 1.01, True, "0.5", float("inf")])
def test_invalid_g_is_not_clamped(g: object) -> None:
    raw = windows()["sections"][WINDOW_CONSTRUCTION_SECTION_ID]["records"][0]
    raw["glazing"]["g_value"] = g
    with pytest.raises(RecordError):
        WindowConstructionRecord.read(raw)


@pytest.mark.parametrize("g", [0, 1])
def test_endpoint_exception_is_explicit_exact_and_narrow(g: int) -> None:
    output = result(document())
    exceptions = output[APERTURE_SECTION_ID]["window_schema_exceptions"]

    def declared(rows: list[dict[str, Any]]) -> dict[str, Any]:
        return {APERTURE_SECTION_ID: {"window_schema_exceptions": rows}}

    sections = (ApertureSection(),)
    with pytest.raises(ValueError, match="exceptions"):
        check(output["canonical_model"], {}, sections)
    with pytest.raises(ValueError, match="exceptions"):
        check(output["canonical_model"], declared([row for row in exceptions if row["g_value"] != g]), sections)
    bad = copy.deepcopy(exceptions)
    bad[0]["extra"] = "not-an-allowed-exception"
    with pytest.raises(ValueError, match="unsupported"):
        check(output["canonical_model"], declared(bad), sections)
    check(output["canonical_model"], declared(exceptions), sections)


def test_inputs_all_requires_declared_typed_requirement_and_sorts_ids() -> None:
    requirement = Requirement("synthetic.rows", str)
    inputs = Inputs((requirement,), {requirement.section: {"b": "second", "a": "first"}})
    assert inputs.all(requirement) == ("first", "second")
    with pytest.raises(LookupError, match="not a declared"):
        Inputs((), {}).all(requirement)


def test_empty_registered_window_sections_preserve_exact_legacy_hbjson() -> None:
    payload = json.loads(LEGACY.read_text())
    payload["sections"].update(
        {section.id: {"version": 1, "records": []} for section in (WindowConstructionSection(), ApertureSection())}
    )
    current = result(payload)

    def normalized(value: Any) -> Any:
        # The pinned PH stack creates UUIDs for unrelated default team/climate objects;
        # Energy resource arrays are sets emitted in process-dependent order.
        if isinstance(value, str):
            return re.sub(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", "<default-ph-uuid>", value)
        if isinstance(value, dict):
            return {key: normalized(item) for key, item in value.items()}
        if isinstance(value, list):
            items = [normalized(item) for item in value]
            if items and all(isinstance(item, dict) and "identifier" in item for item in items):
                return sorted(items, key=lambda item: item["identifier"])
            return items
        return value

    baseline = json.loads((LEGACY.parent / "two_zones.hbjson").read_text())
    assert normalized(json.loads(current["canonical_model"]["hbjson"])) == normalized(baseline)
    assert current["canonical_model"]["rooms"] == 2 and current["canonical_model"]["faces"] == 12
    assert "apertures" not in current["canonical_model"]
    assert current[APERTURE_SECTION_ID] == {"window_usage": [], "window_schema_exceptions": [], "window_face_areas": []}


def test_authoring_provider_and_shading_metadata_never_reaches_hbjson() -> None:
    payload = document()
    for section_id in (WINDOW_CONSTRUCTION_SECTION_ID, APERTURE_SECTION_ID):
        for row in payload["sections"][section_id]["records"]:
            row.update(
                source={"provider_path": "PRIVATE_PATH_TOKEN"},
                shading={"coefficient": "PRIVATE_SHADING_TOKEN"},
                extensions={"payload": "PRIVATE_EXT_TOKEN"},
            )
    output = result(payload)
    serialized = json.dumps(output)
    assert all(
        token not in serialized for token in ("PRIVATE_PATH_TOKEN", "PRIVATE_SHADING_TOKEN", "PRIVATE_EXT_TOKEN")
    )


def test_a_units_user_data_passes_through_to_each_of_its_apertures() -> None:
    payload = document()
    for row in payload["sections"][APERTURE_SECTION_ID]["records"]:
        row["user_data"] = {"firm": {"tag": "north"}}

    apertures = [ap for room in model(result(payload)).rooms for face in room.faces for ap in face.apertures]

    assert apertures and all(ap.user_data == {"firm": {"tag": "north"}} for ap in apertures)


def test_a_user_key_named_like_ph_composer_costs_the_aperture() -> None:
    payload = document()
    payload["sections"][APERTURE_SECTION_ID]["records"][0]["user_data"] = {"ph_composer": {"x": 1}}

    output = result(payload)

    assert any("reserved key" in row["message"] for row in output["findings"])


@pytest.mark.parametrize("uw_w_m2k", [0, -1, 12.01, True, "1.1"])
def test_invalid_or_unrepresentable_uw_blocks_assigned_cell_without_clamping(uw_w_m2k: object) -> None:
    payload = document()
    payload["sections"][WINDOW_CONSTRUCTION_SECTION_ID]["records"][0]["uw_w_m2k"] = uw_w_m2k
    output = result(payload)
    assert not output["summary"]["publishable"]
    assert any(row["code"] == "dependency.unavailable" and row["object_id"] == "ap_0" for row in output["findings"])


def test_signature_separates_every_translated_numeric_and_product_identity() -> None:
    original = windows()["sections"][WINDOW_CONSTRUCTION_SECTION_ID]["records"][0]
    reference = WindowConstructionRecord.read(original).signature()
    changes = [("uw_w_m2k",), ("glazing", "id"), ("glazing", "ug_w_m2k"), ("glazing", "g_value")]
    for side in SIDES:
        changes.extend(("sides", side, "frame", key) for key in ("id", "width_m", "uf_w_m2k", "psi_g_w_mk"))
        changes.extend(("sides", side, key) for key in ("install_id", "psi_install_w_mk"))
    for path in changes:
        raw = copy.deepcopy(original)
        target = raw
        for key in path[:-1]:
            target = target[key]
        old = target[path[-1]]
        target[path[-1]] = old + "_other" if isinstance(old, str) else old + 0.01
        assert WindowConstructionRecord.read(raw).signature() != reference


def test_inputs_all_preserves_wrong_type_dependency_refusal() -> None:
    from ph_composer_translation.sections import DependencyUnavailable

    requirement = Requirement("synthetic.rows", str)
    with pytest.raises(DependencyUnavailable):
        Inputs((requirement,), {requirement.section: {"row": 42}}).all(requirement)


def test_zone_face_and_assembly_user_data_pass_through_beside_ph_composer_keys() -> None:
    payload = document()
    payload["sections"][ZoneSection.id]["records"][0]["user_data"] = {"firm": {"room": "A"}}
    payload["sections"][FaceSection.id]["records"][0]["user_data"] = {"firm": {"face": "north"}}
    constructions = payload["sections"]["ph_composer.assemblies.export.constructions"]["records"]
    constructions[0]["user_data"] = {"firm": {"wall": "W1"}}

    reloaded = model(result(payload))

    room = reloaded.rooms[0]
    assert room.user_data["firm"] == {"room": "A"} and "ph_composer" in room.user_data
    assert room.faces[0].user_data == {"firm": {"face": "north"}}
    construction = room.faces[0].properties.energy.construction
    assert construction.user_data["firm"] == {"wall": "W1"} and "ph_composer" in construction.user_data
