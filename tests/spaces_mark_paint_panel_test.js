"use strict";

/* The Weighting factor column's paint: the menu's icons start the Mark floor tool, the header's pressed glyph,
   Escape and a view switch stop it, and the tool's state comes from the snapshot. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");

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
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.section = function () { return context.document.querySelector("[data-section='ph_composer.overview']"); };
  p.pane = function () { return p.section().closest("[data-pane]"); };
  p.receive = function (state) { p.panel.receive({ type: "panel.snapshot", payload: state }); };
  p.byLabel = function (label) {
    return p.pane().querySelectorAll("button, input").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  };
  p.click = function (node) { node.listeners.click({ preventDefault: function () {} }); };
  p.commands = function () {
    return sent.filter(function (message) { return message.type === "view.invoke"; })
      .map(function (message) { return [message.payload.name, JSON.parse(JSON.stringify(message.payload.params))]; });
  };
  return p;
}

function snapshot(tool) {
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: fixture.section() },
      "ph_composer.spaces.mark_tool": { status: "completed",
        value: tool || { active: false, weighting_factor: 1, gesture_limit: 250 } },
      "ph_composer.zones.faces.palette": { status: "completed", value: { active: false, palette: {},
        face_types: ["Wall"], boundary_conditions: ["Outdoors"] } },
      "ph_composer.zones.faces.faces": { status: "completed", value: { units: { area_m2: "m2" }, faces: [] } }
    }
  };
}

function openMenu(p) {
  var menu = p.byLabel("Weighting factor column menu");
  p.click(menu);
  return menu;
}

test("the menu offers a paint icon for 0, 1 and each factor in use, stating the iCFA rule", function () {
  var state = snapshot();
  state.sections["ph_composer.spaces.spaces"].value.spaces[0].volumes[0].floor_segments[0].weighting_band = "0.6";
  var p = page();
  p.receive(state);
  var menu = openMenu(p);
  var icons = menu.parentNode.querySelectorAll("button").filter(function (node) {
    return /^Mark floor at weighting factor/.test(node.getAttribute("aria-label") || "");
  });
  assert.strictEqual(icons.length, 3, "0, 0.6 and 1");
  var labels = icons.map(function (node) { return node.getAttribute("aria-label"); });
  assert.ok(labels.some(function (text) { return text.indexOf("weighting factor 0.6.") > 0; }), "the value in use");
  assert.ok(labels.some(function (text) { return text.indexOf("weighting factor 0.") > 0; }), "0 is always offered");
  assert.ok(labels.some(function (text) { return text.indexOf("weighting factor 1.") > 0; }), "1 is always offered");
  assert.ok(labels.every(function (text) { return /guidebook 4\.4\.1\.4/.test(text); }), "each states the rule");
});

test("choosing a factor starts the tool with it and closes the menu", function () {
  var p = page();
  p.receive(snapshot());
  var menu = openMenu(p);
  var one = menu.parentNode.querySelectorAll("button").filter(function (node) {
    return /^Mark floor at weighting factor 1\./.test(node.getAttribute("aria-label") || "");
  })[0];
  assert.strictEqual(menu.getAttribute("aria-expanded"), "true", "the menu is open");
  p.click(one);
  assert.deepStrictEqual(p.commands(), [["ph_composer.spaces.mark_tool.start", { weighting_factor: 1 }]]);
  assert.strictEqual(menu.getAttribute("aria-expanded"), "false", "the menu closed");
});

test("while the tool runs the header shows a pressed glyph that stops it", function () {
  var p = page();
  p.receive(snapshot({ active: true, weighting_factor: 0.5, gesture_limit: 250 }));
  var glyph = p.byLabel("Mark floor at Weighting factor 0.5. Click to stop marking");
  assert.ok(glyph && !glyph.hidden);
  assert.strictEqual(glyph.getAttribute("aria-pressed"), "true");
  p.click(glyph);
  assert.deepStrictEqual(p.commands(), [["ph_composer.spaces.mark_tool.stop", {}]]);
  p.receive(snapshot());
  assert.strictEqual(glyph.hidden, true, "a stopped tool releases the glyph");
});

test("Escape and a switch to another view each stop a running tool", function () {
  var p = page();
  p.receive(snapshot({ active: true, weighting_factor: 1, gesture_limit: 250 }));
  dom.dispatch(p.context.document.body, { type: "keydown", key: "Escape" });
  assert.deepStrictEqual(p.commands(), [["ph_composer.spaces.mark_tool.stop", {}]]);
  var q = page();
  q.receive(snapshot({ active: true, weighting_factor: 1, gesture_limit: 250 }));
  q.click(q.pane().querySelectorAll("button").filter(function (node) { return node.textContent === "Geometry"; })[0]);
  assert.deepStrictEqual(q.commands(), [["ph_composer.spaces.mark_tool.stop", {}]]);
});

test("a start that lands after a switch to another view is stopped", function () {
  var p = page();
  p.receive(snapshot());
  var menu = openMenu(p);
  p.click(menu.parentNode.querySelectorAll("button").filter(function (node) {
    return /^Mark floor at weighting factor 1\./.test(node.getAttribute("aria-label") || "");
  })[0]);
  p.click(p.pane().querySelectorAll("button").filter(function (node) { return node.textContent === "Geometry"; })[0]);
  p.receive(snapshot({ active: true, weighting_factor: 1, gesture_limit: 250 }));
  assert.deepStrictEqual(p.commands(), [["ph_composer.spaces.mark_tool.start", { weighting_factor: 1 }],
    ["ph_composer.spaces.mark_tool.stop", {}]]);
});

test("the running factor's icon is pressed whatever text the host gave its band", function () {
  var state = snapshot({ active: true, weighting_factor: 0.0000001, gesture_limit: 250 });
  state.sections["ph_composer.spaces.spaces"].value.spaces[0].volumes[0].floor_segments[0].weighting_band = "1.0e-07";
  var p = page();
  p.receive(state);
  var menu = openMenu(p);
  var pressed = menu.parentNode.querySelectorAll("button").filter(function (node) {
    return /^Mark floor at weighting factor/.test(node.getAttribute("aria-label") || "") &&
      node.getAttribute("aria-pressed") === "true";
  });
  assert.strictEqual(pressed.length, 1);
});

function iconFor(menu, factor) {
  return menu.parentNode.querySelectorAll("button").filter(function (node) {
    return (node.getAttribute("aria-label") || "").indexOf("Mark floor at weighting factor " + factor + ".") === 0;
  })[0];
}

test("Escape before a start lands cancels it: the tool is stopped once it starts", function () {
  var p = page();
  p.receive(snapshot());
  p.click(iconFor(openMenu(p), 1));
  dom.dispatch(p.context.document.body, { type: "keydown", key: "Escape" });
  p.receive(snapshot({ active: true, weighting_factor: 1, gesture_limit: 250 }));
  assert.deepStrictEqual(p.commands(), [["ph_composer.spaces.mark_tool.start", { weighting_factor: 1 }],
    ["ph_composer.spaces.mark_tool.stop", {}]]);
});

test("leaving the Zones tab stops a running tool, and a start that lands there", function () {
  var p = page();
  p.receive(snapshot({ active: true, weighting_factor: 1, gesture_limit: 250 }));
  p.panel.showTab("assemblies");
  assert.deepStrictEqual(p.commands(), [["ph_composer.spaces.mark_tool.stop", {}]], "on the switch itself");
  p.receive(snapshot({ active: true, weighting_factor: 1, gesture_limit: 250 }));
  assert.deepStrictEqual(p.commands(), [["ph_composer.spaces.mark_tool.stop", {}]], "and only once");
});

test("a menu reopened while a start is in flight still offers every factor", function () {
  var p = page();
  p.receive(snapshot());
  p.click(iconFor(openMenu(p), 1));
  var zero = iconFor(openMenu(p), 0);
  assert.strictEqual(zero.disabled, false);
  p.click(zero);
  assert.deepStrictEqual(p.commands().map(function (command) { return command[1].weighting_factor; }), [1, 0]);
});
