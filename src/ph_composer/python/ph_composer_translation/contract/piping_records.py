"""Detached hot water piping extraction values (Ruby `features/piping/runs/extraction.rb`): one record per Hot Water
System with pipes, holding its trunks, each with its branches and each branch's twigs, and its recirculation
elements. Every run is one pipe element of segments, each a pipe with its Pipe Type's values and its points in world
metres. The record also carries the System's recirculation temperature and hours as Ruby works them out, which
conformance holds the reloaded system to.

honeybee-ph keys trunks, branches, fixtures, recirculation elements and segments by identifier when it writes them, so
two siblings under one identifier would silently become one: every identifier in a record must be unique."""

from __future__ import annotations

from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass

from . import JSONObject, RecordError, as_number, as_text, bounded, user_data, whole
from .mechanical_records import flag
from .space_records import Point, mapping, rows
from .thermal_bridge_records import point

#: honeybee-ph's `PhHvacPipeMaterial` numbers, 1 Copper M to 8 PEX CTS SDR.
MATERIALS = range(1, 9)
#: honeybee-ph's `PhHvacPipeInsulationQuality` numbers, 1 None to 3 Good.
INSULATION_QUALITIES = range(1, 4)


@dataclass(frozen=True)
class PipeSegmentValues:
    """One pipe: a `PhHvacPipeSegment` from `start` to `end` with its Pipe Type's values and its own temperature and
    hours (honeybee-ph's 60 C and 24 h for a distribution pipe)."""

    identifier: str
    display_name: str
    start: Point
    end: Point
    material: int
    diameter_mm: float
    insulation_thickness_mm: float
    insulation_conductivity: float
    insulation_reflective: bool
    insulation_quality: int
    water_temp_c: float
    daily_period: float
    user_data: JSONObject

    @classmethod
    def read(cls, raw: object, label: str) -> PipeSegmentValues:
        values = mapping(raw, label)
        identifier = as_text(values.get("identifier"), f"{label} identifier")
        label = f"{label} segment {identifier}"
        points = rows(values.get("points_m"), f"{label} points_m")
        if len(points) != 2:
            raise RecordError(f"{label} points_m must be two points")
        start, end = (point(value, label) for value in points)
        return cls(
            identifier,
            as_text(values.get("display_name"), f"{label} display_name"),
            start,
            end,
            whole(values.get("material"), f"{label} material", MATERIALS),
            bounded(values.get("diameter_mm"), f"{label} diameter_mm", 0.0, above=True),
            bounded(values.get("insulation_thickness_mm"), f"{label} insulation_thickness_mm", 0.0),
            bounded(values.get("insulation_conductivity"), f"{label} insulation_conductivity", 0.0, above=True),
            flag(values.get("insulation_reflective"), f"{label} insulation_reflective"),
            whole(values.get("insulation_quality"), f"{label} insulation_quality", INSULATION_QUALITIES),
            bounded(values.get("water_temp_c"), f"{label} water_temp_c", 0.0, 100.0),
            bounded(values.get("daily_period"), f"{label} daily_period", 0.0, 24.0),
            user_data(values.get("user_data"), label),
        )


@dataclass(frozen=True)
class PipeElementValues:
    """One run as a `PhHvacPipeElement`: a twig, a recirculation element, or the element a trunk or branch holds."""

    identifier: str
    display_name: str
    segments: tuple[PipeSegmentValues, ...]

    @classmethod
    def read(cls, raw: object, label: str) -> PipeElementValues:
        values = mapping(raw, label)
        identifier = as_text(values.get("identifier"), f"{label} identifier")
        label = f"{label} {identifier}"
        segments = tuple(
            PipeSegmentValues.read(segment, label) for segment in rows(values.get("segments"), f"{label} segments")
        )
        if not segments:
            raise RecordError(f"{label} has no segments")
        return cls(identifier, as_text(values.get("display_name"), f"{label} display_name"), segments)


@dataclass(frozen=True)
class PipeBranchValues:
    element: PipeElementValues
    twigs: tuple[PipeElementValues, ...]

    @classmethod
    def read(cls, raw: object, label: str) -> PipeBranchValues:
        element = PipeElementValues.read(raw, label)
        twigs = rows(mapping(raw, label).get("twigs"), f"{label} {element.identifier} twigs")
        return cls(element, tuple(PipeElementValues.read(twig, f"{label} {element.identifier} twig") for twig in twigs))


@dataclass(frozen=True)
class PipeTrunkValues:
    element: PipeElementValues
    multiplier: int
    demand_recirculation: bool
    branches: tuple[PipeBranchValues, ...]

    @classmethod
    def read(cls, raw: object, label: str) -> PipeTrunkValues:
        values = mapping(raw, label)
        element = PipeElementValues.read(values, label)
        label = f"{label} {element.identifier}"
        return cls(
            element,
            whole(values.get("multiplier"), f"{label} multiplier", minimum=1),
            flag(values.get("demand_recirculation"), f"{label} demand_recirculation"),
            tuple(PipeBranchValues.read(branch, f"{label} branch") for branch in rows(values.get("branches"), label)),
        )


@dataclass(frozen=True)
class PipingRecord:
    """One Hot Water System's pipes, for every `PhHotWaterSystem` the hot water section built for it."""

    id: str
    system_id: str
    recirculation_temperature_c: float
    recirculation_hours: int
    trunks: tuple[PipeTrunkValues, ...]
    recirculation: tuple[PipeElementValues, ...]

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> PipingRecord:
        identifier = as_text(raw.get("id"), "piping id")
        label = f"piping {identifier}"
        record = cls(
            identifier,
            as_text(raw.get("system_id"), f"{label} system_id"),
            # A length-weighted mean Ruby works out: a finite number, not held to the authored 0 to 100, since pipes all
            # at 100 C can average a float's width above it.
            as_number(raw.get("recirculation_temperature_c"), f"{label} recirculation_temperature_c"),
            whole(raw.get("recirculation_hours"), f"{label} recirculation_hours", range(0, 25)),
            tuple(
                PipeTrunkValues.read(trunk, f"{label} trunk") for trunk in rows(raw.get("trunks"), f"{label} trunks")
            ),
            tuple(
                PipeElementValues.read(element, f"{label} recirculation")
                for element in rows(raw.get("recirculation"), f"{label} recirculation")
            ),
        )
        record.check_unique(label)
        return record

    def elements(self) -> list[PipeElementValues]:
        """Every run's element: trunks, branches, twigs and recirculation."""
        found = list(self.recirculation)
        for trunk in self.trunks:
            found.append(trunk.element)
            for branch in trunk.branches:
                found.append(branch.element)
                found.extend(branch.twigs)
        return found

    def check_unique(self, label: str) -> None:
        for noun, identifiers in (
            ("run", [element.identifier for element in self.elements()]),
            ("segment", [segment.identifier for element in self.elements() for segment in element.segments]),
        ):
            if repeated := sorted(name for name, count in Counter(identifiers).items() if count > 1):
                raise RecordError(f"{label} names {noun} {', '.join(repeated)} more than once")
