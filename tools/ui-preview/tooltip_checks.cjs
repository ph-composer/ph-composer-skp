/* One styled tooltip across table, toolbar, drawing and modal surfaces; no competing browser title hint. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-tooltips-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });

check({ name: "tooltip", output }, async ({ newPage, step }) => {
    const page = await newPage({ viewport: { width: 1280, height: 900 } });
    page.setDefaultTimeout(5000);
    const tip = page.getByRole("tooltip");
    async function hint(target, text) {
      await target.hover();
      await tip.waitFor();
      assert.equal(await tip.innerText(), text);
      assert.equal(await page.locator('.row-tooltip:not([hidden])').count(), 1);
      assert.equal(await target.getAttribute("title"), null);
      assert(await target.getAttribute("aria-describedby"));
      assert(await tip.evaluate(node => {
        const box = node.getBoundingClientRect();
        return document.elementFromPoint(box.left + 4, box.top + 4) === node;
      }), "tooltip is above the current work surface");
    }
    step("open the authoring fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=authoring`);
    const type = page.locator(".phc-overview th.col-face_type");
    const palette = type.getByRole("button", { name: "Colour by Face type", exact: true });
    await hint(palette, "Colour by Face type");
    await page.screenshot({ path: path.join(output, "tooltip-table.png") });
    await palette.focus();
    assert.equal(await tip.innerText(), "Colour by Face type");
    await page.keyboard.press("Escape");
    assert.equal(await tip.isVisible(), false);
    await page.getByRole("checkbox", { name: "Check Living Zone", exact: true }).check();
    await page.getByRole("checkbox", { name: "Check Attic Zone", exact: true }).check();
    await hint(page.getByRole("button", { name: "Solve adjacencies for checked Zones", exact: true }),
      "Only fully checked Zones are solved, including those hidden by filters. Check touching neighbours too.");
    await page.screenshot({ path: path.join(output, "tooltip-toolbar.png") });
    const resize = page.getByRole("separator", { name: "Resize Level column", exact: true });
    await resize.focus();
    await tip.waitFor();
    assert.equal(await tip.innerText(), "Drag to resize. Use Left or Right Arrow; Enter resets.");
    await page.locator("[data-tab='library']").click();
    assert.equal(await tip.isVisible(), false, "navigation withdraws a tip from the old pane");

    step("open the inventories fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=inventories`);
    for (const pane of ["overview", "assemblies", "windows", "library", "export"]) {
      await page.locator(`[data-tab='${pane}']`).click();
      assert.equal(await page.locator("body [title], body svg title").count(), 0, `no native title in ${pane}`);
    }
    await page.locator("[data-tab='library']").click();
    await page.getByRole("button", { name: "+ New Material", exact: true }).click();
    const dialog = page.getByRole("dialog", { name: "New Material", exact: true });
    await dialog.waitFor();
    await hint(dialog.getByRole("button", { name: "Close", exact: true }), "Close");
    assert.equal(await tip.evaluate(node => node.closest("dialog").open), true,
      "modal tooltip lives in the native top layer");
    await page.screenshot({ path: path.join(output, "tooltip-modal.png") });
    await dialog.getByRole("button", { name: "Close", exact: true }).click();
    assert.equal(await tip.isVisible(), false);
    assert.equal(await page.locator(".row-tooltip").count(), 1, "the dialog did not create a second layer");
    return `Shared tooltip checks passed; evidence in ${output}`;
});
