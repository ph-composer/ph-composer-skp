"""Detached shading extraction values: one Shading Face occurrence with its identifier, the name of the shading
component it exports under, and its outer loop and holes in world metres."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from . import RecordError, as_text
from .space_records import Polygon, polygon, rows

#: Every key a Shade record carries. A record with any other is a contract mismatch, not data to ignore.
KEYS = frozenset({"id", "display_name", "boundary", "holes"})


@dataclass(frozen=True)
class ShadeRecord:
    #: `shd_` and a digest of the occurrence's root path, also the `Shade` identifier.
    id: str
    #: The shading component's name; PHX writes one component per name.
    display_name: str
    boundary: Polygon
    holes: tuple[Polygon, ...]

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> ShadeRecord:
        identifier = as_text(raw.get("id"), "shade id")
        label = f"shade {identifier}"
        if unknown := sorted(set(raw) - KEYS):
            raise RecordError(f"{label} has unknown fields: {', '.join(unknown)}")
        holes = tuple(
            polygon(loop, f"{label} hole {index + 1}")
            for index, loop in enumerate(rows(raw.get("holes"), f"{label} holes"))
        )
        return cls(
            identifier,
            as_text(raw.get("display_name"), f"{label} display_name"),
            polygon(raw.get("boundary"), f"{label} boundary"),
            holes,
        )
