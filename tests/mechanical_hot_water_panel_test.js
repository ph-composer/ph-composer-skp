"use strict";
/* Mechanical › Hot Water: the Systems, Heaters and Tanks pills, each control sending only the registered hot water
   operations. The panel computes nothing: recirculation, the tank slots and the findings are the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/mechanical_fixtures");
var PREFIX = fixtures.PREFIX, SYSTEM = PREFIX + "hot_water";
var SYSTEMS = PREFIX + "hot_water_systems", HEATERS = PREFIX + "hot_water_heaters", TANKS = PREFIX + "hot_water_tanks";

function setup(pill) {
  var document = dom.buildDocument("");
  var sections = {}, navigate = {}, sent = [], notices = [], state = fixtures.state();
  var root = dom.element("div", "phc-workspace");
  document.body.appendChild(root);
  function send(type, payload) { sent.push({ type: type, payload: payload }); }
  function paint() { Object.keys(sections).forEach(function (key) { sections[key](root, state, send); }); }
  var panel = { state: state, send: send, repaint: paint, navigationGuard: function () {}, workedOn: function () {},
    section: function (name, render, options) {
      sections[name] = render; navigate[name] = options && options.onNavigate;
    },
    notify: function (message, tone) { notices.push({ message: message, tone: tone }); },
    setPreference: function (key, value, extra) { modules.unit_preferences.set(key, value, extra); } };
  var context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["features/mechanical/section", "features/mechanical/ventilators",
    "features/mechanical/hot_water", "features/mechanical/hot_water_heaters", "features/mechanical/hot_water_tanks"],
  { panel: panel });
  paint();
  root._view.tabs.select(SYSTEM);
  var system = root._view.systems.filter(function (entry) { return entry.id === SYSTEM; })[0];
  system.pills.select(pill || SYSTEMS);
  function view(id) { return root._view.tables.filter(function (held) { return held.id === id; })[0].view; }
  return { root: root, state: state, sent: sent, notices: notices, paint: paint, modules: modules, view: view,
    pills: system.pills, navigate: function (intent) { navigate.mechanical(root, intent); } };
}
function named(o, name) { return o.sent.filter(function (message) { return message.payload.name === name; }); }
function answer(o, message, outcome) {
  o.state.ui.actionResult = { request_id: message.payload.request_id, session: "session", outcome: outcome };
  o.paint();
}
function cell(o, id, key) { return o.view(id).inventory.edits.cells[key]; }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopImmediatePropagation: function () {} });
}
function type(input, text) { input.value = text; input.listeners.input({}); }
function press(node) { node.listeners.click({ preventDefault: function () {} }); }
function row(o, id) { return o.root.querySelector("[data-row-key=" + id + "]"); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function headers(o, id) {
  return o.view(id).inventory.scroll.querySelectorAll("th").map(function (th) {
    return th.className.match(/col-([a-z_0-9]+)/);
  }).filter(Boolean).map(function (match) { return match[1]; });
}
function records(o, section) { return o.state.sections[section].value.records; }

test("the Hot Water subtab holds Systems, Heaters and Tanks, each Tag first, export fields next, identity hideable",
  function () {
    var o = setup();
    assert.deepStrictEqual(o.root.querySelector(".phc-subtabs").querySelectorAll("[role=tab]").map(function (node) {
      return node.textContent;
    }), ["Ventilation", "Hot Water"]);
    assert.deepStrictEqual(o.pills.root.querySelectorAll("button").map(function (node) {
      return [node.textContent, node.getAttribute("aria-pressed")];
    }), [["Systems", "true"], ["Heaters", "false"], ["Tanks", "false"]]);
    assert.strictEqual(o.root._view.header.root.querySelector(".primary").textContent, "+ New Hot Water System");
    assert.deepStrictEqual(headers(o, SYSTEMS), ["actions", "name", "serves", "number_tap_points", "heaters", "tanks",
      "recirculation_temperature_c", "recirculation_hours", "piping_calc_method", "manufacturer", "model", "notes"]);
    o.pills.select(HEATERS);
    assert.deepStrictEqual(headers(o, HEATERS).slice(0, 6), ["actions", "name", "hot_water_system_id", "variant",
      "percent_coverage", "in_conditioned_space"]);
    o.pills.select(TANKS);
    assert.deepStrictEqual(headers(o, TANKS).slice(0, 10), ["actions", "name", "hot_water_system_id", "role", "slot",
      "tank_type", "quantity", "storage_capacity_l", "standby_losses_w_k", "in_conditioned_space"]);
    var inventory = o.view(TANKS).inventory;
    press(inventory.columnsMenu.trigger);
    assert.deepStrictEqual(inventory.columnsMenu.content.querySelectorAll("button").map(function (item) {
      return item.textContent;
    }), ["Manufacturer", "Model", "Notes"]);
  });

test("a System, a Heater and a Tank cell edit each sends its own update with its expected value; a refusal stays",
  function () {
    var o = setup(), taps = cell(o, SYSTEMS, fixtures.HWS1.id + ":number_tap_points");
    type(taps.input, "10"); key(taps.input, "Enter");
    var update = named(o, SYSTEMS + ".update")[0];
    assert.deepStrictEqual(clone(update.payload.params), { id: fixtures.HWS1.id, values: { number_tap_points: 10 },
      expected_values: { number_tap_points: 8 } });
    answer(o, update, { status: "refused", code: "target.changed", message: "The Hot Water System changed." });
    assert.strictEqual(taps.input.value, "10");
    assert.strictEqual(taps.status, "error");
    assert.ok(o.root._view.guard(), "a refused draft holds the tab");
    key(taps.input, "Escape");
    var blank = cell(o, SYSTEMS, fixtures.HWS2.id + ":number_tap_points");
    type(blank.input, "0"); key(blank.input, "Enter");
    assert.match(blank.message, /whole number of 1 or more, or leave it blank/);
    key(blank.input, "Escape");
    var method = cell(o, SYSTEMS, fixtures.HWS1.id + ":piping_calc_method");
    method.input.value = ""; method.input.listeners.change({});
    assert.deepStrictEqual(clone(named(o, SYSTEMS + ".update")[1].payload.params.values), { piping_calc_method: null });

    var p = setup(HEATERS), coverage = cell(p, HEATERS, fixtures.HE.id + ":percent_coverage");
    assert.strictEqual(coverage.input.value, "30", "coverage reads as a percentage");
    type(coverage.input, "45"); key(coverage.input, "Enter");
    assert.deepStrictEqual(clone(named(p, HEATERS + ".update")[0].payload.params), { id: fixtures.HE.id,
      values: { percent_coverage: 0.45 }, expected_values: { percent_coverage: 0.3 } },
    "sent and guarded as the stored fraction");
    var over = cell(p, HEATERS, fixtures.HHP.id + ":percent_coverage");
    type(over.input, "120"); key(over.input, "Enter");
    assert.match(over.message, /percentage from 0 to 100/);

    var q = setup(TANKS), quantity = cell(q, TANKS, fixtures.T1.id + ":quantity");
    type(quantity.input, "2"); key(quantity.input, "Enter");
    assert.deepStrictEqual(clone(named(q, TANKS + ".update")[0].payload.params), { id: fixtures.T1.id,
      values: { quantity: 2 }, expected_values: { quantity: 1 } });
    var role = cell(q, TANKS, fixtures.T3.id + ":role");
    assert.strictEqual(role.input.value, "buffer");
    answer(q, named(q, TANKS + ".update")[0], { status: "completed", value: {} });
    role.input.value = "solar"; role.input.listeners.change({});
    assert.deepStrictEqual(clone(named(q, TANKS + ".update")[1].payload.params.expected_values), { role: "buffer" });
  });

test("a Heater's Type change asks for the new Type's values and sends one update nulling the old Type's", function () {
  var o = setup(HEATERS), heaters = o.view(HEATERS);
  function liveFields(id) {
    return ["total_system_perf_ratio", "cop_1", "ambient_temp_1_c", "cop_2", "ambient_temp_2_c",
      "annual_energy_factor"].filter(function (field) {
      return !row(o, id).querySelector(".col-" + field).classList.contains("mech-inactive");
    });
  }
  assert.deepStrictEqual(liveFields(fixtures.HE.id), [], "an electric heater takes no efficiency value");
  assert.deepStrictEqual(liveFields(fixtures.HHP.id), ["total_system_perf_ratio"]);
  var dash = row(o, fixtures.HE.id).querySelector(".col-cop_1");
  assert.deepStrictEqual([dash.querySelector("input").value, dash.querySelector("input").placeholder,
    dash.querySelector("input").readOnly], ["", "—", true], "an empty, read-only cell reading as a dash");
  assert.match(dash.getAttribute("data-tooltip"), /Electric takes no COP 1/);

  var select = row(o, fixtures.HHP.id).querySelector(".col-variant").querySelector("select");
  select.value = "heat_pump_monthly"; select.listeners.change({});
  assert.strictEqual(select.value, "heat_pump_annual", "the cell shows the Model's Type until the change lands");
  var form = heaters.typeForm;
  assert.strictEqual(form.root.hidden, false, "the change opens in the shared dialog");
  assert.strictEqual(form.title.textContent, "Change H-HP to Heat pump · monthly");
  assert.strictEqual(form.explanation.textContent, "Removes its Performance ratio.");
  assert.deepStrictEqual(clone(form.units.map(function (held) { return held.key; })),
    ["cop_1", "ambient_temp_1_c", "cop_2", "ambient_temp_2_c"]);
  type(form.units[0].unit.input, "2.1");
  form.submit();
  assert.strictEqual(named(o, HEATERS + ".update").length, 0, "nothing leaves while a value is missing");
  assert.match(form.units[1].unit.error.textContent, /Enter the Rating temperature 1/);
  type(form.units[1].unit.input, "-8.3");
  type(form.units[2].unit.input, "3.4");
  type(form.units[3].unit.input, "8.3");
  key(form.units[3].unit.input, "Enter");
  var change = named(o, HEATERS + ".update")[0];
  assert.deepStrictEqual(clone(change.payload.params), { id: fixtures.HHP.id,
    values: { variant: "heat_pump_monthly", total_system_perf_ratio: null, cop_1: 2.1, ambient_temp_1_c: -8.3,
      cop_2: 3.4, ambient_temp_2_c: 8.3 },
    expected_values: { variant: "heat_pump_annual", total_system_perf_ratio: 2.5 } });
  var heater = records(o, HEATERS)[1].values;
  Object.assign(heater, { variant: "heat_pump_monthly", cop_1: 2.1, ambient_temp_1_c: -8.3, cop_2: 3.4,
    ambient_temp_2_c: 8.3 });
  delete heater.total_system_perf_ratio;
  answer(o, change, { status: "completed", value: { id: fixtures.HHP.id } });
  assert.strictEqual(form.root.hidden, true);
  assert.deepStrictEqual(liveFields(fixtures.HHP.id), ["cop_1", "ambient_temp_1_c", "cop_2", "ambient_temp_2_c"],
    "only the new Type's cells are live");
  assert.strictEqual(cell(o, HEATERS, fixtures.HHP.id + ":cop_1").input.value, "2.1");

  // To electric: nothing to ask, the old values named and nulled.
  select = row(o, fixtures.HHP.id).querySelector(".col-variant").querySelector("select");
  select.value = "electric"; select.listeners.change({});
  assert.strictEqual(form.explanation.textContent,
    "Removes its COP 1, Rating temperature 1, COP 2, Rating temperature 2.");
  form.submit();
  var electric = named(o, HEATERS + ".update")[1];
  assert.deepStrictEqual(clone(electric.payload.params.values), { variant: "electric", cop_1: null,
    ambient_temp_1_c: null, cop_2: null, ambient_temp_2_c: null });
  answer(o, electric, { status: "refused", code: "target.changed", message: "The Hot Water Heater changed." });
  assert.strictEqual(form.root.hidden, false, "a refusal keeps the dialog");
  assert.match(form.error.textContent, /changed/);
});

test("pasted choices read by label or value, and other text is refused before it is sent", function () {
  var o = setup(), edits = o.view(SYSTEMS).inventory.edits;
  assert.strictEqual(edits.normalize("piping_calc_method", "Piping per unit"), 3);
  assert.strictEqual(edits.normalize("piping_calc_method", "2"), 2);
  assert.strictEqual(edits.normalize("piping_calc_method", "none"), null);
  assert.strictEqual(edits.normalize("piping_calc_method", "7").ok, false);
  var tanks = setup(TANKS).view(TANKS).inventory.edits;
  assert.strictEqual(tanks.normalize("role", "Buffer"), "buffer");
  assert.strictEqual(tanks.normalize("tank_type", "hot water only"), "2-DHW ONLY");
  assert.strictEqual(tanks.normalize("role", "heater").ok, false);
});

test("a paste over an efficiency value its Type does not take sends nothing", function () {
  var o = setup(HEATERS), inventory = o.view(HEATERS).inventory;
  inventory.grid.refresh();
  inventory.grid.select(cell(o, HEATERS, fixtures.HE.id + ":in_conditioned_space"), false);
  inventory.grid.paste([["No", "3.1"]]);
  assert.strictEqual(named(o, HEATERS + ".update").length, 0);
  assert.match(o.notices[o.notices.length - 1].message, /read-only cells/);
  inventory.grid.select(cell(o, HEATERS, fixtures.HHP.id + ":in_conditioned_space"), false);
  inventory.grid.paste([["Yes", "3.1"]]);
  answer(o, named(o, HEATERS + ".update")[0], { status: "completed", value: {} });
  assert.deepStrictEqual(named(o, HEATERS + ".update").map(function (message) {
    return clone(message.payload.params);
  }), [{ id: fixtures.HHP.id, values: { in_conditioned_space: true },
    expected_values: { in_conditioned_space: false } },
  { id: fixtures.HHP.id, values: { total_system_perf_ratio: 3.1 },
    expected_values: { total_system_perf_ratio: 2.5 } }],
  "a live cell takes the paste");
});

test("a paste down a column refuses whole when an electric Heater lies between two heat pumps", function () {
  var o = setup(HEATERS), heaters = records(o, HEATERS);
  heaters.push(JSON.parse(JSON.stringify(heaters[1])));
  heaters[2].id = "hwh_CCCCCCCCCCCC"; heaters[2].values.name = "H-Z";
  heaters[0].values.name = "H-M";
  o.paint();
  var inventory = o.view(HEATERS).inventory;
  inventory.grid.refresh();
  // Rows in Tag order: H-HP (annual), H-M (electric), H-Z (annual).
  inventory.grid.select(cell(o, HEATERS, fixtures.HHP.id + ":total_system_perf_ratio"), false);
  inventory.grid.paste([["3.1"], ["3.2"], ["3.3"]]);
  assert.strictEqual(named(o, HEATERS + ".update").length, 0, "no value lands on the wrong Heater");
  assert.match(o.notices[o.notices.length - 1].message, /read-only cells/);
  var inactive = cell(o, HEATERS, fixtures.HE.id + ":total_system_perf_ratio");
  assert.ok(inactive.input.readOnly, "drawn, but closed to typing");
  assert.ok(row(o, fixtures.HE.id).querySelector(".col-total_system_perf_ratio").classList.contains("mech-inactive"));
});

test("a draft on a value its Type stops taking, changed elsewhere, can still be cancelled", function () {
  var o = setup(HEATERS), ratio = cell(o, HEATERS, fixtures.HHP.id + ":total_system_perf_ratio");
  type(ratio.input, "3.0");
  var heater = records(o, HEATERS)[1].values;
  heater.variant = "electric"; delete heater.total_system_perf_ratio;
  o.paint();
  assert.ok(o.root._view.guard(), "the draft holds the tab");
  assert.strictEqual(row(o, fixtures.HHP.id).querySelector(".col-total_system_perf_ratio").querySelector("input"),
    ratio.input, "its field is still on screen");
  key(ratio.input, "Escape");
  assert.strictEqual(o.root._view.guard(), null, "Escape lets it go");
});

test("the Type pill is kept across repaints, and a New form's chosen System that goes is cleared, never replaced",
  function () {
    var o = setup(HEATERS), before = row(o, fixtures.HE.id).querySelector(".col-variant").querySelector("select");
    o.paint();
    assert.strictEqual(row(o, fixtures.HE.id).querySelector(".col-variant").querySelector("select"), before);
    var form = o.view(HEATERS).table.newRecord;
    press(o.root._view.header.root.querySelector(".primary"));
    type(form.name, "H-2");
    form.parent.value = fixtures.HWS2.id; form.parent.listeners.change({});
    var systems = records(o, SYSTEMS);
    systems.splice(1, 1);
    o.paint();
    assert.strictEqual(form.parent.value, "", "the sole System left is not chosen for the user");
    assert.strictEqual(form.submitButton.disabled, true);
  });

test("coverage keeps its drafts, guards and readback in the stored fraction", function () {
  var o = setup(HEATERS), coverage = cell(o, HEATERS, fixtures.HHP.id + ":percent_coverage");
  assert.strictEqual(coverage.input.value, "70");
  type(coverage.input, "42.1234567"); key(coverage.input, "Enter");
  var update = named(o, HEATERS + ".update")[0];
  assert.deepStrictEqual(clone(update.payload.params), { id: fixtures.HHP.id,
    values: { percent_coverage: 0.421234567 }, expected_values: { percent_coverage: 0.7 } });
  records(o, HEATERS)[1].values.percent_coverage = 0.421234567;
  answer(o, update, { status: "completed", value: {} });
  assert.strictEqual(coverage.status, "clean", "the saved value reads back as saved");
  assert.strictEqual(o.root._view.guard(), null);
  type(coverage.input, "50");
  records(o, HEATERS)[1].values.percent_coverage = 0.421234568;
  o.paint();
  assert.strictEqual(coverage.status, "error", "a newer value under the draft stops it, however close");
});

test("a Type change refused after the Type changed elsewhere keeps its values and refusal, and holds Change Type",
  function () {
    var o = setup(HEATERS), form = o.view(HEATERS).typeForm;
    var select = row(o, fixtures.HHP.id).querySelector(".col-variant").querySelector("select");
    select.value = "heat_pump_inside"; select.listeners.change({});
    type(form.units[0].unit.input, "3.2");
    form.submit();
    var change = named(o, HEATERS + ".update")[0];
    var heater = records(o, HEATERS)[1].values;
    heater.variant = "electric"; delete heater.total_system_perf_ratio;
    answer(o, change, { status: "refused", code: "target.changed", message: "The Hot Water Heater changed." });
    assert.strictEqual(form.root.hidden, false, "the dialog stays");
    assert.strictEqual(form.units[0].unit.input.value, "3.2", "with what was typed");
    assert.match(form.error.textContent, /^The Hot Water Heater changed\. H-HP is now Electric; cancel and choose/);
    assert.strictEqual(form.submitButton.disabled, true);
  });

test("a Locate for a record that is gone, in a catalog read empty, says so at once", function () {
  var o = setup();
  o.state.sections[TANKS].value.records = [];
  o.paint();
  o.navigate({ hot_water_tank_ids: [fixtures.T4.id] });
  assert.strictEqual(o.pills.active, TANKS);
  assert.match(o.notices[o.notices.length - 1].message, /no longer in the Model/);
  assert.strictEqual(o.view(TANKS).table.located, null, "nothing waits");
});

test("capacity shows litres under SI and US gallons under IP, and a draft keeps its unit through a switch",
  function () {
    var o = setup(TANKS), capacity = cell(o, TANKS, fixtures.T1.id + ":storage_capacity_l");
    function header() {
      return o.view(TANKS).inventory.scroll.querySelectorAll("th").filter(function (th) {
        return /col-storage_capacity_l/.test(th.className);
      })[0].querySelector(".phc-th-label").textContent;
    }
    assert.strictEqual(capacity.input.value, "300");
    assert.match(header(), /Capacity L/);
    o.modules.unit_preferences.set("unit_system", "IP"); o.paint();
    assert.strictEqual(capacity.input.value, "79.3");
    assert.match(header(), /Capacity gal/);
    type(capacity.input, "80");
    o.modules.unit_preferences.set("unit_system", "SI"); o.paint();
    assert.strictEqual(capacity.input.value, "80", "the draft keeps its text");
    key(capacity.input, "Enter");
    var sent = named(o, TANKS + ".update")[0].payload.params;
    assert.ok(Math.abs(sent.values.storage_capacity_l - 302.83294272) < 1e-6, "read in gallons: " +
      sent.values.storage_capacity_l);
    assert.deepStrictEqual(clone(sent.expected_values), { storage_capacity_l: 300 });
  });

test("the Systems table: recirculation read only and muted at its defaults, an unexported method badged, and the " +
  "pooling note shown once however many rows carry it", function () {
    var pooled = { code: "mechanical.hot_water_pooled", severity: "info",
      blocks_export: false, message: "HWS-1, HWS-2 serve Building Segment Apartments; WUFI-Passive and METr pool " +
        "their tanks and heaters and keep one tap point count." };
    var o = setup();
    records(o, SYSTEMS).forEach(function (record) { record.findings.push(pooled); });
    o.paint();
    var hws1 = row(o, fixtures.HWS1.id), temperature = hws1.querySelector(".col-recirculation_temperature_c");
    assert.deepStrictEqual([temperature.textContent, hws1.querySelector(".col-recirculation_hours").textContent],
      ["60", "24"]);
    assert.ok(temperature.classList.contains("mech-muted"));
    assert.match(temperature.getAttribute("data-tooltip"), /default until recirculation piping is drawn/);
    assert.strictEqual(temperature.querySelector("input"), null, "nothing to edit");
    assert.strictEqual(hws1.querySelector(".col-heaters").textContent, "H-E, H-HP");
    assert.strictEqual(hws1.querySelector(".col-tanks").textContent, "T1, T3, T4");
    assert.strictEqual(row(o, fixtures.HWS2.id).querySelector(".col-heaters").textContent, "None");
    var badge = hws1.querySelector(".col-piping_calc_method").querySelector(".mech-cell-badge");
    assert.ok(badge && !badge.hidden, "the method carries its finding");
    assert.match(badge.getAttribute("aria-label"), /pinned honeybee-ph has no field/);
    assert.ok(!row(o, fixtures.HWS2.id).querySelector(".col-piping_calc_method").querySelector(".mech-cell-badge"));
    var note = o.view(SYSTEMS).note;
    assert.strictEqual(note.hidden, false);
    assert.strictEqual(note.textContent, pooled.message, "one line for one message");
    o.modules.unit_preferences.set("unit_system", "IP"); o.paint();
    assert.strictEqual(hws1.querySelector(".col-recirculation_temperature_c").textContent, "140");
  });

test("a Tank's export slot is the host's, read only, and amber with the reason when its Role has none left",
  function () {
    var o = setup(TANKS);
    assert.deepStrictEqual([fixtures.T1, fixtures.T3, fixtures.T4].map(function (item) {
      return row(o, item.id).querySelector(".col-slot").textContent;
    }), ["Tank 1", "Buffer tank", "No slot left"]);
    var none = row(o, fixtures.T4.id).querySelector(".col-slot");
    assert.ok(none.classList.contains("is-unslotted"));
    assert.match(none.getAttribute("data-tooltip"), /no free buffer slot/);
    assert.strictEqual(cell(o, TANKS, fixtures.T4.id + ":tank_type").input.value, "2-DHW ONLY");
  });

test("the System a Heater names changes in place, guarded, and a refusal is a notice", function () {
  var o = setup(HEATERS);
  var select = row(o, fixtures.HE.id).querySelector(".col-hot_water_system_id").querySelector("select");
  assert.deepStrictEqual(select.querySelectorAll("option").map(function (option) { return option.textContent; }),
    ["HWS-1", "HWS-2"]);
  select.value = fixtures.HWS2.id; select.listeners.change({});
  var update = named(o, HEATERS + ".update")[0];
  assert.deepStrictEqual(clone(update.payload.params), { id: fixtures.HE.id,
    values: { hot_water_system_id: fixtures.HWS2.id }, expected_values: { hot_water_system_id: fixtures.HWS1.id } });
  assert.ok(o.root._view.guard(), "the table holds while it is out");
  answer(o, update, { status: "refused", code: "target.changed", message: "The Hot Water Heater changed." });
  assert.deepStrictEqual(o.notices[o.notices.length - 1], { message: "The Hot Water Heater changed.",
    tone: "warning" });
  assert.strictEqual(row(o, fixtures.HE.id).querySelector(".col-hot_water_system_id").querySelector("select").value,
    fixtures.HWS1.id);
});

test("New Heater asks for its Hot Water System, and a System's delete offers clearing only while nothing names it",
  function () {
    var o = setup(HEATERS), form = o.view(HEATERS).table.newRecord;
    press(o.root._view.header.root.querySelector(".primary"));
    assert.strictEqual(form.root.hidden, false);
    type(form.name, "H-2");
    assert.strictEqual(form.submitButton.disabled, true);
    assert.strictEqual(form.error.textContent, "Choose the Hot Water System it belongs to.");
    form.parent.value = fixtures.HWS2.id; form.parent.listeners.change({});
    form.submit();
    assert.deepStrictEqual(clone(named(o, HEATERS + ".create")[0].payload.params), { values: { name: "H-2",
      hot_water_system_id: fixtures.HWS2.id } });

    var p = setup(), replacement = p.view(SYSTEMS).table.replacement;
    function options() {
      return replacement.select.querySelectorAll("option").map(function (option) { return option.value; });
    }
    replacement.open(records(p, SYSTEMS)[0], records(p, SYSTEMS));
    assert.deepStrictEqual(options(), ["", fixtures.HWS2.id], "HWS-1's Heaters and Tanks need a System");
    assert.match(replacement.uses.textContent, /Serves Zone C\. H-E, H-HP, T1, T3, T4 name it/);
    replacement.hide();
    replacement.open(records(p, SYSTEMS)[1], records(p, SYSTEMS));
    assert.strictEqual(replacement.inUse, false, "nothing names HWS-2");
    replacement.hide();
    var served = records(p, SYSTEMS)[1];
    served.zones = [{ zone_id: fixtures.ZONES.D.zone_id, reference: fixtures.ZONES.D, name: "Zone D" }];
    p.paint();
    replacement.open(served, records(p, SYSTEMS));
    assert.deepStrictEqual(options(), ["", "__clear__", fixtures.HWS1.id], "a System only Zones name may clear them");
  });

test("Serves on a System opens the Zone picker on the hot water slot, and a Locate narrows the Tanks", function () {
  var o = setup();
  press(row(o, fixtures.HWS2.id).querySelector(".mech-serves-cell"));
  var picker = o.view(SYSTEMS).picker.held;
  var c = picker.list.querySelectorAll("input").filter(function (input) {
    return input.getAttribute("data-zone-path") === JSON.stringify(fixtures.ZONES.A.zone_path);
  })[0];
  c.checked = true; c.listeners.change({});
  press(picker.apply);
  assert.deepStrictEqual(clone(named(o, PREFIX + "serves.assign")[0].payload.params), { zones: [{
    reference: fixtures.ZONES.A, expected_values: { ventilator_id: fixtures.ERV1.id, hot_water_system_id: null } }],
  slot: "hot_water_system_id", item_id: fixtures.HWS2.id });

  var p = setup();
  p.navigate({ hot_water_tank_ids: [fixtures.T4.id] });
  assert.strictEqual(p.pills.active, TANKS);
  assert.deepStrictEqual(p.view(TANKS).inventory.controls.columnFilter("name"), ["T4"]);
  assert.strictEqual(row(p, fixtures.T1.id).hidden, true);
});
