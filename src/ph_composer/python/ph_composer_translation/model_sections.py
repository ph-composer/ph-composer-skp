"""Zone and Face sections for the canonical HBJSON model.

Faces translate first to detached typed specifications. Zones declare that dependency and create each
Room once; the Zones attachment to the Model resolves Surface references only after every emitted Room
exists. Nothing here knows what else the model assembly attaches to these Rooms and Faces.
The module imports no Ladybug Tools package until translation begins.
"""

from __future__ import annotations

import hashlib
import re
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any

from . import stack
from .constructions import CONSTRUCTIONS
from .contract import JSONObject, JSONValue, RecordError, as_number, as_text, user_data, with_user_data
from .result import Finding
from .sections import MODEL, Attachment, AttachmentRefused, DependencyUnavailable, Inputs, Requirement, Section

FACE_SECTION_ID = "ph_composer.zones.faces.export.faces"
ZONE_SECTION_ID = "ph_composer.zones.export.zones"


@dataclass(frozen=True)
class FaceOmission:
    code: str
    reason: str
    area_m2: float
    zone_id: str

    def row(self, identifier: str) -> dict[str, JSONValue]:
        return {
            "face_id": identifier,
            "zone_id": self.zone_id,
            "code": self.code,
            "reason": self.reason,
            "area_m2": self.area_m2,
        }


@dataclass(frozen=True)
class FaceSpec:
    identifier: str
    zone_id: str
    face_type: str
    boundary_condition: str | None
    assembly_id: str | None
    loops_m: tuple[tuple[tuple[float, float, float], ...], ...]
    adjacency: Mapping[str, object] | None
    area_m2: float
    omission: FaceOmission | None
    user_data: JSONObject = field(default_factory=dict)
    # The counterpart side of a Surface pair: it names the pair's Assembly and takes its layers reversed.
    assembly_reversed: bool = False


@dataclass(frozen=True)
class ZoneRecord:
    identifier: str
    name: str
    building_segment: str
    level: str | None
    face_ids: tuple[str, ...]
    building_segment_id: str | None = None
    building_segment_export_identifier: str | None = None
    user_data: JSONObject = field(default_factory=dict)


@dataclass
class TranslatedZone:
    source: ZoneRecord
    room: Any
    faces: dict[str, Any]
    specifications: dict[str, FaceSpec]


FACES = Requirement(FACE_SECTION_ID, FaceSpec)


class FaceSection(Section[FaceSpec, FaceSpec]):
    id = FACE_SECTION_ID
    versions = frozenset({1})
    object_type = FaceSpec

    def read(self, raw: Mapping[str, object]) -> FaceSpec:
        identifier = as_text(raw.get("id"), "face id")
        zone_id = as_text(raw.get("zone_id"), f"face {identifier} zone_id")
        face_type = as_text(raw.get("face_type"), f"face {identifier} face_type")
        omission = _read_omission(raw.get("omission"), identifier, zone_id)
        boundary_value = raw.get("boundary_condition")
        boundary = (
            None
            if omission and boundary_value is None
            else as_text(boundary_value, f"face {identifier} boundary_condition")
        )
        if omission:
            try:
                _face_type_name(face_type)
                if boundary is not None and boundary != "Surface":
                    _boundary_name(boundary)
            except KeyError as error:
                raise RecordError(
                    f"face {identifier} has invalid classification independently of its omission"
                ) from error
        assembly = raw.get("assembly_id")
        if assembly is not None and not isinstance(assembly, str):
            raise RecordError(f"face {identifier} assembly_id must be text or null")
        reversed_assembly = raw.get("assembly_reversed", False)
        if not isinstance(reversed_assembly, bool):
            raise RecordError(f"face {identifier} assembly_reversed must be true or false")
        if reversed_assembly and (assembly is None or boundary != "Surface"):
            raise RecordError(f"face {identifier} names a reversed Assembly without a Surface Assembly")
        geometry = raw.get("geometry")
        if not isinstance(geometry, Mapping):
            raise RecordError(f"face {identifier} geometry must be an object")
        loops = self._loops(geometry.get("loops_m"), identifier)
        adjacency = raw.get("adjacency")
        if adjacency is not None and not isinstance(adjacency, Mapping):
            raise RecordError(f"face {identifier} adjacency must be an object")
        area = as_number(geometry.get("area_m2"), f"face {identifier} area_m2")
        if area < 0:
            raise RecordError(f"face {identifier} area_m2 must not be negative")
        return FaceSpec(
            identifier,
            zone_id,
            face_type,
            boundary,
            assembly,
            loops,
            adjacency,
            area,
            omission,
            user_data(raw.get("user_data"), f"face {identifier}"),
            reversed_assembly,
        )

    def translate(self, record: FaceSpec, inputs: Inputs) -> FaceSpec:
        return record

    def findings(self, objects: Mapping[str, FaceSpec]) -> Sequence[Finding]:
        return [
            Finding(
                omission.code,
                self.id,
                identifier,
                f"Face {identifier}, Zone {omission.zone_id}, {omission.area_m2:g} m²: {omission.reason}",
                False,
            )
            for identifier, omission in _omissions(objects).items()
        ]

    def result_fields(self, objects: Mapping[str, FaceSpec]) -> Mapping[str, JSONValue]:
        rows: list[JSONValue] = [omission.row(identifier) for identifier, omission in _omissions(objects).items()]
        return {"surface_omissions": rows}

    @staticmethod
    def _loops(value: object, identifier: str) -> tuple[tuple[tuple[float, float, float], ...], ...]:
        if isinstance(value, (str, bytes)) or not isinstance(value, Sequence) or not value:
            raise RecordError(f"face {identifier} loops_m must be a non-empty list")
        loops: list[tuple[tuple[float, float, float], ...]] = []
        for loop in value:
            if isinstance(loop, (str, bytes)) or not isinstance(loop, Sequence) or len(loop) < 3:
                raise RecordError(f"face {identifier} loop must have at least three points")
            points: list[tuple[float, float, float]] = []
            for point in loop:
                if isinstance(point, (str, bytes)) or not isinstance(point, Sequence) or len(point) != 3:
                    raise RecordError(f"face {identifier} point must have three coordinates")
                points.append(
                    (
                        as_number(point[0], f"face {identifier} coordinate"),
                        as_number(point[1], f"face {identifier} coordinate"),
                        as_number(point[2], f"face {identifier} coordinate"),
                    )
                )
            loops.append(tuple(points))
        return tuple(loops)


class ZoneSection(Section[ZoneRecord, TranslatedZone]):
    id = ZONE_SECTION_ID
    versions = frozenset({1, 2})
    object_type = TranslatedZone
    requires = (FACES, CONSTRUCTIONS)
    attaches = Attachment(MODEL)

    def read(self, raw: Mapping[str, object]) -> ZoneRecord:
        identifier = as_text(raw.get("id"), "zone id")
        name = as_text(raw.get("name"), f"zone {identifier} name")
        segment = as_text(raw.get("building_segment"), f"zone {identifier} building_segment")
        segment_id = None
        export_identifier = None
        if "building_segment_id" in raw or "building_segment_export_identifier" in raw:
            segment_id = as_text(raw.get("building_segment_id"), f"zone {identifier} building_segment_id")
            export_identifier = as_text(
                raw.get("building_segment_export_identifier"), f"zone {identifier} building_segment_export_identifier"
            )
            if len(export_identifier) > 100 or re.fullmatch(r"bseg_[A-Za-z0-9_]+", export_identifier) is None:
                raise RecordError(
                    f"zone {identifier} building_segment_export_identifier must be a valid bseg_ identifier"
                )
        level = raw.get("level")
        if level is not None and not isinstance(level, str):
            raise RecordError(f"zone {identifier} level must be text or null")
        face_ids = raw.get("face_ids")
        if isinstance(face_ids, (str, bytes)) or not isinstance(face_ids, Sequence) or not face_ids:
            raise RecordError(f"zone {identifier} face_ids must be a non-empty list")
        return ZoneRecord(
            identifier,
            name,
            segment,
            level,
            tuple(as_text(value, "face id") for value in face_ids),
            segment_id,
            export_identifier,
            user_data(raw.get("user_data"), f"zone {identifier}"),
        )

    def translate(self, record: ZoneRecord, inputs: Inputs) -> TranslatedZone:
        hb_face = stack.load("honeybee.face")
        hb_room = stack.load("honeybee.room")
        hb_types = stack.load("honeybee.facetype")
        hb_boundaries = stack.load("honeybee.boundarycondition")
        lb_face = stack.load("ladybug_geometry.geometry3d.face")
        lb_point = stack.load("ladybug_geometry.geometry3d.pointvector")
        stack.load("honeybee_energy._extend_honeybee")
        stack.load("honeybee_ph")

        faces: dict[str, Any] = {}
        specifications: dict[str, FaceSpec] = {}
        for face_id in record.face_ids:
            specification = inputs.get(FACES, face_id)
            if specification.zone_id != record.identifier:
                raise RecordError(f"face {face_id} names Zone {specification.zone_id}, not {record.identifier}")
            specifications[face_id] = specification
            omission = specification.omission
            if omission is None and specification.boundary_condition == "Surface":
                counterpart = inputs.get(FACES, _counterpart_id(specification))
                if counterpart.omission:
                    omission = _counterpart_omission(specification, counterpart)
            if omission:
                continue
            if specification.boundary_condition == "Surface":
                _validate_surface(specification, inputs)
            construction = _construction(specification, inputs, face_id)
            points = [[lb_point.Point3D(*point) for point in loop] for loop in specification.loops_m]
            geometry = lb_face.Face3D(points[0], holes=points[1:] or None)
            try:
                face_type = getattr(hb_types.face_types, _face_type_name(specification.face_type))
                # A Surface boundary needs its counterpart's Room, so `attach` sets it once every Room exists.
                boundary = hb_boundaries.boundary_conditions.outdoors
                if specification.boundary_condition != "Surface":
                    boundary = getattr(
                        hb_boundaries.boundary_conditions, _boundary_name(specification.boundary_condition)
                    )
                face = hb_face.Face(specification.identifier, geometry, face_type, boundary)
                if specification.user_data:
                    face.user_data = dict(specification.user_data)
                # An unassigned interior Face keeps honeybee's default interior construction; `attach` refuses
                # one whose counterpart is in another Building-Segment.
                if construction is not None:
                    face.properties.energy.construction = construction
            except (AssertionError, AttributeError, KeyError, ValueError) as error:
                raise RecordError(f"face {face_id} could not be built: {error}") from error
            faces[face_id] = face
        if not faces:
            # honeybee writes a Room with no Faces but cannot read it back, so the diagnostic model
            # would not reload. The Zone is refused instead; its omitted Faces report themselves.
            raise RecordError(f"Zone {record.identifier} has no Faces left to export: every Face is omitted")
        try:
            room = hb_room.Room(record.identifier, list(faces.values()))
        except (AssertionError, ValueError) as error:
            raise RecordError(f"Zone {record.identifier} could not be built: {error}") from error
        room.display_name = record.name
        room.user_data = with_user_data(
            {"ph_composer": {"level": record.level, "building_segment": record.building_segment}}, record.user_data
        )
        return TranslatedZone(record, room, faces, specifications)

    def attach(self, host: Any, objects: Sequence[TranslatedZone]) -> None:
        """Puts every Room in the Model, after giving Rooms of one building segment one shared segment and
        pairing each Surface Face with its counterpart."""
        # Validate the complete inventory before sharing any Segment: the PH stack serializes
        # model Segments by export identifier, so a collision would silently collapse categories.
        identities: dict[tuple[str, str], tuple[str, str]] = {}
        export_owners: dict[str, tuple[str, str]] = {}
        for zone in objects:
            source = zone.source
            identity = (
                ("managed", source.building_segment_id)
                if source.building_segment_id
                else ("legacy", source.building_segment)
            )
            export_identifier = source.building_segment_export_identifier or _segment_identifier(
                source.building_segment
            )
            definition = (export_identifier, source.building_segment)
            if identity in identities and identities[identity] != definition:
                raise RecordError(f"Building Segment {identity[1]} has conflicting export identifiers or names")
            if export_identifier in export_owners and export_owners[export_identifier] != identity:
                raise RecordError(
                    f"Building Segment export identifier {export_identifier} belongs to distinct categories"
                )
            identities[identity] = definition
            export_owners[export_identifier] = identity
        segments: dict[tuple[str, str], Any] = {}
        for zone in objects:
            source = zone.source
            identity = (
                ("managed", source.building_segment_id)
                if source.building_segment_id
                else ("legacy", source.building_segment)
            )
            ph = zone.room.properties.ph
            segment = segments.setdefault(identity, ph.ph_bldg_segment)
            segment.identifier, segment.display_name = identities[identity]
            ph.ph_bldg_segment = segment
        emitted = {identifier: face for zone in objects for identifier, face in zone.faces.items()}
        specifications = {identifier: spec for zone in objects for identifier, spec in zone.specifications.items()}
        omissions = _omissions(specifications)
        paired: set[str] = set()
        unpaired: list[TranslatedZone] = []
        for zone in objects:
            for identifier, specification in zone.specifications.items():
                # A Face `translate` left out, its counterpart omitted, needs no pairing even when that
                # counterpart's Zone was refused and is absent from these specifications.
                if (
                    identifier in omissions
                    or identifier not in emitted
                    or specification.boundary_condition != "Surface"
                    or identifier in paired
                ):
                    continue
                counterpart_id = _counterpart_id(specification)
                counterpart = specifications.get(counterpart_id)
                # A counterpart missing here belongs to a Zone that did not translate, which says so itself.
                if counterpart is None or _counterpart_id(counterpart) != identifier or counterpart_id not in emitted:
                    unpaired.append(zone)
                    continue
                emitted[identifier].set_adjacency(emitted[counterpart_id])
                paired.update((identifier, counterpart_id))
        refused = _unmatched_pairs(objects, specifications, paired)
        host.add_rooms([zone.room for zone in objects if zone.source.identifier not in refused])
        if refused:
            reasons = "; ".join(sorted(set(refused.values())))
            raise AttachmentRefused(reasons, [zone for zone in objects if zone.source.identifier in refused])
        if unpaired:
            names = ", ".join(sorted({zone.source.identifier for zone in unpaired}))
            raise AttachmentRefused(f"Surface Faces of Zone {names} have no emitted reciprocal counterpart", unpaired)

    def result_fields(self, objects: Mapping[str, TranslatedZone]) -> Mapping[str, JSONValue]:
        usage: dict[str, _ConstructionUsage] = {}
        for zone in objects.values():
            for identifier in zone.faces:
                specification = zone.specifications[identifier]
                assembly_id = specification.assembly_id
                if assembly_id is None:
                    continue
                row = usage.setdefault(assembly_id, _ConstructionUsage())
                row.face_count += 1
                row.gross_area_m2 += specification.area_m2
        return {"construction_usage": [usage[assembly_id].row(assembly_id) for assembly_id in sorted(usage)]}


@dataclass
class _ConstructionUsage:
    """One Assembly's running Face count and gross area while result fields are summed."""

    face_count: int = 0
    gross_area_m2: float = 0.0

    def row(self, assembly_id: str) -> JSONValue:
        return {"assembly_id": assembly_id, "face_count": self.face_count, "gross_area_m2": self.gross_area_m2}


def _read_omission(value: object, identifier: str, zone_id: str) -> FaceOmission | None:
    if value is None:
        return None
    if not isinstance(value, Mapping):
        raise RecordError(f"face {identifier} omission must be an object")
    code = as_text(value.get("code"), f"face {identifier} omission code")
    reason = as_text(value.get("reason"), f"face {identifier} omission reason")
    area = as_number(value.get("area_m2"), f"face {identifier} omission area_m2")
    owner = as_text(value.get("zone_id"), f"face {identifier} omission zone_id")
    if area < 0 or owner != zone_id:
        raise RecordError(f"face {identifier} omission has an invalid area or Zone")
    return FaceOmission(code, reason, area, owner)


def _counterpart_omission(specification: FaceSpec, counterpart: FaceSpec) -> FaceOmission:
    return FaceOmission(
        "adjacency.counterpart_omitted",
        f"Surface counterpart {counterpart.identifier} is explicitly omitted",
        specification.area_m2,
        specification.zone_id,
    )


def _omissions(specifications: Mapping[str, FaceSpec]) -> dict[str, FaceOmission]:
    omissions: dict[str, FaceOmission] = {}
    for identifier, specification in specifications.items():
        omission = specification.omission
        counterpart = specifications.get(_counterpart_id(specification))
        if omission is None and specification.boundary_condition == "Surface" and counterpart and counterpart.omission:
            omission = _counterpart_omission(specification, counterpart)
        if omission:
            omissions[identifier] = omission
    return omissions


def _face_type_name(value: str) -> str:
    return {"Wall": "wall", "RoofCeiling": "roof_ceiling", "Floor": "floor", "AirBoundary": "air_boundary"}[value]


def _boundary_name(value: str | None) -> str:
    if value is None:
        raise KeyError("no boundary condition")
    return {"Outdoors": "outdoors", "Ground": "ground", "Adiabatic": "adiabatic"}[value]


def _counterpart_id(specification: FaceSpec) -> str:
    if not specification.adjacency:
        return ""
    counterpart = specification.adjacency.get("counterpart")
    if not isinstance(counterpart, Mapping):
        return ""
    value = counterpart.get("entity_id")
    return value if isinstance(value, str) else ""


def _validate_surface(specification: FaceSpec, inputs: Inputs) -> None:
    counterpart_id = _counterpart_id(specification)
    if not counterpart_id:
        raise RecordError(f"Surface face {specification.identifier} has no counterpart id")
    counterpart = inputs.get(FACES, counterpart_id)
    if counterpart.boundary_condition != "Surface" or _counterpart_id(counterpart) != specification.identifier:
        raise RecordError(f"Surface face {specification.identifier} has no reciprocal counterpart")
    endpoint = specification.adjacency.get("counterpart") if specification.adjacency else None
    counterpart_zone = endpoint.get("zone_id") if isinstance(endpoint, Mapping) else None
    if counterpart.zone_id != counterpart_zone:
        raise RecordError(f"Surface face {specification.identifier} counterpart names the wrong Zone")


def _construction(specification: FaceSpec, inputs: Inputs, face_id: str) -> Any:
    """The construction a Face carries, or None for an unassigned Surface Face."""
    if specification.assembly_id is None and specification.boundary_condition == "Surface":
        return None
    try:
        translated = inputs.get(CONSTRUCTIONS, specification.assembly_id or "(unassigned)")
    except DependencyUnavailable as error:
        raise DependencyUnavailable(error.section, error.object_id, f"Face {face_id}") from error
    if not specification.assembly_reversed:
        return translated.construction
    if translated.reversed_construction is None:
        raise RecordError(f"face {face_id} Assembly {specification.assembly_id} has no reversed construction")
    return translated.reversed_construction


def _unmatched_pairs(
    objects: Sequence[TranslatedZone], specifications: Mapping[str, FaceSpec], paired: set[str]
) -> dict[str, str]:
    """Zones whose Surface pair breaks the interior pair rule, each with the reason, keyed by Zone identifier
    (context/CONTRACTS.md, "Interior pair Assembly"). A pair is unassigned within one Building-Segment, or
    one Assembly reversed on exactly one side, which gives honeybee the mirrored layers its check requires."""
    owners = {identifier: zone for zone in objects for identifier in zone.faces}
    refused: dict[str, str] = {}
    for identifier in sorted(paired):
        mine = specifications[identifier]
        counterpart_id = _counterpart_id(mine)
        if identifier > counterpart_id:
            continue
        theirs = specifications[counterpart_id]
        here, there = owners[identifier], owners[counterpart_id]
        reason = None
        if mine.assembly_id is None and theirs.assembly_id is None:
            if _segment_identity(here.source) != _segment_identity(there.source):
                reason = (
                    f"Surface pair {identifier} and {counterpart_id} crosses Building-Segments and needs an Assembly"
                )
        elif mine.assembly_id != theirs.assembly_id or mine.assembly_reversed == theirs.assembly_reversed:
            reason = (
                f"Surface pair {identifier} and {counterpart_id} needs one Assembly, reversed on one side; "
                "assign the Assembly again to one side"
            )
        if reason:
            refused[here.source.identifier] = refused[there.source.identifier] = reason
    return refused


def _segment_identity(zone: ZoneRecord) -> tuple[str, str]:
    return ("managed", zone.building_segment_id) if zone.building_segment_id else ("legacy", zone.building_segment)


def _segment_identifier(name: str) -> str:
    return "bseg_" + hashlib.sha256(name.encode("utf-8")).hexdigest()[:16]
