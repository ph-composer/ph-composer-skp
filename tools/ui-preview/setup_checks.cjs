/* The Setup gear and view on the real panel with the preview host: the gear closes the tab row at every panel
   size, opens the Setup view, which lists the host's entries and asks for one by name. Opening the Agent Access
   window itself is a host check (the preview has no native windows). */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-setup-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
fs.mkdirSync(output, { recursive: true });

check({ name: "setup", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(5000);
  step("open the panel and its Setup gear");
  await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/`);
  const gear = page.getByRole("button", { name: "Setup", exact: true });
  await gear.click();
  const view = page.locator("[data-section='setup']");
  await view.getByRole("heading", { name: "Setup", level: 1 }).waitFor();
  assert.equal(await gear.getAttribute("aria-pressed"), "true");
  assert.equal(await page.locator(".phc-tabs [aria-pressed='true']").count(), 0, "no section tab stays current");
  await view.getByRole("heading", { name: "Agent Access", level: 2 }).waitFor();
  assert.equal(await view.locator(".phc-setup-entry p").textContent(), "Listening on port 46110 · 1 live token");
  for (const [width, height] of PANEL_SIZES) {
    step(`Setup at ${width} x ${height}`);
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the pane scrolls sideways at ${width}`);
    const fit = await page.evaluate(() => {
      const gearBox = document.querySelector("[data-tab='setup']").getBoundingClientRect();
      const header = document.querySelector(".phc-app-header").getBoundingClientRect();
      const button = document.querySelector(".phc-setup-entry button").getBoundingClientRect();
      return { gear: gearBox.right <= innerWidth && gearBox.top >= header.top && gearBox.bottom <= header.bottom,
        button: button.right <= innerWidth && button.left >= 0 };
    });
    assert.ok(fit.gear, `the gear sits inside the tab row at ${width}`);
    assert.ok(fit.button, `the entry's button is in view at ${width}`);
    await page.screenshot({ path: path.join(output, `setup-${width}x${height}.png`) });
  }
  step("an entry is asked for by name");
  await view.getByRole("button", { name: "Agent Access…", exact: true }).click();
  const asked = await page.evaluate(() => previewHost.sent.filter(message => message.type === "panel.setup_open")
    .map(message => message.payload.name));
  assert.deepEqual(asked, ["ph_composer.agent_access.open"]);
  return `Setup browser checks passed; evidence: ${output}`;
});
