"use strict";

/* The Zones / Programs view (html/features/programs/zones_view.js, zones_cells.js, zones_selection.js): it
   registers on the Zone views host; a single dwelling's Zones show locked values that open the lock bubble and
   have no checkbox, while its heading takes the house's inputs; each cell edit and each selection bar choice is
   one Programs action carrying the painted revision; a library Program choice copies through
   assign_library_program; the Dwelling bubble applies its choice at once; an unknown value is an amber "?" naming
   why. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var REVISION = 7;
var PROVIDER = "provider.phius";

function load(options) {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view",
    "features/certification/section", "features/programs/occupancy", "features/programs/zones_view"]);
  var p = { context: context, panel: modules.panel, sent: sent };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(options || {}) });
  return p;
}

function zone(id, name, segment, path) {
  return { id: id, schema_version: 3, user_data: {}, extension_data: {}, reference: { zone_id: id, zone_path: path },
    state: "found", face_count: 0, face_area_m2: 0, unclassified_face_area_m2: 0,
    values: { name: name, building_segment_id: segment, level_id: null, ground_depth_mm: 0 } };
}

var ASSIGNMENT = { program_id: null, dwelling_id: null, equipment_set_id: null, bedrooms: null, occupants: null };

function zoneRow(id, name, segment, path, given) {
  var values = Object.assign({}, given);
  delete values.assignment;
  return Object.assign({ zone_id: id, reference: { zone_id: id, zone_path: path }, name: name,
    building_segment_id: segment, assignment: Object.assign({}, ASSIGNMENT, given.assignment || {}),
    program_id: "pgm_PHCDEFAULT01", program_name: "Residential default", dwelling_id: null, dwelling_name: null,
    single_dwelling: false, dwelling_units: null, equipment_set_id: null, floor_area_m2: 20, icfa_m2: 18,
    people: 1.5, lighting_w: 40, ventilation_m3h: 50, ventilation_source: "by_program", missing: {},
    findings: [] }, values);
}

function occupancy() {
  var house = { id: "bsg_house", name: "House", category: "residential",
    settings: { single_dwelling: true, default_program_id: null, bedrooms: null, occupants: null,
      equipment_set_id: null }, stored: false, single_dwelling: true,
    dwelling: { name: "House", units: 1, bedrooms: null, occupants: null, occupants_rule: false,
      equipment_set_id: null }, dwelling_count: 1, set_points: { heating_c: 20, cooling_c: 25, agree: true },
    single_dwelling_preview: { building_segment_id: "bsg_house", programs: [], dwelling_ids: [],
      equipment_set_ids: [], bedrooms: null, occupants: null }, findings: [],
    sums: { bedrooms: null, occupants: null, floor_area_m2: 20, icfa_m2: 18, people: null, lighting_w: 40,
      ventilation_m3h: null, incomplete: ["people", "ventilation_m3h"] } };
  var annex = { id: "bsg_annex", name: "Annex", category: "residential",
    settings: { single_dwelling: false, default_program_id: null, bedrooms: null, occupants: null,
      equipment_set_id: null }, stored: true, single_dwelling: false, dwelling: null, dwelling_count: 1,
    set_points: { heating_c: 20, cooling_c: 25, agree: true },
    single_dwelling_preview: { building_segment_id: "bsg_annex", programs: [], dwelling_ids: ["dwl_one"],
      equipment_set_ids: [], bedrooms: 2, occupants: null }, findings: [],
    sums: { bedrooms: 2, occupants: 3, floor_area_m2: 40, icfa_m2: 36, people: 3, lighting_w: 80,
      ventilation_m3h: 100, incomplete: [] } };
  return {
    zones: [
      zoneRow("zon_a", "Living", "bsg_house", [101], { single_dwelling: true, dwelling_name: "House",
        dwelling_units: 1, people: null, ventilation_m3h: null, missing: {
          people: "Enter the bedrooms of House: the Phius rule counts occupants from them.",
          ventilation_m3h: "Ventilation per person waits for the people." } }),
      zoneRow("zon_b", "Apt 1", "bsg_annex", [102], { dwelling_id: "dwl_one", dwelling_name: "Apt 1",
        dwelling_units: 1, assignment: { dwelling_id: "dwl_one", bedrooms: 2 } }),
      zoneRow("zon_c", "Corridor", "bsg_annex", [103], { findings: [{ code: "programs.equipment_watts_residential",
        severity: "warning", message: "Office has electric equipment watts." }] })],
    building_segments: [house, annex],
    dwellings: [{ id: null, name: "House", units: 1, single_dwelling: true, own_bedrooms: null, own_occupants: null,
      bedrooms: null, occupants: null, occupants_rule: false, equipment_set_id: null, zone_ids: ["zon_a"],
      building_segment_ids: ["bsg_house"], floor_area_m2: 20, icfa_m2: 18, findings: [] },
    { id: "dwl_one", name: "Apt 1", units: 1, single_dwelling: false, own_bedrooms: null,
      own_occupants: null, bedrooms: 2, occupants: 3, occupants_rule: true, equipment_set_id: null,
      zone_ids: ["zon_b"], building_segment_ids: ["bsg_annex"], floor_area_m2: 20, icfa_m2: 18, findings: [] }],
    choices: { programs: [{ id: "pgm_office", name: "Office" }, { id: "pgm_PHCDEFAULT01", name: "Residential " +
      "default" }], equipment_sets: [{ id: "eqs_PHCDEFAULT01", name: "Phius single-family" },
      { id: "eqs_kitchen", name: "Kitchen" }], default_program_id: "pgm_PHCDEFAULT01",
    default_equipment_set_id: "eqs_PHCDEFAULT01" } };
}

function snapshot(options) {
  var zones = [zone("zon_a", "Living", "bsg_house", [101]), zone("zon_b", "Apt 1", "bsg_annex", [102]),
    zone("zon_c", "Corridor", "bsg_annex", [103])];
  var sections = {
    "ph_composer.zones.faces.palette": { status: "completed", value: { active: false, palette: {},
      face_types: ["Wall"], boundary_conditions: ["Outdoors"] } },
    "ph_composer.zones.overview": { status: "completed", value: { zones: zones, make_zone: null, units: {},
      building_segments: [] } },
    "ph_composer.zones.faces.faces": { status: "completed", value: { units: { area_m2: "m2" }, faces: [] } },
    "ph_composer.zones.options": { status: "completed", value: {
      building_segments: [
        { id: "bsg_house", values: { name: "House", colour: "#1F7478", export_identifier: "bseg_house" },
          usage: { live: 1, recoverable: 0 }, extension_data: {} },
        { id: "bsg_annex", values: { name: "Annex", colour: "#5588BB", export_identifier: "bseg_annex" },
          usage: { live: 2, recoverable: 0 }, extension_data: {} }],
      levels: [], default_segment_id: "bsg_house",
      adoption: { required: false, sources: [], suggested_segment: "Building Segment" } } },
    "ph_composer.programs.occupancy": { status: "completed", value: occupancy() }
  };
  if (options.library) {
    sections["ph_composer.library.provider_catalogs"] = { status: "completed", value: [{ id: PROVIDER,
      label: "Phius Multifamily", provider_kind: "file", kinds: ["programs", "schedules"], catalogs: [
        { kind: "programs", generation: 3, state: "loaded" },
        { kind: "schedules", generation: 4, state: "loaded" }] }] };
  }
  return { product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: REVISION,
    file_name: "apartments.skp", edit_path: [], preferences: { unit_system: options.ip ? "IP" : "SI",
      dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" },
      table_views: { "ph_composer.zones": "ph_composer.programs.zones" } }, sections: sections };
}

function section(p) { return p.context.document.querySelector("[data-section='ph_composer.overview']"); }

function shown(p) {
  return section(p).querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0];
}

var PATHS = { Living: 101, "Apt 1": 102, Corridor: 103 };

function rowNamed(p, name) {
  var key = JSON.stringify(["Zone", [PATHS[name]]]);
  return shown(p).querySelectorAll("tr").filter(function (tr) { return tr.getAttribute("data-row-key") === key; })[0];
}

function heading(p, name) {
  return shown(p).querySelectorAll("tr").filter(function (tr) {
    var label = tr.getAttribute("data-heading-key") && tr.querySelector(".phc-segment-name");
    return label && label.textContent === name;
  })[0];
}

function cell(row, field) { return row.querySelector(".col-" + field); }

function headers(p) {
  return shown(p).querySelectorAll(".phc-th-label").map(function (node) { return node.textContent.trim(); });
}

function checkbox(row) {
  return row.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; })[0];
}

function tooltipped(root, pattern) {
  return root.querySelectorAll("[data-tooltip]").filter(function (node) {
    return pattern.test(node.getAttribute("data-tooltip"));
  })[0];
}

function labelled(root, tag, label) {
  return root.querySelectorAll(tag).filter(function (node) { return node.getAttribute("aria-label") === label; })[0];
}

function click(node) { node.listeners.click({ preventDefault: function () {} }); }

function change(node, value) { node.value = value; node.listeners.change({}); }

function plain(value) { return JSON.parse(JSON.stringify(value)); }

function last(p) { var all = p.actions(); return all[all.length - 1].payload; }

function bubble(p, title) {
  return p.context.document.querySelectorAll(".phc-bubble").filter(function (node) {
    return node.getAttribute("aria-label") === title && !node.hidden;
  })[0];
}

test("the view registers after Spaces with every column, and names each per-area basis", function () {
  var p = load();
  var view = p.context.PhComposerUI.get("features/programs/zones_view");
  assert.deepStrictEqual(plain([view.id, view.label, view.order, view.sections]),
    ["ph_composer.programs.zones", "Programs", 30, ["ph_composer.programs.occupancy"]]);
  var tabs = section(p).querySelector("[aria-label='Zone views']").querySelectorAll("button").map(function (node) {
    return node.textContent;
  });
  assert.deepStrictEqual(plain(tabs), ["Geometry", "Programs"]);
  var labels = headers(p);
  ["Program", "Dwelling", "Bedrooms", "Occupants", "Equipment Set", "People", "Lighting (W)"].forEach(
    function (label) { assert.ok(labels.indexOf(label) >= 0, label + " in " + labels.join(", ")); });
  assert.ok(labels.some(function (text) { return /Floor area/.test(text); }));
  assert.ok(tooltipped(shown(p), /iCFA\): the basis of the Phius residential rules/), "a header names its basis");
});

test("a single dwelling's Zone is locked and unchecked; its lock opens the bubble with Open settings", function () {
  var p = load();
  var living = rowNamed(p, "Living");
  assert.strictEqual(checkbox(living), undefined, "a locked Zone cannot be checked");
  assert.ok(checkbox(rowNamed(p, "Corridor")), "another Zone can");
  var program = cell(living, "program").querySelector("button");
  assert.ok(/phc-programs-locked/.test(program.className));
  assert.strictEqual(program.textContent, "Residential default");
  click(program);
  var lock = bubble(p, "House is a single dwelling");
  assert.ok(lock, "the lock bubble opens");
  var open = lock.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Open settings";
  })[0];
  click(open);
  assert.ok(p.context.document.querySelectorAll("dialog").some(function (node) {
    return node.className.indexOf("phc-segment-settings-dialog") >= 0 && !node.hidden;
  }), "Open settings opens House's settings");
});

test("the Single dwelling tag opens the same lock bubble", function () {
  var p = load();
  var tag = heading(p, "House").querySelectorAll("button").filter(function (node) {
    return /phc-segment-tag/.test(node.className);
  })[0];
  assert.strictEqual(tag.textContent, "Single dwelling");
  click(tag);
  assert.ok(bubble(p, "House is a single dwelling"));
});

test("the house row takes the bedrooms, in amber until entered, through the Segment's settings Save", function () {
  var p = load();
  var input = labelled(heading(p, "House"), "input", "Bedrooms in House");
  assert.ok(/is-needed/.test(input.className));
  assert.strictEqual(input.placeholder, "?");
  change(input, "3");
  var sent = last(p);
  assert.strictEqual(sent.name, "ph_composer.zones.save_segment_settings");
  assert.strictEqual(sent.expected_revision, REVISION);
  assert.deepStrictEqual(plain(sent.params.extension_payloads), { "ph_composer.programs.segment": {
    single_dwelling: true, default_program_id: null, bedrooms: 3, occupants: null, equipment_set_id: null } });
  assert.deepStrictEqual(plain([sent.params.id, sent.params.default, sent.params.expected_default_segment_id]),
    ["bsg_house", true, "bsg_house"]);
});

test("an unknown value is an amber question mark naming why, on the row and on the heading", function () {
  var p = load();
  var missing = cell(rowNamed(p, "Living"), "people").querySelector(".phc-programs-missing");
  assert.strictEqual(missing.textContent, "?");
  assert.ok(/Enter the bedrooms of House/.test(missing.getAttribute("data-tooltip")));
  assert.ok(cell(heading(p, "House"), "people").querySelector(".phc-programs-missing"));
  assert.strictEqual(cell(heading(p, "Annex"), "bedrooms").textContent, "2");
  assert.ok(tooltipped(rowNamed(p, "Corridor"), /electric equipment watts/), "a finding flags its row");
});

test("a Program choice is one assign_program carrying the painted revision", function () {
  var p = load();
  var select = labelled(rowNamed(p, "Corridor"), "select", "Program for Corridor");
  assert.ok(/is-default/.test(select.className), "an unassigned Zone shows its effective Program in italics");
  change(select, "pgm:pgm_office");
  var sent = last(p);
  assert.deepStrictEqual(plain([sent.name, sent.expected_revision, sent.params]),
    ["ph_composer.programs.assign_program", REVISION, { zones: [{ zone_id: "zon_c", zone_path: [103] }],
      program_id: "pgm_office" }]);
});

test("a library Program copies into this file and assigns in one action", async function () {
  var p = load({ library: true });
  await new Promise(function (resolve) { setTimeout(resolve, 0); });
  var reads = p.sent.filter(function (message) {
    return message.type === "query.invoke" && message.payload.name === "ph_composer.library.in_file" &&
      message.payload.params.kind === "programs";
  });
  assert.strictEqual(reads.length, 1, "the shown view reads the source's Programs");
  p.panel.receive({ type: "query.result", payload: { request_id: reads[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { generation: 3, state: "loaded", next_cursor: null, total: 1,
      rows: [{ library_id: "phius.mf", record_id: "corridor", display_label: "Phius MF Corridor", snapshot: {},
        resolution: { outcome: "create", candidates: [] } }] } } } });
  var select = labelled(rowNamed(p, "Corridor"), "select", "Program for Corridor");
  var option = select.querySelectorAll("option").filter(function (node) {
    return node.textContent === "Phius MF Corridor";
  })[0];
  assert.ok(option, "the library's Program is offered");
  assert.ok(/copies into this file/.test(option.parentNode.label));
  change(select, option.value);
  var sent = last(p);
  assert.strictEqual(sent.name, "ph_composer.programs.assign_library_program");
  assert.deepStrictEqual(plain(sent.params), { zones: [{ zone_id: "zon_c", zone_path: [103] }], copy: {
    provider_id: PROVIDER, kind: "programs", generation: 3, library_id: "phius.mf", record_id: "corridor",
    choice: "create" } });
});

test("bedrooms on a Zone in a Dwelling are one set_counts; a Zone in none shows a dash", function () {
  var p = load();
  var input = labelled(rowNamed(p, "Apt 1"), "input", "Bedrooms in Apt 1");
  assert.strictEqual(input.value, "2");
  change(input, "3");
  assert.deepStrictEqual(plain(last(p).params), { zone: { zone_id: "zon_b", zone_path: [102] }, bedrooms: 3,
    occupants: null });
  assert.strictEqual(cell(rowNamed(p, "Corridor"), "bedrooms").querySelector("span").textContent, "—");
});

test("the Dwelling bubble applies its choice at once and edits the Dwelling's units", function () {
  var p = load();
  click(cell(rowNamed(p, "Apt 1"), "dwelling").querySelector("button"));
  var open = bubble(p, "Dwelling of Apt 1");
  assert.ok(open);
  var choose = labelled(open, "select", "Dwelling of Apt 1");
  assert.strictEqual(choose.value, "dwl_one");
  var units = labelled(open, "input", "Units of Apt 1");
  change(units, "2");
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), ["ph_composer.programs.dwellings.update",
    { id: "dwl_one", values: { units: 2 }, expected_values: { units: 1 } }]);
  p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
    outcome: { status: "completed", code: "ok", effect: "committed", revision: REVISION + 1, value: {} } } });
  change(choose, "none");
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), ["ph_composer.programs.assign_dwelling",
    { zones: [{ zone_id: "zon_b", zone_path: [102] }], choice: "none" }]);
});

test("the selection bar assigns to every checked Zone in one request each", function () {
  var p = load();
  [rowNamed(p, "Apt 1"), rowNamed(p, "Corridor")].forEach(function (row) {
    click(checkbox(row));
  });
  var bar = section(p).querySelector("[aria-label='Checked Zones']");
  assert.ok(bar && !bar.hidden, "the bar shows");
  change(labelled(bar, "select", "Equipment Set for checked Zones"), "eqs_kitchen");
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), ["ph_composer.programs.assign_equipment_set",
    { equipment_set_id: "eqs_kitchen", dwelling_ids: ["dwl_one"], zones: [{ zone_id: "zon_c", zone_path: [103] }] }]);
  p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
    outcome: { status: "completed", code: "ok", effect: "committed", revision: REVISION + 1, value: {} } } });
  change(labelled(bar, "select", "Dwelling for checked Zones"), "each");
  assert.deepStrictEqual(plain(last(p).params), { zones: [{ zone_id: "zon_b", zone_path: [102] },
    { zone_id: "zon_c", zone_path: [103] }], choice: "each" });
});

test("IP shows areas in ft² and ventilation in cfm, lighting stays in W", function () {
  var p = load({ ip: true });
  var labels = headers(p).join(" | ");
  assert.ok(/ft²/.test(labels), labels);
  assert.ok(/cfm/.test(labels), labels);
  assert.ok(/Lighting \(W\)/.test(labels), labels);
  assert.strictEqual(cell(rowNamed(p, "Corridor"), "lighting_w").textContent, "40");
});

test("the control row counts the Dwellings that hold Zones, a single dwelling's house among them", function () {
  var p = load();
  assert.strictEqual(section(p).querySelector(".phc-view-count").textContent, "3 Zones · 2 dwellings");
});

test("a refused choice writes nothing and the cell shows the Model's value again", function () {
  var p = load();
  var select = labelled(rowNamed(p, "Corridor"), "select", "Program for Corridor");
  change(select, "pgm:pgm_office");
  p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
    outcome: { status: "refused", code: "revision.stale", effect: "none", revision: REVISION,
      message: "The Model changed since it was read. Nothing was written." } } });
  assert.strictEqual(labelled(rowNamed(p, "Corridor"), "select", "Program for Corridor").value, "",
    "the unassigned Zone reads its default again");
});

test("the bar's Program, shared Dwelling and Add to each send one request for every checked Zone", function () {
  var p = load();
  click(checkbox(rowNamed(p, "Apt 1"))); click(checkbox(rowNamed(p, "Corridor")));
  var bar = section(p).querySelector("[aria-label='Checked Zones']");
  function answered() {
    p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
      outcome: { status: "completed", code: "ok", effect: "committed", revision: REVISION, value: {} } } });
  }
  var both = [{ zone_id: "zon_b", zone_path: [102] }, { zone_id: "zon_c", zone_path: [103] }];
  change(labelled(bar, "select", "Program for checked Zones"), "pgm:pgm_office");
  assert.deepStrictEqual(plain([last(p).name, last(p).params]), ["ph_composer.programs.assign_program",
    { zones: both, program_id: "pgm_office" }]);
  answered();
  var dwelling = labelled(bar, "select", "Dwelling for checked Zones");
  var addTo = dwelling.querySelectorAll("option").filter(function (node) { return node.value === "dwl_one"; });
  assert.strictEqual(addTo.length, 1, "Add to offers the Segment's Dwelling");
  change(dwelling, "shared");
  assert.deepStrictEqual(plain(last(p).params), { zones: both, choice: "shared" });
  answered();
  change(dwelling, "dwl_one");
  assert.deepStrictEqual(plain(last(p).params), { zones: both, choice: "existing", dwelling_id: "dwl_one" });
});

test("IP cells show ft² and cfm values", function () {
  var p = load({ ip: true });
  assert.strictEqual(cell(rowNamed(p, "Corridor"), "floor_area_m2").textContent, "215.3");
  assert.strictEqual(cell(rowNamed(p, "Corridor"), "ventilation_m3h").textContent, "29.4");
});

/* A later snapshot: the fixture with `change` applied to its occupancy read, at `revision`. */
function republish(p, revision, change) {
  var next = snapshot({});
  next.revision = revision;
  change(next.sections["ph_composer.programs.occupancy"].value);
  p.panel.receive({ type: "panel.snapshot", payload: next });
}

function typeInto(p, input, text) {
  input.focus();
  input.value = text;
  input.listeners.input({});
}

test("a count typed before the Model changed is sent at the revision it was typed against", function () {
  var p = load();
  var input = labelled(rowNamed(p, "Apt 1"), "input", "Bedrooms in Apt 1");
  typeInto(p, input, "3");
  republish(p, REVISION + 1, function (value) { value.zones[1].assignment.bedrooms = 4; });
  input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.deepStrictEqual(plain([last(p).name, last(p).expected_revision, last(p).params.bedrooms]),
    ["ph_composer.programs.set_counts", REVISION, 3]);
});

test("the house row's typed bedrooms are sent at the revision they were typed against", function () {
  var p = load();
  var input = labelled(heading(p, "House"), "input", "Bedrooms in House");
  typeInto(p, input, "3");
  republish(p, REVISION + 1, function (value) { value.building_segments[0].settings.bedrooms = 2; });
  input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.deepStrictEqual(plain([last(p).name, last(p).expected_revision]),
    ["ph_composer.zones.save_segment_settings", REVISION]);
});

test("a refused Units write puts the Model's units back in the focused field", function () {
  var p = load();
  click(cell(rowNamed(p, "Apt 1"), "dwelling").querySelector("button"));
  var units = labelled(bubble(p, "Dwelling of Apt 1"), "input", "Units of Apt 1");
  units.focus();
  change(units, "2");
  p.panel.receive({ type: "action.result", payload: { request_id: last(p).request_id, session: "session-a",
    outcome: { status: "refused", code: "revision.stale", effect: "none", revision: REVISION,
      message: "The Model changed since it was read. Nothing was written." } } });
  var again = labelled(bubble(p, "Dwelling of Apt 1"), "input", "Units of Apt 1");
  assert.strictEqual(again.value, "1");
  assert.strictEqual(again.disabled, false);
});

test("an Equipment Set chosen explicitly shows even when it is the Model's default", function () {
  var p = load();
  republish(p, REVISION, function (value) { value.zones[2].equipment_set_id = "eqs_PHCDEFAULT01"; });
  var select = labelled(rowNamed(p, "Corridor"), "select", "Equipment Set for Corridor");
  assert.strictEqual(select.value, "eqs_PHCDEFAULT01");
  assert.ok(select.querySelectorAll("option").some(function (node) {
    return node.value === "eqs_PHCDEFAULT01" && node.textContent === "Phius single-family";
  }));
});

test("a Dwelling of Zones in no Building Segment is not offered to a Zone in one", function () {
  var p = load();
  republish(p, REVISION, function (value) {
    value.dwellings.push({ id: "dwl_out", name: "Shed", units: 1, single_dwelling: false, own_bedrooms: null,
      own_occupants: null, bedrooms: null, occupants: null, occupants_rule: false, equipment_set_id: null,
      zone_ids: ["zon_x"], building_segment_ids: [], floor_area_m2: 5, icfa_m2: 5, findings: [] });
    value.dwellings.push({ id: "dwl_empty", name: "Spare", units: 1, single_dwelling: false, own_bedrooms: null,
      own_occupants: null, bedrooms: null, occupants: null, occupants_rule: false, equipment_set_id: null,
      zone_ids: [], building_segment_ids: [], floor_area_m2: 0, icfa_m2: 0, findings: [] });
  });
  click(cell(rowNamed(p, "Corridor"), "dwelling").querySelector("button"));
  var names = labelled(bubble(p, "Dwelling of Corridor"), "select", "Dwelling of Corridor").querySelectorAll("option")
    .map(function (node) { return node.textContent; });
  assert.deepStrictEqual(plain(names), ["Apt 1", "Spare", "New dwelling", "Not a dwelling"]);
});
