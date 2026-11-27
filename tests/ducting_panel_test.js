"use strict";
/* Mechanical › Ventilation's Duct Types and Ducting pills and the duct-length columns ducting contributes to the
   Ventilators table, each control sending only the registered ducting operations. The panel computes nothing:
   lengths, runs and findings are the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/ducting_fixtures");
var PREFIX = fixtures.PREFIX, MECHANICAL = fixtures.mechanical.PREFIX;
var VENTILATION = MECHANICAL + "ventilation", VENTILATORS = MECHANICAL + "ventilators";
var TYPES = PREFIX + "duct_types", DUCTING = PREFIX + "ducting";

function setup(pill) {
  var document = dom.buildDocument("");
  var sections = {}, sent = [], notices = [], state = fixtures.state();
  var root = dom.element("div", "phc-workspace");
  document.body.appendChild(root);
  function send(type, payload) { sent.push({ type: type, payload: payload }); }
  function paint() { Object.keys(sections).forEach(function (key) { sections[key](root, state, send); }); }
  var panel = { state: state, send: send, repaint: paint, navigationGuard: function () {}, workedOn: function () {},
    section: function (name, render) { sections[name] = render; },
    notify: function (message, tone) { notices.push({ message: message, tone: tone }); },
    setPreference: function (key, value, extra) { modules.unit_preferences.set(key, value, extra); } };
  var context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["features/mechanical/section", "features/mechanical/ventilators",
    "features/ducting/section"], { panel: panel });
  paint();
  root._view.tabs.select(VENTILATION);
  var system = root._view.systems.filter(function (entry) { return entry.id === VENTILATION; })[0];
  system.pills.select(pill || DUCTING);
  function view(id) { return root._view.tables.filter(function (held) { return held.id === id; })[0].view; }
  return { root: root, state: state, sent: sent, notices: notices, paint: paint, modules: modules, view: view,
    pills: system.pills };
}
function named(o, name) { return o.sent.filter(function (message) { return message.payload.name === name; }); }
function last(o, name) { var all = named(o, name); return all[all.length - 1]; }
function answer(o, message, outcome) {
  o.state.ui.queryResults[message.payload.request_id] = { request_id: message.payload.request_id,
    session: "session", outcome: outcome };
  o.paint();
}
function act(o, message, outcome) {
  o.state.ui.actionResult = { request_id: message.payload.request_id, session: "session", outcome: outcome };
  o.paint();
}
function read(o) {
  answer(o, last(o, PREFIX + "schedule.all"), { status: "completed", revision: o.state.revision,
    value: fixtures.schedule() });
  answer(o, last(o, PREFIX + "groups.all"), { status: "completed", revision: o.state.revision,
    value: { groups: fixtures.groups() } });
}
function press(node) { node.listeners.click({ preventDefault: function () {}, target: node }); }
function change(node, value) { node.value = value; node.listeners.change({}); }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopImmediatePropagation: function () {} });
}
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function headers(surface) {
  return surface.querySelectorAll("th").map(function (th) { return th.className.match(/col-([a-z_0-9]+)/); })
    .filter(Boolean).map(function (match) { return match[1]; });
}
function row(o, id) { return o.root.querySelector("[data-row-key=" + id + "]"); }

test("Duct Types and Ducting follow Ventilators; a Duct Type edits with its guard and keeps a refused draft",
  function () {
    var o = setup(TYPES);
    assert.deepStrictEqual(o.pills.root.querySelectorAll("button").map(function (node) { return node.textContent; }),
      ["Ventilators", "Duct Types", "Ducting"]);
    var table = o.view(TYPES);
    assert.deepStrictEqual(headers(table.inventory.scroll), ["actions", "name", "shape", "diameter_mm", "width_mm",
      "height_mm", "insulation_thickness_mm", "insulation_conductivity_w_mk", "insulation_reflective", "color",
      "used_length_m", "notes"]);
    assert.strictEqual(o.root._view.header.root.querySelector(".primary").textContent, "+ New Duct Type");
    var thickness = table.inventory.edits.cells[fixtures.DT1 + ":insulation_thickness_mm"];
    thickness.input.value = "50"; thickness.input.listeners.input({});
    key(thickness.input, "Enter");
    var edit = named(o, TYPES + ".update")[0];
    assert.deepStrictEqual(clone(edit.payload.params), { id: fixtures.DT1, values: { insulation_thickness_mm: 50 },
      expected_values: { insulation_thickness_mm: 25.4 } });
    act(o, edit, { status: "refused", code: "target.changed", message: "The Duct Type changed." });
    assert.strictEqual(thickness.input.value, "50", "a refused draft is kept");
    assert.ok(o.root._view.guard(), "and holds the tab");
    var width = row(o, fixtures.DT1).querySelector(".col-width_mm");
    assert.ok(width.classList.contains("mech-inactive"));
    assert.match(width.getAttribute("data-tooltip"), /Round takes no Width/);
    assert.strictEqual(row(o, fixtures.DT2).querySelector(".col-used_length_m").textContent, "5.5");
    assert.deepStrictEqual(clone(table.table.replacement.options.usage(o.state, fixtures.DT2)),
      { count: 1, description: "Ducts 5.5 m long use it." }, "Delete names the ducts it moves or clears");
  });

test("a Shape change asks for the new shape's dimensions and sends one guarded update", function () {
  var o = setup(TYPES), table = o.view(TYPES);
  var select = row(o, fixtures.DT1).querySelector(".col-shape").querySelector("select");
  change(select, "rectangular");
  assert.strictEqual(select.value, "round", "the cell shows the Model's shape until the change lands");
  var form = table.shapeForm;
  assert.strictEqual(form.root.hidden, false);
  assert.strictEqual(form.title.textContent, "Change DT-1 to Rectangular");
  assert.strictEqual(form.explanation.textContent, "Removes its Diameter.");
  assert.deepStrictEqual(clone(form.units.map(function (held) { return held.key; })), ["width_mm", "height_mm"]);
  form.units[0].unit.input.value = "250"; form.units[0].unit.input.listeners.input({});
  form.submit();
  assert.strictEqual(named(o, TYPES + ".update").length, 0, "nothing leaves while a dimension is missing");
  form.units[1].unit.input.value = "120"; form.units[1].unit.input.listeners.input({});
  key(form.units[1].unit.input, "Enter");
  assert.deepStrictEqual(clone(named(o, TYPES + ".update")[0].payload.params), { id: fixtures.DT1,
    values: { shape: "rectangular", diameter_mm: null, width_mm: 250, height_mm: 120 },
    expected_values: { shape: "round", diameter_mm: 160 } });
});

test("the Ducting pill says which ducts are drawn, and Assign sends the type, direction, quantity and references",
  function () {
    var o = setup(), pill = o.view(DUCTING), bar = pill.bar;
    assert.strictEqual(o.root.querySelector(".line-group-intro").textContent, "Draw only the two cold runs between " +
      "each ventilator and the outside: Outdoor air and Exhaust air.");
    assert.strictEqual(bar.count.textContent, "3 lines selected, 2 assignable");
    assert.deepStrictEqual(clone(bar.choices.map(function (button) { return [button.textContent,
      button.getAttribute("aria-pressed")]; })), [["Outdoor air", "true"], ["Exhaust air", "false"]]);
    assert.ok(bar.assign.disabled, "no type chosen yet");
    change(bar.type, fixtures.DT1);
    press(bar.choices[1]);
    bar.quantity.value = "0"; bar.quantity.listeners.input({});
    assert.ok(bar.assign.disabled, "a quantity under 1 holds Assign");
    bar.quantity.value = "10001"; bar.quantity.listeners.input({});
    assert.ok(bar.assign.disabled, "and one over 10,000");
    bar.quantity.value = "2"; bar.quantity.listeners.input({});
    press(bar.assign);
    var assign = named(o, PREFIX + "ducts.assign")[0];
    assert.deepStrictEqual(clone(assign.payload.params), { duct_type_id: fixtures.DT1, direction: "exhaust_air",
      quantity: 2, targets: [
        { reference: { group_path: [600], entity_path: [600, 601], entity_id: null }, expected_values: {} },
        { reference: { group_path: [600], entity_path: [600, 602], entity_id: "dce_602" },
          expected_values: { duct_type_id: fixtures.DT2, direction: "exhaust_air", quantity: 2 } }] });
    act(o, assign, { status: "completed", value: { edge_ids: [] } });
    var edges = o.state.sections[PREFIX + "ducts.selected"].value.edges;
    edges.splice(0, 1);
    edges[0].values = { duct_type_id: fixtures.DT2, direction: "exhaust_air", quantity: 3 };
    o.paint();
    assert.strictEqual(bar.quantity.value, "3", "a new selection shows its own quantity over one typed before");
    assert.deepStrictEqual(o.notices[o.notices.length - 1], { message: "Assigned DT-1 as exhaust air to 2 lines.",
      tone: "success" });
    press(bar.clear);
    assert.deepStrictEqual(clone(named(o, PREFIX + "ducts.clear")[0].payload.params.targets.map(function (target) {
      return target.reference.entity_path;
    })), [[600, 602]], "Clear reaches only the assigned line");
  });

test("an unsent quantity outlives a change to the same lines and a Clear, and carries to the next selection",
  function () {
    var o = setup(), bar = o.view(DUCTING).bar, edges = o.state.sections[PREFIX + "ducts.selected"].value.edges;
    bar.quantity.value = "7"; bar.quantity.listeners.input({});
    edges[1].values = { duct_type_id: fixtures.DT1, direction: "exhaust_air", quantity: 2 };
    o.paint();
    press(bar.clear);
    act(o, named(o, PREFIX + "ducts.clear")[0], { status: "completed", value: { edge_ids: [] } });
    edges[1].values = {};
    o.paint();
    assert.strictEqual(bar.quantity.value, "7");
    edges.splice(0, 1);
    edges[0].values = { duct_type_id: fixtures.DT2, direction: "exhaust_air", quantity: 3 };
    o.paint();
    assert.strictEqual(bar.quantity.value, "7", "the quantity typed for the lines before carries to these");
    edges[0].path = [600, 603];
    o.paint();
    assert.strictEqual(bar.quantity.value, "3", "and only to them: the next selection shows its own");
  });

test("opening Ducting reads once; a row Locates, totals apply the quantity, and Refresh reads again", function () {
  var o = setup();
  assert.strictEqual(named(o, PREFIX + "schedule.all").length, 1);
  o.paint();
  assert.strictEqual(named(o, PREFIX + "schedule.all").length, 1, "a panel refresh never reads again");
  read(o);
  var schedule = o.view(DUCTING).schedule;
  assert.deepStrictEqual(schedule.mount.querySelectorAll("[data-row-key]").map(function (node) {
    return node.getAttribute("data-row-key");
  }), ["duct_dg1_oa#0", "duct_dg1_ea#1", "duct_dg2_oa#2", "duct_dg2_ea#3"]);
  var exhaust = schedule.mount.querySelector("[data-row-key='duct_dg2_ea#3']");
  assert.deepStrictEqual([exhaust.querySelector(".col-direction").textContent,
    exhaust.querySelector(".col-quantity").textContent], ["Exhaust air", "2"]);
  schedule.mount.listeners.click({ target: exhaust.querySelector(".col-direction") });
  var locate = named(o, PREFIX + "runs.locate")[0];
  assert.strictEqual(locate.type, "view.invoke");
  assert.deepStrictEqual(clone(locate.payload.params), { edge_paths: [[700, 11]] });
  o.state.ui.viewResults[locate.payload.request_id] = { request_id: locate.payload.request_id, session: "session",
    outcome: { status: "completed", revision: o.state.revision, value: {} } };
  o.paint();
  var bubble = schedule.bubbles["duct_dg2_ea#3"];
  assert.strictEqual(bubble.trigger.getAttribute("aria-label"), "1 finding for Exhaust air 1");
  assert.ok(bubble.trigger.classList.contains("line-group-blocks-export"));
  press(bubble.content.querySelector("button"));
  assert.deepStrictEqual(clone(last(o, PREFIX + "runs.locate").payload.params), { edge_paths: [[700, 9]] },
    "a finding's Locate selects its ducts");
  var byVentilator = schedule.parts[1].mount;
  assert.strictEqual(byVentilator.querySelector("[data-row-key=" + fixtures.mechanical.ERV2.id + "]")
    .querySelector(".col-exhaust_air_length_m").textContent, "3");
  assert.match(byVentilator.querySelector("[data-row-key=" + fixtures.mechanical.ERV3.id + "]")
    .querySelector(".col-note").textContent, /no Outdoor air run/);
  o.state.revision = 2; o.paint();
  assert.strictEqual(schedule.status.textContent, "Changed since read");
  press(schedule.refresh);
  assert.strictEqual(named(o, PREFIX + "schedule.all").length, 2);
});

test("a served Ventilator's missing-run note shows before any duct is drawn", function () {
  var o = setup(), value = fixtures.schedule();
  value.runs = [];
  answer(o, last(o, PREFIX + "schedule.all"), { status: "completed", revision: o.state.revision, value: value });
  var schedule = o.view(DUCTING).schedule;
  assert.strictEqual(schedule.totals.hidden, false);
  assert.match(schedule.parts[1].mount.querySelector("[data-row-key=" + fixtures.mechanical.ERV3.id + "]")
    .querySelector(".col-note").textContent, /no Outdoor air run/);
  value.ventilators.forEach(function (row) { row.findings = []; });
  o.state.revision = 2; o.paint(); press(schedule.refresh);
  answer(o, last(o, PREFIX + "schedule.all"), { status: "completed", revision: 2, value: value });
  assert.strictEqual(schedule.totals.hidden, true, "with no run and no note there is nothing to total");
});

test("a Shape change held after the shape changed elsewhere sends nothing on Enter", function () {
  var o = setup(TYPES), form = o.view(TYPES).shapeForm;
  change(row(o, fixtures.DT1).querySelector(".col-shape").querySelector("select"), "rectangular");
  form.units[0].unit.input.value = "250"; form.units[0].unit.input.listeners.input({});
  form.units[1].unit.input.value = "120"; form.units[1].unit.input.listeners.input({});
  var record = o.state.sections[TYPES].value.records[0];
  record.values.shape = "rectangular"; o.paint();
  record.values.shape = "round"; o.paint();
  assert.ok(form.submitButton.disabled, "the change is held once the shape moved");
  form.units[0].unit.input.value = "260"; form.units[0].unit.input.listeners.input({});
  assert.match(form.error.textContent, /is now Rectangular; cancel and choose its Shape again/, "typing keeps why");
  key(form.units[1].unit.input, "Enter");
  assert.strictEqual(named(o, TYPES + ".update").length, 0);
});

test("a group's Ventilator links in place, and Make Ducting group wraps the selected loose lines", function () {
  var o = setup();
  read(o);
  var select = o.view(DUCTING).groups.mount.querySelector("[data-row-key='600']").querySelector(".col-link")
    .querySelector("select");
  change(select, fixtures.mechanical.ERV2.id);
  assert.deepStrictEqual(clone(named(o, PREFIX + "groups.link")[0].payload.params), {
    targets: [{ reference: { group_id: fixtures.DG1, group_path: [600] },
      expected_values: { ventilator_id: fixtures.mechanical.ERV1.id } }], ventilator_id: fixtures.mechanical.ERV2.id });
  act(o, named(o, PREFIX + "groups.link")[0], { status: "completed", value: { group_ids: [] } });
  var bar = o.view(DUCTING).bar;
  assert.ok(bar.make.disabled, "lines already in a Ducting group cannot make one");
  assert.strictEqual(bar.makeReason._reason,
    "The lines are already in a Ducting group.");
  o.state.sections[PREFIX + "ducts.selected"].value = { ignored: [], ignored_total: 0, make_refusal: null,
    edges: [{ path: [801], reference: null, group: null, reason: "outside_group", values: {}, copied: false,
      record_problem: null, write_refusal: null }] };
  o.paint();
  assert.strictEqual(bar.make.disabled, false);
  press(bar.make);
  var form = o.view(DUCTING).groupForm;
  assert.strictEqual(form.title.textContent, "Make Ducting group");
  assert.strictEqual(form.link.children.length, 4, "a prompt and the three Ventilators");
  assert.match(form.hint.textContent, /^1 selected line moves? into the new group where it is drawn/);
  change(form.link, fixtures.mechanical.ERV1.id);
  form.submit();
  assert.deepStrictEqual(clone(named(o, PREFIX + "groups.make")[0].payload.params),
    { edge_paths: [[801]], ventilator_id: fixtures.mechanical.ERV1.id });
});

test("the Ventilators table shows ducting's two duct lengths in the unit read, a dash with none", function () {
  var o = setup(VENTILATORS), table = o.view(VENTILATORS).inventory;
  assert.deepStrictEqual(headers(table.scroll).slice(-2), ["outdoor_air_length_m", "exhaust_air_length_m"]);
  function lengths(id) {
    var found = row(o, id);
    return [found.querySelector(".col-outdoor_air_length_m").textContent,
      found.querySelector(".col-exhaust_air_length_m").textContent];
  }
  assert.deepStrictEqual(lengths(fixtures.mechanical.ERV1.id), ["2.5", "1.8"]);
  assert.deepStrictEqual(lengths(fixtures.mechanical.ERV2.id), ["2.5", "3"]);
  assert.deepStrictEqual(lengths(fixtures.mechanical.ERV3.id), ["—", "—"]);
  function header() {
    return table.scroll.querySelectorAll("th").filter(function (th) {
      return /col-outdoor_air_length_m/.test(th.className);
    })[0].querySelector(".phc-th-label").textContent;
  }
  assert.match(header(), /Outdoor air duct.*m/);
  o.modules.unit_preferences.set("unit_system", "IP"); o.paint();
  assert.match(header(), /Outdoor air duct.*ft/);
});

test("a Ventilator's Delete names the Ducting groups it leaves unlinked, for the choice made", function () {
  var o = setup(VENTILATORS), form = o.view(VENTILATORS).table.replacement;
  var records = o.state.sections[VENTILATORS].value.records;
  form.open(records[2], records);
  assert.strictEqual(form.inUse, true, "ERV-3 serves no Zone, and its groups are uses");
  assert.ok(form.explanation.hidden, "no Zone uses it, so nothing says Zones move");
  assert.strictEqual(form.uses.textContent, "Ducting group 1, Ducting group 2, Ducting group 3, Ducting group 4, " +
    "Ducting group 5 and 2 more will lose their Ventilator unless you choose a replacement.");
  change(form.select, "__clear__");
  assert.strictEqual(form.uses.textContent, "Ducting group 1, Ducting group 2, Ducting group 3, Ducting group 4, " +
    "Ducting group 5 and 2 more will lose their Ventilator.");
  form.submit();
  assert.strictEqual(clone(last(o, VENTILATORS + ".delete").payload.params).replacement_id, null);
  form.open(records[0], records);
  assert.strictEqual(form.uses.textContent, "Serves Zone A. DG-1 will lose its Ventilator unless you choose a " +
    "replacement.");
  change(form.select, fixtures.mechanical.ERV2.id);
  assert.strictEqual(form.uses.textContent, "Serves Zone A. DG-1 moves to the replacement.");
});
