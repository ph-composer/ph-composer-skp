"use strict";
var assert = require("assert"), test = require("node:test"), dom = require("./support/dom_stub"),
  source = require("./support/panel_source");
function setup(resolution) {
  var context = { document: dom.buildDocument(""), Intl: Intl, setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context; dom.attachEvents(context);
  var modules = source.start(context, ["library/copy"]), sent = [];
  var copy = new modules["library/copy"]("s", function (type, payload) { sent.push({ type: type, payload: payload }); },
    { properties: [] }, function () {});
  context.document.body.appendChild(copy.root);
  var row = { values: { name: "Public" }, display_label: "Public", resolution: resolution,
    library: { provider_id: "p", kind: "materials", generation: 2, library_id: "lib", record_id: "r" } };
  return { copy: copy, row: row, sent: sent, context: context };
}
test("create freezes provider generation and full target in exactly one action", function () {
  var o = setup({ outcome: "create", candidates: [] }), target = { id: "assembly", layer_id: "l", segment_id: "s",
    expected_values: { layers: [{ id: "l", thickness_mm: 140 }] } };
  o.copy.use(o.row, target); target.expected_values.layers[0].thickness_mm = 999;
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.params.assignment.expected_values.layers[0].thickness_mm, 140);
  assert.strictEqual(o.sent[0].payload.params.generation, 2);
  assert.strictEqual(o.sent[0].payload.params.choice, "create");
  o.copy.use(o.row, target); assert.strictEqual(o.sent.length, 1);
});
test("ambiguous candidates require explicit choice, review library update carries complete raw guard", function () {
  var candidates = [{ id: "a", display_label: "First", expected_values: { name: "First", optional: null },
    differences: [{ field: "name", local: "First", incoming: "Public", local_present: true, incoming_present: true }] },
  { id: "b", display_label: "Second", expected_values: { name: "Second" }, differences: [] }];
  var o = setup({ outcome: "ambiguous_name", candidates: candidates }); o.copy.use(o.row);
  assert.strictEqual(o.sent.length, 0); assert.strictEqual(o.copy.libraryButton.disabled, true);
  o.copy.candidates.value = "a"; o.copy.candidates.listeners.change({}); o.copy.apply("use_library");
  assert.strictEqual(o.sent.length, 1);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.expected_values)),
    { name: "First", optional: null });
});
test("Cancel and retained callbacks after dispose never send, even when a dialog was open", function () {
  var o = setup({ outcome: "review_required", candidates: [{ id: "a", display_label: "First", expected_values: {},
    differences: [] }] });
  o.copy.use(o.row); o.copy.cancel.listeners.click({}); assert.strictEqual(o.sent.length, 0);
  o.copy.use(o.row); o.copy.dispose(); o.copy.apply("keep_local"); o.copy.use(o.row);
  assert.strictEqual(o.sent.length, 0);
});
test("a name-free kind's review title and local choices read the declared label", function () {
  var o = setup({ outcome: "ambiguous_source", candidates: [
    { id: "a", display_label: "Wall tag", expected_values: {}, differences: [] },
    { id: "b", display_label: null, expected_values: {}, differences: [] }] });
  o.row.values = { designation: "Wall tag" }; o.row.display_label = "Wall tag";
  o.copy.use(o.row);
  assert.strictEqual(o.copy.title.textContent, "Review Wall tag");
  assert.deepStrictEqual(o.copy.candidates.children.map(function (option) { return option.textContent; }),
    ["Choose a local copy…", "Wall tag", "Unlabelled"]);
  assert.deepStrictEqual(o.copy.candidates.children.map(function (option) { return option.value; }), ["", "a", "b"]);
});
test("same-label candidates stay distinguishable without showing record keys", function () {
  var o = setup({ outcome: "ambiguous_name", candidates: [
    { id: "mat_private_a", display_label: "Insulation", expected_values: {}, differences: [] },
    { id: "mat_private_b", display_label: "Insulation", expected_values: {}, differences: [] }] });
  o.copy.open(o.row);
  assert.deepStrictEqual(o.copy.candidates.children.slice(1).map(function (option) { return option.textContent; }),
    ["Insulation (local copy 1)", "Insulation (local copy 2)"]);
  o.copy.candidates.value = "mat_private_b"; o.copy.apply("keep_local");
  assert.strictEqual(o.sent[0].payload.params.local_id, "mat_private_b");
});
test("equal link counts still show the destinations that replacement changes", function () {
  var o = setup({ outcome: "review_required", candidates: [{ id: "local", display_label: "Insulation",
    expected_values: {}, differences: [{ field: "datasheet_links", local_present: true, incoming_present: true,
      local: ["https://example.com/local.pdf"], incoming: ["https://example.com/revised.pdf"] }] }] });
  o.copy.open(o.row);
  assert.strictEqual(o.copy.comparison.querySelector(".phc-property-value").textContent,
    "https://example.com/local.pdf / https://example.com/revised.pdf");
});
test("an empty authored guard still allows replacement; a missing one does not", function () {
  var o = setup({ outcome: "review_required",
    candidates: [{ id: "a", display_label: null, expected_values: {}, differences: [] }] });
  o.copy.open(o.row);
  assert.strictEqual(o.copy.libraryButton.disabled, false);
  var missing = setup({ outcome: "review_required",
    candidates: [{ id: "a", display_label: null, differences: [] }] });
  missing.copy.open(missing.row);
  assert.strictEqual(missing.copy.libraryButton.disabled, true);
});
