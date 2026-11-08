/*
 * The numerical unit core: one parser and one formatter for every quantity the panel shows.
 * Ported and extended from BLDGTYP's web application at revision c55b519b:
 * units/thermal.ts, material.ts, airflow.ts, temperature.ts, length.ts,
 * numberUnits.ts, and units/length/formatFeetInches.ts,
 * parseFeetInches.ts, evaluateExpression.ts, displayUnitConverter.ts,
 * including the vectors in units.test.ts and units/length/__tests__/.
 */
PhComposerUI.define("units", ["length_expression", "unit_numbers", "unit_tables"],
  function (lengthExpression, numbers, tables) {
  "use strict";
  var LENGTH_UNITS = tables.LENGTH_UNITS, QUANTITIES = tables.QUANTITIES, DIMENSION_FORMATS = tables.DIMENSION_FORMATS;
  var DIMENSION_BY_ID = tables.DIMENSION_BY_ID, MAX_INPUT_LENGTH = tables.MAX_INPUT_LENGTH,
    METRES_PER_INCH = tables.METRES_PER_INCH;
  var classifyUnit = tables.classifyUnit, toBase = tables.toBase, fromBase = tables.fromBase;
  var baseToUnit = tables.baseToUnit, unitToBase = tables.unitToBase, displayValue = tables.displayValue,
    errorResult = tables.errorResult;
  var MESSAGES = tables.MESSAGES, codeError = tables.codeError, unknownUnitError = tables.unknownUnitError,
    titleCase = tables.titleCase;
  var deriveNumberFormat = numbers.deriveNumberFormat, normalizeNumberFormat = numbers.normalizeNumberFormat;
  var parseRegionalNumber = numbers.parseRegionalNumber;
  var parseLengthExpression = lengthExpression.parseLengthExpression,
    defaultLengthUnit = lengthExpression.defaultLengthUnit;

  function unitLabel(definition, unitId) {
    if (definition.length) return defaultLengthUnit({ defaultUnit: unitId });
    return (unitId === definition.ip.id ? definition.ip : definition.si).label;
  }

  function inputForm(definition, unitId) {
    return (definition.forms || []).filter(function (entry) { return entry.id === unitId; })[0];
  }

  function formValue(form, definition, base) {
    if (form.reciprocal) return form.reciprocal / base;
    if (form.factor) return base * form.factor;
    return baseToUnit(base, definition, form.id === definition.ip.id ? "IP" : "SI");
  }

  function validate(value, field, definition, settings) {
    var label = String(field.label || titleCase(definition.label));
    var min = field.min !== undefined ? field.min : definition.min;
    var max = field.max;
    var signed = field.allowNegative !== undefined ? Boolean(field.allowNegative) : Boolean(definition.signed);
    var units = unitLabel(definition, settings.defaultUnit || definition.si.id);
    var suffix = units ? " " + units : "";
    if (!isFinite(value)) return errorResult("nonfinite", MESSAGES.nonfinite);
    if (value < 0 && !signed) return errorResult("negative", label + " cannot be negative.");
    if (field.allowZero === false && value === 0) return errorResult("zero", label + " must be greater than zero.");
    if (min !== undefined && max !== undefined && (value < min || value > max)) return errorResult("out_of_range",
      label + " must be between " + min + " and " + max + suffix + ".");
    if (min !== undefined && value < min) return errorResult("out_of_range",
      label + " must be at least " + min + suffix + ".");
    if (max !== undefined && value > max) return errorResult("out_of_range",
      label + " must be at most " + max + suffix + ".");
    // Rounding in the canonical unit removes floating-point noise before a value reaches a command.
    return { ok: true, value: Math.round(value * 1000000000) / 1000000000 };
  }

  function parseValue(trimmed, field, definition, settings) {
    var match = /^([+\-]?[0-9.,’'   ]*(?:[eE][+\-]?\d+)?)(.*)$/.exec(trimmed);
    var unitText = match[2].trim();
    var parsed = match[1].trim() ?
      parseRegionalNumber(match[1], settings.numberFormat) : { ok: false, code: "malformed" };
    var unitId = settings.defaultUnit || definition.si.id;
    var info;
    var system;
    var converting;
    if (!parsed.ok && parsed.code !== "malformed") return codeError(parsed.code, definition, settings);
    if (unitText) unitId = unitText;
    if (unitText || (unitId !== definition.si.id && unitId !== definition.ip.id)) {
      info = classifyUnit(unitId, definition.id);
      if (!info.unit) return unknownUnitError(unitId, definition);
      unitId = info.unit;
    }
    if (!parsed.ok) return codeError("malformed", definition, settings);
    converting = inputForm(definition, unitId);
    if (converting && (converting.reciprocal || converting.factor)) {
      if (converting.reciprocal && parsed.value === 0) return errorResult("zero",
        titleCase(field.label || definition.label) + " must be greater than zero.");
      return validate(converting.reciprocal ? converting.reciprocal / parsed.value : parsed.value / converting.factor,
        field, definition, settings);
    }
    system = unitId === definition.ip.id && unitId !== definition.si.id ? "IP" : "SI";
    if (definition.reciprocal && system === "IP" && parsed.value === 0) return errorResult("zero",
      titleCase(definition.label) + " must be greater than zero.");
    return validate(unitToBase(parsed.value, definition, system), field, definition, settings);
  }

  function parse(text, field, context) {
    var definition = QUANTITIES[field.quantity];
    var options = context || {};
    var settings = { defaultUnit: options.defaultUnit, numberFormat: normalizeNumberFormat(options.numberFormat) };
    var trimmed = String(text === null || text === undefined ? "" : text).trim();
    var infinite = /^\+?(?:∞|infinity)(?:\s+(.+))?$/i.exec(trimmed);
    var parsed;
    if (!definition) return errorResult("wrong_quantity", "Unknown quantity.");
    if (!trimmed) {
      if (field.allowBlank) return { ok: true, value: null };
      return errorResult("empty", "Enter " + (definition.length ? "a length" : definition.label) + ".");
    }
    if (trimmed.length > MAX_INPUT_LENGTH) return codeError("malformed", definition, settings);
    if (/^[+\-]?nan$/i.test(trimmed)) return codeError("nonfinite", definition, settings);
    if (infinite) {
      if (definition.infiniteAtZero &&
          (!infinite[1] || classifyUnit(infinite[1], definition.id).unit === definition.ip.id)) {
        return validate(0, field, definition, settings);
      }
      return codeError("nonfinite", definition, settings);
    }
    if (!definition.length) return parseValue(trimmed, field, definition, settings);
    parsed = parseLengthExpression(trimmed, settings);
    if (parsed.error === "unsupported_unit" || parsed.error === "wrong_quantity") {
      return unknownUnitError(parsed.data, definition);
    }
    if (parsed.error) return codeError(parsed.error, definition, settings);
    return validate(fromBase(parsed.metres, field, definition), field, definition, settings);
  }

  function roundedText(value, digits, format, grouping) {
    var parts = Math.abs(value).toFixed(digits).split(".");
    var integer = parts[0];
    var fraction = parts[1] ? parts[1].replace(/0+$/, "") : "";
    var groups = [];
    var size;
    if (grouping && Number(integer) >= 10000) {
      while (integer.length) {
        size = format.groupSizes[Math.min(groups.length, format.groupSizes.length - 1)];
        groups.unshift(integer.slice(Math.max(0, integer.length - size)));
        integer = integer.slice(0, Math.max(0, integer.length - size));
      }
      integer = groups.join(format.group);
    }
    return (value < 0 ? "-" : "") + integer + (fraction ? format.decimal + fraction : "");
  }

  function gcd(left, right) { while (right) { var next = left % right; left = right; right = next; } return left; }

  /* Whole inches and a reduced sixteenth, from an integer count of sixteenths: 104 is "6-1/2". */
  function inchText(sixteenths) {
    var whole = Math.floor(sixteenths / 16);
    var numerator = sixteenths % 16;
    var divisor = gcd(numerator, 16);
    if (!numerator) return String(whole);
    return (whole ? whole + "-" : "") + numerator / divisor + "/" + 16 / divisor;
  }

  function architectural(inches, formatId, edit, format) {
    var sign = inches < 0 ? "-" : "";
    var absolute = Math.abs(inches);
    var sixteenths = Math.round(absolute * 16);
    var feet;
    var rest;
    // A thin layer never reads as zero, and a seed that is not exact at 1/16 keeps its decimal value.
    if ((absolute > 0 && sixteenths === 0) || (edit && Math.abs(absolute * 16 - sixteenths) >= 0.000000001)) {
      return sign + roundedText(absolute, edit ? 6 : 3, format, false) + "\"";
    }
    if (formatId === "in-frac") return sign + inchText(sixteenths) + "\"";
    feet = Math.floor(sixteenths / 192);
    rest = sixteenths - feet * 192;
    if (!feet) return sign + inchText(rest) + "\"";
    return sign + feet + "'" + (rest ? " " + inchText(rest) + "\"" : "");
  }

  function render(value, field, profile, options, edit) {
    var definition = QUANTITIES[field.quantity];
    var settings = profile || {};
    var opts = options || {};
    var format = normalizeNumberFormat(settings.numberFormat);
    var system = String(settings.system || "SI").toUpperCase() === "IP" ? "IP" : "SI";
    var dimension = definition.length && DIMENSION_BY_ID[settings.dimensionFormat];
    var base;
    var converted;
    var text;
    var form;
    var digits;
    if (value === null || value === undefined || value === "") return "";
    base = toBase(Number(value), field, definition);
    if (dimension && dimension.architectural) return architectural(base / METRES_PER_INCH, dimension.id, edit, format);
    if (dimension) {
      return roundedText(base / LENGTH_UNITS[dimension.id].metres,
        edit ? dimension.editDigits : dimension.displayDigits, format, false) +
        (edit || opts.showUnit === false ? "" : " " + dimension.id);
    }
    form = field.inputForm && inputForm(definition, field.inputForm);
    converted = form ? formValue(form, definition, base) : baseToUnit(base, definition, system);
    // A value shown in a chosen form is read back in it, so it keeps more digits than a display does.
    digits = opts.precision !== undefined ? opts.precision : (form ? 6 : definition.precision[system]);
    text = converted === Infinity ? "∞" : roundedText(converted, digits, format, !edit && opts.useGrouping !== false);
    var label = (system === "IP" ? definition.ip : definition.si).label;
    return edit || opts.showUnit === false || !label ? text : text + " " + label;
  }

  function format(value, field, profile, options) { return render(value, field, profile, options, false); }
  function formatEdit(value, field, profile, options) { return render(value, field, profile, options, true); }

  /* Convert the preference-store shape into the stateless formatter/parser profile. A field that names
     a dimension scope (`field.scope`) takes that scope's remembered format, or the system's default format
     when the scope has none yet; the format applies to length quantities only. */
  function profile(field, preferences) {
    var current;
    var system;
    var scope = field && field.scope;
    // An already resolved profile (a draft's start profile) is used as is.
    if (preferences && preferences.system) return preferences;
    // peek() avoids cloning the stored profile once per formatted value in table loops.
    current = preferences || (api.preferences && (api.preferences.peek || api.preferences.current)()) || {};
    system = current.unitSystem === "IP" ? "IP" : "SI";
    return {
      system: system,
      numberFormat: current.numberFormat,
      dimensionFormat: scope ? ((current.dimensionFormats || {})[scope] || api.dimensionDefaults)[system] : undefined
    };
  }

  function displayUnit(field, settings) {
    var definition = QUANTITIES[field.quantity];
    var resolved = profile(field, settings);
    var dimension = definition && definition.length && DIMENSION_BY_ID[resolved.dimensionFormat];
    if (!definition) return "";
    if (dimension) return dimension.id;
    return (resolved.system === "IP" ? definition.ip : definition.si).label;
  }

  function parseContext(field, settings) {
    var definition = QUANTITIES[field.quantity];
    var resolved = profile(field, settings);
    return {
      // A field with an input-form selector reads a bare number in the form it shows.
      defaultUnit: field.inputForm || resolved.dimensionFormat ||
        (resolved.system === "IP" ? definition.ip.id : definition.si.id),
      numberFormat: resolved.numberFormat
    };
  }

  /* The datasheet forms a quantity can be entered in, in menu order, and the one offered first in a unit
     system. A quantity with one reading of its numbers has none. */
  function inputForms(field) {
    var definition = QUANTITIES[field.quantity];
    return definition && definition.forms ? definition.forms.slice() : [];
  }
  function defaultInputForm(field, settings) {
    var definition = QUANTITIES[field.quantity];
    return definition && definition.defaultForm ? definition.defaultForm[profile(field, settings).system] : null;
  }

  function header(label, field, settings) {
    var suffix = displayUnit(field, settings);
    return suffix ? label + " " + suffix : label;
  }

  /* Ruby keeps its legacy prose beside these presentation-only parts. Each quantity value is
     canonical SI and is formatted in the current panel profile here, never in Ruby. */
  function formatParts(parts, fallback, settings) {
    if (!parts || !parts.length) return fallback === undefined ? "" : fallback;
    return parts.map(function (part) {
      var definition;
      if (part.text !== undefined) return String(part.text);
      definition = QUANTITIES[part.quantity];
      if (!definition) return "";
      var field = { quantity: part.quantity, unit: part.unit || definition.si.id };
      return format(part.value, field, profile(field, settings));
    }).join("");
  }

  var api = {
    quantities: QUANTITIES,
    dimensionFormats: DIMENSION_FORMATS,
    dimensionDefaults: { SI: "mm", IP: "in" },
    deriveNumberFormat: deriveNumberFormat,
    toDisplay: displayValue,
    parse: parse,
    format: format,
    formatEdit: formatEdit,
    profile: profile,
    displayUnit: displayUnit,
    parseContext: parseContext,
    inputForms: inputForms,
    defaultInputForm: defaultInputForm,
    header: header,
    formatParts: formatParts
  };
  // unit_preferences attaches `preferences`; profile() reads it late so the numerical core stays stateless.
  return api;
});
