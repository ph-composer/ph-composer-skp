"use strict";
/* Mechanical › Hot Water's Pipe Types and Piping pills and the recirculation columns piping contributes to the
   Systems table, each control sending only the registered piping operations. The panel computes nothing: lengths,
   runs, parents and recirculation are the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/piping_fixtures");
var PREFIX = fixtures.PREFIX, MECHANICAL = fixtures.mechanical.PREFIX;
var HOT_WATER = MECHANICAL + "hot_water", SYSTEMS = MECHANICAL + "hot_water_systems";
var TYPES = PREFIX + "pipe_types", PIPING = PREFIX + "piping";

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
  var modules = panelSource.start(context, ["features/mechanical/section", "features/mechanical/hot_water",
    "features/mechanical/hot_water_heaters", "features/mechanical/hot_water_tanks", "features/piping/section"],
  { panel: panel });
  paint();
  root._view.tabs.select(HOT_WATER);
  var system = root._view.systems.filter(function (entry) { return entry.id === HOT_WATER; })[0];
  system.pills.select(pill || PIPING);
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
function shown(node) { return !node.hidden; }

test("Pipe Types and Piping follow Tanks; Pipe Types offers the eight nominal diameters and edits with its guard",
  function () {
    var o = setup(TYPES);
    assert.deepStrictEqual(o.pills.root.querySelectorAll("button").map(function (node) { return node.textContent; }),
      ["Systems", "Heaters", "Tanks", "Pipe Types", "Piping"]);
    var table = o.view(TYPES);
    assert.deepStrictEqual(headers(table.inventory.scroll), ["actions", "name", "material", "diameter_mm",
      "insulation_thickness_mm", "insulation_conductivity_w_mk", "insulation_reflective", "insulation_quality",
      "color", "used_length_m", "notes"]);
    assert.strictEqual(o.root._view.header.root.querySelector(".primary").textContent, "+ New Pipe Type");
    var diameter = table.inventory.edits.cells[fixtures.PT1 + ":diameter_mm"];
    assert.deepStrictEqual(diameter.input.children.map(function (option) { return option.textContent; }),
      ["3/8 in", "1/2 in", "5/8 in", "3/4 in", "1 in", "1 1/4 in", "1 1/2 in", "2 in"]);
    assert.strictEqual(diameter.input.value, "19.05");
    change(diameter.input, "25.4");
    var update = named(o, TYPES + ".update")[0];
    assert.deepStrictEqual(clone(update.payload.params), { id: fixtures.PT1, values: { diameter_mm: 25.4 },
      expected_values: { diameter_mm: 19.05 } });
    var thickness = table.inventory.edits.cells[fixtures.PT1 + ":insulation_thickness_mm"];
    thickness.input.value = "25"; thickness.input.listeners.input({});
    act(o, update, { status: "completed", value: {} });
    key(thickness.input, "Enter");
    var edit = named(o, TYPES + ".update")[1];
    assert.deepStrictEqual(clone(edit.payload.params.values), { insulation_thickness_mm: 25 });
    act(o, edit, { status: "refused", code: "target.changed", message: "The Pipe Type changed." });
    assert.strictEqual(thickness.input.value, "25", "a refused draft is kept");
    assert.ok(o.root._view.guard(), "and holds the tab");
    var used = o.root.querySelector("[data-row-key=" + fixtures.PT1 + "]").querySelector(".col-used_length_m");
    assert.strictEqual(used.textContent, "9");
  });

test("the bar shows only the chosen role's values and Assign sends the selection's references and values",
  function () {
    var o = setup(), bar = o.view(PIPING).bar;
    assert.strictEqual(bar.count.textContent, "3 lines selected, 2 assignable");
    assert.deepStrictEqual(Object.keys(bar.fields).filter(function (k) { return shown(bar.fields[k]); }),
      ["multiplier", "demand_recirculation"], "a trunk shows Multiplier and Demand recirculation");
    change(bar.role, "recirculation");
    assert.deepStrictEqual(Object.keys(bar.fields).filter(function (k) { return shown(bar.fields[k]); }),
      ["water_temp_c", "daily_period"]);
    change(bar.role, "branch");
    assert.deepStrictEqual(Object.keys(bar.fields).filter(function (k) { return shown(bar.fields[k]); }), []);
    assert.ok(bar.assign.disabled, "no type chosen yet");
    change(bar.type, fixtures.PT1);
    change(bar.role, "trunk");
    bar.multiplier.value = "12"; bar.multiplier.listeners.input({});
    press(bar.assign);
    var assign = named(o, PREFIX + "pipes.assign")[0];
    assert.deepStrictEqual(clone(assign.payload.params), { pipe_type_id: fixtures.PT1, role: "trunk", multiplier: 12,
      demand_recirculation: false, targets: [
        { reference: { group_path: [500], entity_path: [500, 601], entity_id: null }, expected_values: {} },
        { reference: { group_path: [500], entity_path: [500, 602], entity_id: "ppe_602" },
          expected_values: { pipe_type_id: fixtures.PT2, role: "twig" } }] });
    act(o, assign, { status: "completed", value: { edge_ids: [] } });
    assert.deepStrictEqual(o.notices[o.notices.length - 1], { message: "Assigned PT-1 as trunk to 2 lines.",
      tone: "success" });
    change(bar.role, "recirculation");
    press(bar.assign);
    var recirculation = named(o, PREFIX + "pipes.assign")[1].payload.params;
    assert.deepStrictEqual([recirculation.water_temp_c, recirculation.daily_period, recirculation.multiplier],
      [60, 24, undefined]);
  });

test("opening Piping reads the schedule and groups once; the tree orders twigs under branches under trunks",
  function () {
    var o = setup();
    assert.strictEqual(named(o, PREFIX + "schedule.all").length, 1);
    assert.strictEqual(named(o, PREFIX + "groups.all")[0].type, "query.invoke");
    o.paint();
    assert.strictEqual(named(o, PREFIX + "schedule.all").length, 1, "a panel refresh never reads again");
    read(o);
    var schedule = o.view(PIPING).schedule;
    var rows = schedule.mount.querySelectorAll("[data-row-key]").map(function (row) {
      return row.getAttribute("data-row-key");
    });
    assert.deepStrictEqual(rows, ["pipe_trunk#0", "pipe_branch#3", "pipe_twig#2", "pipe_recirc#1"]);
    var twig = schedule.mount.querySelector("[data-row-key='pipe_twig#2']");
    assert.strictEqual(twig.querySelector(".col-display_name").style.paddingLeft, "40px");
    assert.strictEqual(schedule.mount.querySelector("[data-row-key='pipe_trunk#0']").querySelector(".col-values")
      .textContent, "× 12");
    schedule.mount.listeners.click({ target: twig.querySelector(".col-role") });
    var locate = named(o, PREFIX + "runs.locate")[0];
    assert.strictEqual(locate.type, "view.invoke");
    assert.deepStrictEqual(clone(locate.payload.params), { edge_paths: [[500, 9]] });
    assert.ok(schedule.totals.querySelector(".col-recirculation_temperature_c"));
    o.state.revision = 2; o.paint();
    assert.strictEqual(schedule.status.textContent, "Changed since read");
    press(schedule.refresh);
    assert.strictEqual(named(o, PREFIX + "schedule.all").length, 2);
  });

test("a group's System links in place, None unlinks, and New Piping group creates and opens one", function () {
  var o = setup();
  read(o);
  var select = o.view(PIPING).groups.mount.querySelector("[data-row-key='500']").querySelector(".col-system")
    .querySelector("select");
  change(select, fixtures.mechanical.HWS2.id);
  var link = named(o, PREFIX + "groups.link")[0];
  assert.deepStrictEqual(clone(link.payload.params), { hot_water_system_id: fixtures.mechanical.HWS2.id,
    targets: [{ reference: { group_id: fixtures.GROUP, group_path: [500] },
      expected_values: { hot_water_system_id: fixtures.mechanical.HWS1.id } }] });
  act(o, link, { status: "completed", value: { group_ids: [] } });
  assert.strictEqual(named(o, PREFIX + "groups.all").length, 2, "a link reads the groups again");
  change(select, "");
  var unlink = named(o, PREFIX + "groups.unlink");
  assert.strictEqual(unlink.length, 1);
  press(o.view(PIPING).bar.newGroup);
  assert.match(o.notices[o.notices.length - 1].message, /Wait for the Piping group/, "a link in flight holds the bar");
  act(o, unlink[0], { status: "completed", value: { group_ids: [] } });
  var bar = o.view(PIPING).bar;
  press(bar.newGroup);
  var form = o.view(PIPING).groupForm;
  assert.strictEqual(form.system.children.length, 3, "a prompt and the two Systems");
  change(form.system, fixtures.mechanical.HWS1.id);
  form.submit();
  assert.deepStrictEqual(clone(named(o, PREFIX + "groups.create")[0].payload.params),
    { hot_water_system_id: fixtures.mechanical.HWS1.id });
});

test("Assign by clicking arms the pipe tool with the bar's type, role and values", function () {
  var o = setup(), bar = o.view(PIPING).bar;
  change(bar.type, fixtures.PT2);
  change(bar.role, "twig");
  press(bar.tool.arm);
  var choose = named(o, PREFIX + "pipe_tool.choose")[0];
  assert.strictEqual(choose.type, "view.invoke");
  assert.deepStrictEqual(clone(choose.payload.params), { pipe_type_id: fixtures.PT2, role: "twig" });
  o.state.sections[PREFIX + "pipe_tool"].value = { active: true, pipe_type_id: fixtures.PT2, role: "twig",
    values: {}, gesture_limit: 250 };
  o.state.ui.viewResults[choose.payload.request_id] = { request_id: choose.payload.request_id, session: "session",
    outcome: { status: "completed", value: {} } };
  o.paint();
  assert.strictEqual(bar.tool.arm.getAttribute("aria-pressed"), "true");
  assert.ok(shown(bar.tool.stop));
  var edges = o.state.sections[PREFIX + "pipes.selected"].value.edges;
  edges.shift();
  edges[0].values = { pipe_type_id: fixtures.PT1, role: "branch" };
  o.paint();
  assert.deepStrictEqual([bar.type.value, bar.role.value], [fixtures.PT2, "twig"],
    "a new selection does not change what the running tool shows");
  press(bar.tool.arm);
  assert.strictEqual(named(o, PREFIX + "pipe_tool.stop").length, 1, "a second click stops it");
});

test("the Systems table shows piping's recirculation columns in the unit read, muted at honeybee-ph's defaults",
  function () {
    var o = setup(SYSTEMS), table = o.view(SYSTEMS).inventory;
    var names = headers(table.scroll);
    assert.deepStrictEqual(names.slice(-2), ["recirculation_temperature_c", "recirculation_hours"]);
    var hws1 = o.root.querySelector("[data-row-key=" + fixtures.mechanical.HWS1.id + "]");
    var temperature = hws1.querySelector(".col-recirculation_temperature_c");
    assert.deepStrictEqual([temperature.textContent, hws1.querySelector(".col-recirculation_hours").textContent],
      ["54.1", "19"]);
    assert.ok(!temperature.classList.contains("mech-muted"));
    var hws2 = o.root.querySelector("[data-row-key=" + fixtures.mechanical.HWS2.id + "]")
      .querySelector(".col-recirculation_temperature_c");
    assert.ok(hws2.classList.contains("mech-muted"));
    assert.match(hws2.getAttribute("data-tooltip"), /default until a recirculation pipe is drawn/);
    function header() {
      return table.scroll.querySelectorAll("th").filter(function (th) {
        return /col-recirculation_temperature_c/.test(th.className);
      })[0].querySelector(".phc-th-label").textContent;
    }
    assert.match(header(), /Recirc\. °C/);
    o.modules.unit_preferences.set("unit_system", "IP"); o.paint();
    assert.match(header(), /Recirc\. °F/);
    assert.strictEqual(hws1.querySelector(".col-recirculation_temperature_c").textContent, "129.4");
  });

test("a Locate that opens a group keeps the read current only through its own revision", function () {
  var o = setup();
  read(o);
  var schedule = o.view(PIPING).schedule;
  schedule.sendLocate([[500, 9]]);
  var locate = named(o, PREFIX + "runs.locate")[0];
  o.state.revision = 2;
  o.state.ui.viewResults[locate.payload.request_id] = { request_id: locate.payload.request_id, session: "session",
    outcome: { status: "completed", revision: 2, value: {} } };
  o.paint();
  assert.strictEqual(schedule.status.textContent, "", "Locate changed no data");
  o.state.revision = 3; o.paint();
  assert.strictEqual(schedule.status.textContent, "Changed since read", "the next change is not adopted");
});

test("two runs sharing an identifier both show, and a group's unreadable record offers no Locate", function () {
  var o = setup(), value = fixtures.schedule();
  value.runs.push(Object.assign(JSON.parse(JSON.stringify(value.runs[1])), { edge_paths: [[510, 1]] }));
  value.unreadable = [{ path: [500], code: "record.unreadable", message: "Its record is not JSON." },
    { path: [500, 3], code: "record.unreadable", message: "A pipe record is not JSON." }];
  value.unreadable_total = 2;
  answer(o, last(o, PREFIX + "groups.all"), { status: "completed", revision: 1, value: { groups: fixtures.groups() } });
  answer(o, last(o, PREFIX + "schedule.all"), { status: "completed", revision: 1, value: value });
  var schedule = o.view(PIPING).schedule;
  assert.strictEqual(schedule.mount.querySelectorAll("[data-row-key]").length, 5);
  var lines = schedule.others.querySelectorAll("li");
  assert.deepStrictEqual(lines.map(function (line) { return line.querySelectorAll("button").length; }), [0, 1]);
  assert.match(lines[0].querySelector("span").textContent, /^Riser: Its record/);
});

test("the bar survives an unknown stored role and shows the tool's values after a refused or invalid change",
  function () {
    var o = setup(), bar = o.view(PIPING).bar;
    o.state.sections[PREFIX + "pipes.selected"].value.edges[1].values = { pipe_type_id: fixtures.PT2, role: "riser" };
    o.paint();
    assert.strictEqual(bar.role.value, "trunk", "an unknown role leaves the bar's choice");
    o.state.sections[PREFIX + "pipe_tool"].value = { active: true, pipe_type_id: fixtures.PT1, role: "trunk",
      values: { multiplier: 1, demand_recirculation: false }, gesture_limit: 250 };
    o.paint();
    assert.strictEqual(bar.multiplier.value, "1");
    bar.multiplier.value = "12"; bar.multiplier.listeners.change({});
    var choose = named(o, PREFIX + "pipe_tool.choose")[0];
    o.state.ui.viewResults[choose.payload.request_id] = { request_id: choose.payload.request_id, session: "session",
      outcome: { status: "refused", code: "target.not_found", message: "That Pipe Type is gone." } };
    o.paint();
    assert.strictEqual(bar.multiplier.value, "1", "the bar shows what the tool still assigns");
    bar.multiplier.value = "0"; bar.multiplier.listeners.change({});
    assert.strictEqual(named(o, PREFIX + "pipe_tool.choose").length, 1, "an invalid value is not sent");
    assert.match(o.notices[o.notices.length - 1].message, /keeps its last values/);
    assert.strictEqual(bar.multiplier.value, "1");
  });

test("a recirculation draft keeps the unit it was typed in through a unit switch", function () {
  var o = setup(), bar = o.view(PIPING).bar;
  change(bar.type, fixtures.PT1);
  change(bar.role, "recirculation");
  o.modules.unit_preferences.set("unit_system", "IP"); o.paint();
  bar.temperature.input.value = "131"; bar.temperature.input.listeners.input({});
  o.modules.unit_preferences.set("unit_system", "SI"); o.paint();
  press(bar.assign);
  var sent = named(o, PREFIX + "pipes.assign")[0].payload.params;
  assert.ok(Math.abs(sent.water_temp_c - 55) < 1e-9, String(sent.water_temp_c));
});

test("a tool armed without a value shows its default, typing repaints Assign, and New Piping group follows the Systems",
  function () {
    var o = setup(), bar = o.view(PIPING).bar;
    bar.multiplier.value = "12"; bar.multiplier.listeners.input({});
    o.state.sections[PREFIX + "pipe_tool"].value = { active: true, pipe_type_id: fixtures.PT1, role: "trunk",
      values: {}, gesture_limit: 250 };
    o.paint();
    assert.strictEqual(bar.multiplier.value, "1", "the default a new trunk takes");
    o.state.sections[PREFIX + "pipe_tool"].value.active = false; o.paint();
    change(bar.role, "recirculation");
    bar.hours.input.value = "30"; bar.hours.input.listeners.input({});
    assert.ok(bar.assign.disabled);
    bar.hours.input.value = "8"; bar.hours.input.listeners.input({});
    assert.strictEqual(bar.assign.disabled, false, "Assign follows the text as typed");
    press(bar.newGroup);
    var form = o.view(PIPING).groupForm;
    change(form.system, fixtures.mechanical.HWS2.id);
    var systems = o.state.sections[MECHANICAL + "hot_water_systems"].value.records;
    systems.splice(1, 1);
    o.paint();
    assert.strictEqual(form.system.value, "", "a deleted System is no longer chosen");
    assert.ok(form.submitButton.disabled);
  });

test("Group by Piping group keeps two groups of one name apart", function () {
  var o = setup(), value = fixtures.schedule();
  value.runs[1] = Object.assign(value.runs[1], { group: { group_id: "ppg_BBBBBBBBBBBB", group_path: [510],
    name: "Riser" } });
  answer(o, last(o, PREFIX + "schedule.all"), { status: "completed", revision: 1, value: value });
  var schedule = o.view(PIPING).schedule;
  schedule.controls.groupBy.value = "group"; schedule.paint();
  var labels = schedule.mount.querySelectorAll(".phc-group-label").map(function (node) { return node.textContent; });
  assert.deepStrictEqual(labels.sort(), ["Riser (500)", "Riser (510)"]);
});
