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

Pumps: one record per (Pump, served Zone) pair. Each becomes its own `PhSupportiveDevice` under the pump's id, with
its Tag, values and `user_data`, so every Room one pump serves carries an equal object and PHX keys one device. A
Room holds every pump that serves it. honeybee-ph reloads supportive devices sharing an identifier by keeping the
last, so each row records its pump's digest. PHX reads supportive devices through a Room's Spaces; Ruby notes a
served Zone with none.

Fans: one record per (Fan, served Zone) pair. Each becomes its own exhaust ventilator of the fan's type under the
fan's id, with its Tag, values and `user_data`, and, when the fan has Power, a linked type 10 `PhSupportiveDevice`
under the same id: one Fan record, two honeybee-ph objects. honeybee-ph and PHX keep the two in separate collections,
each keyed by identifier, so they never collide, and every Room one fan serves carries equal objects. Each row records
both digests. PHX reads both through a Room's Spaces; Ruby notes a served Zone with none.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import stack
from .contract import JSONValue, RecordError
from .contract.mechanical_records import (
    EXHAUST_CLASSES,
    TANK_SLOTS,
    UNIT_FIELDS,
    ElectricHeaterRecord,
    FanRecord,
    HeaterValues,
    HeatPumpRecord,
    HotWaterRecord,
    PumpRecord,
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
PUMP_SECTION_ID = "ph_composer.mechanical.export.pumps"
#: A Pump's record id, which its supportive device carries: a Room's other supportive devices (a Fan's) belong to
#: other sections.
PUMP_ID = re.compile(r"pmp_[A-Za-z0-9]{12}")
FAN_SECTION_ID = "ph_composer.mechanical.export.fans"
#: A Fan's record id, which its exhaust ventilator and supportive device carry: a Room's other supportive devices (a
#: Pump's) belong to other sections.
FAN_ID = re.compile(r"fan_[A-Za-z0-9]{12}")
#: The honeybee-ph heating type this section writes; a Room's other heating systems belong to other sections.
DIRECT_ELECTRIC = "PhHeatingDirectElectric"
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
    heater = getattr(stack.load("honeybee_phhvac.heating"), DIRECT_ELECTRIC)()
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
        heater had as translated; and no Room holds a direct electric heating system the run did not report. Another
        section's heating systems (a boiler) are not this section's to check."""
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
            if {
                system.identifier
                for system in room.properties.ph_hvac.heating_systems
                if system.heating_type == DIRECT_ELECTRIC
            }
            - named.get(room.identifier, set())
        ):
            raise ValueError(f"Room {', '.join(extra)} holds an electric heater the run did not report")


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


# -- Pumps --------------------------------------------------------------------


@dataclass(frozen=True)
class TranslatedPump:
    source: PumpRecord
    zone_name: str
    device: Any

    @property
    def zone_id(self) -> str:
        return self.source.zone_id


def pump(record: PumpRecord) -> Any:
    """The pair's supportive device, built fresh so every pair of one pump builds an equal object. honeybee-ph's
    `device_type` setter re-seeds the usage profile, so the profile Ruby resolved is set after it."""
    device = stack.load("honeybee_phhvac.supportive_device").PhSupportiveDevice()
    device.identifier, device.display_name = record.identifier, record.display_name
    device.device_type = record.device_type
    device.quantity = record.quantity
    device.in_conditioned_space = record.in_conditioned_space
    device.norm_energy_demand_W = record.norm_energy_demand_w
    device.annual_period_operation_khrs = record.annual_period_operation_khrs
    device.ihg_utilization_factor = record.ihg_utilization_factor
    device.ihg_usage_profile = record.ihg_usage_profile
    device.user_data = dict(record.user_data)
    return device


class PumpSection(Section[PumpRecord, TranslatedPump]):
    id = PUMP_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedPump
    requires = (ZONES,)
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> PumpRecord:
        return PumpRecord.read(raw)

    def translate(self, record: PumpRecord, inputs: Inputs) -> TranslatedPump:
        zone = inputs.get(ZONES, record.zone_id)
        return TranslatedPump(record, zone.source.name, pump(record))

    def attach(self, host: Any, objects: Sequence[TranslatedPump]) -> None:
        """A Room holds each pump that serves it, each once, which Ruby's list of pump ids per Zone makes
        structural."""
        identifiers = [item.device.identifier for item in objects]
        if len(set(identifiers)) != len(identifiers):
            raise RecordError(f"Room {host.identifier} holds one pump twice")
        for item in objects:
            host.properties.ph_hvac.add_supportive_device(item.device)

    def result_fields(self, objects: Mapping[str, TranslatedPump]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [pump_row(item) for _identifier, item in sorted(objects.items())]
        return {"pumps": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported pair's Room holds a supportive device with the row's identifier, values and the digest its
        own pump had as translated; and no Room holds a Pump's device the run did not report. Supportive devices of
        other sections (a Fan's) are not this section's to check."""
        rooms = {room.identifier: room for room in model.rooms}
        reported = fields.get("pumps")
        rows = [item for item in (reported if isinstance(reported, list) else []) if isinstance(item, dict)]
        named: dict[str, set[str]] = {}
        for item in rows:
            room = rooms.get(str(item.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {item.get('zone_id')} is not in the model")
            devices = {device.identifier: device for device in room.properties.ph_hvac.supportive_devices}
            identifier = str(item.get("identifier"))
            if identifier not in devices:
                raise ValueError(f"Room {room.identifier} lost pump {identifier}")
            found = pump_fields(devices[identifier])
            expected = {key: item.get(key) for key in found}
            if found != expected:
                raise ValueError(f"Room {room.identifier} pump is {found}, the run reported {expected}")
            named.setdefault(room.identifier, set()).add(identifier)
        if extra := sorted(
            room.identifier
            for room in model.rooms
            if {
                device.identifier
                for device in room.properties.ph_hvac.supportive_devices
                if PUMP_ID.fullmatch(device.identifier)
            }
            - named.get(room.identifier, set())
        ):
            raise ValueError(f"Room {', '.join(extra)} holds a pump the run did not report")


def pump_fields(device: Any) -> dict[str, JSONValue]:
    """What a row reports of its pump and conformance reads back: its identifier and values under the record's names,
    and the digest of the whole, which carries its name and `user_data`."""
    return {
        "identifier": device.identifier,
        "device_type": device.device_type,
        "quantity": device.quantity,
        "in_conditioned_space": device.in_conditioned_space,
        "norm_energy_demand_w": device.norm_energy_demand_W,
        "annual_period_operation_khrs": device.annual_period_operation_khrs,
        "ihg_utilization_factor": device.ihg_utilization_factor,
        "ihg_usage_profile": device.ihg_usage_profile,
        "digest": digest(device),
    }


def pump_row(item: TranslatedPump) -> dict[str, JSONValue]:
    record = item.source
    return {
        "id": record.id,
        "item_id": record.item_id,
        "zone_id": record.zone_id,
        "zone_name": item.zone_name,
        "display_name": record.display_name,
        **pump_fields(item.device),
    }


# -- Fans ---------------------------------------------------------------------

#: Seconds in an hour: a Fan stores its flow in m³/h and honeybee-ph's exhaust ventilator holds m³/s.
SECONDS_PER_HOUR = 3600.0


@dataclass(frozen=True)
class TranslatedFan:
    source: FanRecord
    zone_name: str
    exhaust: Any
    device: Any | None

    @property
    def zone_id(self) -> str:
        return self.source.zone_id


def fan_exhaust(record: FanRecord) -> Any:
    """The pair's exhaust ventilator, of the class its type names, built fresh so every pair of one fan builds an
    equal object."""
    ventilation = stack.load("honeybee_phhvac.ventilation")
    exhaust = getattr(ventilation, EXHAUST_CLASSES[record.exhaust_type])()
    exhaust.identifier, exhaust.display_name = record.identifier, record.display_name
    exhaust.quantity = record.quantity
    exhaust.exhaust_flow_rate_m3s = record.exhaust_flow_rate_m3h / SECONDS_PER_HOUR
    exhaust.annual_runtime_minutes = record.annual_runtime_minutes
    exhaust.user_data = dict(record.user_data)
    return exhaust


def fan_device(record: FanRecord) -> Any | None:
    """The pair's linked supportive device, type 10 under the fan's identifier, when the fan has Power; its
    utilization factor and usage profile stay at the class's (1.0, all year)."""
    if record.norm_energy_demand_w is None:
        return None
    device = stack.load("honeybee_phhvac.supportive_device").PhSupportiveDevice()
    device.identifier, device.display_name = record.identifier, record.display_name
    device.device_type = 10
    device.quantity = record.quantity
    device.in_conditioned_space = record.in_conditioned_space
    device.norm_energy_demand_W = record.norm_energy_demand_w
    device.annual_period_operation_khrs = record.annual_period_operation_khrs
    device.user_data = dict(record.user_data)
    return device


class FanSection(Section[FanRecord, TranslatedFan]):
    id = FAN_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedFan
    requires = (ZONES,)
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> FanRecord:
        return FanRecord.read(raw)

    def translate(self, record: FanRecord, inputs: Inputs) -> TranslatedFan:
        zone = inputs.get(ZONES, record.zone_id)
        return TranslatedFan(record, zone.source.name, fan_exhaust(record), fan_device(record))

    def attach(self, host: Any, objects: Sequence[TranslatedFan]) -> None:
        """A Room holds each fan that serves it, each once, which Ruby's list of fan ids per Zone makes structural:
        its exhaust ventilator and, with Power, its supportive device."""
        identifiers = [item.exhaust.identifier for item in objects]
        if len(set(identifiers)) != len(identifiers):
            raise RecordError(f"Room {host.identifier} holds one fan twice")
        hvac = host.properties.ph_hvac
        for item in objects:
            hvac.add_exhaust_vent_device(item.exhaust)
            if item.device is not None:
                hvac.add_supportive_device(item.device)

    def result_fields(self, objects: Mapping[str, TranslatedFan]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [fan_row(item) for _identifier, item in sorted(objects.items())]
        return {"fans": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported pair's Room holds an exhaust ventilator with the row's identifier, values and the digest its
        own fan had as translated, and a supportive device under that identifier exactly when the row has Power, with
        its values and digest; and no Room holds a Fan's exhaust ventilator or supportive device the run did not
        report. Other sections' supportive devices (a Pump's) are not this section's to check."""
        rooms = {room.identifier: room for room in model.rooms}
        reported = fields.get("fans")
        rows = [item for item in (reported if isinstance(reported, list) else []) if isinstance(item, dict)]
        exhausts: dict[str, set[str]] = {}
        devices: dict[str, set[str]] = {}
        for item in rows:
            room = rooms.get(str(item.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {item.get('zone_id')} is not in the model")
            hvac = room.properties.ph_hvac
            identifier = str(item.get("identifier"))
            held = {exhaust.identifier: exhaust for exhaust in hvac.exhaust_vent_devices}
            if identifier not in held:
                raise ValueError(f"Room {room.identifier} lost fan {identifier}")
            supportive = {device.identifier: device for device in hvac.supportive_devices}.get(identifier)
            found = fan_fields(held[identifier], supportive)
            expected = {key: item.get(key) for key in found}
            if found != expected:
                raise ValueError(f"Room {room.identifier} fan is {found}, the run reported {expected}")
            exhausts.setdefault(room.identifier, set()).add(identifier)
            if supportive is not None:
                devices.setdefault(room.identifier, set()).add(identifier)
        if extra := sorted(
            room.identifier
            for room in model.rooms
            if fan_ids(room.properties.ph_hvac.exhaust_vent_devices) - exhausts.get(room.identifier, set())
            or fan_ids(room.properties.ph_hvac.supportive_devices) - devices.get(room.identifier, set())
        ):
            raise ValueError(f"Room {', '.join(extra)} holds a fan the run did not report")


def fan_ids(objects: Any) -> set[str]:
    return {item.identifier for item in objects if FAN_ID.fullmatch(item.identifier)}


def fan_fields(exhaust: Any, device: Any | None) -> dict[str, JSONValue]:
    """What a row reports of its fan and conformance reads back: its identifier, its exhaust ventilator's values under
    the record's names (the flow in m³/s, as honeybee-ph holds it), its supportive device's (null without Power), and
    the digest of each whole, which carries its name and `user_data`."""
    exhaust_type = {name: key for key, name in EXHAUST_CLASSES.items()}.get(exhaust.device_class_name)
    return {
        "identifier": exhaust.identifier,
        "exhaust_type": exhaust_type,
        "quantity": exhaust.quantity,
        "exhaust_flow_rate_m3s": exhaust.exhaust_flow_rate_m3s,
        "annual_runtime_minutes": exhaust.annual_runtime_minutes,
        "norm_energy_demand_w": None if device is None else device.norm_energy_demand_W,
        "in_conditioned_space": None if device is None else device.in_conditioned_space,
        "annual_period_operation_khrs": None if device is None else device.annual_period_operation_khrs,
        "digest": digest(exhaust),
        "supportive_device_digest": None if device is None else digest(device),
    }


def fan_row(item: TranslatedFan) -> dict[str, JSONValue]:
    record = item.source
    return {
        "id": record.id,
        "item_id": record.item_id,
        "zone_id": record.zone_id,
        "zone_name": item.zone_name,
        "display_name": record.display_name,
        **fan_fields(item.exhaust, item.device),
    }
