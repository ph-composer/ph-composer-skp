"use strict";
/* The values editor behind Enter Values by Hand and Edit Values: one paste fills the grid from the focused
   cell, an oversized block fills nothing, gaps and rows of twelve leave cells empty, Save waits for the name and the
   station elevation and sends the grid in SI in either unit system, Edit Values sends only what changed, a stale
   save keeps the draft, and the pane of a hand-entered climate. The page is the shipped index.html with the real
   panel. Every block, name and value is invented. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var P = "ph_composer.climate.";
var SITE = { latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15, hours_from_utc: -5,
  climate_zone_label: "5", state: "set" };
var MONTHLY = ["air_c", "rad_north_kwh_m2", "rad_east_kwh_m2", "rad_south_kwh_m2", "rad_west_kwh_m2",
  "rad_global_kwh_m2", "dewpoint_c", "sky_c"];
var PEAK = ["air_c", "rad_north_w_m2", "rad_east_w_m2", "rad_south_w_m2", "rad_west_w_m2", "rad_global_w_m2",
  "dewpoint_c", "sky_c"];
var CASES = ["heat_1", "heat_2", "cool_1"];

function completed(value) { return { status: "completed", value: value }; }

/* An invented value for grid row r, column c: distinct, short and exact in tenths. */
function invented(r, c) { return r * 20 + c + 0.5; }
/* A tab-separated block of `rows` by `columns` invented values starting at row r0, column c0, Excel's line ends. */
function block(rows, columns, r0, c0, label) {
  var lines = [];
  for (var r = 0; r < rows; r += 1) {
    var cells = [];
    for (var c = 0; c < columns; c += 1) cells.push(String(invented(r0 + r, c0 + c)));
    lines.push((label ? "Series " + r + "\t" : "") + cells.join("\t"));
  }
  return lines.join("\r\n") + "\r\n";
}
/* The values of a climate whose every grid cell holds invented(r, c). */
function full(extra) {
  var monthly = {}, peaks = { heat_1: {}, heat_2: {}, cool_1: {} };
  MONTHLY.forEach(function (key, r) {
    monthly[key] = []; for (var c = 0; c < 12; c += 1) monthly[key].push(invented(r, c));
  });
  PEAK.forEach(function (key, r) { CASES.forEach(function (name, i) { peaks[name][key] = invented(r, 12 + i); }); });
  return Object.assign({ name: "Elm Street", origin: "hand", station_latitude_deg: null, station_longitude_deg: null,
    station_elevation_m: 92, daily_temp_swing_k: 10, wind_speed_m_s: 3, monthly: monthly, peak_loads: peaks,
    as_read: null, provenance: {} }, extra || {});
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
  var p = { context: context, panel: modules.panel, sent: sent, session: "session-a", revision: 1,
    climate: options.climate || "none", units: options.units || "SI" };
  p.receive = function (type, payload) { p.panel.receive({ type: type, payload: payload }); };
  p.publish = function () {
    var sections = {};
    sections[P + "site"] = completed(SITE);
    sections[P + "design_temperatures"] = completed({ heating_99_c: null, cooling_1_c: null,
      design_temperature_source: null, state: "not_set", warning: null });
    sections[P + "summary"] = completed({ site: "set", design_temperatures: { state: "not_set", warning: null },
      climate: { state: p.climate, origin: p.climate === "none" ? null : "hand", verdict: "not_checked",
        edited: false } });
    p.receive("panel.snapshot", { product: "PH-Composer", version: "0.1.0-dev", session: p.session,
      revision: p.revision, file_name: "house.skp", edit_path: [], sections: sections,
      preferences: { unit_system: p.units, dimension_formats: {}, number_format: options.decimal ?
        { decimal: ",", group: ".", locale: "de-DE" } : { decimal: ".", locale: "en-US" } } });
  };
  p.publish();
  p.panel.showTab("climate");
  click(pane(p).querySelector("[data-card='phius']"));
  answer(p, last(p, P + "folders.list"), completed({ folders: [], last_dataset_id: null }));
  return p;
}
function pane(p) { return p.context.document.querySelector("[data-pane='climate']"); }
function editor(p) { return p.context.document.querySelector(".climate-values"); }
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
function cells(p) { return all(editor(p), "input").filter(function (input) { return Boolean(input._at); }); }
function cell(p, r, c) { return cells(p)[r * 15 + c]; }
function field(p, label) {
  return all(editor(p), "input").filter(function (n) { return n.getAttribute("aria-label") === label; })[0];
}
function type(input, value) { input.value = value; dom.dispatch(input, { type: "input" }); }
function paste(p, target, block) {
  dom.dispatch(target, new dom.ClipboardEvent("paste", { clipboardData: { "text/plain": block } }));
}
/* The form's status line, beside Save. */
function status(p) {
  return all(editor(p), ".cell-error").filter(function (n) { return n.tagName === "div"; })[0].textContent;
}
function notice(p) { return editor(p).querySelector(".climate-values-notice").textContent; }
function save(p) { return byText(editor(p), "button", "Save"); }
function submit(p) { dom.dispatch(editor(p).querySelector("form"), { type: "submit" }); }
function openHand(p) { click(byText(pane(p), "button", "Enter Values by Hand…")); }

test("a full block pasted at the first cell fills all 120 cells; elsewhere it fills from there", function () {
  var p = page();
  openHand(p);
  assert.strictEqual(cells(p).length, 120, "eight rows by twelve months and three design columns");
  paste(p, cell(p, 0, 0), block(8, 15, 0, 0));
  cells(p).forEach(function (input, index) {
    assert.strictEqual(input.value, String(invented(Math.floor(index / 15), index % 15)));
  });
  assert.strictEqual(notice(p), "Pasted 8 rows.");
  assert.strictEqual(p.sent.filter(function (m) { return m.type === "action.invoke"; }).length, 0, "saves nothing");

  var q = page();
  openHand(q);
  paste(q, cell(q, 2, 3), block(2, 4, 2, 3));
  assert.strictEqual(cell(q, 2, 3).value, String(invented(2, 3)));
  assert.strictEqual(cell(q, 3, 6).value, String(invented(3, 6)));
  assert.strictEqual(cell(q, 2, 2).value, "", "nothing left of the cell");
  assert.strictEqual(cell(q, 4, 3).value, "", "nothing below the block");
});

test("a label column is left out, and a block too large from the focused cell fills nothing", function () {
  var p = page();
  openHand(p);
  paste(p, cell(p, 0, 0), block(8, 15, 0, 0, true));
  assert.strictEqual(cell(p, 0, 0).value, String(invented(0, 0)), "a station file's whole lines paste");
  assert.strictEqual(cell(p, 7, 14).value, String(invented(7, 14)));

  var q = page();
  openHand(q);
  paste(q, cell(q, 1, 0), block(8, 15, 0, 0));
  assert.strictEqual(notice(q), "The pasted block is 8 rows by 15 values; from this cell the grid holds 7 by 15. " +
    "Nothing was filled.");
  assert.ok(cells(q).every(function (input) { return input.value === ""; }));
  paste(q, cell(q, 0, 0), block(10, 15, 0, 0));
  assert.ok(cells(q).every(function (input) { return input.value === ""; }), "the workbook's Month and Days rows");
});

test("a block with gaps, rows of twelve and words fills what it holds and counts what is not a number", function () {
  var p = page();
  openHand(p);
  var lines = block(8, 15, 0, 0).split("\r\n");
  lines[1] = lines[1].split("\t").map(function (value, c) { return c === 4 ? "" : value; }).join("\t");
  lines[6] = lines[6].split("\t").slice(0, 12).join("\t");
  lines[7] = lines[7].split("\t").slice(0, 12).concat(["n1", "n2", "n3"]).join("\t");
  paste(p, cell(p, 0, 0), lines.join("\r\n"));
  assert.strictEqual(cell(p, 1, 4).value, "", "a gap stays empty");
  assert.strictEqual(cell(p, 6, 11).value, String(invented(6, 11)));
  [12, 13, 14].forEach(function (c) {
    assert.strictEqual(cell(p, 6, c).value, "", "a row of twelve leaves its design cells empty");
    assert.strictEqual(cell(p, 7, c).value, "", "a word is left empty");
  });
  assert.strictEqual(notice(p), "Pasted 8 rows. 3 values were not numbers and were left empty.");
});

test("Save waits for a name and the station elevation, then sends the grid in SI in one enter_values", function () {
  [["SI", "92", "10", 92, 10], ["IP", "100", "50", 30.48, 10]].forEach(function (run) {
    var p = page({ units: run[0] });
    openHand(p);
    assert.strictEqual(save(p).disabled, true);
    type(field(p, "Name"), "Elm Street");
    assert.strictEqual(save(p).disabled, true, "the station elevation is needed too");
    type(field(p, "Station elevation"), run[1]);
    assert.strictEqual(save(p).disabled, false);
    paste(p, cell(p, 0, 0), run[2] + "\t" + run[2]);
    submit(p);
    var sent = named(p, P + "climate.enter_values");
    assert.strictEqual(sent.length, 1, run[0]);
    var values = sent[0].payload.params.values;
    assert.strictEqual(sent[0].payload.params.expected_values, undefined);
    assert.ok(Math.abs(values.station_elevation_m - run[3]) < 1e-9, run[0] + " " + values.station_elevation_m);
    assert.ok(Math.abs(values.monthly.air_c[0] - run[4]) < 1e-9, run[0] + " " + values.monthly.air_c[0]);
    assert.strictEqual(values.monthly.air_c[2], null, "a gap saves as null");
    assert.deepStrictEqual(Object.keys(values.peak_loads.cool_1).sort(), PEAK.slice().sort());
    assert.strictEqual(values.station_latitude_deg, null);
    assert.strictEqual(values.wind_speed_m_s, null, "no prefill");
  });
});

test("a cell that is not a number refuses the save and is marked", function () {
  var p = page();
  openHand(p);
  type(field(p, "Name"), "Elm Street");
  type(field(p, "Station elevation"), "92");
  type(cell(p, 0, 5), "warm");
  submit(p);
  assert.strictEqual(named(p, P + "climate.enter_values").length, 0);
  assert.strictEqual(cell(p, 0, 5).getAttribute("aria-invalid"), "true");
  assert.ok(/^1 value is not a number\./.test(status(p)));
});

test("a stale save refuses and the grid keeps the draft", function () {
  var p = page();
  openHand(p);
  type(field(p, "Name"), "Elm Street");
  type(field(p, "Station elevation"), "92");
  paste(p, cell(p, 0, 0), block(8, 15, 0, 0));
  submit(p);
  answer(p, last(p, P + "climate.enter_values"), { status: "refused", code: "target.changed",
    message: "The Model already holds a climate.", effect: "none" });
  assert.strictEqual(editor(p).hidden, false);
  assert.strictEqual(status(p), "The Model already holds a climate.");
  assert.strictEqual(cell(p, 7, 14).value, String(invented(7, 14)));
  assert.strictEqual(field(p, "Name").value, "Elm Street");
  assert.strictEqual(save(p).disabled, false, "it can be sent again");
});

test("Edit Values on a station sends only the cell changed, its name and coordinates as read, guarded", function () {
  var p = page({ climate: "complete" });
  var values = full({ name: "Alder Field", origin: "station", station_latitude_deg: 42.61,
    station_longitude_deg: -73.92, monthly: full().monthly });
  values.monthly.air_c[0] = -5.123456; // more digits than the field shows: sent back as read
  answer(p, last(p, P + "climate.get"), completed({ state: "complete", missing: [], edited_cells: [],
    limit_check: null, climate: { id: "clm_AAAAAAAAAAAA", values: values } }));
  click(byText(pane(p).querySelector(".phc-heading"), "button", "Edit Values…"));
  assert.strictEqual(byText(editor(p), "h2", "Edit climate values") !== null, true);
  assert.strictEqual(field(p, "Name").readOnly, true);
  assert.strictEqual(field(p, "Latitude").readOnly, true);
  type(cell(p, 2, 13), "77");
  submit(p);
  var sent = named(p, P + "climate.save_values");
  assert.strictEqual(sent.length, 1);
  var params = sent[0].payload.params;
  assert.strictEqual(params.values.peak_loads.heat_2.rad_east_w_m2, 77);
  assert.strictEqual(params.values.monthly.air_c[0], -5.123456);
  assert.deepStrictEqual(params.values.monthly, values.monthly);
  assert.deepStrictEqual([params.values.name, params.values.station_latitude_deg, params.values.station_longitude_deg],
    ["Alder Field", 42.61, -73.92]);
  assert.strictEqual(params.expected_values.peak_loads.heat_2.rad_east_w_m2, invented(2, 13));
  assert.deepStrictEqual(Object.keys(params.expected_values).sort(), ["daily_temp_swing_k", "monthly", "name",
    "peak_loads", "station_elevation_m", "station_latitude_deg", "station_longitude_deg", "wind_speed_m_s"]);
  answer(p, sent[0], { status: "completed", effect: "committed", revision: 2, value: {} });
  assert.strictEqual(editor(p), null, "the editor closes on save");
});

test("a hand-entered climate's pane reads Incomplete with what is missing and Not checked without coordinates",
  function () {
    var p = page({ climate: "incomplete" });
    var values = full({ wind_speed_m_s: null });
    answer(p, last(p, P + "climate.get"), completed({ state: "incomplete",
      missing: [{ row: "wind_speed_m_s", columns: [] }, { row: "sky_c", columns: ["jan", "heat_1"] }],
      edited_cells: [], limit_check: { verdict: "not_checked", reason: "no_station_coordinates", distance_km: null,
        elevation_difference_m: null, distance_ok: null, elevation_ok: null },
      climate: { id: "clm_AAAAAAAAAAAA", values: values } }));
    var attached = pane(p).querySelector(".climate-attached");
    var chips = all(attached.querySelector(".climate-attached-heading"), ".climate-data-chip").map(text);
    assert.deepStrictEqual(chips, ["Incomplete"], "no edited mark");
    assert.ok(/^Incomplete: Average wind speed; Sky \(Jan, Heating 1\)\./.test(text(attached.querySelector(
      ".climate-attached-notice"))));
    assert.ok(/Not checked, entered by hand/.test(text(attached)));
    assert.ok(/Entered by hand; there is no station file to look for\./.test(text(attached)));
  });

test("the arrow keys and Enter move between cells", function () {
  var p = page();
  openHand(p);
  var from = cell(p, 1, 1);
  from.focus();
  dom.dispatch(from, { type: "keydown", key: "ArrowDown" });
  assert.strictEqual(p.context.document.activeElement, cell(p, 2, 1));
  dom.dispatch(cell(p, 2, 1), { type: "keydown", key: "Enter" });
  assert.strictEqual(p.context.document.activeElement, cell(p, 3, 1));
  cell(p, 3, 1).selectionStart = cell(p, 3, 1).selectionEnd = 0;
  dom.dispatch(cell(p, 3, 1), { type: "keydown", key: "ArrowLeft" });
  assert.strictEqual(p.context.document.activeElement, cell(p, 3, 0));
});

test("a value typed and put back, and coordinates in a comma format, send what the editor opened with", function () {
  var p = page({ climate: "complete", decimal: "," });
  var values = full({ station_latitude_deg: 42.123456, station_longitude_deg: -73.5, daily_temp_swing_k: 10.04 });
  values.monthly.air_c[0] = -5.123456;
  answer(p, last(p, P + "climate.get"), completed({ state: "complete", missing: [], edited_cells: [],
    limit_check: null, climate: { id: "clm_AAAAAAAAAAAA", values: values } }));
  click(byText(pane(p).querySelector(".phc-heading"), "button", "Edit Values…"));
  assert.strictEqual(field(p, "Latitude").value, "42,123456", "shown in the panel's number format");
  var shown = cell(p, 0, 0).value;
  type(cell(p, 0, 0), "1"); type(cell(p, 0, 0), shown);
  var swing = field(p, "Daily temperature swing"), was = swing.value;
  type(swing, "9"); type(swing, was);
  submit(p);
  var params = last(p, P + "climate.save_values").payload.params;
  assert.strictEqual(params.values.monthly.air_c[0], -5.123456, "not the rounded text");
  assert.strictEqual(params.values.daily_temp_swing_k, 10.04);
  assert.strictEqual(params.values.station_latitude_deg, 42.123456);
});

test("an empty clipboard, a column of words and a typographic minus", function () {
  var p = page();
  openHand(p);
  paste(p, cell(p, 0, 0), "");
  assert.strictEqual(notice(p), "", "nothing happens");
  paste(p, cell(p, 0, 0), "warm\r\ncold\r\n");
  assert.strictEqual(notice(p), "Pasted 2 rows. 2 values were not numbers and were left empty.",
    "one column of words is values, not labels");
  paste(p, cell(p, 0, 0), "1\t2");
  paste(p, cell(p, 0, 0), "\t\r\n");
  assert.deepStrictEqual([cell(p, 0, 0).value, cell(p, 0, 1).value], ["", ""], "blank cells empty what they cover");
  paste(p, cell(p, 0, 0), "−5.5\t3");
  assert.strictEqual(cell(p, 0, 0).value, "−5.5");
  type(field(p, "Name"), "Elm Street");
  type(field(p, "Station elevation"), "92");
  submit(p);
  assert.strictEqual(last(p, P + "climate.enter_values").payload.params.values.monthly.air_c[0], -5.5);
});

test("a station file's point decimals paste in a comma number format", function () {
  var p = page({ decimal: "," });
  openHand(p);
  paste(p, cell(p, 0, 0), "0.5\t1.234\t2,5");
  assert.strictEqual(notice(p), "Pasted 1 row.", "none refused");
  type(field(p, "Name"), "Elm Street");
  type(field(p, "Station elevation"), "92");
  submit(p);
  assert.deepStrictEqual(last(p, P + "climate.enter_values").payload.params.values.monthly.air_c.slice(0, 3),
    [0.5, 1.234, 2.5], "a point is a decimal, never a group");
});

test("while a save is out the draft cannot change", function () {
  var p = page();
  openHand(p);
  type(field(p, "Name"), "Elm Street");
  type(field(p, "Station elevation"), "92");
  type(cell(p, 0, 0), "10");
  submit(p);
  assert.strictEqual(cell(p, 0, 0).readOnly, true);
  paste(p, cell(p, 0, 0), "99");
  assert.strictEqual(cell(p, 0, 0).value, "10", "a paste waits too");
  assert.strictEqual(field(p, "Name").readOnly, true);
  assert.strictEqual(field(p, "Station elevation").disabled, true);
  answer(p, last(p, P + "climate.enter_values"), { status: "refused", code: "validation.failed",
    message: "Not saved.", effect: "none" });
  assert.strictEqual(cell(p, 0, 0).readOnly, false, "a refusal gives the draft back");
  assert.strictEqual(field(p, "Station elevation").disabled, false);
});

test("Edit Values pressed as a wind speed saves on blur opens on the values read after it", function () {
  var p = page({ climate: "complete" });
  var values = full({ wind_speed_m_s: 3 });
  answer(p, last(p, P + "climate.get"), completed({ state: "complete", missing: [], edited_cells: [],
    limit_check: null, climate: { id: "clm_AAAAAAAAAAAA", values: values } }));
  var wind = all(pane(p), "input").filter(function (n) {
    return n.getAttribute("aria-label") === "Average wind speed";
  })[0];
  wind.value = "4";
  dom.dispatch(wind, { type: "input" });
  dom.dispatch(wind, { type: "blur" });
  assert.strictEqual(named(p, P + "climate.save_values").length, 1, "the blur saves");
  click(byText(pane(p).querySelector(".phc-heading"), "button", "Edit Values…"));
  assert.strictEqual(editor(p), null, "not on the values read before the save");
  answer(p, last(p, P + "climate.save_values"), { status: "completed", effect: "committed", revision: 2, value: {} });
  p.revision = 2; p.publish();
  var after = full({ wind_speed_m_s: 4 });
  answer(p, last(p, P + "climate.get"), completed({ state: "complete", missing: [], edited_cells: [],
    limit_check: null, climate: { id: "clm_AAAAAAAAAAAA", values: after } }));
  assert.ok(editor(p), "it opens once the Model is read again");
  assert.strictEqual(field(p, "Average wind speed").value, "4");
});
