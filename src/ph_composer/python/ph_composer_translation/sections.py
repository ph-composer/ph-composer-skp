"""What a translation section declares (context/CONTRACTS.md, "Translation sections and artifacts").

A section reads one section of the extraction, one record at a time, into typed objects keyed by the
record's durable id. It names the other sections whose objects it needs, and the type it expects from
each; the coordinator orders sections by those requirements and hands each one only what it declared.

    class Parts(Section[PartRecord, Part]):
        id = "example.foundation.parts"
        versions = frozenset({1})
        object_type = Part
        requires = (DEFINITIONS,)          # Requirement("example.foundation.definitions", Definition)

        def read(self, raw):               # raise RecordError for a bad record
            ...
        def translate(self, record, inputs):
            definition = inputs.get(DEFINITIONS, record.definition_id)   # typed, or DependencyUnavailable
            ...

A section never reads another section's records, and the coordinator names no section.

A section whose objects belong inside another object of the Honeybee model declares where, and the
model assembly (assembly.py) puts them there once every section has run:

    class Apertures(Section[ApertureRecord, TranslatedAperture]):
        attaches = Attachment(FACE, lambda item: item.source.host_face_id)

        def attach(self, host, objects):   # the host Face and its objects; raise RecordError to refuse
            ...
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any, ClassVar, Generic, TypeVar

from .contract import JSONValue, RecordError
from .result import Finding

RecordT = TypeVar("RecordT")
ObjectT = TypeVar("ObjectT")


@dataclass(frozen=True)
class Requirement(Generic[ObjectT]):
    """The objects of section `section`, which must be instances of `object_type`."""

    section: str
    object_type: type[ObjectT]


#: The Honeybee objects an attachment can name as its host, outermost first: the Model, a Room, a Face.
MODEL = "model"
ROOM = "room"
FACE = "face"
HOSTS = (MODEL, ROOM, FACE)


def _no_key(_: object) -> str:
    return ""


@dataclass(frozen=True)
class Attachment:
    """A section's objects join a `host` object of the assembled model. `key` names the host Room or Face
    of one object by its identifier; the Model is the only `MODEL` host, so its attachments need no key."""

    host: str
    key: Callable[[Any], str] = _no_key


class AttachmentRefused(RecordError):
    """`attach` refuses some of a host's objects and has attached the rest. Only `refused` emit findings; a
    refusal from a section required for export still keeps the canonical model from being written."""

    def __init__(self, message: str, refused: Sequence[object]) -> None:
        super().__init__(message)
        self.refused = tuple(refused)


class DependencyUnavailable(Exception):
    """A required object did not translate. The requiring record emits its own finding and produces no
    object: nothing stands in for the missing one."""

    def __init__(self, section: str, object_id: str, context: str | None = None) -> None:
        super().__init__(f"{section} object {object_id} is unavailable")
        self.section = section
        self.object_id = object_id
        self.context = context


class Inputs:
    """The objects a section declared it needs, from sections that have already run."""

    def __init__(self, declared: tuple[Requirement[Any], ...], objects: Mapping[str, Mapping[str, object]]) -> None:
        self._declared = declared
        self._objects = objects

    def get(self, requirement: Requirement[ObjectT], object_id: str) -> ObjectT:
        if requirement not in self._declared:
            raise LookupError(f"{requirement.section} is not a declared requirement of this section")
        found = self._objects.get(requirement.section, {}).get(object_id)
        if not isinstance(found, requirement.object_type):
            raise DependencyUnavailable(requirement.section, object_id)
        return found

    def all(self, requirement: Requirement[ObjectT]) -> tuple[ObjectT, ...]:
        """Available typed objects of one explicitly declared requirement, in durable-id order."""
        if requirement not in self._declared:
            raise LookupError(f"{requirement.section} is not a declared requirement of this section")
        return tuple(self.get(requirement, key) for key in sorted(self._objects.get(requirement.section, {})))


class Section(ABC, Generic[RecordT, ObjectT]):
    """One translation section. Subclasses set the class attributes and implement `read` and `translate`."""

    id: ClassVar[str]
    #: The versions of this section's extraction the section can read.
    versions: ClassVar[frozenset[int]]
    object_type: ClassVar[type]
    requires: ClassVar[tuple[Requirement[Any], ...]] = ()
    #: Whether an object that fails to translate or attach blocks the canonical artifact. An optional
    #: section's failed object is left out with a non-blocking finding. Translation continues either way,
    #: for diagnostics; continuing never grants permission to publish.
    required_for_export: ClassVar[bool] = True
    #: Where this section's objects go in the assembled model, or None when they go nowhere.
    attaches: ClassVar[Attachment | None] = None

    @abstractmethod
    def read(self, raw: Mapping[str, object]) -> RecordT:
        """One record, typed. Raise `RecordError` when this record cannot be read."""

    @abstractmethod
    def translate(self, record: RecordT, inputs: Inputs) -> ObjectT:
        """One object. Raise `RecordError`, or let `DependencyUnavailable` from `inputs` propagate."""

    def findings(self, objects: Mapping[str, ObjectT]) -> Sequence[Finding]:
        """Non-fatal information about translated objects, including deliberate omissions."""
        return ()

    def attach(self, host: Any, objects: Sequence[ObjectT]) -> None:
        """Joins `objects`, all naming `host`, to it. Raise `RecordError` to refuse them all, leaving the host as
        it was, or `AttachmentRefused` to refuse only some. Check what one object's own record can show in
        `translate`, so a defect costs that object only."""
        raise NotImplementedError(f"{self.id} declares an attachment but does not attach")

    def result_fields(self, objects: Mapping[str, ObjectT]) -> Mapping[str, JSONValue]:
        """The fields this section adds to the result document, under its own id. They are read after the
        model is assembled. Each must be declared by the feature's export contributor, or the export's
        privacy check refuses the result."""
        return {}

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Checks the reloaded canonical model against this section's own result `fields`. Raise
        `ValueError` when the published model would not say what this section translated."""
