/* Hot Water's piping pills in the preview: Pipe Types after Tanks with the nominal diameters, an edit in place,
   used length and a colour's Reset to default; the Piping pill's assign bar showing only the chosen role's values,
   Assign with the selection's references, Assign by clicking pressed while the tool runs, the Piping groups linked
   in place and Make Piping group from loose lines; the schedule with each branch under its trunk, a finding behind
   its glyph, totals by role and by System, and a row that Locates; By pipe role from the Role header; and the
   Systems table's recirculation columns contributed by piping; each at the panel's three sizes. Browser evidence;
   not host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-piping-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const PREFIX = "ph_composer.piping.";
const PT1 = "ppt_Pp11Tt22Yy33", DHW1 = "hws_Aa11Bb22Cc33";

check({ name: "piping", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const host = expression => page.evaluate(expression);
  const sent = name => host(`window.previewHost.sent.filter(m => m.payload && m.payload.name === ${
    JSON.stringify(name)})`);

  step("open Hot Water: Pipe Types and Piping follow Tanks");
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=mechanical`);
  await page.locator("[data-tab='mechanical']").click();
  const pane = page.locator("[data-pane='mechanical']");
  await pane.getByRole("tab", { name: "Hot Water" }).click();
  const pills = pane.getByRole("group", { name: "Hot Water tables" });
  assert.deepEqual(await pills.getByRole("button").allTextContents(),
    ["Systems", "Heaters", "Tanks", "Pipe Types", "Piping"]);

  step("Systems: piping's recirculation columns, read from the pipes or muted at honeybee-ph's defaults");
  const systems = pane.locator(".mech-hot-water-systems");
  const system = id => systems.locator(`[data-row-key='${id}']`);
  await system(DHW1).waitFor();
  assert.equal(await system(DHW1).locator(".col-recirculation_temperature_c").textContent(), "54.1");
  assert.equal(await system(DHW1).locator(".col-recirculation_hours").textContent(), "19");
  assert.match(await system("hws_Dd44Ee55Ff66").locator(".col-recirculation_hours").getAttribute("class"),
    /mech-muted/);
  assert.match(await systems.locator("th.col-recirculation_temperature_c").textContent(), /Recirc\. °C/);
  await page.screenshot({ path: path.join(output, "systems-recirculation.png") });

  step("Pipe Types: nominal diameters, an edit in place with its guard, and used length");
  await pills.getByRole("button", { name: "Pipe Types" }).click();
  const types = pane.locator(".piping-types");
  const typeRow = id => types.locator(`[data-row-key='${id}']`);
  await typeRow(PT1).waitFor();
  assert.equal(await typeRow(PT1).locator(".col-used_length_m").textContent(), "20");
  const diameter = typeRow(PT1).locator(".col-diameter_mm select");
  assert.deepEqual(await diameter.locator("option").allTextContents(),
    ["3/8 in", "1/2 in", "5/8 in", "3/4 in", "1 in", "1 1/4 in", "1 1/2 in", "2 in"]);
  await diameter.selectOption("25.4");
  await page.waitForFunction(id => window.previewHost.piping.types.filter(r => r.id === id)[0]
    .values.diameter_mm === 25.4, PT1);
  assert.deepEqual((await sent(PREFIX + "pipe_types.update")).pop().payload.params.expected_values,
    { diameter_mm: 19.05 });
  await pane.getByRole("button", { name: "+ New Pipe Type", exact: true }).first().waitFor();
  await page.screenshot({ path: path.join(output, "pipe-types.png") });

  step("Pipe Types: Reset to default shows only over a colour of the type's own, and clears it");
  const colourCell = id => typeRow(id).locator(".col-color button");
  const colourForm = page.locator(".phc-color-form:not([hidden])");
  const reset = colourForm.getByRole("button", { name: "Reset to default" });
  await colourCell("ppt_Qq44Rr55Ss66").click();
  await colourForm.waitFor();
  assert.equal(await reset.isVisible(), false, "PT-2 draws in its assigned colour");
  await colourForm.getByRole("button", { name: "Cancel" }).click();
  await colourCell(PT1).click();
  await reset.waitFor();
  await page.screenshot({ path: path.join(output, "pipe-type-colour-reset.png") });
  await reset.click();
  await page.waitForFunction(id => !("color" in window.previewHost.piping.types.filter(r => r.id === id)[0].values),
    PT1);
  assert.deepEqual((await sent(PREFIX + "pipe_types.update")).pop().payload.params,
    { id: PT1, values: { color: null }, expected_values: { color: "#3b7ea1" } });
  await colourForm.waitFor({ state: "detached" });
  assert.equal(await colourCell(PT1).evaluate(node => node.style.backgroundColor), "rgb(31, 119, 180)");

  step("Piping: the bar shows the role's values only, and Assign sends the selection");
  await pills.getByRole("button", { name: "Piping" }).click();
  // The line-group parts are shared with ducting, so they are found inside the Piping pill's own surface.
  const piping = pane.locator("#" + await pills.getByRole("button", { name: "Piping" }).getAttribute("aria-controls"));
  const bar = piping.getByRole("region", { name: "Assign to selected lines" });
  await bar.getByText("3 lines selected, 2 assignable").waitFor();
  await bar.getByLabel("Pipe Type for selected lines").selectOption(PT1);
  assert.equal(await bar.getByLabel("Multiplier").isVisible(), true);
  assert.equal(await bar.getByLabel("Hours a day").isVisible(), false);
  await bar.getByLabel("Role for selected lines").selectOption("recirculation");
  assert.equal(await bar.getByLabel("Multiplier").isVisible(), false);
  assert.equal(await bar.getByLabel("Hours a day").isVisible(), true);
  await bar.getByLabel("Role for selected lines").selectOption("trunk");
  await bar.getByLabel("Multiplier").fill("12");
  await bar.getByRole("button", { name: "Assign", exact: true }).click();
  await page.waitForFunction(() => window.previewHost.piping.selected[0].values.role === "trunk");
  const assign = (await sent(PREFIX + "pipes.assign")).pop().payload.params;
  assert.equal(assign.multiplier, 12);
  assert.equal(assign.targets.length, 2);

  step("Assign by clicking arms the pipe tool and stays pressed while it runs");
  await bar.getByRole("button", { name: "Assign by clicking lines" }).click();
  await bar.getByRole("button", { name: "Assign by clicking lines", pressed: true }).waitFor();
  assert.deepEqual((await sent(PREFIX + "pipe_tool.choose")).pop().payload.params,
    { pipe_type_id: PT1, role: "trunk", multiplier: 12, demand_recirculation: false });
  await page.screenshot({ path: path.join(output, "piping-tool.png") });
  await bar.getByRole("button", { name: "Stop assigning pipes by clicking" }).click();
  await bar.getByRole("button", { name: "Assign by clicking lines", pressed: false }).waitFor();

  step("the Piping groups: a System chosen in place, and Make Piping group from loose lines");
  const groups = piping.locator(".line-group-groups");
  await groups.locator("[data-row-key='520']").waitFor();
  assert.match(await groups.locator("[data-row-key='520'] .col-note").textContent(), /Link it to a Hot Water/);
  await groups.locator("[data-row-key='520'] .col-link select").selectOption(DHW1);
  await page.waitForFunction(() => window.previewHost.piping.groups[2].values.hot_water_system_id !== null);
  const make = bar.getByRole("button", { name: "Make Piping group from selected lines" });
  assert.equal(await make.isDisabled(), true, "lines already in a Piping group cannot make one");
  const why = bar.getByRole("button", { name: "Why Make Piping group is unavailable" });
  await why.waitFor();
  // The reason's icon stays beside Make Piping group however the bar wraps: at the panel's sizes and at every
  // width where Make is the last control that fits on a row.
  const widths = [[360, 520], [420, 732], [1280, 800]];
  for (let width = 1200; width <= 1500; width += 10) widths.push([width, 800]);
  for (const [width, height] of widths) {
    await setPanelSize(page, width, height);
    const [button, icon] = [await make.boundingBox(), await why.boundingBox()];
    assert.ok(Math.abs((button.y + button.height / 2) - (icon.y + icon.height / 2)) < 4 &&
      icon.x >= button.x + button.width, `the Make reason sits beside Make at ${width} x ${height}`);
  }
  await setPanelSize(page, 1280, 800);
  await page.screenshot({ path: path.join(output, "make-reason.png") });
  await host(`(() => {
    window.previewHost.piping.selected = [801, 802].map(id => ({ path: [id], reference: null, group: null,
      reason: "outside_group", values: {}, copied: false, record_problem: null, write_refusal: null }));
    window.previewHost.snapshot();
  })()`);
  await bar.getByText("2 lines selected, 0 assignable").waitFor();
  await make.click();
  const dialog = page.getByRole("dialog", { name: "Make Piping group" });
  await dialog.getByText("2 selected lines move into the new group where they are drawn.", { exact: false }).waitFor();
  await dialog.getByLabel("Hot Water System").selectOption(DHW1);
  await dialog.getByRole("button", { name: "Make Piping group", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });
  assert.deepEqual((await sent(PREFIX + "groups.make")).pop().payload.params,
    { edge_paths: [[801], [802]], hot_water_system_id: DHW1 });
  await bar.getByText("No lines selected").waitFor();

  step("the schedule: branches under their trunk, a finding, totals, and a row that Locates");
  const schedule = piping.locator(".line-group-schedule");
  await schedule.locator("[data-row-key='pipe_preview0002#1']").waitFor();
  const order = await schedule.locator("tbody tr[data-row-key]").evaluateAll(rows =>
    rows.map(row => row.getAttribute("data-row-key")));
  assert.deepEqual(order.slice(0, 4), ["pipe_preview0001#0", "pipe_preview0002#1", "pipe_preview0003#2",
    "pipe_preview0004#3"], "the trunk, its first branch and that branch's twigs");
  await schedule.getByRole("button", { name: "1 finding for Branch 3" }).click();
  await page.locator(".line-group-findings").getByText(/reaches no trunk/).waitFor();
  await page.keyboard.press("Escape");
  await piping.locator(".line-group-totals").getByText("By Hot Water System").waitFor();
  await schedule.locator("[data-row-key='pipe_preview0001#0'] .col-length_m").click();
  await page.waitForFunction(() => Array.isArray(window.previewHost.locatedPipes));
  await page.screenshot({ path: path.join(output, "piping.png"), fullPage: true });

  step("By pipe role from the Role header, off again once the tool that leased it stopped");
  const toggle = schedule.locator("th.col-role").getByRole("button", { name: /Colour by/ });
  assert.equal(await toggle.getAttribute("aria-pressed"), "false");
  await toggle.click();
  assert.equal((await sent("ph_composer.colour_by.activate")).pop().payload.params.mode, PREFIX + "by_role");

  step("Systems, Pipe Types and Piping at the panel's three sizes");
  for (const pill of ["Systems", "Pipe Types", "Piping"]) {
    await setPanelSize(page, 1280, 800);
    await pills.getByRole("button", { name: pill, exact: true }).click();
    for (const [width, height] of PANEL_SIZES) {
      await setPanelSize(page, width, height);
      assert.equal((await paneFacts(page, { floating: [], header: null })).sideways, false,
        `${pill} never scrolls the pane sideways at ${width} x ${height}`);
      await page.screenshot({ path: path.join(output, `${pill.toLowerCase().replace(" ", "-")}-${width}x${height}.png`) });
      if (pill !== "Piping") continue;
      // A run's findings bubble fits the panel, clear of the table's header, with its Locate in reach.
      const trigger = schedule.getByRole("button", { name: "1 finding for Branch 3" });
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
});
