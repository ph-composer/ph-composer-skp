"use strict";

/* Building Segment heading rows on the Zones tab (context/EXTENSIBILITY.md, "Zone views" and "Building Segment
   settings"): in Geometry and Spaces each Zone sits under its Segment's heading, with No Building Segment last;
   the heading's two lines, tags, sums and Actions cell; New Building Segment and its name in place; moving
   checked Zones from both selection bars; Delete with a destination; and the settings dialog with a registered
   section, which writes nothing on Cancel, close or Escape. */

var assert = require("assert");
var fs = require("fs");
var path = require("path");
var test = require("node:test");
var vm = require("vm");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");
var root = require("./support/panel_files").root;


function page(view) {
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
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent, view: view };
  p.section = function () { return context.document.querySelector("[data-section='ph_composer.overview']"); };
  p.actions = function () { return sent.filter(function (message) { return message.type === "action.invoke"; }); };
  return p;
}

/* Two Segments, House (the default, holding Zone A) and Annex (empty), and Zone B in no Segment. */
function snapshot(view, change) {
  var zones = fixture.zones();
  zones[0].schema_version = 3;
  zones[0].values = { name: "Zone A", building_segment_id: "bsg_house", level_id: null, ground_depth_mm: 0 };
  zones[0].face_area_m2 = 42;
  zones[1].schema_version = 3;
  zones[1].values = { name: "Zone B", building_segment_id: null, level_id: null, ground_depth_mm: 0 };
  zones[1].face_area_m2 = 18;
  var spaces = fixture.section();
  spaces.building_segments = [
    { key: "bsg_house", name: "House", zone_count: 1, floor_area_m2: 22, weighted_area_m2: 20, net_volume_m3: 55,
      airflows: { v_sup_m3h: 60, v_eta_m3h: 40, v_tran_m3h: 20 }, by_program_zone_count: 0 },
    { key: "", name: null, zone_count: 1, floor_area_m2: 12, weighted_area_m2: 12, net_volume_m3: 36,
      airflows: { v_sup_m3h: null, v_eta_m3h: null, v_tran_m3h: null }, by_program_zone_count: 1 }];
  var state = {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": view || "ph_composer.zones.faces" } },
    sections: {
      "ph_composer.zones.faces.palette": { status: "completed", value: { active: false, palette: {},
        face_types: ["Wall"], boundary_conditions: ["Outdoors"] } },
      "ph_composer.zones.overview": { status: "completed", value: { zones: zones, make_zone: null, units: {},
        building_segments: [{ key: "bsg_house", zone_count: 1, face_area_m2: 42, unclassified_face_area_m2: 0 },
          { key: "", zone_count: 1, face_area_m2: 18, unclassified_face_area_m2: 0 }] } },
      "ph_composer.zones.faces.faces": { status: "completed", value: { units: { area_m2: "m2" }, faces: [
        face("zon_a", [100], 101, 42), face("zon_b", [200], 201, 18)] } },
      "ph_composer.spaces.spaces": { status: "completed", value: spaces },
      "ph_composer.zones.options": { status: "completed", value: {
        building_segments: [
          { id: "bsg_house", values: { name: "House", colour: "#1F7478", export_identifier: "bseg_house" },
            usage: { live: 1, recoverable: 0 }, extension_data: {} },
          { id: "bsg_annex", values: { name: "Annex", colour: "#5588BB", export_identifier: "bseg_annex" },
            usage: { live: 0, recoverable: 0 },
            extension_data: { "example.segment.note": { schema_version: 1, payload: { text: "east" } } } }],
        levels: [], default_segment_id: "bsg_house",
        adoption: { required: false, sources: [], suggested_segment: "Building Segment" } } }
    }
  };
  if (change) change(state);
  return state;
}

function face(zoneId, zonePath, id, area) {
  return { reference: { zone_id: zoneId, zone_path: zonePath, entity_path: [id], entity_id: "fac_" + id },
    zone_name: zoneId, area_m2: area, state: "classified",
    values: { face_type: "Wall", boundary_condition: "Outdoors" },
    suggested: { face_type: "Wall", boundary_condition: "Outdoors" } };
}

function shown(p) {
  return p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0];
}

/* The Zone row named `name` in the shown table. */
function zoneRow(p, name) {
  return shown(p).querySelectorAll("tr").filter(function (tr) {
    var key = tr.getAttribute("data-row-key"), label = tr.querySelector(".col-name");
    if (!key || JSON.parse(key)[0] !== "Zone" || !label) return false;
    var input = label.querySelector("input");
    return (input ? input.value : label.textContent) === name;
  })[0];
}

/* The shown table's top-level rows in order: a heading as ["heading", name, tags], a Zone as ["Zone", name]. */
function outline(p) {
  return shown(p).querySelectorAll("tr").filter(function (tr) {
    return !tr.hidden && (tr.getAttribute("data-heading-key") || tr.className.indexOf("tier-0") >= 0) &&
      tr.querySelector(".col-name");
  }).map(function (tr) {
    var name = tr.querySelector(".col-name");
    if (tr.getAttribute("data-heading-key")) {
      return ["heading", name.querySelector(".phc-segment-name").textContent,
        name.querySelectorAll(".phc-segment-tag").map(function (tag) { return tag.textContent; })];
    }
    var input = name.querySelector("input");
    return ["Zone", input ? input.value : name.textContent];
  });
}

function heading(p, name) {
  return shown(p).querySelectorAll("tr").filter(function (tr) {
    var label = tr.getAttribute("data-heading-key") && tr.querySelector(".phc-segment-name");
    return label && label.textContent === name;
  })[0];
}

function cell(tr, field) {
  return tr.querySelectorAll("td").filter(function (td) {
    return td.className.split(" ").indexOf("col-" + field) >= 0;
  })[0];
}

function byLabel(root, label) {
  var scope = root.closest("[data-pane]") || root;
  return scope.querySelectorAll("input, select, button").filter(function (node) {
    return node.getAttribute("aria-label") === label;
  })[0];
}

function click(node) { node.listeners.click({ preventDefault: function () {} }); }

function choose(select, value) { select.value = value; select.listeners.change({}); }

function dialog(p, className) {
  return p.context.document.querySelectorAll("dialog").filter(function (node) {
    return node.className.indexOf(className) >= 0 && !node.hidden;
  })[0];
}

function load(view, change) {
  var p = page(view);
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(view, change) });
  return p;
}

function complete(p, message, value) {
  p.panel.receive({ type: "action.result", payload: { request_id: message.payload.request_id, session: "session-a",
    outcome: { status: "completed", value: value || {} } } });
}

test("Geometry groups its Zones under each Segment's heading, the empty Segment shown and No Building Segment last",
  function () {
    var p = load();
    assert.deepStrictEqual(outline(p), [["heading", "Annex", []], ["heading", "House", ["Default"]],
      ["Zone", "Zone A"], ["heading", "No Building Segment", []], ["Zone", "Zone B"]]);
    assert.strictEqual(cell(heading(p, "House"), "area_m2").textContent, "42", "the view's own sum");
    var none = heading(p, "No Building Segment");
    assert.ok(cell(none, "name").classList.contains("is-muted"));
    assert.strictEqual(none.querySelector(".phc-segment-name").getAttribute("data-tooltip"),
      "Zones in no Building Segment are left out of export.");
    assert.strictEqual(none.querySelector(".row-check"), null, "a heading is never checked");
    assert.strictEqual(byLabel(p.section(), "Zone A Building-Segment"), undefined, "the column is gone");
    assert.ok(!shown(p).querySelectorAll("th").some(function (th) { return /Building/.test(th.textContent); }));
  });

test("No Building Segment is shown only while it holds a Zone", function () {
  var p = load(null, function (state) {
    state.sections["ph_composer.zones.overview"].value.zones[1].values.building_segment_id = "bsg_annex";
  });
  assert.deepStrictEqual(outline(p), [["heading", "Annex", []], ["Zone", "Zone B"], ["heading", "House", ["Default"]],
    ["Zone", "Zone A"]]);
});

test("Spaces groups the same way and fills its sums, with a dash while a Zone in it is By Program", function () {
  var p = load("ph_composer.spaces");
  assert.deepStrictEqual(outline(p).map(function (row) { return row[1]; }),
    ["Annex", "House", "Zone A", "No Building Segment", "Zone B"]);
  var house = heading(p, "House"), none = heading(p, "No Building Segment");
  assert.deepStrictEqual(["floor_area_m2", "weighted_area_m2", "v_sup_m3h"].map(function (field) {
    return cell(house, field).textContent;
  }), ["22", "20", "60"]);
  assert.strictEqual(cell(none, "v_sup_m3h").textContent, "—");
});

test("a heading's Actions cell holds Settings and Delete, and Delete on the last Segment says why", function () {
  var p = load();
  var house = heading(p, "House");
  assert.deepStrictEqual(house.querySelectorAll(".row-icon").map(function (node) {
    return node.getAttribute("aria-label");
  }), ["Settings for House", "Delete House"]);
  assert.strictEqual(heading(p, "No Building Segment").querySelectorAll(".row-icon").length, 0);
  var last = load(null, function (state) {
    state.sections["ph_composer.zones.options"].value.building_segments.splice(1, 1);
  });
  var remove = heading(last, "House").querySelector("[data-row-action='delete']");
  assert.strictEqual(remove.getAttribute("aria-disabled"), "true");
  assert.match(remove.getAttribute("data-tooltip"), /keeps at least one Building Segment/);
  click(remove);
  assert.strictEqual(last.actions().length, 0, "nothing is sent");
});

test("a long name is cut on screen and whole in its tooltip", function () {
  var name = "Residential tower with retail podium and below-grade parking, phase two";
  var p = load(null, function (state) {
    state.sections["ph_composer.zones.options"].value.building_segments[0].values.name = name;
  });
  var label = heading(p, name).querySelector(".phc-segment-name");
  assert.strictEqual(label.getAttribute("data-tooltip"), name);
});

test("New Building Segment makes one, opens its name in place, and Enter renames it", function () {
  var p = load();
  click(byLabel(p.section(), "New Building Segment"));
  var create = p.actions()[0];
  assert.strictEqual(create.payload.name, "ph_composer.zones.create_segment");
  assert.deepStrictEqual(create.payload.params, { colour: "#9977AA", targets: [] }, "the first free colour");
  complete(p, create, { id: "bsg_three", name: "Building Segment 3", zone_ids: [] });
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(null, function (state) {
    state.revision = 5;
    state.sections["ph_composer.zones.options"].value.building_segments.push({ id: "bsg_three",
      values: { name: "Building Segment 3", colour: "#9977AA", export_identifier: "bseg_three" },
      usage: { live: 0, recoverable: 0 }, extension_data: {} });
  }) });
  var field = byLabel(p.section(), "Building Segment name");
  assert.strictEqual(field.value, "Building Segment 3");
  field.value = "Garage";
  field.listeners.input({});
  field.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  var rename = p.actions()[1];
  assert.strictEqual(rename.payload.name, "ph_composer.zones.options.update");
  assert.deepStrictEqual(rename.payload.params, { collection: "building_segment", id: "bsg_three",
    values: { name: "Garage", colour: "#9977AA" },
    expected_values: { name: "Building Segment 3", colour: "#9977AA" } });
});

test("a name changed elsewhere while a new Segment is being named is never overwritten", function () {
  var p = load();
  click(byLabel(p.section(), "New Building Segment"));
  complete(p, p.actions()[0], { id: "bsg_three", name: "Building Segment 3", zone_ids: [] });
  function withThird(name) {
    return snapshot(null, function (state) {
      state.sections["ph_composer.zones.options"].value.building_segments.push({ id: "bsg_three",
        values: { name: name, colour: "#9977AA", export_identifier: "bseg_three" },
        usage: { live: 0, recoverable: 0 }, extension_data: {} });
    });
  }
  p.panel.receive({ type: "panel.snapshot", payload: withThird("Building Segment 3") });
  var field = byLabel(p.section(), "Building Segment name");
  field.value = "Garage"; field.listeners.input({});
  p.panel.receive({ type: "panel.snapshot", payload: withThird("Shed") });
  byLabel(p.section(), "Building Segment name").listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.strictEqual(p.actions().length, 1, "only the create was sent");
  assert.strictEqual(byLabel(p.section(), "Building Segment name"), undefined);
});

test("a Shift-click range follows the rows as the Segments show them", function () {
  var p = load(null, function (state) {
    var overview = state.sections["ph_composer.zones.overview"].value;
    overview.zones[1].values.building_segment_id = "bsg_annex";
    var third = JSON.parse(JSON.stringify(overview.zones[0]));
    third.id = "zon_c"; third.reference = { zone_id: "zon_c", zone_path: [300] };
    third.values = Object.assign({}, third.values, { name: "Zone C" });
    overview.zones.push(third);
    state.sections["ph_composer.zones.faces.faces"].value.faces.push(face("zon_c", [300], 301, 9));
  });
  assert.deepStrictEqual(outline(p).map(function (row) { return row[1]; }),
    ["Annex", "Zone B", "House", "Zone A", "Zone C"]);
  click(zoneRow(p, "Zone B").querySelector(".row-check"));
  zoneRow(p, "Zone C").querySelector(".row-check").listeners.click({ shiftKey: true, preventDefault: function () {} });
  ["Zone A", "Zone B", "Zone C"].forEach(function (name) {
    assert.strictEqual(zoneRow(p, name).querySelector(".row-check").checked, true, name + " is in the range");
  });
});

test("a Zone with no Faces is checked on its own in Geometry and moves from the bar", function () {
  var p = load(null, function (state) {
    var faces = state.sections["ph_composer.zones.faces.faces"].value.faces;
    faces.splice(1, 1);
  });
  var box = zoneRow(p, "Zone B").querySelector(".row-check");
  assert.ok(box, "a Zone with no Faces still has a box");
  click(box);
  var select = byLabel(p.section(), "Building Segment for checked Zones");
  assert.ok(select && !select.disabled && !select.parentNode.hidden);
  choose(select, "bsg_house");
  var move = p.actions()[0];
  assert.strictEqual(move.payload.name, "ph_composer.zones.update_field");
  assert.deepStrictEqual(move.payload.params.targets.map(function (target) { return target.reference.zone_id; }),
    ["zon_b"]);
});

test("Escape keeps a new Segment's given name and sends nothing", function () {
  var p = load();
  click(byLabel(p.section(), "New Building Segment"));
  complete(p, p.actions()[0], { id: "bsg_annex", name: "Annex", zone_ids: [] });
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var field = byLabel(p.section(), "Building Segment name");
  field.listeners.keydown({ key: "Escape", preventDefault: function () {} });
  assert.strictEqual(byLabel(p.section(), "Building Segment name"), undefined);
  assert.strictEqual(p.actions().length, 1);
});

test("checked Zones move from the Geometry bar to a Segment, to none or into a new one", function () {
  var p = load();
  click(zoneRow(p, "Zone B").querySelector(".row-check"));
  var select = byLabel(p.section(), "Building Segment for checked Zones");
  assert.ok(select && !select.disabled, "the bar offers the checked Zone's Segment");
  assert.strictEqual(select.children[0].textContent, "No Building Segment", "the Zones' Segment now");
  choose(select, "bsg_house");
  var move = p.actions()[0];
  assert.strictEqual(move.payload.name, "ph_composer.zones.update_field");
  assert.strictEqual(move.payload.params.field, "building_segment");
  assert.strictEqual(move.payload.params.value, "House");
  assert.deepStrictEqual(move.payload.params.targets.map(function (target) { return target.reference.zone_id; }),
    ["zon_b"]);
  complete(p, move);
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  choose(byLabel(p.section(), "Building Segment for checked Zones"), "__new");
  var create = p.actions()[1];
  assert.strictEqual(create.payload.name, "ph_composer.zones.create_segment");
  assert.deepStrictEqual(create.payload.params.targets.map(function (target) { return target.reference.zone_id; }),
    ["zon_b"]);
});

test("a checked Zone row in Spaces moves from its bar too", function () {
  var p = load("ph_composer.spaces");
  var box = zoneRow(p, "Zone A").querySelector(".row-check");
  assert.ok(box, "a Zone row is checkable in Spaces");
  click(box);
  var select = byLabel(p.section(), "Building Segment for checked Zones");
  assert.ok(select && !select.disabled);
  choose(select, "__none");
  var move = p.actions()[0];
  assert.strictEqual(move.payload.name, "ph_composer.zones.update_field");
  assert.strictEqual(move.payload.params.value, null);
  assert.deepStrictEqual(move.payload.params.targets.map(function (target) { return target.reference.zone_id; }),
    ["zon_a"]);
});

test("a Zone whose box reads mixed in Spaces is not moved", function () {
  var p = load("ph_composer.spaces");
  fixture.expandAll(p.section());
  click(zoneRow(p, "Zone A").querySelector(".row-check"));
  var living = shown(p).querySelectorAll("tr").filter(function (tr) {
    return tr.getAttribute("data-row-key") === JSON.stringify(["Space", [100, 101]]);
  })[0];
  click(living.querySelector(".row-check"));
  var select = byLabel(p.section(), "Building Segment for checked Zones");
  assert.ok(!select || select.disabled || select.parentNode.hidden, "no Zone is fully checked, so none moves");
  assert.strictEqual(p.actions().length, 0);
});

test("Delete names the Zones' destination and the settings that go, and sends the destination chosen", function () {
  var p = load();
  registerNote(p);
  click(heading(p, "House").querySelector("[data-row-action='delete']"));
  var confirm = dialog(p, "phc-segment-delete-dialog");
  assert.strictEqual(confirm.querySelector("h2").textContent, "Delete House?");
  assert.strictEqual(confirm.querySelector(".phc-segment-zones").textContent, "Zones: Zone A.");
  var destination = confirm.querySelector("select");
  assert.deepStrictEqual(destination.children.map(function (node) { return node.textContent; }),
    ["Annex", "No Building Segment"]);
  assert.match(confirm.querySelector(".phc-segment-consequence").textContent, /New Zones will join Annex/);
  choose(destination, "__none");
  assert.match(confirm.querySelector(".phc-segment-consequence").textContent, /left out of export/);
  click(confirm.querySelectorAll("button").filter(function (node) { return node.textContent === "Delete"; })[0]);
  var remove = p.actions()[0];
  assert.deepStrictEqual(remove.payload.params, { collection: "building_segment", id: "bsg_house",
    replacement_id: null });
  complete(p, remove);

  click(heading(p, "Annex").querySelector("[data-row-action='delete']"));
  var empty = dialog(p, "phc-segment-delete-dialog");
  assert.strictEqual(empty.querySelector("select"), null, "an empty Segment moves nothing");
  assert.strictEqual(empty.querySelector(".phc-segment-consequence").textContent, "Its settings go with it: Note.");
});

test("Delete refuses once the Model has changed under its confirmation, and sends nothing", function () {
  var p = load();
  click(heading(p, "House").querySelector("[data-row-action='delete']"));
  var confirm = dialog(p, "phc-segment-delete-dialog");
  p.panel.receive({ type: "panel.snapshot", payload: snapshot(null, function (state) {
    state.revision = 5;
    state.sections["ph_composer.zones.overview"].value.zones[1].values.building_segment_id = "bsg_house";
  }) });
  click(confirm.querySelectorAll("button").filter(function (node) { return node.textContent === "Delete"; })[0]);
  assert.strictEqual(p.actions().length, 0);
  assert.strictEqual(dialog(p, "phc-segment-delete-dialog"), undefined, "the confirmation closes");
});

/* The development example's section (tools/examples/zones/example_segment_note.js): a note that must not be
   blank. */
function registerNote(p) {
  var file = path.join(root, "tools/examples/zones/example_segment_note.js");
  vm.runInContext(fs.readFileSync(file, "utf8"), p.context, { filename: file });
}

test("settings show General and every registered section, and Save sends one request with each payload", function () {
  var p = load();
  registerNote(p);
  click(heading(p, "Annex").querySelector("[data-row-action='settings']"));
  var settings = dialog(p, "phc-segment-settings-dialog");
  assert.deepStrictEqual(settings.querySelectorAll("h3").map(function (node) { return node.textContent; }),
    ["General", "Note"]);
  var note = byLabel(settings, "Note text"), save = settings.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Save";
  })[0];
  assert.strictEqual(note.value, "east", "the section reads its stored payload");
  note.value = " "; note.listeners.input({});
  assert.strictEqual(save.disabled, true, "a section's problem holds Save");
  assert.match(settings.querySelector(".phc-form-status").textContent, /Note: Enter a note\./);
  note.value = "west wing"; note.listeners.input({});
  var name = byLabel(settings, "Name");
  name.value = "East annex"; name.listeners.input({});
  var joins = byLabel(settings, "New Zones join this Segment");
  joins.checked = true; joins.listeners.change({});
  assert.strictEqual(save.disabled, false);
  click(save);
  var sent = p.actions();
  assert.strictEqual(sent.length, 1);
  assert.strictEqual(sent[0].payload.name, "ph_composer.zones.save_segment_settings");
  assert.deepStrictEqual(sent[0].payload.params, { id: "bsg_annex",
    values: { name: "East annex", colour: "#5588BB" }, expected_values: { name: "Annex", colour: "#5588BB" },
    default: true, expected_default_segment_id: "bsg_house",
    extension_payloads: { "example.segment.note": { text: "west wing" } },
    expected_extension_data: { "example.segment.note": { schema_version: 1, payload: { text: "east" } } } });
});

test("a General-only save leaves every section's stored payload alone and checks no section", function () {
  var p = load();
  registerNote(p);
  click(heading(p, "House").querySelector("[data-row-action='settings']"));
  var settings = dialog(p, "phc-segment-settings-dialog"), name = byLabel(settings, "Name");
  name.value = "Main house"; name.listeners.input({});
  var save = settings.querySelectorAll("button").filter(function (node) { return node.textContent === "Save"; })[0];
  assert.strictEqual(save.disabled, false, "an untouched blank note holds nothing");
  click(save);
  assert.deepStrictEqual(p.actions()[0].payload.params.extension_payloads, {});
});

test("on the default Segment New Zones join is checked and fixed", function () {
  var p = load();
  click(heading(p, "House").querySelector("[data-row-action='settings']"));
  var joins = byLabel(dialog(p, "phc-segment-settings-dialog"), "New Zones join this Segment");
  assert.deepStrictEqual([joins.checked, joins.disabled], [true, true]);
});

test("Cancel, the close icon and Escape each close the settings and write nothing", function () {
  var p = load();
  ["Cancel", "Close", "Escape"].forEach(function (route) {
    click(heading(p, "House").querySelector("[data-row-action='settings']"));
    var settings = dialog(p, "phc-segment-settings-dialog"), name = byLabel(settings, "Name");
    name.value = "Changed"; name.listeners.input({});
    if (route === "Escape") settings.listeners.cancel({ preventDefault: function () {} });
    else if (route === "Close") click(settings.closeButton);
    else {
      click(settings.querySelectorAll("button").filter(function (node) { return node.textContent === "Cancel"; })[0]);
    }
    assert.strictEqual(dialog(p, "phc-segment-settings-dialog"), undefined, route + " closes it");
  });
  assert.strictEqual(p.actions().length, 0);
});

test("a heading contribution shows its tag and findings flag in every view", function () {
  var p = load();
  p.modules.table_views.heading("ph_composer.zones", { id: "example.single_dwelling", order: 20,
    segmentHeading: function (segment) {
      return segment.id === "bsg_house" ? { tags: [{ text: "Single dwelling" }],
        findings: [{ message: "Enter the bedrooms." }] } : null;
    } });
  p.panel.repaint();
  assert.deepStrictEqual(outline(p)[1], ["heading", "House", ["Default", "Single dwelling"]]);
  var flag = heading(p, "House").querySelector(".phc-segment-flag");
  assert.deepStrictEqual([flag.hidden, flag.getAttribute("aria-label")], [false, "Enter the bedrooms."]);
  var spaces = load("ph_composer.spaces");
  spaces.modules.table_views.heading("ph_composer.zones", { id: "example.single_dwelling_b", order: 20,
    segmentHeading: function () { return { tags: [{ text: "Single dwelling" }] }; } });
  spaces.panel.repaint();
  assert.deepStrictEqual(outline(spaces)[1], ["heading", "House", ["Default", "Single dwelling"]]);
});

function answer(p, message, value) {
  p.panel.receive({ type: "query.result", payload: { request_id: message.payload.request_id, session: "session-a",
    outcome: { status: "completed", value: value } } });
}

function queries(p) {
  return p.sent.filter(function (message) { return message.type === "query.invoke"; });
}

function button(root, text) {
  return root.querySelectorAll("button").filter(function (node) { return node.textContent === text; })[0];
}

var SHARED = [{ zone_id: "zon_a", zone_path: [1], entity_path: [11], entity_id: "fac_a" },
  { zone_id: "zon_b", zone_path: [2], entity_path: [21], entity_id: "fac_b" }];

test("moving a Zone out offers to make it the Attached zone of the Faces it shares, in one request", function () {
  var p = load();
  click(zoneRow(p, "Zone A").querySelector(".row-check"));
  choose(byLabel(p.section(), "Building Segment for checked Zones"), "__none");
  complete(p, p.actions()[0], { zone_ids: ["zon_a"] });
  var read = queries(p)[0];
  assert.strictEqual(read.payload.name, "ph_composer.zones.faces.attached_zone.offer");
  assert.strictEqual(read.payload.params.zone.zone_id, "zon_a");
  answer(p, read, { zone_id: "zon_a", name: "Zone A", attached_zone_id: null, faces: SHARED,
    shared_with: ["Zone B"], attached_face_count: 0 });
  var offer = dialog(p, "phc-segment-offer-dialog");
  assert.ok(offer, "the offer opens");
  assert.strictEqual(offer.querySelector("h2").textContent, "Make Zone A an Attached zone?");
  assert.match(offer.querySelector(".phc-segment-consequence").textContent, /1 Face it shares with Zone B/);
  click(button(offer, "Make Attached zone"));
  var made = p.actions()[1];
  assert.strictEqual(made.payload.name, "ph_composer.zones.faces.attached_zone.create_and_assign");
  assert.deepStrictEqual(made.payload.params, { faces: SHARED, values: { name: "Zone A", kind: "other" },
    expected_values: { boundary_condition: "Surface" } });
  assert.strictEqual(dialog(p, "phc-segment-offer-dialog"), undefined);
});

test("the offer reuses an Attached zone of the Zone's name, Not now sends nothing, and moving back notifies",
  function () {
    var p = load();
    click(zoneRow(p, "Zone A").querySelector(".row-check"));
    choose(byLabel(p.section(), "Building Segment for checked Zones"), "__none");
    complete(p, p.actions()[0], { zone_ids: ["zon_a"] });
    answer(p, queries(p)[0], { zone_id: "zon_a", name: "Zone A", attached_zone_id: "atz_zonea", faces: SHARED,
      shared_with: ["Zone B"], attached_face_count: 0 });
    assert.match(dialog(p, "phc-segment-offer-dialog").querySelector(".phc-segment-consequence").textContent,
      /the Attached zone already in this Model/);
    click(button(dialog(p, "phc-segment-offer-dialog"), "Not now"));
    assert.strictEqual(p.actions().length, 1, "Not now writes nothing");

    p = load();
    click(zoneRow(p, "Zone B").querySelector(".row-check"));
    choose(byLabel(p.section(), "Building Segment for checked Zones"), "bsg_house");
    complete(p, p.actions()[0], { zone_ids: ["zon_b"] });
    answer(p, queries(p)[0], { zone_id: "zon_b", name: "Zone B", attached_zone_id: null, faces: [],
      shared_with: [], attached_face_count: 2 });
    assert.strictEqual(dialog(p, "phc-segment-offer-dialog"), undefined, "nothing to offer on the way back");
    assert.match(p.panel.state.ui.notice.message, /Zone B keeps 2 Faces on an Attached zone. Run Solve adjacencies/);
  });

test("two Zones moved out are offered in turn, the second read only once the first write settles", function () {
  var p = load(null, function (state) {
    state.sections["ph_composer.zones.overview"].value.zones[1].values.building_segment_id = "bsg_house";
  });
  click(zoneRow(p, "Zone A").querySelector(".row-check"));
  click(zoneRow(p, "Zone B").querySelector(".row-check"));
  choose(byLabel(p.section(), "Building Segment for checked Zones"), "__none");
  complete(p, p.actions()[0], { zone_ids: ["zon_a", "zon_b"] });
  assert.strictEqual(queries(p).length, 1, "one offer read at a time");
  answer(p, queries(p)[0], { zone_id: "zon_a", name: "Zone A", attached_zone_id: null, faces: SHARED,
    shared_with: ["Zone B"], attached_face_count: 0 });
  click(button(dialog(p, "phc-segment-offer-dialog"), "Make Attached zone"));
  assert.strictEqual(queries(p).length, 1, "the next read waits for the write");
  complete(p, p.actions()[1], { id: "atz_zonea", face_ids: ["fac_a", "fac_b"] });
  assert.strictEqual(queries(p).length, 2);
  assert.strictEqual(queries(p)[1].payload.params.zone.zone_id, "zon_b");
});

test("a Zone moved from none into a New Building Segment gets the Solve notice too", function () {
  var p = load();
  click(zoneRow(p, "Zone B").querySelector(".row-check"));
  choose(byLabel(p.section(), "Building Segment for checked Zones"), "__new");
  assert.strictEqual(queries(p).length, 0);
  complete(p, p.actions()[0], { id: "bsg_annex", name: "Building Segment 2", zone_ids: ["zon_b"] });
  var read = queries(p)[0];
  assert.strictEqual(read.payload.params.zone.zone_id, "zon_b");
  answer(p, read, { zone_id: "zon_b", name: "Zone B", attached_zone_id: null, faces: [], shared_with: [],
    attached_face_count: 1 });
  assert.match(p.panel.state.ui.notice.message, /Zone B keeps 1 Face on an Attached zone/);
});
