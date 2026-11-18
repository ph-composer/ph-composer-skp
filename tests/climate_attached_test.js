"use strict";
/* The Phius climate data pane with a climate in the Model: every table read from `climate.get`, the limit
   block's states, edited cells marked from `edited_cells` with the file's value, Restore, Clear and the wind speed
   each one action, Where this lives from `source_status` with Update from File, and Replace explaining with no
   folder. The page is the shipped index.html with the real panel. Every station and value is invented. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var P = "ph_composer.climate.";
var SITE = { latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15, hours_from_utc: -5,
  climate_zone_label: "5", state: "set" };
var NO_SITE = { latitude_deg: null, longitude_deg: null, elevation_m: null, climate_zone: null, hours_from_utc: null,
  climate_zone_label: null, state: "not_set" };
var FOLDER = { id: "climate_folder_aaaaaaaaaaaa", name: "Invented Set", display_location: "~/Climate/Invented",
  found: true, format: "phius_station_file", station_count: 12, state_count: 2, files_not_read: [],
  files_not_read_total: 0, complete: true };
var MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
var MONTHLY_ROWS = ["air_c", "dewpoint_c", "sky_c", "rad_north_kwh_m2", "rad_east_kwh_m2", "rad_south_kwh_m2",
  "rad_west_kwh_m2", "rad_global_kwh_m2"];
var PEAK_ROWS = ["air_c", "dewpoint_c", "sky_c", "rad_north_w_m2", "rad_east_w_m2", "rad_south_w_m2",
  "rad_west_w_m2", "rad_global_w_m2"];
var PASS = { verdict: "pass", reason: null, distance_km: 18, elevation_difference_m: 11, distance_ok: true,
  elevation_ok: true };

function completed(value) { return { status: "completed", value: value }; }
function refused(code, message) { return { status: "refused", code: code, message: message, effect: "none" }; }

/* An invented station's values: each row a smooth year, the peaks a few round numbers. */
function grid() {
  var monthly = {}, peaks = {};
  MONTHLY_ROWS.forEach(function (row, r) {
    monthly[row] = MONTHS.map(function (_, m) { return Math.round((r * 10 + Math.sin(m / 2) * 12) * 10) / 10; });
  });
  ["heat_1", "heat_2", "cool_1"].forEach(function (name, c) {
    peaks[name] = {};
    PEAK_ROWS.forEach(function (row, r) { peaks[name][row] = c * 20 + r * 5 - 10; });
  });
  return { monthly: monthly, peak_loads: peaks };
}
/* `climate.get` for a station attached from FOLDER, with `edits` ([row, column, value]) applied over its file. */
function station(options) {
  options = options || {};
  var read = grid(), now = JSON.parse(JSON.stringify(read)), cells = [];
  var scalars = { station_elevation_m: 95, daily_temp_swing_k: 11.2 };
  (options.edits || []).forEach(function (edit) {
    if (edit[1] === null) scalars[edit[0]] = edit[2];
    else if (MONTHS.indexOf(edit[1]) >= 0) now.monthly[edit[0]][MONTHS.indexOf(edit[1])] = edit[2];
    else now.peak_loads[edit[1]][edit[0]] = edit[2];
    cells.push({ row: edit[0], column: edit[1] });
  });
  var values = { name: "Alder Field", origin: "station", station_latitude_deg: 42.61, station_longitude_deg: -73.92,
    station_elevation_m: scalars.station_elevation_m, daily_temp_swing_k: scalars.daily_temp_swing_k,
    wind_speed_m_s: 3.9, monthly: now.monthly,
    peak_loads: now.peak_loads, as_read: { station_elevation_m: 95, daily_temp_swing_k: 11.2, monthly: read.monthly,
      peak_loads: read.peak_loads },
    provenance: { dataset_name: FOLDER.name, station_name: "ALDER_FIELD", state: "XA", source_type: "phius_approved",
      source_checksum: options.checksum || "a".repeat(64) } };
  return { state: options.state || "complete", missing: options.missing || [], edited_cells: cells,
    limit_check: options.check || PASS, climate: { id: "clm_AAAAAAAAAAAA", values: values } };
}

function page(options) {
  options = options || {};
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/climate/section"]);
  var notices = [], notify = modules.panel.notify;
  modules.panel.notify = function (message, tone) {
    notices.push([message, tone]); return notify.apply(this, arguments);
  };
  var p = { context: context, panel: modules.panel, sent: sent, notices: notices, session: "session-a", revision: 1,
    site: options.site || SITE, climate: options.climate || "complete", units: "SI" };
  p.receive = function (type, payload) { p.panel.receive({ type: type, payload: payload }); };
  p.publish = function () {
    var sections = {};
    sections[P + "site"] = completed(p.site);
    sections[P + "design_temperatures"] = completed({ heating_99_c: null, cooling_1_c: null,
      design_temperature_source: null, state: "not_set", warning: null });
    sections[P + "summary"] = completed({ site: p.site.state, design_temperatures: { state: "not_set", warning: null },
      climate: { state: p.climate, origin: p.climate === "none" ? null : "station", verdict: "pass", edited: false } });
    p.receive("panel.snapshot", { product: "PH-Composer", version: "0.1.0-dev", session: p.session,
      revision: p.revision, file_name: "house.skp", edit_path: [], sections: sections,
      preferences: { unit_system: p.units, dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } });
  };
  p.publish();
  p.panel.showTab("climate");
  click(pane(p).querySelector("[data-card='phius']"));
  return p;
}
function pane(p) { return p.context.document.querySelector("[data-pane='climate']"); }
function attached(p) { return pane(p).querySelector(".climate-attached"); }
function all(root, selector) { return root.querySelectorAll(selector); }
function text(node) { return node.textContent + node.children.map(text).join(""); }
function byText(root, selector, words) {
  return all(root, selector).filter(function (node) { return text(node) === words; })[0] || null;
}
function click(node) { node.listeners.click({ preventDefault: function () {}, currentTarget: node }); }
function named(p, name) {
  return p.sent.filter(function (message) { return message.payload && message.payload.name === name; });
}
function last(p, name) { var found = named(p, name); return found[found.length - 1]; }
function answer(p, message, outcome) {
  var slot = message.type === "action.invoke" ? "action.result" : "query.result";
  p.receive(slot, { request_id: message.payload.request_id, session: p.session, outcome: outcome });
}
/* Answers the pane's three reads. */
function load(p, got, source, folders) {
  answer(p, last(p, P + "folders.list"), completed({ folders: folders || [FOLDER], last_dataset_id: null }));
  answer(p, last(p, P + "climate.get"), completed(got || station()));
  answer(p, last(p, P + "climate.source_status"), completed(source || { status: "found", folder_id: FOLDER.id,
    station_key: "XA/ALDER_FIELD-mon.txt" }));
}
function section(p, title) {
  return all(attached(p), ".climate-attached-section").filter(function (node) {
    return node.querySelector("h3").textContent === title;
  })[0];
}
function rows(node) {
  return all(node, "tr").map(function (row) { return all(row, "th").concat(all(row, "td")).map(text); });
}
function where(p) {
  var list = section(p, "Where this lives").querySelector("dl"), out = {};
  all(list, "dt").forEach(function (term, index) { out[text(term)] = text(all(list, "dd")[index]); });
  return out;
}
function cellsEdited(p) {
  return all(attached(p), ".is-edited").filter(function (node) { return node.tagName === "td"; });
}

test("a station-origin climate shows every table, the limit block and Cooling 2 as not part of the file", function () {
  var p = page();
  assert.strictEqual(named(p, P + "climate.get").length, 1, "read when the pane is shown");
  assert.strictEqual(named(p, P + "climate.source_status").length, 1);
  load(p);
  var heading = attached(p).querySelector(".climate-attached-heading");
  assert.strictEqual(heading.querySelector("h2").textContent, "Alder Field");
  var place = text(heading.querySelector(".climate-attached-place"));
  assert.ok(/^Invented Set · 42.610° N, 73.920° W · 95 m$/.test(place), place);
  assert.deepStrictEqual(all(heading, ".climate-data-chip").map(text), ["Pass"]);
  assert.deepStrictEqual(rows(section(p, "Phius limit check")).slice(1), [["Distance", "18 km", "50 mi", "Pass"],
    ["Elevation", "11 m", "400 ft", "Pass"]]);
  var temperatures = rows(section(p, "Monthly temperatures"));
  assert.deepStrictEqual(temperatures[0].slice(0, 3), ["Temperature °C", "Jan", "Feb"]);
  assert.deepStrictEqual(temperatures.map(function (row) { return row[0]; }), ["Temperature °C", "Air", "Dewpoint",
    "Sky", "Ground"]);
  assert.strictEqual(temperatures[1].length, 13, "twelve months beside the row name");
  assert.deepStrictEqual(temperatures[4], ["Ground", "Not part of a Phius station file"]);
  assert.deepStrictEqual(rows(section(p, "Monthly radiation")).map(function (row) { return row[0]; }),
    ["Radiation kWh/m²", "North", "East", "South", "West", "Global"]);
  var peaks = rows(section(p, "Peak loads · design conditions"));
  assert.deepStrictEqual(peaks.map(function (row) { return row[0]; }), ["Case", "Heating 1", "Heating 2", "Cooling 1",
    "Cooling 2"]);
  assert.strictEqual(peaks[0].length, 9, "the eight values of each case");
  assert.deepStrictEqual(peaks[4], ["Cooling 2", "Not part of a Phius station file"]);
  assert.strictEqual(all(attached(p), ".is-edited").length, 0);
  assert.ok(/Prefilled with the mean of the file's January and July/.test(text(section(p, "Station values"))));
  assert.strictEqual(attached(p).querySelector(".climate-attached-notice"), null, "no line above the values");
});

test("a failing verdict, a changed site and no site each show their limit block state", function () {
  var p = page();
  var fail = { verdict: "fail", reason: null, distance_km: 66, elevation_difference_m: 310, distance_ok: true,
    elevation_ok: false };
  load(p, station({ check: fail }));
  var notice = attached(p).querySelector(".climate-attached-notice");
  assert.strictEqual(text(notice), "Outside the Phius limits: 310 m higher than the site. Phius asks for a " +
    "custom dataset here unless an exception applies. The Export report says the same.");
  assert.deepStrictEqual(all(attached(p).querySelector(".climate-attached-heading"), ".climate-data-chip").map(text),
    ["Outside Phius limits"]);
  assert.deepStrictEqual(rows(section(p, "Phius limit check"))[2], ["Elevation", "310 m", "400 ft", "Fail"]);

  // A site change bumps the revision: the climate is read again and the check follows (J7); the source is not.
  p.site = Object.assign({}, SITE, { elevation_m: 300 }); p.revision = 2; p.publish();
  assert.strictEqual(named(p, P + "climate.get").length, 2);
  assert.strictEqual(named(p, P + "climate.source_status").length, 1, "the disk is not read on a revision");
  answer(p, last(p, P + "climate.get"), completed(station()));
  assert.strictEqual(attached(p).querySelector(".climate-attached-notice"), null);

  p.site = NO_SITE; p.revision = 3; p.publish();
  answer(p, last(p, P + "climate.get"), completed(station({ check: { verdict: "not_checked", reason: "no_site",
    distance_km: null, elevation_difference_m: null, distance_ok: null, elevation_ok: null } })));
  assert.strictEqual(text(section(p, "Phius limit check").querySelector("p")),
    "Not checked: set the site location to check the station.");
  assert.strictEqual(section(p, "Phius limit check").querySelector("table"), null);
});

test("edited cells are marked with the file's value; Restore sends one action; the wind speed marks nothing",
  function () {
  var p = page();
  load(p, station({ edits: [["air_c", "jan", -6], ["air_c", "heat_1", -15]] }));
  var marked = cellsEdited(p);
  assert.strictEqual(marked.length, 2);
  assert.strictEqual(marked[0].getAttribute("data-tooltip"), "Edited. The station file reads 0 °C.");
  assert.strictEqual(marked[0].getAttribute("aria-label"), "-6 °C, edited; the station file reads 0 °C");
  assert.deepStrictEqual(all(attached(p).querySelector(".climate-attached-heading"), ".climate-data-chip").map(text),
    ["Pass", "Edited"]);
  var line = attached(p).querySelector(".climate-attached-notice");
  assert.ok(/^2 values differ from the station file: Air, January \(file 0 °C\), Heating 1 air \(file -10 °C\)\./
    .test(text(line.querySelector("p"))), text(line));
  click(byText(line, "button", "Restore Original Values"));
  var restore = named(p, P + "climate.restore_original");
  assert.strictEqual(restore.length, 1);
  assert.strictEqual(restore[0].type, "action.invoke");
  assert.deepStrictEqual(Object.keys(restore[0].payload.params.expected_values).sort(), ["daily_temp_swing_k",
    "monthly", "name", "peak_loads", "station_elevation_m", "station_latitude_deg", "station_longitude_deg",
    "wind_speed_m_s"]);
  answer(p, restore[0], { status: "completed", effect: "committed", revision: 2, value: {} });
  p.revision = 2; p.publish();
  answer(p, last(p, P + "climate.get"), completed(station()));
  assert.strictEqual(all(attached(p), ".is-edited").length, 0);

  var wind = section(p, "Station values").querySelector("input");
  wind.value = "4.5";
  wind.listeners.input({ target: wind });
  wind.listeners.keydown({ key: "Enter", preventDefault: function () {}, stopPropagation: function () {} });
  var saved = named(p, P + "climate.save_values");
  assert.strictEqual(saved.length, 1);
  assert.strictEqual(saved[0].payload.params.values.wind_speed_m_s, 4.5);
  assert.strictEqual(saved[0].payload.params.expected_values.wind_speed_m_s, 3.9);
  assert.deepStrictEqual(saved[0].payload.params.values.monthly, station().climate.values.monthly,
    "every other value is sent as read");
  answer(p, saved[0], { status: "completed", effect: "committed", revision: 3, value: {} });
  p.revision = 3; p.publish();
  var after = station(); after.climate.values.wind_speed_m_s = 4.5;
  answer(p, last(p, P + "climate.get"), completed(after));
  assert.strictEqual(all(attached(p), ".is-edited").length, 0, "a wind-speed change marks nothing");
  assert.strictEqual(attached(p).querySelector(".climate-attached-notice"), null);
});

test("a refused write says why and reads the climate again", function () {
  var p = page();
  load(p, station({ edits: [["sky_c", "mar", 1]] }));
  click(byText(attached(p), "button", "Restore Original Values"));
  answer(p, last(p, P + "climate.restore_original"), refused("target.changed",
    "The climate changed since it was read."));
  assert.deepStrictEqual(p.notices, [["The climate changed since it was read.", "error"]]);
  assert.strictEqual(named(p, P + "climate.get").length, 2);
});

test("source found, changed and not on this computer each show their line; changed offers Update from File",
  function () {
    var p = page();
    load(p);
    assert.ok(/^Source found Invented Set · the station file matches/.test(where(p)["On this computer"]));
    assert.strictEqual(byText(attached(p), "button", "Update from File…"), null);

    var q = page();
    load(q, station(), { status: "changed", folder_id: FOLDER.id, station_key: "XA/ALDER_FIELD-mon.txt" });
    assert.ok(/^Source changed Invented Set · the station file differs .* Nothing updates on its own\./
      .test(where(q)["On this computer"]));
    assert.deepStrictEqual(all(attached(q).querySelector(".climate-attached-heading"), ".climate-data-chip").map(text),
      ["Pass", "Source changed"]);
    click(byText(attached(q), "button", "Update from File…"));
    var picker = q.context.document.querySelector(".climate-picker");
    assert.ok(picker && !picker.hidden, "the picker opens in Replace");
    answer(q, last(q, P + "folders.list"), completed({ folders: [FOLDER], last_dataset_id: null }));
    answer(q, last(q, P + "climate.source_status"), completed({ status: "changed", folder_id: FOLDER.id,
      station_key: "XA/ALDER_FIELD-mon.txt" }));
    answer(q, last(q, P + "climate.get"), completed(station()));
    var reads = named(q, P + "stations.all");
    assert.deepStrictEqual(reads[reads.length - 1].payload.params, { folder_id: FOLDER.id });

    var r = page();
    load(r, station(), { status: "not_on_this_computer", folder_id: null, station_key: null }, []);
    assert.strictEqual(where(r)["On this computer"], "Not on this computer Nothing is missing from the Model. " +
      "Replace will ask for a climate data folder.");
    [p, q, r].forEach(function (one) { assert.deepStrictEqual(one.notices, [], "no notice for the source"); });
  });

test("with no folder Replace explains and offers Choose Climate Data Folder and Enter Values by Hand", function () {
  var p = page();
  load(p, station(), { status: "not_on_this_computer", folder_id: null, station_key: null }, []);
  var replace = byText(pane(p), "button", "Replace…");
  assert.ok(/primary/.test(replace.className), "Replace is the page header's primary");
  assert.strictEqual(replace.disabled, false);
  click(replace);
  assert.strictEqual(p.context.document.querySelector(".climate-picker"), null);
  var bubble = pane(p).querySelector(".climate-attached-explain").querySelector(".phc-bubble");
  assert.strictEqual(bubble.hidden, false);
  assert.ok(/no climate data folder on this computer/.test(text(bubble)));
  assert.strictEqual(byText(bubble, "button", "Enter Values by Hand…").disabled, true);
  click(byText(bubble, "button", "Choose Climate Data Folder…"));
  assert.strictEqual(named(p, P + "folders.add").length, 1, "the dialog opens and starts Add Folder");
});

test("Clear is one action with no confirm, from the overflow menu; Edit Values waits with its reason", function () {
  var p = page();
  load(p);
  var heading = pane(p).querySelector(".phc-heading");
  var edit = byText(heading, "button", "Edit Values…");
  assert.strictEqual(edit.disabled, true);
  assert.ok(all(heading, "[aria-label='Why Edit Values is unavailable']").length);
  var menu = all(heading, "[aria-label='More climate actions']")[0];
  click(menu);
  click(byText(heading, "button", "Clear"));
  var cleared = named(p, P + "climate.clear");
  assert.strictEqual(cleared.length, 1);
  assert.deepStrictEqual(Object.keys(cleared[0].payload.params), ["expected_values"]);
  var open = all(p.context.document.body, "dialog").filter(function (node) { return !node.hidden; });
  assert.strictEqual(open.length, 0, "no confirm");
  answer(p, cleared[0], { status: "completed", effect: "committed", revision: 2, value: {} });
  p.climate = "none"; p.revision = 2; p.publish();
  answer(p, last(p, P + "folders.list"), completed({ folders: [FOLDER], last_dataset_id: null }));
  assert.strictEqual(pane(p).querySelector(".climate-phius").getAttribute("data-state"), "ready");
  assert.strictEqual(byText(pane(p).querySelector(".phc-heading"), "button", "Replace…"), null);
  assert.strictEqual(menu.closest(".phc-bubble-anchor").hidden, true, "the overflow goes with the climate");
});

test("every value follows the unit preference", function () {
  var p = page();
  p.units = "IP"; p.publish();
  load(p, station({ edits: [["air_c", "jan", -6]] }));
  assert.deepStrictEqual(rows(section(p, "Phius limit check")).slice(1).map(function (row) { return row.slice(0, 3); }),
    [["Distance", "11.2 mi", "50 mi"], ["Elevation", "36.09 ft", "400 ft"]]);
  assert.strictEqual(rows(section(p, "Monthly temperatures"))[0][0], "Temperature °F");
  assert.ok(/^Radiation kBtu\/ft²|^Radiation Btu\/ft²/.test(rows(section(p, "Monthly radiation"))[0][0]),
    rows(section(p, "Monthly radiation"))[0][0]);
  assert.ok(/°F/.test(cellsEdited(p)[0].getAttribute("data-tooltip")));
  assert.ok(/ft$/.test(text(all(section(p, "Station values"), "dd")[0])));
  p.units = "SI"; p.publish();
  assert.strictEqual(rows(section(p, "Monthly temperatures"))[0][0], "Temperature °C");
});

test("an edited station elevation, daily swing and peak value are marked with the file's value", function () {
  var p = page();
  load(p, station({ edits: [["station_elevation_m", null, 99], ["daily_temp_swing_k", null, 12],
    ["sky_c", "cool_1", 3]] }));
  var facts = all(section(p, "Station values"), "dd").filter(function (node) {
    return /is-edited/.test(node.className);
  });
  assert.deepStrictEqual(facts.map(function (node) { return node.getAttribute("data-tooltip"); }), [
    "Edited. The station file reads 95\u00a0m.", "Edited. The station file reads 11.2\u00a0K."]);
  var peak = cellsEdited(p);
  assert.strictEqual(peak.length, 1);
  assert.strictEqual(peak[0].getAttribute("data-tooltip"), "Edited. The station file reads 40\u00a0°C.");
  assert.strictEqual(peak[0].getAttribute("tabindex"), "0", "an edited cell takes the focus, so its value is read");
  var line = text(attached(p).querySelector(".climate-attached-notice"));
  assert.strictEqual(line.indexOf("3 values differ from the station file: Station elevation (file 95\u00a0m), " +
    "Daily temperature swing (file "), 0, line);
});

test("a wind speed being typed survives a repaint, which waits for the draft to end", function () {
  var p = page();
  load(p);
  var wind = section(p, "Station values").querySelector("input");
  wind.value = "5";
  wind.listeners.input({ target: wind });
  p.revision = 2; p.publish();
  answer(p, last(p, P + "climate.get"), completed(station({ edits: [["air_c", "jan", -6]] })));
  assert.strictEqual(section(p, "Station values").querySelector("input"), wind);
  assert.strictEqual(wind.value, "5", "the draft is kept");
  assert.strictEqual(cellsEdited(p).length, 0, "the repaint waits");
  wind.listeners.keydown({ key: "Escape", preventDefault: function () {}, stopPropagation: function () {} });
  assert.strictEqual(cellsEdited(p).length, 1, "and runs once the draft ends");
  assert.strictEqual(named(p, P + "climate.save_values").length, 0);
});

test("the source is looked for again after the picker closes, and a failed look says so", function () {
  var p = page();
  load(p);
  click(byText(pane(p), "button", "Replace…"));
  var picker = p.context.document.querySelector(".climate-picker");
  assert.ok(picker && !picker.hidden);
  click(byText(picker, "button", "Cancel"));
  assert.strictEqual(named(p, P + "climate.source_status").filter(function (m) {
    return /:climate_attached_source:/.test(m.payload.request_id);
  }).length, 2, "read again when the picker closes");
  answer(p, last(p, P + "climate.source_status"), refused("climate.settings_unreadable",
    "The settings file is damaged."));
  assert.strictEqual(where(p)["On this computer"], "The station file could not be looked for: The settings file is " +
    "damaged.");
});

test("a climate entered by hand has no edits, no file to look for and its check not run", function () {
  var p = page();
  var hand = station();
  Object.assign(hand.climate.values, { name: "Typed values", origin: "hand", station_latitude_deg: null,
    station_longitude_deg: null, as_read: null, provenance: { dataset_name: null, station_name: null, state: null,
      source_type: "user_defined", source_checksum: null } });
  hand.limit_check = { verdict: "not_checked", reason: "no_station_coordinates", distance_km: null,
    elevation_difference_m: null, distance_ok: null, elevation_ok: null };
  load(p, hand, { status: "not_applicable", folder_id: null, station_key: null });
  assert.strictEqual(text(attached(p).querySelector(".climate-attached-place")), "Entered by hand");
  assert.strictEqual(text(section(p, "Phius limit check").querySelector("p")),
    "Not checked, entered by hand: the climate has no station coordinates.");
  assert.strictEqual(where(p)["On this computer"], "Entered by hand; there is no station file to look for.");
  assert.ok(/a station file does not give one/.test(text(section(p, "Station values"))));
});

test("an incomplete climate lists what is missing above the values, the longest lists cut short", function () {
  var p = page();
  var missing = [{ row: "air_c", columns: ["jan", "feb"] }, { row: "wind_speed_m_s", columns: [] },
    { row: "rad_north_w_m2", columns: ["heat_2"] }, { row: "sky_c", columns: ["dec"] },
    { row: "dewpoint_c", columns: ["mar"] }, { row: "daily_temp_swing_k", columns: [] }];
  load(p, station({ state: "incomplete", missing: missing }));
  assert.deepStrictEqual(all(attached(p).querySelector(".climate-attached-heading"), ".climate-data-chip").map(text),
    ["Pass", "Incomplete"]);
  assert.strictEqual(text(attached(p).querySelector(".climate-attached-notice")), "Incomplete: Air (Jan, Feb); " +
    "Average wind speed; North radiation (Heating 2); Sky (Dec); and 2 more. Export leaves the climate out until it " +
    "is complete.");
  assert.ok(/^Not export yet/.test(where(p)["Ready for"]));
});

test("folders that cannot be read: Replace says so rather than that there is no folder", function () {
  var p = page();
  answer(p, last(p, P + "folders.list"), refused("climate.settings_unreadable", "The settings file is damaged."));
  answer(p, last(p, P + "climate.get"), completed(station()));
  click(byText(pane(p), "button", "Replace…"));
  var bubble = pane(p).querySelector(".climate-attached-explain").querySelector(".phc-bubble");
  assert.strictEqual(bubble.hidden, false);
  assert.ok(/could not be read: The settings file is damaged\./.test(text(bubble)));
  assert.strictEqual(byText(bubble, "button", "Choose Climate Data Folder…"), null);
});

test("the header's climate actions show only on the Phius card", function () {
  var p = page();
  load(p);
  var heading = pane(p).querySelector(".phc-heading");
  assert.ok(byText(heading, "button", "Replace…"));
  click(pane(p).querySelector("[data-card='site']"));
  assert.strictEqual(byText(heading, "button", "Replace…"), null);
  assert.strictEqual(byText(heading, "button", "Edit Values…"), null);
  assert.strictEqual(all(heading, "[aria-label='More climate actions']")[0].closest(".phc-bubble-anchor").hidden, true);
  assert.ok(byText(heading, "button", "Set Location…"));
});

function typeWind(p, value) {
  var wind = section(p, "Station values").querySelector("input");
  wind.value = value;
  wind.listeners.input({ target: wind });
  return wind;
}
function press(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopPropagation: function () {} });
}

test("a wind speed is guarded by what the pane showed when typing began, so a change meanwhile refuses", function () {
  var p = page();
  load(p);
  var wind = typeWind(p, "5");
  var changed = station(); changed.climate.values.wind_speed_m_s = 7;
  p.revision = 2; p.publish();
  answer(p, last(p, P + "climate.get"), completed(changed));
  press(wind, "Enter");
  var saved = last(p, P + "climate.save_values");
  assert.strictEqual(saved.payload.params.values.wind_speed_m_s, 5);
  assert.strictEqual(saved.payload.params.expected_values.wind_speed_m_s, 3.9, "the value seen when typing began");
});

test("the same wind speed retyped with Enter lets a held repaint through", function () {
  var p = page();
  load(p);
  var wind = typeWind(p, "3.9");
  p.revision = 2; p.publish();
  answer(p, last(p, P + "climate.get"), completed(station({ edits: [["air_c", "jan", -6]] })));
  assert.strictEqual(cellsEdited(p).length, 0, "held while the draft is open");
  press(wind, "Enter");
  assert.strictEqual(named(p, P + "climate.save_values").length, 0);
  assert.strictEqual(cellsEdited(p).length, 1);
});

test("a wind draft left invalid is dropped when the climate is cleared, so another climate shows", function () {
  var p = page();
  load(p);
  var wind = typeWind(p, "abc");
  press(wind, "Enter");
  p.climate = "none"; p.revision = 2; p.publish();
  p.climate = "complete"; p.revision = 3; p.publish();
  var next = station(); next.climate.values.name = "Birch Point";
  answer(p, last(p, P + "climate.get"), completed(next));
  assert.strictEqual(attached(p).querySelector(".climate-attached-heading").querySelector("h2").textContent,
    "Birch Point");
  assert.strictEqual(wind.value, "3.9");
});

test("Restore pressed as a wind speed saves on blur runs after that save, guarded by the climate read again",
  function () {
    var p = page();
    load(p, station({ edits: [["air_c", "jan", -6]] }));
    var wind = typeWind(p, "5");
    var restore = byText(attached(p), "button", "Restore Original Values");
    wind.listeners.blur({ target: wind });
    assert.ok(restore.parentNode, "the button is still on the page for the click that blurred the field");
    click(restore);
    assert.strictEqual(named(p, P + "climate.save_values").length, 1);
    assert.strictEqual(named(p, P + "climate.restore_original").length, 0, "waits for the save");
    answer(p, last(p, P + "climate.save_values"), { status: "completed", effect: "committed", revision: 2, value: {} });
    p.revision = 2; p.publish();
    var saved = station({ edits: [["air_c", "jan", -6]] }); saved.climate.values.wind_speed_m_s = 5;
    answer(p, last(p, P + "climate.get"), completed(saved));
    var restored = named(p, P + "climate.restore_original");
    assert.strictEqual(restored.length, 1);
    assert.strictEqual(restored[0].payload.params.expected_values.wind_speed_m_s, 5, "guarded by the new read");
  });

test("a failed re-read says so and shows no verdict from the last read", function () {
  var p = page();
  load(p);
  p.revision = 2; p.publish();
  answer(p, last(p, P + "climate.get"), refused("record.unreadable", "The climate record cannot be read."));
  var line = text(attached(p).querySelector(".climate-attached-notice"));
  assert.ok(/^The climate could not be read again: The climate record cannot be read\./.test(line), line);
  assert.deepStrictEqual(all(attached(p).querySelector(".climate-attached-heading"), ".climate-data-chip").map(text),
    []);
  assert.strictEqual(text(section(p, "Phius limit check").querySelector("p")),
    "Not shown: the climate could not be read again.");
  p.revision = 3; p.publish();
  answer(p, last(p, P + "climate.get"), completed(station()));
  assert.deepStrictEqual(all(attached(p).querySelector(".climate-attached-heading"), ".climate-data-chip").map(text),
    ["Pass"]);
});
