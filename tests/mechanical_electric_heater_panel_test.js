"use strict";
/* Mechanical › Electric Heating: the Heaters table, each control sending only the registered Electric Heater and
   Serves operations. Coverage reads and is entered in percent and travels as the stored fraction; the Zones a heater
   serves and its findings are the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/mechanical_fixtures");
var PREFIX = fixtures.PREFIX, SYSTEM = PREFIX + "electric_heating", HEATERS = PREFIX + "electric_heaters";
var EH1 = { id: "ehr_AAAAAAAAAAAA", name: "EH-1" }, EH2 = { id: "ehr_BBBBBBBBBBBB", name: "EH-2" };

function zone(letter) {
  return { zone_id: fixtures.ZONES[letter].zone_id, reference: fixtures.ZONES[letter], name: "Zone " + letter };
}
function heater(item, values, zones, findings) {
  return { id: item.id, kind: PREFIX + "electric_heater", schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], findings: findings || [], zones: zones,
    values: Object.assign({ name: item.name, notes: "", datasheet_links: [], source: { kind: "manual" },
      percent_coverage: 1 }, values) };
}
/* EH-1 (60%) serves Zones A and B; EH-2 (100%) serves nothing. */
function electricHeaters(state) {
  state.sections[HEATERS] = { status: "completed", value: { unreadable: [], records: [
    heater(EH1, { percent_coverage: 0.6, manufacturer: "Kaltwerk" }, [zone("A"), zone("B")]),
    heater(EH2, {}, [], [{ code: "mechanical.item_unserved", severity: "warning", blocks_export: false,
      message: "EH-2 serves no Zone, so nothing exports it." }])] } };
  state.sections[PREFIX + "serves"].value.zones.forEach(function (row) {
    var served = row.zone_id === fixtures.ZONES.A.zone_id || row.zone_id === fixtures.ZONES.B.zone_id;
    row.slots.heater_ids = served ? [EH1.id] : [];
  });
  return state;
}

function setup() {
  var document = dom.buildDocument("");
  var sections = {}, navigate = {}, sent = [], notices = [], state = electricHeaters(fixtures.state());
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
    "features/mechanical/electric_heaters"], { panel: panel });
  paint();
  root._view.tabs.select(SYSTEM);
  var system = root._view.systems.filter(function (entry) { return entry.id === SYSTEM; })[0];
  var view = root._view.tables.filter(function (held) { return held.id === HEATERS; })[0].view;
  return { root: root, state: state, sent: sent, notices: notices, paint: paint, view: view, pills: system.pills,
    navigate: function (intent) { navigate.mechanical(root, intent); } };
}
function named(o, name) { return o.sent.filter(function (message) { return message.payload.name === name; }); }
function press(node) { node.listeners.click({ preventDefault: function () {} }); }
function row(o, id) { return o.root.querySelector("[data-row-key=" + id + "]"); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function type(input, text) { input.value = text; input.listeners.input({}); }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopImmediatePropagation: function () {} });
}
function cell(o, id) { return o.view.inventory.edits.cells[id + ":percent_coverage"]; }

test("the Electric Heating subtab holds the Heaters pill: Tag, Coverage and Serves, identity hideable", function () {
  var o = setup();
  assert.deepStrictEqual(o.root.querySelector(".phc-subtabs").querySelectorAll("[role=tab]").map(function (node) {
    return node.textContent;
  }), ["Ventilation", "Electric Heating"]);
  assert.deepStrictEqual(o.pills.root.querySelectorAll("button").map(function (node) { return node.textContent; }),
    ["Heaters"]);
  assert.deepStrictEqual(o.view.inventory.scroll.querySelectorAll("th").map(function (th) {
    return th.className.match(/col-([a-z_0-9]+)/);
  }).filter(Boolean).map(function (match) { return match[1]; }),
  ["actions", "name", "percent_coverage", "serves", "manufacturer", "model", "notes"]);
  assert.match(o.root._view.header.root.querySelector(".primary").textContent, /New Electric Heater$/);
  assert.deepStrictEqual(row(o, EH1.id).querySelector(".mech-serves-cell").querySelectorAll(".mech-zone-chip")
    .map(function (chip) { return chip.textContent; }), ["Zone A", "Zone B"]);
  assert.deepStrictEqual(row(o, EH2.id).querySelector(".mech-serves-cell").querySelectorAll(".mech-zone-chip")
    .map(function (chip) { return chip.textContent; }), ["Serves no Zone"]);
});

test("coverage reads in percent, is sent and guarded as the stored fraction, and a refused draft is kept",
  function () {
    var o = setup(), coverage = cell(o, EH1.id);
    assert.strictEqual(coverage.input.value, "60", "coverage reads as a percentage");
    type(coverage.input, "45"); key(coverage.input, "Enter");
    assert.deepStrictEqual(clone(named(o, HEATERS + ".update")[0].payload.params), { id: EH1.id,
      values: { percent_coverage: 0.45 }, expected_values: { percent_coverage: 0.6 } });
    var update = named(o, HEATERS + ".update")[0];
    o.state.ui.actionResult = { request_id: update.payload.request_id, session: "session",
      outcome: { status: "refused", code: "target.changed", message: "The Electric Heater changed." } };
    o.paint();
    assert.strictEqual(cell(o, EH1.id).input.value, "45", "a refused draft is kept");
    assert.ok(o.root._view.guard(), "a refused draft holds the tab");
    key(cell(o, EH1.id).input, "Escape");

    var over = cell(o, EH2.id);
    type(over.input, "120"); key(over.input, "Enter");
    assert.match(over.message, /percentage from 0 to 100/);
    assert.strictEqual(named(o, HEATERS + ".update").length, 1, "an out-of-range value is not sent");
  });

test("New asks for the Tag only, and the Zone picker adds a heater beside a Zone's others", function () {
  var o = setup(), form = o.view.table.newRecord;
  press(o.root._view.header.root.querySelector(".primary"));
  type(form.name, "EH-3");
  form.submit();
  assert.deepStrictEqual(clone(named(o, HEATERS + ".create")[0].payload.params), { values: { name: "EH-3" } });

  var p = setup();
  press(row(p, EH1.id).querySelector(".mech-serves-cell"));
  var picker = p.view.picker.held;
  function input(letter) {
    return picker.list.querySelectorAll("input").filter(function (node) {
      return node.getAttribute("data-zone-path") === JSON.stringify(fixtures.ZONES[letter].zone_path);
    })[0];
  }
  assert.strictEqual(input("A").checked, true, "a Zone's list naming the heater reads as served");
  input("A").checked = false; input("A").listeners.change({});
  input("C").checked = true; input("C").listeners.change({});
  press(picker.apply);
  var assign = clone(named(p, PREFIX + "serves.assign")[0].payload.params);
  assert.deepStrictEqual([assign.slot, assign.item_id, assign.replace], ["heater_ids", EH1.id, undefined],
    "nothing is replaced in a list slot");
  assert.deepStrictEqual(assign.zones.map(function (target) { return target.reference.zone_id; }),
    [fixtures.ZONES.C.zone_id]);
});

test("a delete in use asks for a replacement or clearing, and a Locate narrows the table", function () {
  var o = setup(), form = o.view.table.replacement, heaters = o.state.sections[HEATERS].value.records;
  form.open(heaters[0], heaters);
  assert.strictEqual(form.inUse, true, "EH-1 serves Zones A and B");
  form.select.value = "__clear__";
  form.submit();
  assert.deepStrictEqual(clone(named(o, HEATERS + ".delete")[0].payload.params), { id: EH1.id,
    expected_values: { name: "EH-1" }, replacement_id: null });

  var p = setup();
  p.navigate({ electric_heater_ids: [EH2.id] });
  assert.deepStrictEqual(p.view.inventory.controls.columnFilter("name"), ["EH-2"]);
  assert.strictEqual(row(p, EH1.id).hidden, true);
});
