/* Building Segment heading rows and the settings dialog in the real panel with synthetic data
   (context/EXTENSIBILITY.md, "Zone views" and "Building Segment settings"): headings in Geometry and Spaces at every panel size, New Building Segment and its name in
   place, moving a checked Zone from the selection bar, Delete with a destination, a long name, the settings
   dialog with every shipped section and the development Note section (tools/examples/zones/example_segment_note.js),
   the Occupancy section with the Single dwelling tag and findings on the headings, and the Mechanical section.
   The preview host answers the writes; native transactions and Undo remain SketchUp acceptance gates. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { PANEL_SIZES, setPanelSize, paneFacts, assertPaneFits } = require("./support/pane_fit.cjs");
const { check } = require("./support/browser_evidence.cjs");
const BASE = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}/tools/ui-preview/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-segments-"));
fs.mkdirSync(output, { recursive: true });

const shownTable = ".phc-zone-view:not([hidden])";

function heading(page, name) {
  return page.locator(`${shownTable} tr.is-heading`).filter({
    has: page.locator(".phc-segment-name", { hasText: new RegExp(`^${name}$`) }) });
}

async function headings(page) {
  return page.locator(`${shownTable} tr.is-heading:not([hidden]) .phc-segment-name`).allTextContents();
}

function invokes(page) {
  return page.evaluate(() => window.previewHost.sent.filter(message => message.type === "action.invoke")
    .map(message => message.payload.name));
}

check({ name: "segment_rows", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(5000);
  step("open the zone options fixture: House (default, two Zones) and Annex (empty)");
  await page.goto(`${BASE}?fixture=zoneoptions`);
  await page.getByRole("heading", { name: "Zones", exact: true }).waitFor();
  assert.deepEqual(await headings(page), ["Annex", "House"]);
  assert.deepEqual(await heading(page, "House").locator(".phc-segment-tag").allTextContents(),
    ["Default", "Single dwelling"]);
  assert.equal(await heading(page, "Annex").locator(".phc-segment-flag").getAttribute("aria-label"),
    "Annex is residential and has no Dwelling.");
  assert.equal(await page.locator(`${shownTable} th`, { hasText: "Building" }).count(), 0, "no Segment column");

  step("headings at every panel size, Geometry and Spaces");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [] });
    assert.equal(facts.sideways, false, `the Zones pane scrolls sideways at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `geometry-headings-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);
  await page.getByRole("tab", { name: "Spaces", exact: true }).click();
  assert.deepEqual(await headings(page), ["Annex", "House"]);
  await page.screenshot({ path: path.join(output, "spaces-headings-1280.png") });
  const tagLine = await heading(page, "House").locator(".phc-segment-tag").evaluateAll(tags =>
    tags.map(tag => Math.round(tag.getBoundingClientRect().top)));
  assert.equal(new Set(tagLine).size, 1, "the House heading's tags share one line");

  step("a panel narrowed after it opened turns to the Name column, so headings show their names");
  for (const [width, height] of PANEL_SIZES.slice(1)) {
    await setPanelSize(page, width, height);
    const shown = await heading(page, "House").locator(".phc-segment-name").evaluate(node => {
      const box = node.getBoundingClientRect(), frame = node.closest(".phc-table-mount").getBoundingClientRect();
      return box.left >= frame.left && box.left + 20 <= frame.right;
    });
    assert.equal(shown, true, `the House heading names itself at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `spaces-headings-narrowed-${width}.png`) });
    await setPanelSize(page, 1280, 800);
  }
  await page.getByRole("tab", { name: "Geometry", exact: true }).click();

  step("a heading's actions show on hover; Delete holds on the last Segment");
  const house = heading(page, "House");
  await house.hover();
  await house.getByRole("button", { name: "Settings for House", exact: true }).waitFor();
  await house.getByRole("button", { name: "Delete House", exact: true }).waitFor();
  await page.screenshot({ path: path.join(output, "heading-actions.png") });

  step("New Building Segment opens its name in place, scrolled into view; Enter renames it");
  await page.evaluate(() => { const mount = document.querySelector(".phc-zone-view:not([hidden]) .phc-table-mount");
    mount.scrollTop = mount.scrollHeight; });
  await page.getByRole("button", { name: "New Building Segment", exact: true }).click();
  const name = page.getByRole("textbox", { name: "Building Segment name", exact: true });
  await name.waitFor();
  assert.equal(await name.inputValue(), "Building Segment 3");
  assert.equal(await name.evaluate(node => node === document.activeElement), true, "the name has focus");
  const field = await name.evaluate(node => ({ width: node.getBoundingClientRect().width,
    column: node.closest("td").clientWidth, text: node.scrollWidth <= node.clientWidth }));
  assert(field.width >= field.column - 20, `the name field spans the Name column (${field.width} of ${field.column})`);
  assert.equal(field.text, true, "the whole default name shows");
  assert.equal(await name.evaluate(node => {
    const box = node.getBoundingClientRect(), mount = node.closest(".phc-table-mount");
    const top = mount.getBoundingClientRect().top + mount.querySelector("thead").offsetHeight;
    return box.top >= top && box.bottom <= mount.getBoundingClientRect().bottom;
  }), true, "the new heading's name field is scrolled into view below the header");
  await page.screenshot({ path: path.join(output, "new-segment-name.png") });
  await name.fill("Garage");
  await name.press("Enter");
  await heading(page, "Garage").waitFor();
  assert.deepEqual(await headings(page), ["Annex", "Garage", "House"]);

  step("a checked Zone moves from the selection bar");
  await page.getByRole("checkbox", { name: "Check Living Zone", exact: true }).check();
  const move = page.getByRole("combobox", { name: "Building Segment for checked Zones", exact: true });
  await move.waitFor();
  assertPaneFits(await paneFacts(page), "the Geometry bar with a Building Segment");
  await page.screenshot({ path: path.join(output, "bar-move.png") });
  const garageId = await page.evaluate(() => window.previewHost.zoneOptions.building_segments
    .filter(entry => entry.values.name === "Garage")[0].id);
  await move.selectOption(garageId);
  await page.waitForFunction(id => window.previewHost.zones
    .filter(zone => zone.values.name === "Living Zone")[0].values.building_segment_id === id, garageId);
  assert.equal(await heading(page, "Garage").count(), 1);

  step("Delete names where the Zones go and sends that destination");
  const garage = heading(page, "Garage");
  await garage.hover();
  await garage.getByRole("button", { name: "Delete Garage", exact: true }).click();
  const confirm = page.getByRole("dialog", { name: "Delete Garage?", exact: true });
  await confirm.waitFor();
  await confirm.getByRole("combobox").selectOption({ label: "No Building Segment" });
  assert.match(await confirm.locator(".phc-segment-consequence").innerText(), /left out of export/);
  await page.screenshot({ path: path.join(output, "delete-destination.png") });
  await confirm.getByRole("button", { name: "Delete", exact: true }).click();
  await heading(page, "No Building Segment").waitFor();
  assert.deepEqual(await headings(page), ["Annex", "House", "No Building Segment"], "No Building Segment is last");
  assert.equal(await heading(page, "No Building Segment").locator("td.col-name").evaluate(node =>
    getComputedStyle(node).color !== getComputedStyle(node.closest("tr").nextElementSibling.querySelector("td.col-name")).color),
  true, "the No Building Segment heading is muted");

  step("the settings dialog: General, the shipped sections and the registered Note section, Save held by a problem");
  await house.hover();
  await house.getByRole("button", { name: "Settings for House", exact: true }).click();
  const settings = page.getByRole("dialog", { name: "Building Segment settings", exact: true });
  await settings.waitFor();
  assert.deepEqual(await settings.locator("h3").allTextContents(),
    ["General", "Occupancy", "Phius certification", "Airtightness", "Comfort", "Mechanical", "Note"]);
  assert.equal(await settings.getByRole("checkbox", { name: "New Zones join this Segment", exact: true }).isDisabled(), true);
  const result = await settings.locator(".phc-airtightness-result > *").evaluateAll(parts =>
    parts.map(part => { const box = part.getBoundingClientRect(); return Math.round(box.top + box.height / 2); }));
  assert.equal(result.length, 3);
  assert(Math.max(...result) - Math.min(...result) <= 2, "the test result's basis, value and unit share one line");
  const save = settings.getByRole("button", { name: "Save", exact: true });
  assert.equal(await save.isDisabled(), false, "an untouched section holds nothing");
  await settings.getByRole("textbox", { name: "Note text", exact: true }).fill(" ");
  assert.equal(await save.isDisabled(), true, "a blank note holds Save");
  assert.match(await settings.locator(".phc-form-status").innerText(), /Note: Enter a note\./);
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    assert(await settings.evaluate(node => {
      const box = node.getBoundingClientRect(), actions = node.querySelector(".phc-dialog-actions").getBoundingClientRect();
      return node.scrollWidth <= node.clientWidth && box.right <= innerWidth && actions.bottom <= box.bottom;
    }), `the settings dialog fits at ${width} x ${height}`);
    await page.screenshot({ path: path.join(output, `settings-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);
  const before = (await invokes(page)).length;
  await settings.press("Escape");
  await settings.waitFor({ state: "detached" });
  assert.equal((await invokes(page)).length, before, "Escape writes nothing");
  await house.hover();
  await house.getByRole("button", { name: "Settings for House", exact: true }).click();
  await settings.getByRole("textbox", { name: "Note text", exact: true }).fill("North wing");
  await settings.getByRole("textbox", { name: "Name", exact: true }).fill("Main house");
  await settings.getByRole("button", { name: "Save", exact: true }).click();
  await settings.waitFor({ state: "detached" });
  const saved = await page.evaluate(() => window.previewHost.zoneOptions.building_segments
    .filter(entry => entry.id === "bsg_house")[0]);
  assert.equal(saved.values.name, "Main house");
  assert.deepEqual(saved.extension_data["example.segment.note"].payload, { text: "North wing" });

  step("Occupancy: a single dwelling's house rows, disabled with its reason on a non-residential category");
  const main = heading(page, "Main house");
  await main.hover();
  await main.getByRole("button", { name: "Settings for Main house", exact: true }).click();
  await settings.waitFor();
  const single = settings.getByRole("checkbox", { name: "Single dwelling", exact: true });
  assert.equal(await single.isChecked(), true, "an absent payload reads as a single dwelling");
  assert.equal(await settings.getByRole("combobox", { name: "Default Program for its Zones", exact: true })
    .isDisabled(), true);
  const bedrooms = settings.getByRole("textbox", { name: "Bedrooms", exact: true });
  assert.equal(await bedrooms.getAttribute("placeholder"), "?");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    assert(await settings.evaluate(node => node.scrollWidth <= node.clientWidth),
      `the Occupancy section fits at ${width} x ${height}`);
    await settings.locator("[data-namespace='ph_composer.programs.segment']").screenshot({
      path: path.join(output, `occupancy-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);
  const category = settings.getByRole("combobox", { name: "Building category", exact: true });
  await category.selectOption("non_residential");
  assert.equal(await single.isDisabled(), true);
  assert.match(await settings.locator("[data-namespace='ph_composer.programs.segment']").innerText(),
    /Residential Building Segments only/);
  await settings.locator("[data-namespace='ph_composer.programs.segment']").screenshot({
    path: path.join(output, "occupancy-non-residential.png") });
  await category.selectOption("residential");
  await bedrooms.fill("3");
  await settings.getByRole("button", { name: "Save", exact: true }).click();
  await settings.waitFor({ state: "detached" });
  const occupancy = await page.evaluate(() => window.previewHost.zoneOptions.building_segments
    .filter(entry => entry.id === "bsg_house")[0].extension_data["ph_composer.programs.segment"].payload);
  assert.deepEqual(occupancy, { single_dwelling: true, default_program_id: null, bedrooms: 3, occupants: null,
    equipment_set_id: null });

  step("Mechanical: each number beside its unit, every panel size, six values in one Save");
  await main.hover();
  await main.getByRole("button", { name: "Settings for Main house", exact: true }).click();
  await settings.waitFor();
  const mechanical = settings.locator("[data-namespace='ph_composer.mechanical.segment']");
  assert.equal(await mechanical.getByRole("checkbox", { name: "Mechanical cooling", exact: true }).isChecked(), false);
  assert.equal(await mechanical.getByRole("textbox", { name: "Mechanical room temperature", exact: true }).inputValue(),
    "20");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    assert(await settings.evaluate(node => [node].concat(Array.from(node.querySelectorAll(".phc-segment-settings-body")))
      .every(scroller => scroller.scrollWidth <= scroller.clientWidth)),
    `the Mechanical section fits at ${width} x ${height}, its scrolling body included`);
    const lines = await mechanical.locator(".mech-segment-value").evaluateAll(rows => rows.map(row =>
      Array.from(row.children).map(part => { const box = part.getBoundingClientRect(); return box.top + box.height / 2; })));
    assert.equal(lines.length, 4, "the room temperature and three air change rates");
    lines.forEach(parts => assert(Math.max(...parts) - Math.min(...parts) <= 2,
      `a number and its unit share one line at ${width} x ${height}`));
    await mechanical.screenshot({ path: path.join(output, `mechanical-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);
  await mechanical.getByRole("checkbox", { name: "Mechanical cooling", exact: true }).check();
  await mechanical.getByRole("textbox", { name: "Mechanical room temperature", exact: true }).fill("18.5");
  await mechanical.getByRole("combobox", { name: "Summer bypass", exact: true }).selectOption("enthalpy_controlled");
  await mechanical.getByRole("textbox", { name: "Windows, nighttime air changes", exact: true }).fill("1.5");
  await settings.getByRole("button", { name: "Save", exact: true }).click();
  await settings.waitFor({ state: "detached" });
  const mechanicalSaved = await page.evaluate(() => window.previewHost.zoneOptions.building_segments
    .filter(entry => entry.id === "bsg_house")[0].extension_data["ph_composer.mechanical.segment"].payload);
  assert.deepEqual(mechanicalSaved, { mechanical_cooling: true, mech_room_temp_c: 18.5,
    summer_bypass_mode: "enthalpy_controlled", ventilation_system_ach: null, daytime_window_ach: 0,
    nighttime_window_ach: 1.5 });

  step("a long name is cut in its cell and whole in its tooltip");
  const long = "Residential tower with retail podium and below-grade parking, phase two";
  await page.evaluate(text => { window.previewHost.zoneOptions.building_segments[1].values.name = text;
    window.previewHost.snapshot(); }, long);
  for (const [width, height] of [[1280, 800], [360, 520]]) {
    await setPanelSize(page, width, height);
    const label = heading(page, long).locator(".phc-segment-name");
    assert(await label.evaluate(node => node.scrollWidth > node.clientWidth &&
      getComputedStyle(node).textOverflow === "ellipsis"), `the long name is cut at ${width}`);
    assert.equal(await label.getAttribute("data-tooltip"), long);
    assert.equal((await paneFacts(page, { floating: [] })).sideways, false, `no sideways scroll at ${width}`);
    await page.screenshot({ path: path.join(output, `long-name-${width}.png`) });
  }
  return `Segment heading browser checks passed; evidence: ${output}`;
});
