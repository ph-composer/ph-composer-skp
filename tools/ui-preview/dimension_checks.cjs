/* Shared drawing appearance and a visible, editable inline Assembly dimensions. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-dimensions-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
check({ name: "dimension", output }, async ({ newPage, step }) => {
    const page = await newPage({ viewport: { width: 1600, height: 900 } });
    step("open the builder fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=builder`);
    await page.locator("[data-tab='assemblies']").click();
    await page.getByRole("button", { name: "Open Wall", exact: true }).click();
    const editor = page.locator(".assembly-editor");
    const thicknessField = editor.getByRole("textbox", { name: "Layer 2 thickness", exact: true });
    const thicknessTrigger = editor.locator("[data-layer-thickness='lyr_studs_0']");
    await thicknessTrigger.hover();
    assert.equal(await thicknessField.isVisible(), false, "hover never opens a dimension editor");
    await thicknessTrigger.click();
    assert.equal(await thicknessField.evaluate(node => document.activeElement === node), true);
    await page.mouse.move(20, 600);
    assert.equal(await thicknessField.isVisible(), true, "pointer exit preserves an active input");
    await thicknessField.fill("invalid"); await thicknessField.press("Enter");
    assert.equal(await thicknessField.getAttribute("aria-invalid"), "true");
    await thicknessField.press("Escape");
    await thicknessField.waitFor({ state: "hidden" });
    assert.equal(await thicknessTrigger.evaluate(node => document.activeElement === node), true);
    const thinTrigger = editor.locator("[data-layer-thickness='lyr_board_0']");
    await thinTrigger.click();
    const thinField = editor.getByRole("textbox", { name: "Layer 1 thickness", exact: true });
    const thinBox = await thinField.boundingBox();
    assert.equal(thinBox.width, 52, "a thin Layer uses the compact input");
    assert(await thinField.evaluate(node => {
      const box = node.getBoundingClientRect();
      return document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2) === node;
    }), "the thin Layer input is not covered by its neighbor");
    await thinField.fill("invalid"); await thinField.press("Enter");
    const thinErrorBubble = editor.getByRole("dialog", { name: "Layer 1 thickness", exact: true });
    const thinError = thinErrorBubble.locator(".phc-unit-error");
    await thinErrorBubble.waitFor({ state: "visible" });
    assert.equal(await thinErrorBubble.evaluate(node => node.classList.contains("assembly-dimension-error")), true);
    assert(await thinError.evaluate(node => {
      const box = node.getBoundingClientRect();
      return document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2) === node;
    }), "the inline validation message is visible above neighboring drawing targets");
    assert.equal((await thinField.boundingBox()).x, thinBox.x, "validation does not shift the input");
    assert.equal((await thinField.boundingBox()).y, thinBox.y, "validation does not move the input vertically");
    assert.equal(await thinField.evaluate(node => document.activeElement === node), true,
      "detached validation leaves keyboard focus in the input");
    await page.screenshot({ path: path.join(output, "assembly-inline-thin-layer-invalid.png") });
    await thinField.press("Escape");
    await thinTrigger.click(); await thinField.fill("25");
    const beforeCategory = await page.evaluate(() => previewHost.sent.filter(m => m.type === "action.invoke").length);
    const originalCategory = await page.evaluate(() => {
      const layer = previewHost.assemblies.records[0].values.layers[0];
      const material = previewHost.materials.records.find(record => record.id === layer.segments[0].material_id);
      const category = material.values.category; material.values.category = "membrane";
      previewHost.snapshot(); return category;
    });
    await thinField.waitFor({ state: "visible" });
    assert.equal(await thinField.inputValue(), "25", "category snapshots retain the unfinished draft");
    assert.equal(await thinField.getAttribute("aria-invalid"), "true");
    assert.equal(await thinField.evaluate(node => node.readOnly), true);
    await thinField.press("Enter");
    await editor.getByRole("button", { name: "Back to Assemblies", exact: true }).click();
    assert.equal(await editor.isVisible(), true, "Back remains guarded until the draft is cancelled");
    assert.equal(await thinField.inputValue(), "25");
    assert.equal(await page.evaluate(() => previewHost.sent.filter(m => m.type === "action.invoke").length), beforeCategory);
    await page.screenshot({ path: path.join(output, "assembly-thickness-draft-became-membrane.png") });
    await thinField.press("Escape"); await thinField.waitFor({ state: "hidden" });
    assert.equal(await thinTrigger.textContent(), "Membrane");
    assert.equal(await thinTrigger.evaluate(node => document.activeElement === node), true);
    await thinTrigger.click(); assert.equal(await thinField.isVisible(), false, "clean membranes cannot edit thickness");
    await editor.getByRole("button", { name: "Back to Assemblies", exact: true }).click();
    await page.evaluate(category => {
      const layer = previewHost.assemblies.records[0].values.layers[0];
      previewHost.materials.records.find(record => record.id === layer.segments[0].material_id).values.category = category;
      previewHost.snapshot();
    }, originalCategory);
    await page.getByRole("button", { name: "Open Wall", exact: true }).click();
    await thinTrigger.click(); assert.equal(await thinField.inputValue(), "12"); await thinField.press("Escape");
    await editor.locator("[data-segment-id='seg_wool_0'].assembly-hit-target").click();
    const field = editor.getByRole("textbox", { name: "Layer-Segment width", exact: true });
    async function openWidth(segment) {
      const trigger = editor.locator(`[data-segment-width='${segment}']`);
      await trigger.click();
      const box = await field.boundingBox();
      const viewport = page.viewportSize();
      assert(box && box.x >= 0 && box.y >= 0 && box.x + box.width <= viewport.width &&
        box.y + box.height <= viewport.height, "the inline field stays inside the visible viewport");
      assert(await field.evaluate(node => {
        const box = node.getBoundingClientRect();
        return document.elementFromPoint(box.x + box.width / 2, box.y + box.height / 2) === node;
      }), "the field receives real pointer input, without clipping or an overlay");
      assert.equal(await editor.getByRole("dialog", { name: "Layer-Segment width", exact: true }).count(), 0,
        "a dimension opens in place without a dialog");
    }
    async function cancelWidth() {
      await field.press("Escape"); await field.waitFor({ state: "hidden" });
    }
    await openWidth("seg_wool_0");
    await field.fill("-1"); await field.press("Enter");
    assert.equal(await field.getAttribute("aria-invalid"), "true");
    assert.equal(await page.evaluate(() => previewHost.sent.filter(m => m.type === "action.invoke").length), 0);
    await cancelWidth();
    assert.equal(await field.isVisible(), false, "one Escape restores and closes without resizing");
    await openWidth("seg_wool_0");
    await field.fill("650 mm"); await field.press("Enter");
    await page.waitForFunction(() => previewHost.assemblies.records[0].values.layers[1].segments[0].width_mm === 650);
    await field.waitFor({ state: "hidden" });
    await page.getByRole("button", { name: "Set display units to IP", exact: true }).click();
    await openWidth("seg_wool_0");
    await field.fill("24 in"); await field.press("Enter");
    await page.waitForFunction(() =>
      Math.abs(previewHost.assemblies.records[0].values.layers[1].segments[0].width_mm - 609.6) < 1e-8);
    await field.waitFor({ state: "hidden" });
    await page.getByRole("button", { name: "Set display units to SI", exact: true }).click();
    const drawing = editor.locator(".assembly-canvas-block");
    await page.mouse.move(20, 600);
    async function appearance(root) {
      return root.evaluate(node => {
        const line = getComputedStyle(node.querySelector(".phc-dimension-lines line"));
        const dot = node.querySelector(".phc-dimension-lines circle");
        const value = getComputedStyle(node.querySelector(".phc-dimension-value:not(.is-missing)"));
        return { stroke: line.stroke, weight: line.strokeWidth, dot: getComputedStyle(dot).fill,
          radius: dot.getAttribute("r"), font: value.fontSize };
      });
    }
    const assemblyAppearance = await appearance(drawing);
    await page.screenshot({ path: path.join(output, "assembly-shared-dimensions.png") });
    await editor.locator("[data-segment-id='seg_stud_0'].assembly-hit-target").click();
    step("dimensions at panel widths");
    for (const width of [1600, 900, 420, 280]) {
      await page.setViewportSize({ width, height: 900 });
      await openWidth("seg_stud_0");
      await cancelWidth();
    }
    await page.setViewportSize({ width: 1600, height: 900 });
    step("open the windows fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=windows`);
    await page.locator("[data-tab='windows']").click();
    const canvas = page.locator(".window-canvas:not(.proposed)").first();
    await canvas.waitFor(); await page.mouse.move(20, 600);
    assert.deepEqual(await appearance(canvas), assemblyAppearance, "both Builders share rule, dot and text sizing");
    const width = canvas.getByRole("button", { name: "Column 1 width", exact: true });
    await width.focus(); await width.press("Enter");
    const windowField = page.getByRole("dialog", { name: "Column width", exact: true })
      .getByRole("textbox", { name: "Column width", exact: true });
    await windowField.waitFor(); await windowField.press("Escape");
    return `Shared dimension checks passed; screenshots: ${output}`;
});
