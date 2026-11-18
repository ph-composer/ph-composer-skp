/* The Climate tab in the preview (P4c-06): the tab row with Climate first, the source cards and the narrow select,
   Set Location with Read from SketchUp Geolocation, its no-geolocation state, and the design temperatures, at the
   panel's three sizes. Browser evidence, not host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-climate-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const CLIMATE = "ph_composer.climate.";

check({ name: "climate", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const sent = name => page.evaluate(n => window.previewHost.sent.filter(m => m.payload && m.payload.name === n), name);
  const pane = page.locator("[data-pane='climate']");
  const tabRow = () => page.evaluate(() => {
    const tabs = Array.from(document.querySelectorAll(".phc-tabs button"));
    const nav = document.querySelector(".phc-tabs").getBoundingClientRect();
    return { lines: new Set(tabs.map(tab => tab.offsetTop)).size, count: tabs.length,
      reachable: tabs.every(tab => { const box = tab.getBoundingClientRect();
        return box.right <= innerWidth + 0.5 && box.left >= -0.5 && box.bottom <= nav.bottom + 0.5; }) };
  });

  step("the panel opens on Zones with Climate first in the row");
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=climate`);
  await page.locator("[data-pane='overview']").waitFor();
  assert.equal(await page.locator(".phc-tabs button").first().textContent(), "Climate");
  assert.equal(await page.locator("[data-tab='overview']").getAttribute("aria-pressed"), "true");
  assert.equal(await pane.isHidden(), true);

  step("the tab and its cards at the three panel sizes");
  await page.locator("[data-tab='climate']").click();
  await pane.getByRole("heading", { name: "Climate", exact: true }).waitFor();
  const rows = {};
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const row = await tabRow();
    rows[width] = row;
    assert.equal(row.reachable, true, `every tab is reachable at ${width}`);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the pane scrolls sideways at ${width}`);
    const narrow = width < 700;
    assert.equal(await pane.locator(".phc-source-card-select").isVisible(), narrow, `the select at ${width}`);
    assert.equal(await pane.locator(".phc-source-card-list").isVisible(), !narrow, `the cards at ${width}`);
    await page.screenshot({ path: path.join(output, `site-empty-${width}.png`) });
  }
  fs.writeFileSync(path.join(output, "tab-rows.json"), JSON.stringify(rows, null, 2));
  console.log(`tab row lines: ${JSON.stringify(rows)}`);
  await setPanelSize(page, 1280, 800);
  assert.equal(await pane.locator("[data-card='site'] .phc-source-card-chip").textContent(), "Not set");
  assert.equal(await pane.locator("[data-card='hourly']").isDisabled(), true);
  await pane.locator("[data-card='hourly']").click({ force: true });
  assert.equal(await pane.locator("[data-card='site']").getAttribute("aria-current"), "true",
    "the Planned card does nothing");

  step("Set Location: Read from SketchUp Geolocation fills latitude and longitude, then Set");
  await pane.locator(".phc-heading").getByRole("button", { name: "Set Location…" }).click();
  const dialog = page.locator("dialog.climate-set-location");
  await dialog.waitFor();
  const set = dialog.getByRole("button", { name: "Set Location", exact: true });
  assert.equal(await set.isDisabled(), true);
  await dialog.getByRole("button", { name: "Read from SketchUp Geolocation" }).click();
  await dialog.getByText("Latitude and longitude are filled from SketchUp.").waitFor();
  assert.equal(await dialog.getByLabel("Latitude", { exact: true }).inputValue(), "42.75");
  assert.equal(await dialog.getByLabel("Elevation", { exact: true }).inputValue(), "");
  assert.equal((await sent(CLIMATE + "site.update")).length, 0);
  await page.screenshot({ path: path.join(output, "set-location-filled.png") });
  await dialog.getByLabel("Elevation", { exact: true }).fill("84");
  await dialog.getByLabel("Climate zone", { exact: true }).selectOption({ label: "5" });
  await dialog.getByLabel("Hours from UTC", { exact: true }).fill("-5");
  await set.click();
  await dialog.waitFor({ state: "detached" });
  assert.equal((await sent(CLIMATE + "site.update")).length, 1);
  await pane.locator("[data-card='site']").getByText("Climate zone 5 · UTC −5").waitFor();

  step("a Model with no geolocation says so (board 22)");
  await page.evaluate(() => { window.previewHost.climate.geolocation = { geolocated: false, latitude_deg: null,
    longitude_deg: null, hours_from_utc: null }; });
  await pane.locator(".phc-heading").getByRole("button", { name: "Set Location…" }).click();
  await dialog.waitFor();
  await dialog.getByRole("button", { name: "Read from SketchUp Geolocation" }).click();
  await dialog.getByText("This SketchUp model has no geolocation.").waitFor();
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const box = await dialog.boundingBox();
    assert.ok(box.x >= 0 && box.x + box.width <= width + 0.5, `the dialog fits at ${width}`);
    await page.screenshot({ path: path.join(output, `set-location-no-geolocation-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);
  await dialog.getByRole("button", { name: "Cancel" }).click();
  await dialog.waitFor({ state: "detached" });

  step("design temperatures commit per field and warn without refusing");
  await pane.locator("[data-card='design']").click();
  const design = pane.locator(".climate-design");
  await design.getByLabel("99% heating dry bulb").fill("-17.2");
  await design.getByLabel("99% heating dry bulb").press("Enter");
  await page.waitForFunction(() => window.previewHost.climate.design.heating_99_c === -17.2);
  await design.getByLabel("1% cooling dry bulb").fill("30.1");
  await design.getByLabel("1% cooling dry bulb").press("Tab");
  await page.waitForFunction(() => window.previewHost.climate.design.cooling_1_c === 30.1);
  assert.equal((await sent(CLIMATE + "design_temperatures.update")).length, 2);
  await pane.locator("[data-card='design'] .phc-source-card-chip").getByText("Set").waitFor();
  await design.getByLabel("1% cooling dry bulb").fill("warm");
  await design.getByLabel("1% cooling dry bulb").press("Enter");
  const error = design.locator(".phc-unit-error:visible");
  await error.waitFor();
  const [inputBox, errorBox] = [await design.getByLabel("1% cooling dry bulb").boundingBox(), await error.boundingBox()];
  assert.ok(errorBox.y >= inputBox.y + inputBox.height - 0.5, "a field's error sits below it");
  await page.screenshot({ path: path.join(output, "design-error.png") });
  await design.getByLabel("1% cooling dry bulb").press("Escape");
  assert.equal((await sent(CLIMATE + "design_temperatures.update")).length, 2, "an unreadable value is not sent");
  await design.getByLabel("99% heating dry bulb").fill("35");
  await design.getByLabel("99% heating dry bulb").press("Enter");
  await design.locator(".climate-design-warning").getByText(/at or above the cooling/).waitFor();
  assert.equal(await page.evaluate(() => window.previewHost.climate.design.heating_99_c), 35);

  step("IP: the design temperatures and the elevation in IP units");
  await page.locator("[data-unit-system='IP']").click();
  await page.waitForFunction(() =>
    document.querySelector("[aria-label='99% heating dry bulb']").value === "95");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the design pane scrolls sideways at ${width}`);
    await page.screenshot({ path: path.join(output, `design-ip-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);
  await page.locator("[data-unit-system='SI']").click();

  step("a set site and its export fields at the three sizes");
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=climateset`);
  await page.locator("[data-tab='climate']").click();
  await pane.locator(".climate-facts").waitFor();
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the site pane scrolls sideways at ${width}`);
    await page.screenshot({ path: path.join(output, `site-set-${width}.png`) });
  }
});
