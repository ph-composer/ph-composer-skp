"use strict";

/* The panel page as one client: what it renders from a snapshot, what it sends, and what it refuses to
   paint. Each case builds a fresh page from the shipped index.html, so no state crosses cases. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/inventory_fixtures");

function page(extra) {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "sections/export", "request"].concat(extra || []));
  var panel = modules.panel;
  return {
    context: context, modules: modules, panel: panel, sent: sent,
    receive: function (type, payload) { panel.receive({ type: type, payload: payload }); },
    query: function (selector) { return context.document.querySelector(selector); },
    notice: function () { return context.document.querySelector(".phc-floating-notice"); }
  };
}

function snapshot(session, revision, extra) {
  return Object.assign({
    product: "PH-Composer", version: "0.1.0-dev", session: session, revision: revision, file_name: "house.skp",
    edit_path: [], sections: {},
    preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } }
  }, extra || {});
}

function types(sent) { return sent.map(function (message) { return message.type; }); }

test("query results stay keyed, reject another session and clear on Model switch", function () {
  var p = page(); p.receive("panel.snapshot", snapshot("session-a", 7));
  p.receive("query.result", { request_id: "q1", session: "session-a", outcome: { status: "completed", value: [] } });
  p.receive("query.result", { request_id: "q2", session: "session-b", outcome: { status: "completed" } });
  assert.strictEqual(p.panel.state.ui.queryResults.q1.request_id, "q1");
  assert.strictEqual(p.panel.state.ui.queryResults.q2, undefined);
  assert.strictEqual(p.panel.state.ui.actionResult, null);
  p.receive("panel.snapshot", snapshot("session-b", 1));
  assert.deepStrictEqual(Object.keys(p.panel.state.ui.queryResults), []);
});

test("file export results reject another Model and clear on Model switch", function () {
  var p = page(); p.receive("panel.snapshot", snapshot("session-a", 7));
  p.receive("file_export.result", { request_id: "f1", session: "session-a", outcome: { status: "cancelled" } });
  p.receive("file_export.result", { request_id: "f2", session: "session-b", outcome: { status: "completed" } });
  assert.strictEqual(p.panel.state.ui.fileExportResults.f1.request_id, "f1");
  assert.strictEqual(p.panel.state.ui.fileExportResults.f2, undefined);
  assert.strictEqual(p.panel.state.ui.actionResult, null);
  assert.strictEqual(p.panel.state.revision, 7);
  p.receive("panel.snapshot", snapshot("session-b", 1));
  assert.deepStrictEqual(Object.keys(p.panel.state.ui.fileExportResults), []);
});

test("ready asks for the first snapshot, which fills the status bar", function () {
  var p = page();
  p.panel.ready();
  assert.deepStrictEqual(types(p.sent), ["panel.ready"]);

  p.receive("panel.snapshot", snapshot("session-a", 3, { edit_path: ["Level 1", ""] }));

  var footer = p.query("[data-section='footer']").children;
  assert.deepStrictEqual(footer.map(function (node) {
    return node.children.length ? node.children.map(function (child) { return child.textContent; }).join("") :
      node.textContent;
  }),
    ["PH-Composer 0.1.0-dev", "Editing: Level 1 / Unnamed group", "Help & Diagnostics"]);
  footer[2].listeners.click({});
  assert.deepStrictEqual(p.sent[p.sent.length - 1], { type: "panel.support", payload: { incident: null } });
});

test("opening Export reads preflight and retained tasks without starting a write", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 1));
  p.query("[data-tab='export']").listeners.click({});

  assert.strictEqual(p.query("[data-pane='export']").hidden, false);
  assert.strictEqual(p.query("[data-pane='overview']").hidden, true);
  assert.strictEqual(p.query("[data-tab='export']").getAttribute("aria-pressed"), "true");
  assert.strictEqual(p.query("[data-section='export']").querySelector("h1").textContent, "Export");
  assert.deepStrictEqual(types(p.sent), ["export.preflight", "export.latest"]);
});

test("an action names the shown session and the revision the panel last rendered", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 7));
  var channel = p.modules.request.channel("session-a", p.panel.send, "edit");
  var id = channel.run("example.foundation.update_parts", { edits: [] });

  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent)), [{ type: "action.invoke", payload: {
    request_id: id, session: "session-a", name: "example.foundation.update_parts", params: { edits: [] },
    expected_revision: 7 } }]);
});

test("Cmd+Z and Cmd+Shift+Z step SketchUp's Undo and Redo unless a text field is being edited", function () {
  var p = page(), body = p.context.document.body;
  function key(target, init) {
    var event = Object.assign({ type: "keydown", target: target, prevented: false,
      preventDefault: function () { this.prevented = true; } }, init);
    p.context.document.dispatchEvent(event);
    return event;
  }
  key(body, { key: "z", metaKey: true });
  assert.deepStrictEqual(types(p.sent), [], "no Model shown, nothing sent");
  p.receive("panel.snapshot", snapshot("session-a", 7));
  assert.strictEqual(key(body, { key: "z", metaKey: true }).prevented, true);
  key(body, { key: "z", metaKey: true, shiftKey: true });
  key(body, { key: "y", ctrlKey: true });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent)), [
    { type: "panel.undo", payload: { session: "session-a" } },
    { type: "panel.redo", payload: { session: "session-a" } },
    { type: "panel.redo", payload: { session: "session-a" } }]);
  var field = p.context.document.createElement("input");
  field.type = "text";
  assert.strictEqual(key(field, { key: "z", metaKey: true }).prevented, false, "the field keeps its own undo");
  field.readOnly = true;
  key(field, { key: "z", metaKey: true });
  assert.strictEqual(p.sent.length, 4, "a read-only cell at rest passes the shortcut on");
  var modal = p.context.document.createElement("dialog");
  modal.open = true;
  body.appendChild(modal);
  key(body, { key: "z", metaKey: true });
  assert.strictEqual(p.sent.length, 4, "an open dialog's draft keeps the revision it read");
});

test("a snapshot of no Model hides the panes behind one line, and window focus asks the host to catch up", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 7, { edit_path: ["Zone 1"] }));
  assert.strictEqual(p.query(".panel-panes").hidden, false);
  p.receive("panel.snapshot", snapshot(null, null, { file_name: null }));
  var note = p.query(".phc-no-model");
  assert.strictEqual(note.hidden, false);
  assert.strictEqual(note.textContent, "No Model is active. Click a SketchUp document window to show it here.");
  assert.strictEqual(p.query(".panel-panes").hidden, true);
  assert.deepStrictEqual(p.query("[data-section='footer']").children.map(function (span) { return span.textContent; })
    .slice(1, 2), ["Editing: Model"], "the status bar no longer names the closed Model's open group");
  p.receive("panel.snapshot", snapshot("session-b", 2));
  assert.strictEqual(note.hidden, true);
  assert.strictEqual(p.query(".panel-panes").hidden, false);
  p.context.dispatchEvent({ type: "focus" });
  assert.deepStrictEqual(types(p.sent).slice(-1), ["panel.focus"]);
});

test("a dialog the closed Model's screen held open closes when no Model is active", function () {
  var p = page(["overlay"]);
  p.receive("panel.snapshot", snapshot("session-a", 7));
  var dialog = p.modules.overlay.formDialog("held-form", function () {});
  p.context.document.body.appendChild(dialog);
  dialog.openModal();
  assert.strictEqual(dialog.hidden, false);
  p.receive("panel.snapshot", snapshot(null, null, { file_name: null }));
  assert.strictEqual(dialog.hidden, true, "its Save could only reach a session that is gone");
});

test("a refusal stays on screen as a warning and a failure as an error, until dismissed", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 7));
  p.receive("action.result", { request_id: "r1", session: "session-a", outcome: {
    status: "refused", code: "revision.stale", message: "The Model changed. Nothing was written." } });

  var notice = p.notice();
  assert.strictEqual(notice.hidden, false);
  assert.strictEqual(notice.message.textContent, "The Model changed. Nothing was written.");
  assert.strictEqual(notice.getAttribute("data-tone"), "warning");
  assert.strictEqual(notice.getAttribute("data-persistent"), "true");
  assert.strictEqual(p.panel.state.ui.actionResult.request_id, "r1", "the owning view can read the outcome");

  p.receive("action.result", { request_id: "r2", session: "session-a", outcome: {
    status: "failed", code: "operation.failed", message: "The change could not be completed." } });
  assert.strictEqual(notice.getAttribute("data-tone"), "error");
  notice.dismissButton.listeners.click({});
  assert.strictEqual(notice.hidden, true);
});

function timedPage() {
  var p = page(), timers = [];
  p.context.setTimeout = function (run) { timers.push(run); return timers.length; };
  p.context.clearTimeout = function () {};
  p.timers = timers;
  p.recovery = function () { return p.query(".phc-recovery"); };
  p.receive("panel.snapshot", snapshot("session-a", 4));
  return p;
}
function recoveryButton(p, index) {
  return p.recovery().children[index || 0].children[1];
}

test("an unconfirmed change shows Check status, which asks the host and goes when answered", function () {
  var p = timedPage();
  var channel = p.modules.request.channel("session-a", p.panel.send, "form");
  var id = channel.run("example.create", {});

  p.timers[0]();
  assert.strictEqual(p.recovery().hidden, false);
  assert.match(p.recovery().children[0].children[0].textContent, /not confirmed this change yet/);
  assert.strictEqual(p.recovery().getAttribute("data-tone"), "warning");
  assert.strictEqual(recoveryButton(p).textContent, "Check status");

  recoveryButton(p).listeners.click({});
  assert.deepStrictEqual(types(p.sent), ["action.invoke", "action.status"], "the change is never resent");
  assert.strictEqual(p.sent[1].payload.request_id, id);

  p.receive("action.result", { request_id: id, session: "session-a",
    outcome: { status: "completed", effect: "committed" } });
  assert.strictEqual(channel.consume(p.panel.state).status, "completed");
  p.panel.repaint();
  assert.strictEqual(p.recovery().hidden, true, "the answer takes the way out away");
});

test("the way out survives other notices and stays one per unanswered request", function () {
  var p = timedPage();
  var form = p.modules.request.channel("session-a", p.panel.send, "form");
  var catalog = p.modules.request.channel("session-a", p.panel.send, "catalog", "query.invoke");
  form.run("example.create", {});
  catalog.run("example.catalog", {});
  p.timers[0](); p.timers[1]();

  p.panel.notify("Something else happened.", "warning");
  p.receive("panel.notice", { session: "session-a", message: "And another thing.", tone: "info" });
  assert.strictEqual(p.recovery().hidden, false);
  assert.deepStrictEqual(p.recovery().children.map(function (row) { return row.children[1].textContent; }),
    ["Check status", "Stop waiting"]);
});

test("the way out shows inside an open form, where it can be reached", function () {
  var p = timedPage();
  var form = p.modules.workspace.formDialog("example-form", function () { form.closeModal(); });
  p.context.document.body.appendChild(form);
  form.openModal();
  var channel = p.modules.request.channel("session-a", p.panel.send, "form");
  channel.run("example.create", {});

  p.timers[0]();
  assert.strictEqual(p.recovery().parentNode, form);
  form.closeModal();
  assert.notStrictEqual(p.recovery().parentNode, form, "back above the page as the form closes, with no render");
  form.openModal();
  assert.strictEqual(p.recovery().parentNode, form, "and into a form as it opens");
});

test("a way out acts only on the request that raised it", function () {
  var p = timedPage();
  var channel = p.modules.request.channel("session-a", p.panel.send, "catalog", "query.invoke");
  var first = channel.run("example.catalog", {});
  p.timers[0]();
  var stale = recoveryButton(p);

  p.receive("query.result", { request_id: first, session: "session-a", outcome: { status: "completed" } });
  channel.consume(p.panel.state);
  channel.run("example.catalog", {});
  stale.listeners.click({});
  assert.strictEqual(channel.busy(), true, "the old way out never drops the newer request");
});

test("an unconfirmed read offers only to stop waiting, which frees its view", function () {
  var p = timedPage();
  var channel = p.modules.request.channel("session-a", p.panel.send, "catalog", "query.invoke");
  channel.run("example.catalog", {});

  p.timers[0]();
  assert.strictEqual(recoveryButton(p).textContent, "Stop waiting");
  recoveryButton(p).listeners.click({});
  assert.strictEqual(p.recovery().hidden, true);
  assert.strictEqual(channel.consume(p.panel.state).code, "request.abandoned", "its owner settles it as unknown");
  assert.strictEqual(channel.busy(), false);
  assert.deepStrictEqual(types(p.sent), ["query.invoke"]);
});

test("a view result settles in its own slot and says why the viewport did not change", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 7));
  p.receive("view.result", { request_id: "v1", session: "session-a", outcome: {
    status: "completed", value: { found: 4, missing: 0 } } });

  assert.strictEqual(p.panel.state.ui.viewResults.v1.request_id, "v1");
  assert.strictEqual(p.panel.state.ui.actionResult, null, "a view command is not an edit");
  assert.strictEqual(p.notice().hidden, true, "a viewport change that worked says nothing");

  p.receive("view.result", { request_id: "v2", session: "session-a", outcome: {
    status: "refused", code: "validation.failed", message: "There is no Colour-by mode named that." } });
  assert.strictEqual(p.notice().message.textContent, "There is no Colour-by mode named that.");
  assert.strictEqual(p.notice().getAttribute("data-tone"), "warning");
});

test("a result or notice for another Model is not painted, and a new Model clears the old one's", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 7));
  p.receive("action.result", { request_id: "r1", session: "session-b", outcome: { status: "refused", message: "x" } });
  p.receive("panel.notice", { session: "session-b", message: "Elsewhere.", tone: "warning" });
  assert.strictEqual(p.panel.state.ui.actionResult, null);
  assert.strictEqual(p.notice().hidden, true);

  p.receive("panel.notice", { session: "session-a", message: "Checked 4 parts.", tone: "info" });
  assert.strictEqual(p.notice().hidden, false);
  p.receive("panel.snapshot", snapshot("session-b", 1, { file_name: "other.skp" }));
  assert.strictEqual(p.notice().hidden, true, "the other Model's notice is gone");
  assert.strictEqual(p.panel.state.file_name, "other.skp");
});

test("the unit switch applies at once, is remembered by the host, and never becomes a Model action", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 7));
  var seen = [];
  p.modules.unit_preferences.subscribe(function (profile) { seen.push(profile.unitSystem); });

  p.query("[data-unit-system='IP']").listeners.click({});

  assert.deepStrictEqual(seen, ["IP"]);
  assert.strictEqual(p.query("[data-unit-system='IP']").getAttribute("aria-pressed"), "true");
  assert.deepStrictEqual(types(p.sent), ["preferences.set"]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(p.sent[0].payload)),
    { request_id: "preferences:1", key: "unit_system", value: "IP" });

  p.query("[data-unit-system='IP']").listeners.click({});
  assert.strictEqual(p.sent.length, 1, "choosing the current system sends nothing");
});

test("a refused preference restores the previous value and says why", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 7));
  p.panel.setPreference("dimension_format", "cm", { scope: "example.editor", system: "SI" });
  assert.strictEqual(p.modules.unit_preferences.dimensionFormat("example.editor", "SI"), "cm", "applied at once");

  p.receive("preferences.result", { request_id: "preferences:1", status: "refused",
    message: "Too many dimension formats are remembered.",
    preferences: { unit_system: "SI", dimension_formats: {}, number_format: {} } });

  assert.strictEqual(p.modules.unit_preferences.dimensionFormat("example.editor", "SI"), "mm");
  assert.strictEqual(p.notice().message.textContent, "Too many dimension formats are remembered.");
  assert.strictEqual(p.notice().getAttribute("data-tone"), "error");
});

test("a display profile change renders every section once, however many inventories the screens hold", function () {
  var p = page(["library/section", "features/assemblies/section", "features/assemblies/materials",
    "features/zones/attached_zones"]);
  var seen = [];
  p.receive("panel.snapshot", snapshot("session-a", 7, { sections: fixtures.state("session-a").sections }));
  assert.strictEqual(p.query(".phc-inventory-table") !== null, true, "the inventory screens are built");
  // Each render records the unit system it paints with, so a render before the change would show as SI.
  p.panel.section("example.counter", function () { seen.push(p.modules.unit_preferences.current().unitSystem); });

  seen = [];
  p.query("[data-unit-system='IP']").listeners.click({});
  assert.deepStrictEqual(seen, ["IP"], "a unit switch");
  p.receive("preferences.result", { request_id: "preferences:1", status: "completed",
    preferences: { unit_system: "IP", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } });

  seen = [];
  p.receive("panel.snapshot", snapshot("session-a", 8));
  assert.deepStrictEqual(seen, ["SI"], "a snapshot whose stored preferences move the profile back to SI");
});

test("a preference answer renders only when it moves the display or says why it was refused", function () {
  var p = page();
  var seen = [];
  p.receive("panel.snapshot", snapshot("session-a", 7));
  p.panel.section("example.counter", function () { seen.push(p.modules.unit_preferences.current().unitSystem); });
  function stored(system, decimal, locale) {
    return { unit_system: system, dimension_formats: {}, number_format: { decimal: decimal || ".",
      locale: locale || "en-US" } };
  }

  p.panel.setPreference("unit_system", "IP");
  seen = [];
  p.receive("preferences.result", { request_id: "preferences:1", status: "completed", preferences: stored("IP") });
  assert.deepStrictEqual(seen, [], "the confirmation of what is shown changes nothing");

  p.panel.setPreference("unit_system", "SI");
  p.panel.setPreference("unit_system", "IP");
  seen = [];
  p.receive("preferences.result", { request_id: "preferences:2", status: "completed", preferences: stored("SI") });
  assert.deepStrictEqual(seen, [], "an answer to a superseded choice is ignored");
  assert.strictEqual(p.modules.unit_preferences.current().unitSystem, "IP", "the later choice stays shown");
  p.receive("preferences.result", { request_id: "preferences:3", status: "completed", preferences: stored("IP") });
  assert.deepStrictEqual(seen, []);

  p.panel.setPreference("unit_system", "SI");
  seen = [];
  p.receive("preferences.result", { request_id: "preferences:4", status: "completed",
    preferences: stored("SI", ",", "de-DE") });
  assert.deepStrictEqual(seen, ["SI"], "stored preferences that differ from the shown ones repaint once");
  assert.strictEqual(p.modules.unit_preferences.current().numberFormat.decimal, ",");

  p.panel.setPreference("unit_system", "IP");
  seen = [];
  p.receive("preferences.result", { request_id: "preferences:5", status: "refused", message: "Not saved.",
    preferences: stored("SI", ",", "de-DE") });
  assert.deepStrictEqual(seen, ["SI"], "a refusal restores the previous system in one render");
  assert.strictEqual(p.notice().message.textContent, "Not saved.");
});

test("a section registered after start mounts itself in its pane and renders from the current state", function () {
  var p = page();
  var renders = [];
  p.receive("panel.snapshot", snapshot("session-a", 2));
  p.panel.section("example.editor", function (root, state) { renders.push([root.getAttribute("data-section"),
    state.revision]); });

  var root = p.query("[data-section='example.editor']");
  assert.strictEqual(root.parentNode, p.query("[data-pane='overview']"));
  assert.deepStrictEqual(renders, [["example.editor", 2]]);
  p.receive("panel.snapshot", snapshot("session-a", 3));
  assert.deepStrictEqual(renders[1], ["example.editor", 3]);
  assert.throws(function () { p.panel.section("x.y", function () {}, { pane: "nowhere" }); }, /names no pane/);
});

/* REVIEW F02: a render failure went only to the console. */
test("a section that fails to render reports its class and panel frames to the host, never its message", function () {
  var p = page();
  p.panel.section("example.broken", function () {
    var error = new TypeError("Zone North is undefined");
    error.stack = "TypeError: Zone North is undefined\n    at render (file:///Users/example/ph_composer/html/features/x.js:12:3)" +
      "\n    at renderSection (file:///Users/example/ph_composer/html/panel.js:270:13)";
    throw error;
  });
  p.receive("panel.snapshot", snapshot("session-a", 1));
  var reported = p.sent.filter(function (message) { return message.type === "panel.diagnostic"; });
  assert.strictEqual(reported.length, 1);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(reported[0].payload)), {
    event: "panel_render_failed", section: "example.broken", error_class: "TypeError",
    frames: [{ file: "html/features/x.js", line: 12, method: "render" },
      { file: "html/panel.js", line: 270, method: "renderSection" }] });
  assert.ok(JSON.stringify(p.sent).indexOf("Zone North") < 0);
});

test("a blocked load under the page's policy is reported once as a fixed class with no frames", function () {
  var p = page();
  p.context.dispatchEvent({ type: "securitypolicyviolation", violatedDirective: "script-src", blockedURI: "inline" });
  var reported = p.sent.filter(function (message) { return message.type === "panel.diagnostic"; });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(reported)), [{ type: "panel.diagnostic", payload: {
    event: "panel_csp_violation", section: null, error_class: "SecurityPolicyViolation", frames: [] } }]);
});

test("a rejection's own name is never reported as an error class", function () {
  var p = page(), named = new Error("x");
  named.name = "SecretClientHouse";
  var classes = [{ name: "SecretClientHouse", id: "record-1" }, named, new RangeError("y")].map(function (reason) {
    var before = p.sent.length;
    p.panel.section("example.broken" + before, function () { throw reason; });
    p.receive("panel.snapshot", snapshot("session-a", before));
    return p.sent.filter(function (message) { return message.type === "panel.diagnostic"; }).pop().payload.error_class;
  });
  assert.deepStrictEqual(classes, ["NotAnError", "Error", "RangeError"]);
});

test("text in an error's message that looks like a frame is never reported as one", function () {
  var p = page();
  p.panel.section("example.broken", function () {
    var error = new TypeError("bad\n    at secret_model (file:///Users/example/html/client_private.js:12:3)");
    error.stack = String(error) + "\n    at render (file:///Users/example/ph_composer/html/panel.js:5:1)";
    throw error;
  });
  p.receive("panel.snapshot", snapshot("session-a", 1));
  var reported = p.sent.filter(function (message) { return message.type === "panel.diagnostic"; })[0];
  assert.deepStrictEqual(JSON.parse(JSON.stringify(reported.payload.frames)),
    [{ file: "html/panel.js", line: 5, method: "render" }]);
});

test("a failure with an incident reference offers Get help, which opens Help & Diagnostics at it", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 1));
  p.receive("action.result", { request_id: "r1", session: "session-a", outcome: { status: "failed",
    effect: "none", message: "The change could not be prepared. Nothing was written.",
    detail: { incident: "PHC-3FA9C1" } } });

  assert.strictEqual(p.notice().actionButton.textContent, "Get help");
  p.notice().actionButton.listeners.click({});
  assert.deepStrictEqual(p.sent[p.sent.length - 1], { type: "panel.support", payload: { incident: "PHC-3FA9C1" } });
});

test("a failed setup or export with an incident also offers Get help", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 1));
  ["setup.result", "query.result", "file_export.result", "export.result"].forEach(function (type, index) {
    p.panel.notify("", "info"); p.panel.state.ui.notice = null;
    p.receive(type, { request_id: "r" + index, session: "session-a", outcome: { status: "failed", effect: "none",
      message: "That could not be done.", detail: { incident: "PHC-00000" + index } } });
    assert.strictEqual(p.panel.state.ui.notice.action.label, "Get help", type);
  });
});

test("a host failure is shown as an error; an unknown message type changes nothing", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 2));
  var before = p.panel.state;
  p.receive("not.a.type", {});
  assert.strictEqual(p.panel.state, before);
  p.receive("panel.failure", { message: "The panel message is not JSON." });
  assert.strictEqual(p.notice().getAttribute("data-tone"), "error");
});

test("a section that throws does not hide the refusal warning or stop the other sections", function () {
  var p = page(), later = [];
  p.receive("panel.snapshot", snapshot("session-a", 2));
  p.context.console = { error: function () {} };
  p.panel.section("broken.section", function () { throw new Error("render bug"); });
  p.panel.section("later.section", function (root, state) { later.push(state.revision); });
  p.receive("action.result", { request_id: "r1", session: "session-a", outcome: {
    status: "refused", code: "revision.stale", message: "The Model changed. Nothing was written." } });

  assert.strictEqual(p.notice().hidden, false);
  assert.strictEqual(p.notice().getAttribute("data-tone"), "warning");
  assert.deepStrictEqual(later, [2, 2]);
  assert.strictEqual(p.panel.state.ui.actionResult.request_id, "r1");
});

test("the current tab is scrolled into view, so a narrow panel never hides which tab is open", function () {
  var p = page(), scrolled = [];
  var tab = p.query("[data-tab='export']");
  tab.scrollIntoView = function (options) { scrolled.push(JSON.parse(JSON.stringify(options))); };
  p.receive("panel.snapshot", snapshot("session-a", 1));
  tab.listeners.click({});
  assert.deepStrictEqual(scrolled[scrolled.length - 1], { block: "nearest", inline: "nearest" });
});

function enterExport(p, findings) {
  p.panel.showTab("export");
  var requests = p.sent.slice(-2);
  p.receive("export.result", { request_id: requests[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { findings: findings || [], repairs: [] } } });
  p.receive("export.result", { request_id: requests[1].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: null } });
  p.sent.length = 0;
}

test("Export lets the user approve a destination for agents and says what the approval allows", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 1));
  enterExport(p, []);
  var pane = p.query("[data-section='export']");
  var allow = pane.querySelectorAll("button").find(function (button) {
    return button.textContent === "Allow agents to export here…";
  });
  allow.listeners.click({}); allow.listeners.click({});
  assert.deepStrictEqual(types(p.sent), ["setup.invoke"], "one approval at a time");
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.locations.approve_destination");
  assert.deepStrictEqual(p.sent[0].payload.params, {});
  p.receive("setup.result", { request_id: p.sent[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { id: "location_AAAAAAAAAAAA", label: "Export destination 1" } } });
  var status = p.query("[data-section='export']").querySelector(".phc-export-status").textContent;
  assert.ok(status.indexOf("Approved Export destination 1.") === 0, status);
  assert.ok(status.indexOf("location_") === -1, "the id is not shown");
  assert.ok(status.indexOf("Extensions > PH-Composer > Libraries") > 0, "it says where to revoke it");
  p.query("[data-section='export']").querySelectorAll("button").find(function (button) {
    return button.textContent === "Allow agents to export here…";
  }).listeners.click({});
  p.receive("setup.result", { request_id: p.sent[1].payload.request_id, session: "session-a",
    outcome: { status: "cancelled", message: "Cancelled. Nothing changed." } });
  assert.ok(p.query("[data-section='export']").querySelector(".phc-export-status").textContent
    .indexOf("Approved Export destination 1.") === 0, "a dismissed dialog changes nothing said");
  p.query("[data-section='export']").querySelectorAll("button").find(function (button) {
    return button.textContent === "Allow agents to export here…";
  }).listeners.click({});
  p.receive("setup.result", { request_id: p.sent[2].payload.request_id, session: "session-a",
    outcome: { status: "refused", code: "location.setup_unreadable",
      message: "This machine's approved locations cannot be read." } });
  assert.strictEqual(p.query("[data-section='export']").querySelector(".phc-export-status").textContent,
    "This machine's approved locations cannot be read.");
});

test("Export asks for one destination and retains a cancellation message", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 4));
  enterExport(p);
  var pane = function () { return p.query("[data-section='export']"); };
  var button = function () { return pane().querySelector("button"); };
  button().listeners.click({});
  button().listeners.click({});
  assert.strictEqual(p.sent.length, 1);
  assert.strictEqual(p.sent[0].type, "export.start");
  assert.deepStrictEqual(p.sent[0].payload.repairs, []);
  var id = p.sent[0].payload.request_id;
  assert.strictEqual(button().disabled, true);
  assert.strictEqual(button().textContent, "Choosing destination…");
  p.receive("export.result", { request_id: id, session: "session-b", outcome: { message: "Other Model." } });
  assert.strictEqual(button().disabled, true);
  p.receive("export.result", { request_id: id, session: "session-a",
    outcome: { status: "cancelled", code: "export.cancelled", message: "Export cancelled. Nothing was written." } });
  assert.strictEqual(button().disabled, false);
  assert.strictEqual(pane().querySelector(".phc-export-status").textContent, "Export cancelled. Nothing was written.");
});

test("a blocked run's report shows collapsed in the Export tab and stays as the user left it", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 4));
  enterExport(p);
  var pane = function () { return p.query("[data-section='export']"); };
  pane().querySelector("button").listeners.click({});
  var html = "<!doctype html><title>Export not created</title>";
  p.receive("export.result", { request_id: p.sent[0].payload.request_id, session: "session-a", outcome: {
    status: "completed", value: { task_id: "task-1", outcome: { status: "refused", code: "export.blocked",
      message: "Export not created. Resolve the blocking findings.", findings: [],
      value: { result: { findings: [] }, report_html: html } } } } });
  var details = pane().querySelector("details");
  assert.ok(details, "the report is offered");
  assert.strictEqual(details.querySelector("summary").textContent, "Last export report");
  var frame = details.querySelector("iframe");
  assert.strictEqual(frame.srcdoc, html);
  assert.strictEqual(frame.getAttribute("sandbox"), "");
  details.open = true;
  p.receive("panel.snapshot", snapshot("session-a", 4));
  assert.strictEqual(pane().querySelector("details"), details, "a repaint keeps the same panel, open");
});

test("a new destination cancellation or refusal stays separate from the previous successful Export", function () {
  ["cancelled", "refused"].forEach(function (status) {
    var p = page();
    p.receive("panel.snapshot", snapshot("session-a", 4));
    enterExport(p);
    var pane = function () { return p.query("[data-section='export']"); };
    pane().querySelector("button").listeners.click({});
    p.receive("export.result", { request_id: p.sent[0].payload.request_id, session: "session-a", outcome: {
      status: "completed", value: { task_id: "previous", outcome: { status: "completed",
        message: "HBJSON and Export report created.", value: { location: { label: "previous.hbjson" },
          result: { canonical_model: { rooms: 2, faces: 12, surface_pairs: 1 },
            findings: [{ message: "Previous run advisory.", code: "previous.advisory" }] } } } } } });
    pane().querySelector("button").listeners.click({});
    var current = status === "cancelled" ? "Export cancelled. Nothing was written." : "Runtime unavailable.";
    p.receive("export.result", { request_id: p.sent[p.sent.length - 1].payload.request_id, session: "session-a",
      outcome: { status: status, message: current, findings: [{ message: "Current request detail." }] } });
    var history = pane().querySelector(".phc-export-last");
    function text(node) { return node.textContent + node.children.map(text).join(""); }
    var historyText = text(history);
    assert.strictEqual(pane().querySelector(".phc-export-status").textContent, current);
    assert.ok(historyText.includes("Last export: HBJSON and Export report created."));
    assert.ok(historyText.includes("2 Rooms · 12 Faces · 1 Surface pair"));
    assert.ok(historyText.includes("Written to previous.hbjson."));
    assert.ok(historyText.includes("Previous run advisory."));
    assert.ok(!historyText.includes(current));
    assert.ok(!historyText.includes("Current request detail."));
    assert.ok(text(pane()).includes("From this request"));
  });
});

test("blocking preflight disables destination selection and preserves its complete findings", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 1));
  enterExport(p, [{ code: "construction.missing", message: "Assign an Assembly.", blocks_export: true }]);
  var pane = p.query("[data-section='export']");
  assert.strictEqual(pane.querySelector("button").disabled, true);
  assert.strictEqual(pane.querySelector(".phc-export-finding").textContent, "Assign an Assembly.");
  assert.strictEqual(pane.querySelector(".phc-export-readiness").textContent, "Finish 1 thing before exporting.");
  pane.querySelector("button").listeners.click({});
  assert.deepStrictEqual(p.sent, []);
});

test("long advisory lists disclose independently of blockers and retain the user's choice within a Model", function () {
  var p = page(), findings = [{ code: "construction.missing", message: "Assign an Assembly.", blocks_export: true }];
  for (var i = 0; i < 6; i += 1) findings.push({ code: "material.optional", blocks_export: false,
    message: "Review properties for Material " + (i + 1) + "." });
  p.receive("panel.snapshot", snapshot("session-a", 1));
  enterExport(p, findings);
  var pane = p.query("[data-section='export']"), details = pane.querySelector(".phc-export-advisories");
  assert.strictEqual(details.open, false);
  assert.strictEqual(details.querySelector("summary").textContent, "Worth checking · 6 findings");
  assert.strictEqual(pane.querySelector(".phc-export-finding").textContent, "Assign an Assembly.");
  assert.strictEqual(details.querySelectorAll("li").length, 6, "no advisory is omitted");
  details.open = true; details.listeners.toggle({});
  function refresh(session, revision) {
    p.receive("panel.snapshot", snapshot(session, revision));
    var request = p.sent.filter(function (message) { return message.type === "export.preflight"; }).pop();
    p.receive("export.result", { request_id: request.payload.request_id, session: session,
      outcome: { status: "completed", value: { findings: findings, repairs: [] } } });
  }
  refresh("session-a", 2);
  assert.strictEqual(p.query(".phc-export-advisories").open, true, "a refreshed check keeps the disclosure open");
  refresh("session-b", 1);
  assert.strictEqual(p.query(".phc-export-advisories").open, false, "another Model starts with its own view state");
});

test("Export states each cause once, without record ids, with one Locate and a way to its tab", function () {
  var p = page(), faces = [1, 2, 3].map(function (n) {
    return { code: "construction.missing", section: "ph_composer.zones.faces", blocks_export: true,
      message: "Face fac_c3d5e3f176e" + n + " needs an authored Assembly.",
      locate: { name: "ph_composer.zones.faces.locate", params: { faces: [{ entity_path: [n] }] } } };
  });
  p.receive("panel.snapshot", snapshot("session-a", 1));
  // A feature says where its records are worked on; Export names no feature itself.
  p.panel.workedOn("ph_composer.zones", "overview");
  assert.strictEqual(p.panel.tabFor("ph_composer.assemblies.export"), null);
  assert.strictEqual(p.panel.tabFor("ph_composer.zones_other.export"), null, "a prefix ends at a dot");
  enterExport(p, faces.concat([{ code: "adjacency.stale", section: "ph_composer.zones", blocks_export: false,
    message: "Adjacency was solved before the last edit." }]));
  var pane = p.query("[data-section='export']"), groups = pane.querySelectorAll(".phc-export-group");
  assert.deepStrictEqual(groups.map(function (group) { return group.querySelector("h2").textContent; }),
    ["Before exporting", "Worth checking"]);
  var rows = groups[0].querySelectorAll("li");
  assert.strictEqual(rows.length, 1, "three Faces with one cause are one row");
  assert.strictEqual(rows[0].querySelector(".phc-export-finding").textContent, "Face needs an authored Assembly.");
  assert.strictEqual(rows[0].querySelector(".phc-export-count").getAttribute("aria-label"), "3 findings");
  assert.ok(rows[0].querySelector(".phc-export-finding").getAttribute("data-tooltip").indexOf("fac_c3d5e3f176e1") === 0,
    "the ids stay in the tooltip");
  assert.strictEqual(pane.querySelector(".phc-export-readiness").textContent, "Finish 1 thing before exporting.");
  var buttons = rows[0].querySelectorAll("button");
  assert.strictEqual(buttons[0].textContent, "Locate all");
  assert.strictEqual(buttons[1].textContent.indexOf("Open "), 0, "named for the tab the feature registered");
  buttons[0].listeners.click({});
  assert.strictEqual(p.sent.length, 1);
  assert.strictEqual(p.sent[0].payload.params.faces.length, 3, "one Locate carries every Face");
  buttons[1].listeners.click({});
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
});

test("Export lists what its line counts after an earlier export, keeps a typed name, and says when ready", function () {
  var p = page(), blocker = { code: "zone.invalid", section: "ph_composer.zones.export.zones",
    object_id: "zon_abcdef123456", blocks_export: true, message: "Zone top_floor12345 has no Faces." };
  p.receive("panel.snapshot", snapshot("session-a", 1));
  p.panel.showTab("export");
  var requests = p.sent.slice(-2);
  p.receive("export.result", { request_id: requests[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { findings: [blocker], repairs: [] } } });
  // The session's last export is still on record and reported the same thing.
  p.receive("export.result", { request_id: requests[1].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { task_id: "task-old", stage: "finished", cancellable: false,
      outcome: { status: "refused", message: "Export blocked.", findings: [blocker] } } } });
  var pane = p.query("[data-section='export']"), groups = pane.querySelectorAll(".phc-export-group");
  assert.strictEqual(pane.querySelector(".phc-export-status").textContent, "Last export: Export blocked.");
  assert.strictEqual(pane.querySelector(".phc-export-readiness").textContent, "Finish 1 thing before exporting.");
  assert.deepStrictEqual(groups.map(function (group) { return group.querySelector("h2").textContent; }),
    ["Before exporting"], "listed once, not again under the last export");
  assert.strictEqual(pane.querySelector(".phc-export-finding").textContent, "Zone top_floor12345 has no Faces.");
  var clean = page();
  clean.receive("panel.snapshot", snapshot("session-a", 1));
  enterExport(clean);
  assert.strictEqual(clean.query("[data-section='export']").querySelector(".phc-export-readiness").textContent,
    "Ready to export.");
});

test("a finished export counts what it wrote in words that agree with the count", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 1));
  p.panel.showTab("export");
  var requests = p.sent.slice(-2);
  p.receive("export.result", { request_id: requests[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { findings: [], repairs: [] } } });
  p.receive("export.result", { request_id: requests[1].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { task_id: "task-done", stage: "finished", cancellable: false,
      outcome: { status: "completed", message: "HBJSON and Export report created.", value: { artifacts: [],
        result: { findings: [], canonical_model: { rooms: 2, faces: 12, surface_pairs: 1 } } } } } } });
  var texts = p.query("[data-section='export']").querySelectorAll("p").map(function (node) {
    return node.textContent; });
  assert.ok(texts.indexOf("2 Rooms · 12 Faces · 1 Surface pair") >= 0, texts.join(" | "));
});

test("running Export remains visible until cancelled and a Model switch drops its handle", function () {
  var p = page();
  p.receive("panel.snapshot", snapshot("session-a", 1));
  enterExport(p);
  p.query("[data-section='export']").querySelector("button").listeners.click({});
  var start = p.sent[0].payload.request_id;
  p.receive("export.result", { request_id: start, session: "session-a", outcome: { status: "completed",
    value: { task_id: "task-a", stage: "reading", cancellable: true, outcome: null } } });
  assert.strictEqual(p.query("[data-section='export']").querySelector(".phc-export-readiness"), null,
    "the active stage replaces Ready to export");
  assert.strictEqual(p.query("[data-section='export']").querySelector(".phc-export-status").textContent,
    "Reading Model…");
  p.panel.showTab("overview");
  assert.strictEqual(p.panel.state.ui.activeTab, "export");
  var buttons = p.query("[data-section='export']").querySelectorAll("button");
  // The header puts Cancel export before the primary action.
  assert.strictEqual(buttons[0].textContent, "Cancel export");
  buttons[0].listeners.click({});
  var cancellation = p.sent[p.sent.length - 1];
  assert.strictEqual(cancellation.type, "export.cancel");
  assert.strictEqual(cancellation.payload.task_id, "task-a");
  p.receive("export.result", { request_id: cancellation.payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { task_id: "task-a", stage: "finished", cancellable: false,
      outcome: { status: "cancelled", message: "Cancelled.", findings: [] } } } });
  p.panel.showTab("overview");
  assert.strictEqual(p.panel.state.ui.activeTab, "overview");
  p.receive("panel.snapshot", snapshot("session-b", 1));
  assert.strictEqual(p.query("[data-section='export']").querySelector(".phc-export-status").textContent, "");
});


test("last-export findings name Materials, Assemblies and Layers without internal validation text", function () {
  var p = page(), findings = require("./fixtures/assemblies/display_findings.json");
  p.receive("panel.snapshot", snapshot("session-a", 1));
  p.panel.showTab("export");
  var requests = p.sent.slice(-2);
  p.receive("export.result", { request_id: requests[0].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { findings: [], repairs: [] } } });
  p.receive("export.result", { request_id: requests[1].payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { task_id: "last", outcome: { status: "completed",
      message: "Export complete.", value: { result: { findings: findings } } } } } });
  var rows = p.query("[data-section='export']").querySelectorAll(".phc-export-finding");
  assert.deepStrictEqual(rows.map(function (row) { return row.textContent; }),
    findings.map(function (finding) { return finding.message; }));
  assert.match(rows[0].textContent, /Two wool thicknesses.*Layer 1/);
  assert.match(rows[1].textContent, /Synthetic defaults.*Default mass/);
  rows.forEach(function (row) {
    assert.doesNotMatch(row.textContent, /mat_|segment material id must be non-empty text/);
  });
});

/* panel.outcomeText: a contributor translator never stands between a result and its requester. */
var results = require("./support/action_results");

function hookPage(extra) {
  var p = page(extra), logged = [];
  p.receive("panel.snapshot", snapshot("session-a", 7));
  p.context.console = { error: function (message) { logged.push(message); } };
  p.logged = logged;
  return p;
}

function requested(p) {
  var channel = p.modules.request.channel("session-a", p.panel.send, "probe");
  return { channel: channel, id: channel.run("example.probe", {}) };
}

test("a throwing translator is skipped, the result settles and a later translator's text shows", function () {
  var p = hookPage(), r = requested(p);
  p.panel.outcomeText(function () { throw new Error("hook bug"); }, { owner: "test.broken" });
  p.panel.outcomeText(function () { return "Said our way."; });
  p.receive("action.result", results.refused(r.id, "session-a", "Host words."));

  assert.strictEqual(p.panel.state.ui.actionResult.request_id, r.id);
  assert.strictEqual(p.notice().message.textContent, "Said our way.");
  assert.strictEqual(r.channel.consume(p.panel.state).status, "refused");
  assert.strictEqual(r.channel.busy(), false);
  assert.strictEqual(r.channel.consume(p.panel.state), null, "consumed once");
  assert.deepStrictEqual(p.logged, ["panel.outcomeText test.broken threw"]);
});

test("when every translator throws or declines, the host message shows with the outcome's tone", function () {
  var p = hookPage();
  p.panel.outcomeText(function () { throw new Error("hook bug"); });
  p.panel.outcomeText(function () { return null; });
  p.receive("action.result", results.refused("r1", "session-a", "Host words."));
  assert.strictEqual(p.notice().message.textContent, "Host words.");
  assert.strictEqual(p.notice().getAttribute("data-tone"), "warning");
  p.receive("action.result", results.failed("r2", "session-a", "It broke."));
  assert.strictEqual(p.notice().message.textContent, "It broke.");
  assert.strictEqual(p.notice().getAttribute("data-tone"), "error");
  assert.strictEqual(p.panel.state.ui.actionResult.outcome.code, "operation.failed", "the outcome is kept whole");
});

test("with no host message and no translator text the generic sentence shows", function () {
  var p = hookPage();
  p.panel.outcomeText(function () { throw new Error("hook bug"); });
  p.receive("action.result", results.refused("r1", "session-a"));
  assert.strictEqual(p.notice().message.textContent, "The change was not applied.");
});

test("declines fall through and non-string answers are skipped, never shown", function () {
  [null, undefined, "", "   ", 42, Promise.resolve("later"), { text: "object" }].forEach(function (answer) {
    var p = hookPage();
    p.panel.outcomeText(function () { return answer; }, { owner: "test.odd" });
    p.receive("action.result", results.refused("r1", "session-a", "Host words."));
    assert.strictEqual(p.notice().message.textContent, "Host words.", String(answer));
    var declined = answer === null || answer === undefined || (typeof answer === "string" && !answer.trim());
    assert.strictEqual(p.logged.length, declined ? 0 : 1, String(answer));
  });
});

test("the first valid text wins and later translators are not called", function () {
  var p = hookPage(), later = 0;
  p.panel.outcomeText(function () { return "First."; });
  p.panel.outcomeText(function () { later += 1; return "Second."; });
  p.receive("action.result", results.refused("r1", "session-a", "Host words."));
  assert.strictEqual(p.notice().message.textContent, "First.");
  assert.strictEqual(later, 0);
});

test("a translator that edits its input changes neither the kept result nor the next input", function () {
  var p = hookPage(), seen = null;
  p.panel.outcomeText(function (result) {
    result.request_id = "forged"; result.session = "session-b"; result.outcome.status = "completed";
    return null;
  });
  p.panel.outcomeText(function (result) { seen = result; return null; });
  p.receive("action.result", results.refused("r1", "session-a", "Host words."));
  assert.deepStrictEqual([seen.request_id, seen.session, seen.outcome.status], ["r1", "session-a", "refused"]);
  var kept = p.panel.state.ui.actionResult;
  assert.deepStrictEqual([kept.request_id, kept.session, kept.outcome.status], ["r1", "session-a", "refused"]);
});

test("completed outcomes and another Model's results never reach a translator", function () {
  var p = hookPage(), calls = 0;
  p.panel.outcomeText(function () { calls += 1; return "No."; });
  p.receive("action.result", results.completed("r1", "session-a"));
  var before = p.panel.state;
  p.receive("action.result", results.refused("r2", "session-b", "Elsewhere."));
  assert.strictEqual(calls, 0);
  assert.strictEqual(p.panel.state, before);
  assert.strictEqual(p.notice().hidden, true);
});

test("a disposer removes only its own translator, keeps order and is safe to call twice", function () {
  var p = hookPage(), calls = [];
  function hook(name) { return function () { calls.push(name); return null; }; }
  p.panel.outcomeText(hook("a"));
  var disposeB = p.panel.outcomeText(hook("b"));
  p.panel.outcomeText(hook("c"));
  disposeB();
  disposeB();
  p.receive("action.result", results.refused("r1", "session-a", "Host words."));
  assert.deepStrictEqual(calls, ["a", "c"]);
});

test("a failed outcome settles its pending form whole, with Cancel usable and no second settlement", function () {
  var p = hookPage(["record_form"]), changed = [];
  var form = new p.modules.record_form(p.panel.state.session, p.panel.send, {
    title: "Probe", action: "example.probe", label: "probe", submitLabel: "Save", pendingText: "Saving...",
    failureText: "Not saved.", dialog: false, changed: function (arg) { changed.push(arg); }
  });
  form.finish();
  form.show();
  p.panel.outcomeText(function () { throw new Error("hook bug"); });
  form.run({});
  var id = p.sent[p.sent.length - 1].payload.request_id;
  var envelope = results.failed(id, "session-a", "It broke.");
  envelope.outcome.effect = "unknown";
  envelope.outcome.value = { partial: true };
  p.receive("action.result", envelope);

  var outcome = form.settle(p.panel.state);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(outcome)), { status: "failed", code: "operation.failed",
    message: "It broke.", effect: "unknown", value: { partial: true } });
  assert.strictEqual(form.busy(), false);
  assert.strictEqual(form.cancel.disabled, false);
  assert.strictEqual(p.notice().getAttribute("data-tone"), "error");
  assert.strictEqual(form.settle(p.panel.state), null, "a repeated render settles nothing more");
  form.cancel.listeners.click({});
  assert.strictEqual(form.root.hidden, true);
});

test("a translator disposed or added during a call changes the next outcome, not the current one", function () {
  var p = hookPage(), calls = [], disposeSelf;
  disposeSelf = p.panel.outcomeText(function () {
    calls.push("self");
    disposeSelf();
    p.panel.outcomeText(function () { calls.push("late"); return null; });
    return null;
  });
  p.panel.outcomeText(function () { calls.push("next"); return "Next."; });
  p.receive("action.result", results.refused("r1", "session-a", "Host words."));
  assert.deepStrictEqual(calls, ["self", "next"]);
  assert.strictEqual(p.notice().message.textContent, "Next.");

  calls.length = 0;
  p.receive("action.result", results.refused("r2", "session-a", "Host words."));
  assert.deepStrictEqual(calls, ["next"], "the disposed translator is gone and the later one is after the winner");
});

test("a missing or throwing console cannot strand the result", function () {
  [undefined, { error: function () { throw new Error("console bug"); } }].forEach(function (console) {
    var p = hookPage(), r = requested(p);
    p.context.console = console;
    p.panel.outcomeText(function () { throw new Error("hook bug"); });
    p.receive("action.result", results.refused(r.id, "session-a", "Host words."));
    assert.strictEqual(p.notice().message.textContent, "Host words.");
    assert.strictEqual(r.channel.consume(p.panel.state).status, "refused");
  });
});

test("a registration without a function or with an empty owner throws and inserts nothing", function () {
  var p = hookPage(), calls = 0;
  assert.throws(function () { p.panel.outcomeText("not a function"); }, /needs a function/);
  assert.throws(function () { p.panel.outcomeText(function () { calls += 1; return "No."; }, { owner: "" }); },
    /owner must be a nonempty string/);
  p.receive("action.result", results.refused("r1", "session-a", "Host words."));
  assert.strictEqual(calls, 0);
  assert.strictEqual(p.notice().message.textContent, "Host words.");
});
