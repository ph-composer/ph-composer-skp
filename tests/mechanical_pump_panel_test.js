"use strict";
/* Mechanical › Pumps: the Pumps table, each control sending only the registered Pump and Serves operations. The
   internal heat gain values sit behind each row's disclosure, the usage profile following the type until one is
   chosen; the Zones a pump serves, its findings and the profile its type gives are the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/mechanical_fixtures");
var PREFIX = fixtures.PREFIX, SYSTEM = PREFIX + "pumps", PUMPS = PREFIX + "pumps";
var P1 = { id: "pmp_AAAAAAAAAAAA", name: "P-1" }, P2 = { id: "pmp_BBBBBBBBBBBB", name: "P-2" };
var DEFAULTS = { device_type: 6, quantity: 1, in_conditioned_space: true, norm_energy_demand_w: 0,
  annual_period_operation_khrs: 8.76, ihg_utilization_factor: 1 };

function zone(letter) {
  return { zone_id: fixtures.ZONES[letter].zone_id, reference: fixtures.ZONES[letter], name: "Zone " + letter };
}
function pump(item, values, zones, profile, findings) {
  return { id: item.id, kind: PREFIX + "pump", schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], findings: findings || [], zones: zones,
    ihg_usage_profile_default: profile,
    values: Object.assign({ name: item.name, notes: "", datasheet_links: [], source: { kind: "manual" } }, DEFAULTS,
      values) };
}
/* P-1 (a heating circulation pump, 45 W) serves Zones A and B; P-2 (defaults, its gain named summer) serves
   nothing. */
function pumps(state) {
  state.sections[PUMPS] = { status: "completed", value: { unreadable: [], records: [
    pump(P1, { device_type: 4, norm_energy_demand_w: 45, manufacturer: "Kaltwerk" }, [zone("A"), zone("B")], 2),
    pump(P2, { ihg_usage_profile: 3 }, [], 4, [{ code: "mechanical.item_unserved", severity: "warning",
      blocks_export: false, message: "P-2 serves no Zone, so nothing exports it." }])] } };
  state.sections[PREFIX + "serves"].value.zones.forEach(function (row) {
    var served = row.zone_id === fixtures.ZONES.A.zone_id || row.zone_id === fixtures.ZONES.B.zone_id;
    row.slots.pump_ids = served ? [P1.id] : [];
  });
  return state;
}

function setup() {
  var document = dom.buildDocument("");
  var sections = {}, navigate = {}, sent = [], notices = [], state = pumps(fixtures.state());
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
    setTimeout: setTimeout, clearTimeout: clearTimeout, navigator: {} };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["features/mechanical/section", "features/mechanical/ventilators",
    "features/mechanical/pumps"], { panel: panel });
  paint();
  root._view.tabs.select(SYSTEM);
  var system = root._view.systems.filter(function (entry) { return entry.id === SYSTEM; })[0];
  var view = root._view.tables.filter(function (held) { return held.id === PUMPS; })[0].view;
  return { root: root, state: state, sent: sent, notices: notices, paint: paint, view: view, pills: system.pills,
    modules: modules, navigate: function (intent) { navigate.mechanical(root, intent); } };
}
function named(o, name) { return o.sent.filter(function (message) { return message.payload.name === name; }); }
function press(node) { node.listeners.click({ preventDefault: function () {} }); }
function row(o, id) { return o.root.querySelector("[data-row-key=" + id + "]"); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function type(input, text) { input.value = text; input.listeners.input({}); }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopImmediatePropagation: function () {} });
}
function cell(o, id, field) { return o.view.inventory.edits.cells[id + ":" + field]; }
function answer(o, message, outcome) {
  o.state.ui.actionResult = { request_id: message.payload.request_id, session: "session", outcome: outcome };
  o.paint();
}
function disclosure(o, id) {
  return row(o, id).querySelectorAll("button").filter(function (node) {
    return /^Internal heat gains of/.test(node.getAttribute("aria-label") || "");
  })[0];
}

test("the Pumps subtab holds the Pumps pill: Tag, the supportive device values and Serves, identity hideable",
  function () {
    var o = setup();
    assert.deepStrictEqual(o.root.querySelector(".phc-subtabs").querySelectorAll("[role=tab]").map(function (node) {
      return node.textContent;
    }), ["Ventilation", "Pumps"]);
    assert.deepStrictEqual(o.pills.root.querySelectorAll("button").map(function (node) { return node.textContent; }),
      ["Pumps"]);
    assert.deepStrictEqual(o.view.inventory.scroll.querySelectorAll("th").map(function (th) {
      return th.className.match(/col-([a-z_0-9]+)/);
    }).filter(Boolean).map(function (match) { return match[1]; }),
    ["actions", "name", "device_type", "quantity", "norm_energy_demand_w", "annual_period_operation_khrs",
      "in_conditioned_space", "serves", "manufacturer", "model", "notes"]);
    assert.match(o.root._view.header.root.querySelector(".primary").textContent, /New Pump$/);
    assert.strictEqual(cell(o, P1.id, "device_type").input.value, "4");
    assert.strictEqual(cell(o, P1.id, "norm_energy_demand_w").input.value, "45");
    assert.deepStrictEqual(row(o, P2.id).querySelector(".mech-serves-cell").querySelectorAll(".mech-zone-chip")
      .map(function (chip) { return chip.textContent; }), ["Serves no Zone"]);
  });

test("a type change and a power edit send guarded updates, and a negative power is not sent", function () {
  var o = setup(), kind = cell(o, P1.id, "device_type");
  kind.input.value = "10"; kind.input.listeners.change({});
  assert.deepStrictEqual(clone(named(o, PUMPS + ".update")[0].payload.params), { id: P1.id,
    values: { device_type: 10 }, expected_values: { device_type: 4 } });
  answer(o, named(o, PUMPS + ".update")[0], { status: "completed", value: {} });

  var power = cell(o, P2.id, "norm_energy_demand_w");
  type(power.input, "-5"); key(power.input, "Enter");
  assert.match(power.message, /cannot be negative/);
  assert.strictEqual(named(o, PUMPS + ".update").length, 1, "a negative power is not sent");
  key(power.input, "Escape");
  type(power.input, "25"); key(power.input, "Enter");
  assert.deepStrictEqual(clone(named(o, PUMPS + ".update")[1].payload.params), { id: P2.id,
    values: { norm_energy_demand_w: 25 }, expected_values: { norm_energy_demand_w: 0 } });
});

test("power and operation read and take the regional number format, the same unit in SI and IP", function () {
  var o = setup();
  o.modules.unit_preferences.replace({ unit_system: "IP", dimension_formats: {},
    number_format: { decimal: ",", group: ".", locale: "de-DE" } });
  o.paint();
  var operation = cell(o, P2.id, "annual_period_operation_khrs");
  assert.strictEqual(operation.input.value, "8,76", "kilohours stay kilohours under IP");
  type(operation.input, "4,5"); key(operation.input, "Enter");
  assert.deepStrictEqual(clone(named(o, PUMPS + ".update")[0].payload.params), { id: P2.id,
    values: { annual_period_operation_khrs: 4.5 }, expected_values: { annual_period_operation_khrs: 8.76 } });
});

test("a copied power and operation keep every stored digit, so pasting them back sends nothing", function () {
  var o = setup(), values = o.state.sections[PUMPS].value.records[0].values;
  values.norm_energy_demand_w = 45.04; values.annual_period_operation_khrs = 8.7654;
  o.paint();
  var power = cell(o, P1.id, "norm_energy_demand_w"), grid = o.view.inventory.grid;
  assert.strictEqual(power.input.value, "45", "the cell shows the display precision");
  ["SI", "IP"].forEach(function (system) {
    o.modules.unit_preferences.set("unit_system", system); o.paint();
    grid.refresh();
    grid.select(power, false); grid.select(cell(o, P1.id, "annual_period_operation_khrs"), true);
    var copy = new dom.ClipboardEvent("copy");
    o.view.inventory.scroll.listeners.copy(copy);
    assert.strictEqual(copy.clipboardData.getData("text/plain"), "45.04\t8.7654", system);
    grid.paste([["45.04", "8.7654"]]);
    assert.strictEqual(named(o, PUMPS + ".update").length, 0, system + ": pasting the copy back changes nothing");
  });
});

test("a power stored past the nanowatt pastes back as itself, sending nothing", function () {
  var o = setup();
  o.state.sections[PUMPS].value.records[0].values.norm_energy_demand_w = 45.0400000004;
  o.paint();
  var grid = o.view.inventory.grid, power = cell(o, P1.id, "norm_energy_demand_w");
  grid.refresh(); grid.select(power, false);
  var copy = new dom.ClipboardEvent("copy");
  o.view.inventory.scroll.listeners.copy(copy);
  grid.paste([[copy.clipboardData.getData("text/plain")]]);
  assert.strictEqual(named(o, PUMPS + ".update").length, 0);
});

test("the internal heat gains sit behind the row's disclosure, the profile following the type until one is chosen",
  function () {
    var o = setup();
    assert.strictEqual(disclosure(o, P1.id).getAttribute("aria-pressed"), "false", "both at their defaults");
    assert.match(disclosure(o, P1.id).getAttribute("aria-label"), /: Defaults$/);
    assert.strictEqual(disclosure(o, P2.id).getAttribute("aria-pressed"), "true");
    assert.match(disclosure(o, P2.id).getAttribute("aria-label"), /Usage profile Summer/);

    press(disclosure(o, P1.id));
    var held = o.view.optional.held, factor = held.fields[0].unit, profile = held.fields[1].unit;
    assert.strictEqual(held.bubble.panel.getAttribute("aria-label"), "Internal heat gains of P-1");
    assert.deepStrictEqual(profile.input.querySelectorAll("option").map(function (node) { return node.textContent; }),
      ["From type (Winter)", "All year", "Winter", "Summer", "None (hot water)"]);
    assert.strictEqual(profile.input.value, "", "no profile chosen: it follows the type");
    profile.input.value = "1"; profile.input.listeners.change({});
    var update = named(o, PUMPS + ".update")[0];
    assert.deepStrictEqual(clone(update.payload.params), { id: P1.id, values: { ihg_usage_profile: 1 },
      expected_values: { ihg_usage_profile: null } });
    answer(o, update, { status: "refused", code: "target.changed", message: "The Pump changed." });
    assert.strictEqual(profile.error.textContent, "The Pump changed.");
    assert.strictEqual(profile.input.value, "", "a choice shows the Model's value again");

    var records = o.state.sections[PUMPS].value.records;
    records[0].values.ihg_usage_profile = 3;
    records[0].values.device_type = 6;
    records[0].ihg_usage_profile_default = 4;
    o.paint();
    assert.strictEqual(profile.input.value, "3", "after a refusal the choice still follows a newer snapshot");
    assert.strictEqual(profile.input.querySelectorAll("option")[0].textContent, "From type (None (hot water))");
    profile.input.value = ""; profile.input.listeners.change({});
    assert.deepStrictEqual(clone(named(o, PUMPS + ".update")[1].payload.params), { id: P1.id,
      values: { ihg_usage_profile: null }, expected_values: { ihg_usage_profile: 3 } },
    "the next write is guarded by the value shown");
    answer(o, named(o, PUMPS + ".update")[1], { status: "completed", value: {} });

    factor.input.value = "0.5"; factor.input.listeners.input({}); key(factor.input, "Enter");
    assert.deepStrictEqual(clone(named(o, PUMPS + ".update")[2].payload.params), { id: P1.id,
      values: { ihg_utilization_factor: 0.5 }, expected_values: { ihg_utilization_factor: 1 } });

    var update2 = named(o, PUMPS + ".update")[2];
    records[0].values.ihg_utilization_factor = 0.8;
    answer(o, update2, { status: "refused", code: "target.changed", message: "The Pump changed." });
    assert.strictEqual(factor.input.value, "0.8");
    records[0].values.ihg_utilization_factor = 0.6;
    o.paint();
    assert.strictEqual(factor.input.value, "0.6", "a field with no draft follows a newer snapshot after a refusal");
    assert.strictEqual(factor.error.textContent, "The Pump changed.", "and keeps its message");
    factor.input.value = "0.7"; factor.input.listeners.input({}); key(factor.input, "Enter");
    assert.deepStrictEqual(clone(named(o, PUMPS + ".update")[3].payload.params.expected_values),
      { ihg_utilization_factor: 0.6 }, "the retry is guarded by the value shown");

    var p = setup();
    press(disclosure(p, P2.id));
    var chosen = p.view.optional.held.fields[1].unit;
    assert.strictEqual(chosen.input.value, "3");
    chosen.input.value = ""; chosen.input.listeners.change({});
    assert.deepStrictEqual(clone(named(p, PUMPS + ".update")[0].payload.params), { id: P2.id,
      values: { ihg_usage_profile: null }, expected_values: { ihg_usage_profile: 3 } }, "From type sends null");
  });

test("a factor off 1 presses the arrow, and the open profile follows a type change and survives a repaint",
  function () {
    var o = setup(), records = o.state.sections[PUMPS].value.records;
    records[0].values.ihg_utilization_factor = 0.5;
    o.paint();
    assert.strictEqual(disclosure(o, P1.id).getAttribute("aria-pressed"), "true");
    assert.match(disclosure(o, P1.id).getAttribute("aria-label"), /Utilization factor 0.5/);

    press(disclosure(o, P1.id));
    var profile = o.view.optional.held.fields[1].unit, options = profile.input.querySelectorAll("option");
    o.paint();
    assert.strictEqual(profile.input.querySelectorAll("option")[0], options[0], "a repaint keeps the open list");
    records[0].values.device_type = 6;
    records[0].ihg_usage_profile_default = 4;
    o.paint();
    assert.strictEqual(profile.input.querySelectorAll("option")[0].textContent, "From type (None (hot water))");
    assert.strictEqual(profile.input.value, "");
  });

test("New asks for the Tag only, and the Zone picker adds a pump beside a Zone's others", function () {
  var o = setup(), form = o.view.table.newRecord;
  press(o.root._view.header.root.querySelector(".primary"));
  type(form.name, "P-3");
  form.submit();
  assert.deepStrictEqual(clone(named(o, PUMPS + ".create")[0].payload.params), { values: { name: "P-3" } });

  var p = setup();
  press(row(p, P1.id).querySelector(".mech-serves-cell"));
  var picker = p.view.picker.held;
  function input(letter) {
    return picker.list.querySelectorAll("input").filter(function (node) {
      return node.getAttribute("data-zone-path") === JSON.stringify(fixtures.ZONES[letter].zone_path);
    })[0];
  }
  assert.strictEqual(input("A").checked, true, "a Zone's list naming the pump reads as served");
  input("C").checked = true; input("C").listeners.change({});
  press(picker.apply);
  var assign = clone(named(p, PREFIX + "serves.assign")[0].payload.params);
  assert.deepStrictEqual([assign.slot, assign.item_id, assign.replace], ["pump_ids", P1.id, undefined],
    "nothing is replaced in a list slot");
  assert.deepStrictEqual(assign.zones.map(function (target) { return target.reference.zone_id; }),
    [fixtures.ZONES.C.zone_id]);
});

test("a delete in use asks for a replacement or clearing, and a Locate narrows the table", function () {
  var o = setup(), form = o.view.table.replacement, records = o.state.sections[PUMPS].value.records;
  form.open(records[0], records);
  assert.strictEqual(form.inUse, true, "P-1 serves Zones A and B");
  form.select.value = "__clear__";
  form.submit();
  assert.deepStrictEqual(clone(named(o, PUMPS + ".delete")[0].payload.params), { id: P1.id,
    expected_values: { name: "P-1" }, replacement_id: null });

  var p = setup();
  p.navigate({ pump_ids: [P2.id] });
  assert.deepStrictEqual(p.view.inventory.controls.columnFilter("name"), ["P-2"]);
  assert.strictEqual(row(p, P1.id).hidden, true);
});
