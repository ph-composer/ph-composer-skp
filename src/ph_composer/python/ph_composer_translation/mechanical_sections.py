"""Mechanical equipment, translated through the pinned honeybee-ph stack and attached to the Rooms it serves (Ruby
`features/mechanical/export.rb`; context/CONTRACTS.md, "Mechanical equipment").

Ventilation: one record per (Ventilator, served Zone) pair. Each becomes its own `PhVentilationSystem`, `sys_type`
1, holding a `Ventilator` with the record's values and its `user_data`, with the identifiers Ruby derived from the
Ventilator's id, so every Room one Ventilator serves carries equal objects: honeybee-ph reloads them as one system
and PHX keys one device. The objects stay mutable and keyed by pair until the assembly attaches them, so a later
section that requires this one (ducting) can add to them first; every object of one Ventilator must stay equal,
since honeybee-ph refuses to reload two systems that share an identifier and differ. No ducts are written here.

Hot water: one record per (Hot Water System, served Zone) pair. Each becomes its own `PhHotWaterSystem` under the
System's id, holding the Tanks in the slots Ruby worked out and the Heaters, each a fresh honeybee-ph object under its
own record's id, so every Room one System serves carries equal objects and PHX keys each tank and heater once. The
recirculation temperature and hours are honeybee-ph's, read from piping this section does not write. honeybee-ph
reloads two hot water systems sharing an identifier by keeping the last, so a difference between them would vanish
before `conformance`: each row records the digest of its system as translated, and `conformance` compares every
reloaded Room's system with its own row's digest.

Heat pumps: one record per (Building Segment's blended heat pump, served Zone) pair. Each becomes its own
`PhHeatPumpRatedMonthly` under the Segment's identifier, with recirculation cooling when the blend cools, so every
Room of one Segment carries an equal object and PHX keys one device. Its four cooling parameter sets take
identifiers derived from it, so two exports of one Model write equal dictionaries. honeybee-ph reloads heat pumps
sharing an identifier by keeping the last, so each row records its heat pump's digest, as hot water does.

Electric heating: one record per (Electric Heater, served Zone) pair. Each becomes its own `PhHeatingDirectElectric`
under the heater's id, with its Tag, coverage and `user_data`, so every Room one heater serves carries an equal object
and PHX keys one device. A Room holds every heater that serves it. honeybee-ph reloads heating systems sharing an
identifier by keeping the last, so each row records its heater's digest, as hot water does.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import stack
from .contract import JSONValue, RecordError
from .contract.mechanical_records import (
    TANK_SLOTS,
    UNIT_FIELDS,
    ElectricHeaterRecord,
    HeaterValues,
    HeatPumpRecord,
    HotWaterRecord,
    TankValues,
    VentilationRecord,
)
from .model_sections import ZONE_SECTION_ID, TranslatedZone
from .result import Finding
from .sections import ROOM, Attachment, Inputs, Requirement, Section

VENTILATION_SECTION_ID = "ph_composer.mechanical.export.ventilation"
HOT_WATER_SECTION_ID = "ph_composer.mechanical.export.hot_water"
HEAT_PUMP_SECTION_ID = "ph_composer.mechanical.export.heat_pumps"
ELECTRIC_HEATER_SECTION_ID = "ph_composer.mechanical.export.electric_heaters"
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


# -- Hot water ----------------------------------------------------------------

METHOD_NOT_EXPORTED = "mechanical.method_not_exported"
#: The `PhHotWaterSystem` attribute a piping calculation method would be written to, once honeybee-ph carries one
#: (honeybee_ph#135 asks for it; the name is this section's guess, and the pinned class has none). The method counts
#: as written only when the system's dictionary then carries it, so a field under another name, or one `to_dict`
#: leaves out, keeps the finding.
CALC_METHOD_ATTRIBUTE = "piping_calc_method"
#: Each Tank value and the honeybee-ph `PhHvacHotWaterTank` attribute it sets.
TANK_ATTRIBUTES = {
    "tank_type": "tank_type",
    "quantity": "quantity",
    "in_conditioned_space": "in_conditioned_space",
    "solar_connection": "solar_connection",
    "solar_losses_w": "solar_losses",
    "storage_loss_rate_w_k": "storage_loss_rate",
    "storage_capacity_l": "storage_capacity",
    "standby_losses_w_k": "standby_losses",
    "standby_fraction": "standby_fraction",
    "room_temp_c": "room_temp",
    "water_temp_c": "water_temp",
}
#: Each heater variant's honeybee-ph class.
HEATER_CLASSES = {
    "electric": "PhHvacHotWaterHeaterElectric",
    "heat_pump_annual": "PhHvacHotWaterHeaterHeatPump_Annual",
    "heat_pump_monthly": "PhHvacHotWaterHeaterHeatPump_Monthly",
    "heat_pump_inside": "PhHvacHotWaterHeaterHeatPump_Inside",
}
#: Each efficiency value and the heater attribute it sets.
HEATER_ATTRIBUTES = {
    "total_system_perf_ratio": "total_system_perf_ratio",
    "cop_1": "COP_1",
    "ambient_temp_1_c": "ambient_temp_1",
    "cop_2": "COP_2",
    "ambient_temp_2_c": "ambient_temp_2",
    "annual_energy_factor": "annual_energy_factor",
}


@dataclass(frozen=True)
class TranslatedHotWater:
    source: HotWaterRecord
    zone_name: str
    system: Any
    #: Whether the System's piping calculation method was written; False when it is set and the class has no field.
    method_written: bool

    @property
    def zone_id(self) -> str:
        return self.source.zone_id


def hot_water_tank(values: TankValues) -> Any:
    tank = stack.load("honeybee_phhvac.hot_water_devices").PhHvacHotWaterTank()
    tank.identifier, tank.display_name = values.identifier, values.display_name
    for key, attribute in TANK_ATTRIBUTES.items():
        setattr(tank, attribute, getattr(values, key))
    tank.user_data = dict(values.user_data)
    return tank


def hot_water_heater(values: HeaterValues) -> Any:
    devices = stack.load("honeybee_phhvac.hot_water_devices")
    heater = getattr(devices, HEATER_CLASSES[values.variant])()
    heater.identifier, heater.display_name = values.identifier, values.display_name
    heater.percent_coverage, heater.in_conditioned_space = values.percent_coverage, values.in_conditioned_space
    for key, value in values.efficiency.items():
        setattr(heater, HEATER_ATTRIBUTES[key], value)
    heater.user_data = dict(values.user_data)
    return heater


def hot_water_system(record: HotWaterRecord) -> tuple[Any, bool]:
    """The pair's system with fresh tanks and heaters under the records' ids, so every pair of one System builds an
    equal object; and whether its piping calculation method was written."""
    system = stack.load("honeybee_phhvac.hot_water_system").PhHotWaterSystem()
    system.identifier, system.display_name = record.system_identifier, record.display_name
    system.number_tap_points = record.number_tap_points
    for slot in TANK_SLOTS:
        values = record.tanks[slot]
        setattr(system, slot, None if values is None else hot_water_tank(values))
    for heater in record.heaters:
        system.add_heater(hot_water_heater(heater))
    if record.piping_calc_method is None:
        return system, True
    if not hasattr(system, CALC_METHOD_ATTRIBUTE):
        return system, False
    setattr(system, CALC_METHOD_ATTRIBUTE, record.piping_calc_method)
    return system, system.to_dict().get(CALC_METHOD_ATTRIBUTE) == record.piping_calc_method


def digest(system: Any) -> str:
    """The SHA-256 of a honeybee-ph object's dictionary (a hot water system, a heat pump), keys sorted."""
    text = json.dumps(system.to_dict(), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class HotWaterSection(Section[HotWaterRecord, TranslatedHotWater]):
    id = HOT_WATER_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedHotWater
    requires = (ZONES,)
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> HotWaterRecord:
        return HotWaterRecord.read(raw)

    def translate(self, record: HotWaterRecord, inputs: Inputs) -> TranslatedHotWater:
        zone = inputs.get(ZONES, record.zone_id)
        system, written = hot_water_system(record)
        return TranslatedHotWater(record, zone.source.name, system, written)

    def findings(self, objects: Mapping[str, TranslatedHotWater]) -> Sequence[Finding]:
        """A System whose piping calculation method the loaded class cannot take, once per System."""
        unwritten = {item.source.item_id: item.source for item in objects.values() if not item.method_written}
        return [
            Finding(
                METHOD_NOT_EXPORTED,
                self.id,
                item_id,
                f"{record.display_name} sets piping calculation method {record.piping_calc_method}, and the "
                "pinned honeybee-ph has no field for it, so the export leaves it out.",
                False,
            )
            for item_id, record in sorted(unwritten.items())
        ]

    def attach(self, host: Any, objects: Sequence[TranslatedHotWater]) -> None:
        """A Room holds one hot water system, which Ruby's one Hot Water System per Zone makes structural."""
        if len(objects) != 1:
            raise RecordError(f"Room {host.identifier} has more than one hot water system")
        host.properties.ph_hvac.set_hot_water_system(objects[0].system)

    def result_fields(self, objects: Mapping[str, TranslatedHotWater]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [hot_water_row(item) for _identifier, item in sorted(objects.items())]
        return {"hot_water": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported pair's Room holds a hot water system with the row's identifier, tap points, each slot's
        identifier and capacity, its heaters, and the digest its own system had as translated; and no Room holds a
        hot water system the run did not report."""
        rooms = {room.identifier: room for room in model.rooms}
        reported = fields.get("hot_water")
        rows = [item for item in (reported if isinstance(reported, list) else []) if isinstance(item, dict)]
        for item in rows:
            room = rooms.get(str(item.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {item.get('zone_id')} is not in the model")
            system = room.properties.ph_hvac.hot_water_system
            if system is None:
                raise ValueError(f"Room {room.identifier} lost its hot water system")
            found = system_fields(system)
            expected = {key: item.get(key) for key in found}
            if found != expected:
                raise ValueError(f"Room {room.identifier} hot water system is {found}, the run reported {expected}")
        named = {str(item.get("zone_id")) for item in rows}
        if extra := sorted(
            room.identifier
            for room in model.rooms
            if room.properties.ph_hvac.hot_water_system is not None and room.identifier not in named
        ):
            raise ValueError(f"Room {', '.join(extra)} holds a hot water system the run did not report")


def system_fields(system: Any) -> dict[str, JSONValue]:
    """What a row reports of its system and conformance reads back: identifiers, tap points as stored, each slot's
    tank identifier and capacity, the heaters' identifiers in order, and the digest of the whole."""
    values: dict[str, JSONValue] = {
        "system_identifier": system.identifier,
        "number_tap_points": system._number_tap_points,
        "heater_identifiers": sorted(heater.identifier for heater in system.heaters),
    }
    for slot in TANK_SLOTS:
        tank = getattr(system, slot)
        values[f"{slot}_identifier"] = None if tank is None else tank.identifier
        values[f"{slot}_capacity_l"] = None if tank is None else tank.storage_capacity
    values["digest"] = digest(system)
    return values


def hot_water_row(item: TranslatedHotWater) -> dict[str, JSONValue]:
    record = item.source
    return {
        "id": record.id,
        "item_id": record.item_id,
        "zone_id": record.zone_id,
        "zone_name": item.zone_name,
        "display_name": record.display_name,
        **system_fields(item.system),
    }


# -- Heat pumps ---------------------------------------------------------------

#: The `PhHeatPumpCoolingParams` sets, each given an identifier derived from its heat pump's.
COOLING_PARAMS = ("ventilation", "recirculation", "dehumidification", "panel")


@dataclass(frozen=True)
class TranslatedHeatPump:
    source: HeatPumpRecord
    zone_name: str
    heat_pump: Any

    @property
    def zone_id(self) -> str:
        return self.source.zone_id


def heat_pump(record: HeatPumpRecord) -> Any:
    """The pair's rated monthly heat pump with the blend's values, built fresh so every pair of one Segment builds
    an equal object."""
    heat_pump = stack.load("honeybee_phhvac.heat_pumps").PhHeatPumpRatedMonthly()
    heat_pump.identifier, heat_pump.display_name = record.system_identifier, record.display_name
    heat_pump.percent_coverage = record.percent_coverage
    heat_pump.COP_1, heat_pump.ambient_temp_1 = record.cop_1, record.ambient_temp_1_c
    heat_pump.COP_2, heat_pump.ambient_temp_2 = record.cop_2, record.ambient_temp_2_c
    params = heat_pump.cooling_params
    for name in COOLING_PARAMS:
        part = getattr(params, name)
        part.identifier = part.display_name = f"{record.system_identifier}_{name}"
    cooling = record.cooling
    params.percent_coverage = cooling.percent_coverage
    recirculation = params.recirculation
    recirculation.used = cooling.used
    recirculation.capacity = cooling.capacity_kw
    recirculation.flow_rate_m3_hr = cooling.flow_rate_m3_hr
    recirculation.annual_COP = cooling.annual_cop
    recirculation.min_coil_temp = cooling.min_coil_temp_c
    recirculation.single_speed = cooling.single_speed
    recirculation.flow_rate_variable = cooling.flow_rate_variable
    return heat_pump


class HeatPumpSection(Section[HeatPumpRecord, TranslatedHeatPump]):
    id = HEAT_PUMP_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedHeatPump
    requires = (ZONES,)
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> HeatPumpRecord:
        return HeatPumpRecord.read(raw)

    def translate(self, record: HeatPumpRecord, inputs: Inputs) -> TranslatedHeatPump:
        zone = inputs.get(ZONES, record.zone_id)
        return TranslatedHeatPump(record, zone.source.name, heat_pump(record))

    def attach(self, host: Any, objects: Sequence[TranslatedHeatPump]) -> None:
        """A Room holds its Building Segment's one blended heat pump, which Ruby's one blend per Segment makes
        structural."""
        if len(objects) != 1:
            raise RecordError(f"Room {host.identifier} has more than one blended heat pump")
        host.properties.ph_hvac.add_heat_pump_system(objects[0].heat_pump)

    def result_fields(self, objects: Mapping[str, TranslatedHeatPump]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [heat_pump_row(item) for _identifier, item in sorted(objects.items())]
        return {"heat_pumps": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported pair's Room holds one heat pump with the row's identifier, COPs, cooling and the digest its
        own heat pump had as translated; and no Room holds a heat pump the run did not report."""
        rooms = {room.identifier: room for room in model.rooms}
        reported = fields.get("heat_pumps")
        rows = [item for item in (reported if isinstance(reported, list) else []) if isinstance(item, dict)]
        for item in rows:
            room = rooms.get(str(item.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {item.get('zone_id')} is not in the model")
            systems = list(room.properties.ph_hvac.heat_pump_systems)
            if len(systems) != 1:
                raise ValueError(f"Room {room.identifier} holds {len(systems)} heat pumps, the run reported one")
            found = heat_pump_fields(systems[0])
            expected = {key: item.get(key) for key in found}
            if found != expected:
                raise ValueError(f"Room {room.identifier} heat pump is {found}, the run reported {expected}")
        named = {str(item.get("zone_id")) for item in rows}
        if extra := sorted(
            room.identifier
            for room in model.rooms
            if room.properties.ph_hvac.heat_pump_systems and room.identifier not in named
        ):
            raise ValueError(f"Room {', '.join(extra)} holds a heat pump the run did not report")


def heat_pump_fields(heat_pump: Any) -> dict[str, JSONValue]:
    """What a row reports of its heat pump and conformance reads back: its identifier, COPs, recirculation cooling
    and the digest of the whole."""
    recirculation = heat_pump.cooling_params.recirculation
    return {
        "system_identifier": heat_pump.identifier,
        "cop_1": heat_pump.COP_1,
        "cop_2": heat_pump.COP_2,
        "cooling_used": recirculation.used,
        "capacity_kw": recirculation.capacity,
        "flow_rate_m3_hr": recirculation.flow_rate_m3_hr,
        "annual_cop": recirculation.annual_COP,
        "digest": digest(heat_pump),
    }


def heat_pump_row(item: TranslatedHeatPump) -> dict[str, JSONValue]:
    record = item.source
    return {
        "id": record.id,
        "zone_id": record.zone_id,
        "zone_name": item.zone_name,
        "segment": record.segment,
        "display_name": record.display_name,
        **heat_pump_fields(item.heat_pump),
    }


# -- Electric heating ---------------------------------------------------------


@dataclass(frozen=True)
class TranslatedElectricHeater:
    source: ElectricHeaterRecord
    zone_name: str
    heater: Any

    @property
    def zone_id(self) -> str:
        return self.source.zone_id


def electric_heater(record: ElectricHeaterRecord) -> Any:
    """The pair's direct electric heating system, built fresh so every pair of one heater builds an equal object."""
    heater = stack.load("honeybee_phhvac.heating").PhHeatingDirectElectric()
    heater.identifier, heater.display_name = record.identifier, record.display_name
    heater.percent_coverage = record.percent_coverage
    heater.user_data = dict(record.user_data)
    return heater


class ElectricHeaterSection(Section[ElectricHeaterRecord, TranslatedElectricHeater]):
    id = ELECTRIC_HEATER_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedElectricHeater
    requires = (ZONES,)
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> ElectricHeaterRecord:
        return ElectricHeaterRecord.read(raw)

    def translate(self, record: ElectricHeaterRecord, inputs: Inputs) -> TranslatedElectricHeater:
        zone = inputs.get(ZONES, record.zone_id)
        return TranslatedElectricHeater(record, zone.source.name, electric_heater(record))

    def attach(self, host: Any, objects: Sequence[TranslatedElectricHeater]) -> None:
        """A Room holds each heater that serves it, each once, which Ruby's list of heater ids per Zone makes
        structural."""
        identifiers = [item.heater.identifier for item in objects]
        if len(set(identifiers)) != len(identifiers):
            raise RecordError(f"Room {host.identifier} holds one electric heater twice")
        for item in objects:
            host.properties.ph_hvac.add_heating_system(item.heater)

    def result_fields(self, objects: Mapping[str, TranslatedElectricHeater]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [electric_heater_row(item) for _identifier, item in sorted(objects.items())]
        return {"electric_heaters": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported pair's Room holds a heating system with the row's identifier, coverage and the digest its own
        heater had as translated; and no Room holds a heating system the run did not report."""
        rooms = {room.identifier: room for room in model.rooms}
        reported = fields.get("electric_heaters")
        rows = [item for item in (reported if isinstance(reported, list) else []) if isinstance(item, dict)]
        named: dict[str, set[str]] = {}
        for item in rows:
            room = rooms.get(str(item.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {item.get('zone_id')} is not in the model")
            systems = {system.identifier: system for system in room.properties.ph_hvac.heating_systems}
            identifier = str(item.get("identifier"))
            if identifier not in systems:
                raise ValueError(f"Room {room.identifier} lost electric heater {identifier}")
            found = electric_heater_fields(systems[identifier])
            expected = {key: item.get(key) for key in found}
            if found != expected:
                raise ValueError(f"Room {room.identifier} electric heater is {found}, the run reported {expected}")
            named.setdefault(room.identifier, set()).add(identifier)
        if extra := sorted(
            room.identifier
            for room in model.rooms
            if {system.identifier for system in room.properties.ph_hvac.heating_systems}
            - named.get(room.identifier, set())
        ):
            raise ValueError(f"Room {', '.join(extra)} holds a heating system the run did not report")


def electric_heater_fields(heater: Any) -> dict[str, JSONValue]:
    """What a row reports of its heater and conformance reads back: its identifier, coverage and the digest of the
    whole, which carries its type and `user_data`."""
    return {
        "identifier": heater.identifier,
        "percent_coverage": heater.percent_coverage,
        "digest": digest(heater),
    }


def electric_heater_row(item: TranslatedElectricHeater) -> dict[str, JSONValue]:
    record = item.source
    return {
        "id": record.id,
        "item_id": record.item_id,
        "zone_id": record.zone_id,
        "zone_name": item.zone_name,
        "display_name": record.display_name,
        **electric_heater_fields(item.heater),
    }
