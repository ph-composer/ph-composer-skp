/* The outline map (P4c-07) in Chromium: the shipped panel page with Set Location open reaches no network and
   reports no content-policy violation; Set Location in the preview at the panel's three sizes, where a click
   places the site and a site far from the attached station warns; and the development example with a thousand
   markers, timed for first paint and for pan and zoom frames. The current Chrome, not the Chromium 88 floor,
   which the ESLint API list holds; neither is HtmlDialog proof. Timings go to map-timing.json in the output. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./support/browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, paneFacts } = require("./support/pane_fit.cjs");

const port = process.env.UI_PREVIEW_PORT || "8765";
const ROOT = `http://127.0.0.1:${port}`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-map-"));
fs.mkdirSync(output, { recursive: true });
const CLIMATE = "ph_composer.climate.";
const SITE = { latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15, hours_from_utc: -5,
  climate_zone_label: "5", state: "set" };
const SNAPSHOT = { product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 1,
  file_name: "house.skp", edit_path: [],
  sections: { [CLIMATE + "site"]: { status: "completed", value: SITE },
    [CLIMATE + "design_temperatures"]: { status: "completed", value: { heating_99_c: null, cooling_1_c: null,
      design_temperature_source: null, state: "not_set", warning: null } },
    [CLIMATE + "summary"]: { status: "completed", value: { site: "set", design_temperatures: { state: "not_set",
      warning: null }, climate: { state: "complete", origin: "station", verdict: "pass", edited: false } } } },
  preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } };

check({ name: "outline_map", output }, async ({ newPage, step }) => {
  step("the shipped panel with Set Location and its map open: no request and no policy violation");
  const shipped = await newPage({ viewport: { width: 1280, height: 800 } });
  await shipped.route("**/favicon.ico", route => route.fulfill({ status: 204 }));
  await shipped.addInitScript(() => {
    window.sent = [];
    window.violations = [];
    document.addEventListener("securitypolicyviolation", event => {
      window.violations.push(event.violatedDirective + " " + event.blockedURI);
    });
    window.sketchup = { ph_composer_message: message => window.sent.push(JSON.parse(message)) };
  });
  const requests = [];
  shipped.on("request", request => requests.push(request.url()));
  await shipped.goto(`${ROOT}/src/ph_composer/html/index.html`);
  await shipped.waitForFunction(() => window.PhComposerUI && PhComposerUI.get("panel"));
  await shipped.evaluate(snapshot => PhComposerUI.get("panel").receive({ type: "panel.snapshot", payload: snapshot }),
    SNAPSHOT);
  await shipped.locator("[data-tab='climate']").click();
  const loaded = requests.length;
  await shipped.locator("[data-pane='climate'] .phc-heading").getByRole("button", { name: "Set Location…" }).click();
  await shipped.locator(".climate-set-location .phc-outline-map-countries").waitFor({ state: "attached" });
  const read = await shipped.evaluate(name => window.sent.filter(m => m.payload && m.payload.name === name)[0], CLIMATE +
    "climate.get");
  await shipped.evaluate(([id, session]) => PhComposerUI.get("panel").receive({ type: "query.result", payload: {
    request_id: id, session: session, outcome: { status: "completed", value: { state: "complete", missing: [],
      edited_cells: [], limit_check: null, climate: { id: "c", values: { name: "Northfield Regional",
        station_latitude_deg: 42.82, station_longitude_deg: -73.62, station_elevation_m: 90 } } } } } }),
  [read.payload.request_id, read.payload.session]);
  await shipped.locator(".climate-set-location [data-point='station']").waitFor({ state: "attached" });
  const drawing = shipped.locator(".climate-set-location .phc-outline-map-drawing");
  const box = await drawing.boundingBox();
  await shipped.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await shipped.mouse.down();
  await shipped.mouse.move(box.x + box.width / 2 + 80, box.y + box.height / 2 + 40, { steps: 6 });
  await shipped.mouse.up();
  await shipped.mouse.wheel(0, -300);
  await shipped.getByRole("button", { name: "Reset map view" }).click();
  assert.deepEqual(requests.slice(loaded), [], "the map and its gestures fetch nothing");
  assert.ok(requests.every(url => url.startsWith(`${ROOT}/src/ph_composer/html/`)), "only the extension's own files");
  assert.deepEqual(await shipped.evaluate(() => window.violations), []);
  await shipped.screenshot({ path: path.join(output, "shipped-set-location.png") });

  step("Set Location with an attached station at the three panel sizes");
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(`${ROOT}/tools/ui-preview/?fixture=climatestation`);
  await page.locator("[data-tab='climate']").click();
  const pane = page.locator("[data-pane='climate']");
  await pane.locator(".phc-heading").getByRole("button", { name: "Set Location…" }).click();
  const dialog = page.locator("dialog.climate-set-location");
  await dialog.locator("[data-point='station']").waitFor({ state: "attached" });
  for (const [width, height] of PANEL_SIZES) {
    await setPanelSize(page, width, height);
    const facts = await paneFacts(page, { floating: [], header: null });
    assert.equal(facts.sideways, false, `the pane scrolls sideways at ${width}`);
    const sizes = await page.evaluate(() => {
      const d = document.querySelector("dialog.climate-set-location");
      const map = d.querySelector(".phc-outline-map").getBoundingClientRect();
      return { dialogRight: d.getBoundingClientRect().right, scrollWidth: d.scrollWidth, clientWidth: d.clientWidth,
        mapWidth: map.width, mapHeight: map.height };
    });
    assert.ok(sizes.dialogRight <= width + 0.5, `the dialog fits at ${width}`);
    assert.ok(sizes.scrollWidth <= sizes.clientWidth + 1, `the dialog scrolls sideways at ${width}`);
    assert.ok(sizes.mapHeight >= 200 && sizes.mapWidth >= 250, `the map is usable at ${width}: ` +
      JSON.stringify(sizes));
    const set = dialog.getByRole("button", { name: "Set Location", exact: true });
    await set.scrollIntoViewIfNeeded();
    const setBox = await set.boundingBox();
    assert.ok(setBox.y + setBox.height <= height + 0.5 && setBox.x + setBox.width <= width + 0.5,
      `Set Location is reachable at ${width}`);
    await dialog.locator(".phc-outline-map").scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(output, `set-location-station-${width}.png`) });
  }
  await setPanelSize(page, 1280, 800);

  step("a click places the site; a site far from the station warns, and a near one does not");
  const map = dialog.locator(".phc-outline-map-drawing");
  const mapBox = await map.boundingBox();
  await page.mouse.click(mapBox.x + mapBox.width - 80, mapBox.y + 40);
  const latitude = Number(await dialog.getByLabel("Latitude", { exact: true }).inputValue());
  assert.ok(latitude > 43, `the click filled latitude ${latitude}`);
  await dialog.locator(".climate-limit-warning").getByText(/outside the Phius limits/).waitFor();
  await page.screenshot({ path: path.join(output, "set-location-warning.png") });
  await dialog.getByLabel("Latitude", { exact: true }).fill("42.76");
  await dialog.getByLabel("Longitude", { exact: true }).fill("-73.79");
  await page.waitForFunction(() => document.querySelector(".climate-limit-warning").hidden);
  await dialog.getByRole("button", { name: "Zoom in" }).focus();
  await page.keyboard.press("Enter");
  await page.keyboard.press("Tab");
  assert.equal(await page.evaluate(() => document.activeElement.getAttribute("aria-label")), "Zoom out",
    "the zoom buttons are reached by keyboard");

  step("a thousand markers: first paint, and pan and zoom frame times");
  const example = await newPage({ viewport: { width: 1280, height: 800 } });
  await example.goto(`${ROOT}/tools/ui-preview/?example=outline_map&markers=1000`);
  await example.waitForFunction(() => window.exampleOutlineMapFirstPaintMs !== undefined);
  const coldFirstPaintMs = await example.evaluate(() => window.exampleOutlineMapFirstPaintMs);
  const timing = await example.evaluate(async () => {
    const outlineMap = PhComposerUI.get("outline_map");
    const frame = () => new Promise(resolve => requestAnimationFrame(() => resolve(performance.now())));
    const points = window.exampleOutlineMap.points;
    const holder = document.createElement("div");
    holder.style.cssText = "position:fixed;left:0;top:0;width:900px;height:600px;z-index:2000";
    document.body.appendChild(holder);
    const start = performance.now();
    const map = outlineMap({ label: "Timed", points: points });
    map.root.style.height = "600px";
    holder.appendChild(map.root);
    map.frame({ south: 24, west: -126, north: 52, east: -66 });
    const painted = await frame();
    const svg = map.svg, box = svg.getBoundingClientRect();
    const pointer = (type, x, y) => svg.dispatchEvent(new PointerEvent(type, { clientX: box.left + x,
      clientY: box.top + y, pointerId: 9, isPrimary: true, button: 0, buttons: 1, bubbles: true }));
    const frames = { pan: [], zoom: [] }, work = { pan: [], zoom: [] };
    pointer("pointerdown", 450, 300);
    let last = await frame();
    for (let i = 1; i <= 60; i += 1) {
      const before = performance.now();
      pointer("pointermove", 450 + i * 4, 300 + i * 2);
      work.pan.push(performance.now() - before);
      const now = await frame();
      frames.pan.push(now - last);
      last = now;
    }
    pointer("pointerup", 690, 420);
    last = await frame();
    for (let i = 0; i < 30; i += 1) {
      const before = performance.now();
      svg.dispatchEvent(new WheelEvent("wheel", { clientX: box.left + 450, clientY: box.top + 300,
        deltaY: i < 15 ? -60 : 60, bubbles: true, cancelable: true }));
      work.zoom.push(performance.now() - before);
      const now = await frame();
      frames.zoom.push(now - last);
      last = now;
    }
    const summary = list => { const sorted = list.slice().sort((a, b) => a - b);
      return { mean: list.reduce((a, b) => a + b, 0) / list.length, p95: sorted[Math.floor(sorted.length * 0.95)],
        max: sorted[sorted.length - 1] }; };
    return { markers: points.length, warmFirstPaintMs: painted - start, panFrameMs: summary(frames.pan),
      zoomFrameMs: summary(frames.zoom), panScriptMs: summary(work.pan), zoomScriptMs: summary(work.zoom),
      userAgent: navigator.userAgent };
  });
  timing.coldFirstPaintMs = coldFirstPaintMs;
  fs.writeFileSync(path.join(output, "map-timing.json"), JSON.stringify(timing, null, 2));
  console.log(`map timing: ${JSON.stringify(timing)}`);
  assert.equal(timing.markers, 1000);
  await example.screenshot({ path: path.join(output, "example-1000.png") });
});
