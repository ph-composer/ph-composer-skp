"""Hot water piping, translated through the pinned honeybee-ph stack and added to the hot water systems it belongs to
(Ruby `features/piping/export.rb`; context/CONTRACTS.md, "Translation sections and artifacts").

One record per Hot Water System with pipes. The section requires the hot water section and, in `translate`, adds the
System's trunks, each with its branches and their fixtures (twigs), and its recirculation elements to every
`PhHotWaterSystem` that section built for the System, one per served Zone, before the assembly attaches them to their
Rooms. It is the first section that adds to another section's required objects, so it attaches nothing of its own
(`attaches = None`): its objects stand for the work done. Each hot water object gets its own freshly built pipes from
the same record, never an instance shared between Rooms, so every Room of one System carries an equal system and the
hot water section's digests, taken after every section has translated, stay equal.

Everything is built for every hot water object before any is added to, so a record that cannot be built leaves every
system as it was. The section is required for export: a record that fails would leave one System's Rooms unequal.

The canonical HBJSON is written with its keys sorted, and honeybee-ph writes trunks, branches, fixtures,
recirculation elements and segments as maps keyed by identifier, so a reloaded system holds them in identifier order.
`recirc_temp` and `recirc_hours` add in that order, and float addition depends on it, so every collection here is
added in identifier order too: the system as translated, whose digest the hot water section records, then equals the
system as reloaded."""

from __future__ import annotations

import copy
import math
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any, TypeVar

from . import stack
from .contract import JSONValue, RecordError
from .contract.piping_records import (
    PipeBranchValues,
    PipeElementValues,
    PipeSegmentValues,
    PipeTrunkValues,
    PipingRecord,
)
from .mechanical_sections import HOT_WATER_SECTION_ID, TranslatedHotWater
from .sections import Inputs, Requirement, Section

PIPING_SECTION_ID = "ph_composer.piping.export.piping"
HOT_WATER = Requirement(HOT_WATER_SECTION_ID, TranslatedHotWater)
#: Drawn lengths read back to the millimetre.
LENGTH_TOLERANCE_M = 0.001

T = TypeVar("T")


@dataclass(frozen=True)
class TranslatedPiping:
    source: PipingRecord
    #: The hot water systems the record's pipes were added to, one per (System, served Zone) pair; none when no
    #: exported Zone takes the System, which Ruby has already noted.
    systems: tuple[Any, ...]


def by_identifier(items: Iterable[T], identifier: Callable[[T], str]) -> list[T]:
    return sorted(items, key=identifier)


def segment(values: PipeSegmentValues) -> Any:
    piping = stack.load("honeybee_phhvac.hot_water_piping")
    pointvector = stack.load("ladybug_geometry.geometry3d.pointvector")
    polyline = stack.load("ladybug_geometry.geometry3d.polyline")
    geometry = polyline.LineSegment3D.from_end_points(
        pointvector.Point3D(*values.start), pointvector.Point3D(*values.end)
    )
    built = piping.PhHvacPipeSegment(
        geometry,
        values.diameter_mm,
        values.insulation_thickness_mm,
        values.insulation_conductivity,
        values.insulation_reflective,
        values.insulation_quality,
        values.daily_period,
        values.water_temp_c,
        values.material,
    )
    built.identifier, built.display_name = values.identifier, values.display_name
    built.user_data = copy.deepcopy(values.user_data)
    return built


def element(values: PipeElementValues) -> Any:
    """A run's `PhHvacPipeElement`, its segments in identifier order. honeybee-ph refuses an element whose segments
    differ in material only when asked its material, so that is asked here, where the record can still be refused."""
    built = stack.load("honeybee_phhvac.hot_water_piping").PhHvacPipeElement()
    built.identifier, built.display_name = values.identifier, values.display_name
    for part in by_identifier(values.segments, lambda item: item.identifier):
        built.add_segment(segment(part))
    built.material_name  # noqa: B018 - raises ValueError for mixed materials
    return built


def branch(values: PipeBranchValues) -> Any:
    """A branch run with its twigs as `fixtures`. Its element takes the branch's identifier and name, as the trunk's
    does: the run is one element, and an inner element's own random identifier would make two Rooms' systems differ."""
    built = stack.load("honeybee_phhvac.hot_water_piping").PhHvacPipeBranch()
    built.identifier, built.display_name = values.element.identifier, values.element.display_name
    built.pipe_element = element(values.element)
    for twig in by_identifier(values.twigs, lambda item: item.identifier):
        built.add_fixture(element(twig))
    return built


def trunk(values: PipeTrunkValues) -> Any:
    built = stack.load("honeybee_phhvac.hot_water_piping").PhHvacPipeTrunk()
    built.identifier, built.display_name = values.element.identifier, values.element.display_name
    built.pipe_element = element(values.element)
    built.multiplier = values.multiplier
    built.demand_recirculation = values.demand_recirculation
    for part in by_identifier(values.branches, lambda item: item.element.identifier):
        built.add_branch(branch(part))
    return built


def pipes(record: PipingRecord) -> tuple[list[Any], list[Any]]:
    """The record's trunks and recirculation elements, freshly built, each list in identifier order."""
    try:
        trunks = [trunk(part) for part in by_identifier(record.trunks, lambda item: item.element.identifier)]
        recirculation = [element(part) for part in by_identifier(record.recirculation, lambda item: item.identifier)]
    except (ArithmeticError, AssertionError, TypeError, ValueError) as error:
        raise RecordError(f"piping {record.id} could not be built: {error}") from error
    return trunks, recirculation


def add_pipes(system: Any, trunks: Sequence[Any], recirculation: Sequence[Any]) -> None:
    for part in trunks:
        system.add_distribution_piping(part)
    for part in recirculation:
        system.add_recirc_piping(part)


class PipingSection(Section[PipingRecord, TranslatedPiping]):
    id = PIPING_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedPiping
    requires = (HOT_WATER,)
    attaches = None

    def read(self, raw: Mapping[str, object]) -> PipingRecord:
        return PipingRecord.read(raw)

    def translate(self, record: PipingRecord, inputs: Inputs) -> TranslatedPiping:
        systems = [item.system for item in inputs.all(HOT_WATER) if item.source.item_id == record.system_id]
        if held := [system for system in systems if list(system.distribution_piping) or list(system.recirc_piping)]:
            raise RecordError(f"hot water system {held[0].identifier} already holds piping")
        built = [pipes(record) for _system in systems]
        for system, (trunks, recirculation) in zip(systems, built, strict=True):
            add_pipes(system, trunks, recirculation)
        return TranslatedPiping(record, tuple(systems))

    def result_fields(self, objects: Mapping[str, TranslatedPiping]) -> Mapping[str, JSONValue]:
        """Per System the record reached: each trunk and recirculation element as built, and the recirculation
        temperature and hours Ruby worked out, which conformance holds every reloaded system to."""
        trunks: list[JSONValue] = []
        recirculation: list[JSONValue] = []
        systems: list[JSONValue] = []
        for _identifier, item in sorted(objects.items()):
            if not item.systems:
                continue
            source, built = item.source, item.systems[0]
            trunks.extend(trunk_row(source.system_id, part) for part in built.distribution_piping)
            recirculation.extend(
                {"system_id": source.system_id, "identifier": part.identifier, "length_m": float(part.length)}
                for part in built.recirc_piping
            )
            systems.append(
                {
                    "system_id": source.system_id,
                    "room_count": len(item.systems),
                    "recirculation_temperature_c": source.recirculation_temperature_c,
                    "recirculation_hours": source.recirculation_hours,
                }
            )
        return {"trunks": trunks, "recirculation": recirculation, "systems": systems}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported System's reloaded hot water systems, on as many Rooms as it reached, carry each reported
        trunk with its multiplier, demand recirculation, drawn length, branch count and each branch's twig count, and
        each reported recirculation element with its length, and read back Ruby's recirculation temperature and hours;
        and no Room's hot water system holds a trunk or recirculation element the run did not report."""
        held: dict[str, list[Any]] = {}
        for room in model.rooms:
            if (system := room.properties.ph_hvac.hot_water_system) is not None:
                held.setdefault(system.identifier, []).append(system)
        trunk_rows = rows(fields, "trunks")
        recirculation_rows = rows(fields, "recirculation")
        for row in rows(fields, "systems"):
            found = held.get(str(row.get("system_id")), [])
            if len(found) != row.get("room_count"):
                raise ValueError(
                    f"hot water system {row.get('system_id')} is on {len(found)} Rooms, the run reported "
                    f"{row.get('room_count')}"
                )
            for system in found:
                check_recirculation(system, row)
        for row in trunk_rows:
            for system in held.get(str(row.get("system_id")), []):
                check_trunk(system, row)
        for row in recirculation_rows:
            for system in held.get(str(row.get("system_id")), []):
                check_element(system, row)
        reported: dict[str, set[str]] = {}
        for row in trunk_rows + recirculation_rows:
            reported.setdefault(str(row.get("system_id")), set()).add(str(row.get("identifier")))
        for identifier, systems in held.items():
            for system in systems:
                names = [part.identifier for part in system.distribution_piping]
                names += [part.identifier for part in system.recirc_piping]
                if extra := sorted(set(names) - reported.get(identifier, set())):
                    raise ValueError(
                        f"hot water system {system.identifier} holds piping the run did not report: {', '.join(extra)}"
                    )


def trunk_row(system_id: str, built: Any) -> dict[str, JSONValue]:
    return {
        "system_id": system_id,
        "identifier": built.identifier,
        "multiplier": built.multiplier,
        "demand_recirculation": built.demand_recirculation,
        "length_m": float(built.length),
        "branch_count": len(built.branches),
        "twig_counts": twig_counts(built),
    }


def twig_counts(built: Any) -> list[JSONValue]:
    return [part.num_fixtures for part in sorted(built.branches, key=lambda item: item.identifier)]


def rows(fields: Mapping[str, JSONValue], key: str) -> list[dict[str, JSONValue]]:
    reported = fields.get(key)
    return [row for row in (reported if isinstance(reported, list) else []) if isinstance(row, dict)]


def same_length(value: JSONValue, length: float) -> bool:
    return isinstance(value, (int, float)) and math.isclose(value, length, rel_tol=0.0, abs_tol=LENGTH_TOLERANCE_M)


def check_recirculation(system: Any, row: Mapping[str, JSONValue]) -> None:
    """Hours exactly, truncation included; the temperature to float noise."""
    temperature = row.get("recirculation_temperature_c")
    read = (system.recirc_temp, system.recirc_hours)
    if read[1] != row.get("recirculation_hours") or not (
        isinstance(temperature, (int, float)) and math.isclose(read[0], temperature, rel_tol=1e-9, abs_tol=1e-9)
    ):
        raise ValueError(
            f"hot water system {system.identifier} recirculation reads back {read}, the run reported "
            f"{(temperature, row.get('recirculation_hours'))}"
        )


def check_trunk(system: Any, row: Mapping[str, JSONValue]) -> None:
    identifier = str(row.get("identifier"))
    found = {part.identifier: part for part in system.distribution_piping}.get(identifier)
    if found is None:
        raise ValueError(f"hot water system {system.identifier} lost trunk {identifier}")
    read = trunk_row(str(row.get("system_id")), found)
    expected = {key: row.get(key) for key in read if key != "length_m"}
    if {key: value for key, value in read.items() if key != "length_m"} != expected or not same_length(
        row.get("length_m"), float(found.length)
    ):
        raise ValueError(f"trunk {identifier} reads back {read}, the run reported {dict(row)}")


def check_element(system: Any, row: Mapping[str, JSONValue]) -> None:
    identifier = str(row.get("identifier"))
    found = {part.identifier: part for part in system.recirc_piping}.get(identifier)
    if found is None:
        raise ValueError(f"hot water system {system.identifier} lost recirculation element {identifier}")
    if not same_length(row.get("length_m"), float(found.length)):
        raise ValueError(
            f"recirculation element {identifier} reads back {found.length} m, the run reported {row.get('length_m')}"
        )
