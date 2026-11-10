"use strict";

/* The Zones screen as a host of views (context/EXTENSIBILITY.md, "Zone views"): the view row, switching
   between Faces and the synthetic example view (tools/examples/zones/example_zone_view.js), what each view
   keeps across a switch, the remembered view and a navigation intent that names its view. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var vm = require("vm");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var root = require("./support/panel_files").root;

var HOST = "ph_composer.zones";
var AREAS = "example.zones.areas";

function page(options) {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view"]);
  if (!options || options.example !== false) {
    var file = path.join(root, "tools/examples/zones/example_zone_view.js");
    vm.runInContext(fs.readFileSync(file, "utf8"), context, { filename: file });
  }
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.section = function () { return context.document.querySelector("[data-section='ph_composer.overview']"); };
  return p;
}

function snapshot(remembered) {
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: remembered ? { "ph_composer.zones": remembered } : {} },
    sections: {
      "ph_composer.zones.faces.palette": { status: "completed", value: {
        active: false, palette: {}, face_types: ["Wall", "RoofCeiling", "Floor"],
        boundary_conditions: ["Outdoors", "Ground", "Adiabatic", "AttachedZone", "Surface"]
      } },
      "ph_composer.zones.overview": { status: "completed", value: {
        zones: [{ id: "zon_a", schema_version: 1, user_data: {}, extension_data: {},
          reference: { zone_id: "zon_a", zone_path: [100] }, state: "found", face_count: 2,
          face_area_m2: 20, unclassified_face_area_m2: 8,
          values: { name: "Zone 1", building_segment: "house", level: null, ground_depth_mm: 0 } }],
        make_zone: { parent_path: [], entity_ids: [200] },
        units: { ground_depth_mm: "mm", face_area_m2: "m2", unclassified_face_area_m2: "m2" }
      } },
      "ph_composer.zones.faces.faces": { status: "completed", value: { units: { area_m2: "m2" }, faces: [{
        reference: { zone_id: "zon_a", zone_path: [100], entity_path: [101], entity_id: "fac_a" },
        zone_name: "Zone 1", area_m2: 12, state: "classified",
        values: { face_type: "Wall", boundary_condition: "Outdoors" },
        suggested: { face_type: "Wall", boundary_condition: "Outdoors" }
      }, {
        reference: { zone_id: "zon_a", zone_path: [100], entity_path: [102], entity_id: null },
        zone_name: "Zone 1", area_m2: 8, state: "unclassified", values: {},
        suggested: { face_type: "Floor", boundary_condition: "Ground" }
      }] } }
    }
  };
}

function click(node) { node.listeners.click({ preventDefault: function () {} }); }

function viewRow(p) {
  return p.section().querySelector(".phc-view-tabs");
}

function tab(p, label) {
  return viewRow(p).querySelectorAll("button").filter(function (node) { return node.textContent === label; })[0];
}

/* The header fields the shown view's table paints, in order. */
function shownColumns(p) {
  var surface = p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0];
  return surface.querySelectorAll("th").map(function (th) { return th.className.split(" ")[0].replace("col-", ""); });
}

function rowKinds(p) {
  var surface = p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0];
  return surface.querySelectorAll("[data-row-key]").filter(function (node) { return !node.hidden; })
    .map(function (node) { return JSON.parse(node.getAttribute("data-row-key"))[0]; });
}

function byLabel(p, label) {
  return p.section().closest("[data-pane]").querySelectorAll("input, select, button").filter(function (node) {
    return node.getAttribute("aria-label") === label;
  })[0];
}

test("one listed view hides the view row; a second shows it, Faces first", function () {
  var p = page({ example: false });
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  assert.strictEqual(viewRow(p).hidden, true, "Faces alone needs no view row");
  var q = page();
  q.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  assert.strictEqual(viewRow(q).hidden, false);
  assert.strictEqual(viewRow(q).querySelector("nav").getAttribute("aria-label"), "Zone views");
  assert.deepStrictEqual(viewRow(q).querySelectorAll("button").map(function (node) { return node.textContent; }),
    ["Geometry", "Areas"]);
  assert.strictEqual(tab(q, "Geometry").getAttribute("aria-selected"), "true");
  var faceless = snapshot();
  delete faceless.sections["ph_composer.zones.faces.faces"];
  q.panel.receive({ type: "panel.snapshot", payload: faceless });
  assert.strictEqual(viewRow(q).hidden, true, "a view whose sections are not published is not listed");
  assert.deepStrictEqual(shownColumns(q), ["actions", "hierarchy", "name", "gross_m2", "unclassified_m2"]);
});

test("switching shows the other view's columns and rows, sends nothing to the Model and is remembered", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  assert.deepStrictEqual(rowKinds(p), ["Zone", "Face", "Unclassified", "Face"]);
  click(tab(p, "Areas"));
  assert.deepStrictEqual(shownColumns(p), ["actions", "hierarchy", "name", "gross_m2", "unclassified_m2"],
    "the example lists no Zone cells and no Face columns");
  assert.deepStrictEqual(rowKinds(p), ["Zone"], "a view with no child rows shows the Zone rows alone");
  var collapse = p.section().querySelector(".phc-view-expansion");
  assert.strictEqual(collapse.disabled, true, "nothing opens, so nothing collapses");
  var surface = p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0];
  assert.deepStrictEqual(surface.querySelectorAll("td").filter(function (td) {
    return /col-(gross|unclassified)_m2/.test(td.className);
  }).map(function (td) { return td.textContent; }), ["20", "8"]);
  assert.strictEqual(surface.querySelectorAll("input").filter(function (node) {
    return node.classList.contains("row-check");
  }).length, 0, "a view that checks nothing has no checkboxes");
  assert.deepStrictEqual(p.sent.map(function (message) { return message.type; }), ["preferences.set"]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload)), { request_id: p.sent[0].payload.request_id,
    key: "table_view", value: AREAS, scope: HOST });
  assert.strictEqual(p.modules.unit_preferences.tableView(HOST), AREAS);
  click(tab(p, "Geometry"));
  assert.deepStrictEqual(rowKinds(p), ["Zone", "Face", "Unclassified", "Face"], "Faces keeps its rows and expansion");
});

test("another Model gets its own view surfaces and the previous Model's leave the screen", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  click(tab(p, "Areas"));
  var other = snapshot(AREAS);
  other.session = "session-b";
  p.panel.receive({ type: "panel.snapshot", payload: other });
  assert.strictEqual(p.section().querySelectorAll(".phc-zone-view").length, 2, "one surface per listed view");
  assert.strictEqual(p.section().querySelectorAll(".phc-zone-view").filter(function (node) {
    return !node.hidden;
  }).length, 1);
  assert.deepStrictEqual(rowKinds(p), ["Zone"], "the new Model opens on the view this computer remembers");
});

test("the view last shown on this computer is the one a new session opens on", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(AREAS) });
  assert.strictEqual(tab(p, "Areas").getAttribute("aria-selected"), "true");
  assert.deepStrictEqual(rowKinds(p), ["Zone"]);
  var q = page();
  q.panel.receive({ type: "panel.snapshot", payload: snapshot("example.zones.retired") });
  assert.strictEqual(tab(q, "Geometry").getAttribute("aria-selected"), "true", "a remembered view no longer listed");
});

test("each view keeps its own column filters and sort; the Zone filters stay across a switch", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  click(byLabel(p, "Type column menu"));
  var wall = byLabel(p, "Type column menu").parentNode.querySelectorAll("input").filter(function (box) {
    return box.parentNode.children[1].textContent === "Wall";
  })[0];
  wall.checked = false; wall.listeners.change({});
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "1 Zone · 1 filter");
  // A press elsewhere closes the menu and takes focus from its checkbox before the tab is pressed.
  p.context.document.activeElement.blur();
  click(tab(p, "Areas"));
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "1 Zone",
    "a Face filter is the Faces view's and leaves with it");
  var text = byLabel(p, "Filter Zones");
  text.value = "Zone"; text.listeners.input({});
  click(tab(p, "Geometry"));
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "1 Zone · 1 filter",
    "and comes back with it");
  assert.strictEqual(byLabel(p, "Filter Zones").value, "Zone", "the text filter is the host's and stays");
  assert.deepStrictEqual(rowKinds(p), ["Zone", "Unclassified", "Face"]);
});

test("the checked set and Locate's outline outlast a switch; Escape in the other view clears it", function () {
  var p = page(), state = snapshot();
  p.panel.receive({ type: "panel.snapshot", payload: state });
  click(byLabel(p, "Check Wall 1"));
  click(p.section().querySelectorAll("[data-row-action='locate']")[1]);
  var locate = p.sent.filter(function (message) { return message.payload.name === "ph_composer.zones.faces.locate"; });
  assert.strictEqual(locate.length, 1);
  p.panel.receive({ type: "view.result", payload: { request_id: locate[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { found: 1, missing: 0 } } } });
  click(tab(p, "Areas"));
  function names() { return p.sent.map(function (message) { return message.payload.name || message.type; }); }
  assert.strictEqual(names().indexOf("ph_composer.zones.faces.clear_locate"), -1, "a switch leaves the outline");
  var escape = dom.dispatch(p.context.document.body, { type: "keydown", key: "Escape" });
  assert.strictEqual(escape.defaultPrevented, true);
  assert.strictEqual(names()[names().length - 1], "ph_composer.zones.faces.clear_locate");
  click(tab(p, "Geometry"));
  assert.ok(byLabel(p, "Uncheck Wall 1").checked, "Faces' checked set came back with it");
});

test("leaving Faces stops its paint tool", function () {
  var p = page(), state = snapshot();
  state.sections["ph_composer.zones.faces.palette"].value.active = true;
  state.sections["ph_composer.zones.faces.palette"].value.palette = { face_type: "Wall" };
  p.panel.receive({ type: "panel.snapshot", payload: state });
  click(tab(p, "Areas"));
  var stop = p.sent.filter(function (message) {
    return message.type === "view.invoke" && message.payload.name === "ph_composer.zones.faces.stop_classifying";
  });
  assert.strictEqual(stop.length, 1, "the paint tool does not keep painting a view that is not shown");
});

test("a navigation intent that names its view switches to it before checking rows", function () {
  var p = page();
  var state = snapshot(AREAS);
  p.panel.receive({ type: "panel.snapshot", payload: state });
  var reference = state.sections["ph_composer.zones.faces.faces"].value.faces[0].reference;
  assert.strictEqual(p.panel.navigate("overview", { view: "ph_composer.zones.faces", check: [reference] }), true);
  assert.strictEqual(tab(p, "Geometry").getAttribute("aria-selected"), "true");
  var box = byLabel(p, "Uncheck Wall 1");
  assert.ok(box && box.checked, "the named Face is checked in the view that was switched to");
});

test("a view registered under a host that never declares itself is reported at ready", function () {
  var errors = [], context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout, console: { error: function (text) { errors.push(text); } },
    sketchup: { ph_composer_message: function () {} }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view"]);
  modules.table_views.register("example.missing", { id: "example.missing.view", label: "Orphan" });
  modules.panel.ready();
  assert.deepStrictEqual(errors, ["table views with no host: example.missing.view (host example.missing)"]);
});

test("the host names no view and no feature beyond Zones", function () {
  var host = fs.readFileSync(path.join(root, "src/ph_composer/html/features/zones/overview.js"), "utf8");
  ["faces_view", "ph_composer.zones.faces", "classify", "spaces", "example."].forEach(function (name) {
    assert.strictEqual(host.indexOf(name), -1, "overview.js names " + name);
  });
  var kit = fs.readFileSync(path.join(root, "src/ph_composer/html/table_views.js"), "utf8");
  assert.strictEqual(/ph_composer\./.test(kit), false, "table_views.js names no feature");
});

/* ---------------------------------------------------------------- review cycle 1 (PR #149) */

function sentNames(p) {
  return p.sent.map(function (message) { return message.payload.name || message.type; });
}

test("a paint tool that turns on after Faces was left is stopped by the next snapshot", function () {
  var p = page(), state = snapshot();
  p.panel.receive({ type: "panel.snapshot", payload: state });
  click(tab(p, "Areas"));
  var late = snapshot();
  late.sections["ph_composer.zones.faces.palette"].value.active = true;
  late.sections["ph_composer.zones.faces.palette"].value.palette = { face_type: "Wall" };
  p.panel.receive({ type: "panel.snapshot", payload: late });
  assert.ok(sentNames(p).indexOf("ph_composer.zones.faces.stop_classifying") >= 0,
    "a choose that lands after the switch does not leave the tool painting a hidden view");
});

test("Assembly paint runs while the Assemblies table shows it, and stops when Zones shows another view", function () {
  var p = page(), state = snapshot(AREAS), palette = state.sections["ph_composer.zones.faces.palette"].value;
  p.panel.receive({ type: "panel.snapshot", payload: state });
  p.panel.showTab("assemblies");
  palette.active = true;
  palette.palette = { assembly_id: "asm_a" };
  p.panel.receive({ type: "panel.snapshot", payload: state });
  assert.strictEqual(sentNames(p).indexOf("ph_composer.zones.faces.stop_classifying"), -1,
    "the Assemblies table shows it, whatever view Zones last held");
  p.panel.showTab("overview");
  p.panel.receive({ type: "panel.snapshot", payload: state });
  assert.ok(sentNames(p).indexOf("ph_composer.zones.faces.stop_classifying") >= 0);
});

test("a native assignment handoff reaches Faces while another view is shown and shows Faces", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(AREAS) });
  p.panel.showTab("export");
  var handoff = snapshot(AREAS);
  handoff.sections["ph_composer.zones.faces.selection_assignment"] = { status: "completed", value: {
    token: "review-1", revision: 4,
    faces: handoff.sections["ph_composer.zones.faces.faces"].value.faces.map(function (face) { return face.reference; })
  } };
  p.panel.receive({ type: "panel.snapshot", payload: handoff });
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  assert.strictEqual(tab(p, "Geometry").getAttribute("aria-selected"), "true");
  assert.ok(p.context.document.querySelector("dialog"), "the assignment dialog opens");
});

test("an intent that names a view without checking rows shows it and says whether it did", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(AREAS) });
  var intent = { view: "ph_composer.zones.faces" };
  assert.strictEqual(p.panel.navigate("overview", intent), true);
  assert.strictEqual(intent.viewShown, true);
  assert.strictEqual(tab(p, "Geometry").getAttribute("aria-selected"), "true");
});

test("with no view listed the Zone rows show alone", function () {
  var p = page({ example: false }), state = snapshot();
  delete state.sections["ph_composer.zones.faces.faces"];
  p.panel.receive({ type: "panel.snapshot", payload: state });
  assert.deepStrictEqual(rowKinds(p), ["Zone"]);
  assert.strictEqual(viewRow(p).hidden, true);
});

test("pressing a view tab with the pointer keeps Locate's outline", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  click(p.section().querySelectorAll("[data-row-action='locate']")[1]);
  var locate = p.sent.filter(function (message) { return message.payload.name === "ph_composer.zones.faces.locate"; });
  p.panel.receive({ type: "view.result", payload: { request_id: locate[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { found: 1, missing: 0 } } } });
  dom.dispatch(tab(p, "Areas"), { type: "pointerdown" });
  click(tab(p, "Areas"));
  assert.strictEqual(sentNames(p).indexOf("ph_composer.zones.faces.clear_locate"), -1);
});

test("a view's own column sorts the Zone rows by the value it gives", function () {
  var p = page(), state = snapshot(AREAS), zones = state.sections["ph_composer.zones.overview"].value.zones;
  var second = JSON.parse(JSON.stringify(zones[0]));
  second.reference = { zone_id: "zon_b", zone_path: [300] }; second.id = "zon_b";
  second.values.name = "Zone 2"; second.face_area_m2 = 5;
  zones.push(second);
  p.panel.receive({ type: "panel.snapshot", payload: state });
  function names() {
    return p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0]
      .querySelectorAll("td").filter(function (td) { return /col-gross_m2/.test(td.className); })
      .map(function (td) { return td.textContent; });
  }
  assert.deepStrictEqual(names(), ["20", "5"]);
  var menu = byLabel(p, "Gross area m² column menu");
  click(menu);
  click(menu.parentNode.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Sort A to Z";
  })[0]);
  assert.deepStrictEqual(names(), ["5", "20"]);
});

test("the Colour by menu lists every mode, whether or not the shown view has its column", function () {
  var p = page(), state = snapshot(AREAS);
  state.sections["ph_composer.colour_by.legend"] = { status: "completed", value: {
    mode: "ph_composer.zones.by_level", label: "Level", rows: [], modes: [
      { name: "ph_composer.zones.by_zone", label: "Zone", group: null },
      { name: "ph_composer.zones.by_building_segment", label: "Building-Segment", group: null },
      { name: "ph_composer.zones.by_level", label: "Level", group: null }] } };
  p.panel.receive({ type: "panel.snapshot", payload: state });
  var options = byLabel(p, "Colour by");
  click(options);
  assert.deepStrictEqual(options.parentNode.querySelectorAll(".phc-action-menu-item").map(function (node) {
    return node.textContent;
  }), ["Zone", "Building-Segment", "Level"]);
  assert.strictEqual(options.getAttribute("aria-pressed"), "true");
});

/* The `menus` hook: a contributed view's menus follow Columns and Colour by, each fills with the view's own
   state when it opens, and each says why it cannot open while its `unavailable` answers. */
test("a view supplies its own control-row menus through the menus hook", function () {
  var p = page({ example: false }), on = false, filled = [];
  p.modules.table_views.register("ph_composer.zones", { id: "example.menus", label: "Menus", order: 97,
    sections: ["ph_composer.zones.overview"], zoneFields: [],
    create: function () { return { name: "probe state" }; },
    menus: [{ label: "Probe", icon: "tag",
      unavailable: function (vs) { return on ? null : "Not while " + vs.name + " is off."; },
      fill: function (vs, toggle) {
        filled.push(vs.name);
        toggle("Probe line", true, function () { filled.push("ran"); });
      } }] });
  p.panel.receive({ type: "panel.snapshot", payload: snapshot("example.menus") });
  var menus = p.section().closest("[data-pane]").querySelectorAll(".phc-control-menu").filter(function (node) {
    return !node.hidden;
  });
  assert.deepStrictEqual(menus.map(function (node) { return node.children[0].getAttribute("data-icon"); }),
    ["tag"], "no optional columns and no modes leave the view's menu alone");
  var probe = menus[0].children[0];
  assert.strictEqual(probe.getAttribute("aria-label"), "Probe. Not while probe state is off.");
  click(probe);
  assert.deepStrictEqual(filled, [], "an unavailable menu opens nothing");
  on = true;
  p.panel.receive({ type: "panel.snapshot", payload: snapshot("example.menus") });
  assert.strictEqual(probe.getAttribute("aria-label"), "Probe");
  click(probe);
  var item = probe.parentNode.querySelectorAll(".phc-action-menu-item")[0];
  assert.deepStrictEqual([item.textContent, item.getAttribute("aria-pressed")], ["Probe line", "true"]);
  click(item);
  assert.deepStrictEqual(filled, ["probe state", "ran"]);
});

test("a shown view that stops being listed leaves as a switch does: its filters go with it", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  click(byLabel(p, "Type column menu"));
  var wall = byLabel(p, "Type column menu").parentNode.querySelectorAll("input").filter(function (box) {
    return box.parentNode.children[1].textContent === "Wall";
  })[0];
  wall.checked = false; wall.listeners.change({});
  var faceless = snapshot();
  delete faceless.sections["ph_composer.zones.faces.faces"];
  p.panel.receive({ type: "panel.snapshot", payload: faceless });
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "1 Zone");
  assert.deepStrictEqual(rowKinds(p), ["Zone"]);
});

/* ---------------------------------------------------------------- review cycle 2 (PR #149) */

test("a shown view holding a draft stays shown when its section is withdrawn", function () {
  var p = page(), state = snapshot("example.guarded");
  p.modules.table_views.register("ph_composer.zones", { id: "example.guarded", label: "Guarded", order: 95,
    sections: ["example.guard.section"], draftReason: function () { return "Finish draft"; } });
  state.sections["example.guard.section"] = { status: "completed", value: {} };
  p.panel.receive({ type: "panel.snapshot", payload: state });
  assert.strictEqual(tab(p, "Guarded").getAttribute("aria-selected"), "true");
  p.panel.receive({ type: "panel.snapshot", payload: snapshot("example.guarded") });
  assert.strictEqual(tab(p, "Guarded").getAttribute("aria-selected"), "true", "the draft keeps its view");
});

test("an invalid Faces settings entry holds the switch", function () {
  var p = page(), state = snapshot();
  state.sections["ph_composer.zones.settings"] = { status: "completed", value: {
    suggest_on_make: true, roof_angle_deg: 60, floor_angle_deg: 130 } };
  p.panel.receive({ type: "panel.snapshot", payload: state });
  byLabel(p, "Faces settings").listeners.click({});
  var roof = byLabel(p, "Roof maximum tilt [deg]");
  roof.value = "170"; roof.listeners.change({});
  roof.blur();
  click(tab(p, "Areas"));
  assert.strictEqual(tab(p, "Geometry").getAttribute("aria-selected"), "true");
  roof.listeners.keydown({ key: "Escape" });
  click(tab(p, "Areas"));
  assert.strictEqual(tab(p, "Areas").getAttribute("aria-selected"), "true", "Escape restores and releases it");
});

test("a focused row checkbox does not hold a switch: its value already applies", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var shown = p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0];
  var box = shown.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; })[0];
  box.focus();
  click(tab(p, "Areas"));
  assert.strictEqual(tab(p, "Areas").getAttribute("aria-selected"), "true");
});

test("a refused switch's notice goes once a switch goes through", function () {
  var p = page(), state = snapshot();
  state.sections["ph_composer.zones.settings"] = { status: "completed", value: {
    suggest_on_make: true, roof_angle_deg: 60, floor_angle_deg: 130 } };
  p.panel.receive({ type: "panel.snapshot", payload: state });
  byLabel(p, "Faces settings").listeners.click({});
  var roof = byLabel(p, "Roof maximum tilt [deg]");
  roof.value = "170"; roof.listeners.change({});
  roof.blur();
  click(tab(p, "Areas"));
  var notice = p.context.document.querySelector(".phc-floating-notice");
  assert.strictEqual(notice.hidden, false, "the held switch says why");
  roof.listeners.keydown({ key: "Escape" });
  click(tab(p, "Areas"));
  assert.strictEqual(tab(p, "Areas").getAttribute("aria-selected"), "true");
  assert.strictEqual(notice.hidden, true, "the refusal no longer holds");
});

test("a finding that belongs to no Zone row shows below the table in the read's words", function () {
  var p = page(), state = snapshot();
  var message = "Zone \"Annex\" is now a component, so it is not read as a Zone.";
  state.sections["ph_composer.zones.overview"].value.findings = [{ code: "zone.component", message: message,
    reference: { zone_id: "zon_b", entity_path: [300] } }];
  p.panel.receive({ type: "panel.snapshot", payload: state });
  var list = p.section().querySelector(".phc-zone-findings");
  assert.strictEqual(list.hidden, false);
  assert.deepStrictEqual(list.children.map(function (line) { return line.textContent; }), [message]);
  assert.deepStrictEqual(rowKinds(p).slice(0, 1), ["Zone"], "the other Zones stay listed");
  state = snapshot();
  p.panel.receive({ type: "panel.snapshot", payload: state });
  assert.strictEqual(list.hidden, true, "it goes with the finding");
});

test("a Zone filter on a column the next view does not show leaves with the view that shows it", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var menu = byLabel(p, "Building-Segment column menu");
  click(menu);
  var box = menu.parentNode.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; })[0];
  box.checked = false; box.listeners.change({});
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "0 of 1 Zone · 1 filter");
  p.context.document.activeElement.blur();
  click(tab(p, "Areas"));
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "1 Zone");
  click(tab(p, "Geometry"));
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "0 of 1 Zone · 1 filter");
});

test("a view's filter column has a menu without sorting, and its Zone predicate reaches the viewport", function () {
  var p = page(), state = snapshot("example.kinds");
  p.modules.table_views.register("ph_composer.zones", { id: "example.kinds", label: "Kinds", order: 96,
    sections: ["ph_composer.zones.overview"], zoneFields: [], filteredFields: { kind: true },
    columns: function () { return [["kind", "Kind"]]; },
    value: function (vs, row, field) { return field === "kind" ? "A" : ""; },
    filterValues: function () { return ["a", "b"]; },
    filterLabel: function (vs, field, value) { return value.toUpperCase(); },
    zoneMatch: function (vs, record, filters) { return !filters.kind || filters.kind.indexOf("a") >= 0; } });
  p.panel.receive({ type: "panel.snapshot", payload: state });
  var menu = byLabel(p, "Kind column menu");
  assert.ok(menu, "a filterable column has a menu");
  click(menu);
  assert.strictEqual(menu.parentNode.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Sort A to Z";
  }).length, 0, "and offers no sort it did not declare");
  var a = menu.parentNode.querySelectorAll("input").filter(function (node) {
    return node.type === "checkbox" && node.parentNode.children[1].textContent === "A";
  })[0];
  a.checked = false; a.listeners.change({});
  var filter = p.sent.filter(function (message) { return message.payload.name === "ph_composer.colour_by.filter"; });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(filter[filter.length - 1].payload.params)), { paths: [] });
});

/* ---------------------------------------------------------------- review (PR #150) */

test("a Zone filter set while its column was shown elsewhere replaces an older one held by a view", function () {
  var p = page({ example: false });
  var probe = { id: "example.segments", label: "Segments", order: 97, sections: ["ph_composer.zones.overview"],
    zoneFields: ["building_segment"], hiddenColumns: { building_segment: true },
    optionalColumns: [["building_segment", "Building-Segment"]] };
  p.modules.table_views.register("ph_composer.zones", probe);
  var state = snapshot(), zones = state.sections["ph_composer.zones.overview"].value.zones;
  var second = JSON.parse(JSON.stringify(zones[0]));
  second.reference = { zone_id: "zon_b", zone_path: [300] }; second.id = "zon_b";
  second.values.name = "Zone 2"; second.values.building_segment = "annex";
  zones.push(second);
  p.panel.receive({ type: "panel.snapshot", payload: state });
  function keep(label) {
    var menu = byLabel(p, "Building-Segment column menu");
    click(menu);
    menu.parentNode.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; })
      .forEach(function (box) {
        var wanted = box.parentNode.children[1].textContent === label;
        if (box.checked !== wanted) { box.checked = wanted; box.listeners.change({}); }
      });
    p.context.document.activeElement && p.context.document.activeElement.blur();
  }
  function count() { return p.section().querySelector(".phc-view-count").textContent; }
  keep("house");
  click(tab(p, "Segments"));
  var options = byLabel(p, "Columns");
  click(options);
  click(options.parentNode.querySelectorAll(".phc-action-menu-item").filter(function (node) {
    return node.textContent === "Building-Segment";
  })[0]);
  keep("annex");
  assert.strictEqual(count(), "1 of 2 Zones · 1 filter");
  click(tab(p, "Geometry"));
  var names = p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0]
    .querySelectorAll("[data-row-key]").filter(function (node) { return !node.hidden; })
    .map(function (node) { return JSON.parse(node.getAttribute("data-row-key")); })
    .filter(function (key) { return key[0] === "Zone"; }).map(function (key) { return key[1][0]; });
  assert.deepStrictEqual(names, [300], "the filter last set, to annex, is the one in force");
});

test("a leading column is the view's own for header and menu hooks", function () {
  var p = page({ example: false }), seen = [];
  p.modules.table_views.register("ph_composer.zones", { id: "example.leading", label: "Leading", order: 98,
    sections: ["ph_composer.zones.overview"], zoneFields: [], sorted: ["code"],
    leadingColumns: function () { return [["code", "Code"]]; },
    headerAction: function (vs, field) { seen.push(field); return null; } });
  p.panel.receive({ type: "panel.snapshot", payload: snapshot("example.leading") });
  assert.ok(seen.indexOf("code") >= 0);
});
