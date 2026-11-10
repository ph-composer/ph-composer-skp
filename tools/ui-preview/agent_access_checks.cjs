/* The Agent Access New token form's layout in Chromium, on the dialog's own page with synthetic state. Each
   checkbox must sit on its label's row, left of the label, so it cannot read as the previous row's (#242).
   This does not prove token issue or the listener; those are tests/agent_access_*_test.rb and host gates. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const BASE = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}/src/ph_composer/html/agent_access/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-agent-access-"));
fs.mkdirSync(output, { recursive: true });
const STATE = { type: "access.state", payload: { state: "readable", tokens: [],
  offered: ["read", "view", "model_write", "setup", "export", "capture"], server: { state: "stopped" },
  model: { key: "model_1", name: "Reference.skp" } } };
const CLIENTS = [
  { id: "claude_code", client: "Claude Code", check: "claude mcp get ph-composer",
    forms: [{ title: "What Connect runs. If it cannot, run this in Terminal once.", text: "claude mcp add-json ..." }] },
  { id: "codex", client: "Codex", check: "codex mcp get ph-composer",
    forms: [{ title: "What Connect adds to ~/.codex/config.toml.", text: "[mcp_servers.ph-composer]" }] }];
check({ name: "agent_access", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 560, height: 700 } });
  step("open the Agent Access page with every capability offered");
  // The shipped page names no icon, so Chrome asks for /favicon.ico; answer it here rather than ship a data: icon.
  await page.route("**/favicon.ico", route => route.fulfill({ status: 204 }));
  await page.goto(`${BASE}index.html`);
  await page.evaluate(state => PhComposerUI.get("agent_access/page").receive(state), STATE);
  await page.getByRole("button", { name: "New token", exact: true }).click();
  const dialog = page.getByRole("dialog");
  await dialog.getByRole("heading", { name: "New agent token" }).waitFor();
  for (const width of [560, 360]) {
    step(`checkbox rows at ${width} px`);
    await page.setViewportSize({ width, height: 700 });
    const rows = await dialog.locator(".agent-access-capability").evaluateAll(nodes => nodes.map(row => {
      const box = row.querySelector("input").getBoundingClientRect();
      const label = row.querySelector("strong").getBoundingClientRect();
      return { name: row.querySelector("strong").textContent, boxTop: box.top, boxBottom: box.bottom,
        boxRight: box.right, labelLeft: label.left, labelTop: label.top, labelBottom: label.bottom };
    }));
    assert.equal(rows.length, 7, "six capabilities and This Model only");
    for (const row of rows) {
      assert(row.boxRight <= row.labelLeft, `${row.name}: box left of its label at ${width}`);
      assert(row.boxBottom > row.labelTop && row.boxTop < row.labelBottom, `${row.name}: box on its label's line at ${width}`);
    }
    await page.screenshot({ path: path.join(output, `new-token-${width}.png`) });
  }
  await page.keyboard.press("Escape");
  step("issued and revoke dialogs preserve the shared viewport limit");
  const token = { id: "synthetic-review-token", label: "Synthetic review agent", capabilities: ["read"],
    created_at: "2026-11-01T12:00:00Z" };
  const receive = (type, payload) => page.evaluate(({ type, payload }) => {
    PhComposerUI.get("agent_access/page").receive({ type, payload });
  }, { type, payload });
  for (const [width, height] of [[420, 732], [360, 520]]) {
    await page.setViewportSize({ width, height });
    await receive("access.state", { ...STATE.payload, tokens: [token], server: { state: "listening", port: 52761 } });
    const folded = page.locator("details.agent-access-tokens");
    if (!(await folded.evaluate(node => node.open))) await folded.locator("summary").click();
    await page.getByRole("button", { name: "Revoke Synthetic review agent", exact: true }).click();
    for (const kind of ["revoke", "issued"]) {
      if (kind === "issued") await receive("access.issued", {
        token: "SYNTHETIC-NOT-A-CREDENTIAL", row: token, clients: CLIENTS });
      const modal = page.locator("dialog[open]");
      assert(await modal.evaluate(node => {
        const box = node.getBoundingClientRect();
        const actions = node.querySelector(".phc-dialog-actions").getBoundingClientRect();
        return box.left >= 15 && box.right <= innerWidth - 15 && box.top >= 0 && box.bottom <= innerHeight &&
          actions.left >= box.left && actions.right <= box.right && actions.bottom <= innerHeight;
      }), `${kind}: dialog and footer fit ${width} x ${height}`);
      if (kind === "issued") {
        assert.equal(await modal.locator(".agent-access-client:not([hidden])").count(), 1, "one client at a time");
        assert(await modal.evaluate(node => node.scrollWidth <= node.clientWidth + 1), `issued: no sideways scroll ${width}`);
      }
      await page.screenshot({ path: path.join(output, `${kind}-${width}x${height}.png`) });
      if (kind === "issued") {
        await modal.locator(".agent-access-client:not([hidden]) details summary").click();
        await page.screenshot({ path: path.join(output, `issued-other-ways-${width}x${height}.png`) });
      }
      await page.keyboard.press("Escape");
    }
  }
  step("connections and Connect's profile choice fit the narrow widths without sideways scroll");
  const CONNECTIONS = [
    { client: "claude_code", client_name: "Claude Code", profile: "default", server: "ph-composer",
      token: { id: token.id, label: token.label, capabilities: ["read"] }, source: "file", entry: "configured",
      contacted: { client: "claude-code 2.1.317", at: "2026-11-10T12:00:00Z" }, verified_at: "2026-11-10T12:01:00Z",
      setup: "claude mcp add-json --scope user ph-composer '{}'" },
    { client: "codex", client_name: "Codex", profile: "house-b-with-a-long-profile-name", server: "ph-composer-house-b",
      token: { id: "synthetic-b", label: "Synthetic house B agent", capabilities: ["read"],
        model_name: "A rather long synthetic file name.skp", model_open: false },
      source: "file", saved_token: { id: "synthetic-b", label: "Synthetic house B agent", capabilities: ["read"] }, entry: "outdated", contacted: null, verified_at: null,
      setup: "[mcp_servers.ph-composer-house-b]\nurl = \"http://127.0.0.1:47001/mcp\"\nhttp_headers_helper = \"/bin/cat /Users/example/.ph-composer/codex.house-b.json\"" }];
  for (const [width, height] of [[420, 732], [360, 520]]) {
    await page.setViewportSize({ width, height });
    await receive("access.state", { ...STATE.payload, tokens: [token], connections: CONNECTIONS,
      server: { state: "listening", port: 47001 } });
    const box = page.locator("details.agent-access-connections");
    if (!(await box.evaluate(node => node.open))) await box.locator(":scope > summary").click();
    await box.locator(".agent-access-connection details summary").first().click();
    await page.getByRole("button", { name: "Repair Codex (house-b-with-a-long-profile-name)", exact: true }).waitFor();
    assert(await page.locator(".agent-access").evaluate(node => node.scrollWidth <= node.clientWidth + 1),
      `connections: no sideways scroll at ${width}`);
    await page.screenshot({ path: path.join(output, `connections-${width}x${height}.png`), fullPage: true });
    await receive("access.issued", { token: "SYNTHETIC-NOT-A-CREDENTIAL", row: { ...token, id: "synthetic-new" },
      clients: CLIENTS });
    const modal = page.locator("dialog[open]");
    await modal.getByRole("button", { name: "Replace and connect", exact: true }).waitFor();
    await modal.getByLabel("Claude Code profile", { exact: true }).selectOption("");
    await modal.getByLabel("Claude Code new profile name", { exact: true }).fill("house-c");
    await modal.getByRole("button", { name: "Connect Claude Code", exact: true }).waitFor();
    assert(await modal.evaluate(node => node.scrollWidth <= node.clientWidth + 1), `profile: no sideways scroll ${width}`);
    await page.screenshot({ path: path.join(output, `issued-profile-${width}x${height}.png`) });
    await page.keyboard.press("Escape");
  }
  step("wide recovery state retains one centered reading column");
  await page.setViewportSize({ width: 1280, height: 800 });
  await receive("access.state", { ...STATE.payload, state: "unreadable",
    server: { state: "unavailable", port: 52761, message: "The port is already in use." } });
  const edges = await page.locator(".agent-access > .phc-heading, .agent-access-server, .agent-access-unreadable")
    .evaluateAll(nodes => nodes.map(node => node.getBoundingClientRect().left));
  assert.equal(edges.length, 3);
  assert(Math.max(...edges) - Math.min(...edges) < 1, "heading, server state and recovery share a left edge");
  await page.screenshot({ path: path.join(output, "unavailable-wide.png") });
  return `Agent Access browser checks passed; evidence: ${output}`;
});
