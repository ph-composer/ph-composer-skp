"""The Model's own metadata (Ruby `shell/model_metadata.rb`), set on the Honeybee Model itself.

The section has at most one record, the Model's, whose `user_data` becomes `Model.user_data` as given.
PH-Composer writes no reserved entry there, and a user's map may not take the reserved key.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from .contract import JSONObject, RecordError, as_text, user_data
from .sections import MODEL, Attachment, Inputs, Section

MODEL_METADATA_SECTION_ID = "ph_composer.model.export.model"


@dataclass(frozen=True)
class ModelMetadata:
    id: str
    user_data: JSONObject


class ModelMetadataSection(Section[ModelMetadata, ModelMetadata]):
    id = MODEL_METADATA_SECTION_ID
    versions = frozenset({1})
    object_type = ModelMetadata
    attaches = Attachment(MODEL)

    def read(self, raw: Mapping[str, object]) -> ModelMetadata:
        identifier = as_text(raw.get("id"), "model metadata id")
        return ModelMetadata(identifier, user_data(raw.get("user_data"), "model"))

    def translate(self, record: ModelMetadata, inputs: Inputs) -> ModelMetadata:
        return record

    def attach(self, host: Any, objects: Sequence[ModelMetadata]) -> None:
        if len(objects) > 1:
            raise RecordError("the Model has one metadata record")
        if objects[0].user_data:
            host.user_data = dict(objects[0].user_data)
