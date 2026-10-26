"""Builds the one Honeybee Model from the sections' attachments (context/CONTRACTS.md, "Translation
sections and artifacts").

Honeybee nests Apertures in Faces, Faces in Rooms and Rooms in the Model. A section whose objects
belong inside another declares `attaches = Attachment(host, key)`; the assembly attaches each host
level in turn, outermost first, so a Face exists before anything is attached to it. Each host's
objects are attached in one call, in id order, so the attaching section can check them together.
The assembly names no section and knows no feature: it only follows the declarations.

The canonical model is serialized when it holds a Room and no required section's attachment was refused, even
when other findings keep it from being published, so a run that fails still shows what did translate. A
required section's refusal withholds it, because the Model would then not hold what the sections said. A
section with `required_for_export = False` may be refused: its refused objects are left out of the Model with
a non-blocking finding each, and the Model holds the rest. Its accounting counts what the Model holds, not what
any section reports.
"""

from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

from . import stack
from .contract import JSONObject, RecordError
from .result import OBJECT_UNAVAILABLE, Finding, Translation
from .sections import FACE, HOSTS, MODEL, ROOM, AttachmentRefused, Section

MODEL_ID = "ph_composer_model"


def assemble(translation: Translation, sections: Sequence[Section[Any, Any]]) -> None:
    """Attaches every declared object, records a finding for each one that cannot be attached, and sets
    `translation.canonical` when nothing a required section declared failed to attach."""
    attaching = [section for section in sections if section.attaches is not None]
    if not any(section.attaches.host == MODEL for section in attaching if section.attaches):
        return
    hb_model = stack.load("honeybee.model")
    stack.load("honeybee_energy._extend_honeybee")
    stack.load("honeybee_ph")
    model = hb_model.Model(MODEL_ID, units="Meters")
    complete = True
    for level in HOSTS:
        hosts = _hosts(model, level)
        for section in attaching:
            if section.attaches and section.attaches.host == level:
                attached = _attach(translation, section, hosts, level)
                complete = complete and (attached or not section.required_for_export)
    if complete and model.rooms:
        translation.canonical = _canonical(model)


def _hosts(model: Any, level: str) -> dict[str, Any]:
    if level == MODEL:
        return {"": model}
    if level == ROOM:
        return {room.identifier: room for room in model.rooms}
    assert level == FACE
    return {face.identifier: face for room in model.rooms for face in room.faces}


def _attach(translation: Translation, section: Section[Any, Any], hosts: dict[str, Any], level: str) -> bool:
    """Whether every one of the section's objects was attached."""
    attachment = section.attaches
    assert attachment is not None
    groups: dict[str, list[tuple[str, object]]] = {}
    for object_id, translated in sorted(translation.objects(section.id).items()):
        groups.setdefault(attachment.key(translated), []).append((object_id, translated))
    complete = True
    for host_id, items in groups.items():
        host = hosts.get(host_id)
        try:
            if host is None:
                raise RecordError(f"has no emitted host {level} {host_id}")
            section.attach(host, [translated for _, translated in items])
        except RecordError as error:
            complete = False
            refused = error.refused if isinstance(error, AttachmentRefused) else [item for _, item in items]
            translation.findings.extend(
                Finding(OBJECT_UNAVAILABLE, section.id, object_id, str(error), section.required_for_export)
                for object_id, translated in items
                if any(translated is item for item in refused)
            )
    return complete


def _canonical(model: Any) -> JSONObject:
    faces = [face for room in model.rooms for face in room.faces]
    surfaces = sum(1 for face in faces if face.boundary_condition.name == "Surface")
    return {
        "hbjson": json.dumps(model.to_dict(), sort_keys=True, separators=(",", ":")),
        "rooms": len(model.rooms),
        "faces": len(faces),
        "surface_pairs": surfaces // 2,
    }
