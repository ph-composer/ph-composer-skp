/* The Mechanical section of the Building Segment settings dialog (context/EXTENSIBILITY.md, "Building Segment
   settings"): whether the Segment has mechanical cooling, its mechanical room temperature, and its summer ventilation,
   the heat recovery bypass and three air change rates. It edits a draft of its namespace's payload, which Zones' Save
   sends with the dialog's other sections in one Undo step; the mechanical feature's validator checks it there too. A
   Segment with no settings shows the defaults, and Save sends all six once the user changes one. The values and
   defaults are Ruby's (features/mechanical/segment/settings.rb); this file labels them, shows the room temperature in
   the unit preference's temperature unit and reads the typed numbers. Whether the cooling switch agrees with the
   heat pumps is the export preflight's warning. */
PhComposerUI.define("features/mechanical/segment_settings", ["panel", "workspace", "units", "unit_preferences",
  "fields"],
function (panel, ui, units, preferences, fields) {
  "use strict";
  var NAMESPACE = "ph_composer.mechanical.segment";
  var BYPASS_MODES = [["none", "None"], ["temperature_controlled", "Temperature controlled"],
    ["enthalpy_controlled", "Enthalpy controlled"], ["always", "Always"]];
  var DEFAULTS = { mechanical_cooling: false, mech_room_temp_c: 20.0, summer_bypass_mode: "always",
    ventilation_system_ach: null, daytime_window_ach: 0.0, nighttime_window_ach: 0.0 };
  // Each air change rate in the order shown, with its label and whether it may be left blank.
  var RATES = [["ventilation_system_ach", "Ventilation system", true],
    ["daytime_window_ach", "Windows, daytime", false], ["nighttime_window_ach", "Windows, nighttime", false]];
  var TEMPERATURE = fields.TEMPERATURE_C;
  var DECIMAL = /^\+?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i;
  var COOLING = "The building has mechanical cooling.";
  var SUMMER = "Summer ventilation. The extract system and night flush values export at their defaults.";

  function offered(value) {
    return BYPASS_MODES.some(function (pair) { return pair[0] === value; });
  }

  /* A typed air change rate: null when blank, the number when it is a decimal of at least 0, else undefined. A
     stored number is kept as it is. */
  function rate(value) {
    if (value === null || value === undefined) return null;
    if (typeof value === "number") return isFinite(value) && value >= 0 ? value : undefined;
    var text = String(value).trim();
    if (text === "") return null;
    var number = DECIMAL.test(text) ? Number(text) : NaN;
    return isFinite(number) ? number : undefined;
  }

  /* The room temperature in °C: a stored number as it is, typed text read in the unit preference's temperature
     unit, else undefined. */
  function temperature(value) {
    if (typeof value === "number") return isFinite(value) ? value : undefined;
    var settings = units.profile(TEMPERATURE, preferences.current());
    var parsed = units.parse(value, TEMPERATURE, units.parseContext(TEMPERATURE, settings));
    return parsed.ok && typeof parsed.value === "number" ? parsed.value : undefined;
  }

  function row(label, content) {
    var part = ui.element("div", "phc-segment-settings-row");
    part.appendChild(ui.element("span", "phc-segment-settings-label", label));
    part.appendChild(content);
    return part;
  }

  /* A number field with its unit after it, on one line. */
  function number(label, text, unit, disabled, changed) {
    var line = ui.element("span", "mech-segment-value");
    var input = ui.element("input");
    input.type = "text"; input.setAttribute("type", "text"); input.setAttribute("inputmode", "decimal");
    input.setAttribute("aria-label", label);
    input.size = 6;
    input.value = text;
    input.disabled = disabled;
    input.addEventListener("input", function () { changed(input.value); });
    line.appendChild(input);
    line.appendChild(ui.element("span", "mech-segment-unit", unit));
    return line;
  }

  panel.segmentSettingsSection(NAMESPACE, {
    title: "Mechanical", order: 60,
    // `draft` is the stored payload, or {} for a Segment with none: a field it lacks shows its default. A stored
    // value the section does not offer is kept, so its problem holds Save until the user corrects it, rather than
    // being replaced unseen.
    render: function (segment, draft, context) {
      var part = ui.element("div");
      // A stored payload that is not an object cannot be edited here; it is kept as stored, and the dialog's
      // other sections still save.
      if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
        part.appendChild(row("Settings", ui.element("span", "", "These settings cannot be read, so they are kept " +
          "as stored and the export refuses them.")));
        return part;
      }
      Object.keys(DEFAULTS).forEach(function (key) {
        if (!Object.prototype.hasOwnProperty.call(draft, key)) draft[key] = DEFAULTS[key];
      });
      var disabled = Boolean(context.readOnly);

      var box = ui.element("input");
      box.type = "checkbox"; box.setAttribute("type", "checkbox"); box.checked = draft.mechanical_cooling === true;
      box.setAttribute("aria-label", "Mechanical cooling");
      box.disabled = disabled;
      box.addEventListener("change", function () { draft.mechanical_cooling = box.checked; context.changed(); });
      var label = ui.element("label", "phc-segment-joins");
      label.appendChild(box);
      label.appendChild(ui.element("span", "", COOLING));
      part.appendChild(row("Mechanical cooling", label));

      var settings = units.profile(TEMPERATURE, preferences.current());
      var room = typeof draft.mech_room_temp_c === "number" ?
        units.formatEdit(draft.mech_room_temp_c, TEMPERATURE, settings) : String(draft.mech_room_temp_c);
      part.appendChild(row("Mechanical room", number("Mechanical room temperature", room,
        units.displayUnit(TEMPERATURE, settings), disabled, function (text) {
          draft.mech_room_temp_c = text; context.changed();
        })));

      part.appendChild(ui.element("p", "phc-zone-option-help", SUMMER));
      var bypass = ui.element("select");
      bypass.setAttribute("aria-label", "Summer bypass");
      BYPASS_MODES.forEach(function (pair) {
        var option = ui.element("option", "", pair[1]);
        option.value = pair[0];
        bypass.appendChild(option);
      });
      bypass.value = draft.summer_bypass_mode;
      bypass.disabled = disabled;
      bypass.addEventListener("change", function () { draft.summer_bypass_mode = bypass.value; context.changed(); });
      part.appendChild(row("Summer bypass", bypass));

      RATES.forEach(function (entry) {
        var key = entry[0], value = draft[key];
        part.appendChild(row(entry[1], number(entry[1] + " air changes", value === null ? "" : String(value), "1/h",
          disabled, function (text) { draft[key] = text; context.changed(); })));
      });
      return part;
    },
    validate: function (draft) {
      var problems = [];
      if (typeof draft.mechanical_cooling !== "boolean") problems.push("Switch mechanical cooling on or off.");
      if (temperature(draft.mech_room_temp_c) === undefined) problems.push("Enter the mechanical room temperature.");
      if (!offered(draft.summer_bypass_mode)) problems.push("Choose a summer bypass.");
      RATES.forEach(function (entry) {
        var value = rate(draft[entry[0]]);
        if (value === undefined || (value === null && !entry[2])) {
          problems.push("Enter the " + entry[1].toLowerCase() + " air changes as a number of at least 0" +
            (entry[2] ? ", or leave it blank." : "."));
        }
      });
      return problems;
    },
    collect: function (draft) {
      var payload = { mechanical_cooling: draft.mechanical_cooling,
        mech_room_temp_c: temperature(draft.mech_room_temp_c), summer_bypass_mode: draft.summer_bypass_mode };
      RATES.forEach(function (entry) { payload[entry[0]] = rate(draft[entry[0]]); });
      return payload;
    }
  });

  return { NAMESPACE: NAMESPACE, BYPASS_MODES: BYPASS_MODES, DEFAULTS: DEFAULTS, rate: rate, temperature: temperature };
});
