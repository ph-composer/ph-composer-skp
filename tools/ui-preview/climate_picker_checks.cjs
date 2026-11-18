/* The station picker in the preview (P4c-09), boards 4, 11 and 16 at the panel's three sizes: 1,007 invented
   stations on the map and in the list, opening on the nearest with the map on the site's ring; the State filter
   and Find Nearest; a marker click selecting its row; hover facts; a failing station's warning before Attach; and
   Replace's comparison with its lost edits. Times the open, a selection and a filter with every station listed
   (entry check 3). Browser evidence, not host acceptance. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-climate-picker-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });
const CLIMATE = "ph_composer.climate.";

check({ name: "climate-picker", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  const sent = name => page.evaluate(n => window.previewHost.sent.filter(m => m.payload && m.payload.name === n), name);
  const picker = page.locator("dialog.climate-picker");
  const rows = picker.locator("tr[data-row-key]");

  async function open(fixture, button) {
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=${fixture}`);
    await page.locator("[data-tab='climate']").click();
    await page.locator("[data-pane='climate'] [data-card='phius']").click();
    const started = Date.now();
    await page.locator(".climate-phius").getByRole("button", { name: button }).click();
    await page.waitForFunction(() => document.querySelectorAll("dialog.climate-picker tr[data-row-key]").length === 1007);
    return Date.now() - started;
  }
  /* The dialog at every size: inside the window, never scrolling sideways, Attach or Replace in reach. */
  async function atSizes(name, commit) {
    for (const [width, height] of PANEL_SIZES) {
      await setPanelSize(page, width, height);
      const fit = await picker.evaluate(node => ({ box: node.getBoundingClientRect().toJSON(),
        sideways: node.scrollWidth > node.clientWidth + 1 }));
      assert.ok(fit.box.x >= 0 && fit.box.x + fit.box.width <= width + 0.5, `${name}: the dialog fits at ${width}`);
      assert.equal(fit.sideways, false, `${name}: the dialog scrolls sideways at ${width}`);
      const button = await picker.getByRole("button", { name: commit, exact: true }).boundingBox();
      assert.ok(button.y >= 0 && button.y + button.height <= height, `${name}: ${commit} is in reach at ${width}`);
      const controls = await picker.locator(".climate-picker-controls select").evaluateAll(nodes => nodes.map(n =>
        n.getBoundingClientRect().right));
      assert.ok(Math.max(...controls) <= fit.box.x + fit.box.width, `${name}: Dataset and State fit at ${width}`);
      const compare = picker.locator(".climate-picker-compare-scroll");
      if (await compare.count()) {
        const clipped = await compare.evaluate(node => Array.prototype.some.call(node.querySelectorAll("td"),
          cell => cell.scrollWidth > cell.clientWidth + 1));
        assert.equal(clipped, false, `${name}: the Now and New facts are not cut at ${width}`);
      }
      const stateColumn = await picker.locator("th.col-state").isVisible();
      assert.equal(stateColumn, width > 500, `${name}: the State column ${width > 500 ? "shows" : "gives way"} at ${width}`);
      const map = await picker.locator(".phc-outline-map").boundingBox();
      const list = await picker.locator(".climate-picker-list").boundingBox();
      assert.ok(width > 900 ? list.x > map.x + map.width - 1 : list.y >= map.y + map.height - 1,
        `${name}: the list ${width > 900 ? "beside" : "below"} the map at ${width}`);
      await picker.evaluate(node => { node.scrollTop = 0; });
      await page.screenshot({ path: path.join(output, `${name}-${width}.png`) });
    }
    await setPanelSize(page, 1280, 800);
  }

  step("board 4: every station listed and drawn, the nearest selected, the map on the site's ring");
  const opened = await open("climatepicker", "Choose Station…");
  assert.equal((await sent(CLIMATE + "stations.all")).length, 1);
  assert.equal((await sent(CLIMATE + "stations.list")).length, 0, "never paged");
  assert.equal(await picker.locator("[data-point]").count(), 1007);
  await picker.getByText("Preview Stations · 1,007 stations on this computer · 1,007 shown").waitFor();
  assert.equal(await rows.first().getAttribute("class"), "tier-0 host-selected");
  await picker.getByText("50 mi from the site").waitFor();
  const timing = { open_ms: opened };
  await atSizes("picker", "Attach");

  step("State and the search narrow the list and the map; Find Nearest returns to the opening view");
  await picker.getByLabel("State", { exact: true }).selectOption("XC");
  timing.filter_ms = await page.evaluate(() => {
    const select = document.querySelector("dialog.climate-picker select[aria-label=State]");
    const started = performance.now(); select.value = ""; select.dispatchEvent(new Event("change"));
    select.value = "XC"; select.dispatchEvent(new Event("change"));
    return Math.round((performance.now() - started) / 2);
  });
  const shown = await rows.evaluateAll(list => list.filter(row => !row.hidden).length);
  assert.equal(shown, await picker.locator("[data-point]").count());
  assert.ok(shown > 100 && shown < 140, `one state's stations (${shown})`);
  await picker.getByLabel("Filter stations").fill("Station XC 1022");
  assert.equal(await rows.evaluateAll(list => list.filter(row => !row.hidden).length), 1);
  await picker.getByRole("button", { name: "Find Nearest" }).click();
  assert.equal(await rows.evaluateAll(list => list.filter(row => !row.hidden).length), 1007);
  assert.equal(await picker.getByLabel("State", { exact: true }).inputValue(), "");

  step("a marker click selects its row and scrolls it into view; hover gives the four facts");
  const far = await rows.nth(600).getAttribute("data-row-key");
  timing.select_ms = await page.evaluate(key => {
    const marker = document.querySelector(`dialog.climate-picker [data-point="${key}"]`);
    const started = performance.now();
    const box = marker.getBoundingClientRect(), at = { bubbles: true, clientX: box.x + 5, clientY: box.y + 5,
      button: 0, isPrimary: true, pointerId: 1 };
    marker.querySelector("circle").dispatchEvent(new PointerEvent("pointerdown", at));
    marker.querySelector("circle").dispatchEvent(new PointerEvent("pointerup", at));
    return Math.round(performance.now() - started);
  }, far);
  assert.equal(await picker.locator(`tr[data-row-key="${far}"]`).getAttribute("class"), "tier-0 host-selected");
  const scrolled = await picker.locator(".climate-picker-list").evaluate(node => node.scrollTop);
  assert.ok(scrolled > 1000, "the row was scrolled into view");
  const near = await rows.first().getAttribute("data-row-key");
  const marker = picker.locator(`[data-point="${near}"] circle`);
  await marker.hover({ force: true });
  const tip = picker.locator(".phc-outline-map-tip");
  await tip.waitFor();
  assert.match(await tip.innerText(), /^Station .+\n[\d.]+ km · [+−]?[\d.]+ m\n(Pass|Outside Phius limits)$/);
  await page.screenshot({ path: path.join(output, "hover.png") });

  step("the keyboard: the arrows move along the list and Tab reaches Attach");
  await rows.first().locator(".climate-picker-station").focus();
  await page.keyboard.press("ArrowDown");
  assert.equal(await rows.nth(1).getAttribute("class"), "tier-0 host-selected");
  await page.keyboard.press("Tab");
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.textContent), "Attach");

  step("board 11: a failing station is warned about before Attach, which stays enabled");
  const failing = picker.locator("tr[data-row-key]").filter({ hasText: "Fail" }).first();
  await failing.locator(".climate-picker-station").click();
  await picker.locator(".climate-picker-warning").getByText("Phius asks for a custom dataset").waitFor();
  assert.equal(await picker.getByRole("button", { name: "Attach", exact: true }).isDisabled(), false);
  await atSizes("picker-fail", "Attach");
  await picker.getByRole("button", { name: "Attach", exact: true }).click();
  await picker.waitFor({ state: "detached" });
  assert.equal((await sent(CLIMATE + "climate.attach_station")).length, 1, "one action, no confirm");

  step("board 16: Replace compares the current and the selected, names the lost edits and replaces in one action");
  await open("climatereplace", "Replace Station…");
  await picker.getByText("has 2 edited values. Replacing it discards them.").waitFor();
  assert.equal(await rows.filter({ hasText: "Attached" }).count(), 1, "the attached station is marked");
  await rows.nth(3).locator(".climate-picker-station").click();
  assert.equal(await picker.locator(".climate-picker-compare tr").count(), 3);
  await atSizes("picker-replace", "Replace");
  await picker.getByRole("button", { name: "Replace", exact: true }).click();
  await picker.waitFor({ state: "detached" });
  assert.equal((await sent(CLIMATE + "climate.replace_station")).length, 1);
  fs.writeFileSync(path.join(output, "timing.json"), JSON.stringify(timing, null, 2));
  console.log("picker timing", JSON.stringify(timing));
});
