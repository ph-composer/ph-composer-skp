"""Thermal bridges, translated through the pinned honeybee-ph stack and added to their Zone's Building-Segment.

One honeybee-ph `PhThermalBridge` per run record: a `LineSegment3D` for one Edge, otherwise a `Polyline3D` (a
closed run repeats its first point), with the type's psi-value and group and the assignment's quantity;
`fRsi_value` and `is_interior_pipe` keep their defaults. Its identifier is the run's, and its `user_data`
carries only the type id under PH-Composer's reserved key: a run joins many Edges, so no one Edge's own
user_data stands for it.

The section is optional (`required_for_export = False`): a run that fails to translate or attach is left out
with a non-blocking finding, and the canonical model is still written. Rooms of one Building-Segment share one
`BldgSegment` (the Zones section's attach), so every run of the segment lands on that one object."""

from __future__ import annotations

import math
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any, ClassVar

from . import stack
from .contract import JSONValue, RecordError
from .contract.thermal_bridge_records import ThermalBridgeRecord
from .model_sections import ZONE_SECTION_ID, TranslatedZone
from .sections import ROOM, Attachment, AttachmentRefused, Inputs, Requirement, Section

THERMAL_BRIDGE_SECTION_ID = "ph_composer.thermal_bridges.export.thermal_bridges"
ZONES = Requirement(ZONE_SECTION_ID, TranslatedZone)
#: The one user_data key the section writes, declared by the Ruby contributor's `user_data_keys`.
TYPE_ID_KEY = "thermal_bridge_type_id"


@dataclass
class TranslatedThermalBridge:
    source: ThermalBridgeRecord
    bridge: Any
    #: Whether `attach` added it to its Building-Segment; a refused run is not in the model.
    attached: bool = False

    @property
    def zone_id(self) -> str:
        return self.source.zone_id


class ThermalBridgeSection(Section[ThermalBridgeRecord, TranslatedThermalBridge]):
    id = THERMAL_BRIDGE_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedThermalBridge
    requires = (ZONES,)
    required_for_export: ClassVar[bool] = False
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> ThermalBridgeRecord:
        return ThermalBridgeRecord.read(raw)

    def translate(self, record: ThermalBridgeRecord, inputs: Inputs) -> TranslatedThermalBridge:
        inputs.get(ZONES, record.zone_id)
        thermal_bridge = stack.load("honeybee_energy_ph.construction.thermal_bridge")
        try:
            bridge = thermal_bridge.PhThermalBridge(record.id, geometry(record))
            bridge.display_name = record.display_name
            bridge.psi_value = record.psi_w_mk
            bridge.group_type = record.group
            bridge.quantity = record.quantity
            bridge.user_data = {"ph_composer": {TYPE_ID_KEY: record.type_id}}
        except (AssertionError, ValueError) as error:
            raise RecordError(f"thermal bridge {record.id} could not be built: {error}") from error
        return TranslatedThermalBridge(record, bridge)

    def attach(self, host: Any, objects: Sequence[TranslatedThermalBridge]) -> None:
        """Every run is checked against the Room's Building-Segment before any is added, so a refused run is
        never left half-added."""
        segment = host.properties.ph.ph_bldg_segment
        refused = self.refused(segment, objects)
        for item in objects:
            if item not in refused:
                segment.add_new_thermal_bridge(item.bridge)
                item.attached = True
        if refused:
            names = ", ".join(item.bridge.identifier for item in refused)
            raise AttachmentRefused(
                f"Building-Segment {segment.identifier} cannot take thermal bridge {names}", refused
            )

    def refused(self, segment: Any, objects: Sequence[TranslatedThermalBridge]) -> list[TranslatedThermalBridge]:
        """The runs a Building-Segment cannot take: one whose identifier it already holds."""
        return [item for item in objects if item.bridge.identifier in segment.thermal_bridges]

    def result_fields(self, objects: Mapping[str, TranslatedThermalBridge]) -> Mapping[str, JSONValue]:
        runs: list[JSONValue] = [run_row(item) for _, item in sorted(objects.items()) if item.attached]
        return {"thermal_bridge_runs": runs}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Each reported run is on its Zone's Building-Segment in the reloaded model with the length, psi-value,
        group and quantity the run reported, and the model holds no thermal bridge the run did not report."""
        segments: dict[str, Any] = {}
        room_segment: dict[str, str] = {}
        for room in model.rooms:
            segment = room.properties.ph.ph_bldg_segment
            segments.setdefault(segment.identifier, segment)
            room_segment[room.identifier] = segment.identifier
        reported = fields.get("thermal_bridge_runs")
        rows = [row for row in (reported if isinstance(reported, list) else []) if isinstance(row, dict)]
        held = {identifier for segment in segments.values() for identifier in segment.thermal_bridges}
        if extra := sorted(held - {str(row.get("identifier")) for row in rows}):
            raise ValueError(f"the model holds thermal bridges the run did not report: {', '.join(extra)}")
        for row in rows:
            identifier = str(row.get("identifier"))
            segment_id = room_segment.get(str(row.get("zone_id")))
            bridge = segments[segment_id].thermal_bridges.get(identifier) if segment_id else None
            if bridge is None:
                raise ValueError(f"thermal bridge {identifier} is not on its Zone's Building-Segment")
            expected = (row.get("length_m"), row.get("psi_w_mk"), row.get("quantity"))
            actual = (float(bridge.length), float(bridge.psi_value), float(bridge.quantity))
            if not all(
                isinstance(value, (int, float)) and math.isclose(value, read, rel_tol=1e-9, abs_tol=1e-9)
                for value, read in zip(expected, actual, strict=True)
            ):
                raise ValueError(f"thermal bridge {identifier} reads back {actual}, the run reported {expected}")
            if str(bridge.group_type.value).upper() != str(row.get("group")).upper():
                raise ValueError(f"thermal bridge {identifier} group is {bridge.group_type.value}")


def geometry(record: ThermalBridgeRecord) -> Any:
    lb_point = stack.load("ladybug_geometry.geometry3d.pointvector")
    lb_polyline = stack.load("ladybug_geometry.geometry3d.polyline")
    points = [lb_point.Point3D(*point) for point in record.points_m]
    if len(points) == 2:
        return lb_polyline.LineSegment3D.from_end_points(*points)
    return lb_polyline.Polyline3D(points)


def run_row(item: TranslatedThermalBridge) -> dict[str, JSONValue]:
    """One exported run as the report lists it, read from the built object: lengths in metres, psi in W/mK and
    psi times length times quantity in W/K."""
    source, bridge = item.source, item.bridge
    length = float(bridge.length)
    return {
        "identifier": source.id,
        "display_name": source.display_name,
        "zone_id": source.zone_id,
        "type_id": source.type_id,
        "type_name": source.type_name,
        "group": source.group,
        "psi_w_mk": float(bridge.psi_value),
        "quantity": float(bridge.quantity),
        "length_m": length,
        "heat_loss_w_k": float(bridge.psi_value) * length * float(bridge.quantity),
    }
