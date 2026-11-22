"use strict";

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

function setup(state, extra) {
  var document = dom.buildDocument("");
  var context = { document: document };
  context.window = context;
  var Subtabs = panelSource.start(context, ["subtabs"]).subtabs;
  var first = dom.element("section"), second = dom.element("section"), input = dom.element("input");
  first.appendChild(input);
  var tabs = new Subtabs(Object.assign({ label: "Example sections", state: state || {}, stateKey: "surface",
    tabs: [{ id: "first", label: "First", surface: first }, { id: "second", label: "Second", surface: second }]
  }, extra));
  document.body.appendChild(tabs.root);
  document.body.appendChild(first);
  document.body.appendChild(second);
  return { tabs: tabs, first: first, second: second, input: input, document: document };
}

test("subtabs show exactly one surface and remember the active tab in session-owned page state", function () {
  var state = {}, o = setup(state);
  assert.deepStrictEqual([o.first.hidden, o.second.hidden], [false, true]);
  assert.strictEqual(o.tabs.select("second"), true);
  assert.deepStrictEqual([o.first.hidden, o.second.hidden], [true, false]);
  assert.strictEqual(state.surface, "second");
  var rebuilt = setup(state);
  assert.deepStrictEqual([rebuilt.first.hidden, rebuilt.second.hidden], [true, false]);
  assert.strictEqual(setup().tabs.active, "first", "a new session's page state starts independently");
});

/* Focus as the browser gives it: the field takes focus, and focusin bubbles to its surface. */
function visit(o, value) {
  o.input.value = value || "";
  o.input.focus();
  o.first.listeners.focusin({ target: o.input });
}

test("switching never hides or moves a focused input that holds an edit", function () {
  var o = setup();
  visit(o, "20");
  o.input.value = "21";
  assert.strictEqual(o.tabs.select("second"), false);
  assert.strictEqual(o.document.activeElement, o.input);
  assert.deepStrictEqual([o.first.hidden, o.second.hidden], [false, true]);
  var prevented = false;
  o.tabs.buttons.second.listeners.mousedown({ preventDefault: function () { prevented = true; } });
  assert.strictEqual(prevented, true);
});

test("a focused field the user only visited, or put back, never holds the tab", function () {
  var o = setup();
  visit(o, "20");
  var prevented = false;
  o.tabs.buttons.second.listeners.mousedown({ preventDefault: function () { prevented = true; } });
  assert.strictEqual(prevented, false, "the click may take focus from an unchanged field");
  o.input.value = "21";
  o.input.value = "20";
  assert.strictEqual(o.tabs.select("second"), true);
  assert.deepStrictEqual([o.first.hidden, o.second.hidden], [true, false]);
});

test("a change that applied sets the value a field holds against", function () {
  var o = setup();
  visit(o, "Mon");
  o.input.value = "Tue";
  o.first.listeners.change({ target: o.input });
  assert.strictEqual(o.tabs.select("second"), true);
});

test("an owner's typed flag decides for its field: held while typed, free once Escape or Enter ends it", function () {
  var o = setup();
  visit(o, "20");
  o.input.typed = true;
  assert.strictEqual(o.tabs.select("second"), false, "typed, even back at its value");
  o.input.value = "1.25";
  o.input.typed = false;
  assert.strictEqual(o.tabs.select("second"), true, "Enter applied it and repainted the value");
});

test("an owner's entry typed back to the value it shows from the Model holds nothing", function () {
  var o = setup();
  visit(o, "0.4");
  o.input.seed = "0.4";
  o.input.typed = true;
  o.input.value = "0.2";
  assert.strictEqual(o.tabs.select("second"), false, "a changed value holds");
  o.input.value = " 0.4";
  assert.strictEqual(o.tabs.select("second"), true, "typed back, it does not");
});

test("focus in a read-only field holds no edit and never holds the tab", function () {
  var o = setup();
  o.input.readOnly = true;
  o.input.focus();
  assert.strictEqual(o.tabs.select("second"), true);
  assert.deepStrictEqual([o.first.hidden, o.second.hidden], [true, false]);
});

test("a page draft guard prevents switching after input focus leaves", function () {
  var notices = [];
  var o = setup({}, { guard: function () { return "Save or Cancel first."; },
    refused: function (message) { notices.push(message); } });
  assert.strictEqual(o.tabs.select("second"), false);
  assert.deepStrictEqual(notices, ["Save or Cancel first."]);
  assert.strictEqual(o.tabs.active, "first");
});

test("tabs have linked accessible surfaces and keyboard navigation", function () {
  var o = setup();
  assert.strictEqual(o.tabs.root.getAttribute("aria-label"), "Example sections");
  assert.strictEqual(o.tabs.root.getAttribute("role"), "tablist");
  assert.strictEqual(o.tabs.buttons.first.getAttribute("role"), "tab");
  assert.strictEqual(o.tabs.buttons.first.getAttribute("aria-controls"), o.first.id);
  assert.strictEqual(o.first.getAttribute("aria-labelledby"), o.tabs.buttons.first.id);
  o.tabs.buttons.first.listeners.keydown({ key: "ArrowRight", preventDefault: function () {} });
  assert.strictEqual(o.document.activeElement, o.tabs.buttons.second);
  assert.strictEqual(o.tabs.active, "second");
  assert.strictEqual(o.tabs.buttons.second.getAttribute("aria-selected"), "true");
  o.tabs.buttons.second.listeners.keydown({ key: "Home", preventDefault: function () {} });
  assert.strictEqual(o.tabs.active, "first");
  o.tabs.dispose();
  assert.strictEqual(o.tabs.select("second"), false);
});

test("a refusal names the tab that was asked for, and choosing the shown tab again is reported", function () {
  var seen = [], o = setup({}, { guard: function (id) { return id === "second" ? "Finish the draft." : null; },
    refused: function (reason, id) { seen.push(reason + " " + id); },
    reselected: function (id) { seen.push("again " + id); } });
  assert.strictEqual(o.tabs.select("second"), false);
  assert.strictEqual(o.tabs.select("first"), true);
  assert.deepStrictEqual(seen, ["Finish the draft. second", "again first"]);
});
