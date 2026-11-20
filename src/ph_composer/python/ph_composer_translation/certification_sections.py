"""Each exported Building Segment's Phius certification settings on its honeybee-ph `BldgSegment` (Ruby
`features/certification/export.rb`; context/CONTRACTS.md, "Building Segment settings").

One record per exported Building Segment, named by its `bseg_` export identifier, which is the identifier of the
one `BldgSegment` its Rooms share. Ruby has applied the defaults; this maps each value to honeybee-ph's
`PhiusCertification` enum and sets it on that shared object, attached at `SEGMENT`, so the `Site` the Site
section set is kept. Conformance reads the five values back from the reloaded model.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from .contract import JSONValue, RecordError, as_text
from .sections import SEGMENT, Attachment, Inputs, Section

CERTIFICATION_SECTION_ID = "ph_composer.certification.export.segments"
#: Each record field, the `PhiusCertification` attribute it sets, and honeybee-ph's value for each of its values
#: (honeybee_ph/phius.py). Ruby's `Certification::Segment::CHOICES` lists the same values.
FIELDS: dict[str, tuple[str, dict[str, str]]] = {
    "category": (
        "building_category_type",
        {"residential": "1-RESIDENTIAL BUILDING", "non_residential": "2-NON-RESIDENTIAL BUILDING"},
    ),
    "program": (
        "certification_program",
        {
            "phius_2021_core": "7-PHIUS 2021 CORE",
            "phius_2021_zero": "8-PHIUS 2021 ZERO",
            "phius_2018_core": "5-PHIUS 2018 CORE",
            "phius_2018_zero": "6-PHIUS 2018 ZERO",
            "phius_2018": "3-PHIUS 2018",
            "phius_2015": "2-PHIUS 2015",
        },
    ),
    "use": (
        "building_use_type",
        {
            "residential": "1-RESIDENTIAL",
            "office_administrative": "4-OFFICE/ADMINISTRATIVE BUILDING",
            "school": "5-SCHOOL",
            "other": "6-OTHER",
            "undefined_unfinished": "7-UNDEFINED/UNFINISHED",
        },
    ),
    "status": (
        "building_status",
        {"in_planning": "1-IN_PLANNING", "under_construction": "2-UNDER_CONSTRUCTION", "complete": "3-COMPLETE"},
    ),
    "type": (
        "building_type",
        {"new_construction": "1-NEW_CONSTRUCTION", "retrofit": "2-RETROFIT", "mixed": "3-MIXED"},
    ),
}


@dataclass(frozen=True)
class CertificationRecord:
    identifier: str
    export_identifier: str
    #: Each field's honeybee-ph value, by record field.
    values: tuple[tuple[str, str], ...]


def _value(enum: Any) -> str:
    """The value of honeybee-ph's enum as its `to_dict` stores it."""
    return str(enum.value)


class CertificationSection(Section[CertificationRecord, CertificationRecord]):
    id = CERTIFICATION_SECTION_ID
    versions = frozenset({1})
    object_type = CertificationRecord
    attaches = Attachment(SEGMENT, lambda item: item.export_identifier)

    def read(self, raw: Mapping[str, object]) -> CertificationRecord:
        identifier = as_text(raw.get("id"), "certification id")
        export_identifier = as_text(raw.get("export_identifier"), f"certification {identifier} export_identifier")
        values = []
        for field, (_attribute, choices) in FIELDS.items():
            value = raw.get(field)
            if not isinstance(value, str) or value not in choices:
                raise RecordError(f"certification {identifier} {field} must be one of {', '.join(choices)}")
            values.append((field, choices[value]))
        return CertificationRecord(identifier, export_identifier, tuple(values))

    def translate(self, record: CertificationRecord, inputs: Inputs) -> CertificationRecord:
        return record

    def attach(self, host: Any, objects: Sequence[CertificationRecord]) -> None:
        """Sets the five values on the `PhiusCertification` of the one `BldgSegment` the Segment's Rooms share."""
        if len(objects) != 1:
            raise RecordError(f"Building Segment {host.identifier} has more than one certification record")
        certification = host.phius_certification
        for field, value in objects[0].values:
            setattr(certification, FIELDS[field][0], value)

    def result_fields(self, objects: Mapping[str, CertificationRecord]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [
            {"export_identifier": item.export_identifier, **dict(item.values)}
            for _identifier, item in sorted(objects.items())
        ]
        return {"building_segments": rows}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reported Building Segment is in the reloaded model and carries the five values set."""
        segments = {
            segment.identifier: segment for segment in (room.properties.ph.ph_bldg_segment for room in model.rooms)
        }
        rows = fields.get("building_segments")
        for row in rows if isinstance(rows, list) else []:
            if not isinstance(row, dict):
                raise ValueError("a certification row is not an object")
            segment = segments.get(str(row.get("export_identifier")))
            if segment is None:
                raise ValueError(f"Building Segment {row.get('export_identifier')} is not in the model")
            for field, (attribute, _choices) in FIELDS.items():
                actual = _value(getattr(segment.phius_certification, attribute))
                if actual != row.get(field):
                    raise ValueError(
                        f"Building Segment {segment.identifier} {field} is {actual}, not {row.get(field)} as set"
                    )
