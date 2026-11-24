"use strict";

/* The Mechanical section of the Building Segment settings dialog (context/EXTENSIBILITY.md, "Building Segment
   settings"; html/features/mechanical/segment_settings.js): it lists after the other sections with mechanical
   cooling, the mechanical room temperature in the unit preference's unit and the four summer ventilation values; a
   Segment with no settings shows the defaults and one with settings shows them; a change sends all six in the
   dialog's one Save request, the temperature in °C; and a value it cannot read holds Save. Its values and defaults
   are Ruby's, written to tests/fixtures/segments/mechanical_choices.json by tests/segment_mechanical_test.rb. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");
var root = require("./support/panel_files").root;

var NAMESPACE = "ph_composer.mechanical.segment";
var CHOICES = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/segments/mechanical_choices.json"), "utf8"));
var STORED = { mechanical_cooling: true, mech_room_temp_c: 18.5, summer_bypass_mode: "temperature_controlled",
  ventilation_system_ach: 0.3, daytime_window_ach: 0.5, nighttime_window_ach: 1.2 };

function load(system, decimal) {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view",
    "features/mechanical/segment_settings"]);
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(system || "SI", decimal) });
  return p;
}

/* House holds Zone A and has no settings; Annex holds Zone B and has mechanical settings. */
function snapshot(system, decimal) {
  var zones = fixture.zones();
  [["Zone A", "bsg_house"], ["Zone B", "bsg_annex"]].forEach(function (pair, index) {
    zones[index].schema_version = 3;
    zones[index].values = { name: pair[0], building_segment_id: pair[1], level_id: null, ground_depth_mm: 0 };
  });
  var envelope = { schema_version: 1, payload: STORED, references: [], export_relevance: "required" };
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: system, dimension_formats: {}, number_format: { decimal: decimal || ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.zones.faces" } },
    sections: {
      "ph_composer.zones.faces.palette": { status: "completed", value: { active: false, palette: {},
        face_types: ["Wall"], boundary_conditions: ["Outdoors"] } },
      "ph_composer.zones.overview": { status: "completed", value: { zones: zones, make_zone: null, units: {},
        building_segments: [{ key: "bsg_house", zone_count: 1, face_area_m2: 0, unclassified_face_area_m2: 0 },
          { key: "bsg_annex", zone_count: 1, face_area_m2: 0, unclassified_face_area_m2: 0 }] } },
      "ph_composer.zones.faces.faces": { status: "completed", value: { units: { area_m2: "m2" }, faces: [] } },
      "ph_composer.zones.options": { status: "completed", value: {
        building_segments: [
          { id: "bsg_house", values: { name: "House", colour: "#1F7478", export_identifier: "bseg_house" },
            usage: { live: 1, recoverable: 0 }, extension_data: {} },
          { id: "bsg_annex", values: { name: "Annex", colour: "#5588BB", export_identifier: "bseg_annex" },
            usage: { live: 1, recoverable: 0 }, extension_data: { "ph_composer.mechanical.segment": envelope } }],
        levels: [], default_segment_id: "bsg_house",
        adoption: { required: false, sources: [], suggested_segment: "Building Segment" } } }
    }
  };
}

function section(p) {
  return p.context.document.querySelector("[data-section='ph_composer.overview']");
}

function heading(p, name) {
  return section(p).querySelectorAll("tr").filter(function (tr) {
    var label = tr.getAttribute("data-heading-key") && tr.querySelector(".phc-segment-name");
    return label && label.textContent === name && !tr.closest("[hidden]");
  })[0];
}

function settings(p, name) {
  click(heading(p, name).querySelector("[data-row-action='settings']"));
  return p.context.document.querySelectorAll("dialog").filter(function (node) {
    return node.className.indexOf("phc-segment-settings-dialog") >= 0 && !node.hidden;
  })[0];
}

function control(dialog, tag, label) {
  return dialog.querySelectorAll(tag).filter(function (node) { return node.getAttribute("aria-label") === label; })[0];
}

function fields(dialog) {
  return { cooling: control(dialog, "input", "Mechanical cooling"),
    room: control(dialog, "input", "Mechanical room temperature"), bypass: control(dialog, "select", "Summer bypass"),
    system: control(dialog, "input", "Ventilation system air changes"),
    day: control(dialog, "input", "Windows, daytime air changes"),
    night: control(dialog, "input", "Windows, nighttime air changes") };
}

/* Every span and paragraph's own text, joined: what the section shows beside its controls. */
function shownText(dialog) {
  return dialog.querySelectorAll("span").concat(dialog.querySelectorAll("p")).map(function (node) {
    return node.textContent;
  }).join(" | ");
}

function saveButton(dialog) {
  return dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Save"; })[0];
}

function click(node) { node.listeners.click({ preventDefault: function () {} }); }

/* A value from the panel's context, as one of this realm's, so deepStrictEqual compares its contents. */
function plain(value) { return JSON.parse(JSON.stringify(value)); }

function spec(p) {
  return p.panel.segmentSettingsSections().filter(function (item) { return item.namespace === NAMESPACE; })[0];
}

test("the section offers Ruby's values after Comfort and shows the defaults on a Segment with none", function () {
  var p = load();
  var module = p.modules["features/mechanical/segment_settings"];
  assert.deepStrictEqual(plain(module.BYPASS_MODES.map(function (pair) { return pair[0]; })), CHOICES.bypass_modes);
  assert.deepStrictEqual(plain(module.DEFAULTS), CHOICES.defaults);
  assert.strictEqual(spec(p).order, 60, "after Comfort, which is 50");

  var dialog = settings(p, "House"), shown = fields(dialog);
  assert.deepStrictEqual(plain(dialog.querySelectorAll("h3").map(function (node) { return node.textContent; })),
    ["General", "Mechanical"]);
  assert.deepStrictEqual([shown.cooling.checked, shown.room.value, shown.bypass.value, shown.system.value,
    shown.day.value, shown.night.value], [false, "20", "always", "", "0", "0"]);
  assert.ok(shownText(dialog).indexOf("°C") >= 0, "the room temperature shows its unit");
  assert.ok(shownText(dialog).indexOf("1/h") >= 0, "the air changes show theirs");
  assert.ok(/Summer ventilation\./.test(shownText(dialog)), "the bypass and air changes sit under Summer ventilation");
  var name = control(dialog, "input", "Name");
  name.value = "Main house"; name.listeners.input({});
  click(saveButton(dialog));
  assert.deepStrictEqual(plain(p.actions()[0].payload.params.extension_payloads), {},
    "an untouched section sends nothing");
});

test("a change sends the six values in the dialog's one Save request, the room temperature in C", function () {
  var p = load("IP");
  var dialog = settings(p, "Annex"), shown = fields(dialog);
  assert.deepStrictEqual([shown.cooling.checked, shown.room.value, shown.bypass.value, shown.system.value],
    [true, "65.3", "temperature_controlled", "0.3"], "the stored values, the temperature in °F");
  assert.ok(shownText(dialog).indexOf("°F") >= 0);
  shown.cooling.checked = false; shown.cooling.listeners.change({});
  shown.room.value = "68"; shown.room.listeners.input({});
  shown.system.value = " "; shown.system.listeners.input({});
  shown.night.value = "2"; shown.night.listeners.input({});

  click(saveButton(dialog));

  var sent = p.actions();
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].payload.name, "ph_composer.zones.save_segment_settings");
  var payload = plain(sent[0].payload.params.extension_payloads)[NAMESPACE];
  assert.ok(Math.abs(payload.mech_room_temp_c - 20) < 1e-9, payload.mech_room_temp_c);
  delete payload.mech_room_temp_c;
  assert.deepStrictEqual(payload, { mechanical_cooling: false, summer_bypass_mode: "temperature_controlled",
    ventilation_system_ach: null, daytime_window_ach: 0.5, nighttime_window_ach: 2 });
});

test("a blank or unreadable value holds Save with the reason", function () {
  var p = load();
  var section = spec(p);
  assert.deepStrictEqual(plain(section.validate(STORED)), []);
  assert.deepStrictEqual(plain(section.validate(Object.assign({}, STORED, { ventilation_system_ach: null }))), [],
    "the ventilation system may be blank");
  assert.deepStrictEqual(plain(section.validate(Object.assign({}, STORED, { daytime_window_ach: null }))),
    ["Enter the windows, daytime air changes as a number of at least 0."]);
  ["-1", "two", "1,5"].forEach(function (text) {
    assert.strictEqual(section.validate(Object.assign({}, STORED, { nighttime_window_ach: text })).length, 1, text);
  });
  assert.deepStrictEqual(plain(section.validate(Object.assign({}, STORED, { mech_room_temp_c: "warm" }))),
    ["Enter the mechanical room temperature."]);
  assert.deepStrictEqual(plain(section.validate(Object.assign({}, STORED, { summer_bypass_mode: "sometimes" }))),
    ["Choose a summer bypass."]);

  var dialog = settings(p, "Annex"), shown = fields(dialog);
  shown.day.value = "-0.5"; shown.day.listeners.input({});
  assert.strictEqual(saveButton(dialog).disabled, true);
  assert.match(dialog.querySelector(".phc-form-status").textContent, /Mechanical: Enter the windows, daytime/);
  shown.day.value = "0"; shown.day.listeners.input({});
  assert.strictEqual(saveButton(dialog).disabled, false);
});

test("a typed value keeps the unit it was typed in when the preferences change before Save", function () {
  var p = load("IP");
  var dialog = settings(p, "Annex"), shown = fields(dialog);
  shown.room.value = "68"; shown.room.listeners.input({});
  p.panel.receive({ type: "panel.snapshot", payload: snapshot("SI") });
  click(saveButton(dialog));
  var payload = plain(p.actions()[0].payload.params.extension_payloads)[NAMESPACE];
  assert.ok(Math.abs(payload.mech_room_temp_c - 20) < 1e-9, "68 °F, not 68 °C: " + payload.mech_room_temp_c);
});

test("the air changes are shown and read in the number format's decimal", function () {
  var p = load("SI", ",");
  var dialog = settings(p, "Annex"), shown = fields(dialog);
  assert.deepStrictEqual([shown.system.value, shown.day.value, shown.night.value], ["0,3", "0,5", "1,2"]);
  shown.day.value = "0,75"; shown.day.listeners.input({});
  shown.system.value = ""; shown.system.listeners.input({});
  assert.strictEqual(saveButton(dialog).disabled, false);
  click(saveButton(dialog));
  var payload = plain(p.actions()[0].payload.params.extension_payloads)[NAMESPACE];
  assert.deepStrictEqual([payload.ventilation_system_ach, payload.daytime_window_ach, payload.nighttime_window_ach],
    [null, 0.75, 1.2]);
});

test("text the number reader cannot read, a line separator included, holds Save until corrected", function () {
  var p = load();
  var dialog = settings(p, "Annex"), shown = fields(dialog);
  shown.day.value = "0\u20285"; shown.day.listeners.input({});
  assert.strictEqual(saveButton(dialog).disabled, true);
  shown.cooling.checked = false; shown.cooling.listeners.change({});
  assert.strictEqual(saveButton(dialog).disabled, true, "another edit does not release the stale rate");
  shown.day.value = "0.25"; shown.day.listeners.input({});
  click(saveButton(dialog));
  assert.strictEqual(plain(p.actions()[0].payload.params.extension_payloads)[NAMESPACE].daytime_window_ach, 0.25);
});
