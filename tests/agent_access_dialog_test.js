"use strict";
var assert = require("assert"), test = require("node:test"), fs = require("fs"),
  dom = require("./support/dom_stub"), source = require("./support/panel_source"),
  manifest = require("../tools/panel_manifest");

var TOKEN = { id: "token_AAAAAAAAAAAA", label: "Claude Code", capabilities: ["read"],
  created_at: "2026-10-18T12:00:00Z", last_used_at: null, revoked_at: null };
var REVOKED = { id: "token_BBBBBBBBBBBB", label: "Old Codex", capabilities: ["read"],
  created_at: "2026-10-01T12:00:00Z", last_used_at: "2026-10-02T12:00:00Z", revoked_at: "2026-10-03T12:00:00Z" };

function context() {
  var page = { document: dom.buildDocument(""), Intl: Intl, innerWidth: 560, innerHeight: 600,
    setTimeout: setTimeout, clearTimeout: clearTimeout, navigator: {} };
  page.window = page; dom.attachEvents(page);
  return page;
}
function setup(state) {
  var page = context(), modules = source.start(page, ["agent_access/page"]), sent = [];
  var view = new modules["agent_access/page"].Page(function (type, payload) {
    sent.push({ type: type, payload: payload });
  });
  page.document.body.appendChild(view.root);
  view.receive({ type: "access.state", payload: Object.assign({ state: "readable", tokens: [TOKEN, REVOKED],
    offered: ["read"], server: { state: "stopped" } }, state || {}) });
  return { view: view, sent: sent, page: page };
}
function allText(node) {
  var text = [node.textContent];
  dom.walk(node, function (child) { if (child !== node) text.push(child.textContent); });
  return text.join(" ");
}
function named(root, label) {
  return root.querySelectorAll("button").find(function (button) {
    return button.getAttribute("aria-label") === label || button.textContent === label;
  });
}

test("tokens list by label and access, revoked ones dated and without a Revoke", function () {
  var o = setup(), text = allText(o.view.list);
  assert.ok(text.includes("Claude Code") && text.includes("Read") && text.includes("no calls since SketchUp started"));
  assert.ok(text.includes("Old Codex") && text.includes("revoked"));
  assert.ok(named(o.view.list, "Revoke Claude Code"));
  assert.strictEqual(named(o.view.list, "Revoke Old Codex"), undefined);
  assert.ok(o.view.server.textContent.includes("Not listening"));
  o.view.receive({ type: "access.state", payload: { state: "readable", tokens: [TOKEN], offered: ["read"],
    server: { state: "listening", port: 46110 } } });
  assert.ok(o.view.server.textContent.includes("port 46110"));
  o.view.receive({ type: "access.state", payload: { state: "readable", tokens: [TOKEN], offered: ["read"],
    server: { state: "unavailable", port: 46110, message: "Port 46110 is in use by another program." } } });
  assert.ok(o.view.server.textContent.includes("in use by another program"));
  assert.strictEqual(o.view.portRow.hidden, false);
  assert.ok(o.view.create.disabled, "no token is issued for a port nothing listens on");
  o.view.portInput.value = "47001";
  o.view.portApply.dispatchEvent({ type: "click" });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent)), [{ type: "access.port", payload: { port: 47001 } }]);
});

test("a token's latest call shows its time and how it ended", function () {
  var called = Object.assign({}, TOKEN, { last_call: { at: "2026-10-18T14:02:00Z", status: "refused" } });
  var o = setup({ tokens: [called] });
  assert.ok(allText(o.view.list).includes("last call") && allText(o.view.list).includes("refused"));
});

test("the created token comes with each client's Connect and setup to copy, and none of it outlives the dialog",
  function () {
    var o = setup(), commands = [];
    o.page.document.execCommand = function (name) { commands.push(name); return true; };
    var clients = [{ id: "claude_code", client: "Claude Code",
      forms: [{ title: "What Connect runs", text: "claude mcp add-json ..." },
        { title: "Or, one command", text: "claude mcp add ... " + "ab".repeat(24) }],
      check: "claude mcp get ph-composer", remove: "claude mcp remove ph-composer" }];
    o.view.receive({ type: "access.issued", payload: { token: "ab".repeat(24), row: TOKEN, clients: clients } });
    var fields = o.view.clients.querySelectorAll("textarea");
    assert.deepStrictEqual(Array.prototype.map.call(fields, function (field) { return field.value; }),
      clients[0].forms.map(function (form) { return form.text; }));
    var text = allText(o.view.clients), at = clients[0].forms.map(function (form) { return text.indexOf(form.title); });
    assert.ok(at[0] >= 0 && at[0] < at[1], "the titles show in the forms' order");
    assert.ok(text.indexOf("Connect Claude Code") < at[0], "Connect leads the client's section");
    assert.ok(allText(o.view.clients).includes("claude mcp get ph-composer"));
    assert.ok(allText(o.view.issuedDialog).includes("Connect saves the token in a file only your account can read"));
    named(o.view.clients, "Copy Claude Code setup").dispatchEvent({ type: "click" });
    assert.deepStrictEqual(commands, ["copy"]);
    assert.strictEqual(o.view.copyStatus.textContent, "Claude Code setup copied.");
    named(o.view.issuedDialog, "Done").dispatchEvent({ type: "click" });
    assert.ok(!allText(o.view.root).includes("ab".repeat(24)));
  });

test("Connect sends the client and the token once, says what it did and what to do next", function () {
  var o = setup();
  o.view.receive({ type: "access.issued", payload: { token: "ab".repeat(24), row: TOKEN, clients: [
    { id: "codex", client: "Codex", forms: [{ title: "What Connect adds", text: "[mcp_servers.ph-composer]" }],
      check: "codex mcp get ph-composer", remove: "" }] } });
  var connect = named(o.view.clients, "Connect Codex");
  connect.dispatchEvent({ type: "click" }); connect.dispatchEvent({ type: "click" });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent)),
    [{ type: "access.connect", payload: { client: "codex", token: "ab".repeat(24) } }]);
  assert.ok(connect.disabled, "one Connect at a time");
  o.view.receive({ type: "access.connected", payload: { client: "codex", state: "configured",
    message: "Codex is set up to read its token from PH-Composer. Then start a new Codex session to connect." } });
  assert.ok(allText(o.view.clients).includes("start a new Codex session"));
  assert.strictEqual(connect.disabled, false);
  connect.dispatchEvent({ type: "click" });
  o.view.receive({ type: "access.failure", payload: { message: "This token is no longer live." } });
  assert.ok(allText(o.view.clients).includes("This token is no longer live."), "the refusal replaces Connecting");
  assert.ok(!allText(o.view.clients).includes("Connecting Codex"));
  o.view.receive({ type: "access.state", payload: { state: "readable", offered: ["read"],
    server: { state: "listening", port: 46110 }, tokens: [Object.assign({}, TOKEN, { connected: ["Codex"] })] } });
  assert.ok(allText(o.view.list).includes("used by Codex"));
});

test("New token offers Read fixed and sends the label and capabilities once", function () {
  var o = setup();
  named(o.view.root, "New token").dispatchEvent({ type: "click" });
  assert.strictEqual(o.view.createDialog.hidden, false);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.view.checks.map(function (box) {
    return [box.value, box.checked, box.disabled];
  }))), [["read", true, true]]);
  o.view.labelInput.value = "  Codex  ";
  o.view.submitCreate(); o.view.submitCreate();
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent)),
    [{ type: "access.issue", payload: { label: "Codex", capabilities: ["read"], model_only: false } }]);
});

test("every capability is offered unchecked beside Read, with its consent, and This Model only binds a saved Model",
  function () {
    var all = ["read", "view", "model_write", "setup", "export"];
    var o = setup({ offered: all, model: null });
    named(o.view.root, "New token").dispatchEvent({ type: "click" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(o.view.checks.map(function (box) {
      return [box.value, box.checked];
    }))), all.map(function (name) { return [name, name === "read"]; }));
    var form = allText(o.view.createDialog);
    assert.ok(form.includes("lock it again") && form.includes("every Model") && form.includes("one Undo step"));
    assert.ok(o.view.modelOnly.disabled && form.includes("Save this Model first"));
    o.view.createDialog.closeModal();
    o.view.receive({ type: "access.state", payload: { state: "readable", offered: all,
      model: { name: "house.skp", key: "k1" },
      server: { state: "listening", port: 46110 },
      tokens: [Object.assign({}, TOKEN, { capabilities: ["read", "view"], model_name: "house.skp" })] } });
    assert.ok(allText(o.view.list).includes("only house.skp") && allText(o.view.list).includes("View"));
    named(o.view.root, "New token").dispatchEvent({ type: "click" });
    o.view.modelOnly.checked = true; o.view.checks[2].checked = true;
    o.view.submitCreate();
    assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent.pop())), { type: "access.issue",
      payload: { label: null, capabilities: ["read", "model_write"], model_only: "k1" } });
  });

test("the issued token shows once and is gone after Done", function () {
  var o = setup();
  named(o.view.root, "New token").dispatchEvent({ type: "click" });
  o.view.submitCreate();
  o.view.receive({ type: "access.issued", payload: { token: "ab".repeat(24), row: TOKEN } });
  assert.strictEqual(o.view.createDialog.hidden, true);
  assert.strictEqual(o.view.issuedDialog.hidden, false);
  assert.strictEqual(o.view.secret.value, "ab".repeat(24));
  named(o.view.issuedDialog, "Done").dispatchEvent({ type: "click" });
  assert.strictEqual(o.view.issuedDialog.hidden, true);
  assert.strictEqual(o.view.secret.value, "");
  assert.ok(!allText(o.view.root).includes("ab".repeat(24)));
});

test("Revoke confirms naming the token, sends its id and closes when the list says it is revoked", function () {
  var o = setup();
  named(o.view.list, "Revoke Claude Code").dispatchEvent({ type: "click" });
  assert.strictEqual(o.view.revokeDialog.hidden, false);
  assert.ok(o.view.revokeTitle.textContent.includes("Claude Code"));
  o.view.revokeConfirm.dispatchEvent({ type: "click" });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent)), [{ type: "access.revoke", payload: { id: TOKEN.id } }]);
  o.view.receive({ type: "access.state", payload: { state: "readable", offered: ["read"], server: { state: "stopped" },
    tokens: [Object.assign({}, TOKEN, { revoked_at: "2026-10-18T13:00:00Z" }), REVOKED] } });
  assert.strictEqual(o.view.revokeDialog.hidden, true);
  assert.strictEqual(named(o.view.list, "Revoke Claude Code"), undefined);
});

test("an unreadable store offers only Reset, and a failure shows as a warning and frees the page", function () {
  var o = setup({ state: "unreadable", tokens: [] });
  assert.strictEqual(o.view.unreadableNotice.hidden, false);
  assert.ok(o.view.create.disabled);
  o.view.reset.dispatchEvent({ type: "click" });
  assert.deepStrictEqual(o.sent.map(function (item) { return item.type; }), ["access.reset"]);
  o.view.receive({ type: "access.failure", payload: { message: "Agent tokens could not be saved." } });
  assert.strictEqual(o.view.notice.getAttribute("data-tone"), "warning");
  assert.strictEqual(o.view.pending, false);
});

test("a refusal while New token is open shows inside the form, which stays open to retry", function () {
  var o = setup();
  named(o.view.root, "New token").dispatchEvent({ type: "click" });
  o.view.submitCreate();
  o.view.receive({ type: "access.failure", payload: { message: "This machine already has 8 live agent tokens." } });
  assert.strictEqual(o.view.createDialog.hidden, false);
  assert.ok(o.view.createError.textContent.includes("8 live agent tokens"));
  assert.strictEqual(o.view.notice.hidden, true);
  assert.strictEqual(o.view.createSubmit.disabled, false);
});

test("the page lists its entry and the kit it needs, starts, and asks the host for the list", function () {
  var page = PAGE(), markup = fs.readFileSync(page.path, "utf8"), scripts = [], sent = [];
  var modules = manifest.graph(true);
  var expected = manifest.closure(modules.order, modules.definitions, page.entry);
  markup.replace(/<script src="\.\.\/([^"]+)"><\/script>/g, function (tag, src) { scripts.push(src); return tag; });
  assert.deepStrictEqual(scripts, ["module.js"].concat(expected.map(function (name) { return name + ".js"; }),
    ["boot.js"]));
  assert.ok(expected.indexOf("workspace") === -1 && manifest.graph().order.indexOf(page.entry) === -1);
  var view = context();
  view.sketchup = { ph_composer_agent_access: function (message) { sent.push(JSON.parse(message)); } };
  view.document.body.setAttribute("data-phc-entry", /<body[^>]* data-phc-entry="([^"]+)"/.exec(markup)[1]);
  scripts.forEach(function (src) { source.load(view, src); });
  assert.deepStrictEqual(sent.map(function (message) { return message.type; }), ["access.ready"]);
});

function PAGE() {
  return manifest.PAGES.find(function (page) { return page.entry === "agent_access/page"; });
}

test("Copy token copies the selected token within the click, or says to copy it by hand", function () {
  var o = setup(), commands = [];
  o.page.document.execCommand = function (name) { commands.push(name); return false; };
  o.view.receive({ type: "access.issued", payload: { token: "cd".repeat(24), row: TOKEN } });
  named(o.view.issuedDialog, "Copy token").dispatchEvent({ type: "click" });
  assert.deepStrictEqual(commands, ["copy"]);
  assert.ok(o.view.copyStatus.textContent.includes("Command-C"));
  o.page.document.execCommand = function () { return true; };
  named(o.view.issuedDialog, "Copy token").dispatchEvent({ type: "click" });
  assert.strictEqual(o.view.copyStatus.textContent, "Token copied.");
  assert.strictEqual(o.view.notice.hidden, true);
});

test("This Model only binds the Model the open form named, whatever becomes active", function () {
  var o = setup({ offered: ["read"], model: { name: "a.skp", key: "kA" } });
  named(o.view.root, "New token").dispatchEvent({ type: "click" });
  o.view.modelOnly.checked = true;
  o.view.receive({ type: "access.state", payload: { state: "readable", tokens: [], offered: ["read"], model: null,
    server: { state: "listening", port: 46110 } } });
  o.view.submitCreate();
  assert.strictEqual(o.sent.pop().payload.model_only, "kA");
});

test("a revoke is acknowledged with what the token's exports had done", function () {
  var o = setup();
  o.view.receive({ type: "access.revoked", payload: { id: TOKEN.id,
    summary: { exports_completed: 1, exports_stopped: 1, changes_committed: 2, calls_refused: 1 } } });
  var text = allText(o.view.notice);
  assert.ok(text.includes("Token revoked") && text.includes("1 export(s) it started had completed") &&
    text.includes("stop without writing") && text.includes("2 change(s)") && text.includes("1 waiting call(s)"));
});
