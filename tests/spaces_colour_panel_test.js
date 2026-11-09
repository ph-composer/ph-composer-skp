"use strict";

/* The Spaces view's Colour by: the Name, airflow, Weighting factor and Height headers offer the Spaces modes,
   and Table options lists the Spaces readouts and, while Show Spaces is on, their lines. Every control is a
   view command. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");

var MODES = [["by_space", "Space", null], ["by_ventilation", "Ventilation", "ventilation"],
  ["by_weighting_factor", "Weighting factor", null], ["by_height", "Height", null]].map(function (mode) {
  return { name: "ph_composer.spaces." + mode[0], label: mode[1], entity_kind: "volume", group: mode[2] };
});

function page() {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view",
    "features/spaces/view"]);
  var p = { context: context, panel: modules.panel, sent: sent };
  p.pane = function () {
    return context.document.querySelector("[data-section='ph_composer.overview']").closest("[data-pane]");
  };
  p.receive = function (state) { p.panel.receive({ type: "panel.snapshot", payload: state }); };
  p.byLabel = function (label) {
    return p.pane().querySelectorAll("button").filter(function (node) {
      return node.getAttribute("aria-label") === label || node.textContent === label;
    });
  };
  p.click = function (node) { node.listeners.click({ preventDefault: function () {} }); };
  p.views = function () {
    return sent.filter(function (message) { return message.type === "view.invoke"; })
      .map(function (message) { return [message.payload.name, JSON.parse(JSON.stringify(message.payload.params))]; });
  };
  return p;
}

function snapshot(readouts, options) {
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: fixture.section() },
      "ph_composer.colour_by.legend": { status: "completed", value: { mode: null, modes: MODES, rows: [],
        filter_paths: null, readouts: readouts || [
          { name: "ph_composer.spaces.show", label: "Show Spaces", selection: false, on: false },
          { name: "ph_composer.spaces.selection_totals", label: "Spaces selection totals", selection: true,
            on: false }] } },
      "ph_composer.spaces.label_options": { status: "completed", value: options || { weighted_area: false,
        net_volume: false, airflows: false } }
    }
  };
}

function openOptions(p) {
  p.click(p.byLabel("Table options")[0]);
  return p.pane().querySelectorAll(".phc-action-menu-item").filter(function (node) { return !node.hidden; });
}

function item(items, text) { return items.filter(function (node) { return node.textContent === text; })[0]; }

test("the Name, airflow, Weighting factor and Height headers offer the Spaces modes", function () {
  var p = page();
  p.receive(snapshot());
  ["Colour by Space", "Colour by Weighting factor", "Colour by Height"].forEach(function (label) {
    assert.strictEqual(p.byLabel(label).length, 1, label);
  });
  assert.strictEqual(p.byLabel("Colour by Ventilation").length, 3, "Supply, Extract and Transfer");
  p.click(p.byLabel("Colour by Height")[0]);
  assert.deepStrictEqual(p.views().pop(), ["ph_composer.colour_by.activate", { mode: "ph_composer.spaces.by_height" }]);
});

test("Table options turns each Spaces readout on", function () {
  var p = page();
  p.receive(snapshot());
  var items = openOptions(p);
  assert.strictEqual(item(items, "Show Spaces").getAttribute("aria-pressed"), "false");
  assert.ok(item(items, "Selection totals"));
  assert.strictEqual(item(items, "Label net volume"), undefined, "no label lines while the labels are off");
  p.click(item(items, "Show Spaces"));
  assert.deepStrictEqual(p.views().pop(), ["ph_composer.colour_by.readout",
    { readout: "ph_composer.spaces.show", on: true }]);
});

test("while Show Spaces is on, Table options lists each line and toggles it", function () {
  var p = page();
  p.receive(snapshot([{ name: "ph_composer.spaces.show", label: "Show Spaces", selection: false, on: true }],
    { weighted_area: true, net_volume: false, airflows: false }));
  var items = openOptions(p);
  assert.strictEqual(item(items, "Label weighted area (iCFA)").getAttribute("aria-pressed"), "true");
  p.click(item(items, "Label net volume"));
  assert.deepStrictEqual(p.views().pop(), ["ph_composer.spaces.labels.set_options", { net_volume: true }]);
});
