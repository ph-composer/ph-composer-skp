/* The Thermal Bridges tab in the preview: Types edits and forms, the assign bar, the Schedule read on opening,
   Locate and the totals, at the panel's sizes. Browser evidence for P3b-05; not host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-thermal-bridges-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const TB = "ph_composer.thermal_bridges.";

check({ name: "thermal_bridges", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const host = expression => page.evaluate(expression);
  const sent = name => host(`window.previewHost.sent.filter(m => m.payload && m.payload.name === ${
    JSON.stringify(name)})`);
  step("open the tab, which reads the schedule once");
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=thermalbridges`);
  await page.locator("[data-tab='thermal_bridges']").click();
  const pane = page.locator("[data-pane='thermal_bridges']");
  await pane.getByRole("heading", { name: "Thermal Bridges", exact: true }).waitFor();
  const types = pane.locator(".tb-types");
  await types.locator("[data-row-key='tbt_Aa11Bb22Cc33'] .col-length_m").getByText("34", { exact: true }).waitFor();
  assert.equal((await sent(TB + "schedule.all")).length, 1);
  assert.equal(await types.locator("[data-row-key='tbt_Dd44Ee55Ff66'] select").inputValue(), "17-FS/BC");
  assert.equal(await types.locator("[data-row-key='tbt_Dd44Ee55Ff66'] select option:checked").textContent(),
    "Floor slab / basement ceiling");
  await page.screenshot({ path: path.join(output, "types.png") });

  step("edit a psi-value in place");
  const psi = types.locator("[data-row-key='tbt_Gg77Hh88Ii99'] [data-record-field='psi_w_mk']");
  await psi.dblclick();
  await psi.fill("0.05");
  await psi.press("Enter");
  await page.waitForFunction(() => window.previewHost.thermalBridges.types[2].values.psi_w_mk === 0.05);
  await types.locator("[data-row-key='tbt_Aa11Bb22Cc33'] .col-length_m.tb-muted").waitFor();

  step("assign the selected Edges from the bar");
  const bar = types.locator(".tb-assign-bar");
  await bar.getByText("3 Edges selected", { exact: true }).waitFor();
  await bar.getByRole("combobox", { name: "Thermal Bridge Type for selected Edges" }).selectOption("tbt_Dd44Ee55Ff66");
  await bar.getByRole("button", { name: "Assign", exact: true }).click();
  await page.waitForFunction(() => window.previewHost.thermalBridges.selected.every(edge =>
    edge.values.thermal_bridge_type_id === "tbt_Dd44Ee55Ff66"));
  assert.equal((await sent(TB + "edges.assign"))[0].payload.params.targets.length, 3);

  step("create, duplicate and delete in the form dialog");
  await pane.getByRole("button", { name: "+ New Thermal Bridge Type", exact: true }).click();
  const create = page.getByRole("dialog", { name: "New Thermal Bridge Type" });
  await create.getByRole("textbox", { name: "Name", exact: true }).fill("Window sill");
  await create.getByRole("textbox", { name: "ψ-value", exact: true }).fill("-0.03");
  await create.getByRole("button", { name: /Create Thermal Bridge Type$/ }).click();
  await create.waitFor({ state: "hidden" });
  assert.equal(await host("window.previewHost.thermalBridges.types[3].values.psi_w_mk"), -0.03);
  await types.getByRole("button", { name: "Duplicate Window sill", exact: true }).click();
  const duplicate = page.getByRole("dialog", { name: "Duplicate Thermal Bridge Type" });
  assert.equal(await duplicate.getByRole("textbox").inputValue(), "Window sill (copy)");
  await duplicate.getByRole("button", { name: /Duplicate Thermal Bridge Type$/ }).click();
  await duplicate.waitFor({ state: "hidden" });
  await types.getByRole("button", { name: "Delete Window sill (copy)", exact: true }).click();
  const remove = page.getByRole("dialog", { name: /Window sill \(copy\)$/ });
  await remove.getByRole("combobox").selectOption("__clear__");
  await remove.getByRole("button", { name: /delete$/i }).click();
  await remove.waitFor({ state: "hidden" });
  assert.equal(await host("window.previewHost.thermalBridges.types.length"), 4);

  step("a display unit switch keeps a refused draft");
  const draft = types.locator("[data-row-key='tbt_Aa11Bb22Cc33'] [data-record-field='psi_w_mk']");
  await draft.dblclick();
  await draft.fill("0.2");
  await host("window.previewHost.thermalBridges.types[0].values.psi_w_mk = 0.14");
  await draft.press("Enter");
  await page.waitForFunction(() => document.querySelector("[data-section='thermal_bridges']")._view.types
    .inventory.edits.cells["tbt_Aa11Bb22Cc33:psi_w_mk"].status === "error");
  await page.getByRole("button", { name: "Set display units to IP", exact: true }).click();
  assert.equal(await draft.inputValue(), "0.2", "a refused draft keeps its starting units");
  await page.screenshot({ path: path.join(output, "types-refused-draft-ip.png") });
  await draft.press("Escape");
  await page.getByRole("button", { name: "Set display units to SI", exact: true }).click();
  assert.equal(await host("window.previewHost.thermalBridges.types[0].values.psi_w_mk"), 0.14);

  step("the Group column filters from its menu");
  await types.locator("th.col-group").hover();
  await types.locator("th.col-group").getByRole("button", { name: /Group column menu/ }).click();
  const menu = page.locator(".phc-column-menu:visible");
  await menu.locator(".phc-column-filter-value").filter({ hasText: /^Ambient$/ }).locator("input").uncheck();
  await types.locator("[data-row-key='tbt_Aa11Bb22Cc33']").waitFor({ state: "hidden" });
  await types.locator("[data-row-key='tbt_Dd44Ee55Ff66']").waitFor();
  await page.screenshot({ path: path.join(output, "types-group-filter.png") });
  await menu.getByRole("button", { name: "Clear filter", exact: true }).click();
  await page.keyboard.press("Escape");
  await types.locator("[data-row-key='tbt_Aa11Bb22Cc33']").waitFor();

  step("the Schedule reads the changed Model, locates a run and a finding, and totals");
  await pane.getByRole("tab", { name: "Schedule", exact: true }).click();
  const schedule = pane.locator(".tb-schedule");
  await page.waitForFunction(() => window.previewHost.sent.filter(m => m.payload &&
    m.payload.name === "ph_composer.thermal_bridges.schedule.all").length === 2);
  await schedule.locator("[data-row-key='tb_Aa11Bb22Cc33']").waitFor();
  assert.equal(await schedule.locator(".phc-view-count").textContent(), "3 runs");
  await schedule.getByRole("button", { name: "Locate Parapet 1", exact: true }).click();
  await page.waitForFunction(() => (window.previewHost.locatedEdges || []).length === 4);
  await schedule.getByRole("button", { name: "1 finding for Parapet 2", exact: true }).click();
  const finding = page.getByRole("dialog", { name: "Findings" });
  await finding.getByText(/counted twice/).waitFor();
  await page.screenshot({ path: path.join(output, "schedule-finding.png") });
  await finding.getByRole("button", { name: "Locate", exact: true }).click();
  await page.waitForFunction(() => JSON.stringify(window.previewHost.locatedEdges) === "[[200,401]]");
  await schedule.getByRole("heading", { name: "Totals", exact: true }).waitFor();
  await schedule.getByRole("heading", { name: "Not in the schedule (1)", exact: true }).waitFor();
  await page.screenshot({ path: path.join(output, "schedule.png"), fullPage: true });

  step("both subtabs fit the panel's sizes");
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    for (const tab of ["Types", "Schedule"]) {
      await pane.getByRole("tab", { name: tab, exact: true }).click();
      assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false,
        `${tab} does not scroll sideways at ${width} x ${height}`);
      await page.screenshot({ path: path.join(output, `${tab.toLowerCase()}-${width}x${height}.png`) });
    }
  }
  return `thermal bridges browser checks passed; screenshots: ${output}`;
});
