"use strict";
var assert = require("assert"), test = require("node:test"), dom = require("./support/dom_stub"),
  source = require("./support/panel_source"), fixtures = require("./support/window_fixtures");
function setup(inventoryKind) {
  var document = dom.buildDocument(""), context = { document: document, Intl: Intl, innerWidth: 1280,
    setTimeout: setTimeout, clearTimeout: clearTimeout }; context.window = context; dom.attachEvents(context);
  var create = document.createElement;
  document.createElement = function (tag) { var node = create(tag);
    node.remove = function () { if (node.parentNode) node.parentNode.removeChild(node); }; return node; };
  var modules = source.start(context, ["features/windows/editor", "features/windows/inventory",
    "features/windows/library"]),
    state = fixtures.state(), sent = [];
  state.sections["ph_composer.library.provider_catalogs"] = { status: "completed", value: [{ id: "provider",
    label: "Synthetic windows", provider_kind: "ph_composer.library.file", kinds: ["frames", "glazings",
      "psi_install_types"], catalogs: ["frames", "glazings", "psi_install_types"].map(function (kind) {
      return { kind: kind, generation: 1, state: "loaded" };
    }) }] };
  function send(type, payload) { sent.push({ type: type, payload: payload }); }
  var view = inventoryKind ? new modules["features/windows/inventory"].Inventory(document.body, "session", send,
    inventoryKind, function () {}) : new modules["features/windows/editor"].View(document.body, "session", send);
  view.render(state); return { view: view, state: state, sent: sent, modules: modules, document: document };
}
function provider(o, sidebar, kind) {
  sidebar.store.select("provider"); var message = o.sent[o.sent.length - 1].payload;
  var values = JSON.parse(JSON.stringify(o.state.sections["ph_composer.windows." + kind].value.records[0].values));
  values.name = "Library " + values.name;
  o.state.ui.queryResults = {}; o.state.ui.queryResults[message.request_id] = { session: "session",
    request_id: message.request_id, outcome: { status: "completed", value: { generation: 1, state: "loaded",
      total: 1, next_cursor: null, rows: [{ library_id: "lib", library_name: "Synthetic", record_id: "incoming",
        snapshot: values, resolution: { outcome: "create", candidates: [] } }] } } };
  o.view.render(o.state); return sidebar.records[0];
}
function click(node) { node.listeners.click({ preventDefault: function () {}, stopPropagation: function () {} }); }
function plain(value) { return JSON.parse(JSON.stringify(value)); }
test("three Window adapters retain SI descriptors and manufacturer groups without requesting data", function () {
  var o = setup(); ["frames", "glazings", "psi_install_types"].forEach(function (kind) {
    var adapter = o.modules["features/windows/library"].adapter(kind);
    assert.strictEqual(adapter.wireKind, kind); assert.ok(adapter.properties.length);
    assert.strictEqual(adapter.read(o.state).length, 1);
  });
  var frames = o.modules["features/windows/library"].adapter("frames");
  assert.strictEqual(frames.category({ values: { manufacturer: "Maker" } }), "Maker");
  assert.strictEqual(o.sent.length, 0);
});
test("Frame native drag copies and assigns one canonical side using the full frozen Type guard", function () {
  var o = setup(), sidebar = o.view.sidebars.frames, row = provider(o, sidebar, "frames");
  o.view.interior = true; o.view.render(o.state);
  var hit = o.view.cards.wel_a.rows.right.button; o.document.elementFromPoint = function () { return hit; };
  var entry = sidebar.entries[row.id]; sidebar.drag.start(entry, { button: 0, clientX: 0, clientY: 0 });
  sidebar.drag.update({ clientX: 20, clientY: 20, preventDefault: function () {} });
  assert.ok(hit.classList.contains("is-drop-target"));
  sidebar.drag.up({ clientX: 20, clientY: 20 });
  var request = o.sent[o.sent.length - 1]; assert.strictEqual(request.type, "action.invoke");
  assert.strictEqual(request.payload.name, "ph_composer.library.copy");
  assert.strictEqual(request.payload.params.assignment.element_id, "wel_a");
  assert.strictEqual(request.payload.params.assignment.side, "right");
  var baseline = plain(o.view.rawRecord().values);
  assert.deepStrictEqual(plain(request.payload.params.assignment.expected_values), baseline);
  o.view.rawRecord().values.name = "Changed after release";
  assert.strictEqual(request.payload.params.assignment.expected_values.name, "Three elements");
  assert.strictEqual(o.sent.filter(function (item) { return item.type === "action.invoke"; }).length, 1);
});
test("Glazing drops reject Empty, draft and outside targets while keyboard Use keeps local picks working", function () {
  var o = setup(), sidebar = o.view.sidebars.glazings, row = provider(o, sidebar, "glazings");
  var empty = o.view.cards.wel_c.rows.glazing.button;
  assert.ok(sidebar.adapter.target({ record: o.view.rawRecord(), selection:
    sidebar.adapter.dropSelection(empty) }).hint);
  o.document.elementFromPoint = function () { return o.document.body; };
  sidebar.drag.start(sidebar.entries[row.id], { button: 0, clientX: 0, clientY: 0 });
  sidebar.drag.up({ clientX: 20, clientY: 20 }); assert.strictEqual(o.sent.length, 1);
  o.view.select("wel_a"); o.view.dimension("columns_m", 0, o.view.title);
  o.view.dimensionField.input.value = "600 mm"; o.view.dimensionField.input.listeners.input({});
  assert.strictEqual(sidebar.use(row), false); o.view.dimensionField.cancel();
  sidebar.store.select(""); o.view.render(o.state); sidebar.openDetails(sidebar.entries.glz_a);
  click(sidebar.detail.use); var request = o.sent[o.sent.length - 1];
  assert.strictEqual(request.payload.name, "ph_composer.windows.types.grid.set_element_glazing");
  assert.strictEqual(request.payload.params.glazing_id, "glz_a"); assert.strictEqual(request.payload.params.element_id,
    "wel_a");
});
test("each Window Library subtab exposes provider Add without an implicit assignment", function () {
  ["frames", "glazings", "psi_install_types"].forEach(function (kind) {
    var o = setup(kind), sidebar = o.view.sidebar, row = provider(o, sidebar, kind);
    sidebar.openDetails(sidebar.entries[row.id]); assert.strictEqual(o.sent.length, 1);
    sidebar.add(row); var params = o.sent[o.sent.length - 1].payload.params;
    assert.strictEqual(params.kind, kind); assert.strictEqual(params.assignment, undefined);
    o.view.dispose(); sidebar.add(row); assert.strictEqual(o.sent.length, 2);
  });
});
test("Psi inventory Use freezes the complete Model defaults instead of assigning an element", function () {
  var o = setup("psi_install_types"), sidebar = o.view.sidebar, row = provider(o, sidebar, "psi_install_types");
  sidebar.use(row); var params = o.sent[o.sent.length - 1].payload.params;
  assert.strictEqual(params.assignment.mode, "model_default");
  assert.deepStrictEqual(plain(params.assignment.expected_settings), { default_psi_install_id: "psi_a",
    default_psi_install_w_mk: 0.04, default_install_depth_m: 0.1 });
  assert.strictEqual(params.assignment.element_id, undefined);
  delete o.state.sections["ph_composer.windows.settings"]; o.view.render(o.state);
  assert.strictEqual(sidebar.use(row), false);
});
test("provider Psi choices remain detached and one Save carries imports plus perimeter assignments", function () {
  var o = setup(), installs = o.view.installEditor; installs.open(o.view.rawRecord());
  var sidebar = installs.sidebar, row = provider(o, sidebar, "psi_install_types");
  sidebar.openDetails(sidebar.entries[row.id]); sidebar.use(row);
  assert.strictEqual(o.sent.filter(function (item) { return item.type === "action.invoke"; }).length, 0);
  var token = installs.selected; assert.ok(token);
  sidebar.use(row); assert.strictEqual(installs.selected, token);
  assert.strictEqual(Object.keys(installs.imports).length, 1, "repeated picks reuse their staged identity");
  assert.strictEqual(Object.keys(installs.creates).length, 0);
  installs.paintEdge("wel_a", "top"); installs.saveAction();
  var save = o.sent[o.sent.length - 1]; assert.strictEqual(save.payload.name,
    "ph_composer.windows.types.installs.save");
  assert.strictEqual(save.payload.params.imports[0].client_id, token);
  assert.strictEqual(save.payload.params.imports[0].copy.choice, "create");
  assert.strictEqual(save.payload.params.imports[0].copy.generation, 1);
  assert.strictEqual(save.payload.params.imports[0].copy.assignment, undefined);
  assert.strictEqual(save.payload.params.imports[0].values, undefined, "the host resolves all authored values");
  assert.strictEqual(save.payload.params.types[0].installs[0].sides.top, token);
  assert.strictEqual(save.payload.params.types[0].installs[0].sides.right, null);
});
test("staged Psi review preserves a whole local guard and Cancel, withdrawal, disposal never writes", function () {
  var o = setup(), installs = o.view.installEditor; installs.open(o.view.rawRecord());
  var sidebar = installs.sidebar, row = provider(o, sidebar, "psi_install_types");
  row.resolution = { outcome: "review_required", candidates: [{ id: "psi_a", name: "Local junction",
    differences: [{ field: "psi_w_mk", local: 0.04, incoming: 0.08, local_present: true, incoming_present: true }],
    expected_values: { name: "Insulated junction", notes: "", psi_w_mk: 0.04 } }] };
  sidebar.use(row); assert.strictEqual(sidebar.copy.root.hidden, false);
  assert.strictEqual(installs.saveAction(), false);
  sidebar.copy.apply("use_library"); var staged = Object.values(installs.imports)[0];
  assert.strictEqual(staged.copy.expected_values.psi_w_mk, 0.04);
  row.resolution.candidates[0].expected_values.psi_w_mk = 7;
  assert.strictEqual(staged.copy.expected_values.psi_w_mk, 0.04);
  installs.cancelSession(true); assert.strictEqual(o.sent.length, 1);
  installs.open(o.view.rawRecord()); assert.strictEqual(Object.keys(installs.imports).length, 0);
  sidebar.store.select(""); o.view.render(o.state); sidebar.use(sidebar.records[0]);
  assert.strictEqual(installs.selected, "psi_a", "local picks only arm paint");
  assert.strictEqual(o.sent.length, 1);
  delete o.state.sections["ph_composer.windows.settings"]; o.view.render(o.state);
  sidebar.copy.apply("use_library"); installs.saveAction(); assert.strictEqual(o.sent.length, 1);
  o.view.dispose(); sidebar.use(row); assert.strictEqual(o.sent.length, 1);
});
test("withdrawn Window Types disable held provider review and retained sidebar actions", function () {
  var o = setup(), sidebar = o.view.sidebars.frames, row = provider(o, sidebar, "frames");
  o.view.select("wel_a"); row.resolution = { outcome: "review_required", candidates: [{ id: "frm_a",
    name: "Timber frame", differences: [], expected_values: { name: "Timber frame" } }] };
  sidebar.use(row); assert.strictEqual(sidebar.copy.root.hidden, false);
  delete o.state.sections["ph_composer.windows.types"]; o.view.render(o.state);
  assert.strictEqual(sidebar.enabled, false); assert.strictEqual(sidebar.copy.root.hidden, true);
  sidebar.use(row); sidebar.add(row); sidebar.copy.apply("use_library");
  assert.strictEqual(o.sent.filter(function (item) { return item.type === "action.invoke"; }).length, 0);
});
test("the Library pane heading carries each Window product's New button and refuses it over an open form", function () {
  var document = dom.buildDocument(""), context = { document: document, Intl: Intl, innerWidth: 1280,
    setTimeout: setTimeout, clearTimeout: clearTimeout }; context.window = context; dom.attachEvents(context);
  var sections = {}, notices = [], root = dom.element("div"), state = fixtures.state();
  document.body.appendChild(root);
  function paint() { sections.library(root, state, function () {}); }
  source.start(context, ["library/section", "features/windows/section"], { panel: {
    section: function (name, render) { sections[name] = render; }, repaint: paint, navigationGuard: function () {},
    workedOn: function () {},
    notify: function (message, tone) {
      notices.push(tone ? message + " / " + tone : message); }, navigate: function () {} } });
  paint(); var view = root._view;
  assert.strictEqual(view.surfaces.map(function (entry) { return entry.create.textContent; }).join(),
    "+ New Frame,+ New Glazing,+ New Psi-Install Type");
  assert.strictEqual(view.surfaces.map(function (entry) {
    return entry.create.parentNode === view.header.root.querySelector(".phc-heading-actions");
  }).join(), "true,false,false");
  assert.ok(view.surfaces.every(function (entry) {
    return entry.root.querySelectorAll("h2").every(function (title) { return title.closest("dialog, [role=dialog]"); });
  }), "only a dialog carries a title inside a surface");
  view.surface("glazings").create(); click(view.surfaces[0].create);
  assert.deepStrictEqual(notices, ["Finish or cancel the product form."]);
  assert.strictEqual(view.surface("frames").form.root.hidden, true);
});
