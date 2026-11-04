/* The preview page in a real browser: the shipped panel, its stand-in host and the synthetic editor. Checks
   what the offline DOM double cannot: layout at four panel sizes with no sideways page scroll, focus staying
   in a field through a unit switch, the modal form's focus and Escape, and no script errors. Screenshots go
   to PH_COMPOSER_PREVIEW_EVIDENCE. Run through `make ui-checks`. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { setPanelSize, settle, paneFacts } = require("./support/pane_fit.cjs");

const PORT = process.env.UI_PREVIEW_PORT || "8765";
const BASE = `http://127.0.0.1:${PORT}/tools/ui-preview/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-preview-"));
fs.mkdirSync(output, { recursive: true });

check({ name: "preview", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const shot = (name) => page.screenshot({ path: path.join(output, `${name}.png`) });

  step("open the parts fixture");
  await page.goto(`${BASE}?fixture=parts`);
  await page.getByRole("heading", { name: "Example parts" }).waitFor();
  assert.equal(await page.title(), "PH-Composer UI preview");
  for (const [width, height] of [[1280, 800], [900, 650], [360, 520], [1680, 1000]]) {
    await page.setViewportSize({ width, height });
    assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth), `no page scroll at ${width}`);
    assert(await page.evaluate(() => {
      const last = document.querySelector("[data-tab=export]").getBoundingClientRect();
      const toggle = document.querySelector(".phc-unit-toggle").getBoundingClientRect();
      const row = document.querySelector("[data-tab=overview]").getBoundingClientRect().height;
      return last.width > 0 && last.left >= 0 && last.right <= toggle.left && last.height === row && row < 40;
    }), `the Export tab is in view, clear of the unit switch and on one line at ${width}`);
    await shot(`overview-${width}`);
  }
  await page.setViewportSize({ width: 1280, height: 800 });

  step("draft through a unit switch");
  // A draft keeps focus, text and its starting unit through a display switch made from the keyboard route.
  const head = page.getByRole("textbox", { name: "Head length", exact: true });
  await head.click();
  await head.fill("1300");
  await page.evaluate(() => document.querySelector("[data-unit-system='IP']").click());
  assert.equal(await head.inputValue(), "1300");
  await shot("draft-through-switch");
  await head.press("Enter");
  assert.equal(await page.evaluate(() => window.previewHost.parts[1].length_mm), 1300);
  assert.equal(await head.inputValue(), "51.181102");

  step("invalid entry");
  // Invalid input: the message sits beside the field and the text stays.
  const sill = page.getByRole("textbox", { name: "Sill length", exact: true });
  await sill.fill("2 kg");
  await sill.press("Enter");
  assert.equal(await sill.getAttribute("aria-invalid"), "true");
  await page.getByText("Expected a length; kg is a mass unit.").waitFor();
  await shot("invalid-entry");
  await sill.press("Escape");
  assert.equal(await sill.getAttribute("aria-invalid"), "false");

  step("New part form");
  // The New part form: modal, focus inside, Escape cancels and nothing is sent.
  const invokes = () => page.evaluate(() => window.previewHost.sent.filter((m) => m.type === "action.invoke")
    .length);
  const before = await invokes();
  await page.getByRole("button", { name: "New part" }).click();
  const dialog = page.getByRole("dialog", { name: "New part" });
  await dialog.waitFor();
  assert(await page.evaluate(() => document.activeElement.closest("dialog") !== null), "focus is in the form");
  await shot("new-part-form");
  await page.keyboard.press("Escape");
  await dialog.waitFor({ state: "hidden" });
  assert.equal(await invokes(), before);

  step("refused edit");
  // A refused edit leaves a persistent warning and the Model's value.
  await page.evaluate(() => { window.previewHost.parts[0].length_mm = 1500; });
  await sill.fill("1300");
  await sill.press("Enter");
  const notice = page.locator("[data-notice-layer] .phc-floating-notice:not(.phc-recovery)");
  assert.equal(await notice.getAttribute("data-tone"), "warning");
  await shot("refused-edit");
  await page.mouse.click(5, 5);
  assert(await notice.isVisible(), "a warning survives an unrelated click");
  await page.getByRole("button", { name: "Dismiss message" }).click();
  assert(!(await notice.isVisible()));

  step("empty and Export panes");
  await page.goto(`${BASE}?fixture=empty`);
  await page.getByText("No example parts yet.").waitFor();
  await page.setViewportSize({ width: 360, height: 520 });
  await shot("empty-narrow");
  await page.getByRole("button", { name: "Export" }).click();
  await page.getByText("Export writes are unavailable in this browser preview.").waitFor();
  assert(await page.getByRole("button", { name: "Choose destination…" }).isDisabled());
  await shot("export-narrow");

  step("authoring pane");
  await page.goto(`${BASE}?fixture=authoring`);
  await page.getByRole("heading", { name: "Zones" }).waitFor();
  await page.getByRole("cell", { name: "Living Zone", exact: true }).waitFor();
  await page.getByRole("cell", { name: "Attic Zone", exact: true }).waitFor();
  await page.setViewportSize({ width: 360, height: 520 });
  assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth), "authoring has no page scroll");
  await shot("authoring-narrow");
  await page.getByRole("button", { name: "Faces settings", exact: true }).click();
  const roof = page.getByRole("spinbutton", { name: "Roof maximum tilt [deg]" });
  await roof.fill("45");
  await roof.press("Enter");
  assert.equal(await page.evaluate(() => window.previewHost.zoneSettings.roof_angle_deg), 45);
  assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth), "settings have no page scroll");
  await shot("zone-settings-narrow");
  await page.keyboard.press("Escape");

  step("column paint menus");
  // Column paint choices float over the table without narrowing or shifting it.
  // At narrow widths the table scrolls inside its mount with identity columns held.
  await page.goto(`${BASE}?fixture=authoring`);
  await page.getByRole("heading", { name: "Zones" }).waitFor();
  for (const width of [1280, 900, 420]) {
    await page.setViewportSize({ width, height: 800 });
    const table = page.locator("[data-pane=overview] .phc-zone-view:not([hidden]) .phc-table-mount");
    assert.equal(await page.locator("[data-pane=overview] [data-phc-region=inspector]").count(), 0, `no inspector at ${width}`);
    const before = await table.boundingBox(), pane = await page.locator("[data-pane=overview]").boundingBox();
    assert(before.width >= pane.width - 2 * 24, `the table spans the pane at ${width}`);
    const paintMenu = page.getByRole("button", { name: "Type column menu", exact: true });
    await paintMenu.focus();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await paintMenu.press("Enter");
    await page.getByRole("dialog", { name: "Type", exact: true }).waitFor();
    assert.equal(await page.getByRole("button", { name: "Paint faces…", exact: true }).count(), 0);
    const after = await table.boundingBox();
    assert.equal(after.y, before.y, `the table stays put at ${width}`);
    assert.equal(after.width, before.width, `the table keeps its width at ${width}`);
    assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth), `no page scroll at ${width}`);
    // At every narrow width Name stays at the left (zones.css); below 500 only Hierarchy scrolls away.
    if (width <= 900) {
      assert.equal(await page.evaluate(() => getComputedStyle(document.querySelector(
        "[data-pane=overview] td.col-name")).position), "sticky", `Name stays at the left at ${width}`);
    }
    await shot(`column-show-paint-${width}`);
    await page.keyboard.press("Escape");
  }

  step("narrow subtab discovery and keyboard navigation");
  await page.goto(`${BASE}?fixture=rich`);
  await setPanelSize(page, 360, 520);
  await page.locator("[data-tab=library]").click();
  const libraryTabs = page.getByRole("tablist", { name: "Library definitions", exact: true });
  const cue = libraryTabs.locator(".phc-subtabs-overflow");
  await cue.waitFor({ state: "visible" });
  assert(await cue.evaluate(node => {
    const box = node.getBoundingClientRect(), nav = node.parentElement.getBoundingClientRect();
    const padding = parseFloat(getComputedStyle(node.parentElement).paddingRight) || 0;
    return box.left > nav.left + nav.width / 2 && box.right <= nav.right + 1 &&
      nav.right - box.right <= padding + 1;
  }), "the passive overflow cue stays at the visible right edge");
  assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false,
    "overflowing subtabs do not widen the panel pane");
  await page.mouse.move(0, 0); await shot("library-subtabs-overflow-360x520");
  const materials = libraryTabs.getByRole("tab", { name: "Materials", exact: true });
  const psi = libraryTabs.getByRole("tab", { name: "Psi-Install Types", exact: true });
  await materials.focus(); await materials.press("End"); await settle(page);
  await page.waitForFunction(() => document.querySelector(
    '[aria-label="Library definitions"] .phc-subtabs-overflow').classList.contains("is-at-end"), null, { timeout: 3000 });
  assert.equal(await psi.getAttribute("aria-selected"), "true", "End selects the final shipping tab");
  assert(await psi.evaluate(node => {
    const range = document.createRange(); range.selectNodeContents(node);
    const label = range.getBoundingClientRect(), nav = node.parentElement.getBoundingClientRect();
    const cue = node.parentElement.querySelector(".phc-subtabs-overflow").getBoundingClientRect();
    return document.activeElement === node && label.left >= nav.left && label.right <= cue.left + 1;
  }), "native keyboard focus scrolls the entire Psi-Install label clear of the cue");
  assert.equal(await cue.locator("svg").evaluate(node => getComputedStyle(node).transform),
    "matrix(0, 1, -1, 0, 0, 0)", "the cue points back at the scroll end");
  await shot("library-subtabs-end-360x520");
  await psi.press("Home"); await settle(page);
  assert.equal(await materials.getAttribute("aria-selected"), "true", "Home restores Materials");
  assert.equal(await cue.evaluate(node => node.classList.contains("is-at-end")), false);
  await setPanelSize(page, 1280, 800); await cue.waitFor({ state: "hidden" });
  await setPanelSize(page, 360, 520); await cue.waitFor({ state: "visible" });
  async function selectedPsiIsClear(reason) {
    await page.waitForFunction(() => document.querySelector(
      '[aria-label="Library definitions"] .phc-subtabs-overflow').classList.contains("is-at-end"), null, { timeout: 3000 });
    assert.equal(await psi.getAttribute("aria-selected"), "true", reason);
    assert(await psi.evaluate(node => {
      const range = document.createRange(); range.selectNodeContents(node);
      const label = range.getBoundingClientRect(), nav = node.parentElement.getBoundingClientRect();
      const cue = node.parentElement.querySelector(".phc-subtabs-overflow").getBoundingClientRect();
      return label.left >= nav.left && label.right <= cue.left + 1;
    }), `${reason}: the full label clears the passive cue`);
    assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false);
  }
  step("pointer selection and remembered final subtab");
  for (const width of [360, 420]) {
    await setPanelSize(page, width, 520);
    await materials.focus(); await materials.press("Home"); await settle(page);
    const target = await psi.boundingBox(), frame = await libraryTabs.boundingBox();
    // Click the currently visible edge, without Playwright auto-scrolling the whole button first.
    const x = Math.min(frame.x + frame.width - 2, target.x + 4), y = target.y + target.height / 2;
    assert(x >= target.x && x < target.x + target.width, "the pointer targets the partially visible final tab");
    await page.mouse.click(x, y); await settle(page);
    await selectedPsiIsClear(`pointer selection at ${width}px`);
    await page.mouse.move(0, 0); await shot(`library-subtabs-pointer-psi-${width}x520`);
  }
  await setPanelSize(page, 1280, 800); await cue.waitFor({ state: "hidden" });
  await setPanelSize(page, 360, 520); await selectedPsiIsClear("resize preserves selected Psi visibility");
  await page.evaluate(() => {
    window.previewOriginalSubtabsSession = previewHost.session;
    window.previewOldSubtabs = document.querySelector('[data-section="library"]')._view.tabs;
    previewHost.session = "subtabs-rebuilt-session"; previewHost.snapshot();
  });
  await page.locator("[data-tab=library]").click(); await cue.waitFor({ state: "visible" });
  assert(await page.evaluate(() => previewOldSubtabs.disposed && !previewOldSubtabs.root.isConnected &&
    document.querySelector('[data-section="library"]')._view.tabs !== previewOldSubtabs),
  "a Model session rebuild disposes the old navigation and replaces its observed root");
  assert.equal(await libraryTabs.locator(".phc-subtabs-overflow").count(), 1, "rebuild leaves one current cue");
  await page.evaluate(() => { previewHost.session = previewOriginalSubtabsSession; previewHost.snapshot(); });
  await page.locator("[data-tab=library]").click();
  await selectedPsiIsClear("returning to the original Model restores its remembered final tab");
  await page.mouse.move(0, 0); await shot("library-subtabs-remembered-psi-360x520");
  await page.locator("[data-tab=thermal_bridges]").click(); await settle(page);
  const thermalTabs = page.getByRole("tablist", { name: "Thermal Bridges", exact: true });
  assert.equal(await thermalTabs.locator(".phc-subtabs-overflow").isVisible(), false,
    "fitting Types and Schedule tabs have no overflow cue");
  assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false);
  await page.mouse.move(0, 0); await shot("thermal-bridge-types-subtabs-360x520");
  await page.locator("[data-tab=windows]").click();
  await page.locator(".panel-panes").evaluate(node => { node.scrollTop = 0; });
  await settle(page); await shot("window-toolbar-360x520");

  return `PASS: preview on the real panel: 4 viewports, draft through a unit switch, invalid entry, ` +
    `form Escape, refused edit warning, empty, Export, authoring and narrow subtab navigation; evidence in ${output}`;
});
