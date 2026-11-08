"use strict";
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var source = require("./support/panel_source");
var fixtures = require("./support/inventory_fixtures");
var PREFIX = "ph_composer.zones.faces";
function setup() {
  var document = dom.buildDocument(source.markup("index.html"));
  var sent = [], context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 900,
    setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } } };
  context.window = context;
  dom.attachEvents(context);
  var modules = source.start(context, ["features/zones/overview", "features/zones/faces_view",
    "features/zones/classify", "features/assemblies/section"]);
  var state = fixtures.state("session-a");
  state.product = "PH-Composer";
  state.preferences = { unit_system: "SI", dimension_formats: {},
    number_format: { decimal: ".", locale: "en-US" } };
  var face = { reference: { zone_id: "zon_a", zone_path: [100], entity_path: [101], entity_id: "fac_a" },
    values: { face_type: "Wall", boundary_condition: "Surface", assembly_id: "asm_missing",
      boundary_face_id: "fac_b" }, area_m2: 12, state: "classified", assembly_state: "dangling", findings: [] };
  state.sections["ph_composer.zones.overview"] = { status: "completed", value: {
    zones: [{ id: "zon_a", reference: { zone_id: "zon_a", zone_path: [100] }, state: "found",
      values: { name: "Zone 1", ground_depth_mm: 0, level: null }, face_count: 1 }], make_zone: null } };
  state.sections[PREFIX + ".faces"] = { status: "completed", value: { faces: [face] } };
  state.sections[PREFIX + ".palette"] = { status: "completed", value: { active: false,
    palette: {}, face_types: ["Wall", "RoofCeiling", "Floor"],
    boundary_conditions: ["Outdoors", "Ground", "Surface"] } };
  state.sections[PREFIX + ".selected"] = { status: "completed", value: {
    faces: [face.reference],
    targets: [{ reference: face.reference, expected_values: face.values }] } };
  state.sections[PREFIX + ".assemblies"] = { status: "completed", value: { assemblies: [
    { id: "asm_b", name: "A Roof", type: "RoofCeiling", color: "#bbdefb" },
    { id: "asm_a", name: "Wall", type: "Wall", color: "#c5e1a5" }] } };
  state.sections[PREFIX + ".usage"] = { status: "completed", value: {
    faces: [Object.assign({ zone_name: "Zone 1" }, face)], assembly_usage: [
    { assembly_id: "asm_a", face_count: 1, gross_area_m2: 12, faces: [face.reference] }] } };
  function paint() { modules.panel.receive({ type: "panel.snapshot", payload: state }); }
  paint();
  return { document: document, modules: modules, panel: modules.panel, state: state, face: face,
    sent: sent, paint: paint, query: function (selector) { return document.querySelector(selector); } };
}
function byLabel(root, label) {
  return root.querySelectorAll("input, select, button").filter(function (node) {
    return node.getAttribute("aria-label") === label;
  })[0];
}
function click(node) { node.listeners.click({ preventDefault: function () {} }); }
function text(node) { return node.textContent + node.children.map(text).join(" "); }
test("selection Assembly choices prioritize matching hints; a choice assigns at once to its targets", function () {
  var o = setup(), picker = byLabel(o.document.body, "Assembly for selected Faces");
  assert.deepStrictEqual(picker.children.map(function (entry) { return entry.textContent; }),
    ["Choose Assembly", "Clear Assembly", "Wall", "A Roof"]);
  assert.strictEqual(byLabel(o.document.body, "Apply Assembly to selected Faces"), undefined, "no Apply step");
  picker.value = "asm_a";
  picker.listeners.change({});
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, PREFIX + ".assign_assembly");
  assert.deepStrictEqual(o.sent[0].payload.params, { targets: [{ reference: o.face.reference,
    expected_values: o.face.values }], assembly_id: "asm_a" });
  assert.ok(text(o.document.body).includes("1 Face selected"));
});
test("table Assembly chip names dangling references and clears only the guarded Assembly", function () {
  var o = setup(), chip = byLabel(o.document.body, "Wall 1 Assembly");
  assert.ok(chip.children.some(function (entry) { return entry.textContent.includes("Missing Assembly"); }));
  chip.value = "";
  chip.listeners.change({});
  assert.strictEqual(o.sent.length, 1);
  assert.deepStrictEqual(o.sent[0].payload.params, { targets: [{ reference: o.face.reference,
    expected_values: o.face.values }], assembly_id: null });
});
test("the table Assembly chip takes its Assembly's colour and follows it; None stays neutral", function () {
  var o = setup(), chip = byLabel(o.document.body, "Wall 1 Assembly");
  assert.strictEqual(chip.style["--category-fill"], undefined, "a missing Assembly keeps the neutral pill");
  o.face.values.assembly_id = "asm_a";
  o.paint();
  assert.strictEqual(chip.style["--category-fill"], "#c5e1a5");
  assert.strictEqual(chip.style["--category-ink"], "#111111");
  assert.strictEqual(chip.style["--choice-chevron"], undefined);
  o.state.sections[PREFIX + ".assemblies"].value.assemblies[1].color = "#263238";
  o.paint();
  assert.deepStrictEqual([chip.style["--category-fill"], chip.style["--category-ink"]], ["#263238", "#FFFFFF"]);
  assert.strictEqual(chip.style["--choice-chevron"], "var(--choice-chevron-light)");
  o.state.sections[PREFIX + ".assemblies"].value.assemblies[1].color = "#808080";
  o.paint();
  assert.strictEqual(chip.style["--category-ink"], "#111111", "a mid grey reads better with dark text than white");
  assert.strictEqual(chip.style["--choice-chevron"], undefined);
  o.face.values.assembly_id = null;
  o.paint();
  assert.deepStrictEqual([chip.style["--category-fill"], chip.style["--category-ink"]], [undefined, undefined]);
  assert.strictEqual(chip.style["--choice-chevron"], undefined);
});
test("Assembly paint intent is named in its column header", function () {
  var o = setup();
  assert.strictEqual(o.query("[data-section='ph_composer.classify']"), null);
  o.state.sections[PREFIX + ".palette"].value.palette.assembly_id = "asm_a";
  o.state.sections[PREFIX + ".palette"].value.active = true;
  o.paint();
  var glyph = byLabel(o.document.body, "Paint Assembly: Wall. Click to stop painting");
  assert.ok(glyph);
  assert.strictEqual(glyph.hidden, false);
  assert.strictEqual(glyph.tagName, "button", "the header keeps only a stop glyph");
});
test("Zones contributes gross usage and view actions through the generic Assembly inventory seam", function () {
  var o = setup(), inventory = o.query("[data-section='assemblies']")._view.inventory;
  o.panel.showTab("assemblies");
  assert.ok(inventory.tableOptions.columns.some(function (column) { return column[0] === "face_usage"; }));
  var cell = inventory.scroll._table.rows.asm_a.cells.face_usage;
  assert.ok(text(cell).includes("12 m²"));
  var action = inventory.tableOptions.actions({ record: inventory.records[0] }).filter(function (item) {
    return item.id === "select_assembly_faces";
  })[0];
  o.state.sections[PREFIX + ".selected"].value.targets = [];
  o.paint();
  inventory.tableOptions.action({ record: inventory.records[0] }, action);
  assert.strictEqual(o.panel.state.ui.activeTab, "overview", "Select faces opens the Zones tab");
  assert.strictEqual(o.query("[data-section='ph_composer.overview']").querySelectorAll(".row-check").filter(
    function (box) { return box.getAttribute("aria-checked") === "true"; }).length > 0, true,
  "with the Assembly's Faces checked");
  assert.deepStrictEqual([o.sent[0].type, o.sent[0].payload.name], ["view.invoke", PREFIX + ".locate"]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params)), { faces: [o.face.reference] });
  o.panel.receive({ type: "view.result", payload: { request_id: o.sent[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { found: 1, missing: 0 } } } });
  dom.dispatch(o.document.body, { type: "keydown", key: "Escape" });
  dom.dispatch(o.document.body, { type: "keydown", key: "Escape" });
  assert.strictEqual(o.sent[1].payload.name, PREFIX + ".clear_locate", "the outline is the Faces view's to clear");
  delete o.state.sections[PREFIX + ".usage"];
  o.paint();
  assert.ok(!inventory.tableOptions.columns.some(function (column) { return column[0] === "face_usage"; }));
});
test("an assignment refusal says why and leaves the control ready; a Model switch forbids it", function () {
  var o = setup(), picker = byLabel(o.document.body, "Assembly for selected Faces");
  picker.value = "asm_a";
  picker.listeners.change({});
  o.panel.receive({ type: "action.result", payload: { session: "session-a",
    request_id: o.sent[0].payload.request_id, outcome: { status: "refused", message: "Changed in the Model." } } });
  assert.strictEqual(picker.value, "", "nothing is left looking chosen");
  assert.strictEqual(picker.disabled, false);
  assert.ok(text(o.document.body).includes("Changed in the Model."));
  var chip = byLabel(o.document.body, "Wall 1 Assembly");
  o.state.session = "session-b";
  o.paint();
  picker.value = "asm_b";
  picker.listeners.change({});
  chip.value = "asm_b";
  chip.listeners.change({});
  assert.strictEqual(o.sent.length, 1);
});
test("Assembly replacement UI requires an explicit replacement or Clear before one delete action", function () {
  var o = setup(), view = o.query("[data-section='assemblies']")._view, inventory = view.inventory;
  var row = { record: inventory.records[0] };
  var action = inventory.tableOptions.actions(row).filter(function (item) {
    return item.id === "replace_assembly";
  })[0];
  inventory.tableOptions.action(row, action);
  var dialog = o.document.querySelectorAll("dialog").filter(function (node) { return !node.hidden; })[0];
  assert.ok(text(dialog).includes("1 Face"));
  var select = byLabel(dialog, "Replacement assembly");
  var submit = dialog.querySelectorAll("button").filter(function (button) { return button.type === "submit"; })[0];
  assert.ok(submit.disabled);
  select.value = "__clear__";
  select.listeners.change({});
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.assemblies.assemblies.delete");
  assert.strictEqual(o.sent[0].payload.params.replacement_id, null);
});
test("selection Clear is explicit and inventory Paint resets other fields", function () {
  var o = setup(), picker = byLabel(o.document.body, "Assembly for selected Faces");
  picker.value = "__clear__";
  picker.listeners.change({});
  assert.strictEqual(o.sent[0].payload.params.assembly_id, null);
  o = setup();
  var inventory = o.query("[data-section='assemblies']")._view.inventory, row = { record: inventory.records[0] };
  var paint = inventory.tableOptions.actions(row).filter(function (action) {
    return action.id === "paint_assembly";
  })[0];
  inventory.tableOptions.action(row, paint);
  assert.strictEqual(o.sent.length, 1);
  assert.deepStrictEqual(o.sent[0].payload.params, { field: "assembly_id", value: "asm_a", reset: true });
});
function rowAction(inventory, row, id) {
  return inventory.tableOptions.actions(row).filter(function (action) { return action.id === id; })[0];
}
function settle(o, message, active, palette) {
  o.state.sections[PREFIX + ".palette"].value.active = active;
  o.state.sections[PREFIX + ".palette"].value.palette = palette;
  o.panel.receive({ type: "view.result", payload: { request_id: message.payload.request_id,
    session: message.payload.session, outcome: { status: "completed" } } });
  o.paint();
}
function stops(o) {
  return o.sent.filter(function (message) { return message.payload.name === PREFIX + ".stop_classifying"; });
}
test("Paint from the Assemblies table stays there, shows what is painting and stops on a second press", function () {
  var o = setup(), inventory = o.query("[data-section='assemblies']")._view.inventory;
  var row = { record: inventory.records[0] };
  o.panel.showTab("assemblies");
  inventory.tableOptions.action(row, rowAction(inventory, row, "paint_assembly"));
  assert.strictEqual(o.panel.state.ui.activeTab, "assemblies", "the panel stays where Paint was pressed");
  assert.strictEqual(o.sent[0].payload.name, PREFIX + ".choose");
  settle(o, o.sent[0], true, { assembly_id: "asm_a" });
  assert.strictEqual(stops(o).length, 0, "the snapshot that reports the tool on does not stop it");
  var pressed = rowAction(inventory, row, "paint_assembly");
  assert.strictEqual(pressed.pressed, true);
  assert.strictEqual(pressed.label, "Stop painting Wall");
  assert.strictEqual(rowAction(inventory, { record: inventory.records[1] }, "paint_assembly").pressed, false);
  inventory.tableOptions.action(row, pressed);
  assert.strictEqual(o.sent[o.sent.length - 1].payload.name, PREFIX + ".stop_classifying");
  assert.strictEqual(o.panel.state.ui.activeTab, "assemblies");
});
test("Replace and delete says what it does and lists Faces by Zone and Face name, never by id", function () {
  var o = setup(), inventory = o.query("[data-section='assemblies']")._view.inventory;
  var row = { record: inventory.records[0] };
  var usage = o.state.sections[PREFIX + ".usage"].value, second = JSON.parse(JSON.stringify(usage.faces[0]));
  second.reference.entity_path = [102]; second.reference.entity_id = "fac_c";
  usage.faces.unshift(Object.assign({}, second, { state: "unclassified", values: {} }));
  usage.faces.push(Object.assign({}, second, {
    reference: Object.assign({}, second.reference, { entity_path: [103] }) }));
  usage.assembly_usage[0].face_count = 2;
  usage.assembly_usage[0].faces.push(usage.faces[2].reference);
  o.paint();
  var replace = rowAction(inventory, row, "replace_assembly");
  assert.strictEqual(replace.label, "Replace and delete Wall");
  inventory.tableOptions.action(row, replace);
  var dialog = o.document.querySelectorAll("dialog").filter(function (node) { return !node.hidden; })[0];
  var shown = text(dialog);
  assert.ok(shown.includes("Replace and delete Wall"));
  assert.ok(shown.includes("Moves every Face that uses Wall to the Assembly you choose, or leaves them with none, " +
    "then deletes Wall."), shown);
  assert.ok(shown.includes("2 Faces: Zone 1 · Wall 2, Zone 1 · Wall 3"), shown);
  assert.ok(!/\[|10[123]|fac_/.test(shown), "no internal id reaches the dialog: " + shown);
});
test("the row's Delete lists the same Faces, and an Assembly on no Face is not told its Faces will move", function () {
  var o = setup(), inventory = o.query("[data-section='assemblies']")._view.inventory;
  var used = { record: inventory.records[0] }, unused = { record: inventory.records[1] };
  inventory.tableOptions.action(used, rowAction(inventory, used, "delete"));
  var dialog = o.document.querySelectorAll("dialog").filter(function (node) { return !node.hidden; })[0];
  assert.ok(text(dialog).includes("Moves every Face that uses Wall"), text(dialog));
  assert.ok(text(dialog).includes("1 Face: Zone 1 · Wall 1"), text(dialog));
  click(dialog.querySelectorAll("button").filter(function (button) { return button.textContent === "Cancel"; })[0]);
  inventory.tableOptions.action(unused, rowAction(inventory, unused, "delete"));
  dialog = o.document.querySelectorAll("dialog").filter(function (node) { return !node.hidden; })[0];
  assert.ok(!text(dialog).includes("Moves every Face"), text(dialog));
  assert.ok(text(dialog).includes("Choose a replacement or clear existing uses."), text(dialog));
});
test("a long Face list in Replace and delete names the first Faces and counts the rest", function () {
  var o = setup(), inventory = o.query("[data-section='assemblies']")._view.inventory;
  var row = { record: inventory.records[0] };
  var usage = o.state.sections[PREFIX + ".usage"].value, base = usage.faces[0];
  usage.faces = []; usage.assembly_usage[0].faces = [];
  for (var n = 0; n < 25; n += 1) {
    var face = JSON.parse(JSON.stringify(base));
    face.reference.entity_path = [200 + n];
    usage.faces.push(face);
    usage.assembly_usage[0].faces.push(face.reference);
  }
  usage.assembly_usage[0].face_count = 25;
  o.paint();
  inventory.tableOptions.action(row, rowAction(inventory, row, "replace_assembly"));
  var shown = text(o.document.querySelectorAll("dialog").filter(function (node) { return !node.hidden; })[0]);
  assert.ok(shown.includes("25 Faces: Zone 1 · Wall 1"), shown);
  assert.ok(shown.includes("and 5 more"), shown);
  assert.ok(!shown.includes("Wall 21"), shown);
});
test("Replace and delete is unavailable, with a reason, when no other Assembly exists", function () {
  var o = setup(), inventory = o.query("[data-section='assemblies']")._view.inventory;
  var records = o.state.sections["ph_composer.assemblies.assemblies"].value.records;
  records.splice(1, 1);
  o.paint();
  var row = { record: inventory.records[0] }, replace = rowAction(inventory, row, "replace_assembly");
  assert.strictEqual(replace.disabled, false, "the control stays on screen to say why");
  assert.strictEqual(replace.unavailable, "Wall is the only Assembly, so there is nothing to replace it with.");
});
test("withdrawal forgets a pending selection request and restores navigation without a late result", function () {
  var o = setup(), picker = byLabel(o.document.body, "Assembly for selected Faces");
  picker.value = "asm_a"; picker.listeners.change({});
  o.panel.showTab("assemblies");
  assert.strictEqual(o.panel.state.ui.activeTab, "overview", "a request in flight holds the tab");
  delete o.state.sections[PREFIX + ".assemblies"]; o.paint();
  o.panel.showTab("assemblies");
  assert.strictEqual(o.panel.state.ui.activeTab, "assemblies");
  assert.ok(picker.disabled);
  picker.value = "asm_b"; picker.listeners.change({});
  assert.strictEqual(o.sent.length, 1);
});
test("contributed actions respect inventory drafts and withdrawn replacement controls cannot write", function () {
  var o = setup(), inventory = o.query("[data-section='assemblies']")._view.inventory;
  var cell = inventory.edits.cells["asm_a:name"], input = cell.input;
  input.value = "Draft name"; input.listeners.input({});
  var row = { record: inventory.records[0] };
  var replace = inventory.tableOptions.actions(row).filter(function (action) {
    return action.id === "replace_assembly";
  })[0];
  inventory.tableOptions.action(row, replace);
  assert.ok(!o.document.querySelectorAll("dialog").some(function (node) { return !node.hidden; }));
  inventory.edits.cancel(cell); o.paint();
  inventory.tableOptions.action(row, replace);
  var dialog = o.document.querySelectorAll("dialog").filter(function (node) { return !node.hidden; })[0];
  var select = byLabel(dialog, "Replacement assembly");
  select.value = "asm_b"; select.listeners.change({});
  delete o.state.sections[PREFIX + ".usage"]; o.paint();
  dialog.querySelector("form").listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(o.sent.length, 0);
  o.panel.showTab("library");
  assert.strictEqual(o.panel.state.ui.activeTab, "library");
});


/* A second Face in the Faces read, checked through SketchUp's selection like the first. */
function addFace(o, entityPath, values) {
  var face = JSON.parse(JSON.stringify(o.face));
  face.reference.entity_path = [entityPath];
  face.reference.entity_id = "fac_" + entityPath;
  face.values = values;
  o.state.sections[PREFIX + ".faces"].value.faces.push(face);
  o.state.sections[PREFIX + ".selected"].value.targets.push({ reference: face.reference, expected_values: values });
  o.paint();
  return face;
}

test("the selection bar sets Type and Boundary on every checked Face, one attribute at a time", function () {
  var o = setup(), type = byLabel(o.document.body, "Type for selected Faces");
  var boundary = byLabel(o.document.body, "Boundary for selected Faces");
  assert.strictEqual(type.value, o.face.values.face_type, "what the selection shares is shown");
  assert.ok(!boundary.children.some(function (entry) { return entry.value === "AttachedZone"; }),
    "an Attached zone needs a record, so it is not offered here");
  boundary.value = "Ground";
  boundary.listeners.change({});
  assert.strictEqual(o.sent[0].payload.name, PREFIX + ".classify");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params)), { faces: [o.face.reference],
    intent: { face_type: { mode: "keep" }, boundary_condition: { mode: "set", value: "Ground" } },
    expected_values: o.face.values });
  var bar = o.query("[data-section='ph_composer.overview']").querySelector(".phc-selection-bar");
  assert.strictEqual(bar.hidden, false);
  assert.strictEqual(bar.querySelector(".phc-selection-bar-count").textContent, "1 Face selected");
  o.state.sections[PREFIX + ".selected"].value.targets = []; o.paint();
  assert.strictEqual(bar.hidden, true, "nothing checked, no bar");
});

test("the bar's Assembly rests on what the checked Faces share, and reads Mixed when they differ", function () {
  var o = setup();
  var picker = byLabel(o.document.body, "Assembly for selected Faces");
  o.face.values.assembly_id = "asm_a";
  o.paint();
  assert.deepStrictEqual([picker.value, picker.children[0].textContent], ["asm_a", "Choose Assembly"]);
  picker.listeners.change({});
  assert.strictEqual(o.sent.length, 0, "choosing what is already assigned sends nothing");
  picker.value = ""; picker.listeners.change({});
  assert.deepStrictEqual([picker.value, o.sent.length], ["asm_a", 0], "the label is not a choice");
  addFace(o, 999, { face_type: "Wall", boundary_condition: "Outdoors", assembly_id: null });
  assert.deepStrictEqual([picker.value, picker.children[0].textContent], ["", "Mixed"]);
  addFace(o, 998, {});
  assert.strictEqual(picker.disabled, true, "an unclassified Face cannot hold an Assembly yet");
  assert.match(picker.getAttribute("data-tooltip"), /Classify every checked Face/);
});

test("checked Faces that disagree read Mixed; a value the tree keeps read only is read only here", function () {
  var o = setup();
  addFace(o, 999, { face_type: "Floor", boundary_condition: "Surface" });
  var type = byLabel(o.document.body, "Type for selected Faces");
  var boundary = byLabel(o.document.body, "Boundary for selected Faces");
  assert.deepStrictEqual([type.value, type.children[0].textContent, type.children[0].disabled], ["", "Mixed", true]);
  assert.strictEqual(boundary.disabled, true, "one of them is a paired Surface");
  type.value = "Wall";
  type.listeners.change({});
  var params = JSON.parse(JSON.stringify(o.sent[0].payload.params));
  assert.strictEqual(params.faces.length, 2);
  assert.strictEqual(params.expected_values, undefined, "several Faces share no one set of values to guard by");
});

test("the Assembly paint glyph stops the tool without sending a null assignment", function () {
  var o = setup();
  o.state.sections[PREFIX + ".palette"].value.palette.assembly_id = "asm_a";
  o.state.sections[PREFIX + ".palette"].value.active = true;
  o.paint();
  click(byLabel(o.document.body, "Paint Assembly: Wall. Click to stop painting"));
  assert.strictEqual(o.sent[0].type, "view.invoke");
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.zones.faces.stop_classifying");
  assert.deepStrictEqual(o.sent[0].payload.params, {});
});
