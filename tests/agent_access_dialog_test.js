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
var NOW = new Date(2026, 9, 18, 15, 0, 0);
function setup(state) {
  var page = context(), modules = source.start(page, ["agent_access/page"]), sent = [];
  var view = new modules["agent_access/page"].Page(function (type, payload) {
    sent.push({ type: type, payload: payload });
  }, { now: function () { return NOW; } });
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
  assert.ok(!text.includes("Old Codex"), "revoked tokens wait behind their toggle");
  assert.strictEqual(o.view.revokedToggle.textContent, "Show revoked tokens (1)");
  o.view.revokedToggle.dispatchEvent({ type: "click" });
  text = allText(o.view.list);
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

test("the window leads with New token; the tokens are folded, live ones grouped by when they were issued",
  function () {
    var at = function (days) { return new Date(NOW.getTime() - days * 86400000).toISOString(); };
    var tokens = [0, 1, 3, 40, 400].map(function (days, index) {
      return Object.assign({}, TOKEN, { id: "token_AAAAAAAAAAA" + index, label: "T" + index, created_at: at(days) });
    });
    var o = setup({ tokens: tokens.concat([REVOKED]) });
    assert.ok(/(^| )primary( |$)/.test(o.view.create.className), "New token is the page's primary action");
    assert.strictEqual(o.view.tokensBox.tagName, "details");
    assert.ok(!o.view.tokensBox.open, "the list starts folded");
    assert.strictEqual(o.view.tokensSummary.textContent, "Tokens · 5 live");
    var headings = o.view.list.querySelectorAll("h3").map(function (node) { return node.textContent; });
    assert.deepStrictEqual(headings, ["Today", "Yesterday", "This week", "This year", "Earlier"]);
    assert.strictEqual(o.view.empty.hidden, true);
    o.view.revokedToggle.dispatchEvent({ type: "click" });
    headings = o.view.list.querySelectorAll("h3").map(function (node) { return node.textContent; });
    assert.strictEqual(headings[headings.length - 1], "Revoked");
    assert.strictEqual(o.view.revokedToggle.getAttribute("aria-pressed"), "true");
    o.view.receive({ type: "access.state", payload: { state: "readable", tokens: [], offered: ["read"],
      server: { state: "stopped" } } });
    assert.strictEqual(o.view.tokensBox.hidden, true);
    assert.strictEqual(o.view.empty.hidden, false);
  });

test("on a Monday the week has only begun: Sunday is Yesterday, Saturday is This year", function () {
  var monday = new Date(2026, 9, 19, 9, 0, 0), page = context(), sent = [];
  var modules = source.start(page, ["agent_access/page"]);
  var view = new modules["agent_access/page"].Page(function (type, payload) { sent.push(type, payload); },
    { now: function () { return monday; } });
  var made = function (date, label) {
    return Object.assign({}, TOKEN, { id: "token_" + label + "AAAAAAAAA", label: label,
      created_at: date.toISOString() });
  };
  view.receive({ type: "access.state", payload: { state: "readable", offered: ["read"], server: { state: "stopped" },
    tokens: [made(new Date(2026, 9, 18, 23, 30), "Sun"), made(new Date(2026, 9, 17, 12, 0), "Sat")] } });
  var headings = view.list.querySelectorAll("h3").map(function (node) { return node.textContent; });
  assert.deepStrictEqual(headings, ["Yesterday", "This year"]);
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
    var fields = o.view.clients.querySelectorAll("textarea").filter(function (field) {
      return field.getAttribute("aria-label") === "Claude Code setup";
    });
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

test("the created token shows one client at a time: Connect first, other setups only when asked for", function () {
  var o = setup(), form = function (title) { return [{ title: title, text: title + " text" }]; };
  o.view.receive({ type: "access.issued", payload: { token: "ab".repeat(24), row: TOKEN, clients: [
    { id: "claude_code", client: "Claude Code", forms: form("Claude setup"), check: "claude mcp get ph-composer" },
    { id: "codex", client: "Codex", forms: form("Codex setup"), check: "codex mcp get ph-composer" }] } });
  var tabs = o.view.clients.querySelector("nav");
  assert.strictEqual(tabs.getAttribute("aria-label"), "Client");
  var sections = o.view.clients.querySelectorAll(".agent-access-client");
  assert.deepStrictEqual(sections.map(function (node) { return node.hidden; }), [false, true]);
  var claude = sections[0];
  assert.ok(/(^| )primary( |$)/.test(named(claude, "Connect Claude Code").className), "Connect is the default");
  var other = claude.querySelector("details");
  assert.strictEqual(other.querySelector("summary").textContent, "Other ways to connect the Default profile");
  assert.ok(!other.open, "the other setups start folded");
  assert.ok(allText(other).includes("Claude setup") && allText(other).includes("claude mcp get ph-composer"));
  named(tabs, "Codex").dispatchEvent({ type: "click" });
  assert.deepStrictEqual(sections.map(function (node) { return node.hidden; }), [true, false]);
});

test("Connect sends the client and the token once, says what it did and what to do next", function () {
  var o = setup();
  o.view.receive({ type: "access.issued", payload: { token: "ab".repeat(24), row: TOKEN, clients: [
    { id: "codex", client: "Codex", forms: [{ title: "What Connect adds", text: "[mcp_servers.ph-composer]" }],
      check: "codex mcp get ph-composer", remove: "" }] } });
  var connect = named(o.view.clients, "Connect Codex");
  connect.dispatchEvent({ type: "click" }); connect.dispatchEvent({ type: "click" });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent)),
    [{ type: "access.connect", payload: { client: "codex", token: "ab".repeat(24), profile: "default",
      replace: null } }]);
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

/* Client profiles (context/AGENT_INTERFACE.md, "User-controlled local access"): each saved profile, the token
   it uses, what the client's settings say, contacted and verified kept apart; Repair and the hand setup
   only where the entry is not set up. */
var CONNECTIONS = [
  { client: "claude_code", client_name: "Claude Code", profile: "default", server: "ph-composer",
    token: { id: TOKEN.id, label: "Claude Code", capabilities: ["read"] }, source: "file", entry: "configured",
    contacted: { client: "claude-code 2.1.317", at: "2026-10-18T14:00:00Z" }, verified_at: "2026-10-18T14:01:00Z",
    setup: "claude mcp add-json --scope user ph-composer '{}'" },
  { client: "codex", client_name: "Codex", profile: "house-b", server: "ph-composer-house-b",
    token: { id: "token_CCCCCCCCCCCC", label: "House B", capabilities: ["read"], model_name: "b.skp",
      model_open: false }, source: "file", saved_token: { id: "token_CCCCCCCCCCCC", label: "House B" },
    entry: "outdated", contacted: null, verified_at: null,
    setup: "[mcp_servers.ph-composer-house-b]\nurl = \"http://127.0.0.1:47001/mcp\"" },
  { client: "codex", client_name: "Codex", profile: "default", server: "ph-composer", token: null, source: null,
    entry: "inline", contacted: null, verified_at: null, setup: "[mcp_servers.ph-composer]" }];

test("connections list each profile's token, set-up state, contact and verification apart, with Repair where needed",
  function () {
    var o = setup({ connections: CONNECTIONS, server: { state: "listening", port: 47001 } });
    assert.strictEqual(o.view.connectionsSummary.textContent, "Client profiles · 3");
    var rows = o.view.connectionList.querySelectorAll(".agent-access-connection").map(allText);
    assert.ok(rows[0].includes("Claude Code · Default") && rows[0].includes("set up") &&
      rows[0].includes("contacted by claude-code 2.1.317") && rows[0].includes("verified") &&
      !rows[0].includes("token contacted"));
    assert.ok(rows[1].includes("Codex · house-b") && rows[1].includes("only b.skp (not open)") &&
      rows[1].includes("another port") && rows[1].includes("not contacted") && !rows[1].includes("verified"));
    assert.ok(rows[2].includes("no live token") && rows[2].includes("kept in the client's settings"));
    assert.strictEqual(named(o.view.connectionList, "Repair Claude Code"), undefined, "a set-up entry needs none");
    assert.strictEqual(named(o.view.connectionList, "Repair Codex"), undefined, "no live token, nothing to repair");
    assert.strictEqual(o.view.connectionList.querySelectorAll("details").length, 2, "hand setup where not set up");
    named(o.view.connectionList, "Repair Codex (house-b)").dispatchEvent({ type: "click" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent)),
      [{ type: "access.repair", payload: { client: "codex", profile: "house-b" } }]);
    o.view.receive({ type: "access.connected", payload: { client: "codex", profile: "house-b", state: "configured",
      message: "Codex is set up to read its token from PH-Composer." } });
    assert.strictEqual(o.view.notice.getAttribute("data-tone"), "success");
    assert.ok(allText(o.view.notice).includes("Codex is set up"));
  });

test("Connect picks a profile, shows the token it replaces before sending, and a new profile needs a valid name",
  function () {
    var o = setup({ connections: CONNECTIONS, server: { state: "listening", port: 46110 } });
    var mine = Object.assign({}, TOKEN, { id: "token_NEWNEWNEWNEW", label: "New one" });
    o.view.receive({ type: "access.issued", payload: { token: "ab".repeat(24), row: mine, clients: [
      { id: "claude_code", client: "Claude Code", forms: [], check: "" },
      { id: "codex", client: "Codex", forms: [], check: "" }] } });
    var picker = o.view.pickers.claude_code;
    assert.deepStrictEqual(picker.select.querySelectorAll("option").map(function (node) { return node.value; }),
      ["default", ""]);
    assert.ok(picker.replace.textContent.includes("Default uses Claude Code now"));
    assert.strictEqual(picker.connect.textContent, "Replace and connect");
    picker.connect.dispatchEvent({ type: "click" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent.pop())), { type: "access.connect", payload: {
      client: "claude_code", token: "ab".repeat(24), profile: "default", replace: TOKEN.id } });
    o.view.receive({ type: "access.failure", payload: { message: "refused" } });
    picker.select.value = ""; picker.select.dispatchEvent({ type: "change" });
    assert.strictEqual(picker.nameRow.hidden, false);
    picker.name.value = "House B"; picker.name.dispatchEvent({ type: "input" });
    assert.ok(picker.connect.disabled, "a name that cannot be a profile");
    picker.name.value = "house-c"; picker.name.dispatchEvent({ type: "input" });
    assert.strictEqual(picker.connect.textContent, "Connect Claude Code");
    picker.connect.dispatchEvent({ type: "click" });
    assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent.pop().payload)),
      { client: "claude_code", token: "ab".repeat(24), profile: "house-c", replace: null });
    // The host found a token the page had not shown: nothing changed, and the page now names it.
    o.view.receive({ type: "access.replacement", payload: { client: "claude_code", profile: "house-c",
      token: { id: "token_DDDDDDDDDDDD", label: "Other" } } });
    assert.ok(picker.replace.textContent.includes("house-c uses Other now"));
    assert.ok(allText(o.view.clients).includes("Nothing changed yet"));
    assert.strictEqual(picker.connect.textContent, "Replace and connect");
    o.view.receive({ type: "access.connected", payload: { client: "codex", profile: "house-b", state: "manual",
      message: "The token is saved for Codex.", setup: "[mcp_servers.ph-composer-house-b]" } });
    assert.strictEqual(o.view.connectSetup.codex.hidden, false);
    assert.strictEqual(o.view.connectSetupValue.codex.value, "[mcp_servers.ph-composer-house-b]");
    assert.ok(!allText(o.view.connectSetup.codex).includes("ab".repeat(24)));
  });

test("a refresh keeps an open hand setup open and a refusal drops a replacement the host no longer holds",
  function () {
    var o = setup({ connections: CONNECTIONS });
    var details = o.view.connectionList.querySelectorAll("details")[0];
    details.open = true; details.dispatchEvent({ type: "toggle" });
    o.view.receive({ type: "access.state", payload: { state: "readable", tokens: [TOKEN], offered: ["read"],
      server: { state: "listening", port: 47001 }, connections: CONNECTIONS } });
    assert.strictEqual(o.view.connectionList.querySelectorAll("details")[0].open, true);
    o.view.receive({ type: "access.issued", payload: { token: "ab".repeat(24), row: Object.assign({}, TOKEN,
      { id: "token_NEWNEWNEWNEW" }), clients: [{ id: "codex", client: "Codex", forms: [], check: "" }] } });
    o.view.receive({ type: "access.replacement", payload: { client: "codex", profile: "default",
      token: { id: "token_GONEGONEGONE", label: "Gone" } } });
    assert.ok(o.view.pickers.codex.replace.textContent.includes("Gone"));
    o.view.receive({ type: "access.failure", payload: { message: "This connection changed since it was shown." } });
    assert.strictEqual(o.view.pickers.codex.replace.textContent, "", "the next Connect asks the host again");
  });

test("Revoke names the connections that lose access", function () {
  var o = setup({ connections: CONNECTIONS });
  named(o.view.list, "Revoke Claude Code").dispatchEvent({ type: "click" });
  assert.ok(o.view.revokeEffects.textContent.includes("These client profiles lose access") &&
    o.view.revokeEffects.textContent.includes("Claude Code"));
});
