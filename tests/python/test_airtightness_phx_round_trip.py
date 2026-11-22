"""The PHX round trip of each Building Segment's airtightness (context/CONTRACTS.md, "Building Segment settings"):
the canonical HBJSON of the two-Segment extraction tests/segment_airtightness_test.rb writes, House with n50 2.0
and ADU with q50 0.6, converted by the pinned PHX of the optional `phx` group.

WUFI XML and METr JSON carry q50 alone (`EnvelopeAirtightnessCoefficient`, `tightEnv50`; METr's `n50` is NaN), so
each file's q50 is read back, and the n50 PHX reports is its own Variant's: q50 times the merged Room's gross
envelope area over its net volume. House's envelope tells PHX's area rules apart (an interior Surface pair it
drops; a Surface pair to the ADU, an Adiabatic wall and Ground floors it keeps), so a Ruby area that differed
from PHX's would move n50. Segment names hold no space: PHX 1.59.3 refuses one in `cleanup.merge_rooms`.
Skipped without the group:
`uv run --group phx pytest tests/python/test_airtightness_phx_round_trip.py`."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import pytest

from ph_composer_translation import stack
from test_certification_phx_round_trip import _phius
from test_certification_sections import run
from test_site_phx_round_trip import convert

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "segments" / "airtightness_extraction.json"
N50 = 2.0
ADU_Q50 = 0.6
#: House's envelope as tests/segment_airtightness_test.rb counts it: 158 m² kept, 95 m³ of Space.
HOUSE_Q50 = N50 * 95.0 / 158.0
#: Each Variant's wind exposure, honeybee-ph's number, which PHX writes as WUFI's and METr's code.
WIND = {"House": 5, "ADU": 3}


def wufi_variants(xml: str) -> dict[str, tuple[float, int]]:
    """Each WUFI XML Variant's name, q50 and wind exposure."""
    rows = {}
    for block in re.findall(r"<Variant index=\"\d+\">(.*?)</Variant>", xml, re.S):
        name = re.search(r"<Name>([^<]*)</Name>", block)
        q50 = re.search(r"<EnvelopeAirtightnessCoefficient>([^<]*)</EnvelopeAirtightnessCoefficient>", block)
        wind = re.search(r"<BuildingWindExposure>([^<]*)</BuildingWindExposure>", block)
        assert name and q50 and wind
        rows[name.group(1)] = (float(q50.group(1)), int(wind.group(1)))
    return rows


def metr_variants(metr: dict[str, Any]) -> dict[str, float]:
    """Each METr Variant's name and q50."""
    return {variant["n"]: float(_phius(variant)["tightEnv50"]) for variant in metr["lVariant"]}


def phx_variants(result: dict[str, Any]) -> dict[str, tuple[float, float]]:
    """Each PHX Variant's q50 and n50, as the converter computed them."""
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    project = create_project.convert_hb_model_to_PhxProject(model)
    return {
        variant.name: (
            variant.phius_cert.ph_building_data.airtightness_q50,
            variant.phius_cert.ph_building_data.airtightness_n50,
        )
        for variant in project.variants
    }


def test_an_n50_and_a_q50_segment_each_read_back_from_wufi_xml_and_metr_json_within_0_01() -> None:
    result = run(json.loads(FIXTURE.read_text()))
    assert result["summary"]["publishable"] is True, result["findings"]

    xml, metr = convert(result)
    wufi = wufi_variants(xml)
    metr_q50 = metr_variants(metr)
    phx = phx_variants(result)

    assert set(wufi) == set(metr_q50) == set(phx) == {"House", "ADU"}
    assert wufi["ADU"][0] == pytest.approx(ADU_Q50, abs=0.01)
    assert metr_q50["ADU"] == pytest.approx(ADU_Q50, abs=0.01)
    assert wufi["House"][0] == pytest.approx(HOUSE_Q50, abs=0.01)
    assert metr_q50["House"] == pytest.approx(HOUSE_Q50, abs=0.01)
    assert phx["House"][1] == pytest.approx(N50, abs=0.01), "PHX's n50 is the entered one"
    assert phx["House"][0] == pytest.approx(wufi["House"][0], abs=1e-9), "the file's q50 is PHX's"
    assert {name: row[1] for name, row in wufi.items()} == WIND
