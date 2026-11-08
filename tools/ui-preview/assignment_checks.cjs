/* Synthetic browser evidence for assignment controls; SketchUp owns reference and Undo acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-assignment-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
check({ name: "assignment", output }, async ({ newPage, step }) => {
    const page = await newPage({ viewport: { width: 1280, height: 900 } });
    step("open the assignment fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=assignment`);
    const picker = page.getByRole("combobox", { name: "Assembly for selected Faces", exact: true });
    const writes = () => page.evaluate(() => window.previewHost.sent.filter(m => m.type === "action.invoke").length);
    const initial = await page.evaluate(() => window.previewHost.faces.slice(0, 2).map(face => ({ ...face.values })));
    const bar = page.locator(".phc-selection-bar");
    const count = bar.locator(".phc-selection-bar-count");
    await count.getByText("2 Faces selected", { exact: true }).waitFor();
    assert.equal(await page.getByRole("button", { name: "Apply Assembly to selected Faces" }).count(), 0);

    step("choice assigns to checked Faces");
    // A choice assigns at once to every checked Face, and nothing else about them changes.
    assert.equal(await writes(), 0);
    await picker.selectOption("asm_a");
    await page.waitForFunction(() => window.previewHost.faces.slice(0, 2).every(f => f.values.assembly_id === "asm_a"));
    assert.equal(await writes(), 1);
    assert.deepEqual(await page.evaluate(() => window.previewHost.faces.slice(0, 2).map(face => ({ ...face.values }))),
      initial.map(value => ({ ...value, assembly_id: "asm_a" })));

    step("selection replaces checked set");
    // A new SketchUp selection replaces the checked set; Type and Boundary are set from the same bar.
    await page.evaluate(() => {
      window.previewHost.selectedFaces = [window.previewHost.faces[0].reference]; window.previewHost.snapshot();
    });
    await count.getByText("1 Face selected", { exact: true }).waitFor();
    await page.getByRole("combobox", { name: "Boundary for selected Faces", exact: true }).selectOption("Ground");
    await page.waitForFunction(() => window.previewHost.faces[0].values.boundary_condition === "Ground");
    assert.equal(await page.evaluate(() => window.previewHost.faces[0].values.assembly_id), "asm_a");

    step("table choice clears assembly");
    // A table choice clears only assembly_id and preserves the edited boundary and Face type.
    await page.getByRole("row", { name: /^Uncheck Wall 1/ }).getByRole("combobox", { name: "Wall 1 Assembly", exact: true })
      .selectOption("");
    assert.equal(await page.evaluate(() => window.previewHost.faces[0].values.assembly_id), undefined);
    assert.equal(await page.evaluate(() => window.previewHost.faces[0].values.boundary_condition), "Ground");
    await page.getByRole("searchbox", { name: "Filter Zones", exact: true }).fill("Incomplete roof");
    await page.getByRole("textbox", { name: "Attic Zone name", exact: true }).waitFor();
    await page.getByRole("searchbox", { name: "Filter Zones", exact: true }).fill("");

    await page.locator("[data-tab='assemblies']").click();
    const row = page.locator("[data-row-key='asm_b']");
    await row.locator(".col-face_usage").getByText(/1/).waitFor();
    step("Select faces");
    // Select faces checks the Assembly's Faces in the Zones tab's Faces view and frames them; SketchUp's selection stays.
    const selectedBefore = await page.evaluate(() => JSON.stringify(window.previewHost.selectedFaces));
    await row.getByRole("button", { name: "Select faces using Incomplete roof", exact: true }).click();
    await count.getByText("1 Face selected", { exact: true }).waitFor();
    assert.equal(await page.evaluate(() => JSON.stringify(window.previewHost.selectedFaces)), selectedBefore);
    const beforePaint = await writes();
    await page.locator("[data-tab='assemblies']").click();
    await row.getByRole("button", { name: "Paint Incomplete roof onto faces", exact: true }).click();
    step("painting stays on the Assemblies table");
    // Painting happens in the viewport: the panel stays where Paint was pressed, and the row shows it is on.
    const stop = row.getByRole("button", { name: "Stop painting Incomplete roof", exact: true });
    await stop.waitFor();
    assert.equal(await stop.getAttribute("aria-pressed"), "true");
    assert.equal(await page.locator("[data-pane='assemblies']").isVisible(), true);
    assert.deepEqual(await page.evaluate(() => window.previewHost.palette.palette), { assembly_id: "asm_b" });
    assert.equal(await writes(), beforePaint);
    // The Faces view keeps showing it, and the checked controls survive it.
    await page.locator("[data-tab='overview']").click();
    await page.getByRole("button", { name: "Paint Assembly: Incomplete roof. Click to stop painting", exact: true }).waitFor();
    assert.equal(await picker.isVisible(), true);
    await page.locator("[data-tab='assemblies']").click();
    await stop.click();
    await row.getByRole("button", { name: "Paint Incomplete roof onto faces", exact: true }).waitFor();
    assert.equal(await page.evaluate(() => window.previewHost.palette.active), false);
    step("replace and delete");
    await row.getByRole("button", { name: "Replace and delete Incomplete roof", exact: true }).click();
    const dialog = page.getByRole("dialog", { name: "Replace and delete Incomplete roof", exact: true });
    await dialog.getByText("Moves every Face that uses Incomplete roof to the Assembly you choose, or leaves them with none, then deletes Incomplete roof.", { exact: true }).waitFor();
    const listed = await dialog.getByText(/1 Face:/).textContent();
    assert(/^1 Face: .+ · .+ \d+$/.test(listed) && !listed.includes("["), listed);
    assert(await dialog.getByRole("button", { name: /Replace and delete$/ }).isDisabled());
    await dialog.getByRole("combobox", { name: "Replacement assembly", exact: true }).selectOption("asm_a");
    await dialog.getByRole("button", { name: /Replace and delete$/ }).click();
    await dialog.waitFor({ state: "hidden" });
    assert.equal(await writes(), beforePaint + 1);
    assert.equal(await page.evaluate(() => window.previewHost.faces.filter(f => f.values.assembly_id === "asm_b").length), 0);
    step("panes at panel widths");
    for (const width of [1280, 900, 420, 280]) {
      await page.setViewportSize({ width, height: 900 });
      for (const pane of ["overview", "assemblies"]) {
        await page.locator(`[data-tab='${pane}']`).click();
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${pane} ${width}px`);
        await page.screenshot({ path: path.join(output, `${pane}-${width}.png`) });
      }
    }
    return `assignment browser checks passed; screenshots: ${output}`;
});
