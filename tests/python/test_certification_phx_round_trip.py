"""The PHX round trip of each Building Segment's Phius certification settings (context/CONTRACTS.md, "Building
Segment settings"): the canonical HBJSON of the two-Segment extraction tests/segment_certification_test.rb writes,
House residential and ADU non-residential with no default value on either, converted by the pinned PHX of the
optional `phx` group. WUFI XML and METr JSON each carry two Variants, and each reads back its Segment's category,
program, use, status and type. Segment names hold no space: PHX 1.59.3 refuses one in `cleanup.merge_rooms`.
Skipped without the group: `uv run --group phx pytest tests/python/test_certification_phx_round_trip.py`."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import pytest

from test_certification_sections import run
from test_site_phx_round_trip import convert

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "segments" / "certification_extraction.json"
#: What each Variant reads back, by its Segment's name: honeybee-ph's enum number for category, program, use,
#: status and type, which PHX writes as WUFI's and METr's codes.
EXPECTED = {"House": (1, 6, 6, 3, 3), "ADU": (2, 8, 5, 2, 2)}
WUFI_TAGS = ("BuildingCategory", "PH_CertificateCriteria", "OccupancyTypeResidential", "BuildingStatus", "BuildingType")


def wufi_variants(xml: str) -> dict[str, tuple[int, ...]]:
    """Each WUFI XML Variant's name and its five certification codes."""
    rows = {}
    for block in re.findall(r"<Variant index=\"\d+\">(.*?)</Variant>", xml, re.S):
        name = re.search(r"<Name>([^<]*)</Name>", block)
        assert name is not None
        rows[name.group(1)] = tuple(int(re.findall(rf"<{tag}>([^<]*)</{tag}>", block)[0]) for tag in WUFI_TAGS)
    return rows


def metr_variants(metr: dict[str, Any]) -> dict[str, tuple[int, ...]]:
    """Each METr Variant's name and its five certification codes."""
    rows = {}
    for variant in metr["lVariant"]:
        found = _phius(variant)
        assert found, variant.get("n")
        rows[variant["n"]] = (
            found["bCatResnR"],
            found["certCri"],
            found["typeOccR"],
            found["bStatus"],
            found["tBState"],
        )
    return rows


def _phius(node: Any) -> dict[str, Any]:
    """The block that holds the category, wherever PHX nests it."""
    if isinstance(node, dict):
        if "bCatResnR" in node:
            return node
        node = list(node.values())
    if isinstance(node, list):
        for item in node:
            if found := _phius(item):
                return found
    return {}


def test_each_variant_reads_back_its_segments_five_values_in_wufi_xml_and_metr_json() -> None:
    result = run(json.loads(FIXTURE.read_text()))
    assert result["summary"]["publishable"] is True, result["findings"]

    xml, metr = convert(result)

    assert wufi_variants(xml) == EXPECTED
    assert metr_variants(metr) == EXPECTED
