/* Material/Assembly browser flows supplement the record contracts; they are not native Undo evidence. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-inventories-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });

check({ name: "inventories", output }, async ({ newPage, step }) => {
    const page = await newPage({ viewport: { width: 1280, height: 800 } });
    step("open the inventories fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=inventories`);
    await page.locator("[data-tab='library']").click();
    const library = page.locator("[data-section='library']");
    await library.getByRole("heading", { name: "Library", exact: true }).waitFor();
    await library.locator(".phc-view-count").getByText("2 total", { exact: true }).waitFor();
    step("inventory housekeeping reveals without moving the row");
    const row = library.locator("[data-row-key='mat_a']");
    const duplicateAction = row.getByRole("button", { name: "Duplicate Mineral wool", exact: true });
    await page.mouse.move(0, 0);
    assert.equal(await duplicateAction.evaluate(node => getComputedStyle(node).opacity), "0");
    const idleBounds = await duplicateAction.boundingBox();
    await row.hover();
    assert.equal(await duplicateAction.evaluate(node => getComputedStyle(node).opacity), "1");
    assert.deepEqual(await duplicateAction.boundingBox(), idleBounds, "hover keeps the action's target still");
    await page.mouse.move(0, 0);
    await duplicateAction.focus();
    assert.equal(await duplicateAction.evaluate(node => getComputedStyle(node).opacity), "1",
      "keyboard focus reveals the row's actions");
    await duplicateAction.press("Enter");
    const keyboardDuplicate = library.getByRole("dialog", { name: /Duplicate Material$/ });
    await keyboardDuplicate.waitFor();
    await page.keyboard.press("Escape");
    await keyboardDuplicate.waitFor({ state: "hidden" });
    assert(await duplicateAction.evaluate(node => node === document.activeElement), "Cancel returns to the action");
    assert.equal(await library.locator("[data-material-use-count]").textContent(), "1");
    await library.locator("[data-material-use-count]").click();
    await library.getByRole("dialog", { name: "Used by Assemblies" }).getByText("Wall", { exact: true }).waitFor();
    await page.keyboard.press("Escape");

    await library.getByRole("button", { name: "Color for Mineral wool: #fff2cc", exact: true }).click();
    const color = library.getByRole("dialog", { name: "Color for Mineral wool", exact: true });
    await color.locator(".phc-color-square").press("ArrowDown");
    await page.locator("[data-tab='assemblies']").click();
    assert.equal(await library.isVisible(), true, "modified color draft keeps its work surface");
    assert.equal(await color.isVisible(), true);
    await color.getByRole("button", { name: /Apply Color$/ }).click();
    await color.waitFor({ state: "hidden" });
    assert.notEqual(await page.evaluate(() => window.previewHost.materials.records[0].values.color), "#fff2cc");

    step("New Material opens with thermal properties blank and sends them unset, in SI and IP");
    const materialForm = library.getByRole("dialog", { name: "New Material", exact: true });
    const thermal = ["Conductivity", "Density", "Specific heat", "Emissivity"];
    for (const system of ["IP", "SI"]) {
      await page.getByRole("button", { name: `Set display units to ${system}`, exact: true }).click();
      await library.getByRole("button", { name: "+ New Material", exact: true }).click();
      for (const name of thermal) {
        assert.equal(await materialForm.getByRole("textbox", { name, exact: true }).inputValue(), "",
          `${name} opens blank in ${system}`);
      }
      assert.equal(await materialForm.getByRole("combobox", { name: "Conductivity input form", exact: true }).inputValue(),
        system === "IP" ? "r_per_in" : "w_mk", `the input form follows ${system}`);
      if (system === "IP") {
        await page.keyboard.press("Escape");
        await materialForm.waitFor({ state: "hidden" });
      }
    }
    await materialForm.getByRole("button", { name: "Wood #c69c6d", exact: true }).click();
    await page.screenshot({ path: path.join(output, "new-material-form.png") });
    await materialForm.getByRole("textbox", { name: "Name", exact: true }).fill("New board");
    await materialForm.getByRole("combobox", { name: "Category", exact: true }).selectOption("woods");
    await materialForm.getByRole("textbox", { name: "Conductivity", exact: true }).fill("0.05 W/(m K)");
    await materialForm.getByRole("textbox", { name: "Conductivity", exact: true }).press("Enter");
    await materialForm.waitFor({ state: "hidden" });
    assert.equal(await page.evaluate(() => window.previewHost.materials.records[2].values.conductivity_w_mk), 0.05);
    const created = await page.evaluate(() => window.previewHost.sent.filter(message => message.type === "action.invoke" &&
      message.payload.name === "ph_composer.assemblies.materials.create").slice(-1)[0].payload.params.values);
    assert.equal(created.color, "#c69c6d");
    assert.deepEqual([created.density_kg_m3, created.specific_heat_j_kgk, created.emissivity], [null, null, null],
      "unset thermal properties are sent as null, never a placeholder");
    const stored = await page.evaluate(() => window.previewHost.materials.records[2].values);
    assert.deepEqual([stored.density_kg_m3, stored.specific_heat_j_kgk, stored.emissivity], [null, null, null]);
    await library.getByRole("button", { name: "Duplicate New board", exact: true }).click();
    const duplicate = library.getByRole("dialog", { name: /Duplicate Material$/ });
    assert.equal(await duplicate.getByRole("checkbox", { name: "Copy datasheet links", exact: true }).isChecked(), false);
    await duplicate.getByRole("button", { name: /Duplicate Material$/ }).click();
    await duplicate.waitFor({ state: "hidden" });
    await library.getByRole("button", { name: "Delete New board (copy)", exact: true }).click();
    const deleteCopy = library.getByRole("dialog", { name: "Delete New board (copy)", exact: true });
    await deleteCopy.getByRole("button", { name: /Delete$/ }).click();
    await deleteCopy.waitFor({ state: "hidden" });

    await library.getByRole("button", { name: "Delete Mineral wool", exact: true }).click();
    const replacement = library.getByRole("dialog", { name: "Replace and delete Mineral wool", exact: true });
    await replacement.getByText("Used by: Wall", { exact: true }).waitFor();
    assert.equal(await replacement.getByRole("button", { name: /Replace and delete$/ }).isDisabled(), true);
    await replacement.getByRole("combobox", { name: "Replacement material", exact: true }).selectOption("mat_b");
    await replacement.getByRole("button", { name: /Replace and delete$/ }).click();
    await replacement.waitFor({ state: "hidden" });
    assert.equal(await page.evaluate(() => window.previewHost.materials.records[0].use_count), 1);

    const wood = library.locator("[data-row-key='mat_b'] [data-record-field='conductivity_w_mk']");
    await wood.dblclick();
    await wood.fill("0.13");
    await page.evaluate(() => { window.previewHost.materials.records[0].values.conductivity_w_mk = 0.14; });
    await wood.press("Enter");
    await page.waitForFunction(() => document.querySelector("[data-section='library']")._view.surface("materials")
      .inventory.edits.cells["mat_b:conductivity_w_mk"].status === "error");
    assert.equal(await wood.inputValue(), "0.13");
    await page.getByRole("button", { name: "Set display units to IP", exact: true }).click();
    assert.equal(await wood.inputValue(), "0.13", "refused draft keeps its starting units");
    await library.getByRole("tab", { name: "Attached zones", exact: true }).click();
    assert.equal(await library.getByRole("tab", { name: "Materials", exact: true }).getAttribute("aria-selected"), "true");
    await page.locator("[data-tab='assemblies']").click();
    assert.equal(await library.isVisible(), true);
    await page.screenshot({ path: path.join(output, "material-refusal.png") });
    await wood.press("Escape");
    await page.getByRole("button", { name: "Set display units to SI", exact: true }).click();
    await library.getByRole("heading").click();
    await library.getByRole("tab", { name: "Attached zones", exact: true }).click();
    const attached = library.locator("[data-row-key='atz_a'] [data-record-field='name']");
    await attached.dblclick();
    await attached.fill("Carport");
    await attached.press("Enter");
    await page.waitForFunction(() => window.previewHost.attachedZones[0].values.name === "Carport");
    assert.equal(await page.evaluate(() => window.previewHost.sent.filter(message =>
      message.type === "action.invoke").slice(-1)[0].payload.name), "ph_composer.zones.faces.attached_zone.save");
    await library.getByRole("heading").click();
    await library.getByRole("tab", { name: "Materials", exact: true }).click();

    await page.locator("[data-tab='assemblies']").click();
    const assemblies = page.locator("[data-section='assemblies']");
    await assemblies.getByRole("heading", { name: "Assemblies", exact: true }).waitFor();
    await assemblies.locator(".phc-view-count").getByText("2 total", { exact: true }).waitFor();
    assert((await assemblies.locator("[data-u-withheld]").getAttribute("aria-label")).includes("Choose a Material"));
    await assemblies.getByRole("button", { name: "Open Wall", exact: true }).click();
    await assemblies.getByRole("button", { name: "Back to Assemblies", exact: true }).click();
    const type = assemblies.locator("[data-row-key='asm_a'] [data-record-field='type']");
    assert.equal(await type.inputValue(), "Wall");
    await type.selectOption("RoofCeiling");
    await page.waitForFunction(() => window.previewHost.assemblies.records[0].values.type === "RoofCeiling");
    await assemblies.getByRole("button", { name: "+ New Assembly", exact: true }).click();
    step("New Assembly opens the Builder");
    // New acts at once: the Assembly exists under a free name and opens in the Builder, its title ready to rename.
    await assemblies.getByRole("button", { name: "Back to Assemblies", exact: true }).waitFor();
    assert.equal(await assemblies.locator(".assembly-name input").inputValue(), "Assembly 1");
    assert.equal(await assemblies.locator(".assembly-name input").evaluate(node => node === document.activeElement), true);
    await assemblies.getByRole("button", { name: "Back to Assemblies", exact: true }).click();
    await assemblies.getByRole("button", { name: "Duplicate Assembly 1", exact: true }).click();
    await assemblies.getByRole("button", { name: "Delete Assembly 1 (copy)", exact: true }).waitFor();
    await assemblies.getByRole("button", { name: "Delete Assembly 1 (copy)", exact: true }).click();
    const deleteAssembly = assemblies.getByRole("dialog", { name: "Replace and delete Assembly 1 (copy)", exact: true });
    assert.equal(await deleteAssembly.locator("button[type=submit]").isDisabled(), true);
    await deleteAssembly.getByRole("combobox", { name: "Replacement assembly", exact: true }).selectOption("__clear__");
    await deleteAssembly.getByRole("button", { name: /Replace and delete$/ }).click();
    await deleteAssembly.waitFor({ state: "hidden" });
    assert.equal(await page.evaluate(() => window.previewHost.assemblies.records.length), 3);

    step("panes at panel widths");
    for (const width of [1280, 900, 420, 280]) {
      await page.setViewportSize({ width, height: 800 });
      for (const pane of ["assemblies", "library"]) {
        await page.locator(`[data-tab='${pane}']`).click();
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
          `${pane} at ${width}px must scroll the table internally`);
        await page.screenshot({ path: path.join(output, `${pane}-${width}.png`) });
      }
    }
    return `inventories browser checks passed; screenshots: ${output}`;
});
