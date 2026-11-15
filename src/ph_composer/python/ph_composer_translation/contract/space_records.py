"""Detached Spaces extraction values: a Space with its Zone, stored airflows, and each Volume with its prism and
Floor Segments. Loops and polygons are world coordinates in metres; a Floor Segment's loops are already
projected onto its horizontal plane."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field

from . import JSONObject, RecordError, as_number, as_text, user_data

#: The three airflow rates a Space record may store, in m3/h.
AIRFLOWS = ("v_sup_m3h", "v_eta_m3h", "v_tran_m3h")

Point = tuple[float, float, float]
Polygon = tuple[Point, ...]


def mapping(value: object, label: str) -> Mapping[str, object]:
    if not isinstance(value, Mapping):
        raise RecordError(f"{label} must be an object")
    return value


def rows(value: object, label: str) -> Sequence[object]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Sequence):
        raise RecordError(f"{label} must be a list")
    return value


def polygon(value: object, label: str) -> Polygon:
    points = rows(value, label)
    if len(points) < 3:
        raise RecordError(f"{label} must have at least three points")
    read: list[Point] = []
    for point in points:
        coordinates = rows(point, label)
        if len(coordinates) != 3:
            raise RecordError(f"{label} points must have three coordinates")
        x, y, z = (as_number(value, label) for value in coordinates)
        read.append((x, y, z))
    return tuple(read)


def factor(row: Mapping[str, object], key: str, label: str) -> float:
    value = as_number(row.get(key), f"{label} {key}")
    if not 0 <= value <= 1:
        raise RecordError(f"{label} {key} must be between 0 and 1")
    return value


def text(value: object, label: str) -> str:
    """Optional text: absent or null is empty, a string is kept, anything else is a malformed record."""
    if value is None:
        return ""
    if not isinstance(value, str):
        raise RecordError(f"{label} must be text")
    return value.strip()


@dataclass(frozen=True)
class FloorSegmentRecord:
    id: str
    display_name: str
    weighting_factor: float
    net_area_factor: float
    #: The outer loop first, then any holes.
    loops_m: tuple[Polygon, ...]
    user_data: JSONObject = field(default_factory=dict)

    @classmethod
    def read(cls, value: object) -> FloorSegmentRecord:
        row = mapping(value, "floor segment")
        identifier = as_text(row.get("id"), "floor segment id")
        label = f"floor segment {identifier}"
        loops = tuple(polygon(loop, f"{label} loop") for loop in rows(row.get("loops_m"), f"{label} loops_m"))
        if not loops:
            raise RecordError(f"{label} loops_m must not be empty")
        return cls(
            identifier,
            text(row.get("display_name"), f"{label} display_name"),
            factor(row, "weighting_factor", label),
            factor(row, "net_area_factor", label),
            loops,
            user_data(row.get("user_data"), label),
        )


@dataclass(frozen=True)
class VolumeRecord:
    id: str
    display_name: str
    avg_ceiling_height_m: float
    floor_id: str
    #: The preview prism's polygons.
    geometry: tuple[Polygon, ...]
    floor_segments: tuple[FloorSegmentRecord, ...]
    user_data: JSONObject = field(default_factory=dict)
    #: The Volume's Space Floor's own map, never the Volume's.
    floor_user_data: JSONObject = field(default_factory=dict)

    @classmethod
    def read(cls, value: object) -> VolumeRecord:
        row = mapping(value, "volume")
        identifier = as_text(row.get("id"), "volume id")
        label = f"volume {identifier}"
        height = as_number(row.get("avg_ceiling_height_m"), f"{label} avg_ceiling_height_m")
        if height <= 0:
            raise RecordError(f"{label} avg_ceiling_height_m must be positive")
        return cls(
            identifier,
            text(row.get("display_name"), f"{label} display_name"),
            height,
            as_text(row.get("floor_id"), f"{label} floor_id"),
            tuple(polygon(item, f"{label} geometry") for item in rows(row.get("geometry"), f"{label} geometry")),
            tuple(FloorSegmentRecord.read(item) for item in rows(row.get("floor_segments"), f"{label} segments")),
            user_data(row.get("user_data"), label),
            user_data(row.get("floor_user_data"), f"{label} floor"),
        )


@dataclass(frozen=True)
class SpaceRecord:
    id: str
    zone_id: str
    name: str
    number: str
    #: The stored rates in m3/h; an absent rate is absent here too.
    airflows: Mapping[str, float]
    volumes: tuple[VolumeRecord, ...]
    user_data: JSONObject = field(default_factory=dict)
    #: Drawn outside its Zone's extents: exported as drawn, named in the report.
    offset_from_zone: bool = False

    @classmethod
    def read(cls, value: object) -> SpaceRecord:
        row = mapping(value, "space")
        identifier = as_text(row.get("id"), "space id")
        label = f"space {identifier}"
        airflows: dict[str, float] = {}
        for key in AIRFLOWS:
            if key in row:
                rate = as_number(row[key], f"{label} {key}")
                if rate < 0:
                    raise RecordError(f"{label} {key} must not be negative")
                airflows[key] = rate
        offset = row.get("offset_from_zone", False)
        if not isinstance(offset, bool):
            raise RecordError(f"{label} offset_from_zone must be true or false")
        return cls(
            identifier,
            as_text(row.get("zone_id"), f"{label} zone_id"),
            text(row.get("name"), f"{label} name"),
            text(row.get("number"), f"{label} number"),
            airflows,
            tuple(VolumeRecord.read(item) for item in rows(row.get("volumes"), f"{label} volumes")),
            user_data(row.get("user_data"), label),
            offset,
        )
