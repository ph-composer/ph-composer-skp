"use strict";

/* The Spaces view's checked rows and selection bar, and checked Zones shared with the Faces view. */

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
    return p.pane().querySelectorAll("input, button, select").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  };
  p.click = function (node) { node.listeners.click({ preventDefault: function () {} }); };
  return p;
}

function snapshot(view) {
  var section = fixture.section();
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": view || "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: section },
      "ph_composer.zones.faces.palette": { status: "completed", value: { active: false, palette: {},
        face_types: ["Wall"], boundary_conditions: ["Outdoors"] } },
      "ph_composer.zones.faces.faces": { status: "completed", value: { units: { area_m2: "m2" }, faces: [
        { reference: { zone_id: "zon_a", zone_path: [100], entity_path: [150], entity_id: "fac_a" },
          zone_name: "Zone A", area_m2: 10, state: "classified",
          values: { face_type: "Wall", boundary_condition: "Outdoors" }, suggested: {} },
        { reference: { zone_id: "zon_b", zone_path: [200], entity_path: [250], entity_id: "fac_b" },
          zone_name: "Zone B", area_m2: 10, state: "classified",
          values: { face_type: "Wall", boundary_condition: "Outdoors" }, suggested: {} }] } }
    }
  };
}

function expandAll(p) {
  p.section().querySelectorAll("button").filter(function (node) { return node.textContent === "Expand all"; })[0]
    .listeners.click({ preventDefault: function () {} });
}

function bar(p) {
  return p.section().querySelectorAll(".phc-selection-bar").filter(function (node) { return !node.hidden; })[0];
}

function batches(p) {
  return p.sent.filter(function (message) { return message.payload.name === "ph_composer.spaces.batch_update"; })
    .map(function (message) { return JSON.parse(JSON.stringify(message.payload.params)); });
}

/* Typing then Enter: typing begins the draft. */
function enter(input, text) {
  if (input.value !== text) { input.value = text; input.listeners.input({}); }
  input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
}

test("two checked Floor Segments take one factor from the bar in one batch_update", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  var boxes = p.pane().querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Check Segment 1";
  });
  p.click(boxes[0]); p.click(boxes[1]);
  assert.strictEqual(bar(p).querySelector(".phc-selection-bar-count").textContent, "2 Floor Segments checked");
  var factor = p.byLabel("Weighting factor for checked Floor Segments");
  assert.strictEqual(factor.value, "1", "the value both share");
  enter(factor, "0.6");
  assert.deepStrictEqual(batches(p), [{ edits: [
    { reference: { floor_segment_id: "sfs_100_101_1_1", entity_path: [100, 101, 1, 1] },
      values: { weighting_factor: 0.6 }, expected_values: { weighting_factor: 1 } },
    { reference: { floor_segment_id: "sfs_100_102_1_1", entity_path: [100, 102, 1, 1] },
      values: { weighting_factor: 0.6 }, expected_values: { weighting_factor: 1 } }] }]);
});

test("a Space's box checks it and everything beneath; values they do not share read Mixed", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Hall"));
  assert.strictEqual(bar(p).querySelector(".phc-selection-bar-count").textContent,
    "1 Space, 2 Volumes, 2 Floor Segments checked");
  var factor = p.byLabel("Weighting factor for checked Floor Segments");
  assert.deepStrictEqual([factor.value, factor.placeholder], ["", "Mixed"]);
  var height = p.byLabel("Height for checked Volumes");
  assert.deepStrictEqual([height.value, height.placeholder], ["", "Mixed"]);
  assert.strictEqual(p.byLabel("Transfer for checked Spaces").value, "20");
  var supply = p.byLabel("Supply for checked Spaces");
  assert.deepStrictEqual([supply.value, supply.placeholder], ["", ""], "one Space with no supply is not Mixed");
  enter(p.byLabel("Weighting factor for checked Floor Segments"), "1.2");
  assert.strictEqual(batches(p).length, 0, "a factor out of range refuses at the bar");
});

test("a blank airflow in the bar clears the rate on each checked Space that has one", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  p.click(p.byLabel("Check Bath"));
  var supply = p.byLabel("Supply for checked Spaces");
  supply.value = "5"; supply.listeners.input({});
  enter(supply, "");
  assert.deepStrictEqual(batches(p), [{ edits: [
    { reference: { space_id: "spc_101", entity_path: [100, 101] }, values: { v_sup_m3h: null },
      expected_values: { v_sup_m3h: 60 } },
    { reference: { space_id: "spc_102", entity_path: [100, 102] }, values: { v_sup_m3h: null },
      expected_values: {} }] }], "Bath has no supply to clear, and goes so the host checks it is still unset");
});

test("a Zone's box checks every row in it and reads mixed while only some are; Escape clears", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  var zone = p.byLabel("Check Zone A");
  assert.strictEqual(zone.indeterminate, true);
  p.click(zone);
  assert.strictEqual(p.byLabel("Uncheck Zone A").checked, true);
  dom.dispatch(p.context.document.body, { type: "keydown", key: "Escape" });
  assert.strictEqual(p.byLabel("Check Zone A").checked, false);
});

test("Zones checked in one view read checked in the other after a switch", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Zone B"));
  p.click(p.pane().querySelectorAll("button").filter(function (node) { return node.textContent === "Geometry"; })[0]);
  assert.strictEqual(p.byLabel("Uncheck Zone B").checked, true, "Zone B's Faces are checked in Faces");
  p.click(p.byLabel("Uncheck Zone B"));
  p.click(p.byLabel("Check Zone A"));
  p.click(p.pane().querySelectorAll("button").filter(function (node) { return node.textContent === "Spaces"; })[0]);
  assert.strictEqual(p.byLabel("Uncheck Zone A").checked, true, "and Zone A's Spaces in Spaces");
  assert.strictEqual(p.byLabel("Check Zone B").checked, false, "Zone B was handed over only as Faces checked it");
});

/* ---------------------------------------------------------------- review (PR #153) */

function type(input, text) {
  input.value = text;
  input.listeners.input({});
}

function result(p, message, outcome) {
  p.panel.receive({ type: "action.result", payload: { request_id: message.payload.request_id, session: "session-a",
    outcome: outcome } });
}

test("a bar draft keeps the unit it was typed in through a unit switch", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  var height = p.byLabel("Height for checked Volumes");
  type(height, "3");
  var ip = snapshot();
  ip.preferences.unit_system = "IP";
  p.receive(ip);
  enter(height, height.value);
  assert.strictEqual(batches(p)[0].edits[0].values.avg_ceiling_height_m, 3, "metres, as typed");
});

test("a bar draft is guarded by the values it began against, not later ones", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  var supply = p.byLabel("Supply for checked Spaces");
  type(supply, "70");
  var changed = snapshot();
  changed.sections["ph_composer.spaces.spaces"].value.spaces[0].values.v_sup_m3h = 80;
  p.receive(changed);
  enter(supply, "70");
  assert.deepStrictEqual(batches(p)[0].edits[0].expected_values, { v_sup_m3h: 60 });
});

test("Enter on a field the user has not edited sends nothing", function () {
  var p = page(), ip = snapshot();
  ip.preferences.unit_system = "IP";
  p.receive(ip);
  p.click(p.byLabel("Check Living"));
  var supply = p.byLabel("Supply for checked Spaces");
  supply.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.strictEqual(batches(p).length, 0);
});

test("a refused bar entry keeps its text and holds a view switch until it is cancelled", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  var supply = p.byLabel("Supply for checked Spaces");
  type(supply, "70");
  enter(supply, "70");
  var sent = p.sent.filter(function (message) { return message.payload.name === "ph_composer.spaces.batch_update"; });
  result(p, sent[0], { status: "refused", code: "target.changed", effect: "none",
    message: "Changed. Nothing was written." });
  p.receive(snapshot());
  assert.strictEqual(supply.value, "70", "the refused text stays");
  p.click(p.pane().querySelectorAll("button").filter(function (node) { return node.textContent === "Geometry"; })[0]);
  assert.strictEqual(p.pane().querySelectorAll("button").filter(function (node) {
    return node.textContent === "Spaces";
  })[0].getAttribute("aria-selected"), "true", "the switch is held");
  supply.listeners.keydown({ key: "Escape", preventDefault: function () {} });
  assert.strictEqual(supply.value, "60", "Escape restores the Model's value");
});

test("checked Zones go with an automatic switch too", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Zone B"));
  var faceless = snapshot();
  delete faceless.sections["ph_composer.spaces.spaces"];
  p.receive(faceless);
  assert.strictEqual(p.byLabel("Uncheck Zone B").checked, true, "Faces took Zone B");
});

/* ---------------------------------------------------------------- review (PR #153), cycle 2 */

test("the checked set holds still while a bar draft is open", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  type(p.byLabel("Supply for checked Spaces"), "70");
  p.click(p.byLabel("Uncheck Living"));
  assert.ok(p.byLabel("Uncheck Living"), "Living stays checked");
  assert.match(p.panel.state.ui.notice.message, /selection bar/);
});

test("correcting a refused entry keeps the unit it was first typed in", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  var height = p.byLabel("Height for checked Volumes");
  enter(height, "3");
  var sent = p.sent.filter(function (message) { return message.payload.name === "ph_composer.spaces.batch_update"; });
  result(p, sent[0], { status: "refused", code: "target.changed", effect: "none", message: "Changed." });
  var ip = snapshot();
  ip.preferences.unit_system = "IP";
  p.receive(ip);
  enter(height, "3.1");
  assert.strictEqual(batches(p)[1].edits[0].values.avg_ceiling_height_m, 3.1);
});

test("every checked row's value is checked by the host, unchanged ones included", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  p.click(p.byLabel("Check Bath"));
  enter(p.byLabel("Height for checked Volumes"), "2.5");
  assert.deepStrictEqual(batches(p)[0].edits.map(function (edit) { return edit.expected_values; }),
    [{ avg_ceiling_height_m: 2.5 }, { avg_ceiling_height_m: 2.4 }]);
});

test("Enter on an untouched Mixed airflow clears it", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  p.click(p.byLabel("Check Bath"));
  p.byLabel("Supply for checked Spaces").listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.strictEqual(batches(p).length, 1);
});

test("a held bar draft shows a visible Cancel that restores the Model's value", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.byLabel("Check Living"));
  var supply = p.byLabel("Supply for checked Spaces");
  enter(supply, "abc");
  var cancel = p.byLabel("Cancel the change");
  assert.ok(cancel && !cancel.hidden);
  p.click(cancel);
  assert.strictEqual(supply.value, "60");
});

test("an automatic switch hands checked Zones to a view that first appears in that snapshot", function () {
  var p = page(), only = snapshot();
  delete only.sections["ph_composer.zones.faces.faces"];
  p.receive(only);
  p.click(p.byLabel("Check Zone B"));
  var faces = snapshot();
  delete faces.sections["ph_composer.spaces.spaces"];
  p.receive(faces);
  assert.strictEqual(p.byLabel("Uncheck Zone B").checked, true);
});
