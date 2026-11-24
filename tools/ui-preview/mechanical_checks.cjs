/* The Mechanical tab in the preview: the Ventilation subtab and its Ventilators pill, in-place edits, electric
   efficiency in both unit systems, the Zone picker with its replace route, By ventilator from the Serves header,
   the optional values, the Columns menu and the record forms; then the Hot Water subtab's Systems, Heaters and
   Tanks: read-only recirculation, the method badge and the pooling note, Serves and By hot water system, a Heater's
   Type change, litres in US gallons, the export slot, the System delete and New Tank; each at the panel's three
   sizes. Browser evidence; not host acceptance. */
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
  step("Hot Water › Systems: recirculation read only, the method badge and the pooling note");
  await setPanelSize(page, 1280, 800);
  const hotWater = id => host(`JSON.parse(JSON.stringify(window.previewHost.mechanical.hotWater.${id}))`);
  await pane.getByRole("tab", { name: "Hot Water" }).click();
  const pills = pane.getByRole("group", { name: "Hot Water tables" });
  await pills.getByRole("button", { name: "Systems", pressed: true }).waitFor();
  const systems = pane.locator(".mech-hot-water-systems");
  const systemRow = id => systems.locator(`[data-row-key='${id}']`);
  const DHW1 = "hws_Aa11Bb22Cc33", DHW3 = "hws_Gg77Hh88Ii99";
  await systemRow(DHW1).waitFor();
  assert.equal(await systemRow(DHW1).locator(".col-recirculation_temperature_c").textContent(), "60");
  assert.equal(await systemRow(DHW1).locator(".col-recirculation_temperature_c input").count(), 0, "read only");
  assert.match(await systemRow(DHW1).locator(".col-piping_calc_method .mech-cell-badge").getAttribute("aria-label"),
    /pinned honeybee-ph has no field/);
  assert.match(await pane.locator(".mech-table-note").textContent(), /DHW-1 Central, DHW-2 Retail serve Building Segment Apartments/);
  await page.screenshot({ path: path.join(output, "hot-water-systems.png") });
  const taps = systemRow(DHW1).locator("[data-record-field='number_tap_points']");
  await taps.dblclick();
  await taps.fill("30");
  await taps.press("Enter");
  await page.waitForFunction(() => window.previewHost.mechanical.hotWater.systems[0].values.number_tap_points === 30);
  assert.deepEqual((await sent(PREFIX + "hot_water_systems.update")).pop().payload.params.expected_values,
    { number_tap_points: 24 });

  step("Serves on a System assigns on the hot water slot, and By hot water system colours from its header");
  await clickSettled(page, systemRow(DHW3).locator(".mech-serves-cell"));
  const hwPicker = page.getByRole("dialog", { name: "Zones served by DHW-3 Spare" });
  await hwPicker.locator(".mech-zone-row").filter({ hasText: "Classroom" }).locator("input").check();
  await hwPicker.getByRole("button", { name: "Assign 1 Zone", exact: true }).click();
  await hwPicker.waitFor({ state: "hidden" });
  assert.equal((await hotWater("serves")).zon_classroom, DHW3);
  assert.equal((await sent(PREFIX + "serves.assign")).pop().payload.params.slot, "hot_water_system_id");
  const hwServes = systems.locator("th.col-serves");
  await hwServes.hover();
  const byHotWater = hwServes.getByRole("button", { name: "Colour by Hot Water System", exact: true });
  await byHotWater.click();
  await page.waitForFunction(() =>
    window.previewHost.colourBy.mode === "ph_composer.mechanical.by_hot_water_system");
  await byHotWater.click();
  await page.waitForFunction(() => !window.previewHost.colourBy.mode);

  step("a System that Heaters and Tanks name offers no clearing on delete");
  await systems.getByRole("button", { name: "Delete DHW-1 Central", exact: true }).click();
  const removeSystem = page.getByRole("dialog", { name: /DHW-1 Central$/ });
  const choices = await removeSystem.getByRole("combobox").locator("option").evaluateAll(nodes =>
    nodes.map(node => node.value));
  assert.ok(choices.indexOf("__clear__") < 0, "Heaters and Tanks need a System");
  await removeSystem.getByRole("button", { name: "Cancel", exact: true }).click();
  await removeSystem.waitFor({ state: "hidden" });

  step("Hot Water › Heaters: only the Type's efficiency cells are live; a Type change asks for its values");
  await pills.getByRole("button", { name: "Heaters" }).click();
  const heaters = pane.locator(".mech-hot-water-heaters");
  const heaterRow = id => heaters.locator(`[data-row-key='${id}']`);
  const HPWH1 = "hwh_Aa11Bb22Cc33";
  await heaterRow(HPWH1).waitFor();
  assert.equal(await heaterRow(HPWH1).locator(".col-cop_1").textContent(), "—");
  assert.equal(await heaterRow(HPWH1).locator("[data-record-field='annual_energy_factor']").inputValue(), "3.75");
  await page.screenshot({ path: path.join(output, "hot-water-heaters.png") });
  await heaterRow(HPWH1).locator(".col-variant select").selectOption("heat_pump_annual");
  const typeDialog = page.getByRole("dialog", { name: "Change HPWH-1 to Heat pump · annual" });
  await typeDialog.getByText("Removes its Energy factor.").waitFor();
  await typeDialog.getByRole("textbox", { name: "Performance ratio" }).fill("2.8");
  await page.screenshot({ path: path.join(output, "heater-type-change.png") });
  await typeDialog.getByRole("button", { name: "Change Type", exact: true }).click();
  await typeDialog.waitFor({ state: "hidden" });
  const changed = (await hotWater("heaters")).filter(row => row.id === HPWH1)[0].values;
  assert.equal(changed.variant, "heat_pump_annual");
  assert.equal(changed.total_system_perf_ratio, 2.8);
  assert.equal(changed.annual_energy_factor, undefined, "the old Type's value went with it");
  assert.equal(await heaterRow(HPWH1).locator(".col-annual_energy_factor").textContent(), "—");

  step("Hot Water › Tanks: litres in US gallons under IP, the export slot from Role, New Tank with its System");
  await pills.getByRole("button", { name: "Tanks" }).click();
  const tanks = pane.locator(".mech-hot-water-tanks");
  const tankRow = id => tanks.locator(`[data-row-key='${id}']`);
  const T3 = "hwt_Gg77Hh88Ii99";
  await tankRow(T3).waitFor();
  assert.equal(await tankRow(T3).locator(".col-slot").textContent(), "No slot left");
  await page.getByRole("button", { name: "Set display units to IP", exact: true }).click();
  assert.equal(await tankRow("hwt_Aa11Bb22Cc33").locator("[data-record-field='storage_capacity_l']").inputValue(),
    "118.9");
  assert.match(await tanks.locator("th.col-storage_capacity_l").textContent(), /gal/);
  await page.screenshot({ path: path.join(output, "hot-water-tanks-ip.png") });
  await page.getByRole("button", { name: "Set display units to SI", exact: true }).click();
  await tankRow(T3).locator("[data-record-field='role']").selectOption("solar");
  await page.waitForFunction(id => window.previewHost.mechanical.hotWater.tanks.filter(r => r.id === id)[0]
    .values.role === "solar", T3);
  await tankRow(T3).locator(".col-slot").getByText("Solar tank").waitFor();
  await pane.getByRole("button", { name: "+ New Hot Water Tank", exact: true }).click();
  const newTank = page.getByRole("dialog", { name: "New Hot Water Tank" });
  await newTank.getByRole("textbox", { name: "Tag", exact: true }).fill("T-4");
  await newTank.getByRole("combobox", { name: "Hot Water System" }).selectOption("hws_Dd44Ee55Ff66");
  await newTank.getByRole("button", { name: "Create Hot Water Tank", exact: true }).click();
  await newTank.waitFor({ state: "hidden" });
  assert.equal((await hotWater("tanks")).filter(row => row.values.name === "T-4")[0].values.hot_water_system_id,
    "hws_Dd44Ee55Ff66");

  step("each Hot Water table fits the panel's sizes");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    for (const pill of ["Systems", "Heaters", "Tanks"]) {
      await pills.getByRole("button", { name: pill }).click();
      assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false,
        `Hot Water ${pill} does not scroll sideways at ${width} x ${height}`);
      await page.screenshot({ path: path.join(output, `hot-water-${pill.toLowerCase()}-${width}x${height}.png`) });
    }
  }
  return `mechanical browser checks passed; screenshots: ${output}`;
});
