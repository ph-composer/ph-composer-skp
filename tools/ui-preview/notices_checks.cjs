/* Notices close on Escape, popovers and cell messages clear a table's overflow, tooltips keep one size and
   column-header icons line up (issue #367). Layout claims, so they run in a browser. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-notices-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
const BASE = `http://127.0.0.1:${port}/tools/ui-preview/`;
fs.mkdirSync(output, { recursive: true });

/* Every corner and the middle of the box is the box, and nothing else, on screen. */
async function fullyVisible(locator, label) {
  const result = await locator.evaluate(node => {
    const box = node.getBoundingClientRect();
    const points = [[box.left + 6, box.top + 6], [box.right - 6, box.top + 6], [box.left + 6, box.bottom - 6],
      [box.right - 6, box.bottom - 6], [(box.left + box.right) / 2, (box.top + box.bottom) / 2]];
    return { inside: box.left >= 0 && box.top >= 0 && box.right <= innerWidth && box.bottom <= innerHeight,
      hits: points.map(point => node.contains(document.elementFromPoint(point[0], point[1]))) };
  });
  assert.equal(result.inside, true, `${label} is inside the viewport`);
  assert.deepEqual(result.hits, [true, true, true, true, true], `${label} is not covered`);
}

check({ name: "notices", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(5000);
  const notice = page.locator("[data-notice-layer] .phc-floating-notice:not(.phc-recovery)");

  step("a warning closes on its close control and on Escape");
  await page.goto(`${BASE}?fixture=windows`);
  await page.locator("[data-tab='windows']").click();
  async function warn() {
    await page.evaluate(() => {
      const panel = PhComposerUI.get("panel");
      panel.receive({ type: "panel.notice", payload: { session: panel.state.session, tone: "warning",
        message: "Installation topology differs. Nothing was written." } });
    });
    await notice.waitFor();
  }
  await warn();
  await notice.getByRole("button", { name: "Dismiss message", exact: true }).click();
  await notice.waitFor({ state: "hidden" });
  await warn();
  await page.keyboard.press("Escape");
  await notice.waitFor({ state: "hidden" });

  step("the Used by popover clears the rows beneath it");
  await page.goto(`${BASE}?fixture=inventories`);
  await page.locator("[data-tab='library']").click();
  const library = page.locator("[data-section='library']");
  await library.locator("[data-material-use-count]").click();
  const used = library.getByRole("dialog", { name: "Used by Assemblies" });
  await used.waitFor();
  await fullyVisible(used, "the Used by popover");
  await page.screenshot({ path: path.join(output, "used-by.png") });
  await page.keyboard.press("Escape");

  step("a validation message on the last row clears the table's scroller");
  for (const size of [{ width: 1280, height: 800 }, { width: 420, height: 732 }]) {
    await page.setViewportSize(size);
    await page.goto(`${BASE}?fixture=windows`);
    await page.locator("[data-tab='library']").click();
    const pane = page.locator("[data-section='library']");
    await pane.getByRole("tab", { name: "Glazings", exact: true }).click();
    const table = pane.locator(".phc-table:visible");
    const field = table.locator("tbody tr").last().locator("td.col-g_value input");
    await field.click();
    await page.keyboard.type("37");
    await page.keyboard.press("Enter");
    const message = table.locator(".cell-error").filter({ hasText: /./ }).first();
    await message.waitFor({ state: "attached" });
    await field.focus();
    await fullyVisible(message, `the g-value message at ${size.width} wide`);
    await page.screenshot({ path: path.join(output, `cell-error-${size.width}.png`) });
    await page.keyboard.press("Escape");
  }

  step("a tooltip keeps one size however the pointer moves over its icon");
  // The table's help sits near the right edge, where a tooltip would otherwise shrink against the viewport.
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto(`${BASE}?fixture=inventories`);
  await page.locator("[data-tab='library']").click();
  const help = page.locator("[data-section='library'] .phc-grid-toolbar .phc-help:visible").first();
  const tip = page.getByRole("tooltip");
  await help.waitFor();
  // The last tooltip's position is still set when the next one is measured, so start from one at the far edge.
  await page.getByRole("button", { name: "Setup", exact: true }).hover();
  await tip.waitFor();
  const icon = await help.boundingBox();
  await page.mouse.move(icon.x + 2, icon.y + 2);
  await tip.waitFor();
  const first = await tip.boundingBox();
  await page.mouse.move(icon.x + icon.width / 2, icon.y + icon.height / 2);
  await page.mouse.move(icon.x + icon.width - 2, icon.y + icon.height - 2);
  const second = await tip.boundingBox();
  assert.deepEqual([second.width, second.height], [first.width, first.height], "the tooltip keeps one size");
  await page.mouse.move(0, 0);

  step("column-header icons line up whatever the column holds, with room under the label");
  await page.goto(`${BASE}?fixture=authoring`);
  const heading = page.locator(".phc-overview table.has-header-action-row").first();
  const layout = await heading.locator("th.has-header-actions:not([hidden])").evaluateAll(cells => cells.map(cell => {
    const band = cell.querySelector(".phc-header-actions");
    const action = Array.from(band.querySelectorAll("button")).find(node =>
      !node.closest(".phc-bubble") && node.getBoundingClientRect().width);
    const label = cell.querySelector(".phc-th-label");
    return { name: cell.textContent.trim(), inset: action.getBoundingClientRect().left - cell.getBoundingClientRect().left,
      gap: action.getBoundingClientRect().top - label.getBoundingClientRect().bottom };
  }));
  assert.ok(layout.length > 1, "several columns carry header actions");
  layout.forEach(item => {
    assert.ok(item.inset <= 12, `${item.name}: the first icon starts the band (${item.inset})`);
    assert.ok(item.gap >= 2, `${item.name}: the icon clears the label (${item.gap})`);
  });
  return "notices: dismissal, popover, cell message, tooltip and header icons";
});
