"use strict";

/* The Spaces view's editable cells: one update per cell commit with the value it was read
   with, a refusal that keeps the draft, a range fill and a paste as one batch_update, the factor range, the
   airflow clear marker, and a unit switch that keeps drafts. */

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
  p.input = function (label) {
    return p.section().querySelectorAll("input").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  };
  p.receive = function (state) { p.panel.receive({ type: "panel.snapshot", payload: state }); };
  p.result = function (index, outcome) {
    p.panel.receive({ type: "action.result", payload: { request_id: p.sent[index].payload.request_id,
      session: "session-a", outcome: outcome } });
  };
  return p;
}

function snapshot(change) {
  var state = {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: fixture.section() }
    }
  };
  if (change) change(state.sections["ph_composer.spaces.spaces"].value);
  return state;
}

function enter(input, text) {
  input.value = text;
  input.listeners.input({});
  input.listeners.keydown({ key: "Enter", preventDefault: function () {}, stopImmediatePropagation: function () {} });
}

function expandAll(p) {
  fixture.expandAll(p.section());
}

function payloads(p, name) {
  return p.sent.filter(function (message) { return message.payload.name === name; })
    .map(function (message) { return JSON.parse(JSON.stringify(message.payload.params)); });
}

test("a cell commit sends one update with the value it was read with", function () {
  var p = page();
  p.receive(snapshot());
  enter(p.input("Living name"), "Lounge");
  assert.deepStrictEqual(payloads(p, "ph_composer.spaces.update"), [{
    reference: { space_id: "spc_101", entity_path: [100, 101] },
    values: { name: "Lounge" }, expected_values: { name: "Living" } }]);
});

test("a refusal keeps the draft and says why", function () {
  var p = page();
  p.receive(snapshot());
  var name = p.input("Living name");
  enter(name, "Lounge");
  p.result(0, { status: "refused", code: "target.changed", effect: "none",
    message: "The Space changed after it was read. Nothing was written." });
  assert.strictEqual(name.value, "Lounge");
  assert.match(name.parentNode.querySelector(".cell-error").textContent, /Nothing was written\./);
});

test("the weighting factor refuses 1.2 and -0.1 at the cell and sends 0.6", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  var factor = p.section().querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Segment 1 weighting factor";
  })[0];
  enter(factor, "1.2");
  enter(factor, "-0.1");
  assert.strictEqual(payloads(p, "ph_composer.spaces.update").length, 0);
  enter(factor, "0.6");
  var sent = payloads(p, "ph_composer.spaces.update");
  assert.strictEqual(sent.length, 1);
  assert.deepStrictEqual(sent[0].values, { weighting_factor: 0.6 });
  assert.deepStrictEqual(sent[0].expected_values, { weighting_factor: 1 });
});

test("a typed 0 is a value and a cleared rate sends the clear marker, not 0", function () {
  var p = page();
  p.receive(snapshot());
  var extract = p.input("Living extract");
  assert.strictEqual(extract.value, "", "unset");
  assert.strictEqual(extract.placeholder, "0", "beside a set supply it reads as a muted 0");
  enter(extract, "0");
  assert.deepStrictEqual(payloads(p, "ph_composer.spaces.update")[0],
    { reference: { space_id: "spc_101", entity_path: [100, 101] }, values: { v_eta_m3h: 0 }, expected_values: {} });
  p.result(0, { status: "completed", effect: "committed", value: { ids: ["spc_101"] } });
  enter(p.input("Living supply"), "");
  assert.deepStrictEqual(payloads(p, "ph_composer.spaces.update")[1].values, { v_sup_m3h: null });
  assert.deepStrictEqual(payloads(p, "ph_composer.spaces.update")[1].expected_values, { v_sup_m3h: 60 });
});

test("the three airflow states: all unset, supply only, three explicit zeros", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    section.spaces[2].values.v_sup_m3h = 0; section.spaces[2].values.v_eta_m3h = 0;
    section.spaces[2].values.v_tran_m3h = 0;
  }));
  function shown(label) { var input = p.input(label); return [input.value, input.placeholder]; }
  assert.deepStrictEqual(shown("Loft supply"), ["", "Zone"], "all unset inherits");
  assert.deepStrictEqual(shown("Living supply"), ["60", "0"]);
  assert.deepStrictEqual(shown("Living transfer"), ["", "0"], "supply only: the others a muted 0");
  assert.deepStrictEqual(shown("Hall supply"), ["0", "0"], "an explicit zero is a value");
});

test("a range fill sends one batch_update, one edit per record", function () {
  var p = page();
  p.receive(snapshot());
  var first = p.input("Living supply"), second = p.input("Bath supply"), third = p.input("Hall supply");
  first.listeners.mousedown({ shiftKey: false });
  third.listeners.mousedown({ shiftKey: true });
  p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Fill selected cells down";
  })[0].listeners.click({ preventDefault: function () {} });
  assert.ok(second, "the middle cell is in the range");
  assert.deepStrictEqual(payloads(p, "ph_composer.spaces.update"), []);
  assert.deepStrictEqual(payloads(p, "ph_composer.spaces.batch_update"), [{ edits: [
    { reference: { space_id: "spc_102", entity_path: [100, 102] }, values: { v_sup_m3h: 60 }, expected_values: {} },
    { reference: { space_id: "spc_103", entity_path: [100, 103] }, values: { v_sup_m3h: 60 }, expected_values: {} }
  ] }]);
});

test("a paste of values and blanks sends sets and clears in one batch_update", function () {
  var p = page();
  p.receive(snapshot());
  p.input("Living supply").listeners.mousedown({ shiftKey: false });
  var mount = p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0]
    .querySelector(".phc-table-mount");
  mount.listeners.paste({ preventDefault: function () {},
    clipboardData: { getData: function () { return "50\t\t5\n\t30\t\n\t\t"; } } });
  assert.deepStrictEqual(payloads(p, "ph_composer.spaces.batch_update"), [{ edits: [
    { reference: { space_id: "spc_101", entity_path: [100, 101] }, values: { v_sup_m3h: 50, v_tran_m3h: 5 },
      expected_values: { v_sup_m3h: 60 } },
    { reference: { space_id: "spc_102", entity_path: [100, 102] }, values: { v_eta_m3h: 30 },
      expected_values: { v_eta_m3h: 40 } },
    { reference: { space_id: "spc_103", entity_path: [100, 103] }, values: { v_tran_m3h: null },
      expected_values: { v_tran_m3h: 20 } }
  ] }], "a blank over a set rate clears it; a blank over an unset rate changes nothing");
});

test("a unit switch reformats the cells and keeps a draft as typed", function () {
  var p = page();
  p.receive(snapshot());
  var bath = p.input("Bath extract");
  bath.value = "45"; bath.listeners.input({});
  var ip = snapshot();
  ip.preferences.unit_system = "IP";
  p.receive(ip);
  assert.strictEqual(p.input("Living supply").value, "35.3", "60 m³/h reads in cfm");
  assert.strictEqual(p.input("Bath extract").value, "45", "the draft keeps what was typed");
  assert.deepStrictEqual(p.sent.filter(function (message) { return message.type !== "preferences.set"; }), []);
});

/* ---------------------------------------------------------------- review (PR #151) */

function chevron(p, label) {
  return p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === label;
  })[0];
}

test("cells a row chevron reveals join the range at once", function () {
  var p = page();
  p.receive(snapshot());
  chevron(p, "Expand Space Living").listeners.click({ preventDefault: function () {} });
  var height = p.input("Volume 1 height");
  assert.ok(height, "the Volume's height is shown");
  height.listeners.mousedown({ shiftKey: false });
  var tools = p.section().querySelectorAll(".phc-grid-tool-group")[0];
  height.listeners.focus({});
  assert.ok(height.parentNode.classList.contains("inventory-selected"), "the grid knows the revealed cell");
  assert.ok(tools);
});

test("a Volume's or a Floor Segment's name may be cleared", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  enter(p.section().querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Volume 1 name";
  })[0], "");
  var sent = payloads(p, "ph_composer.spaces.update");
  assert.strictEqual(sent.length, 1);
  assert.deepStrictEqual(sent[0].values, { display_name: "" });
});

test("a refused draft has a visible Cancel, and the guard notice offers it too", function () {
  var p = page();
  p.receive(snapshot());
  var name = p.input("Living name");
  enter(name, "Lounge");
  p.result(0, { status: "refused", code: "target.changed", effect: "none", message: "Changed. Nothing was written." });
  var cancel = p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Cancel Living name edit";
  })[0];
  assert.ok(cancel && !cancel.hidden, "a visible Cancel");
  p.panel.showTab("export");
  var notice = p.panel.state.ui.notice;
  assert.ok(notice.action, "the notice offers a way out");
  notice.action.run();
  assert.strictEqual(name.value, "Living");
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "export");
});

test("a row holding a draft beneath it does not collapse", function () {
  var p = page();
  p.receive(snapshot());
  var name = p.input("Living name");
  enter(name, "Lounge");
  p.result(0, { status: "refused", code: "target.changed", effect: "none", message: "Changed. Nothing was written." });
  chevron(p, "Collapse Zone A").listeners.click({ preventDefault: function () {} });
  assert.ok(p.input("Living name"), "the draft stays in view");
  assert.match(p.panel.state.ui.notice.message, /Finish or cancel/);
});

/* ---------------------------------------------------------------- review (PR #151), cycle 2 */

test("a snapshot that removes a Space under a draft says so once and keeps painting", function () {
  var p = page(), errors = [];
  p.context.console = { error: function (text) { errors.push(text); } };
  p.receive(snapshot());
  var name = p.input("Living name");
  name.value = "Lounge"; name.listeners.input({});
  p.receive(snapshot(function (section) { section.spaces.splice(0, 1); }));
  assert.deepStrictEqual(errors, []);
  assert.ok(p.input("Bath name"), "the table still paints");
});

test("an edit already sent is waited for, not offered for cancellation", function () {
  var p = page();
  p.receive(snapshot());
  enter(p.input("Living name"), "Lounge");
  p.panel.showTab("export");
  var notice = p.panel.state.ui.notice;
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  assert.ok(!notice.action, "nothing to cancel while the edit is in flight: " + notice.message);
});

