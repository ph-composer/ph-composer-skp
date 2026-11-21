/* A Program's eight loads as the Program editor lays them out (features/programs/program.rb): each load's label,
   its values with the unit each is entered in, its Schedule slots by the type each must name, its Phius rule
   when it has one, and the notes its card carries. Values are stored in honeybee's units; an airflow stored in m³/s
   is shown and entered in m³/h (×3600), as the units core reads airflows. Formatting only: what a value means,
   and which are missing, is Ruby's (`missing` on each `programs.all` row). */
PhComposerUI.define("features/programs/program_loads", ["fields", "units", "unit_preferences"],
function (fields, units, preferences) {
  "use strict";
  var M3S = 3600;
  var POWER_PER_AREA = { quantity: "power_per_area", unit: "w_m2", allowBlank: true };
  var PEOPLE_PER_AREA = { quantity: "people_per_area", unit: "people_m2", allowBlank: true };
  var AIRFLOW_PER_PERSON = { quantity: "airflow_per_person", unit: "m3_h_person", allowBlank: true };
  var AIRFLOW_PER_AREA = { quantity: "airflow_per_area", unit: "m3_h_m2", allowBlank: true };
  var AIRFLOW = fields.with(fields.AIRFLOW_M3H, { allowBlank: true });
  var TEMPERATURE = fields.with(fields.TEMPERATURE_C, { allowBlank: true });
  var FRACTION = fields.with(fields.FRACTION, { max: 1 });

  function value(key, label, field, extra) { return Object.assign({ key: key, label: label, field: field }, extra); }
  /* A number with a unit the units core has no quantity for (ACH, %, L/h per m²): read and written in the user's
     number format as a plain number, its unit the same in either system. */
  function plain(key, label, unit, extra) {
    var settings = { allowBlank: true, label: label };
    if (extra && extra.max !== undefined) settings.max = extra.max;
    return Object.assign({ key: key, label: label, plain: unit, field: fields.with(fields.FRACTION, settings) },
      extra);
  }
  function fraction(key, label, extra) { return value(key, label, FRACTION, extra); }
  function slot(key, label, type) { return { key: key, label: label, type: type }; }

  var FRACTIONS = [fraction("radiant_fraction", "Radiant fraction"), fraction("latent_fraction", "Latent fraction"),
    fraction("lost_fraction", "Lost fraction")];

  /* The cards in the order the Programs tab review fixed: six, then two that only EnergyPlus reads. */
  var LOADS = [
    { key: "people", label: "Occupancy", rule: "phius_residential",
      ruleText: "Phius rule: people per Dwelling from its bedrooms, over its floor area, worked out at export.",
      values: [value("people_per_area", "People per area", PEOPLE_PER_AREA)],
      more: [fraction("radiant_fraction", "Radiant fraction"),
        fraction("latent_fraction", "Latent fraction", { allowBlank: true, blank: "Autocalculate" })],
      slots: [slot("occupancy_schedule_id", "Occupancy schedule", "fractional"),
        slot("activity_schedule_id", "Activity schedule", "activity")] },
    { key: "lighting", label: "Lighting", rule: "phius_interior",
      ruleText: "Phius rule: interior lighting per Dwelling from its iCFA, worked out at export.",
      ruleInputs: [fraction("high_efficacy_fraction", "High-efficacy fraction")],
      values: [value("watts_per_area", "Lighting per area", POWER_PER_AREA)],
      more: [fraction("return_air_fraction", "Return air fraction"), fraction("radiant_fraction", "Radiant fraction"),
        fraction("visible_fraction", "Visible fraction")],
      slots: [slot("schedule_id", "Lighting schedule", "fractional")] },
    { key: "ventilation", label: "Ventilation", tag: "Sum of terms",
      values: [value("flow_per_person", "Per person", AIRFLOW_PER_PERSON, { scale: M3S }),
        value("flow_per_area", "Per floor area", AIRFLOW_PER_AREA, { scale: M3S }),
        value("flow_per_zone", "Per Zone", AIRFLOW, { scale: M3S }),
        plain("air_changes_per_hour", "Air changes", "ACH")],
      slots: [slot("schedule_id", "Ventilation schedule", "ventilation")],
      note: "Detailed Space airflows replace the flow, not the schedule." },
    { key: "electric_equipment", label: "Electric equipment",
      values: [value("watts_per_area", "Equipment per area", POWER_PER_AREA)], more: FRACTIONS,
      slots: [slot("schedule_id", "Equipment schedule", "fractional")] },
    { key: "setpoint", label: "Setpoint", tag: "Sets the Segment",
      values: [value("heating_c", "Heating", TEMPERATURE, { schedule: "heating_schedule_id" }),
        value("cooling_c", "Cooling", TEMPERATURE, { schedule: "cooling_schedule_id" }),
        plain("dehumidify_rh", "Dehumidify above", "%", { max: 100 }),
        plain("humidify_rh", "Humidify below", "%", { max: 100 })],
      slots: [slot("heating_schedule_id", "Heating schedule", "temperature"),
        slot("cooling_schedule_id", "Cooling schedule", "temperature")],
      note: "A set point is a value or a Schedule: choosing one clears the other." },
    { key: "infiltration", label: "Infiltration", tag: "Replaced by the Segment's test result",
      values: [value("flow_per_exterior_area", "Per exterior area", AIRFLOW_PER_AREA, { scale: M3S })],
      slots: [slot("schedule_id", "Infiltration schedule", "fractional")],
      note: "A Building Segment with an airtightness test result exports that result instead." },
    { key: "gas_equipment", label: "Gas equipment", energyPlus: true,
      values: [value("watts_per_area", "Gas equipment per area", POWER_PER_AREA)], more: FRACTIONS,
      slots: [slot("schedule_id", "Gas equipment schedule", "fractional")] },
    { key: "service_hot_water", label: "Hot water", energyPlus: true, rule: "building_america",
      ruleText: "Building America rule: hot water per Dwelling from its bedrooms, worked out at export.",
      values: [plain("flow_per_area", "Flow per area", "L/h per m²")],
      more: [value("target_temperature_c", "Target temperature", fields.TEMPERATURE_C),
        fraction("sensible_fraction", "Sensible fraction"), fraction("latent_fraction", "Latent fraction")],
      slots: [slot("schedule_id", "Hot water schedule", "fractional")] }
  ];
  var RULE_LABELS = { phius_residential: "Phius rule", phius_interior: "Phius rule",
    building_america: "Building America rule" };
  var NONE = { fractional: "None (always on)", activity: "None", ventilation: "None (full flow)",
    temperature: "None (use the value)" };

  function profile(entry) { return units.profile(entry.field, preferences.current()); }

  /* The display system, which every unit label follows. */
  function system() { return preferences.current().unitSystem; }

  /* The unit a value's row names: the display unit of its quantity, or its plain unit; `given` is the profile of a
     draft typed in other units. */
  function unit(entry, given) { return entry.plain || units.displayUnit(entry.field, given || profile(entry)); }

  /* The text an input shows for a stored value, in the display units. */
  function editText(entry, stored) {
    if (stored === null || stored === undefined) return "";
    return units.formatEdit(stored * (entry.scale || 1), entry.field, profile(entry), { showUnit: false });
  }

  /* A value for a closed card's line and the header: the number and its unit. */
  function shown(entry, stored) {
    if (stored === null || stored === undefined) return "?";
    var number = stored * (entry.scale || 1);
    if (entry.plain) return units.format(number, entry.field, profile(entry), { showUnit: false }) + " " + entry.plain;
    return units.format(number, entry.field, profile(entry));
  }

  /* A value as a headline number, without its unit; a dash while it is missing. */
  function number(entry, stored) {
    if (stored === null || stored === undefined) return "\u2014";
    return units.format(stored * (entry.scale || 1), entry.field, profile(entry), { showUnit: false });
  }

  /* The stored value a typed entry gives, or `{ error }`, read in `settings`: the unit profile the entry began in,
     so a unit switch while typing never reinterprets it. A blank is null where the value may be missing. */
  function parse(entry, text, settings) {
    var trimmed = String(text).trim();
    if (trimmed === "") {
      return entry.allowBlank || (entry.field && entry.field.allowBlank) ? { value: null } :
        { error: entry.label + " needs a value." };
    }
    var context = units.parseContext(entry.field, settings || profile(entry));
    var result = units.parse(trimmed, entry.field, context);
    if (!result.ok) return { error: result.message };
    if (result.value === null) return { value: null };
    if (result.value < 0 && entry.field.quantity !== "temperature") {
      return { error: entry.label + " cannot be negative." };
    }
    return { value: result.value / (entry.scale || 1) };
  }

  function load(key) { return LOADS.filter(function (entry) { return entry.key === key; })[0]; }

  /* The schedule a slot names, by name, or null. */
  function scheduleName(schedules, id) {
    var row = id && schedules[id];
    return row ? row.values.name : (id ? "Missing Schedule" : null);
  }

  /* A closed card's one line: its values, then its first Schedule. */
  function summary(definition, values, schedules) {
    var parts = [];
    if (definition.rule && values.rule) parts.push(RULE_LABELS[values.rule] || "Rule");
    else if (definition.key === "ventilation") {
      var terms = definition.values.filter(function (entry) {
        return values[entry.key] !== null && values[entry.key] !== undefined && values[entry.key] !== 0;
      }).map(function (entry) { return shown(entry, values[entry.key]); });
      parts.push(terms.length ? terms.join(" + ") : definition.values.every(function (entry) {
        return values[entry.key] === null || values[entry.key] === undefined;
      }) ? "?" : "0");
    } else if (definition.key === "setpoint") {
      parts.push(["heating", "cooling"].map(function (side) {
        var schedule = values[side + "_schedule_id"];
        return schedule ? scheduleName(schedules, schedule) : shown(definition.values[side === "heating" ? 0 : 1],
          values[side + "_c"]);
      }).join(" / "));
    } else parts.push(shown(definition.values[0], values[definition.values[0].key]));
    if (definition.key === "service_hot_water") {
      parts.push(shown(definition.more[0], values.target_temperature_c));
    } else if (definition.key !== "setpoint") {
      var first = scheduleName(schedules, values[definition.slots[0].key]);
      if (first) parts.push(first);
    }
    return parts.join(" · ");
  }

  /* `{ load: [field] }` from a Program row's `missing`. */
  function missingByLoad(row) {
    var found = Object.create(null);
    (row.missing || []).forEach(function (gap) { (found[gap.load] = found[gap.load] || []).push(gap.field); });
    return found;
  }

  /* The label of a missing field, for the amber flag's tooltip. */
  function fieldLabel(definition, key) {
    var all = definition.values.concat(definition.more || [], definition.ruleInputs || [], definition.slots);
    var hit = all.filter(function (entry) { return entry.key === key; })[0];
    if (definition.key === "ventilation" && key === "flow_per_person") return "A ventilation rate";
    return hit ? hit.label : key;
  }

  /* The load with one field changed. A set point is a value or a Schedule, never both, so choosing one clears the
     other side's. */
  function patched(definition, values, key, next) {
    var result = JSON.parse(JSON.stringify(values));
    result[key] = next;
    if (definition.key === "setpoint" && next !== null) {
      var match = /^(heating|cooling)_(c|schedule_id)$/.exec(key);
      if (match) result[match[1] + (match[2] === "c" ? "_schedule_id" : "_c")] = null;
    }
    return result;
  }

  return { LOADS: LOADS, RULE_LABELS: RULE_LABELS, NONE: NONE, load: load, unit: unit, editText: editText,
    shown: shown, number: number, system: system, profile: profile, parse: parse, summary: summary,
    missingByLoad: missingByLoad, fieldLabel: fieldLabel, patched: patched, scheduleName: scheduleName };
});
