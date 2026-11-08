"use strict";
var assert = require("assert"), test = require("node:test"), dom = require("./support/dom_stub"),
  source = require("./support/panel_source"), fixtures = require("./support/window_fixtures");
function setup() {
  var document = dom.buildDocument(""), context = { document: document, Intl: Intl, innerWidth: 1280,
    setTimeout: setTimeout, clearTimeout: clearTimeout }; context.window = context; dom.attachEvents(context);
  var modules = source.start(context, ["features/windows/editor"]), state = fixtures.state(), sent = [];
  var editor = new modules["features/windows/editor"].View(document.body, state.session, function (type, payload) {
    sent.push({ type: type, payload: payload }); }); editor.render(state);
  return { editor: editor, state: state, sent: sent, modules: modules, document: document };
}
function click(node) { node.listeners.click({ preventDefault: function () {}, stopPropagation: function () {} }); }
function text(node) { return node.textContent + node.children.map(text).join(" "); }
test("drawing renders explicit three elements including Empty and canonical U headlines", function () {
  var o = setup(); assert.strictEqual(o.editor.canvas.root.querySelectorAll("[data-window-element]").length, 3);
  assert.ok(text(o.editor.uwMetric).includes("0.8")); assert.ok(text(o.editor.installedMetric).includes("0.9"));
  assert.strictEqual(o.sent.length, 0);
  o.state.sections["ph_composer.windows.types"].value.records[0].display.thermal.uw_w_m2k = null;
  o.editor.render(o.state); assert.strictEqual(o.editor.uwMetric.textContent, "—");
});
function overallSize(o) { return o.editor.canvas.root.querySelector(".window-overall-dimension").textContent; }
test("each Dimension format changes the drawing's labels", function () {
  var o = setup(), preferences = o.modules.unit_preferences;
  var scope = o.editor.root.querySelector("[data-dimension-format-scope]")
    .getAttribute("data-dimension-format-scope");
  var seen = {}, units = o.modules.units, field = o.modules.fields.LENGTH_M;
  units.dimensionFormats.forEach(function (entry) {
    preferences.set("unit_system", entry.system);
    preferences.set("dimension_format", entry.id, { scope: scope, system: entry.system }); o.editor.render(o.state);
    var profile = units.profile({ scope: scope }), side = units.format(1.5, field, profile);
    assert.strictEqual(profile.dimensionFormat, entry.id);
    assert.strictEqual(overallSize(o), side + " × " + side, entry.id);
    assert.ok(!seen[overallSize(o)], entry.id + " reads differently from the other formats");
    seen[overallSize(o)] = true;
  });
});
function operationLines(o, operation, interior) {
  o.state.sections["ph_composer.windows.types"].value.records[0].values.elements[0].operation = operation;
  o.editor.interior = Boolean(interior); o.editor.render(o.state);
  return o.editor.canvas.root.querySelector("[data-window-element='wel_a']").querySelectorAll(".window-operation")
    .map(function (line) { return line.getAttribute("points").split(" ").map(function (point) {
      return point.split(",").map(Number); }); });
}
test("a Slide operation draws an arrow in its direction, in either view", function () {
  var o = setup();
  [["right", 0, 1, false], ["left", 0, -1, false], ["down", 1, 1, false], ["up", 1, -1, false],
    ["right", 0, -1, true], ["left", 0, 1, true]].forEach(function (entry) {
    var lines = operationLines(o, { type: "slide", directions: [entry[0]] }, entry[3]);
    assert.strictEqual(lines.length, 2, "a shaft and a head");
    var shaft = lines[0], head = lines[1], axis = entry[1], across = 1 - axis, tail = shaft[0], tip = shaft[1];
    assert.strictEqual(shaft.length, 2);
    assert.ok((tip[axis] - tail[axis]) * entry[2] > 0, entry[0] + " points its own way");
    assert.strictEqual(tip[across], tail[across], entry[0] + " is a straight shaft");
    assert.strictEqual(head.length, 3);
    assert.deepStrictEqual(head[1], tip, "both barbs leave the tip");
    [head[0], head[2]].forEach(function (barb) {
      assert.ok((barb[axis] - tip[axis]) * entry[2] < 0, "barbs sweep back"); });
    assert.ok(Math.abs((head[0][across] + head[2][across]) / 2 - tip[across]) < 1e-9, "barbs are symmetric");
  });
});
test("a Swing operation keeps its triangle to the hinge side", function () {
  var line = operationLines(setup(), { type: "swing", directions: ["right"] })[0];
  assert.strictEqual(line.length, 3);
  assert.ok(line[1][0] > line[0][0] && line[1][0] > line[2][0]);
});
test("toolbar sends one named grid action with explicit IDs and raw expected values", function () {
  var o = setup(); o.editor.select("wel_a"); o.editor.select("wel_b", { shiftKey: true });
  click(o.editor.root.querySelector("[data-window-action='merge']"));
  assert.strictEqual(o.sent.length, 1); assert.strictEqual(o.sent[0].payload.name,
    "ph_composer.windows.types.grid.merge");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.ids)), ["wel_a", "wel_b"]);
  assert.ok(o.sent[0].payload.params.expected_values.elements);
  click(o.editor.root.querySelector("[data-window-action='flip']")); assert.strictEqual(o.sent.length, 1);
});
test("dimension unit draft survives a unit switch and navigation is guarded", function () {
  var o = setup(); o.editor.dimension("columns_m", 0, o.editor.title);
  var field = o.editor.dimensionField; field.input.value = "500 mm"; field.input.listeners.input({});
  o.modules.unit_preferences.set("unit_system", "IP"); o.editor.render(o.state);
  assert.strictEqual(field.input.value, "500 mm"); assert.ok(o.editor.guard());
  field.cancel(); assert.strictEqual(o.sent.length, 0);
});
test("Installs stage locally, exclude shared edge, Save once and Cancel never writes", function () {
  var o = setup(), installs = o.editor.installEditor; installs.open(o.editor.rawRecord()); installs.selected = "psi_a";
  assert.strictEqual(installs.paintEdge("wel_a", "right"), false); assert.strictEqual(o.sent.length, 0);
  installs.paintEdge("wel_a", "top"); assert.ok(installs.guard()); assert.strictEqual(o.sent.length, 0);
  installs.saveAction(); installs.saveAction(); assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.types.installs.save");
  assert.strictEqual(o.sent[0].payload.params.types[0].installs[0].sides.top, "psi_a");
  var other = setup(); other.editor.installEditor.open(other.editor.rawRecord());
  other.editor.installEditor.paintEdge("wel_a", "top"); other.editor.installEditor.cancelSession(true);
  assert.strictEqual(other.sent.length, 0); assert.ok(other.editor.installEditor.root.hidden);
});
test("disposed Builder and withdrawn snapshots forbid retained actions", function () {
  var o = setup(), button = o.editor.addType; o.editor.dispose(); click(button); assert.strictEqual(o.sent.length, 0);
  o = setup(); delete o.state.sections["ph_composer.windows.types"]; o.editor.render(o.state);
  click(o.editor.addType); assert.strictEqual(o.sent.length, 0); assert.strictEqual(o.editor.guard(), null);
});
function outcome(o, status) {
  o.state.ui.actionResult = { session: "session", request_id: o.sent[o.sent.length - 1].payload.request_id,
    outcome: { status: status, message: "Changed in the Model. Cancel and reopen." } };
  o.editor.render(o.state);
}
test("one and two-element drawings are independent of missing thermal data", function () {
  var o = setup(), record = o.state.sections["ph_composer.windows.types"].value.records[0];
  record.values.elements = record.values.elements.slice(0, 2); record.values.columns_m = [0.5, null];
  fixtures.withTopology(record);
  record.display.thermal = { elements: [], uw_w_m2k: null, u_effective_w_m2k: null,
    findings: [{ code: "window_type.dimensions_incomplete", message: "Enter all grid dimensions." }] };
  o.editor.render(o.state);
    assert.strictEqual(o.editor.canvas.root.querySelectorAll("[data-window-element]").length, 2);
  assert.ok(o.editor.canvas.root.querySelector("[aria-label='Set column 2 width']"));
  record.values.elements = record.values.elements.slice(0, 1); record.values.columns_m = [null];
  fixtures.withTopology(record);
  o.editor.render(o.state);
    assert.strictEqual(o.editor.canvas.root.querySelectorAll("[data-window-element]").length, 1);
  o.editor.installEditor.open(record); o.editor.installEditor.selected = "psi_a";
  assert.strictEqual(o.editor.installEditor.paintEdge("wel_a", "top"), true);
  assert.strictEqual(o.sent.length, 0, "missing dimensions do not prevent local edge staging");
});
test("split, dimension, operation and repeated eyedropper paste carry their exact public shapes", function () {
  var o = setup(); o.editor.selected = ["wel_a"];
  o.editor.change("split", { id: "wel_a" });
  assert.strictEqual(o.sent[0].payload.params.id, "wnt_a");
  assert.strictEqual(o.sent[0].payload.params.element_id, "wel_a"); outcome(o, "completed");
  o.editor.change("set_element_operation", { id: "wel_a", operation: { type: "swing", directions: ["right"] } });
  assert.strictEqual(o.sent[1].payload.name, "ph_composer.windows.types.grid.set_element_operation");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[1].payload.params.operation)),
    { type: "swing", directions: ["right"] });
  assert.strictEqual(o.sent[1].payload.params.element_id, "wel_a"); outcome(o, "completed");
  o.editor.togglePick(); o.editor.select("wel_c"); assert.ok(o.editor.picking, "Empty cannot be the source");
  o.editor.select("wel_a"); o.editor.select("wel_c"); assert.strictEqual(o.sent.length, 2, "Empty cannot be pasted");
  o.editor.select("wel_b"); assert.strictEqual(o.sent[2].payload.params.source_id, "wel_a");
  outcome(o, "completed"); o.editor.select("wel_b"); assert.strictEqual(o.sent.length, 4);
  assert.strictEqual(o.editor.source, "wel_a");
});
test("dimension commit uses shared parsing, holds refusal text and prevents other writes", function () {
  var o = setup(); o.editor.dimension("columns_m", 0, o.editor.title);
  var field = o.editor.dimensionField; field.input.value = "600 mm"; field.input.listeners.input({});
  o.editor.createType(); assert.strictEqual(o.sent.length, 0);
  field.commit(); assert.strictEqual(o.sent[0].payload.params.value, 0.6);
  outcome(o, "refused"); assert.strictEqual(field.input.value, "600 mm"); assert.ok(field.editing);
  assert.ok(field.error.textContent.includes("Changed in the Model"));
  field.cancel(); assert.strictEqual(o.editor.guard(), null);
});
test("type depth resets through a null patch and numeric drafts retain full raw guards", function () {
  var o = setup(); o.editor.depthOverride(); var field = o.editor.dimensionField;
  field.input.value = "200 mm"; field.input.listeners.input({}); field.commit();
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.types.update");
  assert.strictEqual(o.sent[0].payload.params.values.install_depth_m, 0.2);
  assert.ok(!Object.prototype.hasOwnProperty.call(o.sent[0].payload.params.expected_values, "install_depth_m"));
  outcome(o, "completed"); assert.strictEqual(o.editor.dimensionField, null);
});
test("Installs copies compatible topology with independent element IDs and refuses changed shape", function () {
  var o = setup(), installs = o.editor.installEditor;
  var original = o.editor.rawRecord(), target = JSON.parse(JSON.stringify(original)); target.id = "wnt_b";
  target.values.name = "Other"; target.values.elements.forEach(function (cell) { cell.id += "_other"; });
  fixtures.withTopology(target);
  o.state.sections["ph_composer.windows.types"].value.records.push(target); o.editor.render(o.state);
  installs.open(original); installs.selected = "psi_a"; installs.paintEdge("wel_a", "top");
  assert.strictEqual(installs.copyTo(target), true);
  target.values.name = "Changed later"; installs.saveAction();
  var types = o.sent[0].payload.params.types;
  assert.strictEqual(types.length, 2); assert.strictEqual(types[1].expected_values.name, "Other");
  assert.strictEqual(types[1].installs[0].element_id, "wel_a_other");
  assert.strictEqual(types[1].installs[0].sides.top, "psi_a");
  outcome(o, "refused"); assert.ok(installs.dirty); assert.ok(!installs.root.hidden);
  target.values.columns_m = [2]; fixtures.withTopology(target); assert.strictEqual(installs.copyTo(target), false);
});
test("product cards retain input identity, warn on missing quantities and audit names Empty", function () {
  var o = setup(), frame = o.state.sections["ph_composer.windows.frames"].value.records[0];
  frame.values.uf_w_m2k = null; o.editor.render(o.state);
  assert.ok(o.editor.cards.wel_a.rows.top.row.className.includes("is-incomplete"));
  assert.strictEqual(o.editor.cards.wel_a.rows.top.cells[0].textContent, "—");
  var operation = o.editor.cards.wel_a.operation; o.editor.select("wel_a");
  assert.strictEqual(o.editor.cards.wel_a.operation, operation);
  o.editor.tabs.select("audit"); assert.ok(text(o.editor.audit).includes("Empty, excluded wall area"));
  assert.ok(text(o.editor.audit).includes("Installed U"));
});
test("local product sidebar remains available without providers and details send no actions", function () {
  var o = setup(), sidebar = o.editor.sidebars.frames;
  assert.strictEqual(sidebar.store.available, false); assert.strictEqual(sidebar.source.value, "");
  sidebar.openDetails(sidebar.entries.frm_a); assert.strictEqual(o.sent.length, 0);
  o.editor.select("wel_a"); sidebar.use(sidebar.entries.frm_a.row);
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.types.grid.set_element_frame");
  assert.strictEqual(o.sent[0].payload.params.side, "top");
  assert.strictEqual(o.sent[0].payload.params.frame_id, "frm_a");
});
test("leaving a dirty Installs session asks, then discards locally and continues only after confirmation", function () {
  var o = setup(), installs = o.editor.installEditor, continued = false;
  installs.open(o.editor.rawRecord()); installs.selected = "psi_a"; installs.paintEdge("wel_a", "top");
  installs.cancelSession(false, function () { continued = true; });
  assert.ok(!installs.confirm.hidden); assert.strictEqual(continued, false); assert.strictEqual(o.sent.length, 0);
  var discard = installs.confirm.querySelectorAll("button").filter(function (button) {
    return button.textContent === "Discard changes";
  })[0]; click(discard);
  assert.strictEqual(continued, true); assert.ok(installs.root.hidden); assert.strictEqual(o.sent.length, 0);
});
test("renaming retains a refused draft, rejects empty names locally, then permits Cancel", function () {
  var o = setup(); o.editor.renameInline(); var input = o.editor.root.querySelector(".window-title-input");
  input.value = ""; input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.strictEqual(o.sent.length, 0); assert.ok(o.editor.renameDraft);
  input.value = "Renamed"; input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.types.update");
  outcome(o, "refused"); assert.strictEqual(input.value, "Renamed"); assert.strictEqual(input.disabled, false);
  input.listeners.keydown({ key: "Escape", preventDefault: function () {} });
  assert.strictEqual(o.editor.guard(), null);
});
test("rail rename remains keyed and visible when the Model name changes", function () {
  var o = setup(), anchor = o.editor.list.querySelector("button");
  o.editor.renameInline(o.editor.record(), anchor);
  var input = o.editor.renameNodes[0]; input.value = "Local name draft";
  o.editor.rawRecord().values.name = "Changed elsewhere"; o.editor.render(o.state);
  assert.strictEqual(o.editor.root.querySelector(".window-title-input"), input);
  assert.strictEqual(input.value, "Local name draft"); assert.ok(o.editor.guard());
  click(o.editor.renameNodes[2]); assert.strictEqual(o.editor.guard(), null);
  assert.ok(text(o.editor.list).includes("Changed elsewhere")); assert.strictEqual(o.sent.length, 0);
});
test("missing rename target and withdrawn types explicitly cancel header and rail drafts", function () {
  [true, false].forEach(function (header) {
    var o = setup(); o.editor.renameInline(o.editor.record(), header ? o.editor.title :
      o.editor.list.querySelector("button")); var input = o.editor.renameNodes[0]; input.value = "Draft";
    if (header) delete o.state.sections["ph_composer.windows.types"];
    else o.state.sections["ph_composer.windows.types"].value.records = [];
    o.editor.render(o.state); assert.strictEqual(o.editor.guard(), null);
    assert.strictEqual(o.editor.renameNodes, null);
    input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
    assert.strictEqual(o.sent.length, 0);
  });
});
test("Element name draft guards type, subtab and section navigation and bubble dismissal", function () {
  var o = setup(), other = JSON.parse(JSON.stringify(o.editor.rawRecord())); other.id = "wnt_b";
  o.state.sections["ph_composer.windows.types"].value.records.push(other); o.editor.render(o.state);
  o.editor.editName(o.editor.record().elements[0], o.editor.title);
  var bubble = o.editor.bubble, form = bubble.content.querySelector("form"), input = form.querySelector("input");
  input.value = "Unsaved name"; input.listeners.input({});
  o.editor.choose("wnt_b"); assert.strictEqual(o.editor.active, "wnt_a");
  assert.strictEqual(o.editor.tabs.select("audit"), false);
  assert.ok(o.editor.guard(), "the section navigation guard must retain this form");
  assert.strictEqual(bubble.close(false), false); assert.strictEqual(bubble.panel.hidden, false);
  assert.strictEqual(input.value, "Unsaved name"); assert.strictEqual(o.sent.length, 0);
  form.listeners.submit({ preventDefault: function () {} });
  assert.strictEqual(o.sent.length, 1); assert.strictEqual(o.sent[0].payload.params.name, "Unsaved name");
  outcome(o, "refused"); assert.strictEqual(bubble.panel.hidden, false); assert.ok(o.editor.guard());
  click(form.querySelectorAll("button")[0]); assert.strictEqual(o.editor.guard(), null);
  o.editor.choose("wnt_b"); assert.strictEqual(o.editor.active, "wnt_b");
});
test("withdrawn or disposed Element name form cancels and retained Apply cannot write", function () {
  [true, false].forEach(function (withdraw) {
    var o = setup(); o.editor.editName(o.editor.record().elements[0], o.editor.title);
    var bubble = o.editor.bubble, form = bubble.content.querySelector("form"), input = form.querySelector("input");
    input.value = "Unsaved"; input.listeners.input({});
    if (withdraw) { delete o.state.sections["ph_composer.windows.types"]; o.editor.render(o.state); }
    else o.editor.dispose();
    assert.strictEqual(bubble.panel.hidden, true); assert.strictEqual(o.editor.guard(), null);
    form.listeners.submit({ preventDefault: function () {} }); assert.strictEqual(o.sent.length, 0);
  });
});
test("Window section navigation uses the Element name guard and missing target cancels pending Apply", function () {
  var o = setup(), sectionGuard, context = { document: o.document }; context.window = context;
  var modules = source.start(context, ["features/windows/section"], {
    panel: { section: function () {}, workedOn: function () {},
      navigationGuard: function (name, guard) { sectionGuard = guard; } },
    "features/windows/editor": { View: function () { return o.editor; } },
    "features/windows/inventory": { definitions: {} }, "library/section": { registerSurface: function () {} }
  });
  modules["features/windows/section"].render(o.document.body, o.state, function () {});
  o.editor.editName(o.editor.record().elements[0], o.editor.title);
  var bubble = o.editor.bubble, form = bubble.content.querySelector("form"), input = form.querySelector("input");
  input.value = "Pending name"; input.listeners.input({}); assert.ok(sectionGuard("library"));
  form.listeners.submit({ preventDefault: function () {} }); assert.strictEqual(o.sent.length, 1);
  o.editor.rawRecord().values.elements.shift(); o.editor.render(o.state);
  assert.strictEqual(sectionGuard("library"), null); assert.strictEqual(bubble.panel.hidden, true);
  form.listeners.submit({ preventDefault: function () {} }); assert.strictEqual(o.sent.length, 1);
});
test("product picker filters replacements but keeps the current assignment and freezes the Frame patch", function () {
  var o = setup(), replacement = fixtures.record("frm_b", { name: "Steel casement", manufacturer: "Other",
    product_code: "SC-1", position: "head", operation: "swing", width_m: 0.06, uf_w_m2k: 1.5, psi_g_w_mk: 0.04 });
  o.state.sections["ph_composer.windows.frames"].value.records.push(replacement); o.editor.render(o.state);
  o.editor.picker("wel_a", "frames", "top", o.editor.cards.wel_a.rows.top.button);
  var bubble = o.editor.bubble, search = bubble.content.querySelector("input");
  search.value = "SC-1"; search.listeners.input({});
  assert.ok(bubble.content.querySelector("[aria-current='true']"));
  assert.ok(bubble.content.querySelector("[data-record-id='frm_b']"));
  var position = bubble.heading.querySelector("[data-filter='position']");
  position.value = "sill"; position.listeners.input({});
  assert.strictEqual(bubble.content.querySelector("[data-record-id='frm_b']"), null);
  var clear = bubble.heading.querySelectorAll("button").filter(function (button) {
    return text(button).includes("Clear filters");
  })[0]; click(clear);
  o.editor.rawRecord().values.elements[0].frames.bottom = "Changed later";
  click(bubble.content.querySelector("[data-record-id='frm_b']"));
  assert.strictEqual(o.sent.length, 1); var params = o.sent[0].payload.params;
  assert.strictEqual(params.side, "top"); assert.strictEqual(params.frame_id, "frm_b");
  assert.strictEqual(params.expected_values.elements[0].frames.bottom, "frm_a");
  outcome(o, "refused"); assert.strictEqual(bubble.panel.hidden, false);
  click(bubble.content.querySelector("[data-record-id='frm_b']")); assert.strictEqual(o.sent.length, 2);
  outcome(o, "completed"); assert.strictEqual(bubble.panel.hidden, true);
});
test("Glazing picker diagnoses a missing assignment and replacement or clear writes once", function () {
  var o = setup(); o.editor.rawRecord().values.elements[0].glazing_id = "glz_missing"; o.editor.render(o.state);
  o.editor.picker("wel_a", "glazings", null, o.editor.cards.wel_a.rows.glazing.button);
  var bubble = o.editor.bubble; assert.ok(text(bubble.content).includes("no longer in this model"));
  click(bubble.content.querySelector("[data-record-id='glz_a']"));
  assert.strictEqual(o.sent[0].payload.params.glazing_id, "glz_a");
  assert.strictEqual(o.sent[0].payload.params.expected_values.elements[0].glazing_id, "glz_missing");
  outcome(o, "completed"); o.editor.picker("wel_a", "glazings", null, o.editor.cards.wel_a.rows.glazing.button);
  var clear = o.editor.bubble.heading.querySelectorAll("button").filter(function (button) {
    return text(button).includes("Clear assignment");
  })[0]; click(clear); assert.strictEqual(o.sent[1].payload.params.glazing_id, null);
  outcome(o, "completed"); o.state.sections["ph_composer.windows.glazings"].value.records = [];
  o.editor.render(o.state); o.editor.picker("wel_b", "glazings", null, o.editor.title);
  assert.ok(text(o.editor.bubble.content).includes("No glazings in this model yet"));
  assert.strictEqual(o.sent.length, 2);
});
test("Empty cards hide products and missing construction findings identify the affected rows", function () {
  var o = setup(), raw = o.editor.rawRecord(), detail = raw.display.thermal.elements[0];
  assert.ok(o.editor.cards.wel_c.content.hidden); assert.ok(o.editor.cards.wel_c.value.hidden);
  assert.strictEqual(o.editor.cards.wel_c.empty.hidden, false);
  var cell = raw.values.elements[0]; cell.frames.left = null; cell.frames.right = "missing";
  var frame = o.state.sections["ph_composer.windows.frames"].value.records[0].values;
  frame.width_m = null; frame.uf_w_m2k = null; frame.psi_g_w_mk = null;
  var glazing = o.state.sections["ph_composer.windows.glazings"].value.records[0].values;
  glazing.ug_w_m2k = null; glazing.g_value = null;
  detail.findings = [{ code: "window_type.frame_width_unresolved", message: "A Frame width is missing." },
    { code: "window_type.construction_unresolved", message: "A value is missing." },
    { code: "window_type.g_value_missing", message: "Missing g-value." },
    { code: "window_type.install_unresolved", message: "top: no Psi-Install Type resolves.", side: "top" },
    { code: "window_type.glazing_area_nonpositive", message: "Frame widths leave no glazing area." },
    { code: "window_type.operation_incomplete", message: "Choose operation and handedness." },
    { code: "window_type.partial_shared_edge", message: "Canonical warning." }];
  o.editor.render(o.state); var card = o.editor.cards.wel_a;
  assert.ok(card.rows.glazing.flag.getAttribute("data-tooltip").includes("Ug"));
  assert.ok(card.rows.glazing.flag.getAttribute("data-tooltip").includes("g-value"));
  assert.ok(card.rows.left.flag.getAttribute("data-tooltip").includes("Product"));
  assert.ok(card.rows.right.flag.getAttribute("data-tooltip").includes("Product not found"));
  assert.ok(card.rows.top.flag.getAttribute("data-tooltip").includes("Width"));
  assert.ok(card.rows.top.flag.getAttribute("data-tooltip").includes("Psi-Install"));
  assert.ok(card.operationFlag.getAttribute("data-tooltip").includes("direction"));
  assert.ok(text(card.findings).includes("Frame widths leave no glazing area"));
  assert.ok(text(card.findings).includes("Canonical warning")); assert.strictEqual(o.sent.length, 0);
});
test("operation direction buttons map Interior presentation to canonical handedness", function () {
  var o = setup(), card = o.editor.cards.wel_a; card.operation.value = "swing";
  card.operation.listeners.change({}); assert.strictEqual(o.sent[0].payload.params.operation.type, "swing");
  outcome(o, "completed"); o.editor.rawRecord().values.elements[0].operation = { type: "swing", directions: [] };
  o.editor.interior = true; o.editor.render(o.state); click(card.directions.left);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[1].payload.params.operation.directions)), ["right"]);
  outcome(o, "completed"); o.editor.rawRecord().values.elements[0].operation.directions = ["right"];
  o.editor.render(o.state); assert.strictEqual(card.directions.left.getAttribute("aria-pressed"), "true");
  click(card.directions.left); assert.strictEqual(o.sent[2].payload.params.operation.directions.length, 0);
});
test("Installs validates and stages Psi products, then saves their frozen updates atomically", function () {
  var o = setup(), installs = o.editor.installEditor; installs.open(o.editor.rawRecord());
  installs.editProduct(); var name = installs.form.querySelector("input");
  installs.form.onsubmit({ preventDefault: function () {} }); assert.strictEqual(installs.products.length, 1);
  name.value = " New junction "; installs.productField.input.value = "bad psi";
  installs.productField.input.listeners.input({}); installs.form.onsubmit({ preventDefault: function () {} });
  assert.strictEqual(installs.form.hidden, false); assert.strictEqual(installs.productField.error.hidden, false);
  installs.productField.input.value = "0.05"; installs.productField.input.listeners.input({});
  installs.form.onsubmit({ preventDefault: function () {} });
  var created = installs.products[1], clientId = created.id; assert.strictEqual(created.values.name, "New junction");
  assert.strictEqual(o.sent.length, 0); installs.editProduct(created);
  installs.form.querySelector("input").value = "Renamed staged junction";
  installs.form.onsubmit({ preventDefault: function () {} });
  assert.strictEqual(Object.keys(installs.updates).length, 0);
  installs.editProduct(installs.products[0]); installs.form.querySelector("input").value = "Edited existing junction";
  installs.form.onsubmit({ preventDefault: function () {} }); installs.selected = clientId; installs.applyAll();
  installs.saveAction(); var params = o.sent[0].payload.params;
  assert.strictEqual(o.sent.length, 1); assert.strictEqual(params.psi_install_types.create[0].client_id, clientId);
  assert.strictEqual(params.psi_install_types.create[0].values.name, "Renamed staged junction");
  assert.strictEqual(params.psi_install_types.update[0].expected_values.name, "Insulated junction");
  assert.strictEqual(params.psi_install_types.update[0].values.name, "Edited existing junction");
  assert.strictEqual(params.types[0].installs.length, 2, "Empty contributes no installations");
  assert.strictEqual(params.types[0].installs[0].sides.top, clientId);
  assert.strictEqual(params.types[0].installs[0].sides.right, null, "shared edges stay derived");
  outcome(o, "completed"); assert.strictEqual(installs.root.hidden, true); assert.strictEqual(installs.guard(), null);
});
test("Installs bulk paint and compatible copies stay local; missing defaults remain visible", function () {
  var o = setup(), installs = o.editor.installEditor, target = JSON.parse(JSON.stringify(o.editor.rawRecord()));
  target.id = "wnt_b"; target.values.name = "Compatible target";
  target.values.elements.forEach(function (cell) { cell.id += "_target"; }); fixtures.withTopology(target);
  o.state.sections["ph_composer.windows.types"].value.records.push(target);
  o.state.sections["ph_composer.windows.settings"].value.default_psi_install_id = "missing";
  o.editor.render(o.state); installs.open(o.editor.rawRecord());
  assert.ok(/Model default\s+Missing/.test(text(installs.list)));
  assert.ok(installs.drawing.querySelector("[aria-label='Element 1 top: Missing default']"));
  installs.selected = "psi_a"; click(installs.apply); click(installs.copyButton);
  var copy = installs.copyForm.querySelector("button"); assert.ok(copy.textContent.includes("Compatible target"));
  click(copy); assert.strictEqual(installs.drafts.wnt_b.elements[0].installs.top, "psi_a");
  assert.strictEqual(o.sent.length, 0); installs.selected = null; installs.applyAll();
  assert.strictEqual(installs.drafts.wnt_a.elements[0].installs.top, null);
  installs.cancelSession(true); installs.open(o.editor.rawRecord());
  o.state.sections["ph_composer.windows.types"].value.records.pop(); o.editor.render(o.state); installs.showCopy();
  assert.ok(text(installs.copyForm).includes("No compatible Window Types"));
  installs.editProduct(installs.products[0]);
  delete o.state.sections["ph_composer.windows.settings"]; o.editor.render(o.state);
  assert.strictEqual(installs.root.hidden, true); assert.strictEqual(installs.productField, null);
  assert.strictEqual(o.editor.guard(), null); installs.saveAction(); assert.strictEqual(o.sent.length, 0);
});
test("a new Type asks for the round imperial size only while the display system is IP", function () {
  var o = setup(), preferences = o.modules.unit_preferences;
  o.editor.createType();
  assert.deepStrictEqual(Object.keys(o.sent[0].payload.params.values), ["name"]);
  outcome(o, "completed"); preferences.replace({ unit_system: "IP", dimension_formats: {} });
  o.editor.createType();
  var values = o.sent[1].payload.params.values;
  assert.deepStrictEqual([values.columns_m[0], values.rows_m[0]], [1.016, 1.524]);
  preferences.replace({ unit_system: "SI", dimension_formats: {} });
});
test("Manage in Library on a product picker opens the Library tab at that kind", function () {
  var document = dom.buildDocument(source.markup("index.html")), context = { document: document, Intl: Intl,
    innerWidth: 1280, setTimeout: setTimeout, clearTimeout: clearTimeout }; context.window = context;
  dom.attachEvents(context);
  var modules = source.start(context, ["features/windows/editor"]), state = fixtures.state(), intents = [];
  var editor = new modules["features/windows/editor"].View(document.querySelector("[data-pane='windows']"),
    state.session, function () {});
  editor.render(state);
  modules.panel.section("library-probe", function () {}, { pane: "library", onNavigate: function (root, intent) {
    intents.push(intent);
  } });
  editor.picker("wel_a", "frames", "top", editor.cards.wel_a.rows.top.button);
  click(editor.bubble.heading.querySelectorAll("button").filter(function (button) {
    return text(button).includes("in Library");
  })[0]);
  assert.strictEqual(modules.panel.state.ui.activeTab, "library");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(intents)), [{ kind: "frames" }]);
});

function escape(node, target) {
  node.dispatchEvent({ type: "keydown", key: "Escape", target: target || node,
    preventDefault: function () { this.defaultPrevented = true; } });
}
test("Installs opens focused, with Save and Cancel in its header, and Escape unwinds one layer", function () {
  var o = setup(), installs = o.editor.installEditor; installs.open(o.editor.rawRecord());
  assert.ok(installs.list.contains(o.document.activeElement), "focus moves to the chosen Psi-Install Type");
  assert.strictEqual(o.document.activeElement.getAttribute("aria-pressed"), "true");
  var header = installs.root.querySelector(".phc-heading");
  assert.ok(text(header).includes("Three elements Installs"));
  assert.ok(header.contains(installs.save) && header.contains(installs.cancel));
  installs.editProduct(); assert.strictEqual(installs.form.hidden, false);
  escape(installs.root); assert.strictEqual(installs.form.hidden, true);
    assert.strictEqual(installs.root.hidden, false);
  installs.showCopy(); assert.strictEqual(installs.copyForm.hidden, false);
  escape(installs.root); assert.strictEqual(installs.copyForm.hidden, true);
    assert.strictEqual(installs.root.hidden, false);
  installs.open(o.editor.rawRecord()); installs.selected = "psi_a"; installs.paintEdge("wel_a", "top");
  escape(installs.root); assert.strictEqual(installs.confirm.hidden, false);
  escape(installs.root); assert.strictEqual(installs.root.hidden, false, "the open confirmation owns its own Escape");
  installs.confirm.closeModal(); installs.cancelSession(true); installs.open(o.editor.rawRecord());
  // The page body holds focus after a repaint; Escape still reaches the session.
  escape(o.document, o.document.body);
    assert.strictEqual(installs.root.hidden, true); assert.strictEqual(o.sent.length, 0);
});
test("a subtab chosen over Installs leaves a clean session and asks before discarding a staged one", function () {
  var o = setup(), installs = o.editor.installEditor, notices = []; installs.open(o.editor.rawRecord());
  o.modules.panel.notify = function (message, tone) { notices.push((tone || "info") + ": " + message); };
  click(o.editor.tabs.buttons.audit);
  assert.ok(installs.root.hidden); assert.strictEqual(o.editor.tabs.active, "audit");
  click(o.editor.tabs.buttons.builder); installs.open(o.editor.rawRecord()); installs.selected = "psi_a";
  installs.paintEdge("wel_a", "top"); click(o.editor.tabs.buttons.schedule);
  assert.strictEqual(installs.confirm.hidden, false); assert.strictEqual(o.editor.tabs.active, "builder");
  click(installs.confirm.querySelectorAll("button").filter(function (button) {
    return button.textContent === "Discard changes"; })[0]);
  assert.ok(installs.root.hidden); assert.strictEqual(o.editor.tabs.active, "schedule");
  // The shown subtab, chosen again, is the way back to the Builder.
  click(o.editor.tabs.buttons.builder); installs.open(o.editor.rawRecord()); click(o.editor.tabs.buttons.builder);
  assert.ok(installs.root.hidden); assert.strictEqual(o.editor.layout.hidden, false);
  installs.open(o.editor.rawRecord()); installs.paintEdge("wel_a", "top"); installs.saveAction();
  click(o.editor.tabs.buttons.audit);
  assert.strictEqual(installs.root.hidden, false, "a Save in flight keeps the session");
  assert.strictEqual(notices[notices.length - 1], "warning: Wait for Installs Save.",
    "the refusal goes to the panel's notice");
  // An open Psi-Install form is unaccepted work: the subtab is refused until it is accepted or cancelled.
  var other = setup(), form = other.editor.installEditor, said = [];
  other.modules.panel.notify = function (message, tone) { said.push(tone + ": " + message); };
  form.open(other.editor.rawRecord()); assert.strictEqual(other.editor.placement.root.hidden, true,
    "the Anchor row belongs to Place and is hidden during Installs");
  form.editProduct(); click(other.editor.tabs.buttons.audit);
  assert.strictEqual(form.root.hidden, false);
  assert.deepStrictEqual(said, ["warning: Accept or cancel the Psi-Install Type edit first."]);
});
test("Installs writes each perimeter value outside its element and one zero on a shared edge", function () {
  var o = setup(), installs = o.editor.installEditor; installs.open(o.editor.rawRecord());
  var labels = installs.drawing.querySelectorAll(".window-install-edge-label");
  assert.ok(labels.length && labels.every(function (label) { return !/D ·/.test(label.textContent); }));
  var first = installs.drawing.querySelector("rect"), top = Number(first.getAttribute("y")),
    left = Number(first.getAttribute("x")), bottom = top + Number(first.getAttribute("height")),
    right = left + Number(first.getAttribute("width"));
  var values = labels.filter(function (label) { return label.textContent !== "0"; });
  assert.ok(!values.some(function (label) {
    var x = Number(label.getAttribute("x")), y = Number(label.getAttribute("y"));
    return x > left && x < right && y > top && y < bottom;
  }), "no perimeter value sits inside the first element, whose edges are all on the outline or shared");
  // Element 2's right edge faces the Empty element, so its value stays inside Element 2.
  assert.strictEqual(values.filter(function (label) { return label.getAttribute("text-anchor") === "end"; }).length,
    2, "one value left of the outline and one held inside the element that faces Empty");
  assert.strictEqual(labels.filter(function (label) { return label.textContent === "0"; }).length, 1);
  var target = installs.drawing.querySelectorAll("[data-install-side=top]").filter(function (node) {
    return node.getAttribute("data-install-element") === "wel_a"; })[0];
  assert.strictEqual(target.getAttribute("role"), "button");
  // An edge too short to hold its value keeps its target and tooltip and drops the label.
  var record = JSON.parse(JSON.stringify(o.editor.rawRecord())); record.values.columns_m = [0.05, 0.05, 3];
  installs.cancelSession(true); installs.open(record);
  assert.strictEqual(installs.drawing.querySelectorAll(".window-install-edge-label").filter(function (label) {
    return label.getAttribute("text-anchor") === "middle" && label.textContent !== "0"; }).length, 0);
});

test("the Place anchor is one setting beside Place; its row shows only while the tool is placing", function () {
  var o = setup(), placement = o.editor.placement, tool = "ph_composer.windows.place_tool";
  o.state.sections[tool] = JSON.parse(JSON.stringify(o.state.sections["ph_composer.windows.settings"]));
  o.state.sections[tool].value = { active: false }; o.editor.render(o.state);
  assert.strictEqual(placement.root.hidden, true, "nothing is placing");
  assert.ok(o.editor.typeActions.contains(placement.anchorButton));
  assert.strictEqual(placement.anchorButton.getAttribute("aria-label"), "Placement anchor: Sill center");
  var choices = placement.anchorBubble.content.querySelectorAll("button");
  assert.strictEqual(choices.length, 9);
  assert.deepStrictEqual(choices.filter(function (node) { return node.getAttribute("aria-pressed") === "true"; })
    .map(function (node) { return node.textContent; }), ["Sill center"]);
  click(placement.anchors.head_right);
  assert.strictEqual(placement.anchorButton.getAttribute("aria-label"), "Placement anchor: Head right");
  assert.strictEqual(o.sent.length, 0, "an idle tool is not started by choosing its anchor");
  o.state.sections[tool].value = { active: true, type_id: o.editor.active, anchor: "head_right" };
  o.editor.render(o.state); assert.strictEqual(placement.root.hidden, false);
  assert.deepStrictEqual(placement.hint.querySelectorAll("code").map(function (node) { return node.textContent; }),
    ["sill=", "offset="], "the measurements the tool takes are a callout while it runs");
  click(placement.anchors.center);
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.params.anchor, "center", "a placing tool is re-armed with the new anchor");
});
test("an Empty element says so in the Builder and in the Installs drawing", function () {
  var o = setup(), marks = o.editor.canvas.root.querySelectorAll(".window-empty-mark");
  assert.deepStrictEqual(marks.map(function (node) { return node.textContent; }), ["Empty"]);
  o.editor.installEditor.open(o.editor.rawRecord());
  assert.strictEqual(o.editor.installEditor.drawing.querySelectorAll(".window-empty-mark").length, 1);
});

test("an incomplete Window Type carries the amber mark in the rail; no Types names the next step", function () {
  var o = setup(), record = o.state.sections["ph_composer.windows.types"].value.records[0];
  assert.strictEqual(o.editor.list.querySelectorAll(".window-type-flag").length, 0);
  assert.strictEqual(o.editor.emptyPrompt.hidden, true);
  // The record's own findings, which also carry what its elements are missing.
  record.findings = [{ code: "window_type.glazing_missing", element_id: "wel_a", message: "Missing g-value." },
    { code: "window_type.glazing_missing", element_id: "wel_b", message: "Missing g-value." },
    { code: "window_type.dimensions_incomplete", message: "Enter all grid dimensions." }];
  o.editor.render(o.state);
  var flag = o.editor.list.querySelector(".window-type-flag");
  assert.strictEqual(flag.getAttribute("aria-label"), "Three elements is incomplete");
  assert.strictEqual(flag.getAttribute("data-tooltip"), "Missing g-value. Enter all grid dimensions.",
    "each thing once");
  o.state.sections["ph_composer.windows.types"].value.records = [];
  o.editor.render(o.state);
  assert.strictEqual(o.editor.emptyPrompt.hidden, false);
  assert.strictEqual(o.editor.main.hidden, true);
});
test("Installs without the host's edge facts paints nothing and offers no copy, and sends nothing", function () {
  var o = setup(), installs = o.editor.installEditor, raw = o.editor.rawRecord();
  var target = JSON.parse(JSON.stringify(raw)); target.id = "wnt_b"; target.values.name = "Compatible target";
  o.state.sections["ph_composer.windows.types"].value.records.push(target);
  delete raw.display.install_topology; o.editor.render(o.state);
  installs.open(raw); installs.selected = "psi_a";
  assert.strictEqual(installs.paintEdge("wel_a", "top"), false);
  assert.ok(installs.drawing.querySelector("[aria-label='Element 1 top: Edge not read · cannot paint']"));
  click(installs.copyButton);
  assert.ok(text(installs.copyForm).includes("No compatible Window Types."));
  assert.strictEqual(installs.copyTo(target), false);
  assert.strictEqual(o.sent.length, 0);
});
test("Installs offers only Types whose published copy key matches, and keeps its facts through staging", function () {
  var o = setup(), installs = o.editor.installEditor, raw = o.editor.rawRecord();
  var same = JSON.parse(JSON.stringify(raw)); same.id = "wnt_b"; same.values.name = "Same key";
  var other = JSON.parse(JSON.stringify(raw)); other.id = "wnt_c"; other.values.name = "Other key";
  other.display.install_topology.copy_key = "different";
  o.state.sections["ph_composer.windows.types"].value.records.push(same, other); o.editor.render(o.state);
  installs.open(raw); installs.selected = "psi_a";
  installs.stageImport({ provider_id: "p", kind: "psi_install_types", generation: 1, library_id: "l",
    record_id: "r" }, { name: "Staged", psi_w_mk: 0.02 });
  assert.strictEqual(installs.paintEdge("wel_a", "top"), true, "staging changes no edge fact");
  click(installs.copyButton);
  var offered = installs.copyForm.querySelectorAll("button").map(function (button) { return button.textContent; });
  assert.deepStrictEqual(offered, ["Copy to Same key"]);
});
test("Installs refuses a copy whose slots are missing, empty or ambiguous, staging nothing", function () {
  [function (facts) { facts.copy_slots = {}; },
    function (facts) { delete facts.copy_slots.wel_a_other; },
    function (facts) { facts.copy_slots.wel_b_other = facts.copy_slots.wel_a_other; }].forEach(function (spoil, index) {
    var o = setup(), installs = o.editor.installEditor, raw = o.editor.rawRecord();
    var target = JSON.parse(JSON.stringify(raw)); target.id = "wnt_b"; target.values.name = "Other";
    target.values.elements.forEach(function (cell) { cell.id += "_other"; }); fixtures.withTopology(target);
    spoil(target.display.install_topology);
    o.state.sections["ph_composer.windows.types"].value.records.push(target); o.editor.render(o.state);
    installs.open(raw); installs.selected = "psi_a"; installs.paintEdge("wel_a", "top");
    assert.strictEqual(installs.copyTo(target), false, "case " + index);
    assert.strictEqual(installs.drafts.wnt_b, undefined, "case " + index);
    assert.ok(/not read/.test(installs.notice.textContent), "case " + index);
  });
});
test("Installs refuses a second copy to a Type changed in the Model and keeps the first", function () {
  var o = setup(), installs = o.editor.installEditor, raw = o.editor.rawRecord();
  var target = JSON.parse(JSON.stringify(raw)); target.id = "wnt_b"; target.values.name = "Other";
  target.values.elements.forEach(function (cell) { cell.id += "_other"; }); fixtures.withTopology(target);
  o.state.sections["ph_composer.windows.types"].value.records.push(target); o.editor.render(o.state);
  installs.open(raw); installs.selected = "psi_a"; installs.paintEdge("wel_a", "top");
  assert.strictEqual(installs.copyTo(target), true);
  var staged = JSON.stringify(installs.drafts.wnt_b);
  target.values.elements.forEach(function (cell) { cell.id += "_renamed"; }); fixtures.withTopology(target);
  o.editor.render(o.state);
  assert.strictEqual(installs.copyTo(target), false);
  assert.ok(/changed in the Model/.test(installs.notice.textContent));
  assert.strictEqual(JSON.stringify(installs.drafts.wnt_b), staged, "the first staged copy is untouched");
});
test("Installs with malformed facts paints nothing and a missing copy key offers no copy", function () {
  var o = setup(), installs = o.editor.installEditor, raw = o.editor.rawRecord();
  var target = JSON.parse(JSON.stringify(raw)); target.id = "wnt_b"; target.values.name = "Other";
  target.values.columns_m = [0.6, 0.5, 0.5];
  delete raw.display.install_topology.edges; delete raw.display.install_topology.copy_key;
  delete target.display.install_topology.copy_key;
  o.state.sections["ph_composer.windows.types"].value.records.push(target); o.editor.render(o.state);
  assert.doesNotThrow(function () { installs.open(raw); });
  installs.selected = "psi_a";
  assert.strictEqual(installs.paintEdge("wel_a", "top"), false);
  assert.strictEqual(installs.copyTo(target), false);
  click(installs.copyButton); assert.ok(text(installs.copyForm).includes("No compatible Window Types."));
  installs.saveAction();
  assert.strictEqual(o.sent[0].payload.params.types.length, 1, "only the open Type is saved");
});
