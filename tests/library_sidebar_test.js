"use strict";
var assert = require("assert"), test = require("node:test"), dom = require("./support/dom_stub"),
  source = require("./support/panel_source");
function setup() {
  var context = { document: dom.buildDocument(""), Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context; dom.attachEvents(context);
  var modules = source.start(context, ["library/sidebar"]), sent = [], target = { id: "a", layer_id: "l",
    segment_id: "s", expected_values: { name: "Assembly", layers: [] } };
  var sidebar = new modules["library/sidebar"]({ session: "session", send: function (type, payload) {
    sent.push({ type: type, payload: payload });
  }, adapter: { title: "Synthetic library", wireKind: "test_parts", read: function () { return []; },
    properties: [], target: function () { return { params: target }; } }, onUse: function () {} });
  context.document.body.appendChild(sidebar.root);
  var state = { session: "session", revision: 1, ui: { queryResults: {}, setupResults: {} }, sections: {
    "ph_composer.library.provider_catalogs": { status: "completed", value: [{ id: "p", label: "Public provider",
      provider_kind: "example.provider", kinds: ["test_parts"], catalogs: [{ kind: "test_parts", generation: 1,
        state: "loaded" }] }] } } };
  sidebar.refresh(state, {}, true); sidebar.store.select("p");
  var request = sent[0].payload;
  state.ui.queryResults[request.request_id] = { session: "session", request_id: request.request_id,
    outcome: { status: "completed", value: { generation: 1, state: "loaded", total: 1, next_cursor: null,
      rows: [{ library_id: "lib", library_name: "Public library", record_id: "r", snapshot: { id: "r", name: "Part" },
        display_label: "Part", resolution: { outcome: "create", candidates: [] } }] } } };
  sidebar.refresh(state, {}, true);
  return { sidebar: sidebar, sent: sent, state: state, target: target };
}
test("a row's swatch follows its record: a colour set after the row was first drawn shows (W-068)", function () {
  var context = { document: dom.buildDocument(""), Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context; dom.attachEvents(context);
  var Sidebar = source.start(context, ["library/sidebar"])["library/sidebar"];
  var record = { id: "mat_a", values: { name: "Plywood", color: "#ffffff" } };
  var sidebar = new Sidebar({ session: "session", send: function () {}, adapter: { title: "Material Library",
    wireKind: "materials", read: function () { return [record]; }, name: function (row) { return row.values.name; },
    properties: [], decorate: function (node, row) {
      var swatch = dom.element("span"); swatch.className = "library-sidebar-swatch";
      swatch.style.backgroundColor = row.values.color; node.appendChild(swatch);
    } } });
  context.document.body.appendChild(sidebar.root);
  var state = { session: "session", revision: 1, ui: { queryResults: {}, setupResults: {} }, sections: {} };
  sidebar.refresh(state, {}, true);
  function swatches() { return sidebar.root.querySelectorAll(".library-sidebar-swatch"); }
  assert.strictEqual(swatches()[0].style.backgroundColor, "#ffffff");
  record = { id: "mat_a", values: { name: "Plywood", color: "#e6c99c" } };
  sidebar.refresh(state, {}, true);
  assert.strictEqual(swatches().length, 1, "one swatch, redrawn, not one more");
  assert.strictEqual(swatches()[0].style.backgroundColor, "#e6c99c");
});
test("Details never writes; Add and selected-target Use each dispatch one coordinator action", function () {
  var o = setup(), row = o.sidebar.records[0]; o.sidebar.openDetails(o.sidebar.entries[row.id]);
  assert.deepStrictEqual(o.sent.map(function (item) { return item.type; }), ["query.invoke"]);
  o.sidebar.use(row); o.target.expected_values.name = "Changed";
  assert.strictEqual(o.sent.length, 2);
  assert.strictEqual(o.sent[1].payload.name, "ph_composer.library.copy");
  assert.strictEqual(o.sent[1].payload.params.assignment.expected_values.name, "Assembly");
  o.sidebar.add(row); assert.strictEqual(o.sent.length, 2, "a pending copy cannot overlap Add");
  o.sidebar.dispose(); o.sidebar.use(row); o.sidebar.add(row); assert.strictEqual(o.sent.length, 2);
});
test("failed refresh keeps old rows and discloses age; search/expansion/scroll persist", function () {
  var o = setup(); o.sidebar.search.value = "Part"; o.sidebar.expanded[""] = false;
  o.sidebar.list.scrollTop = 15;
  o.sidebar.store.page.state = "failed"; o.sidebar.store.page.failure = { message: "Unavailable." };
  o.sidebar.store.page.age_seconds = 65;
  Object.assign(o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0],
    { state: "failed", failure: { message: "Unavailable." }, age_seconds: 65 });
  o.sidebar.refresh(o.state, {}, true);
  assert.strictEqual(o.sidebar.records.length, 1);
  assert.match(o.sidebar.sourceStatus.textContent, /last successful catalog.*65 seconds/);
  assert.strictEqual(o.sidebar.search.value, "Part"); assert.strictEqual(o.sidebar.expanded[""], false);
  assert.strictEqual(o.sidebar.list.scrollTop, 15);
});
test("provider withdrawal cancels open review and retained Add/Use/Setup callbacks cannot write", function () {
  var o = setup(), row = o.sidebar.records[0]; o.sidebar.copy.open(Object.assign({}, row, {
    resolution: { outcome: "review_required", candidates: [{ id: "local", name: "Local", differences: [],
      expected_values: { name: "Local" } }] } }));
  delete o.state.sections["ph_composer.library.provider_catalogs"]; o.sidebar.refresh(o.state, {}, true);
  o.sidebar.copy.apply("use_library"); o.sidebar.add(row); o.sidebar.use(row); o.sidebar.setup.run("add_file", {});
  assert.strictEqual(o.sent.length, 1); assert.strictEqual(o.sidebar.copy.root.hidden, true);
});

function review(o) {
  o.sidebar.copy.open(Object.assign({}, o.sidebar.records[0], {
    resolution: { outcome: "review_required", candidates: [{ id: "local", name: "Local", differences: [],
      expected_values: { name: "Local" } }] } }));
}
["removed", "kind_removed", "generation_changed"].forEach(function (change) {
  test("a held review is withdrawn when its catalog is " + change + " while metadata remains available", function () {
    var o = setup(), providers = o.state.sections["ph_composer.library.provider_catalogs"].value;
    providers.push({ id: "other", label: "Other provider", kinds: ["test_parts"],
      catalogs: [{ kind: "test_parts", generation: 1, state: "loaded" }] });
    review(o);
    var libraryButton = o.sidebar.copy.libraryButton;
    if (change === "removed") providers.splice(0, 1);
    else if (change === "kind_removed") providers[0].kinds = ["other_kind"];
    else providers[0].catalogs[0].generation = 2;
    o.sidebar.refresh(o.state, {}, true);
    assert.strictEqual(o.sidebar.store.available, true, "the completed metadata section remains available");
    assert.strictEqual(o.sidebar.copy.root.hidden, true);
    assert.strictEqual(o.sidebar.copy.held, null);
    libraryButton.listeners.click({});
    o.sidebar.copy.apply("keep_local");
    assert.strictEqual(o.sent.filter(function (message) { return message.type === "action.invoke"; }).length, 0);
  });
});
test("a failed refresh preserves a held review when its generation remains valid", function () {
  var o = setup(); review(o);
  Object.assign(o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0],
    { state: "failed", failure: { message: "Unavailable." } });
  o.sidebar.refresh(o.state, {}, true);
  assert.strictEqual(o.sidebar.copy.root.hidden, false);
  assert.strictEqual(o.sidebar.copy.held.row.library.generation, 1);
  o.sidebar.copy.apply("keep_local");
  assert.strictEqual(o.sent.filter(function (message) { return message.type === "action.invoke"; }).length, 1);
});

test("a library's row says its click adds it; beside a table the local list gives way to one line", function () {
  var o = setup(), entry = o.sidebar.entries[o.sidebar.records[0].id];
  assert.strictEqual(entry.button.getAttribute("data-tooltip"), "Add Part to this file");
  assert.strictEqual(entry.addGlyph.hidden, false);
  o.sidebar.records[0].resolution.candidates = [{ id: "local" }];
  o.sidebar.renderList();
  assert.strictEqual(entry.addGlyph.hidden, true);
  assert.strictEqual(entry.button.getAttribute("data-tooltip"), "Part is already in this file");
  o.sidebar.besideTable = true; o.sidebar.renderList();
  assert.strictEqual(o.sidebar.search.hidden, false, "a chosen library is listed as before");
  o.sidebar.store.select(""); o.sidebar.updateRows(); o.sidebar.renderList();
  assert.strictEqual(o.sidebar.search.hidden, true);
  assert.strictEqual(o.sidebar.list.children.length, 0, "beside its table the local choice adds no list and no note");
});
function plainSidebar(options) {
  var context = { document: dom.buildDocument(""), Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context; dom.attachEvents(context);
  var Sidebar = source.start(context, ["library/sidebar"])["library/sidebar"];
  var sidebar = new Sidebar(Object.assign({ session: "session", send: function () {}, adapter: {
    title: "Material Library", localLabel: "Materials in this file", wireKind: "materials",
    read: function () { return []; }, properties: [] } },
  options));
  context.document.body.appendChild(sidebar.root);
  sidebar.refresh({ session: "session", revision: 1, ui: { queryResults: {}, setupResults: {} }, sections: {} }, {},
    true);
  return sidebar;
}
test("the source choice names this file's records by kind (W-070)", function () {
  assert.strictEqual(plainSidebar().source.children[0].textContent, "Materials in this file");
});
test("Library setup is an icon on the title row, beside the title and not inside it (W-071)", function () {
  var sidebar = plainSidebar(), gear = sidebar.setupButton;
  assert.strictEqual(gear.getAttribute("data-icon"), "settings");
  assert.strictEqual(gear.parentNode, sidebar.toggleButton.parentNode);
  assert.strictEqual(gear.getAttribute("aria-label"), "Add a library…", "before any library it says what it is for");
  assert.strictEqual(sidebar.controls.hidden, true, "no empty row is left where the link was");
  var o = setup();
  assert.strictEqual(o.sidebar.setupButton.getAttribute("aria-label"), "Library setup…");
  assert.strictEqual(o.sidebar.controls.hidden, false, "a chosen library keeps Refresh");
  assert.strictEqual(plainSidebar({ localOnly: true }).setupButton.parentNode, null, "a local-only list has no setup");
});
test("a long list starts with its groups folded, a search opens them, and a fold the user chose stays", function () {
  var o = setup(), template = JSON.stringify(o.sidebar.records[0]);
  o.sidebar.records = [];
  for (var i = 0; i < 25; i += 1) {
    var row = JSON.parse(template);
    row.id = "row" + i; row.display_label = "Part " + i;
    o.sidebar.records.push(row);
  }
  o.sidebar.renderList();
  var heading = o.sidebar.list.querySelector(".library-sidebar-group-heading");
  assert.strictEqual(heading.getAttribute("aria-expanded"), "false", "25 records start folded");
  assert.strictEqual(o.sidebar.list.querySelectorAll(".library-sidebar-row-button").length, 0);
  o.sidebar.search.value = "Part 1";
  o.sidebar.renderList();
  assert.ok(o.sidebar.list.querySelectorAll(".library-sidebar-row-button").length > 0, "a search opens what it finds");
  o.sidebar.search.value = "";
  o.sidebar.renderList();
  o.sidebar.list.querySelector(".library-sidebar-group-heading").dispatchEvent({ type: "click" });
  assert.strictEqual(o.sidebar.list.querySelector(".library-sidebar-group-heading").getAttribute("aria-expanded"),
    "true", "the user's choice outlasts the default");
});
test("the sidebar narrows to one category and orders names either way, and the choice survives a repaint", function () {
  var o = setup(), template = JSON.stringify(o.sidebar.records[0]);
  o.sidebar.records = [["Board", "wood"], ["Fiber", "insulation"], ["Wool", "insulation"]].map(function (pair, i) {
    var row = JSON.parse(template);
    row.id = "row" + i; row.display_label = pair[0]; row.values.category = pair[1];
    return row;
  });
  o.sidebar.renderList();
  assert.strictEqual(o.sidebar.category.children.map(function (node) { return node.value; }).join(),
    ",insulation,wood");
  o.sidebar.category.value = "insulation";
  o.sidebar.category.listeners.change({});
  assert.strictEqual(o.sidebar.visible.length, 2);
  o.sidebar.order.value = "desc";
  o.sidebar.order.listeners.change({});
  assert.strictEqual(o.sidebar.visible.map(function (entry) { return entry.row.display_label; }).join(), "Wool,Fiber");
  o.sidebar.renderList();
  assert.strictEqual(o.sidebar.category.value, "insulation", "a repaint keeps the category chosen");
});
test("a hosted catalog says it is loading, cancelled or stale, and keeps the last rows", function () {
  var o = setup();
  [["loading", null, /^Loading library…$/], ["cancelled", null, /cancelled\. Showing the last catalog/],
    ["stale", { message: "The library could not be loaded." }, /could not be loaded\. Showing the last successful/]]
    .forEach(function (row) {
      Object.assign(o.sidebar.store.page, { state: row[0], failure: row[1], age_seconds: 5 });
      Object.assign(o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0],
        { state: row[0], failure: row[1], age_seconds: 5 });
      o.sidebar.refresh(o.state, {}, true);
      assert.match(o.sidebar.sourceStatus.textContent, row[2]);
      assert.strictEqual(o.sidebar.records.length, 1);
    });
});
test("rows a load left out are listed by record ID with the reason in PH-Composer's words", function () {
  var o = setup(), notes = [
    { code: "library.row_required_invalid", kind: "test_parts", library_id: "lib", record_id: "nameless-frame" },
    { code: "library.row_optional_absent", kind: "test_parts", library_id: "lib", record_id: "r" }];
  o.sidebar.store.page.warnings = notes;
  o.sidebar.updateRows();
  assert.match(o.sidebar.sourceStatus.textContent, /Some library records were normalized\. 1 record was not loaded:$/);
  assert.strictEqual(o.sidebar.skipped.hidden, false);
  assert.deepStrictEqual(o.sidebar.skipped.children.map(function (item) { return item.textContent; }),
    ["Record nameless-frame: a required value, such as its name, is missing or not valid."]);
  o.sidebar.store.page.warnings = Array.from({ length: 23 }, function (_, n) {
    return { code: "library.row_label_invalid", kind: "test_parts", library_id: "lib", record_id: "x" + n };
  });
  o.sidebar.updateRows();
  assert.strictEqual(o.sidebar.skipped.children.length, 21);
  assert.strictEqual(o.sidebar.skipped.children[20].textContent, "And 3 more.");
  o.sidebar.store.page.warnings = [];
  o.sidebar.updateRows();
  assert.strictEqual(o.sidebar.skipped.hidden, true);
  assert.doesNotMatch(o.sidebar.sourceStatus.textContent, /not loaded/);
});
test("notes that name no skipped row are reported apart: kept rows as normalized, the rest as skipped", function () {
  var o = setup(), cases = [
    [[{ code: "library.row_optional_absent", kind: "test_parts", library_id: "lib", record_id: "r" }],
      /Some library records were normalized\.$/],
    [[{ code: "library.file_malformed", kind: "test_parts", library_id: "lib" }],
      /Some library records or files were skipped\.$/],
    [[{ code: "library.row_required_invalid", kind: "test_parts", library_id: "lib" },
      { code: "example.provider_note", kind: "test_parts", library_id: "lib", record_id: "q" }],
    /Some library records or files were skipped\.$/]];
  cases.forEach(function (row) {
    o.sidebar.store.page.warnings = row[0];
    o.sidebar.updateRows();
    assert.match(o.sidebar.sourceStatus.textContent, row[1]);
    assert.doesNotMatch(o.sidebar.sourceStatus.textContent, /not loaded/);
    assert.strictEqual(o.sidebar.skipped.hidden, true);
  });
});
