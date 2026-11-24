"""Each exported Building Segment's mechanical settings on its honeybee-ph `BldgSegment` (Ruby
`features/mechanical/segment_export.rb`; context/CONTRACTS.md, "Building Segment settings").

One record per exported Building Segment, named by its `bseg_` export identifier, which is the identifier of the
one `BldgSegment` its Rooms share. Ruby has applied the defaults; this sets `set_points.mechanical_cooling`,
`mech_room_temp` and four `summer_ventilation` values on that shared object, attached at `SEGMENT`, and nothing else:
the winter and summer set points are Programs' (`program_sections.SetPointSection`), and honeybee-ph's other seven
summer ventilation values keep their defaults. Conformance reads the six values back from the reloaded model.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from .contract import JSONValue, RecordError, as_number, as_text
from .sections import SEGMENT, Attachment, Inputs, Section

MECHANICAL_SEGMENT_SECTION_ID = "ph_composer.mechanical.export.segments"
#: Ruby's bypass modes and honeybee-ph's `PhVentilationSummerBypassMode` value for each (honeybee_ph/bldg_segment.py),
#: upper case as the enum stores and reports it.
BYPASS_MODES: dict[str, str] = {
    "none": "1-NONE",
    "temperature_controlled": "2-TEMPERATURE CONTROLLED",
    "enthalpy_controlled": "3-ENTHALPY CONTROLLED",
    "always": "4-ALWAYS",
}
#: The three air change rates, each the `SummerVentilation` attribute it sets and whether it may be null.
RATES: dict[str, bool] = {"ventilation_system_ach": True, "daytime_window_ach": False, "nighttime_window_ach": False}


@dataclass(frozen=True)
class MechanicalSegmentRecord:
    identifier: str
    export_identifier: str
    mechanical_cooling: bool
    mech_room_temp_c: float
    #: honeybee-ph's bypass mode value, such as "4-ALWAYS".
    summer_bypass_mode: str
    #: Each rate by its `SummerVentilation` attribute, in RATES' order.
    rates: tuple[tuple[str, float | None], ...]

    def values(self) -> dict[str, JSONValue]:
        """What the section reports, and conformance compares with each reloaded Building Segment."""
        return {
            "mechanical_cooling": self.mechanical_cooling,
            "mech_room_temp_c": self.mech_room_temp_c,
            "summer_bypass_mode": self.summer_bypass_mode,
            **dict(self.rates),
        }


def _rate(raw: Mapping[str, object], field: str, label: str, nullable: bool) -> float | None:
    """A rate the record must carry: null only where honeybee-ph's default is None, and never left out."""
    if field not in raw:
        raise RecordError(f"{label} is missing")
    value = raw[field]
    if value is None and nullable:
        return None
    number = as_number(value, label)
    if number < 0:
        raise RecordError(f"{label} must be 0 or more")
    return number


def segment_values(segment: Any) -> dict[str, JSONValue]:
    """The six values a reloaded `BldgSegment` carries, as a record reports them."""
    ventilation = segment.summer_ventilation
    return {
        "mechanical_cooling": segment.set_points.mechanical_cooling,
        "mech_room_temp_c": segment.mech_room_temp,
        "summer_bypass_mode": str(ventilation.summer_bypass_mode.value),
        **{field: getattr(ventilation, field) for field in RATES},
    }


class MechanicalSegmentSection(Section[MechanicalSegmentRecord, MechanicalSegmentRecord]):
    id = MECHANICAL_SEGMENT_SECTION_ID
    versions = frozenset({1})
    object_type = MechanicalSegmentRecord
    attaches = Attachment(SEGMENT, lambda item: item.export_identifier)

    def read(self, raw: Mapping[str, object]) -> MechanicalSegmentRecord:
        identifier = as_text(raw.get("id"), "mechanical settings id")
        label = f"mechanical settings {identifier}"
        cooling = raw.get("mechanical_cooling")
        if not isinstance(cooling, bool):
            raise RecordError(f"{label} mechanical_cooling must be true or false")
        mode = raw.get("summer_bypass_mode")
        if not isinstance(mode, str) or mode not in BYPASS_MODES:
            raise RecordError(f"{label} summer_bypass_mode must be one of {', '.join(BYPASS_MODES)}")
        return MechanicalSegmentRecord(
            identifier,
            as_text(raw.get("export_identifier"), f"{label} export_identifier"),
            cooling,
            as_number(raw.get("mech_room_temp_c"), f"{label} mech_room_temp_c"),
            BYPASS_MODES[mode],
            tuple((field, _rate(raw, field, f"{label} {field}", nullable)) for field, nullable in RATES.items()),
        )

    def translate(self, record: MechanicalSegmentRecord, inputs: Inputs) -> MechanicalSegmentRecord:
        return record

    def attach(self, host: Any, objects: Sequence[MechanicalSegmentRecord]) -> None:
        """Sets the six values on the one `BldgSegment` the Segment's Rooms share, in place."""
        if len(objects) != 1:
            raise RecordError(f"Building Segment {host.identifier} has more than one mechanical settings record")
        record = objects[0]
        modes = type(host.summer_ventilation.summer_bypass_mode)
        host.set_points.mechanical_cooling = record.mechanical_cooling
        host.mech_room_temp = record.mech_room_temp_c
        host.summer_ventilation.summer_bypass_mode = modes(record.summer_bypass_mode)
        for field, value in record.rates:
            setattr(host.summer_ventilation, field, value)

    def result_fields(self, objects: Mapping[str, MechanicalSegmentRecord]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [
            {"export_identifier": item.export_identifier, **item.values()}
            for _identifier, item in sorted(objects.items())
        ]
        return {"building_segments": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reported Building Segment is in the reloaded model and carries the six values set."""
        segments = {
            segment.identifier: segment for segment in (room.properties.ph.ph_bldg_segment for room in model.rooms)
        }
        rows = fields.get("building_segments")
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                raise ValueError("a mechanical settings row is not an object")
            segment = segments.get(str(row.get("export_identifier")))
            if segment is None:
                raise ValueError(f"Building Segment {row.get('export_identifier')} is not in the model")
            for field, actual in segment_values(segment).items():
                if actual != row.get(field):
                    raise ValueError(
                        f"Building Segment {segment.identifier} {field} is {actual}, not {row.get(field)} as set"
                    )
