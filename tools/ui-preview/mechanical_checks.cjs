/* The Mechanical tab in the preview: the Ventilation subtab and its Ventilators pill, in-place edits, electric
   efficiency in both unit systems, the Zone picker with its replace route, By ventilator from the Serves header,
   the optional values, the Columns menu and the record forms, at the panel's three sizes. Browser evidence; not
   host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-mechanical-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const PREFIX = "ph_composer.mechanical.";
const ERV1 = "vnt_Aa11Bb22Cc33", ERV2 = "vnt_Dd44Ee55Ff66", ERV3 = "vnt_Gg77Hh88Ii99";

/* Scrolls a cell into the table's view and lets the scroll settle before clicking it: a scroll closes an open
   bubble, and Playwright's own scroll-before-click lands after the click opened one. */
async function clickSettled(page, locator) {
  await locator.scrollIntoViewIfNeeded();
  await page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
  await locator.click();
}

check({ name: "mechanical", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const host = expression => page.evaluate(expression);
  const sent = name => host(`window.previewHost.sent.filter(m => m.payload && m.payload.name === ${
    JSON.stringify(name)})`);
  const served = zone => host(`window.previewHost.mechanical.serves[${JSON.stringify(zone)}] || null`);
  const ventilator = id => host(`window.previewHost.mechanical.ventilators.filter(r => r.id === ${
    JSON.stringify(id)})[0].values`);

  step("open the tab: the Ventilation subtab, the Ventilators pill and the table");
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=mechanical`);
  const tabs = await page.locator(".phc-tabs button").allTextContents();
  assert.deepEqual(tabs.slice(tabs.indexOf("Thermal Bridges"), tabs.indexOf("Thermal Bridges") + 3),
    ["Thermal Bridges", "Mechanical", "Library"], "Mechanical sits after Thermal Bridges, before Library");
  await page.locator("[data-tab='mechanical']").click();
  const pane = page.locator("[data-pane='mechanical']");
  await pane.getByRole("heading", { name: "Mechanical", exact: true }).waitFor();
  await pane.getByRole("tab", { name: "Ventilation", selected: true }).waitFor();
  await pane.getByRole("group", { name: "Ventilation tables" }).getByRole("button", { name: "Ventilators",
    pressed: true }).waitFor();
  const table = pane.locator(".mech-ventilators-table");
  const rowOf = id => table.locator(`[data-row-key='${id}']`);
  await rowOf(ERV1).waitFor();
  assert.equal(await rowOf(ERV1).locator(".col-supply_m3h").textContent(), "60");
  assert.match(await rowOf(ERV1).locator(".col-supply_m3h").getAttribute("class"), /is-imbalanced/);
  assert.equal(await rowOf(ERV2).locator(".col-extract_m3h").textContent(), "40");
  assert.equal(await rowOf(ERV3).locator(".col-supply_m3h").textContent(), "—");
  await page.screenshot({ path: path.join(output, "ventilators.png") });

  step("edit a value in place, and see electric efficiency in W/cfm under IP");
  const efficiency = id => rowOf(id).locator("[data-record-field='electric_efficiency_wh_m3']");
  await efficiency(ERV3).dblclick();
  await efficiency(ERV3).fill("0.3");
  await efficiency(ERV3).press("Enter");
  await page.waitForFunction(id => window.previewHost.mechanical.ventilators.filter(r => r.id === id)[0]
    .values.electric_efficiency_wh_m3 === 0.3, ERV3);
  const update = (await sent(PREFIX + "ventilators.update")).pop().payload.params;
  assert.deepEqual(update.expected_values, { electric_efficiency_wh_m3: 0.24 });
  await page.getByRole("button", { name: "Set display units to IP", exact: true }).click();
  assert.equal(await efficiency(ERV1).inputValue(), "0.76");
  assert.match(await table.locator("th.col-electric_efficiency_wh_m3").textContent(), /W\/cfm/);
  await page.screenshot({ path: path.join(output, "ventilators-ip.png") });
  await page.getByRole("button", { name: "Set display units to SI", exact: true }).click();
  assert.equal(await efficiency(ERV1).inputValue(), "0.45");

  step("the Zone picker: assign, refused naming the Ventilator, then Replace and assign");
  await clickSettled(page, rowOf(ERV3).locator(".mech-serves-cell"));
  const picker = page.getByRole("dialog", { name: "Zones served by ERV-3 Spare" });
  await picker.waitFor();
  assert.deepEqual(await picker.locator(".mech-zone-group span").allTextContents(),
    ["Apartments", "House", "School"]);
  await picker.locator(".mech-zone-row").filter({ hasText: "Apt 1" }).locator("input").check();
  await picker.getByText("ERV-1, will be replaced").waitFor();
  await page.screenshot({ path: path.join(output, "zone-picker.png") });
  await picker.getByRole("button", { name: "Assign 1 Zone", exact: true }).click();
  await picker.locator(".mech-zone-status").getByText(/served by ERV-1/).waitFor();
  assert.equal(await served("zon_apt1"), ERV1, "a refused assign writes nothing");
  await page.screenshot({ path: path.join(output, "zone-picker-refused.png") });
  await picker.getByRole("button", { name: "Replace and assign", exact: true }).click();
  await picker.waitFor({ state: "hidden" });
  assert.equal(await served("zon_apt1"), ERV3);
  assert.equal((await sent(PREFIX + "serves.assign")).pop().payload.params.replace, true);
  await rowOf(ERV1).locator(".mech-zone-chip.is-empty").waitFor();

  step("a Segment heading takes all its Zones, and unchecking clears");
  await clickSettled(page, rowOf(ERV2).locator(".mech-serves-cell"));
  const second = page.getByRole("dialog", { name: "Zones served by ERV-2" });
  await second.locator(".mech-zone-row").filter({ hasText: "Corridor" }).locator("input").uncheck();
  await second.getByRole("button", { name: "Clear 1 Zone", exact: true }).click();
  await second.waitFor({ state: "hidden" });
  assert.equal(await served("zon_corridor"), null);

  step("Colour by Ventilator from the Serves header, and off again");
  const servesHeader = table.locator("th.col-serves");
  await servesHeader.hover();
  const byVentilator = servesHeader.getByRole("button", { name: "Colour by Ventilator", exact: true });
  await byVentilator.click();
  await page.waitForFunction(() => window.previewHost.colourBy.mode === "ph_composer.mechanical.by_ventilator");
  await byVentilator.click();
  await page.waitForFunction(() => !window.previewHost.colourBy.mode);

  step("the optional values open from the row's disclosure and apply on Enter");
  await rowOf(ERV1).hover();
  await clickSettled(page, rowOf(ERV1).getByRole("button", { name: /^Optional values of ERV-1/ }));
  const values = page.getByRole("dialog", { name: "Optional values of ERV-1" });
  await values.getByRole("textbox", { name: "Subsoil heat exchanger" }).fill("0.3");
  await values.getByRole("textbox", { name: "Subsoil heat exchanger" }).press("Enter");
  await page.waitForFunction(id => window.previewHost.mechanical.ventilators.filter(r => r.id === id)[0]
    .values.subsoil_heat_exchange_efficiency === 0.3, ERV1);
  await page.screenshot({ path: path.join(output, "optional-values.png") });
  await page.keyboard.press("Escape");
  await values.waitFor({ state: "hidden" });
  assert.equal(await rowOf(ERV1).getByRole("button", { name: /^Optional values of ERV-1/ })
    .getAttribute("aria-pressed"), "true");

  step("Columns hides Manufacturer");
  await pane.getByRole("button", { name: "Columns", exact: true }).click();
  await page.locator(".phc-action-menu:visible").getByRole("button", { name: "Manufacturer", exact: true }).click();
  await table.locator("th.col-manufacturer").waitFor({ state: "hidden" });
  await pane.getByRole("button", { name: "Columns", exact: true }).click();
  await page.locator(".phc-action-menu:visible").getByRole("button", { name: "Manufacturer", exact: true }).click();
  await table.locator("th.col-manufacturer").waitFor();

  step("create, duplicate and delete in the form dialog");
  await pane.getByRole("button", { name: "+ New Ventilator", exact: true }).click();
  const create = page.getByRole("dialog", { name: "New Ventilator" });
  await create.getByRole("textbox", { name: "Tag", exact: true }).fill("HRV-5");
  await create.getByRole("button", { name: "Create Ventilator", exact: true }).click();
  await create.waitFor({ state: "hidden" });
  assert.equal(await host("window.previewHost.mechanical.ventilators.length"), 5);
  await table.getByRole("button", { name: "Duplicate HRV-5", exact: true }).click();
  const duplicate = page.getByRole("dialog", { name: "Duplicate Ventilator" });
  assert.equal(await duplicate.getByRole("textbox").inputValue(), "HRV-5 (copy)");
  assert.equal(await duplicate.getByRole("checkbox").count(), 0, "no datasheet choice for a Ventilator");
  await duplicate.getByRole("button", { name: "Duplicate Ventilator", exact: true }).click();
  await duplicate.waitFor({ state: "hidden" });
  await table.getByRole("button", { name: "Delete ERV-2", exact: true }).click();
  const remove = page.getByRole("dialog", { name: /ERV-2$/ });
  await remove.getByRole("combobox").selectOption("__clear__");
  await remove.getByRole("button", { name: /delete$/i }).click();
  await remove.waitFor({ state: "hidden" });
  assert.equal(await served("zon_apt2"), null, "the Zones it served are cleared");
  assert.equal((await ventilator(ERV1)).name, "ERV-1");

  step("the tab fits the panel's sizes, the picker open at each");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false,
      `Mechanical does not scroll sideways at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `ventilators-${width}x${height}.png`) });
    await clickSettled(page, rowOf(ERV3).locator(".mech-serves-cell"));
    const open = page.getByRole("dialog", { name: "Zones served by ERV-3 Spare" });
    await open.waitFor();
    const box = await open.boundingBox();
    assert.ok(box.x >= 0 && box.x + box.width <= width, `the picker stays inside ${width} px`);
    await page.screenshot({ path: path.join(output, `zone-picker-${width}x${height}.png`) });
    await page.keyboard.press("Escape");
    await open.waitFor({ state: "hidden" });
  }
  return `mechanical browser checks passed; screenshots: ${output}`;
});
