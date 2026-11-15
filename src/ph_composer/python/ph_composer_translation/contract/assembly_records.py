"""Typed authored construction records. Missing values never become invented thermal layers."""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field

from . import JSONObject, RecordError, as_number, as_text, user_data


def positive(value: object, label: str) -> float:
    number = as_number(value, label)
    if number <= 0:
        raise RecordError(f"{label} must be positive")
    return number


def optional_number(value: object, label: str) -> float | None:
    return None if value is None else positive(value, label)


def rows(value: object, label: str) -> tuple[Mapping[str, object], ...]:
    if isinstance(value, (str, bytes)) or not isinstance(value, Sequence):
        raise RecordError(f"{label} must be a list")
    found = []
    ids: set[str] = set()
    for row in value:
        if not isinstance(row, Mapping):
            raise RecordError(f"{label} entries must be objects")
        identifier = as_text(row.get("id"), f"{label} id")
        if identifier in ids:
            raise RecordError(f"{label} repeats id {identifier}")
        ids.add(identifier)
        found.append(row)
    return tuple(found)


@dataclass(frozen=True)
class MaterialRecord:
    id: str
    name: str
    category: str
    conductivity_w_mk: float | None
    density_kg_m3: float | None
    specific_heat_j_kgk: float | None
    emissivity: float | None
    color: str | None

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> MaterialRecord:
        identifier = as_text(raw.get("id"), "material id")
        category = raw.get("category", "")
        if not isinstance(category, str):
            raise RecordError(f"material {identifier} category must be text")
        color = raw.get("color")
        if color is not None and (not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color)):
            raise RecordError(f"material {identifier} color must be a hex colour")
        emissivity = raw.get("emissivity")
        em = None if emissivity is None else as_number(emissivity, "emissivity")
        if em is not None and not 0 <= em <= 1:
            raise RecordError(f"material {identifier} emissivity must be between zero and one")
        return cls(
            identifier,
            as_text(raw.get("name"), "material name"),
            category,
            optional_number(raw.get("conductivity_w_mk"), "conductivity"),
            optional_number(raw.get("density_kg_m3"), "density"),
            optional_number(raw.get("specific_heat_j_kgk"), "specific heat"),
            em,
            color,
        )


@dataclass(frozen=True)
class SegmentRecord:
    id: str
    width_mm: float
    material_id: str
    steel_stud_spacing_mm: float | None
    #: Present only when its Layer is divided: the map rides on this Segment's own cell material.
    user_data: JSONObject = field(default_factory=dict)

    @classmethod
    def read(cls, raw: Mapping[str, object], location: str = "Layer") -> SegmentRecord:
        try:
            material_id = as_text(raw.get("material_id"), "segment material id")
        except RecordError as error:
            raise RecordError(f"{location}: choose a Material for each Layer-Segment.") from error
        identifier = as_text(raw.get("id"), "segment id")
        return cls(
            identifier,
            positive(raw.get("width_mm"), "segment width"),
            material_id,
            optional_number(raw.get("steel_stud_spacing_mm"), "steel stud spacing"),
            user_data(raw.get("user_data"), f"segment {identifier}"),
        )


@dataclass(frozen=True)
class LayerRecord:
    id: str
    thickness_mm: float
    segments: tuple[SegmentRecord, ...]
    #: Rides on the Layer's own material: its single EnergyMaterial, or the hybrid host when it is divided.
    user_data: JSONObject = field(default_factory=dict)

    @property
    def divided(self) -> bool:
        """Whether the Layer is built as a grid of cell materials under a hybrid host. The Ruby contributor
        passes Segment maps only for such a Layer (features/assemblies/export.rb, `divided?`)."""
        return len(self.segments) > 1 or self.segments[0].steel_stud_spacing_mm is not None

    @classmethod
    def read(cls, raw: Mapping[str, object], location: str = "Layer") -> LayerRecord:
        segments = tuple(SegmentRecord.read(row, location) for row in rows(raw.get("segments"), "segments"))
        if not segments:
            raise RecordError("a Layer needs a Layer-Segment")
        if sum(segment.steel_stud_spacing_mm is not None for segment in segments) > 1:
            raise RecordError("a Layer can carry only one steel stud spacing")
        if len(segments) == 1 and segments[0].steel_stud_spacing_mm is None and segments[0].user_data:
            raise RecordError("an undivided Layer's Layer-Segment has no material of its own for its user_data")
        identifier = as_text(raw.get("id"), "layer id")
        return cls(
            identifier,
            positive(raw.get("thickness_mm"), "layer thickness"),
            segments,
            user_data(raw.get("user_data"), f"layer {identifier}"),
        )


@dataclass(frozen=True)
class AssemblyRecord:
    id: str
    name: str
    layers: tuple[LayerRecord, ...]
    materials: Mapping[str, MaterialRecord]
    user_data: JSONObject = field(default_factory=dict)

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> AssemblyRecord:
        identifier = as_text(raw.get("id"), "assembly id")
        name = as_text(raw.get("name"), "assembly name")
        orientation = raw.get("orientation")
        if orientation not in ("first_layer_outside", "last_layer_outside"):
            raise RecordError(f"assembly {identifier} has invalid orientation")
        materials = {
            material.id: material
            for material in (MaterialRecord.read(row) for row in rows(raw.get("materials"), "materials"))
        }
        layers = tuple(
            LayerRecord.read(row, f'Assembly "{name}", Layer {index + 1}')
            for index, row in enumerate(rows(raw.get("layers"), "layers"))
        )
        if not layers:
            raise RecordError(f"assembly {identifier} has no thermal layers")
        segment_ids = [segment.id for layer in layers for segment in layer.segments]
        if len(segment_ids) != len(set(segment_ids)):
            raise RecordError(f"assembly {identifier} repeats a segment id")
        for layer in layers:
            for segment in layer.segments:
                if segment.material_id not in materials:
                    raise RecordError(f"assembly {identifier} references unavailable material {segment.material_id}")
            membranes = [materials[segment.material_id].category == "membrane" for segment in layer.segments]
            if any(membranes) and len(layer.segments) != 1:
                raise RecordError(f"assembly {identifier} has a membrane in a mixed Layer")
            for segment in layer.segments:
                material = materials[segment.material_id]
                if material.category != "membrane":
                    if material.conductivity_w_mk is None:
                        raise RecordError(f"material {material.id} needs conductivity")
                    if material.specific_heat_j_kgk is not None and material.specific_heat_j_kgk < 100:
                        raise RecordError(
                            f"material {material.id} specific heat must be at least 100 J/kgK for Honeybee"
                        )
        if all(materials[layer.segments[0].material_id].category == "membrane" for layer in layers):
            raise RecordError(f"assembly {identifier} has no thermal layers")
        return cls(
            identifier,
            name,
            tuple(reversed(layers)) if orientation == "last_layer_outside" else layers,
            materials,
            user_data(raw.get("user_data"), f"assembly {identifier}"),
        )
