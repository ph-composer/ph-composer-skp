"use strict";

/* The Phius certification section of the Building Segment settings dialog (context/EXTENSIBILITY.md, "Building
   Segment settings"; html/features/certification/section.js): it lists after General with its five choices, a
   Segment with no settings shows the defaults and one with settings shows them, an untouched section sends
   nothing, a change sends all five in the dialog's one Save request, and a value the section does not offer
   holds Save. Its values and defaults are Ruby's, written to tests/fixtures/segments/certification_choices.json
   by tests/segment_certification_test.rb. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");
var root = require("./support/panel_files").root;

var NAMESPACE = "ph_composer.certification.segment";
var CHOICES = JSON.parse(fs.readFileSync(path.join(root, "tests/fixtures/segments/certification_choices.json"),
  "utf8"));
var LABELS = ["Building category", "Certification program", "Building use", "Building status", "Building type"];
var STORED = { category: "non_residential", program: "phius_2018_zero", use: "school", status: "complete",
  type: "retrofit" };

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
    "features/certification/section"]);
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  return p;
}

/* House holds Zone A and has no settings; Annex holds Zone B and has certification settings. */
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
            usage: { live: 1, recoverable: 0 }, extension_data: { "ph_composer.certification.segment": envelope } }],
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

function choices(dialog) {
  return LABELS.map(function (label) {
    return dialog.querySelectorAll("select").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  });
}

function saveButton(dialog) {
  return dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Save"; })[0];
}

function click(node) { node.listeners.click({ preventDefault: function () {} }); }

/* A value from the panel's context, as one of this realm's, so deepStrictEqual compares its contents. */
function plain(value) { return JSON.parse(JSON.stringify(value)); }

test("the section offers Ruby's values in its order and shows the defaults on a Segment with none", function () {
  var p = load();
  var spec = p.modules["features/certification/section"];
  assert.deepStrictEqual(plain(spec.FIELDS.map(function (field) { return field.key; })),
    ["category", "program", "use", "status", "type"]);
  spec.FIELDS.forEach(function (field) {
    assert.deepStrictEqual(plain(field.values.map(function (pair) { return pair[0]; })), CHOICES.choices[field.key],
      field.key);
  });
  assert.deepStrictEqual(plain(spec.DEFAULTS), CHOICES.defaults);

  var dialog = settings(p, "House");
  assert.deepStrictEqual(plain(dialog.querySelectorAll("h3").map(function (node) { return node.textContent; })),
    ["General", "Phius certification"]);
  assert.deepStrictEqual(choices(dialog).map(function (select) { return select.value; }),
    ["residential", "phius_2021_core", "residential", "in_planning", "new_construction"]);
  var name = dialog.querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Name";
  })[0];
  name.value = "Main house"; name.listeners.input({});
  click(saveButton(dialog));
  assert.deepStrictEqual(plain(p.actions()[0].payload.params.extension_payloads), {},
    "an untouched section sends nothing");
});

test("a change sends all five values in the dialog's one Save request", function () {
  var p = load();
  var dialog = settings(p, "Annex"), selects = choices(dialog);
  assert.deepStrictEqual(selects.map(function (select) { return select.value; }),
    ["non_residential", "phius_2018_zero", "school", "complete", "retrofit"], "the stored values");
  selects[1].value = "phius_2021_zero"; selects[1].listeners.change({});

  click(saveButton(dialog));

  var sent = p.actions();
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].payload.name, "ph_composer.zones.save_segment_settings");
  assert.deepStrictEqual(plain(sent[0].payload.params.extension_payloads), { "ph_composer.certification.segment": {
    category: "non_residential", program: "phius_2021_zero", use: "school", status: "complete", type: "retrofit" } });
});

test("a value the section does not offer holds Save with the field named", function () {
  var p = load();
  var spec = p.panel.segmentSettingsSections().filter(function (item) { return item.namespace === NAMESPACE; })[0];
  assert.strictEqual(spec.order, 30, "after Occupancy, before Airtightness");
  var draft = Object.assign({}, STORED, { use: "hotel" });
  assert.deepStrictEqual(plain(spec.validate(draft)), ["Choose a building use."]);
  assert.deepStrictEqual(plain(spec.validate(STORED)), []);
  assert.deepStrictEqual(plain(spec.collect(Object.assign({ extra: 1 }, STORED))), STORED);
});

test("a stored value the section does not offer is kept, shows no choice and holds Save", function () {
  var p = load();
  var options = snapshot();
  var annex = options.sections["ph_composer.zones.options"].value.building_segments[1];
  annex.extension_data[NAMESPACE].payload = Object.assign({}, STORED, { use: "hotel" });
  p.panel.receive({ type: "panel.snapshot", payload: options });
  var dialog = settings(p, "Annex"), selects = choices(dialog);
  selects[0].value = "residential"; selects[0].listeners.change({});
  assert.strictEqual(saveButton(dialog).disabled, true, "the unknown use is not replaced unseen");
  assert.match(dialog.querySelector(".phc-form-status").textContent, /Phius certification: Choose a building use\./);
  selects[2].value = "other"; selects[2].listeners.change({});
  assert.strictEqual(saveButton(dialog).disabled, false);
});

test("a stored payload that is not an object opens the dialog with a notice and sends nothing for it", function () {
  var p = load();
  var options = snapshot();
  options.sections["ph_composer.zones.options"].value.building_segments[1].extension_data[NAMESPACE].payload =
    "unreadable";
  p.panel.receive({ type: "panel.snapshot", payload: options });
  var dialog = settings(p, "Annex");
  assert.strictEqual(choices(dialog)[0], undefined, "no choice to edit");
  assert.ok(dialog.querySelectorAll("span").some(function (node) {
    return /These settings cannot be read/.test(node.textContent);
  }), "the section says why");
  var name = dialog.querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Name";
  })[0];
  name.value = "East annex"; name.listeners.input({});
  click(saveButton(dialog));
  assert.deepStrictEqual(plain(p.actions()[0].payload.params.extension_payloads), {});
});
