"use strict";

/* The Schedule and Equipment Set editors on the Programs tab (html/features/programs/schedule_editor.js,
   equipment_set_editor.js, device_dialog.js): each Schedule value commits as one schedules.update guarded by the
   value as drawn, a whole number refuses a fraction, a temperature reads in the display units, ventilation hours
   wait as one draft until they total 24, and the strip and week row draw the row's profile; devices are added,
   edited and deleted one at a time through the dialog the device types lay out, a gas dryer's gas fields showing
   only for a gas dryer. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var REVISION = 3;
var PREFIX = "ph_composer.programs";
var DEVICE_TYPES = JSON.parse(fs.readFileSync(path.join(__dirname, "fixtures/programs/device_types.json"), "utf8"));
var WEEK = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
function repeat(value, count) { var out = []; while (out.length < count) out.push(value); return out; }
var VENTILATION = [{ period: "high", hours: 2, fraction: 1 }, { period: "standard", hours: 14, fraction: 0.77 },
  { period: "basic", hours: 6, fraction: 0.54 }, { period: "minimum", hours: 2, fraction: 0.4 }];

function row(kind, id, name, values, extra) {
  return Object.assign({ kind: PREFIX + "." + kind, id: id, schema_version: 1, user_data: {}, extension_status: {},
    stored: true, values: Object.assign({ name: name, notes: "", datasheet_links: [], source: { kind: "manual" } },
      values) }, extra);
}

function schedule(id, name, values, profile) {
  return row("schedule", id, name, Object.assign({ days_per_week: 7, weeks_per_year: 52 }, values),
    { uses: [{ program_id: "pgm_a", name: "Office", slot: "people.occupancy_schedule_id" }], use_count: 1,
      profile: profile });
}

function schedules(changes) {
  var office = Object.assign({ type: "fractional", start_h: 7, end_h: 19, fraction_on: 0.8, fraction_off: 0,
    days_per_week: 5 }, (changes || {}).office);
  return [schedule("sch_office", "Office hours", office, { hours: [0, 0, 0, 0, 0, 0, 0, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8,
    0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0, 0, 0, 0, 0], daily_full_load_hours: 9.6, annual_full_load_hours: 2496,
  weekdays: ["monday", "tuesday", "wednesday", "thursday", "friday"] }),
  schedule("sch_heat", "Heating", { type: "temperature", value_c: 20 }, { hours: repeat(20, 24),
    daily_full_load_hours: null, annual_full_load_hours: null, weekdays: WEEK }),
  schedule("sch_vent", "Ventilation", (changes || {}).vent || { type: "ventilation", periods: VENTILATION },
    { hours: repeat(1, 2).concat(repeat(0.77, 14), repeat(0.54, 6), repeat(0.4, 2)), daily_full_load_hours: 16.02,
      annual_full_load_hours: 5831.28, weekdays: WEEK })];
}

var DISHWASHER = { id: "dev_dish", type: "dishwasher", display_name: "Kitchen dishwasher", quantity: 1,
  in_conditioned_space: true, comment: "", reference_quantity: 1, reference_energy_norm: 2, energy_demand: 269,
  energy_demand_per_use: 0, capacity_type: 1, capacity_place_settings: 12, water_connection: "cold_water" };
var MEL = { id: "dev_mel", type: "phius_mel", display_name: "Phius MEL", quantity: 1, in_conditioned_space: true,
  comment: "", reference_quantity: 3 };

function snapshot(scheduleRows, devices, preferences) {
  return { product: "PH-Composer", version: "test", session: "session-a", revision: REVISION, file_name: "a.skp",
    edit_path: [], preferences: preferences || { unit_system: "SI" }, sections: {
      "ph_composer.programs.programs": { status: "completed", value: { records: [], unreadable: [] } },
      "ph_composer.programs.schedules": { status: "completed", value: { records: scheduleRows, unreadable: [] } },
      "ph_composer.programs.equipment_sets": { status: "completed", value: { records: [
        row("equipment_set", "eqs_PHCDEFAULT01", "Default devices", { devices: devices }, { default: true,
          use_count: 1 })], unreadable: [] } },
      "ph_composer.programs.occupancy": { status: "completed", value: { zones: [], building_segments: [],
        dwellings: [{ id: null, name: "House", equipment_set_id: null }, { id: "dwl_a", name: "Flat A",
          equipment_set_id: "eqs_other" }],
        choices: { default_equipment_set_id: "eqs_PHCDEFAULT01" } } } } };
}

function load(tab) {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/programs/tab"]);
  var p = { context: context, panel: modules.panel, sent: sent };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  p.snapshot = function (scheduleRows, devices, preferences) {
    p.panel.receive({ type: "panel.snapshot", payload: snapshot(scheduleRows || schedules(), devices ||
      [DISHWASHER, MEL], preferences) });
  };
  p.snapshot();
  p.panel.showTab("programs");
  click(p.context.document.querySelectorAll("[role='tab']").filter(function (node) {
    return node.textContent === tab; })[0]);
  return p;
}

function pane(p) { return p.context.document.querySelector("[data-pane='programs']"); }
function shown(p) {
  return pane(p).querySelectorAll(".pgm-layout").filter(function (node) { return !node.hidden; })[0];
}
function labelled(root, tag, label) {
  return root.querySelectorAll(tag).filter(function (node) { return node.getAttribute("aria-label") === label; })[0];
}
function click(node) { node.listeners.click({ preventDefault: function () {}, target: node }); }
function plain(value) { return JSON.parse(JSON.stringify(value)); }
/* What a node reads: its children's text where it has children, as the stub keeps no textContent for them. */
function text(node) {
  return node.children.length ? node.children.map(text).join("") : String(node.textContent || "");
}
function last(p) { var all = p.actions(); return all[all.length - 1].payload; }
function type(input, text) { input.focus(); input.value = text; input.listeners.input({}); }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopPropagation: function () {} });
}
function open(p, name) {
  click(shown(p).querySelectorAll(".library-sidebar-row-button").filter(function (node) {
    return node.querySelector(".library-sidebar-name").textContent === name; })[0]);
}
function answer(p, outcome) {
  p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
    outcome: Object.assign({ effect: outcome.status === "completed" ? "committed" : "none", revision: REVISION },
      outcome) } });
}
/* Answers the device types read with the golden Ruby keeps equal to its catalog. */
function types(p) {
  var read = p.sent.filter(function (message) {
    return message.type === "query.invoke" && message.payload.name === PREFIX + ".equipment_sets.device_types";
  });
  assert.strictEqual(read.length, 1, "the device types are read once");
  p.panel.receive({ type: "query.result", payload: { request_id: read[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", code: "ok", revision: REVISION, value: { types: DEVICE_TYPES } } } });
}
function dialog(p) { return shown(p).querySelector(".pgm-device-dialog"); }
function field(root, key_) {
  return root.querySelectorAll("[data-key]").filter(function (node) {
    return node.getAttribute("data-key") === key_; })[0];
}
function change(select, value) { select.value = value; select.listeners.change({}); }

/* ---------------------------------------------------------------- Schedules */

test("a Schedule value commits as one update of that field, guarded by it as drawn", function () {
  var p = load("Schedules");
  open(p, "Office hours");
  var start = labelled(shown(p), "input", "Starts at");
  assert.strictEqual(start.value, "7");
  type(start, "8");
  key(start, "Enter");
  assert.strictEqual(p.actions().length, 1, "one request");
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), [PREFIX + ".schedules.update",
    { id: "sch_office", values: { start_h: 8 }, expected_values: { start_h: 7 } }]);
  answer(p, { status: "refused", code: "target.changed", message: "Schedule Office hours has changed." });
  p.snapshot();
  assert.strictEqual(start.value, "7", "a refusal lets the Model's value back in");
  assert.match(p.panel.state.ui.notice.message, /has changed/);
});

test("a whole number refuses a fraction, and nothing is sent", function () {
  var p = load("Schedules");
  open(p, "Office hours");
  var days = labelled(shown(p), "input", "Days per week");
  type(days, "4.5");
  key(days, "Enter");
  assert.strictEqual(p.actions().length, 0);
  assert.match(p.panel.state.ui.notice.message, /Days per week is a whole number from 1 to 7/);
  assert.strictEqual(days.value, "5");
});

test("a temperature Schedule is one value in the display units, with no days or weeks", function () {
  var p = load("Schedules");
  p.snapshot(null, null, { unit_system: "IP" });
  open(p, "Heating");
  var value = labelled(shown(p), "input", "Temperature");
  assert.strictEqual(value.value, "68");
  assert.strictEqual(Boolean(labelled(shown(p), "input", "Days per week")), false);
  type(value, "70");
  key(value, "Enter");
  assert.strictEqual(Math.round(last(p).params.values.value_c * 100) / 100, 21.11, "stored in °C");
  assert.match(shown(p).querySelector(".sch-week").getAttribute("aria-label"), /every day/);
});

test("ventilation hours wait as one draft, amber, until they total 24, then go as one update", function () {
  var p = load("Schedules");
  open(p, "Ventilation");
  var high = labelled(shown(p), "input", "High hours per day");
  var standard = labelled(shown(p), "input", "Standard hours per day");
  var total = shown(p).querySelector(".sch-total");
  assert.match(text(total), /Total 24 of 24 h/);
  type(high, "3");
  key(high, "Enter");
  assert.strictEqual(p.actions().length, 0, "25 h is held");
  assert.ok(total.classList.contains("is-missing"));
  assert.match(text(total), /Total 25 of 24 h/);
  click(p.context.document.querySelectorAll("[role='tab']").filter(function (node) {
    return node.textContent === "Programs"; })[0]);
  assert.match(p.panel.state.ui.notice.message, /total 24 h/, "the draft holds the page");
  type(standard, "13");
  key(standard, "Enter");
  assert.strictEqual(p.actions().length, 1);
  var periods = plain(VENTILATION);
  periods[0].hours = 3; periods[1].hours = 13;
  assert.deepStrictEqual(plain(last(p).params), { id: "sch_vent", values: { periods: periods },
    expected_values: { periods: VENTILATION } });
});

test("Escape takes back the typing first, then the held draft", function () {
  var p = load("Schedules");
  open(p, "Ventilation");
  var basic = labelled(shown(p), "input", "Basic hours per day");
  var minimum = labelled(shown(p), "input", "Minimum fraction of design flow");
  type(basic, "8");
  key(basic, "Enter");
  type(minimum, "0.2");
  key(minimum, "Escape");
  assert.strictEqual(minimum.value, "0.4", "the typing goes");
  assert.strictEqual(basic.value, "8", "the draft stays");
  key(minimum, "Escape");
  assert.strictEqual(basic.value, "6", "then the draft goes");
});

test("a fraction typed while hours are held joins the draft and goes with them", function () {
  var p = load("Schedules");
  open(p, "Ventilation");
  var basic = labelled(shown(p), "input", "Basic hours per day");
  var minimum = labelled(shown(p), "input", "Minimum hours per day");
  var fraction = labelled(shown(p), "input", "High fraction of design flow");
  type(basic, "7"); key(basic, "Enter");
  type(fraction, "0.9"); key(fraction, "Enter");
  assert.strictEqual(p.actions().length, 0);
  type(minimum, "1"); key(minimum, "Enter");
  var periods = plain(VENTILATION);
  periods[0].fraction = 0.9; periods[2].hours = 7; periods[3].hours = 1;
  assert.deepStrictEqual(plain(last(p).params.values.periods), periods);
});

test("a period edit is guarded by the periods as they were when typing began", function () {
  var p = load("Schedules");
  open(p, "Ventilation");
  var fraction = labelled(shown(p), "input", "High fraction of design flow");
  type(fraction, "0.9");
  var changed = plain(VENTILATION);
  changed[0].fraction = 0.8;
  p.snapshot(schedules({ vent: { type: "ventilation", periods: changed } }));
  key(fraction, "Enter");
  assert.deepStrictEqual(plain(last(p).params.expected_values), { periods: VENTILATION }, "so Ruby refuses it");
  assert.strictEqual(last(p).params.values.periods[0].fraction, 0.9);
});

test("New and Duplicate wait while ventilation periods are held", function () {
  var p = load("Schedules");
  open(p, "Ventilation");
  var high = labelled(shown(p), "input", "High hours per day");
  type(high, "3"); key(high, "Enter");
  high.blur();
  click(labelled(shown(p), "button", "Duplicate Schedule"));
  click(shown(p).querySelectorAll("button").filter(function (node) {
    return node.textContent === "+ New Schedule"; })[0]);
  assert.strictEqual(p.actions().length, 0);
  assert.match(p.panel.state.ui.notice.message, /total 24 h/);
  assert.strictEqual(high.value, "3", "the draft stays");
});

test("a Schedule whose type changes underneath draws its new form", function () {
  var p = load("Schedules");
  open(p, "Ventilation");
  var high = labelled(shown(p), "input", "High hours per day");
  type(high, "3"); key(high, "Enter");
  p.snapshot(schedules({ vent: { type: "fractional", start_h: 0, end_h: 24, fraction_on: 1, fraction_off: 0 } }));
  assert.strictEqual(Boolean(labelled(shown(p), "input", "High hours per day")), false);
  assert.strictEqual(labelled(shown(p), "input", "Starts at").value, "0");
  var programs = p.context.document.querySelectorAll("[role='tab']").filter(function (node) {
    return node.textContent === "Programs"; })[0];
  click(programs);
  assert.strictEqual(programs.getAttribute("aria-selected"), "true", "the page is free to move on");
});

test("Escape restores a held draft of the periods", function () {
  var p = load("Schedules");
  open(p, "Ventilation");
  var basic = labelled(shown(p), "input", "Basic hours per day");
  type(basic, "8");
  key(basic, "Enter");
  assert.strictEqual(basic.value, "8");
  key(basic, "Escape");
  assert.strictEqual(basic.value, "6");
  assert.match(text(shown(p).querySelector(".sch-total")), /Total 24 of 24 h/);
  assert.strictEqual(p.actions().length, 0);
});

test("the strip and the week row draw the row's profile; Used by names the loads", function () {
  var p = load("Schedules");
  open(p, "Office hours");
  assert.strictEqual(shown(p).querySelectorAll(".sch-bar").length, 24);
  var on = shown(p).querySelectorAll(".sch-day").filter(function (node) { return node.classList.contains("is-on"); });
  assert.deepStrictEqual(on.map(function (node) { return node.textContent; }), ["Mon", "Tue", "Wed", "Thu", "Fri"]);
  assert.strictEqual(shown(p).querySelector(".pgm-use").textContent, "Office · Occupancy");
  var metrics = shown(p).querySelectorAll(".pgm-metric").map(function (node) {
    return node.querySelector("strong").textContent; });
  assert.deepStrictEqual(metrics, ["Fractional", "2496", "1 load"]);
  var hourly = shown(p).querySelectorAll("button").filter(function (node) {
    return node.textContent === "Hourly editor"; })[0];
  assert.strictEqual(hourly.disabled, true, "planned");
});

/* ---------------------------------------------------------------- Equipment Sets */

test("the device grid marks a Phius-rule device and names a renamed device's type", function () {
  var p = load("Equipment Sets");
  types(p);
  var rows = shown(p).querySelector("tbody").querySelectorAll("tr");
  assert.strictEqual(rows.length, 2);
  var cells = rows.map(function (tr) {
    return [text(tr.querySelector(".col-device")), text(tr.querySelector(".col-energy"))];
  });
  assert.deepStrictEqual(cells, [["Kitchen dishwasher · Dishwasher", "269 kWh/a"],
    ["Phius MEL", "Σ Phius rule: bedrooms and iCFA"]]);
});

test("Add device lays out a type's fields; a gas dryer's gas fields show only for a gas dryer", function () {
  var p = load("Equipment Sets");
  types(p);
  click(shown(p).querySelector(".pgm-add-device"));
  var root = dialog(p);
  assert.strictEqual(root.querySelector("h2").textContent, "Add device to Default devices");
  change(field(root, "type"), "clothes_dryer");
  assert.strictEqual(field(root, "display_name").value, "Laundry - dryer");
  assert.strictEqual(Boolean(field(root, "gas_consumption")), false, "an electric dryer has no gas fields");
  assert.ok(field(root, "combined_energy_factor"));
  change(field(root, "dryer_type"), "gas_exhaust_air");
  assert.ok(field(root, "gas_consumption"), "a gas dryer shows them");
  assert.ok(field(root, "gas_efficiency_factor"));
  type(field(root, "gas_consumption"), "1.5");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  var sent = last(p);
  assert.strictEqual(sent.name, PREFIX + ".equipment_sets.add_device");
  assert.strictEqual(sent.params.type, "clothes_dryer");
  assert.deepStrictEqual([sent.params.values.dryer_type, sent.params.values.gas_consumption,
    sent.params.values.quantity], ["gas_exhaust_air", 1.5, 1]);
  answer(p, { status: "completed", code: "ok", value: { id: "eqs_PHCDEFAULT01", device_id: "dev_new" } });
  p.snapshot();
  assert.strictEqual(Boolean(dialog(p)), false, "it closes once added");
  assert.match(p.panel.state.ui.notice.message, /Added Laundry - dryer to Default devices/);
});

test("every type lays out from the catalog, its rule or its energy demand shown", function () {
  var p = load("Equipment Sets");
  types(p);
  click(shown(p).querySelector(".pgm-add-device"));
  var root = dialog(p);
  DEVICE_TYPES.forEach(function (entry) {
    change(field(root, "type"), entry.type);
    var references = field(root, "reference_quantity").querySelectorAll("option").map(function (node) {
      return Number(node.value); });
    assert.deepStrictEqual(references, entry.reference_quantities, entry.type);
    var rule = root.querySelector(".pgm-device-rule");
    assert.strictEqual(Boolean(rule), entry.phius_rule, entry.type + " rule");
    entry.fields.forEach(function (own) {
      if (own.applies_when) return;
      if (own.key === "reference_energy_norm" && entry.energy_norms.length < 2) return;
      assert.ok(field(root, own.key), entry.type + " shows " + own.key);
    });
  });
});

test("Edit sends only what changed, guarded as it opened; the type is fixed", function () {
  var p = load("Equipment Sets");
  types(p);
  click(labelled(shown(p), "button", "Edit Kitchen dishwasher"));
  var root = dialog(p);
  assert.strictEqual(root.querySelector("h2").textContent, "Edit Kitchen dishwasher");
  assert.strictEqual(Boolean(field(root, "type")), false, "no type choice on Edit");
  assert.match(root.querySelector(".pgm-device-type").textContent, /Dishwasher/);
  type(field(root, "quantity"), "2");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), [PREFIX + ".equipment_sets.update_device",
    { id: "eqs_PHCDEFAULT01", device_id: "dev_dish", values: { quantity: 2 }, expected_values: { quantity: 1 } }]);
  answer(p, { status: "refused", code: "target.changed", message: "Device dev_dish has changed since it was read." });
  p.snapshot();
  assert.ok(dialog(p), "a refusal keeps the draft");
  assert.match(root.querySelector(".cell-error").textContent, /changed since it was read/);
  assert.strictEqual(field(root, "quantity").value, "2");
});

var WASHER = { id: "dev_wash", type: "clothes_washer", display_name: "Laundry - washer", quantity: 1,
  in_conditioned_space: true, comment: "", reference_quantity: 1, reference_energy_norm: 2, energy_demand: 120.4567,
  energy_demand_per_use: 0, capacity_m3: 0.1274, modified_energy_factor: 2.7, water_connection: "cold_water",
  utilization_factor: 1 };

["SI", "IP"].forEach(function (system) {
  test("an edit of the name alone sends the name alone, a rounded value left as stored (" + system + ")", function () {
    var p = load("Equipment Sets");
    p.snapshot(null, [WASHER], { unit_system: system });
    types(p);
    click(labelled(shown(p), "button", "Edit Laundry - washer"));
    var root = dialog(p);
    type(field(root, "display_name"), "Washer");
    root.querySelector("form").listeners.submit({ preventDefault: function () {} });
    assert.deepStrictEqual(plain(last(p).params), { id: "eqs_PHCDEFAULT01", device_id: "dev_wash",
      values: { display_name: "Washer" }, expected_values: { display_name: "Laundry - washer" } });
  });
});

test("a washer's capacity reads in the display volume and is stored in m³", function () {
  var p = load("Equipment Sets");
  p.snapshot(null, [WASHER], { unit_system: "IP" });
  types(p);
  click(labelled(shown(p), "button", "Edit Laundry - washer"));
  var root = dialog(p);
  assert.match(text(root), /Capacity \[ft³\]/);
  type(field(root, "capacity_m3"), "5");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(Math.round(last(p).params.values.capacity_m3 * 10000) / 10000, 0.1416);
});

test("a number typed before the unit system changes keeps its units through a layout", function () {
  var p = load("Equipment Sets");
  p.snapshot(null, [WASHER], { unit_system: "SI" });
  types(p);
  click(labelled(shown(p), "button", "Edit Laundry - washer"));
  var root = dialog(p);
  type(field(root, "capacity_m3"), "0.1");
  p.snapshot(null, [WASHER], { unit_system: "IP" });
  change(field(root, "water_connection"), "dhw");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(last(p).params.values.capacity_m3, 0.1, "0.1 m³, as typed in SI");
});

test("a choice lays the form out again and keeps a number not yet read", function () {
  var p = load("Equipment Sets");
  types(p);
  click(shown(p).querySelector(".pgm-add-device"));
  var root = dialog(p);
  change(field(root, "type"), "clothes_dryer");
  type(field(root, "combined_energy_factor"), "abc");
  change(field(root, "dryer_type"), "gas_exhaust_air");
  assert.ok(field(root, "gas_consumption"), "the choice applies");
  assert.strictEqual(field(root, "combined_energy_factor").value, "abc");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.actions().length, 0, "the submit names what does not read");
  assert.notStrictEqual(root.querySelector(".cell-error").textContent, "");
});

test("the fields hold still while a device write is out; a refusal gives them and the commit back", function () {
  var p = load("Equipment Sets");
  types(p);
  click(labelled(shown(p), "button", "Edit Kitchen dishwasher"));
  var root = dialog(p);
  type(field(root, "quantity"), "2");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  var save = root.querySelectorAll("button").filter(function (node) { return node.textContent === "Save"; })[0];
  assert.deepStrictEqual([field(root, "quantity").disabled, field(root, "display_name").disabled, save.disabled],
    [true, true, true]);
  answer(p, { status: "refused", code: "validation.failed", message: "Quantity is too large." });
  p.snapshot();
  assert.deepStrictEqual([field(root, "quantity").disabled, save.disabled], [false, false]);
  type(field(root, "quantity"), "3");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.deepStrictEqual(plain(last(p).params.values), { quantity: 3 }, "the corrected value goes");
  assert.strictEqual(p.actions().length, 2);
});

test("a number typed back to what it was sends what it was, after a refused submit", function () {
  var p = load("Equipment Sets");
  types(p);
  click(labelled(shown(p), "button", "Edit Kitchen dishwasher"));
  var root = dialog(p);
  type(field(root, "quantity"), "2");
  type(field(root, "display_name"), "");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.actions().length, 0, "no name");
  type(field(root, "quantity"), "1");
  type(field(root, "display_name"), "Dishwasher");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.deepStrictEqual(plain(last(p).params.values), { display_name: "Dishwasher" });
});

test("a quantity must be a whole number of at least 1", function () {
  var p = load("Equipment Sets");
  types(p);
  click(labelled(shown(p), "button", "Edit Phius MEL"));
  var root = dialog(p);
  type(field(root, "quantity"), "1.5");
  root.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.actions().length, 0);
  assert.match(root.querySelector(".cell-error").textContent, /whole number of at least 1/);
});

test("a row click edits; Delete confirms naming the Set and the Dwellings using it", function () {
  var p = load("Equipment Sets");
  types(p);
  var tr = shown(p).querySelector("tbody").querySelectorAll("tr")[1];
  var cell = tr.querySelector(".col-device");
  shown(p).querySelector(".pgm-devices").listeners.click({ target: cell });
  assert.strictEqual(dialog(p).querySelector("h2").textContent, "Edit Phius MEL");
  click(dialog(p).querySelectorAll("button").filter(function (node) { return node.textContent === "Cancel"; })[0]);
  assert.strictEqual(Boolean(dialog(p)), false);
  click(labelled(shown(p), "button", "Delete Phius MEL"));
  var confirm = shown(p).querySelector(".pgm-confirm");
  assert.strictEqual(confirm.querySelector("p").textContent,
    "This removes Phius MEL from Default devices. Dwelling House uses this Set.");
  click(confirm.querySelectorAll("button").filter(function (node) { return node.textContent === "Delete device"; })[0]);
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), [PREFIX + ".equipment_sets.delete_device",
    { id: "eqs_PHCDEFAULT01", device_id: "dev_mel", expected_values: { display_name: "Phius MEL", quantity: 1 } }]);
});
