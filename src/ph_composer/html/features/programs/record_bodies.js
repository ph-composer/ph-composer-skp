/* The Schedules and Equipment Sets subtabs' bodies, read only until their editors land: a Schedule's PH
   form values, its full-load hours and the loads that use it; an Equipment Set's devices as a grid. Every value is
   the `all` row's (features/programs/inventory.rb); nothing here is worked out. */
PhComposerUI.define("features/programs/record_bodies", ["workspace", "units", "unit_preferences", "fields",
  "features/programs/program_loads"],
function (ui, units, preferences, fields, loads) {
  "use strict";
  var el = ui.element;
  var TYPES = { fractional: "Fractional", activity: "Activity level", temperature: "Temperature",
    ventilation: "Ventilation" };
  var PERIODS = { high: "High", standard: "Standard", basic: "Basic", minimum: "Minimum" };
  var REFERENCE = { 1: "PH-case occupants", 2: "Zone occupants", 3: "Bedrooms", 4: "PH-case units",
    5: "User defined", 6: "PH-case floor area", 7: "Zone floor area", 8: "n.a." };

  function metric(label, value) {
    var node = el("div", "pgm-metric");
    node.appendChild(el("small", "", label)); node.appendChild(el("strong", "", value));
    return node;
  }

  function number(value, digits) {
    return value === null || value === undefined ? "—" : String(Math.round(value * Math.pow(10, digits)) /
      Math.pow(10, digits));
  }

  function section(title, rows) {
    var root = el("section", "pgm-readonly");
    var heading = el("h3", "", title);
    heading.appendChild(el("span", "pgm-tag", "Read only"));
    root.appendChild(heading);
    rows.forEach(function (row) { root.appendChild(ui.propertyRow(row[0], row[1], "")); });
    return root;
  }

  /* ---------------------------------------------------------------- Schedules */

  function ScheduleBody() {
    this.root = el("div", "pgm-editor");
  }
  ScheduleBody.prototype.render = function (row) {
    var values = row.values, profile = row.profile || {}, settings = units.profile(fields.TEMPERATURE_C,
      preferences.current());
    var metrics = el("div", "pgm-metrics");
    metrics.appendChild(metric("Type", TYPES[values.type] || values.type));
    if (profile.annual_full_load_hours !== null && profile.annual_full_load_hours !== undefined) {
      metrics.appendChild(metric("Full-load hours [h/a]", number(profile.annual_full_load_hours, 0)));
    }
    metrics.appendChild(metric("Used by", row.use_count === 1 ? "1 load" : row.use_count + " loads"));
    var rows = [];
    if (values.type === "fractional" || values.type === "activity") {
      rows.push(["Starts at [h]", number(values.start_h, 0)], ["Ends at [h]", number(values.end_h, 0)]);
      if (values.type === "fractional") {
        rows.push(["Fraction while operating", number(values.fraction_on, 3)],
          ["Fraction otherwise", number(values.fraction_off, 3)]);
      } else {
        rows.push(["While operating [W per person]", number(values.watts_on, 1)],
          ["Otherwise [W per person]", number(values.watts_off, 1)]);
      }
    } else if (values.type === "temperature") {
      rows.push(["Value", units.format(values.value_c, fields.TEMPERATURE_C, settings)]);
    } else if (values.type === "ventilation") {
      (values.periods || []).forEach(function (period) {
        rows.push([PERIODS[period.period] || period.period, number(period.hours, 0) + " h at " +
          number(period.fraction, 2)]);
      });
    }
    rows.push(["Days per week", number(values.days_per_week, 0)], ["Weeks per year", number(values.weeks_per_year, 0)]);
    var used = el("section", "pgm-used-by");
    used.appendChild(el("h3", "", "Used by"));
    if (!(row.uses || []).length) used.appendChild(el("p", "muted", "No Program uses this Schedule."));
    (row.uses || []).forEach(function (use) {
      var load = loads.load(use.slot.split(".")[0]);
      used.appendChild(el("div", "pgm-use", use.name + " · " + (load ? load.label : use.slot)));
    });
    this.root.replaceChildren(metrics, section("Schedule", rows), used);
  };

  /* ---------------------------------------------------------------- Equipment Sets */

  function demand(device) {
    if (/^phius_/.test(device.type)) return "Phius rule";
    if (device.type === "clothes_dryer" && device.combined_energy_factor !== undefined) {
      return "CEF " + number(device.combined_energy_factor, 2) + " lb/kWh";
    }
    if (device.energy_demand === undefined || device.energy_demand === null) return "—";
    return number(device.energy_demand, 2) + (device.reference_energy_norm === 1 ? " kWh/d" : " kWh/a");
  }

  function SetBody() {
    this.root = el("div", "pgm-editor");
  }
  SetBody.prototype.render = function (row, context) {
    var metrics = el("div", "pgm-metrics");
    metrics.appendChild(metric("Used by", context.zones === 1 ? "1 Zone" : context.zones + " Zones"));
    metrics.appendChild(metric("Devices", String((row.values.devices || []).length)));
    var heading = el("h3", "", "Devices");
    heading.appendChild(el("span", "pgm-tag", "Read only"));
    var table = el("table", "phc-table pgm-devices");
    var head = el("tr");
    ["Device", "Quantity", "Energy demand", "In conditioned space", "Reference quantity"].forEach(function (label) {
      head.appendChild(el("th", "", label));
    });
    var thead = el("thead"); thead.appendChild(head); table.appendChild(thead);
    var body = el("tbody");
    (row.values.devices || []).forEach(function (device) {
      var tr = el("tr");
      var name = el("td", "", device.display_name || ui.titleCase(device.type.replace(/_/g, " ")));
      ui.tooltip(name, ui.titleCase(device.type.replace(/_/g, " ")));
      tr.appendChild(name);
      tr.appendChild(el("td", "is-numeric", number(device.quantity, 2)));
      tr.appendChild(el("td", "", demand(device)));
      tr.appendChild(el("td", "", device.in_conditioned_space ? "Yes" : "No"));
      tr.appendChild(el("td", "", REFERENCE[device.reference_quantity] || "—"));
      body.appendChild(tr);
    });
    table.appendChild(body);
    var devices = el("section", "pgm-readonly");
    devices.appendChild(heading);
    devices.appendChild((row.values.devices || []).length ? table : el("p", "muted", "No devices."));
    this.root.replaceChildren(metrics, devices);
  };

  return { ScheduleBody: ScheduleBody, SetBody: SetBody, TYPES: TYPES };
});
