# /// script
# requires-python = "==3.11.*"
# dependencies = [
#   "honeybee-core==1.64.65",
#   "honeybee-energy==1.123.23",
#   "honeybee-ph==1.33.68",
#   "honeybee-standards==2.0.7",
#   "ladybug-core==0.44.56",
#   "ladybug-geometry==1.35.3",
#   "ladybug-geometry-polyskel==1.7.52",
#   "ph-units==1.5.38",
# ]
# ///
"""Verify the normal authored-construction composition and its exact two-Zone HBJSON."""

from __future__ import annotations

import importlib.metadata
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "src" / "ph_composer" / "python"))

from ph_composer_translation import stack  # noqa: E402
from ph_composer_translation.composition import SECTIONS  # noqa: E402
from ph_composer_translation.coordinator import translate  # noqa: E402

FIXTURE = ROOT / "tests" / "fixtures" / "phase_one" / "two_zones_extraction.json"
PINNED = {
    "honeybee-core": "1.64.65",
    "honeybee-energy": "1.123.23",
    "honeybee-ph": "1.33.68",
    "honeybee-standards": "2.0.7",
    "ladybug-core": "0.44.56",
    "ladybug-geometry": "1.35.3",
    "ladybug-geometry-polyskel": "1.7.52",
    "ph-units": "1.5.38",
}


def main() -> int:
    versions = {name: importlib.metadata.version(name) for name in PINNED}
    assert versions == PINNED, versions
    extraction = json.loads(FIXTURE.read_text())
    # Complete the current contributor envelope without changing the retained Phase 1 records.
    for name in ("window_constructions", "apertures"):
        extraction["sections"][f"ph_composer.windows.export.{name}"] = {"version": 1, "records": []}
    translated = translate(extraction, SECTIONS)
    result = translated.to_document()
    assert result["state"] == "complete" and result["summary"] == {
        "objects": 15,
        "unavailable": 0,
        "findings": 0,
        "publishable": True,
    }
    canonical = result["canonical_model"]
    assert canonical == {**canonical, "rooms": 2, "faces": 12, "surface_pairs": 1}

    hbjson = json.loads(canonical["hbjson"])
    model = stack.load("honeybee.model").Model.from_dict(hbjson)
    assert {room.identifier for room in model.rooms} == {"zon_AAAAAAAAAAAA", "zon_BBBBBBBBBBBB"}
    faces = {face.identifier: face for room in model.rooms for face in room.faces}
    assert set(faces) == {f"fac_{letter}{number:011d}" for letter in "AB" for number in range(1, 7)}
    surfaces = [face for face in faces.values() if face.boundary_condition.name == "Surface"]
    assert len(surfaces) == 2
    for face in surfaces:
        target = face.boundary_condition.boundary_condition_objects[0]
        assert target in faces and faces[target].boundary_condition.boundary_condition_objects[0] == face.identifier
    assert abs(sum(room.volume for room in model.rooms) - 108.0) < 1e-8
    floor_area = sum(face.area for face in faces.values() if face.type.name == "Floor")
    roof_area = sum(face.area for face in faces.values() if face.type.name == "RoofCeiling")
    outside_wall_area = sum(
        face.area for face in faces.values() if face.type.name == "Wall" and face.boundary_condition.name == "Outdoors"
    )
    assert abs(floor_area - 36.0) < 1e-8
    assert abs(roof_area - 36.0) < 1e-8
    assert abs(outside_wall_area - 78.0) < 1e-8
    segments = hbjson["properties"]["ph"]["bldg_segments"]
    assert len(segments) == 1 and segments[0]["display_name"] == "Main Building"
    assert all(room["properties"]["ph"]["ph_bldg_segment_id"] == segments[0]["identifier"] for room in hbjson["rooms"])
    assert all(
        face.properties.energy.construction.identifier == "ph_composer_asm_Single000001" for face in faces.values()
    )
    if "--write-hbjson" in sys.argv:
        # The exact canonical bytes, for the Ruby artifact-guard contract example.
        Path(sys.argv[sys.argv.index("--write-hbjson") + 1]).write_text(canonical["hbjson"])
    print(json.dumps({"state": "PASS", "versions": versions, **{k: canonical[k] for k in canonical if k != "hbjson"}}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
