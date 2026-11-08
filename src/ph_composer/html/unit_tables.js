/* The unit tables: the conversion constants, the quantity definitions with their SI and IP units, the length
   units and dimension formats, and the refusal messages every reading shares. */
PhComposerUI.define("unit_tables", [], function () {
  "use strict";

  var METRES_PER_FOOT = 0.3048;
  var METRES_PER_INCH = 0.0254;
  var KG_PER_POUND = 0.45359237;
  var JOULES_PER_BTU = 1055.05585262;
  var F_PER_K = 1.8;
  var FT2_PER_M2 = 1 / (METRES_PER_FOOT * METRES_PER_FOOT);
  var FT3_PER_M3 = FT2_PER_M2 / METRES_PER_FOOT;
  var BTU_H_PER_W = 3600 / JOULES_PER_BTU;
  var U_FACTOR = BTU_H_PER_W / FT2_PER_M2 / F_PER_K;
  var CONDUCTIVITY_FACTOR = BTU_H_PER_W * METRES_PER_FOOT / F_PER_K;
  var MAX_INPUT_LENGTH = 256;
  var SPACE_GROUPS = /[   ]/g;

  // Length units in metres: one table drives unit lookup, conversion, dimension display and messages.
  var LENGTH_UNITS = {
    mm: { metres: 0.001, aliases: ["millimeter", "millimeters", "millimetre", "millimetres"] },
    cm: { metres: 0.01, aliases: ["centimeter", "centimeters", "centimetre", "centimetres"] },
    m: { metres: 1, aliases: ["meter", "meters", "metre", "metres"] },
    in: { metres: METRES_PER_INCH, aliases: ["inch", "inches", "\""] },
    ft: { metres: METRES_PER_FOOT, aliases: ["foot", "feet", "'"] }
  };
  var LENGTH_UNIT_LIST = "mm, cm, m, in or ft";

  function unit(id, label, aliases) { return { id: id, label: label, aliases: aliases || [] }; }
  /* One way a datasheet states a quantity, offered by the input-form selector. A form with a `factor` or a
     `reciprocal` is a unit of its own (form = base * factor, or reciprocal / base); one naming the quantity's
     SI or IP unit converts as that unit does. */
  function form(id, label, conversion, aliases) {
    return Object.assign({ id: id, label: label, aliases: aliases || [] }, conversion);
  }

  /* Conversion data per quantity. Lengths convert through LENGTH_UNITS; every other quantity's SI unit is
     its canonical unit, and IP = SI * factor + offset, or reciprocal / SI for the vapour pairs.
     Aliases list only extra spellings: each unit's id and label are registered too. */
  var QUANTITIES = {
    fraction: { label: "fraction", factor: 1, min: 0, precision: { SI: 3, IP: 3 },
    si: unit("1", ""), ip: unit("1", "") },
    length: { label: "length", length: true, si: unit("m", "m"), ip: unit("ft", "ft"), precision: { SI: 2, IP: 2 } },
    length_mm: { label: "length", length: true, si: unit("mm", "mm"), ip: unit("in", "in"),
    precision: { SI: 1, IP: 2 } },
    area: {
      label: "area", factor: FT2_PER_M2, precision: { SI: 2, IP: 2 },
      si: unit("m2", "m²", ["sqm", "square meter", "square meters", "square metre", "square metres"]),
      ip: unit("ft2", "ft²", ["sf", "sqft", "square foot", "square feet"])
    },
    volume: {
      label: "volume", factor: FT3_PER_M3, precision: { SI: 2, IP: 2 },
      si: unit("m3", "m³", ["cum", "cubic meter", "cubic meters", "cubic metre", "cubic metres"]),
      ip: unit("ft3", "ft³", ["cuft", "cubic foot", "cubic feet"])
    },
    u_value: { label: "U-value", factor: U_FACTOR, precision: { SI: 3, IP: 3 }, si: unit("w_m2k", "W/(m² K)"),
    ip: unit("btu_h_ft2_f", "Btu/(h ft² °F)") },
    thermal_resistance: { label: "thermal resistance", factor: 1 / U_FACTOR, precision: { SI: 2, IP: 2 },
    si: unit("m2k_w", "m² K/W"), ip: unit("h_ft2_f_btu", "h ft² °F/Btu") },
    conductivity: { label: "conductivity", factor: CONDUCTIVITY_FACTOR, precision: { SI: 3, IP: 3 },
    si: unit("w_mk", "W/(m K)"), ip: unit("btu_h_ft_f", "Btu/(h ft °F)"),
    defaultForm: { SI: "w_mk", IP: "r_per_in" },
    forms: [
      form("r_per_in", "R per inch", { reciprocal: METRES_PER_INCH / U_FACTOR },
        ["r/in", "r/inch", "r per in", "r per inch", "h ft2 F/Btu in"]),
      form("w_mk", "W/(m K)"),
      form("btu_h_ft_f", "Btu/(h ft °F)"),
      form("btu_in_h_ft2_f", "Btu in/(h ft² °F)", { factor: U_FACTOR / METRES_PER_INCH })
    ] },
    linear_psi: { label: "psi-value", factor: CONDUCTIVITY_FACTOR, signed: true, precision: { SI: 3, IP: 3 },
    si: unit("w_mk", "W/(m K)"), ip: unit("btu_h_ft_f", "Btu/(h ft °F)") },
    heat_loss_rate: { label: "heat loss rate", factor: BTU_H_PER_W / F_PER_K, precision: { SI: 3, IP: 3 },
    si: unit("w_k", "W/K"), ip: unit("btu_h_f", "Btu/(h °F)") },
    density: { label: "density", factor: 1 / KG_PER_POUND / FT3_PER_M3, precision: { SI: 1, IP: 1 },
    si: unit("kg_m3", "kg/m³"), ip: unit("lb_ft3", "lb/ft³", ["pcf"]) },
    specific_heat: { label: "specific heat", factor: KG_PER_POUND / JOULES_PER_BTU / F_PER_K,
    precision: { SI: 0, IP: 3 }, si: unit("j_kgk", "J/(kg K)"), ip: unit("btu_lb_f", "Btu/(lb °F)") },
    airflow: { label: "airflow", factor: FT3_PER_M3 / 60, precision: { SI: 1, IP: 1 }, si: unit("m3_h", "m³/h"),
    ip: unit("cfm", "cfm", ["ft3/min"]) },
    temperature: { label: "temperature", factor: F_PER_K, offset: 32, signed: true, precision: { SI: 1, IP: 1 },
    si: unit("c", "°C", ["degc"]), ip: unit("f", "°F", ["degf"]) },
    temperature_difference: { label: "temperature difference", factor: F_PER_K, signed: true,
    precision: { SI: 1, IP: 1 }, si: unit("k", "K", ["kelvin"]), ip: unit("delta_f", "°F", ["degf", "deltaf"]) },
    air_permeance: { label: "air permeance", factor: FT3_PER_M3 * 60 * 0.001 / FT2_PER_M2, precision: { SI: 4, IP: 4 },
    si: unit("l_s_m2_75pa", "L/(s m²) at 75 Pa"), ip: unit("cfm_ft2_75pa", "cfm/ft² at 1.57 psf") },
    vapor_sd: { label: "equivalent air-layer thickness", reciprocal: 3.496, infiniteAtZero: true,
    precision: { SI: 2, IP: 3 }, si: unit("sd_m", "m", ["sdm"]), ip: unit("perm", "perm") },
    vapor_diffusion_resistance: { label: "vapor diffusion resistance", reciprocal: 137.6, min: 1,
    precision: { SI: 1, IP: 2 }, si: unit("mu", "μ"), ip: unit("perm_in", "perm-in") }
  };

  var DIMENSION_FORMATS = [
    { id: "mm", label: "Millimetres (mm)", system: "SI", displayDigits: 2, editDigits: 6 },
    { id: "cm", label: "Centimetres (cm)", system: "SI", displayDigits: 3, editDigits: 7 },
    { id: "m", label: "Metres (m)", system: "SI", displayDigits: 5, editDigits: 9 },
    { id: "in", label: "Decimal inches (in)", system: "IP", displayDigits: 3, editDigits: 6 },
    { id: "ft", label: "Decimal feet (ft)", system: "IP", displayDigits: 4, editDigits: 7 },
    { id: "ft-in", label: "Feet and inches (ft-in)", system: "IP", architectural: true },
    { id: "in-frac", label: "Fractional inches (in-frac)", system: "IP", architectural: true }
  ];
  var DIMENSION_BY_ID = {};
  var UNIT_ALIASES = {};
  DIMENSION_FORMATS.forEach(function (entry) { DIMENSION_BY_ID[entry.id] = entry; });

  function normalizeAlias(text) {
    return String(text).toLowerCase().replace(/²/g, "2").replace(/³/g, "3")
      .replace(/hr/g, "h").replace(/[\s·*\-()^°]/g, "");
  }
  function register(alias, entry) {
    var key = normalizeAlias(alias);
    (UNIT_ALIASES[key] = UNIT_ALIASES[key] || []).push(entry);
  }
  Object.keys(LENGTH_UNITS).forEach(function (id) {
    [id].concat(LENGTH_UNITS[id].aliases).forEach(function (alias) {
      register(alias, { quantity: "length", unit: id, label: "length" });
    });
  });
  Object.keys(QUANTITIES).forEach(function (id) {
    var definition = QUANTITIES[id];
    definition.id = id;
    if (definition.length) return;
    [definition.si, definition.ip].concat(definition.forms || []).forEach(function (entry) {
      [entry.id, entry.label].concat(entry.aliases).forEach(function (alias) {
        register(alias, { quantity: id, unit: entry.id, label: definition.label });
      });
    });
  });
  register("kg", { quantity: "mass", label: "mass" });

  /* The unit a text names for the expected quantity, or why it cannot be used. Lengths share one quantity. */
  function classifyUnit(text, quantityId) {
    var matches = UNIT_ALIASES[normalizeAlias(text)] || [];
    var expected = QUANTITIES[quantityId] && QUANTITIES[quantityId].length ? "length" : quantityId;
    var index;
    for (index = 0; index < matches.length; index += 1) {
      if (matches[index].quantity === expected) return { unit: matches[index].unit };
    }
    return matches.length ? { wrongLabel: matches[0].label } : {};
  }

  function toBase(value, field, definition) {
    return definition.length ? value * LENGTH_UNITS[field.unit || definition.si.id].metres : value;
  }
  function fromBase(value, field, definition) {
    return definition.length ? value / LENGTH_UNITS[field.unit || definition.si.id].metres : value;
  }

  function baseToUnit(base, definition, system) {
    if (definition.length) return base / LENGTH_UNITS[(system === "IP" ? definition.ip : definition.si).id].metres;
    if (system !== "IP") return base;
    if (definition.reciprocal) return definition.reciprocal / base;
    return base * definition.factor + (definition.offset || 0);
  }
  function unitToBase(value, definition, system) {
    if (system !== "IP") return value;
    if (definition.reciprocal) return definition.reciprocal / value;
    return (value - (definition.offset || 0)) / definition.factor;
  }

  function displayValue(value, field, system) {
    var definition = QUANTITIES[field.quantity];
    return baseToUnit(toBase(Number(value), field, definition), definition, system === "IP" ? "IP" : "SI");
  }

  function errorResult(code, message) { return { ok: false, code: code, message: message }; }
  function titleCase(text) { return text.charAt(0).toUpperCase() + text.slice(1); }

  var MESSAGES = {
    non_length_result: "The result must be a length.",
    double_unit: "A unit cannot follow a value that already has one.",
    division_by_zero: "Cannot divide by zero.",
    nonfinite: "Enter a finite number."
  };

  function numberFormatMessage(format) {
    var integer = format.groupSizes.length > 1 ?
      "12" + format.group + "34" + format.group + "567" : "1" + format.group + "200";
    return "Use \"" + format.decimal + "\" for decimals, as in " + integer + format.decimal + "5.";
  }

  function malformedLengthMessage(defaultUnit) {
    if (defaultUnit === "ft-in") return "Enter a length, for example 2' 6\", 30 in or 762 mm.";
    if (defaultUnit === "in-frac") return "Enter a length, for example 6-1/2\", 6.5 in or 165.1 mm.";
    if (defaultUnit === "in" || defaultUnit === "ft") return "Enter a length, for example 12, 1' 6\" or 1.2 m.";
    return "Enter a length, for example 1200, 1' 6\" or 1.2 m.";
  }

  function codeError(code, definition, settings) {
    if (code === "number_format") return errorResult(code, numberFormatMessage(settings.numberFormat));
    if (MESSAGES[code]) return errorResult(code, MESSAGES[code]);
    return errorResult("malformed",
      definition.length ? malformedLengthMessage(settings.defaultUnit) : "Enter a number.");
  }

  function unknownUnitError(text, definition) {
    var info = classifyUnit(text, definition.id);
    if (info.wrongLabel) return errorResult("wrong_quantity",
      "Expected " + (definition.length ? "a length" : definition.label) + "; " + text + " is a " + info.wrongLabel +
      " unit.");
    return errorResult("unsupported_unit", "\"" + text + "\" is not a supported unit" +
      (definition.length ? ". Use " + LENGTH_UNIT_LIST + "." : " for " + definition.label + "."));
  }

  return { METRES_PER_FOOT: METRES_PER_FOOT, METRES_PER_INCH: METRES_PER_INCH, MAX_INPUT_LENGTH: MAX_INPUT_LENGTH,
    SPACE_GROUPS: SPACE_GROUPS, LENGTH_UNITS: LENGTH_UNITS, LENGTH_UNIT_LIST: LENGTH_UNIT_LIST, QUANTITIES: QUANTITIES,
    DIMENSION_FORMATS: DIMENSION_FORMATS, DIMENSION_BY_ID: DIMENSION_BY_ID, normalizeAlias: normalizeAlias,
    classifyUnit: classifyUnit, toBase: toBase, fromBase: fromBase, baseToUnit: baseToUnit, unitToBase: unitToBase,
    displayValue: displayValue, errorResult: errorResult, titleCase: titleCase, MESSAGES: MESSAGES,
    numberFormatMessage: numberFormatMessage, malformedLengthMessage: malformedLengthMessage, codeError: codeError,
    unknownUnitError: unknownUnitError };
});
