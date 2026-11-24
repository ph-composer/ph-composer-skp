"""One Ventilator serving two Zones, written as one honeybee-ph object per (item, Zone) pair that share the item's
identifiers (context/CONTRACTS.md, "Translation sections and artifacts"): a section attaching at `ROOM` builds a
separate `PhVentilationSystem` and `Ventilator` for each Room, and the canonical HBJSON reloads both Rooms onto
one system whose unit carries the record's values. The pinned honeybee-ph keys the systems by identifier on
reload and refuses two that share one but differ, so equal identifiers must mean equal objects."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.contract import as_text
from ph_composer_translation.coordinator import translate
from ph_composer_translation.model_sections import TranslatedZone, ZoneSection
from ph_composer_translation.sections import ROOM, Attachment, Inputs, Requirement, Section
from ph_composer_translation.space_sections import SPACE_SECTION_ID
from test_space_sections import segment, space, square, volume

FIXTURE = Path(__file__).resolve().parents[1] / "fixtures" / "phase_one" / "two_zones_extraction.json"
ID = "test.shared_ventilators"
ZONE_A = "zon_AAAAAAAAAAAA"
ZONE_B = "zon_BBBBBBBBBBBB"
ITEM = "vnt_SharedUnit01"
#: Not the honeybee-ph defaults, so a reloaded unit shows the record's values and not its own.
UNIT = {
    "quantity": 2,
    "sensible_heat_recovery": 0.84,
    "latent_heat_recovery": 0.12,
    "electric_efficiency": 0.41,
    "frost_protection_reqd": False,
    "temperature_below_defrost_used": -8.0,
    "in_conditioned_space": True,
}


@dataclass(frozen=True)
class ServedPair:
    """One (Ventilator, served Zone) pair: what a ventilation section reads per pair."""

    identifier: str
    item_id: str
    zone_id: str
    unit: Mapping[str, object]


@dataclass(frozen=True)
class RoomVentilation:
    zone_id: str
    system: Any


class SharedVentilators(Section[ServedPair, RoomVentilation]):
    id = ID
    versions = frozenset({1})
    object_type = RoomVentilation
    ZONES = Requirement(ZoneSection.id, TranslatedZone)
    requires = (ZONES,)
    attaches = Attachment(ROOM, key=lambda translated: translated.zone_id)

    def read(self, raw: Mapping[str, object]) -> ServedPair:
        return ServedPair(
            as_text(raw["id"], "id"),
            as_text(raw["item_id"], "item_id"),
            as_text(raw["zone_id"], "zone_id"),
            cast(Mapping[str, object], raw["unit"]),
        )

    def __init__(self) -> None:
        self.built: list[Any] = []

    def translate(self, record: ServedPair, inputs: Inputs) -> RoomVentilation:
        inputs.get(self.ZONES, record.zone_id)
        ventilation = stack.load("honeybee_phhvac.ventilation")
        unit = ventilation.Ventilator()
        unit.identifier, unit.display_name = f"{record.item_id}_unit", "ERV-1"
        for key, value in record.unit.items():
            setattr(unit, key, value)
        system = ventilation.PhVentilationSystem()
        system.identifier, system.display_name = record.item_id, "ERV-1"
        system.ventilation_unit = unit
        self.built.append(system)
        return RoomVentilation(record.zone_id, system)

    def attach(self, host: Any, objects: Sequence[RoomVentilation]) -> None:
        for item in objects:
            host.properties.ph_hvac.set_ventilation_system(item.system)


def pair(zone: str) -> dict[str, Any]:
    return {"id": f"{ITEM}_{zone}", "item_id": ITEM, "zone_id": zone, "unit": UNIT}


def extraction(*records: dict[str, Any], spaces: Sequence[dict[str, Any]] = ()) -> dict[str, Any]:
    value: dict[str, Any] = json.loads(FIXTURE.read_text())
    value["sections"].update(
        {
            "ph_composer.windows.export.window_constructions": {"version": 1, "records": []},
            "ph_composer.windows.export.apertures": {"version": 1, "records": []},
            SPACE_SECTION_ID: {"version": 2, "records": list(spaces)},
            ID: {"version": 1, "records": list(records)},
        }
    )
    return value


def run(value: dict[str, Any], section: SharedVentilators | None = None) -> dict[str, Any]:
    sections = (*SECTIONS, section or SharedVentilators())
    return cast(dict[str, Any], translate(value, sections).to_document())


def one_space_per_zone() -> list[dict[str, Any]]:
    """A detailed Space on each Zone: PHX reads a Room's ventilation through its Spaces."""
    found = []
    for zone, x in ((ZONE_A, 1.0), (ZONE_B, 6.0)):
        tag = zone[-4:]
        floor = [volume(f"vol_{tag}", [segment(f"fsg_{tag}", [square(x, 1, 2)])], 2.5)]
        found.append(space(f"spc_{tag}", zone, floor, v_sup_m3h=60.0, v_eta_m3h=60.0))
    return found


def reload(hbjson: str) -> Any:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    stack.load("honeybee_phhvac")
    return stack.load("honeybee.model").Model.from_dict(json.loads(hbjson))


def test_two_rooms_written_with_equal_identifiers_reload_onto_one_system_carrying_the_records_values() -> None:
    section = SharedVentilators()
    result = run(extraction(pair(ZONE_A), pair(ZONE_B)), section)
    assert result["summary"]["publishable"] is True, result["findings"]
    first, second = section.built
    assert first is not second and first.identifier == second.identifier, "one object per (item, Zone) pair"

    written = json.loads(result["canonical_model"]["hbjson"])
    systems = [room["properties"]["ph_hvac"]["ventilation_system"] for room in written["rooms"]]
    assert [system["identifier"] for system in systems] == [ITEM, ITEM]
    assert systems[0] == systems[1], "two objects, written equal"

    model = reload(result["canonical_model"]["hbjson"])
    rooms = {room.identifier: room.properties.ph_hvac.ventilation_system for room in model.rooms}
    assert set(rooms) == {ZONE_A, ZONE_B}
    assert rooms[ZONE_A] is rooms[ZONE_B], "honeybee-ph reloads one system for the shared identifier"
    unit = rooms[ZONE_A].ventilation_unit
    assert unit.identifier == f"{ITEM}_unit"
    assert {key: getattr(unit, key) for key in UNIT} == UNIT


def test_two_rooms_sharing_an_identifier_with_different_values_do_not_reload() -> None:
    result = run(extraction(pair(ZONE_A), pair(ZONE_B)))
    written = json.loads(result["canonical_model"]["hbjson"])
    written["rooms"][1]["properties"]["ph_hvac"]["ventilation_system"]["ventilation_unit"]["quantity"] = 3

    # honeybee re-raises the ValueError as a bare Exception naming it.
    with pytest.raises(Exception, match="Conflicting ventilation systems share identifier"):
        reload(json.dumps(written))
