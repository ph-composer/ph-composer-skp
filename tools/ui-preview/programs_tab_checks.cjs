/* The Programs tab in the real panel with synthetic data (planning P4a-11): the three subtabs and their sidebars,
   opening a record from its row, a library Program copied with its Schedules' catalog read beside it, the
   accordion cards (pointer and keyboard), their one-line summaries and missing-value flags, the rule switch, a
   value edit as one guarded action, a stale value refused and the field back at the Model's value, New, rename in
   place, Duplicate, Delete with a replacement, Reset on the default, IP and SI, and the pane at every panel size.
   The preview host answers the writes (host.js `programCatalogAction`); native Undo is the SketchUp gate PG11. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const { check } = require("./support/browser_evidence.cjs");
const BASE = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}/tools/ui-preview/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-programs-tab-"));
fs.mkdirSync(output, { recursive: true });

const pane = "[data-pane='programs']";
const shown = `${pane} .pgm-layout:not([hidden])`;

function sent(page, name) {
  return page.evaluate(target => window.previewHost.sent.filter(message => message.type === "action.invoke" &&
    message.payload.name === target).map(message => message.payload.params), name);
}

function rows(page) {
  return page.locator(`${shown} .library-sidebar-row-button .library-sidebar-name`).allTextContents();
}

check({ name: "programs_tab", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(5000);

  step("the tab opens on the Model's default Program, its sidebar grouped Default and In this file");
  await page.goto(`${BASE}?fixture=programs`);
  await page.locator("[data-tab='programs']").click();
  const title = page.locator(`${shown} .pgm-title`);
  await title.filter({ hasText: "Residential default" }).waitFor();
  assert.equal(await page.locator(`${shown} .pgm-badge`).textContent(), "Unassigned Zones use this");
  const groups = await page.locator(`${shown} .library-sidebar-group-heading`).allTextContents();
  assert.deepEqual(groups.map(text => text.replace(/\d+$/, "")), ["Default", "In this file"]);
  assert.equal(await page.locator(`${shown} .library-sidebar-row-button[aria-current='true'] .library-sidebar-name`)
    .textContent(), "Residential default");
  const tabs = await page.getByRole("tablist", { name: "Programs" }).getByRole("tab").allTextContents();
  assert.deepEqual(tabs, ["Programs", "Schedules", "Equipment Sets"]);

  step("closed cards read on one line; the default's rule loads say so");
  const card = key => page.locator(`${shown} .pgm-card[data-load='${key}']`);
  assert.equal(await card("people").locator(".pgm-sum").textContent(), "Phius rule · Residential occupancy");
  assert.equal(await card("setpoint").locator(".pgm-sum").textContent(), "20 °C / 25 °C");
  assert.equal(await page.locator(`${shown} .pgm-card`).count(), 8);
  assert.equal(await card("gas_equipment").evaluate(node => node.previousElementSibling.textContent),
    "EnergyPlus only", "the EnergyPlus loads sit under their caption");
  await page.screenshot({ path: path.join(output, "programs-default.png") });

  step("cards open and close by pointer and by keyboard, the arrows moving between heads");
  const head = key => card(key).locator(".pgm-card-head");
  await head("people").click();
  assert.equal(await head("people").getAttribute("aria-expanded"), "true");
  await head("people").press("ArrowDown");
  assert.equal(await page.evaluate(() => document.activeElement.closest(".pgm-card").dataset.load), "lighting");
  await page.keyboard.press("Enter");
  assert.equal(await head("lighting").getAttribute("aria-expanded"), "true");
  assert.match(await card("lighting").locator(".pgm-rule").textContent(), /Phius rule/);
  assert.equal(await card("lighting").getByRole("textbox", { name: "Lighting high-efficacy fraction" }).inputValue(),
    "1", "the rule's input stays editable");
  await page.keyboard.press("Enter");
  assert.equal(await head("lighting").getAttribute("aria-expanded"), "false");

  step("the rule switches to a fixed value and back, each one update of the load");
  await card("people").getByRole("button", { name: "Use a fixed value" }).click();
  await card("people").getByRole("button", { name: "Use the Phius rule" }).waitFor();
  const fixed = (await sent(page, "ph_composer.programs.programs.update")).pop();
  assert.equal(fixed.id, "pgm_PHCDEFAULT01");
  assert.equal(fixed.values.people.rule, null);
  assert.equal(fixed.expected_values.people.rule, "phius_residential", "guarded by the load as drawn");
  assert.match(await card("people").locator(".pgm-row").first().getAttribute("class"), /is-missing/);
  assert.equal(await card("people").locator(".pgm-flag").isVisible(), true, "the missing value is flagged");

  step("a typed value commits on Enter as one guarded update, in the display units");
  const people = card("people").getByRole("textbox", { name: "Occupancy people per area" });
  await people.fill("0.05");
  await people.press("Enter");
  await page.waitForFunction(() => window.previewHost.programCatalog.programs[0].values.people.people_per_area === 0.05);
  await card("people").locator(".pgm-flag").waitFor({ state: "hidden" });
  assert.equal(await card("people").locator(".pgm-sum").textContent(), "0.05 people/m² · Residential occupancy");
  await page.screenshot({ path: path.join(output, "programs-edit.png") });

  step("a value changed meanwhile refuses, and the field shows the Model's value again");
  await people.fill("0.07");
  await page.evaluate(() => { window.previewHost.programCatalog.programs[0].values.people.radiant_fraction = 0.4; });
  await people.press("Enter");
  await page.waitForFunction(() => /changed since/.test(document.querySelector("[data-notice-layer]").textContent));
  await page.evaluate(() => window.previewHost.snapshot());
  await page.waitForFunction(() => document.querySelector("[aria-label='Occupancy people per area']").value === "0.05");
  assert.equal(await card("people").getByRole("textbox", { name: "Occupancy radiant fraction" }).inputValue(), "0.4");

  step("IP shows people per ft² and SI people per m², stored SI");
  await page.locator("[data-unit-system='IP']").click();
  await card("people").locator(".pgm-row .unit", { hasText: "people/ft²" }).waitFor();
  assert.match(await card("people").locator(".pgm-sum").textContent(), /people\/ft²/);
  await card("ventilation").locator(".pgm-card-head").click();
  assert.match(await card("ventilation").locator(".pgm-rows").textContent(), /cfm per person/);
  await page.screenshot({ path: path.join(output, "programs-ip.png") });
  await page.locator("[data-unit-system='SI']").click();
  await card("people").locator(".pgm-row .unit", { hasText: "people/m²" }).waitFor();

  step("a Program missing values flags each card; a row opens it");
  await page.locator(`${shown} .library-sidebar-row-button`, { hasText: "Wet lab" }).click();
  await title.filter({ hasText: "Wet lab" }).waitFor();
  assert.equal(await page.locator(`${shown} .pgm-flag:not([hidden])`).count(), 8);
  assert.match(await card("ventilation").locator(".pgm-flag").getAttribute("data-tooltip"), /ventilation rate/);

  step("a Schedule slot lists its type's Schedules and names one in one update");
  await head("lighting").click();
  const slot = card("lighting").getByRole("combobox", { name: "Lighting lighting schedule" });
  const options = await slot.locator("option").allTextContents();
  assert.deepEqual(options, ["None (always on)", "Always on", "Office hours", "Residential hot water",
    "Residential lighting", "Residential occupancy"], "fractional Schedules only");
  await slot.selectOption({ label: "Office hours" });
  await page.waitForFunction(() => window.previewHost.programCatalog.programs.filter(row => row.id === "pgm_lab")[0]
    .values.lighting.schedule_id === "sch_office");

  step("+ New Schedule makes a Schedule of the slot's type, then the slot names it once the snapshot has it");
  await card("lighting").getByRole("button", { name: "New fractional Schedule for lighting schedule" }).click();
  await page.waitForFunction(() => {
    const lab = window.previewHost.programCatalog.programs.filter(row => row.id === "pgm_lab")[0];
    return /^sch_preview/.test(lab.values.lighting.schedule_id);
  });
  const created = (await sent(page, "ph_composer.programs.schedules.create")).pop();
  assert.deepEqual(created, { values: { type: "fractional" } });
  await page.waitForFunction(() => {
    const select = document.querySelector("[aria-label='Lighting lighting schedule']");
    return select && select.selectedOptions[0] && select.selectedOptions[0].textContent === "Schedule 1";
  });

  step("New acts at once under a free name and opens the title for renaming");
  await page.locator(`${shown}`).getByRole("button", { name: "+ New Program" }).click();
  const rename = page.locator(`${shown} .pgm-title-input`);
  await rename.waitFor();
  assert.equal(await rename.inputValue(), "Program 1");
  await rename.fill("Clean lab");
  await rename.press("Enter");
  await title.filter({ hasText: "Clean lab" }).waitFor();
  assert.deepEqual((await sent(page, "ph_composer.programs.programs.update")).pop().values, { name: "Clean lab" });
  await page.screenshot({ path: path.join(output, "programs-new.png") });

  step("Duplicate copies under a free name; Escape cancels its rename");
  await page.locator(`${shown}`).getByRole("button", { name: "Duplicate Program" }).click();
  await rename.waitFor();
  assert.equal(await rename.inputValue(), "Clean lab (copy)");
  await rename.press("Escape");
  await title.filter({ hasText: "Clean lab (copy)" }).waitFor();

  step("Reset is offered only on PH-Composer's default, and confirms");
  const menu = page.locator(`${shown}`).getByRole("button", { name: "Program actions" });
  await menu.click();
  assert.equal(await page.getByRole("button", { name: "Reset to PH-Composer default" }).isVisible(), false);
  await page.keyboard.press("Escape");
  await page.locator(`${shown} .library-sidebar-row-button`, { hasText: "Residential default" }).click();
  await menu.click();
  await page.getByRole("button", { name: "Reset to PH-Composer default" }).click();
  const confirm = page.locator("dialog.pgm-confirm[open]");
  await confirm.getByRole("button", { name: "Reset" }).click();
  await page.waitForFunction(() => window.previewHost.sent.some(message => message.payload &&
    message.payload.name === "ph_composer.programs.reset_default"));
  assert.deepEqual((await sent(page, "ph_composer.programs.reset_default")).pop(), { kind: "program" });
  await card("people").locator(".pgm-sum", { hasText: "Phius rule" }).waitFor();

  step("Delete of a used record asks for its replacement, and opens it");
  await menu.click();
  await page.getByRole("button", { name: "Delete Program" }).click();
  await confirm.waitFor();
  assert.match(await confirm.textContent(), /Model's default Program, on 6 Zones/);
  await page.screenshot({ path: path.join(output, "programs-delete.png") });
  await confirm.getByRole("combobox").selectOption({ label: "Phius NR Office" });
  await confirm.getByRole("button", { name: "Delete Program" }).click();
  await title.filter({ hasText: "Phius NR Office" }).waitFor();
  assert.deepEqual((await sent(page, "ph_composer.programs.programs.delete")).pop(),
    { id: "pgm_PHCDEFAULT01", expected_values: { name: "Residential default" }, replacement_id: "pgm_office" });

  step("a library Program is copied from the sidebar with its library's Schedules read beside it");
  await page.locator(`${shown} .library-sidebar-source`).selectOption({ label: "Phius Multifamily" });
  await page.locator(`${shown} .library-sidebar-row-button`, { hasText: "Phius MF Lobby" }).waitFor();
  const reads = await page.evaluate(() => window.previewHost.sent.filter(message => message.type === "query.invoke")
    .map(message => message.payload.params.kind));
  assert.ok(reads.includes("schedules"), "the Schedules catalog is read for the copy");
  await page.locator(`${shown} .library-sidebar-row-button`, { hasText: "Phius MF Lobby" }).click();
  await page.locator(".library-record-card:visible").getByRole("button", { name: "Add to file" }).click();
  await page.locator(`${shown} .library-sidebar-row-button`, { hasText: "Phius MF Lobby" })
    .locator(".library-sidebar-known:not([hidden])").waitFor();
  const copy = (await sent(page, "ph_composer.library.copy")).pop();
  assert.equal(copy.kind, "programs");
  assert.equal(copy.assignment, undefined, "a sidebar copy does not become the Model's default");
  await page.locator(`${shown} .library-sidebar-source`).selectOption({ label: "Programs in this file" });

  step("Schedules group by type; Equipment Sets list this file's Sets with their devices");
  await page.getByRole("tab", { name: "Schedules" }).click();
  const scheduleGroups = await page.locator(`${shown} .library-sidebar-group-heading`).allTextContents();
  assert.deepEqual(scheduleGroups.map(text => text.replace(/\d+$/, "")),
    ["Fractional", "Activity level", "Ventilation"]);
  assert.equal(await page.locator(`${shown} .library-sidebar-source`).isVisible(), false, "this file only");
  await page.locator(`${shown} .library-sidebar-row-button`, { hasText: "Office hours" }).click();
  await title.filter({ hasText: "Office hours" }).waitFor();
  assert.match(await page.locator(`${shown} .pgm-used-by`).textContent(), /Phius NR Office · Occupancy/);
  await page.screenshot({ path: path.join(output, "schedules.png") });
  await page.getByRole("tab", { name: "Equipment Sets" }).click();
  await title.filter({ hasText: "Phius single-family" }).waitFor();
  assert.equal(await page.locator(`${shown} .pgm-devices tbody tr`).count(), 3);
  assert.deepEqual(await rows(page), ["Phius single-family", "Apartment kitchen"]);
  await page.screenshot({ path: path.join(output, "equipment-sets.png") });

  step("the pane at every panel size: the sidebar drops beneath the editor, which stays where it was");
  await page.getByRole("tab", { name: "Programs" }).click();
  // A long source badge truncates within the header rather than widening the pane.
  await page.evaluate(() => {
    const office = window.previewHost.programCatalog.programs.filter(row => row.id === "pgm_office")[0];
    office.default = false;
    office.values.source.library_name = "Phius Non-Residential programs for schools, offices and laboratories, 2024";
    window.previewHost.snapshot();
  });
  await page.locator(`${shown} .pgm-badge`, { hasText: "laboratories" }).waitFor();
  const editorTop = await page.locator(`${shown} .pgm-main`).evaluate(node => node.getBoundingClientRect().top);
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the Programs pane scrolls sideways at ${width} x ${height}`);
    const boxes = await page.evaluate(selector => {
      const root = document.querySelector(selector);
      return [root.querySelector(".pgm-main").getBoundingClientRect().toJSON(),
        root.querySelector(".library-sidebar-root").getBoundingClientRect().toJSON()];
    }, shown);
    if (width < 700) {
      assert.ok(boxes[1].top >= boxes[0].bottom - 1, `the sidebar sits beneath the editor at ${width}`);
    }
    assert.ok(Math.abs(boxes[0].top - editorTop) < 60, `the editor keeps its place at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `programs-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);
});
