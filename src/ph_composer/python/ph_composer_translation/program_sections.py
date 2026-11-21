"""Each exported Zone's Program, occupancy and devices, and each Building Segment's set points (Ruby
`features/programs/program_export.rb`; context/CONTRACTS.md, "Program export").

Ruby has worked out every value: the ScheduleRuleset each Schedule's PH form says, each ProgramType's loads
(a Phius rule Program once per Dwelling, its rule loads over that Dwelling), each Room's People counts and
Dwelling, and each device with its honeybee-ph class and attributes. These sections build the honeybee objects
from the records and compute nothing beyond honeybee's own conversions:

- `ScheduleSection`: one honeybee `ScheduleRuleset` per Schedule, with honeybee-ph's operating days, weeks and,
  on a ventilation Schedule, its four operating periods. Attached nowhere; ProgramTypes take them.
- `ProgramTypeSection`: one honeybee `ProgramType`, with the Phius interior lighting device on a rule Program's
  Lighting. Attached nowhere; Rooms take them.
- `RoomProgramSection`: attached at `ROOM`. The Room takes its ProgramType, its own copy of the People load with
  honeybee-ph's counts and the Dwelling it shares, and a `Process` load per device carrying its `PhEquipment`,
  whose watts are honeybee-ph's annual average from the Dwelling's counts (EnergyPlus only; PHX reads the device).
- `SetPointSection`: attached at `SEGMENT`. The shared `BldgSegment` takes its winter and summer set points.

Every identifier is Ruby's, so the HBJSON is the same each run: honeybee-ph's own defaults would mint a random
`PhDwellings` identifier on every People load, so each one is set.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import stack
from .contract import JSONValue, RecordError, as_number, as_text
from .sections import ROOM, SEGMENT, Attachment, Inputs, Requirement, Section

SCHEDULES_SECTION_ID = "ph_composer.programs.export.schedules"
PROGRAM_TYPES_SECTION_ID = "ph_composer.programs.export.program_types"
ROOMS_SECTION_ID = "ph_composer.programs.export.rooms"
SET_POINTS_SECTION_ID = "ph_composer.programs.export.set_points"
WEEKDAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
TYPE_LIMITS = frozenset({"Fractional", "Activity Level", "Temperature"})
PERIODS = ("high", "standard", "basic", "minimum")
#: honeybee-ph's Set Residential Program files every device's Process under this end use.
END_USE = "HBPH_Process"


def _mapping(value: object, label: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise RecordError(f"{label} must be an object")
    return value


def _rows(value: object, label: str) -> Sequence[Any]:
    if not isinstance(value, list):
        raise RecordError(f"{label} must be a list")
    return value


def _optional(value: object, label: str) -> float | None:
    return None if value is None else as_number(value, label)


def _optional_text(value: object, label: str) -> str | None:
    return None if value is None else as_text(value, label)


def _day(value: object, label: str) -> tuple[float, ...]:
    values = tuple(as_number(item, label) for item in _rows(value, label))
    if len(values) != 24:
        raise RecordError(f"{label} must hold 24 hourly values")
    return values


def _no_dwelling(identifier: str) -> Any:
    """A deterministic `PhDwellings` of no units, which PHX reads as untagged."""
    dwellings = stack.load("honeybee_energy_ph.properties.load.people").PhDwellings(0)
    dwellings.identifier = identifier
    return dwellings


# ---------------------------------------------------------------- Schedules


@dataclass(frozen=True)
class ScheduleRecord:
    id: str
    name: str
    type_limit: str
    operating_day: tuple[float, ...]
    off_day: tuple[float, ...] | None
    operating_weekdays: tuple[str, ...]
    #: Inclusive ((month, day), (month, day)) ranges over which the operating day applies.
    operating_dates: tuple[tuple[tuple[int, int], tuple[int, int]], ...]
    days_per_week: int
    weeks_per_year: int
    #: (name, start hour, end hour, fraction), a ventilation Schedule's four; none otherwise.
    operating_periods: tuple[tuple[str, float, float, float], ...]


@dataclass(frozen=True)
class TranslatedSchedule:
    source: ScheduleRecord
    schedule: Any


def _month_day(value: object, label: str) -> tuple[int, int]:
    pair = _rows(value, label)
    if len(pair) != 2 or not all(isinstance(item, int) and not isinstance(item, bool) for item in pair):
        raise RecordError(f"{label} must be [month, day]")
    return int(pair[0]), int(pair[1])


class ScheduleSection(Section[ScheduleRecord, TranslatedSchedule]):
    id = SCHEDULES_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedSchedule

    def read(self, raw: Mapping[str, object]) -> ScheduleRecord:
        identifier = as_text(raw.get("id"), "schedule id")
        label = f"schedule {identifier}"
        type_limit = raw.get("type_limit")
        if type_limit not in TYPE_LIMITS:
            raise RecordError(f"{label} type_limit must be one of {', '.join(sorted(TYPE_LIMITS))}")
        weekdays = tuple(_rows(raw.get("operating_weekdays"), f"{label} operating_weekdays"))
        if not weekdays or any(day not in WEEKDAYS for day in weekdays):
            raise RecordError(f"{label} operating_weekdays must name weekdays")
        ranges = [_rows(row, f"{label} operating_dates") for row in _rows(raw.get("operating_dates"), label)]
        if not ranges or any(len(row) != 2 for row in ranges):
            raise RecordError(f"{label} operating_dates must be [[month, day], [month, day]] ranges")
        dates = tuple(
            (_month_day(row[0], f"{label} operating_dates"), _month_day(row[1], f"{label} operating_dates"))
            for row in ranges
        )
        periods = tuple(
            (
                as_text(row.get("name"), f"{label} period name"),
                as_number(row.get("start_hour"), f"{label} period start_hour"),
                as_number(row.get("end_hour"), f"{label} period end_hour"),
                as_number(row.get("fraction"), f"{label} period fraction"),
            )
            for row in (_mapping(item, f"{label} period") for item in _rows(raw.get("operating_periods"), label))
        )
        if periods and tuple(period[0] for period in periods) != PERIODS:
            raise RecordError(f"{label} operating periods must be {', '.join(PERIODS)}")
        off_day = raw.get("off_day")
        return ScheduleRecord(
            identifier,
            as_text(raw.get("name"), f"{label} name"),
            str(type_limit),
            _day(raw.get("operating_day"), f"{label} operating_day"),
            None if off_day is None else _day(off_day, f"{label} off_day"),
            weekdays,
            dates,
            int(as_number(raw.get("days_per_week"), f"{label} days_per_week")),
            int(as_number(raw.get("weeks_per_year"), f"{label} weeks_per_year")),
            periods,
        )

    def translate(self, record: ScheduleRecord, inputs: Inputs) -> TranslatedSchedule:
        ruleset_module = stack.load("honeybee_energy.schedule.ruleset")
        day_module = stack.load("honeybee_energy.schedule.day")
        rule_module = stack.load("honeybee_energy.schedule.rule")
        limits = stack.load("honeybee_energy.lib.scheduletypelimits")
        date = stack.load("ladybug.dt").Date
        periods_module = stack.load("honeybee_energy_ph.properties.ruleset")
        try:
            operating = day_module.ScheduleDay.from_values_at_timestep(f"{record.id}_operating", record.operating_day)
            if record.off_day is None:
                ruleset = ruleset_module.ScheduleRuleset(record.id, operating)
            else:
                off = day_module.ScheduleDay.from_values_at_timestep(f"{record.id}_off", record.off_day)
                rules = []
                for start, end in record.operating_dates:
                    rule = rule_module.ScheduleRule(operating, start_date=date(*start), end_date=date(*end))
                    for day in record.operating_weekdays:
                        setattr(rule, f"apply_{day}", True)
                    rules.append(rule)
                ruleset = ruleset_module.ScheduleRuleset(record.id, off, rules)
            ruleset.display_name = record.name
            ruleset.schedule_type_limit = limits.schedule_type_limit_by_identifier(record.type_limit)
            ph = ruleset.properties.ph
            ph.operating_days_wk = record.days_per_week
            ph.operating_weeks_year = record.weeks_per_year
            for name, start, end, fraction in record.operating_periods:
                period = periods_module.DailyOperationPeriod.from_start_end_hours(start, end, fraction, name)
                ph.daily_operating_periods.add_period_to_collection(period)
        except (AssertionError, TypeError, ValueError) as error:
            raise RecordError(f"schedule {record.id} could not be built: {error}") from error
        return TranslatedSchedule(record, ruleset)

    def result_fields(self, objects: Mapping[str, TranslatedSchedule]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [
            {
                "id": item.source.id,
                "days_per_week": item.source.days_per_week,
                "weeks_per_year": item.source.weeks_per_year,
                "period_count": len(item.source.operating_periods),
            }
            for _identifier, item in sorted(objects.items())
        ]
        return {"schedules": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reported Schedule is in the reloaded model with its operating days, weeks and periods."""
        schedules = {schedule.identifier: schedule for schedule in model.properties.energy.schedules}
        rows = fields.get("schedules")
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                raise ValueError("a schedule row is not an object")
            schedule = schedules.get(str(row.get("id")))
            if schedule is None:
                raise ValueError(f"Schedule {row.get('id')} is not in the model")
            ph = schedule.properties.ph
            if ph.operating_days_wk != row.get("days_per_week") or ph.operating_weeks_year != row.get("weeks_per_year"):
                raise ValueError(f"Schedule {schedule.identifier} lost its operating days or weeks")
            if len(list(ph.daily_operating_periods)) != row.get("period_count"):
                raise ValueError(f"Schedule {schedule.identifier} lost its operating periods")


SCHEDULES = Requirement(SCHEDULES_SECTION_ID, TranslatedSchedule)


# ---------------------------------------------------------------- ProgramTypes


@dataclass(frozen=True)
class DeviceRecord:
    identifier: str
    #: The honeybee-ph class, and each attribute it sets on a new instance by honeybee-ph's names and values.
    hbph_class: str
    attributes: tuple[tuple[str, JSONValue], ...]


def _device(raw: object, label: str) -> DeviceRecord:
    row = _mapping(raw, label)
    attributes = _mapping(row.get("attributes"), f"{label} attributes")
    return DeviceRecord(
        as_text(row.get("identifier"), f"{label} identifier"),
        as_text(row.get("class"), f"{label} class"),
        tuple(sorted(attributes.items())),
    )


def _equipment(record: DeviceRecord) -> Any:
    """The device's `PhEquipment`: a new instance of its class with each attribute set."""
    module = stack.load("honeybee_energy_ph.load.ph_equipment")
    cls = getattr(module, record.hbph_class, None)
    if not isinstance(cls, type) or not issubclass(cls, module.PhEquipment):
        raise RecordError(f"device {record.identifier} names an unknown honeybee-ph class {record.hbph_class}")
    equipment = cls()
    for name, value in record.attributes:
        if not hasattr(equipment, name):
            raise RecordError(f"device {record.identifier} {record.hbph_class} has no attribute {name}")
        setattr(equipment, name, value)
    equipment.identifier = record.identifier
    return equipment


@dataclass(frozen=True)
class ProgramTypeRecord:
    id: str
    name: str
    loads: Mapping[str, Mapping[str, Any]]
    lighting_device: DeviceRecord | None


@dataclass(frozen=True)
class TranslatedProgramType:
    source: ProgramTypeRecord
    program_type: Any


LOADS = (
    "people",
    "lighting",
    "electric_equipment",
    "gas_equipment",
    "service_hot_water",
    "infiltration",
    "ventilation",
    "setpoint",
)


class ProgramTypeSection(Section[ProgramTypeRecord, TranslatedProgramType]):
    id = PROGRAM_TYPES_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedProgramType
    requires = (SCHEDULES,)

    def read(self, raw: Mapping[str, object]) -> ProgramTypeRecord:
        identifier = as_text(raw.get("id"), "program type id")
        label = f"program type {identifier}"
        loads = {load: dict(_mapping(raw.get(load), f"{label} {load}")) for load in LOADS}
        device = loads["lighting"].pop("device", None)
        return ProgramTypeRecord(
            identifier,
            as_text(raw.get("name"), f"{label} name"),
            loads,
            None if device is None else _device(device, f"{label} lighting device"),
        )

    def translate(self, record: ProgramTypeRecord, inputs: Inputs) -> TranslatedProgramType:
        energy = "honeybee_energy.load."
        people_module = stack.load(f"{energy}people")
        lighting_module = stack.load(f"{energy}lighting")
        equipment_module = stack.load(f"{energy}equipment")
        hot_water = stack.load(f"{energy}hotwater").ServiceHotWater
        infiltration = stack.load(f"{energy}infiltration").Infiltration
        ventilation = stack.load(f"{energy}ventilation").Ventilation
        setpoint = stack.load(f"{energy}setpoint").Setpoint
        program_module = stack.load("honeybee_energy.programtype")
        autocalculate = stack.load("honeybee.altnumber").autocalculate
        label = f"program type {record.id}"

        def schedule(load: Mapping[str, Any], key: str = "schedule_id") -> Any:
            identifier = _optional_text(load.get(key), f"{label} {key}")
            return None if identifier is None else inputs.get(SCHEDULES, identifier).schedule

        def number(load: Mapping[str, Any], key: str) -> float:
            return as_number(load.get(key), f"{label} {key}")

        loads = record.loads
        try:
            people_load = loads["people"]
            latent = _optional(people_load.get("latent_fraction"), f"{label} latent_fraction")
            people = people_module.People(
                f"{record.id}_people",
                number(people_load, "people_per_area"),
                schedule(people_load, "occupancy_schedule_id"),
                schedule(people_load, "activity_schedule_id"),
                number(people_load, "radiant_fraction"),
                autocalculate if latent is None else latent,
            )
            people.properties.ph.dwellings = _no_dwelling(f"{record.id}_people")
            light = loads["lighting"]
            lighting = lighting_module.Lighting(
                f"{record.id}_lighting",
                number(light, "watts_per_area"),
                schedule(light),
                number(light, "return_air_fraction"),
                number(light, "radiant_fraction"),
                number(light, "visible_fraction"),
            )
            if record.lighting_device is not None:
                lighting.properties.ph.ph_equipment = _equipment(record.lighting_device)
            electric, gas = (
                cls(
                    f"{record.id}_{key}",
                    number(loads[key], "watts_per_area"),
                    schedule(loads[key]),
                    number(loads[key], "radiant_fraction"),
                    number(loads[key], "latent_fraction"),
                    number(loads[key], "lost_fraction"),
                )
                for cls, key in (
                    (equipment_module.ElectricEquipment, "electric_equipment"),
                    (equipment_module.GasEquipment, "gas_equipment"),
                )
            )
            water = loads["service_hot_water"]
            service_hot_water = hot_water(
                f"{record.id}_service_hot_water",
                number(water, "flow_per_area"),
                schedule(water),
                number(water, "target_temperature_c"),
                number(water, "sensible_fraction"),
                number(water, "latent_fraction"),
            )
            leakage = loads["infiltration"]
            air = loads["ventilation"]
            outdoor_air = ventilation(
                f"{record.id}_ventilation",
                number(air, "flow_per_person"),
                number(air, "flow_per_area"),
                number(air, "flow_per_zone"),
                number(air, "air_changes_per_hour"),
                schedule(air),
            )
            points = loads["setpoint"]
            thermostat = setpoint(
                f"{record.id}_setpoint",
                schedule(points, "heating_schedule_id"),
                schedule(points, "cooling_schedule_id"),
            )
            dehumidify = _optional(points.get("dehumidify_rh"), f"{label} dehumidify_rh")
            humidify = _optional(points.get("humidify_rh"), f"{label} humidify_rh")
            if dehumidify is not None:
                thermostat.dehumidifying_setpoint = dehumidify
            if humidify is not None:
                thermostat.humidifying_setpoint = humidify
            program = program_module.ProgramType(
                record.id,
                people,
                lighting,
                electric,
                gas,
                service_hot_water,
                infiltration(
                    f"{record.id}_infiltration",
                    number(leakage, "flow_per_exterior_area"),
                    schedule(leakage),
                ),
                outdoor_air,
                thermostat,
            )
            program.display_name = record.name
        except (AssertionError, TypeError, ValueError) as error:
            raise RecordError(f"{label} could not be built: {error}") from error
        return TranslatedProgramType(record, program)

    def result_fields(self, objects: Mapping[str, TranslatedProgramType]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [
            {
                "id": item.source.id,
                "people_per_area": item.program_type.people.people_per_area,
                "lighting_watts_per_area": item.program_type.lighting.watts_per_area,
            }
            for _identifier, item in sorted(objects.items())
        ]
        return {"program_types": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reported ProgramType is in the reloaded model with its people and lighting per area."""
        programs = {program.identifier: program for program in model.properties.energy.program_types}
        rows = fields.get("program_types")
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                raise ValueError("a program type row is not an object")
            program = programs.get(str(row.get("id")))
            if program is None:
                raise ValueError(f"ProgramType {row.get('id')} is not in the model")
            for actual, key in (
                (program.people.people_per_area, "people_per_area"),
                (program.lighting.watts_per_area, "lighting_watts_per_area"),
            ):
                expected = row.get(key)
                if not isinstance(expected, (int, float)) or abs(actual - expected) > 1e-9:
                    raise ValueError(f"ProgramType {program.identifier} {key} is {actual}, not {expected}")


PROGRAM_TYPES = Requirement(PROGRAM_TYPES_SECTION_ID, TranslatedProgramType)


# ---------------------------------------------------------------- Rooms


@dataclass(frozen=True)
class RoomDevice:
    device: DeviceRecord
    process_id: str
    occupants: float
    bedrooms: float
    floor_area_ft2: float


@dataclass(frozen=True)
class RoomRecord:
    zone_id: str
    program_type_id: str
    number_bedrooms: float
    number_people: float
    #: The Dwelling's identifier and units, or None for a Zone in no Dwelling.
    dwelling: tuple[str, int] | None
    devices: tuple[RoomDevice, ...]


@dataclass(frozen=True)
class TranslatedRoom:
    source: RoomRecord
    program_type: Any
    people: Any
    processes: tuple[Any, ...]


class RoomProgramSection(Section[RoomRecord, TranslatedRoom]):
    id = ROOMS_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedRoom
    requires = (PROGRAM_TYPES,)
    attaches = Attachment(ROOM, lambda item: item.source.zone_id)

    def read(self, raw: Mapping[str, object]) -> RoomRecord:
        zone_id = as_text(raw.get("id"), "room id")
        label = f"room {zone_id}"
        dwelling = raw.get("dwelling")
        pair = None
        if dwelling is not None:
            row = _mapping(dwelling, f"{label} dwelling")
            units = as_number(row.get("num_dwellings"), f"{label} num_dwellings")
            if units < 1 or units != int(units):
                raise RecordError(f"{label} num_dwellings must be a whole number of at least 1")
            pair = (as_text(row.get("identifier"), f"{label} dwelling identifier"), int(units))
        devices = []
        for item in _rows(raw.get("devices"), f"{label} devices"):
            row = _mapping(item, f"{label} device")
            devices.append(
                RoomDevice(
                    _device(row, f"{label} device"),
                    as_text(row.get("process_id"), f"{label} process_id"),
                    as_number(row.get("occupants"), f"{label} device occupants"),
                    as_number(row.get("bedrooms"), f"{label} device bedrooms"),
                    as_number(row.get("floor_area_ft2"), f"{label} device floor_area_ft2"),
                )
            )
        return RoomRecord(
            zone_id,
            as_text(raw.get("program_type_id"), f"{label} program_type_id"),
            as_number(raw.get("number_bedrooms"), f"{label} number_bedrooms"),
            as_number(raw.get("number_people"), f"{label} number_people"),
            pair,
            tuple(devices),
        )

    def translate(self, record: RoomRecord, inputs: Inputs) -> TranslatedRoom:
        program = inputs.get(PROGRAM_TYPES, record.program_type_id).program_type
        process_module = stack.load("honeybee_energy.load.process")
        always_on = stack.load("honeybee_energy.lib.schedules").always_on
        people_module = stack.load("honeybee_energy_ph.properties.load.people")
        try:
            people = program.people.duplicate()
            people.identifier = f"{record.zone_id}_people"
            ph = people.properties.ph
            # As entered: a count may be fractional, and PHX makes its own whole number of each Room's.
            ph.number_bedrooms = record.number_bedrooms
            ph.number_people = record.number_people
            if record.dwelling is None:
                ph.dwellings = _no_dwelling(f"{record.zone_id}_people")
            else:
                ph.dwellings = people_module.PhDwellings(record.dwelling[1])
                ph.dwellings.identifier = record.dwelling[0]
            processes = []
            for item in record.devices:
                equipment = _equipment(item.device)
                watts = equipment.annual_avg_wattage(
                    None,
                    _num_occupants=item.occupants,
                    _num_bedrooms=item.bedrooms,
                    _floor_area_ft2=item.floor_area_ft2,
                )
                process = process_module.Process(item.process_id, watts, always_on, "Electricity", END_USE, 0, 0, 0)
                process.display_name = equipment.display_name
                process.properties.ph.ph_equipment = equipment
                processes.append(process)
        except (AssertionError, TypeError, ValueError, ZeroDivisionError) as error:
            raise RecordError(f"room {record.zone_id} program could not be built: {error}") from error
        return TranslatedRoom(record, program, people, tuple(processes))

    def attach(self, host: Any, objects: Sequence[TranslatedRoom]) -> None:
        """Sets the Room's ProgramType, its own People, and its devices' Process loads."""
        if len(objects) != 1:
            raise RecordError(f"Room {host.identifier} has more than one program record")
        room = objects[0]
        energy = host.properties.energy
        energy.program_type = room.program_type
        energy.people = room.people
        for process in room.processes:
            energy.add_process_load(process)

    def result_fields(self, objects: Mapping[str, TranslatedRoom]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [
            {
                "zone_id": item.source.zone_id,
                "program_type_id": item.source.program_type_id,
                "number_bedrooms": item.source.number_bedrooms,
                "number_people": item.source.number_people,
                "dwelling_identifier": None if item.source.dwelling is None else item.source.dwelling[0],
                "num_dwellings": 0 if item.source.dwelling is None else item.source.dwelling[1],
                "device_count": len(item.processes),
            }
            for _identifier, item in sorted(objects.items())
        ]
        return {"rooms": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reported Room is in the reloaded model with its ProgramType, its People counts and Dwelling, and
        its devices."""
        rooms = {room.identifier: room for room in model.rooms}
        rows = fields.get("rooms")
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                raise ValueError("a room row is not an object")
            room = rooms.get(str(row.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {row.get('zone_id')} is not in the model")
            energy = room.properties.energy
            if energy.program_type.identifier != row.get("program_type_id"):
                raise ValueError(f"Room {room.identifier} lost its ProgramType")
            ph = energy.people.properties.ph
            if ph.number_bedrooms != row.get("number_bedrooms") or ph.number_people != row.get("number_people"):
                raise ValueError(f"Room {room.identifier} lost its People counts")
            if row.get("dwelling_identifier") is not None and (
                ph.dwellings.identifier != row.get("dwelling_identifier")
                or ph.dwellings.num_dwellings != row.get("num_dwellings")
            ):
                raise ValueError(f"Room {room.identifier} lost its Dwelling")
            devices = [load for load in energy.process_loads if load.properties.ph.ph_equipment is not None]
            if len(devices) != row.get("device_count"):
                raise ValueError(f"Room {room.identifier} has {len(devices)} devices, not {row.get('device_count')}")


# ---------------------------------------------------------------- Building Segments


@dataclass(frozen=True)
class SetPointRecord:
    id: str
    export_identifier: str
    name: str
    winter_c: float
    summer_c: float
    #: (name, units, bedrooms or None, occupants or None) per Dwelling, for the report.
    dwellings: tuple[tuple[str, int, float | None, float | None], ...]


class SetPointSection(Section[SetPointRecord, SetPointRecord]):
    id = SET_POINTS_SECTION_ID
    versions = frozenset({1})
    object_type = SetPointRecord
    attaches = Attachment(SEGMENT, lambda item: item.export_identifier)

    def read(self, raw: Mapping[str, object]) -> SetPointRecord:
        identifier = as_text(raw.get("id"), "set points id")
        label = f"set points {identifier}"
        dwellings = []
        for item in _rows(raw.get("dwellings"), f"{label} dwellings"):
            row = _mapping(item, f"{label} dwelling")
            dwellings.append(
                (
                    as_text(row.get("name"), f"{label} dwelling name"),
                    int(as_number(row.get("units"), f"{label} dwelling units")),
                    _optional(row.get("bedrooms"), f"{label} dwelling bedrooms"),
                    _optional(row.get("occupants"), f"{label} dwelling occupants"),
                )
            )
        return SetPointRecord(
            identifier,
            as_text(raw.get("export_identifier"), f"{label} export_identifier"),
            as_text(raw.get("name"), f"{label} name"),
            as_number(raw.get("winter_c"), f"{label} winter_c"),
            as_number(raw.get("summer_c"), f"{label} summer_c"),
            tuple(dwellings),
        )

    def translate(self, record: SetPointRecord, inputs: Inputs) -> SetPointRecord:
        return record

    def attach(self, host: Any, objects: Sequence[SetPointRecord]) -> None:
        """Sets the winter and summer set points of the one `BldgSegment` the Segment's Rooms share."""
        if len(objects) != 1:
            raise RecordError(f"Building Segment {host.identifier} has more than one set points record")
        host.set_points.winter = objects[0].winter_c
        host.set_points.summer = objects[0].summer_c

    def result_fields(self, objects: Mapping[str, SetPointRecord]) -> Mapping[str, JSONValue]:
        items = [item for _identifier, item in sorted(objects.items())]
        points: list[JSONValue] = [
            {
                "export_identifier": item.export_identifier,
                "name": item.name,
                "winter_c": item.winter_c,
                "summer_c": item.summer_c,
            }
            for item in items
        ]
        dwellings: list[JSONValue] = [
            {
                "export_identifier": item.export_identifier,
                "name": name,
                "units": units,
                "bedrooms": bedrooms,
                "occupants": occupants,
            }
            for item in items
            for name, units, bedrooms, occupants in item.dwellings
        ]
        return {"set_points": points, "dwellings": dwellings}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reported Building Segment is in the reloaded model with its set points."""
        segments = {
            room.properties.ph.ph_bldg_segment.identifier: room.properties.ph.ph_bldg_segment for room in model.rooms
        }
        rows = fields.get("set_points")
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                raise ValueError("a set points row is not an object")
            segment = segments.get(str(row.get("export_identifier")))
            if segment is None:
                raise ValueError(f"Building Segment {row.get('export_identifier')} is not in the model")
            if segment.set_points.winter != row.get("winter_c") or segment.set_points.summer != row.get("summer_c"):
                raise ValueError(f"Building Segment {segment.identifier} lost its set points")
