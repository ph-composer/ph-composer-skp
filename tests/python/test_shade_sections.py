"""The Shades section over the extraction Ruby writes for ACCEPTANCE's reference model
(tests/shading_export_test.rb): each Shading Face occurrence becomes an orphaned, detached honeybee Shade named for
its shading component, read back from the canonical HBJSON; a Shade that fails is left out without withholding
the model; and a Model with no shading writes the same HBJSON and result as before the section existed."""

from __future__ import annotations

import copy
import json
import re
from collections import Counter
from collections.abc import Sequence
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.contract import RecordError
from ph_composer_translation.contract.shade_records import ShadeRecord
from ph_composer_translation.coordinator import translate
from ph_composer_translation.sections import AttachmentRefused, Section
from ph_composer_translation.shade_sections import SHADE_SECTION_ID, ShadeSection, TranslatedShade

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
FIXTURE = FIXTURES / "shading" / "extraction.json"
#: The result fields the Ruby contributor declares, written by tests/shading_export_test.rb.
RESULT_FIELDS = FIXTURE.with_name("result_fields.json")
PHASE_ONE = FIXTURES / "phase_one" / "two_zones_extraction.json"
EXPECTED = {"Fin": 2, "Louvre": 6, "Neighbour": 6, "Shading": 3, "Zone A Shading": 1}
WINDOWS = ("ph_composer.windows.export.window_constructions", "ph_composer.windows.export.apertures")


def document(path: Path = FIXTURE) -> dict[str, Any]:
    value: dict[str, Any] = json.loads(path.read_text())
    value["sections"].update({section: {"version": 1, "records": []} for section in WINDOWS})
    return value


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][SHADE_SECTION_ID]["records"])


def run(value: dict[str, Any], sections: Sequence[Section[Any, Any]] = SECTIONS) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, sections).to_document())


def reloaded(result: dict[str, Any]) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    return stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))


def test_eighteen_detached_shades_read_back_in_five_components() -> None:
    result = run(document())

    assert result["summary"]["publishable"] is True
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)
    model = reloaded(result)
    shades = model.orphaned_shades
    assert Counter(shade.display_name for shade in shades) == EXPECTED
    assert all(shade.is_detached for shade in shades)
    assert sorted(shade.identifier for shade in shades) == sorted(record["id"] for record in records(document()))
    holed = next(shade for shade in shades if shade.geometry.has_holes)
    assert holed.area == pytest.approx(32.0) and holed.display_name == "Shading"
    fields = result[SHADE_SECTION_ID]
    assert fields["shade_count"] == 18 and fields["area_m2"] == pytest.approx(sum(shade.area for shade in shades))
    assert {row["display_name"]: row["face_count"] for row in fields["shading_components"]} == EXPECTED
    assert len(model.rooms) == 1, "the Room is unchanged by the Shades beside it"


def test_each_component_row_has_exactly_the_fields_the_ruby_contributor_declares() -> None:
    declared = json.loads(RESULT_FIELDS.read_text())
    rows = run(document())[SHADE_SECTION_ID]["shading_components"]
    assert all(sorted(row) == sorted(declared) for row in rows)


class RefusingShadeSection(ShadeSection):
    """The test seam for a refused attach: the Model refuses the holed Face's Shade, as nothing in the product can
    arrange, so `attach` refuses that Shade alone."""

    def refused(self, model: Any, objects: Sequence[TranslatedShade]) -> list[TranslatedShade]:
        forced = [item for item in objects if item.source.holes]
        return forced + [item for item in super().refused(model, objects) if item not in forced]


def test_a_refused_shade_is_left_out_with_a_non_blocking_finding_and_the_model_is_still_written() -> None:
    sections = tuple(RefusingShadeSection() if isinstance(section, ShadeSection) else section for section in SECTIONS)
    result = run(document(), sections)

    assert result["summary"]["publishable"] is True and "canonical_model" in result
    (finding,) = result["findings"]
    assert (finding["code"], finding["section"], finding["blocks_export"]) == (
        "object.unavailable",
        SHADE_SECTION_ID,
        False,
    )
    check(result["canonical_model"], result, sections)
    assert len(reloaded(result).orphaned_shades) == 17
    assert result[SHADE_SECTION_ID]["shade_count"] == 17


def test_an_unreadable_shade_costs_that_shade_only() -> None:
    value = document()
    rows = records(value)
    rows[0]["boundary"] = rows[0]["boundary"][:2]
    rows[1]["colour"] = "red"
    result = run(value)

    assert result["summary"]["publishable"] is True
    assert sorted(finding["object_id"] for finding in result["findings"]) == sorted([rows[0]["id"], rows[1]["id"]])
    assert all(finding["blocks_export"] is False for finding in result["findings"])
    check(result["canonical_model"], result, SECTIONS)
    assert len(reloaded(result).orphaned_shades) == 16


def test_the_record_contract_names_each_malformed_field() -> None:
    good = records(document())[0]
    for change, message in (
        ({"id": ""}, "shade id must be non-empty text"),
        ({"display_name": None}, "display_name must be non-empty text"),
        ({"holes": [[[0, 0, 0], [1, 0, 0]]]}, "hole 1 must have at least three points"),
        ({"boundary": [[0, 0, 0], [1, 0, "x"], [1, 1, 0]]}, "boundary must be a finite number"),
        ({"unknown": 1}, "unknown fields: unknown"),
    ):
        with pytest.raises(RecordError, match=message):
            ShadeRecord.read({**good, **change})


def test_an_unread_section_version_fails_the_run_before_translation() -> None:
    value = document()
    value["sections"][SHADE_SECTION_ID]["version"] = 2
    result = run(value)
    assert result["failure"]["code"] == "section.version_unsupported" and "canonical_model" not in result


def test_conformance_refuses_a_model_that_does_not_hold_the_reported_shades() -> None:
    result = run(document())
    altered = copy.deepcopy(result)
    altered[SHADE_SECTION_ID]["shade_count"] = 17
    with pytest.raises(ValueError, match="holds 18 orphaned Shades"):
        check(altered["canonical_model"], altered, SECTIONS)
    altered = copy.deepcopy(result)
    altered[SHADE_SECTION_ID]["shading_components"][0]["area_m2"] += 1.0
    with pytest.raises(ValueError, match="reads back"):
        check(altered["canonical_model"], altered, SECTIONS)
    hbjson = json.loads(result["canonical_model"]["hbjson"])
    hbjson["orphaned_shades"][0]["is_detached"] = False
    with pytest.raises(ValueError, match="not detached"):
        check({**result["canonical_model"], "hbjson": json.dumps(hbjson)}, result, SECTIONS)


def normalized(value: Any) -> Any:
    """The result with the pinned PH stack's random default identifiers masked and identified lists sorted, as
    test_window_sections.py compares the legacy HBJSON."""
    if isinstance(value, str):
        return re.sub(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", "<default-ph-uuid>", value)
    if isinstance(value, dict):
        return {key: normalized(json.loads(item) if key == "hbjson" else item) for key, item in value.items()}
    if isinstance(value, list):
        items = [normalized(item) for item in value]
        if items and all(isinstance(item, dict) and "identifier" in item for item in items):
            return sorted(items, key=lambda item: item["identifier"])
        return items
    return value


def test_a_model_with_no_shading_exports_exactly_as_before_the_section() -> None:
    with_section = run(document(PHASE_ONE))
    before = document(PHASE_ONE)
    del before["sections"][SHADE_SECTION_ID]
    without = run(before, tuple(section for section in SECTIONS if not isinstance(section, ShadeSection)))

    assert SHADE_SECTION_ID not in with_section
    assert "orphaned_shades" not in json.loads(with_section["canonical_model"]["hbjson"])
    # The result lists the section it ran, with nothing in it; everything else, the HBJSON included, is unchanged.
    row = {"id": SHADE_SECTION_ID, "objects": [], "unavailable": []}
    assert row in with_section["sections"]
    with_section["sections"].remove(row)
    assert normalized(with_section) == normalized(without)
    check(without["canonical_model"], with_section, SECTIONS)


def test_attach_refuses_a_shade_whose_identifier_the_model_already_holds() -> None:
    section = ShadeSection()
    rows = records(document())[:2]
    built = [section.translate(section.read(row), cast(Any, None)) for row in rows]
    model = stack.load("honeybee.model").Model("held", units="Meters")
    model.add_shade(section.translate(section.read(rows[0]), cast(Any, None)).shade)

    with pytest.raises(AttachmentRefused) as refused:
        section.attach(model, built)
    assert refused.value.refused == (built[0],)
    assert [item.attached for item in built] == [False, True]
    assert sorted(shade.identifier for shade in model.orphaned_shades) == sorted(row["id"] for row in rows)
