/* Development-only visual inventory of the real panel and its separate windows. Start make ui-preview,
   then NODE_PATH=$HOME/.cache/ph-composer-ui/node_modules node tools/ui-preview/support/visual_atlas.cjs.
   Synthetic host responses exercise presentation only; this is neither export nor native-host evidence. */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const crypto = require("node:crypto");
const os = require("node:os");
const path = require("node:path");
const { check } = require("./browser_evidence.cjs");
const { PANEL_SIZES, setPanelSize, settle, paneFacts, assertPaneFits } = require("./pane_fit.cjs");
const base = `http://127.0.0.1:${process.env.UI_PREVIEW_PORT || "8765"}`;
const output = process.env.PH_COMPOSER_PREVIEW_EVIDENCE || fs.mkdtempSync(path.join(os.tmpdir(), "phc-visual-atlas-"));
const group = process.env.PH_COMPOSER_ATLAS_GROUP || "all";
assert(["all", "matrix", "details", "separate", "key-popups", "export-states"].includes(group), "unknown PH_COMPOSER_ATLAS_GROUP");
fs.mkdirSync(output, { recursive: true });
const manifest = { schema: 1, kind: "ph-composer.visual-atlas", created_at: new Date().toISOString(),
  requested_group: group,
  preview_only_hidden: ["Example parts section", "Areas example tab"],
  represented_aliases: { "Material library-source badge comparison": "library-copy-comparison" },
  uncaptured_surfaces: ["Drawing drag affordances and every insertion/resize preview",
    "Every column menu, unit preference, tooltip, notice tone and rejected-edit permutation"],
  limitations: ["Chrome screenshots of synthetic state, not SketchUp or Chromium 88 acceptance.",
    "Viewport captures show initial scroll positions; content below or beside the viewport remains scrollable.",
    "The tab matrix shows the preview's write refusal. Export-state captures use synthetic host responses on the shipped page; no export, file write or native picker runs.",
    "Native context menus, file pickers, viewport tools, operating-system dialogs and every hover/validation permutation are excluded.",
    "Token values and support-report text are deliberately synthetic; no credential, clipboard or file operation is performed."],
  captures: [] };
const sourceHash = crypto.createHash("sha256");
const htmlRoot = path.resolve(__dirname, "../../../src/ph_composer/html");
function presentationFiles(directory, prefix = "") {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const relative = prefix + entry.name;
    return entry.isDirectory() ? presentationFiles(path.join(directory, entry.name), relative + "/") :
      /\.(?:js|css|html)$/.test(entry.name) ? [relative] : [];
  }).sort();
}
// Cover the whole shipped presentation graph, including files added during a review round.
const sourceFiles = presentationFiles(htmlRoot);
for (const file of sourceFiles) {
  sourceHash.update(file); sourceHash.update(fs.readFileSync(path.join(htmlRoot, file)));
}
const sourceDigest = sourceHash.digest("hex");
const fixtureDigest = crypto.createHash("sha256").update(fs.readFileSync(path.resolve(__dirname, "../fixtures.js"))).digest("hex");
if (process.env.PH_COMPOSER_ATLAS_APPEND === "1" && fs.existsSync(path.join(output, "manifest.json"))) {
  const previous = JSON.parse(fs.readFileSync(path.join(output, "manifest.json"), "utf8"));
  manifest.captures = previous.captures;
  manifest.previous_runs = (previous.previous_runs || []).concat({ created_at: previous.created_at,
    requested_group: previous.requested_group, completed: previous.completed, captures: previous.captures.length });
}
const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;",
  ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
function saveManifest() {
  manifest.coverage_groups = [...new Set(manifest.captures.map(capture => ({ rich: "matrix", dense: "matrix",
    empty: "matrix", detail: "details", separate: "separate", "key-popup": "key-popups", "synthetic-export": "export-states" })[capture.scenario]))];
  fs.writeFileSync(path.join(output, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
  const scenarios = [...new Set(manifest.captures.map(capture => capture.scenario))];
  const gallery = scenarios.map(scenario => `<section><h2>${escapeHtml(scenario)}</h2><div class="grid">` +
    manifest.captures.filter(capture => capture.scenario === scenario).map(capture => `<article><h3>${
      escapeHtml(capture.screen)}</h3><p>${escapeHtml(capture.fixture)} · ${capture.viewport.width} × ${
      capture.viewport.height}</p><a href="${encodeURIComponent(capture.file)}"><img loading="lazy" src="${
      encodeURIComponent(capture.file)}" alt="${escapeHtml(capture.screen)}"></a>${capture.note ? `<p>${
      escapeHtml(capture.note)}</p>` : ""}</article>`).join("") + "</div></section>").join("");
  fs.writeFileSync(path.join(output, "index.html"), `<!doctype html><html lang="en"><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1"><title>PH-Composer visual atlas</title>
    <style>body{margin:32px;font:14px system-ui;color:#132a2b;background:#f6f8f9}h1{font-size:26px}h2{margin-top:32px}
    h3{font-size:15px;margin:0}p,li{line-height:1.5;color:#46565e}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:20px}
    article{background:white;border:1px solid #c9d2d7;border-radius:7px;padding:16px;min-width:0}img{display:block;max-width:100%;max-height:680px;margin:auto;object-fit:contain}a{color:#075360}</style>
    <h1>PH-Composer visual atlas</h1><p>${manifest.captures.length} screenshots · ${escapeHtml(manifest.coverage_groups.join(", "))} · ${
    manifest.completed ? "Complete" : "Capture in progress"}. <a href="manifest.json">Machine-readable manifest</a>.</p>
    <p>Chrome screenshots of synthetic state. This gallery does not establish SketchUp acceptance or real export behavior.
    Preview-only Example parts and Areas are hidden. Open an image for its original dimensions.</p><ul>${
    manifest.limitations.map(item => `<li>${escapeHtml(item)}</li>`).join("")}</ul>
    <details><summary>Uncaptured permutations</summary><ul>${manifest.uncaptured_surfaces.map(item => `<li>${
    escapeHtml(item)}</li>`).join("")}</ul></details>${gallery}</html>`);
}
const routes = [
  ["overview", "Faces"], ["overview", "Spaces"], ["assemblies"],
  ["windows", "Types"], ["windows", "U-Values"], ["windows", "Schedule"],
  ["thermal_bridges", "Types"], ["thermal_bridges", "Schedule"],
  ...["Materials", "Attached zones", "Frames", "Glazings", "Psi-Install Types"].map(tab => ["library", tab]),
  ["export"]
];
const slug = text => text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

check({ name: "visual_atlas", output }, async ({ newPage, step }) => {
  const page = await newPage({ viewport: { width: 1280, height: 800 } });
  page.setDefaultTimeout(6000);
  await page.route("**/favicon.ico", route => route.fulfill({ status: 204 }));
  async function cleanPreview() {
    await page.evaluate(() => {
      const example = document.querySelector('[data-section="example.foundation.editor"]');
      if (example) example.hidden = true;
      document.querySelectorAll('[role="tab"]').forEach(node => {
        if (node.textContent.trim() === "Areas") node.hidden = true;
      });
      window.dispatchEvent(new Event("resize"));
    });
    await settle(page);
  }
  async function open(fixture, pane, tab) {
    await page.goto(`${base}/tools/ui-preview/?fixture=${fixture}`);
    await page.locator(`[data-tab="${pane}"]`).click();
    if (tab) await page.locator(`[data-pane="${pane}"]`).getByRole("tab", { name: tab, exact: true }).click();
    await cleanPreview();
  }
  async function shot(scenario, fixture, screen, options = {}) {
    // A pointer left on the previous page's control can put a tooltip across the next screenshot.
    // Intentional contextual-menu captures keep the pointer on the noninteractive title instead.
    const popup = options.popup && page.getByRole("dialog", { name: options.popup.name, exact: true });
    if (options.keepPopupHovered) {
      await popup.locator(".phc-bubble-heading strong, h2").first().hover();
      // Exercise the actual leave delay rather than photographing a menu that is already closing.
      await page.waitForTimeout(250);
    } else await page.mouse.move(0, 0);
    await settle(page);
    if (popup) {
      await popup.waitFor({ state: "visible" });
      const action = popup.getByRole("button", { name: options.popup.action, exact: true });
      await action.waitFor({ state: "visible" });
      assert.equal(await action.isEnabled(), true, `${screen}: first popup action is disabled`);
    }
    const viewport = page.viewportSize(), name = `${slug(scenario)}-${slug(screen)}-${viewport.width}x${viewport.height}.png`;
    const entry = { file: name, scenario, fixture, screen, viewport, synthetic: true,
      captured_at: new Date().toISOString(), presentation_source_sha256: sourceDigest,
      presentation_source_files: sourceFiles, preview_fixture_sha256: fixtureDigest };
    if (await page.locator(".panel-panes").count()) {
      entry.pane_fit = await paneFacts(page, { floating: [], header: null });
      assert.equal(entry.pane_fit.sideways, false, `${name}: panel pane has sideways overflow`);
    }
    entry.dialogs = await page.locator("dialog[open], [role=dialog]:visible").evaluateAll(nodes => nodes.map(node => {
      const box = node.getBoundingClientRect();
      return { name: node.getAttribute("aria-label") || node.querySelector("h2")?.textContent || "",
        x: box.x, y: box.y, width: box.width, height: box.height,
        within_viewport: box.left >= 0 && box.top >= 0 && box.right <= innerWidth + 1 && box.bottom <= innerHeight + 1 };
    }));
    if (options.note) entry.note = options.note;
    if (options.popup) entry.required_popup = options.popup;
    if (popup) {
      assert.equal(await popup.isVisible(), true, `${screen}: popup withdrew before capture`);
      const actionBox = await popup.getByRole("button", { name: options.popup.action, exact: true }).boundingBox();
      assert.ok(actionBox && actionBox.x >= 0 && actionBox.y >= 0 &&
        actionBox.x + actionBox.width <= viewport.width + 1 && actionBox.y + actionBox.height <= viewport.height + 1,
      `${screen}: first popup action is outside the viewport`);
    }
    await page.screenshot({ path: path.join(output, name) });
    const prior = manifest.captures.findIndex(capture => capture.file === name);
    if (prior < 0) manifest.captures.push(entry); else manifest.captures[prior] = entry;
    saveManifest();
  }
  async function cancel() { await page.keyboard.press("Escape"); await settle(page); }
  const pane = id => page.locator(`[data-pane="${id}"]`);

  try {
    if (group === "all" || group === "matrix") {
    for (const fixture of ["rich", "dense", "empty"]) {
      step(`wide tab inventory: ${fixture}`);
      await setPanelSize(page, ...PANEL_SIZES[0]);
      for (const [id, tab] of routes) {
        await open(fixture, id, tab);
        await shot(fixture, fixture, [id, tab].filter(Boolean).join("-"));
      }
    }
    for (const [width, height] of PANEL_SIZES.slice(1)) {
      step(`narrow tab inventory: ${width}x${height}`);
      await setPanelSize(page, width, height);
      for (const [id, tab] of routes) {
        await open("rich", id, tab); await shot("rich", "rich", [id, tab].filter(Boolean).join("-"));
      }
      for (const [id, tab] of [["overview", "Spaces"], ["assemblies"], ["windows", "Types"],
        ...routes.filter(route => route[0] === "library")]) {
        await open("dense", id, tab); await shot("dense", "dense", [id, tab].filter(Boolean).join("-"));
      }
    }
    }
    if (group === "all" || group === "details") {
    for (const [width, height] of PANEL_SIZES) {
      step(`editors and overlays: ${width}x${height}`);
      await setPanelSize(page, width, height);
      await open("rich", "assemblies");
      await page.getByRole("button", { name: "Open Wall", exact: true }).click();
      await shot("detail", "rich", "assembly-builder");
      const editor = page.locator(".assembly-editor");
      await editor.locator("[data-segment-id='seg_stud_0'].assembly-hit-target").click();
      await shot("detail", "rich", "assembly-selection");
      await editor.getByRole("button", { name: "Advanced", exact: true }).click();
      await shot("detail", "rich", "assembly-properties");
      await cancel();

      await open("rich", "windows", "Types");
      const element = pane("windows").getByRole("button", { name: "Element 1 glazed", exact: true });
      await element.scrollIntoViewIfNeeded(); await settle(page);
      const box = await element.boundingBox();
      await element.click({ position: { x: box.width / 2, y: box.height / 4 } });
      await pane("windows").locator(".window-card:not([hidden])").waitFor();
      await shot("detail", "rich", "window-selection-drawing");
      await pane("windows").locator(".window-card:not([hidden])").scrollIntoViewIfNeeded();
      await shot("detail", "rich", "window-selection-cards");
      await pane("windows").getByRole("button", { name: "Clear element selection" }).click();
      await pane("windows").getByRole("button", { name: "Edit Window Type installs" }).click();
      await page.locator(".panel-panes").evaluate(node => { node.scrollTop = 0; });
      await shot("detail", "rich", "window-installs");
      await pane("windows").locator(".window-install-list").scrollIntoViewIfNeeded();
      await shot("detail", "rich", "window-installs-products", { note: "Scrolled to the Psi-Install Types controls." });

      await open("rich", "windows", "Types");
      await pane("windows").getByRole("button", { name: "Place", exact: true }).click();
      await pane("windows").getByRole("button", { name: "Placement anchor: Sill center", exact: true }).click();
      await shot("detail", "rich", "window-placement-anchor");

      for (const [tab, label] of [["Materials", "Material"], ["Attached zones", "Attached zone"],
        ["Frames", "Frame"], ["Glazings", "Glazing"], ["Psi-Install Types", "Psi-Install Type"]]) {
        await open("rich", "library", tab);
        await pane("library").getByRole("button", { name: `+ New ${label}`, exact: true }).click();
        await page.locator("dialog[open]").waitFor();
        await shot("detail", "rich", `new-${label}`);
      }
      await open("rich", "library", "Materials");
      await pane("library").getByRole("button", { name: "Duplicate Mineral wool", exact: true }).click();
      await shot("detail", "rich", "duplicate-material"); await cancel();
      await pane("library").getByRole("button", { name: "Delete Mineral wool", exact: true }).click();
      await shot("detail", "rich", "replace-delete-material"); await cancel();
      await pane("library").getByRole("button", { name: "Delete Wood", exact: true }).click();
      await shot("detail", "rich", "delete-unused-material"); await cancel();
      await pane("library").locator("[data-material-use-count]").first().click();
      await shot("detail", "rich", "material-uses"); await cancel();
      const colorTrigger = pane("library").getByRole("button", { name: "Color for Mineral wool: #fff2cc", exact: true });
      await colorTrigger.scrollIntoViewIfNeeded(); await settle(page); await settle(page);
      await colorTrigger.click();
      await shot("detail", "rich", "material-color", {
        popup: { name: "Color for Mineral wool", action: "White #ffffff" } }); await cancel();
      await pane("library").getByRole("button", { name: "Export library", exact: true }).click();
      await shot("detail", "rich", "export-library"); await cancel();
      const sidebar = pane("library").getByRole("tabpanel", { name: "Materials", exact: true }).locator(".library-sidebar-root");
      if (width < 900) await sidebar.getByRole("button", { name: "Material Library", exact: true }).click();
      await sidebar.getByRole("button", { name: "Library setup…", exact: true }).click();
      await shot("detail", "rich", "library-setup"); await cancel();
      await sidebar.getByLabel("Library source", { exact: true }).selectOption("synthetic");
      const providerRow = sidebar.locator(".library-sidebar-row-button").filter({ hasText: "Synthetic fiber" });
      await providerRow.scrollIntoViewIfNeeded(); await settle(page); await providerRow.click();
      await shot("detail", "rich", "library-source-detail");

      await open("rich", "thermal_bridges", "Schedule");
      await pane("thermal_bridges").getByRole("button", { name: "1 finding for Parapet 2", exact: true }).click();
      await shot("detail", "rich", "thermal-bridge-finding");
      await open("rich", "thermal_bridges", "Types");
      await pane("thermal_bridges").getByRole("button", { name: "+ New Thermal Bridge Type", exact: true }).click();
      await shot("detail", "rich", "new-thermal-bridge-type");

      await open("rich", "overview", "Faces");
      await page.getByRole("button", { name: "Faces settings", exact: true }).click();
      await shot("detail", "rich", "faces-settings"); await cancel();
      await page.getByRole("checkbox", { name: "Check Living Zone", exact: true }).check();
      await page.getByRole("checkbox", { name: "Check Attic Zone", exact: true }).check();
      assertPaneFits(await paneFacts(page), "checked Zones in visual atlas");
      await shot("detail", "rich", "zones-selection");
      await page.locator(".phc-selection-bar:not([hidden])").scrollIntoViewIfNeeded();
      await shot("detail", "rich", "zones-selection-controls", { note: "Scrolled to the checked-Zone controls when docked below the table." });
      await open("zoneoptions", "overview", "Faces");
      const segmentMenu = page.getByRole("button", { name: "Building-Segment column menu", exact: true });
      // Narrow tables scroll to the header first: their scroll listener closes an already-open bubble.
      await segmentMenu.scrollIntoViewIfNeeded(); await settle(page); await segmentMenu.click();
      await page.getByRole("button", { name: "Manage Building Segments…", exact: true }).click();
      await shot("detail", "zoneoptions", "managed-zone-options");
    }
    }
    if (group === "all" || group === "key-popups") {
      for (const [width, height] of PANEL_SIZES) {
        step(`key popup inventory: ${width}x${height}`);
        await setPanelSize(page, width, height);
        await page.goto(`${base}/tools/ui-preview/?fixture=spacescreate`);
        await page.locator("dialog.phc-create-space[open]").waitFor(); await cleanPreview();
        await shot("key-popup", "spacescreate", "space-create-review");
        await open("spaces", "overview", "Spaces");
        for (const [label, screen] of [["Move Living to another Zone", "space-move"], ["Delete Living", "space-delete"]]) {
          await page.getByRole("button", { name: label, exact: true }).click();
          await shot("key-popup", "spaces", screen); await cancel();
        }
        await page.getByRole("button", { name: "Expand all", exact: true }).click();
        for (const [label, screen] of [["Height of Volume 1 from a solid", "space-height-from-solid"],
          ["Remove Volume 1", "space-remove-volume"]]) {
          await page.getByRole("button", { name: label, exact: true }).first().click();
          await page.locator("dialog[open]").waitFor(); await shot("key-popup", "spaces", screen); await cancel();
        }
        await page.getByRole("button", { name: "Table options", exact: true }).click();
        await shot("key-popup", "spaces", "spaces-table-options");

        await open("rich", "overview", "Faces");
        await page.getByRole("combobox", { name: "Wall 1 boundary", exact: true }).first().selectOption("AttachedZone");
        await page.getByRole("dialog", { name: "Attached zone", exact: true }).waitFor();
        await shot("key-popup", "rich", "face-attached-zone-assignment");

        await open("rich", "windows", "Schedule");
        for (const [label, screen] of [["Reset to Type", "window-reset"], ["Remove Window", "window-remove"],
          ["Swap Window Type", "window-swap-type"]]) {
          await pane("windows").getByRole("button", { name: label, exact: true }).first().click();
          await shot("key-popup", "rich", screen); await cancel();
        }
        await open("rich", "windows", "U-Values");
        await pane("windows").locator(".window-audit-type > summary").first().click();
        await pane("windows").locator(".window-audit-type details > summary").first().click();
        await shot("key-popup", "rich", "window-audit-expanded");
        await open("rich", "windows", "Types");
        await pane("windows").getByRole("button", { name: "More Window Type actions", exact: true }).click();
        await page.getByRole("button", { name: "Delete Window Type", exact: true }).click();
        await shot("key-popup", "rich", "window-type-delete");

        await open("rich", "windows", "Types");
        await pane("windows").getByRole("button", { name: "Edit Window Type installs", exact: true }).click();
        const installs = pane("windows").locator(".window-install-editor");
        await installs.getByRole("button", { name: "Copy to other Window Types", exact: true }).click();
        await installs.locator(".window-install-copy").scrollIntoViewIfNeeded();
        await shot("key-popup", "rich", "window-installs-copy");
        await installs.locator(".window-install-list").getByRole("button", { name: /^Insulated junction/ }).click();
        await installs.getByRole("button", { name: "Apply to perimeter edges", exact: true }).click();
        await installs.getByRole("button", { name: "Cancel Installs", exact: true }).click();
        await shot("key-popup", "rich", "window-installs-discard");

        await open("builder", "assemblies");
        await page.getByRole("button", { name: "Open Wall", exact: true }).click();
        const assembly = page.locator(".assembly-editor");
        await assembly.locator(".assembly-hit-target[data-segment-id='seg_wool_0']").click();
        await assembly.getByRole("button", { name: "Segment properties", exact: true }).click();
        await shot("key-popup", "builder", "assembly-segment-properties"); await cancel();
        await assembly.getByRole("button", { name: "Delete segment", exact: true }).click();
        await shot("key-popup", "builder", "assembly-segment-removal");
        await cancel();
        const label = assembly.locator("[data-layer-thickness='lyr_board_0']");
        await label.scrollIntoViewIfNeeded(); await settle(page); await settle(page); await label.hover();
        const layerTrigger = assembly.locator("[data-layer-tools-trigger='lyr_board_0']");
        // The gear protrudes beyond its dimension row. Finish its own scroll before opening;
        // scrolling only the label leaves a deferred stage scroll that legitimately closes bubbles.
        await layerTrigger.scrollIntoViewIfNeeded(); await settle(page); await settle(page);
        await layerTrigger.click();
        await shot("key-popup", "builder", "assembly-layer-tools", {
          popup: { name: "Layer 1 tools", action: "Add outside" }, keepPopupHovered: true,
          note: "Pointer rests on the popup title; the named popup and first action are required after its leave delay." });
        const layerMenu = page.getByRole("dialog", { name: "Layer 1 tools", exact: true });
        await layerMenu.getByRole("button", { name: "Delete Layer", exact: true }).click();
        await shot("key-popup", "builder", "assembly-layer-removal");
        await cancel();
        await assembly.getByRole("button", { name: "Layer 2 thickness", exact: true }).click();
        const thickness = assembly.getByRole("textbox", { name: "Layer 2 thickness", exact: true });
        await shot("key-popup", "builder", "assembly-inline-dimension");
        await thickness.fill("invalid"); await thickness.press("Enter");
        await shot("key-popup", "builder", "assembly-inline-dimension-invalid");

        await open("copylinks", "library", "Materials");
        const library = pane("library").getByRole("tabpanel", { name: "Materials", exact: true });
        const sidebar = library.locator(".library-sidebar-root");
        if (width < 900) await sidebar.getByRole("button", { name: "Material Library", exact: true }).click();
        await sidebar.getByLabel("Library source", { exact: true }).selectOption("synthetic");
        const row = sidebar.locator(".library-sidebar-row-button").filter({ hasText: "Mineral wool" });
        await row.scrollIntoViewIfNeeded(); await settle(page); await row.click();
        await sidebar.getByRole("dialog", { name: "Mineral wool", exact: true })
          .getByRole("button", { name: "Add to file", exact: true }).click();
        const comparison = page.locator("dialog[open] .library-source-comparison");
        for (const destination of ["https://example.com/local.pdf", "https://example.com/revised.pdf"]) {
          const rendered = comparison.getByText(destination, { exact: false });
          await rendered.waitFor({ state: "visible" });
          assert.ok((await comparison.innerText()).includes(destination), "comparison shows the full datasheet destination");
          const box = await rendered.boundingBox();
          assert.ok(box && box.x >= 0 && box.y >= 0 && box.x + box.width <= width + 1 &&
            box.y + box.height <= height + 1, "both datasheet destinations fit the captured viewport");
        }
        await shot("key-popup", "copylinks", "library-copy-comparison", {
          note: "Distinct synthetic local and proposed datasheet destinations are shown in full. No link or file action is invoked." });
        await open("rich", "library", "Psi-Install Types");
        for (const [label, screen] of [[/^Default Psi-Install:/, "default-psi-install"],
          [/^Default install depth:/, "default-install-depth"]]) {
          const trigger = pane("library").getByRole("button", { name: label });
          await trigger.scrollIntoViewIfNeeded(); await settle(page); await trigger.click();
          await shot("key-popup", "rich", screen); await cancel();
        }
      }
    }

    if (group === "all" || group === "separate") {
    const offered = ["read", "view", "model_write", "setup", "export", "capture"];
    const token = { id: "atlas-token", label: "Design review agent", capabilities: offered,
      created_at: "2026-11-01T12:00:00Z", model_name: "Reference.skp",
      last_call: { at: "2026-11-04T12:00:00Z", status: "completed" } };
    const receive = (module, type, payload) => page.evaluate(({ module, type, payload }) => {
      PhComposerUI.get(module).receive({ type, payload });
    }, { module, type, payload });
    for (const [width, height] of PANEL_SIZES) {
      step(`separate windows: ${width}x${height}`);
      await setPanelSize(page, width, height);
      await page.goto(`${base}/src/ph_composer/html/agent_access/index.html`);
      await receive("agent_access/page", "access.state", { state: "readable", tokens: [token,
        { ...token, id: "atlas-revoked", label: "Previous agent", revoked_at: "2026-11-02T12:00:00Z" }],
      offered, server: { state: "listening", port: 52761 }, model: { key: "atlas", name: "Reference.skp" } });
      await shot("separate", "synthetic-receive", "agent-access-populated");
      await page.getByRole("button", { name: "New token", exact: true }).click();
      await shot("separate", "synthetic-receive", "agent-access-new"); await cancel();
      await page.getByRole("button", { name: "Revoke Design review agent", exact: true }).click();
      await shot("separate", "synthetic-receive", "agent-access-revoke"); await cancel();
      await receive("agent_access/page", "access.issued", { token: "SYNTHETIC-ATLAS-TOKEN-NOT-A-CREDENTIAL", row: token,
        clients: [{ client: "Codex", forms: [{ title: "Environment variable setup", text: "Synthetic setup preview only" }],
          check: "your client's connection check" }] });
      await shot("separate", "synthetic-receive", "agent-access-issued"); await cancel();
      await receive("agent_access/page", "access.state", { state: "unreadable", tokens: [], offered,
        server: { state: "unavailable", port: 52761, message: "The port is already in use." } });
      await shot("separate", "synthetic-receive", "agent-access-unavailable");

      await page.goto(`${base}/src/ph_composer/html/support/index.html`);
      await receive("support/page", "support.state", { about: { version: "development", development: true,
        host: { sketchup: "2026", platform: "macOS", supported: true }, log: { writing: true } },
      incident: "ATLAS-002", retention_days: 7, resettable: ["Display units", "Table layouts", "Panel placement"],
      problems: [{ time: "2026-11-04T12:00:00Z", label: "A library request could not be completed", incident: "ATLAS-002" },
        { time: "2026-11-03T10:30:00Z", label: "An edit was refused because the Model changed", incident: "ATLAS-001" }] });
      await shot("separate", "synthetic-receive", "support-populated");
      await page.getByRole("button", { name: "Copy diagnostics", exact: true }).click();
      await receive("support/page", "support.capture", { purpose: "copy", capture_id: "atlas-capture",
        captured_at: "2026-11-04T12:00:00Z", text: "PH-Composer synthetic support report\n\nBuild: development\nHost: SketchUp 2026 on macOS\n\nATLAS-002 Library request failed\nATLAS-001 Edit refused\n\nNo real diagnostics or project data." });
      await shot("separate", "synthetic-receive", "support-report-preview"); await cancel();
      await page.getByRole("button", { name: "Report a problem…", exact: true }).click();
      await shot("separate", "synthetic-receive", "support-public-issue-confirm"); await cancel();
      for (const [action, screen] of [["Reopen panel…", "reopen"], ["Reset display preferences…", "reset"],
        ["Clear diagnostic history…", "clear-history"]]) {
        await page.getByRole("button", { name: "More actions", exact: true }).click();
        await page.getByRole("button", { name: action, exact: true }).click();
        await shot("separate", "synthetic-receive", `support-${screen}-confirm`); await cancel();
      }
    }
    }
    if (group === "all" || group === "export-states") {
      await page.addInitScript(() => {
        window.visualAtlasSent = [];
        window.sketchup = { ph_composer_message: message => window.visualAtlasSent.push(JSON.parse(message)) };
      });
      const snapshot = { product: "PH-Composer", version: "0.1.0-dev", session: "atlas-export", revision: 1,
        file_name: "Synthetic Atlas.skp", edit_path: [], sections: {}, preferences: { unit_system: "SI",
          dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } };
      const deliver = (type, payload) => page.evaluate(({ type, payload }) => {
        PhComposerUI.get("panel").receive({ type, payload });
      }, { type, payload });
      const requestOf = type => page.evaluate(type => window.visualAtlasSent.filter(message => message.type === type).slice(-1)[0], type);
      const completed = value => ({ status: "completed", value });
      const reply = async (type, outcome) => {
        const request = await requestOf(type); assert(request, `shipped panel requested ${type}`);
        await deliver("export.result", { session: snapshot.session, request_id: request.payload.request_id, outcome });
      };
      const findings = [1, 2, 3].map(number => ({ code: "construction.missing", section: "ph_composer.zones.faces",
        blocks_export: true, object_id: `fac_c3d5e3f176e${number}`,
        message: `Face fac_c3d5e3f176e${number} needs an authored Assembly.`,
        locate: { name: "ph_composer.zones.faces.locate", params: { faces: [{ entity_path: [number] }] } } }));
      const dense = [{ code: "zone.none", section: "ph_composer.zones.export.zones", object_id: null,
        message: "Make at least one Zone before exporting.", blocks_export: true }].concat(Array.from({ length: 20 },
        (_, index) => ({ code: "material.thermal_mass_defaulted", section: "ph_composer.assemblies.export.constructions",
          object_id: `mat_Atlas${String(index).padStart(7, "0")}`, blocks_export: false,
          message: `Missing thermal mass properties use 600 kg/m3 density and 1000 J/kgK specific heat for Material "Synthetic material ${index + 1}".` })));
      const openExport = async (rows, latest = null) => {
        await page.goto(`${base}/src/ph_composer/html/index.html`);
        await deliver("panel.snapshot", snapshot);
        await page.locator("[data-tab=export]").click();
        await reply("export.preflight", completed({ findings: rows, repairs: [] }));
        await reply("export.latest", completed(latest));
      };
      const exportShot = screen => shot("synthetic-export", "synthetic-host-responses", screen,
        { note: "Synthetic host responses on the shipped page; no export, file write or native picker performed." });
      for (const [width, height] of PANEL_SIZES) {
        step(`shipped Export presentation: ${width}x${height}`);
        await setPanelSize(page, width, height);
        await openExport(findings.concat({ code: "adjacency.stale", section: "ph_composer.zones", blocks_export: false,
          message: "Adjacency was solved before the last edit." }));
        await exportShot("export-blocked-grouped");
        await openExport(dense); await exportShot("export-dense-advisories");
        const disclosure = page.locator("details > summary").filter({ hasText: "Worth checking" });
        if (await disclosure.count()) { await disclosure.click(); await exportShot("export-dense-advisories-expanded"); }
        await openExport([]); await exportShot("export-ready");
        await pane("export").getByRole("button", { name: "Choose destination…", exact: true }).click();
        await reply("export.start", completed({ task_id: "atlas-task", stage: "translating", cancellable: true, outcome: null }));
        await pane("export").getByRole("button", { name: "Cancel export", exact: true }).waitFor();
        await exportShot("export-translating");
        const terminalAdvisory = { code: "adjacency.stale", section: "ph_composer.zones", blocks_export: false,
          message: "Adjacency was solved before the last edit." };
        await openExport([], { task_id: "atlas-complete", stage: "finished", cancellable: false,
          outcome: { status: "completed", message: "HBJSON and Export report created.", value: { artifacts: [],
            location: { label: "Synthetic destination (no files written)" },
            result: { findings: [terminalAdvisory], canonical_model: { rooms: 2, faces: 12, surface_pairs: 1 } } } } });
        await pane("export").getByText("2 Rooms · 12 Faces · 1 Surface pair", { exact: true }).waitFor();
        await exportShot("export-completed-summary");
        for (const [outcome, screen] of [
          [{ status: "cancelled", code: "export.cancelled", message: "Export cancelled. Nothing was written." },
            "export-completed-then-picker-cancelled"],
          [{ status: "refused", code: "export.runtime_unavailable", message: "The export runtime is unavailable." },
            "export-completed-then-start-refused"]]) {
          await pane("export").getByRole("button", { name: "Choose destination…", exact: true }).click();
          await reply("export.start", outcome);
          const history = pane("export").locator(".phc-export-last");
          const current = pane("export").locator(".phc-export-status").filter({ hasText: outcome.message });
          await current.waitFor({ state: "visible" });
          assert.equal(await current.evaluate(node => Boolean(node.closest(".phc-export-last"))), false,
            "the new request's result is separate from the preceding terminal task");
          for (const text of ["Last export: HBJSON and Export report created.", "2 Rooms · 12 Faces · 1 Surface pair",
            "Written to Synthetic destination (no files written).", terminalAdvisory.message]) {
            await history.getByText(text, { exact: true }).waitFor({ state: "visible" });
          }
          await exportShot(screen);
        }
        await openExport([]);
        await pane("export").getByRole("button", { name: "Choose destination…", exact: true }).click();
        await reply("export.start", completed({ task_id: "atlas-refused", stage: "finished", cancellable: false,
          outcome: { status: "refused", code: "export.blocked", message: "Export not created. Resolve the blocking findings.",
            findings, value: { result: { findings }, report_html: '<!doctype html><html lang="en"><meta charset="utf-8">' +
              '<title>Synthetic export report</title><style>body{font:14px sans-serif;padding:16px;color:#132a2b}h1{font-size:22px}</style>' +
              '<h1>Export not created</h1><p>Synthetic presentation fixture. No export was performed.</p>' +
              '<p>Assign an Assembly to the three Faces, then retry.</p></html>' } } }));
        await pane("export").getByText("Last export report", { exact: true }).click();
        await page.frameLocator("iframe").getByRole("heading", { name: "Export not created", exact: true }).waitFor();
        await pane("export").locator("iframe").scrollIntoViewIfNeeded();
        await exportShot("export-refused-report-expanded");
      }
    }
    const clippedDialogs = manifest.captures.filter(capture => capture.dialogs.some(dialog => !dialog.within_viewport));
    assert.deepEqual(clippedDialogs.map(capture => capture.file), [], "every captured dialog fits its viewport");
    manifest.completed = true;
    return `Visual atlas: ${manifest.captures.length} screenshots; manifest: ${path.join(output, "manifest.json")}`;
  } finally { saveManifest(); }
});
