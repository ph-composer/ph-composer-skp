/* Contextual Layer tools stay reachable from drawing hover without changing segment selection. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-layer-tools-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
check({ name: "assembly_layer_tools", output }, async ({ newPage, step }) => {
    const page = await newPage({ viewport: { width: 1600, height: 900 } });
    step("open the builder fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=builder`);
    await page.locator("[data-tab='assemblies']").click();
    await page.getByRole("button", { name: "Open Wall", exact: true }).click();
    const editor = page.locator(".assembly-editor");
    const target = editor.locator(".assembly-hit-target[data-segment-id='seg_wool_0']");
    const gear = editor.locator("[data-layer-tools-trigger='lyr_board_0']");
    const label = editor.locator("[data-layer-thickness='lyr_board_0']");
    await target.click(); await page.mouse.move(20, 600);
    step("the pointer's cue waits a beat");
    assert.equal(await target.evaluate(node => getComputedStyle(node).transitionProperty), "none",
      "a click's selection shows at once");
    const other = editor.locator(".assembly-hit-target:not([aria-pressed='true'])").first();
    const box0 = await other.boundingBox();
    await page.mouse.move(box0.x + box0.width / 2, box0.y + box0.height / 2);
    assert.equal(await other.evaluate(node => getComputedStyle(node).transitionDelay), "0.12s");
    await page.mouse.move(20, 600);
    assert.equal(await editor.locator(".assembly-toolbar").getByRole("button", { name: "Layer tools", exact: true }).count(), 0);
    assert.equal(await editor.locator(".assembly-toolbar").getByRole("button", { name: "Add Layer", exact: true }).count(), 0);
    const selection = () => editor.locator(".assembly-hit-target[aria-pressed='true']").getAttribute("data-segment-id");
    const writes = () => page.evaluate(() => previewHost.sent.filter(message => message.type === "action.invoke"));
    assert.equal(await gear.evaluate(node => getComputedStyle(node).opacity), "0");
    const before = await label.boundingBox();
    await editor.locator(".assembly-hit-target[data-segment-id='seg_board_0']").hover();
    assert.equal(await gear.evaluate(node => getComputedStyle(node).opacity), "1");
    assert.deepEqual(await label.boundingBox(), before, "revealing the gear never moves the thickness label");
    const box = await gear.boundingBox(), layer = await label.boundingBox();
    // The thin Layer's icon protrudes above/below its row. Descendant hits must retain that Layer.
    for (const y of [box.y + 2, box.y + box.height / 2, box.y + box.height - 2]) {
      await page.mouse.move(layer.x + layer.width / 2, layer.y + layer.height / 2);
      await page.mouse.move(box.x + box.width / 2, y, { steps: 8 });
      assert.equal(await gear.evaluate(node => getComputedStyle(node).opacity), "1");
    }
    await gear.click();
    const menu = editor.getByRole("dialog", { name: "Layer 1 tools", exact: true });
    await menu.waitFor(); await page.mouse.move(20, 600);
    assert.equal(await menu.getByRole("button", { name: "Add outside", exact: true }).count(), 1);
    assert.equal(await menu.getByRole("button", { name: "Add inside", exact: true }).count(), 1);
    assert.equal(await gear.evaluate(node => getComputedStyle(node).opacity), "1", "an open menu holds its gear");
    assert.equal(await selection(), "seg_wool_0"); assert.equal((await writes()).length, 0);
    await menu.getByRole("button", { name: "Interior face air barrier", exact: true }).click();
    await page.waitForFunction(() => {
      const barrier = previewHost.assemblies.records[0].values.air_barrier;
      return barrier && barrier.layer_id === "lyr_board_0";
    });
    assert.equal(await selection(), "seg_wool_0", "Layer tools never redirect segment assignment selection");
    assert.equal((await writes()).length, 1);
    await label.click();
    const field = editor.getByRole("textbox", { name: "Layer 1 thickness", exact: true });
    assert.equal(await gear.evaluate(node => getComputedStyle(node).opacity), "0", "inline input has the whole gutter");
    assert(await field.evaluate(node => {
      const rect = node.getBoundingClientRect();
      return document.elementFromPoint(rect.x + 4, rect.y + rect.height / 2) === node;
    }), "the gear does not cover the inline input text");
    await field.press("Escape");
    await gear.focus(); assert.equal(await gear.evaluate(node => getComputedStyle(node).opacity), "1");
    await gear.press("Enter"); await menu.waitFor(); await page.keyboard.press("Escape");
    assert.equal(await gear.evaluate(node => document.activeElement === node), true);
    step("layer tools at panel widths");
    for (const width of [1600, 900, 420, 280]) {
      await page.setViewportSize({ width, height: 900 });
      await label.hover(); await gear.click();
      const bounds = await menu.boundingBox(), viewport = page.viewportSize();
      assert(bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= viewport.width &&
        bounds.y + bounds.height <= viewport.height, `menu is visible at ${width}px`);
      const close = menu.getByRole("button", { name: "Close Layer 1 tools", exact: true });
      const closeBox = await close.boundingBox();
      await page.screenshot({ path: path.join(output, `assembly-layer-tools-${width}.png`) });
      await page.mouse.click(closeBox.x + closeBox.width / 2, closeBox.y + closeBox.height / 2);
    }
    return `Assembly Layer tools checks passed; screenshots: ${output}`;
});
