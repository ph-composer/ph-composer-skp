"use strict";

/* The Occupancy section of the Building Segment settings dialog and the Segment heading contribution
   (html/features/programs/occupancy.js): a Segment with no settings is a single dwelling with the house's rows, a
   non-residential certification draft disables the switch with its reason, switching on names what gives way and
   enters the summed bedrooms from Ruby's preview, and every heading shows the tag and the Segment's findings. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");

var NAMESPACE = "ph_composer.programs.segment";
var STORED = { single_dwelling: false, default_program_id: "pgm_office", bedrooms: null, occupants: null,
  equipment_set_id: null };
var PREVIEW = { building_segment_id: "bsg_annex", programs: [{ zone_id: "zon_b", program_id: "pgm_office" }],
  dwelling_ids: ["dwl_one", "dwl_two"], equipment_set_ids: [], bedrooms: 3, occupants: null };

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
    "features/certification/section", "features/programs/occupancy"]);
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  return p;
}

/* House holds Zone A and has no settings: a single dwelling by default. Annex holds Zone B, switched off, its
   Zone in an Office Program and one of two Dwellings. */
function snapshot() {
  var zones = fixture.zones();
  [["Zone A", "bsg_house"], ["Zone B", "bsg_annex"]].forEach(function (pair, index) {
    zones[index].schema_version = 3;
    zones[index].values = { name: pair[0], building_segment_id: pair[1], level_id: null, ground_depth_mm: 0 };
  });
  var envelope = { schema_version: 1, payload: STORED, references: [], export_relevance: "local_only" };
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
            usage: { live: 1, recoverable: 0 }, extension_data: { "ph_composer.programs.segment": envelope } }],
        levels: [], default_segment_id: "bsg_house",
        adoption: { required: false, sources: [], suggested_segment: "Building Segment" } } },
      "ph_composer.programs.occupancy": { status: "completed", value: occupancy() }
    }
  };
}

function occupancy() {
  var house = { id: "bsg_house", name: "House", category: "residential",
    settings: { single_dwelling: true, default_program_id: null, bedrooms: null, occupants: null,
      equipment_set_id: null }, stored: false, single_dwelling: true,
    dwelling: { name: "House", units: 1, bedrooms: null, occupants: null, occupants_rule: false,
      equipment_set_id: null }, dwelling_count: 1, set_points: { heating_c: 20, cooling_c: 25, agree: true },
    single_dwelling_preview: { building_segment_id: "bsg_house", programs: [], dwelling_ids: [],
      equipment_set_ids: [], bedrooms: null, occupants: null }, findings: [] };
  var annex = { id: "bsg_annex", name: "Annex", category: "residential", settings: STORED, stored: true,
    single_dwelling: false, dwelling: null, dwelling_count: 2, set_points: { heating_c: 20, cooling_c: 25,
      agree: true }, single_dwelling_preview: PREVIEW,
    findings: [{ code: "programs.residential_without_dwelling", severity: "warning",
      message: "Annex is residential and has no Dwelling." }] };
  return { zones: [], building_segments: [house, annex], choices: {
    programs: [{ id: "pgm_PHCDEFAULT01", name: "Residential default" }, { id: "pgm_office", name: "Office" }],
    equipment_sets: [{ id: "eqs_PHCDEFAULT01", name: "Residential default devices" }],
    default_program_id: "pgm_PHCDEFAULT01", default_equipment_set_id: "eqs_PHCDEFAULT01" } };
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


function sectionNode(dialog) {
  return dialog.querySelectorAll("div").filter(function (node) {
    return node.getAttribute("data-namespace") === NAMESPACE;
  })[0];
}

test("a Segment with no settings reads as a single dwelling with the house's rows", function () {
  var p = load();
  var dialog = settings(p, "House");
  assert.deepStrictEqual(plain(dialog.querySelectorAll("h3").map(function (node) { return node.textContent; })),
    ["General", "Occupancy", "Phius certification"]);
  var box = control(dialog, "input", "Single dwelling");
  assert.strictEqual(box.checked, true);
  assert.strictEqual(box.disabled, false);
  assert.strictEqual(control(dialog, "select", "Default Program for its Zones").disabled, true,
    "Single dwelling uses the residential default");
  assert.strictEqual(control(dialog, "input", "Bedrooms").placeholder, "?");
  assert.strictEqual(control(dialog, "input", "Occupants").placeholder, "Phius rule");
  control(dialog, "input", "Bedrooms").value = "3";
  control(dialog, "input", "Bedrooms").listeners.input({});
  click(saveButton(dialog));
  assert.deepStrictEqual(plain(p.actions()[0].payload.params.extension_payloads), { "ph_composer.programs.segment": {
    single_dwelling: true, default_program_id: null, bedrooms: 3, occupants: null, equipment_set_id: null } });
});

test("a non-residential category disables Single dwelling with the reason, and follows the draft", function () {
  var p = load();
  var dialog = settings(p, "House");
  var category = control(dialog, "select", "Building category");
  category.value = "non_residential"; category.listeners.change({});
  var box = control(dialog, "input", "Single dwelling");
  assert.strictEqual(box.disabled, true);
  assert.ok(/Residential Building Segments only/.test(shownText(sectionNode(dialog))));
  assert.strictEqual(control(dialog, "input", "Bedrooms"), undefined, "the house rows go with it");
  category.value = "residential"; category.listeners.change({});
  assert.strictEqual(control(dialog, "input", "Single dwelling").disabled, false);
});

test("switching on names what gives way and enters the Zones' summed bedrooms", function () {
  var p = load();
  var dialog = settings(p, "Annex");
  var box = control(dialog, "input", "Single dwelling");
  assert.strictEqual(box.checked, false);
  assert.strictEqual(control(dialog, "select", "Default Program for its Zones").value, "pgm_office");
  box.checked = true; box.listeners.change({});
  assert.strictEqual(control(dialog, "input", "Bedrooms").value, "3");
  assert.ok(/Saving replaces 1 Zone Program, 2 Dwellings with the house/.test(shownText(sectionNode(dialog))));
  click(saveButton(dialog));
  assert.deepStrictEqual(plain(p.actions()[0].payload.params.extension_payloads[NAMESPACE]),
    { single_dwelling: true, default_program_id: "pgm_office", bedrooms: 3, occupants: null,
      equipment_set_id: null });
});

test("an unreadable count holds Save with the reason", function () {
  var p = load();
  var spec = p.panel.segmentSettingsSections().filter(function (item) { return item.namespace === NAMESPACE; })[0];
  assert.strictEqual(spec.order, 20, "before Phius certification");
  assert.deepStrictEqual(plain(spec.validate({ bedrooms: "two", occupants: "" })),
    ["Enter the bedrooms as a number of at least 0."]);
  assert.deepStrictEqual(plain(spec.validate({ bedrooms: "2", occupants: "-1" })),
    ["Enter the occupants as a number of at least 0, or leave them empty for the Phius rule."]);
  var dialog = settings(p, "House");
  control(dialog, "input", "Bedrooms").value = "x";
  control(dialog, "input", "Bedrooms").listeners.input({});
  assert.strictEqual(saveButton(dialog).disabled, true);
});

test("the heading carries the Single dwelling tag and the Segment's findings", function () {
  var p = load();
  var house = heading(p, "House"), annex = heading(p, "Annex");
  assert.ok(house.querySelectorAll(".phc-segment-tag").some(function (tag) {
    return tag.textContent === "Single dwelling";
  }));
  assert.strictEqual(annex.querySelector(".phc-segment-flag").hidden, false);
  assert.ok(/no Dwelling/.test(annex.querySelector(".phc-segment-flag").getAttribute("aria-label")));
});

test("typing a count keeps its field, and the note follows the stored setting, not the read", function () {
  var p = load();
  var dialog = settings(p, "House");
  var bedrooms = control(dialog, "input", "Bedrooms");
  bedrooms.value = "1"; bedrooms.listeners.input({});
  bedrooms.value = "12"; bedrooms.listeners.input({});
  assert.strictEqual(control(dialog, "input", "Bedrooms"), bedrooms, "no repaint while typing");
  var box = control(dialog, "input", "Single dwelling");
  box.checked = false; box.listeners.change({});
  box.checked = true; box.listeners.change({});
  assert.ok(!/Saving replaces/.test(shownText(sectionNode(dialog))), "stored on: switching back replaces nothing");
});
