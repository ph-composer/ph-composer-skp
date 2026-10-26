"""The thermal-bridge section over the extraction Ruby writes for ACCEPTANCE's reference model
(tests/thermal_bridge_export_test.rb): each run becomes a honeybee-ph PhThermalBridge on its Zone's
Building-Segment, read back from the canonical HBJSON with its geometry, psi-value, group and quantity; a run
that fails is left out without withholding the model."""

from __future__ import annotations

import copy
import json
from collections.abc import Sequence
from pathlib import Path
from typing import Any, ClassVar, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.coordinator import translate
from ph_composer_translation.entry import export_json
from ph_composer_translation.sections import Section
from ph_composer_translation.thermal_bridge_sections import (
    THERMAL_BRIDGE_SECTION_ID,
    ThermalBridgeSection,
    TranslatedThermalBridge,
)

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "thermal_bridges" / "extraction.json"
#: The result fields the Ruby contributor declares, written by tests/thermal_bridge_export_test.rb.
RESULT_FIELDS = FIXTURE.with_name("result_fields.json")
#: ACCEPTANCE's hand calculation: length in metres, psi, group, quantity and point count by run name.
EXPECTED = {
    "Parapet 1": (14.0, 0.05, "15-AMBIENT", 1.0, 4),
    "Parapet 2": (12.0, 0.05, "15-AMBIENT", 1.0, 4),
    "Slab edge 1": (14.0, 0.12, "16-PERIMETER", 1.0, 4),
    "Footing 1": (12.0, -0.02, "17-FS/BC", 1.0, 4),
    "Balcony 1": (4.0, 0.25, "15-AMBIENT", 2.0, 2),
}


def document() -> dict[str, Any]:
    value: dict[str, Any] = json.loads(FIXTURE.read_text())
    value["sections"].update(
        {
            "ph_composer.windows.export.window_constructions": {"version": 1, "records": []},
            "ph_composer.windows.export.apertures": {"version": 1, "records": []},
        }
    )
    return value


def records(value: dict[str, Any]) -> list[dict[str, Any]]:
    return cast(list[dict[str, Any]], value["sections"][THERMAL_BRIDGE_SECTION_ID]["records"])


def run(value: dict[str, Any], sections: Sequence[Section[Any, Any]] = SECTIONS) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, sections).to_document())


def segments(result: dict[str, Any]) -> list[Any]:
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    found = {room.properties.ph.ph_bldg_segment.identifier: room.properties.ph.ph_bldg_segment for room in model.rooms}
    return list(found.values())


def test_five_runs_read_back_on_one_building_segment_shared_by_both_rooms() -> None:
    result = run(document())

    assert result["summary"]["publishable"] is True
    assert result["findings"] == []
    check(result["canonical_model"], result, SECTIONS)
    (segment,) = segments(result)
    bridges = {bridge.display_name: bridge for bridge in segment.thermal_bridges.values()}
    assert sorted(bridges) == sorted(EXPECTED)
    for name, (length, psi, group, quantity, points) in EXPECTED.items():
        bridge = bridges[name]
        assert bridge.length == pytest.approx(length, abs=1e-9)
        assert (bridge.psi_value, bridge.group_type.value.upper(), bridge.quantity) == (psi, group, quantity)
        vertices = bridge.geometry.vertices
        assert len(vertices) == points
        assert type(bridge.geometry).__name__ == ("LineSegment3D" if points == 2 else "Polyline3D")
        assert list(bridge.user_data) == ["ph_composer"] and list(bridge.user_data["ph_composer"]) == [
            "thermal_bridge_type_id"
        ]
    assert bridges["Footing 1"].user_data["ph_composer"]["thermal_bridge_type_id"] == "tbt_FOOTING00001"
    rows = {row["display_name"]: row for row in result[THERMAL_BRIDGE_SECTION_ID]["thermal_bridge_runs"]}
    assert rows["Balcony 1"]["heat_loss_w_k"] == pytest.approx(2.0)
    assert sum(row["heat_loss_w_k"] for row in rows.values()) == pytest.approx(4.74)


def test_a_closed_run_repeats_its_first_point_and_reads_back_its_length() -> None:
    value = document()
    parapet = next(row for row in records(value) if row["display_name"] == "Parapet 1")
    parapet["points_m"] = [*parapet["points_m"], parapet["points_m"][0]]
    parapet["closed"] = True

    result = run(value)
    bridge = next(b for b in segments(result)[0].thermal_bridges.values() if b.display_name == "Parapet 1")
    assert bridge.length == pytest.approx(18.0)
    assert bridge.geometry.vertices[0] == bridge.geometry.vertices[-1]
    check(result["canonical_model"], result, SECTIONS)


class RefusingSection(ThermalBridgeSection):
    """The test seam for a refused attach: the Building-Segment refuses Balcony 1, as nothing in the product
    can arrange, so `attach` refuses that run alone."""

    def refused(self, segment: Any, objects: Sequence[TranslatedThermalBridge]) -> list[TranslatedThermalBridge]:
        forced = [item for item in objects if item.source.display_name == "Balcony 1"]
        return forced + [item for item in super().refused(segment, objects) if item not in forced]


def test_a_refused_run_is_left_out_with_a_non_blocking_finding_and_the_rest_export() -> None:
    sections = tuple(RefusingSection() if item.id == THERMAL_BRIDGE_SECTION_ID else item for item in SECTIONS)
    # The packaged entry point, which reloads the exact bytes and runs every section's conformance.
    result = cast(dict[str, Any], json.loads(export_json(json.dumps(document()), sections)))

    unavailable = [(f["code"], f["blocks_export"]) for f in result["findings"]]
    assert unavailable == [("object.unavailable", False)]
    assert result["summary"]["publishable"] is True
    rows = result[THERMAL_BRIDGE_SECTION_ID]["thermal_bridge_runs"]
    assert sorted(row["display_name"] for row in rows) == sorted(set(EXPECTED) - {"Balcony 1"})
    (segment,) = segments(result)
    assert sorted(bridge.display_name for bridge in segment.thermal_bridges.values()) == sorted(
        set(EXPECTED) - {"Balcony 1"}
    )


def test_a_required_section_refusing_a_run_still_withholds_the_model() -> None:
    class Required(RefusingSection):
        required_for_export: ClassVar[bool] = True

    sections = tuple(Required() if item.id == THERMAL_BRIDGE_SECTION_ID else item for item in SECTIONS)
    result = run(document(), sections)
    assert [(f["code"], f["blocks_export"]) for f in result["findings"]] == [("object.unavailable", True)]
    assert "canonical_model" not in result


def test_two_building_segments_each_carry_their_own_zones_runs() -> None:
    value = document()
    zones = value["sections"]["ph_composer.zones.export.zones"]["records"]
    next(zone for zone in zones if zone["id"] == "zon_BBBBBBBBBBBB")["building_segment"] = "Annex"

    result = run(value)
    check(result["canonical_model"], result, SECTIONS)
    by_segment = {segment.display_name: segment for segment in segments(result)}
    names = {name: sorted(b.display_name for b in s.thermal_bridges.values()) for name, s in by_segment.items()}
    assert names == {"Main Building": ["Parapet 1", "Slab edge 1"], "Annex": ["Balcony 1", "Footing 1", "Parapet 2"]}


def test_each_result_row_has_exactly_the_fields_the_ruby_contributor_declares() -> None:
    declared = json.loads(RESULT_FIELDS.read_text())
    rows = run(document())[THERMAL_BRIDGE_SECTION_ID]["thermal_bridge_runs"]
    assert rows and all(sorted(row) == sorted(declared) for row in rows)


def test_an_unreadable_run_costs_that_run_only_and_the_model_is_still_written() -> None:
    value = document()
    records(value)[0]["group"] = "Ambient"

    result = run(value)
    assert [(f["code"], f["blocks_export"]) for f in result["findings"]] == [("object.unavailable", False)]
    assert result["summary"]["publishable"] is True
    assert len(result[THERMAL_BRIDGE_SECTION_ID]["thermal_bridge_runs"]) == 4
    check(result["canonical_model"], result, SECTIONS)


def test_conformance_refuses_a_run_the_model_does_not_hold_as_reported() -> None:
    result = run(document())
    altered = copy.deepcopy(result)
    altered[THERMAL_BRIDGE_SECTION_ID]["thermal_bridge_runs"][0]["length_m"] += 0.5
    with pytest.raises(ValueError, match="reads back"):
        check(altered["canonical_model"], altered, SECTIONS)
    altered = copy.deepcopy(result)
    altered[THERMAL_BRIDGE_SECTION_ID]["thermal_bridge_runs"].pop()
    with pytest.raises(ValueError, match="did not report"):
        check(altered["canonical_model"], altered, SECTIONS)
