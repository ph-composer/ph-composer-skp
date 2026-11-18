"use strict";
/* Set Phius Climate Data, the station picker: every station of one dataset on the outline map and in a list, read in
   one `stations.all`, opening on the dataset the rule names, sorted by distance with State on All and the map framed
   on the 50 mile ring around the site; the State filter, the search and Find Nearest; Dataset remembered; map and list
   selecting together; the verdict before Attach, a failing station attached with no confirm; Replace's comparison and
   its lost edits; refusals kept in the dialog; and no station value beyond name, location and elevation in the station
   reads and the attach. The page is the shipped index.html with the real panel. Every station is invented. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var P = "ph_composer.climate.";
var SITE = { latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15, hours_from_utc: -5,
  climate_zone_label: "5", state: "set" };
var DESIGN = { heating_99_c: null, cooling_1_c: null, design_temperature_source: null, state: "not_set",
  warning: null };
function folder(id, name, count) {
  return { id: "climate_folder_" + id, name: name, display_location: "~/Climate/" + name, found: true,
    format: count ? "phius_station_file" : null, station_count: count, state_count: count ? 3 : 0,
    files_not_read: [], files_not_read_total: 0, complete: true };
}
var SET_A = folder("aaaaaaaaaaaa", "Station Set One", 6);
var SET_B = folder("bbbbbbbbbbbb", "Station Set Two", 6);
var EMPTY = folder("cccccccccccc", "Spreadsheets", 0);
var ROW_KEYS = ["key", "name", "state", "latitude_deg", "longitude_deg", "elevation_m", "limit_check"];

/* An invented station `km` north of the site and `rise` metres above it, checked as limit_check.rb would. */
function station(state, name, km, rise) {
  var distanceOk = km <= 80.4672, elevationOk = Math.abs(rise) <= 121.92;
  return { key: state + "/" + name.toUpperCase().replace(/ /g, "_") + "-mon.txt", name: name, state: state,
    latitude_deg: SITE.latitude_deg + km / 111.195, longitude_deg: SITE.longitude_deg,
    elevation_m: SITE.elevation_m + rise,
    limit_check: { verdict: distanceOk && elevationOk ? "pass" : "fail", reason: null, distance_km: km,
      elevation_difference_m: Math.abs(rise), distance_ok: distanceOk, elevation_ok: elevationOk } };
}
var NEAR = station("XA", "Alder Field", 18, 11);
var SECOND = station("XB", "Birch Point", 41, -52);
var HIGH = station("XA", "Cedar Ridge", 66, 310);
var FAR = station("XC", "Dune Airfield", 112, 20);
var FIFTH = station("XB", "Elm Crossing", 139, -8);
var SIXTH = station("XC", "Fir Hollow", 151, 402);
// Given out of distance order, as nothing but the picker's own sort should be trusted with the order shown.
var STATIONS = [HIGH, NEAR, FIFTH, SECOND, SIXTH, FAR];

function completed(value) { return { status: "completed", value: value }; }
function refused(code, message) { return { status: "refused", code: code, message: message, effect: "none" }; }

function page(options) {
  options = options || {};
  var sent = [], received = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/climate/section"]);
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent, received: received,
    session: "session-a",
    revision: 1, site: options.site || SITE, climate: options.climate || null };
  p.receive = function (type, payload) {
    received.push({ type: type, payload: payload });
    p.panel.receive({ type: type, payload: payload });
  };
  p.publish = function () {
    var sections = {}, climate = p.climate;
    sections[P + "site"] = completed(p.site);
    sections[P + "design_temperatures"] = completed(DESIGN);
    sections[P + "summary"] = completed({ site: p.site.state, design_temperatures: { state: "not_set", warning: null },
      climate: climate ? { state: "complete", origin: "station", verdict: "pass", edited: climate.edited > 0 } :
        { state: "none", origin: null, verdict: null, edited: false } });
    p.receive("panel.snapshot", { product: "PH-Composer", version: "0.1.0-dev", session: p.session,
      revision: p.revision, file_name: "house.skp", edit_path: [], sections: sections,
      preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } });
  };
  p.publish();
  return p;
}
function pane(p) { return p.context.document.querySelector("[data-pane='climate']"); }
function picker(p) { return p.context.document.querySelector(".climate-picker"); }
/* The Climate tab's view, kept on the node the section renders into. */
function tab(p) {
  var found = null;
  (function walk(node) { if (node._view) found = node._view; else node.children.forEach(walk); })(pane(p));
  return found;
}
function view(p) { return tab(p).picker; }
function all(root, selector) { return root.querySelectorAll(selector); }
function byText(root, selector, text) {
  return all(root, selector).filter(function (node) { return node.textContent === text; })[0] || null;
}
function labelled(root, label) { return all(root, "[aria-label='" + label + "']")[0] || null; }
function text(node) { return node.textContent + node.children.map(text).join(""); }
function click(node) { node.listeners.click({ preventDefault: function () {}, currentTarget: node }); }
function change(select, value) { select.value = value; select.listeners.change({ target: select }); }
function type(input, value) { input.value = value; input.listeners.input({ target: input }); }
function key(node, name) {
  var event = { key: name, target: node, preventDefault: function () { event.prevented = true; } };
  node.listeners.keydown(event);
  return event;
}
/* Every request but the attached pane's: with a climate attached it reads the climate and its source too
   (attached.js), and these tests leave those unanswered. */
function named(p, name) {
  return p.sent.filter(function (message) {
    return message.payload && message.payload.name === name &&
      !/:climate_attached/.test(message.payload.request_id || "");
  });
}
function last(p, name) { var found = named(p, name); return found[found.length - 1]; }
function answer(p, message, outcome) {
  var slot = message.type === "setup.invoke" ? "setup.result" : message.type === "action.invoke" ? "action.result" :
    "query.result";
  p.receive(slot, { request_id: message.payload.request_id, session: p.session, outcome: outcome });
}
function folders(p, list, lastId) {
  answer(p, last(p, P + "folders.list"), completed({ folders: list, last_dataset_id: lastId || null }));
}
function stations(p, rows, set) {
  var dataset = set || SET_A;
  answer(p, last(p, P + "stations.all"), completed({ folder_id: dataset.id, dataset_name: dataset.name,
    complete: true, total: rows.length, stations: rows }));
}
function select(p, name) { return labelled(picker(p), name); }
/* The station rows the list shows now, in order. */
function shown(p) {
  return all(picker(p), "tr").filter(function (row) {
    return row.getAttribute("data-row-key") && !row.hidden;
  }).map(function (row) { return row.getAttribute("data-row-key"); });
}
function row(p, station) { return picker(p).querySelector("[data-row-key='" + station.key + "']"); }
function rowButton(p, station) { return row(p, station).querySelector(".climate-picker-station"); }
function selectedRow(p) {
  return all(picker(p), "tr").filter(function (node) { return node.classList.contains("host-selected"); })
    .map(function (node) { return node.getAttribute("data-row-key"); });
}
function marker(p, station) { return picker(p).querySelector("[data-point='" + station.key + "']"); }
function markers(p) { return all(picker(p), "[data-point]"); }
function footer(p) { return text(picker(p).querySelector(".climate-picker-selection")); }
/* Attach and Replace are the form's submit, as Enter is. */
function commit(p) { picker(p).querySelector("form").listeners.submit({ preventDefault: function () {} }); }
var MAP_RECT = { left: 0, top: 0, right: 560, bottom: 380, width: 560, height: 380, x: 0, y: 0 };
function pointer(p, type, target, x, y) {
  var svg = picker(p).querySelector(".phc-outline-map-drawing");
  svg.rect = MAP_RECT;
  svg.listeners[type]({ type: type, clientX: x || 10, clientY: y || 10, button: 0, isPrimary: true, pointerId: 3,
    target: target, preventDefault: function () {} });
}
function clickMarker(p, station) {
  pointer(p, "pointerdown", marker(p, station).children[0]);
  pointer(p, "pointerup", marker(p, station).children[0]);
}

/* The Phius pane's Choose Station opens the picker: the pane read the folders, the picker reads them again. */
function openPicker(p, list, lastId) {
  p.panel.showTab("climate");
  click(pane(p).querySelector("[data-card='phius']"));
  folders(p, list || [SET_A], lastId);
  click(byText(pane(p), "button", "Choose Station…"));
  assert.ok(picker(p), "the picker opens");
  folders(p, list || [SET_A], lastId);
}
function opened(rows) {
  var p = page();
  openPicker(p);
  stations(p, rows || STATIONS);
  return p;
}
/* A Model holding a climate: the page header offers Replace, which opens the picker in Replace. */
function climateGet(p, edited) {
  return completed({ state: "complete", missing: [], edited_cells: Array.from({ length: edited }, function (_, i) {
    return { row: "air_c", column: i };
  }), limit_check: NEAR.limit_check, climate: { id: "climate-1", values: { name: NEAR.name, origin: "station",
    station_latitude_deg: NEAR.latitude_deg, station_longitude_deg: NEAR.longitude_deg,
    station_elevation_m: NEAR.elevation_m, monthly: { air_c: [1, 2, 3] },
    provenance: { dataset_name: SET_A.name, station_name: "ALDER_FIELD", state: "XA" } } } });
}
function openReplace(edited) {
  var p = page({ climate: { edited: edited } });
  p.panel.showTab("climate");
  click(pane(p).querySelector("[data-card='phius']"));
  click(byText(pane(p), "button", "Replace…"));
  folders(p, [SET_B, SET_A]);
  answer(p, last(p, P + "climate.source_status"), completed({ status: "found", folder_id: SET_A.id,
    station_key: NEAR.key }));
  answer(p, last(p, P + "climate.get"), climateGet(p, edited));
  stations(p, STATIONS);
  return p;
}

test("it opens on the dataset used last, sorted by distance, State on All and framed on the site's 50 mi ring",
  function () {
    var p = page();
    openPicker(p, [EMPTY, SET_A, SET_B], SET_B.id);
    assert.deepStrictEqual(last(p, P + "stations.all").payload.params, { folder_id: SET_B.id });
    assert.strictEqual(named(p, P + "stations.list").length, 0, "the whole list is one read, never paged");
    stations(p, STATIONS, SET_B);
    assert.deepStrictEqual(shown(p), [NEAR, SECOND, HIGH, FAR, FIFTH, SIXTH].map(function (s) { return s.key; }));
    assert.strictEqual(select(p, "State").value, "");
    assert.strictEqual(select(p, "Dataset").value, SET_B.id);
    assert.deepStrictEqual(selectedRow(p), [NEAR.key], "the nearest station is selected");
    var map = view(p).map, projection = p.modules.map_projection;
    assert.deepStrictEqual(map.home, projection.ringBounds(SITE.latitude_deg, SITE.longitude_deg, 80.4672));
    assert.ok(byText(picker(p), "text", "50 mi from the site"), "the ring around the site");
    assert.ok(text(picker(p)).indexOf("Station Set Two · 6 stations on this computer · 6 shown") >= 0);
    assert.strictEqual(picker(p).querySelector(".climate-picker-title").textContent, "Set Phius climate data");
  });

test("with no dataset used last it opens on the first found folder holding stations", function () {
  var p = page();
  openPicker(p, [EMPTY, Object.assign({}, SET_B, { found: false }), SET_A], "climate_folder_gonegonegone");
  assert.deepStrictEqual(last(p, P + "stations.all").payload.params, { folder_id: SET_A.id });
});

test("with a climate attached it opens on the attached station's dataset when its file is on this computer",
  function () {
    var p = openReplace(0);
    assert.deepStrictEqual(last(p, P + "stations.all").payload.params, { folder_id: SET_A.id },
      "the attached station's folder, not the first found");
    assert.ok(text(row(p, NEAR)).indexOf("Attached") >= 0, "the attached station is marked in the list");
  });

test("State narrows the list and the map; the search narrows by name; Find Nearest returns to the opening view",
  function () {
    var p = opened();
    assert.deepStrictEqual(all(select(p, "State"), "option").map(function (o) { return o.textContent; }),
      ["All", "XA", "XB", "XC"]);
    change(select(p, "State"), "XB");
    assert.deepStrictEqual(shown(p), [SECOND.key, FIFTH.key]);
    assert.strictEqual(markers(p).length, 2);
    assert.ok(text(picker(p)).indexOf("2 shown") >= 0);
    change(select(p, "State"), "");
    type(labelled(picker(p), "Filter stations"), "cedar");
    assert.deepStrictEqual(shown(p), [HIGH.key]);
    clickMarker(p, HIGH);
    view(p).map.zoomBy(2);
    click(byText(picker(p), "button", "Find Nearest"));
    assert.strictEqual(shown(p).length, 6);
    assert.strictEqual(labelled(picker(p), "Filter stations").value, "");
    assert.strictEqual(select(p, "State").value, "");
    assert.deepStrictEqual(selectedRow(p), [NEAR.key]);
    assert.strictEqual(view(p).map.userMoved(), false, "the map is back on the ring");
  });

test("Dataset reads the other folder and remembers it on this computer", function () {
  var p = page();
  openPicker(p, [SET_A, SET_B], SET_A.id);
  stations(p, STATIONS);
  change(select(p, "State"), "XC");
  change(select(p, "Dataset"), SET_B.id);
  assert.deepStrictEqual(last(p, P + "folders.remember_dataset").payload.params, { id: SET_B.id });
  assert.deepStrictEqual(last(p, P + "stations.all").payload.params, { folder_id: SET_B.id });
  stations(p, [FAR, SIXTH], SET_B);
  assert.deepStrictEqual(shown(p), [FAR.key, SIXTH.key]);
  assert.strictEqual(select(p, "State").value, "", "a new dataset opens on All");
  assert.deepStrictEqual(selectedRow(p), [FAR.key]);
});

test("a click on a marker selects the row and scrolls it into view; a row selects its marker", function () {
  var p = opened();
  var scrolled = [];
  row(p, FIFTH).scrollIntoView = function (options) { scrolled.push(options); };
  clickMarker(p, FIFTH);
  assert.deepStrictEqual(selectedRow(p), [FIFTH.key]);
  assert.strictEqual(scrolled.length, 1, "the row is brought into view");
  assert.ok(footer(p).indexOf("Elm Crossing") === 0);
  click(rowButton(p, SECOND));
  assert.strictEqual(marker(p, SECOND).getAttribute("aria-current"), "true");
  assert.strictEqual(marker(p, FIFTH).getAttribute("aria-current"), null);
  assert.deepStrictEqual(selectedRow(p), [SECOND.key]);
});

test("hovering a marker shows its name, distance, elevation difference and verdict", function () {
  var p = opened();
  pointer(p, "pointermove", marker(p, HIGH).children[0], 40, 40);
  var tip = picker(p).querySelector(".phc-outline-map-tip");
  assert.strictEqual(tip.hidden, false);
  assert.strictEqual(text(tip), "Cedar Ridge66 km · +310 mOutside Phius limits");
  pointer(p, "pointermove", marker(p, SECOND).children[0], 50, 50);
  assert.strictEqual(text(picker(p).querySelector(".phc-outline-map-tip")),
    "Birch Point41 km · −52 mPass");
});

test("the footer gives a passing station's verdict against both limits", function () {
  var p = opened();
  assert.strictEqual(footer(p), "Alder Field is 18 km from the site and 11 m higher. Within the Phius " +
    "limits of 50 mi and 400 ft.Attaching copies this station's values into the Model.");
});

test("a failing station is warned about before Attach and attaches with one action and no confirm", function () {
  var p = opened();
  click(rowButton(p, HIGH));
  assert.ok(footer(p).indexOf("Cedar Ridge is 66 km from the site and 310 m higher. Outside the Phius " +
    "elevation limit of 400 ft.") === 0, footer(p));
  assert.ok(footer(p).indexOf("It can still be attached. The Model and the Export report will show it as outside " +
    "the Phius limits.") >= 0);
  assert.ok(picker(p).querySelector(".climate-picker-warning"), "the warning is set apart");
  var attach = byText(picker(p), "button", "Attach");
  assert.strictEqual(attach.disabled, false);
  var before = p.sent.length;
  commit(p);
  var actions = p.sent.slice(before).filter(function (m) { return m.type === "action.invoke"; });
  assert.strictEqual(actions.length, 1);
  assert.strictEqual(actions[0].payload.name, P + "climate.attach_station");
  assert.deepStrictEqual(actions[0].payload.params, { folder_id: SET_A.id, station_key: HIGH.key });
  assert.strictEqual(p.context.document.querySelector(".phc-confirm-dialog"), null, "no confirm step");
  answer(p, actions[0], { status: "completed", effect: "committed", revision: 2, value: {} });
  assert.strictEqual(picker(p), null, "the dialog closes on the pane");
});

test("with a climate attached the two stations are compared, lost edits counted, and Replace is one action",
  function () {
    var p = openReplace(2);
    assert.strictEqual(picker(p).querySelector(".climate-picker-title").textContent, "Replace Phius climate data");
    click(rowButton(p, SECOND));
    var compared = all(picker(p).querySelector(".climate-picker-compare"), "tr").map(text);
    assert.deepStrictEqual(compared, ["StationDatasetDistanceElevationResult",
      "NowAlder FieldStation Set One18 km+11 mPass",
      "NewBirch PointStation Set One41 km−52 mPass"]);
    assert.ok(footer(p).indexOf("Alder Field has 2 edited values. Replacing it discards them.") >= 0);
    assert.ok(footer(p).indexOf("Replacing is one Undo step.") >= 0);
    var before = p.sent.length;
    assert.ok(byText(picker(p), "button", "Replace"));
    commit(p);
    var actions = p.sent.slice(before).filter(function (m) { return m.type === "action.invoke"; });
    assert.deepStrictEqual(actions.map(function (m) { return m.payload.name; }), [P + "climate.replace_station"]);
    assert.deepStrictEqual(actions[0].payload.params, { folder_id: SET_A.id, station_key: SECOND.key });
  });

test("with no edited values Replace says nothing is lost", function () {
  var p = openReplace(0);
  assert.strictEqual(footer(p).indexOf("edited value"), -1);
});

test("a refusal stays in the dialog as its message and nothing is attached", function () {
  [["climate.site_not_set", "Set the site first."], ["climate.station_not_found", "The file is gone."],
    ["climate.station_unreadable", "The file could not be read."]].forEach(function (refusal) {
    var p = opened();
    commit(p);
    answer(p, last(p, P + "climate.attach_station"), refused(refusal[0], refusal[1]));
    assert.ok(picker(p), refusal[0] + ": the dialog stays open");
    assert.ok(text(picker(p)).indexOf(refusal[1]) >= 0, refusal[0] + ": its message shows");
    assert.strictEqual(byText(picker(p), "button", "Attach").disabled, false, refusal[0] + ": it can be tried again");
  });
});

test("a list that cannot be read says why in the dialog and offers nothing to attach", function () {
  var p = page();
  openPicker(p);
  answer(p, last(p, P + "stations.all"), refused("climate.folder_not_found", "That folder is not on this computer."));
  assert.ok(text(picker(p)).indexOf("That folder is not on this computer.") >= 0);
  assert.strictEqual(byText(picker(p), "button", "Attach").disabled, true);
});

test("a change to the site reads the stations again and keeps the selection", function () {
  var p = opened();
  click(rowButton(p, FAR));
  p.revision = 2; p.site = Object.assign({}, SITE, { elevation_m: 90 }); p.publish();
  assert.strictEqual(named(p, P + "stations.all").length, 2);
  stations(p, STATIONS);
  assert.deepStrictEqual(selectedRow(p), [FAR.key]);
});

test("the station reads and the attach carry no station value beyond its name, location and elevation", function () {
  var p = opened();
  click(rowButton(p, SECOND));
  commit(p);
  answer(p, last(p, P + "climate.attach_station"), { status: "completed", effect: "committed", revision: 2,
    value: { state: "complete", missing: [], edited_cells: [], limit_check: SECOND.limit_check } });
  var picked = p.sent.filter(function (m) { return m.payload && m.payload.name && m.payload.name.indexOf(P) === 0; });
  picked.forEach(function (m) {
    assert.ok([P + "folders.list", P + "stations.all", P + "climate.attach_station"].indexOf(m.payload.name) >= 0,
      m.payload.name);
    if (m.payload.name === P + "climate.attach_station") {
      assert.deepStrictEqual(Object.keys(m.payload.params).sort(), ["folder_id", "station_key"]);
    }
  });
  p.received.filter(function (m) { return /\.result$/.test(m.type); }).forEach(function (m) {
    var value = m.payload.outcome.value || {};
    (value.stations || []).forEach(function (s) { assert.deepStrictEqual(Object.keys(s), ROW_KEYS); });
    assert.ok(!/monthly|peak_loads|as_read|daily_temp_swing|wind_speed/.test(JSON.stringify(value)));
  });
});

test("the keyboard moves along the list with the arrows, one row in the tab order, and Tab reaches Attach",
  function () {
    var p = opened();
    var first = rowButton(p, NEAR);
    first.focus();
    assert.strictEqual(key(first, "ArrowDown").prevented, true);
    assert.deepStrictEqual(selectedRow(p), [SECOND.key]);
    assert.strictEqual(p.context.document.activeElement, rowButton(p, SECOND));
    key(rowButton(p, SECOND), "ArrowUp");
    assert.deepStrictEqual(selectedRow(p), [NEAR.key]);
    var reachable = all(picker(p), ".climate-picker-station").filter(function (b) {
      return b.getAttribute("tabindex") !== "-1";
    });
    assert.deepStrictEqual(reachable, [rowButton(p, NEAR)], "only the selected row takes Tab");
    var buttons = all(picker(p), "button");
    assert.ok(buttons.indexOf(byText(picker(p), "button", "Attach")) > buttons.indexOf(rowButton(p, NEAR)),
      "Attach follows the list");
  });

test("a thousand invented stations fill the list and the map, and selection follows across them", function () {
  var many = [];
  for (var i = 0; i < 1000; i += 1) {
    many.push(station(["XA", "XB", "XC", "XD"][i % 4], "Station " + (1000 + i), 5 + i * 0.4, i % 300));
  }
  var p = opened(many);
  assert.strictEqual(shown(p).length, 1000);
  assert.strictEqual(markers(p).length, 1000);
  clickMarker(p, many[700]);
  assert.deepStrictEqual(selectedRow(p), [many[700].key]);
  change(select(p, "State"), "XD");
  assert.strictEqual(shown(p).length, 250);
});

test("Update from File opens the picker on the matched station", function () {
  var p = page({ climate: { edited: 0 } });
  p.panel.showTab("climate");
  tab(p).openPicker({ folder_id: SET_B.id, station_key: FAR.key });
  folders(p, [SET_A, SET_B]);
  answer(p, last(p, P + "climate.source_status"), completed({ status: "changed", folder_id: SET_B.id,
    station_key: FAR.key }));
  answer(p, last(p, P + "climate.get"), climateGet(p, 0));
  assert.deepStrictEqual(last(p, P + "stations.all").payload.params, { folder_id: SET_B.id });
  stations(p, STATIONS, SET_B);
  assert.deepStrictEqual(selectedRow(p), [FAR.key]);
});

test("Enter in the search narrows and never attaches", function () {
  var p = opened();
  var search = labelled(picker(p), "Filter stations");
  type(search, "birch");
  assert.strictEqual(key(search, "Enter").prevented, true, "the form is not submitted");
  assert.strictEqual(named(p, P + "climate.attach_station").length, 0);
});

test("a filter that hides the selected station selects the first it leaves", function () {
  var p = opened();
  change(select(p, "State"), "XC");
  assert.deepStrictEqual(selectedRow(p), [FAR.key]);
  assert.ok(footer(p).indexOf("Dune Airfield") === 0);
  type(labelled(picker(p), "Filter stations"), "nothing here");
  assert.deepStrictEqual(selectedRow(p), []);
  assert.strictEqual(byText(picker(p), "button", "Attach").disabled, true);
});

test("after Dataset the old rows are gone before the new list answers", function () {
  var p = page();
  openPicker(p, [SET_A, SET_B], SET_A.id);
  stations(p, STATIONS);
  change(select(p, "Dataset"), SET_B.id);
  assert.deepStrictEqual(shown(p), []);
  assert.strictEqual(byText(picker(p), "button", "Attach").disabled, true);
});

test("distances and elevations follow the unit preference", function () {
  var p = opened();
  var state = Object.assign({}, p.panel.state);
  p.receive("panel.snapshot", { product: "PH-Composer", version: "0.1.0-dev", session: p.session, revision: p.revision,
    file_name: "house.skp", edit_path: [], sections: state.sections,
    preferences: { unit_system: "IP", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } });
  assert.ok(/mi$/.test(text(row(p, NEAR).querySelector(".col-distance"))), text(row(p, NEAR)));
  assert.ok(/^\+36(\.\d+)?\u00a0ft$/.test(text(row(p, NEAR).querySelector(".col-elevation"))), text(row(p, NEAR)));
});

test("Replace over a climate entered by hand compares it as entered by hand, not checked", function () {
  var p = page({ climate: { edited: 0 } });
  p.panel.showTab("climate");
  click(pane(p).querySelector("[data-card='phius']"));
  click(byText(pane(p), "button", "Replace…"));
  folders(p, [SET_A]);
  answer(p, last(p, P + "climate.source_status"), completed({ status: "not_applicable", folder_id: null,
    station_key: null }));
  answer(p, last(p, P + "climate.get"), completed({ state: "complete", missing: [], edited_cells: [],
    limit_check: { verdict: "not_checked", reason: "no_station_coordinates", distance_km: null,
      elevation_difference_m: null, distance_ok: null, elevation_ok: null },
    climate: { id: "climate-1", values: { name: "Typed values", origin: "hand", station_latitude_deg: null,
      station_longitude_deg: null, station_elevation_m: 80, provenance: { dataset_name: null } } } }));
  stations(p, STATIONS);
  var compared = all(picker(p).querySelector(".climate-picker-compare"), "tr").map(text);
  assert.strictEqual(compared[1], "NowTyped valuesEntered by hand——Not checked");
});

test("Replace without a site explains and offers Set Location; the picker does not open without one", function () {
  var p = page({ climate: { edited: 0 }, site: { latitude_deg: null, longitude_deg: null, elevation_m: null,
    climate_zone: null, hours_from_utc: null, climate_zone_label: null, state: "not_set" } });
  p.panel.showTab("climate");
  click(pane(p).querySelector("[data-card='phius']"));
  click(byText(pane(p), "button", "Replace…"));
  assert.strictEqual(picker(p), null);
  var explained = pane(p).querySelector(".climate-attached-explain").querySelector(".phc-bubble");
  assert.strictEqual(explained.hidden, false);
  tab(p).openPicker(null);
  assert.strictEqual(picker(p), null);
  click(byText(explained, "button", "Set Location…"));
  assert.strictEqual(explained.hidden, true);
  var setLocation = p.context.document.querySelector(".climate-set-location");
  assert.ok(setLocation && !setLocation.hidden, "Set Location opens");
});

test("in Replace only the Model's own climate read carries values; the station reads and Replace do not", function () {
  var p = openReplace(2);
  click(rowButton(p, SECOND));
  commit(p);
  var reads = [P + "folders.list", P + "stations.all", P + "climate.source_status", P + "climate.get",
    P + "climate.replace_station"];
  p.sent.filter(function (m) { return m.payload && m.payload.name && m.payload.name.indexOf(P) === 0; })
    .forEach(function (m) {
      assert.ok(reads.indexOf(m.payload.name) >= 0, m.payload.name);
      if (m.payload.name === P + "climate.replace_station") {
        assert.deepStrictEqual(Object.keys(m.payload.params).sort(), ["folder_id", "station_key"]);
      }
    });
  var climateIds = named(p, P + "climate.get").map(function (m) { return m.payload.request_id; });
  p.received.filter(function (m) { return /\.result$/.test(m.type) && climateIds.indexOf(m.payload.request_id) < 0; })
    .forEach(function (m) {
      assert.ok(!/monthly|peak_loads|as_read|daily_temp_swing|wind_speed/.test(JSON.stringify(m.payload.outcome)));
    });
});

test("a change while Replace is out is read once it answers, and Replace waits for that read", function () {
  var p = openReplace(2);
  click(rowButton(p, SECOND));
  commit(p);
  var replace = last(p, P + "climate.replace_station");
  p.revision = 2; p.publish();
  assert.strictEqual(named(p, P + "climate.get").length, 1, "nothing is read while Replace is out");
  answer(p, replace, refused("revision.stale", "The Model changed since it was read."));
  assert.strictEqual(named(p, P + "climate.get").length, 2, "the climate is read again");
  assert.strictEqual(byText(picker(p), "button", "Replace").disabled, true, "Replace waits for it");
  answer(p, last(p, P + "climate.get"), climateGet(p, 5));
  assert.ok(footer(p).indexOf("has 5 edited values") >= 0, "the new edits are named before a retry");
  assert.strictEqual(byText(picker(p), "button", "Replace").disabled, false);
});

test("a search that matched nothing selects again when it matches", function () {
  var p = opened();
  var search = labelled(picker(p), "Filter stations");
  type(search, "nothing here");
  assert.deepStrictEqual(selectedRow(p), []);
  type(search, "birch");
  assert.deepStrictEqual(selectedRow(p), [SECOND.key]);
  assert.strictEqual(rowButton(p, SECOND).getAttribute("tabindex"), "0");
  assert.strictEqual(byText(picker(p), "button", "Attach").disabled, false);
});

test("a folder not read whole says so in the dialog", function () {
  var p = page();
  openPicker(p);
  answer(p, last(p, P + "stations.all"), completed({ folder_id: SET_A.id, dataset_name: SET_A.name, complete: false,
    total: STATIONS.length, stations: STATIONS }));
  assert.ok(text(picker(p).querySelector(".climate-picker-notice")).indexOf("This folder was not read whole") === 0);
  assert.strictEqual(picker(p).querySelector(".climate-picker-notice").hidden, false);
});

test("a dataset that could not be remembered says so, and its stations still show", function () {
  var p = page();
  openPicker(p, [SET_A, SET_B], SET_A.id);
  stations(p, STATIONS);
  change(select(p, "Dataset"), SET_B.id);
  answer(p, last(p, P + "folders.remember_dataset"), refused("climate.settings_unreadable", "The settings file " +
    "cannot be written."));
  stations(p, [FAR], SET_B);
  assert.deepStrictEqual(shown(p), [FAR.key]);
  assert.ok(text(picker(p).querySelector(".climate-picker-notice")).indexOf("The dataset was not remembered for " +
    "next time: The settings file cannot be written.") >= 0);
});

test("a station renamed in its file shows its new name after a re-read", function () {
  var p = opened();
  p.revision = 2; p.site = Object.assign({}, SITE, { elevation_m: 90 }); p.publish();
  stations(p, STATIONS.map(function (s) {
    return s === NEAR ? Object.assign({}, s, { name: "Alder Field East" }) : s;
  }));
  assert.strictEqual(rowButton(p, NEAR).textContent, "Alder Field East");
});

test("in Replace, a climate replaced elsewhere moves the Attached mark", function () {
  var p = openReplace(0);
  assert.ok(text(row(p, NEAR)).indexOf("Attached") >= 0);
  p.revision = 2; p.publish();
  assert.strictEqual(named(p, P + "climate.source_status").length, 2, "where the attached station is, read again");
  answer(p, last(p, P + "climate.source_status"), completed({ status: "found", folder_id: SET_A.id,
    station_key: SECOND.key }));
  assert.strictEqual(text(row(p, NEAR)).indexOf("Attached"), -1);
  assert.ok(text(row(p, SECOND)).indexOf("Attached") >= 0);
});
