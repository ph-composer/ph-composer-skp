/* Regional number formats: deriving one from a locale, and reading a number written in it. */
PhComposerUI.define("unit_numbers", ["unit_tables"], function (tables) {
  "use strict";
  var SPACE_GROUPS = tables.SPACE_GROUPS;

  function normalizeNumberFormat(numberFormat) {
    var value = numberFormat || {};
    return {
      decimal: typeof value.decimal === "string" && value.decimal ? value.decimal : ".",
      group: typeof value.group === "string" ? value.group : ",",
      groupSizes: value.groupSizes && value.groupSizes.length ? value.groupSizes : [3]
    };
  }

  function deriveNumberFormat(locale, sketchupDecimal) {
    var decimal = sketchupDecimal === "," ? "," : ".";
    var result = { decimal: decimal, group: decimal === "." ? "," : ".", groupSizes: [3] };
    var parts;
    var integers;
    var intlDecimal;
    var group;
    try {
      parts = new Intl.NumberFormat(locale || "en-US").formatToParts(1234567890.5);
      integers = parts.filter(function (part) {
        return part.type === "integer";
      }).map(function (part) { return part.value.length; });
      intlDecimal = parts.filter(function (part) { return part.type === "decimal"; })[0];
      group = parts.filter(function (part) { return part.type === "group"; })[0];
      // A custom macOS decimal that disagrees with the region keeps SketchUp's decimal and the other separator.
      if (group && (!intlDecimal || intlDecimal.value === decimal)) result.group = group.value;
      if (integers.length > 1) {
        result.groupSizes = [integers[integers.length - 1]];
        if (integers.length > 2 &&
          integers[integers.length - 2] !== result.groupSizes[0]) result.groupSizes.push(integers[integers.length - 2]);
      }
    } catch (error) {
      // Without Intl the fallback group and sizes stand.
    }
    return result;
  }

  function isSpaceGroup(group) { return group === " " || group === " " || group === " "; }

  /* The digits of a correctly grouped integer, or null. */
  function groupedDigits(integer, format) {
    var group = format.group;
    var normalized = integer;
    var primary = format.groupSizes[0];
    var secondary = format.groupSizes[1] || primary;
    var parts;
    var index;
    if (!group) return null;
    if (isSpaceGroup(group)) normalized = normalized.replace(SPACE_GROUPS, group);
    if (group === "’") normalized = normalized.replace(/'/g, "’");
    parts = normalized.split(group);
    if (parts.length < 2 || !/^\d+$/.test(parts.join("")) || parts[parts.length - 1].length !== primary) return null;
    for (index = parts.length - 2; index > 0; index -= 1) if (parts[index].length !== secondary) return null;
    return parts[0].length <= secondary ? parts.join("") : null;
  }

  function parseRegionalNumber(text, format) {
    var match = /^([+\-]?)(.*?)([eE][+\-]?\d+)?$/.exec(String(text).trim());
    // A line or paragraph separator inside the text matches nothing: unreadable, not an exception.
    if (!match) return { ok: false, code: "malformed" };
    var body = match[2];
    var parts;
    var integer;
    var fraction;
    var digits;
    var value;
    if (!body || /[eE]/.test(body)) return { ok: false, code: "malformed" };
    parts = body.split(format.decimal);
    if (parts.length > 2) return { ok: false, code: "number_format" };
    fraction = parts.length === 2 ? parts[1] : null;
    integer = parts[0] || (fraction !== null ? "0" : "");
    if (fraction !== null && !/^\d+$/.test(fraction)) return { ok: false, code: "number_format" };
    if (!integer) return { ok: false, code: "malformed" };
    digits = /^\d+$/.test(integer) ? integer : groupedDigits(integer, format);
    if (digits === null) return { ok: false, code: /[.,’'   ]/.test(integer) ? "number_format" : "malformed" };
    value = Number(match[1] + digits + (fraction === null ? "" : "." + fraction) + (match[3] || ""));
    return isFinite(value) ? { ok: true, value: value } : { ok: false, code: "nonfinite" };
  }

  /* Canonical field values to the quantity's base (metres for lengths, the SI unit otherwise) and back. */

  return { isSpaceGroup: isSpaceGroup, normalizeNumberFormat: normalizeNumberFormat,
    deriveNumberFormat: deriveNumberFormat, parseRegionalNumber: parseRegionalNumber };
});
