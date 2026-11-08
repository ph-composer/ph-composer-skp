"use strict";

/* The units registry, conversion, parsing and formatting.

   `units` holds no mutable state, so one load serves every case here; the tests that follow
   share nothing else. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var panelSource = require("./support/panel_source");

var context = { Intl: Intl };
context.window = context;
var units = panelSource.start(context, ["units"]).units;

var US = { decimal: ".", group: ",", groupSizes: [3] };
var DE = { decimal: ",", group: ".", groupSizes: [3] };
var FR = { decimal: ",", group: " ", groupSizes: [3] };
var CH = { decimal: ".", group: "’", groupSizes: [3] };
var IN = { decimal: ".", group: ",", groupSizes: [3, 2] };

function close(actual, expected, tolerance, message) {
  assert(Math.abs(actual - expected) <= tolerance, message + ": " + actual + " vs " + expected);
}

function relative(actual, expected, tolerance, message) {
  close(actual / expected, 1, tolerance, message);
}

function field(quantity, canonical, label) {
  return { quantity: quantity, unit: canonical, label: label || units.quantities[quantity].label };
}

function parse(text, valueField, defaultUnit, numberFormat) {
  return units.parse(text, valueField, { defaultUnit: defaultUnit, numberFormat: numberFormat || US });
}

function parsed(text, valueField, defaultUnit, expected, numberFormat) {
  var result = parse(text, valueField, defaultUnit, numberFormat);
  assert.strictEqual(result.ok, true, text + ": " + result.message);
  close(result.value, expected, 1e-8, text);
}

function code(text, valueField, defaultUnit, expected, numberFormat) {
  var result = parse(text, valueField, defaultUnit, numberFormat);
  assert.strictEqual(result.ok, false, text);
  assert.strictEqual(result.code, expected, text + ": " + result.message);
}

var mmField = field("length_mm", "mm", "Width");
var metreField = field("length", "m", "Width");
var dimensionField = field("length_mm", "mm");

test("the registry lists every quantity in its published order", function () {
  assert.deepStrictEqual(Object.keys(units.quantities), [
    "fraction", "length", "length_mm", "area", "volume", "u_value", "thermal_resistance", "conductivity",
    "linear_psi", "heat_loss_rate", "density", "specific_heat", "airflow", "temperature",
    "temperature_difference", "air_permeance", "vapor_sd", "vapor_diffusion_resistance"
  ]);
});

test("every conversion factor agrees with the web application it was ported from", function () {
  var webFactors = {
    area: 10.7639104167,
    volume: 35.3146667215,
    u_value: 0.1761101838,
    thermal_resistance: 5.678263337,
    conductivity: 0.577789317,
    linear_psi: 0.577789317,
    heat_loss_rate: 3.412141633 / 1.8,
    density: 0.06242796,
    specific_heat: 0.0002388458966275,
    airflow: 0.588577779
  };

  Object.keys(webFactors).forEach(function (quantity) {
    // The web density literal has only eight significant figures, so it needs a
    // wider comparison tolerance.
    var tolerance = quantity === "density" ? 1e-7 : 1e-9;
    relative(units.quantities[quantity].factor, webFactors[quantity], tolerance, quantity + " web factor");
  });
});

test("one shared vector per quantity converts to its recorded IP value", function () {
  var vectors = JSON.parse(fs.readFileSync(path.join(__dirname, "support", "units_vectors.json"), "utf8"));

  assert.deepStrictEqual(
    vectors.map(function (row) { return row.quantity; }),
    Object.keys(units.quantities),
    "one shared vector per quantity"
  );
  vectors.forEach(function (row) {
    close(units.toDisplay(row.canonical_value, field(row.quantity, row.canonical_unit), "IP"),
          row.expected_ip_value, row.tolerance, row.quantity + " shared vector");
  });
});

test("temperature converts by scale and a temperature difference by ratio", function () {
  assert.strictEqual(units.toDisplay(-40, field("temperature", "c"), "IP"), -40);
  assert.strictEqual(units.toDisplay(10, field("temperature_difference", "k"), "IP"), 18);
});

test("a length expression carries its units through the arithmetic", function () {
  parsed("0.5 ft", mmField, "mm", 152.4);
  parsed("0.5 ft", metreField, "m", 0.1524);
  parsed("1 ft + 2 in", mmField, "mm", 355.6);
  parsed("3' 4-1/2\"", metreField, "ft-in", 1.0287);
  parsed("1 ft + 2 in", metreField, "ft-in", 0.3556);
  parsed("40.5", metreField, "ft-in", 1.0287);
  parsed("40.5", metreField, "in-frac", 1.0287);
  parsed("1 ft - 2 in", mmField, "mm", 254);
  parsed("2 * 3 ft", mmField, "mm", 1828.8);
  parsed("(1 ft + 2 in) / 2", mmField, "mm", 177.8);
  parsed("(100 + 2) in", mmField, "mm", 2590.8);
  parsed("100 + 2 in", mmField, "mm", 150.8);
  parsed("(1200 - 50) / 4", mmField, "mm", 287.5);
  parsed("2-1/2\"", mmField, "mm", 63.5);
  parsed("1'-2\"", mmField, "mm", 355.6);
  parsed("1' - 2\"", mmField, "mm", 254);
  parsed("100-50/2", mmField, "mm", 75);
});

test("an expression whose result is not a length is refused", function () {
  code("2 ft * 3 ft", mmField, "mm", "non_length_result");
  code("100 / 4 in", mmField, "mm", "non_length_result");
  code("(1 ft + 2 in) mm", mmField, "mm", "double_unit");
  code("2 - 1/2 in", mmField, "mm", "negative");
});

test("a negative value is refused unless the field allows one", function () {
  parsed("-1 ft + 2 in", { quantity: "length_mm", unit: "mm", label: "Offset", allowNegative: true }, "mm", -254);
  parsed("-0.02", field("linear_psi", "w_mk", "Psi-install"), "w_mk", -0.02);
  code("-0.02", { quantity: "linear_psi", unit: "w_mk", label: "Psi-install", allowNegative: false }, "w_mk",
    "negative");
  code("-1", field("u_value", "w_m2k"), "w_m2k", "negative");
});

test("every architectural input form a consultant types is read", function () {
  [
    ["2'", 609.6], ["6\"", 152.4], ["2' 6\"", 762], ["2'6\"", 762],
    ["3'-4\"", 1016], ["6-1/2\"", 165.1], ["6 1/2\"", 165.1],
    ["1/2\"", 12.7], ["24 3/8\"", 619.125], ["2’ 6”", 762],
    ["2' 6-1/2\"", 774.7], ["1' 3/4\"", 323.85]
  ].forEach(function (row) { parsed(row[0], mmField, "mm", row[1]); });
});

test("the dimension format catalogue is the published list with its labels", function () {
  assert.deepStrictEqual(
    JSON.parse(JSON.stringify(units.dimensionFormats.map(function (entry) { return [entry.id, entry.label]; }))),
    [
      ["mm", "Millimetres (mm)"], ["cm", "Centimetres (cm)"], ["m", "Metres (m)"],
      ["in", "Decimal inches (in)"], ["ft", "Decimal feet (ft)"],
      ["ft-in", "Feet and inches (ft-in)"], ["in-frac", "Fractional inches (in-frac)"]
    ]
  );
  assert.deepStrictEqual(JSON.parse(JSON.stringify(units.dimensionDefaults)), { SI: "mm", IP: "in" });
});

test("each dimension format has its own display text and edit seed", function () {
  var expectedFormats = {
    mm: ["762 mm", "762"], cm: ["76.2 cm", "76.2"], m: ["0.762 m", "0.762"],
    in: ["30 in", "30"], ft: ["2.5 ft", "2.5"], "ft-in": ["2' 6\"", "2' 6\""],
    "in-frac": ["30\"", "30\""]
  };

  Object.keys(expectedFormats).forEach(function (id) {
    var profile = {
      system: id === "mm" || id === "cm" || id === "m" ? "SI" : "IP",
      numberFormat: US,
      dimensionFormat: id
    };
    assert.strictEqual(units.format(762, dimensionField, profile), expectedFormats[id][0], id + " display");
    assert.strictEqual(units.formatEdit(762, dimensionField, profile), expectedFormats[id][1], id + " seed");
  });
});

test("a cell under a unit header drops a decimal length's unit and keeps architectural marks", function () {
  var field = { quantity: "length", unit: "mm" };
  var mm = { system: "SI", numberFormat: US, dimensionFormat: "mm" };
  var arch = { system: "IP", numberFormat: US, dimensionFormat: "ft-in" };
  assert.strictEqual(units.format(762, field, mm), "762 mm");
  assert.strictEqual(units.format(762, field, mm, { showUnit: false }), "762");
  assert.strictEqual(units.format(762, field, arch, { showUnit: false }), units.format(762, field, arch),
    "feet and inches marks are the number, not a unit label");
});

test("feet and inches carry rather than printing twelve inches or sixteen sixteenths", function () {
  var arch = { system: "IP", numberFormat: US, dimensionFormat: "ft-in" };
  var inchFraction = { system: "IP", numberFormat: US, dimensionFormat: "in-frac" };

  assert.strictEqual(units.format(0, dimensionField, arch), '0"');
  assert.strictEqual(units.format(-304.8, dimensionField, arch), "-1'");
  assert.strictEqual(units.format(306.3875, dimensionField, inchFraction), '12-1/16"');
  assert.strictEqual(units.format(304.7, dimensionField, arch).indexOf('12"'), -1, "carry removes twelve inches");
  assert.strictEqual(units.format(24.60625, dimensionField, inchFraction).indexOf("16/16"), -1,
                     "carry removes sixteen sixteenths");
  assert.strictEqual(units.format(0.15, dimensionField, arch), '0.006"');
  assert.strictEqual(units.formatEdit(1, dimensionField, arch), '0.03937"');
});

test("the locale's own separators are read and written, and the other locale's are refused", function () {
  parsed("1,200.5 mm", mmField, "mm", 1200.5, US);
  code("1,5", mmField, "mm", "number_format", US);
  parsed("1.200,5 mm", mmField, "mm", 1200.5, DE);
  code("1.5", mmField, "mm", "number_format", DE);
  parsed("1 234,5 mm", mmField, "mm", 1234.5, FR);
  parsed("1 234,5 mm", mmField, "mm", 1234.5, FR);
  parsed("1 234,5 mm", mmField, "mm", 1234.5, FR);
  parsed("2 1/2 in", mmField, "mm", 63.5, FR);
  parsed("1’234 mm", mmField, "mm", 1234, CH);
  parsed("1’ 2\"", mmField, "mm", 355.6, CH);
  parsed("1'2\"", mmField, "mm", 355.6, CH);
  parsed("12,34,567.5 mm", mmField, "mm", 1234567.5, IN);
});

test("a number format is derived from the locale, including the Indian grouping", function () {
  assert.deepStrictEqual(JSON.parse(JSON.stringify(units.deriveNumberFormat("en-IN", "."))), IN);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(units.deriveNumberFormat("es-ES", ","))), DE);
  assert.strictEqual(units.format(12345.5, mmField, { system: "SI", numberFormat: FR }), "12 345,5 mm");
  assert.strictEqual(units.format(9999.96, mmField, { system: "SI", numberFormat: US }), "10,000 mm");
  assert.strictEqual(units.formatEdit(12345.5, mmField, { system: "SI", numberFormat: FR }), "12345,5");
  assert.strictEqual(
    units.formatEdit(1, dimensionField, { system: "IP", numberFormat: DE, dimensionFormat: "ft-in" }),
    '0,03937"'
  );
});

test("exponent notation is read in either locale", function () {
  var densityField = field("density", "kg_m3", "Density");

  parsed("1.2e3 mm", mmField, "mm", 1200);
  parsed("4e-2", mmField, "in", 1.016);
  parsed("1,2e3 mm", mmField, "mm", 1200, DE);
  parsed("1e2", densityField, "kg_m3", 100);
  parsed("1e2 lb/ft³", densityField, "kg_m3", 100 / units.quantities.density.factor);
});

test("every refusal reports its own code", function () {
  code("", mmField, "mm", "empty");
  code("1' 2", mmField, "mm", "malformed");
  code("1'-2", mmField, "mm", "malformed");
  code("4 yd", mmField, "mm", "unsupported_unit");
  code("2 kg", mmField, "mm", "wrong_quantity");
  code("1 " + new Array(300).join("1 "), mmField, "mm", "malformed");
  code("(1 ft) mm", mmField, "mm", "double_unit");
  code("2 in mm", mmField, "mm", "double_unit");
  code("1 / 0", mmField, "mm", "division_by_zero");
  code("1e309 mm", mmField, "mm", "nonfinite");
  code("NaN", mmField, "mm", "nonfinite");
  code("-1 mm", mmField, "mm", "negative");
  code("0", { quantity: "length_mm", unit: "mm", label: "Width", allowZero: false }, "mm", "zero");
  code("4000", { quantity: "length_mm", unit: "mm", label: "Width", min: 1, max: 3000 }, "mm", "out_of_range");
});

test("conductivity reads every datasheet form, by selector or by a typed unit", function () {
  var valueField = field("conductivity", "w_mk");
  function reads(text, unitId, expected) {
    var parsed = parse(text, valueField, unitId);
    assert.strictEqual(parsed.ok, true, text);
    assert.ok(Math.abs(parsed.value - expected) < 0.000001, text + " read " + parsed.value);
  }
  reads("5", "r_per_in", 0.028846);
  reads("1", "btu_in_h_ft2_f", 0.144228);
  reads("5 R/in", "w_mk", 0.028846);
  reads("5 R per inch", "btu_h_ft_f", 0.028846);
  reads("5 h ft2 F/Btu in", "w_mk", 0.028846);
  reads("1 Btu-in/hr-ft2-F", "w_mk", 0.144228);
  reads("0.04 W/(m K)", "r_per_in", 0.04);
  code("0", field("conductivity", "w_mk"), "r_per_in", "zero");
  code("-4", field("conductivity", "w_mk"), "r_per_in", "negative");
  assert.strictEqual(units.inputForms(valueField).map(function (entry) { return entry.id; }).join(),
    "r_per_in,w_mk,btu_h_ft_f,btu_in_h_ft2_f");
  assert.strictEqual(units.defaultInputForm(valueField, { system: "IP" }), "r_per_in");
  assert.strictEqual(units.defaultInputForm(valueField, { system: "SI" }), "w_mk");
  assert.strictEqual(units.inputForms(field("density", "kg_m3")).length, 0);
});

test("each quantity reads its SI and IP unit aliases", function () {
  [
    ["area", "m2", "2 m²", "2 sqft"], ["volume", "m3", "2 m³", "2 ft3"],
    ["u_value", "w_m2k", "2 W/(m² K)", "2 Btu/(h ft² °F)"],
    ["thermal_resistance", "m2k_w", "2 m² K/W", "2 h ft² °F/Btu"],
    ["conductivity", "w_mk", "2 W/(m K)", "2 Btu/(h ft °F)"],
    ["linear_psi", "w_mk", "2 W/mK", "2 btu/hftf"], ["heat_loss_rate", "w_k", "2 W/K", "2 Btu/(h °F)"],
    ["density", "kg_m3", "2 kg/m³", "2 pcf"], ["specific_heat", "j_kgk", "2 J/(kg K)", "2 Btu/(lb °F)"],
    ["airflow", "m3_h", "2 m³/h", "2 ft3/min"], ["temperature", "c", "2 °C", "2 °F"],
    ["temperature_difference", "k", "2 K", "2 deltaF"],
    ["air_permeance", "l_s_m2_75pa", "2 L/(s m²) at 75 Pa", "2 cfm/ft² at 1.57 psf"],
    ["vapor_sd", "sd_m", "2 sd_m", "2 perm"], ["vapor_diffusion_resistance", "mu", "2 μ", "2 perm-in"]
  ].forEach(function (row) {
    var valueField = field(row[0], row[1]);
    assert.strictEqual(parse(row[2], valueField, units.quantities[row[0]].si.id).ok, true, row[2]);
    assert.strictEqual(parse(row[3], valueField, units.quantities[row[0]].ip.id).ok, true, row[3]);
  });
  code("2 kg/m³", field("area", "m2"), "m2", "wrong_quantity");
});

test("an infinite vapour resistance is a value for vapour and a refusal elsewhere", function () {
  assert.strictEqual(parse("∞", field("vapor_sd", "sd_m"), "perm").value, 0);
  assert.strictEqual(parse("∞ perm", field("vapor_sd", "sd_m"), "perm").value, 0);
  code("∞", field("area", "m2"), "m2", "nonfinite");
  assert.strictEqual(units.format(0, field("vapor_sd", "sd_m"), { system: "IP", numberFormat: US }), "∞ perm");
});


test("fractions keep their canonical value in SI and IP without a unit suffix", function () {
  var fraction = { quantity: "fraction", unit: "1", label: "Emissivity", min: 0, max: 1, allowBlank: true };
  ["SI", "IP"].forEach(function (system) {
    assert.strictEqual(units.format(0.95, fraction, { system: system, numberFormat: US }), "0.95");
    assert.strictEqual(units.formatEdit(0.95, fraction, { system: system, numberFormat: DE }), "0,95");
    parsed("0,95", fraction, "1", 0.95, DE);
    parsed("0", fraction, "1", 0);
    parsed("1", fraction, "1", 1);
  });
  code("1.01", fraction, "1", "out_of_range");
  assert.strictEqual(parse("1.01", fraction, "1").message, "Emissivity must be between 0 and 1.");
});
