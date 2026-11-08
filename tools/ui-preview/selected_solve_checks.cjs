/* Selection-scoped Solve on the real panel with synthetic Zones; geometry/Undo belong to the host. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PANEL_SIZES, setPanelSize, paneFacts, assertPaneFits } = require("./support/pane_fit.cjs");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-solve-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
check({ name: "selected_solve", output }, async ({ newPage, step }) => {
    const page = await newPage({ viewport: { width: 1280, height: 900 } });
    page.setDefaultTimeout(5000);
    step("open the authoring fixture");
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=authoring`);
    const solve = page.getByRole("button", { name: "Solve adjacencies for checked Zones", exact: true });
    assert.equal(await solve.isVisible(), false);
    assert.equal(await page.locator(".phc-heading").getByRole("button", { name: /Solve adjacencies/ }).count(), 0);
    await page.getByRole("checkbox", { name: "Check Living Zone", exact: true }).check();
    await solve.waitFor();
    assert.equal(await solve.isEnabled(), false);
    assert.equal(await page.locator(".phc-checked-zone-count").innerText(), "1 Zone checked");
    await page.getByRole("checkbox", { name: "Check Attic Zone", exact: true }).check();
    assert.equal(await solve.isEnabled(), true);
    await page.getByRole("row", { name: /Wall Outdoors 12/ }).getByRole("checkbox", { name: "Uncheck Wall 1", exact: true })
      .uncheck();
    assert.equal(await solve.isEnabled(), false, "a mixed Zone does not qualify");
    await page.getByRole("checkbox", { name: "Check Living Zone", exact: true }).check();
    step("Solve bar at panel widths");
    for (const width of [1280, 900, 420, 280]) {
      await page.setViewportSize({ width, height: 900 });
      assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth), `no page overflow at ${width}`);
      const bounds = await page.locator(".phc-selection-bar").evaluate(bar => {
        const box = bar.getBoundingClientRect();
        return [...bar.querySelectorAll("button, select")].filter(n => n.getBoundingClientRect().width).every(n => {
          const child = n.getBoundingClientRect();
          return child.left >= box.left && child.right <= box.right && child.bottom <= box.bottom;
        });
      });
      assert(bounds, `all selection controls fit the bar at ${width}`);
      await page.screenshot({ path: path.join(output, `selected-solve-${width}.png`) });
    }
    step("Solve bar at real panel sizes");
    // Real panel sizes (#188), through the shared pane-fit facts: the bar never covers the table's header
    // and is always within reach of the pane's scroll; at the panel minimum it docks beneath the table. The
    // preview's development section after the overview takes 129 px the shipping panel lacks, so the case
    // where the bar floats with Solve in view and nothing scrolls runs at 420 x 900; the host covers 420 x 732.
    for (const [width, height] of [...PANEL_SIZES, [420, 900]]) {
      await setPanelSize(page, width, height);
      const facts = await paneFacts(page);
      const docked = await page.locator(".phc-selection-bar:not([hidden])").evaluate(bar => bar.classList.contains("is-docked"));
      const roomy = width === 420 && height === 900;
      assertPaneFits(facts, "the checked-Zone bar", { inView: roomy });
      if (roomy) {
        assert.equal(docked, false, "the bar floats where the table can spare the room");
        assert.equal(facts.overflowsDown, false, "the pane does not scroll when everything fits");
      }
      if (width === 360 && height === 520) assert.equal(docked, true, "the bar docks at the panel minimum");
      await page.screenshot({ path: path.join(output, `selected-solve-${width}x${height}.png`) });
    }
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.getByLabel("Filter Zones", { exact: true }).fill("Living Zone");
    assert.equal(await page.locator(".phc-checked-zone-count").innerText(), "2 Zones checked");
    await solve.click();
    const request = await page.evaluate(() => window.previewHost.sent.filter(m =>
      m.type === "action.invoke" && m.payload.name === "ph_composer.zones.solve_adjacency").pop());
    assert.deepEqual(request.payload.params.zones.map(z => z.zone_path).sort(), [[100], [200]],
      "fully checked hidden Zones remain in the explicit scope");
    return `Selected Solve checks passed; evidence in ${output}`;
});
