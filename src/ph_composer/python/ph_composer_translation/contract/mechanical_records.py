"""Detached Ventilator export values: one (Ventilator, Zone) pair with the identifiers Ruby derived from the
Ventilator's id and the unit's values as the record stores them, SI throughout (Wh/m³, °C)."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from . import JSONObject, RecordError, as_number, as_text, user_data

#: The unit's values each pair carries, the Ruby record's names; Ruby's `VentilationPlan::UNIT_FIELDS`.
UNIT_FIELDS = (
    "quantity",
    "sensible_heat_recovery",
    "latent_heat_recovery",
    "electric_efficiency_wh_m3",
    "frost_protection_reqd",
    "temperature_below_defrost_used_c",
    "in_conditioned_space",
    "subsoil_heat_exchange_efficiency",
    "preheated_intake_temperature_c",
)


@dataclass(frozen=True)
class VentilationRecord:
    id: str
    item_id: str
    zone_id: str
    display_name: str
    system_identifier: str
    unit_identifier: str
    quantity: int
    sensible_heat_recovery: float
    latent_heat_recovery: float
    electric_efficiency_wh_m3: float
    frost_protection_reqd: bool
    temperature_below_defrost_used_c: float
    in_conditioned_space: bool
    subsoil_heat_exchange_efficiency: float | None
    preheated_intake_temperature_c: float | None
    user_data: JSONObject

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> VentilationRecord:
        identifier = as_text(raw.get("id"), "ventilation id")
        label = f"ventilation {identifier}"
        quantity = raw.get("quantity")
        if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity < 1:
            raise RecordError(f"{label} quantity must be a whole number of at least 1")
        efficiency = as_number(raw.get("electric_efficiency_wh_m3"), f"{label} electric_efficiency_wh_m3")
        if efficiency < 0:
            raise RecordError(f"{label} electric_efficiency_wh_m3 must not be negative")
        subsoil = raw.get("subsoil_heat_exchange_efficiency")
        preheated = raw.get("preheated_intake_temperature_c")
        return cls(
            identifier,
            as_text(raw.get("item_id"), f"{label} item_id"),
            as_text(raw.get("zone_id"), f"{label} zone_id"),
            as_text(raw.get("display_name"), f"{label} display_name"),
            as_text(raw.get("system_identifier"), f"{label} system_identifier"),
            as_text(raw.get("unit_identifier"), f"{label} unit_identifier"),
            quantity,
            fraction(raw.get("sensible_heat_recovery"), f"{label} sensible_heat_recovery"),
            fraction(raw.get("latent_heat_recovery"), f"{label} latent_heat_recovery"),
            efficiency,
            flag(raw.get("frost_protection_reqd"), f"{label} frost_protection_reqd"),
            as_number(raw.get("temperature_below_defrost_used_c"), f"{label} temperature_below_defrost_used_c"),
            flag(raw.get("in_conditioned_space"), f"{label} in_conditioned_space"),
            None if subsoil is None else fraction(subsoil, f"{label} subsoil_heat_exchange_efficiency"),
            None if preheated is None else as_number(preheated, f"{label} preheated_intake_temperature_c"),
            user_data(raw.get("user_data"), label),
        )

    def unit_values(self) -> dict[str, object]:
        """The unit's values under the record's names, as the result rows carry them."""
        return {key: getattr(self, key) for key in UNIT_FIELDS}


def fraction(value: object, label: str) -> float:
    number = as_number(value, label)
    if not 0.0 <= number <= 1.0:
        raise RecordError(f"{label} must be from 0 to 1")
    return number


def flag(value: object, label: str) -> bool:
    if not isinstance(value, bool):
        raise RecordError(f"{label} must be true or false")
    return value
