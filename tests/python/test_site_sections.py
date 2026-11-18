"""The Site section over board 18's record, which tests/climate_export_test.rb writes
(tests/fixtures/climate/extraction.json), on the two-Zone reference model of the thermal-bridge golden: one
honeybee-ph `Site` on every Building Segment, read back from the canonical HBJSON; a part the record does not
carry is honeybee-ph's default; Cooling 2 repeats Cooling 1; no `source_uri`. The section's result is the
golden the Ruby report test renders (tests/fixtures/climate/result.json): `make fixtures` rewrites it."""

from __future__ import annotations

import copy
import json
import os
import re
from pathlib import Path
from typing import Any, cast

import pytest

from ph_composer_translation import stack
from ph_composer_translation.composition import SECTIONS
from ph_composer_translation.conformance import check
from ph_composer_translation.coordinator import translate
from ph_composer_translation.site_sections import (
    CASES,
    PEAK_RADIATION,
    RADIATION,
    SITE_SECTION_ID,
    TEMPERATURES,
    comparable,
)

FIXTURES = Path(__file__).resolve().parents[1] / "fixtures"
EXTRACTION = FIXTURES / "climate" / "extraction.json"
RESULT_FIELDS = FIXTURES / "climate" / "result_fields.json"
RESULT = FIXTURES / "climate" / "result.json"
GEOMETRY = FIXTURES / "thermal_bridges" / "extraction.json"


def site_record() -> dict[str, Any]:
    value = json.loads(EXTRACTION.read_text())
    (record,) = value["sections"][SITE_SECTION_ID]["records"]
    return cast(dict[str, Any], record)


def document(record: dict[str, Any] | None = None, annex: bool = False) -> dict[str, Any]:
    """The reference model's extraction with the site record added; `annex` moves Zone B to its own Building
    Segment."""
    value: dict[str, Any] = json.loads(GEOMETRY.read_text())
    value["sections"].update(
        {
            "ph_composer.windows.export.window_constructions": {"version": 1, "records": []},
            "ph_composer.windows.export.apertures": {"version": 1, "records": []},
            SITE_SECTION_ID: {"version": 1, "records": [site_record() if record is None else record]},
        }
    )
    if annex:
        zones = value["sections"]["ph_composer.zones.export.zones"]["records"]
        zones[-1]["building_segment"] = "Annex"
    return value


#: The shapes of a local path `Diagnostics.absolute_path?` refuses: a leading slash, two or more segments after
#: a separator, a drive letter, a share, a home folder or a file URL.
LOCAL_PATH = re.compile(r"\A/[^/\s]+|[\s(=:,;\"'\[](?:/[^/\s]+){2,}|(?:\A|[^A-Za-z0-9])[A-Za-z]:[\\/]|\\\\|~/|file://")


def strings(value: Any) -> list[str]:
    if isinstance(value, dict):
        return [text for item in value.values() for text in strings(item)]
    if isinstance(value, list):
        return [text for item in value for text in strings(item)]
    return [value] if isinstance(value, str) else []


def run(value: dict[str, Any]) -> dict[str, Any]:
    return cast(dict[str, Any], translate(value, SECTIONS).to_document())


def sites(result: dict[str, Any]) -> list[Any]:
    model = stack.load("honeybee.model").Model.from_dict(json.loads(result["canonical_model"]["hbjson"]))
    segments = {
        room.properties.ph.ph_bldg_segment.identifier: room.properties.ph.ph_bldg_segment for room in model.rooms
    }
    return [segment.site for _, segment in sorted(segments.items())]


def default(part: str) -> Any:
    site = stack.load("honeybee_ph.site")
    return comparable(getattr(site, part)().to_dict())


def test_board_18_reloads_with_its_site_on_the_building_segment_and_owns_the_result_golden() -> None:
    record = site_record()
    result = run(document())

    assert result["summary"]["publishable"] is True
    assert [row for row in result["findings"] if row["section"] == SITE_SECTION_ID] == []
    check(result["canonical_model"], result, SECTIONS)
    (site,) = sites(result)
    location = record["location"]
    assert (site.location.latitude, site.location.longitude, site.location.site_elevation) == (40.0, -100.0, 500.0)
    assert (site.location.climate_zone, site.location.hours_from_UTC) == (location["climate_zone"], None)
    climate = site.climate
    values = record["climate"]
    assert (climate.display_name, climate.station_elevation, climate.summer_daily_temperature_swing) == (
        values["name"],
        values["station_elevation_m"],
        values["daily_temp_swing_k"],
    )
    assert climate.average_wind_speed == values["wind_speed_m_s"]
    for key, attribute in TEMPERATURES.items():
        assert getattr(climate.monthly_temps, attribute).values == values["monthly"][key], key
    for key, attribute in RADIATION.items():
        assert getattr(climate.monthly_radiation, attribute).values == values["monthly"][key], key
    assert climate.monthly_temps.ground_temps.values == [0.0] * 12, "ground temperatures are not touched"
    peaks = climate.peak_loads
    for key, attribute in CASES.items():
        case, built = values["peak_loads"][key], getattr(peaks, attribute)
        assert (built.temp, built.dewpoint, built.sky_temp) == (case["air_c"], case["dewpoint_c"], case["sky_c"]), key
        assert [built.rad_north, built.rad_east, built.rad_south, built.rad_west, built.rad_global] == [
            case[row] for row in PEAK_RADIATION
        ], key
    assert values["peak_loads"]["cool_2"] == values["peak_loads"]["cool_1"]
    assert comparable(peaks.cooling_load_2.to_dict()) == comparable(peaks.cooling_load_1.to_dict())
    provenance = climate.provenance
    assert (provenance.source_type, provenance.source_uri) == ("user_defined", None)
    assert provenance.assumptions == record["provenance"]["assumptions"]
    assert provenance.assumptions["ph_composer"]["cooling_load_2"] == "repeats cooling_load_1"
    assert (provenance.monthly_data_available, provenance.peak_load_data_available) == (True, True)
    assert climate.monthly_demand_readiness_issues() == [] and climate.peak_load_readiness_issues() == []

    fields = result[SITE_SECTION_ID]
    assert sorted(fields) == sorted(json.loads(RESULT_FIELDS.read_text()))
    assert (fields["building_segments"], fields["climate_written"], fields["climate"]["source_type"]) == (
        1,
        True,
        "user_defined",
    )
    golden = json.dumps({SITE_SECTION_ID: fields}, indent=2, sort_keys=True) + "\n"
    if os.environ.get("PHC_WRITE_FIXTURES") == "1" and (not RESULT.exists() or RESULT.read_text() != golden):
        RESULT.write_text(golden)
    assert RESULT.read_text() == golden, "tests/fixtures/climate/result.json is stale; run `make fixtures`"
    hbjson = json.loads(result["canonical_model"]["hbjson"])
    texts = strings(fields) + strings(hbjson["properties"]["ph"]["bldg_segments"])
    assert [text for text in texts if LOCAL_PATH.search(text)] == [], "no folder location in the result or the HBJSON"
    assert record["report"]["climate"]["dataset_name"] in texts


def test_two_building_segments_carry_the_same_site() -> None:
    result = run(document(annex=True))

    check(result["canonical_model"], result, SECTIONS)
    first, second = sites(result)
    assert comparable(first.to_dict()) == comparable(second.to_dict())
    assert result[SITE_SECTION_ID]["building_segments"] == 2


def test_a_site_alone_writes_its_location_over_the_default_climate() -> None:
    record = site_record()
    record.update(climate=None, provenance=None)
    record["location"].update(hours_from_utc=-6, climate_zone=1)
    result = run(document(record, annex=True))

    check(result["canonical_model"], result, SECTIONS)
    for site in sites(result):
        assert (site.location.latitude, site.location.hours_from_UTC, site.location.climate_zone) == (40.0, -6, 1)
        assert comparable(site.climate.to_dict()) == default("Climate")
        assert site.climate.provenance is None
    assert result[SITE_SECTION_ID]["climate_written"] is False


def test_neither_part_leaves_honeybee_phs_default_site_in_place() -> None:
    record = site_record()
    record.update(location=None, climate=None, provenance=None, climate_left_out=None)
    result = run(document(record, annex=True))

    check(result["canonical_model"], result, SECTIONS)
    for site in sites(result):
        assert comparable(site.location.to_dict()) == default("Location")
        assert comparable(site.climate.to_dict()) == default("Climate")
    assert result[SITE_SECTION_ID]["site_digest"] is None


def test_conformance_fails_when_a_segments_site_is_altered_after_assembly() -> None:
    result = run(document(annex=True))
    hbjson = json.loads(result["canonical_model"]["hbjson"])
    segment = hbjson["properties"]["ph"]["bldg_segments"][-1]
    segment["site"]["climate"]["peak_loads"]["cooling_load_2"]["temp"] = 99.0
    altered = {**result["canonical_model"], "hbjson": json.dumps(hbjson)}

    with pytest.raises(ValueError, match="site that was built"):
        check(altered, result, SECTIONS)


def test_a_site_that_cannot_be_built_is_left_out_and_the_model_still_publishes() -> None:
    record = copy.deepcopy(site_record())
    record["provenance"]["source_uri"] = "anything"
    result = run(document(record))

    assert result["summary"]["publishable"] is True
    rows = [row for row in result["findings"] if row["section"] == SITE_SECTION_ID]
    assert [(row["object_id"], row["blocks_export"]) for row in rows] == [("Site", False)]
    (site,) = sites(result)
    assert comparable(site.climate.to_dict()) == default("Climate")


def test_a_case_without_dewpoint_or_sky_temperature_is_written_with_none() -> None:
    record = site_record()
    for key in ("cool_1", "cool_2"):
        record["climate"]["peak_loads"][key].update(dewpoint_c=None, sky_c=None)
    result = run(document(record))

    check(result["canonical_model"], result, SECTIONS)
    (site,) = sites(result)
    cooling = site.climate.peak_loads.cooling_load_1
    assert (cooling.dewpoint, cooling.sky_temp) == (None, None)
    assert site.climate.peak_load_readiness_issues() == []
