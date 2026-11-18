/* The values editor in the preview (P4c-11), board 12 at the panel's three sizes: the dialog stays inside the window
   and never scrolls sideways while its grid scrolls inside its own box with the row names held; Save stays in reach;
   one pasted block fills the grid; Tab and the arrow keys reach every cell; Edit Values opens on an attached
   station and sends one save_values. Browser evidence, not host acceptance. Every value is invented. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-climate-values-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const CLIMATE = "ph_composer.climate.";
// Eight rows of fifteen invented values, each row led by a label as a station file's lines are.
const BLOCK = Array.from({ length: 8 }, (_, r) => ["Series " + r].concat(Array.from({ length: 15 },
  (_, c) => String(r * 20 + c + 0.5))).join("\t")).join("\r\n") + "\r\n";

check({ name: "climate-values", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const sent = name => page.evaluate(n => window.previewHost.sent.filter(m => m.payload && m.payload.name === n), name);
  const pane = page.locator("[data-pane='climate']");
  const editor = page.locator("dialog.climate-values");
  const cells = editor.locator(".climate-values-grid tbody input");

  async function open(fixture) {
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=${fixture}`);
    await page.locator("[data-tab='climate']").click();
    await pane.locator("[data-card='phius']").click();
  }
  /* The dialog at every size: inside the window, never sideways, the grid scrolling in its own box below the widest
     size with the row names held, and Save reachable. */
  async function atSizes(name) {
    for (const [width, height] of PANEL_SIZES) {
      await setPanelSize(page, width, height);
      const fit = await editor.evaluate(node => ({ box: node.getBoundingClientRect().toJSON(),
        sideways: node.scrollWidth > node.clientWidth + 1 }));
      assert.ok(fit.box.x >= 0 && fit.box.x + fit.box.width <= width + 0.5, `${name}: the dialog fits at ${width}`);
      assert.equal(fit.sideways, false, `${name}: the dialog scrolls sideways at ${width}`);
      const grid = await editor.locator(".climate-values-scroll").evaluate(node => {
        const row = node.querySelector("tbody .climate-attached-rowname"), before = row.getBoundingClientRect().left;
        const wide = node.scrollWidth > node.clientWidth + 1;
        node.scrollLeft = node.scrollWidth;
        const held = Math.abs(row.getBoundingClientRect().left - before) < 1;
        node.scrollLeft = 0;
        return { wide, held };
      });
      if (width < 1280) assert.ok(grid.wide, `${name}: the grid scrolls in its box at ${width}`);
      assert.ok(grid.held, `${name}: the row names stay at the left at ${width}`);
      const save = editor.getByRole("button", { name: "Save", exact: true });
      await save.scrollIntoViewIfNeeded();
      const box = await save.boundingBox();
      assert.ok(box && box.x + box.width <= width && box.y + box.height <= height, `${name}: Save in reach at ${width}`);
      await page.screenshot({ path: path.join(output, `${name}-${width}.png`) });
    }
    await setPanelSize(page, 1280, 800);
  }

  step("board 12: Enter Values by Hand opens the editor with no folder and no site needed");
  await open("climate");
  await pane.getByRole("button", { name: "Enter Values by Hand…" }).click();
  await editor.getByRole("heading", { name: "Enter Phius climate values" }).waitFor();
  assert.equal(await cells.count(), 120);
  await atSizes("hand");

  step("one paste of a labelled block fills all 120 cells");
  await cells.first().focus();
  await cells.first().evaluate((node, text) => {
    const data = new DataTransfer();
    data.setData("text/plain", text);
    node.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
  }, BLOCK);
  assert.equal(await cells.nth(119).inputValue(), String(7 * 20 + 14 + 0.5));
  await editor.getByText("Pasted 8 rows.").waitFor();
  await page.screenshot({ path: path.join(output, "hand-pasted-1280.png") });

  step("Tab reaches the grid from the fields and the arrow keys move inside it");
  await editor.getByRole("textbox", { name: "Longitude" }).focus();
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("aria-label")),
    "Outdoor temperature, Jan");
  await page.keyboard.press("ArrowDown");
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("aria-label")), "North, Jan");
  for (let i = 0; i < 14; i += 1) await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("aria-label")), "North, Cooling");

  step("the name and the station elevation enable Save, which sends one enter_values");
  const save = editor.getByRole("button", { name: "Save", exact: true });
  assert.equal(await save.isDisabled(), true);
  await editor.getByRole("textbox", { name: "Name" }).fill("Invented Street");
  await editor.getByRole("textbox", { name: "Station elevation" }).fill("92");
  await save.click();
  const entered = await sent(CLIMATE + "climate.enter_values");
  assert.equal(entered.length, 1);
  assert.equal(entered[0].payload.params.values.monthly.sky_c[11], 7 * 20 + 11 + 0.5);

  step("board 15: Edit Values on an attached station sends one save_values");
  await open("climateattached");
  await page.locator(".climate-attached-where").waitFor();
  await pane.getByRole("button", { name: "Edit Values…" }).click();
  await editor.getByRole("heading", { name: "Edit climate values" }).waitFor();
  assert.equal(await editor.getByRole("textbox", { name: "Name" }).getAttribute("readonly"), "");
  await atSizes("edit");
  await cells.nth(0).fill("-30");
  await editor.getByRole("button", { name: "Save", exact: true }).click();
  const edited = await sent(CLIMATE + "climate.save_values");
  assert.equal(edited.length, 1);
  assert.equal(edited[0].payload.params.values.monthly.air_c[0], -30);
});
