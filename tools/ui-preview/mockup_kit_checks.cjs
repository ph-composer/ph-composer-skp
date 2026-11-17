/* The mockup kit (tools/ui-preview/.index.md, "Mockup kit") on its starter page: panel stylesheets load,
   `do=` replay reaches the state and flags itself ready, an unknown step is a console error, the journey
   strip restarts a journey, and data-tip shows the kit tooltip. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE ||
  fs.mkdtempSync(path.join(os.tmpdir(), "ph-composer-mockup-kit-"));
const port = process.env.UI_PREVIEW_PORT || "8765";
const STARTER = `http://127.0.0.1:${port}/tools/ui-preview/mockup/starter/mockup.html`;
fs.mkdirSync(output, { recursive: true });

check({ name: "mockup-kit", output }, async ({ newPage, step, expect }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(5000);
  const ready = () => page.waitForSelector("html[data-mockup-ready]");

  step("replay a journey and a step");
  await page.goto(`${STARTER}?journey=2&do=check`);
  await ready();
  assert.equal(await page.locator(".phc-heading").evaluate((n) => getComputedStyle(n).display), "flex",
    "the panel's base.css is loaded");
  assert.equal(await page.getByRole("button", { name: "2 · One flagged" }).getAttribute("aria-pressed"), "true");
  assert.equal(await page.getByRole("checkbox", { name: "Check Living" }).isChecked(), true);
  assert.equal(await page.locator(".mk-notice").count(), 0, "replay shows no transient notice");
  assert.equal(await page.evaluate(() => window.MOCKUP.scenes.length), 2);

  step("hover a data-tip");
  await page.locator(".zp-flag").hover();
  assert.equal(await page.getByRole("tooltip").innerText(), "No Assembly on the Attic floor");

  step("restart from the strip");
  await page.getByRole("button", { name: "1 · Three Zones" }).click();
  assert.equal(await page.getByRole("checkbox", { name: "Check Living" }).isChecked(), false);
  assert.match(await page.locator(".mk-hint").innerText(), /Check a Zone/);

  step("an unknown step is a console error");
  expect("console", "Mockup: no step named nope");
  await page.goto(`${STARTER}?do=nope`);
  await ready();
});
