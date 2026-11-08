/* Browser gesture/draft evidence only. Ruby and fresh SketchUp establish thermal and native Undo behavior. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-builder-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
check({ name: "builder", output }, async ({ newPage, step }) => {
    step("invalid inline dimensions keep a complete explanation in the minimum pane");
    const minimum = await newPage({ viewport: { width: 360, height: 520 } });
    await minimum.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=builder`);
    await minimum.locator("[data-tab=assemblies]").click();
    await minimum.getByRole("button", { name: "Open Wall", exact: true }).click();
    await minimum.getByRole("button", { name: "Layer 2 thickness", exact: true }).click();
    const input = minimum.getByRole("textbox", { name: "Layer 2 thickness", exact: true });
    const before = await input.boundingBox();
    await input.fill("invalid"); await input.press("Enter");
    const explanation = minimum.getByRole("dialog", { name: "Layer 2 thickness", exact: true });
    await explanation.waitFor();
    assert(await explanation.locator(".phc-unit-error").evaluate(node => {
      const box = node.getBoundingClientRect(), frame = document.querySelector(".panel-panes").getBoundingClientRect();
      return box.top >= frame.top && box.bottom <= frame.bottom && box.left >= frame.left && box.right <= frame.right;
    }), "the entire correction fits above the footer");
    assert.deepEqual(await input.boundingBox(), before, "the error does not move the dimension");
    assert(await input.evaluate(node => node === document.activeElement), "typing focus stays in the dimension");
    await minimum.screenshot({ path: path.join(output, "dimension-invalid-minimum.png") });
    await input.press("Escape");
    await explanation.waitFor({ state: "hidden" });
    assert.equal(await minimum.evaluate(() => previewHost.sent.filter(message => message.type === "action.invoke").length), 0);
    await minimum.close();
    const page = await newPage({ viewport: { width: 1280, height: 900 } });
    step("open the builder fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=builder`);
    await page.locator("[data-tab='assemblies']").click();
    await page.getByRole("button", { name: "Open Wall", exact: true }).click();
    const editor = page.locator(".assembly-editor");
    await editor.getByRole("button", { name: "Back to Assemblies", exact: true }).waitFor();
    assert.equal(await editor.locator(".assembly-hit-target").first().evaluate(node =>
      getComputedStyle(node).backgroundColor), "rgba(0, 0, 0, 0)", "hit targets preserve material fills");
    const writes = () => page.evaluate(() => window.previewHost.sent.filter(x => x.type === "action.invoke").length);
    const baseline = await writes();
    await editor.locator("[data-segment-id='seg_stud_0'].assembly-hit-target").click();
    step("Escape cancels removal before changing drawing selection");
    await editor.getByRole("button", { name: "Delete Layer-Segment", exact: true }).click();
    const removal = editor.getByRole("dialog", { name: "Delete Layer-Segment", exact: true });
    await removal.waitFor();
    await page.keyboard.press("Escape");
    await removal.waitFor({ state: "hidden" });
    assert.equal(await editor.locator(".assembly-hit-target[aria-pressed='true']").getAttribute("data-segment-id"),
      "seg_stud_0", "cancelling removal preserves selection");
    assert.equal(await writes(), baseline, "cancelling removal writes nothing");
    await editor.locator("[data-library-row='mat_a']").click();
    const details = editor.getByRole("dialog", { name: "Mineral wool", exact: true });
    await details.getByText("Conductivity", { exact: true }).waitFor();
    assert.equal(await writes(), baseline);
    await details.getByRole("button", { name: "Use on selected target", exact: true }).click();
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.layers[1].segments[1].material_id ===
      "mat_a");
    assert.equal(await writes(), baseline + 1);
    await page.keyboard.press("Escape");
    await editor.getByRole("button", { name: "Layer 2 thickness", exact: true }).click();
    const thickness = editor.getByRole("textbox", { name: "Layer 2 thickness", exact: true });
    await thickness.fill("160");
    step("inline dimension draft");
    // An inline dimension applies its draft when the user leaves it, in the units it was typed in: switching
    // the display units is leaving it, and the value stays 160 mm.
    await page.getByRole("button", { name: "Set display units to IP", exact: true }).click();
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.layers[1].thickness_mm === 160);
    assert.equal(await writes(), baseline + 2);
    await page.getByRole("button", { name: "Set display units to SI", exact: true }).click();
    await editor.getByRole("button", { name: "Layer 2 thickness", exact: true }).click();
    await thickness.fill("170");
    await page.evaluate(() => { window.previewHost.assemblies.records[0].values.layers[1].thickness_mm = 165; });
    await thickness.press("Enter");
    await page.waitForFunction(() => document.querySelector("[data-builder-dimension='thickness:lyr_studs_0']")
      .getAttribute("aria-invalid") === "true");
    assert.equal(await thickness.inputValue(), "170");
    await thickness.press("Escape");
    const beforeDrop = await writes();
    const row = editor.locator("[data-library-row='mat_b']"), target = editor.locator(
      "[data-segment-id='seg_stud_0'].assembly-hit-target");
    const from = await row.boundingBox(), to = await target.boundingBox();
    await page.mouse.move(from.x + 25, from.y + from.height / 2);
    await page.mouse.down();
    await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 12 });
    await page.mouse.up();
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.layers[1].segments[1].material_id ===
      "mat_b");
    assert.equal(await writes(), beforeDrop + 1);
    const beforeInvalid = await writes();
    await row.hover();
    await page.mouse.down();
    await page.mouse.move(15, 15, { steps: 8 });
    await page.mouse.up();
    assert.equal(await writes(), beforeInvalid, "outside drop writes nothing");
    assert.equal(await editor.locator(".assembly-toolbar").getByRole("button",
      { name: "Insert Layer-Segment right", exact: true }).count(), 0);
    const insertBounds = await target.boundingBox();
    await page.mouse.move(insertBounds.x + insertBounds.width - 1, insertBounds.y + insertBounds.height / 2);
    await editor.getByRole("button", { name: "Insert Layer-Segment right", exact: true }).click();
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.layers[1].segments.length === 3);
    step("insert and delete");
    // What the insert made is selected; it has no Material, so deleting it needs no confirmation.
    const added = await page.evaluate(() => window.previewHost.assemblies.records[0].values.layers[1].segments
      .map(segment => segment.id));
    await editor.locator(".assembly-hit-target[aria-pressed='true']").first().waitFor();
    assert.equal(await editor.locator(".assembly-hit-target[aria-pressed='true']").getAttribute("data-segment-id"),
      added[2], "the new Layer-Segment, right of the selection, is selected");
    await editor.locator("[data-builder-action='segments.remove']").click();
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.layers[1].segments.length === 2);
    const groups = await editor.locator(".assembly-toolbar > .assembly-tool-group").evaluateAll(nodes =>
      nodes.map(node => Math.round(node.getBoundingClientRect().top)));
    assert.ok(Math.max(...groups) - Math.min(...groups) < 12, "the toolbar is one row at 1280");
    await editor.getByRole("button", { name: "More drawing actions", exact: true }).click();
    await editor.locator("[data-builder-action='layers.flip_orientation']").click();
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.orientation === "last_layer_outside");
    await editor.locator("select[data-record-field='exterior_condition']").selectOption("Outdoors:ventilated");
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.ventilated_cladding === true);
    assert.equal(await page.evaluate(() => window.previewHost.assemblies.records[0].display.thermal.rse_m2k_w), 0.13);
    assert.equal(await page.evaluate(() => window.previewHost.assemblies.records[0].display.thermal.u_construction_w_m2k), 0.21);
    assert.equal(await page.evaluate(() => window.previewHost.assemblies.records[0].values.exterior_condition), "Outdoors");
    step("builder at panel widths");
    for (const width of [1600, 1280, 900, 420, 280]) {
      await page.setViewportSize({ width, height: 900 });
      await editor.getByRole("button", { name: "Material Library", exact: true }).last().click();
      await page.keyboard.press("Escape");
      const toolbar = editor.locator(".assembly-toolbar");
      const emptyToolbar = await toolbar.boundingBox();
      const drawingBefore = await editor.locator(".assembly-canvas-block").boundingBox();
      await editor.locator("[data-segment-id='seg_stud_0'].assembly-hit-target").click();
      const selectedToolbar = await toolbar.boundingBox();
      const drawingAfter = await editor.locator(".assembly-canvas-block").boundingBox();
      assert.equal(selectedToolbar.height, emptyToolbar.height, `selection keeps toolbar height at ${width}px`);
      // Clicking a drawing below the fold can scroll the pane; measure its position relative to the toolbar.
      assert.equal(drawingAfter.y - selectedToolbar.y, drawingBefore.y - emptyToolbar.y,
        `selection keeps drawing position at ${width}px`);
      const main = await editor.locator(".assembly-editor-main").boundingBox();
      assert.ok(Math.abs(selectedToolbar.x + selectedToolbar.width / 2 - main.x - main.width / 2) < 1,
        `toolbar is centered on the work surface at ${width}px`);
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
        `Builder at ${width}px must scroll the drawing internally`);
      await page.screenshot({ path: path.join(output, `builder-${width}.png`) });
    }
    await editor.getByRole("button", { name: "Back to Assemblies", exact: true }).click();
    await page.getByRole("button", { name: "Open Incomplete roof", exact: true }).click();
    assert.equal(await page.locator(".assembly-editor [data-u-withheld]").count(), 2);
    await page.screenshot({ path: path.join(output, "builder-incomplete.png") });
    return `Builder browser checks passed; screenshots: ${output}`;
});
