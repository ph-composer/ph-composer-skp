/* Column-header layout on the real panel: labels and actions keep separate baselines while the table
   resizes, scrolls, repaints and switches units. SketchUp pixels remain a separate acceptance check. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-headers-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });

check({ name: "header", output }, async ({ newPage, step }) => {
    const page = await newPage({ viewport: { width: 1280, height: 900 } });
    page.setDefaultTimeout(5000);
    step("open the authoring fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=authoring`);
    const table = page.locator(".phc-overview .phc-table");
    await table.waitFor();
    step("headers at panel widths");
    for (const width of [1559, 1280, 900, 420, 280]) {
      await page.setViewportSize({ width, height: 900 });
      const geometry = await table.locator("th").evaluateAll(headers => headers.filter(h => !h.hidden).map(h => {
        const label = h.querySelector(".phc-th-label");
        const band = h.querySelector(".phc-header-actions");
        return { top: label.getBoundingClientRect().top, bottom: label.getBoundingClientRect().bottom,
          actionsTop: band.getBoundingClientRect().top, actionsHeight: band.getBoundingClientRect().height,
          clipped: label.scrollWidth > label.clientWidth };
      }));
      assert(geometry.every(h => Math.abs(h.top - geometry[0].top) < 1), `aligned labels at ${width}`);
      assert(geometry.every(h => h.actionsTop >= h.bottom && h.actionsHeight === 26), `separate actions at ${width}`);
      if (width >= 1280) assert(geometry.every(h => !h.clipped), `complete default labels at ${width}`);
      assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth), `no page overflow at ${width}`);
      await page.screenshot({ path: path.join(output, `headers-${width}.png`) });
    }
    await page.setViewportSize({ width: 1280, height: 900 });
    const level = table.locator("th.col-level");
    const type = table.locator("th.col-face_type");
    const palette = type.getByRole("button", { name: "Colour by Face type", exact: true });
    const labelBefore = await level.locator(".phc-th-label").boundingBox();
    await palette.focus();
    await page.waitForFunction(() =>
      getComputedStyle(document.querySelector("th.col-face_type .phc-header-action")).opacity === "1");
    assert.equal(await palette.evaluate(node => getComputedStyle(node.closest(".phc-header-action")).opacity), "1");
    await palette.press("Enter");
    await page.waitForFunction(() => document.querySelector('th.col-face_type [aria-pressed="true"]'));
    assert.deepEqual(await level.locator(".phc-th-label").boundingBox(), labelBefore, "pressed mode does not move label");
    await page.locator("h1").first().hover();
    assert.equal(await palette.evaluate(node => getComputedStyle(node.closest(".phc-header-action")).opacity), "1");
    const menu = level.getByRole("button", { name: /Level.*column menu/i });
    await menu.focus();
    await menu.press("Enter");
    await page.getByRole("button", { name: "Sort Z to A", exact: true }).click();
    assert.deepEqual(await level.locator(".phc-th-label").boundingBox(), labelBefore, "sort repaint does not move label");
    await menu.click();
    await page.locator(".phc-column-filter-value").filter({ hasText: "Upper" }).locator("input").uncheck();
    await page.keyboard.press("Escape");
    await page.waitForFunction(() =>
      getComputedStyle(document.querySelector("th.col-level .phc-header-action")).opacity === "1");
    assert.equal(await menu.evaluate(node => getComputedStyle(node.closest(".phc-header-action")).opacity), "1",
      "active filter remains visible at rest");
    await page.screenshot({ path: path.join(output, "headers-active.png") });
    step("Ground depth starts hidden, and says what it does once shown");
    assert.equal(await table.locator("th.col-ground_depth_mm").isHidden(), true);
    await page.getByRole("button", { name: "Table options", exact: true }).click();
    await page.getByRole("button", { name: "Ground depth column", exact: true }).click();
    await page.keyboard.press("Escape");
    await page.locator("[data-unit-system='IP']").click();
    assert.equal(await table.locator("th.col-ground_depth_mm .phc-th-label").innerText(), "Ground depth in");
    assert.match(await table.locator("th.col-ground_depth_mm .phc-th-label").getAttribute("data-tooltip"),
      /Suggest classification sets a Face to Ground/);
    const resize = table.getByRole("separator", { name: "Resize Building-Segment column", exact: true });
    await resize.focus();
    step("resize by keyboard");
    for (let count = 0; count < 8; count += 1) await resize.press("ArrowLeft");
    const actionsFit = await table.locator("th.col-building_segment").evaluate(h => {
      const right = h.getBoundingClientRect().right;
      return [...h.querySelectorAll(".phc-header-action")].every(n => n.getBoundingClientRect().right <= right);
    });
    assert(actionsFit, "resizing keeps both buttons inside their column");
    await resize.press("Enter");
    const mount = page.locator(".phc-overview .phc-zone-view:not([hidden]) .phc-table-mount");
    step("no heading shows a piece of itself as the table scrolls");
    await page.setViewportSize({ width: 800, height: 900 });
    for (const left of [40, 90, 150, 230]) {
      const cut = await mount.evaluate(async (node, scrollTo) => {
        node.scrollLeft = scrollTo;
        await new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)));
        let covered = node.getBoundingClientRect().left;
        const shown = [];
        const pieces = [...node.querySelectorAll("th")].filter(h => !h.hidden).flatMap(h => {
          if (getComputedStyle(h).left !== "auto") { covered = Math.max(covered, h.getBoundingClientRect().right); return []; }
          const label = h.querySelector(".phc-th-label");
          if (getComputedStyle(label).opacity === "0") return [];
          shown.push(label.textContent);
          return label.getBoundingClientRect().left < covered - 0.5 ? [label.textContent] : [];
        });
        return { pieces, shown };
      }, left);
      assert.deepEqual(cut.pieces, [], `no cut heading at scrollLeft ${left}`);
      assert(cut.shown.length > 0, `whole headings still show at scrollLeft ${left}`);
    }
    await page.screenshot({ path: path.join(output, "headers-scrolled.png") });
    await mount.evaluate(node => { node.scrollLeft = 0; });
    await page.setViewportSize({ width: 1280, height: 900 });
    const before = await table.locator("th.col-name").boundingBox();
    await mount.evaluate(node => { node.style.maxHeight = "100px"; node.scrollTop = 100; });
    const after = await table.locator("th.col-name").boundingBox();
    assert.equal(after.y, before.y, "both header bands stay sticky together");
    assert.equal(after.height, before.height);
    return `Column header checks passed; evidence in ${output}`;
});
