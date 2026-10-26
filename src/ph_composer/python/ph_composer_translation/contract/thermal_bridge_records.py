"""Detached thermal-bridge extraction values: one run of assigned Edges with its Zone, its type's psi-value and
group, its quantity and its points in world metres, in order, the first repeated last when the run is closed."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from . import RecordError, as_number, as_text
from .space_records import Point, rows

#: honeybee-ph's group strings, as the type stores them.
GROUPS = ("15-Ambient", "16-Perimeter", "17-FS/BC")


@dataclass(frozen=True)
class ThermalBridgeRecord:
    #: The run's identifier (`tb_` and a digest), also the `PhThermalBridge` identifier.
    id: str
    display_name: str
    zone_id: str
    type_id: str
    type_name: str
    #: Signed: a negative psi-value is legal for an exterior-dimension model.
    psi_w_mk: float
    group: str
    quantity: float
    closed: bool
    points_m: tuple[Point, ...]

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> ThermalBridgeRecord:
        identifier = as_text(raw.get("id"), "thermal bridge id")
        label = f"thermal bridge {identifier}"
        group = as_text(raw.get("group"), f"{label} group")
        if group not in GROUPS:
            raise RecordError(f"{label} group must be one of {', '.join(GROUPS)}")
        quantity = as_number(raw.get("quantity"), f"{label} quantity")
        if quantity <= 0:
            raise RecordError(f"{label} quantity must be greater than 0")
        closed = raw.get("closed")
        if not isinstance(closed, bool):
            raise RecordError(f"{label} closed must be true or false")
        points = tuple(point(value, label) for value in rows(raw.get("points_m"), f"{label} points_m"))
        # An open run of one Edge is two points; a closed run is at least a triangle and its first point again.
        if len(points) < (4 if closed else 2):
            raise RecordError(f"{label} points_m has too few points for a {'closed' if closed else 'open'} run")
        if closed and points[0] != points[-1]:
            raise RecordError(f"{label} points_m must repeat its first point last when closed")
        return cls(
            identifier,
            as_text(raw.get("display_name"), f"{label} display_name"),
            as_text(raw.get("zone_id"), f"{label} zone_id"),
            as_text(raw.get("type_id"), f"{label} type_id"),
            as_text(raw.get("type_name"), f"{label} type_name"),
            as_number(raw.get("psi_w_mk"), f"{label} psi_w_mk"),
            group,
            quantity,
            closed,
            points,
        )


def point(value: object, label: str) -> Point:
    coordinates = rows(value, f"{label} point")
    if len(coordinates) != 3:
        raise RecordError(f"{label} points must have three coordinates")
    x, y, z = (as_number(item, f"{label} coordinate") for item in coordinates)
    return (x, y, z)
