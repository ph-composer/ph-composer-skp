"use strict";

/* The inventory grid against its declared options, with no owning section: range fill submits one batch,
   and a busy owner, a pending draft or unreadable paste text refuses through notify instead. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var document = dom.buildDocument("");
var context = { document: document, innerWidth: 1280, innerHeight: 800 };
context.window = context;
dom.attachEvents(context);
var Grid = panelSource.start(context, ["inventory_grid"]).inventory_grid;

/* Two records by two fields, one input per cell, as a RecordEdits controller would render them. */
function owner() {
  var scroll = dom.element("div"), root = dom.element("div");
  root.appendChild(scroll);
  var edits = { enabled: true, pending: null, queue: [], cells: {},
    fieldAttribute: "data-test-field", fields: ["width", "height"],
    display: function (field, value) { return String(value); },
    copyText: function (field, value) { return String(value); },
    normalize: function (field, value) { return Number(value); },
    validate: function () { return ""; }, cancel: function () {} };
  var rows = [{ key: "a", record: { id: "rec_a" } }, { key: "b", record: { id: "rec_b" } }];
  rows.forEach(function (row, r) {
    edits.fields.forEach(function (field, c) {
      var input = dom.element("input");
      input.setAttribute("data-test-field", field);
      var td = dom.element("td");
      td.appendChild(input);
      scroll.appendChild(td);
      edits.cells[row.key + ":" + field] = { row: row, field: field, input: input,
        status: "clean", current: (r + 1) * 10 + c };
    });
  });
  var state = { busy: false, notices: [], batches: [] };
  var grid = new Grid({ edits: edits, scroll: scroll, root: root, hiddenColumns: function () { return {}; },
    notify: function (message) { state.notices.push(message); }, isBusy: function () { return state.busy; },
    submitBatch: function (changes) { state.batches.push(JSON.parse(JSON.stringify(changes))); } });
  rows.forEach(function (row) { edits.fields.forEach(function (field) { grid.bind(null, row, field, false); }); });
  grid.refresh();
  return { grid: grid, edits: edits, state: state, scroll: scroll };
}

test("fill down submits one batch in the default change shape", function () {
  var o = owner();
  o.grid.select(o.edits.cells["a:width"], false); o.grid.select(o.edits.cells["b:width"], true);
  o.grid.fill(false);
  assert.deepStrictEqual(o.state.batches, [[{ id: "rec_b", values: { width: 10 }, expected_values: { width: 20 } }]]);
  assert.deepStrictEqual(o.state.notices, []);
});

test("fill right preserves each target's expected value", function () {
  var o = owner();
  o.grid.select(o.edits.cells["a:width"], false);
  o.grid.select(o.edits.cells["b:height"], true);
  o.grid.fill(true);
  assert.deepStrictEqual(o.state.batches, [[
    { id: "rec_a", values: { height: 10 }, expected_values: { height: 11 } },
    { id: "rec_b", values: { height: 20 }, expected_values: { height: 21 } }
  ]]);
});

test("a range containing a read-only target refuses the entire batch", function () {
  var o = owner();
  o.edits.isReadOnly = function (cell) { return cell === o.edits.cells["b:width"]; };
  o.grid.select(o.edits.cells["a:width"], false);
  o.grid.select(o.edits.cells["b:width"], true);
  o.grid.fill(false);
  assert.deepStrictEqual(o.state.batches, []);
  assert.deepStrictEqual(o.state.notices, ["This range includes read-only cells. Nothing was changed."]);
  o.grid.bind(null, o.edits.cells["b:width"].row, "width", false);
  o.edits.cells["b:width"].input.listeners.dblclick({});
  assert.strictEqual(o.grid.editing, null);
});

test("Shift-click selects a range, which brings the fill tools, and the help button describes editing", function () {
  var o = owner();
  assert.ok(o.grid.tools.classList.contains("is-idle"), "idle from the start");
  o.edits.cells["a:width"].input.listeners.mousedown({ shiftKey: false });
  assert.ok(o.grid.tools.classList.contains("is-idle"), "one cell is not a range to fill");
  o.edits.cells["b:height"].input.listeners.mousedown({ shiftKey: true });
  assert.strictEqual(o.grid.matrix().length, 2);
  assert.strictEqual(o.grid.matrix()[0].length, 2);
  assert.ok(!o.grid.tools.classList.contains("is-idle"));
  assert.strictEqual(o.grid.toolbar.querySelector("small"), null, "no permanent hint line");
  assert.ok(o.grid.toolbar.querySelector(".phc-help").getAttribute("aria-label").includes("Enter"));
  assert.ok(o.edits.cells["b:height"].input.parentNode.classList.contains("inventory-selected"));
  o.grid.clear();
  assert.ok(o.grid.tools.classList.contains("is-idle"), "clearing the range puts the fill tools away");
});

test("copy and paste round-trip quoted rows, and a disposed grid cannot write", function () {
  assert.deepStrictEqual(JSON.parse(JSON.stringify(Grid.parse('"line\none"\t"a""b"\r\n2\t3'))),
    [["line\none", 'a"b'], ["2", "3"]]);
  assert.strictEqual(Grid.encode('a"b'), '"a""b"');
  var o = owner();
  o.grid.select(o.edits.cells["a:width"], false);
  o.grid.select(o.edits.cells["b:width"], true);
  var copy = new dom.ClipboardEvent("copy");
  o.scroll.listeners.copy(copy);
  assert.strictEqual(copy.clipboardData.getData("text/plain"), "10\n20");
  o.grid.dispose();
  o.grid.fill(false);
  assert.deepStrictEqual(o.state.batches, []);
  assert.strictEqual(o.grid.fillDown.disabled, true);
});

test("a busy owner disables the fill tools and refuses a write", function () {
  var o = owner();
  o.state.busy = true; o.grid.refresh();
  assert.strictEqual(o.grid.fillDown.disabled, true);
  o.grid.select(o.edits.cells["a:width"], false); o.grid.select(o.edits.cells["a:height"], true);
  o.grid.fill(true);
  assert.deepStrictEqual(o.state.batches, []);
});

test("a pending cell draft blocks a range edit and says why", function () {
  var o = owner();
  o.edits.cells["a:height"].status = "dirty";
  o.grid.select(o.edits.cells["a:width"], false); o.grid.select(o.edits.cells["b:width"], true);
  o.grid.fill(false);
  assert.deepStrictEqual(o.state.batches, []);
  assert.deepStrictEqual(o.state.notices, ["Cancel or finish the existing cell draft before a range edit."]);
});

test("pasted text with an unclosed quote is reported through notify", function () {
  var o = owner();
  o.grid.select(o.edits.cells["a:width"], false);
  o.scroll.listeners.paste(new dom.ClipboardEvent("paste", { clipboardData: { "text/plain": "\"unclosed" } }));
  assert.deepStrictEqual(o.state.notices, ["The pasted text has an unclosed quote."]);
  assert.deepStrictEqual(o.state.batches, []);
});

function key(input, name, extra) {
  var event = Object.assign({ key: name, defaultPrevented: false,
    preventDefault: function () { this.defaultPrevented = true; },
    stopImmediatePropagation: function () {} }, extra);
  input.listeners.keydown(event);
  return event;
}

test("keyboard navigation extends ranges and Enter, typing and Escape control editing", function () {
  var o = owner(), first = o.edits.cells["a:width"].input;
  o.grid.select(o.edits.cells["a:width"], false);
  key(first, "ArrowRight", { shiftKey: true });
  assert.strictEqual(o.grid.end, o.edits.cells["a:height"]);
  assert.strictEqual(o.grid.matrix()[0].length, 2);
  key(o.edits.cells["a:height"].input, "ArrowDown");
  assert.strictEqual(o.grid.end, o.edits.cells["b:height"]);
  key(o.edits.cells["b:height"].input, "ArrowLeft");
  key(o.edits.cells["b:width"].input, "ArrowUp");
  assert.strictEqual(o.grid.end, o.edits.cells["a:width"]);
  key(first, "Tab");
  assert.strictEqual(o.grid.end, o.edits.cells["a:height"]);
  key(o.edits.cells["a:height"].input, "Tab", { shiftKey: true });
  key(first, " ", { shiftKey: true });
  assert.strictEqual(o.grid.matrix()[0].length, 2);
  key(first, "Enter");
  assert.strictEqual(o.grid.editing, o.edits.cells["a:width"]);
  key(first, "Escape");
  assert.strictEqual(o.grid.editing, null);
  key(first, "5");
  assert.strictEqual(first.value, "5");
  assert.strictEqual(o.grid.editing, o.edits.cells["a:width"]);
  key(first, "Enter");
  assert.strictEqual(o.grid.editing, null);
  o.edits.cells["a:width"].status = "pending";
  assert.strictEqual(key(first, "Enter").defaultPrevented, true);
});

test("paste submits expected values, reports bounds, and refuses missing cells", function () {
  var o = owner();
  o.grid.select(o.edits.cells["a:width"], false);
  o.grid.paste([["30", "40"], ["50", "60"]]);
  assert.strictEqual(o.state.batches[0].length, 4);
  assert.deepStrictEqual(o.state.batches[0][3],
    { id: "rec_b", values: { height: 60 }, expected_values: { height: 21 } });
  o.grid.paste([["1", "2", "3"]]);
  assert.deepStrictEqual(o.state.notices, ["Paste exceeds the visible rows or editable columns. Nothing was changed."]);
  o.edits.cells["b:width"].input.parentNode.hidden = true;
  o.grid.select(o.edits.cells["a:width"], false);
  o.grid.select(o.edits.cells["b:height"], true);
  o.grid.fill(false);
  assert.ok(o.state.notices[1].includes("can't be edited"));
  o.grid.select(o.edits.cells["a:width"], false);
  o.grid.paste([["1", "2"], ["3", "4"]]);
  assert.ok(o.state.notices[2].includes("can't be edited"));
  assert.strictEqual(o.state.batches.length, 1);
});

test("hidden rows clear selection and the grid ignores copy and paste during editing", function () {
  var o = owner(), first = o.edits.cells["a:width"];
  o.grid.select(first, false);
  o.grid.beginEdit(first);
  var copy = new dom.ClipboardEvent("copy"), paste = new dom.ClipboardEvent("paste");
  o.scroll.listeners.copy(copy);
  o.scroll.listeners.paste(paste);
  assert.strictEqual(copy.defaultPrevented, false);
  assert.strictEqual(paste.defaultPrevented, false);
  first.input.listeners.blur({});
  assert.strictEqual(o.grid.editing, null);
  first.input.parentNode.hidden = true;
  o.grid.refresh();
  assert.strictEqual(o.grid.anchor, null);
  assert.strictEqual(o.grid.end, null);
});

test("validation refuses the whole range and custom changes are supplied by the owner", function () {
  var o = owner();
  o.edits.validate = function (field, value) { return value < 0 ? "Negative dimension." : ""; };
  o.grid.select(o.edits.cells["a:width"], false);
  o.grid.paste([["1", "-1"]]);
  assert.deepStrictEqual(o.state.batches, []);
  assert.deepStrictEqual(o.state.notices, ["Negative dimension."]);
  o.grid.options.changeFor = function (cell, value) { return { field: cell.field, value: value }; };
  o.grid.paste([["50"]]);
  assert.deepStrictEqual(o.state.batches, [[{ field: "width", value: 50 }]]);
});

function selectInventory() {
  var document = dom.buildDocument("");
  var createElement = document.createElement;
  document.createElement = function (tag) {
    var element = createElement(tag);
    // The shared stub exposes text-selection helpers on every element. Native selects have neither.
    if (tag === "select") {
      delete element.select;
      delete element.setSelectionRange;
      var selected = "";
      // The browser clears select.value if no option matches, including before options are created.
      Object.defineProperty(element, "value", { get: function () { return selected; }, set: function (value) {
        selected = element.children.some(function (option) { return option.value === value; }) ? value : "";
      } });
    }
    return element;
  };
  var context = { document: document };
  context.window = context;
  var modules = panelSource.start(context, ["inventory_grid"]);
  var sent = [], rows = [
    { key: "a", record: { id: "a", values: { category: "First" } } },
    { key: "b", record: { id: "b", values: { category: "Second" } } }
  ];
  var edits = new modules.record_edits("session", function (type, payload) {
    sent.push({ type: type, payload: payload });
  }, function () {}, { action: "example.update", fields: ["category"],
    selectFields: { category: ["First", "Second"] }, readOnly: function (cell) { return cell.row.key === "b"; } });
  var scroll = dom.element("div");
  document.body.appendChild(scroll);
  var grid = new modules.inventory_grid({ edits: edits, scroll: scroll, hiddenColumns: function () { return {}; },
    isBusy: function () { return false; }, notify: function () {}, submitBatch: function () {} });
  rows.forEach(function (row) {
    var td = dom.element("td");
    scroll.appendChild(td);
    edits.render(td, row, "category");
    grid.bind(td, row, "category", false);
  });
  grid.refresh();
  return { grid: grid, edits: edits, rows: rows, sent: sent, document: document,
    editable: edits.cells["a:category"], readonly: edits.cells["b:category"] };
}

test("RecordEdits selects activate without text-selection APIs and keep native keyboard behavior", function () {
  var o = selectInventory();
  assert.strictEqual(o.editable.input.select, undefined);
  assert.strictEqual(o.editable.input.value, "First", "options must exist before setting the authored value");
  o.editable.input.listeners.dblclick({});
  assert.strictEqual(o.document.activeElement, o.editable.input);
  assert.strictEqual(key(o.editable.input, "ArrowDown").defaultPrevented, false);
  assert.strictEqual(key(o.editable.input, "S").defaultPrevented, false);
  o.editable.input.value = "Second";
  o.editable.input.listeners.change({});
  assert.strictEqual(o.sent.length, 1);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params)), {
    id: "a", values: { category: "Second" }, expected_values: { category: "First" }
  });
  assert.strictEqual(o.editable.input.disabled, true, "pending native selects remain disabled after binding");
  o.grid.bind(null, o.rows[0], "category", false);
  assert.strictEqual(o.editable.input.disabled, true);
  o.grid.dispose();
  o.edits.dispose();
});

test("RecordEdits read-only selects remain disabled through grid binding, refresh and activation", function () {
  var o = selectInventory();
  assert.strictEqual(o.readonly.input.disabled, true);
  o.grid.beginEdit(o.readonly);
  o.readonly.input.listeners.dblclick({});
  key(o.readonly.input, "Enter");
  assert.notStrictEqual(o.grid.editing, o.readonly);
  o.readonly.input.value = "First";
  o.readonly.input.listeners.change({});
  assert.strictEqual(o.sent.length, 0);
  o.edits.refresh(o.rows, { ui: {} });
  o.grid.refresh();
  o.grid.bind(null, o.rows[1], "category", false);
  assert.strictEqual(o.readonly.input.disabled, true);
  o.grid.dispose();
  o.edits.dispose();
});
