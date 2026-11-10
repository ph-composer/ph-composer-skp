"use strict";

/* The shared inventory controls: filter, order, direction, grouping and the collapse and expand
   pair. They own view state only, so these cases hand them a synthetic record shape. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var RECORDS = [
  { id: "a", name: "Attic", size: 3, level: "Upper" },
  { id: "b", name: "Basement", size: 10, level: "Lower" },
  { id: "c", name: "Cellar", size: null, level: "Lower" }
];

function harness(options) {
  var context = {
    document: dom.buildDocument("<body><div data-mount></div></body>"), Intl: Intl,
    setTimeout: setTimeout, clearTimeout: clearTimeout
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["view_controls"]);
  var changes = [];
  var settings = { label: "Zones", placeholder: "Search", fields: [["name", "Name"], ["size", "Size"]],
    initialOrder: "name" };
  Object.keys(options || {}).forEach(function (key) { settings[key] = options[key]; });
  var controls = new modules.view_controls.ViewControls(settings, function () { changes.push(true); });
  return { controls: controls, changes: changes, modules: modules };
}

function config(extra) {
  var base = {
    value: function (record, field) { return record[field]; },
    search: function (record) { return record.name; },
    group: function (record, field) { return { label: String(record[field]) }; }
  };
  Object.keys(extra || {}).forEach(function (key) { base[key] = extra[key]; });
  return base;
}

function names(projection) {
  return projection.records.map(function (record) { return record.name; });
}

function control(h, label) {
  return h.controls.root.querySelectorAll("select").filter(function (node) {
    return node.getAttribute("aria-label") === label;
  })[0];
}

test("records come back in the chosen order and direction, blanks last either way", function () {
  var h = harness();

  assert.deepStrictEqual(names(h.controls.project(RECORDS, config())), ["Attic", "Basement", "Cellar"]);

  control(h, "Order by").value = "size";
  assert.deepStrictEqual(names(h.controls.project(RECORDS, config())), ["Attic", "Basement", "Cellar"]);

  assert.strictEqual(h.controls.directionToggle.getAttribute("aria-label"), "Sort descending");
  h.controls.directionToggle.listeners.click({});
  assert.strictEqual(h.controls.directionToggle.getAttribute("aria-label"), "Sort ascending",
    "the button names the change it offers");
  assert.deepStrictEqual(names(h.controls.project(RECORDS, config())), ["Basement", "Attic", "Cellar"],
    "a record with no value stays at the end rather than leading a descending sort");
});

test("a filter hides what does not match, counts what is left and offers Clear", function () {
  var h = harness();
  h.controls.filter.value = "cell";

  var projection = h.controls.project(RECORDS, config());

  assert.strictEqual(projection.visibleCount, 1);
  assert.strictEqual(h.controls.count.textContent, "1 of 3");
  assert.strictEqual(h.controls.clear.hidden, false);
  assert.strictEqual(projection.hidden({ key: "a", record: RECORDS[0], depth: 0 }), true);
  assert.strictEqual(projection.hidden({ key: "c", record: RECORDS[2], depth: 0 }), false);

  h.controls.clear.listeners.click({});
  assert.strictEqual(h.controls.filter.value, "");
  assert.strictEqual(h.changes.length, 1, "clearing asks the caller to repaint");
});

test("a child row is hidden by the record its parent row stands for", function () {
  var h = harness();
  var rows = [
    { key: "a", parent: null, depth: 0, record: RECORDS[0] },
    { key: "a1", parent: "a", depth: 1, record: { id: "a1", name: "Inner" } }
  ];
  h.controls.filter.value = "basement";

  var projection = h.controls.project(RECORDS, config({ rows: function () { return rows; } }));

  assert.strictEqual(projection.hidden(rows[1]), true, "the child follows its parent out of view");
});

test("grouping counts each group and the toggle collapses one at a time", function () {
  var h = harness({ groups: [["level", "Level"]] });
  control(h, "Group by").value = "level";

  var projection = h.controls.project(RECORDS, config());
  var lower = projection.group({ key: "b", record: RECORDS[1], depth: 0 });

  assert.deepStrictEqual(names(projection), ["Basement", "Cellar", "Attic"], "groups lead, then names");
  assert.strictEqual(lower.count, 2);
  assert.strictEqual(lower.collapsed, false);

  h.controls.toggleGroup(lower.key);
  assert.strictEqual(h.controls.project(RECORDS, config()).group(
    { key: "b", record: RECORDS[1], depth: 0 }).collapsed, true);
});

/* The toggle's icon, tooltip and accessible name, and whether it can be pressed. */
function toggleState(h) {
  var node = h.controls.expansionToggle;
  return [node.getAttribute("data-icon"), node.getAttribute("data-tooltip"), node.getAttribute("aria-label"),
    node.disabled];
}

test("one toggle collapses while any group is open and expands once all are shut", function () {
  var h = harness({ groups: [["level", "Level"]] });

  h.controls.project(RECORDS, config());
  assert.strictEqual(h.controls.expansionToggle.hidden, true, "no grouping, nothing to collapse");

  control(h, "Group by").value = "level";
  var projection = h.controls.project(RECORDS, config());
  assert.strictEqual(h.controls.expansionToggle.hidden, false);
  assert.deepStrictEqual(toggleState(h), ["copy_minus", "Collapse all", "Collapse all", false]);

  h.controls.toggleGroup(projection.group({ key: "b", record: RECORDS[1], depth: 0 }).key);
  h.controls.project(RECORDS, config());
  assert.deepStrictEqual(toggleState(h), ["copy_minus", "Collapse all", "Collapse all", false],
    "a partly open table still offers Collapse all");

  h.controls.expansionToggle.listeners.click({});
  h.controls.project(RECORDS, config());
  assert.deepStrictEqual(toggleState(h), ["copy_plus", "Expand all", "Expand all", false]);
  h.controls.expansionToggle.listeners.click({});
  h.controls.project(RECORDS, config());
  assert.deepStrictEqual(toggleState(h), ["copy_minus", "Collapse all", "Collapse all", false]);
});

/* A screen whose tree is its grouping hands over its own expansion, and the toggle acts on it. */
test("a caller's own expansion replaces the group collapse", function () {
  var acted = [], open = true, closed = false;
  var h = harness({ expansion: {
    collapseAll: function () { acted.push("collapse"); },
    expandAll: function () { acted.push("expand"); },
    canCollapse: function () { return open; },
    canExpand: function () { return closed; }
  } });

  h.controls.project(RECORDS, config());
  assert.strictEqual(h.controls.expansionToggle.hidden, false, "shown without any grouping");
  assert.deepStrictEqual(toggleState(h), ["copy_minus", "Collapse all", "Collapse all", false]);
  h.controls.expansionToggle.listeners.click({});

  open = false; closed = true;
  h.controls.project(RECORDS, config());
  assert.deepStrictEqual(toggleState(h), ["copy_plus", "Expand all", "Expand all", false]);
  h.controls.expansionToggle.listeners.click({});
  assert.deepStrictEqual(acted, ["collapse", "expand"]);

  closed = false;
  h.controls.project(RECORDS, config());
  assert.strictEqual(h.controls.expansionToggle.disabled, true, "nothing to open or shut");
});

test("the order choices are replaced only when they actually differ", function () {
  var h = harness();
  var order = control(h, "Order by");
  order.value = "size";

  h.controls.setFields([["name", "Name"], ["size", "Size"]]);
  assert.strictEqual(order.value, "size", "the same choices leave the selection alone");

  h.controls.setFields([["name", "Name"], ["size", "Area"]]);
  assert.deepStrictEqual(order.children.map(function (node) { return node.textContent; }), ["Name", "Area"]);
  assert.strictEqual(order.value, "size", "the selected field survives a relabelling");
});

test("the control row counts the records, a filter's share of them, or the screen's own words", function () {
  var plain = harness(), quiet = harness({ count: false });
  var worded = harness({ count: function (shown, total, filtered) {
    return (filtered ? shown + " of " : "") + total + " parts";
  } });
  [plain, quiet, worded].forEach(function (h) { h.controls.project(RECORDS, config()); });
  assert.deepStrictEqual([plain, quiet, worded].map(function (h) { return h.controls.count.textContent; }),
    ["3 total", "", "3 parts"]);
  [plain, worded].forEach(function (h) { h.controls.filter.value = "cell"; h.controls.project(RECORDS, config()); });
  assert.deepStrictEqual([plain.controls.count.textContent, worded.controls.count.textContent],
    ["1 of 3", "1 of 3 parts"]);
});

test("column sort and value filters replace Order by when a screen opts in, and count as filters", function () {
  var counts = [];
  var h = harness({ columnSort: true, count: function (shown, total, filtered, filters) {
    counts.push([shown, total, filtered, filters]); return "";
  } });
  assert.strictEqual(control(h, "Order by").parentNode.hidden, true);
  h.controls.sortBy("size", "desc");
  assert.deepStrictEqual([h.controls.sortField(), h.controls.columnDirection("size"),
    h.controls.columnDirection("name")], ["size", "desc", null]);
  var settings = config({ columnMatch: function (record, filters) {
    return filters.level.indexOf(record.level) >= 0;
  } });
  assert.deepStrictEqual(names(h.controls.project(RECORDS, settings)), ["Basement", "Attic", "Cellar"]);
  assert.strictEqual(h.controls.filterColumn("level", ["Lower"]), true);
  var projection = h.controls.project(RECORDS, settings);
  assert.deepStrictEqual(RECORDS.filter(function (record) {
    return !projection.hidden({ record: record, key: record.id });
  }).map(function (record) { return record.name; }), ["Basement", "Cellar"], "filtering hides and never drops");
  assert.deepStrictEqual(counts[counts.length - 1], [2, 3, true, 1]);
  h.controls.filterColumn("level", null);
  assert.strictEqual(h.controls.filterCount(), 0);
});

test("a refused column filter changes nothing and says why", function () {
  var refused = [];
  var h = harness({ columnSort: true, guard: function () { return "Finish first."; },
    refused: function (reason) { refused.push(reason); } });
  assert.strictEqual(h.controls.filterColumn("level", ["Lower"]), false);
  assert.deepStrictEqual([h.controls.columnFilter("level"), refused, h.changes.length], [null, ["Finish first."], 0]);
});
