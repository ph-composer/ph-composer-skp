"use strict";

/* The Airtightness section of the Building Segment settings dialog (context/EXTENSIBILITY.md, "Building Segment
   settings"; html/features/programs/airtightness.js): it lists after General with the test result, its unit and
   the wind exposure, a Segment with no settings shows the defaults and one with settings shows them, a change
   sends the three values in the dialog's one Save request with a blank result as null, and a result that is not
   a number greater than 0 holds Save. Its values and defaults are Ruby's, written to
   tests/fixtures/segments/airtightness_choices.json by tests/segment_airtightness_test.rb. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");
var root = require("./support/panel_files").root;

var NAMESPACE = "ph_composer.programs.airtightness";
var CHOICES = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/segments/airtightness_choices.json"),
  "utf8"));
var STORED = { basis: "q50", value: 0.6, wind_exposure: "one_side_high_screening" };

function load() {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view",
    "features/programs/airtightness"]);
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  return p;
}

/* House holds Zone A and has no settings; Annex holds Zone B and has airtightness settings. */
function snapshot() {
  var zones = fixture.zones();
  [["Zone A", "bsg_house"], ["Zone B", "bsg_annex"]].forEach(function (pair, index) {
    zones[index].schema_version = 3;
    zones[index].values = { name: pair[0], building_segment_id: pair[1], level_id: null, ground_depth_mm: 0 };
  });
  var envelope = { schema_version: 1, payload: STORED, references: [], export_relevance: "required" };
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
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
            usage: { live: 1, recoverable: 0 }, extension_data: { "ph_composer.programs.airtightness": envelope } }],
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
  return { basis: control(dialog, "select", "Test result basis"), value: control(dialog, "input", "Test result"),
    wind: control(dialog, "select", "Wind exposure") };
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

test("the section offers Ruby's values in its order and shows the defaults on a Segment with none", function () {
  var p = load();
  var spec = p.modules["features/programs/airtightness"];
  assert.deepStrictEqual(plain(spec.BASES.map(function (pair) { return pair[0]; })), CHOICES.bases);
  assert.deepStrictEqual(plain(spec.WIND_EXPOSURES.map(function (pair) { return pair[0]; })), CHOICES.wind_exposures);
  assert.deepStrictEqual(plain(spec.DEFAULTS), CHOICES.defaults);

  var dialog = settings(p, "House"), shown = fields(dialog);
  assert.deepStrictEqual(plain(dialog.querySelectorAll("h3").map(function (node) { return node.textContent; })),
    ["General", "Airtightness"]);
  assert.deepStrictEqual([shown.basis.value, shown.value.value, shown.wind.value],
    ["n50", "", "several_sides_no_screening"]);
  assert.ok(shownText(dialog).indexOf("1/h") >= 0, "n50 shows its unit");
  var line = shown.basis.parentNode;
  assert.strictEqual(line.className, "phc-airtightness-result", "the test result is one line of the row");
  assert.deepStrictEqual(line.children.map(function (node) { return node.className || node.tagName.toLowerCase(); }),
    ["select", "input", "phc-airtightness-unit"], "basis, value, then its unit");
  assert.ok(/replacing the Program's value/.test(shownText(dialog)), "the section says what export does");
  var name = control(dialog, "input", "Name");
  name.value = "Main house"; name.listeners.input({});
  click(saveButton(dialog));
  assert.deepStrictEqual(plain(p.actions()[0].payload.params.extension_payloads), {},
    "an untouched section sends nothing");
});

test("a change sends the three values in the dialog's one Save request, and a blank result as null", function () {
  var p = load();
  var dialog = settings(p, "Annex"), shown = fields(dialog);
  assert.deepStrictEqual([shown.basis.value, shown.value.value, shown.wind.value],
    ["q50", "0.6", "one_side_high_screening"], "the stored values");
  assert.ok(shownText(dialog).indexOf("m³/h·m²") >= 0, "q50 shows its unit");
  shown.basis.value = "n50"; shown.basis.listeners.change({});
  shown.value.value = " 1.5 "; shown.value.listeners.input({});
  assert.ok(shownText(dialog).indexOf("1/h") >= 0, "the unit follows the basis");

  click(saveButton(dialog));

  var sent = p.actions();
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].payload.name, "ph_composer.zones.save_segment_settings");
  assert.deepStrictEqual(plain(sent[0].payload.params.extension_payloads), { "ph_composer.programs.airtightness": {
    basis: "n50", value: 1.5, wind_exposure: "one_side_high_screening" } });

  var spec = p.panel.segmentSettingsSections().filter(function (item) { return item.namespace === NAMESPACE; })[0];
  assert.deepStrictEqual(plain(spec.collect(Object.assign({}, STORED, { value: "" }))),
    Object.assign({}, STORED, { value: null }));
});

test("a zero, negative or unreadable result holds Save with the reason", function () {
  var p = load();
  var spec = p.panel.segmentSettingsSections().filter(function (item) { return item.namespace === NAMESPACE; })[0];
  assert.strictEqual(spec.order, 40, "after Phius certification, before Comfort");
  ["0", "-1", "tight", "1,5", "0x10"].forEach(function (text) {
    assert.deepStrictEqual(plain(spec.validate(Object.assign({}, STORED, { value: text }))),
      ["Enter a test result greater than 0, or leave it blank."], text);
  });
  assert.deepStrictEqual(plain(spec.validate(Object.assign({}, STORED, { value: "" }))), []);
  assert.deepStrictEqual(plain(spec.validate(Object.assign({}, STORED, { wind_exposure: "sheltered" }))),
    ["Choose a wind exposure."]);

  var dialog = settings(p, "Annex"), shown = fields(dialog);
  shown.value.value = "0"; shown.value.listeners.input({});
  assert.strictEqual(saveButton(dialog).disabled, true);
  assert.match(dialog.querySelector(".phc-form-status").textContent, /Airtightness: Enter a test result greater/);
  shown.value.value = ""; shown.value.listeners.input({});
  assert.strictEqual(saveButton(dialog).disabled, false, "a blank result is no test result");
});
