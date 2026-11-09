"use strict";

/* Create Space's review in the panel: what the context menu handed over opens in the shared dialog, Create
   sends `create` with the accepted Faces at the review's revision, Cancel sends nothing, a refusal stays in
   the dialog, and the review is closed by its own token. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");

var ZONE = { zone_id: "zon_AAAAAAAAAAAA", zone_path: [100] };

var ZONES = [{ zone_id: ZONE.zone_id, zone_path: [100], name: "Living Zone" },
  { zone_id: "zon_BBBBBBBBBBBB", zone_path: [200], name: "Attic Zone" }];

function face(id) { return [100, id]; }

function page() {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  var errors = [];
  context.console = { error: function () { errors.push(Array.prototype.slice.call(arguments).join(" ")); },
    warn: function () {}, log: function () {} };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view",
    "features/spaces/view"]);
  var p = { context: context, panel: modules.panel, sent: sent, errors: errors };
  p.receive = function (state) { p.panel.receive({ type: "panel.snapshot", payload: state }); };
  p.dialog = function () {
    return context.document.querySelectorAll("dialog").filter(function (node) {
      return /phc-create-space/.test(node.className);
    })[0];
  };
  p.button = function (text) {
    return p.dialog().querySelectorAll("button").filter(function (node) { return node.textContent === text; })[0];
  };
  p.input = function (label) {
    return p.dialog().querySelectorAll("input").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  };
  // The DOM stub keeps each element's own text, so the dialog's text is gathered from its elements.
  p.text = function () {
    return p.dialog().querySelectorAll("h2, p, li, div").map(function (node) { return node.textContent; }).join("\n");
  };
  p.click = function (node) { node.listeners.click({ preventDefault: function () {} }); };
  p.type = function (input, text) {
    input.value = text;
    if (input.listeners.input) input.listeners.input({ target: input });
  };
  p.messages = function (type) { return sent.filter(function (message) { return message.type === type; }); };
  p.result = function (message, outcome) {
    p.panel.receive({ type: message.type === "view.invoke" ? "view.result" : "action.result",
      payload: { request_id: message.payload.request_id, session: "session-a", outcome: outcome } });
  };
  return p;
}

function snapshot(review) {
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 6, file_name: "house.skp",
    edit_path: [100], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: fixture.section() },
      "ph_composer.spaces.create_review": { status: "completed", value: review || { token: null, revision: null,
        zone: null, zones: [], accepted: [], left_out: [], height_m: null, height_source: null } }
    }
  };
}

function review(accepted) {
  return { token: "review-1", revision: 5, zone: ZONE, zones: ZONES, height_m: 2.5, height_source: "last_height",
    accepted: accepted === undefined ? [face(1200), face(1210)] : accepted,
    left_out: [{ path: face(1300), reason: "classified", message: "The Face is one of the Zone's own." },
      { path: face(1301), reason: "classified", message: "The Face is one of the Zone's own." },
      { path: face(1400), reason: "shares_edge", message: "The Face shares an Edge with an unselected Face." }] };
}

test("a review opens in the shared dialog, saying what is accepted and why each other Face is left out", function () {
  var p = page();
  p.receive(snapshot(review()));
  var dialog = p.dialog();
  assert.ok(dialog && !dialog.hidden);
  assert.strictEqual(dialog.querySelector("h2").textContent, "Create Space from floor outline");
  var text = p.text();
  assert.match(text, /A Space is a floor outline plus a height\. 2 Faces become one Space with one Volume/);
  assert.match(text, /Height 2\.5 m, the Model's last height\./);
  assert.match(text, /2 Faces: The Face is one of the Zone's own\./);
  assert.match(text, /1 Face: The Face shares an Edge/);
  assert.strictEqual(p.input("Number").getAttribute("placeholder"), "Next free");
});

test("one accepted Face becomes one Space, in the singular", function () {
  var p = page();
  p.receive(snapshot(review([face(1200)])));
  assert.match(p.text(), /1 Face becomes one Space with one Volume/);
});

test("Create sends create with the accepted Faces at the review's revision, and Enter does the same", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.type(p.input("Name"), " Living ");
  p.input("Name").listeners.keydown({ key: "Enter", preventDefault: function () {} });
  var sent = p.messages("action.invoke");
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].payload.name, "ph_composer.spaces.create");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(sent[0].payload.params)),
    { zone: ZONE, faces: [face(1200), face(1210)], name: "Living" });
  assert.strictEqual(sent[0].payload.expected_revision, 5);
});

test("the Zone picker opens preselected, and No Zone or another Zone is what Create sends", function () {
  var p = page();
  p.receive(snapshot(review()));
  var select = p.dialog().querySelector("select");
  assert.strictEqual(select.value, "0");
  select.value = "";
  p.click(p.button("Create"));
  assert.strictEqual(JSON.parse(JSON.stringify(p.messages("action.invoke")[0].payload.params)).zone, null);
});

test("a review with no Zone preselected opens on No Zone, and another Zone is what Create sends", function () {
  var p = page();
  p.receive(snapshot(Object.assign(review(), { zone: null })));
  var select = p.dialog().querySelector("select");
  assert.strictEqual(select.value, "");
  select.value = "1";
  p.click(p.button("Create"));
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.messages("action.invoke")[0].payload.params)).zone,
    { zone_id: "zon_BBBBBBBBBBBB", zone_path: [200] });
});

test("the height says it is the default until one is entered", function () {
  var p = page();
  p.receive(snapshot(Object.assign(review(), { height_source: "default" })));
  assert.match(p.text(), /Height 2\.5 m, the default height\./);
});

test("Create sends once while one is in flight", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.click(p.button("Create"));
  var sent = p.messages("action.invoke");
  assert.strictEqual(sent.length, 1);
  p.click(p.button("Create"));
  assert.strictEqual(p.messages("action.invoke").length, 1, "one create in flight");
});

test("a refused create stays in the dialog; a completed one closes it and the review by its token", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.type(p.input("Number"), "104");
  p.click(p.button("Create"));
  var create = p.messages("action.invoke")[0];
  assert.strictEqual(create.payload.params.number, "104");
  p.result(create, { status: "refused", code: "revision.stale", message: "The Model changed. Nothing was written." });
  assert.ok(!p.dialog().hidden);
  assert.match(p.text(), /The Model changed/);
  p.click(p.button("Create"));
  p.result(p.messages("action.invoke")[1], { status: "completed", message: "Created Space 104." });
  assert.ok(p.dialog().hidden);
  var close = p.messages("view.invoke").filter(function (message) {
    return message.payload.name === "ph_composer.spaces.create_review.close";
  });
  assert.deepStrictEqual(close.map(function (message) { return message.payload.params.token; }), ["review-1"]);
});

test("Cancel writes nothing and closes the review; with nothing accepted Create is unavailable", function () {
  var p = page();
  p.receive(snapshot(review([])));
  assert.match(p.text(), /None of the selected Faces can become one/);
  assert.strictEqual(p.button("Create").disabled, true);
  p.click(p.button("Cancel"));
  assert.ok(p.dialog().hidden);
  assert.strictEqual(p.messages("action.invoke").length, 0);
  assert.strictEqual(p.messages("view.invoke").filter(function (message) {
    return message.payload.name === "ph_composer.spaces.create_review.close";
  }).length, 1);
  p.receive(snapshot(review([])));
  assert.ok(p.dialog().hidden, "the same review does not reopen");
});

function closes(p) {
  return p.messages("view.invoke").filter(function (message) {
    return message.payload.name === "ph_composer.spaces.create_review.close";
  }).map(function (message) { return message.payload.params.token; });
}

test("a newer review waits for a submitted one, whose result closes only its own review", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.click(p.button("Create"));
  var newer = Object.assign(review([face(1200)]), { token: "review-2" });
  p.receive(snapshot(newer));
  assert.ok(!p.dialog().hidden, "the submitted review stays");
  assert.match(p.text(), /2 Faces become/);
  p.result(p.messages("action.invoke")[0], { status: "completed", message: "Created Space 104." });
  assert.deepStrictEqual(closes(p), ["review-1"]);
  p.receive(snapshot(newer));
  assert.ok(!p.dialog().hidden);
  assert.match(p.text(), /1 Face becomes/, "then the newer review opens");
});

test("a review closed elsewhere closes its dialog, and Create then sends nothing", function () {
  var p = page();
  p.receive(snapshot(review()));
  p.receive(snapshot());
  assert.ok(p.dialog().hidden);
  p.click(p.button("Create"));
  assert.strictEqual(p.messages("action.invoke").length, 0);
});

test("a review refused by a held tab is shown once the tab lets go", function () {
  var p = page();
  p.receive(snapshot());
  p.panel.showTab("assemblies");
  var holding = true;
  p.panel.navigationGuard("probe", function () { return holding ? "Finish the probe first." : null; });
  p.receive(snapshot(review()));
  assert.ok(!p.dialog() || p.dialog().hidden, "the tab is held");
  holding = false;
  p.receive(snapshot(review()));
  assert.ok(p.dialog() && !p.dialog().hidden, "shown on a later snapshot");
});

test("a review waits for a held Zone edit in the Spaces view", function () {
  var p = page();
  p.receive(snapshot());
  var zoneName = p.context.document.querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Zone A name";
  })[0];
  if (zoneName.listeners.focus) zoneName.listeners.focus({ target: zoneName });
  p.type(zoneName, "Zone A2");
  var notices = 0, notify = p.panel.notify;
  p.panel.notify = function () { notices += 1; return notify.apply(this, arguments); };
  var thrown = null;
  try { p.receive(snapshot(review())); } catch (error) { thrown = error; }
  assert.strictEqual(thrown, null);
  assert.ok(!p.dialog() || p.dialog().hidden, "no dialog opens over the Zone edit");
  assert.strictEqual(notices, 1, "one refusal");
  assert.deepStrictEqual(p.errors, []);
});

test("an open review holds the view, so a Faces hand-off waits behind it", function () {
  var p = page();
  var state = snapshot(review());
  p.receive(state);
  p.type(p.input("Name"), "Kitchen");
  var handoff = snapshot(review());
  handoff.sections["ph_composer.zones.faces.selection_assignment"] = { status: "completed",
    value: { token: "assign-1", revision: 6, faces: [face(1200)] } };
  handoff.sections["ph_composer.zones.faces.palette"] = { status: "completed", value: { active: false, palette: {},
    face_types: ["Wall"], boundary_conditions: ["Outdoors"] } };
  handoff.sections["ph_composer.zones.faces.faces"] = { status: "completed", value: { units: { area_m2: "m2" },
    faces: [] } };
  p.receive(handoff);
  p.receive(handoff);
  var open = p.context.document.querySelectorAll("dialog").filter(function (node) { return !node.hidden; });
  assert.strictEqual(open.length, 1, "only the Create Space review is open");
  assert.ok(!p.dialog().hidden);
});
