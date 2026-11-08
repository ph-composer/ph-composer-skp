"use strict";

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

function page() {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view"]);
  return { context: context, panel: modules.panel, modules: modules, sent: sent,
    query: function (selector) { return context.document.querySelector(selector); } };
}

function snapshot() {
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4,
    file_name: "house.skp", edit_path: [], preferences: {
      unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" }
    },
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

function managedSnapshot() {
  var state = snapshot(), zone = state.sections["ph_composer.zones.overview"].value.zones[0];
  zone.schema_version = 2;
  zone.values = { name: "Zone 1", building_segment_id: "bsg_house", level_id: null, ground_depth_mm: 0 };
  state.sections["ph_composer.zones.options"] = { status: "completed", value: {
    building_segments: [{ id: "bsg_house", values: { name: "House", colour: "#268589",
      export_identifier: "seg_house" }, usage: { live: 1, recoverable: 1 } },
      { id: "bsg_tower", values: { name: "Tower", colour: "#5588BB", export_identifier: "seg_tower" }, usage: {
        live: 0, recoverable: 0 } }],
    levels: [{ id: "lvl_1", values: { name: "Level 1", colour: "#9977AA" }, usage: { live: 0, recoverable: 0 } }],
    default_segment_id: "bsg_house", adoption: { required: false, sources: [], suggested_segment: "House" }
  } };
  return state;
}

/* What a Name cell reads: a Zone's name is an editor on its row, a Face's is text. */
function nameText(td) {
  var input = td.querySelector("input");
  return input ? input.value : td.textContent;
}

/* A control by its accessible name, anywhere in the root's pane: the table, its control row and header, and
   the selection bar over it. */
function byLabel(root, label) {
  var scope = root.closest("[data-pane]") || root;
  return scope.querySelectorAll("input, select, button").filter(function (node) {
    return node.getAttribute("aria-label") === label;
  })[0];
}

function settingsPage() {
  var p = page(), state = snapshot();
  state.sections["ph_composer.zones.settings"] = { status: "completed", value: {
    suggest_on_make: true, roof_angle_deg: 60, floor_angle_deg: 130
  } };
  p.panel.receive({ type: "panel.snapshot", payload: state });
  p.section = p.query("[data-section='ph_composer.overview']");
  p.settings = byLabel(p.section, "Faces settings");
  p.settings.listeners.click({});
  return p;
}

test("Faces settings commit Enter once with the reviewed values and revision", function () {
  var p = settingsPage(), roof = byLabel(p.section, "Roof maximum tilt [deg]");
  assert.ok(panelSource.markup("index.html").includes('data-tab="overview">Zones<'));
  roof.value = "45";
  roof.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  roof.listeners.change({});

  assert.strictEqual(p.sent.length, 1);
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.settings.update");
  assert.strictEqual(p.sent[0].payload.expected_revision, 4);
  assert.deepStrictEqual(p.sent[0].payload.params, {
    values: { suggest_on_make: true, roof_angle_deg: 45, floor_angle_deg: 130 },
    expected_values: { suggest_on_make: true, roof_angle_deg: 60, floor_angle_deg: 130 }
  });
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  var bubble = p.section.querySelector(".phc-bubble");
  bubble._bubble.close(true);
  assert.strictEqual(bubble.hidden, false, "the pending operation keeps its work surface visible");
});

test("Faces settings reject invalid angles locally and Escape restores the field", function () {
  var p = settingsPage(), roof = byLabel(p.section, "Roof maximum tilt [deg]");
  roof.value = "140";
  roof.listeners.change({});
  assert.strictEqual(p.sent.length, 0);
  assert.ok(p.section.querySelector(".phc-form-status").textContent.includes("roof angle below"));
  roof.listeners.keydown({ key: "Escape" });
  assert.strictEqual(roof.value, "60");
});


function rowAction(root, id) {
  return root.querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("data-row-action") === id;
  })[0];
}

function suggest(root) {
  return rowAction(root, "suggest");
}

test("Overview has no placeholder section beneath the feature work surface", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });

  assert.strictEqual(Boolean(p.query("[data-section='overview']")), false);
  assert.strictEqual(p.query("[data-pane='overview']").textContent.includes("Nothing to show yet."), false);
});

test("area headers and Zone and Face values follow the display profile together", function () {
  var p = page(), payload = snapshot();
  payload.preferences.unit_system = "IP";
  var faces = payload.sections["ph_composer.zones.faces.faces"].value.faces;
  faces[0].area_m2 = 1;
  var additional = JSON.parse(JSON.stringify(faces[0]));
  additional.area_m2 = 3;
  additional.reference.entity_path = [103];
  additional.reference.entity_id = "fac_c";
  faces.push(additional);
  // The host totals the occurrence's Faces; the panel shows its numbers and sums nothing.
  payload.sections["ph_composer.zones.overview"].value.zones[0].face_area_m2 = 12;
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  assert.ok(section.querySelectorAll("select").some(function (node) {
    return node.classList.contains("phc-enum-cell") && node.classList.contains("phc-cell-input");
  }), "a Face's type and boundary chips are the kit's enum cell");
  function areas() {
    return section.querySelectorAll(".col-area_m2").filter(function (node) { return node.tagName === "td"; })
      .map(nameText);
  }
  function header() {
    return section.querySelectorAll(".col-area_m2").filter(function (node) { return node.tagName === "th"; })[0];
  }

  assert.ok(header().querySelector(".phc-th-label").textContent.includes("Gross area ft²"));
  assert.deepStrictEqual(areas(), ["129.17", "10.76", "32.29", "86.11", "86.11"],
    "the Zone over every Face it has, its two recorded Faces, then the unclassified as a group and one by one");
  p.modules.unit_preferences.set("unit_system", "SI");
  p.panel.repaint();
  assert.ok(header().querySelector(".phc-th-label").textContent.includes("Gross area m²"));
  assert.deepStrictEqual(areas(), ["12", "1", "3", "8", "8"]);
  assert.strictEqual(faces[0].area_m2, 1, "display changes leave the canonical snapshot alone");
});

test("Overview leaves Make Zone and its blocked explanation to the native menu", function () {
  var p = page(), payload = snapshot();
  [payload.sections["ph_composer.zones.overview"].value.make_zone, null].forEach(function (target) {
    payload.sections["ph_composer.zones.overview"].value.make_zone = target;
    p.panel.receive({ type: "panel.snapshot", payload: payload });
    var section = p.query("[data-section='ph_composer.overview']");
    assert.ok(!section.querySelectorAll("button").some(function (node) {
      return /Make Zone/.test(node.textContent + " " + node.getAttribute("aria-label"));
    }));
    assert.strictEqual(section.querySelector(".phc-heading .phc-blocked-reason"), null);
  });
  assert.strictEqual(p.sent.length, 0);
});

function solvePage() {
  var p = checkPage(), zones = p.payload.sections["ph_composer.zones.overview"].value.zones;
  var faces = p.payload.sections["ph_composer.zones.faces.faces"].value.faces;
  var original = faces.slice();
  [2, 3].forEach(function (number) {
    var zone = JSON.parse(JSON.stringify(zones[0]));
    zone.id = zone.reference.zone_id = "zon_" + number;
    zone.reference.zone_path = [number * 100]; zone.values.name = "Zone " + number;
    zones.push(zone);
    original.forEach(function (face) {
      var copy = JSON.parse(JSON.stringify(face));
      copy.reference.zone_id = zone.id; copy.reference.zone_path = zone.reference.zone_path;
      copy.reference.entity_id += "_" + number;
      faces.push(copy);
    });
  });
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  return p;
}
function solveButton(p) { return bar(p).querySelector(".phc-zone-selection-controls").querySelector("button"); }

test("Solve requires two fully checked Zones and submits only those occurrences", function () {
  var p = solvePage(), solve = solveButton(p);
  assert.strictEqual(bar(p).hidden, true);
  click(p.box("Wall 1"));
  assert.strictEqual(solve.parentNode.hidden, true, "a partial Zone does not offer Zone Solve");
  click(p.box("Zone 2"));
  assert.strictEqual(solve.disabled, true);
  assert.strictEqual(bar(p).querySelector(".phc-checked-zone-count").textContent, "1 Zone checked");
  click(solve); assert.strictEqual(p.sent.length, 0);
  click(p.box("Zone 1"));
  assert.strictEqual(solve.disabled, false);
  assert.strictEqual(bar(p).querySelector(".phc-checked-zone-count").textContent, "2 Zones checked");
  click(solve);
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.solve_adjacency");
  assert.strictEqual(p.sent[0].payload.expected_revision, 4);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload.params)), {
    zones: [{ zone_id: "zon_a", zone_path: [100] }, { zone_id: "zon_2", zone_path: [200] }]
  });
  assert.strictEqual(solve.disabled, true, "an in-flight edit prevents a second Solve");
  click(solve); assert.strictEqual(p.sent.length, 1);
});

test("filtering preserves checked Solve scope; a neighbour refusal leaves checks intact", function () {
  var p = solvePage();
  click(p.box("Zone 1")); click(p.box("Zone 2"));
  var filter = byLabel(p.section, "Filter Zones");
  filter.value = "Zone 2"; filter.listeners.input({});
  assert.strictEqual(bar(p).querySelector(".phc-checked-zone-count").textContent, "2 Zones checked");
  var solve = solveButton(p); click(solve);
  assert.strictEqual(p.sent[0].payload.params.zones.length, 2);
  p.panel.receive({ type: "action.result", payload: { request_id: p.sent[0].payload.request_id,
    session: "session-a", outcome: { status: "refused", code: "scope.incomplete", effect: "none",
      message: "Updating this adjacency would change Zone 3. Check that Zone too and solve again." } } });
  assert.match(p.query(".phc-floating-notice-message").textContent, /Zone 3/);
  assert.strictEqual(solve.disabled, false);
  assert.strictEqual(bar(p).querySelector(".phc-checked-zone-count").textContent, "2 Zones checked");
  click(bar(p).querySelector(".phc-selection-bar-clear"));
  assert.strictEqual(bar(p).hidden, true);
  assert.strictEqual(solve.parentNode.hidden, true);
});

test("unchecking a Face makes its Zone ineligible and Select all restores whole-model scope", function () {
  var p = solvePage();
  click(p.box("Zone 1")); click(p.box("Zone 2"));
  click(p.box("Wall 1"));
  assert.strictEqual(solveButton(p).disabled, true);
  assert.strictEqual(bar(p).querySelector(".phc-checked-zone-count").textContent, "1 Zone checked");
  click(p.header());
  assert.strictEqual(bar(p).querySelector(".phc-checked-zone-count").textContent, "3 Zones checked");
  // A shared Zone refuses every write, so Solve is refused whole rather than dropping it from the scope.
  p.payload.sections["ph_composer.zones.overview"].value.zones[2].state = "ambiguous";
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(solveButton(p).disabled, true);
  assert.strictEqual(bar(p).querySelector(".phc-checked-zone-count").textContent, "3 Zones checked");
  click(solveButton(p));
  assert.strictEqual(p.sent.length, 0);
});

test("painting preserves checked Solve scope and a Model switch clears it", function () {
  var p = solvePage();
  click(p.box("Zone 1")); click(p.box("Zone 2"));
  var solve = solveButton(p);
  p.payload.sections["ph_composer.zones.faces.palette"].value.active = true;
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(solve.parentNode.hidden, false);
  assert.strictEqual(solve.disabled, false);
  p.payload.sections["ph_composer.zones.faces.palette"].value.active = false;
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(solve.parentNode.hidden, false);
  assert.strictEqual(solve.disabled, false);
  p.payload.session = "session-b";
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(bar(p).hidden, true);
  assert.strictEqual(solveButton(p).parentNode.hidden, true);
  assert.strictEqual(solveButton(p).disabled, true);
});

test("a Face chip sets one field, keeps the other, and guards on the values it painted", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");
  var chip = byLabel(section, "Wall 1 boundary");

  chip.value = "Ground";
  chip.listeners.change({});

  var sent = p.sent[0].payload;
  assert.strictEqual(sent.name, "ph_composer.zones.faces.classify");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(sent.params)), {
    faces: [{ zone_id: "zon_a", zone_path: [100], entity_path: [101], entity_id: "fac_a" }],
    intent: {
      face_type: { mode: "keep" },
      boundary_condition: { mode: "set", value: "Ground" }
    },
    expected_values: { face_type: "Wall", boundary_condition: "Outdoors" }
  });
});

test("an unclassified Face is a row under its Zone's summary, and choosing a value classifies it", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");

  var names = section.querySelectorAll(".col-name").filter(function (node) { return node.tagName === "td"; })
    .map(nameText);
  assert.deepStrictEqual(names, ["Zone 1", "Wall 1", "1 unclassified Face", "Face 1"]);
  assert.strictEqual(section.querySelector(".phc-row-marker").textContent, "1", "the Zone still counts them");

  var type = byLabel(section, "Set Face 1 type");
  assert.strictEqual(byLabel(section, "Face 1 Assembly"), undefined, "no Assembly before there is a record");
  type.value = "Floor";
  type.listeners.change({});
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.faces.classify");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload.params)), {
    faces: [{ zone_id: "zon_a", zone_path: [100], entity_path: [102], entity_id: null }],
    intent: { face_type: { mode: "set", value: "Floor" }, boundary_condition: { mode: "keep" } },
    expected_values: {}
  });

  p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  suggest(p.query("[data-section='ph_composer.overview']")).listeners.click({});
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.faces.auto_classify");
});

test("a long list of unclassified Faces waits to be opened and shows its first fifty", function () {
  var p = page(), payload = snapshot();
  var faces = payload.sections["ph_composer.zones.faces.faces"].value.faces, index;
  for (index = 0; index < 60; index += 1) {
    faces.push({ reference: { zone_id: "zon_a", zone_path: [100], entity_path: [500 + index], entity_id: null },
      zone_name: "Zone 1", area_m2: 1, state: "unclassified", values: {}, suggested: {} });
  }
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  function count() { return section.querySelectorAll("[data-row-key]").length; }
  assert.strictEqual(count(), 3, "the Zone, its Face and the summary: sixty-one rows are not painted unasked");
  var chevron = section.querySelectorAll(".row-chevron").filter(function (node) {
    return /unclassified/.test(node.getAttribute("aria-label"));
  })[0];
  chevron.listeners.click({});
  assert.strictEqual(count(), 3 + 50 + 1, "fifty Faces and one row offering the rest");
  var more = section.querySelectorAll(".row-target").filter(function (node) {
    return node.textContent === "Show all";
  })[0];
  more.listeners.click({});
  assert.strictEqual(count(), 3 + 61);
});

/* A copied Zone Group shares its original's dictionary until it is repaired, so two occurrences can
   carry one record id. The tree is built from occurrences, not ids, or the copy takes the
   original's place and its Faces and area are summed into it. */
test("two Zone occurrences sharing one record id are two rows", function () {
  var p = page();
  var payload = snapshot();
  var overview = payload.sections["ph_composer.zones.overview"].value;
  var faces = payload.sections["ph_composer.zones.faces.faces"].value;
  overview.zones = overview.zones.concat([{ id: "zon_a", schema_version: 1, user_data: {}, extension_data: {},
    reference: { zone_id: "zon_a", zone_path: [200] }, state: "ambiguous", face_count: 1,
    values: { name: "Zone 1 copy", building_segment: "house", level: null, ground_depth_mm: 0 } }]);
  overview.zones[0].state = "ambiguous";
  faces.faces = faces.faces.concat([{
    reference: { zone_id: "zon_a", zone_path: [200], entity_path: [201], entity_id: "fac_b" },
    zone_name: "Zone 1 copy", area_m2: 5, state: "classified",
    values: { face_type: "Floor", boundary_condition: "Ground" },
    suggested: { face_type: "Floor", boundary_condition: "Ground" }
  }]);
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");

  var names = section.querySelectorAll(".col-name").filter(function (node) { return node.tagName === "td"; })
    .map(nameText);
  assert.deepStrictEqual(names, ["Zone 1", "Wall 1", "1 unclassified Face", "Face 1", "Zone 1 copy", "Floor 1"],
    "each occurrence keeps its own row and its own Faces");
  var markers = section.querySelectorAll(".phc-row-marker").filter(function (node) {
    return node.classList.contains("is-icon") && /same identity/.test(node.getAttribute("aria-label"));
  });
  assert.strictEqual(markers.length, 2, "both occurrences say why, and neither is called the copy");
});

/* A Face row must not be rekeyed or renamed because a neighbour was classified: the table drops a
   rekeyed row's cached entry, and with it the selection and any edit in progress. */
test("classifying one Face leaves its neighbours' rows alone", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");
  var before = section.querySelectorAll("[data-row-key]").map(function (node) {
    return node.getAttribute("data-row-key");
  });

  var payload = snapshot();
  var faces = payload.sections["ph_composer.zones.faces.faces"].value.faces;
  faces[1].state = "classified";
  faces[1].values = { face_type: "Floor", boundary_condition: "Ground" };
  p.panel.receive({ type: "panel.snapshot", payload: payload });

  var after = section.querySelectorAll("[data-row-key]").map(function (node) {
    return node.getAttribute("data-row-key");
  });
  assert.ok(after.every(function (key) { return before.indexOf(key) >= 0; }),
    "every row still there keeps its key, the newly classified Face included");
  assert.strictEqual(after.length, before.length - 1, "only the emptied summary row goes");
  var names = section.querySelectorAll(".col-name").filter(function (node) { return node.tagName === "td"; })
    .map(nameText);
  assert.deepStrictEqual(names, ["Zone 1", "Wall 1", "Floor 1"],
    "and a Face numbers among the Faces of its own type");
});

/* A stored value no chip offers reads as what it is rather than vanishing from the control. */
test("a Face the chips cannot set keeps its value and stays read only", function () {
  var p = page();
  var payload = snapshot();
  payload.sections["ph_composer.zones.faces.faces"].value.faces[0].values = {
    face_type: "AirBoundary", boundary_condition: "Surface"
  };
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");

  assert.strictEqual(byLabel(section, "Air boundary 1 type"), undefined, "no chip offers Air boundary");
  var cells = section.querySelectorAll(".col-face_type").filter(function (node) { return node.tagName === "td"; });
  assert.strictEqual(cells[1].querySelector(".phc-enum-pill").textContent, "Air boundary",
    "the cell says what the Face is, as a read-only pill");
  assert.match(cells[1].getAttribute("data-tooltip"), /Air boundary/);
  assert.strictEqual(cells[1].getAttribute("title"), null);
});

test("Locate goes to the viewport channel and never to an action", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");

  rowAction(section, "locate").listeners.click({});

  assert.strictEqual(p.sent[0].type, "view.invoke");
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.faces.locate");
  assert.strictEqual(p.sent[0].payload.params.faces.length, 2,
    "a Zone locates every Face it has, recorded or not, as its rows now list them");
  assert.strictEqual(p.sent[0].payload.expected_revision, undefined, "a view command guards no revision");
});

function enter(control, text) {
  control.value = text;
  control.listeners.input({});
  control.listeners.keydown({ key: "Enter", preventDefault: function () {} });
}

test("a Zone's fields are cells on its row, and each commit is one update of that value", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");
  assert.strictEqual(p.query("[data-section='ph_composer.zones.details']"), null, "there is no Zone form");
  assert.strictEqual(byLabel(section, "Zone 1 Building-Segment").textContent, "house");
  assert.strictEqual(byLabel(section, "Wall 1 Level"), undefined, "a Face row leaves the Zone columns blank");

  enter(byLabel(section, "Zone 1 name"), "North Zone");

  assert.strictEqual(p.sent.length, 1);
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.update");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload.params)), {
    reference: { zone_id: "zon_a", zone_path: [100] },
    values: { name: "North Zone", building_segment: "house", level: null, ground_depth_mm: 0 },
    expected_values: { name: "Zone 1", building_segment: "house", level: null, ground_depth_mm: 0 }
  });
});

test("a Zone's Ground depth follows display units and sends canonical millimetres", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  p.modules.unit_preferences.set("unit_system", "IP");
  p.panel.repaint();
  var section = p.query("[data-section='ph_composer.overview']");
  assert.ok(section.querySelectorAll(".phc-th-label").some(function (label) {
    return /^Ground depth in/.test(label.textContent);
  }));
  enter(byLabel(section, "Zone 1 ground depth"), "1 ft");
  assert.strictEqual(p.sent[0].payload.params.values.ground_depth_mm, 304.8);
});

test("managed choices use IDs, unchanged choices send nothing, and an empty Level is no Level", function () {
  var p = page(), payload = managedSnapshot();
  payload.sections["ph_composer.zones.overview"].value.zones[0].values.level_id = "lvl_1";
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.listeners.change({});
  assert.strictEqual(p.sent.length, 0);
  var level = byLabel(section, "Zone 1 Level"); level.value = ""; level.listeners.change({});
  assert.strictEqual(p.sent[0].payload.params.values.level_id, null);
  assert.strictEqual(p.sent[0].payload.params.expected_values.level_id, "lvl_1");
});

test("an invalid Ground depth or a blank name sends nothing and says why on the cell", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), depth = byLabel(section, "Zone 1 ground depth");
  enter(depth, "deep");
  enter(byLabel(section, "Zone 1 name"), "  ");
  assert.strictEqual(p.sent.length, 0);
  assert.strictEqual(depth.getAttribute("aria-invalid"), "true");
  assert.ok(depth.parentNode.querySelector(".cell-error").textContent);
});

function result(p, index, outcome) {
  p.panel.receive({ type: "action.result", payload: { request_id: p.sent[index].payload.request_id,
    session: "session-a", outcome: outcome } });
}

/* A managed snapshot with a third Segment, so a held choice can be retried with a different one. */
function threeSegments() {
  var payload = managedSnapshot();
  payload.sections["ph_composer.zones.options"].value.building_segments.push({ id: "bsg_annex",
    values: { name: "Annex", colour: "#AA7755", export_identifier: "seg_annex" }, usage: { live: 0, recoverable: 0 } });
  return payload;
}

test("a refused Zone choice returns to the Model's value, says why, and leaves the screen usable", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "refused", code: "target.ambiguous", effect: "none",
    message: "Zone zon_a occurs more than once. Nothing was written." });
  assert.strictEqual(segment.value, "bsg_house", "nothing was written, so the Model's value shows");
  assert.match(segment.parentNode.querySelector(".cell-error").textContent, /made independent/);
  assert.match(p.query(".phc-floating-notice-message").textContent, /made independent/,
    "the notice names the route out, not the duplicated id");
  assert.strictEqual(byLabel(section, "Cancel Zone 1 Building-Segment choice").hidden, true, "nothing is held");
  enter(byLabel(section, "Zone 1 name"), "North Zone");
  assert.strictEqual(p.sent[1].payload.name, "ph_composer.zones.update", "another edit is not blocked");
});

test("a failed Zone choice with an uncertain effect shows the Model's value and says to check it", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "failed", code: "operation.failed", effect: "unknown", message: "It broke." });
  assert.strictEqual(segment.value, "bsg_house");
  assert.match(segment.parentNode.querySelector(".cell-error").textContent, /may have been partly applied/);
});

test("a held Zone choice has a visible Cancel, and the guard notice offers it too", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  var cancel = byLabel(section, "Cancel Zone 1 Building-Segment choice");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "completed", effect: "committed" });
  assert.strictEqual(segment.value, "bsg_tower", "the Model settled elsewhere, so the choice is held");
  assert.strictEqual(cancel.hidden, false);
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "overview", "a held choice guards navigation");
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  assert.strictEqual(cancel.hidden, false, "a later snapshot keeps the held choice and its Cancel");
  click(cancel);
  assert.strictEqual(segment.value, "bsg_house");
  assert.strictEqual(cancel.hidden, true);
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "export", "Cancel released the guard without a request");
  assert.strictEqual(p.sent.length, 1);
});

test("the guard notice's Cancel drops a held Zone choice", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "completed", effect: "committed" });
  var filter = byLabel(section, "Filter Zones");
  filter.value = "Zone"; filter.listeners.input({});
  assert.strictEqual(p.query(".phc-floating-notice-message").textContent, "Finish or cancel the Zone edit first.");
  var action = p.query(".phc-floating-notice-action");
  assert.strictEqual(action.hidden, false);
  assert.strictEqual(action.textContent, "Cancel the Zone edit");
  click(action);
  assert.strictEqual(segment.value, "bsg_house");
  assert.strictEqual(p.query(".phc-floating-notice").hidden, true);
  filter.value = "Zone"; filter.listeners.input({});
  assert.strictEqual(filter.value, "Zone", "the filter is no longer refused");
  assert.strictEqual(p.sent.length, 1);
});

test("choosing the Model's value cancels a held choice; a new choice retries with current values", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: threeSegments() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "completed", effect: "committed" });
  segment.value = "bsg_house"; segment.listeners.change({});
  assert.strictEqual(p.sent.length, 1, "the Model's own value cancels without a request");
  assert.strictEqual(byLabel(section, "Cancel Zone 1 Building-Segment choice").hidden, true);
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 1, { status: "completed", effect: "committed" });
  var moved = threeSegments();
  moved.sections["ph_composer.zones.overview"].value.zones[0].values.level_id = "lvl_1";
  p.panel.receive({ type: "panel.snapshot", payload: moved });
  assert.match(segment.parentNode.querySelector(".cell-error").textContent, /Changed in the Model/);
  segment.value = "bsg_annex"; segment.listeners.change({});
  assert.strictEqual(p.sent.length, 3, "a held choice retries instead of being ignored");
  assert.strictEqual(p.sent[2].payload.params.expected_values.level_id, "lvl_1", "against the current values");
  assert.strictEqual(segment.parentNode.querySelector(".cell-error").hidden, true);
});

test("a refused Zone name keeps the typed text until a visible Cancel restores the Model's name", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), name = byLabel(section, "Zone 1 name");
  var cancel = byLabel(section, "Cancel Zone 1 name edit");
  assert.strictEqual(cancel.hidden, true);
  enter(name, "North Zone");
  result(p, 0, { status: "refused", code: "target.shared_definition", effect: "none", message: "Shared." });
  assert.strictEqual(name.value, "North Zone", "the typed text survives the refusal");
  assert.match(name.parentNode.querySelector(".cell-error").textContent, /reach both/);
  assert.strictEqual(cancel.hidden, false);
  name.listeners.blur({});
  name.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.strictEqual(p.sent.length, 1, "Enter and blur do not resubmit a refused draft");
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  click(cancel);
  assert.strictEqual(name.value, "Zone 1");
  assert.strictEqual(cancel.hidden, true);
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "export");
  assert.strictEqual(p.sent.length, 1, "Cancel writes nothing");
});

test("the Zone screen restates its own refused write and leaves another request's message alone", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");
  var notice = function () { return p.query(".phc-floating-notice").message.textContent; };
  enter(byLabel(section, "Zone 1 name"), "North Zone");
  result(p, 0, { status: "refused", code: "target.shared_definition", effect: "none", message: "Shared." });
  assert.match(notice(), /reach both/);
  p.panel.receive({ type: "action.result", payload: { request_id: "session-a:other:1", session: "session-a",
    outcome: { status: "refused", code: "target.shared_definition", effect: "none", message: "Not ours." } } });
  assert.strictEqual(notice(), "Not ours.");
});

test("an invalid Ground depth offers Cancel, which restores the Model's value", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), depth = byLabel(section, "Zone 1 ground depth");
  enter(depth, "deep");
  click(byLabel(section, "Cancel Zone 1 ground depth edit"));
  assert.strictEqual(depth.getAttribute("aria-invalid"), "false");
  assert.strictEqual(p.sent.length, 0);
});

test("a refused tab change while a Zone choice is held offers Cancel on its notice", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "completed", effect: "committed" });
  p.panel.showTab("export");
  click(p.query(".phc-floating-notice-action"));
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "export");
});

test("a typed draft its Zone turns read only underneath keeps a visible Cancel", function () {
  var p = page(), payload = snapshot();
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']"), name = byLabel(section, "Zone 1 name");
  name.value = "North"; name.listeners.input({});
  payload = snapshot();
  payload.sections["ph_composer.zones.overview"].value.zones[0].state = "shared_definition";
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var cancel = byLabel(section, "Cancel Zone 1 name edit");
  assert.strictEqual(cancel.hidden, false);
  click(cancel);
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "export", "nothing is left holding the screen");
});

test("a refused choice's reason clears once the Zone it was refused against changes", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "refused", code: "target.ambiguous", effect: "none", message: "Duplicated." });
  var error = segment.parentNode.querySelector(".cell-error");
  assert.strictEqual(error.hidden, false);
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  assert.strictEqual(error.hidden, false, "an unchanged Zone keeps the reason");
  var renamed = managedSnapshot();
  renamed.sections["ph_composer.zones.overview"].value.zones[0].values.name = "Renamed";
  p.panel.receive({ type: "panel.snapshot", payload: renamed });
  assert.strictEqual(error.hidden, true);
});

/* Zone 1 and a copy carrying its id, both read "ambiguous", plus Zone 2, an ordinary Zone. */
function sharedPage() {
  var p = checkPage(), payload = p.payload;
  var zones = payload.sections["ph_composer.zones.overview"].value.zones;
  var faces = payload.sections["ph_composer.zones.faces.faces"].value.faces;
  var copy = JSON.parse(JSON.stringify(zones[0])), other = JSON.parse(JSON.stringify(zones[0]));
  copy.reference.zone_path = [200]; copy.values.name = "Zone 1 copy";
  other.id = other.reference.zone_id = "zon_2"; other.reference.zone_path = [300]; other.values.name = "Zone 2";
  zones[0].state = copy.state = "ambiguous";
  zones.push(copy, other);
  faces.push({ reference: { zone_id: "zon_2", zone_path: [300], entity_path: [301], entity_id: "fac_z2" },
    zone_name: "Zone 2", area_m2: 4, state: "classified",
    values: { face_type: "Floor", boundary_condition: "Outdoors" },
    suggested: { face_type: "Floor", boundary_condition: "Outdoors" } });
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  return p;
}

test("a shared Zone's cells and its Faces' chips are read only, and Suggest says why", function () {
  var p = sharedPage();
  assert.strictEqual(byLabel(p.section, "Zone 1 name").readOnly, true);
  assert.strictEqual(byLabel(p.section, "Wall 1 type"), undefined, "the Face's type is a read-only pill");
  assert.strictEqual(byLabel(p.section, "Zone 2 name").readOnly, false, "an ordinary Zone stays editable");
  var suggest = p.section.querySelectorAll("[data-row-action='suggest']").filter(function (node) {
    return /Zone 1\b/.test(node.getAttribute("aria-label") || "");
  })[0];
  assert.strictEqual(suggest.disabled, true);
  assert.match(suggest.getAttribute("aria-label"), /read only/);
});

test("an eligible shared Zone offers Make independent, names what it costs, and sends one action", function () {
  var p = sharedPage(), zones = p.payload.sections["ph_composer.zones.overview"].value.zones;
  zones[0].independence = { available: true, code: null, reason: null, retired_pairs: 2 };
  zones[1].independence = { available: false, code: "target.locked", reason: "Unlock it first.", retired_pairs: 0 };
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  var offered = p.section.querySelectorAll("[data-row-action='independent']");
  assert.strictEqual(offered.length, 1, "only the occurrence the command can act on");
  assert.match(p.section.querySelectorAll(".phc-row-marker").filter(function (m) {
    return m.classList.contains("is-icon");
  })[1].getAttribute("aria-label"), /Unlock it first/,
    "the other says what comes first");
  click(offered[0]);
  var dialog = p.query("dialog");
  assert.match(dialog.querySelector("p").textContent, /2 Surface pairs on this occurrence's Faces are retired/);
  var buttons = dialog.querySelectorAll("button");
  click(buttons.filter(function (b) { return b.textContent === "Locate"; })[0]);
  assert.strictEqual(p.sent[p.sent.length - 1].payload.name, "ph_composer.zones.faces.locate");
  click(buttons.filter(function (b) { return b.textContent === "Make independent"; })[0]);
  var sent = p.sent[p.sent.length - 1].payload;
  assert.strictEqual(sent.name, "ph_composer.zones.make_independent");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(sent.params)), { zone_path: [100] });
});

test("a checked Face in a shared Zone refuses the bar's assignment whole and says why", function () {
  var p = sharedPage();
  click(p.box("Floor 1")); click(p.box("Wall 1"));
  assert.strictEqual(byLabel(bar(p), "Type for selected Faces").disabled, true);
  assert.strictEqual(byLabel(bar(p), "Boundary for selected Faces").disabled, true);
  assert.ok(byLabel(bar(p), "Why Assign is unavailable"));
  assert.strictEqual(bar(p).querySelector(".phc-selection-bar-count").textContent, "2 Faces selected",
    "the checked set is kept whole");
  click(p.box("Wall 1"));
  assert.strictEqual(byLabel(bar(p), "Type for selected Faces").disabled, false);
});

function attachedDialog(p, payload) {
  p.panel.receive({ type: "panel.snapshot", payload: payload || snapshot() });
  var chip = byLabel(p.query("[data-section='ph_composer.overview']"), "Wall 1 boundary");
  if (chip.tagName === "button") chip.listeners.click({});
  else { chip.value = "AttachedZone"; chip.listeners.change({}); }
  return p.query("dialog");
}

test("inline Attached-zone creation cancels without writing or changing the Face chip", function () {
  var p = page(), dialog = attachedDialog(p);
  assert.strictEqual(p.sent.length, 0);
  assert.strictEqual(byLabel(p.query("[data-section='ph_composer.overview']"), "Wall 1 boundary").value, "Outdoors");
  dialog.listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(p.sent.length, 0);
  assert.strictEqual(p.query("dialog"), null);
  assert.strictEqual(p.context.document.activeElement.getAttribute("aria-label"), "Wall 1 boundary");
});

test("inline create-and-assign sends one action with the original Face and reviewed revision", function () {
  var p = page(), dialog = attachedDialog(p);
  var newer = snapshot(); newer.revision = 9;
  p.panel.receive({ type: "panel.snapshot", payload: newer });
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.sent.length, 1);
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.faces.attached_zone.create_and_assign");
  assert.strictEqual(p.sent[0].payload.expected_revision, 4);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload.params)), {
    faces: [snapshot().sections["ph_composer.zones.faces.faces"].value.faces[0].reference],
    expected_values: { face_type: "Wall", boundary_condition: "Outdoors" },
    values: { name: "Attached zone 1", kind: "other", temperature_reduction_factor: 0.95 }
  });
  dialog.listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(p.query("dialog"), dialog, "pending writes keep their controls visible");
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.sent.length, 1, "one in-flight request");
});

test("a refused inline assignment preserves the draft; success closes and restores focus", function () {
  var p = page(), dialog = attachedDialog(p), form = dialog.querySelector("form");
  byLabel(dialog, "Name").value = "Garage draft";
  form.listeners.submit({ preventDefault: function () {} });
  p.panel.receive({ type: "action.result", payload: { request_id: p.sent[0].payload.request_id,
    session: "session-a", outcome: { status: "refused", message: "The Face changed." } } });
  assert.strictEqual(p.query("dialog"), dialog);
  assert.strictEqual(byLabel(dialog, "Name").value, "Garage draft");
  assert.strictEqual(dialog.querySelector("[role='status']").textContent, "The Face changed.");
  assert.strictEqual(dialog.querySelector(".phc-action-apply").disabled, false);
  form.listeners.submit({ preventDefault: function () {} });
  p.panel.receive({ type: "action.result", payload: { request_id: p.sent[1].payload.request_id,
    session: "session-a", outcome: { status: "completed", value: { id: "atz_new", face_ids: ["fac_a"] } } } });
  assert.strictEqual(p.query("dialog"), null);
  assert.strictEqual(p.context.document.activeElement.getAttribute("aria-label"), "Wall 1 boundary");
});

test("an existing Attached-zone choice assigns without creating a definition", function () {
  var p = page(), payload = snapshot();
  payload.sections["ph_composer.zones.faces.attached_zone.list"] = { status: "completed", value: {
    records: [{ id: "atz_existing", values: { name: "Garage" } }]
  } };
  var dialog = attachedDialog(p, payload), picker = byLabel(dialog, "Attached zone");
  picker.value = "atz_existing"; picker.listeners.change({});
  assert.strictEqual(byLabel(dialog, "Name").disabled, true);
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.faces.classify");
  assert.strictEqual(p.sent[0].payload.params.intent.attached_zone_id.value, "atz_existing");
  assert.strictEqual(p.sent[0].payload.params.values, undefined);
});

test("an incomplete AttachedZone Face can open and cancel inline creation", function () {
  var p = page(), payload = snapshot();
  payload.sections["ph_composer.zones.faces.faces"].value.faces[0].values.boundary_condition = "AttachedZone";
  var dialog = attachedDialog(p, payload);
  assert.ok(dialog);
  dialog.listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(p.sent.length, 0);
  assert.strictEqual(payload.sections["ph_composer.zones.faces.faces"].value.faces[0]
    .values.attached_zone_id, undefined);
});

test("switching Models withdraws the pending Attached-zone draft", function () {
  var p = page(); attachedDialog(p);
  var other = snapshot(); other.session = "session-b";
  p.panel.receive({ type: "panel.snapshot", payload: other });
  assert.strictEqual(p.query("dialog"), null);
  assert.strictEqual(p.sent.length, 0);
});

function batchSnapshot(token) {
  var payload = snapshot();
  payload.sections["ph_composer.zones.faces.selection_assignment"] = { status: "completed", value: {
    token: token || "review-1", revision: 4,
    faces: payload.sections["ph_composer.zones.faces.faces"].value.faces.map(function (face) { return face.reference; })
  } };
  return payload;
}

test("native assignment retries a refused tab switch after the guard releases", function () {
  var p = page(), blocked = true;
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  p.panel.showTab("export");
  p.panel.navigationGuard("export-work", function () { return blocked ? "Export is busy." : null; });
  p.panel.receive({ type: "panel.snapshot", payload: batchSnapshot() });
  assert.strictEqual(p.panel.state.ui.activeTab, "export");
  assert.strictEqual(p.query("dialog"), null);
  blocked = false;
  p.panel.repaint();
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  assert.ok(p.query("dialog"));
  assert.strictEqual(p.sent.length, 0);
});

test("native batch assignment switches to the Zones tab and freezes heterogeneous targets and revision", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  p.panel.showTab("export");
  p.panel.receive({ type: "panel.snapshot", payload: batchSnapshot() });
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  var dialog = p.query("dialog");
  assert.ok(dialog);
  assert.strictEqual(p.sent.length, 0);
  var newer = batchSnapshot(); newer.revision = 12;
  p.panel.receive({ type: "panel.snapshot", payload: newer });
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  var sent = JSON.parse(JSON.stringify(p.sent[0].payload));
  assert.strictEqual(sent.name, "ph_composer.zones.faces.attached_zone.create_and_assign");
  assert.strictEqual(sent.expected_revision, 4);
  var reviewedFaces = batchSnapshot().sections["ph_composer.zones.faces.selection_assignment"].value.faces;
  assert.deepStrictEqual(sent.params.faces, reviewedFaces);
  assert.strictEqual(sent.params.expected_values, undefined);
  p.panel.showTab("export");
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  dialog.listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(p.query("dialog"), dialog, "pending batch cannot disappear");
  p.panel.receive({ type: "action.result", payload: { session: "session-a", request_id: sent.request_id,
    outcome: { status: "refused", message: "The Model changed." } } });
  assert.strictEqual(p.query("dialog"), dialog);
  assert.strictEqual(dialog.querySelector("[role='status']").textContent, "The Model changed.");
  dialog.listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(p.query("dialog"), null);
  assert.strictEqual(p.sent[1].type, "view.invoke");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[1].payload.params)), { token: "review-1" });
  p.panel.repaint();
  assert.strictEqual(p.query("dialog"), null, "unchanged handoff snapshot cannot reopen a closed form");
});

test("native batch assignment can select an existing definition and closes its handoff on success", function () {
  var p = page(), payload = batchSnapshot();
  payload.sections["ph_composer.zones.faces.attached_zone.list"] = { status: "completed", value: {
    records: [{ id: "atz_existing", values: { name: "Garage" } }]
  } };
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var dialog = p.query("dialog"), picker = byLabel(dialog, "Attached zone");
  picker.value = "atz_existing"; picker.listeners.change({});
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.faces.classify");
  assert.strictEqual(p.sent[0].payload.params.expected_values, undefined);
  assert.strictEqual(p.sent[0].payload.params.faces.length, 2);
  p.panel.receive({ type: "action.result", payload: { session: "session-a", request_id: p.sent[0].payload.request_id,
    outcome: { status: "completed", value: { face_ids: ["fac_a", "fac_b"] } } } });
  assert.strictEqual(p.query("dialog"), null);
  assert.strictEqual(p.sent[1].payload.name, "ph_composer.zones.faces.close_attached_assignment");
});

test("inline create-and-assign reads the factor through the shared unit field", function () {
  var p = page(), dialog = attachedDialog(p), factor = byLabel(dialog, "Temperature reduction factor");
  assert.ok(factor.parentNode.className.includes("phc-unit-field"));
  factor.value = "1.1";
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(p.sent.length, 0);
  assert.ok(dialog.querySelector("[role='status']").textContent);
});

test("a Model switch brings the new session's control row, with the pane's tools still in it", function () {
  var p = page(), first = snapshot(), second = snapshot();
  p.panel.section("example.tool", function (root) { root.textContent = "tool"; }, { region: "tools" });
  p.panel.receive({ type: "panel.snapshot", payload: first });
  var section = p.query("[data-section='ph_composer.overview']"), tool = p.query("[data-section='example.tool']");
  var before = section.querySelector(".phc-inventory-controls");
  assert.strictEqual(tool.parentNode.parentNode, before, "the tools end the control row");
  second.session = "session-b";
  p.panel.receive({ type: "panel.snapshot", payload: second });
  var after = section.querySelector(".phc-inventory-controls");
  assert.notStrictEqual(after, before, "the new session's own controls are the ones on screen");
  assert.strictEqual(section.querySelectorAll(".phc-inventory-controls").length, 1);
  assert.strictEqual(p.query("[data-section='example.tool']"), tool);
  assert.strictEqual(tool.parentNode.parentNode, after);
});

test("a missing value is flagged on its cell, a Face row has nothing to expand, and State is gone", function () {
  var p = page(), payload = snapshot();
  var face = payload.sections["ph_composer.zones.faces.faces"].value.faces[0];
  delete face.values.boundary_condition;
  face.state = "incomplete";
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  var boundary = byLabel(section, "Set Wall 1 boundary");
  assert.ok(boundary, "the control names what is to be set");
  assert.deepStrictEqual([boundary.children[0].textContent, boundary.children[0].disabled], ["?", true]);
  assert.ok(boundary.parentNode.classList.contains("is-flagged"));
  assert.strictEqual(boundary.parentNode.getAttribute("data-tooltip"), "Boundary not set");
  assert.strictEqual(section.querySelector(".col-state"), null);
  var chevrons = section.querySelectorAll(".row-chevron");
  assert.deepStrictEqual(chevrons.map(function (node) { return node.classList.contains("is-leaf"); }),
    [false, true, false], "the Zone and its unclassified summary open; a recorded Face does not");

  // Filling the "?" rebuilds the control without it, and the focus stays on the cell.
  boundary.focus();
  face.values.boundary_condition = "Outdoors";
  face.state = "classified";
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var filled = byLabel(section, "Wall 1 boundary");
  assert.strictEqual(filled.value, "Outdoors");
  assert.strictEqual(p.context.document.activeElement, filled);
  assert.strictEqual(filled.parentNode.classList.contains("is-flagged"), false);
});

test("what the old State column said about a boundary is said on the boundary cell", function () {
  var p = page(), payload = snapshot();
  var face = payload.sections["ph_composer.zones.faces.faces"].value.faces[0];
  face.values.boundary_condition = "Surface";
  face.adjacency_state = "stale";
  face.state = "incomplete";
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  var cell = section.querySelectorAll("td").filter(function (td) {
    return /col-boundary_condition/.test(td.className);
  })[1];
  assert.strictEqual(cell.querySelector(".phc-enum-pill").textContent, "Surface", "a paired Face stays read only");
  assert.ok(cell.classList.contains("is-flagged"));
  assert.match(cell.getAttribute("data-tooltip"), /out of date/);

  face.values.boundary_condition = "AttachedZone";
  face.adjacency_state = null;
  face.attached_zone_state = "dangling";
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  assert.ok(cell.classList.contains("is-flagged"));
  assert.match(cell.getAttribute("data-tooltip"), /Attached zone record is missing/);
});

test("a Zone with no Faces at all offers nothing to expand", function () {
  var p = page(), payload = snapshot();
  payload.sections["ph_composer.zones.faces.faces"].value.faces = [];
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var chevrons = p.query("[data-section='ph_composer.overview']").querySelectorAll(".row-chevron");
  assert.deepStrictEqual(chevrons.map(function (node) { return node.classList.contains("is-leaf"); }), [true]);
});

test("a Face that gains a record moves up under its Zone and lines up there; Undo moves it back", function () {
  var p = page(), payload = snapshot();
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  var key = JSON.stringify(["Face", [100], [102]]);
  function row() {
    return section.querySelectorAll("[data-row-key]").filter(function (node) {
      return node.getAttribute("data-row-key") === key;
    })[0];
  }
  var unclassified = row();
  assert.ok(/tier-2/.test(unclassified.className));
  assert.strictEqual(unclassified.querySelector(".row-chevron"), null, "a row under the summary has no chevron");

  var faces = payload.sections["ph_composer.zones.faces.faces"].value.faces;
  faces[1].state = "classified";
  faces[1].reference.entity_id = "fac_b";
  faces[1].values = { face_type: "Floor", boundary_condition: "Ground" };
  payload.sections["ph_composer.zones.faces.assemblies"] = { status: "completed", value: { assemblies: [] } };
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  assert.strictEqual(row(), unclassified, "the same row, so selection and focus go with it");
  assert.ok(/tier-1/.test(unclassified.className));
  var chevron = unclassified.querySelector(".row-chevron");
  assert.ok(chevron && chevron.classList.contains("is-leaf") && !chevron.hidden,
    "it takes the chevron's place its neighbours keep, so its label lines up");

  faces[1].state = "unclassified";
  faces[1].reference.entity_id = null;
  faces[1].values = {};
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  assert.ok(/tier-2/.test(row().className));
  assert.strictEqual(row().querySelector(".row-chevron").hidden, true);
});

test("Expand all and Collapse all reach the unclassified summary, and the filter finds unclassified", function () {
  var p = page(), payload = snapshot();
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  function count() {
    return section.querySelectorAll("[data-row-key]").filter(function (node) { return !node.hidden; }).length;
  }
  function byText(root, text) {
    return root.querySelectorAll("button").filter(function (node) { return node.textContent === text; })[0];
  }
  assert.strictEqual(count(), 4);
  byText(section, "Collapse all").listeners.click({});
  assert.strictEqual(count(), 1);
  byText(section, "Expand all").listeners.click({});
  assert.strictEqual(count(), 4);
  var filter = byLabel(section, "Filter Zones");
  filter.value = "unclassified";
  filter.listeners.input({});
  assert.strictEqual(count(), 4, "a Zone with unclassified Faces matches the word");
});

test("column menus sort: a Zone field orders Zones, a Face field orders Faces within their Zone", function () {
  var p = page(), payload = snapshot(), faces = payload.sections["ph_composer.zones.faces.faces"].value.faces;
  faces.push({ reference: { zone_id: "zon_a", zone_path: [100], entity_path: [103], entity_id: "fac_c" },
    zone_name: "Zone 1", area_m2: 30, state: "classified", values: { face_type: "Floor", boundary_condition: "Ground" },
    suggested: {} });
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  function names() {
    return section.querySelectorAll("td").filter(function (td) { return /col-name/.test(td.className); })
      .map(nameText);
  }
  assert.strictEqual(byLabel(section, "Order by").parentNode.hidden, true, "Order by moves into the column menus");
  assert.strictEqual(byLabel(section, "Sort descending").hidden, true);
  // By name, Faces keep their place numbers in order, so choosing a type never moves a row; the
  // unclassified summary stays last.
  assert.deepStrictEqual(names(), ["Zone 1", "Wall 1", "Floor 1", "1 unclassified Face", "Face 1"]);
  menuItem(section, "Name column menu", "Sort Z to A");
  assert.deepStrictEqual(names(), ["Zone 1", "Floor 1", "Wall 1", "1 unclassified Face", "Face 1"]);
  menuItem(section, "Gross area m² column menu", "Sort Z to A");
  assert.deepStrictEqual(names(), ["Zone 1", "Floor 1", "Wall 1", "1 unclassified Face", "Face 1"], "largest first");
  menuItem(section, "Type column menu", "Sort A to Z");
  assert.deepStrictEqual(names(), ["Zone 1", "Floor 1", "Wall 1", "1 unclassified Face", "Face 1"],
    "Floor before Wall, within the Zone");
  var sorted = menuItem(section, "Type column menu");
  assert.strictEqual(sorted.filter(function (node) { return node.textContent === "Sort A to Z"; })[0]
    .getAttribute("aria-pressed"), "true", "the menu marks the sort in force");
});

test("a column's value filter hides rows, counts in the control row and shows its glyph at rest", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");
  var trigger = byLabel(section, "Type column menu");
  assert.strictEqual(trigger.classList.contains("is-persistent"), false, "an idle menu shows only on hover");
  click(trigger);
  var boxes = trigger.parentNode.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; });
  assert.deepStrictEqual(boxes.map(function (box) { return box.parentNode.children[1].textContent; }),
    ["Floor", "Roof or ceiling", "Wall", "Unclassified"], "declared choices are available; Unclassified stays last");
  var wall = boxes.filter(function (box) { return box.parentNode.children[1].textContent === "Wall"; })[0];
  wall.checked = false;
  wall.listeners.change({});
  var visible = section.querySelectorAll("[data-row-key]").filter(function (node) { return !node.hidden; })
    .map(function (node) { return JSON.parse(node.getAttribute("data-row-key"))[0]; });
  assert.deepStrictEqual(visible, ["Zone", "Unclassified", "Face"], "Wall 1 is hidden, the unclassified Face shows");
  assert.strictEqual(section.querySelector(".phc-view-count").textContent, "1 Zone · 1 filter");
  var filtered = byLabel(section, "Type: filtered. Column menu");
  assert.ok(filtered, "the trigger says the column is filtered");
  assert.strictEqual(filtered.parentNode.classList.contains("is-persistent"), true, "and stays visible at rest");
  click(filtered);
  click(filtered.parentNode.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Clear filter";
  })[0]);
  assert.strictEqual(section.querySelector(".phc-view-count").textContent, "1 Zone");
  assert.strictEqual(p.sent.length, 1, "column filtering sends its viewport scope");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload.params)), { paths: [[100, 102]] });
  p.panel.receive({ type: "view.result", payload: { request_id: p.sent[0].payload.request_id,
    session: "session-a", outcome: { status: "completed" } } });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[1].payload.params)), { paths: null },
    "clearing while the previous request was pending is applied after it settles");
});

function click(node) { node.listeners.click({ preventDefault: function () {} }); }

/* Opens a column's menu and, given an item's text, presses it; answers the menu's buttons. */
function menuItem(section, menu, text) {
  var trigger = byLabel(section, menu);
  click(trigger);
  var items = trigger.parentNode.querySelectorAll("button");
  if (text) click(items.filter(function (node) { return node.textContent === text; })[0]);
  return items;
}

test("the header groups the authoring tools, the pane has no inspector, and help sits in the control row", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");
  var toolbar = section.querySelector("[role='toolbar']");
  assert.strictEqual(toolbar.getAttribute("aria-label"), "Zone and Face tools");
  assert.strictEqual(byLabel(section, "Solve adjacencies for all Zones in this Model"), undefined);
  assert.ok(!toolbar.textContent.includes("Solve adjacencies"));
  assert.strictEqual(p.query("[data-pane='overview'] [data-phc-region='inspector']"), null, "the table spans the pane");
  assert.strictEqual(p.query("[data-pane='overview']").classList.contains("has-inspector"), false);
  var help = section.querySelector(".phc-inventory-controls").querySelector(".phc-help");
  assert.match(help.getAttribute("aria-label"), /^Zones: Select Faces in SketchUp, or check their rows/);
  var header = section.querySelector(".phc-heading");
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  assert.ok(section.querySelector(".phc-heading") === header, "the header is repainted in place, not rebuilt");
});

test("Colour by lives in the column headers, Window Type in the Assembly's, the rest in Table options", function () {
  var p = page(), payload = snapshot();
  payload.sections["ph_composer.colour_by.legend"] = { status: "completed", value: {
    mode: "ph_composer.zones.faces.by_boundary_condition", label: "Boundary condition", rows: [], modes: [
      { name: "ph_composer.zones.by_zone", label: "Zone", group: null },
      { name: "ph_composer.zones.by_building_segment", label: "Building-Segment", group: null },
      { name: "ph_composer.zones.by_level", label: "Level", group: null },
      { name: "ph_composer.zones.faces.by_face_type", label: "Face type", group: null },
      { name: "ph_composer.zones.faces.by_boundary_condition", label: "Boundary condition", group: null },
      { name: "ph_composer.zones.faces.by_assembly", label: "Assembly", group: "construction" },
      { name: "ph_composer.windows.by_type", label: "Window Type", group: "construction" },
      { name: "outside.probe.by_side", label: "Side", group: null }] } };
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  var toggles = section.querySelectorAll(".phc-colour-toggle");
  assert.strictEqual(toggles.length, 6, "Name, Building-Segment, Level, Type, Boundary and Assembly");
  var boundary = byLabel(section, "Colour by Boundary condition");
  assert.strictEqual(boundary.getAttribute("aria-pressed"), "true");
  assert.strictEqual(boundary.parentNode.classList.contains("is-persistent"), true, "a pressed toggle stays at rest");
  var assembly = byLabel(section, "Colour by Assembly or Window Type");
  click(assembly);
  assert.deepStrictEqual(assembly.parentNode.querySelectorAll(".phc-action-menu-item").map(function (node) {
    return node.textContent;
  }), ["Assembly", "Window Type"]);
  var options = byLabel(section, "Table options");
  click(options);
  var items = options.parentNode.querySelectorAll(".phc-action-menu-item");
  assert.deepStrictEqual(items.map(function (node) { return node.textContent; }),
    ["Ground depth column", "Colour by Side"], "only a mode no column offers is listed");
  click(items[1]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload.params)), { mode: "outside.probe.by_side" });
  click(options);
  click(options.parentNode.querySelectorAll(".phc-action-menu-item")[0]);
  assert.strictEqual(section.querySelectorAll(".col-ground_depth_mm").filter(function (node) {
    return node.tagName === "th";
  })[0].hidden, false, "Ground depth shows from Table options");
});

test("Ground depth waits in Table options, and its heading says what it does", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var section = p.query("[data-section='ph_composer.overview']");
  var heading = section.querySelectorAll(".col-ground_depth_mm").filter(function (node) {
    return node.tagName === "th";
  })[0];
  assert.strictEqual(heading.hidden, true);
  assert.match(heading.querySelector(".phc-th-label").getAttribute("data-tooltip"), /Suggest classification.*Ground/);
});

/* Three Faces in one Zone, two of them recorded, so a Zone's box can read mixed. */
function checkPage(selected) {
  var p = page(), payload = snapshot();
  var faces = payload.sections["ph_composer.zones.faces.faces"].value.faces;
  var third = JSON.parse(JSON.stringify(faces[0]));
  third.reference.entity_path = [103]; third.reference.entity_id = "fac_c";
  faces.splice(1, 0, third);
  payload.sections["ph_composer.zones.faces.selected"] = { status: "completed",
    value: { faces: [], targets: (selected || []).map(function (index) {
      return { reference: faces[index].reference, expected_values: faces[index].values };
    }) } };
  p.payload = payload;
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  p.section = p.query("[data-section='ph_composer.overview']");
  p.box = function (label) {
    return p.section.querySelectorAll("input").filter(function (node) {
      return /row-check/.test(node.className) && node.getAttribute("aria-label").indexOf(label) >= 0;
    })[0];
  };
  p.state = function (label) { return p.box(label).getAttribute("aria-checked"); };
  p.header = function () { return p.section.querySelector("th").querySelector(".row-check"); };
  return p;
}

test("a Zone's box checks every Face under it and reads mixed when some are; the header follows", function () {
  var p = checkPage();
  assert.ok(p.section.querySelector(".phc-table").classList.contains("reveals-row-actions"),
    "row icons show on hover");
  click(p.box("Wall 1"));
  assert.deepStrictEqual([p.state("Zone 1"), p.header().getAttribute("aria-checked")], ["mixed", "mixed"]);
  assert.ok(p.section.querySelector(".phc-table").classList.contains("has-checked"), "every box shows now");
  click(p.box("Zone 1"));
  assert.deepStrictEqual([p.state("Wall 1"), p.state("Wall 2"), p.state("Face 1"), p.state("Zone 1")],
    ["true", "true", "true", "true"], "and an unclassified Face can be checked");
  click(p.header());
  assert.strictEqual(p.state("Zone 1"), "false", "the header unchecks every row shown");
  assert.strictEqual(p.sent.length, 0, "checking reaches nothing in SketchUp");
});

test("Shift-click checks the range between the last box clicked and this one", function () {
  var p = checkPage();
  click(p.box("Wall 1"));
  p.box("Face 1").listeners.click({ shiftKey: true, preventDefault: function () {} });
  assert.deepStrictEqual([p.state("Wall 1"), p.state("Wall 2"), p.state("Face 1")], ["true", "true", "true"]);
});

test("a new SketchUp selection replaces the checked set; the same one leaves the user's checks", function () {
  var p = checkPage([0]);
  assert.deepStrictEqual([p.state("Wall 1"), p.state("Wall 2")], ["true", "false"]);
  click(p.box("Wall 2"));
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(p.state("Wall 2"), "true", "an unchanged selection keeps what the user checked");
  p.payload.sections["ph_composer.zones.faces.selected"].value.targets = [];
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.deepStrictEqual([p.state("Wall 1"), p.state("Wall 2")], ["false", "false"], "an empty selection clears");
});

test("Locate frames without touching the checked set; a press elsewhere and Escape clear in layers", function () {
  var p = checkPage([0]);
  click(rowAction(p.section, "locate"));
  assert.deepStrictEqual([p.sent[0].type, p.sent[0].payload.name], ["view.invoke", "ph_composer.zones.faces.locate"]);
  p.panel.receive({ type: "view.result", payload: { request_id: p.sent[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { found: 3, missing: 0 } } } });
  assert.strictEqual(p.state("Wall 1"), "true", "Locate leaves the set alone");
  function escape() {
    return dom.dispatch(p.context.document.body, { type: "keydown", key: "Escape" });
  }
  assert.strictEqual(escape().defaultPrevented, true);
  assert.strictEqual(p.state("Wall 1"), "false", "Escape clears the checked set first");
  assert.strictEqual(p.sent.length, 1);
  escape();
  assert.strictEqual(p.sent[1].payload.name, "ph_composer.zones.faces.clear_locate", "then Locate's outline");
  p.panel.receive({ type: "view.result", payload: { request_id: p.sent[1].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: {} } } });
  click(rowAction(p.section, "locate"));
  p.panel.receive({ type: "view.result", payload: { request_id: p.sent[2].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { found: 3, missing: 0 } } } });
  dom.dispatch(p.box("Wall 1"), { type: "pointerdown" });
  assert.strictEqual(p.sent[3].payload.name, "ph_composer.zones.faces.clear_locate", "a press elsewhere clears it");
  dom.dispatch(p.box("Wall 1"), { type: "pointerdown" });
  assert.strictEqual(p.sent.length, 4, "once");
});

test("another tab can open the Faces view with Faces checked", function () {
  var p = checkPage();
  p.panel.showTab("export");
  assert.strictEqual(p.panel.navigate("overview", { check: [p.payload.sections["ph_composer.zones.faces.faces"]
    .value.faces[1].reference] }), true);
  assert.deepStrictEqual([p.state("Wall 1"), p.state("Wall 2")], ["false", "true"]);
});

function bar(p) {
  return p.query("[data-section='ph_composer.overview']").querySelector(".phc-selection-bar");
}

test("the bar edits every checked Face in one request, and says how many a filter hides", function () {
  var p = checkPage();
  assert.strictEqual(bar(p).hidden, true, "nothing checked, no bar");
  click(p.box("Wall 1"));
  click(p.box("Face 1"));
  assert.strictEqual(bar(p).hidden, false);
  click(byLabel(p.section, "Type column menu"));
  var wall = byLabel(p.section, "Type column menu").parentNode.querySelectorAll("input").filter(function (box) {
    return box.parentNode.children[1].textContent === "Wall";
  })[0];
  wall.checked = false; wall.listeners.change({});
  assert.strictEqual(bar(p).querySelector(".phc-selection-bar-count").textContent, "2 Faces selected, 1 hidden");
  var boundary = byLabel(bar(p), "Boundary for selected Faces");
  boundary.value = "Ground"; boundary.listeners.change({});
  var action = p.sent.filter(function (entry) { return entry.type === "action.invoke"; })[0];
  var sent = JSON.parse(JSON.stringify(action.payload));
  assert.strictEqual(sent.name, "ph_composer.zones.faces.classify");
  assert.deepStrictEqual(sent.params.faces.map(function (face) { return face.entity_path[0]; }), [101, 102],
    "the hidden Face too, as one Undo step");
  assert.strictEqual(sent.params.expected_values, undefined);
  click(bar(p).querySelector(".phc-selection-bar-clear"));
  assert.deepStrictEqual([bar(p).hidden, p.state("Zone 1")], [true, "false"], "clear unchecks every Face");
});

test("more Faces than one gesture may change disables the bar's controls and says why", function () {
  var p = checkPage();
  p.payload.sections["ph_composer.zones.faces.palette"].value.gesture_face_limit = 1;
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  click(p.box("Wall 1"));
  assert.strictEqual(byLabel(bar(p), "Type for selected Faces").disabled, false);
  click(p.box("Wall 2"));
  assert.strictEqual(byLabel(bar(p), "Type for selected Faces").disabled, true);
  assert.ok(byLabel(bar(p), "Why Assign is unavailable"), "the limit is the reason, beside the controls");
});

test("painting preserves checked Face controls and the selection count", function () {
  var p = checkPage([0]);
  p.payload.sections["ph_composer.zones.faces.palette"].value = {
    active: true, palette: { face_type: "Wall" }, face_types: ["Wall", "RoofCeiling", "Floor"],
    boundary_conditions: ["Outdoors", "Ground", "Adiabatic", "AttachedZone", "Surface"]
  };
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(bar(p).hidden, false);
  assert.strictEqual(bar(p).querySelector(".phc-selection-controls").hidden, false);
  assert.strictEqual(byLabel(bar(p), "Type for selected Faces").disabled, false);
  assert.strictEqual(bar(p).querySelector(".phc-selection-bar-count").textContent, "1 Face selected");
  assert.strictEqual(p.query("[data-section='ph_composer.classify']"), null);
  assert.strictEqual(p.query("[data-section='ph_composer.classify.toggle']"), null);
});

test("a Model switch takes the old Model's selection bar with it", function () {
  var p = checkPage([0]);
  var old = bar(p);
  assert.strictEqual(old.hidden, false);
  var other = JSON.parse(JSON.stringify(p.payload));
  other.session = "session-b"; other.revision = 9;
  p.panel.receive({ type: "panel.snapshot", payload: other });
  var bars = p.section.querySelectorAll(".phc-selection-bar");
  assert.strictEqual(bars.length, 1, "one bar, the new Model's");
  assert.ok(bars[0] !== old);
  assert.strictEqual(p.query("[data-section='ph_composer.classify']"), null, "no palette section crosses Models");
});

test("Escape closes the column menu before clearing checked Faces", function () {
  var p = checkPage([0]);
  menuItem(p.section, "Type column menu");
  var bubble = p.context.document.querySelectorAll(".phc-bubble").filter(function (node) { return !node.hidden; })[0];
  assert.ok(bubble);
  dom.dispatch(bubble.querySelector("input"), { type: "keydown", key: "Escape" });
  assert.deepStrictEqual([bubble.hidden, p.state("Wall 1")], [true, "true"]);
  dom.dispatch(p.context.document.body, { type: "keydown", key: "Escape" });
  assert.strictEqual(p.state("Wall 1"), "false");
  assert.strictEqual(p.sent.length, 0);
});

test("Show rows have separate paint actions and include unused Type and Assembly choices", function () {
  var p = checkPage();
  p.payload.sections["ph_composer.zones.faces.assemblies"] = { status: "completed", value: { assemblies: [
    { id: "asy_unused", name: "Unused Assembly", type: "Wall" }
  ] } };
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  menuItem(p.section, "Type column menu");
  var trigger = byLabel(p.section, "Type column menu");
  var roof = byLabel(trigger.parentNode, "Paint Roof or ceiling");
  assert.ok(roof, "valid unused face types can be painted");
  assert.strictEqual(roof.parentNode.querySelector("label").contains(roof), false,
    "the paint action is a sibling, outside the checkbox label");
  click(roof);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload.params)),
    { field: "face_type", value: "RoofCeiling", reset: true });
  assert.strictEqual(trigger.getAttribute("aria-label"), "Type column menu", "paint did not set a Show filter");

  p.panel.receive({ type: "view.result", payload: { request_id: p.sent[0].payload.request_id,
    session: "session-a", outcome: { status: "completed" } } });
  menuItem(p.section, "Assembly column menu");
  var assembly = byLabel(p.section, "Assembly column menu").parentNode;
  assert.ok(byLabel(assembly, "Paint Unused Assembly"));
  assert.strictEqual(byLabel(assembly, "Paint None"), undefined);
  menuItem(p.section, "Boundary column menu");
  var boundary = byLabel(p.section, "Boundary column menu").parentNode;
  assert.ok(byLabel(boundary, "Paint To neighbour"));
  assert.strictEqual(byLabel(boundary, "Paint Surface"), undefined);
  assert.strictEqual(byLabel(boundary, "Paint Attached zone"), undefined);
  assert.ok(byLabel(boundary, "Attached zone"));
  menuItem(p.section, "Level column menu");
  assert.strictEqual(byLabel(p.section, "Level column menu").parentNode.querySelectorAll("[data-icon='paint_bucket']")
    .length, 0);
});

test("changing a Show checkbox filters without painting or toggling another value", function () {
  var p = checkPage(); menuItem(p.section, "Type column menu");
  var menu = byLabel(p.section, "Type column menu").parentNode;
  var wall = menu.querySelectorAll("input").filter(function (box) {
    return box.parentNode.children[1].textContent === "Wall";
  })[0];
  wall.checked = false; wall.listeners.change({});
  assert.ok(p.sent.every(function (message) { return message.payload.name !== "ph_composer.zones.faces.choose"; }));
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.colour_by.filter");
  assert.ok(menu.querySelectorAll("input").filter(function (box) { return box !== wall; })
    .every(function (box) { return box.checked; }));
});

test("past fifty unclassified Faces the header box and the hidden count read every Face the filter shows", function () {
  var p = page(), payload = snapshot();
  var faces = payload.sections["ph_composer.zones.faces.faces"].value.faces;
  for (var index = 0; index < 60; index += 1) {
    var extra = JSON.parse(JSON.stringify(faces[1]));
    extra.reference.entity_path = [200 + index];
    faces.push(extra);
  }
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  click(section.querySelector("th").querySelector(".row-check"));
  assert.strictEqual(bar(p).querySelector(".phc-selection-bar-count").textContent, "62 Faces selected",
    "every Face, painted or not, and none counted hidden");
  assert.strictEqual(section.querySelector("th").querySelector(".row-check").getAttribute("aria-checked"), "true");
});

test("a selection change with no Faces clears the checked set; an unchanged one keeps manual checks", function () {
  var p = checkPage();
  p.payload.sections["ph_composer.zones.faces.selection_change"] = { status: "completed", value: { generation: 0 } };
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  click(p.box("Wall 1"));
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(p.state("Wall 1"), "true", "a snapshot with no selection change keeps the user's checks");
  // A Group is selected: the Faces read refuses, so there are no Face targets, but the selection changed.
  p.payload.sections["ph_composer.zones.faces.selected"] = { status: "refused", code: "selection.invalid" };
  p.payload.sections["ph_composer.zones.faces.selection_change"].value.generation = 1;
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(p.state("Wall 1"), "false");
  click(p.box("Wall 2"));
  p.payload.sections["ph_composer.zones.faces.selection_change"].value.generation = 2;
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  assert.strictEqual(p.state("Wall 2"), "false", "clearing SketchUp's selection clears the checked set");
});

test("a press or Escape while Locate is still in flight clears the outline after it", function () {
  ["pointer", "escape"].forEach(function (route) {
    var p = checkPage();
    click(rowAction(p.section, "locate"));
    if (route === "pointer") dom.dispatch(p.box("Wall 1"), { type: "pointerdown" });
    else dom.dispatch(p.context.document.body, { type: "keydown", key: "Escape" });
    assert.deepStrictEqual(p.sent.map(function (message) { return message.payload.name; }),
      ["ph_composer.zones.faces.locate", "ph_composer.zones.faces.clear_locate"], route);
    p.panel.receive({ type: "view.result", payload: { request_id: p.sent[0].payload.request_id, session: "session-a",
      outcome: { status: "completed", value: { found: 1, missing: 0 } } } });
    assert.strictEqual(p.sent.length, 2, route + ": the clear is not sent twice");
  });
});

test("column filters combine across Zone and Face values without using text search or collapse", function () {
  var p = solvePage();
  var zones = p.payload.sections["ph_composer.zones.overview"].value.zones;
  zones[1].values.level = "Upper"; zones[2].values.level = "Upper";
  p.panel.receive({ type: "panel.snapshot", payload: p.payload });
  function exclude(column, label) {
    var trigger = byLabel(p.section, column + " column menu");
    click(trigger);
    var box = trigger.parentNode.querySelectorAll("input").filter(function (node) {
      return node.parentNode.children[node.parentNode.children.length - 1].textContent === label;
    })[0];
    box.checked = false; box.listeners.change({});
  }
  exclude("Level", "Upper");
  var first = p.sent[0];
  assert.deepStrictEqual(JSON.parse(JSON.stringify(first.payload.params.paths)),
    [[100]], "Zone-only scope includes all descendant geometry, including Window units");
  exclude("Type", "Unclassified");
  p.panel.receive({ type: "view.result", payload: { request_id: first.payload.request_id,
    session: "session-a", outcome: { status: "completed" } } });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[1].payload.params.paths)), [[100, 101], [100, 103]],
    "the latest scope intersects every Show filter");
  p.panel.receive({ type: "view.result", payload: { request_id: p.sent[1].payload.request_id,
    session: "session-a", outcome: { status: "completed" } } });
  var search = byLabel(p.section, "Filter Zones"); search.value = "Nothing"; search.listeners.input({});
  var collapse = p.section.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Collapse all";
  })[0];
  click(collapse);
  assert.strictEqual(p.sent.length, 2, "search and collapsing do not change viewport scope");
  exclude("Boundary", "Outdoors");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[2].payload.params.paths)), [],
    "no match is an explicit empty scope, not Show all");
});

test("managed chip updates send complete v2 values and expected values, with custom colour", function () {
  var p = page(), payload = managedSnapshot(); p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  assert.strictEqual(segment.style["--category-fill"], "#268589");
  assert.strictEqual(segment.children[0].textContent, "House");
  segment.value = "bsg_tower"; segment.listeners.change({});
  assert.strictEqual(p.sent.length, 1);
  assert.strictEqual(p.sent[0].payload.expected_revision, 4);
  assert.deepStrictEqual(p.sent[0].payload.params.values, { name: "Zone 1", building_segment_id: "bsg_tower",
    level_id: null, ground_depth_mm: 0 });
  assert.deepStrictEqual(p.sent[0].payload.params.expected_values,
    payload.sections["ph_composer.zones.overview"].value.zones[0].values);
});

test("managed choice error descriptions remain unique after removing and adding Zone rows", function () {
  var p = page(), payload = managedSnapshot(), zones = payload.sections["ph_composer.zones.overview"].value.zones;
  function another(id, name, path) {
    var zone = JSON.parse(JSON.stringify(zones[0]));
    zone.id = id; zone.values.name = name; zone.reference = { zone_id: id, zone_path: [path] };
    return zone;
  }
  zones.push(another("zon_b", "Zone 2", 200));
  payload.sections["ph_composer.zones.faces.faces"].value.faces = [];
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  zones.splice(0, 1); zones.push(another("zon_c", "Zone 3", 300));
  payload.revision++;
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  var ids = ["Zone 2", "Zone 3"].flatMap(function (name) {
    return ["Building-Segment", "Level"].map(function (field) {
      var id = byLabel(section, name + " " + field).getAttribute("aria-describedby");
      assert.strictEqual(section.querySelectorAll("small").filter(function (node) { return node.id === id; }).length,
        1, name + " " + field + " describes its own error status");
      return id;
    });
  });
  assert.strictEqual(new Set(ids).size, 4);
});

test("managed category filters retain IDs through rename and use current display text", function () {
  var p = page(), payload = managedSnapshot(); p.panel.receive({ type: "panel.snapshot", payload: payload });
  p.section = p.query("[data-section='ph_composer.overview']");
  menuItem(p.section, "Building-Segment column menu");
  var trigger = byLabel(p.section, "Building-Segment column menu"),
    boxes = trigger.parentNode.querySelectorAll("input");
  boxes[1].checked = false; boxes[1].listeners.change({});
  payload.sections["ph_composer.zones.options"].value.building_segments[0].values.name = "North House";
  payload.revision = 5; p.panel.receive({ type: "panel.snapshot", payload: payload });
  assert.ok(p.section.querySelector(".phc-table"));
  assert.strictEqual(byLabel(p.section, "Zone 1 Building-Segment").children[0].textContent, "North House");
});

test("empty collection column menus still expose management and Cancel writes nothing", function () {
  var p = page(), payload = managedSnapshot();
  payload.sections["ph_composer.zones.overview"].value.zones = [];
  payload.sections["ph_composer.zones.faces.faces"].value.faces = [];
  payload.sections["ph_composer.zones.options"].value.levels = [];
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  var section = p.query("[data-section='ph_composer.overview']");
  menuItem(section, "Level column menu", "Manage Levels…");
  var dialog = p.query("dialog"); assert.ok(dialog);
    assert.strictEqual(dialog.querySelector(".phc-empty").textContent, "No Levels defined.");
  p.panel.showTab("export"); assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  dialog.listeners.cancel({ preventDefault: function () {} }); assert.strictEqual(p.query("dialog"), null);
  assert.strictEqual(p.sent.length, 0);
});

test("removing an unused Segment drops its stale filter without clearing checked Faces", function () {
  var p = page(), payload = managedSnapshot(); p.panel.receive({ type: "panel.snapshot", payload: payload });
  p.section = p.query("[data-section='ph_composer.overview']");
  var box = p.section.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; })[1];
  click(box);
  menuItem(p.section, "Building-Segment column menu");
  var trigger = byLabel(p.section, "Building-Segment column menu");
  var filters = trigger.parentNode.querySelectorAll("input");
  filters[0].checked = false; filters[0].listeners.change({});
  menuItem(p.section, "Building-Segment: filtered. Column menu", "Manage Building Segments…");
  var dialog = p.query("dialog"), rows = dialog.querySelectorAll(".phc-zone-option-row");
  rows[1].querySelectorAll("button").filter(function (button) { return button.textContent === "Merge / Delete"; })[0]
    .listeners.click({});
  var replacement = dialog.querySelectorAll("select").filter(function (node) {
    return node.getAttribute("aria-label") === "Replacement for Tower";
  })[0];
  replacement.value = ""; replacement.listeners.change({});
  dialog.querySelectorAll("button").filter(function (button) { return button.textContent === "Remove"; })[0]
    .listeners.click({});
  dialog.querySelectorAll("button").filter(function (button) { return button.textContent === "Save"; })[0]
    .listeners.click({});
  var request = p.sent[0].payload;
  payload.revision = 5; payload.sections["ph_composer.zones.options"].value.building_segments.splice(1, 1);
  p.panel.receive({ type: "panel.snapshot", payload: payload });
  p.panel.receive({ type: "action.result", payload: { session: request.session, request_id: request.request_id,
    outcome: { status: "completed", value: { replacement_ids: { bsg_tower: null } } } } });
  assert.ok(byLabel(p.section, "Zone 1 Building-Segment"), "no stale empty filter hides the remaining Zone");
  assert.ok(p.section.closest("[data-pane]").querySelector(".phc-selection-bar"), "checked Faces survive management");
});

test("Table options will not hide a column while a Zone edit is held", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: managedSnapshot() });
  var section = p.query("[data-section='ph_composer.overview']"), segment = byLabel(section, "Zone 1 Building-Segment");
  segment.value = "bsg_tower"; segment.listeners.change({});
  result(p, 0, { status: "completed", effect: "committed" });
  var options = byLabel(section, "Table options");
  click(options);
  click(options.parentNode.querySelectorAll(".phc-action-menu-item").filter(function (node) {
    return node.textContent === "Ground depth column";
  })[0]);
  assert.strictEqual(section.querySelectorAll(".col-ground_depth_mm").filter(function (node) {
    return node.tagName === "th";
  })[0].hidden, true, "the held edit keeps the table as it is");
  assert.strictEqual(p.panel.state.ui.notice.message, "Finish or cancel the Zone edit first.");
});
