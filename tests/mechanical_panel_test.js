"use strict";
/* The Mechanical tab: a subtab per system, a pill per table, and Ventilation › Ventilators, each control sending
   only the registered Mechanical operations. The panel computes nothing: the balance is the host's. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/mechanical_fixtures");
var PREFIX = fixtures.PREFIX;

function setup(register) {
  var document = dom.buildDocument("");
  var sections = {}, navigate = {}, sent = [], notices = [], preferences = [], state = fixtures.state();
  var root = dom.element("div", "phc-workspace");
  document.body.appendChild(root);
  function send(type, payload) { sent.push({ type: type, payload: payload }); }
  function paint() { Object.keys(sections).forEach(function (key) { sections[key](root, state, send); }); }
  var panel = { state: state, send: send, repaint: paint, navigationGuard: function () {}, workedOn: function () {},
    section: function (name, render, options) {
      sections[name] = render; navigate[name] = options && options.onNavigate;
    },
    notify: function (message, tone) { notices.push({ message: message, tone: tone }); },
    setPreference: function (key, value, extra) {
      preferences.push({ key: key, value: value, scope: extra.scope });
      modules.unit_preferences.set(key, value, extra);
    } };
  var context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["features/mechanical/section", "features/mechanical/ventilators"],
    { panel: panel });
  if (register) register(modules["features/mechanical/systems"]);
  paint();
  return { root: root, view: root._view, state: state, sent: sent, notices: notices, preferences: preferences,
    paint: paint, modules: modules, navigate: function (intent) { navigate.mechanical(root, intent); },
    ventilators: function () { return root._view.tables[0].view; } };
}
function named(o, name) { return o.sent.filter(function (message) { return message.payload.name === name; }); }
function answer(o, message, outcome) {
  o.state.ui.actionResult = { request_id: message.payload.request_id, session: "session", outcome: outcome };
  o.paint();
}
function cell(o, key) { return o.ventilators().inventory.edits.cells[key]; }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopImmediatePropagation: function () {} });
}
function press(node) { node.listeners.click({ preventDefault: function () {} }); }
function row(o, id) { return o.root.querySelector("[data-row-key=" + id + "]"); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }

test("the tab heads with Mechanical, a Ventilation subtab and a Ventilators pill, Tag first and export fields next",
  function () {
    var o = setup();
    assert.strictEqual(o.root.querySelector("h1").textContent, "Mechanical");
    var subtabs = o.root.querySelector(".phc-subtabs");
    assert.strictEqual(subtabs.getAttribute("aria-label"), "Mechanical systems");
    assert.deepStrictEqual(subtabs.querySelectorAll("[role=tab]").map(function (node) { return node.textContent; }),
      ["Ventilation"]);
    var pills = o.root.querySelector(".phc-pill-row");
    assert.deepStrictEqual(pills.querySelectorAll("button").map(function (node) {
      return [node.textContent, node.getAttribute("aria-pressed")];
    }), [["Ventilators", "true"]]);
    var headers = o.root.querySelectorAll("th").map(function (th) { return th.className.match(/col-([a-z_0-9]+)/); })
      .filter(Boolean).map(function (match) { return match[1]; });
    assert.deepStrictEqual(headers.slice(0, 4), ["actions", "name", "quantity", "sensible_heat_recovery"]);
    assert.ok(headers.indexOf("serves") < headers.indexOf("manufacturer"), "identity columns follow export fields");
    assert.strictEqual(o.view.header.root.querySelector(".primary").textContent, "+ New Ventilator");
  });

test("a cell edit sends ventilators.update with its expected value and keeps a refused draft", function () {
  var o = setup(), quantity = cell(o, fixtures.ERV1.id + ":quantity");
  quantity.input.value = "2"; quantity.input.listeners.input({}); key(quantity.input, "Enter");
  var update = named(o, PREFIX + "ventilators.update")[0];
  assert.deepStrictEqual(clone(update.payload.params), { id: fixtures.ERV1.id, values: { quantity: 2 },
    expected_values: { quantity: 1 } });
  answer(o, update, { status: "refused", code: "target.changed", message: "The Ventilator changed." });
  assert.strictEqual(quantity.input.value, "2");
  assert.strictEqual(quantity.status, "error");
  assert.ok(o.view.guard(), "a refused draft holds the tab");

  var frost = cell(o, fixtures.ERV1.id + ":frost_protection_reqd");
  assert.strictEqual(frost.input.value, "true");
  key(quantity.input, "Escape");
  frost.input.value = "false"; frost.input.listeners.change({});
  var choice = named(o, PREFIX + "ventilators.update")[1];
  assert.deepStrictEqual(clone(choice.payload.params.values), { frost_protection_reqd: false });
  assert.deepStrictEqual(clone(choice.payload.params.expected_values), { frost_protection_reqd: true });
});

test("electric efficiency shows Wh/m³ under SI and W/cfm under IP, and a draft keeps its unit through a switch",
  function () {
    var o = setup(), efficiency = cell(o, fixtures.ERV1.id + ":electric_efficiency_wh_m3");
    var header = function () {
      return o.root.querySelectorAll("th").filter(function (th) {
        return /col-electric_efficiency_wh_m3/.test(th.className);
      })[0].querySelector(".phc-th-label").textContent;
    };
    assert.strictEqual(efficiency.input.value, "0.45");
    assert.match(header(), /Wh\/m³/);
    o.modules.unit_preferences.set("unit_system", "IP"); o.paint();
    assert.strictEqual(efficiency.input.value, "0.76");
    assert.match(header(), /W\/cfm/);
    efficiency.input.value = "0.8"; efficiency.input.listeners.input({});
    o.modules.unit_preferences.set("unit_system", "SI"); o.paint();
    assert.strictEqual(efficiency.input.value, "0.8", "the draft keeps its text");
    key(efficiency.input, "Enter");
    var sent = named(o, PREFIX + "ventilators.update")[0].payload.params.values.electric_efficiency_wh_m3;
    assert.ok(Math.abs(sent - 0.8 / 1.69901079552) < 1e-9, "read in the unit it was typed in: " + sent);
  });

test("the balance cells read the host's sums, amber while imbalanced and a dash with its reason", function () {
  var o = setup();
  var supply = row(o, fixtures.ERV1.id).querySelector(".col-supply_m3h");
  var extract = row(o, fixtures.ERV1.id).querySelector(".col-extract_m3h");
  assert.deepStrictEqual([supply.textContent, extract.textContent], ["60", "50"]);
  assert.ok(supply.classList.contains("is-imbalanced") && extract.classList.contains("is-imbalanced"));
  var balanced = row(o, fixtures.ERV2.id).querySelector(".col-supply_m3h");
  assert.strictEqual(balanced.textContent, "40");
  assert.ok(!balanced.classList.contains("is-imbalanced"));
  var unknown = row(o, fixtures.ERV3.id).querySelector(".col-supply_m3h");
  assert.strictEqual(unknown.textContent, "—");
  assert.match(unknown.getAttribute("data-tooltip"), /serves no Zone/);
});

test("the Zone picker assigns, refuses a filled Zone naming its item, replaces on request, then clears", function () {
  var o = setup();
  var cellButton = row(o, fixtures.ERV1.id).querySelector(".mech-serves-cell");
  assert.match(cellButton.getAttribute("aria-label"), /Zones served by ERV-1: Zone A/);
  press(cellButton);
  var picker = o.ventilators().picker.held;
  assert.ok(picker, "the picker opens");
  var groups = picker.list.querySelectorAll(".mech-zone-group").map(function (node) {
    return node.children[1].textContent;
  });
  assert.deepStrictEqual(groups, ["Apartments", "Old wing (not adopted)", "No Building Segment"]);
  function box(path) {
    return picker.list.querySelectorAll("input").filter(function (input) {
      return input.getAttribute("data-zone-path") === JSON.stringify(path);
    })[0];
  }
  assert.strictEqual(box([1000]).checked, true);
  var b = box([8000, 2000]);
  b.checked = true; b.listeners.change({});
  assert.deepStrictEqual(picker.list.querySelectorAll(".mech-zone-note").map(function (node) {
    return node.textContent;
  }), ["ERV-2, will be replaced"]);
  var a = box([1000]);
  a.checked = false; a.listeners.change({});
  assert.strictEqual(picker.apply.textContent, "Save");
  press(picker.apply);
  var assign = named(o, PREFIX + "serves.assign")[0];
  assert.deepStrictEqual(clone(assign.payload.params), { zones: [{ reference: fixtures.ZONES.B,
    expected_values: { ventilator_id: fixtures.ERV2.id } }], slot: "ventilator_id", item_id: fixtures.ERV1.id });
  answer(o, assign, { status: "refused", code: "mechanical.slot_filled",
    message: "Zone B is served by ERV-2; assign with replace to replace it." });
  assert.ok(o.ventilators().picker.held, "the draft stays open");
  assert.strictEqual(picker.apply.textContent, "Replace and assign");
  assert.match(picker.status.textContent, /ERV-2/);
  assert.ok(o.view.guard(), "an unapplied draft holds the tab");
  press(picker.apply);
  var replace = named(o, PREFIX + "serves.assign")[1];
  assert.strictEqual(replace.payload.params.replace, true);
  answer(o, replace, { status: "completed", value: {} });
  var clear = named(o, PREFIX + "serves.clear")[0];
  assert.deepStrictEqual(clone(clear.payload.params), { zones: [{ reference: fixtures.ZONES.A,
    expected_values: { ventilator_id: fixtures.ERV1.id } }], slot: "ventilator_id" });
  answer(o, clear, { status: "completed", value: {} });
  assert.strictEqual(o.ventilators().picker.held, null, "the picker closes once both land");
  assert.strictEqual(o.notices[o.notices.length - 1].tone, "success");
});

test("a Segment heading checks every Zone in it, and Cancel writes nothing", function () {
  var o = setup();
  press(row(o, fixtures.ERV3.id).querySelector(".mech-serves-cell"));
  var picker = o.ventilators().picker.held, heading = picker.list.querySelector(".mech-zone-group").children[0];
  heading.checked = true; heading.listeners.change({});
  assert.strictEqual(picker.apply.textContent, "Assign 2 Zones");
  picker.find.value = "Zone A"; picker.find.listeners.input({});
  assert.strictEqual(picker.list.querySelector(".mech-zone-group").children[0].getAttribute("aria-label"),
    "Every shown Zone in Apartments", "a search narrows what a heading takes");
  press(picker.cancel);
  assert.strictEqual(o.ventilators().picker.held, null);
  assert.strictEqual(named(o, PREFIX + "serves.assign").length, 0);
});

test("the optional values sit behind the row's disclosure, pressed while one is set, and apply guarded", function () {
  var o = setup();
  var disclosure = function (id) {
    return row(o, id).querySelectorAll("button").filter(function (node) {
      return /^Optional values of/.test(node.getAttribute("aria-label") || "");
    })[0];
  };
  assert.strictEqual(disclosure(fixtures.ERV1.id).getAttribute("aria-pressed"), "false");
  assert.strictEqual(disclosure(fixtures.ERV2.id).getAttribute("aria-pressed"), "true");
  assert.match(disclosure(fixtures.ERV2.id).getAttribute("aria-label"), /Subsoil heat exchanger 0.2/);
  press(disclosure(fixtures.ERV2.id));
  var held = o.ventilators().optional.held, subsoil = held.fields[0].unit;
  subsoil.input.value = ""; subsoil.input.listeners.input({}); key(subsoil.input, "Enter");
  var update = named(o, PREFIX + "ventilators.update")[0];
  assert.deepStrictEqual(clone(update.payload.params), { id: fixtures.ERV2.id,
    values: { subsoil_heat_exchange_efficiency: null }, expected_values: { subsoil_heat_exchange_efficiency: 0.2 } });
  answer(o, update, { status: "refused", code: "target.changed", message: "The Ventilator changed." });
  assert.strictEqual(subsoil.error.textContent, "The Ventilator changed.");
});

test("Columns hides Manufacturer, Model and Notes, and a Locate narrows the table to its Ventilators", function () {
  var o = setup(), inventory = o.ventilators().inventory;
  assert.ok(inventory.columnsMenu, "the Columns menu is in the control row");
  press(inventory.columnsMenu.trigger);
  var items = inventory.columnsMenu.content.querySelectorAll("button");
  assert.deepStrictEqual(items.map(function (item) { return [item.textContent, item.getAttribute("aria-pressed")]; }),
    [["Manufacturer", "true"], ["Model", "true"], ["Notes", "true"]]);
  inventory.controls.filterColumn("model", ["Q350"]);
  press(items[1]);
  assert.strictEqual(inventory.controls.columnFilter("model"), null, "hiding a column clears its filter");
  assert.strictEqual(inventory.hidden.model, true);
  function manufacturer() {
    return o.root.querySelectorAll("th").filter(function (th) { return /col-manufacturer/.test(th.className); })[0];
  }
  assert.ok(manufacturer().hidden !== true);
  inventory.toggleColumn("manufacturer", function () {});
  assert.strictEqual(manufacturer().hidden, true);
  o.navigate({ ventilator_ids: [fixtures.ERV2.id] });
  assert.deepStrictEqual(inventory.controls.columnFilter("name"), ["ERV-2"]);
  assert.strictEqual(row(o, fixtures.ERV1.id).hidden, true);
});

test("switching subtabs and pills changes the table, writes nothing to the Model and is remembered", function () {
  var built = [];
  var o = setup(function (systems) {
    systems.system({ id: "test.heating", label: "Test Heating", order: 20 });
    ["test.heating.boilers", "test.heating.pumps"].forEach(function (id, index) {
      systems.table({ system: "test.heating", id: id, label: index ? "Pumps" : "Boilers", order: index,
        build: function (surface) {
          var view = { shown: false, render: function (state, shown) { view.shown = shown; }, guard: function () {
            return null; }, dispose: function () {}, create: null };
          built.push(view); surface.textContent = id; return view;
        } });
    });
  });
  var tabs = o.view.tabs;
  assert.strictEqual(tabs.active, "ph_composer.mechanical.ventilation");
  tabs.select("test.heating");
  assert.deepStrictEqual(built.map(function (view) { return view.shown; }), [true, false]);
  var pills = o.view.systems[1].pills;
  pills.select("test.heating.pumps");
  assert.deepStrictEqual(built.map(function (view) { return view.shown; }), [false, true]);
  assert.strictEqual(o.view.header.root.querySelector(".primary"), null, "a table with no New has none");
  assert.strictEqual(o.sent.filter(function (message) { return message.type === "action.invoke"; }).length, 0);
  assert.deepStrictEqual(o.preferences.map(function (entry) { return [entry.scope, entry.value]; }),
    [["ph_composer.mechanical", "test.heating"], ["test.heating", "test.heating.pumps"]]);
  // A view rebuilt for another Model session opens on the remembered system and table.
  o.state.session = "session-2"; o.paint();
  assert.strictEqual(o.root._view.tabs.active, "test.heating");
  assert.strictEqual(o.root._view.systems[1].pills.active, "test.heating.pumps");
});

test("Duplicate asks for the copy's Tag and sends no datasheet choice", function () {
  var o = setup(), duplicate = o.ventilators().duplicate;
  var button = row(o, fixtures.ERV1.id).querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Duplicate ERV-1";
  })[0];
  press(button);
  assert.strictEqual(duplicate.name.value, "ERV-1 (copy)");
  assert.strictEqual(duplicate.copyDatasheets.parentNode.hidden, true);
  duplicate.submit();
  assert.deepStrictEqual(clone(named(o, PREFIX + "ventilators.duplicate")[0].payload.params),
    { id: fixtures.ERV1.id, name: "ERV-1 (copy)" });
});

test("the picker's draft holds only the Zones the user changed, guarded by what they saw, and outlives a stray click",
  function () {
    var o = setup();
    press(row(o, fixtures.ERV1.id).querySelector(".mech-serves-cell"));
    var picker = o.ventilators().picker;
    // Another client gives Zone C to ERV-1 while the picker is open and untouched: no edit appears.
    var zones = o.state.sections[PREFIX + "serves"].value.zones;
    zones[2].slots = { ventilator_id: fixtures.ERV1.id };
    o.paint();
    assert.strictEqual(picker.changes().count, 0, "a snapshot is not a draft");
    var b = picker.held.list.querySelectorAll("input").filter(function (input) {
      return input.getAttribute("data-zone-path") === JSON.stringify(fixtures.ZONES.B.zone_path);
    })[0];
    b.checked = true; b.listeners.change({});
    // Zone B changes under the draft: the assign still carries the slot the user saw.
    zones[1].slots = { ventilator_id: fixtures.ERV3.id };
    o.paint();
    assert.strictEqual(picker.held.bubble.close(false), false, "a click elsewhere keeps a changed draft");
    assert.ok(picker.held);
    press(picker.held.apply);
    var assign = named(o, PREFIX + "serves.assign")[0];
    assert.deepStrictEqual(clone(assign.payload.params.zones[0].expected_values), { ventilator_id: fixtures.ERV2.id });
  });

test("a clear refused after an assign landed says the assign stays written", function () {
  var o = setup();
  press(row(o, fixtures.ERV1.id).querySelector(".mech-serves-cell"));
  var picker = o.ventilators().picker, inputs = picker.held.list.querySelectorAll("input");
  function box(zone) {
    return inputs.filter(function (input) { return input.getAttribute("data-zone-path") === JSON.stringify(zone); })[0];
  }
  var c = box(fixtures.ZONES.C.zone_path), a = box(fixtures.ZONES.A.zone_path);
  c.checked = true; c.listeners.change({});
  a.checked = false; a.listeners.change({});
  press(picker.held.apply);
  var zones = o.state.sections[PREFIX + "serves"].value.zones;
  zones[2].slots = { ventilator_id: fixtures.ERV1.id };
  answer(o, named(o, PREFIX + "serves.assign")[0], { status: "completed", value: { zone_ids: ["zon_C"] } });
  answer(o, named(o, PREFIX + "serves.clear")[0], { status: "refused", code: "target.locked",
    message: "Zone A is locked. Nothing was written." });
  assert.match(picker.held.status.textContent, /^Assigned 1 Zone; clearing the unchecked Zones was refused\./);
});

test("an optional value's edit is guarded by the value it started from, and a vanished row sends nothing",
  function () {
    var o = setup();
    var disclosure = row(o, fixtures.ERV2.id).querySelectorAll("button").filter(function (node) {
      return /^Optional values of/.test(node.getAttribute("aria-label") || "");
    })[0];
    press(disclosure);
    var optional = o.ventilators().optional, subsoil = optional.held.fields[0].unit;
    subsoil.input.value = "0.35"; subsoil.input.listeners.input({});
    o.state.sections[PREFIX + "ventilators"].value.records[1].values.subsoil_heat_exchange_efficiency = 0.25;
    o.paint();
    key(subsoil.input, "Enter");
    assert.deepStrictEqual(clone(named(o, PREFIX + "ventilators.update")[0].payload.params.expected_values),
      { subsoil_heat_exchange_efficiency: 0.2 });

    var p = setup(), records;
    press(row(p, fixtures.ERV2.id).querySelectorAll("button").filter(function (node) {
      return /^Optional values of/.test(node.getAttribute("aria-label") || "");
    })[0]);
    var draft = p.ventilators().optional.held.fields[1].unit;
    draft.input.value = "5"; draft.input.listeners.input({});
    records = p.state.sections[PREFIX + "ventilators"].value.records;
    records.splice(1, 1);
    p.paint();
    assert.strictEqual(named(p, PREFIX + "ventilators.update").length, 0, "the draft is dropped, not sent");
    assert.strictEqual(p.ventilators().optional.held, null);
  });

test("pasted Yes and No reach the booleans, other text is refused, and an absent identity value is null",
  function () {
    var o = setup(), edits = o.ventilators().inventory.edits;
    assert.strictEqual(edits.normalize("frost_protection_reqd", "Yes"), true);
    assert.strictEqual(edits.normalize("in_conditioned_space", "no"), false);
    assert.strictEqual(edits.normalize("frost_protection_reqd", "maybe").ok, false);
    assert.strictEqual(edits.normalize("frost_protection_reqd", "").ok, false);
    assert.strictEqual(cell(o, fixtures.ERV3.id + ":manufacturer").current, null);
  });

test("search reads the Tag, model and served Zones, and a Locate shows its rows past other filters", function () {
  var o = setup(), inventory = o.ventilators().inventory;
  inventory.controls.filter.value = "Q350"; inventory.controls.filter.listeners.input({});
  assert.strictEqual(row(o, fixtures.ERV1.id).hidden, false);
  assert.strictEqual(row(o, fixtures.ERV2.id).hidden, true);
  inventory.controls.filter.value = "Zone B"; inventory.controls.filter.listeners.input({});
  assert.strictEqual(row(o, fixtures.ERV2.id).hidden, false);
  assert.strictEqual(row(o, fixtures.ERV1.id).hidden, true);
  inventory.controls.filterColumn("in_conditioned_space", ["true"]);
  o.navigate({ ventilator_ids: [fixtures.ERV2.id] });
  assert.strictEqual(inventory.controls.columnFilter("in_conditioned_space"), null);
  assert.strictEqual(inventory.controls.filter.value, "");
  assert.strictEqual(row(o, fixtures.ERV2.id).hidden, false);
});

function zoneBox(picker, zone) {
  return picker.held.list.querySelectorAll("input").filter(function (input) {
    return input.getAttribute("data-zone-path") === JSON.stringify(zone.zone_path);
  })[0];
}
function toggle(box, checked) { box.checked = checked; box.listeners.change({}); }

test("a box put back drops its change, a Zone replaced at its path drops it too, and the table locks while out",
  function () {
    var o = setup();
    press(row(o, fixtures.ERV1.id).querySelector(".mech-serves-cell"));
    var picker = o.ventilators().picker, zones = o.state.sections[PREFIX + "serves"].value.zones;
    toggle(zoneBox(picker, fixtures.ZONES.A), false);
    toggle(zoneBox(picker, fixtures.ZONES.A), true);
    assert.strictEqual(picker.changes().count, 0, "put back, nothing to send");
    zones[0].slots = { ventilator_id: fixtures.ERV2.id };
    o.paint();
    assert.strictEqual(zoneBox(picker, fixtures.ZONES.A).checked, false, "the Model drives it again");
    toggle(zoneBox(picker, fixtures.ZONES.C), true);
    zones[2].zone_id = "zon_NEWNEWNEWNEW"; zones[2].reference = { zone_id: "zon_NEWNEWNEWNEW", zone_path: [3000] };
    o.paint();
    assert.strictEqual(picker.changes().count, 0, "a change to a Zone that is gone lapses");
    toggle(zoneBox(picker, fixtures.ZONES.C), true);
    press(picker.held.apply);
    var assign = named(o, PREFIX + "serves.assign")[0];
    assert.strictEqual(assign.payload.params.zones[0].reference.zone_id, "zon_NEWNEWNEWNEW");
    assert.ok(o.ventilators().inventory.busy(), "the table is locked while the assign is out");
    var quantity = cell(o, fixtures.ERV1.id + ":quantity");
    quantity.input.value = "3"; quantity.input.listeners.input({}); key(quantity.input, "Enter");
    assert.strictEqual(named(o, PREFIX + "ventilators.update").length, 0, "no edit leaves beside it");
  });

test("an optional field typed back drops its guard, and a refusal stays with the typed text", function () {
  var o = setup();
  press(row(o, fixtures.ERV2.id).querySelectorAll("button").filter(function (node) {
    return /^Optional values of/.test(node.getAttribute("aria-label") || "");
  })[0]);
  var optional = o.ventilators().optional, field = optional.held.fields[0], unit = field.unit;
  unit.input.value = "0.3"; unit.input.listeners.input({});
  unit.input.value = "0.2"; unit.input.listeners.input({}); key(unit.input, "Enter");
  assert.strictEqual(named(o, PREFIX + "ventilators.update").length, 0);
  o.state.sections[PREFIX + "ventilators"].value.records[1].values.subsoil_heat_exchange_efficiency = 0.25;
  o.paint();
  unit.input.value = "0.4"; unit.input.listeners.input({}); key(unit.input, "Enter");
  var update = named(o, PREFIX + "ventilators.update")[0];
  assert.deepStrictEqual(clone(update.payload.params.expected_values), { subsoil_heat_exchange_efficiency: 0.25 });
  answer(o, update, { status: "refused", code: "validation.failed", message: "The value is out of range." });
  o.paint();
  assert.strictEqual(unit.input.value, "0.4", "the typed text stays");
  assert.strictEqual(unit.error.textContent, "The value is out of range.", "and the reason with it");
  assert.ok(optional.guard(), "the refused draft holds the tab");
});

test("a Locate's cleared search survives a refused search edit", function () {
  var o = setup(), controls = o.ventilators().inventory.controls;
  controls.filter.value = "Q350"; controls.filter.listeners.input({});
  o.navigate({ ventilator_ids: [fixtures.ERV2.id] });
  var quantity = cell(o, fixtures.ERV2.id + ":quantity");
  quantity.input.value = "4"; quantity.input.listeners.input({});
  controls.filter.value = "x"; controls.filter.listeners.input({});
  assert.strictEqual(controls.filter.value, "", "the refused edit returns to the cleared search");
});

test("a pasted range sends booleans and null guards, and invalid text sends nothing", function () {
  var o = setup(), inventory = o.ventilators().inventory;
  inventory.grid.refresh();
  inventory.grid.select(cell(o, fixtures.ERV1.id + ":frost_protection_reqd"), false);
  inventory.grid.paste([["No", "-5", "Yes"]]);
  var sent = named(o, PREFIX + "ventilators.update").map(function (message) { return clone(message.payload.params); });
  assert.deepStrictEqual(sent, [{ id: fixtures.ERV1.id, values: { frost_protection_reqd: false },
    expected_values: { frost_protection_reqd: true } }]);
  answer(o, named(o, PREFIX + "ventilators.update")[0], { status: "completed", value: {} });
  inventory.grid.select(cell(o, fixtures.ERV3.id + ":manufacturer"), false);
  inventory.grid.paste([["Acme"]]);
  var identity = named(o, PREFIX + "ventilators.update")[1];
  assert.deepStrictEqual(clone(identity.payload.params.expected_values), { manufacturer: null });
  answer(o, identity, { status: "completed", value: {} });
  inventory.grid.select(cell(o, fixtures.ERV2.id + ":frost_protection_reqd"), false);
  inventory.grid.paste([["maybe"]]);
  assert.strictEqual(named(o, PREFIX + "ventilators.update").length, 2, "an invalid paste sends no write");
  assert.match(o.notices[o.notices.length - 1].message, /Yes or No/);
});
