"use strict";
var assert = require("assert"), test = require("node:test"), dom = require("./support/dom_stub"),
  source = require("./support/panel_source");
function setup(setupState) {
  var context = { document: dom.buildDocument(""), Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context; dom.attachEvents(context);
  var modules = source.start(context, ["library/setup"]), sent = [];
  var dialog = new modules["library/setup"]("session", function (type, payload) {
    sent.push({ type: type, payload: payload });
  }, function () {});
  context.document.body.appendChild(dialog.root);
  dialog.refresh({ session: "session", revision: 1, ui: { queryResults: {}, setupResults: {} }, sections: {
    "ph_composer.library.provider_catalogs": { status: "completed", value: [] },
    "ph_composer.library.provider_setup": { status: "completed", value: { state: setupState } } } });
  return { dialog: dialog, sent: sent };
}
test("an unreadable setup offers only Reset, which sends the reset setup command", function () {
  var o = setup("unreadable");
  assert.strictEqual(o.dialog.unreadableNotice.hidden, false);
  assert.ok(o.dialog.file.disabled && o.dialog.folder.disabled);
  assert.ok(!o.dialog.list.textContent.includes("No libraries configured."));
  o.dialog.reset.dispatchEvent({ type: "click" });
  assert.deepStrictEqual(o.sent.map(function (item) { return [item.type, item.payload.name]; }),
    [["setup.invoke", "ph_composer.library.providers.reset"]]);
});
test("a readable setup hides the reset notice and allows adding", function () {
  var o = setup("readable");
  assert.strictEqual(o.dialog.unreadableNotice.hidden, true);
  assert.ok(!o.dialog.file.disabled && !o.dialog.folder.disabled);
});
function withLocations(locations, listingState) {
  var o = setup("readable");
  o.state = { session: "session", revision: 1, ui: { queryResults: {}, setupResults: {} }, sections: {
    "ph_composer.library.provider_catalogs": { status: "completed", value: [] },
    "ph_composer.library.provider_setup": { status: "completed", value: { state: "readable" } },
    "ph_composer.locations.approved": { status: "completed",
      value: { state: listingState || "readable", locations: locations } } } };
  o.dialog.refresh(o.state);
  return o;
}
var LOCATION = { id: "location_AAAAAAAAAAAA", kind: "save_file", label: "Library export", use: "reusable",
  approved_at: "2026-10-03T12:00:00Z", last_used_at: null, available: false };
function allText(node) {
  var text = [node.textContent];
  dom.walk(node, function (child) { if (child !== node) text.push(child.textContent); });
  return text.join(" ");
}
function plain(value) { return JSON.parse(JSON.stringify(value)); }
function named(root, label) {
  return root.querySelectorAll("button").find(function (button) {
    return button.getAttribute("aria-label") === label || button.textContent === label;
  });
}
test("approved locations list by label with kind and state, never a path, and approve through the host", function () {
  var o = withLocations([LOCATION]);
  var text = allText(o.dialog.locations.list);
  assert.ok(text.includes("Library export") && text.includes("Export destination") && text.includes("not used yet"));
  assert.ok(text.includes("No longer there as approved"));
  named(o.dialog.locations.root, "Approve folder…").dispatchEvent({ type: "click" });
  var sent = o.sent.map(function (item) { return [item.type, item.payload.name, item.payload.params]; });
  assert.deepStrictEqual(plain(sent), [["setup.invoke", "ph_composer.locations.approve_folder", {}]]);
  assert.ok(o.dialog.cancel.disabled);
});
test("rename applies on Enter and revoke asks once before it sends", function () {
  var o = withLocations([LOCATION]);
  named(o.dialog.locations.root, "Rename Library export").dispatchEvent({ type: "click" });
  var input = o.dialog.locations.list.querySelector("input");
  input.value = "Project export";
  input.dispatchEvent({ type: "keydown", key: "Enter", preventDefault: function () {} });
  assert.deepStrictEqual(plain(o.sent[0].payload), { request_id: o.sent[0].payload.request_id, session: "session",
    name: "ph_composer.locations.rename", params: { id: LOCATION.id, label: "Project export" } });
  o.state.ui.setupResults[o.sent[0].payload.request_id] = { request_id: o.sent[0].payload.request_id,
    session: "session", outcome: { status: "completed", value: LOCATION } };
  o.dialog.refresh(o.state);
  named(o.dialog.locations.root, "Revoke Library export").dispatchEvent({ type: "click" });
  assert.strictEqual(o.sent.length, 1);
  named(o.dialog.locations.root, "Confirm revoke Library export").dispatchEvent({ type: "click" });
  assert.deepStrictEqual(plain([o.sent[1].payload.name, o.sent[1].payload.params]),
    ["ph_composer.locations.revoke", { id: LOCATION.id }]);
});
test("an unreadable store offers only Reset approved locations", function () {
  var o = withLocations([], "unreadable");
  assert.strictEqual(o.dialog.locations.unreadableNotice.hidden, false);
  assert.ok(o.dialog.locations.approvals.every(function (button) { return button.disabled; }));
  o.dialog.locations.reset.dispatchEvent({ type: "click" });
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.locations.reset");
});
test("a refresh while renaming keeps the typed name, its focus and caret, and sends nothing", function () {
  var o = withLocations([LOCATION]), list = o.dialog.locations.list, rebuild = list.replaceChildren;
  // Chrome blurs the focused field while the list it sits in is rebuilt, before the field is detached.
  list.replaceChildren = function () {
    var input = list.querySelector("input");
    if (input && input.isConnected) input.dispatchEvent({ type: "blur", target: input });
    return rebuild.apply(this, arguments);
  };
  named(o.dialog.locations.root, "Rename Library export").dispatchEvent({ type: "click" });
  var input = list.querySelector("input");
  input.value = "Half typ"; input.setSelectionRange(8, 8);
  o.dialog.refresh(o.state);
  var again = list.querySelector("input");
  assert.strictEqual(again, input);
  assert.deepStrictEqual([again.value, again.selectionStart, again.selectionEnd], ["Half typ", 8, 8]);
  assert.strictEqual(o.sent.length, 0);
  again.dispatchEvent({ type: "keydown", key: "Enter", preventDefault: function () {} });
  assert.deepStrictEqual(plain([o.sent[0].payload.name, o.sent[0].payload.params]),
    ["ph_composer.locations.rename", { id: LOCATION.id, label: "Half typ" }]);
});
test("with no library yet the two ways to add one show at once and adding is the only primary job", function () {
  var o = setup("readable");
  assert.strictEqual(o.dialog.routes.hidden, false);
  assert.strictEqual(o.dialog.add.hidden, true, "nothing to fold the choice behind yet");
  assert.strictEqual(o.dialog.cancel.textContent, "Done");
  assert.strictEqual(o.dialog.cancel.classList.contains("primary"), false);
  assert.strictEqual(o.dialog.agentAccess.tagName, "details", "agent access is folded away beneath");
});
test("an added library is named and marked, its choice folds away, and Done becomes the next step", function () {
  var o = setup("readable");
  o.dialog.file.dispatchEvent({ type: "click" });
  var request = o.sent[0].payload;
  assert.strictEqual(request.name, "ph_composer.library.providers.add_file");
  assert.ok(/window that opened/.test(o.dialog.error.textContent), "the picker is the host's; the dialog says so");
  var added = { id: "lib_a", label: "Office library", provider_kind: "ph_composer.library.file" };
  o.dialog.refresh({ session: "session", revision: 2, ui: { queryResults: {}, setupResults: (function () {
    var results = {};
    results[request.request_id] = { request_id: request.request_id, session: "session",
      outcome: { status: "completed", value: [added] } };
    return results;
  }()) }, sections: {
    "ph_composer.library.provider_catalogs": { status: "completed", value: [added] },
    "ph_composer.library.provider_setup": { status: "completed", value: { state: "readable" } } } });
  assert.ok(/^Added Office library\./.test(o.dialog.error.textContent));
  assert.ok(o.dialog.list.querySelector(".is-added"), "the new library is marked in the list");
  assert.deepStrictEqual([o.dialog.routes.hidden, o.dialog.add.hidden], [true, false]);
  assert.strictEqual(o.dialog.cancel.classList.contains("primary"), true);
  o.dialog.add.dispatchEvent({ type: "click" });
  assert.strictEqual(o.dialog.routes.hidden, false, "Add a library… opens the choice again");
});
test("picking a library already in the list says so instead of saying nothing", function () {
  var o = setup("readable"), lib = { id: "lib_a", label: "Office library", provider_kind: "ph_composer.library.file" };
  var sections = {
    "ph_composer.library.provider_catalogs": { status: "completed", value: [lib] },
    "ph_composer.library.provider_setup": { status: "completed", value: { state: "readable" } } };
  o.dialog.refresh({ session: "session", revision: 2, ui: { queryResults: {}, setupResults: {} }, sections: sections });
  o.dialog.choosing = true; o.dialog.paint();
  o.dialog.file.dispatchEvent({ type: "click" });
  var request = o.sent[0].payload, results = {};
  results[request.request_id] = { request_id: request.request_id, session: "session",
    outcome: { status: "completed", value: [lib] } };
  o.dialog.refresh({ session: "session", revision: 3, ui: { queryResults: {}, setupResults: results },
    sections: sections });
  assert.strictEqual(o.dialog.error.textContent, "That library is already in the list.");
  assert.strictEqual(o.dialog.list.querySelector(".is-added"), null);
});
function withConnections(connections, providers) {
  var o = setup("readable");
  o.dialog.refresh({ session: "session", revision: 1, ui: { queryResults: {}, setupResults: {} }, sections: {
    "ph_composer.library.provider_catalogs": { status: "completed", value: providers || [] },
    "ph_composer.library.provider_setup": { status: "completed", value: { state: "readable" } },
    "ph_composer.library.connection_states": { status: "completed", value: connections } } });
  return o;
}
var HOSTED = { provider_kind: "test.hosted.library", label: "Hosted library", state: "disconnected",
  lifecycle: ["connect", "disconnect", "reauthorize", "settings"] };
test("a hosted library shows its state and offers the lifecycle actions that fit it, with Remove", function () {
  var o = withConnections([HOSTED], [{ id: "hosted.firm", provider_kind: "test.hosted.library", label: "Firm",
    kinds: ["materials"], catalogs: [] }]);
  var text = allText(o.dialog.list);
  assert.ok(text.includes("Hosted library") && text.includes("Not connected"));
  assert.ok(!text.includes("Added by another tool") && !text.includes("Firm"));
  assert.ok(named(o.dialog.list, "Connect Hosted library"));
  assert.ok(!named(o.dialog.list, "Disconnect Hosted library"));
  named(o.dialog.list, "Connect Hosted library").dispatchEvent({ type: "click" });
  assert.deepStrictEqual(o.sent.map(function (item) { return [item.payload.name, plain(item.payload.params)]; }),
    [["ph_composer.library.connections.connect", { provider_kind: "test.hosted.library" }]]);
});
test("a hosted library that must sign in again offers Reconnect and Disconnect; Remove is not file-gated",
  function () {
  var o = withConnections([Object.assign({}, HOSTED, { state: "reauthorization_required" })]);
  assert.ok(allText(o.dialog.list).includes("Sign in again"));
  assert.ok(named(o.dialog.list, "Reconnect Hosted library") && named(o.dialog.list, "Disconnect Hosted library"));
  assert.ok(!named(o.dialog.list, "Connect Hosted library"));
  named(o.dialog.list, "Remove Hosted library").dispatchEvent({ type: "click" });
  assert.deepStrictEqual(o.sent.map(function (item) { return item.payload.name; }),
    ["ph_composer.library.connections.remove"]);
});
test("a hosted library offers only the lifecycle actions it declares", function () {
  var o = withConnections([Object.assign({}, HOSTED, { state: "connected", lifecycle: ["connect"] })]);
  assert.ok(allText(o.dialog.list).includes("Connected"));
  assert.ok(!named(o.dialog.list, "Disconnect Hosted library") && !named(o.dialog.list, "Settings… Hosted library"));
  assert.ok(named(o.dialog.list, "Remove Hosted library"));
});
