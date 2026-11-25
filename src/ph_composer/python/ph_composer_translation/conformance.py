"""Reload the exact canonical HBJSON and reconcile identifiers and reciprocal Surface targets, then let each
section check the reloaded model against its own result fields (`Section.conformance`)."""

from __future__ import annotations

import json
import math
from collections.abc import Mapping, Sequence
from typing import Any

from . import stack
from .contract import JSONValue
from .sections import Section

#: Drawn lengths read back to the millimetre.
LENGTH_TOLERANCE_M = 0.001


class ConformanceError(ValueError):
    """The canonical bytes did not reconcile with the result. Its class name, not its message, tells the
    runtime page and the log that conformance, rather than translation, failed."""


def check(
    canonical: Mapping[str, Any], result: Mapping[str, Any] | None = None, sections: Sequence[Section[Any, Any]] = ()
) -> None:
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    model = stack.load("honeybee.model").Model.from_dict(json.loads(canonical["hbjson"]))
    if model.units != "Meters":
        raise ValueError("canonical geometry must use meters")
    rooms = {room.identifier: room for room in model.rooms}
    faces = {face.identifier: face for room in model.rooms for face in room.faces}
    owners = {face.identifier: room.identifier for room in model.rooms for face in room.faces}
    if len(rooms) != len(model.rooms) or len(faces) != sum(len(room.faces) for room in model.rooms):
        raise ValueError("canonical identifiers repeat")
    if len(rooms) != canonical["rooms"] or len(faces) != canonical["faces"]:
        raise ValueError("canonical object counts disagree")
    if not rooms or not faces:
        raise ValueError("canonical model has no usable geometry")
    surfaces = 0
    for face in faces.values():
        boundary = face.boundary_condition
        if boundary.name != "Surface":
            continue
        surfaces += 1
        target_id, room_id = boundary.boundary_condition_objects[:2]
        target = faces.get(target_id)
        if target is None or room_id not in rooms or target not in rooms[room_id].faces:
            raise ValueError("canonical Surface has no emitted counterpart")
        if target.boundary_condition.name != "Surface":
            raise ValueError("canonical Surface counterpart is not Surface")
        if tuple(target.boundary_condition.boundary_condition_objects[:2]) != (
            face.identifier,
            owners[face.identifier],
        ):
            raise ValueError("canonical Surface is not reciprocal")
    if surfaces != 2 * canonical["surface_pairs"]:
        raise ValueError("canonical Surface accounting disagrees")
    for section in sections:
        section.conformance(model, (result or {}).get(section.id, {}))


def result_rows(fields: Mapping[str, JSONValue], key: str) -> list[dict[str, JSONValue]]:
    """A section's result rows under `key`, each a JSON object; anything else reads as no row."""
    reported = fields.get(key)
    return [row for row in (reported if isinstance(reported, list) else []) if isinstance(row, dict)]


def same_length(value: JSONValue, length: float) -> bool:
    """A reported length equal to a reloaded one to the millimetre."""
    return isinstance(value, (int, float)) and math.isclose(value, length, rel_tol=0.0, abs_tol=LENGTH_TOLERANCE_M)
