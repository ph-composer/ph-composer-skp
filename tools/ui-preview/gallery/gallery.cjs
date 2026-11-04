"use strict";
/* Full-size 1x screenshots of every tab, subtab and key container of the preview panel, at every panel
   size, for a design review (tools/ui-preview/.index.md). A capture tool, not a check: it asserts nothing.
   Run it with `make ui-gallery`, which serves the preview on a free port. Files land in
   UI_GALLERY_OUT (a temporary folder by default) as <w>x<h>/<fixture>--<tab>--<subtab>.png. */
const { chromium } = require("playwright");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PANEL_SIZES } = require("../support/pane_fit.cjs");

const port = process.env.UI_PREVIEW_PORT || "8765";
const BASE = `http://127.0.0.1:${port}/tools/ui-preview/`;
const root = process.env.UI_GALLERY_OUT || fs.mkdtempSync(path.join(os.tmpdir(), "phc-gallery-"));
const fixtures = (process.env.UI_GALLERY_FIXTURES || "rich dense empty").split(/\s+/).filter(Boolean);
// UI_GALLERY_SIZES narrows the sizes, as in "1280x800"; the default is every PANEL_SIZES entry.
const sizes = process.env.UI_GALLERY_SIZES
  ? process.env.UI_GALLERY_SIZES.split(/\s+/).filter(Boolean).map((size) => size.split("x").map(Number))
  : PANEL_SIZES;
let out = root;

async function hideDevOnly(page) {
  await page.evaluate(() => {
    document.querySelectorAll("h2").forEach((h) => {
      if (h.textContent === "Example parts") { const s = h.closest("section") || h.parentElement.parentElement; s.style.display = "none"; }
    });
    document.querySelectorAll("[role=tab]").forEach((b) => { if (b.textContent.trim() === "Areas") b.style.display = "none"; });
    window.dispatchEvent(new Event("resize"));
  });
}
const settle = (page, ms = 250) => page.waitForTimeout(ms);

async function shot(page, name) {
  await hideDevOnly(page);
  await settle(page, 120);
  await page.screenshot({ path: path.join(out, name + ".png") });
  console.log("shot", name);
}

async function clickByRole(page, role, name, opts = {}) {
  const loc = page.getByRole(role, { name, exact: opts.exact !== false }).filter({ visible: true }).first();
  if (!(await loc.count())) return false;
  await loc.click({ timeout: 2000 }).catch(() => {});
  await settle(page);
  return true;
}
async function escape(page, n = 2) { for (let i = 0; i < n; i++) { await page.keyboard.press("Escape"); await settle(page, 80); } }

(async () => {
  // The installed Chrome, as the checks use: Playwright's bundled browser is not installed by ui-deps.
  const browser = await chromium.launch({ headless: true, channel: "chrome" });
  for (const [WIDTH, HEIGHT] of sizes) {
  out = path.join(root, `${WIDTH}x${HEIGHT}`);
  fs.mkdirSync(out, { recursive: true });
  for (const fixture of fixtures) {
    const ctx = await browser.newContext({ viewport: { width: WIDTH, height: HEIGHT }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    page.on("pageerror", (e) => console.log("PAGEERROR", fixture, e.message));
    await page.goto(`${BASE}?fixture=${fixture}`);
    await page.waitForSelector("[data-tab=overview]");
    await settle(page, 600);
    const tabs = await page.$$eval(".phc-tabs button[data-tab]", (els) => els.filter((e) => !e.disabled).map((e) => [e.dataset.tab, e.textContent.trim()]));
    for (const [tab, label] of tabs) {
      await page.click(`.phc-tabs button[data-tab=${tab}]`);
      await settle(page, 400);
      const subs = await page.$$eval("[data-pane]:not([hidden]) [role=tab]", (els) => els.filter((e) => e.offsetParent && e.textContent.trim() !== "Areas").map((e) => e.textContent.trim()));
      if (!subs.length) await shot(page, `${fixture}--${tab}`);
      for (const sub of subs) {
        await page.locator("[data-pane]:not([hidden]) [role=tab]", { hasText: sub }).first().click();
        await settle(page, 400);
        await shot(page, `${fixture}--${tab}--${sub.replace(/[^a-z0-9]+/gi, "_").toLowerCase()}`);
        if (fixture !== "rich") continue;
        // Key containers on the rich Model.
        if (tab === "library" && sub === "Materials") {
          if (await clickByRole(page, "button", "+ New Material")) { await shot(page, "rich--modal--new_material"); await escape(page); }
          if (await clickByRole(page, "button", "Library setup…") || await clickByRole(page, "button", "Library setup...")) { await shot(page, "rich--modal--library_setup"); await escape(page); }
          if (await clickByRole(page, "button", "Export library")) { await shot(page, "rich--modal--export_library"); await escape(page); }
        }
        if (tab === "library" && sub === "Frames") {
          const n = page.getByRole("button", { name: /New Frame/ }).filter({ visible: true }).first();
          if (await n.count()) { await n.click(); await settle(page); await shot(page, "rich--modal--new_frame"); await escape(page); }
        }
        if (tab === "thermal_bridges" && sub === "Types") {
          const n = page.getByRole("button", { name: /New Thermal Bridge Type/ }).filter({ visible: true }).first();
          if (await n.count()) { await n.click(); await settle(page); await shot(page, "rich--modal--new_tb_type"); await escape(page); }
        }
        if (tab === "overview" && sub === "Faces") {
          const opts = page.locator("[data-pane]:not([hidden]) button[aria-label*='ptions'], [data-pane]:not([hidden]) button[title*='ptions']").filter({ visible: true }).first();
          if (await opts.count()) { await opts.click(); await settle(page); await shot(page, "rich--bubble--table_options"); await escape(page); }
          const gear = page.locator("[data-pane]:not([hidden]) .phc-heading button.phc-icon-button").filter({ visible: true }).last();
          if (await gear.count()) { await gear.click(); await settle(page); await shot(page, "rich--bubble--zone_settings"); await escape(page); }
        }
      }
      if (fixture === "rich" && tab === "assemblies") {
        const del = page.locator("[data-pane]:not([hidden]) tbody tr").first();
        await del.hover();
        const delBtn = del.locator(".row-delete").first();
        if (await delBtn.count()) { await delBtn.click({ force: true }); await settle(page); await shot(page, "rich--modal--delete_confirm"); await escape(page); }
        if (await clickByRole(page, "button", "Open Wall")) {
          await settle(page, 600); await shot(page, "rich--assemblies--builder");
          const seg = page.locator("[data-segment-id='seg_stud_0'].assembly-hit-target").first();
          if (await seg.count()) { await seg.click(); await page.mouse.move(2, 400); await settle(page); await shot(page, "rich--assemblies--builder_selected"); }
          const more = page.locator("[data-pane]:not([hidden]) button[aria-label='More actions'], [data-pane]:not([hidden]) button[aria-label*='actions']").filter({ visible: true }).first();
          if (await more.count()) { await more.click(); await settle(page); await shot(page, "rich--menu--builder_more"); await escape(page, 1); }
          await clickByRole(page, "button", "Back to Assemblies");
        }
      }
      if (fixture === "rich" && tab === "windows") {
        await page.locator("[data-pane]:not([hidden]) [role=tab]", { hasText: /^Types$/ }).first().click();
        await settle(page);
        const more = page.locator("[data-pane]:not([hidden]) .phc-heading button[aria-label]").filter({ visible: true }).last();
        if (await more.count()) { await more.click(); await settle(page); await shot(page, "rich--menu--window_type_more"); await escape(page, 1); }
      }
      if (fixture === "rich" && tab === "overview") {
        await page.locator("[data-pane]:not([hidden]) [role=tab]", { hasText: "Faces" }).first().click();
        await settle(page);
        const th = page.locator("[data-pane]:not([hidden]) th").filter({ hasText: "Type" }).first();
        if (await th.count()) {
          await th.hover();
          const act = th.locator(".phc-header-action button, button.phc-header-action").first();
          if (await act.count()) { await act.click({ force: true }); await settle(page); await shot(page, "rich--menu--column_menu"); await escape(page, 1); }
        }
        // A floating warning notice, as a refused edit raises it.
        await page.evaluate(() => {
          const panel = PhComposerUI.get("panel");
          if (panel && panel.notify) panel.notify("The Face changed in SketchUp after the panel read it. Nothing was written.", "warning");
        });
        await settle(page);
        await shot(page, "rich--notice--warning");
        await page.locator(".phc-floating-notice-dismiss").first().click().catch(() => {}); await settle(page);
      }
    }
    await ctx.close();
  }
  }
  // The two separate dialogs, on their own pages with synthetic state, at their own window size.
  out = root;
  const HTML = `http://127.0.0.1:${port}/src/ph_composer/html/`;
  const sctx = await browser.newContext({ viewport: { width: 560, height: 700 } });
  const sp = await sctx.newPage();
  await sp.addInitScript(() => { window.sketchup = { ph_composer_support: () => {}, ph_composer_agent_access: () => {} }; });
  await sp.goto(HTML + "support/index.html");
  await sp.evaluate(() => PhComposerUI.get("support/page").receive({ type: "support.state", payload: {
    about: { version: "0.1.0-dev", build: "development", development: true, commit: null, manifest: "abc123def456",
      host: { sketchup: "26.1.188", platform: "macOS", ruby: "3.2.2", supported: true, supported_text: "SketchUp 2023 or later on macOS" },
      log: { writing: true, last_error: null } },
    problems: [{ time: "2026-10-19T14:02:00Z", label: "An edit or read could not be completed", incident: "PHC-3FA9C1" },
      { time: "2026-10-18T09:40:00Z", label: "The panel could not show part of a page", incident: "PHC-07B2D4" }],
    incident: "PHC-07B2D4", retention_days: 7, resettable: ["Display units (back to SI)", "Remembered table views"] } }));
  await settle(sp, 300);
  await sp.screenshot({ path: path.join(out, "dialog--help_diagnostics.png"), fullPage: true }); console.log("shot help");
  await sp.goto(HTML + "agent_access/index.html");
  await sp.evaluate(() => PhComposerUI.get("agent_access/page").receive({ type: "access.state", payload: { state: "readable",
    tokens: [{ id: "tok_1", label: "Codex on laptop", capabilities: ["read", "view"], model_scope: "model_1", created_at: "2026-10-20T10:00:00Z", last_used_at: "2026-10-30T08:00:00Z" }],
    offered: ["read", "view", "model_write", "setup", "export", "capture"], server: { state: "running", port: 47110 },
    model: { key: "model_1", name: "Reference.skp" } } }));
  await settle(sp, 300);
  await sp.screenshot({ path: path.join(out, "dialog--agent_access.png"), fullPage: true }); console.log("shot agent");
  const nt = sp.getByRole("button", { name: "New token", exact: true });
  if (await nt.count()) { await nt.click(); await settle(sp); await sp.screenshot({ path: path.join(out, "dialog--agent_access_new_token.png") }); console.log("shot token"); }
  await sctx.close();
  await browser.close();
  console.log("Gallery: " + root);
})().catch((e) => { console.error(e); process.exit(1); });
