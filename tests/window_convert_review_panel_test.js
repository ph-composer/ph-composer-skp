"use strict";

/* Convert to Window Type's review in the panel: what the menus handed over opens in the shared dialog, Convert
   sends `units.convert` with each group's choices at the review's revision, Cancel sends nothing, a refusal stays
   in the dialog, and the review is closed by its own token. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

function source(path) { return { path: [100, path], row_span: [0, 0], column_span: [0, 0], digest: "sha256:" + path,
  outline_m: [] }; }

function group(path, index, matches) {
  return { host: { zone_id: "zon_AAAAAAAAAAAA", zone_path: [100], entity_path: [101], entity_id: null },
    columns_m: [1.2], rows_m: [1.5], layout_index: index, matching_types: matches || [],
    preselected_type_id: matches && matches.length ? matches[0].id : null, default_name: "Window 1200 x 1500",
    sources: [source(path)] };
}

function review() {
  return { token: "review-1", revision: 5, groups: [group(901, 0), group(902, 0), group(903, 2,
    [{ id: "wnt_B", name: "Same size" }])],
  left_out: [{ paths: [[100, 906]], code: "window.not_rectangle", message: "Not a rectangle." },
    { paths: [[100, 907], [100, 908]], code: "window.mull_not_rectangular", message: "Does not tile." }] };
}

function element(id, kind) {
  return { id: id, kind: kind, name: "Element", row_span: [0, 0], column_span: [0, 0], glazing_id: null,
    frames: {}, installs: {}, operation: null };
}

function type(id, name, kind) {
  return { id: id, values: { name: name, rows_m: [1], columns_m: [1], elements: [element("wel_" + id, kind)] },
    display: { thermal: { elements: [], findings: [] } } };
}

function snapshot(dialog) {
  return { product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 6, file_name: "house.skp",
    preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" },
      table_views: {} },
    sections: {
      "ph_composer.windows.types": { status: "completed", value: { records: [type("wnt_B", "Same size", "glazed"),
        type("wnt_A", "A source", "glazed"), type("wnt_C", "All empty", "empty")] } },
      "ph_composer.windows.frames": { status: "completed", value: { records: [] } },
      "ph_composer.windows.glazings": { status: "completed", value: { records: [] } },
      "ph_composer.windows.psi_install_types": { status: "completed", value: { records: [] } },
      "ph_composer.windows.convert_dialog": { status: "completed", value: dialog || { token: null, revision: null,
        groups: [], left_out: [] } }
    }, };
}

function page() {
  var sent = [], errors = [];
  var context = { document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl, innerWidth: 1280,
    innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } } };
  context.console = { error: function () { errors.push(Array.prototype.slice.call(arguments).join(" ")); },
    warn: function () {}, log: function () {} };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/windows/section"]);
  var p = { context: context, panel: modules.panel, sent: sent, errors: errors };
  p.receive = function (state) { p.panel.receive({ type: "panel.snapshot", payload: state }); };
  p.dialog = function () {
    return context.document.querySelectorAll("dialog").filter(function (node) {
      return /phc-convert-window/.test(node.className);
    })[0];
  };
  p.button = function (text) {
    return p.dialog().querySelectorAll("button").filter(function (node) { return node.textContent === text; })[0];
  };
  p.controls = function (tag, label) {
    return p.dialog().querySelectorAll(tag).filter(function (node) {
      return node.getAttribute("aria-label") === label;
    });
  };
  p.text = function () {
    return p.dialog().querySelectorAll("h2, p, li, div").map(function (node) { return node.textContent; }).join("\n");
  };
  p.click = function (node) { node.listeners.click({ preventDefault: function () {} }); };
  p.messages = function (type) { return sent.filter(function (message) { return message.type === type; }); };
  p.result = function (message, outcome) {
    p.panel.receive({ type: message.type === "view.invoke" ? "view.result" : "action.result",
      payload: { request_id: message.payload.request_id, session: "session-a", outcome: outcome } });
  };
  return p;
}

test("a review opens on the Windows tab, one row per size, saying why each other Face is left out", function () {
  var p = page();
  p.receive(snapshot(review()));
  assert.strictEqual(p.panel.state.ui.activeTab, "windows");
  var text = p.text();
  assert.match(text, /3 rectangles become 3 Windows\./);
  assert.match(text, /1 Face: Not a rectangle\./);
  assert.match(text, /2 Faces: Does not tile\./);
  assert.strictEqual(p.controls("select", "Window Type").length, 2, "one choice per size");
  var names = p.controls("input", "Name");
  assert.strictEqual(names[0].value, "Window 1200 x 1500");
  assert.ok(names[1].parentNode.hidden, "a preselected existing Type takes no name");
  assert.deepStrictEqual(p.errors, []);
});

test("Copy from lists the Types with a glazed element, by name, and defaults to None", function () {
  var p = page();
  p.receive(snapshot(review()));
  var copy = p.controls("select", "Copy from")[0];
  assert.strictEqual(copy.value, "");
  assert.deepStrictEqual(copy.children.map(function (node) { return node.textContent; }),
    ["None", "A source", "Same size"]);
});

test("Convert sends each group's choice at the review's revision and closes by its token", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.controls("input", "Name")[0].value = "W-1";
  p.controls("select", "Copy from")[0].value = "wnt_A";
  p.click(p.button("Convert"));
  var invoke = p.messages("action.invoke")[0];
  assert.strictEqual(invoke.payload.name, "ph_composer.windows.units.convert");
  assert.strictEqual(invoke.payload.expected_revision, 5);
  assert.deepStrictEqual(invoke.payload.params.groups.map(function (row) {
    return [row.sources[0].path[1], row.name, row.copy_from_type_id, row.type_id];
  }), [[901, "W-1", "wnt_A", undefined], [902, "W-1", "wnt_A", undefined], [903, undefined, undefined, "wnt_B"]]);
  p.result(invoke, { status: "completed", value: { created_type_ids: ["wnt_A"], units: [] }, message: "Done." });
  assert.strictEqual(p.dialog().open, false);
  var close = p.messages("view.invoke").filter(function (message) {
    return message.payload.name === "ph_composer.windows.convert_dialog.close";
  })[0];
  assert.strictEqual(close.payload.params.token, "review-1");
});

test("Cancel sends no action, and a refusal stays in the dialog", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.click(p.button("Convert"));
  p.result(p.messages("action.invoke")[0], { status: "refused", code: "target.changed", message: "Review it again." });
  assert.match(p.text(), /Review it again\./);
  assert.ok(!p.dialog().hidden);
  p.click(p.button("Cancel"));
  assert.strictEqual(p.messages("action.invoke").length, 1);
  assert.ok(p.messages("view.invoke").some(function (message) {
    return message.payload.name === "ph_composer.windows.convert_dialog.close";
  }));
});

test("with nothing convertible the review says so and Convert is disabled", function () {
  var p = page();
  p.receive(snapshot({ token: "review-2", revision: 5, groups: [], left_out: [{ paths: [[100, 906]], code: "x",
    message: "Not a rectangle." }] }));
  assert.match(p.text(), /None of the selected Faces can become a Window\./);
  assert.strictEqual(p.button("Convert").disabled, true);
});

test("a newer review replaces the open one, and only the Types every group can take are offered", function () {
  var p = page();
  p.receive(snapshot(review()));
  var newer = review();
  newer.token = "review-2";
  newer.groups = [group(910, 0, [{ id: "wnt_B", name: "Same size" }, { id: "wnt_A", name: "A source" }]),
    group(911, 0, [{ id: "wnt_B", name: "Same size" }])];
  p.receive(snapshot(newer));
  var choice = p.controls("select", "Window Type")[0];
  assert.strictEqual(choice.value, "wnt_B");
  assert.deepStrictEqual(choice.children.map(function (node) { return node.textContent; }),
    ["New Window Type", "Same size"]);
});

test("while a review is open the screen holds, and Convert lands on the Type it made", function () {
  var p = page();
  p.receive(snapshot(review()));
  var view = p.context.document.querySelector("[data-section='windows']")._view;
  assert.strictEqual(view.guard(), "Finish the Convert to Window Type review first.");
  p.click(p.button("Convert"));
  p.result(p.messages("action.invoke")[0], { status: "completed", message: "Done.",
    value: { created_type_ids: ["wnt_A"], units: [{ type_id: "wnt_A" }] } });
  assert.strictEqual(view.active, "wnt_A");
  assert.strictEqual(view.guard(), null);
});

test("Escape's close control cancels without an action", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.click(p.dialog().closeButton);
  assert.strictEqual(p.dialog().open, false);
  assert.strictEqual(p.messages("action.invoke").length, 0);
});

test("a review closed elsewhere closes its dialog without a close command", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.receive(snapshot(null));
  assert.strictEqual(p.dialog().open, false);
  assert.strictEqual(p.messages("view.invoke").filter(function (message) {
    return message.payload.name === "ph_composer.windows.convert_dialog.close";
  }).length, 0);
});
