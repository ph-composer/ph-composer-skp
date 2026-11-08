/* Managed options layout and modal behavior in the real panel with synthetic data. This does not
   prove native Model transactions, recovery or adoption; those remain SketchUp acceptance gates. */
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
    await page.getByRole("button", { name: "Building-Segment column menu", exact: true }).click();
    await page.getByRole("button", { name: "Manage Building Segments…", exact: true }).click();
  };
  await menu();
  const dialog = page.getByRole("dialog");
  step("Zone options at panel widths");
  for (const width of [1280, 900, 420, 280]) {
    await page.setViewportSize({ width, height: 650 });
    assert(await page.evaluate(() => document.body.scrollWidth <= window.innerWidth), `page width at ${width}`);
    assert(await dialog.evaluate(node => node.scrollWidth <= node.clientWidth), `dialog width at ${width}`);
    assert(await dialog.locator(".phc-zone-option-list").evaluate(node => node.scrollWidth <= node.clientWidth),
      `option rows fit at ${width}`);
    assert(await dialog.locator(".phc-zone-option-default select").evaluate(node => {
      const box = node.getBoundingClientRect(), outer = node.closest("dialog").getBoundingClientRect();
      return box.width > 0 && box.height > 0 && box.left >= outer.left && box.right <= outer.right &&
        box.bottom <= node.closest("dialog").querySelector(".phc-dialog-actions").getBoundingClientRect().top;
    }), `default choice remains visible at ${width}`);
    assert(await dialog.evaluate(node => {
      const controls = node.querySelector(".phc-dialog-actions").getBoundingClientRect();
      const box = node.getBoundingClientRect(); return controls.top >= box.top && controls.bottom <= box.bottom;
    }), `Save and Cancel remain visible at ${width}`);
    await page.screenshot({ path: path.join(output, `management-${width}.png`) });
  }
  await page.setViewportSize({ width: 900, height: 650 });
  const add = await dialog.getByRole("button", { name: "Add", exact: true }).boundingBox();
  assert(add.width < 120, "Add is a small button, not a full-width bar");
  await dialog.getByRole("textbox", { name: "House hex colour", exact: true }).waitFor();
  assert.equal(await dialog.getByRole("group", { name: "House colour palette", exact: true })
    .evaluate(node => node.nextElementSibling.getAttribute("aria-label")), "House custom colour");
  await dialog.getByRole("button", { name: "Add", exact: true }).click();
  assert(await page.evaluate(() => document.activeElement.getAttribute("data-option-name").startsWith("new:")));
  await page.getByRole("textbox", { name: "Building Segment name", exact: true }).fill("Future phase");
  await page.getByRole("button", { name: "Building Segment colour #A95C78", exact: true }).click();
  await page.getByRole("textbox", { name: "House name", exact: true }).fill("North House");
  await page.getByRole("textbox", { name: "House hex colour", exact: true }).fill("#FFFFFF");
  await page.getByRole("textbox", { name: "House name", exact: true }).press("Enter");
  await dialog.waitFor({ state: "detached" });
  assert.equal(await page.getByRole("combobox", { name: "Living Zone Building-Segment", exact: true }).inputValue(), "bsg_house");
  assert.equal(await page.evaluate(() => window.previewHost.zoneOptions.building_segments[0].values.name), "North House");
  assert.equal(await page.evaluate(() => window.previewHost.zoneOptions.building_segments[2].values.colour), "#A95C78");
  assert.equal(await page.getByRole("combobox", { name: "Living Zone Building-Segment", exact: true })
    .evaluate(node => getComputedStyle(node).color), "rgb(17, 17, 17)");
  const count = await page.evaluate(() => window.previewHost.sent.filter(message => message.type === "action.invoke").length);
  await menu();
  await page.getByRole("textbox", { name: "North House name", exact: true }).fill("Cancelled rename");
  await dialog.press("Escape"); await dialog.waitFor({ state: "detached" });
  assert.equal(await page.evaluate(() => window.previewHost.sent.filter(message => message.type === "action.invoke").length), count);
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("aria-label")), "Building-Segment column menu");
  await menu();
  await dialog.getByRole("button", { name: "Merge / Delete", exact: true }).first().click();
  await page.getByRole("combobox", { name: "Replacement for North House", exact: true }).selectOption("bsg_annex");
  await dialog.getByRole("button", { name: "Remove", exact: true }).click();
  await dialog.getByRole("button", { name: /Save$/ }).click();
  await dialog.waitFor({ state: "detached" });
  assert.equal(await page.evaluate(() => window.previewHost.zoneOptions.default_segment_id), "bsg_annex");
  assert(await page.evaluate(() => window.previewHost.zones.every(zone => zone.values.building_segment_id === "bsg_annex")));
  step("clamped column-menu actions remain reachable in the minimum panel");
  await page.setViewportSize({ width: 360, height: 520 });
  await page.goto(`${BASE}?fixture=zoneoptions`);
  const trigger = page.getByRole("button", { name: "Building-Segment column menu", exact: true });
  await trigger.scrollIntoViewIfNeeded();
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await trigger.click();
  const manage = page.getByRole("button", { name: "Manage Building Segments…", exact: true });
  await manage.scrollIntoViewIfNeeded();
  assert(await manage.evaluate(node => {
    const box = node.getBoundingClientRect(), menu = node.closest(".phc-bubble").getBoundingClientRect();
    return box.top >= menu.top && box.bottom <= menu.bottom && box.bottom <= innerHeight;
  }), "the last action scrolls inside its bubble and stays in the window");
  await manage.click();
  await page.getByRole("dialog").getByRole("heading", { name: "Manage Building Segments", exact: true }).waitFor();
  await page.screenshot({ path: path.join(output, "management-minimum.png") });
  await page.keyboard.press("Escape");
  return `Zone options browser checks passed; evidence: ${output}`;
});
