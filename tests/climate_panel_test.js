"use strict";
/* The Climate tab: Climate first in the tab row with the panel still opening on Zones, the source cards
   and their states, Set Location with Read from SketchUp Geolocation, and the design temperatures. The page is
   the shipped index.html with the real panel, so what is sent is what the host would receive. */
var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var P = "ph_composer.climate.";
var SITE_UNSET = { latitude_deg: null, longitude_deg: null, elevation_m: null, climate_zone: null,
  hours_from_utc: null, climate_zone_label: null, state: "not_set" };
var SITE_SET = { latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15,
  hours_from_utc: -5, climate_zone_label: "5", state: "set" };
var DESIGN_UNSET = { heating_99_c: null, cooling_1_c: null, design_temperature_source: null, state: "not_set",
  warning: null };
var CLIMATE_NONE = { state: "none", origin: null, verdict: null, edited: false };

function completed(value) { return { status: "completed", value: value }; }
function sections(site, design, summary) {
  var result = {};
  result[P + "site"] = completed(site);
  result[P + "design_temperatures"] = completed(design);
  result[P + "summary"] = completed(summary || { site: site.state, climate: CLIMATE_NONE,
    design_temperatures: { state: design.state, warning: design.warning } });
  return result;
}
function snapshot(session, revision, parts, system) {
  return { product: "PH-Composer", version: "0.1.0-dev", session: session, revision: revision,
    file_name: "house.skp", edit_path: [], sections: parts,
    preferences: { unit_system: system || "SI", dimension_formats: {},
      number_format: { decimal: ".", locale: "en-US" } } };
}

function page(site, design, options) {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "sections/export", "features/climate/section"]);
  var p = { context: context, modules: modules, panel: modules.panel, sent: sent, session: "session-a", revision: 1,
    site: site || SITE_UNSET, design: design || DESIGN_UNSET, system: (options && options.system) || "SI" };
  p.receive = function (type, payload) { p.panel.receive({ type: type, payload: payload }); };
  p.publish = function () {
    p.receive("panel.snapshot", snapshot(p.session, p.revision, sections(p.site, p.design, p.summary), p.system));
  };
  p.publish();
  return p;
}
function pane(p) { return p.context.document.querySelector("[data-pane='climate']"); }
function all(root, selector) { return root.querySelectorAll(selector); }
function byText(root, selector, text) {
  return all(root, selector).filter(function (node) { return node.textContent === text; })[0] || null;
}
function card(p, id) { return pane(p).querySelector("[data-card='" + id + "']"); }
function chip(p, id) { return card(p, id).querySelector(".phc-source-card-chip"); }
function click(node) { node.listeners.click({ preventDefault: function () {} }); }
function type(input, text) { input.value = text; if (input.listeners.input) input.listeners.input({}); }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopImmediatePropagation: function () {} });
}
function open(p) { p.panel.showTab("climate"); }
function named(p, name) {
  return p.sent.filter(function (message) { return message.payload && message.payload.name === name; });
}
function answer(p, message, outcome, slot) {
  p.receive(slot || "action.result", { request_id: message.payload.request_id, session: p.session, outcome: outcome });
}
function dialog(p) { return p.context.document.querySelector(".climate-set-location"); }
function field(root, label) { return all(root, "[aria-label='" + label + "']")[0]; }
function setButton(root) { return byText(root, "button", "Set Location"); }

test("the panel opens on Zones with Climate first in the tab row (R1, W7)", function () {
  var p = page();
  var tabs = all(p.context.document.body, "[data-tab]").map(function (node) { return node.getAttribute("data-tab"); });
  assert.deepStrictEqual(tabs.slice(0, 2), ["climate", "overview"]);
  var markup = panelSource.markup("index.html");
  assert.ok(markup.indexOf('data-tab="climate">Climate<') < markup.indexOf('data-tab="overview">Zones<'));
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  assert.strictEqual(pane(p).hidden, true);
  open(p);
  assert.strictEqual(pane(p).hidden, false);
  assert.ok(byText(pane(p), "h1", "Climate"), "one page header names the tab");
});

test("each card shows its state from the summary; the Hourly weather file card is Planned and inert", function () {
  var p = page();
  open(p);
  assert.strictEqual(chip(p, "site").textContent, "Not set");
  assert.strictEqual(chip(p, "phius").textContent, "Not set");
  assert.strictEqual(chip(p, "design").textContent, "Not set");
  assert.strictEqual(chip(p, "hourly").textContent, "Planned");
  [["incomplete", null, "Incomplete"], ["complete", "pass", "Pass"], ["complete", "fail", "Outside Phius limits"],
    ["complete", "not_checked", "Not checked"]].forEach(function (row) {
    p.summary = { site: "not_set", design_temperatures: { state: "not_set", warning: null },
      climate: { state: row[0], origin: "station", verdict: row[1], edited: false } };
    p.publish();
    assert.strictEqual(chip(p, "phius").textContent, row[2]);
  });
  p.summary = null; p.site = SITE_SET;
  p.design = { heating_99_c: -17.2, cooling_1_c: 30.1, design_temperature_source: null, state: "set", warning: null };
  p.publish();
  assert.strictEqual(chip(p, "site").hidden, true, "a set site shows its values instead of a chip");
  assert.deepStrictEqual(all(card(p, "site"), ".phc-source-card-line").map(function (n) { return n.textContent; }),
    ["42.750° N, 73.800° W · 84\u00a0m", "Climate zone 5 · UTC −5"]);
  assert.strictEqual(chip(p, "design").textContent, "Set");
  p.design = { heating_99_c: -17.2, cooling_1_c: null, design_temperature_source: null, state: "incomplete",
    warning: null };
  p.publish();
  assert.strictEqual(chip(p, "design").textContent, "Incomplete");

  var hourly = card(p, "hourly"), select = pane(p).querySelector(".phc-source-card-select");
  assert.strictEqual(hourly.disabled, true);
  assert.strictEqual(hourly.getAttribute("aria-disabled"), "true");
  dom.dispatch(hourly, { type: "click" });
  assert.strictEqual(card(p, "site").getAttribute("aria-current"), "true", "a click on it selects nothing");
  assert.strictEqual(pane(p).querySelector(".climate-site").hidden, false);
  assert.strictEqual(all(select, "option").filter(function (o) { return o.value === "hourly"; })[0].disabled, true);
  select.value = "hourly"; select.listeners.change({});
  assert.strictEqual(select.value, "site", "the narrow select refuses the Planned card too");
  assert.strictEqual(card(p, "site").getAttribute("aria-current"), "true");
});

test("the selected card is remembered per Model session, and the select follows the cards", function () {
  var p = page();
  open(p);
  click(card(p, "design"));
  assert.strictEqual(pane(p).querySelector(".climate-design").hidden, false);
  assert.strictEqual(pane(p).querySelector(".climate-site").hidden, true);
  assert.strictEqual(pane(p).querySelector(".phc-source-card-select").value, "design");
  p.session = "session-b"; p.publish();
  assert.strictEqual(card(p, "site").getAttribute("aria-current"), "true", "another Model starts on Site location");
  p.session = "session-a"; p.publish();
  assert.strictEqual(card(p, "design").getAttribute("aria-current"), "true");
});

test("Site location reads Not set on a new Model and offers Set Location in the pane and the header", function () {
  var p = page();
  open(p);
  assert.ok(byText(pane(p), "h2", "The site location is not set"));
  var buttons = all(pane(p), "button").filter(function (b) { return b.textContent === "Set Location…"; });
  assert.strictEqual(buttons.length, 2, "the header's primary and the empty state's own");
  click(card(p, "design"));
  assert.strictEqual(all(pane(p), "button").filter(function (b) {
    return b.textContent === "Set Location…" && b.isConnected && !b.closest("[hidden]");
  }).length, 0, "the header offers Set Location only beside the site");
  p.site = SITE_SET; p.publish();
  click(card(p, "site"));
  var facts = all(pane(p), "dd").map(function (n) { return n.textContent; });
  assert.deepStrictEqual(facts, ["42.750°", "-73.800°", "84\u00a0m", "5", "−5"]);
  p.site = Object.assign({}, SITE_SET, { climate_zone: null, climate_zone_label: null, hours_from_utc: null });
  p.publish();
  facts = all(pane(p), "dd").map(function (n) { return n.textContent; });
  assert.deepStrictEqual(facts.slice(3), ["Not set", "Not set"], "each unset one is shown as such");
});

test("Set Location waits for latitude, longitude and elevation and sends one site.update", function () {
  var p = page();
  open(p);
  click(byText(pane(p), "button", "Set Location…"));
  var d = dialog(p);
  assert.ok(d && d.open, "the dialog opens");
  assert.strictEqual(setButton(d).disabled, true);
  type(field(d, "Latitude"), "42.3233");
  type(field(d, "Longitude"), "-73.3887");
  assert.strictEqual(setButton(d).disabled, true, "a partial site cannot be set");
  type(field(d, "Elevation"), "300");
  assert.strictEqual(setButton(d).disabled, false);
  assert.strictEqual(field(d, "Climate zone").value, "", "an unset zone is not Not defined");
  d.querySelector("form").listeners.submit({ preventDefault: function () {} });
  var updates = named(p, P + "site.update");
  assert.strictEqual(updates.length, 1);
  assert.deepStrictEqual(updates[0].payload.params, { values: { latitude_deg: 42.3233, longitude_deg: -73.3887,
    elevation_m: 300, climate_zone: null, hours_from_utc: null },
  expected_values: { latitude_deg: null, longitude_deg: null, elevation_m: null, climate_zone: null,
    hours_from_utc: null } });
  assert.strictEqual(setButton(d).disabled, true, "single flight");
  answer(p, updates[0], { status: "completed", value: {} });
  assert.strictEqual(dialog(p), null, "a completed write closes the dialog");
});

test("Set Location sends the zone's code and a typed offset, and Enter in the elevation sets it", function () {
  var p = page();
  open(p);
  click(byText(pane(p), "button", "Set Location…"));
  var d = dialog(p);
  type(field(d, "Latitude"), "40"); type(field(d, "Longitude"), "−105"); type(field(d, "Elevation"), "1655");
  field(d, "Climate zone").value = "141";
  type(field(d, "Hours from UTC"), "-7");
  key(field(d, "Elevation"), "Enter");
  var params = named(p, P + "site.update")[0].payload.params.values;
  assert.deepStrictEqual(params, { latitude_deg: 40, longitude_deg: -105, elevation_m: 1655, climate_zone: 141,
    hours_from_utc: -7 });
});

test("a refused Set keeps the dialog and its draft; a stale site puts the Model's values back", function () {
  var p = page();
  open(p);
  click(byText(pane(p), "button", "Set Location…"));
  var d = dialog(p);
  type(field(d, "Latitude"), "95"); type(field(d, "Longitude"), "10"); type(field(d, "Elevation"), "5");
  d.querySelector("form").listeners.submit({ preventDefault: function () {} });
  var first = named(p, P + "site.update");
  assert.strictEqual(first.length, 1);
  answer(p, first[0], { status: "refused", code: "validation.failed", message: "Latitude must be from -90 to 90." });
  assert.ok(dialog(p) && dialog(p).open, "the dialog stays open");
  assert.strictEqual(field(d, "Latitude").value, "95", "the draft is kept");
  assert.ok(byText(d, "div", "Latitude must be from -90 to 90."), "the refusal shows in the dialog");
  type(field(d, "Latitude"), "45");
  d.querySelector("form").listeners.submit({ preventDefault: function () {} });
  var second = named(p, P + "site.update")[1];
  p.site = SITE_SET; p.revision = 2; p.publish();
  answer(p, second, { status: "refused", code: "target.changed", message: "The site changed." });
  assert.ok(dialog(p).open);
  assert.strictEqual(field(d, "Latitude").value, "42.75", "the Model's values return");
  assert.strictEqual(field(d, "Elevation").value, "84");
  d.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.deepStrictEqual(named(p, P + "site.update")[2].payload.params.expected_values, {
    latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15, hours_from_utc: -5 },
  "the next Set is guarded by what the Model holds now");
});

test("Read from SketchUp Geolocation fills latitude and longitude, never elevation, and writes nothing", function () {
  var p = page();
  open(p);
  click(byText(pane(p), "button", "Set Location…"));
  var d = dialog(p);
  click(byText(d, "button", "Read from SketchUp Geolocation"));
  var reads = named(p, P + "site.geolocation");
  assert.strictEqual(reads.length, 1);
  assert.strictEqual(reads[0].type, "query.invoke");
  answer(p, reads[0], completed({ geolocated: true, latitude_deg: 42.3233, longitude_deg: -73.3887,
    hours_from_utc: null }), "query.result");
  assert.strictEqual(field(d, "Latitude").value, "42.3233");
  assert.strictEqual(field(d, "Longitude").value, "-73.3887");
  assert.strictEqual(field(d, "Elevation").value, "", "elevation is never filled");
  assert.strictEqual(field(d, "Hours from UTC").value, "");
  assert.strictEqual(named(p, P + "site.update").length, 0, "nothing is written until Set");
  assert.strictEqual(setButton(d).disabled, true, "elevation is still needed");

  click(byText(d, "button", "Read from SketchUp Geolocation"));
  answer(p, named(p, P + "site.geolocation")[1], completed({ geolocated: false, latitude_deg: null,
    longitude_deg: null, hours_from_utc: null }), "query.result");
  assert.ok(byText(d, "p", "This SketchUp model has no geolocation."), "board 22's state");
  assert.strictEqual(field(d, "Latitude").value, "42.3233", "an empty read clears nothing");
});

test("design temperatures commit one field at a time, unset when cleared, and warn without refusing", function () {
  var p = page();
  open(p);
  click(card(p, "design"));
  var root = pane(p).querySelector(".climate-design");
  var heating = field(root, "99% heating dry bulb"), cooling = field(root, "1% cooling dry bulb");
  type(heating, "-17.2"); key(heating, "Enter");
  type(cooling, "30.1"); cooling.listeners.blur({});
  var updates = named(p, P + "design_temperatures.update");
  assert.strictEqual(updates.length, 1, "the second commit waits for the first, which carries this revision");
  assert.deepStrictEqual(updates[0].payload.params, { values: { heating_99_c: -17.2 },
    expected_values: { heating_99_c: null } });
  assert.strictEqual(updates[0].payload.expected_revision, 1);
  assert.strictEqual(heating.readOnly, true, "a field is read only while its write is out");
  assert.strictEqual(cooling.readOnly, true, "and while it waits");
  p.design = { heating_99_c: -17.2, cooling_1_c: null, design_temperature_source: null, state: "incomplete",
    warning: null };
  p.revision = 2; p.publish();
  answer(p, updates[0], completed(p.design));
  updates = named(p, P + "design_temperatures.update");
  assert.strictEqual(updates.length, 2, "then the waiting one goes, against the new revision");
  assert.deepStrictEqual(updates[1].payload.params, { values: { cooling_1_c: 30.1 },
    expected_values: { cooling_1_c: null } });
  assert.strictEqual(updates[1].payload.expected_revision, 2);
  assert.strictEqual(heating.readOnly, false);
  p.design = { heating_99_c: -17.2, cooling_1_c: 30.1, design_temperature_source: null, state: "set", warning: null };
  p.revision = 3; p.publish();
  answer(p, updates[1], completed(p.design));

  type(heating, ""); key(heating, "Enter");
  assert.deepStrictEqual(named(p, P + "design_temperatures.update")[2].payload.params,
    { values: { heating_99_c: null }, expected_values: { heating_99_c: -17.2 } }, "clearing a field unsets it");
  answer(p, named(p, P + "design_temperatures.update")[2], completed(p.design));

  var source = field(root, "Source (optional)");
  type(source, "ASHRAE 2021, Albany"); source.listeners.blur({});
  assert.deepStrictEqual(named(p, P + "design_temperatures.update")[3].payload.params,
    { values: { design_temperature_source: "ASHRAE 2021, Albany" },
      expected_values: { design_temperature_source: null } });

  p.design = { heating_99_c: 31, cooling_1_c: 30.1, design_temperature_source: null, state: "set",
    warning: "climate.heating_not_below_cooling" };
  p.publish();
  var warning = root.querySelector(".climate-design-warning");
  assert.strictEqual(warning.hidden, false);
  assert.ok(/at or above the cooling/.test(warning.textContent));
  assert.strictEqual(heating.value, "31", "the value saved and shows");
});

test("a half-typed design temperature is not sent or lost by a repaint", function () {
  var p = page();
  open(p);
  click(card(p, "design"));
  var root = pane(p).querySelector(".climate-design");
  var heating = field(root, "99% heating dry bulb");
  type(heating, "-1");
  p.revision = 4; p.publish(); p.publish();
  assert.strictEqual(named(p, P + "design_temperatures.update").length, 0);
  assert.strictEqual(heating.value, "-1");
  assert.strictEqual(field(pane(p).querySelector(".climate-design"), "99% heating dry bulb"), heating,
    "the field is the same node");
});

test("IP and SI: elevation in feet and temperatures in Fahrenheit are stored in SI", function () {
  var p = page(null, null, { system: "IP" });
  open(p);
  click(byText(pane(p), "button", "Set Location…"));
  var d = dialog(p);
  type(field(d, "Latitude"), "42"); type(field(d, "Longitude"), "-73"); type(field(d, "Elevation"), "1000");
  d.querySelector("form").listeners.submit({ preventDefault: function () {} });
  var elevation = named(p, P + "site.update")[0].payload.params.values.elevation_m;
  assert.ok(Math.abs(elevation - 304.8) < 1e-9, String(elevation));
  answer(p, named(p, P + "site.update")[0], completed({}));

  click(card(p, "design"));
  var heating = field(pane(p).querySelector(".climate-design"), "99% heating dry bulb");
  type(heating, "5"); key(heating, "Enter");
  var celsius = named(p, P + "design_temperatures.update")[0].payload.params.values.heating_99_c;
  assert.ok(Math.abs(celsius - -15) < 1e-9, String(celsius));

  p.site = SITE_SET;
  p.design = { heating_99_c: -15, cooling_1_c: 30, design_temperature_source: null, state: "set", warning: null };
  p.publish();
  answer(p, named(p, P + "design_temperatures.update")[0], completed(p.design));
  assert.strictEqual(all(card(p, "site"), ".phc-source-card-line")[0].textContent,
    "42.750° N, 73.800° W · 275.59\u00a0ft");
  assert.strictEqual(all(card(p, "design"), ".phc-source-card-line")[0].textContent,
    "99% heating 5\u00a0°F · 1% cooling 86\u00a0°F");
  assert.strictEqual(heating.value, "5");
});

test("an export finding opens the Climate tab at the card that fixes it", function () {
  var p = page();
  p.panel.navigate("climate", { code: "climate.zone_not_set" });
  assert.strictEqual(p.panel.state.ui.activeTab, "climate");
  assert.strictEqual(card(p, "site").getAttribute("aria-current"), "true");
  p.panel.navigate("climate", { code: "climate.incomplete" });
  assert.strictEqual(card(p, "phius").getAttribute("aria-current"), "true");
  assert.strictEqual(pane(p).querySelector(".climate-phius").hidden, false);
  assert.strictEqual(p.panel.tabFor("ph_composer.climate.export.site").tab, "climate",
    "the Export tab's Open Climate reaches this tab");
});

test("the climate zone labels match the Ruby list the Model's codes come from", function () {
  var ruby = fs.readFileSync(path.join(__dirname, "..", "src", "ph_composer", "features", "climate", "site",
    "climate_zones.rb"), "utf8");
  var pairs = [], expression = /(\d+) => "([^"]+)"/g, match;
  while ((match = expression.exec(ruby))) pairs.push([Number(match[1]), match[2]]);
  var p = page();
  open(p);
  click(byText(pane(p), "button", "Set Location…"));
  var options = all(field(dialog(p), "Climate zone"), "option").slice(1).map(function (option) {
    return [Number(option.value), option.textContent];
  });
  assert.deepStrictEqual(options, pairs);
});

test("the Export tab's Open Climate carries the finding's code to the card that fixes it", function () {
  var p = page();
  p.panel.showTab("export");
  var requests = p.sent.filter(function (m) { return m.type === "export.preflight" || m.type === "export.latest"; });
  p.receive("export.result", { request_id: requests[0].payload.request_id, session: p.session, outcome: {
    status: "completed", value: { repairs: [], findings: [{ code: "climate.utc_offset_not_set", blocks_export: false,
      section: "ph_composer.climate.export.site", object_id: "Site", message: "Hours from UTC is not set." }] } } });
  p.receive("export.result", { request_id: requests[1].payload.request_id, session: p.session,
    outcome: { status: "completed", value: null } });
  click(card(p, "design"));
  var open = all(p.context.document.querySelector("[data-section='export']"), "button").filter(function (b) {
    return b.textContent.indexOf("Open ") === 0;
  })[0];
  assert.ok(open, "the finding offers a way to its tab");
  click(open);
  assert.strictEqual(p.panel.state.ui.activeTab, "climate");
  assert.strictEqual(card(p, "site").getAttribute("aria-current"), "true", "it lands on Site location");
});

test("a design temperature is guarded by its value when typing began; a refusal shows the Model's", function () {
  var p = page(null, { heating_99_c: -10, cooling_1_c: 30, design_temperature_source: "Old note", state: "set",
    warning: null });
  open(p);
  click(card(p, "design"));
  var root = pane(p).querySelector(".climate-design"), heating = field(root, "99% heating dry bulb");
  type(heating, "-12");
  p.design = Object.assign({}, p.design, { heating_99_c: -11 }); p.revision = 2; p.publish();
  assert.strictEqual(heating.value, "-12", "the draft stays while another writer changes the value");
  key(heating, "Enter");
  var update = named(p, P + "design_temperatures.update")[0];
  assert.deepStrictEqual(update.payload.params,
    { values: { heating_99_c: -12 }, expected_values: { heating_99_c: -10 } },
    "guarded by what the user was looking at, so the change elsewhere is not overwritten");
  answer(p, update, { status: "refused", code: "target.changed", message: "The value changed." });
  assert.strictEqual(heating.value, "-11", "the refusal leaves the Model's value in the field");
  assert.strictEqual(heating.readOnly, false);

  var source = field(root, "Source (optional)");
  type(source, "Draft note");
  key(source, "Escape");
  assert.strictEqual(source.value, "Old note", "Escape puts the saved note back");
  source.listeners.blur({});
  assert.strictEqual(named(p, P + "design_temperatures.update").length, 1, "and nothing is sent");
  type(source, "New note"); key(source, "Enter");
  assert.deepStrictEqual(named(p, P + "design_temperatures.update")[1].payload.params,
    { values: { design_temperature_source: "New note" }, expected_values: { design_temperature_source: "Old note" } });
});

test("Set Location says what it cannot read, and a failed geolocation read says so", function () {
  var p = page();
  open(p);
  click(byText(pane(p), "button", "Set Location…"));
  var d = dialog(p);
  type(field(d, "Latitude"), "40"); type(field(d, "Longitude"), "-105"); type(field(d, "Elevation"), "1655");
  type(field(d, "Hours from UTC"), "-5.5");
  d.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(named(p, P + "site.update").length, 0);
  assert.ok(byText(d, "div", "Enter hours from UTC as a whole number, such as -5."));
  type(field(d, "Latitude"), "north");
  assert.strictEqual(setButton(d).disabled, true, "a latitude that is not a number is not present");
  click(byText(d, "button", "Read from SketchUp Geolocation"));
  answer(p, named(p, P + "site.geolocation")[0], { status: "failed", message: "SketchUp could not be read." },
    "query.result");
  assert.ok(byText(d, "p", "SketchUp could not be read."));
  d.listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(dialog(p), null, "Escape closes it with nothing written");
  assert.strictEqual(named(p, P + "site.update").length, 0);
});
