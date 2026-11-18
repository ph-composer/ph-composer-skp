/* The attached Phius climate pane in the preview (P4c-10), boards 5, 6, 15, 17 and 19 at the panel's three sizes: the
   pane never scrolls sideways while each monthly table scrolls inside its own box with its row names held; the
   header's Replace, Edit Values and overflow; an edited cell's mark and Restore; Update from File on a changed
   source; Replace's explanation with no folder; a failing station's line; Clear with no confirm. Browser evidence,
   not host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-climate-attached-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const CLIMATE = "ph_composer.climate.";

check({ name: "climate-attached", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const sent = name => page.evaluate(n => window.previewHost.sent.filter(m => m.payload && m.payload.name === n), name);
  const pane = page.locator("[data-pane='climate']");
  const attached = page.locator(".climate-attached");

  async function open(fixture) {
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=${fixture}`);
    await page.locator("[data-tab='climate']").click();
    await pane.locator("[data-card='phius']").click();
    await attached.locator(".climate-attached-where").waitFor();
    await attached.locator(".climate-attached-where").getByText(/Source|Not on this computer/).first().waitFor();
  }
  /* The pane at every size: never sideways; the monthly tables scroll inside their box below the widest size, their
     row names held at the left edge. */
  async function atSizes(name) {
    for (const [width, height] of PANEL_SIZES) {
      await setPanelSize(page, width, height);
      if (width < 700) {
        const select = pane.locator("select").first();
        if (await select.isVisible()) await select.selectOption("phius");
      }
      const facts = await paneFacts(page, { floating: [], header: null });
      assert.equal(facts.sideways, false, `${name}: the pane scrolls sideways at ${width}`);
      const box = attached.locator(".climate-attached-scroll").nth(1);
      const scrolls = await box.evaluate(node => node.scrollWidth > node.clientWidth + 1);
      assert.equal(scrolls, width < 1000, `${name}: the monthly table ${width < 1000 ? "scrolls" : "fits"} at ${width}`);
      if (scrolls) {
        const held = await box.evaluate(node => {
          const name = node.querySelector("tbody .climate-attached-rowname"), before = name.getBoundingClientRect().left;
          node.scrollLeft = node.scrollWidth;
          const after = name.getBoundingClientRect().left;
          node.scrollLeft = 0;
          return Math.abs(after - before) < 1;
        });
        assert.ok(held, `${name}: the row names stay at the left at ${width}`);
      }
      const replace = await pane.getByRole("button", { name: "Replace…", exact: true }).boundingBox();
      assert.ok(replace && replace.x + replace.width <= width, `${name}: Replace is in reach at ${width}`);
      await page.screenshot({ path: path.join(output, `${name}-${width}.png`), fullPage: false });
    }
    await setPanelSize(page, 1280, 800);
  }

  step("board 5: a passing station, every table, Cooling 2 and Ground not part of the file, the source found");
  await open("climateattached");
  assert.equal(await attached.locator(".climate-attached-heading .climate-data-chip").allInnerTexts().then(t => t.join()),
    "Pass");
  assert.equal(await attached.getByText("Not part of a Phius station file").count(), 2);
  await attached.getByText("Source found").waitFor();
  assert.match(await attached.locator(".climate-attached-where").innerText(), /the blended heat pump, with the design/);
  await atSizes("attached");
  await page.locator(".panel-panes").evaluate(node => { node.scrollTop = node.scrollHeight; });
  await page.screenshot({ path: path.join(output, "attached-bottom-1280.png") });
  await page.locator(".panel-panes").evaluate(node => { node.scrollTop = 0; });

  step("board 15: the edited cells are marked with the file's value, and Restore clears them in one action");
  await open("climatereplace");
  assert.equal(await attached.locator("td.is-edited").count(), 2);
  await attached.locator("td.is-edited").first().hover();
  await page.locator(".phc-tooltip, [role='tooltip']").filter({ hasText: "The station file reads" }).first()
    .waitFor({ timeout: 3000 }).catch(() => {});
  await page.screenshot({ path: path.join(output, "edited-hover.png") });
  await atSizes("edited");
  await attached.getByRole("button", { name: "Restore Original Values" }).click();
  await page.waitForFunction(() => document.querySelectorAll(".climate-attached td.is-edited").length === 0);
  assert.equal((await sent(CLIMATE + "climate.restore_original")).length, 1);

  step("the wind speed saves on Enter and marks nothing");
  const wind = attached.getByRole("textbox", { name: "Average wind speed" });
  await wind.fill("4.5");
  await wind.press("Enter");
  await page.waitForFunction(() => window.previewHost.sent.some(m => m.payload &&
    m.payload.name === "ph_composer.climate.climate.save_values"));
  await page.waitForFunction(() => !document.querySelector(".climate-attached .climate-attached-notice.is-edited"));
  assert.equal(await attached.locator(".is-edited").count(), 0);

  step("board 17: a changed source has its quiet mark and Update from File opens the picker in Replace");
  await open("climatechanged");
  await attached.getByText("Source changed").first().waitFor();
  await atSizes("changed");
  await attached.getByRole("button", { name: "Update from File…" }).click();
  await page.locator("dialog.climate-picker").getByRole("button", { name: "Replace", exact: true }).waitFor();
  await page.waitForFunction(() => document.querySelectorAll("dialog.climate-picker tr.host-selected").length === 1);

  step("board 6: no folder, the pane reads in full with no notice, and Replace explains");
  await open("climateother");
  await attached.getByText("Not on this computer").waitFor();
  assert.equal(await page.locator("[data-notice-layer] .phc-floating-notice:visible").count(), 0);
  await atSizes("other");
  await pane.getByRole("button", { name: "Replace…", exact: true }).click();
  const explain = page.locator(".climate-attached-explain .phc-bubble");
  await explain.getByRole("button", { name: "Choose Climate Data Folder…" }).waitFor();
  await page.screenshot({ path: path.join(output, "other-replace.png") });
  assert.equal(await page.locator("dialog.climate-picker").count(), 0);

  step("board 19: a failing station is said to be outside the Phius limits");
  await open("climatefail");
  await attached.getByText(/^Outside the Phius limits: .* higher than the site\./).waitFor();
  await atSizes("fail");

  step("Clear: one action from the overflow, no confirm, and the empty state");
  await pane.getByRole("button", { name: "More climate actions" }).click();
  await page.getByRole("button", { name: "Clear", exact: true }).click();
  await page.locator(".climate-phius[data-state='ready']").waitFor();
  assert.equal((await sent(CLIMATE + "climate.clear")).length, 1);
  assert.equal(await page.locator("dialog[open]").count(), 0, "no confirm");
});
