"use strict";

/* The Spaces view's per-Zone airflow mode (context/UBIQUITOUS_LANGUAGE.md, "By Program", "Detailed airflows"):
   From Program on a detailed Zone row, the notice when an edit switches a Zone to detailed, the amber "No
   Spaces" row, and the Transfer column's header help. */

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
  var p = { context: context, panel: modules.panel, sent: sent };
  p.section = function () { return context.document.querySelector("[data-section='ph_composer.overview']"); };
  p.receive = function (state) { p.panel.receive({ type: "panel.snapshot", payload: state }); };
  p.action = function (label) {
    return p.section().querySelectorAll("[data-row-action]").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  };
  p.input = function (label) {
    return p.section().querySelectorAll("input").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  };
  p.click = function (node) { node.listeners.click({ preventDefault: function () {} }); };
  p.result = function (message, outcome) {
    p.panel.receive({ type: "action.result",
      payload: { request_id: message.payload.request_id, session: "session-a", outcome: outcome } });
  };
  return p;
}

function snapshot(options, revision) {
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: revision || 4,
    file_name: "house.skp", edit_path: [], preferences: { unit_system: "SI", dimension_formats: {},
      number_format: { decimal: ".", locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: fixture.section(options) }
    }
  };
}

function enter(input, text) {
  input.value = text;
  input.listeners.input({});
  input.listeners.keydown({ key: "Enter", preventDefault: function () {}, stopImmediatePropagation: function () {} });
}

function button(dialog, label) {
  return dialog.querySelectorAll("button").filter(function (node) { return node.textContent === label; })[0];
}

function notice(p) { return p.panel.state.ui.notice; }

test("From Program is offered on a detailed Zone row only, confirms what goes and clears the Zone", function () {
  var p = page();
  p.receive(snapshot());
  assert.ok(!p.action("From Program: clear every Space's airflows in Zone B"), "Zone B is By Program");
  p.click(p.action("From Program: clear every Space's airflows in Zone A"));
  var dialog = p.context.document.querySelector("dialog");
  assert.strictEqual(dialog.querySelector("h2").textContent, "Use Program airflows?");
  assert.match(dialog.querySelector("p").textContent, /^The supply, extract and transfer rates of 3 Spaces in Zone A/);
  p.click(button(dialog, "Cancel"));
  assert.strictEqual(p.sent.length, 0, "Cancel sends nothing");
  p.click(p.action("From Program: clear every Space's airflows in Zone A"));
  p.click(button(dialog, "Clear airflows"));
  var sent = p.sent[p.sent.length - 1].payload;
  assert.strictEqual(sent.name, "ph_composer.spaces.clear_zone_airflows");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(sent.params)), { zones: [{ zone_id: "zon_a", zone_path: [100] }] });
});

test("a rate typed in a By Program Zone switches it to detailed and the notice says so", function () {
  var p = page();
  p.receive(snapshot());
  enter(p.input("Loft supply"), "30");
  var update = p.sent.filter(function (message) { return message.payload.name === "ph_composer.spaces.update"; })[0];
  assert.ok(update, "the edit is sent");
  p.receive(snapshot({ loft: { v_sup_m3h: 30 } }, 5));
  assert.strictEqual(notice(p).message, "Zone B now uses detailed airflows.");
  assert.strictEqual(notice(p).tone, "info");
  p.result(update, { status: "completed", effect: "committed", value: { ids: ["spc_201"] } });
});

test("the notice names how many other Spaces in the Zone now export 0", function () {
  var p = page();
  p.receive(snapshot({ stair: true }));
  enter(p.input("Loft supply"), "30");
  p.receive(snapshot({ stair: true, loft: { v_sup_m3h: 30 } }, 5));
  assert.strictEqual(notice(p).message,
    "Zone B now uses detailed airflows: its other Space exports 0 until you enter its rates.");
});

test("a Zone turning detailed with nothing of this view's in flight, as on Undo, raises no notice", function () {
  var p = page();
  p.receive(snapshot());
  p.receive(snapshot({ loft: { v_sup_m3h: 30 } }, 5));
  assert.ok(!notice(p) || !/detailed airflows/.test(notice(p).message));
});

test("a Zone with no Spaces shows an amber No Spaces row naming why", function () {
  var p = page();
  p.receive(snapshot({ noLoft: true }));
  var row = p.section().querySelectorAll("tr").filter(function (tr) {
    return (tr.getAttribute("data-row-key") || "").indexOf("[\"NoSpaces\"") === 0;
  })[0];
  assert.ok(row && !row.hidden, "the row shows under its open Zone");
  var name = row.querySelectorAll("td").filter(function (td) { return td.classList.contains("col-name"); })[0];
  assert.strictEqual(name.textContent, "No Spaces");
  assert.ok(name.classList.contains("is-flagged"));
  assert.match(name.getAttribute("data-tooltip"), /^No Spaces: this Zone exports its geometry/);
  assert.match(row.querySelector(".phc-row-marker").getAttribute("aria-label"), /no iCFA, net volume or ventilation/);
});

test("the Transfer header says it reaches PHPP only", function () {
  var p = page();
  p.receive(snapshot());
  var header = p.section().querySelectorAll(".col-v_tran_m3h").filter(function (node) {
    return node.tagName === "th";
  })[0];
  assert.strictEqual(header.querySelector(".phc-th-label").getAttribute("data-tooltip"),
    "Transfer air reaches PHPP only. WUFI-Passive and METr receive supply and extract.");
});
