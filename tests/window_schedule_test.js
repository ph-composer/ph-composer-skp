"use strict";
var assert = require("assert"), test = require("node:test"), dom = require("./support/dom_stub"),
  source = require("./support/panel_source"), fixtures = require("./support/window_fixtures");
function setup() {
  var document = dom.buildDocument(""), context = { document: document, Intl: Intl, innerWidth: 1280,
    setTimeout: setTimeout, clearTimeout: clearTimeout }; context.window = context; dom.attachEvents(context);
  var modules = source.start(context, ["features/windows/editor"]), state = fixtures.state(), sent = [];
  var host = { zone_id: "zon_a", zone_path: [10], entity_path: [20], entity_id: null };
  state.sections["ph_composer.windows.place_tool"] = { status: "completed", value: {
    active: false, type_id: null, anchor: "sill_center", host: null } };
  state.sections["ph_composer.windows.units"] = { status: "completed", value: { units: [
    { id: "wun_a", reference: { unit_id: "wun_a", entity_path: [10, 30] },
      values: { window_type_id: "wnt_a", anchor: "sill_center" }, host: host,
      findings: [{ code: "window.definition_detached", repair: { name: "ph_composer.windows.units.reset_to_type",
        params: { units: [{ unit_id: "wun_a", entity_path: [10, 30] }] } } }] },
    { id: "wun_a", reference: { unit_id: "wun_a", entity_path: [10, 31] },
      values: { window_type_id: "wnt_a", anchor: "head_left" }, host: null,
      findings: [{ code: "window.copy_id_pending", repair: { name: "ph_composer.windows.units.repair_copied_identities",
        params: { units: [{ unit_id: "wun_a", entity_path: [10, 31] }] } } },
        { code: "window.unhosted", repair: { name: "ph_composer.windows.units.rehost",
        params: { unit: { unit_id: "wun_a", entity_path: [10, 31] } } } }] }
  ] } };
  state.sections["ph_composer.zones.overview"] = { status: "completed", value: { zones: [
    { reference: { zone_id: "zon_a", zone_path: [10] }, values: { name: "Room A", level: "Ground" } }
  ] } };
  state.sections["ph_composer.zones.faces.faces"] = { status: "completed", value: { faces: [
    { reference: host, values: { face_type: "Wall", boundary_condition: "Outdoors" } }
  ] } };
  var editor = new modules["features/windows/editor"].View(document.body, state.session, function (type, payload) {
    sent.push({ type: type, payload: payload }); }); editor.render(state);
  return { editor: editor, state: state, sent: sent, document: document };
}
function click(node) { node.listeners.click({ preventDefault: function () {}, stopPropagation: function () {} }); }
function text(node) { return node.textContent + node.children.map(text).join(" "); }
function viewOutcome(o, status) {
  var call = o.sent[o.sent.length - 1].payload;
  o.state.ui.viewResults = {}; o.state.ui.viewResults[call.request_id] = { session: o.state.session,
    request_id: call.request_id, outcome: { status: status, message: "Placement refused." } };
  o.editor.render(o.state);
}
test("Place uses the view channel; active tool keeps Stop and measurement guidance", function () {
  var o = setup(); click(o.editor.placeButton);
  assert.strictEqual(o.sent[0].type, "view.invoke");
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.place_tool.choose");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params)),
    { type_id: "wnt_a", anchor: "sill_center" });
  click(o.editor.placeButton); assert.strictEqual(o.sent.length, 1);
  viewOutcome(o, "completed");
  o.state.sections["ph_composer.windows.place_tool"].value = {
    active: true, type_id: "wnt_a", anchor: "head_right", host: null }; o.editor.render(o.state);
  assert.strictEqual(o.editor.placement.anchorButton.getAttribute("aria-label"), "Placement anchor: Head right");
  assert.strictEqual(o.editor.placement.root.hidden, false);
  assert.ok(text(o.editor.placement.root).includes("sill="));
  click(o.editor.placement.anchors.center);
  assert.strictEqual(o.sent[1].payload.params.anchor, "center"); viewOutcome(o, "completed");
  click(o.editor.placement.stop); assert.strictEqual(o.sent[2].payload.name, "ph_composer.windows.place_tool.stop");
  assert.strictEqual(o.sent.filter(function (call) { return call.type === "action.invoke"; }).length, 0);
});
test("Schedule counts occurrences independently of copied ids and shows host context and native state", function () {
  var o = setup(); assert.strictEqual(o.editor.tabs.select("schedule"), true);
  var rows = o.editor.schedule.mount._table.rows;
  assert.strictEqual(rows["type:wnt_a"].cells.count.textContent, "2");
  assert.ok(text(o.editor.schedule.root).includes("Room A"));
  assert.ok(text(o.editor.schedule.root).includes("Ground"));
  assert.ok(text(o.editor.schedule.root).includes("Wall 1"));
  assert.ok(text(o.editor.schedule.root).includes("Detached definition"));
  assert.ok(text(o.editor.schedule.root).includes("Copy, id pending"));
  var locate = o.editor.schedule.root.querySelector("[data-row-action='locate']"); click(locate);
  assert.strictEqual(o.sent[0].type, "view.invoke");
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.units.locate");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.units[0].entity_path)), [10, 30]);
});
function unitRow(o, key) { return o.editor.schedule.mount._table.rows[key]; }
function nameInput(o, key) { return unitRow(o, key).cells.name.children[0]; }
function selectUnits(o, paths) {
  o.state.sections["ph_composer.windows.units.selected"] = { status: "completed", value: { units: paths.map(
    function (path) { return { unit_id: "wun_a", entity_path: path }; }) } };
  o.editor.render(o.state);
}
function typeName(o, key, value) {
  var input = nameInput(o, key); input.value = value;
  input.listeners.input({}); input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
}
test("an unnamed Window shows its Type and number as a hint, and its name when it has one (W-099)", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  o.state.sections["ph_composer.windows.units"].value.units[0].name = "W-101";
  o.state.sections["ph_composer.windows.units"].value.units[1].name = ""; o.editor.render(o.state);
  assert.strictEqual(nameInput(o, "[10,30]").value, "W-101");
  assert.strictEqual(nameInput(o, "[10,31]").value, "");
  var type = o.state.sections["ph_composer.windows.types"].value.records[0].values.name;
  assert.strictEqual(nameInput(o, "[10,31]").placeholder, type + " 2");
  assert.strictEqual(unitRow(o, "type:wnt_a").cells.name.textContent, type, "a Type row stays text");
});
test("a name typed in the Schedule writes the instance name, guarded by the name last read (W-099)", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  o.state.sections["ph_composer.windows.units"].value.units[0].name = "Old"; o.editor.render(o.state);
  typeName(o, "[10,30]", " W-101 ");
  var call = o.sent[o.sent.length - 1];
  assert.strictEqual(call.type, "action.invoke");
  assert.strictEqual(call.payload.name, "ph_composer.windows.units.rename");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(call.payload.params)), {
    unit: { unit_id: "wun_a", entity_path: [10, 30] }, name: "W-101", expected_name: "Old" });
  assert.strictEqual(o.editor.schedule.guard(), "Wait for the Window command.", "the row actions wait for it");
});
test("a name changed in Entity Info reaches an idle cell (W-099)", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  o.state.sections["ph_composer.windows.units"].value.units[0].name = "Before"; o.editor.render(o.state);
  o.state.sections["ph_composer.windows.units"].value.units[0].name = "From Entity Info"; o.editor.render(o.state);
  assert.strictEqual(nameInput(o, "[10,30]").value, "From Entity Info");
});
test("a Window selected in SketchUp has its row marked and scrolled to, once, under an open Type (W-100)", function () {
  var o = setup(), scrolled = []; o.editor.tabs.select("schedule");
  ["[10,30]", "[10,31]"].forEach(function (key) {
    unitRow(o, key).node.scrollIntoView = function () { scrolled.push(key); };
  });
  assert.strictEqual(unitRow(o, "[10,31]").node.classList.contains("host-selected"), false);
  selectUnits(o, [[10, 31]]);
  assert.strictEqual(unitRow(o, "[10,31]").node.classList.contains("host-selected"), true);
  assert.strictEqual(unitRow(o, "[10,30]").node.classList.contains("host-selected"), false);
  assert.deepStrictEqual(scrolled, ["[10,31]"]);
  o.editor.render(o.state);
  assert.strictEqual(scrolled.length, 1, "a repaint of the same selection leaves the scroll alone");
  o.editor.schedule.expanded["type:wnt_a"] = false; o.editor.schedule.paint();
  selectUnits(o, []);
  assert.strictEqual(o.editor.schedule.expanded["type:wnt_a"], false, "clearing the selection opens nothing");
  selectUnits(o, [[10, 30]]);
  assert.strictEqual(o.editor.schedule.expanded["type:wnt_a"], true, "a selected Window's Type opens");
  assert.deepStrictEqual(scrolled, ["[10,31]", "[10,30]"]);
  assert.strictEqual(unitRow(o, "[10,30]").node.classList.contains("host-selected"), true);
});
test("with no Window Types the Schedule and the Builder both offer to make the first", function () {
  var o = setup(), types = o.state.sections["ph_composer.windows.types"].value;
  types.records = []; o.state.sections["ph_composer.windows.units"].value.units = []; o.editor.render(o.state);
  var button = o.editor.schedule.mount.querySelector(".phc-empty-action");
  assert.strictEqual(button.hidden, false);
  assert.strictEqual(button.textContent, "+ New Window Type");
  click(button);
  assert.strictEqual(o.sent[o.sent.length - 1].payload.name, "ph_composer.windows.types.create");
  assert.strictEqual(o.editor.firstType.textContent, "+ New Window Type");
  assert.strictEqual(o.editor.firstType.disabled, true, "held while that create is pending");
});

test("Schedule lists Window Types by name, numbers read as numbers, and an unknown Type last", function () {
  var o = setup(), section = o.state.sections["ph_composer.windows.types"].value, first = section.records[0];
  function named(id, name) {
    var type = JSON.parse(JSON.stringify(first)); type.id = id; type.values.name = name; return type;
  }
  section.records = [named("wnt_c", "Type-10"), named("wnt_b", "Door"), named("wnt_a", "Type-2")];
  o.state.sections["ph_composer.windows.units"].value.units[1].values.window_type_id = "wnt_gone";
  o.editor.render(o.state); o.editor.tabs.select("schedule");
  assert.strictEqual(o.editor.schedule.rows().filter(function (row) { return row.tier === "Type"; })
    .map(function (row) { return row.record.name; }).join(), "Door,Type-2,Type-10,Unknown Type");
});
test("Schedule repairs freeze occurrence targets and confirm consequences before the one mutation", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  click(o.editor.schedule.root.querySelector("[data-row-action='reset_to_type']"));
  assert.strictEqual(o.sent.length, 0); assert.ok(o.editor.guard());
  assert.strictEqual(o.editor.tabs.select("builder"), false);
  var form = o.editor.schedule.dialog; assert.ok(text(form).includes("primary definition"));
  assert.strictEqual(o.editor.schedule.cancel.getAttribute("aria-label"), "Cancel");
  click(form.querySelector("[data-schedule-apply]"));
  assert.strictEqual(o.sent.length, 1); assert.strictEqual(o.sent[0].payload.name,
    "ph_composer.windows.units.reset_to_type");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.units)), [
    { unit_id: "wun_a", entity_path: [10, 30] } ]);
});
test("the row menu offers the repairs the findings name and sends their params", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  var copied = o.editor.schedule.mount._table.rows[JSON.stringify([10, 31])];
  assert.strictEqual(copied.node.querySelector("[data-row-action='reset_to_type']"), null);
  click(copied.node.querySelector("[data-row-action='repair_copied_identities']"));
  click(o.editor.schedule.apply);
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.units.repair_copied_identities");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params)), {
    units: [{ unit_id: "wun_a", entity_path: [10, 31] }] });
});
test("drafts guard Schedule and Place; withdrawn/disposed controls cannot send", function () {
  var o = setup(); o.editor.dimension("columns_m", 0, o.editor.title);
  o.editor.dimensionField.input.value = "600 mm"; o.editor.dimensionField.input.listeners.input({});
  assert.strictEqual(o.editor.tabs.select("schedule"), false); click(o.editor.placeButton);
  assert.strictEqual(o.sent.length, 0); o.editor.dimensionField.cancel(); o.editor.tabs.select("schedule");
  click(o.editor.schedule.root.querySelector("[data-row-action='reset_to_type']"));
  var held = o.editor.schedule.dialog.querySelector("[data-schedule-apply]");
  delete o.state.sections["ph_composer.windows.units"]; o.editor.render(o.state); click(held);
  assert.strictEqual(o.sent.length, 0); assert.strictEqual(o.editor.guard(), null);
  o.editor.dispose(); click(o.editor.placeButton); assert.strictEqual(o.sent.length, 0);
});
test("finite geometry permits Place without complete products; each route chooses an explicit Type", function () {
  var o = setup(), record = o.editor.rawRecord(); record.display.thermal.complete = false;
  record.values.elements[0].glazing_id = null; o.editor.render(o.state);
  assert.strictEqual(o.editor.placeButton.disabled, false);
  assert.strictEqual(Object.keys(o.editor.placement.anchors).length, 9);
  assert.strictEqual(o.editor.placement.root.hidden, true);
  click(o.editor.list.querySelector("[aria-label='Place Three elements']"));
  assert.strictEqual(o.sent[0].payload.params.type_id, "wnt_a"); viewOutcome(o, "completed");
  o.editor.tabs.select("schedule"); click(o.editor.schedule.root.querySelector("[data-row-action='place']"));
  assert.strictEqual(o.sent[1].payload.params.type_id, "wnt_a"); viewOutcome(o, "completed");
  record.values.columns_m[0] = null; o.editor.render(o.state);
  assert.strictEqual(o.editor.placeButton.disabled, true);
  assert.strictEqual(o.editor.list.querySelector("[aria-label='Place Three elements']").disabled, true);
  o.editor.placement.choose("wnt_a"); assert.strictEqual(o.sent.length, 2);
});
test("view refusal settles only its channel and permits retry; Escape stops the active tool", function () {
  var o = setup(); click(o.editor.placeButton); viewOutcome(o, "refused");
  assert.strictEqual(o.editor.guard(), null); click(o.editor.placeButton); assert.strictEqual(o.sent.length, 2);
  viewOutcome(o, "completed"); o.state.sections["ph_composer.windows.place_tool"].value.active = true;
  o.state.sections["ph_composer.windows.place_tool"].value.type_id = "wnt_a"; o.editor.render(o.state);
  o.editor.onKeydown({ key: "Escape", target: o.editor.root, preventDefault: function () {} });
  assert.strictEqual(o.sent[2].payload.name, "ph_composer.windows.place_tool.stop");
});
test("Swap and Re-host pick explicit targets; a refused mutation retains Apply and Cancel", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  click(o.editor.schedule.root.querySelector("[data-row-action='swap_type']"));
  var dialog = o.editor.schedule.dialog, select = dialog.querySelector("select");
  click(dialog.querySelector("[data-schedule-apply]")); assert.strictEqual(o.sent.length, 0);
  select.value = "wnt_a"; click(dialog.querySelector("[data-schedule-apply]"));
  assert.strictEqual(o.sent[0].payload.params.type_id, "wnt_a");
  o.state.ui.actionResult = { session: o.state.session, request_id: o.sent[0].payload.request_id,
    outcome: { status: "refused", message: "Overlapping Window." } }; o.editor.render(o.state);
  assert.strictEqual(dialog.open, true); assert.strictEqual(o.editor.schedule.apply.disabled, false);
  assert.ok(text(dialog).includes("Overlapping Window.")); click(o.editor.schedule.cancel);
  click(o.editor.schedule.root.querySelector("[data-row-action='rehost']"));
  dialog = o.editor.schedule.dialog; select = dialog.querySelector("select"); select.value = select.children[1].value;
  click(dialog.querySelector("[data-schedule-apply]"));
  assert.strictEqual(o.sent[1].payload.name, "ph_composer.windows.units.rehost");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[1].payload.params.unit.entity_path)), [10, 31]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[1].payload.params.host.zone_path)), [10]);
});
test("a changed unit blocks held repair Apply until Cancel; missing Types cancel repairs", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  click(o.editor.schedule.root.querySelector("[data-row-action='reset_to_type']"));
  var held = o.editor.schedule.apply;
  o.state.sections["ph_composer.windows.units"].value.units[0].values.anchor = "head_left"; o.editor.render(o.state);
  assert.strictEqual(held.disabled, true); click(held); assert.strictEqual(o.sent.length, 0);
  assert.ok(text(o.editor.schedule.dialog).includes("changed")); click(o.editor.schedule.cancel);
  click(o.editor.schedule.root.querySelector("[data-row-action='remove']")); held = o.editor.schedule.apply;
  delete o.state.sections["ph_composer.windows.types"]; o.editor.render(o.state); click(held);
  assert.strictEqual(o.sent.length, 0); assert.strictEqual(o.editor.guard(), null);
});
test("unknown Type occurrences remain counted; mirrored repair uses its singular public parameter", function () {
  var o = setup(), rows = o.state.sections["ph_composer.windows.units"].value.units;
  rows[0].values.window_type_id = "wnt_missing"; rows[0].findings = [{ code: "window.unknown_type", repair: {
    name: "ph_composer.windows.units.swap_type", params: { units: [rows[0].reference] } } }];
  rows[1].findings = [{ code: "window.mirrored", repair: { name: "ph_composer.windows.units.new_flipped_type",
        params: { unit: rows[1].reference } } }]; o.editor.render(o.state);
  o.editor.tabs.select("schedule");
  assert.strictEqual(o.editor.schedule.mount._table.rows["type:wnt_missing"].cells.count.textContent, "1");
  click(o.editor.schedule.root.querySelector("[data-row-action='new_flipped_type']"));
  click(o.editor.schedule.apply); assert.strictEqual(o.sent[0].payload.name,
    "ph_composer.windows.units.new_flipped_type");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.unit.entity_path)), [10, 31]);
  assert.strictEqual(o.sent[0].payload.params.units, undefined);
});
test("a changed replacement Type or native revision invalidates the opened repair and keeps Cancel", function () {
  [true, false].forEach(function (typeChanged) {
    var o = setup(); o.editor.tabs.select("schedule");
    click(o.editor.schedule.root.querySelector("[data-row-action='swap_type']"));
    var dialog = o.editor.schedule.dialog, held = o.editor.schedule.apply;
    dialog.querySelector("select").value = "wnt_a";
    if (typeChanged) o.editor.rawRecord().values.columns_m[0] = 4;
    o.state.revision += 1; o.editor.render(o.state);
    assert.strictEqual(held.disabled, true); assert.strictEqual(o.editor.schedule.cancel.disabled, false);
    click(held); assert.strictEqual(o.sent.length, 0);
    assert.ok(text(dialog).includes("Model changed"));
    click(o.editor.schedule.cancel); assert.strictEqual(o.editor.guard(), null);
  });
});
test("a stale refusal cannot retry from the held review; reopening captures the new revision", function () {
  var o = setup(); o.editor.tabs.select("schedule");
  click(o.editor.schedule.root.querySelector("[data-row-action='reset_to_type']"));
  click(o.editor.schedule.apply); assert.strictEqual(o.sent.length, 1);
  o.state.revision += 1;
  o.state.ui.actionResult = { session: o.state.session, request_id: o.sent[0].payload.request_id,
    outcome: { status: "refused", message: "Native geometry changed." } };
  o.editor.render(o.state); var held = o.editor.schedule.apply;
  assert.strictEqual(held.disabled, true); click(held); assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.editor.schedule.cancel.disabled, false);
  assert.ok(text(o.editor.schedule.dialog).includes("Cancel and reopen")); click(o.editor.schedule.cancel);
  click(o.editor.schedule.root.querySelector("[data-row-action='reset_to_type']"));
  click(o.editor.schedule.apply); assert.strictEqual(o.sent.length, 2);
});
test("Schedule shows distinct occurrence words, friendly Face labels and identity only in tooltips", function () {
  var o = setup(); o.state.sections["ph_composer.zones.faces.faces"].value.faces[0].values.face_type = "RoofCeiling";
  o.editor.render(o.state); o.editor.tabs.select("schedule");
  var rows = o.editor.schedule.mount._table.rows, first = rows["[10,30]"], second = rows["[10,31]"];
  var type = o.state.sections["ph_composer.windows.types"].value.records[0].values.name;
  assert.strictEqual(first.cells.name.children[0].placeholder, type + " 1");
  assert.strictEqual(second.cells.name.children[0].placeholder, type + " 2");
  assert.strictEqual(first.cells.host.textContent, "Roof or ceiling 1");
  assert.ok(first.cells.name.getAttribute("data-tooltip").includes("wun_a"));
  assert.ok(first.cells.name.getAttribute("data-tooltip").includes("10 / 30"));
  assert.ok(second.cells.name.getAttribute("data-tooltip").includes("10 / 31"));
  assert.ok(!text(o.editor.schedule.root).includes("wun_a"));
  assert.ok(!text(o.editor.schedule.root).includes("RoofCeiling"));
  o.state.sections["ph_composer.windows.units"].value.units[0].values.window_type_id = "wnt_missing";
  o.editor.render(o.state);
  var missing = o.editor.schedule.mount._table.rows["type:wnt_missing"];
  assert.strictEqual(missing.cells.name.textContent, "Unknown Type");
  assert.ok(missing.cells.name.getAttribute("data-tooltip").includes("wnt_missing"));
  assert.ok(!text(o.editor.schedule.root).includes("wnt_missing"));
  click(first.controls.locate.node);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.units[0])),
    { unit_id: "wun_a", entity_path: [10, 30] });
});

test("Schedule shows net opaque area of the host occurrence and withholds uncertain area", function () {
  var o = setup(), host = o.state.sections["ph_composer.windows.units"].value.units[0].host;
  o.state.sections["ph_composer.windows.unit_areas"] = { status: "completed", value: {
    faces: [{ reference: { entity_id: host.entity_id, entity_path: host.entity_path,
      zone_path: host.zone_path, zone_id: host.zone_id }, net_opaque_area_m2: 10.01 }] } };
  o.editor.render(o.state); o.editor.tabs.select("schedule");
  var rows = o.editor.schedule.mount._table.rows;
  assert.strictEqual(rows["[10,30]"].cells.net_area.textContent, "10.01");
  assert.strictEqual(rows["[10,31]"].cells.net_area.textContent, "—");
  o.state.sections["ph_composer.windows.unit_areas"].value.faces[0].net_opaque_area_m2 = null;
  o.editor.render(o.state);
  assert.strictEqual(o.editor.schedule.mount._table.rows["[10,30]"].cells.net_area.textContent, "—");
});
