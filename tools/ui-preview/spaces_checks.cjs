/* The Spaces view on the real panel with the synthetic Spaces fixtures: the reference model's rows, sums,
   airflow states and selection bar at representative widths; the Weighting factor column's paint; the
   Spaces modes' header toggles and the readouts in Table options; an empty
   Model; and the unit-switch cost on 300 Spaces (units U1-F1), whose median it prints. SketchUp pixels and
   Chromium 88 remain host checks. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PANEL_SIZES, settle, setPanelSize, paneFacts, assertPaneFits } = require("./support/pane_fit.cjs");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "phc-spaces-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });

async function open(page, fixture) {
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=${fixture}`);
  await page.locator(".phc-overview .phc-table").first().waitFor();
  await page.getByRole("tab", { name: "Spaces" }).click();
  await page.locator(".phc-zone-view:not([hidden]) .phc-table").waitFor();
}

function visibleRows(page) {
  return page.locator(".phc-zone-view:not([hidden]) tr[data-row-key]:not([hidden])");
}

check({ name: "spaces", output }, async ({ newPage, step }) => {
    step("a narrow view opens on identity and preserves a later horizontal pan");
    const narrow = await newPage({ viewport: { width: 360, height: 520 } });
    await open(narrow, "spaces");
    const narrowTable = narrow.locator(".phc-zone-view:not([hidden]) .phc-table-mount");
    assert(await narrowTable.evaluate(node => {
      const frame = node.getBoundingClientRect(), name = node.querySelector("th.col-name").getBoundingClientRect();
      return node.scrollLeft > 0 && name.left >= frame.left && name.right <= frame.right;
    }), "Space names are in the initial viewport");
    await narrow.screenshot({ path: path.join(output, "spaces-narrow-identity.png") });
    await narrowTable.evaluate(node => { node.scrollLeft = 0; });
    await narrow.getByRole("tab", { name: "Faces", exact: true }).click();
    await narrow.getByRole("tab", { name: "Spaces", exact: true }).click();
    assert.equal(await narrowTable.evaluate(node => node.scrollLeft), 0, "returning preserves the user's pan");
    await narrow.close();
    const page = await newPage({ viewport: { width: 1280, height: 900 } });
    page.setDefaultTimeout(5000);

    step("reference model");
    // The reference model: Zone rows with sums, Spaces beneath, the imbalance marker on Living Zone.
    await open(page, "spaces");
    assert.equal(await page.locator(".phc-overview .phc-view-count").textContent(), "2 Zones · 4 Spaces");
    await page.getByRole("button", { name: "Expand all" }).click();
    assert.equal(await visibleRows(page).count(), 16, "2 Zones, 4 Spaces, 5 Volumes and 5 Floor Segments");
    const living = page.locator('.phc-zone-view:not([hidden]) tr[data-row-key=\'["Zone",[100]]\']');
    assert.equal(await living.locator(".phc-row-marker:not([hidden])").count(), 1, "the imbalance marker");
    const loft = page.getByRole("textbox", { name: "Loft supply" });
    assert.equal(await loft.getAttribute("placeholder"), "Zone", "an inheriting Space reads Zone");
    step("Spaces at panel widths");
    for (const width of [1280, 900, 420, 365]) {
      await page.setViewportSize({ width, height: 900 });
      await settle(page);
      assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth), `no page overflow at ${width}`);
      assert.equal((await paneFacts(page, { floating: [] })).sideways, false, `the tab does not scroll sideways at ${width} (#179)`);
      if (width <= 420) {
        assert(await page.evaluate(() => {
          const mount = document.querySelector(".phc-zone-view:not([hidden]) .phc-table-mount");
          return mount.scrollWidth > mount.clientWidth;
        }), `the table scrolls inside its own mount at ${width}`);
      }
      await page.screenshot({ path: path.join(output, `spaces-${width}.png`) });
    }
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.getByRole("checkbox", { name: "Check Hall" }).check();
    const bar = page.locator(".phc-selection-bar:visible");
    await bar.waitFor();
    assert.equal(await bar.locator(".phc-selection-bar-count").textContent(),
      "1 Space, 2 Volumes, 2 Floor Segments checked");
    assert.equal(await page.getByRole("textbox", { name: "Weighting factor for checked Floor Segments" })
      .getAttribute("placeholder"), "Mixed");
    await page.screenshot({ path: path.join(output, "spaces-checked.png") });
    step("shared bar at real panel sizes");
    // The shared bar at real panel sizes (#188): never over the table's header, always within reach of the
    // pane's scroll, docked beneath the table at the panel minimum.
    for (const [width, height] of PANEL_SIZES) {
      await setPanelSize(page, width, height);
      assertPaneFits(await paneFacts(page), "the checked Spaces bar");
      if (width === 360 && height === 520) {
        assert(await bar.evaluate(node => node.classList.contains("is-docked")), "the bar docks at the panel minimum");
      }
    }
    await page.setViewportSize({ width: 1280, height: 900 });

    step("Weighting factor paint");
    // The Weighting factor column's paint: an icon beside 0, 1 and each factor in use starts Mark floor, and
    // while it runs the header shows a pressed glyph that stops it.
    await page.getByRole("checkbox", { name: "Check Hall" }).uncheck();
    await page.getByRole("button", { name: "Weighting factor column menu" }).click();
    const icons = page.locator(".phc-column-menu:visible button[aria-label^='Mark floor at weighting factor']");
    assert(await icons.count() >= 2, "0 and 1 are always offered");
    // The menu fades in once it is placed, a frame after it opens.
    await page.evaluate(async () => {
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      await Promise.all(document.getAnimations().map(animation => animation.finished));
    });
    await page.screenshot({ path: path.join(output, "spaces-paint-menu.png") });
    await page.locator(".phc-column-menu:visible button[aria-label^='Mark floor at weighting factor 1.']").click();
    assert.equal(await page.locator(".phc-column-menu:visible").count(), 0, "choosing a factor closes the menu");
    const glyph = page.getByRole("button", { name: "Mark floor at Weighting factor 1. Click to stop marking" });
    assert.equal(await glyph.getAttribute("aria-pressed"), "true");
    await page.screenshot({ path: path.join(output, "spaces-marking.png") });
    // Escape unwinds one layer at a time: an open menu first, then the tool.
    await page.getByRole("button", { name: "Weighting factor column menu" }).click();
    await page.locator(".phc-column-menu:visible").waitFor();
    await page.keyboard.press("Escape");
    assert.equal(await page.locator(".phc-column-menu:visible").count(), 0, "Escape closes the menu");
    assert.equal(await glyph.getAttribute("aria-pressed"), "true", "and leaves the tool running");
    await glyph.click();
    await glyph.waitFor({ state: "hidden" });

    step("Spaces modes and Table options");
    // The Spaces modes from their column headers, and the readouts and label lines in Table options.
    await open(page, "spaces");
    assert.equal(await page.getByRole("button", { name: "Colour by Ventilation" }).count(), 3);
    await page.getByRole("button", { name: "Colour by Height" }).click();
    await page.locator(".phc-zone-view:not([hidden]) button[aria-label='Colour by Height'][aria-pressed='true']")
      .waitFor();
    await page.getByRole("button", { name: "Table options" }).click();
    await page.locator(".phc-table-options .phc-action-menu-item", { hasText: "Space labels" }).click();
    await page.getByRole("button", { name: "Table options" }).click();
    const options = page.locator(".phc-table-options .phc-action-menu-item:visible");
    await options.filter({ hasText: "Label net volume" }).waitFor();
    assert.equal(await options.filter({ hasText: "Space labels" }).getAttribute("aria-pressed"), "true");
    await page.evaluate(async () => {
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      await Promise.all(document.getAnimations().map(animation => animation.finished));
    });
    await page.screenshot({ path: path.join(output, "spaces-table-options.png") });
    await page.keyboard.press("Escape");

    step("Height from solid");
    // Height from solid from a Volume row: the confirmation shows the solid's volume, the floor area and the height.
    await open(page, "spaces");
    await page.getByRole("button", { name: "Expand all" }).click();
    await page.getByRole("button", { name: "Height of Volume 1 from a solid" }).first().click();
    const height = page.locator("dialog:visible");
    await height.waitFor();
    assert.match(await height.textContent(), /becomes 3 m\./);
    await page.screenshot({ path: path.join(output, "spaces-height-from-solid.png") });
    await height.getByRole("button", { name: "Cancel" }).click();

    step("Create Space review");
    // Create Space's review from SketchUp's context menu: it shows the Spaces view under the shared dialog,
    // says what is accepted and why the rest is left out, and Create closes it.
    for (const width of [1280, 420]) {
      await page.setViewportSize({ width, height: 900 });
      await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=spacescreate`);
      const review = page.locator("dialog.phc-create-space");
      await review.waitFor();
      assert.match(await review.textContent(), /2 Faces in Living Zone become one Space with one Volume/);
      assert.match(await review.textContent(), /2 Faces: The Face is one of the Zone's own Faces\./);
      assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth), `no page overflow at ${width}`);
      await page.screenshot({ path: path.join(output, `spaces-create-${width}.png`) });
    }
    await page.setViewportSize({ width: 1280, height: 900 });
    const name = page.locator("dialog.phc-create-space").getByRole("textbox", { name: "Name", exact: true });
    await name.fill("Kitchen");
    await name.press("Enter");
    await page.locator("dialog.phc-create-space").waitFor({ state: "hidden" });

    step("Zones without Spaces");
    // Zones with no Spaces yet: the Zones and nothing beneath them.
    await open(page, "spacesnone");
    assert.equal(await page.locator(".phc-overview .phc-view-count").textContent(), "2 Zones · 0 Spaces");
    assert.equal(await visibleRows(page).count(), 2);
    step("empty Model");
    // An empty Model: no rows, and the empty table says what to do first.
    await open(page, "spacesempty");
    assert.equal(await visibleRows(page).count(), 0);
    assert.match(await page.locator(".phc-zone-view:not([hidden]) .phc-empty").textContent(), /^No Zones yet\./);

    step("300 Spaces unit switch");
    // 300 Spaces: the median of five unit switches, each from the press to the repainted header, with the
    // Zones open (the default) and with every row open.
    await open(page, "spaceslarge");
    const measure = async label => {
      const times = [];
      for (let run = 0; run < 5; run += 1) {
        // Each run switches to the other system from the one shown, and stops once the changed table has had a
        // frame to paint in; a header that never changes fails within ten seconds rather than hanging the run.
        times.push(await page.evaluate(async () => {
          const header = () => document.querySelector(".phc-zone-view:not([hidden]) th.col-v_sup_m3h");
          const system = header().textContent.includes("cfm") ? "SI" : "IP";
          const unit = system === "IP" ? "cfm" : "m³/h";
          const frame = () => new Promise(resolve => requestAnimationFrame(() => resolve()));
          const start = performance.now();
          document.querySelector(`[data-unit-system="${system}"]`).click();
          while (!header().textContent.includes(unit)) {
            if (performance.now() - start > 10000) throw new Error("The unit header did not change.");
            await new Promise(resolve => setTimeout(resolve, 0));
          }
          await frame();
          await frame();
          return performance.now() - start;
        }));
      }
      times.sort((a, b) => a - b);
      console.log(`Spaces unit switch, 300 Spaces, ${label}: median ${times[2].toFixed(0)} ms ` +
        `(runs ${times.map(time => time.toFixed(0)).join(", ")} ms)`);
    };
    await measure("Zones open");
    await page.getByRole("button", { name: "Expand all" }).click();
    await measure("every row open");
    return `Spaces browser checks passed; evidence in ${output}`;
});
