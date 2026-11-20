"""Shading Faces as orphaned honeybee `Shade`s on the Model (Ruby `features/shading/export.rb`).

One `Shade` per record: its identifier, a `Face3D` of the outer loop and holes in world metres, `is_detached`
true as the Grasshopper `HB Shade` component writes it, and the shading component's name as `display_name`, which
PHX groups by into one shading component in WUFI-Passive and METr. No energy or PH value is set: PHX reads none.

The section is optional (`required_for_export = False`) and attaches at `MODEL`: a Shade that fails to translate or
attach is left out with a non-blocking finding, and the canonical model is still written. `attach` checks every
Shade before it adds any. With no record the section adds nothing and reports no field, so a Model without
shading exports exactly as it did before the section existed."""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any, ClassVar

from . import stack
from .contract import JSONValue, RecordError
from .contract.shade_records import ShadeRecord
from .sections import MODEL, Attachment, AttachmentRefused, Inputs, Section

SHADE_SECTION_ID = "ph_composer.shading.export.shades"


@dataclass
class TranslatedShade:
    source: ShadeRecord
    shade: Any
    #: Whether `attach` added it to the Model; a refused Shade is not in the model.
    attached: bool = False


class ShadeSection(Section[ShadeRecord, TranslatedShade]):
    id = SHADE_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedShade
    required_for_export: ClassVar[bool] = False
    attaches = Attachment(MODEL)

    def read(self, raw: Mapping[str, object]) -> ShadeRecord:
        return ShadeRecord.read(raw)

    def translate(self, record: ShadeRecord, inputs: Inputs) -> TranslatedShade:
        """Builds the Shade and serializes it once, so geometry honeybee cannot write costs this record here and
        never the Model's serialization."""
        lb_face = stack.load("ladybug_geometry.geometry3d.face")
        lb_point = stack.load("ladybug_geometry.geometry3d.pointvector")
        hb_shade = stack.load("honeybee.shade")
        try:
            points = [[lb_point.Point3D(*point) for point in loop] for loop in (record.boundary, *record.holes)]
            geometry = lb_face.Face3D(points[0], holes=points[1:] or None)
            shade = hb_shade.Shade(record.id, geometry, is_detached=True)
            shade.display_name = record.display_name
            shade.to_dict()
        except (AssertionError, TypeError, ValueError, ZeroDivisionError) as error:
            raise RecordError(f"shade {record.id} could not be built: {error}") from error
        if not math.isfinite(geometry.area):
            raise RecordError(f"shade {record.id} has no finite area")
        return TranslatedShade(record, shade)

    def attach(self, host: Any, objects: Sequence[TranslatedShade]) -> None:
        """Every Shade is checked against the Model before any is added, so a refused one is never half-added."""
        refused = self.refused(host, objects)
        for item in objects:
            if not any(item is other for other in refused):
                host.add_shade(item.shade)
                item.attached = True
        if refused:
            names = ", ".join(item.shade.identifier for item in refused)
            raise AttachmentRefused(f"the Model cannot take Shade {names}", refused)

    def refused(self, model: Any, objects: Sequence[TranslatedShade]) -> list[TranslatedShade]:
        """The Shades the Model cannot take: one whose identifier it already holds."""
        held = {shade.identifier for shade in model.orphaned_shades}
        return [item for item in objects if item.shade.identifier in held]

    def result_fields(self, objects: Mapping[str, TranslatedShade]) -> Mapping[str, JSONValue]:
        """Each shading component's Face count and area over the attached Shades, and the totals; nothing when no
        Shade was attached."""
        attached = [item for _, item in sorted(objects.items()) if item.attached]
        if not attached:
            return {}
        components: dict[str, list[float]] = {}
        for item in attached:
            components.setdefault(item.shade.display_name, []).append(float(item.shade.area))
        rows: list[JSONValue] = [
            {"display_name": name, "face_count": len(areas), "area_m2": sum(areas)}
            for name, areas in sorted(components.items())
        ]
        return {
            "shading_components": rows,
            "shade_count": len(attached),
            "area_m2": sum(float(item.shade.area) for item in attached),
        }

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """The reloaded Model's orphaned Shades are exactly the reported ones: the same count, and per shading
        component the same Face count and area, each Shade detached."""
        shades = list(model.orphaned_shades)
        count = fields.get("shade_count", 0)
        if len(shades) != count:
            raise ValueError(f"the model holds {len(shades)} orphaned Shades, the run reported {count}")
        if attached := [shade.identifier for shade in shades if not shade.is_detached]:
            raise ValueError(f"orphaned Shades {', '.join(attached)} are not detached")
        held: dict[str, list[float]] = {}
        for shade in shades:
            held.setdefault(shade.display_name, []).append(float(shade.area))
        reported = fields.get("shading_components")
        rows = [row for row in (reported if isinstance(reported, list) else []) if isinstance(row, dict)]
        if sorted(held) != sorted(str(row.get("display_name")) for row in rows):
            raise ValueError("the reloaded shading components do not match the reported ones")
        for row in rows:
            areas = held[str(row.get("display_name"))]
            area = row.get("area_m2")
            if len(areas) != row.get("face_count") or not (
                isinstance(area, (int, float)) and math.isclose(sum(areas), area, rel_tol=1e-9, abs_tol=1e-9)
            ):
                raise ValueError(
                    f"shading component {row.get('display_name')} reads back {len(areas)} Shades of "
                    f"{sum(areas)} m2, the run reported {row.get('face_count')} of {area}"
                )
