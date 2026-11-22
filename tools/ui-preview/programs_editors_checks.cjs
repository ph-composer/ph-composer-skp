/* The Schedule and Equipment Set editors in the real panel with synthetic data: each Schedule type's form, a value
   committed as one guarded update, the ventilation total held amber until it is 24 h, the strip and the week row;
   devices added (a gas dryer's gas fields shown only for a gas dryer), edited (each type laid out from the device
   types) and deleted, each one action; IP and SI; the device grid, the Schedule form and the device dialog at every
   panel size. The preview host answers the writes and the device types read (host.js `deviceAction`,
   `deviceTypesQuery`); native Undo is the SketchUp gate PG11b. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const { check } = require("./support/browser_evidence.cjs");
const BASE = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}/tools/ui-preview/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-programs-ed-"));
fs.mkdirSync(output, { recursive: true });
const TYPES = JSON.parse(fs.readFileSync(path.join(__dirname, "../../tests/fixtures/programs/device_types.json"),
  "utf8"));

const pane = "[data-pane='programs']";
const shown = `${pane} .pgm-layout:not([hidden])`;

function sent(page, name) {
  return page.evaluate(target => window.previewHost.sent.filter(message => message.type === "action.invoke" &&
    message.payload.name === target).map(message => message.payload.params), name);
}

check({ name: "programs_editors", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(5000);
  const title = page.locator(`${shown} .pgm-title`);
  const openRow = async name => {
    await page.locator(`${shown} .library-sidebar-row-button`, { hasText: name }).click();
    await title.filter({ hasText: name }).waitFor();
  };

  step("a fractional Schedule's form, its strip over 24 hours and its week row from the profile");
  await page.goto(`${BASE}?fixture=programs`);
  await page.locator("[data-tab='programs']").click();
  await page.getByRole("tab", { name: "Schedules" }).click();
  await openRow("Office hours");
  const field = name => page.locator(shown).getByRole("textbox", { name, exact: true });
  assert.equal(await field("Starts at").inputValue(), "7");
  assert.equal(await field("Fraction while operating").inputValue(), "0.8");
  assert.equal(await page.locator(`${shown} .sch-bar`).count(), 24);
  assert.deepEqual(await page.locator(`${shown} .sch-day.is-on`).allTextContents(),
    ["Mon", "Tue", "Wed", "Thu", "Fri"]);
  assert.equal(await page.locator(`${shown}`).getByRole("button", { name: "Hourly editor" }).isDisabled(), true);
  await page.screenshot({ path: path.join(output, "schedule-fractional.png") });

  step("a value commits on Enter as one guarded update, and the strip follows the Model");
  await field("Ends at").fill("17");
  await field("Ends at").press("Enter");
  await page.waitForFunction(() => window.previewHost.programCatalog.schedules.filter(row => row.id === "sch_office")[0]
    .values.end_h === 17);
  assert.deepEqual((await sent(page, "ph_composer.programs.schedules.update")).pop(),
    { id: "sch_office", values: { end_h: 17 }, expected_values: { end_h: 19 } });
  await page.waitForFunction(() => document.querySelectorAll("[data-pane='programs'] .sch-bar[height='0']")
    .length >= 14);

  step("a whole number refuses a fraction; the field returns to the Model's value");
  await field("Days per week").fill("4.5");
  await field("Days per week").press("Enter");
  await page.waitForFunction(() => /whole number from 1 to 7/.test(document.querySelector("[data-notice-layer]")
    .textContent));
  assert.equal(await field("Days per week").inputValue(), "5");

  step("an activity Schedule reads W per person; a temperature Schedule one value, °F in IP, every day");
  await openRow("Residential activity");
  assert.match(await page.locator(`${shown} .sch-field`, { hasText: "While operating" }).textContent(), /W per person/);
  await openRow("Heating setback");
  assert.equal(await field("Days per week").count(), 0, "a temperature Schedule has no days or weeks");
  assert.equal(await page.locator(`${shown} .sch-day.is-on`).count(), 7);
  await page.locator("[data-unit-system='IP']").click();
  await page.locator(`${shown} .sch-field .unit`, { hasText: "°F" }).waitFor();
  assert.equal(await field("Temperature").inputValue(), "68");
  await field("Temperature").fill("70");
  await field("Temperature").press("Enter");
  await page.waitForFunction(() => Math.abs(window.previewHost.programCatalog.schedules
    .filter(row => row.id === "sch_heating")[0].values.value_c - 21.111) < 0.01);
  await page.screenshot({ path: path.join(output, "schedule-temperature-ip.png") });
  await page.locator("[data-unit-system='SI']").click();
  await page.locator(`${shown} .sch-field .unit`, { hasText: "°C" }).waitFor();

  step("ventilation hours wait amber until they total 24 h, then go as one update of the periods");
  await openRow("Constant ventilation");
  const total = page.locator(`${shown} .sch-total`);
  assert.equal((await total.textContent()).trim(), "Total 24 of 24 h");
  const high = page.locator(shown).getByRole("textbox", { name: "High hours per day" });
  const standard = page.locator(shown).getByRole("textbox", { name: "Standard hours per day" });
  const before = (await sent(page, "ph_composer.programs.schedules.update")).length;
  await high.fill("2");
  await high.press("Enter");
  await page.locator(`${shown} .sch-total.is-missing`).waitFor();
  assert.match(await total.textContent(), /Total 26 of 24 h/);
  assert.equal((await sent(page, "ph_composer.programs.schedules.update")).length, before, "nothing sent at 26 h");
  await page.screenshot({ path: path.join(output, "schedule-ventilation-held.png") });
  await page.getByRole("tab", { name: "Programs" }).click();
  await page.waitForFunction(() => /total 24 h/.test(document.querySelector("[data-notice-layer]").textContent));
  assert.equal(await page.getByRole("tab", { name: "Schedules" }).getAttribute("aria-selected"), "true",
    "the held draft keeps the page");
  await standard.fill("22");
  await standard.press("Enter");
  await page.waitForFunction(() => window.previewHost.programCatalog.schedules
    .filter(row => row.id === "sch_PHCDEFAULT06")[0].values.periods[0].hours === 2);
  const update = (await sent(page, "ph_composer.programs.schedules.update")).pop();
  assert.deepEqual(update.values.periods.map(period => period.hours), [2, 22, 0, 0]);
  assert.deepEqual(update.expected_values.periods.map(period => period.hours), [0, 24, 0, 0]);
  await page.locator(`${shown} .sch-total:not(.is-missing)`).waitFor();

  step("the Schedule form at every panel size");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the Schedule form scrolls sideways at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `schedule-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);

  step("Escape ends a typed entry, and the still-focused field lets the subtabs switch");
  const minimum = field("Minimum fraction of design flow");
  await minimum.fill("0.2");
  await page.getByRole("tab", { name: "Equipment Sets" }).click();
  assert.equal(await page.getByRole("tab", { name: "Schedules" }).getAttribute("aria-selected"), "true",
    "a typed entry holds the switch");
  await minimum.press("Escape");
  assert.equal(await minimum.evaluate(node => node === document.activeElement), true, "the field keeps focus");

  step("the device grid: a Phius-rule device marked, a renamed device's type beside its name");
  await page.getByRole("tab", { name: "Equipment Sets" }).click();
  await title.filter({ hasText: "Phius single-family" }).waitFor();
  const add = page.locator(`${shown} .pgm-add-device`);
  await page.waitForFunction(() => !document.querySelector("[data-pane='programs'] .pgm-layout:not([hidden]) " +
    ".pgm-add-device").disabled);
  const grid = page.locator(`${shown} .pgm-devices tbody tr`);
  assert.equal(await grid.count(), 4);
  assert.match(await grid.filter({ hasText: "Phius MEL" }).locator(".col-energy").textContent(), /Phius rule/);
  assert.match(await grid.filter({ hasText: "Laundry - dryer" }).locator(".col-device").textContent(),
    /Clothes dryer/);
  await grid.filter({ hasText: "Dishwasher" }).hover();
  await page.screenshot({ path: path.join(output, "equipment-set.png") });

  step("Add device lays out each type from the device types; a gas dryer's gas fields only for a gas dryer");
  await add.click();
  const dialog = page.locator("dialog.pgm-device-dialog[open]");
  await dialog.waitFor();
  const keyed = key => dialog.locator(`[data-key='${key}']`);
  for (const entry of TYPES) {
    await keyed("type").selectOption(entry.type);
    assert.equal(await keyed("display_name").inputValue(), entry.defaults.display_name, entry.type);
    assert.equal(await dialog.locator(".pgm-device-rule").count(), entry.phius_rule ? 1 : 0, entry.type);
    for (const own of entry.fields) {
      if (own.applies_when || (own.key === "reference_energy_norm" && entry.energy_norms.length < 2)) continue;
      assert.equal(await keyed(own.key).count(), 1, `${entry.type} shows ${own.key}`);
    }
  }
  await keyed("type").selectOption("clothes_dryer");
  assert.equal(await keyed("gas_consumption").count(), 0, "an electric dryer has no gas fields");
  await keyed("dryer_type").selectOption("gas_exhaust_air");
  await keyed("gas_consumption").waitFor();
  await keyed("gas_consumption").fill("1.5");
  await page.screenshot({ path: path.join(output, "device-add-gas-dryer.png") });
  await keyed("gas_consumption").press("Enter");
  await dialog.waitFor({ state: "hidden" });
  const added = (await sent(page, "ph_composer.programs.equipment_sets.add_device")).pop();
  assert.equal(added.type, "clothes_dryer");
  assert.deepEqual([added.values.dryer_type, added.values.gas_consumption], ["gas_exhaust_air", 1.5]);
  await grid.nth(4).waitFor();

  step("a row click edits: the type fixed, only what changed sent, guarded as it opened");
  await grid.filter({ hasText: "Dishwasher" }).locator(".col-quantity").click();
  await dialog.waitFor();
  assert.equal(await keyed("type").count(), 0);
  assert.match(await dialog.locator(".pgm-device-type").textContent(), /Dishwasher/);
  await keyed("quantity").fill("2");
  await dialog.getByRole("button", { name: "Save" }).click();
  await dialog.waitFor({ state: "hidden" });
  assert.deepEqual((await sent(page, "ph_composer.programs.equipment_sets.update_device")).pop(),
    { id: "eqs_PHCDEFAULT01", device_id: "dev_PHCDEFAULT02", values: { quantity: 2 },
      expected_values: { quantity: 1 } });

  step("a device changed meanwhile refuses, and the dialog keeps the draft");
  await grid.filter({ hasText: "Phius MEL" }).hover();
  await page.locator(shown).getByRole("button", { name: "Edit Phius MEL" }).click();
  await dialog.waitFor();
  await keyed("quantity").fill("3");
  await page.evaluate(() => {
    window.previewHost.programCatalog.equipment_sets[0].values.devices
      .filter(device => device.id === "dev_PHCDEFAULT08")[0].quantity = 4;
  });
  await keyed("quantity").press("Enter");
  await dialog.locator(".cell-error", { hasText: "changed since it was read" }).waitFor();
  assert.equal(await keyed("quantity").inputValue(), "3");
  await dialog.getByRole("button", { name: "Cancel" }).click();
  await dialog.waitFor({ state: "hidden" });

  step("Delete confirms naming the Set and the Dwellings using it");
  await grid.filter({ hasText: "Fridge-freezer" }).hover();
  await page.locator(shown).getByRole("button", { name: "Delete Fridge-freezer" }).click();
  const confirm = page.locator("dialog.pgm-confirm[open]");
  assert.equal(await confirm.locator("p").textContent(),
    "This removes Fridge-freezer from Phius single-family. Dwelling House uses this Set.");
  await confirm.getByRole("button", { name: "Delete device" }).click();
  await grid.filter({ hasText: "Fridge-freezer" }).waitFor({ state: "detached" });
  assert.equal((await sent(page, "ph_composer.programs.equipment_sets.delete_device")).pop().device_id,
    "dev_PHCDEFAULT01");

  step("the device grid and the device dialog at every panel size");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the Equipment Sets pane scrolls sideways at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `equipment-set-${width}.png`) });
    await add.click();
    await dialog.waitFor();
    const box = await dialog.evaluate(node => node.getBoundingClientRect().toJSON());
    assert.ok(box.right <= width + 1 && box.left >= -1, `the device dialog fits ${width}`);
    await page.screenshot({ path: path.join(output, `device-dialog-${width}.png`) });
    await page.keyboard.press("Escape");
    await dialog.waitFor({ state: "hidden" });
  }
  await setPanelSize(page, 1280, 800);

  step("at 1280 the grid shows the host's long device names and Phius rule lines whole");
  await page.evaluate(() => {
    // As long as the host's "PHIUS+ Exterior Lighting · Phius exterior lighting" with this device's type.
    const names = { dev_PHCDEFAULT02: "PHIUS+ Exterior Lighting, north porch", dev_PHCDEFAULT08: "PHIUS+ MELS" };
    window.previewHost.programCatalog.equipment_sets.forEach(row => (row.values.devices || []).forEach(device => {
      if (names[device.id]) device.display_name = names[device.id];
    }));
    window.previewHost.snapshot();
  });
  await grid.filter({ hasText: "PHIUS+ MELS" }).waitFor();
  const clipped = await grid.evaluateAll(rows => rows.flatMap(tr => ["device", "energy"].map(field =>
    tr.querySelector(`.col-${field}`)).filter(td => td.scrollWidth > td.clientWidth).map(td => td.textContent)));
  assert.deepEqual(clipped, [], "nothing in Device or Energy demand is cut");
  await page.screenshot({ path: path.join(output, "equipment-set-long-names.png") });
});
