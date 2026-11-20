"""The Phius certification section (context/CONTRACTS.md, "Building Segment settings"): each exported Building
Segment's five values reach the one honeybee-ph `BldgSegment` its Rooms share, attached at the `segment` host
after the Site section has set its `Site`, which stays; every value Ruby offers maps to a value the pinned
honeybee-ph enum accepts; and a record naming no exported Segment, or holding an unknown value, is refused."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, cast

from ph_composer_translation import stack
from ph_composer_translation.certification_sections import CERTIFICATION_SECTION_ID, FIELDS
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.coordinator import translate
from ph_composer_translation.model_sections import _segment_identifier
from test_site_sections import comparable, document

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures" / "segments"
#: Ruby's values and defaults, written by tests/segment_certification_test.rb.
CHOICES = FIXTURES / "certification_choices.json"
#: The two-Segment extraction with non-default values on both, written by the same test.
EXTRACTION = FIXTURES / "certification_extraction.json"
ANNEX = {
    "category": "non_residential",
    "program": "phius_2018_core",
    "use": "other",
    "status": "complete",
    "type": "mixed",
}


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def segments(result: dict[str, Any]) -> dict[str, Any]:
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    return {room.display_name: room.properties.ph.ph_bldg_segment for room in model.rooms}


def values(segment: Any) -> dict[str, str]:
    certification = segment.phius_certification
    return {field: str(getattr(certification, attribute).value) for field, (attribute, _) in FIELDS.items()}


def record(identifier: str, export_identifier: str, payload: dict[str, str]) -> dict[str, str]:
    return {"id": identifier, "export_identifier": export_identifier, **payload}


def test_every_value_ruby_offers_maps_to_a_value_the_pinned_honeybee_ph_enum_accepts() -> None:
    stack.load("honeybee_ph")
    phius = stack.load("honeybee_ph.phius")
    choices = json.loads(CHOICES.read_text())
    assert set(choices["choices"]) == set(FIELDS)
    for field, offered in choices["choices"].items():
        attribute, mapped = FIELDS[field]
        assert set(offered) == set(mapped), field
        for value in offered:
            certification = phius.PhiusCertification()
            setattr(certification, attribute, mapped[value])
            assert getattr(certification, attribute).value == mapped[value]
    defaults = phius.PhiusCertification()
    assert {field: FIELDS[field][1][value] for field, value in choices["defaults"].items()} == values(
        type("Segment", (), {"phius_certification": defaults})()
    ), "the defaults are honeybee-ph's own"


def test_each_segment_carries_its_values_and_the_site_the_site_section_set() -> None:
    value = document(annex=True)
    defaults = json.loads(CHOICES.read_text())["defaults"]
    value["sections"][CERTIFICATION_SECTION_ID] = {
        "version": 1,
        "records": [
            record("bsg_AAAAAAAAAAAA", _segment_identifier("Main Building"), defaults),
            record("bsg_BBBBBBBBBBBB", _segment_identifier("Annex"), ANNEX),
        ],
    }

    result = run(value)

    assert result["summary"]["publishable"] is True, result["findings"]
    check(result["canonical_model"], result, SECTIONS)
    found = segments(result)
    assert values(found["Zone B"]) == {field: FIELDS[field][1][ANNEX[field]] for field in FIELDS}
    assert values(found["Zone A"])["category"] == "1-RESIDENTIAL BUILDING"
    first, second = (found["Zone A"].site, found["Zone B"].site)
    assert first.location.latitude == second.location.latitude == 40.0
    assert comparable(first.to_dict()) == comparable(second.to_dict()), "the Site is kept on both"
    assert [row["export_identifier"] for row in result[CERTIFICATION_SECTION_ID]["building_segments"]] == [
        _segment_identifier("Main Building"),
        _segment_identifier("Annex"),
    ]


def test_the_ruby_extraction_reloads_with_both_segments_non_default_values() -> None:
    result = run(json.loads(EXTRACTION.read_text()))

    assert result["summary"]["publishable"] is True, result["findings"]
    check(result["canonical_model"], result, SECTIONS)
    found = segments(result)
    assert values(found["Living"]) == {
        "category": "1-RESIDENTIAL BUILDING",
        "program": "6-PHIUS 2018 ZERO",
        "use": "6-OTHER",
        "status": "3-COMPLETE",
        "type": "3-MIXED",
    }
    assert values(found["Annex"]) == {
        "category": "2-NON-RESIDENTIAL BUILDING",
        "program": "8-PHIUS 2021 ZERO",
        "use": "5-SCHOOL",
        "status": "2-UNDER_CONSTRUCTION",
        "type": "2-RETROFIT",
    }


def test_a_record_for_no_exported_segment_or_with_an_unknown_value_withholds_the_model() -> None:
    for change in ({"export_identifier": "bseg_0000000000000000"}, {"use": "hotel"}):
        value = json.loads(EXTRACTION.read_text())
        value["sections"][CERTIFICATION_SECTION_ID]["records"][0].update(change)

        result = run(value)

        assert result["summary"]["publishable"] is False
        rows = [row for row in result["findings"] if row["section"] == CERTIFICATION_SECTION_ID]
        assert [row["blocks_export"] for row in rows] == [True], rows


def test_conformance_refuses_a_segment_whose_value_changed_after_assembly() -> None:
    result = run(json.loads(EXTRACTION.read_text()))
    hbjson = json.loads(result["canonical_model"]["hbjson"])
    for segment in hbjson["properties"]["ph"]["bldg_segments"]:
        segment["phius_certification"]["building_type"] = {"value": "1-NEW_CONSTRUCTION"}
    altered = {**result["canonical_model"], "hbjson": json.dumps(hbjson)}

    try:
        check(altered, result, SECTIONS)
    except ValueError as error:
        assert "type is 1-NEW_CONSTRUCTION" in str(error)
    else:
        raise AssertionError("conformance passed a model that does not say what was set")
