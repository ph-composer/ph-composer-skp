"use strict";
/* The Thermal Bridges tab: the Types inventory, the assign bar and the Schedule, each sending only the
   registered thermal-bridge operations. The panel computes nothing. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/thermal_bridge_fixtures");
var PREFIX = fixtures.PREFIX;

function setup(edges) {
  var document = dom.buildDocument("");
  var sections = {}, sent = [], notices = [], state = fixtures.state(edges), root = dom.element("div");
  document.body.appendChild(root);
  function send(type, payload) { sent.push({ type: type, payload: payload }); }
  function paint() { Object.keys(sections).forEach(function (key) { sections[key](root, state, send); }); }
  var panel = { section: function (name, render) { sections[name] = render; }, repaint: paint,
    navigationGuard: function () {}, workedOn: function () {},
    notify: function (message) { notices.push(message); } };
  var context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context;
  dom.attachEvents(context);
  panelSource.start(context, ["features/thermal_bridges/section"], { panel: panel });
  paint();
  return { root: root, view: root._view, state: state, sent: sent, notices: notices, paint: paint };
}
function named(o, name) { return o.sent.filter(function (message) { return message.payload.name === name; }); }
function answer(o, message, outcome) {
  o.state.ui.queryResults[message.payload.request_id] = { request_id: message.payload.request_id,
    session: "session", outcome: outcome };
  o.paint();
}
function readSchedule(o) {
  var reads = named(o, PREFIX + "schedule.all");
  answer(o, reads[reads.length - 1], { status: "completed", revision: o.state.revision,
    value: fixtures.schedule() });
}
function cell(o, key) { return o.view.types.inventory.edits.cells[key]; }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopImmediatePropagation: function () {} });
}

test("opening the tab reads the schedule once; used length shows it, and a dash once the Model changes", function () {
  var o = setup(), reads = named(o, PREFIX + "schedule.all");
  assert.strictEqual(reads.length, 1);
  assert.strictEqual(reads[0].type, "query.invoke");
  o.paint();
  assert.strictEqual(named(o, PREFIX + "schedule.all").length, 1, "a panel refresh never reads again");
  readSchedule(o);
  var length = o.root.querySelector(".col-length_m");
  var rows = o.root.querySelectorAll(".col-length_m").map(function (td) { return td.textContent; });
  assert.ok(rows.indexOf("18") >= 0 && rows.indexOf("0") >= 0, rows.join());
  assert.ok(length, "the Used length column is drawn");
  var parapet = function () { return o.root.querySelector("[data-row-key=tbt_a]").querySelector(".col-length_m"); };
  assert.strictEqual(parapet().classList.contains("tb-muted"), false);
  o.state.revision = 2; o.paint();
  assert.strictEqual(named(o, PREFIX + "schedule.all").length, 1, "a changed Model is marked, not read again");
  assert.strictEqual(parapet().textContent, "—", "a length read before the change is not shown as current");
  assert.strictEqual(parapet().classList.contains("tb-muted"), true);
  o.view.tabs.select("schedule");
  assert.strictEqual(named(o, PREFIX + "schedule.all").length, 2, "opening Schedule on a changed Model reads it");
  readSchedule(o);
  o.state.revision = 3; o.paint();
  o.view.tabs.select("types");
  assert.strictEqual(named(o, PREFIX + "schedule.all").length, 3, "choosing Types on a changed Model reads it");
});

test("a Types cell edit sends types.update with its expected value and keeps a refused draft", function () {
  var o = setup(), psi = cell(o, "tbt_a:psi_w_mk");
  psi.input.value = "0.15"; psi.input.listeners.input({}); key(psi.input, "Enter");
  var update = named(o, PREFIX + "types.update")[0];
  assert.deepStrictEqual(JSON.parse(JSON.stringify(update.payload.params)),
    { id: "tbt_a", values: { psi_w_mk: 0.15 }, expected_values: { psi_w_mk: 0.12 } });
  o.state.ui.actionResult = { request_id: update.payload.request_id, session: "session",
    outcome: { status: "refused", code: "target.changed", message: "The type changed. Nothing was written." } };
  o.paint();
  assert.strictEqual(psi.input.value, "0.15");
  assert.strictEqual(psi.status, "error");
  assert.ok(o.view.guard(), "a refused draft holds the tab");
});

test("the group chip shows METr's word and sends honeybee-ph's string", function () {
  var o = setup(), group = cell(o, "tbt_b:group");
  assert.strictEqual(group.input.value, "17-FS/BC");
  assert.deepStrictEqual(group.input.children.map(function (option) { return option.textContent; }),
    ["Ambient", "Perimeter", "Basement floor"]);
  group.input.value = "16-Perimeter"; group.input.listeners.change({});
  var update = named(o, PREFIX + "types.update")[0];
  assert.strictEqual(update.payload.params.values.group, "16-Perimeter");
  assert.strictEqual(update.payload.params.expected_values.group, "17-FS/BC");
});

test("the assign bar disables Assign with its reason when nothing selected can be assigned", function () {
  var none = setup();
  assert.strictEqual(none.view.types.bar.assign.disabled, true);
  assert.strictEqual(none.view.types.bar.count.textContent, "No Edges selected");
  assert.ok(none.root.querySelector(".phc-blocked-reason-text").textContent.includes("Select Edges inside a Zone"));
  var outside = setup([fixtures.outside(5)]), bar = outside.view.types.bar;
  assert.strictEqual(bar.assign.disabled, true);
  assert.strictEqual(bar.count.textContent, "1 Edge selected, 0 assignable");
  assert.ok(outside.root.querySelector(".phc-blocked-reason-text").textContent.includes("not inside a Zone"));
  bar.submit("assign");
  assert.strictEqual(named(outside, PREFIX + "edges.assign").length, 0);
});

test("Assign sends the assignable Edges with their values; Clear only those holding one", function () {
  var o = setup([fixtures.edge(101), fixtures.edge(102, { thermal_bridge_type_id: "tbt_b", quantity: 2 })]);
  var bar = o.view.types.bar;
  assert.strictEqual(bar.type.value, "", "Edges holding different types choose none");
  assert.strictEqual(bar.assign.disabled, true);
  bar.type.value = "tbt_a"; bar.type.listeners.change({});
  bar.quantity.value = "2"; bar.quantity.listeners.input({});
  bar.assign.listeners.click({});
  var assign = named(o, PREFIX + "edges.assign")[0].payload.params;
  assert.strictEqual(assign.thermal_bridge_type_id, "tbt_a");
  assert.strictEqual(assign.quantity, 2);
  assert.deepStrictEqual(assign.targets.map(function (target) { return target.reference.entity_path[0]; }),
    [101, 102]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(assign.targets[1].expected_values)),
    { thermal_bridge_type_id: "tbt_b", quantity: 2 });
  assert.strictEqual(bar.assign.disabled, true, "a pending Assign holds the bar");
  assert.strictEqual(o.notices.length, 0, "nothing is confirmed before the Model answers");
  o.state.ui.actionResult = { request_id: named(o, PREFIX + "edges.assign")[0].payload.request_id,
    session: "session", outcome: { status: "refused", code: "target.changed", message: "An Edge changed." } };
  o.paint();
  assert.strictEqual(bar.busy(), false, "a refused Assign settles the bar");
  assert.strictEqual(bar.type.value, "tbt_a", "the choice stands while the selection is the same");
  bar.clear.listeners.click({});
  var clear = named(o, PREFIX + "edges.clear")[0].payload.params;
  assert.deepStrictEqual(clear.targets.map(function (target) { return target.reference.entity_path[0]; }), [102]);
  o.state.ui.actionResult = { request_id: named(o, PREFIX + "edges.clear")[0].payload.request_id,
    session: "session", outcome: { status: "completed", value: { cleared: 1 } } };
  o.paint();
  assert.deepStrictEqual(o.notices, ["Cleared the thermal bridge from 1 Edge."], "a completed write is confirmed");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(clear.targets[0].expected_values)),
    { thermal_bridge_type_id: "tbt_b", quantity: 2 });
});

test("Assign by clicking arms the edge tool with the bar's type and quantity, with nothing selected", function () {
  var o = setup(), bar = o.view.types.bar, tool = bar.tool;
  assert.strictEqual(bar.type.disabled, false, "the type stays open for the tool with nothing selected");
  assert.strictEqual(tool.arm.disabled, true, "no type chosen yet");
  assert.strictEqual(tool.stop.hidden, true, "Stop shows only while the tool runs");
  bar.type.value = "tbt_a"; bar.type.listeners.change({});
  bar.quantity.value = "2"; bar.quantity.listeners.input({});
  assert.strictEqual(named(o, PREFIX + "edge_tool.choose").length, 0, "choosing a type alone arms nothing");
  tool.arm.listeners.click({});
  var choose = named(o, PREFIX + "edge_tool.choose");
  assert.strictEqual(choose.length, 1);
  assert.strictEqual(choose[0].type, "view.invoke");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(choose[0].payload.params)),
    { thermal_bridge_type_id: "tbt_a", quantity: 2 });
  assert.strictEqual(named(o, PREFIX + "edges.assign").length, 0, "arming writes nothing");
  o.state.ui.viewResults[choose[0].payload.request_id] = { request_id: choose[0].payload.request_id,
    session: "session", outcome: { status: "refused", code: "target.not_found", message: "There is no type." } };
  o.paint();
  assert.deepStrictEqual(o.notices, ["There is no type."], "a refused choice says why");
});

test("a type chosen with nothing selected survives selecting unassigned Edges", function () {
  var o = setup(), bar = o.view.types.bar;
  bar.type.value = "tbt_a"; bar.type.listeners.change({});
  o.state.sections[PREFIX + "edges.selected"].value.edges = [fixtures.edge(101)];
  o.paint();
  assert.strictEqual(bar.type.value, "tbt_a");
  o.state.sections[PREFIX + "edges.selected"].value.edges = [fixtures.edge(102, { thermal_bridge_type_id: "tbt_b",
    quantity: 2 })];
  o.paint();
  assert.strictEqual(bar.type.value, "tbt_b", "Edges sharing a type still start from it");
  assert.strictEqual(bar.quantity.value, "2");
});

test("Enter in Quantity re-arms a running tool and writes nothing to the selection", function () {
  var o = setup([fixtures.edge(101)]), bar = o.view.types.bar;
  o.state.sections[PREFIX + "edge_tool"].value = { active: true, thermal_bridge_type_id: "tbt_a", quantity: 1,
    gesture_limit: 250 };
  o.paint();
  bar.quantity.listeners.focus({});
  bar.quantity.value = "3"; bar.quantity.listeners.input({});
  key(bar.quantity, "Enter");
  assert.strictEqual(named(o, PREFIX + "edges.assign").length, 0);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(named(o, PREFIX + "edge_tool.choose")[0].payload.params)),
    { thermal_bridge_type_id: "tbt_a", quantity: 3 });
});

test("while the tool runs the bar shows what it assigns, re-arms on a change and Stop ends it", function () {
  var o = setup(), bar = o.view.types.bar, tool = bar.tool;
  o.state.sections[PREFIX + "edge_tool"].value = { active: true, thermal_bridge_type_id: "tbt_b", quantity: 3,
    gesture_limit: 250 };
  o.paint();
  assert.strictEqual(tool.arm.getAttribute("aria-pressed"), "true");
  assert.strictEqual(tool.stop.hidden, false);
  assert.strictEqual(bar.type.value, "tbt_b", "a tool armed in SketchUp shows its type");
  assert.strictEqual(bar.quantity.value, "3");
  bar.type.value = "tbt_a"; bar.type.listeners.change({});
  var choose = named(o, PREFIX + "edge_tool.choose");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(choose[0].payload.params)),
    { thermal_bridge_type_id: "tbt_a", quantity: 3 }, "a new type re-arms the running tool");
  o.paint();
  assert.strictEqual(bar.type.value, "tbt_a", "the change shows while it is on its way");
  o.state.ui.viewResults[choose[0].payload.request_id] = { request_id: choose[0].payload.request_id,
    session: "session", outcome: { status: "completed", value: {} } };
  o.state.sections[PREFIX + "edge_tool"].value.thermal_bridge_type_id = "tbt_a";
  o.paint();
  tool.arm.listeners.click({});
  assert.strictEqual(named(o, PREFIX + "edge_tool.stop").length, 1, "a second click on the pressed button stops");
  tool.stop.listeners.click({});
  assert.strictEqual(named(o, PREFIX + "edge_tool.stop").length, 1, "one stop in flight at a time");
  o.state.ui.viewResults[named(o, PREFIX + "edge_tool.stop")[0].payload.request_id] = {
    request_id: named(o, PREFIX + "edge_tool.stop")[0].payload.request_id, session: "session",
    outcome: { status: "completed", value: {} } };
  o.state.sections[PREFIX + "edge_tool"].value.active = false;
  o.paint();
  assert.strictEqual(tool.arm.getAttribute("aria-pressed"), "false");
  assert.strictEqual(tool.stop.hidden, true);
});

test("Clear takes an invalid assignment that reads with no values", function () {
  var broken = fixtures.edge(103);
  broken.reference.entity_id = "tbe_BADBADBADBAD";
  broken.record_problem = "thermal_bridge_type_id is required";
  var o = setup([broken]), bar = o.view.types.bar;
  assert.strictEqual(bar.clear.disabled, false);
  bar.clear.listeners.click({});
  var clear = named(o, PREFIX + "edges.clear")[0].payload.params;
  assert.deepStrictEqual(JSON.parse(JSON.stringify(clear.targets)), [{ reference: broken.reference,
    expected_values: {} }]);
});

test("the Group column filters by METr's words and sorts from its menu", function () {
  var o = setup(), inventory = o.view.types.inventory;
  assert.deepStrictEqual(JSON.parse(JSON.stringify(inventory.filterValues("group").map(function (entry) {
    return entry.label; }))), ["Ambient", "Perimeter", "Basement floor"]);
  assert.strictEqual(inventory.controls.orderBy.parentNode.hidden, true, "column menus replace Order by");
  inventory.controls.filterColumn("group", ["17-FS/BC"]);
  function rows() {
    return o.root.querySelector(".tb-types").querySelectorAll("[data-row-key]").filter(function (row) {
      return !row.hidden && /^tbt_/.test(row.getAttribute("data-row-key"));
    }).map(function (row) { return row.getAttribute("data-row-key"); });
  }
  var shown = rows();
  assert.deepStrictEqual(shown, ["tbt_b"]);
  assert.ok(inventory.menus.group.filtered(), "the filtered column's menu says so");
  assert.strictEqual(inventory.menus.color, undefined, "Color offers no menu");
  inventory.controls.filterColumn("group", null);
  inventory.controls.sortBy("psi_w_mk", "asc");
  assert.deepStrictEqual(rows(), ["tbt_b", "tbt_a"]);
});

test("a schedule row's Locate icon, and a click on the row, send runs.locate with that run's Edges", function () {
  var o = setup();
  readSchedule(o);
  o.view.tabs.select("schedule");
  var locate = o.root.querySelector("[aria-label='Locate Parapet 1']");
  assert.ok(locate, "each run offers Locate");
  locate.listeners.click({ stopPropagation: function () {} });
  var sent = named(o, PREFIX + "runs.locate")[0];
  assert.strictEqual(sent.type, "view.invoke");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(sent.payload.params)),
    { edge_paths: [[100, 101], [100, 102], [100, 103], [100, 104]] });
  var zone = o.root.querySelector("[data-row-key=tb_aaaa]").querySelector(".col-zone");
  o.view.schedule.mount.listeners.click({ target: zone });
  assert.strictEqual(named(o, PREFIX + "runs.locate").length, 1, "a pending Locate takes no second click");
  o.state.ui.viewResults[sent.payload.request_id] = { request_id: sent.payload.request_id, session: "session",
    outcome: { status: "completed", value: {} } };
  o.paint();
  o.view.schedule.mount.listeners.click({ target: zone });
  assert.strictEqual(named(o, PREFIX + "runs.locate").length, 2, "clicking a row's cell locates the run");
  var second = named(o, PREFIX + "runs.locate")[1].payload.request_id;
  o.state.ui.viewResults[second] = { request_id: second, session: "session", outcome: { status: "completed",
    value: {} } };
  o.state.revision = 2; o.paint();
  assert.strictEqual(o.view.read.stale(o.state), false, "opening the Edges' context leaves the read current");
  assert.strictEqual(o.view.schedule.status.textContent, "");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(named(o, PREFIX + "runs.locate")[1].payload.params.edge_paths)),
    [[100, 101], [100, 102], [100, 103], [100, 104]]);
  var heat = o.root.querySelectorAll(".col-heat_loss_w_k").map(function (td) { return td.textContent; });
  assert.ok(heat.indexOf("2.16") >= 0, heat.join());
});

test("a refused schedule read keeps the last good one and says why", function () {
  var o = setup();
  readSchedule(o);
  o.view.tabs.select("schedule");
  o.view.schedule.refresh.listeners.click({});
  answer(o, named(o, PREFIX + "schedule.all")[1], { status: "refused", code: "record.unreadable",
    message: "A Thermal Bridge Type cannot be read." });
  assert.strictEqual(o.view.schedule.status.textContent, "A Thermal Bridge Type cannot be read.");
  assert.strictEqual(o.view.read.value().runs.length, 1);
});

test("Delete asks for a replacement when the last read is out of date, and not for an unused type", function () {
  var o = setup();
  readSchedule(o);
  var form = o.view.types.replacement, records = o.view.types.records;
  form.open(records[1], records);
  assert.strictEqual(form.inUse, false, "an unused type deletes plainly");
  form.hide();
  form.open(records[0], records);
  assert.strictEqual(form.inUse, true);
  assert.ok(form.uses.textContent.includes("4 Edges"));
  form.hide();
  o.state.revision = 2; o.paint();
  form.open(records[1], records);
  assert.strictEqual(form.inUse, true, "after a change the read cannot say the type is unused");
});

test("Delete asks for a replacement while assigned Edges sit outside every run", function () {
  var o = setup(), schedule = fixtures.schedule();
  schedule.edge_findings = [{ path: [5], code: "thermal_bridge.outside_zone", blocks_export: false,
    message: "An assigned Edge is not inside a Zone.", locate: { edge_paths: [[5]] } }];
  schedule.edge_finding_total = 1;
  answer(o, named(o, PREFIX + "schedule.all")[0], { status: "completed", revision: 1, value: schedule });
  var form = o.view.types.replacement, records = o.view.types.records;
  form.open(records[1], records);
  assert.strictEqual(form.inUse, true, "the Edge outside a Zone may use this type");
});

test("a hidden Schedule paints nothing until it is shown", function () {
  var o = setup();
  readSchedule(o);
  assert.strictEqual(o.root.querySelectorAll("[aria-label='Locate Parapet 1']").length, 0);
  o.view.tabs.select("schedule");
  assert.strictEqual(o.root.querySelectorAll("[aria-label='Locate Parapet 1']").length, 1);
});

test("New Thermal Bridge Type takes a negative psi-value and starts at the Ambient group", function () {
  var o = setup(), form = o.view.types.newType;
  assert.ok(o.view.header.root.querySelector(".primary") === o.view.types.create, "New is the page's primary");
  o.view.types.create.listeners.click({});
  assert.strictEqual(form.group.value, "15-Ambient");
  assert.strictEqual(form.submitButton.disabled, true, "Create waits for a name");
  assert.strictEqual(form.error.textContent, "Enter a name to create the type.");
  form.name.value = "Balcony"; form.name.listeners.input({});
  assert.strictEqual(form.submitButton.disabled, false);
  form.psi.input.value = "-0.02"; form.psi.input.listeners.input({});
  form.psi.input.listeners.keydown({ key: "Enter", preventDefault: function () {},
    stopImmediatePropagation: function () {} });
  var create = named(o, PREFIX + "types.create")[0].payload.params.values;
  assert.deepStrictEqual(JSON.parse(JSON.stringify(create)),
    { name: "Balcony", psi_w_mk: -0.02, group: "15-Ambient", notes: "" });
  assert.strictEqual(o.view.tabs.select("schedule"), false, "an open form holds the subtab");
  o.state.ui.actionResult = { request_id: named(o, PREFIX + "types.create")[0].payload.request_id,
    session: "session", outcome: { status: "completed", value: { id: "tbt_c" } } };
  o.paint();
  assert.strictEqual(form.root.hidden, true);
  o.view.types.create.focus();
  assert.strictEqual(o.view.tabs.select("schedule"), true);
  assert.ok(o.view.header.root.querySelector(".primary") === null, "Schedule has no New");
});
