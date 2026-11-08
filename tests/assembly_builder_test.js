"use strict";
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var source = require("./support/panel_source");
var fixtures = require("./support/inventory_fixtures");
var ASSEMBLIES = "ph_composer.assemblies.assemblies";
var MATERIALS = "ph_composer.assemblies.materials";
function setup() {
  var document = dom.buildDocument("");
  var context = { document: document, Intl: Intl, innerWidth: 1280, setTimeout: setTimeout,
    clearTimeout: clearTimeout };
  context.window = context;
  dom.attachEvents(context);
  var modules = source.start(context, ["features/assemblies/editor"]), sent = [], notices = [];
  var state = fixtures.state();
  var record = state.sections[ASSEMBLIES].value.records[0];
  record.values.orientation = "first_layer_outside";
  record.values.ventilated_cladding = false;
  record.values.layers = [
    { id: "layer_board", thickness_mm: 12, segments: [{ id: "seg_board", width_mm: 600, material_id: "mat_b" }] },
    { id: "layer_studs", thickness_mm: 140, segments: [
      { id: "seg_wool", width_mm: 560, material_id: "mat_a", is_continuous_insulation: false },
      { id: "seg_steel", width_mm: 40, material_id: null, steel_stud_spacing_mm: 600 }] }
  ];
  record.display = { total_thickness_mm: 152, color: "#c5e1a5", thermal: { complete: true,
    u_effective_w_m2k: 0.21, u_construction_w_m2k: 0.22, rsi_m2k_w: 0.13, rse_m2k_w: 0.04, direction: "horizontal",
    warnings: [], message_parts: [] } };
  var editor = new modules["features/assemblies/editor"].Editor("session", function (type, payload) {
    sent.push({ type: type, payload: payload });
  }, function (message) { notices.push(message); }, function () {});
  document.body.appendChild(editor.root);
  editor.refresh(state, record.id);
  return { editor: editor, modules: modules, state: state, record: record, sent: sent, notices: notices,
    document: document };
}
function click(node) { node.listeners.click({ preventDefault: function () {} }); }
function typed(field, text) { field.input.value = text; field.input.listeners.input({}); }
function text(node) { return node.textContent + node.children.map(text).join(" "); }
function result(o, status) {
  o.state.ui.actionResult = { session: "session", request_id: o.sent[o.sent.length - 1].payload.request_id,
    outcome: { status: status || "completed", message: "Changed in the Model." } };
  o.editor.refresh(o.state, o.record.id);
}
test("Canvas reference retains mixed widths, steel metadata and keyed selection without thermal math", function () {
  var o = setup(), shared = o.modules["features/assemblies/editor_shared"];
  var materials = shared.lookup(o.state.sections[MATERIALS].value.records);
  var canvas = o.modules["features/assemblies/canvas"], layout = canvas.geometry(o.record.values, materials);
  assert.strictEqual(layout.widthMm, 600);
  assert.strictEqual(layout.heightMm, 152);
  assert.strictEqual(layout.segments[2].xMm, 560);
  assert.strictEqual(layout.segments[2].segment.steel_stud_spacing_mm, 600);
  var svg = dom.element("svg");
  canvas.render(svg, layout, materials, { selectedLayerId: "layer_studs", selectedSegmentId: "seg_steel" });
  var shape = svg.querySelector("[data-segment-id='seg_steel']");
  assert.ok(shape.className.includes("is-selected"));
  assert.ok(shape.className.includes("is-null-material"));
  canvas.render(svg, layout, materials, {});
  assert.strictEqual(svg.querySelector("[data-segment-id='seg_steel']"), shape);
  assert.strictEqual(o.sent.length, 0);
});
test("drawing insertion carries explicit nested IDs and snapshot expected_values in one action", function () {
  var o = setup();
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_steel" });
  click(hover(o, "layer_studs", "seg_steel", 198, 50));
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].type, "action.invoke");
  assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + ".segments.add");
  assert.strictEqual(o.sent[0].payload.params.layer_id, "layer_studs");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.expected_values.layers)),
    o.record.values.layers);
  click(o.editor.root.querySelector("[data-builder-action='layers.flip']"));
  assert.strictEqual(o.sent.length, 1, "a second gesture waits for the first");
});
test("both canonical U-values and films are shown, withheld values show reasons instead of zero", function () {
  var o = setup();
  assert.ok(text(o.editor.root).includes("U-value with films"));
  assert.ok(text(o.editor.root).includes("U-value construction only"));
  assert.ok(text(o.editor.root).includes("0.21"));
  assert.ok(text(o.editor.root).includes("0.22"));
  o.record.display.thermal = { complete: false, u_effective_w_m2k: null, u_construction_w_m2k: null,
    rsi_m2k_w: 0.13, rse_m2k_w: null, warnings: ["Choose a Material for Layer 2 · Layer-Segment 2."] };
  o.editor.refresh(o.state, o.record.id);
  assert.strictEqual(o.editor.root.querySelectorAll("[data-u-withheld]").length, 2);
  assert.ok(text(o.editor.root).includes("Choose a Material for Layer 2"));
  assert.strictEqual(o.sent.length, 0);
});
test("sidebar reads details and search without writes; Use and valid drops assign one explicit segment", function () {
  var o = setup(), sidebar = o.editor.sidebar;
  sidebar.openDetails(sidebar.entries.mat_a);
  assert.ok(text(sidebar.detail.bubble.content).includes("Conductivity"));
  assert.strictEqual(o.sent.length, 0);
  assert.strictEqual(sidebar.use(sidebar.entries.mat_a.row, { layerId: "bad", segmentId: "bad" }), false);
  assert.strictEqual(o.sent.length, 0);
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_steel" });
  sidebar.openDetails(sidebar.entries.mat_a);
  click(sidebar.detail.use);
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + ".segments.set_material");
  assert.strictEqual(o.sent[0].payload.params.segment_id, "seg_steel");
  assert.strictEqual(o.sent[0].payload.params.material_id, "mat_a");
});
test("each Dimension format changes the drawing's labels and its scope is one the host accepts", function () {
  var o = setup(), preferences = o.modules.unit_preferences;
  var scope = o.editor.root.querySelector("[data-dimension-format-scope]").getAttribute("data-dimension-format-scope");
  // Registry::ID_PATTERN, which Preferences.set applies to a scope; a scope it refuses is rolled back by the panel.
  assert.match(scope, /^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/);
  var units = o.modules.units, field = o.modules.fields.LENGTH_MM;
  units.dimensionFormats.forEach(function (entry) {
    preferences.set("unit_system", entry.system);
    preferences.set("dimension_format", entry.id, { scope: scope, system: entry.system });
    o.editor.refresh(o.state, o.record.id);
    var profile = units.profile({ scope: scope });
    assert.strictEqual(profile.dimensionFormat, entry.id);
    assert.strictEqual(o.editor.root.querySelector("[data-layer-thickness='layer_studs']").textContent,
      units.format(140, field, profile), entry.id);
  });
});
test("dimension UnitField freezes SI/IP drafts across repaint, guards Back and retains refusal", function () {
  var o = setup(), field = o.editor.dimensions["thickness:layer_studs"].field;
  typed(field, "160");
  o.modules.unit_preferences.set("unit_system", "IP");
  o.editor.refresh(o.state, o.record.id);
  assert.strictEqual(field.input.value, "160");
  assert.strictEqual(field.unit.textContent, "mm");
  assert.ok(o.editor.guard());
  o.editor.commitDimension("thickness:layer_studs");
  assert.strictEqual(o.sent[0].payload.params.thickness_mm, 160);
  result(o, "refused");
  assert.strictEqual(field.input.value, "160");
  assert.ok(field.editing);
  assert.ok(field.error.textContent.includes("Changed in the Model"));
  field.cancel();
  assert.strictEqual(o.editor.guard(), null);
  assert.notStrictEqual(field.input.value, "140");
});
test("external dimension changes require cancel and a disposed Builder forbids retained callbacks", function () {
  var o = setup(), field = o.editor.dimensions["thickness:layer_studs"].field;
  typed(field, "160");
  o.record.values.layers[1].thickness_mm = 145;
  o.editor.refresh(o.state, o.record.id);
  o.editor.commitDimension("thickness:layer_studs");
  assert.strictEqual(o.sent.length, 0);
  assert.ok(field.error.textContent.includes("Changed in the Model"));
  var add = o.editor.root.querySelector("[data-builder-action='layers.add']");
  o.editor.dispose();
  click(add);
  field.commit();
  assert.strictEqual(o.sent.length, 0);
});
module.exports = { setup: setup };

test("each topology and descriptor gesture sends one operation with physical target IDs", function () {
  var cases = [
    ["layers.add", { anchor_layer_id: "layer_studs", side: "outside" }],
    ["layers.remove", { layer_id: "layer_studs" }],
    ["layers.move", { layer_id: "layer_studs", direction: "outward" }],
    ["layers.flip", {}], ["layers.flip_orientation", {}],
    ["layers.set_air_barrier", { layer_id: "layer_studs", face: "interior" }],
    ["segments.remove", { layer_id: "layer_studs", segment_id: "seg_steel" }],
    ["segments.update", { layer_id: "layer_studs", segment_id: "seg_steel",
      values: { is_continuous_insulation: true } }], ["segments.mirror", {}]
  ];
  cases.forEach(function (entry) {
    var o = setup();
    assert.ok(o.editor.action(entry[0], entry[1]));
    assert.strictEqual(o.sent.length, 1);
    assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + "." + entry[0]);
    assert.strictEqual(o.sent[0].payload.params.id, "asm_a");
    Object.keys(entry[1]).forEach(function (key) {
      assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params[key])), entry[1][key]);
    });
    o.editor.dispose();
  });
});
test("membranes draw as rules and air barrier faces follow orientation without changing dimensions", function () {
  var o = setup(), values = o.record.values, canvas = o.modules["features/assemblies/canvas"];
  var materials = o.modules["features/assemblies/editor_shared"].lookup(o.state.sections[MATERIALS].value.records);
  materials.mat_b.category = "membrane";
  values.air_barrier = { layer_id: "layer_studs", face: "exterior" };
  var layout = canvas.geometry(values, materials);
  assert.strictEqual(layout.layers[0].heightMm, 9);
  assert.strictEqual(layout.layers[0].isMembrane, true);
  assert.strictEqual(layout.airBarrier.yMm, 9);
  values.orientation = "last_layer_outside";
  assert.strictEqual(canvas.geometry(values, materials).airBarrier.yMm, 149);
  assert.strictEqual(values.layers[0].thickness_mm, 12);
});
test("pointer drops reject outside/removed targets and dispatch exactly one accepted assignment", function () {
  var o = setup(), sidebar = o.editor.sidebar, drag = sidebar.drag, entry = sidebar.entries.mat_a;
  var hit = o.editor.main.querySelectorAll(".assembly-hit-target").filter(function (node) {
    return node.getAttribute("data-segment-id") === "seg_steel";
  })[0];
  var event = { button: 0, clientX: 30, clientY: 30, preventDefault: function () {} };
  o.document.elementFromPoint = function () { return null; };
  drag.start(entry, event);
  drag.update(Object.assign({}, event, { clientX: 50 }));
  drag.up(event);
  assert.strictEqual(o.sent.length, 0);
  o.document.elementFromPoint = function () { return hit; };
  drag.start(entry, event);
  drag.update(Object.assign({}, event, { clientX: 50 }));
  assert.ok(hit.classList.contains("is-drop-target"));
  drag.up(event);
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.params.segment_id, "seg_steel");
  assert.strictEqual(hit.classList.contains("is-drop-target"), false);
  assert.strictEqual(drag.entry, null);
});
test("leaving a dimension field applies it once; a sidebar toggle alone sends nothing", function () {
  var o = setup(), field = o.editor.dimensions["thickness:layer_studs"].field;
  typed(field, "160");
  o.editor.sidebar.toggle();
  assert.strictEqual(o.sent.length, 0, "folding the library is not leaving the field");
  field.input.listeners.blur({});
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.params.thickness_mm, 160);
  o.record.values.layers[1].thickness_mm = 160;
  result(o);
  assert.strictEqual(field.editing, false);
  assert.strictEqual(field.input.disabled, false);
  assert.strictEqual(o.editor.guard(), null);
});
test("a dimension bubble applies a changed draft as it closes and stays open on one it cannot apply", function () {
  var o = setup(), field = o.editor.dimensions["thickness:layer_studs"].field;
  typed(field, "abc");
  assert.ok(o.editor.settleDimension("thickness:layer_studs"), "an invalid draft keeps the bubble open");
  assert.strictEqual(o.sent.length, 0);
  typed(field, "150");
  assert.strictEqual(o.editor.settleDimension("thickness:layer_studs"), null);
  assert.strictEqual(o.sent[0].payload.params.thickness_mm, 150);
});
function hover(o, layerId, segmentId, x, y) {
  var hit = o.editor.root.querySelectorAll(".assembly-hit-target").filter(function (node) {
    return node.getAttribute("data-layer-id") === layerId && node.getAttribute("data-segment-id") === segmentId;
  })[0];
  hit.rect = { left: 0, top: 0, right: 200, bottom: 100, width: 200, height: 100 };
  hit.closest = function () { return hit; };
  o.editor.root.querySelector(".assembly-drawing").listeners.mousemove({ target: hit, clientX: x, clientY: y });
  return o.editor.root.querySelector(".assembly-insert");
}
test("an edge insert shows one control near the edge, named by its result, and selects what it made", function () {
  var o = setup();
  var control = hover(o, "layer_studs", "seg_wool", 100, 50);
  assert.strictEqual(control.hidden, true, "nothing in the middle of a Layer-Segment");
  control = hover(o, "layer_studs", "seg_wool", 198, 50);
  assert.deepStrictEqual([control.hidden, control.getAttribute("aria-label")], [false, "Insert Layer-Segment right"]);
  control = hover(o, "layer_studs", "seg_wool", 100, 2);
  assert.strictEqual(control.getAttribute("aria-label"), "Insert layer above");
  click(control);
  var params = o.sent[0].payload.params;
  assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + ".layers.add");
  assert.deepStrictEqual([params.anchor_layer_id, params.side, params.thickness_mm], ["layer_studs", "outside", 100],
    "the top of a first-Layer-outside Assembly is the exterior side, at a round default");
  o.record.values.layers.splice(1, 0, { id: "layer_new", thickness_mm: 100, segments: [{ id: "seg_new",
    width_mm: 600, material_id: null }] });
  result(o);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.editor.selection)),
    { layerId: "layer_new", segmentId: "seg_new" });
});
test("the insert icon's descendants retain the edge cue, and leaving clears only transient hover", function () {
  var o = setup(), control = hover(o, "layer_studs", "seg_wool", 198, 50);
  var drawing = o.editor.root.querySelector(".assembly-drawing");
  var highlight = drawing.querySelector(".assembly-edge-highlight");
  var hit = drawing.querySelector("[data-hover-edge='right']");
  var icon = o.document.createElementNS("http://www.w3.org/2000/svg", "svg");
  var path = o.document.createElementNS("http://www.w3.org/2000/svg", "path");
  icon.appendChild(path);
  control.appendChild(icon);
  var target = control._target;
  drawing.listeners.mousemove({ target: path, clientX: 200, clientY: 50 });
  assert.strictEqual(control.hidden, false);
  assert.strictEqual(control._target, target, "the icon preserves the intended insertion");
  assert.strictEqual(highlight.hidden, false);
  assert.strictEqual(hit.getAttribute("data-hover-edge"), "right");
  assert.strictEqual(o.sent.length, 0, "hover sends no action");
  drawing.listeners.mousemove({ target: drawing, clientX: 400, clientY: 400 });
  assert.strictEqual(control.hidden, true);
  assert.strictEqual(highlight.hidden, true);
  assert.strictEqual(hit.getAttribute("data-hover-edge"), null);
});
test("a Layer edge cue spans the Layer and its insert control stays at the same midpoint across segments", function () {
  var o = setup(), control = hover(o, "layer_studs", "seg_wool", 100, 2);
  var highlight = o.editor.root.querySelector(".assembly-edge-highlight");
  var midpoint = control.style.left;
  assert.strictEqual(highlight.style.left, "0px");
  assert.strictEqual(highlight.style.width, 600 * o.editor.zoom + "px");
  control = hover(o, "layer_studs", "seg_steel", 100, 2);
  assert.strictEqual(control.style.left, midpoint, "a Layer action has one stable control position");
  assert.strictEqual(highlight.hidden, false);
});
test("a membrane's side edges explain why they add nothing, and a second click lets a selection go", function () {
  var o = setup();
  o.state.sections[MATERIALS].value.records.forEach(function (record) {
    if (record.id === "mat_b") record.values.category = "Membrane";
  });
  o.editor.refresh(o.state, o.record.id);
  var control = hover(o, "layer_board", "seg_board", 2, 50);
  assert.ok(control.classList.contains("is-blocked"));
  click(control);
  assert.strictEqual(o.sent.length, 0);
  assert.ok(/membrane/i.test(o.notices[o.notices.length - 1]));
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_wool" });
  var hit = o.editor.root.querySelectorAll(".assembly-hit-target").filter(function (node) {
    return node.getAttribute("data-segment-id") === "seg_wool";
  })[0];
  click(hit);
  assert.strictEqual(o.editor.selection, null);
});
test("the selected Layer-Segment's width is a dimension line under exactly that segment", function () {
  var o = setup();
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_steel" });
  var line = o.editor.root.querySelector(".assembly-width-dimension");
  assert.strictEqual(line.style.left, 560 * o.editor.zoom + "px");
  assert.strictEqual(line.style.width, 40 * o.editor.zoom + "px");
  assert.ok(line.classList.contains("is-narrow"), "a narrow segment puts its label beside the line");
  assert.ok(o.editor.root.querySelector("[data-segment-width='seg_steel']"));
});
test("withdrawal resets a pending Builder and retained menu/sidebar callbacks cannot write", function () {
  var o = setup(), add = o.editor.root.querySelector("[data-builder-action='layers.add']");
  var entry = o.editor.sidebar.entries.mat_a;
  o.editor.action("layers.add", {});
  delete o.state.sections[ASSEMBLIES];
  o.editor.refresh(o.state, o.record.id);
  assert.strictEqual(o.editor.requests.busy(), false);
  click(add);
  o.editor.sidebar.use(entry.row, { layerId: "layer_studs", segmentId: "seg_steel" });
  assert.strictEqual(o.sent.length, 1);
});

test("assigned removal confirms consequences, Cancel writes nothing, and confirmation uses frozen guards", function () {
  var o = setup();
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_wool" });
  click(o.editor.root.querySelector("[data-builder-action='segments.remove']"));
  assert.strictEqual(o.sent.length, 0);
  assert.strictEqual(o.editor.removal.hidden, false);
  assert.ok(text(o.editor.removal).includes("Material assignment"));
  // The dialog's top-right close does what Cancel does.
  click(o.editor.removal.querySelector(".phc-dialog-close"));
  assert.strictEqual(o.editor.removal.hidden, true);
  assert.strictEqual(o.sent.length, 0);
  click(o.editor.main.querySelector("[data-layer-tools-trigger='layer_studs']"));
  click(o.editor.main.querySelector("[data-layer-tools-key='drawing:layer_studs']")
    .querySelector("[data-builder-action='layers.remove']"));
  var expected = JSON.parse(JSON.stringify(o.record.values.layers));
  o.record.values.layers[1].thickness_mm = 180;
  click(o.editor.removal.querySelector(".primary"));
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + ".layers.remove");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.expected_values.layers)), expected);
});
test("drawing selection restores keyed focus so Escape deselects after repaint", function () {
  var o = setup(), hit = o.editor.main.querySelector(".assembly-hit-target");
  hit.focus();
  click(hit);
  assert.strictEqual(o.document.activeElement.parentNode !== null, true);
  assert.notStrictEqual(o.document.activeElement, hit);
  assert.strictEqual(o.document.activeElement.getAttribute("data-segment-id"), "seg_board");
  var prevented = false;
  o.editor.root.listeners.keydown({ key: "Escape", preventDefault: function () { prevented = true; } });
  assert.strictEqual(prevented, true);
  assert.strictEqual(o.editor.selection, null);
  assert.strictEqual(o.sent.length, 0);
});
test("outside drag only suppresses its trailing pointer click and permits keyboard details", async function () {
  var o = setup(), sidebar = o.editor.sidebar, entry = sidebar.entries.mat_a, drag = sidebar.drag;
  var event = { button: 0, clientX: 30, clientY: 30, preventDefault: function () {} };
  o.document.elementFromPoint = function () { return null; };
  drag.start(entry, event);
  drag.update(Object.assign({}, event, { clientX: 50 }));
  drag.up(event);
  entry.button.listeners.click({ detail: 1 });
  assert.strictEqual(Boolean(sidebar.detail), false);
  entry.button.listeners.click({ detail: 0 });
  assert.ok(sidebar.detail);
  sidebar.closeDetails();
  drag.start(entry, event);
  drag.update(Object.assign({}, event, { clientX: 50 }));
  drag.up(event);
  await new Promise(function (resolve) { setTimeout(resolve, 1); });
  assert.strictEqual(entry.suppressClick, false);
  assert.strictEqual(o.sent.length, 0);
});

test("the toolbar shows a selection's tools only while a Layer-Segment is selected", function () {
  var o = setup(), bar = o.editor.root.querySelector(".assembly-toolbar");
  var selection = bar.querySelector(".assembly-selection-tools");
  assert.strictEqual(selection.querySelectorAll("button").length, 1, "Material Library stays available");
  assert.strictEqual(bar.children[0], selection, "selection context precedes drawing controls");
  o.editor.sidebar.collapsed = true;
  var writes = o.sent.length;
  click(selection.querySelector("button"));
  assert.strictEqual(o.editor.sidebar.collapsed, false);
  assert.strictEqual(o.document.activeElement, o.editor.sidebar.search);
  assert.strictEqual(o.sent.length, writes, "opening the library does not write to the Model");
  assert.strictEqual(selection.children[0].textContent, "Select a Layer-Segment");
  assert.strictEqual(o.editor.root.querySelectorAll("[data-builder-action='segments.add']").length, 0);
  ["segments.mirror", "layers.flip", "layers.flip_orientation"].forEach(function (action) {
    assert.ok(bar.querySelector("[data-builder-action='" + action + "']"), action + " is in the menu");
  });
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_steel" });
  bar = o.editor.root.querySelector(".assembly-toolbar");
  assert.strictEqual(bar.querySelectorAll("[data-builder-action='segments.add']").length, 0,
    "segment insertion is offered on the drawing edge");
  ["Delete segment", "Segment properties"].forEach(function (label) {
    assert.ok(bar.querySelectorAll("button").some(function (node) {
      return node.getAttribute("aria-label") === label; }), label + " is an icon named for what it does");
  });
  ["Delete segment"].forEach(function (label) {
    var button = bar.querySelectorAll("button").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
    assert.strictEqual(button.getAttribute("data-tooltip"), label, "enabled actions retain their hints");
  });
  assert.strictEqual(o.editor.root.querySelector(".assembly-back").getAttribute("aria-label"), "Back to Assemblies");
});

test("the last segment's disabled delete icon retains its reason in the app tooltip", function () {
  var o = setup();
  o.state.sections[MATERIALS].value.records.forEach(function (record) {
    if (record.id === "mat_b") record.values.category = "Membrane";
  });
  o.editor.refresh(o.state, o.record.id);
  o.editor.select({ layerId: "layer_board", segmentId: "seg_board" });
  var remove = o.editor.root.querySelector("[data-builder-action='segments.remove']");
  assert.strictEqual(remove.disabled, true);
  assert.strictEqual(remove.getAttribute("data-tooltip"), "A Layer keeps at least one Layer-Segment");
});

test("closing a dimension bubble settles an equal retype and never refuses a Builder being torn down", function () {
  var o = setup(), field = o.editor.dimensions["thickness:layer_studs"].field;
  typed(field, "140.0");
  assert.strictEqual(o.editor.settleDimension("thickness:layer_studs"), null,
    "an equal value is settled, not refused");
  assert.strictEqual(o.sent.length, 0);
  typed(field, "abc");
  o.editor.dispose();
  assert.strictEqual(o.editor.settleDimension("thickness:layer_studs"), null, "teardown closes whatever is open");
});
test("a turned Assembly inserts toward its interior above, and a refused insert selects nothing later", function () {
  var o = setup();
  o.record.values.orientation = "last_layer_outside";
  o.editor.refresh(o.state, o.record.id);
  click(hover(o, "layer_studs", "seg_wool", 100, 2));
  assert.strictEqual(o.sent[0].payload.params.side, "inside");
  result(o, "refused");
  assert.strictEqual(o.editor.pendingInsert, null);
  click(hover(o, "layer_studs", "seg_steel", 2, 50));
  assert.strictEqual(o.sent[1].payload.params.index, 1, "the left edge inserts before the Layer-Segment");
});
test("Enter in a dimension, sent through the tree, is the Builder's and sends one action", function () {
  var o = setup(), entry = o.editor.dimensions["thickness:layer_studs"];
  typed(entry.field, "150");
  var event = dom.dispatch(entry.field.input, { type: "keydown", key: "Enter" });
  assert.strictEqual(event.defaultPrevented, true);
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.params.thickness_mm, 150);
  assert.strictEqual(entry.field.editing, true, "UnitField's own Enter never ran, so the draft waits for the Model");
});
test("Layer tools retains Delete Layer and confirms assigned Materials", function () {
  var o = setup();
  o.editor.select({ layerId: "layer_board", segmentId: "seg_board" });
  var board = o.editor.root.querySelector("[data-builder-action='layers.remove']");
  assert.ok(board, "Layer tools keeps the destructive action");
  click(board);
  assert.strictEqual(o.sent.length, 0, "a Layer holding a Material asks first");
  assert.strictEqual(o.editor.removal.hidden, false);
  click(o.editor.removal.querySelector(".primary"));
  assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + ".layers.remove");
  assert.strictEqual(o.sent[0].payload.params.layer_id, "layer_board");
});
test("the segment bubble shows its Material's values read only, and the header explains the U-value", function () {
  var o = setup();
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_wool" });
  var facts = o.editor.root.querySelector(".assembly-material-facts");
  assert.ok(facts.querySelectorAll(".phc-property-row").length === 4,
    "conductivity, density, specific heat, emissivity");
  assert.strictEqual(facts.querySelectorAll("input").length, 0, "nothing there is editable");
  var about = o.editor.root.querySelector(".assembly-information");
  assert.ok(text(about).includes("Surface films (ISO 6946)"));
  assert.ok(text(about).includes("Rse"));
});
test("the U-value popover shows each message once, with a count, whichever source repeats it", function () {
  var o = setup(), unassigned = { code: "assembly.segment_unassigned", message: "A Layer-Segment has no Material." };
  o.record.findings = [unassigned, unassigned, unassigned, unassigned,
    { code: "assembly.thermal_layer_limit", message: "Too many Layers." }];
  o.record.display.thermal = { complete: false, u_effective_w_m2k: null, u_construction_w_m2k: null, rsi_m2k_w: 0.13,
    rse_m2k_w: 0.04, direction: "horizontal", flags: ["assembly.geometry_invalid", "assembly.segment_unassigned"],
    warnings: ["Layer thickness is invalid.", "One or more segments do not have a material assignment."] };
  o.editor.refresh(o.state, o.record.id);
  var notes = o.editor.root.querySelector(".assembly-information-notes");
  assert.deepStrictEqual(notes.children.map(function (item) { return text(item).replace(/\s+/g, " ").trim(); }), [
    "Layer thickness is invalid.", "A Layer-Segment has no Material. × 4", "Too many Layers."]);
});
test("the U-value popover keeps a withheld reason that says something the list does not", function () {
  var o = setup();
  o.record.display.thermal = { complete: false, u_effective_w_m2k: null, u_construction_w_m2k: null, rsi_m2k_w: 0.13,
    rse_m2k_w: 0.04, flags: [], warnings: [],
    message_parts: [[{ type: "text", text: "Layer 2 is too thin." }]] };
  o.editor.refresh(o.state, o.record.id);
  var notes = o.editor.root.querySelector(".assembly-information-notes");
  assert.deepStrictEqual(notes.children.map(text), ["Layer 2 is too thin."]);
});
test("dimensions edit in place; Escape restores and closes without changing selection", function () {
  var o = setup(), entry = o.editor.dimensions["thickness:layer_studs"];
  o.editor.select({ layerId: "layer_studs", segmentId: "seg_wool" });
  click(entry.inlineControl.trigger);
  assert.strictEqual(entry.root.hidden, false);
  assert.strictEqual(o.document.activeElement, entry.field.input);
  assert.strictEqual(entry.inlineControl.trigger.hidden, true);
  typed(entry.field, "180");
  dom.dispatch(entry.field.input, { type: "keydown", key: "Escape" });
  assert.strictEqual(entry.root.hidden, true);
  assert.strictEqual(entry.field.input.value, "140");
  assert.strictEqual(o.document.activeElement, entry.inlineControl.trigger);
  assert.strictEqual(o.editor.selection.segmentId, "seg_wool");
  assert.strictEqual(o.sent.length, 0);
});
test("inline acceptance closes the field and returns Enter focus to its value", function () {
  var o = setup(), key = "thickness:layer_studs", entry = o.editor.dimensions[key];
  click(entry.inlineControl.trigger); typed(entry.field, "160");
  dom.dispatch(entry.field.input, { type: "keydown", key: "Enter" });
  assert.strictEqual(entry.inlineOpen, true, "the draft stays until the Model accepts");
  o.record.values.layers[1].thickness_mm = 160; result(o);
  assert.strictEqual(entry.root.hidden, true);
  assert.strictEqual(o.document.activeElement, entry.inlineControl.trigger);
  assert.strictEqual(o.sent.length, 1);
});
test("an invalid inline blur retains the field and Layer tools owns air-barrier choices", function () {
  var o = setup(), entry = o.editor.dimensions["thickness:layer_studs"];
  click(entry.inlineControl.trigger); typed(entry.field, "bad"); entry.field.input.listeners.blur({});
  assert.strictEqual(entry.root.hidden, false); assert.strictEqual(entry.field.error.hidden, false);
  assert.strictEqual(o.sent.length, 0);
  entry.field.cancel(); o.editor.select({ layerId: "layer_studs", segmentId: "seg_wool" });
  click(o.editor.main.querySelector("[data-layer-tools-trigger='layer_studs']"));
  click(o.editor.main.querySelector("[data-layer-tools-key='drawing:layer_studs']")
    .querySelector("[aria-label='Exterior face air barrier']"));
  assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + ".layers.set_air_barrier");
  assert.strictEqual(o.sent[0].payload.params.layer_id, "layer_studs");
  assert.strictEqual(o.sent[0].payload.params.face, "exterior");
});
test("an inline draft survives repaint and retains a refusal until Escape", function () {
  var o = setup(), entry = o.editor.dimensions["thickness:layer_studs"];
  click(entry.inlineControl.trigger); typed(entry.field, "180");
  o.editor.setZoom(0.8);
  assert.strictEqual(entry.inlineOpen, true); assert.strictEqual(entry.root.hidden, false);
  assert.strictEqual(entry.field.input.value, "180");
  assert.strictEqual(o.document.activeElement, entry.field.input);
  dom.dispatch(entry.field.input, { type: "keydown", key: "Enter" }); result(o, "refused");
  assert.strictEqual(entry.inlineOpen, true); assert.strictEqual(entry.root.hidden, false);
  assert.strictEqual(entry.field.input.value, "180"); assert.strictEqual(entry.field.error.hidden, false);
  dom.dispatch(entry.field.input, { type: "keydown", key: "Enter" });
  assert.strictEqual(o.sent.length, 1, "refused drafts cannot resend without canceling");
  dom.dispatch(entry.field.input, { type: "keydown", key: "Escape" });
  assert.strictEqual(entry.root.hidden, true); assert.strictEqual(entry.field.input.value, "140");
});
test("inline blur acceptance closes without taking focus from the next control", function () {
  var o = setup(), entry = o.editor.dimensions["thickness:layer_studs"], external = dom.element("button");
  o.document.body.appendChild(external);
  click(entry.inlineControl.trigger); typed(entry.field, "180"); external.focus();
  entry.field.input.listeners.blur({});
  o.record.values.layers[1].thickness_mm = 180; result(o);
  assert.strictEqual(entry.root.hidden, true); assert.strictEqual(o.document.activeElement, external);
  assert.strictEqual(o.sent.length, 1);
});
test("a membrane thickness label selects its Layer for tools without a numeric editor", function () {
  var o = setup(); o.state.sections[MATERIALS].value.records[1].values.category = "membrane";
  o.editor.refresh(o.state, o.record.id);
  click(o.editor.main.querySelector("[data-layer-thickness='layer_board']"));
  assert.strictEqual(o.editor.selection.layerId, "layer_board");
  assert.strictEqual(o.editor.dimensions["thickness:layer_board"], undefined);
  assert.ok(o.editor.main.querySelector("[aria-label='Interior face air barrier']"));
});
test("a Material becoming a membrane retains a thickness draft until explicit cancellation", function () {
  var o = setup(), key = "thickness:layer_board", entry = o.editor.dimensions[key];
  click(entry.inlineControl.trigger); typed(entry.field, "25");
  var material = o.state.sections[MATERIALS].value.records.filter(function (row) { return row.id === "mat_b"; })[0];
  material.values.category = "membrane";
  o.editor.refresh(o.state, o.record.id);
  assert.strictEqual(o.editor.dimensions[key], entry, "the snapshot must retain the draft owner");
  assert.strictEqual(entry.root.hidden, false); assert.strictEqual(entry.field.input.value, "25");
  assert.strictEqual(entry.field.input.readOnly, true); assert.strictEqual(entry.field.error.hidden, false);
  assert.ok(/membrane/.test(entry.field.error.textContent));
  assert.ok(o.editor.guard()); assert.strictEqual(o.editor.close(), false);
  dom.dispatch(entry.field.input, { type: "keydown", key: "Enter" });
  entry.field.input.listeners.blur({});
  assert.strictEqual(o.sent.length, 0, "a newly inapplicable thickness cannot be committed");
  material.values.category = "insulation"; o.editor.refresh(o.state, o.record.id);
  assert.strictEqual(entry.field.input.value, "25"); assert.strictEqual(entry.field.input.readOnly, false);
  assert.strictEqual(o.editor.commitDimension(key), false, "restoring applicability still requires cancellation");
  assert.ok(o.editor.guard()); assert.strictEqual(o.sent.length, 0);
  material.values.category = "membrane"; o.editor.refresh(o.state, o.record.id);
  dom.dispatch(entry.field.input, { type: "keydown", key: "Escape" });
  assert.strictEqual(o.editor.dimensions[key], undefined);
  assert.strictEqual(o.editor.guard(), null);
  var trigger = o.editor.main.querySelector("[data-layer-thickness='layer_board']");
  assert.strictEqual(trigger.textContent, "Membrane"); assert.strictEqual(o.document.activeElement, trigger);
  click(trigger); assert.strictEqual(o.editor.dimensions[key], undefined, "clean membranes have no numeric editor");
  material.values.category = "insulation"; o.editor.refresh(o.state, o.record.id);
  assert.strictEqual(o.editor.dimensions[key].field.input.value, "12"); assert.strictEqual(o.sent.length, 0);
});
test("drawing Layer tools target the hovered Layer without changing segment selection", function () {
  var o = setup(); o.editor.select({ layerId: "layer_studs", segmentId: "seg_wool" });
  assert.strictEqual(o.editor.main.querySelector(".assembly-toolbar")
    .querySelectorAll("[data-layer-tools-key]").length, 0, "Layer tools lives beside thickness, not in the toolbar");
  assert.strictEqual(o.editor.main.querySelector(".assembly-toolbar")
    .querySelectorAll("[data-builder-action='layers.add']").length, 0, "Layer insertion lives in the drawing");
  var trigger = o.editor.main.querySelector("[data-layer-tools-trigger='layer_board']");
  click(trigger);
  assert.strictEqual(trigger.getAttribute("aria-expanded"), "true");
  assert.strictEqual(o.editor.selection.segmentId, "seg_wool");
  assert.strictEqual(o.sent.length, 0);
  var menu = o.editor.main.querySelector("[data-layer-tools-key='drawing:layer_board']");
  click(menu.querySelector("[aria-label='Interior face air barrier']"));
  assert.strictEqual(o.sent[0].payload.name, ASSEMBLIES + ".layers.set_air_barrier");
  assert.strictEqual(o.sent[0].payload.params.layer_id, "layer_board");
  assert.strictEqual(o.sent[0].payload.params.face, "interior");
});
test("a Layer menu remains keyed to its Layer when a move renumbers the drawing", function () {
  var o = setup(), trigger = o.editor.main.querySelector("[data-layer-tools-trigger='layer_board']");
  click(trigger);
  var menu = o.editor.main.querySelector("[data-layer-tools-key='drawing:layer_board']");
  click(menu.querySelector("[data-builder-action='layers.move']"));
  assert.strictEqual(o.sent[0].payload.params.layer_id, "layer_board");
  o.record.values.layers.reverse(); result(o);
  menu = o.editor.main.querySelector("[data-layer-tools-key='drawing:layer_board']");
  assert.strictEqual(menu.hidden, false); assert.strictEqual(menu.getAttribute("aria-label"), "Layer 2 tools");
  assert.strictEqual(o.editor.main.querySelector("[data-layer-tools-key='drawing:layer_studs']").hidden, true);
});
test("Layer tools refuse opening over a dimension draft and protect the last Layer", function () {
  var o = setup(), entry = o.editor.dimensions["thickness:layer_studs"];
  typed(entry.field, "160");
  var trigger = o.editor.main.querySelector("[data-layer-tools-trigger='layer_board']"); click(trigger);
  assert.strictEqual(trigger.getAttribute("aria-expanded"), "false"); assert.strictEqual(o.sent.length, 0);
  entry.field.cancel(); o.record.values.layers = o.record.values.layers.slice(0, 1);
  o.editor.refresh(o.state, o.record.id);
  var menu = o.editor.main.querySelector("[data-layer-tools-key='drawing:layer_board']");
  assert.strictEqual(menu.querySelector("[data-builder-action='layers.remove']").disabled, true);
});
