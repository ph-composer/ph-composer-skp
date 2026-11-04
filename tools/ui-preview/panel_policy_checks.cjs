/* The shipped pages under their own Content-Security-Policy in Chromium. The panel, html/index.html, starts
   from boot.js with no inline script; a blocked run's report opens in its sandboxed srcdoc frame with the
   report's inline stylesheet applied (a srcdoc frame inherits the page's policy and is not a frame-src load,
   which this shows rather than assumes); and an inline script is refused and reported as
   panel_csp_violation, so the policy is shown in force, not only declared. Agent Access and Help &
   Diagnostics start from boot.js too. The collector fails the run on any other console error. A stand-in
   `sketchup` bridge records what each page sends; messages arrive as the host's execute_script delivers
   them. This is neither HtmlDialog nor file:// proof; that is the native host gate. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");

const BASE = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}/src/ph_composer/html/`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-policy-"));
fs.mkdirSync(output, { recursive: true });

// The shape of Export::Report's page: an inline stylesheet, a heading and the result embedded as JSON.
const REPORT = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Export not created</title>" +
  "<style>h1 { color: rgb(170, 0, 0); }</style></head><body><main><h1>Export not created</h1>" +
  "<p>Resolve the blocking findings.</p></main>" +
  "<script id=\"ph-composer-result\" type=\"application/json\">{\"findings\":[]}</script></body></html>";
const SNAPSHOT = { product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 1,
  file_name: "house.skp", edit_path: [], sections: {},
  preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } };

check({ name: "panel_policy", output }, async ({ newPage, step, expect }) => {
  const page = await newPage({ viewport: { width: 1100, height: 800 } });
  await page.route("**/favicon.ico", route => route.fulfill({ status: 204 }));
  await page.addInitScript(() => {
    window.sent = [];
    const record = message => window.sent.push(JSON.parse(message));
    window.sketchup = { ph_composer_message: record, ph_composer_agent_access: record, ph_composer_support: record };
  });
  const deliver = (type, payload) => page.evaluate(([kind, body]) => {
    PhComposerUI.get("panel").receive({ type: kind, payload: body });
  }, [type, payload]);
  const sent = type => page.evaluate(kind => window.sent.filter(message => message.type === kind), type);

  step("start the shipped panel page under its policy");
  await page.goto(`${BASE}index.html`);
  assert.match(await page.locator("meta[http-equiv='Content-Security-Policy']").getAttribute("content"),
    /script-src 'self';/);
  assert.equal((await sent("panel.ready")).length, 1, "boot.js started the panel");
  await deliver("panel.snapshot", SNAPSHOT);

  step("a blocked run's report in its sandboxed frame");
  await page.evaluate(() => PhComposerUI.get("panel").showTab("export"));
  const [preflight, latest] = [...await sent("export.preflight"), ...await sent("export.latest")];
  await deliver("export.result", { request_id: preflight.payload.request_id, session: "session-a",
    outcome: { status: "completed", value: { findings: [], repairs: [] } } });
  await deliver("export.result", { request_id: latest.payload.request_id, session: "session-a",
    outcome: { status: "completed", value: null } });
  await page.locator("[data-section='export'] button").first().click();
  const [start] = await sent("export.start");
  await deliver("export.result", { request_id: start.payload.request_id, session: "session-a", outcome: {
    status: "completed", value: { task_id: "task-1", outcome: { status: "refused", code: "export.blocked",
      message: "Export not created. Resolve the blocking findings.", findings: [],
      value: { result: { findings: [] }, report_html: REPORT } } } } });
  await page.getByText("Last export report").click();
  const frame = page.frameLocator("iframe[title='Last export report']");
  const heading = frame.getByRole("heading", { name: "Export not created" });
  await heading.waitFor();
  assert.equal(await heading.evaluate(node => getComputedStyle(node).color), "rgb(170, 0, 0)",
    "the report's inline stylesheet applies in the frame");
  await page.screenshot({ path: path.join(output, "blocked-report.png") });

  step("an inline script is refused and reported");
  expect("console", /violates the following Content Security Policy directive/);
  await page.evaluate(() => {
    const script = document.createElement("script");
    script.textContent = "window.inlineRan = true;";
    document.head.appendChild(script);
  });
  await page.waitForFunction(() => window.sent.some(message => message.type === "panel.diagnostic"));
  assert.equal(await page.evaluate(() => window.inlineRan), undefined, "the inline script did not run");
  assert.deepEqual((await sent("panel.diagnostic")).map(message => message.payload), [{
    event: "panel_csp_violation", section: null, error_class: "SecurityPolicyViolation", frames: [] }]);

  for (const [folder, ready] of [["agent_access", "access.ready"], ["support", "support.ready"]]) {
    step(`the ${folder} page starts from boot.js under its policy`);
    await page.goto(`${BASE}${folder}/index.html`);
    assert.equal((await sent(ready)).length, 1, `${folder} announced ${ready}`);
  }

  return `PASS: pages under their policies: panel boot.js start, blocked-run report heading and inline style ` +
    `in its srcdoc frame, an inline script refused and reported, Agent Access and Help & Diagnostics started; ` +
    `evidence in ${output}`;
});
