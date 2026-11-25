"""Detached ERV ducting extraction values (Ruby `features/ducting/extraction.rb`): one record per Ventilator with
ducts, holding its supply (Outdoor air) and exhaust (Exhaust air) elements. Every run is one duct element of segments,
or N identical elements for a run of quantity N, each segment a duct with its Duct Type's values in metres and its
points in world metres. The record also carries each direction's length, quantity applied, as Ruby works it out, which
conformance holds the reloaded system's total lengths to.

honeybee-ph keys an element's segments by identifier, so two segments under one identifier would silently become one;
and an element joins only round or only rectangular segments. Every identifier in a record must be unique, and every
segment of an element must share its shape."""

from __future__ import annotations

from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass

from . import JSONObject, RecordError, as_text, bounded, user_data, whole
from .mechanical_records import flag
from .space_records import Point, mapping, rows
from .thermal_bridge_records import point

#: honeybee-ph's `PhDuctElement.duct_type`: 1 supply, 2 exhaust.
SUPPLY, EXHAUST = 1, 2


def optional_size(value: object, label: str) -> float | None:
    return None if value is None else bounded(value, label, 0.0, above=True)


@dataclass(frozen=True)
class DuctSegmentValues:
    """One duct: a `PhDuctSegment` from `start` to `end` with its Duct Type's values in metres. Rectangular when it has
    a width and a height, round otherwise, as honeybee-ph reads its shape."""

    identifier: str
    display_name: str
    start: Point
    end: Point
    diameter_m: float
    width_m: float | None
    height_m: float | None
    insulation_thickness_m: float
    insulation_conductivity: float
    insulation_reflective: bool
    user_data: JSONObject

    @property
    def rectangular(self) -> bool:
        return self.width_m is not None

    @classmethod
    def read(cls, raw: object, label: str) -> DuctSegmentValues:
        values = mapping(raw, label)
        identifier = as_text(values.get("identifier"), f"{label} identifier")
        label = f"{label} segment {identifier}"
        points = rows(values.get("points_m"), f"{label} points_m")
        if len(points) != 2:
            raise RecordError(f"{label} points_m must be two points")
        start, end = (point(value, label) for value in points)
        width = optional_size(values.get("width_m"), f"{label} width_m")
        height = optional_size(values.get("height_m"), f"{label} height_m")
        if (width is None) != (height is None):
            raise RecordError(f"{label} must have both a width and a height, or neither")
        return cls(
            identifier,
            as_text(values.get("display_name"), f"{label} display_name"),
            start,
            end,
            bounded(values.get("diameter_m"), f"{label} diameter_m", 0.0, above=True),
            width,
            height,
            bounded(values.get("insulation_thickness_m"), f"{label} insulation_thickness_m", 0.0),
            bounded(values.get("insulation_conductivity"), f"{label} insulation_conductivity", 0.0, above=True),
            flag(values.get("insulation_reflective"), f"{label} insulation_reflective"),
            user_data(values.get("user_data"), label),
        )


@dataclass(frozen=True)
class DuctElementValues:
    """One run, or one copy of a run, as a `PhDuctElement` of one direction and one shape."""

    identifier: str
    display_name: str
    duct_type: int
    segments: tuple[DuctSegmentValues, ...]

    @classmethod
    def read(cls, raw: object, label: str, duct_type: int) -> DuctElementValues:
        values = mapping(raw, label)
        identifier = as_text(values.get("identifier"), f"{label} identifier")
        label = f"{label} {identifier}"
        if whole(values.get("duct_type"), f"{label} duct_type") != duct_type:
            raise RecordError(f"{label} duct_type must be {duct_type}")
        segments = tuple(
            DuctSegmentValues.read(segment, label) for segment in rows(values.get("segments"), f"{label} segments")
        )
        if not segments:
            raise RecordError(f"{label} has no segments")
        if len({segment.rectangular for segment in segments}) > 1:
            raise RecordError(f"{label} joins round and rectangular segments")
        return cls(identifier, as_text(values.get("display_name"), f"{label} display_name"), duct_type, segments)


@dataclass(frozen=True)
class DuctingRecord:
    """One Ventilator's ducts, for every `PhVentilationSystem` the ventilation section built for it."""

    id: str
    ventilator_id: str
    supply: tuple[DuctElementValues, ...]
    exhaust: tuple[DuctElementValues, ...]
    supply_length_m: float
    exhaust_length_m: float

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> DuctingRecord:
        identifier = as_text(raw.get("id"), "ducting id")
        label = f"ducting {identifier}"
        supply, exhaust = (
            tuple(
                DuctElementValues.read(element, f"{label} {key}", duct_type)
                for element in rows(raw.get(key), f"{label} {key}")
            )
            for key, duct_type in (("supply", SUPPLY), ("exhaust", EXHAUST))
        )
        record = cls(
            identifier,
            as_text(raw.get("ventilator_id"), f"{label} ventilator_id"),
            supply,
            exhaust,
            bounded(raw.get("supply_length_m"), f"{label} supply_length_m", 0.0),
            bounded(raw.get("exhaust_length_m"), f"{label} exhaust_length_m", 0.0),
        )
        record.check_unique(label)
        return record

    def check_unique(self, label: str) -> None:
        elements = self.supply + self.exhaust
        for noun, identifiers in (
            ("element", [element.identifier for element in elements]),
            ("segment", [segment.identifier for element in elements for segment in element.segments]),
        ):
            if repeated := sorted(name for name, count in Counter(identifiers).items() if count > 1):
                raise RecordError(f"{label} names {noun} {', '.join(repeated)} more than once")
