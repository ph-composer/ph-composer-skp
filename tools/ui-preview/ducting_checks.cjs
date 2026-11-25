/* Ventilation's ducting pills in the preview: Duct Types after Ventilators with a Shape change asking for the new
   dimensions and used length; the Ducting pill's cold-runs line, the assign bar's direction choice and quantity with
   Assign sending the selection's references, the Ducting groups linked in place and New Ducting group; the schedule
   with a finding behind its glyph, totals by direction and by Ventilator, and a row that Locates; Colour by duct
   direction from the Direction header; and the Ventilators table's two duct-length columns contributed by ducting;
   each at the panel's three sizes. Browser evidence; not host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-ducting-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const PREFIX = "ph_composer.ducting.";
const DT1 = "dct_Dd11Tt22Yy33", ERV1 = "vnt_Aa11Bb22Cc33", ERV2 = "vnt_Dd44Ee55Ff66";

check({ name: "ducting", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const host = expression => page.evaluate(expression);
  const sent = name => host(`window.previewHost.sent.filter(m => m.payload && m.payload.name === ${
    JSON.stringify(name)})`);

  step("open Ventilation: Duct Types and Ducting follow Ventilators");
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=mechanical`);
  await page.locator("[data-tab='mechanical']").click();
  const pane = page.locator("[data-pane='mechanical']");
  await pane.getByRole("tab", { name: "Ventilation", selected: true }).waitFor();
  const pills = pane.getByRole("group", { name: "Ventilation tables" });
  assert.deepEqual(await pills.getByRole("button").allTextContents(), ["Ventilators", "Duct Types", "Ducting"]);

  step("Ventilators: ducting's two duct-length columns, a dash with no duct");
  const ventilators = pane.locator(".mech-ventilators-table");
  const ventilator = id => ventilators.locator(`[data-row-key='${id}']`);
  await ventilator(ERV1).waitFor();
  assert.equal(await ventilator(ERV1).locator(".col-outdoor_air_length_m").textContent(), "2.5");
  assert.equal(await ventilator(ERV1).locator(".col-exhaust_air_length_m").textContent(), "1.8");
  assert.equal(await ventilator(ERV2).locator(".col-exhaust_air_length_m").textContent(), "3");
  assert.equal(await ventilator("vnt_Gg77Hh88Ii99").locator(".col-outdoor_air_length_m").textContent(), "—");
  assert.match(await ventilators.locator("th.col-outdoor_air_length_m").textContent(), /Outdoor air duct/);
  await page.screenshot({ path: path.join(output, "ventilators-ducts.png") });

  step("Duct Types: a Shape change asks for the new dimensions, and used length applies the quantity");
  await pills.getByRole("button", { name: "Duct Types" }).click();
  const types = pane.locator(".ducting-types");
  const typeRow = id => types.locator(`[data-row-key='${id}']`);
  await typeRow(DT1).waitFor();
  assert.equal(await typeRow(DT1).locator(".col-used_length_m").textContent(), "4.3");
  assert.match(await typeRow(DT1).locator(".col-width_mm").getAttribute("class"), /mech-inactive/);
  await typeRow(DT1).locator(".col-shape select").selectOption("rectangular");
  const shape = page.getByRole("dialog", { name: "Change DT-1 Round 160 to Rectangular" });
  await shape.getByText("Removes its Diameter.").waitFor();
  await shape.getByLabel("Width").fill("250");
  await shape.getByLabel("Height").fill("120");
  await page.screenshot({ path: path.join(output, "duct-type-shape.png") });
  await shape.getByRole("button", { name: "Change Shape", exact: true }).click();
  await shape.waitFor({ state: "hidden" });
  assert.deepEqual((await sent(PREFIX + "duct_types.update")).pop().payload.params.values,
    { shape: "rectangular", diameter_mm: null, width_mm: 250, height_mm: 120 });
  await pane.getByRole("button", { name: "+ New Duct Type", exact: true }).first().waitFor();

  step("Ducting: the cold-runs line, then the bar's direction and quantity, and Assign sends the selection");
  await pills.getByRole("button", { name: "Ducting" }).click();
  // The line-group parts are shared with piping, so they are found inside the Ducting pill's own surface.
  const ducting = pane.locator("#" + await pills.getByRole("button", { name: "Ducting" })
    .getAttribute("aria-controls"));
  await ducting.getByText("Draw only the two cold runs between each ventilator and the outside").waitFor();
  const bar = ducting.getByRole("region", { name: "Assign to selected lines" });
  await bar.getByText("3 lines selected, 2 assignable").waitFor();
  await bar.getByLabel("Duct Type for selected lines").selectOption(DT1);
  const directions = bar.getByRole("group", { name: "Direction for selected lines" });
  await directions.getByRole("button", { name: "Exhaust air" }).click();
  await directions.getByRole("button", { name: "Exhaust air", pressed: true }).waitFor();
  await bar.getByLabel("Quantity").fill("2");
  await bar.getByRole("button", { name: "Assign", exact: true }).click();
  await page.waitForFunction(() => window.previewHost.ducting.selected[0].values.direction === "exhaust_air");
  const assign = (await sent(PREFIX + "ducts.assign")).pop().payload.params;
  assert.deepEqual([assign.duct_type_id, assign.direction, assign.quantity, assign.targets.length],
    [DT1, "exhaust_air", 2, 2]);
  await page.screenshot({ path: path.join(output, "ducting-bar.png") });

  step("the Ducting groups: a Ventilator chosen in place, and New Ducting group");
  const groups = ducting.locator(".line-group-groups");
  await groups.locator("[data-row-key='720']").waitFor();
  assert.match(await groups.locator("[data-row-key='720'] .col-note").textContent(), /Link it to a Ventilator/);
  await groups.locator("[data-row-key='720'] .col-link select").selectOption(ERV2);
  await page.waitForFunction(() => window.previewHost.ducting.groups[2].values.ventilator_id !== null);
  await bar.getByRole("button", { name: "+ New Ducting group" }).click();
  const dialog = page.getByRole("dialog", { name: "New Ducting group" });
  await dialog.getByLabel("Ventilator").selectOption(ERV1);
  await dialog.getByRole("button", { name: "Create and open" }).click();
  await dialog.waitFor({ state: "hidden" });
  assert.equal((await sent(PREFIX + "groups.create")).length, 1);

  step("the schedule: runs by Ventilator, a finding, totals with the quantity, and a row that Locates");
  const schedule = ducting.locator(".line-group-schedule");
  await schedule.locator("[data-row-key='duct_preview0004#3']").waitFor();
  await schedule.getByRole("button", { name: "1 finding for Exhaust air 1" }).click();
  await page.locator(".line-group-findings").getByText(/has no Duct Type/).waitFor();
  await page.keyboard.press("Escape");
  const totals = ducting.locator(".line-group-totals");
  await totals.getByText("By Ventilator").waitFor();
  assert.equal(await totals.locator(`[data-row-key='${ERV2}'] .col-exhaust_air_length_m`).textContent(), "3");
  await schedule.locator("[data-row-key='duct_preview0001#0'] .col-length_m").click();
  await page.waitForFunction(() => Array.isArray(window.previewHost.locatedDucts));
  await page.screenshot({ path: path.join(output, "ducting.png"), fullPage: true });

  step("Colour by duct direction from the Direction header");
  const toggle = schedule.locator("th.col-direction").getByRole("button", { name: /Colour by/ });
  assert.equal(await toggle.getAttribute("aria-pressed"), "false");
  await toggle.click();
  assert.equal((await sent("ph_composer.colour_by.activate")).pop().payload.params.mode, PREFIX + "by_direction");

  step("Ventilators, Duct Types and Ducting at the panel's three sizes");
  for (const pill of ["Ventilators", "Duct Types", "Ducting"]) {
    await setPanelSize(page, 1280, 800);
    await pills.getByRole("button", { name: pill, exact: true }).click();
    for (const [width, height] of PANEL_SIZES) {
      await setPanelSize(page, width, height);
      assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false,
        `${pill} never scrolls the pane sideways at ${width} x ${height}`);
      await page.screenshot({ path: path.join(output, `${pill.toLowerCase().replace(" ", "-")}-${width}x${height}.png`) });
      if (pill !== "Ducting") continue;
      // A run's findings bubble fits the panel, clear of the table's header, with its Locate in reach.
      const trigger = schedule.getByRole("button", { name: "1 finding for Exhaust air 1" });
      await trigger.scrollIntoViewIfNeeded();
      // A scroll closes an open bubble, so the click waits for the scroll to settle.
      await page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
      await trigger.click();
      const bubble = page.locator(".line-group-findings .line-group-finding");
      await bubble.getByRole("button", { name: "Locate" }).waitFor();
      const box = await bubble.boundingBox(), head = await schedule.locator("thead").boundingBox();
      assert.ok(box.x >= 0 && box.x + box.width <= width, `the findings bubble fits ${width} px`);
      assert.ok(box.y >= head.y + head.height - 1 || box.y + box.height <= head.y + 1,
        `the findings bubble clears the header at ${width} x ${height}`);
      const locate = await bubble.getByRole("button", { name: "Locate" }).boundingBox();
      assert.ok(locate.x >= 0 && locate.x + locate.width <= width && locate.y + locate.height <= height,
        `the bubble's Locate is in reach at ${width} x ${height}`);
      await page.keyboard.press("Escape");
    }
  }
  return `ducting browser checks passed; screenshots: ${output}`;
});
