"use strict";
/* Mechanical › Fans: the Fans table, each control sending only the registered Fan and Serves operations. Whether the
   fan sits in conditioned space and an operation overriding the one its runtime gives sit behind each row's
   disclosure; the Zones a fan serves, its findings and the operation its runtime gives are the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/mechanical_fixtures");
var PREFIX = fixtures.PREFIX, SYSTEM = PREFIX + "fans", FANS = PREFIX + "fans";
var FAN_1 = { id: "fan_AAAAAAAAAAAA", name: "F-1" }, FAN_2 = { id: "fan_BBBBBBBBBBBB", name: "F-2" };
var DEFAULTS = { exhaust_type: "user_defined", quantity: 1, exhaust_flow_rate_m3h: 0, annual_runtime_minutes: 0,
  in_conditioned_space: true };

function zone(letter) {
  return { zone_id: fixtures.ZONES[letter].zone_id, reference: fixtures.ZONES[letter], name: "Zone " + letter };
}
function fan(item, values, zones, findings) {
  var stored = Object.assign({ name: item.name, notes: "", datasheet_links: [], source: { kind: "manual" } },
    DEFAULTS, values);
  return { id: item.id, kind: PREFIX + "fan", schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], findings: findings || [], zones: zones,
    annual_period_operation_khrs_default: stored.annual_runtime_minutes / 60000, values: stored };
}
/* F-1 (a kitchen hood, 250 m³/h for 10,950 minutes a year, 120 W) serves Zones A and B; F-2 (defaults, outside the
   envelope, with no Power) serves nothing. */
function fans(state) {
  state.sections[FANS] = { status: "completed", value: { unreadable: [], records: [
    fan(FAN_1, { exhaust_type: "kitchen_hood", exhaust_flow_rate_m3h: 250, annual_runtime_minutes: 10950,
      norm_energy_demand_w: 120, manufacturer: "Kaltwerk" }, [zone("A"), zone("B")]),
    fan(FAN_2, { in_conditioned_space: false }, [], [{ code: "mechanical.item_unserved", severity: "warning",
      blocks_export: false, message: "F-2 serves no Zone, so nothing exports it." }])] } };
  state.sections[PREFIX + "serves"].value.zones.forEach(function (row) {
    var served = row.zone_id === fixtures.ZONES.A.zone_id || row.zone_id === fixtures.ZONES.B.zone_id;
    row.slots.fan_ids = served ? [FAN_1.id] : [];
  });
  return state;
}

function setup() {
  var document = dom.buildDocument("");
  var sections = {}, navigate = {}, sent = [], notices = [], state = fans(fixtures.state());
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
    "features/mechanical/fans"], { panel: panel });
  paint();
  root._view.tabs.select(SYSTEM);
  var system = root._view.systems.filter(function (entry) { return entry.id === SYSTEM; })[0];
  var view = root._view.tables.filter(function (held) { return held.id === FANS; })[0].view;
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
    return /^Electric values of/.test(node.getAttribute("aria-label") || "");
  })[0];
}

test("the Fans subtab holds the Fans pill: Tag, the exhaust values, Power and Serves, identity hideable", function () {
  var o = setup();
  assert.deepStrictEqual(o.root.querySelector(".phc-subtabs").querySelectorAll("[role=tab]").map(function (node) {
    return node.textContent;
  }), ["Ventilation", "Fans"]);
  assert.deepStrictEqual(o.pills.root.querySelectorAll("button").map(function (node) { return node.textContent; }),
    ["Fans"]);
  assert.deepStrictEqual(o.view.inventory.scroll.querySelectorAll("th").map(function (th) {
    return th.className.match(/col-([a-z_0-9]+)/);
  }).filter(Boolean).map(function (match) { return match[1]; }),
  ["actions", "name", "exhaust_type", "quantity", "exhaust_flow_rate_m3h", "annual_runtime_minutes",
    "norm_energy_demand_w", "serves", "manufacturer", "model", "notes"]);
  assert.match(o.root._view.header.root.querySelector(".primary").textContent, /New Fan$/);
  assert.strictEqual(cell(o, FAN_1.id, "exhaust_type").input.value, "kitchen_hood");
  assert.strictEqual(cell(o, FAN_1.id, "annual_runtime_minutes").input.value, "10950");
  assert.strictEqual(cell(o, FAN_1.id, "norm_energy_demand_w").input.value, "120");
  assert.strictEqual(cell(o, FAN_2.id, "norm_energy_demand_w").input.value, "", "no Power reads blank");
  assert.deepStrictEqual(row(o, FAN_2.id).querySelector(".mech-serves-cell").querySelectorAll(".mech-zone-chip")
    .map(function (chip) { return chip.textContent; }), ["Serves no Zone"]);
});

test("a type change and a flow edit send guarded updates; a negative value is not sent; a blank Power is null",
  function () {
    var o = setup(), kind = cell(o, FAN_1.id, "exhaust_type");
    kind.input.value = "dryer"; kind.input.listeners.change({});
    assert.deepStrictEqual(clone(named(o, FANS + ".update")[0].payload.params), { id: FAN_1.id,
      values: { exhaust_type: "dryer" }, expected_values: { exhaust_type: "kitchen_hood" } });
    answer(o, named(o, FANS + ".update")[0], { status: "completed", value: {} });

    ["exhaust_flow_rate_m3h", "annual_runtime_minutes", "norm_energy_demand_w"].forEach(function (field) {
      var entered = cell(o, FAN_2.id, field);
      type(entered.input, "-5"); key(entered.input, "Enter");
      assert.match(entered.message, /cannot be negative/, field);
      key(entered.input, "Escape");
    });
    var quantity = cell(o, FAN_2.id, "quantity");
    type(quantity.input, "0"); key(quantity.input, "Enter");
    assert.match(quantity.message, /Enter a whole number of 1 or more/);
    key(quantity.input, "Escape");
    assert.strictEqual(named(o, FANS + ".update").length, 1, "a negative value is not sent");

    var flow = cell(o, FAN_2.id, "exhaust_flow_rate_m3h");
    type(flow.input, "80"); key(flow.input, "Enter");
    assert.deepStrictEqual(clone(named(o, FANS + ".update")[1].payload.params), { id: FAN_2.id,
      values: { exhaust_flow_rate_m3h: 80 }, expected_values: { exhaust_flow_rate_m3h: 0 } });
    answer(o, named(o, FANS + ".update")[1], { status: "completed", value: {} });

    var power = cell(o, FAN_1.id, "norm_energy_demand_w");
    type(power.input, ""); key(power.input, "Enter");
    assert.deepStrictEqual(clone(named(o, FANS + ".update")[2].payload.params), { id: FAN_1.id,
      values: { norm_energy_demand_w: null }, expected_values: { norm_energy_demand_w: 120 } },
    "a blank Power takes the supportive device away");
  });

test("the electric values sit behind the row's disclosure, the operation following the runtime until one is named",
  function () {
    var o = setup();
    assert.strictEqual(disclosure(o, FAN_1.id).getAttribute("aria-pressed"), "false", "both at their defaults");
    assert.match(disclosure(o, FAN_1.id).getAttribute("aria-label"), /: Defaults$/);
    assert.strictEqual(disclosure(o, FAN_2.id).getAttribute("aria-pressed"), "true");
    assert.match(disclosure(o, FAN_2.id).getAttribute("aria-label"),
      /: In conditioned space No \(exported only with Power\)$/, "with no Power, the label says they do not export");

    press(disclosure(o, FAN_1.id));
    var held = o.view.optional.held, space = held.fields[0].unit, operation = held.fields[1].unit;
    assert.strictEqual(held.bubble.panel.getAttribute("aria-label"), "Electric values of F-1");
    assert.deepStrictEqual(space.input.querySelectorAll("option").map(function (node) { return node.textContent; }),
      ["Yes", "No"], "no blank: the fan is in conditioned space or not");
    assert.strictEqual(space.input.value, "true");
    assert.strictEqual(operation.input.value, "", "no operation named: it follows the runtime");
    assert.strictEqual(operation.input.placeholder, "From runtime (0.18 kh/yr)");

    space.input.value = "false"; space.input.listeners.change({});
    var update = named(o, FANS + ".update")[0];
    assert.deepStrictEqual(clone(update.payload.params), { id: FAN_1.id, values: { in_conditioned_space: false },
      expected_values: { in_conditioned_space: true } });
    answer(o, update, { status: "completed", value: {} });

    operation.input.value = "2.5"; operation.input.listeners.input({}); key(operation.input, "Enter");
    assert.deepStrictEqual(clone(named(o, FANS + ".update")[1].payload.params), { id: FAN_1.id,
      values: { annual_period_operation_khrs: 2.5 }, expected_values: { annual_period_operation_khrs: null } });
    answer(o, named(o, FANS + ".update")[1], { status: "completed", value: {} });

    var records = o.state.sections[FANS].value.records;
    records[0].values.annual_period_operation_khrs = 2.5;
    records[0].values.annual_runtime_minutes = 60000;
    records[0].annual_period_operation_khrs_default = 1;
    o.paint();
    assert.strictEqual(disclosure(o, FAN_1.id).getAttribute("aria-pressed"), "true");
    assert.match(disclosure(o, FAN_1.id).getAttribute("aria-label"), /Operation 2.5 kh\/yr/);
    assert.strictEqual(operation.input.placeholder, "From runtime (1 kh/yr)", "the placeholder follows the runtime");
    operation.input.value = ""; operation.input.listeners.input({}); key(operation.input, "Enter");
    assert.deepStrictEqual(clone(named(o, FANS + ".update")[2].payload.params), { id: FAN_1.id,
      values: { annual_period_operation_khrs: null }, expected_values: { annual_period_operation_khrs: 2.5 } },
    "a blank follows the runtime again");
  });

test("New asks for the Tag only, and the Zone picker adds a fan beside a Zone's others", function () {
  var o = setup(), form = o.view.table.newRecord;
  press(o.root._view.header.root.querySelector(".primary"));
  type(form.name, "F-3");
  form.submit();
  assert.deepStrictEqual(clone(named(o, FANS + ".create")[0].payload.params), { values: { name: "F-3" } });

  var p = setup();
  press(row(p, FAN_1.id).querySelector(".mech-serves-cell"));
  var picker = p.view.picker.held;
  function input(letter) {
    return picker.list.querySelectorAll("input").filter(function (node) {
      return node.getAttribute("data-zone-path") === JSON.stringify(fixtures.ZONES[letter].zone_path);
    })[0];
  }
  assert.strictEqual(input("A").checked, true, "a Zone's list naming the fan reads as served");
  input("C").checked = true; input("C").listeners.change({});
  press(picker.apply);
  var assign = clone(named(p, PREFIX + "serves.assign")[0].payload.params);
  assert.deepStrictEqual([assign.slot, assign.item_id, assign.replace], ["fan_ids", FAN_1.id, undefined],
    "nothing is replaced in a list slot");
  assert.deepStrictEqual(assign.zones.map(function (target) { return target.reference.zone_id; }),
    [fixtures.ZONES.C.zone_id]);
});

test("a delete in use asks for a replacement or clearing, and a Locate narrows the table", function () {
  var o = setup(), form = o.view.table.replacement, records = o.state.sections[FANS].value.records;
  form.open(records[0], records);
  assert.strictEqual(form.inUse, true, "F-1 serves Zones A and B");
  form.select.value = "__clear__";
  form.submit();
  assert.deepStrictEqual(clone(named(o, FANS + ".delete")[0].payload.params), { id: FAN_1.id,
    expected_values: { name: "F-1" }, replacement_id: null });

  var p = setup();
  p.navigate({ fan_ids: [FAN_2.id] });
  assert.deepStrictEqual(p.view.inventory.controls.columnFilter("name"), ["F-2"]);
  assert.strictEqual(row(p, FAN_1.id).hidden, true);
});
