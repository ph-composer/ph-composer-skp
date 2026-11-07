"""Shared authored records, real pinned Honeybee objects and their serialized references."""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.constructions import ConstructionSection, TranslatedConstruction
from ph_composer_translation.coordinator import translate

ROOT = Path(__file__).resolve().parents[1] / "fixtures" / "assemblies"


def document() -> dict[str, Any]:
    return cast(dict[str, Any], json.loads((ROOT / "extraction.json").read_text()))


def constructions() -> dict[str, Any]:
    result = translate(document(), (ConstructionSection(),))
    expected = json.loads((ROOT / "expected.json").read_text())
    assert set(result.objects(ConstructionSection.id)) == set(expected["built"])
    assert set(result.results[ConstructionSection.id].unavailable) == set(expected["unavailable"])
    assert result.publishable
    return {
        key: cast(TranslatedConstruction, value).construction
        for key, value in result.objects(ConstructionSection.id).items()
    }


def reload(construction: Any) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee_energy.construction.opaque").OpaqueConstruction.from_dict(construction.to_dict())


def test_single_layers_keep_distinct_thickness_identifiers_and_colour_after_round_trip() -> None:
    construction = reload(constructions()["asm_Single000001"])
    assert [material.thickness for material in construction.materials] == [0.1, 0.05]
    assert len({material.identifier for material in construction.materials}) == 2
    for material in construction.materials:
        assert (material.conductivity, material.density, material.specific_heat) == (0.04, 40, 1400)
        assert material.properties.ph.ph_color.to_dict() == {"r": 136, "g": 170, "b": 68, "a": 255}
        assert (
            material.roughness,
            material.thermal_absorptance,
            material.solar_absorptance,
            material.visible_absorptance,
        ) == ("MediumRough", 0.9, 0.7, 0.7)


@pytest.mark.parametrize(
    ("identifier", "widths", "conductivity", "spacing"),
    [
        ("asm_Mixed0000001", [0.15, 0.85], 0.0535, None),
        ("asm_Steel0000001", [0.0035, 0.5965], (3.5 * 50 + 596.5 * 0.04) / 600, 600),
        ("asm_Repeat000001", [0.1, 0.4, 0.1, 0.4], 0.058, None),
    ],
)
def test_grid_keeps_every_column_material_and_base_properties_after_round_trip(
    identifier: str, widths: list[float], conductivity: float, spacing: float | None
) -> None:
    host = reload(constructions()[identifier]).materials[0]
    grid = host.properties.ph.divisions
    assert grid.row_heights == [1.0]
    assert grid.column_widths == widths
    assert len(grid.cells) == len(widths)
    assert len({cell.material.identifier for cell in grid.cells}) == len(widths)
    assert host.conductivity == pytest.approx(conductivity)
    assert host.conductivity == pytest.approx(grid.get_equivalent_conductivity())
    base = grid.get_base_material()
    assert (host.density, host.specific_heat) == (base.density, base.specific_heat)
    assert grid.steel_stud_spacing_mm == spacing
    assert grid.is_a_steel_stud_cavity is (spacing is not None)


def test_reversed_membrane_is_side_channel_only_and_has_full_outside_index() -> None:
    construction = reload(constructions()["asm_Membrane0001"])
    assert [material.thickness for material in construction.materials] == [0.1, 0.01]
    metadata = construction.user_data["ph_composer"]
    assert set(metadata) == {"assembly_id", "membrane_layers"}
    membrane = metadata["membrane_layers"][0]
    assert membrane["outside_index"] == 1
    assert membrane["thickness_mm"] == 1
    assert membrane["layer_id"] == "lyr_000000000007"
    assert membrane["segment_id"] == "seg_000000000070"
    assert set(membrane["material"]) == {
        "project_material_id",
        "name",
        "category",
        "color",
        "density_kg_m3",
        "specific_heat_j_kgk",
        "emissivity",
    }
    assert membrane["material"]["project_material_id"] == "mat_Film00000001"


def test_mass_defaults_are_actual_written_values_with_nonblocking_disclosure() -> None:
    source = document()
    records = source["sections"][ConstructionSection.id]["records"]
    unset = next(row for row in records if row["id"] == "asm_Default00001")["materials"][0]
    unset["emissivity"] = None
    assert (unset["density_kg_m3"], unset["specific_heat_j_kgk"]) == (None, None)
    result = translate(source, (ConstructionSection(),))
    host = reload(
        cast(TranslatedConstruction, result.objects(ConstructionSection.id)["asm_Default00001"]).construction
    ).materials[0]
    assert (host.density, host.specific_heat, host.thermal_absorptance) == (600, 1000, 0.9)
    finding = next(f for f in result.findings if f.code == "material.thermal_mass_defaulted")
    assert not finding.blocks_export
    assert "600" in finding.message and "1000" in finding.message


@pytest.mark.parametrize(
    "change", [{"density_kg_m3": True}, {"conductivity_w_mk": None}, {"specific_heat_j_kgk": 99}, {"color": "bad"}]
)
def test_bad_material_costs_only_its_assembly_without_guessing(change: dict[str, object]) -> None:
    payload = document()
    row = next(row for row in payload["sections"][ConstructionSection.id]["records"] if row["id"] == "asm_Single000001")
    row["materials"][0].update(change)
    before = copy.deepcopy(payload)
    result = translate(payload, (ConstructionSection(),))
    assert row["id"] not in result.objects(ConstructionSection.id)
    assert "asm_Mixed0000001" in result.objects(ConstructionSection.id)
    assert payload == before


def test_nested_ids_are_scoped_by_assembly_in_actual_honeybee_definitions() -> None:
    payload = document()
    records = payload["sections"][ConstructionSection.id]["records"]
    original = next(row for row in records if row["id"] == "asm_Single000001")
    duplicate = copy.deepcopy(original)
    duplicate["id"] = "asm_Another00001"
    duplicate["layers"][0]["thickness_mm"] = 300
    records.append(duplicate)
    result = translate(payload, (ConstructionSection(),))
    first = cast(TranslatedConstruction, result.objects(ConstructionSection.id)[original["id"]]).construction
    second = cast(TranslatedConstruction, result.objects(ConstructionSection.id)[duplicate["id"]]).construction
    assert first.materials[0].identifier != second.materials[0].identifier
    assert first.materials[0].thickness == 0.1 and second.materials[0].thickness == 0.3


def model_document() -> dict[str, Any]:
    payload = cast(dict[str, Any], json.loads((ROOT.parent / "phase_one" / "two_zones_extraction.json").read_text()))
    payload["sections"].update(document()["sections"])
    from ph_composer_translation.window_sections import ApertureSection, WindowConstructionSection

    payload["sections"].update(
        {section.id: {"version": 1, "records": []} for section in (WindowConstructionSection(), ApertureSection())}
    )
    return payload


def test_actual_model_references_share_authored_construction_and_exclude_unused_assemblies() -> None:
    from ph_composer_translation.composition import SECTIONS
    from ph_composer_translation.conformance import check

    payload = model_document()
    faces = payload["sections"]["ph_composer.zones.faces.export.faces"]["records"]
    assigned = ["asm_Single000001", "asm_Mixed0000001", "asm_Steel0000001", "asm_Repeat000001", "asm_Membrane0001"]
    for index, face in enumerate(faces):
        face["assembly_id"] = assigned[index % len(assigned)]
    result = cast(dict[str, Any], translate(payload, SECTIONS).to_document())
    assert result["summary"]["publishable"] is True
    check(result["canonical_model"])
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    emitted = {face.identifier: face for room in model.rooms for face in room.faces}
    assert set(emitted) == {face["id"] for face in faces}
    for source in faces:
        actual = emitted[source["id"]].properties.energy.construction
        assert actual.user_data["ph_composer"]["assembly_id"] == source["assembly_id"]
        assert actual.identifier == f"ph_composer_{source['assembly_id']}"
        if source["assembly_id"] == "asm_Steel0000001":
            assert actual.materials[0].properties.ph.divisions.steel_stud_spacing_mm == 600
    shared = [
        emitted[face["id"]].properties.energy.construction
        for face in faces
        if face["assembly_id"] == "asm_Single000001"
    ]
    assert all(construction is shared[0] for construction in shared)
    identifiers = {construction.identifier for construction in model.properties.energy.constructions}
    assert "ph_composer_asm_Default00001" not in identifiers
    assert "ph_composer_asm_OnlyFilm0001" not in identifiers
    usage = {row["assembly_id"]: row for row in result["ph_composer.zones.export.zones"]["construction_usage"]}
    for identifier in assigned:
        used = [emitted[face["id"]] for face in faces if face["assembly_id"] == identifier]
        assert usage[identifier]["face_count"] == len(used)
        assert usage[identifier]["gross_area_m2"] == pytest.approx(sum(face.area for face in used))


@pytest.mark.parametrize("unavailable", [None, "asm_Absent000001", "asm_OnlyFilm0001"])
def test_unavailable_face_construction_costs_zone_and_keeps_independent_zone(
    unavailable: str | None,
) -> None:
    from ph_composer_translation.composition import SECTIONS

    payload = model_document()
    faces = payload["sections"]["ph_composer.zones.faces.export.faces"]["records"]
    # Independent Rooms continue. A failed Room is never emitted as a fabricated partial Room.
    for face in faces:
        if face["boundary_condition"] == "Surface":
            face["boundary_condition"] = "Outdoors"
            face["adjacency"] = None
    face = next(row for row in faces if row["zone_id"] == "zon_AAAAAAAAAAAA")
    face["assembly_id"] = unavailable
    result = cast(dict[str, Any], translate(payload, SECTIONS).to_document())
    assert result["summary"]["publishable"] is False
    canonical = result["canonical_model"]
    assert (canonical["rooms"], canonical["faces"]) == (1, 6)
    model = stack.load("honeybee.model").Model.from_dict(json.loads(canonical["hbjson"]))
    assert [room.identifier for room in model.rooms] == ["zon_BBBBBBBBBBBB"]
    finding = next(f for f in result["findings"] if f["code"] == "dependency.unavailable")
    assert finding["object_id"] == "zon_AAAAAAAAAAAA"
    assert face["id"] in finding["message"]
    assert (unavailable or "(unassigned)") in finding["message"]
    assert sum(row["face_count"] for row in result["ph_composer.zones.export.zones"]["construction_usage"]) == 6


def test_omitted_face_requires_no_construction_and_does_not_inflate_report_usage() -> None:
    from ph_composer_translation.composition import SECTIONS

    payload = model_document()
    face = payload["sections"]["ph_composer.zones.faces.export.faces"]["records"][0]
    face["assembly_id"] = "asm_Absent000001"
    face["boundary_condition"] = None
    face["omission"] = {
        "code": "face.boundary_unassigned",
        "reason": "No boundary",
        "zone_id": face["zone_id"],
        "area_m2": face["geometry"]["area_m2"],
    }
    result = cast(dict[str, Any], translate(payload, SECTIONS).to_document())
    assert result["summary"]["publishable"] is True
    assert result["canonical_model"]["faces"] == 11
    assert sum(row["face_count"] for row in result["ph_composer.zones.export.zones"]["construction_usage"]) == 11
    assert "asm_Absent000001" not in {
        row["assembly_id"] for row in result["ph_composer.zones.export.zones"]["construction_usage"]
    }


@pytest.mark.parametrize("thermal_count", [10, 11])
def test_pinned_opaque_construction_limit_preserves_authored_layers(thermal_count: int) -> None:
    payload = document()
    records = payload["sections"][ConstructionSection.id]["records"]
    row = next(row for row in records if row["id"] == "asm_Single000001")
    layer = row["layers"][0]
    row["layers"] = [
        dict(
            copy.deepcopy(layer),
            id=f"lyr_{index:012d}",
            segments=[dict(copy.deepcopy(layer["segments"][0]), id=f"seg_{index:012d}")],
        )
        for index in range(thermal_count)
    ]
    before = copy.deepcopy(payload)
    result = translate(payload, (ConstructionSection(),))
    assert (row["id"] in result.objects(ConstructionSection.id)) is (thermal_count == 10)
    assert payload == before
    if thermal_count == 11:
        assert any("10 materials" in finding.message for finding in result.findings if finding.object_id == row["id"])


@pytest.mark.parametrize("orientation", [{}, [], False, None, "inside"])
def test_unreadable_orientation_costs_record_only(orientation: object) -> None:
    payload = document()
    row = next(row for row in payload["sections"][ConstructionSection.id]["records"] if row["id"] == "asm_Single000001")
    row["orientation"] = orientation
    result = translate(payload, (ConstructionSection(),))
    assert row["id"] in result.results[ConstructionSection.id].unavailable
    assert "asm_Mixed0000001" in result.objects(ConstructionSection.id)


def test_multiple_steel_spacings_are_not_silently_collapsed() -> None:
    payload = document()
    row = next(row for row in payload["sections"][ConstructionSection.id]["records"] if row["id"] == "asm_Steel0000001")
    row["layers"][0]["segments"][1]["steel_stud_spacing_mm"] = 600
    result = translate(payload, (ConstructionSection(),))
    assert row["id"] in result.results[ConstructionSection.id].unavailable
    assert any("only one steel" in finding.message for finding in result.findings if finding.object_id == row["id"])


@pytest.mark.parametrize("emissivity", [None, 0, 0.25])
def test_authored_emissivity_controls_single_grid_cells_and_base_host_after_round_trip(
    emissivity: float | None,
) -> None:
    payload = document()
    records = payload["sections"][ConstructionSection.id]["records"]
    for row in records:
        for material in row["materials"]:
            material["emissivity"] = emissivity
    result = translate(payload, (ConstructionSection(),))
    expected = 0.9 if emissivity is None else emissivity
    for identifier in ("asm_Single000001", "asm_Mixed0000001", "asm_Repeat000001"):
        translated = cast(TranslatedConstruction, result.objects(ConstructionSection.id)[identifier])
        for material in reload(translated.construction).materials:
            assert material.thermal_absorptance == expected
            assert material.to_dict()["thermal_absorptance"] == expected
            if material.properties.ph.divisions.cell_count:
                for cell in material.properties.ph.divisions.cells:
                    assert cell.material.thermal_absorptance == expected
                    assert cell.material.to_dict()["thermal_absorptance"] == expected


@pytest.mark.parametrize("missing", [None, "", " ", 42])
def test_export_findings_name_materials_and_the_unassigned_assembly_layer(missing: object) -> None:
    payload = document()
    records = payload["sections"][ConstructionSection.id]["records"]
    payload["sections"][ConstructionSection.id]["records"] = [
        row for row in records if row["id"] in {"asm_Single000001", "asm_Default00001"}
    ]
    unassigned = next(row for row in records if row["id"] == "asm_Single000001")
    unassigned["layers"][0]["segments"][0]["material_id"] = missing
    result = translate(payload, (ConstructionSection(),))
    expected = json.loads((ROOT / "display_findings.json").read_text())
    assert [finding.to_json() for finding in result.findings] == expected
    assert set(result.objects(ConstructionSection.id)) == {"asm_Default00001"}
    assert result.publishable  # The incomplete unused definition still costs only itself.
