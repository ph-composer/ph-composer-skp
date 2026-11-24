"use strict";
/* Mechanical › Heat Pumps: the four tables and the Blended result, each control sending only the registered heat pump
   and Serves operations. The panel computes nothing: the blend, the counts and the findings are the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/mechanical_fixtures");
var PREFIX = fixtures.PREFIX, SYSTEM = PREFIX + "heat_pumps";
var OUTDOOR = SYSTEM + ".outdoor_equipment", INDOOR = SYSTEM + ".indoor_equipment";
var OUTDOOR_UNITS = SYSTEM + ".outdoor_units", INDOOR_UNITS = SYSTEM + ".indoor_units";
var BLENDED = PREFIX + "heat_pumps_blended";
var ODU_A = { id: "hpo_AAAAAAAAAAAA", name: "ODU-A" }, ODU_B = { id: "hpo_BBBBBBBBBBBB", name: "ODU-B" };
var IDU = { id: "hpi_AAAAAAAAAAAA", name: "IDU-W09" };
var HP1 = { id: "hou_AAAAAAAAAAAA", name: "HP-1" };
var HP11 = { id: "hiu_AAAAAAAAAAAA", name: "HP-1.1" }, HP12 = { id: "hiu_BBBBBBBBBBBB", name: "HP-1.2" };

function record(kind, item, values, extra) {
  return Object.assign({ id: item.id, kind: PREFIX + kind, schema_version: 1, user_data: {}, extension_data: {},
    extension_status: {}, export_ready: true, export_blockers: [], findings: [],
    values: Object.assign({ name: item.name, notes: "", datasheet_links: [], source: { kind: "manual" } }, values) },
  extra || {});
}
/* ODU-A is rated by COPs with EER2/SEER2 cooling; ODU-B by HSPF2 and lacks its capacities. HP-1 installs ODU-A;
   HP-1.1 serves Zone A and HP-1.2 nothing. One blend, of Apartments. */
function heatPumps(state) {
  var sections = state.sections;
  sections[OUTDOOR] = { status: "completed", value: { unreadable: [], records: [
    record("hp_outdoor_equipment", ODU_A, { heating_rating_mode: "cop_pair", hspf_version: "hspf2",
      seer_version: "seer2", heating_cap_17f_kw: 6.4, heating_cap_47f_kw: 7.3, cop_17f: 2.4, cop_47f: 3.9,
      cooling_rating_mode: "eer_seer", cooling_cap_95f_kw: 6.4, eer: 12.5, seer: 20 }, { unit_count: 1 }),
    record("hp_outdoor_equipment", ODU_B, { heating_rating_mode: "hspf", hspf_version: "hspf2",
      seer_version: "seer2", cop_17f: 2.5, cop_47f: 2.5, hspf_value: 10, cooling_rating_mode: null },
    { unit_count: 0, export_ready: false,
      export_blockers: ["mechanical.hp_equipment_incomplete"] })] } };
  sections[INDOOR] = { status: "completed", value: { unreadable: [], records: [
    record("hp_indoor_equipment", IDU, { manufacturer: "Kaltwerk" }, { unit_count: 2 })] } };
  sections[OUTDOOR_UNITS] = { status: "completed", value: { unreadable: [], records: [
    record("hp_outdoor_unit", HP1, { outdoor_equipment_id: ODU_A.id, quantity: 1, in_conditioned_space: false },
      { indoor_unit_count: 2 })] } };
  function unit(item, zones, findings) {
    return record("hp_indoor_unit", item, { indoor_equipment_id: IDU.id, outdoor_unit_id: HP1.id, quantity: 1,
      in_conditioned_space: true }, { zones: zones, findings: findings || [] });
  }
  sections[INDOOR_UNITS] = { status: "completed", value: { unreadable: [], records: [
    unit(HP11, [{ zone_id: fixtures.ZONES.A.zone_id, reference: fixtures.ZONES.A, name: "Zone A" }]),
    unit(HP12, [], [{ code: "mechanical.hp_unit_unpaired", severity: "warning", blocks_export: false,
      message: "HP-1.2 serves no Zone, so the blend leaves it out." }])] } };
  sections[PREFIX + "serves"].value.zones.forEach(function (row) {
    row.slots.hp_indoor_unit_ids = row.zone_id === fixtures.ZONES.A.zone_id ? [HP11.id] : [];
  });
  var weighted = { id: ODU_A.id, name: "ODU-A", recirc: 1, capacity_17f: 1, capacity_47f: 1, cop_17f: 2.4,
    cop_47f: 3.9, hspf: null, derated_hspf: null, eer: 13, seer: 20.9, derated_seer: 18.3, ieer: 0, cop: 4.59 };
  var total = function (capacity, cop) { return { capacity_kbtuh: capacity, cop: cop, input_kbtuh: capacity / cop }; };
  sections[BLENDED] = { status: "completed", value: { climate: { state: "complete", reason: null }, findings: [
    { code: "mechanical.hp_unit_unpaired", severity: "warning", blocks_export: false, object_id: HP12.id,
      message: "HP-1.2 serves no Zone, so the blend leaves it out." }],
  segments: [{ segment: "Apartments", identifier: "ph_composer_heat_pump_abc", display_name: "Heat pumps: Apartments",
    zones: [{ zone_id: fixtures.ZONES.A.zone_id, name: "Zone A" }], outdoor_unit_ids: [HP1.id], result: {
      climate: { heating_99_f: 10.4, cooling_1_f: 88.7, monthly_air_f: [], heating_months: 5, share_below_17f: 0,
        share_below_47f: 1 },
      devices: [{ id: ODU_A.id, name: "ODU-A", quantity: 1, heating_data_type: "COPs", capacity_17f_kbtuh: 21.8,
        capacity_47f_kbtuh: 24.9, cop_17f: 2.4, cop_47f: 3.9, hspf: null, cooling_data_type: "EER2/SEER2",
        capacity_95f_kbtuh: 21.8, eer: 12.5, seer: 20, ieer: null }],
      weighted: [weighted],
      totals: { cooling: total(21.8, 4.59), heating_17f: total(21.8, 2.4), heating_47f: total(24.9, 3.9) },
      energy_model: { systems_needed: 1, cooling_coverage: 1, min_coil_temp_f: 53.6, flow_rate_cfm: 545,
        cooling_capacity_kbtuh: 21.8, cooling_cop: 4.59, heating_coverage: 1, cop_1: 2.4, ambient_1_f: 17,
        cop_2: 3.9, ambient_2_f: 47 },
      export: {} } }] } };
  return state;
}

function setup(pill) {
  var document = dom.buildDocument("");
  var sections = {}, sent = [], notices = [], state = heatPumps(fixtures.state());
  var root = dom.element("div", "phc-workspace");
  document.body.appendChild(root);
  function send(type, payload) { sent.push({ type: type, payload: payload }); }
  function paint() { Object.keys(sections).forEach(function (key) { sections[key](root, state, send); }); }
  var panel = { state: state, send: send, repaint: paint, navigationGuard: function () {}, workedOn: function () {},
    section: function (name, render) { sections[name] = render; },
    notify: function (message, tone) { notices.push({ message: message, tone: tone }); },
    setPreference: function (key, value, extra) { modules.unit_preferences.set(key, value, extra); } };
  var context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout, navigator: {} };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["features/mechanical/section", "features/mechanical/ventilators",
    "features/mechanical/heat_pumps", "features/mechanical/heat_pump_units", "features/mechanical/heat_pump_blended"],
  { panel: panel });
  paint();
  root._view.tabs.select(SYSTEM);
  var system = root._view.systems.filter(function (entry) { return entry.id === SYSTEM; })[0];
  system.pills.select(pill || OUTDOOR);
  function view(id) { return root._view.tables.filter(function (held) { return held.id === id; })[0].view; }
  return { root: root, state: state, sent: sent, notices: notices, paint: paint, modules: modules, view: view,
    pills: system.pills, document: document };
}
function named(o, name) { return o.sent.filter(function (message) { return message.payload.name === name; }); }
function press(node) { node.listeners.click({ preventDefault: function () {} }); }
function row(o, id) { return o.root.querySelector("[data-row-key=" + id + "]"); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function type(input, text) { input.value = text; input.listeners.input({}); }
function headers(o, id) {
  return o.view(id).inventory.scroll.querySelectorAll("th").map(function (th) {
    return th.className.match(/col-([a-z_0-9]+)/);
  }).filter(Boolean).map(function (match) { return match[1]; });
}
function choose(cellNode, value) {
  var select = cellNode.querySelector("select");
  select.value = value; select.listeners.change({});
}

test("the Heat Pumps subtab holds the five pills, and Equipment · Indoor is identity only", function () {
  var o = setup();
  assert.deepStrictEqual(o.root.querySelector(".phc-subtabs").querySelectorAll("[role=tab]").map(function (node) {
    return node.textContent;
  }), ["Ventilation", "Heat Pumps"]);
  assert.deepStrictEqual(o.pills.root.querySelectorAll("button").map(function (node) { return node.textContent; }),
    ["Equipment · Outdoor", "Equipment · Indoor", "Units · Outdoor", "Units · Indoor", "Blended result"]);
  assert.deepStrictEqual(headers(o, OUTDOOR), ["actions", "name", "paired_indoor_equipment_id", "heating_cap_17f_kw",
    "heating_cap_47f_kw", "heating_data", "cop_17f", "cop_47f", "hspf_value", "cooling_cap_95f_kw", "cooling_data",
    "eer", "seer", "ieer", "unit_count", "manufacturer", "model", "notes"]);
  o.pills.select(INDOOR);
  assert.deepStrictEqual(headers(o, INDOOR), ["actions", "name", "manufacturer", "model", "notes"]);
});

test("a rating mode is one guarded choice; the other mode's values are read only, and a lacking value is amber",
  function () {
    var o = setup();
    choose(row(o, ODU_A.id).querySelector(".col-heating_data"), "hspf");
    assert.deepStrictEqual(clone(named(o, OUTDOOR + ".update")[0].payload.params), { id: ODU_A.id,
      values: { heating_rating_mode: "hspf", hspf_version: "hspf" },
      expected_values: { heating_rating_mode: "cop_pair", hspf_version: "hspf2" } });
    var first = named(o, OUTDOOR + ".update")[0];
    o.state.ui.actionResult = { request_id: first.payload.request_id, session: "session",
      outcome: { status: "completed", value: {} } };
    o.paint();
    choose(row(o, ODU_A.id).querySelector(".col-cooling_data"), "");
    assert.deepStrictEqual(clone(named(o, OUTDOOR + ".update")[1].payload.params.values),
      { cooling_rating_mode: null });
    var second = named(o, OUTDOOR + ".update")[1];
    o.state.ui.actionResult = { request_id: second.payload.request_id, session: "session",
      outcome: { status: "completed", value: {} } };
    o.paint();
    var capacityCell = o.view(OUTDOOR).inventory.edits.cells[ODU_A.id + ":heating_cap_17f_kw"];
    capacityCell.input.value = ""; capacityCell.input.listeners.input({});
    capacityCell.input.listeners.keydown({ key: "Enter", preventDefault: function () {},
      stopImmediatePropagation: function () {} });
    assert.deepStrictEqual(clone(named(o, OUTDOOR + ".update").pop().payload.params.values),
      { heating_cap_17f_kw: null }, "a blank empties a capacity");
    var b = row(o, ODU_B.id);
    assert.ok(b.querySelector(".col-cop_17f").classList.contains("mech-inactive"), "an HSPF model reads no COP");
    assert.ok(b.querySelector(".col-heating_cap_17f_kw").classList.contains("mech-missing"));
    assert.ok(!b.querySelector(".col-hspf_value").classList.contains("mech-missing"));
    assert.ok(row(o, ODU_A.id).querySelector(".col-ieer").classList.contains("mech-inactive"));
  });

test("Units · Indoor sits under its outdoor unit, New names both parents, and its Zone picker keeps the list",
  function () {
    var o = setup(INDOOR_UNITS), view = o.view(INDOOR_UNITS);
    assert.strictEqual(view.inventory.controls.groupBy.value, "outdoor_unit_id");
    assert.strictEqual(view.outdoorLabel(HP1.id), "HP-1 · ODU-A");
    assert.match(view.note.textContent, /HP-1\.2 serves no Zone/);
    var form = view.table.newRecord;
    press(o.root._view.header.root.querySelector(".primary"));
    type(form.name, "HP-1.3");
    assert.deepStrictEqual(clone(form.parents.map(function (parent) { return parent.select.value; })), [IDU.id, HP1.id],
      "each sole choice is taken for a form just opened");
    form.submit();
    assert.deepStrictEqual(clone(named(o, INDOOR_UNITS + ".create")[0].payload.params), { values: {
      name: "HP-1.3", indoor_equipment_id: IDU.id, outdoor_unit_id: HP1.id } });

    var p = setup(INDOOR_UNITS);
    press(row(p, HP11.id).querySelector(".mech-serves-cell"));
    var picker = p.view(INDOOR_UNITS).picker.held;
    var zoneA = picker.list.querySelectorAll("input").filter(function (input) {
      return input.getAttribute("data-zone-path") === JSON.stringify(fixtures.ZONES.A.zone_path);
    })[0];
    assert.strictEqual(zoneA.checked, true, "a Zone's list naming the unit reads as served");
    zoneA.checked = false; zoneA.listeners.change({});
    press(picker.apply);
    var clear = clone(named(p, PREFIX + "serves.clear")[0].payload.params);
    assert.deepStrictEqual([clear.slot, clear.item_id], ["hp_indoor_unit_ids", HP11.id],
      "an unchecked Zone gives up only this unit");
  });

test("a delete in use asks for a replacement, and offers clearing only where nothing needs the record", function () {
  var o = setup();
  var form = o.view(OUTDOOR).table.replacement, models = o.state.sections[OUTDOOR].value.records;
  form.open(models[0], models);
  assert.strictEqual(form.inUse, true, "HP-1 installs ODU-A");
  var values = function () { return clone(form.select.querySelectorAll("option").map(function (node) {
    return node.value;
  })); };
  assert.deepStrictEqual(values(), ["", ODU_B.id], "an outdoor unit needs its model: no clearing");
  form.select.value = ODU_B.id;
  form.submit();
  assert.deepStrictEqual(clone(named(o, OUTDOOR + ".delete")[0].payload.params), { id: ODU_A.id,
    expected_values: { name: "ODU-A" }, replacement_id: ODU_B.id });

  var p = setup(INDOOR_UNITS), units = p.state.sections[INDOOR_UNITS].value.records;
  var unitForm = p.view(INDOOR_UNITS).table.replacement;
  unitForm.open(units[0], units);
  assert.strictEqual(unitForm.inUse, true, "HP-1.1 serves Zone A");
  unitForm.select.value = "__clear__";
  unitForm.submit();
  assert.strictEqual(clone(named(p, INDOOR_UNITS + ".delete")[0].payload.params).replacement_id, null);
});

test("the Blended result shows each Segment's estimator sections and copies their rows", function () {
  var o = setup(BLENDED), view = o.view(BLENDED);
  assert.strictEqual(o.root._view.header.root.querySelector(".primary").textContent, "Copy for the estimator");
  var block = o.root.querySelector(".mech-blend-segment");
  assert.strictEqual(block.querySelector(".mech-blend-title").textContent, "Apartments");
  assert.deepStrictEqual(block.querySelectorAll(".mech-blend-section").map(function (node) {
    return node.textContent;
  }),
    ["Inputs for Energy Model", "Climate Information", "Pumps or Fans", "Performance Data",
      "Weighted Value Calculations"]);
  assert.deepStrictEqual(o.root.querySelector(".mech-blend-notes").querySelectorAll("p").map(function (node) {
    return node.textContent;
  }), ["HP-1.2 serves no Zone, so the blend leaves it out."]);
  var lines = o.modules["features/mechanical/heat_pump_blended"].copyText(view.blends).split("\n");
  assert.strictEqual(lines[0], "Building Segment\tApartments");
  assert.ok(lines.indexOf("Weighted ASHP Heating COP 1\t2.40") >= 0, lines.join("\n"));
  assert.ok(lines.indexOf("Recirculation Air Flow Rate\t545") >= 0);
  assert.ok(lines.indexOf("ODU-A\t1\tCOPs\t21.8\t24.9\t2.40\t3.90\t\tEER2/SEER2\t21.8\t12.5\t20.0\t") >= 0);

  o.state.sections[BLENDED].value = { climate: { state: "missing", reason: "No climate." }, segments: [],
    findings: [] };
  o.paint();
  assert.strictEqual(view.create.disabled, true);
  assert.match(o.root.querySelector(".mech-blend-empty").textContent, /climate is incomplete/);
});
