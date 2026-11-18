/* What the Climate tab's parts share: the operation names, the snapshot sections they paint from, and the words
   for a site. The Model stores the climate zone's WUFI-Passive code; these labels mirror
   features/climate/site/climate_zones.rb, which tests/climate_panel_test.js compares them with. */
PhComposerUI.define("features/climate/shared", ["fields", "units"], function (fields, units) {
  "use strict";
  var PREFIX = "ph_composer.climate.";
  var ZONES = [[1, "Not defined"], [11, "1"], [12, "2"], [13, "3"], [14, "4"], [141, "4C"], [15, "5"], [16, "6"],
    [17, "7"], [18, "8"]];
  var SITE_FIELDS = ["latitude_deg", "longitude_deg", "elevation_m", "climate_zone", "hours_from_utc"];
  var ELEVATION = fields.with(fields.LENGTH_M, { label: "Elevation", allowBlank: true, allowNegative: true });
  var TEMPERATURE = fields.with(fields.TEMPERATURE_C, { label: "Temperature", allowBlank: true });
  var DISTANCE = fields.with(fields.DISTANCE_KM, { label: "Distance" });
  /* Phius's limit on how far the station may be from the site, 50 mi, held in km as
     features/climate/climate/limit_check.rb holds it; tests/climate_panel_test.js compares the two. */
  var DISTANCE_LIMIT_KM = 80.4672;
  // The record's columns and the eight fields a write is guarded by (features/climate/climate/schema.rb).
  var MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
  var CASES = [["heat_1", "Heating 1"], ["heat_2", "Heating 2"], ["cool_1", "Cooling 1"]];
  var EDITABLE = ["name", "station_latitude_deg", "station_longitude_deg", "station_elevation_m",
    "daily_temp_swing_k", "wind_speed_m_s", "monthly", "peak_loads"];
  var RADIATION = fields.with(fields.IRRADIATION_KWH_M2, { allowBlank: true });
  var PEAK = fields.with(fields.IRRADIANCE_W_M2, { allowBlank: true });

  /* A monthly or peak-load row's unit: temperature, monthly radiation or peak radiation. */
  function rowField(row) {
    if (/_c$/.test(row)) return TEMPERATURE;
    return /_kwh_m2$/.test(row) ? RADIATION : PEAK;
  }
  /* The editable fields of a climate's values, the guard of its next write. */
  function editable(values) {
    var picked = {};
    EDITABLE.forEach(function (key) { picked[key] = values[key]; });
    return picked;
  }

  // A value and its unit stay on one line.
  function formatted(value, field) { return units.format(value, field, units.profile(field)).replace(/ /g, "\u00a0"); }
  function degrees(value, positive, negative) {
    return Math.abs(value).toFixed(3) + "° " + (value < 0 ? negative : positive);
  }
  /* "42.750° N, 73.800° W · 84 m", or null while the site is not set. */
  function coordinates(site) {
    if (!site || site.state !== "set") return null;
    return degrees(site.latitude_deg, "N", "S") + ", " + degrees(site.longitude_deg, "E", "W") + " · " +
      formatted(site.elevation_m, ELEVATION);
  }
  function hours(value) {
    if (value === null || value === undefined) return null;
    return value < 0 ? "\u2212" + Math.abs(value) : value > 0 ? "+" + value : "0";
  }
  function offset(value) { return value === null || value === undefined ? null : "UTC " + hours(value); }
  /* The export fields in one line, each unset one said so. */
  function exportLine(site) {
    var zone = site.climate_zone_label;
    return (zone ? "Climate zone " + zone : "Climate zone not set") + " · " +
      (offset(site.hours_from_utc) || "Hours from UTC not set");
  }

  /* The dataset the station picker opens on: the attached station's, when its file is on this computer,
     else the one used last, else the first found holding stations, else the first found. Only folders found now
     count. */
  function openingDataset(listed, attachedId) {
    var found = ((listed && listed.folders) || []).filter(function (folder) { return folder.found; });
    function byId(id) { return found.filter(function (folder) { return folder.id === id; })[0]; }
    return (attachedId && byId(attachedId)) || byId(listed.last_dataset_id) ||
      found.filter(function (folder) { return folder.station_count > 0; })[0] || found[0] || null;
  }

  return { PREFIX: PREFIX, SITE: PREFIX + "site", DESIGN: PREFIX + "design_temperatures",
    SUMMARY: PREFIX + "summary", ZONES: ZONES, SITE_FIELDS: SITE_FIELDS, ELEVATION: ELEVATION,
    TEMPERATURE: TEMPERATURE, DISTANCE: DISTANCE, DISTANCE_LIMIT_KM: DISTANCE_LIMIT_KM, MONTHS: MONTHS, CASES: CASES,
    RADIATION: RADIATION, PEAK: PEAK, rowField: rowField, editable: editable,
    formatted: formatted, openingDataset: openingDataset, coordinates: coordinates, hours: hours, offset: offset,
    exportLine: exportLine };
});
