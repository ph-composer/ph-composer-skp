"use strict";
var assert = require("assert"), test = require("node:test"), source = require("./support/panel_source");
function setup() {
  var context = { Intl: Intl }; context.window = context;
  var modules = source.start(context, ["library/store"]), sent = [];
  var store = new modules["library/store"]("s", function (type, payload) {
    sent.push({ type: type, payload: payload }); },
    "materials", function () {});
  var state = { session: "s", revision: 1,
    sections: { "ph_composer.library.provider_catalogs": { status: "completed",
    value: [{ id: "p", label: "Synthetic", kinds: ["materials"],
      catalogs: [{ kind: "materials", state: "unloaded" }] }] } },
    ui: { setupResults: {}, queryResults: {} } };
  return { store: store, sent: sent, state: state };
}
function answer(o, slot, value) {
  var last = o.sent[o.sent.length - 1].payload;
  o.state.ui[slot][last.request_id] = { session: "s", request_id: last.request_id,
    outcome: { status: "completed", value: value } };
  o.store.update(o.state);
}
test("selecting one unloaded provider loads then queries one bounded immutable generation", function () {
  var o = setup(); o.store.update(o.state); o.store.select("p");
  assert.strictEqual(o.sent[0].type, "setup.invoke");
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.library.load");
  answer(o, "setupResults", { generation: 1, state: "loaded" });
  assert.strictEqual(o.sent[1].type, "query.invoke");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[1].payload.params)),
    { provider_id: "p", kind: "materials", generation: 1, limit: 100 });
  answer(o, "queryResults", { generation: 1, state: "loaded", rows: [{ library_id: "one", library_name: "One",
    record_id: "r", snapshot: { id: "r", name: "Public" }, resolution: { outcome: "create", candidates: [] } }],
    total: 1, next_cursor: null });
  assert.strictEqual(o.store.rows[0].values.name, "Public");
  assert.strictEqual(o.store.rows[0].library.provider_id, "p");
  assert.strictEqual(o.store.rows[0].library.generation, 1);
});
test("late old-source answers and retained calls after withdrawal/dispose cannot restore rows or send", function () {
  var o = setup(); o.store.update(o.state); o.store.select("p");
  var pending = o.sent[0].payload; o.store.select("");
  o.state.ui.setupResults[pending.request_id] = { session: "s", request_id: pending.request_id,
    outcome: { status: "completed", value: { generation: 1 } } };
  o.store.update(o.state); assert.strictEqual(o.sent.length, 1);
  delete o.state.sections["ph_composer.library.provider_catalogs"]; o.store.update(o.state);
  o.store.select("p"); assert.strictEqual(o.sent.length, 1);
  o.store.dispose(); o.store.refresh(); o.store.more(); assert.strictEqual(o.sent.length, 1);
});

test("refresh keeps row identity stable and follows generation changes from another placement", function () {
  var o = setup(); o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0] =
    { kind: "materials", state: "loaded", generation: 1 };
  o.store.update(o.state); o.store.select("p");
  var row = { library_id: "one", library_name: "One", record_id: "r", snapshot: { id: "r", name: "Public" },
    resolution: { outcome: "create", candidates: [] } };
  answer(o, "queryResults", { generation: 1, state: "loaded", rows: [row], total: 1, next_cursor: null });
  var identity = o.store.rows[0].id;
  o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0].generation = 2;
  o.store.update(o.state);
  assert.strictEqual(o.sent[o.sent.length - 1].payload.params.generation, 2);
  assert.strictEqual(o.store.loaded.p, undefined, "old generation resolution is not advertised");
  answer(o, "queryResults", { generation: 2, state: "loaded", rows: [row], total: 1, next_cursor: null });
  assert.strictEqual(o.store.rows[0].id, identity);
  assert.strictEqual(o.store.rows[0].library.generation, 2);
  o.store.select(""); o.state.revision = 2; o.store.update(o.state);
  assert.strictEqual(o.store.loaded.p, undefined, "another source's old local guards are discarded on Model change");
});

test("a Model change while a page is pending re-reads current guards; refusals do not auto-loop", function () {
  var o = setup(); o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0] =
    { kind: "materials", state: "loaded", generation: 1 };
  o.store.update(o.state); o.store.select("p");
  var first = o.sent[0].payload;
  o.state.revision = 2; o.store.update(o.state);
  o.state.ui.queryResults[first.request_id] = { session: "s", request_id: first.request_id,
    outcome: { status: "completed", revision: 1, value: { generation: 1, state: "loaded", rows: [],
      total: 0, next_cursor: null } } };
  o.store.update(o.state); assert.strictEqual(o.sent.length, 2, "stale returned local guards are read again");
  var retry = o.sent[1].payload;
  o.state.ui.queryResults[retry.request_id] = { session: "s", request_id: retry.request_id,
    outcome: { status: "refused", message: "Read unavailable." } };
  o.store.update(o.state); o.store.update(o.state);
  assert.strictEqual(o.sent.length, 2, "the same refusal waits for an explicit retry or changed state");
});
test("a hosted catalog that disconnects drops its shown rows instead of keeping them as current", function () {
  var o = setup(); o.store.update(o.state); o.store.select("p");
  answer(o, "setupResults", { generation: 1, state: "ready" });
  answer(o, "queryResults", { generation: 1, state: "ready", rows: [{ library_id: "one", library_name: "One",
    record_id: "r", snapshot: { id: "r", name: "Public" }, resolution: { outcome: "create", candidates: [] } }],
    total: 1, next_cursor: null });
  o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0] =
    { kind: "materials", state: "ready", generation: 1 };
  o.store.update(o.state);
  assert.strictEqual(o.store.rows.length, 1);
  o.state.sections["ph_composer.library.provider_catalogs"].value[0].catalogs[0] =
    { kind: "materials", state: "unloaded", generation: null };
  o.state.revision = 2; o.store.update(o.state);
  assert.strictEqual(o.store.rows.length, 0);
  assert.strictEqual(o.store.page.state, "unloaded");
});
