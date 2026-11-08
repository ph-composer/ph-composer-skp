"use strict";
var assert = require("assert"), test = require("node:test"), dom = require("./support/dom_stub"),
  source = require("./support/panel_source"), fixtures = require("./support/window_fixtures");
function setup(kind) {
  var document = dom.buildDocument(""), context = { document: document, Intl: Intl, innerWidth: 1280,
    setTimeout: setTimeout, clearTimeout: clearTimeout }; context.window = context; dom.attachEvents(context);
  var modules = source.start(context, ["features/windows/inventory"]), state = fixtures.state(), sent = [];
  var view = new modules["features/windows/inventory"].Inventory(document.body, "session", function (type, payload) {
    sent.push({ type: type, payload: payload }); }, kind || "frames", function () {}); view.render(state);
  return { view: view, state: state, sent: sent, modules: modules };
}
test("Window product inventory uses shared grid edits with quantity descriptors", function () {
  var o = setup(); assert.ok(o.view.inventory.grid); assert.ok(o.view.inventory.edits);
  assert.ok(o.view.inventory.edits.fields.indexOf("width_m") >= 0);
  assert.strictEqual(o.view.inventory.edits.quantities.width_m.unit, "m");
});
test("used product deletion freezes the complete guard and requires replacement", function () {
  var o = setup(), record = o.state.sections["ph_composer.windows.frames"].value.records[0];
  record.use_count = 1; o.view.form.open("delete", record, [record]); o.view.form.submit();
  assert.strictEqual(o.sent.length, 0); assert.ok(o.view.form.error.textContent.includes("replacement"));
  o.view.form.records.push(fixtures.record("frm_b", { name: "Replacement" }));
  o.view.form.replacement.value = "frm_b"; o.view.form.submit();
  assert.strictEqual(o.sent.length, 1); assert.strictEqual(o.sent[0].payload.params.replacement_id, "frm_b");
  assert.strictEqual(o.sent[0].payload.params.expected_values.name, "Timber frame");
});
function key(input, name) { input.listeners.keydown({ key: name, preventDefault: function () {} }); }
function type(field, text) { field.input.value = text; field.input.listeners.input({}); }
function complete(o, status, message) {
  o.state.ui.actionResult = { session: "session", request_id: o.sent[o.sent.length - 1].payload.request_id,
    outcome: { status: status, message: message } }; o.view.render(o.state);
}
test("choosing a default Psi-Install Type applies at once with both settings and their expected values", function () {
  var o = setup("psi_install_types"), menu = o.view.defaultPsi;
  assert.strictEqual(o.view.inventory.settingsRoot.children.length, 3, "the defaults sit in the action bar");
  assert.strictEqual(menu.trigger.getAttribute("aria-label"), "Default Psi-Install: Insulated junction");
  var choices = menu.content.children;
  assert.strictEqual(choices.map(function (choice) {
    return choice.textContent + "=" + choice.getAttribute("aria-pressed"); }).join(),
    "Model value=false,Insulated junction=true");
  menu.open(); choices[0].listeners.click({}); assert.strictEqual(menu.panel.hidden, true);
  assert.strictEqual(o.sent.length, 1); var params = o.sent[0].payload.params;
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.settings.update");
  assert.strictEqual(params.values.default_psi_install_id, null);
  assert.strictEqual(params.values.default_psi_install_w_mk, 0.04);
  assert.strictEqual(params.values.default_install_depth_m, 0.1);
  assert.strictEqual(params.expected_values.default_psi_install_id, "psi_a");
  assert.strictEqual(o.view.guard(), "Wait for the defaults edit.");
  complete(o, "completed"); assert.strictEqual(o.view.guard(), null);
  o.view.dispose(); o.view.saveDefaults({ default_install_depth_m: 0.1 }); assert.strictEqual(o.sent.length, 1);
});
test("with no default Type the Model value shows and edits; a chosen Type hides it", function () {
  var o = setup("psi_install_types"), bubble = o.view.psiValueBubble, field = o.view.psiValue;
  assert.strictEqual(bubble.root.hidden, true, "the Type's own value applies");
  o.state.sections["ph_composer.windows.settings"].value.default_psi_install_id = null; o.view.render(o.state);
  assert.strictEqual(bubble.root.hidden, false);
  assert.strictEqual(o.view.defaultPsi.trigger.getAttribute("aria-label"), "Default Psi-Install: Model value");
  assert.ok(/0\.04/.test(bubble.trigger.getAttribute("aria-label")));
  bubble.open(); type(field, "0.06"); key(field.input, "Enter");
  assert.strictEqual(o.sent.length, 1); var values = o.sent[0].payload.params.values;
  assert.strictEqual(values.default_psi_install_w_mk, 0.06);
  assert.strictEqual(values.default_psi_install_id, null);
  assert.strictEqual(values.default_install_depth_m, 0.1);
  assert.strictEqual(o.sent[0].payload.params.expected_values.default_psi_install_w_mk, 0.04);
  complete(o, "completed"); assert.strictEqual(bubble.panel.hidden, true);
});
test("an unfinished Model value stays on screen when a default Type arrives, and goes once cancelled", function () {
  var o = setup("psi_install_types"), bubble = o.view.psiValueBubble, field = o.view.psiValue;
  var settings = o.state.sections["ph_composer.windows.settings"].value;
  settings.default_psi_install_id = null; o.view.render(o.state);
  bubble.open(); type(field, "abc"); key(field.input, "Enter"); assert.ok(field.error.textContent);
  settings.default_psi_install_id = "psi_a"; o.view.render(o.state);
  assert.strictEqual(bubble.root.hidden, false, "the guard's draft stays reachable");
  assert.strictEqual(bubble.panel.hidden, false); assert.strictEqual(o.sent.length, 0);
  key(field.input, "Escape");
  assert.strictEqual(bubble.panel.hidden, true); assert.strictEqual(bubble.root.hidden, true);
  assert.strictEqual(o.view.guard(), null); assert.strictEqual(o.sent.length, 0);
});
test("a default Type no longer in the Model reads Missing, not the Model value", function () {
  var o = setup("psi_install_types");
  o.state.sections["ph_composer.windows.settings"].value.default_psi_install_id = "gone"; o.view.render(o.state);
  assert.strictEqual(o.view.defaultPsi.trigger.getAttribute("aria-label"), "Default Psi-Install: Missing");
  assert.strictEqual(o.view.psiValueBubble.root.hidden, true);
});
test("install depth applies on Enter and on leaving, restores on Escape, keeps an invalid entry", function () {
  var o = setup("psi_install_types"), bubble = o.view.depthBubble, field = o.view.depth;
  bubble.open(); type(field, "abc"); key(field.input, "Enter");
  assert.strictEqual(o.sent.length, 0); assert.ok(field.error.textContent);
  bubble.close(false); assert.strictEqual(bubble.panel.hidden, false, "an invalid entry keeps the bubble open");
  key(field.input, "Escape"); assert.strictEqual(bubble.panel.hidden, true);
  assert.strictEqual(field.editing, false); assert.strictEqual(o.view.guard(), null);
  bubble.open(); type(field, "200 mm"); key(field.input, "Enter");
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.params.values.default_install_depth_m, 0.2);
  assert.strictEqual(o.sent[0].payload.params.values.default_psi_install_id, "psi_a");
  complete(o, "refused", "The settings changed."); assert.strictEqual(bubble.panel.hidden, false);
  assert.strictEqual(field.error.textContent, "The settings changed."); assert.strictEqual(field.input.value, "200 mm");
  field.input.listeners.blur({}); assert.strictEqual(o.sent.length, 2, "leaving the field applies the draft");
  complete(o, "completed"); assert.strictEqual(bubble.panel.hidden, true); assert.strictEqual(o.view.guard(), null);
});
test("leaving an unchanged depth keeps the user's focus; Escape while pending closes on the outcome", function () {
  var o = setup("psi_install_types"), bubble = o.view.depthBubble, field = o.view.depth, notices = [];
  var elsewhere = o.view.root.ownerDocument.createElement("input"); o.view.root.appendChild(elsewhere);
  o.modules.panel.notify = function (message, tone) { notices.push(tone + ": " + message); };
  bubble.open(); type(field, "0.1"); elsewhere.focus(); field.input.listeners.blur({});
  assert.strictEqual(bubble.panel.hidden, true); assert.strictEqual(o.view.root.ownerDocument.activeElement, elsewhere);
  bubble.open(); type(field, "300 mm"); key(field.input, "Enter"); assert.strictEqual(field.input.disabled, true);
  field.cancel(); assert.strictEqual(bubble.panel.hidden, false, "the pending request holds the bubble");
  complete(o, "refused", "The settings changed."); assert.strictEqual(bubble.panel.hidden, true);
  assert.deepStrictEqual(notices, ["warning: The settings changed."]); assert.strictEqual(field.input.disabled, false);
});
test("withdrawn settings close the depth bubble and reset a pending defaults channel", function () {
  var o = setup("psi_install_types"), bubble = o.view.depthBubble;
  bubble.open(); type(o.view.depth, "200 mm"); key(o.view.depth.input, "Enter"); assert.ok(o.view.requests.busy());
  delete o.state.sections["ph_composer.windows.settings"]; o.view.render(o.state);
  assert.strictEqual(o.view.requests.busy(), false); assert.strictEqual(bubble.panel.hidden, true);
  assert.strictEqual(bubble.root.hidden, true); assert.strictEqual(o.view.guard(), null);
  o.view.saveDefaults(null, 0.1); assert.strictEqual(o.sent.length, 1);
});
test("the pane's New button is offered only while the inventory has a payload and is idle", function () {
  var o = setup(); assert.strictEqual(o.view.canCreate(), true);
  o.view.inventory.externalBusy = true; assert.strictEqual(o.view.canCreate(), false);
  delete o.state.sections["ph_composer.windows.frames"]; o.view.render(o.state);
  assert.strictEqual(o.view.canCreate(), false);
});
test("a refused creation keeps the form draft and permits retry after a new snapshot", function () {
  var o = setup(); o.view.create(); o.view.form.fields.name.value = "New Frame";
  o.view.form.submit(); o.state.ui.actionResult = { session: "session", request_id: o.sent[0].payload.request_id,
    outcome: { status: "refused", message: "The name is already used." } }; o.view.render(o.state);
  assert.strictEqual(o.view.form.fields.name.value, "New Frame");
    assert.strictEqual(o.view.form.submitButton.disabled, false);
  o.view.form.fields.name.value = "Other Frame"; o.view.form.submit(); assert.strictEqual(o.sent.length, 2);
});
test("new Frame parses authored width and thermal quantities and completion releases the form", function () {
  var o = setup(), form = o.view.form; o.view.create();
  form.fields.name.value = " New frame "; form.fields.manufacturer.value = " Synthetic maker ";
  form.fields.width_m.value = "80 mm"; form.fields.uf_w_m2k.value = "1.2"; form.fields.psi_g_w_mk.value = "0.03";
  form.submit(); assert.strictEqual(o.sent.length, 1);
  var values = o.sent[0].payload.params.values; assert.strictEqual(values.name, "New frame");
  assert.strictEqual(values.manufacturer, "Synthetic maker"); assert.strictEqual(values.width_m, 0.08);
  assert.strictEqual(values.uf_w_m2k, 1.2); assert.strictEqual(values.psi_g_w_mk, 0.03);
  o.state.ui.actionResult = { session: "session", request_id: o.sent[0].payload.request_id,
    outcome: { status: "completed", value: { id: "frm_created" } } }; o.view.render(o.state);
  assert.ok(form.root.hidden); assert.strictEqual(o.view.guard(), null);
});
test("new Glazing rejects an out-of-range g-value and preserves the draft for corrected Apply", function () {
  var o = setup("glazings"), form = o.view.form; o.view.create();
  form.fields.name.value = "New glazing"; form.fields.ug_w_m2k.value = "0.6"; form.fields.g_value.value = "1.2";
  form.submit(); assert.strictEqual(o.sent.length, 0); assert.ok(form.error.textContent);
  assert.strictEqual(form.fields.name.value, "New glazing"); assert.strictEqual(form.root.hidden, false);
  form.fields.g_value.value = "0.5"; form.submit(); assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.windows.glazings.create");
  assert.strictEqual(o.sent[0].payload.params.values.ug_w_m2k, 0.6);
  assert.strictEqual(o.sent[0].payload.params.values.g_value, 0.5);
});
test("Duplicate and Delete hide entire quantity labels; reopening Create restores the complete controls", function () {
  var o = setup(), form = o.view.form, record = o.view.records[0];
  function label(key) { var input = form.fields[key]; return form.unitFields[key] ? input.parentNode.parentNode :
    input.parentNode; }
  form.open("duplicate", record, o.view.records);
  assert.strictEqual(label("name").hidden, false);
  ["width_m", "uf_w_m2k", "psi_g_w_mk", "manufacturer"].forEach(function (key) {
    assert.strictEqual(label(key).hidden, true, key + " label and control must disappear together");
  });
  form.open("delete", record, o.view.records); assert.strictEqual(label("name").hidden, true);
  assert.strictEqual(label("width_m").hidden, true);
  form.open("create", null, o.view.records);
  Object.keys(form.fields).forEach(function (key) { assert.strictEqual(label(key).hidden, false); });
  assert.strictEqual(form.unitFields.width_m.root.hidden, false);
  assert.strictEqual(o.sent.length, 0);
});
function frameUses(record, elements) {
  record.uses = []; elements.forEach(function (element) {
    ["top", "right", "bottom", "left"].forEach(function (side) {
      record.uses.push({ kind: "window_element", type_id: "wnt_a", element_id: element, side: side,
        name: "R11 type / " + element + " / " + side });
    });
  });
  record.use_count = record.uses.length; record.element_use_count = elements.length;
}
function bubble(o, record) {
  var td = o.view.root.ownerDocument.createElement("td"); o.view.uses(td, record);
  var rows = td._uses.content.children.slice(1).map(function (row) {
    return row.children[0].children.map(function (node) { return node.textContent; });
  });
  return { td: td, heading: td._uses.content.children[0].textContent, rows: rows };
}
test("the uses bubble lists one row per element with its sides and counts what it lists", function () {
  var o = setup(), record = o.state.sections["ph_composer.windows.frames"].value.records[0], navigated = [];
  frameUses(record, ["Element A"]); var one = bubble(o, record);
  assert.strictEqual(one.td._uses.trigger.textContent, "1"); assert.strictEqual(one.heading, "Used by 1 element");
  assert.deepStrictEqual(one.rows, [["R11 type / Element A", "Top, right, bottom, left"]]);
  frameUses(record, ["Element A", "Element B"]); var two = bubble(o, record);
  assert.strictEqual(two.heading, "Used by 2 elements"); assert.strictEqual(two.rows.length, 2);
  o.modules.panel.navigate = function (name, intent) { navigated.push([name, intent.use]); };
  two.td._uses.content.children[2].children[1].listeners.click({});
  assert.deepStrictEqual(navigated, [["windows", record.uses[4]]]);
});
test("a Psi-Install Type that is also the Model default lists that row and says so", function () {
  var o = setup("psi_install_types"),
    record = o.state.sections["ph_composer.windows.psi_install_types"].value.records[0];
  record.uses = [{ kind: "window_element", type_id: "wnt_a", element_id: "wel_a", side: "top",
    name: "R11 type / Element A / top (default)" }, { kind: "model_default", name: "Model default" }];
  record.use_count = 2; record.element_use_count = 1;
  var view = bubble(o, record);
  assert.strictEqual(view.heading, "Used by 1 element and the Model default");
  assert.deepStrictEqual(view.rows, [["R11 type / Element A", "Top (default)"], ["Model default"]]);
  record.uses = [record.uses[1]]; record.use_count = 1; record.element_use_count = 0;
  assert.strictEqual(bubble(o, record).heading, "Used as the Model default");
});

test("product uses sort sides clockwise while preserving inherited markers and first-use navigation", function () {
  var o = setup("psi_install_types"),
    record = o.state.sections["ph_composer.windows.psi_install_types"].value.records[0], navigated = [];
  record.uses = ["bottom", "left", "right", "top"].map(function (side) {
    return { kind: "window_element", type_id: "wnt_a", element_id: "wel_a", side: side,
      name: "R11 type / Element A / " + side + (side === "top" ? " (default)" : "") };
  });
  record.use_count = 4; record.element_use_count = 1;
  var before = JSON.stringify(record.uses), view = bubble(o, record);
  assert.deepStrictEqual(view.rows, [["R11 type / Element A", "Top (default), right, bottom, left"]]);
  assert.strictEqual(JSON.stringify(record.uses), before, "presentation does not reorder the snapshot");
  o.modules.panel.navigate = function (name, intent) { navigated.push(intent.use); };
  view.td._uses.content.children[1].children[1].listeners.click({});
  assert.deepStrictEqual(navigated, [record.uses[0]], "navigation keeps the first-use target");
});
