/* Climate Data on This Computer and the Phius climate data pane's empty states in the preview (P4c-08), boards 2,
   3, 9, 10 and 14 at the panel's three sizes: the pane's three states, the dialog's rows, Add Folder with its name
   open for editing, a folder not found with Locate, and the Setup view's route to the dialog. Synthetic folders
   only. Browser evidence, not host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-climate-data-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const CLIMATE = "ph_composer.climate.";

check({ name: "climate-data", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const sent = name => page.evaluate(n => window.previewHost.sent.filter(m => m.payload && m.payload.name === n), name);
  const pane = page.locator("[data-pane='climate']");
  const phius = pane.locator(".climate-phius");
  const dialog = page.locator("dialog.climate-data-setup");

  async function openPhius(fixture) {
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=${fixture}`);
    await page.locator("[data-tab='climate']").click();
    await pane.locator("[data-card='phius']").click();
  }
  /* The pane in one state at every size: it never scrolls sideways and its actions stay in the pane. */
  async function paneAtSizes(state, name) {
    await page.waitForFunction(s => document.querySelector(".climate-phius").getAttribute("data-state") === s, state);
    for (const [width, height] of PANEL_SIZES) {
      await setPanelSize(page, width, height);
      const facts = await paneFacts(page, { floating: [], header: null });
      assert.equal(facts.sideways, false, `the ${state} pane scrolls sideways at ${width}`);
      const right = await phius.locator(".climate-empty-actions button").evaluateAll(buttons =>
        Math.max(...buttons.map(button => button.getBoundingClientRect().right)));
      assert.ok(right <= width + 0.5, `the ${state} actions fit at ${width}`);
      await page.screenshot({ path: path.join(output, `${name}-${width}.png`) });
    }
    await setPanelSize(page, 1280, 800);
  }
  /* The dialog at every size, and at 1060 and 800 px either side of where its table stacks: inside the window,
     and its own content never wider than it. */
  async function dialogAtSizes(name) {
    for (const [width, height] of PANEL_SIZES.concat([[1060, 760], [800, 700]])) {
      await setPanelSize(page, width, height);
      const fit = await dialog.evaluate(node => ({ box: node.getBoundingClientRect().toJSON(),
        sideways: node.scrollWidth > node.clientWidth + 1 }));
      assert.ok(fit.box.x >= 0 && fit.box.x + fit.box.width <= width + 0.5, `the dialog fits at ${width}`);
      assert.equal(fit.sideways, false, `the dialog scrolls sideways at ${width}`);
      await page.screenshot({ path: path.join(output, `${name}-${width}.png`) });
    }
    await setPanelSize(page, 1280, 800);
  }

  step("no folder (board 2): why none ships, and Choose Climate Data Folder starts Add");
  await openPhius("climate");
  await paneAtSizes("no_folder", "pane-no-folder");
  await phius.getByRole("heading", { name: "No Phius climate data on this computer" }).waitFor();
  assert.equal(await phius.getByRole("button", { name: "Enter Values by Hand…" }).isDisabled(), true);
  await phius.getByRole("button", { name: "Why Enter Values by Hand is unavailable" }).click();
  await page.getByText("Typing climate values by hand comes in a later version of PH-Composer.").waitFor();
  await page.keyboard.press("Escape");
  await phius.getByRole("button", { name: "Choose Climate Data Folder…" }).click();
  await dialog.waitFor();
  const name = dialog.getByLabel("Dataset name");
  await name.waitFor();
  assert.equal(await name.inputValue(), "Sheets", "the new name is open, prefilled from the folder");
  assert.equal((await sent(CLIMATE + "folders.add")).length, 1);
  await name.fill("Spreadsheets");
  await name.press("Enter");
  await dialog.locator("[data-folder-id='climate_folder_previewccccc']").getByText("Spreadsheets").waitFor();
  assert.deepEqual((await sent(CLIMATE + "folders.rename")).map(m => m.payload.params),
    [{ id: "climate_folder_previewccccc", name: "Spreadsheets" }]);
  await dialog.locator("[data-folder-id='climate_folder_previewccccc']").getByText("No station files").waitFor();
  await dialogAtSizes("dialog-other-formats");
  await dialog.getByRole("button", { name: "Done" }).click();
  await dialog.waitFor({ state: "hidden" });
  await page.waitForFunction(() => document.querySelector(".climate-phius").getAttribute("data-state") === "no_site");

  step("a folder and no site (board 9), and the dialog with a folder not found (boards 3 and 14)");
  await openPhius("climatedata");
  await paneAtSizes("no_site", "pane-no-site");
  await pane.locator(".phc-heading").getByRole("button", { name: "Climate Data on This Computer…" }).click();
  await dialog.locator("[data-found='false']").waitFor();
  assert.equal(await dialog.getByRole("button", { name: /Rescan/ }).count(), 0);
  await dialog.getByText("Custom sets: the folder is not where it was.", { exact: false }).waitFor();
  await dialog.locator("[data-found='true']").getByText("1,150 Excel files · 4 other").waitFor();
  await dialogAtSizes("dialog-not-found");
  await dialog.getByRole("button", { name: "Remove Custom sets" }).click();
  const confirm = page.locator("dialog.phc-confirm-dialog");
  await confirm.getByRole("heading", { name: "Remove Custom sets?" }).waitFor();
  await page.screenshot({ path: path.join(output, "dialog-remove-confirm.png") });
  await confirm.getByRole("button", { name: "Cancel" }).click();
  await dialog.getByRole("button", { name: "Locate Custom sets" }).click();
  await page.waitForFunction(() => !document.querySelector("dialog.climate-data-setup [data-found='false']"));
  assert.equal((await sent(CLIMATE + "folders.locate")).length, 1);
  await dialog.getByRole("button", { name: "Done" }).click();
  await phius.getByRole("button", { name: "Set Location…" }).click();
  await page.locator("dialog.climate-set-location").waitFor();
  await page.locator("dialog.climate-set-location").getByRole("button", { name: "Cancel" }).click();

  step("a folder and a site (board 10): the dataset and its stations; Choose Station waits for the picker");
  await openPhius("climateready");
  await paneAtSizes("ready", "pane-ready");
  await phius.getByText("Preview Stations · 1,007 stations on this computer.").waitFor();
  assert.equal(await phius.getByRole("button", { name: "Choose Station…" }).isDisabled(), true);

  step("the Setup view's entry shows its summary and opens the dialog on the Climate tab");
  await page.locator("[data-tab='setup']").click();
  const entry = page.locator(".phc-setup-entry").filter({ hasText: "1 folder" });
  await entry.waitFor();
  await entry.getByRole("button", { name: "Climate Data on This Computer…" }).click();
  await dialog.waitFor();
  assert.equal(await page.locator("[data-tab='climate']").getAttribute("aria-pressed"), "true");
  await page.screenshot({ path: path.join(output, "setup-route.png") });
});
