/* Managed Level options layout and modal behavior in the real panel with synthetic data. Building Segments are
   managed from their heading rows (segment_rows_checks.cjs). This does not prove native Model transactions,
   recovery or adoption; those remain SketchUp acceptance gates. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const BASE = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}/tools/ui-preview/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-zone-options-"));
fs.mkdirSync(output, { recursive: true });
check({ name: "zone_options", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  step("open the zone options fixture");
  await page.goto(`${BASE}?fixture=zoneoptions`);
  await page.getByRole("heading", { name: "Zones", exact: true }).waitFor();
  const menu = async () => {
    await page.getByRole("button", { name: "Level column menu", exact: true }).click();
    await page.getByRole("button", { name: "Manage Levels…", exact: true }).click();
  };
  assert.equal(await page.getByRole("button", { name: "Building-Segment column menu", exact: true }).count(), 0,
    "Building Segments have no column and no Manage dialog");
  await menu();
  const dialog = page.getByRole("dialog");
  step("Level options at panel widths");
  for (const width of [1280, 900, 420, 280]) {
    await page.setViewportSize({ width, height: 650 });
    assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth), `page width at ${width}`);
    assert(await dialog.evaluate(node => node.scrollWidth <= node.clientWidth), `dialog width at ${width}`);
    assert(await dialog.locator(".phc-zone-option-list").evaluate(node => node.scrollWidth <= node.clientWidth),
      `option rows fit at ${width}`);
    assert(await dialog.evaluate(node => {
      const controls = node.querySelector(".phc-dialog-actions").getBoundingClientRect();
      const box = node.getBoundingClientRect(); return controls.top >= box.top && controls.bottom <= box.bottom;
    }), `Save and Cancel remain visible at ${width}`);
    await page.screenshot({ path: path.join(output, `management-${width}.png`) });
  }
  await page.setViewportSize({ width: 900, height: 650 });
  const add = await dialog.getByRole("button", { name: "Add", exact: true }).boundingBox();
  assert(add.width < 120, "Add is a small button, not a full-width bar");
  assert.equal(await dialog.getByRole("group", { name: "Ground colour palette", exact: true })
    .evaluate(node => node.nextElementSibling.getAttribute("aria-label")), "Ground custom colour");
  await dialog.getByRole("button", { name: "Add", exact: true }).click();
  assert(await page.evaluate(() => document.activeElement.getAttribute("data-option-name").startsWith("new:")));
  await page.getByRole("textbox", { name: "Level name", exact: true }).fill("Roof");
  await page.getByRole("button", { name: "Level colour #A95C78", exact: true }).click();
  await page.getByRole("textbox", { name: "Ground name", exact: true }).fill("Basement");
  await page.getByRole("textbox", { name: "Ground name", exact: true }).press("Enter");
  await dialog.waitFor({ state: "detached" });
  assert.equal(await page.getByRole("combobox", { name: "Living Zone Level", exact: true }).inputValue(), "lvl_ground");
  assert.equal(await page.evaluate(() => window.previewHost.zoneOptions.levels[0].values.name), "Basement");
  assert.equal(await page.evaluate(() => window.previewHost.zoneOptions.levels[2].values.colour), "#A95C78");
  const count = await page.evaluate(() => window.previewHost.sent.filter(message => message.type === "action.invoke").length);
  await menu();
  await page.getByRole("textbox", { name: "Basement name", exact: true }).fill("Cancelled rename");
  await dialog.press("Escape"); await dialog.waitFor({ state: "detached" });
  assert.equal(await page.evaluate(() => window.previewHost.sent.filter(message => message.type === "action.invoke").length), count);
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("aria-label")), "Level column menu");
  await menu();
  await dialog.getByRole("button", { name: "Merge / Delete", exact: true }).nth(1).click();
  await page.getByRole("combobox", { name: "Replacement for Upper", exact: true }).selectOption("lvl_ground");
  await dialog.getByRole("button", { name: "Remove", exact: true }).click();
  await dialog.getByRole("button", { name: /Save$/ }).click();
  await dialog.waitFor({ state: "detached" });
  assert(await page.evaluate(() => window.previewHost.zones.every(zone => zone.values.level_id === "lvl_ground")));
  step("clamped column-menu actions remain reachable in the minimum panel");
  await page.setViewportSize({ width: 360, height: 520 });
  await page.goto(`${BASE}?fixture=zoneoptions`);
  const trigger = page.getByRole("button", { name: "Level column menu", exact: true });
  await trigger.scrollIntoViewIfNeeded();
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await trigger.click();
  const manage = page.getByRole("button", { name: "Manage Levels…", exact: true });
  await manage.scrollIntoViewIfNeeded();
  assert(await manage.evaluate(node => {
    const box = node.getBoundingClientRect(), menu = node.closest(".phc-bubble").getBoundingClientRect();
    return box.top >= menu.top && box.bottom <= menu.bottom && box.bottom <= innerHeight;
  }), "the last action scrolls inside its bubble and stays in the window");
  await manage.click();
  await page.getByRole("dialog").getByRole("heading", { name: "Manage Levels", exact: true }).waitFor();
  await page.screenshot({ path: path.join(output, "management-minimum.png") });
  await page.keyboard.press("Escape");
  return `Zone options browser checks passed; evidence: ${output}`;
});
