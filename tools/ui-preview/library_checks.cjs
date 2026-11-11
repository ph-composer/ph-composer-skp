/* Provider UI acceptance uses public synthetic rows; host Undo and native pickers remain separate gates. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-library-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
async function openRow(page, row) {
  await row.scrollIntoViewIfNeeded();
  // The shared bubble closes on scrolling; let the scroll finish before the user's click.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  await row.click();
}
async function writes(page) {
  return page.evaluate(() => previewHost.sent.filter(item => item.type === "action.invoke").length);
}
/* The screen angle of the title's chevron: right is 0, down 90, left 180, up -90 (its corner is drawn pointing down). */
async function chevronAngle(toggle) {
  return toggle.evaluate((node) => {
    const style = getComputedStyle(node, "::after");
    if (style.display === "none") return null;
    const matrix = new DOMMatrix(style.transform);
    return Math.round(Math.atan2(matrix.b, matrix.a) * 180 / Math.PI) + 45;
  });
}
check({ name: "library_sidebar_title", output }, async ({ newPage, step }) => {
  for (const [width, open, folded] of [[1280, 0, 180], [420, -90, 90]]) {
    step(`sidebar title ${width}px`);
    const page = await newPage({ viewport: { width, height: 900 } });
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=libraries`);
    await page.locator("[data-tab='library']").click();
    const library = page.locator("[data-section='library']");
    const sidebar = library.getByRole("tabpanel", { name: "Materials", exact: true }).locator(".library-sidebar-root");
    const toggle = sidebar.getByRole("button", { name: "Material Library", exact: true });
    if (width < 900) await toggle.click();
    assert.equal(await chevronAngle(toggle), open, "open, the chevron points the way the sidebar folds");
    const gear = sidebar.getByRole("button", { name: "Library setup…", exact: true });
    const [titleBox, gearBox] = [await toggle.boundingBox(), await gear.boundingBox()];
    assert.ok(gearBox.y >= titleBox.y && gearBox.y + gearBox.height <= titleBox.y + titleBox.height + 1, "the gear sits on the title row");
    assert.equal(await sidebar.getByLabel("Library source", { exact: true }).locator("option").first().textContent(),
      "Materials in this file");
    assert.equal(await sidebar.getByText("These records are in the table", { exact: false }).count(), 0);
    await toggle.click();
    assert.equal(await chevronAngle(toggle), folded, "folded, it points the way the sidebar comes back");
    assert.equal(await gear.isVisible(), false, "a folded sidebar is its title alone");
    await page.close();
  }
});
check({ name: "library_hosted_loading", output }, async ({ newPage, step }) => {
  for (const [width, height] of PANEL_SIZES) {
    step(`hosted load ${width}x${height}`);
    const page = await newPage({ viewport: { width, height } });
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=libraries`);
    await page.evaluate(() => { previewHost.holdLibraryLoads = true; });
    await page.locator("[data-tab='library']").click();
    const library = page.locator("[data-section='library']");
    const sidebar = library.getByRole("tabpanel", { name: "Materials", exact: true }).locator(".library-sidebar-root");
    if (width < 900) await sidebar.getByRole("button", { name: "Material Library", exact: true }).click();
    await sidebar.getByLabel("Library source", { exact: true }).selectOption("synthetic");
    const list = sidebar.locator(".library-sidebar-list");
    await list.getByText("Loading library…", { exact: true }).waitFor();
    assert.equal(await list.getAttribute("aria-busy"), "true");
    assert.equal(await sidebar.getByText(/in library/).count(), 0, "no count before the catalog has a total");
    assert.equal(await sidebar.getByText(/undefined|No records in this library/).count(), 0);
    assert.equal(await sidebar.getByRole("button", { name: "Refresh", exact: true }).isVisible(), false);
    await page.screenshot({ path: path.join(output, `library-hosted-loading-${width}.png`), fullPage: true });
    await sidebar.getByRole("button", { name: "Cancel loading", exact: true }).click();
    await sidebar.getByText("Loading was cancelled.", { exact: true }).waitFor();
    await list.getByText("No catalog is available.", { exact: true }).waitFor();
    assert.equal(await page.evaluate(() => previewHost.sent.filter(item => item.type === "setup.invoke" &&
      item.payload.name === "ph_composer.library.cancel_load").length), 1);
    // A refresh that runs over a loaded catalog keeps its rows in view but copies nothing until it ends.
    await sidebar.getByRole("button", { name: "Refresh", exact: true }).click();
    await page.evaluate(() => previewHost.finishLibraryLoad("synthetic"));
    const fiber = sidebar.locator(".library-sidebar-row-button").filter({ hasText: "Synthetic fiber" });
    await fiber.waitFor();
    await sidebar.getByRole("button", { name: "Refresh", exact: true }).click();
    await sidebar.getByRole("button", { name: "Cancel loading", exact: true }).waitFor();
    await openRow(page, fiber);
    const details = sidebar.getByRole("dialog", { name: "Synthetic fiber", exact: true });
    assert.equal(await details.getByRole("button", { name: "Add to file", exact: true }).isDisabled(), true);
    await details.getByText("The library is still loading.", { exact: true }).waitFor();
    await page.evaluate(() => previewHost.finishLibraryLoad("synthetic"));
    await sidebar.getByRole("button", { name: "Refresh", exact: true }).waitFor();
    // The status line it leaves can scroll a narrow pane, and the shared bubble closes on scrolling.
    if (!(await details.isVisible())) await openRow(page, fiber);
    assert.equal(await details.getByRole("button", { name: "Add to file", exact: true }).isDisabled(), false);
    assert.equal(await writes(page), 0);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the pane never scrolls sideways at ${width}`);
    await page.close();
  }
});
check({ name: "library", output }, async ({ newPage, step }) => {
    for (const width of (process.env.LIBRARY_WIDTHS || "1280,900,420,280").split(",").map(Number)) {
      step(`library ${width}px`);
      console.log(`Checking library ${width}`);
      const page = await newPage({ viewport: { width, height: 900 } });
      await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=libraries`);
      await page.locator("[data-tab='library']").click();
      const library = page.locator("[data-section='library']");
      const sidebar = library.getByRole("tabpanel", { name: "Materials", exact: true }).locator(".library-sidebar-root");
      if (width < 900) await sidebar.getByRole("button", { name: "Material Library", exact: true }).click();
      await sidebar.getByLabel("Library source", { exact: true }).selectOption("synthetic");
      const fiber = sidebar.locator(".library-sidebar-row-button").filter({ hasText: "Synthetic fiber" });
      await fiber.waitFor();
      await openRow(page, fiber);
      const details = sidebar.getByRole("dialog", { name: "Synthetic fiber", exact: true });
      await details.getByText("Library: Public insulation", { exact: true }).waitFor();
      assert.equal(await writes(page), 0, "opening a provider row never copies");
      await details.getByRole("button", { name: "Add to file", exact: true }).click();
      await library.locator(".phc-view-count").getByText("3 total", { exact: true }).waitFor();
      assert.equal(await writes(page), 1);
      await details.getByRole("button", { name: "Close Synthetic fiber", exact: true }).click();
      const wool = sidebar.locator(".library-sidebar-row-button").filter({ hasText: "Mineral wool" });
      await openRow(page, wool);
      await sidebar.getByRole("dialog", { name: "Mineral wool", exact: true })
        .getByRole("button", { name: "Add to file", exact: true }).click();
      const review = sidebar.getByRole("dialog", { name: "Review Mineral wool", exact: true });
      await review.waitFor(); assert.equal(await writes(page), 1, "review opens before applying");
      await review.getByText("Local copy / Library copy", { exact: true }).waitFor();
      await review.getByRole("button", { name: "Cancel", exact: true }).click();
      assert.equal(await writes(page), 1, "Cancel leaves the Model unchanged");
      await openRow(page, wool);
      await sidebar.getByRole("dialog", { name: "Mineral wool", exact: true })
        .getByRole("button", { name: "Add to file", exact: true }).click();
      await review.getByRole("button", { name: "Use library copy", exact: true }).click();
      await review.waitFor({ state: "hidden" }); assert.equal(await writes(page), 2);
      await page.keyboard.press("Escape");
      await page.evaluate(() => {
        previewHost.libraryCatalogs.synthetic[1].snapshot.notes = "Later library notes";
      });
      await sidebar.getByRole("button", { name: "Refresh", exact: true }).click();
      await library.getByRole("button", { name: /Mineral wool library source: Synthetic library, source changed/ })
        .waitFor();
      await sidebar.getByLabel("Search material library", { exact: true }).fill("fiber");
      await page.evaluate(() => { previewHost.failLibraryRefresh = true; });
      await sidebar.getByRole("button", { name: "Refresh", exact: true }).click();
      await sidebar.getByText(/last successful catalog, loaded 65 seconds ago/).waitFor();
      await fiber.waitFor(); assert.equal(await sidebar.getByLabel("Search material library").inputValue(), "fiber");
      await sidebar.getByRole("button", { name: "Library setup…", exact: true }).click();
      const setup = sidebar.getByRole("dialog", { name: "Libraries", exact: true });
      await setup.getByText("Synthetic library", { exact: true }).waitFor();
      assert.equal(await setup.innerText().then(text => text.includes("/Users/")), false);
      // Agent access waits folded beneath the libraries until someone opens it.
      assert.equal(await setup.getByRole("button", { name: /^Approve/ }).first().isVisible(), false);
      await setup.getByRole("button", { name: "Done", exact: true }).click();
      assert.equal(await writes(page), 2, "Refresh and setup do not author records");
      await page.screenshot({ path: path.join(output, `library-${width}.png`), fullPage: true });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true,
        `no sideways page scroll at ${width}`);
      await page.close();
    }
    step("Library sidebar in the Assembly editor");
    const page = await newPage({ viewport: { width: 1280, height: 900 } });
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=libraries`);
    await page.locator("[data-tab='assemblies']").click();
    await page.getByRole("button", { name: "Open Wall", exact: true }).click();
    const editor = page.locator(".assembly-editor");
    await editor.locator(".assembly-hit-target[data-layer-id='lyr_studs_0'][data-segment-id='seg_stud_0']").first().click();
    const sidebar = editor.locator(".library-sidebar-root");
    await sidebar.getByLabel("Library source", { exact: true }).selectOption("synthetic");
    await openRow(page, sidebar.locator(".library-sidebar-row-button").filter({ hasText: "Synthetic fiber" }));
    await sidebar.getByRole("button", { name: "Use on selected target", exact: true }).click();
    await page.waitForFunction(() => previewHost.assemblies.records[0].values.layers[1].segments[1]
      .material_id.startsWith("mat_library_"));
    const action = await page.evaluate(() => previewHost.sent.filter(row => row.type === "action.invoke"));
    assert.equal(action.length, 1, "provider Use copies and assigns in one gesture");
    assert.equal(action[0].payload.name, "ph_composer.library.copy");
    assert.equal(action[0].payload.params.assignment.layer_id, "lyr_studs_0");
    assert.equal(action[0].payload.params.assignment.segment_id, "seg_stud_0");
    assert.ok(action[0].payload.params.assignment.expected_values.layers);
    step("disabled dialog actions");
    // A disabled primary or destructive dialog action reads as disabled, not as its enabled fill.
    await page.locator("[data-tab='library']").click();
    await page.evaluate(() => { previewHost.librarySetupState = "unreadable"; previewHost.snapshot(); });
    const materials = page.locator("[data-section='library']").getByRole("tabpanel", { name: "Materials", exact: true });
    await materials.getByRole("button", { name: "Library setup…", exact: true }).click();
    const setup = materials.getByRole("dialog", { name: "Libraries", exact: true });
    step("unreadable setup");
    // An unreadable setup offers only Reset: the ways to add a library stay out of sight.
    assert.equal(await setup.locator(".library-setup-routes").isVisible(), false);
    assert.equal(await setup.getByRole("button", { name: "Add a library…", exact: true }).isVisible(), false);
    const file = setup.getByRole("button", { name: "Done", exact: true });
    // Each fill is read with the button disabled, then enabled, in the apply and the destructive role.
    const fills = (locator, role) => locator.evaluate((node, role) => {
      node.classList.remove("phc-action-apply", "phc-action-delete"); node.classList.add(role);
      const read = disabled => { node.disabled = disabled; return getComputedStyle(node).backgroundColor; };
      const result = { disabled: read(true), enabled: read(false) }; node.disabled = true; return result;
    }, role);
    const apply = await fills(file, "phc-action-apply");
    const destructive = await fills(file, "phc-action-delete");
    assert.notEqual(apply.disabled, apply.enabled, "a disabled primary loses its accent fill");
    assert.equal(destructive.enabled, "rgb(180, 35, 24)", "an enabled destructive action keeps its red fill");
    assert.equal(destructive.disabled, apply.disabled, "a disabled destructive action loses its red fill");
    await file.evaluate(node => node.classList.replace("phc-action-delete", "phc-action-apply"));
    await page.screenshot({ path: path.join(output, "library-setup-unreadable.png"), fullPage: true });
    step("snapshot refresh during rename");
    // A snapshot refresh while an approved location is renamed keeps the draft, its focus and caret, and
    // sends nothing: the browser blurs the field while the list is rebuilt.
    await setup.getByText("Agent access", { exact: true }).click();
    await setup.getByRole("button", { name: "Rename Library export", exact: true }).click();
    const name = setup.getByLabel("Location name", { exact: true });
    await name.fill("Half typed"); await name.press("End");
    await page.evaluate(() => previewHost.snapshot());
    const renames = () => page.evaluate(() => previewHost.sent.filter(row => row.type === "setup.invoke" &&
      row.payload.name === "ph_composer.locations.rename").length);
    assert.equal(await renames(), 0, "a refresh does not submit a rename");
    assert.equal(await name.inputValue(), "Half typed");
    assert.equal(await name.evaluate(node => document.activeElement === node), true, "the draft keeps focus");
    await page.keyboard.type(" name"); await name.press("Enter");
    assert.equal(await renames(), 1);
    await setup.getByText("Half typed name", { exact: true }).waitFor();
    await page.close();
    return `Library checks passed at 1280/900/420/280; evidence: ${output}`;
});
