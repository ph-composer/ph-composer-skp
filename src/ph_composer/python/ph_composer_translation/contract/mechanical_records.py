"""Detached mechanical export values, SI throughout (Wh/m³, °C, L, W, W/K).

Ventilation: one (Ventilator, Zone) pair with the identifiers Ruby derived from the Ventilator's id and the unit's
values as the record stores them. Hot water: one (Hot Water System, Zone) pair with the System's values, its Tanks in
the slots Ruby worked out and its Heaters, each Tank and Heater under its own record's id. Electric heating: one
(Electric Heater, Zone) pair under the heater's id."""

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


# -- Hot water ----------------------------------------------------------------

#: The System's four tank slots, honeybee-ph's `PhHotWaterSystem` attributes; Ruby's `HotWater::Slotting::SLOTS`.
TANK_SLOTS = ("tank_1", "tank_2", "tank_buffer", "tank_solar")
#: A Tank's values each slot carries, the Ruby record's names; Ruby's `HotWaterPlan::TANK_FIELDS`.
TANK_FIELDS = (
    "tank_type",
    "quantity",
    "in_conditioned_space",
    "solar_connection",
    "solar_losses_w",
    "storage_loss_rate_w_k",
    "storage_capacity_l",
    "standby_losses_w_k",
    "standby_fraction",
    "room_temp_c",
    "water_temp_c",
)
#: honeybee-ph's tank types, as its enumeration reads them back.
TANK_TYPES = ("0-NO STORAGE TANK", "1-DHW AND HEATING", "2-DHW ONLY")
#: Each heater variant's efficiency values, the Ruby record's names; Ruby's `HotWater::Heaters::VARIANT_FIELDS`.
VARIANT_FIELDS: dict[str, tuple[str, ...]] = {
    "electric": (),
    "heat_pump_annual": ("total_system_perf_ratio",),
    "heat_pump_monthly": ("cop_1", "ambient_temp_1_c", "cop_2", "ambient_temp_2_c"),
    "heat_pump_inside": ("annual_energy_factor",),
}
#: The monthly variant's temperatures, any finite number; every other efficiency value is above 0.
TEMPERATURE_FIELDS = frozenset({"ambient_temp_1_c", "ambient_temp_2_c"})


@dataclass(frozen=True)
class TankValues:
    identifier: str
    display_name: str
    tank_type: str
    quantity: int
    in_conditioned_space: bool
    solar_connection: bool
    solar_losses_w: float
    storage_loss_rate_w_k: float
    storage_capacity_l: float
    standby_losses_w_k: float
    standby_fraction: float
    room_temp_c: float
    water_temp_c: float
    user_data: JSONObject

    @classmethod
    def read(cls, raw: object, label: str) -> TankValues:
        if not isinstance(raw, Mapping):
            raise RecordError(f"{label} must be an object")
        identifier = as_text(raw.get("identifier"), f"{label} identifier")
        label = f"{label} {identifier}"
        tank_type = raw.get("tank_type")
        if tank_type not in TANK_TYPES:
            raise RecordError(f"{label} tank_type must be one of {', '.join(TANK_TYPES)}")
        quantity = raw.get("quantity")
        if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity < 1:
            raise RecordError(f"{label} quantity must be a whole number of at least 1")
        return cls(
            identifier,
            as_text(raw.get("display_name"), f"{label} display_name"),
            str(tank_type),
            quantity,
            flag(raw.get("in_conditioned_space"), f"{label} in_conditioned_space"),
            flag(raw.get("solar_connection"), f"{label} solar_connection"),
            non_negative(raw.get("solar_losses_w"), f"{label} solar_losses_w"),
            non_negative(raw.get("storage_loss_rate_w_k"), f"{label} storage_loss_rate_w_k"),
            non_negative(raw.get("storage_capacity_l"), f"{label} storage_capacity_l"),
            non_negative(raw.get("standby_losses_w_k"), f"{label} standby_losses_w_k"),
            fraction(raw.get("standby_fraction"), f"{label} standby_fraction"),
            as_number(raw.get("room_temp_c"), f"{label} room_temp_c"),
            as_number(raw.get("water_temp_c"), f"{label} water_temp_c"),
            user_data(raw.get("user_data"), label),
        )


@dataclass(frozen=True)
class HeaterValues:
    identifier: str
    display_name: str
    variant: str
    percent_coverage: float
    in_conditioned_space: bool
    #: The variant's own efficiency values, under the record's names.
    efficiency: dict[str, float]
    user_data: JSONObject

    @classmethod
    def read(cls, raw: object, label: str) -> HeaterValues:
        if not isinstance(raw, Mapping):
            raise RecordError(f"{label} must be an object")
        identifier = as_text(raw.get("identifier"), f"{label} identifier")
        label = f"{label} {identifier}"
        variant = raw.get("variant")
        if not isinstance(variant, str) or variant not in VARIANT_FIELDS:
            raise RecordError(f"{label} variant must be one of {', '.join(VARIANT_FIELDS)}")
        own = VARIANT_FIELDS[variant]
        foreign = sorted(
            key for fields in VARIANT_FIELDS.values() for key in fields if key not in own and raw.get(key) is not None
        )
        if foreign:
            raise RecordError(f"{label} is a {variant} heater and takes no {', '.join(foreign)}")
        efficiency = {
            key: (as_number if key in TEMPERATURE_FIELDS else positive)(raw.get(key), f"{label} {key}") for key in own
        }
        return cls(
            identifier,
            as_text(raw.get("display_name"), f"{label} display_name"),
            variant,
            fraction(raw.get("percent_coverage"), f"{label} percent_coverage"),
            flag(raw.get("in_conditioned_space"), f"{label} in_conditioned_space"),
            efficiency,
            user_data(raw.get("user_data"), label),
        )


@dataclass(frozen=True)
class HotWaterRecord:
    """One (Hot Water System, Zone) pair: the System's identifier (its id), name, tap points and piping calculation
    method, its Tanks by slot (None for an empty slot) and its Heaters in name order."""

    id: str
    item_id: str
    zone_id: str
    display_name: str
    system_identifier: str
    number_tap_points: int | None
    piping_calc_method: int | None
    tanks: dict[str, TankValues | None]
    heaters: tuple[HeaterValues, ...]

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> HotWaterRecord:
        identifier = as_text(raw.get("id"), "hot water id")
        label = f"hot water {identifier}"
        taps = optional_whole(raw.get("number_tap_points"), f"{label} number_tap_points", 1, None)
        method = optional_whole(raw.get("piping_calc_method"), f"{label} piping_calc_method", 1, 4)
        heaters = raw.get("heaters")
        if not isinstance(heaters, list):
            raise RecordError(f"{label} heaters must be a list")
        return cls(
            identifier,
            as_text(raw.get("item_id"), f"{label} item_id"),
            as_text(raw.get("zone_id"), f"{label} zone_id"),
            as_text(raw.get("display_name"), f"{label} display_name"),
            as_text(raw.get("system_identifier"), f"{label} system_identifier"),
            taps,
            method,
            {
                slot: None if raw.get(slot) is None else TankValues.read(raw.get(slot), f"{label} {slot}")
                for slot in TANK_SLOTS
            },
            tuple(HeaterValues.read(heater, f"{label} heater") for heater in heaters),
        )


def non_negative(value: object, label: str) -> float:
    number = as_number(value, label)
    if number < 0:
        raise RecordError(f"{label} must not be negative")
    return number


def positive(value: object, label: str) -> float:
    number = as_number(value, label)
    if number <= 0:
        raise RecordError(f"{label} must be above 0")
    return number


def optional_whole(value: object, label: str, minimum: int, maximum: int | None) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum or (maximum and value > maximum):
        bound = f"from {minimum} to {maximum}" if maximum else f"of at least {minimum}"
        raise RecordError(f"{label} must be a whole number {bound}")
    return value


# -- Heat pumps ---------------------------------------------------------------


@dataclass(frozen=True)
class RecirculationValues:
    """The blend's recirculation cooling: used only when the blend cools; capacity in kW, airflow in m³/h, the coil's
    minimum temperature in °C."""

    used: bool
    percent_coverage: float
    capacity_kw: float
    flow_rate_m3_hr: float
    annual_cop: float
    min_coil_temp_c: float
    single_speed: bool
    flow_rate_variable: bool

    @classmethod
    def read(cls, raw: object, label: str) -> RecirculationValues:
        if not isinstance(raw, dict):
            raise RecordError(f"{label} must be an object")
        return cls(
            flag(raw.get("used"), f"{label} used"),
            fraction(raw.get("percent_coverage"), f"{label} percent_coverage"),
            non_negative(raw.get("capacity_kw"), f"{label} capacity_kw"),
            non_negative(raw.get("flow_rate_m3_hr"), f"{label} flow_rate_m3_hr"),
            non_negative(raw.get("annual_cop"), f"{label} annual_cop"),
            as_number(raw.get("min_coil_temp_c"), f"{label} min_coil_temp_c"),
            flag(raw.get("single_speed"), f"{label} single_speed"),
            flag(raw.get("flow_rate_variable"), f"{label} flow_rate_variable"),
        )


@dataclass(frozen=True)
class HeatPumpRecord:
    """One (Building Segment's blended heat pump, Zone) pair: the blend's identifier and name, which every pair of
    one Segment shares, its COPs at its two rating temperatures and its recirculation cooling, as Ruby worked them
    out (`HeatPumpPlan`)."""

    id: str
    zone_id: str
    segment: str
    display_name: str
    system_identifier: str
    percent_coverage: float
    cop_1: float
    ambient_temp_1_c: float
    cop_2: float
    ambient_temp_2_c: float
    cooling: RecirculationValues

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> HeatPumpRecord:
        identifier = as_text(raw.get("id"), "heat pump id")
        label = f"heat pump {identifier}"
        return cls(
            identifier,
            as_text(raw.get("zone_id"), f"{label} zone_id"),
            as_text(raw.get("segment"), f"{label} segment"),
            as_text(raw.get("display_name"), f"{label} display_name"),
            as_text(raw.get("system_identifier"), f"{label} system_identifier"),
            fraction(raw.get("percent_coverage"), f"{label} percent_coverage"),
            positive(raw.get("cop_1"), f"{label} cop_1"),
            as_number(raw.get("ambient_temp_1_c"), f"{label} ambient_temp_1_c"),
            positive(raw.get("cop_2"), f"{label} cop_2"),
            as_number(raw.get("ambient_temp_2_c"), f"{label} ambient_temp_2_c"),
            RecirculationValues.read(raw.get("cooling"), f"{label} cooling"),
        )


# -- Electric heaters ---------------------------------------------------------


@dataclass(frozen=True)
class ElectricHeaterRecord:
    """One (Electric Heater, Zone) pair: the heater's identifier (its record id) and Tag, which every pair of one
    heater shares, its coverage as a fraction and its `user_data` (`ElectricHeaterPlan`)."""

    id: str
    item_id: str
    zone_id: str
    identifier: str
    display_name: str
    percent_coverage: float
    user_data: JSONObject

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> ElectricHeaterRecord:
        identifier = as_text(raw.get("id"), "electric heater id")
        label = f"electric heater {identifier}"
        return cls(
            identifier,
            as_text(raw.get("item_id"), f"{label} item_id"),
            as_text(raw.get("zone_id"), f"{label} zone_id"),
            as_text(raw.get("identifier"), f"{label} identifier"),
            as_text(raw.get("display_name"), f"{label} display_name"),
            fraction(raw.get("percent_coverage"), f"{label} percent_coverage"),
            user_data(raw.get("user_data"), label),
        )
