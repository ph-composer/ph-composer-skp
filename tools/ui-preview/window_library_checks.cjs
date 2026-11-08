"use strict";
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path");
const { check } = require("./support/browser_evidence.cjs");
const port = process.env.UI_PREVIEW_PORT || "8765";
const directory = fs.mkdtempSync(path.join(os.tmpdir(), "phc-window-libraries-"));
console.log("Evidence: " + directory);
check({ name: "window_library", output: directory }, async ({ newPage, step }) => {
  for (const width of [1280, 900, 420, 280]) {
    const page = await newPage({ viewport: { width, height: 900 } });
    step(`window library: ${width}px`);
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=windows`);
    await page.getByRole("button", { name: "Window Types", exact: true }).click();
    const pane = page.locator("[data-pane=windows]");
    const writes = () => page.evaluate(() => previewHost.sent.filter(item => item.type === "action.invoke").length);
    async function chooseProvider(sidebar) {
      if (await sidebar.locator(".library-sidebar-content").isHidden()) {
        await sidebar.locator(".library-sidebar-toggle").click();
      }
      await sidebar.getByRole("combobox", { name: "Library source", exact: true }).selectOption("window_products");
      await sidebar.locator(".library-sidebar-row-button").first().waitFor();
    }
    async function drop(source, target) {
      await source.scrollIntoViewIfNeeded(); const start = await source.boundingBox();
      await page.mouse.move(start.x + start.width / 2, start.y + start.height / 2); await page.mouse.down();
      await page.mouse.move(start.x + start.width / 2 + 10, start.y + start.height / 2 + 10);
      await target.scrollIntoViewIfNeeded(); const end = await target.boundingBox();
      await page.mouse.move(end.x + end.width / 2, end.y + end.height / 2, { steps: 5 }); await page.mouse.up();
    }
    const frames = pane.locator(".library-sidebar-root[aria-label='Frame Library']");
    await chooseProvider(frames);
    const before = await writes();
    await drop(frames.locator(".library-sidebar-row-button").first(),
      pane.locator(".window-frame-target[data-element-id=wel_a][data-frame-side=top]"));
    await pane.locator(".window-frame-target[data-element-id=wel_a][data-frame-side=top]")
      .getByText(/^Library /).waitFor();
    assert.strictEqual(await writes(), before + 1);
    await pane.getByRole("combobox", { name: "Product Library" }).selectOption("glazings");
    const glazings = pane.locator(".library-sidebar-root[aria-label='Glazing Library']");
    await chooseProvider(glazings);
    await drop(glazings.locator(".library-sidebar-row-button").first(),
      pane.locator(".window-glazing-target[data-element-id=wel_a]"));
    await pane.locator(".window-glazing-target[data-element-id=wel_a]").getByText(/^Library /).waitFor();
    assert.strictEqual(await writes(), before + 2);
    await page.screenshot({ path: path.join(directory, "builder-" + width + ".png"), fullPage: true });
    await pane.getByRole("button", { name: "Edit Window Type installs" }).click();
    const installs = pane.locator(".window-install-editor"), psi = installs.locator(".library-sidebar-root");
    await chooseProvider(psi);
    const psiRow = psi.locator(".library-sidebar-row-button").first(); await psiRow.scrollIntoViewIfNeeded();
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await psiRow.click();
    await psi.getByRole("button", { name: "Use on selected target" }).click();
    assert.strictEqual(await writes(), before + 2);
    const edge = installs.locator("[data-install-element=wel_a][data-install-side=top]");
    await edge.scrollIntoViewIfNeeded(); const edgeBox = await edge.boundingBox();
    await page.mouse.click(edgeBox.x + edgeBox.width / 2, edgeBox.y);
    await page.screenshot({ path: path.join(directory, "installs-" + width + ".png"), fullPage: true });
    await installs.getByRole("button", { name: "Save Installs", exact: true }).click();
    await installs.waitFor({ state: "hidden" }); assert.strictEqual(await writes(), before + 3);
    const imports = await page.evaluate(() => previewHost.sent.filter(item =>
      item.payload.name === "ph_composer.windows.types.installs.save").pop().payload.params.imports);
    assert.strictEqual(imports.length, 1); assert.strictEqual(imports[0].copy.kind, "psi_install_types");
    await page.getByRole("button", { name: "Library", exact: true }).click();
    await page.getByRole("tab", { name: "Glazings", exact: true }).click();
    const library = page.locator("[data-pane=library]");
    await library.locator(".library-sidebar-root[aria-label='Glazing Library']").waitFor();
    await page.getByRole("tab", { name: "Psi-Install Types", exact: true }).click();
    const settings = library.locator(".phc-inventory-settings:visible");
    const psiDefault = settings.getByRole("button", { name: /^Default Psi-Install: / });
    const depthDefault = settings.getByRole("button", { name: /^Default install depth: / });
    // A long selected name shrinks to an ellipsis inside the panel; at 1280 px, with the Psi-Install
    // Library sidebar open, the defaults stay on the view controls' row.
    await page.evaluate(name => {
      previewHost.windows.psi_install_types.records[0].values.name = name; previewHost.snapshot();
    }, "Synthetic thermally broken masonry sill installation detail");
    await psiDefault.and(page.locator('[data-tooltip*="masonry sill"]')).waitFor();
    for (const control of [psiDefault, depthDefault]) {
      const box = await control.boundingBox(), chevron = await control.locator(".phc-glyph").boundingBox();
      assert.ok(box.x >= 0 && box.x + box.width <= width && chevron.x + chevron.width <= box.x + box.width,
        "a default control and its chevron stay inside the panel at " + width + " px");
    }
    // With no default Type the Model's own value appears, editable, and fits beside the other two.
    await page.evaluate(() => {
      previewHost.windows.settings.default_psi_install_id = null; previewHost.snapshot();
    });
    const valueDefault = settings.getByRole("button", { name: /^Default ψ-install: 0\.04/ });
    await valueDefault.waitFor();
    assert.match(await psiDefault.getAttribute("aria-label"), /Model value$/);
    for (const control of [psiDefault, valueDefault, depthDefault]) {
      const box = await control.boundingBox();
      assert.ok(box.x >= 0 && box.x + box.width <= width, "a default control stays inside the panel at " + width + " px");
    }
    await page.screenshot({ path: path.join(directory, "psi-model-value-" + width + ".png") });
    await page.evaluate(() => {
      previewHost.windows.settings.default_psi_install_id = "psi_a"; previewHost.snapshot();
    });
    await valueDefault.waitFor({ state: "hidden" });
    if (width === 1280) {
      const filter = library.getByRole("searchbox", { name: "Filter Psi-Install Type", exact: true });
      const tops = [psiDefault, depthDefault, filter].map(async control => Math.round((await control.boundingBox()).y));
      assert.strictEqual(new Set(await Promise.all(tops)).size, 1, "the defaults share the view controls' row");
    }
    await psiDefault.click();
    const current = page.getByRole("dialog", { name: "Default Psi-Install", exact: true })
      .locator("button[aria-pressed=true]");
    await page.mouse.move(0, 0); await current.blur();
    assert.strictEqual(await current.evaluate(node => getComputedStyle(node).color),
      await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--interaction-highlight")
        .trim()).then(hex => { const n = parseInt(hex.slice(1), 16);
          return "rgb(" + [n >> 16, (n >> 8) & 255, n & 255].join(", ") + ")"; }),
      "the current Psi-Install choice is marked teal at rest");
    await psiDefault.click();
    await depthDefault.click();
    const depthBubble = page.getByRole("dialog", { name: "Default install depth", exact: true });
    await depthBubble.getByRole("textbox", { name: "Default install depth", exact: true }).waitFor();
    await page.screenshot({ path: path.join(directory, "psi-defaults-" + width + ".png"), fullPage: true });
    await page.keyboard.press("Escape"); await depthBubble.waitFor({ state: "hidden" });
    assert.strictEqual(await writes(), before + 3);
    assert.strictEqual(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    await page.close(); console.log("Window library screens " + width + "px: pass");
  }
});
