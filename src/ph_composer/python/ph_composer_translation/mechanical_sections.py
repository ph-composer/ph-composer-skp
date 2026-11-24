"""Mechanical equipment, translated through the pinned honeybee-ph stack and attached to the Rooms it serves (Ruby
`features/mechanical/export.rb`; context/CONTRACTS.md, "Mechanical equipment").

Ventilation: one record per (Ventilator, served Zone) pair. Each becomes its own `PhVentilationSystem`, `sys_type`
1, holding a `Ventilator` with the record's values and its `user_data`, with the identifiers Ruby derived from the
Ventilator's id, so every Room one Ventilator serves carries equal objects: honeybee-ph reloads them as one system
and PHX keys one device. The objects stay mutable and keyed by pair until the assembly attaches them, so a later
section that requires this one (ducting) can add to them first; every object of one Ventilator must stay equal,
since honeybee-ph refuses to reload two systems that share an identifier and differ. No ducts are written here.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import stack
from .contract import JSONValue, RecordError
from .contract.mechanical_records import UNIT_FIELDS, VentilationRecord
from .model_sections import ZONE_SECTION_ID, TranslatedZone
from .sections import ROOM, Attachment, Inputs, Requirement, Section

VENTILATION_SECTION_ID = "ph_composer.mechanical.export.ventilation"
ZONES = Requirement(ZONE_SECTION_ID, TranslatedZone)
#: Balanced ventilation with heat recovery, the only system type PH-Composer writes.
SYS_TYPE = 1
#: Each record value and the honeybee-ph `Ventilator` attribute it sets.
UNIT_ATTRIBUTES = dict(
    zip(
        UNIT_FIELDS,
        (
            "quantity",
            "sensible_heat_recovery",
            "latent_heat_recovery",
            "electric_efficiency",
            "frost_protection_reqd",
            "temperature_below_defrost_used",
            "in_conditioned_space",
            "subsoil_heat_exchange_efficiency",
            "preheated_intake_temperature_c",
        ),
        strict=True,
    )
)
#: The identity fields of each result row, before the unit's values.
ROW_FIELDS = ("id", "item_id", "zone_id", "zone_name", "display_name", "system_identifier", "unit_identifier")


@dataclass(frozen=True)
class TranslatedVentilation:
    source: VentilationRecord
    zone_name: str
    system: Any

    @property
    def zone_id(self) -> str:
        return self.source.zone_id


def ventilation_system(record: VentilationRecord) -> Any:
    """The pair's system and unit, built as honeybee-ph's own constructors leave them and then given the record's
    values; the identifiers are Ruby's, so every pair of one Ventilator builds an equal object."""
    ventilation = stack.load("honeybee_phhvac.ventilation")
    unit = ventilation.Ventilator()
    unit.identifier, unit.display_name = record.unit_identifier, record.display_name
    for key, attribute in UNIT_ATTRIBUTES.items():
        setattr(unit, attribute, getattr(record, key))
    if record.user_data:
        unit.user_data = dict(record.user_data)
    system = ventilation.PhVentilationSystem()
    system.identifier, system.display_name, system.sys_type = record.system_identifier, record.display_name, SYS_TYPE
    system.ventilation_unit = unit
    return system


class VentilationSection(Section[VentilationRecord, TranslatedVentilation]):
    id = VENTILATION_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedVentilation
    requires = (ZONES,)
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> VentilationRecord:
        return VentilationRecord.read(raw)

    def translate(self, record: VentilationRecord, inputs: Inputs) -> TranslatedVentilation:
        zone = inputs.get(ZONES, record.zone_id)
        return TranslatedVentilation(record, zone.source.name, ventilation_system(record))

    def attach(self, host: Any, objects: Sequence[TranslatedVentilation]) -> None:
        """A Room holds one ventilation system, which Ruby's one Ventilator per Zone makes structural."""
        if len(objects) != 1:
            raise RecordError(f"Room {host.identifier} has more than one ventilation system")
        host.properties.ph_hvac.set_ventilation_system(objects[0].system)

    def result_fields(self, objects: Mapping[str, TranslatedVentilation]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [row(item) for _identifier, item in sorted(objects.items())]
        return {"ventilation": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported pair's Room holds its system with the reported identifiers, `sys_type` 1 and the unit's
        values; one Ventilator carries one identifier on every Room it serves; and no Room holds a ventilation
        system the run did not report."""
        rooms = {room.identifier: room for room in model.rooms}
        reported = fields.get("ventilation")
        rows = [item for item in (reported if isinstance(reported, list) else []) if isinstance(item, dict)]
        identifiers: dict[str, set[tuple[object, object]]] = {}
        for item in rows:
            room = rooms.get(str(item.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {item.get('zone_id')} is not in the model")
            check_system(room, item)
            identifiers.setdefault(str(item.get("item_id")), set()).add(
                (item.get("system_identifier"), item.get("unit_identifier"))
            )
        if shared := sorted(item_id for item_id, found in identifiers.items() if len(found) > 1):
            raise ValueError(f"Ventilator {', '.join(shared)} carries more than one identifier across its Rooms")
        named = {str(item.get("zone_id")) for item in rows}
        if extra := sorted(
            room.identifier
            for room in model.rooms
            if room.properties.ph_hvac.ventilation_system is not None and room.identifier not in named
        ):
            raise ValueError(f"Room {', '.join(extra)} holds a ventilation system the run did not report")


def row(item: TranslatedVentilation) -> dict[str, JSONValue]:
    record = item.source
    values: dict[str, JSONValue] = {
        "id": record.id,
        "item_id": record.item_id,
        "zone_id": record.zone_id,
        "zone_name": item.zone_name,
        "display_name": record.display_name,
        "system_identifier": record.system_identifier,
        "unit_identifier": record.unit_identifier,
    }
    for key in UNIT_FIELDS:
        values[key] = getattr(record, key)
    return values


def check_system(room: Any, item: Mapping[str, JSONValue]) -> None:
    system = room.properties.ph_hvac.ventilation_system
    if system is None:
        raise ValueError(f"Room {room.identifier} lost its ventilation system")
    unit = system.ventilation_unit
    found = {
        "system_identifier": system.identifier,
        "sys_type": system.sys_type,
        "unit_identifier": unit.identifier if unit is not None else None,
    }
    expected = {
        "system_identifier": item.get("system_identifier"),
        "sys_type": SYS_TYPE,
        "unit_identifier": item.get("unit_identifier"),
    }
    if found != expected:
        raise ValueError(f"Room {room.identifier} ventilation system is {found}, the run reported {expected}")
    for key, attribute in UNIT_ATTRIBUTES.items():
        actual, reported = getattr(unit, attribute), item.get(key)
        if actual != reported or isinstance(actual, bool) != isinstance(reported, bool):
            raise ValueError(f"Room {room.identifier} ventilator {key} is {actual!r}, the run reported {reported!r}")
