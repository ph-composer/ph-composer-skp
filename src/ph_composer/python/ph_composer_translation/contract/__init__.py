"""The JSON seam. Every value from the extraction is read through these, so a wrong type is found at the
edge and named, never deep inside a translation."""

from __future__ import annotations

import math
from collections.abc import Mapping
from typing import TypeAlias

JSONValue: TypeAlias = bool | int | float | str | list["JSONValue"] | dict[str, "JSONValue"] | None
JSONObject: TypeAlias = dict[str, JSONValue]


class ContractError(Exception):
    """The document, or a whole section of it, cannot be read. The run stops before any translation.

    `code` is one of the translation codes in context/CONTRACTS.md, "Outcomes and codes".
    """

    def __init__(self, code: str, detail: str) -> None:
        super().__init__(detail)
        self.code = code
        self.detail = detail


class RecordError(Exception):
    """One record cannot be read or translated. It costs that record only; the rest continue."""


def as_text(value: object, label: str) -> str:
    """A non-empty string. Blank and whitespace-only are both missing."""
    if not isinstance(value, str) or not value.strip():
        raise RecordError(f"{label} must be non-empty text")
    return value.strip()


#: The user_data key PH-Composer writes its own values under; a user's data never takes it.
RESERVED_USER_DATA_KEY = "ph_composer"


def user_data(value: object, label: str) -> JSONObject:
    """A record's user_data, passed to Honeybee as given: absent or null is empty, anything else must be
    a JSON object that does not use the reserved key. Nothing here interprets the values."""
    if value is None:
        return {}
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise RecordError(f"{label} user_data must be an object")
    if RESERVED_USER_DATA_KEY in value:
        raise RecordError(f"{label} user_data must not use the reserved key {RESERVED_USER_DATA_KEY}")
    return dict(value)


def with_user_data(own: Mapping[str, object], user: JSONObject) -> dict[str, object]:
    """A Honeybee object's user_data: the user's keys beside PH-Composer's own reserved entry."""
    return {**user, **own}


def as_number(value: object, label: str) -> float:
    """A finite JSON number. A boolean is not a number, and a numeric string is a misread upstream."""
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise RecordError(f"{label} must be a finite number")
    return float(value)


def whole(value: object, label: str, allowed: range | None = None, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise RecordError(f"{label} must be a whole number")
    if allowed is not None and value not in allowed:
        raise RecordError(f"{label} must be from {allowed.start} to {allowed.stop - 1}")
    if minimum is not None and value < minimum:
        raise RecordError(f"{label} must be at least {minimum}")
    return value


def bounded(value: object, label: str, low: float, high: float | None = None, above: bool = False) -> float:
    number = as_number(value, label)
    if number < low or (above and number == low) or (high is not None and number > high):
        span = f"above {low}" if above else f"from {low} to {high}" if high is not None else f"at least {low}"
        raise RecordError(f"{label} must be {span}")
    return number
