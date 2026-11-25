"""ERV ducting, translated through the pinned honeybee-ph stack and appended to the ventilation systems it belongs to
(Ruby `features/ducting/export.rb`; context/CONTRACTS.md, "Translation sections and artifacts").

One record per Ventilator with ducts. The section requires the ventilation section and, in `translate`, appends the
Ventilator's supply and exhaust `PhDuctElement`s to every `PhVentilationSystem` that section built for it, one per
served Zone, before the assembly attaches them to their Rooms. Like the piping section it adds to another section's
required objects, so it attaches nothing of its own (`attaches = None`). Each ventilation object gets its own freshly
built ducts from the same record, never an instance shared between Rooms: honeybee-ph reloads two Rooms' systems that
share an identifier only when their dictionaries are equal, and refuses them otherwise.

Everything is built for every ventilation object before any is appended to, so a record that cannot be built leaves
every system as it was. The section is required for export: a record that fails would leave one Ventilator's Rooms
unequal.

A system writes its supply and exhaust elements as lists, in the order appended, and each element's segments as a map
keyed by identifier, which the canonical HBJSON writes with its keys sorted. Elements and segments are appended in
identifier order, so the system as translated equals the system as reloaded."""

from __future__ import annotations

import copy
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import stack
from .conformance import result_rows, same_length
from .contract import JSONValue, RecordError
from .contract.ducting_records import EXHAUST, SUPPLY, DuctElementValues, DuctingRecord, DuctSegmentValues
from .mechanical_sections import VENTILATION_SECTION_ID, TranslatedVentilation
from .sections import Inputs, Requirement, Section

DUCTING_SECTION_ID = "ph_composer.ducting.export.ducting"
VENTILATION = Requirement(VENTILATION_SECTION_ID, TranslatedVentilation)
#: Each `duct_type` and the `PhVentilationSystem` list holding it.
LISTS = {SUPPLY: "supply_ducting", EXHAUST: "exhaust_ducting"}
#: The size and insulation fields a result row carries, as `PhDuctSegment` names them.
SIZES = {
    "diameter_m": "diameter",
    "width_m": "width",
    "height_m": "height",
    "insulation_thickness_m": "insulation_thickness",
    "insulation_conductivity": "insulation_conductivity",
    "insulation_reflective": "insulation_reflective",
}


@dataclass(frozen=True)
class TranslatedDucting:
    source: DuctingRecord
    #: The ventilation systems the record's ducts were appended to, one per (Ventilator, served Zone) pair; none when
    #: no exported Zone takes the Ventilator, which Ruby has already noted.
    systems: tuple[Any, ...]


def segment(values: DuctSegmentValues) -> Any:
    ducting = stack.load("honeybee_phhvac.ducting")
    pointvector = stack.load("ladybug_geometry.geometry3d.pointvector")
    polyline = stack.load("ladybug_geometry.geometry3d.polyline")
    geometry = polyline.LineSegment3D.from_end_points(
        pointvector.Point3D(*values.start), pointvector.Point3D(*values.end)
    )
    built = ducting.PhDuctSegment(
        geometry,
        _insul_thickness=values.insulation_thickness_m,
        _insul_conductivity=values.insulation_conductivity,
        _insul_refl=values.insulation_reflective,
        _diameter=values.diameter_m,
        _height=values.height_m,
        _width=values.width_m,
    )
    built.identifier, built.display_name = values.identifier, values.display_name
    built.user_data = copy.deepcopy(values.user_data)
    return built


def element(values: DuctElementValues) -> Any:
    """A run's `PhDuctElement`, its segments in identifier order."""
    built = stack.load("honeybee_phhvac.ducting").PhDuctElement(values.display_name, values.duct_type)
    built.identifier = values.identifier
    for part in sorted(values.segments, key=lambda item: item.identifier):
        built.add_segment(segment(part))
    return built


def ducts(record: DuctingRecord) -> tuple[list[Any], list[Any]]:
    """The record's supply and exhaust elements, freshly built, each list in identifier order. `add_segment` raises a
    bare `Exception` for round and rectangular segments in one element, which `DuctElementValues.read` refuses first."""
    try:
        supply = [element(part) for part in sorted(record.supply, key=lambda item: item.identifier)]
        exhaust = [element(part) for part in sorted(record.exhaust, key=lambda item: item.identifier)]
    except (ArithmeticError, AssertionError, TypeError, ValueError) as error:
        raise RecordError(f"ducting {record.id} could not be built: {error}") from error
    return supply, exhaust


def add_ducts(system: Any, supply: Sequence[Any], exhaust: Sequence[Any]) -> None:
    for part in supply:
        system.add_supply_duct_element(part)
    for part in exhaust:
        system.add_exhaust_duct_element(part)


class DuctingSection(Section[DuctingRecord, TranslatedDucting]):
    id = DUCTING_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedDucting
    requires = (VENTILATION,)
    attaches = None

    def read(self, raw: Mapping[str, object]) -> DuctingRecord:
        return DuctingRecord.read(raw)

    def translate(self, record: DuctingRecord, inputs: Inputs) -> TranslatedDucting:
        systems = [item.system for item in inputs.all(VENTILATION) if item.source.item_id == record.ventilator_id]
        if held := [system for system in systems if system.supply_ducting or system.exhaust_ducting]:
            raise RecordError(f"ventilation system {held[0].identifier} already holds ducts")
        built = [ducts(record) for _system in systems]
        for system, (supply, exhaust) in zip(systems, built, strict=True):
            add_ducts(system, supply, exhaust)
        return TranslatedDucting(record, tuple(systems))

    def result_fields(self, objects: Mapping[str, TranslatedDucting]) -> Mapping[str, JSONValue]:
        """Per Ventilator the record reached: each element as built, and the system's identifier, its Room count and
        Ruby's two lengths, which conformance holds every reloaded system to."""
        elements: list[JSONValue] = []
        ventilators: list[JSONValue] = []
        for _identifier, item in sorted(objects.items()):
            if not item.systems:
                continue
            source, built = item.source, item.systems[0]
            elements.extend(
                element_row(source.ventilator_id, part) for part in built.supply_ducting + built.exhaust_ducting
            )
            ventilators.append(
                {
                    "ventilator_id": source.ventilator_id,
                    "system_identifier": built.identifier,
                    "room_count": len(item.systems),
                    "supply_length_m": source.supply_length_m,
                    "exhaust_length_m": source.exhaust_length_m,
                }
            )
        return {"elements": elements, "ventilators": ventilators}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reloaded ventilation system holds only supply elements (`duct_type` 1) in `supply_ducting` and only
        exhaust elements (2) in `exhaust_ducting`. Each reported Ventilator's systems, on as many Rooms as it reached,
        read back Ruby's two lengths as their total lengths and carry each reported element with its direction,
        segment count, length, shape and sizes; and no Room's system holds an element the run did not report."""
        held: dict[str, list[Any]] = {}
        for room in model.rooms:
            if (system := room.properties.ph_hvac.ventilation_system) is not None:
                check_directions(system)
                held.setdefault(system.identifier, []).append(system)
        by_ventilator: dict[str, str] = {}
        for row in result_rows(fields, "ventilators"):
            identifier = str(row.get("system_identifier"))
            by_ventilator[str(row.get("ventilator_id"))] = identifier
            found = held.get(identifier, [])
            if len(found) != row.get("room_count"):
                raise ValueError(
                    f"ventilation system {identifier} is on {len(found)} Rooms, the run reported "
                    f"{row.get('room_count')}"
                )
            for system in found:
                check_totals(system, row)
        reported: dict[str, set[str]] = {}
        for row in result_rows(fields, "elements"):
            identifier = by_ventilator.get(str(row.get("ventilator_id")), "")
            reported.setdefault(identifier, set()).add(str(row.get("identifier")))
            for system in held.get(identifier, []):
                check_element(system, row)
        for identifier, systems in held.items():
            for system in systems:
                names = [part.identifier for part in system.supply_ducting + system.exhaust_ducting]
                if extra := sorted(set(names) - reported.get(identifier, set())):
                    raise ValueError(
                        f"ventilation system {system.identifier} holds ducts the run did not report: {', '.join(extra)}"
                    )


def element_row(ventilator_id: str, built: Any) -> dict[str, JSONValue]:
    first = sorted(built.segments, key=lambda item: item.identifier)[0]
    row: dict[str, JSONValue] = {
        "ventilator_id": ventilator_id,
        "identifier": built.identifier,
        "duct_type": built.duct_type,
        "segment_count": len(built.segments),
        "length_m": float(built.length),
        "shape_type": built.shape_type,
    }
    for key, attribute in SIZES.items():
        value = getattr(first, attribute)
        row[key] = value if value is None or isinstance(value, bool) else float(value)
    return row


def check_directions(system: Any) -> None:
    for duct_type, attribute in LISTS.items():
        if wrong := [part.identifier for part in getattr(system, attribute) if part.duct_type != duct_type]:
            raise ValueError(
                f"ventilation system {system.identifier} {attribute} holds {', '.join(wrong)} with another duct_type"
            )


def check_totals(system: Any, row: Mapping[str, JSONValue]) -> None:
    read = (float(system.supply_ducting_total_length), float(system.exhaust_ducting_total_length))
    if not (same_length(row.get("supply_length_m"), read[0]) and same_length(row.get("exhaust_length_m"), read[1])):
        raise ValueError(
            f"ventilation system {system.identifier} duct lengths read back {read}, the run reported "
            f"{(row.get('supply_length_m'), row.get('exhaust_length_m'))}"
        )


def check_element(system: Any, row: Mapping[str, JSONValue]) -> None:
    """The reported element, in the list its `duct_type` names, reads back its row: segment count, shape, sizes and
    insulation exactly as written, its length to the millimetre, and every segment the row's size and insulation."""
    identifier = str(row.get("identifier"))
    duct_type = row.get("duct_type")
    listed = getattr(system, LISTS[duct_type]) if isinstance(duct_type, int) and duct_type in LISTS else []
    found = {part.identifier: part for part in listed}.get(identifier)
    if found is None:
        raise ValueError(f"ventilation system {system.identifier} lost duct element {identifier}")
    if not found.segments:
        raise ValueError(f"duct element {identifier} has no segments")
    read = element_row(str(row.get("ventilator_id")), found)
    others = {key: value for key, value in read.items() if key != "length_m"}
    sizes = {tuple(getattr(part, name) for name in SIZES.values()) for part in found.segments}
    if (
        others != {key: row.get(key) for key in others}
        or not same_length(row.get("length_m"), float(found.length))
        or len(sizes) != 1
    ):
        raise ValueError(f"duct element {identifier} reads back {read}, the run reported {dict(row)}")
