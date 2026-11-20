"""Each exported Zone's Infiltration and its Building Segment's wind exposure, from the Segment's airtightness
settings (Ruby `features/programs/export.rb`; context/CONTRACTS.md, "Building Segment settings").

One record per exported Zone of a Segment with settings. Ruby has converted the Segment's test result into the
honeybee Infiltration flow per exterior area that PHX reads back as that result; this section takes it as given
and computes nothing. A record with no flow (no test result) leaves the Room's Infiltration to its Program. The
wind exposure maps to honeybee-ph's `PhWindExposureType` on the one `BldgSegment` the Segment's Rooms share, the
same value from each of them. Conformance reads both back from the reloaded model.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from . import stack
from .contract import JSONValue, RecordError, as_number, as_text
from .sections import ROOM, Attachment, Inputs, Section

AIRTIGHTNESS_SECTION_ID = "ph_composer.programs.export.airtightness"
#: Each wind exposure Ruby offers and honeybee-ph's value for it (honeybee_ph/bldg_segment.py). Ruby's
#: `Programs::Airtightness::WIND_EXPOSURES` lists the same values.
WIND_EXPOSURES: dict[str, str] = {
    "several_sides_no_screening": "1-SEVERAL_SIDES_EXPOSED_NO_SCREENING",
    "several_sides_moderate_screening": "2-SEVERAL_SIDES_EXPOSED_MODERATE_SCREENING",
    "several_sides_high_screening": "3-SEVERAL_SIDES_EXPOSED_HIGH_SCREENING",
    "one_side_no_screening": "4-ONE_SIDE_EXPOSED_NO_SCREENING",
    "one_side_moderate_screening": "5-ONE_SIDE_EXPOSED_MODERATE_SCREENING",
    "user_defined": "6-USER_DEFINED",
    "one_side_high_screening": "7-ONE_SIDE_EXPOSED_HIGH_SCREENING",
}


@dataclass(frozen=True)
class AirtightnessRecord:
    zone_id: str
    export_identifier: str
    #: honeybee-ph's wind exposure value.
    wind_exposure: str
    #: m³/s per m² of exposed area at 4 Pa, or None for no test result.
    flow_per_exterior_area: float | None


def _infiltration_identifier(zone_id: str) -> str:
    return f"{zone_id}_airtightness"


class AirtightnessSection(Section[AirtightnessRecord, AirtightnessRecord]):
    id = AIRTIGHTNESS_SECTION_ID
    versions = frozenset({1})
    object_type = AirtightnessRecord
    attaches = Attachment(ROOM, lambda item: item.zone_id)

    def read(self, raw: Mapping[str, object]) -> AirtightnessRecord:
        zone_id = as_text(raw.get("id"), "airtightness id")
        export_identifier = as_text(raw.get("export_identifier"), f"airtightness {zone_id} export_identifier")
        wind = raw.get("wind_exposure")
        if not isinstance(wind, str) or wind not in WIND_EXPOSURES:
            raise RecordError(f"airtightness {zone_id} wind_exposure must be one of {', '.join(WIND_EXPOSURES)}")
        flow_value = raw.get("flow_per_exterior_area")
        flow = None if flow_value is None else as_number(flow_value, f"airtightness {zone_id} flow_per_exterior_area")
        if flow is not None and not flow > 0:
            raise RecordError(f"airtightness {zone_id} flow_per_exterior_area must be greater than 0")
        return AirtightnessRecord(zone_id, export_identifier, WIND_EXPOSURES[wind], flow)

    def translate(self, record: AirtightnessRecord, inputs: Inputs) -> AirtightnessRecord:
        return record

    def attach(self, host: Any, objects: Sequence[AirtightnessRecord]) -> None:
        """Sets the Room's Infiltration when the Segment has a test result, and the shared `BldgSegment`'s wind
        exposure."""
        if len(objects) != 1:
            raise RecordError(f"Room {host.identifier} has more than one airtightness record")
        record = objects[0]
        segment = host.properties.ph.ph_bldg_segment
        if segment.identifier != record.export_identifier:
            raise RecordError(f"Room {host.identifier} is not in Building Segment {record.export_identifier}")
        segment.wind_exposure_type = stack.load("honeybee_ph.bldg_segment").PhWindExposureType(record.wind_exposure)
        if record.flow_per_exterior_area is not None:
            infiltration = stack.load("honeybee_energy.load.infiltration").Infiltration
            always_on = stack.load("honeybee_energy.lib.schedules").always_on
            host.properties.energy.infiltration = infiltration(
                _infiltration_identifier(record.zone_id), record.flow_per_exterior_area, always_on
            )

    def result_fields(self, objects: Mapping[str, AirtightnessRecord]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [
            {
                "zone_id": item.zone_id,
                "export_identifier": item.export_identifier,
                "wind_exposure": item.wind_exposure,
                "flow_per_exterior_area": item.flow_per_exterior_area,
            }
            for _identifier, item in sorted(objects.items())
        ]
        return {"airtightness": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reported Room is in the reloaded model with its Segment's wind exposure and, with a test result,
        the Infiltration flow set."""
        rooms = {room.identifier: room for room in model.rooms}
        rows = fields.get("airtightness")
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                raise ValueError("an airtightness row is not an object")
            room = rooms.get(str(row.get("zone_id")))
            if room is None:
                raise ValueError(f"Room {row.get('zone_id')} is not in the model")
            wind = str(room.properties.ph.ph_bldg_segment.wind_exposure_type.value)
            if wind != row.get("wind_exposure"):
                raise ValueError(f"Room {room.identifier} wind exposure is {wind}, not {row.get('wind_exposure')}")
            flow = row.get("flow_per_exterior_area")
            if flow is None:
                continue
            infiltration = room.properties.energy.infiltration
            if infiltration is None or infiltration.identifier != _infiltration_identifier(room.identifier):
                raise ValueError(f"Room {room.identifier} lost its airtightness Infiltration")
            actual = infiltration.flow_per_exterior_area
            if not isinstance(flow, (int, float)) or abs(actual - flow) > 1e-12:
                raise ValueError(f"Room {room.identifier} infiltration is {actual}, not {flow}")
