"""The Model's site and climate as one honeybee-ph `Site` on every Building Segment (Ruby
`features/climate/export.rb`, CONTRACTS section 7 of the Climate packet).

The section has one record, always. Ruby has decided everything in it: which parts are written, the climate
zone an unset zone writes, the provenance and the copied Cooling 2 case. This builds honeybee-ph's `Location`,
monthly collections, four `Climate_PeakLoadValueSet`s, `ClimateProvenance` and `Site` from it and computes
nothing. A null part is passed to `Site` as `None`, so honeybee-ph supplies its own default for that part, as
its Grasshopper components do; with both parts null nothing is set and every Building Segment keeps its own
default `Site`. Ground temperatures are not touched.

The section requires the Zones section only for its order: it attaches at `MODEL` once the Rooms and the
Building Segments they share exist. It is optional (`required_for_export = False`): a `Site` that cannot be
built is left out with a non-blocking finding, and the model is written with honeybee-ph's defaults.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any, ClassVar

from . import stack
from .contract import JSONObject, JSONValue, RecordError, as_number, as_text
from .model_sections import ZONE_SECTION_ID, TranslatedZone
from .sections import MODEL, Attachment, Inputs, Requirement, Section

SITE_SECTION_ID = "ph_composer.climate.export.site"
ZONES = Requirement(ZONE_SECTION_ID, TranslatedZone)
MONTHS = 12
TEMPERATURES = {"air_c": "air_temps", "dewpoint_c": "dewpoints", "sky_c": "sky_temps"}
RADIATION = {
    "rad_north_kwh_m2": "north",
    "rad_east_kwh_m2": "east",
    "rad_south_kwh_m2": "south",
    "rad_west_kwh_m2": "west",
    "rad_global_kwh_m2": "glob",
}
#: The record's peak-load cases and honeybee-ph's attribute for each.
CASES = {"heat_1": "heat_load_1", "heat_2": "heat_load_2", "cool_1": "cooling_load_1", "cool_2": "cooling_load_2"}
PEAK_RADIATION = ("rad_north_w_m2", "rad_east_w_m2", "rad_south_w_m2", "rad_west_w_m2", "rad_global_w_m2")
PROVENANCE_FIELDS = (
    "source_type",
    "source_name",
    "source_version",
    "source_checksum",
    "conversion_method",
    "conversion_method_version",
    "is_certification_approved",
    "monthly_data_available",
    "peak_load_data_available",
    "assumptions",
)
#: The report block's keys, passed to the result as Ruby wrote them.
REPORT_FIELDS = (
    "climate",
    "missing_values",
    "limit_check",
    "edited_cells",
    "design_temperatures",
    "design_temperature_source",
)


@dataclass(frozen=True)
class SiteRecord:
    id: str
    location: JSONObject | None
    climate: JSONObject | None
    climate_left_out: str | None
    provenance: JSONObject | None
    report: JSONObject = field(default_factory=dict)

    @classmethod
    def read(cls, raw: Mapping[str, object]) -> SiteRecord:
        location, climate, provenance, report = (
            _object_or_none(raw.get(key), key) for key in ("location", "climate", "provenance", "report")
        )
        raw_left_out = raw.get("climate_left_out")
        left_out = raw_left_out if isinstance(raw_left_out, str) else None
        if left_out != raw_left_out or left_out not in (None, "site_not_set", "incomplete"):
            raise RecordError(f"climate_left_out {raw_left_out!r} is not a reason the section knows")
        if (climate is None) != (provenance is None):
            raise RecordError("a written climate carries its provenance, and only a written one does")
        if report is None or set(report) != set(REPORT_FIELDS):
            raise RecordError("the site record's report block names " + ", ".join(REPORT_FIELDS))
        return cls(as_text(raw.get("id"), "site record id"), location, climate, left_out, provenance, report)


@dataclass
class TranslatedSite:
    source: SiteRecord
    #: The one `Site` every Building Segment gets, or None when the record carries neither part.
    site: Any
    #: How many distinct Building Segments `attach` set it on.
    segments: int = 0


class SiteSection(Section[SiteRecord, TranslatedSite]):
    id = SITE_SECTION_ID
    versions = frozenset({1})
    object_type = TranslatedSite
    requires = (ZONES,)
    required_for_export: ClassVar[bool] = False
    attaches = Attachment(MODEL)

    def read(self, raw: Mapping[str, object]) -> SiteRecord:
        return SiteRecord.read(raw)

    def translate(self, record: SiteRecord, inputs: Inputs) -> TranslatedSite:
        if record.location is None and record.climate is None:
            return TranslatedSite(record, None)
        site = stack.load("honeybee_ph.site")
        try:
            location = None if record.location is None else build_location(site, record.location)
            climate = None if record.climate is None else build_climate(site, record.climate, record.provenance)
            return TranslatedSite(record, site.Site(location, climate))
        except (AssertionError, TypeError, ValueError) as error:
            raise RecordError(f"the site could not be built: {error}") from error

    def attach(self, host: Any, objects: Sequence[TranslatedSite]) -> None:
        """The one `Site` on every distinct Building Segment the Rooms share. A Model holds one site, so they
        all carry the same one."""
        if len(objects) != 1:
            raise RecordError("the Model has one site record")
        (item,) = objects
        segments = {id(segment): segment for segment in (room.properties.ph.ph_bldg_segment for room in host.rooms)}
        if item.site is not None:
            for segment in segments.values():
                segment.site = item.site
        item.segments = len(segments)

    def result_fields(self, objects: Mapping[str, TranslatedSite]) -> Mapping[str, JSONValue]:
        if len(objects) != 1:
            return {}
        (item,) = objects.values()
        record, built = item.source, item.site
        written = record.climate is not None
        identity = record.report.get("climate")
        climate: JSONValue = None
        if isinstance(identity, dict):
            climate = {
                **identity,
                "source_type": built.climate.provenance.source_type if written else None,
                "wind_speed_m_s": float(built.climate.average_wind_speed) if written else None,
            }
        return {
            "location": dict(record.location) if record.location is not None else None,
            "climate": climate,
            "climate_written": written,
            "climate_left_out": record.climate_left_out,
            "peak_load_temperatures_c": peak_temperatures(built.climate) if written else None,
            "building_segments": item.segments,
            "site_digest": digest(built) if built is not None else None,
            **{key: record.report[key] for key in REPORT_FIELDS if key != "climate"},
        }

    def conformance(self, model: Any, fields: Mapping[str, JSONValue]) -> None:
        """Every reloaded Building Segment carries the `Site` that was built, or honeybee-ph's default when the
        record carried neither part; a part the record did not carry is honeybee-ph's default; Cooling 2
        equals Cooling 1; and no `source_uri` is written."""
        if not fields:
            return
        segments = {
            segment.identifier: segment for segment in (room.properties.ph.ph_bldg_segment for room in model.rooms)
        }
        if len(segments) != fields.get("building_segments"):
            raise ValueError(
                f"the model has {len(segments)} Building Segments, the site reported {fields.get('building_segments')}"
            )
        site = stack.load("honeybee_ph.site")
        defaults = {"location": comparable(site.Location().to_dict()), "climate": comparable(site.Climate().to_dict())}
        expected_digest = fields.get("site_digest")
        location = fields.get("location")
        for identifier, segment in sorted(segments.items()):
            actual = segment.site
            if expected_digest is not None and digest(actual) != expected_digest:
                raise ValueError(f"Building Segment {identifier} does not carry the site that was built")
            if location is None and comparable(actual.location.to_dict()) != defaults["location"]:
                raise ValueError(f"Building Segment {identifier} has a location the record did not carry")
            if isinstance(location, dict) and _location_fields(actual.location) != location:
                raise ValueError(f"Building Segment {identifier} has a location other than the one reported")
            if not fields.get("climate_written"):
                if comparable(actual.climate.to_dict()) != defaults["climate"]:
                    raise ValueError(f"Building Segment {identifier} has a climate the record did not carry")
                continue
            peaks = actual.climate.peak_loads
            if comparable(peaks.cooling_load_2.to_dict()) != comparable(peaks.cooling_load_1.to_dict()):
                raise ValueError(f"Building Segment {identifier}: Cooling 2 does not repeat Cooling 1")
            if actual.climate.provenance is None or actual.climate.provenance.source_uri is not None:
                raise ValueError(
                    f"Building Segment {identifier}: the climate's provenance names a source_uri or is missing"
                )


def build_location(site: Any, location: JSONObject) -> Any:
    zone = location.get("climate_zone")
    hours = location.get("hours_from_utc")
    if not isinstance(zone, int) or isinstance(zone, bool):
        raise RecordError("the site's climate zone must be a code")
    if hours is not None and (not isinstance(hours, int) or isinstance(hours, bool)):
        raise RecordError("the site's hours from UTC must be whole hours or null")
    return site.Location(
        as_number(location.get("latitude_deg"), "latitude"),
        as_number(location.get("longitude_deg"), "longitude"),
        as_number(location.get("elevation_m"), "site elevation"),
        zone,
        hours,
    )


def build_climate(site: Any, climate: JSONObject, provenance: JSONObject | None) -> Any:
    monthly = _object(climate.get("monthly"), "monthly")
    temperatures = site.Climate_MonthlyTempCollection()
    for key, attribute in TEMPERATURES.items():
        getattr(temperatures, attribute).values = _months(monthly.get(key), key)
    radiation = site.Climate_MonthlyRadiationCollection()
    for key, attribute in RADIATION.items():
        getattr(radiation, attribute).values = _months(monthly.get(key), key)
    peaks = site.Climate_PeakLoadCollection()
    cases = _object(climate.get("peak_loads"), "peak_loads")
    for key, attribute in CASES.items():
        setattr(peaks, attribute, peak_case(site, _object(cases.get(key), key), key))
    stored = _object(provenance, "provenance")
    if set(stored) != set(PROVENANCE_FIELDS):
        raise RecordError("the provenance names honeybee-ph's fields, without source_uri")
    return site.Climate(
        as_text(climate.get("name"), "climate name"),
        as_number(climate.get("station_elevation_m"), "station elevation"),
        as_number(climate.get("daily_temp_swing_k"), "daily temperature swing"),
        as_number(climate.get("wind_speed_m_s"), "wind speed"),
        temperatures,
        radiation,
        peaks,
        site.ClimateProvenance(**{key: stored[key] for key in PROVENANCE_FIELDS}),
    )


def peak_case(site: Any, values: JSONObject, label: str) -> Any:
    radiation = [as_number(values.get(key), f"{label} {key}") for key in PEAK_RADIATION]
    optional = [_number_or_none(values.get(key), f"{label} {key}") for key in ("dewpoint_c", "sky_c")]
    return site.Climate_PeakLoadValueSet(as_number(values.get("air_c"), f"{label} air"), *radiation, *optional)


def peak_temperatures(climate: Any) -> dict[str, JSONValue]:
    """Each case's air temperature, read from the built climate."""
    return {key: float(getattr(climate.peak_loads, attribute).temp) for key, attribute in CASES.items()}


def comparable(value: Any) -> Any:
    """A honeybee-ph dict without its random identifiers: a display name that only repeats the identifier
    goes with it, so two objects built alike compare equal."""
    if isinstance(value, dict):
        identifier = value.get("identifier")
        return {
            key: comparable(item)
            for key, item in value.items()
            if key != "identifier" and not (key == "display_name" and item == identifier)
        }
    if isinstance(value, list):
        return [comparable(item) for item in value]
    return value


def digest(site_object: Any) -> str:
    """The SHA-256 of a `Site`'s comparable dict as canonical JSON."""
    text = json.dumps(comparable(site_object.to_dict()), sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _location_fields(location: Any) -> dict[str, JSONValue]:
    return {
        "latitude_deg": location.latitude,
        "longitude_deg": location.longitude,
        "elevation_m": location.site_elevation,
        "climate_zone": location.climate_zone,
        "hours_from_utc": location.hours_from_UTC,
    }


def _object(value: object, label: str) -> JSONObject:
    if not isinstance(value, dict):
        raise RecordError(f"{label} must be an object")
    return value


def _object_or_none(value: object, label: str) -> JSONObject | None:
    return None if value is None else _object(value, label)


def _months(value: object, label: str) -> list[float]:
    if not isinstance(value, list) or len(value) != MONTHS:
        raise RecordError(f"{label} must hold twelve months")
    return [as_number(item, f"{label} month {index + 1}") for index, item in enumerate(value)]


def _number_or_none(value: object, label: str) -> float | None:
    return None if value is None else as_number(value, label)
