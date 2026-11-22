/* The Zones / Programs view in the real panel with synthetic data (planning P4a-09; the Phase 4a prototype's
   journeys 1 to 4): a single dwelling's locked Zones, its bedrooms on the house row and the lock bubble; switching
   Single dwelling off from Open settings and the Dwelling bubble; apartments made one Dwelling each from the
   selection bar; a library Program copied on choice and reused; a non-residential school with its flag, its
   Equipment Set dash and an assignment; IP units; and the pane at every panel size. The preview host answers the
   Programs writes (host.js `programsAction`); native transactions and Undo remain SketchUp acceptance gates. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const { check } = require("./support/browser_evidence.cjs");
const BASE = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}/tools/ui-preview/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-programs-"));
fs.mkdirSync(output, { recursive: true });

const shownTable = ".phc-zone-view:not([hidden])";

function zoneRow(page, name) {
  return page.locator(`${shownTable} tr[data-row-key]`).filter({ has: page.getByRole("checkbox",
    { name: `Check ${name}`, exact: true }) }).or(page.locator(`${shownTable} tr[data-row-key]`)
    .filter({ has: page.locator(".row-target", { hasText: new RegExp(`^${name}$`) }) })).first();
}

function heading(page, name) {
  return page.locator(`${shownTable} tr.is-heading`).filter({
    has: page.locator(".phc-segment-name", { hasText: new RegExp(`^${name}$`) }) });
}

function sent(page, name) {
  return page.evaluate(target => window.previewHost.sent.filter(message => message.type === "action.invoke" &&
    message.payload.name === target).map(message => message.payload.params), name);
}

check({ name: "programs_view", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(5000);

  step("journey 1: the house is a single dwelling, its Zones locked and its bedrooms on the house row");
  await page.goto(`${BASE}?fixture=programs`);
  await page.getByRole("heading", { name: "Zones", exact: true }).waitFor();
  await page.getByRole("tab", { name: "Programs", exact: true }).click();
  await heading(page, "House").waitFor();
  const living = page.locator(`${shownTable} tr[data-row-key='["Zone",[101]]']`);
  assert.equal(await living.getByRole("checkbox").count(), 0, "a single dwelling's Zone has no checkbox");
  assert.equal(await living.locator(".phc-programs-locked").count(), 5,
    "Program, Dwelling, counts and Equipment Set locked");
  const bedrooms = heading(page, "House").getByRole("textbox", { name: "Bedrooms in House", exact: true });
  assert.match(await bedrooms.getAttribute("class"), /is-needed/);
  assert.equal(await living.locator(".col-people .phc-programs-missing").count(), 1, "people wait for bedrooms");
  await page.screenshot({ path: path.join(output, "j1-start.png") });
  await bedrooms.fill("3");
  await bedrooms.press("Enter");
  await living.locator(".col-people .phc-programs-missing").waitFor({ state: "detached" });
  assert.deepEqual((await sent(page, "ph_composer.zones.save_segment_settings"))[0]
    .extension_payloads["ph_composer.programs.segment"].bedrooms, 3);
  await page.screenshot({ path: path.join(output, "j1-bedrooms.png") });

  step("the lock bubble explains the lock and opens the Segment's settings");
  await living.locator(".col-program .phc-programs-locked").click();
  const lock = page.getByRole("dialog", { name: "House is a single dwelling", exact: true });
  await lock.waitFor();
  await page.screenshot({ path: path.join(output, "j1-lock-bubble.png") });
  await lock.getByRole("button", { name: "Open settings", exact: true }).click();
  const settings = page.locator("dialog.phc-segment-settings-dialog[open]");
  await settings.waitFor();
  await settings.getByRole("checkbox", { name: "Single dwelling", exact: true }).uncheck();
  await settings.getByRole("button", { name: "Save", exact: true }).click();
  await settings.waitFor({ state: "hidden" });
  const program = living.getByRole("combobox", { name: "Program for Living", exact: true });
  await program.waitFor();
  assert.match(await program.getAttribute("class"), /is-default/, "the effective Program reads inherited");
  const houseCells = await heading(page, "House").evaluate(tr => ["bedrooms", "occupants", "equipment_set"]
    .map(field => tr.querySelector(`.col-${field}`).querySelectorAll("input, select").length));
  assert.deepEqual(houseCells, [0, 0, 0], "no longer single, the heading gives its house inputs back");

  step("the Dwelling bubble names the house's Dwelling and its values");
  await living.locator(".col-dwelling button").click();
  const dwelling = page.getByRole("dialog", { name: "Dwelling of Living", exact: true });
  await dwelling.waitFor();
  assert.equal(await dwelling.getByRole("combobox", { name: "Dwelling of Living", exact: true })
    .locator("option:checked").textContent(), "House");
  assert.equal(await dwelling.getByRole("textbox", { name: "Units of House", exact: true }).inputValue(), "1");
  await page.screenshot({ path: path.join(output, "j1-unlocked.png") });
  await page.keyboard.press("Escape");

  step("Not a dwelling: the bubble's sentence wraps inside it");
  await page.locator(`${shownTable} tr[data-row-key='["Zone",[203]]'] .col-dwelling button`).click();
  const none = page.getByRole("dialog", { name: "Dwelling of Corridor", exact: true });
  const sentence = none.locator(".phc-dwelling-detail > p");
  await sentence.waitFor();
  const fits = await sentence.evaluate(node => {
    const box = node.getBoundingClientRect(), bubble = node.closest(".phc-bubble").getBoundingClientRect();
    return node.scrollWidth <= node.clientWidth + 1 && box.right <= bubble.right;
  });
  assert.equal(fits, true, "the sentence is not clipped at the bubble's edge");
  await page.keyboard.press("Escape");

  step("journey 2: apartments made one Dwelling each from the selection bar");
  await page.getByRole("checkbox", { name: "Check Apt 1", exact: true }).check();
  await page.getByRole("checkbox", { name: "Check Apt 2", exact: true }).check();
  const bar = page.getByRole("region", { name: "Checked Zones", exact: true });
  await bar.waitFor();
  await page.screenshot({ path: path.join(output, "j2-checked.png") });
  await bar.getByRole("combobox", { name: "Dwelling for checked Zones", exact: true })
    .selectOption({ label: "One dwelling each" });
  const apt = page.locator(`${shownTable} tr[data-row-key='["Zone",[201]]']`);
  await apt.locator(".col-dwelling button", { hasText: "Apt 1" }).waitFor();
  assert.deepEqual((await sent(page, "ph_composer.programs.assign_dwelling")).pop(),
    { zones: [{ zone_id: "zon_apt1", zone_path: [201] }, { zone_id: "zon_apt2", zone_path: [202] }],
      choice: "each" });
  const aptBedrooms = apt.getByRole("textbox", { name: "Bedrooms in Apt 1", exact: true });
  await aptBedrooms.fill("2");
  await aptBedrooms.press("Enter");
  await page.waitForFunction(() => window.previewHost.sent.some(message =>
    message.payload && message.payload.name === "ph_composer.programs.set_counts"));
  await page.screenshot({ path: path.join(output, "j2-dwellings.png") });
  await bar.getByRole("button", { name: "Clear selection", exact: true }).click();

  step("journey 3: a library Program is copied on choice, and the next Zone uses the local copy");
  const corridor = page.locator(`${shownTable} tr[data-row-key='["Zone",[203]]']`);
  const corridorProgram = corridor.getByRole("combobox", { name: "Program for Corridor", exact: true });
  await page.waitForFunction(() => Array.from(document.querySelectorAll("select")).some(select =>
    Array.from(select.options).some(option => option.textContent === "Phius MF Corridor")));
  await corridorProgram.selectOption({ label: "Phius MF Corridor" });
  await page.waitForFunction(() => window.previewHost.sent.some(message =>
    message.payload && message.payload.name === "ph_composer.programs.assign_library_program"));
  const copied = (await sent(page, "ph_composer.programs.assign_library_program"))[0];
  assert.deepEqual(copied.copy.record_id, "corridor");
  assert.equal(copied.copy.choice, "create");
  await page.waitForFunction(() => {
    const select = document.querySelector("select[aria-label='Program for Corridor']");
    return select && select.selectedOptions[0] && select.selectedOptions[0].textContent === "Phius MF Corridor" &&
      select.selectedOptions[0].parentNode.label === "In this file";
  });
  const aptProgram = page.getByRole("combobox", { name: "Program for Apt 2", exact: true });
  const offered = await aptProgram.locator("option").allTextContents();
  assert.equal(offered.filter(text => text === "Phius MF Corridor").length, 1, "copied once, listed once");
  await aptProgram.selectOption({ label: "Phius MF Corridor" });
  await page.waitForFunction(() => window.previewHost.sent.filter(message => message.payload &&
    message.payload.name === "ph_composer.programs.assign_program").length > 0);
  assert.equal((await sent(page, "ph_composer.programs.assign_library_program")).length, 1, "no second copy");
  await page.screenshot({ path: path.join(output, "j3-common-areas.png") });

  step("journey 4: the school's unassigned Classroom is flagged until it has a Program");
  const classroom = page.locator(`${shownTable} tr[data-row-key='["Zone",[301]]']`);
  assert.match(await classroom.locator(".phc-row-marker").getAttribute("aria-label"), /no Program of its own/);
  assert.equal((await classroom.locator(".col-equipment_set").textContent()).trim(), "—");
  await page.screenshot({ path: path.join(output, "j4-start.png") });
  await classroom.getByRole("combobox", { name: "Program for Classroom", exact: true })
    .selectOption({ label: "Phius NR Office" });
  await classroom.locator(".phc-row-marker").waitFor({ state: "hidden" });
  await page.screenshot({ path: path.join(output, "j4-assigned.png") });

  step("the pane at every panel size, with the selection bar showing");
  await page.getByRole("checkbox", { name: "Check Corridor", exact: true }).check();
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [".phc-selection-bar"] });
    assert.equal(facts.sideways, false, `the Zones pane scrolls sideways at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `programs-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);

  step("an export finding's Locate checks its Zones clear of the selection bar and opens nothing else");
  await page.getByRole("button", { name: "Clear selection", exact: true }).click();
  for (const [width, height] of [[1280, 520], [420, 732], [360, 520]]) {
    await setPanelSize(page, width, height);
    await page.evaluate(() => {
      document.querySelector(".phc-zone-view:not([hidden]) .phc-table-mount").scrollTop = 0;
      document.querySelector(".panel-panes").scrollTop = 0;
      const host = window.previewHost;
      host.publish("panel.navigate", { session: host.session, owner: "ph_composer.zones", intent: {
        view: "ph_composer.programs.zones", zones: [{ zone_id: "zon_classroom", zone_path: [301] }] } });
    });
    await page.locator(".phc-selection-bar:not([hidden])").waitFor();
    const placed = await page.evaluate(() => {
      const row = document.querySelector(".phc-zone-view:not([hidden]) tr.is-checked").getBoundingClientRect();
      const head = document.querySelector(".phc-zone-view:not([hidden]) thead").getBoundingClientRect();
      const bar = document.querySelector(".phc-selection-bar:not([hidden])");
      const pane = document.querySelector(".panel-panes").getBoundingClientRect();
      const barTop = bar.classList.contains("is-docked") ? Infinity : bar.getBoundingClientRect().top;
      return { clearOfBar: row.bottom <= barTop, belowHeader: row.top >= head.bottom - 1,
        inPane: row.top >= pane.top && row.bottom <= pane.bottom,
        dialog: Boolean(document.querySelector("dialog[open]")) };
    });
    assert.deepEqual(placed, { clearOfBar: true, belowHeader: true, inPane: true, dialog: false },
      `the located Classroom at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `locate-${width}.png`) });
    await page.getByRole("button", { name: "Clear selection", exact: true }).click();
  }
  await setPanelSize(page, 1280, 800);

  step("IP shows areas in ft² and ventilation in cfm; lighting stays in W");
  await page.evaluate(() => { window.previewHost.preferences.unit_system = "IP"; window.previewHost.snapshot(); });
  const labels = (await page.locator(`${shownTable} .phc-th-label`).allTextContents()).join(" | ");
  assert.match(labels, /ft²/);
  assert.match(labels, /cfm/);
  assert.match(labels, /Lighting \(W\)/);
  await page.screenshot({ path: path.join(output, "programs-ip.png") });
});
