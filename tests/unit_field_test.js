"use strict";

/* The shared unit-aware input: what it puts on the element, when it commits, and what a unit
   preference switch does to a draft.

   One control carried through one scenario, because that is what the behaviour is: the baseline
   moves with each commit, and a case that rebuilt the control could not see that. The cases run
   in order and say what they depend on. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var field = {
  quantity: "conductivity", unit: "w_mk", label: "Conductivity", allowBlank: true, allowZero: false
};

test.describe("unit field", function () {
  var document = dom.buildDocument("");
  var context = {
    document: document, Object: Object, Array: Array, Intl: Intl, Math: Math, isFinite: isFinite
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["unit_field"]);

  var commits = [];
  var cancels = [];
  var control = new modules.unit_field.UnitField({
    field: field,
    value: 0.04,
    commitOnBlur: true,
    onCommit: function (value) { commits.push(value); },
    onCancel: function (value) { cancels.push(value); }
  });
  document.body.appendChild(control.root);

  function type(value) {
    control.input.value = value;
    control.input.listeners.input({});
  }

  function press(key) {
    control.input.listeners.keydown({ key: key, preventDefault: function () {} });
  }

  test("the input is a text field the browser will not autocorrect", function () {
    assert.strictEqual(control.input.getAttribute("type"), "text");
    assert.strictEqual(control.input.getAttribute("inputmode"), "decimal");
    assert.strictEqual(control.input.getAttribute("spellcheck"), "false");
    assert.strictEqual(control.input.getAttribute("autocomplete"), "off");
    assert.strictEqual(control.input.getAttribute("aria-describedby"), control.error.getAttribute("id"));
    assert.strictEqual(control.unit.textContent, "W/(m K)");
  });

  test("a blur that changed nothing commits nothing", function () {
    control.input.listeners.blur({});
    assert.deepStrictEqual(commits, []);

    control.input.listeners.input({});
    control.input.listeners.blur({});

    assert.deepStrictEqual(commits, [], "a seed-identical edit is a no-op");
  });

  test("Enter commits and moves the baseline", function () {
    type("0.05");
    press("Enter");

    assert.deepStrictEqual(commits, [0.05]);
    assert.strictEqual(control.baseline, 0.05);
  });

  test("Escape restores the committed value and reports the cancel", function () {
    type("0.06");
    press("Escape");

    assert.strictEqual(control.input.value, "0.05");
    assert.deepStrictEqual(cancels, [0.05]);
  });

  test("an invalid entry and its message survive a unit preference switch", function () {
    type("-1");
    press("Enter");
    assert.strictEqual(control.input.value, "-1");
    assert.strictEqual(control.input.getAttribute("aria-invalid"), "true");
    var error = control.error.textContent;

    modules.unit_preferences.set("unit_system", "IP");

    assert.strictEqual(control.input.value, "-1");
    assert.strictEqual(control.unit.textContent, "W/(m K)");
    assert.strictEqual(control.error.textContent, error);
    assert.strictEqual(control.input.getAttribute("aria-invalid"), "true");
    control.cancel();
    assert.strictEqual(control.unit.textContent, "Btu/(h ft °F)");
  });

  test("a draft keeps the unit it was started in, and commits in it", function () {
    modules.unit_preferences.set("unit_system", "SI");
    type("0.3");

    modules.unit_preferences.set("unit_system", "IP");

    assert.strictEqual(control.unit.textContent, "W/(m K)", "the starting unit stays visible during a draft");
    press("Enter");
    assert.strictEqual(commits[commits.length - 1], 0.3, "an unsuffixed draft commits in its starting profile");
  });

  test("a suffixed entry commits the value that suffix means", function () {
    type("0.4 Btu/(h ft °F)");
    control.input.listeners.blur({});

    assert.strictEqual(commits[commits.length - 1], modules.units.parse("0.4 Btu/(h ft °F)", field, {
      defaultUnit: "btu_h_ft_f",
      numberFormat: modules.unit_preferences.current().numberFormat
    }).value);
    control.dispose();
  });
});

test.describe("dimension format control", function () {
  var document = dom.buildDocument("");
  var context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 800 };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["unit_field"]);
  var preferences = modules.unit_preferences;
  preferences.replace({ unit_system: "SI", dimension_formats: { "example.editor": { SI: "cm", IP: "ft-in" } } });

  test("a scoped length field shows that scope's remembered format, per system", function () {
    var control = new modules.unit_field.UnitField({
      field: { quantity: "length_mm", unit: "mm", label: "Length", scope: "example.editor" }, value: 1231.9
    });
    assert.strictEqual(control.input.value, "123.19");
    assert.strictEqual(control.unit.textContent, "cm");
    preferences.set("unit_system", "IP");
    assert.strictEqual(control.input.value, "4' 1/2\"", "IP repaints in the scope's feet and inches");
    assert.strictEqual(control.unit.textContent, "ft-in");
    preferences.set("unit_system", "SI");
    control.dispose();
  });

  test("the chooser offers the active system's formats, marks the current one and reports the choice", function () {
    var chosen = [];
    var bubble = modules.unit_field.DimensionFormatControl("example.editor", function (format, system) {
      chosen.push([format, system]);
    });
    document.body.appendChild(bubble.root);
    var choices = bubble.content.querySelectorAll("[data-dimension-format]");
    assert.deepStrictEqual(choices.map(function (node) { return node.getAttribute("data-dimension-format"); }),
      ["mm", "cm", "m"]);
    assert.deepStrictEqual(choices.map(function (node) { return node.getAttribute("aria-pressed"); }),
      ["false", "true", "false"]);
    choices[2].listeners.click({});
    assert.deepStrictEqual(chosen, [["m", "SI"]]);
  });
});

test.describe("a field the page takes away", function () {
  var document = dom.buildDocument("");
  var context = { document: document, Intl: Intl };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["unit_field"]);

  function field(commits) {
    var control = new modules.unit_field.UnitField({ field: { quantity: "length_mm", unit: "mm", label: "Length" },
      value: 1200, commitOnBlur: true, onCommit: function (value) { commits.push(value); } });
    document.body.appendChild(control.root);
    return control;
  }
  function type(control, text) { control.input.value = text; control.input.listeners.input({}); }

  test("a blur caused by removing the input keeps the draft and sends nothing", function () {
    var commits = [], control = field(commits);
    type(control, "13");
    document.body.removeChild(control.root);
    control.input.listeners.blur({});
    assert.deepStrictEqual(commits, []);
    assert.strictEqual(control.input.value, "13");
  });

  test("a disposed field never commits, however it is left", function () {
    var commits = [], control = field(commits);
    type(control, "13");
    control.dispose();
    control.input.listeners.blur({});
    control.input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
    assert.deepStrictEqual(commits, []);
  });

  test("Escape belongs to the field only while a draft is open", function () {
    var control = field([]), prevented = 0;
    function escape() {
      control.input.listeners.keydown({ key: "Escape", preventDefault: function () { prevented += 1; } });
    }
    escape();
    assert.strictEqual(prevented, 0, "an untouched field lets Escape close the dialog around it");
    type(control, "13");
    escape();
    assert.strictEqual(prevented, 1);
    assert.strictEqual(control.input.value, "1200");
  });
  test("a field with an input form reads and rewrites a number in the chosen form", function () {
    var control = new modules.unit_field.UnitField({ forms: true, field: { quantity: "conductivity", unit: "w_mk",
      label: "Conductivity", allowBlank: true } }), changes = 0;
    modules.unit_preferences.set("unit_system", "IP");
    assert.strictEqual(control.formChoice.value, "r_per_in");
    assert.strictEqual(control.field.inputForm, "r_per_in");
    control.input.value = "4.006"; control.input.listeners.input({});
    control.onCommit = function () { changes += 1; };
    control.input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
    assert.strictEqual(changes, 1);
    assert.ok(Math.abs(control.baseline - 0.036003) < 0.000001);
    assert.strictEqual(control.input.value, "4.006", "the Enter route leaves the number in the chosen form");
    var parsed = control.parse();
    assert.ok(Math.abs(parsed.value - control.baseline) < 0.000001, "and a later read gives the same value");
    control.formChoice.value = "w_mk";
    control.formChoice.listeners.change({});
    assert.strictEqual(control.input.value, "4.006", "choosing a form rereads the number on screen");
    control.input.listeners.keydown({ key: "Enter", preventDefault: function () {} });
    assert.strictEqual(control.baseline, 4.006, "and Enter commits it in the new form");
    modules.unit_preferences.set("unit_system", "SI");
    control.setValue(null);
    modules.unit_preferences.set("unit_system", "IP");
    assert.strictEqual(control.formChoice.value, "w_mk", "the user's choice outlives a unit switch");
  });
});
