"""The PHX round trip of the exported Shades (context/CONTRACTS.md, "Translation sections and artifacts"): the
canonical HBJSON of ACCEPTANCE's reference model, converted by the pinned PHX of the optional `phx` group to WUFI
XML and METr JSON, carries one shading component per name in every Variant, with no interior attachment.
Skipped without the group: `uv run --group phx pytest tests/python/test_shade_phx_round_trip.py`."""

from __future__ import annotations

import re
from collections import Counter
from typing import Any

import pytest

from test_shade_sections import EXPECTED, document, reloaded, run
from test_site_phx_round_trip import convert

create_project = pytest.importorskip("PHX.from_HBJSON.create_project")


TAGS = ("Name", "InnerAttachment", "OuterAttachment", "IdentNrAssembly")


def wufi_components(xml: str) -> list[dict[str, str]]:
    """Each WUFI XML Component's name, attachments and assembly."""
    rows = []
    for block in re.findall(r"<Component(?: [^>]*)?>(.*?)</Component>", xml, re.S):
        found = {tag: re.search(rf"<{tag}>([^<]*)</{tag}>", block) for tag in TAGS}
        rows.append({tag: match.group(1) if match else "" for tag, match in found.items()})
    return rows


def metr_components(node: Any) -> list[dict[str, Any]]:
    """Every METr component row, wherever the project nests it."""
    if isinstance(node, dict):
        found = [node] if "idIC" in node and "n" in node else []
        return found + [row for item in node.values() for row in metr_components(item)]
    if isinstance(node, list):
        return [row for item in node for row in metr_components(item)]
    return []


def test_the_reference_shading_reaches_wufi_xml_and_metr_json_as_five_components_per_variant() -> None:
    result = run(document())
    model = reloaded(result)
    project = create_project.convert_hb_model_to_PhxProject(model)
    variants = len(project.variants)
    xml, metr = convert(result)

    shading = [row for row in wufi_components(xml) if row["Name"] in EXPECTED]
    assert variants == 1
    assert Counter(row["Name"] for row in shading) == Counter({name: variants for name in EXPECTED})
    assert all(row["InnerAttachment"] == "-1" and row["OuterAttachment"] == "-1" for row in shading)
    assert all(row["IdentNrAssembly"] == "-1" for row in shading)

    rows = [row for row in metr_components(metr) if row["n"] in EXPECTED]
    assert Counter(row["n"] for row in rows) == Counter({name: variants for name in EXPECTED})
    assert all(row["idIC"] == -1 and row["idEC"] == -1 for row in rows)
    areas = {
        row["display_name"]: row["area_m2"] for row in result["ph_composer.shading.export.shades"]["shading_components"]
    }
    assert {row["n"]: row["areaC"] for row in rows} == pytest.approx(areas)
