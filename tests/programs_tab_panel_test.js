"use strict";

/* The Programs tab (html/features/programs/tab.js, record_page.js, program_editor.js, program_loads.js): it opens
   on the Model's default Program with its sidebar; a load's value commits as one programs.update of the whole load,
   guarded by it as drawn and stored in SI; a refusal lets the Model's value back into the field; a used record's
   Delete asks for its replacement; and the Export tab sends Programs findings here. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var REVISION = 3;
var PREFIX = "ph_composer.programs";

function load() {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/programs/tab"]);
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  p.snapshot = function (programs) {
    p.panel.receive({ type: "panel.snapshot", payload: snapshot(programs) });
  };
  p.snapshot(programs());
  p.panel.showTab("programs");
  return p;
}

function loads(changes) {
  var all = {
    people: { rule: "phius_residential", people_per_area: null, occupancy_schedule_id: "sch_occ",
      activity_schedule_id: null, radiant_fraction: 0.3, latent_fraction: null },
    lighting: { rule: null, watts_per_area: 2, high_efficacy_fraction: 1, schedule_id: null,
      return_air_fraction: 0, radiant_fraction: 0.32, visible_fraction: 0.25 },
    electric_equipment: { watts_per_area: 0, schedule_id: null, radiant_fraction: 0, latent_fraction: 0,
      lost_fraction: 0 },
    gas_equipment: { watts_per_area: 0, schedule_id: null, radiant_fraction: 0, latent_fraction: 0, lost_fraction: 0 },
    service_hot_water: { rule: null, flow_per_area: 0.1, target_temperature_c: 60, schedule_id: null,
      sensible_fraction: 0.2, latent_fraction: 0.05 },
    infiltration: { flow_per_exterior_area: 0.0003, schedule_id: null },
    ventilation: { flow_per_person: 0.0025, flow_per_area: null, flow_per_zone: null, air_changes_per_hour: null,
      schedule_id: null },
    setpoint: { heating_c: 20, cooling_c: 25, heating_schedule_id: null, cooling_schedule_id: null,
      dehumidify_rh: null, humidify_rh: null }
  };
  Object.keys(changes || {}).forEach(function (key) { Object.assign(all[key], changes[key]); });
  return all;
}

function row(kind, id, name, values, extra) {
  return Object.assign({ kind: PREFIX + "." + kind, id: id, schema_version: 1, user_data: {}, extension_status: {},
    stored: true, values: Object.assign({ name: name, notes: "", datasheet_links: [], source: { kind: "manual" } },
      values) }, extra);
}

function programs(changes) {
  return [row("program", "pgm_PHCDEFAULT01", "Residential default", loads(changes), { default: true, use_count: 2,
    missing: [] }), row("program", "pgm_office", "Office", loads({ people: { rule: null } }), { default: false,
    use_count: 0, missing: [{ load: "people", field: "people_per_area" }] })];
}

function snapshot(programRows) {
  var schedule = row("schedule", "sch_occ", "Occupancy", { type: "fractional", days_per_week: 7, weeks_per_year: 52,
    start_h: 0, end_h: 24, fraction_on: 1, fraction_off: 0 }, { uses: [], use_count: 0,
    profile: { hours: [], daily_full_load_hours: 24, annual_full_load_hours: 8760 } });
  return { product: "PH-Composer", version: "test", session: "session-a", revision: REVISION, file_name: "a.skp",
    edit_path: [], preferences: { unit_system: "SI" }, sections: {
      "ph_composer.programs.programs": { status: "completed", value: { records: programRows, unreadable: [] } },
      "ph_composer.programs.schedules": { status: "completed", value: { records: [schedule], unreadable: [] } },
      "ph_composer.programs.equipment_sets": { status: "completed", value: { records: [], unreadable: [] } },
      "ph_composer.programs.occupancy": { status: "completed", value: { zones: [
        { zone_id: "zon_a", program_id: "pgm_PHCDEFAULT01", equipment_set_id: null },
        { zone_id: "zon_b", program_id: "pgm_PHCDEFAULT01", equipment_set_id: null }],
      choices: { default_equipment_set_id: null } } } } };
}

function pane(p) { return p.context.document.querySelector("[data-pane='programs']"); }
function shown(p) {
  return pane(p).querySelectorAll(".pgm-layout").filter(function (node) { return !node.hidden; })[0];
}
function card(p, key) {
  return shown(p).querySelectorAll(".pgm-card").filter(function (node) {
    return node.getAttribute("data-load") === key; })[0];
}
function labelled(root, tag, label) {
  return root.querySelectorAll(tag).filter(function (node) { return node.getAttribute("aria-label") === label; })[0];
}
function click(node) { node.listeners.click({ preventDefault: function () {} }); }
function plain(value) { return JSON.parse(JSON.stringify(value)); }
function last(p) { var all = p.actions(); return all[all.length - 1].payload; }
function type(input, text) { input.focus(); input.value = text; input.listeners.input({}); }
function enter(input) {
  input.listeners.keydown({ key: "Enter", preventDefault: function () {}, stopPropagation: function () {} });
}

test("the tab opens on the Model's default Program, its sidebar naming this file's Programs", function () {
  var p = load();
  assert.strictEqual(shown(p).querySelector(".pgm-title").textContent, "Residential default");
  assert.strictEqual(shown(p).querySelector(".pgm-badge").textContent, "Unassigned Zones use this");
  var names = shown(p).querySelectorAll(".library-sidebar-name").map(function (node) { return node.textContent; });
  assert.deepStrictEqual(names, ["Residential default", "Office"]);
  assert.strictEqual(card(p, "people").querySelector(".pgm-sum").textContent, "Phius rule · Occupancy");
  assert.strictEqual(shown(p).querySelector(".pgm-metric").querySelector("strong").textContent, "2 Zones");
});

test("a value commits as one update of its load, guarded by the load and stored in m³/s", function () {
  var p = load();
  click(card(p, "ventilation").querySelector(".pgm-card-head"));
  var input = labelled(card(p, "ventilation"), "input", "Ventilation per person");
  assert.strictEqual(input.value, "9", "0.0025 m³/s is 9 m³/h per person");
  type(input, "18");
  enter(input);
  var sent = last(p);
  assert.strictEqual(sent.name, PREFIX + ".programs.update");
  assert.strictEqual(p.actions().length, 1, "one request");
  assert.deepStrictEqual(plain(sent.params.expected_values), { ventilation: loads().ventilation });
  assert.strictEqual(sent.params.values.ventilation.flow_per_person, 0.005);
  assert.strictEqual(sent.params.values.ventilation.air_changes_per_hour, null, "the rest of the load as drawn");
});

test("a refused value lets the Model's value back into the field", function () {
  var p = load();
  click(card(p, "ventilation").querySelector(".pgm-card-head"));
  var input = labelled(card(p, "ventilation"), "input", "Ventilation per person");
  type(input, "18");
  enter(input);
  p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
    outcome: { status: "refused", code: "target.changed", effect: "none", revision: REVISION,
      message: "Program Residential default has changed since it was read (ventilation)." } } });
  p.snapshot(programs({ ventilation: { flow_per_person: 0.003 } }));
  assert.strictEqual(input.value, "10.8", "the Model's 0.003 m³/s");
});

test("the rule switch is one update; a used record's Delete names its replacement", function () {
  var p = load();
  click(card(p, "people").querySelector(".pgm-card-head"));
  click(card(p, "people").querySelector(".pgm-rule-switch"));
  assert.deepStrictEqual(plain(last(p).params.values.people.rule), null);
  p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
    outcome: { status: "completed", code: "ok", effect: "committed", revision: REVISION + 1, value: {} } } });
  var menu = labelled(shown(p), "button", "Program actions");
  click(menu);
  click(shown(p).querySelectorAll(".phc-action-menu-item").filter(function (node) {
    return node.textContent === "Delete Program"; })[0]);
  var dialog = shown(p).querySelector(".pgm-confirm");
  assert.match(dialog.querySelector("p").textContent, /Model's default Program, on 2 Zones/);
  var replacement = dialog.querySelector("select");
  assert.deepStrictEqual(replacement.querySelectorAll("option").map(function (node) { return node.value; }),
    ["", "pgm_office"]);
  var commit = dialog.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Delete Program"; })[0];
  assert.strictEqual(commit.disabled, true, "a replacement is chosen, never assumed");
  replacement.value = "pgm_office"; replacement.listeners.change({});
  assert.strictEqual(commit.disabled, false);
  click(commit);
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), [PREFIX + ".programs.delete",
    { id: "pgm_PHCDEFAULT01", expected_values: { name: "Residential default" }, replacement_id: "pgm_office" }]);
});

test("Programs findings on the Export tab open this tab", function () {
  var p = load();
  assert.strictEqual(p.panel.tabFor(PREFIX + ".export_preflight").tab, "programs");
});

test("Reset is offered on PH-Composer's own default only; a set point may be below zero", function () {
  var p = load();
  var reset = shown(p).querySelectorAll(".phc-action-menu-item").filter(function (node) {
    return node.textContent === "Reset to PH-Composer default"; })[0];
  assert.strictEqual(reset.hidden, false);
  click(shown(p).querySelectorAll(".library-sidebar-row-button")[1]);
  assert.strictEqual(shown(p).querySelector(".pgm-title").textContent, "Office");
  assert.strictEqual(reset.hidden, true);
  click(card(p, "setpoint").querySelector(".pgm-card-head"));
  var heating = labelled(card(p, "setpoint"), "input", "Setpoint heating");
  type(heating, "-5");
  enter(heating);
  assert.deepStrictEqual(plain([last(p).params.id, last(p).params.values.setpoint.heating_c]), ["pgm_office", -5]);
});
