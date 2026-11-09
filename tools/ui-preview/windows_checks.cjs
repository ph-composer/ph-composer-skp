"use strict";
const assert = require("assert"), fs = require("fs"), os = require("os"), path = require("path");
const { check } = require("./support/browser_evidence.cjs");
const port = process.env.UI_PREVIEW_PORT || "8765";
const directory = fs.mkdtempSync(path.join(os.tmpdir(), "phc-windows-"));
console.log("Evidence: " + directory);
check({ name: "windows", output: directory }, async ({ newPage, step }) => {
  for (const width of [1280, 420]) {
    const page = await newPage({ viewport: { width: width, height: 900 } });
    step(`convert review: ${width}px`);
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=windowsconvert`);
    const review = page.locator("dialog.phc-convert-window");
    await review.waitFor();
    assert.match(await review.textContent(), /5 rectangles become 3 Windows\./);
    assert.match(await review.textContent(), /1 Face: The Face is not a rectangle/);
    assert.strictEqual(await page.locator("[data-pane=windows]").isVisible(), true, "the review shows the Windows tab");
    assert(await page.evaluate(() => document.body.scrollWidth <= innerWidth), `no page overflow at ${width}`);
    await page.screenshot({ path: path.join(directory, `convert-review-${width}.png`), fullPage: true });
    if (width === 1280) {
      const names = review.getByRole("textbox", { name: "Name", exact: true });
      assert.strictEqual(await names.first().inputValue(), "Window 1200 x 1500");
      assert.strictEqual(await names.nth(1).isVisible(), false, "a preselected existing Type takes no name");
      await names.first().fill("W-1");
      await names.first().press("Enter");
      await review.waitFor({ state: "hidden" });
      await page.getByText("Converted to Window Type.").waitFor();
      const sent = await page.evaluate(() => previewHost.sent.filter(message => message.type === "action.invoke")
        .map(message => message.payload.params)[0]);
      assert.deepStrictEqual(sent.groups.map(group => group.name || group.type_id), ["W-1", "W-1", "wnt_a"]);
    }
    await page.close();
  }
  for (const width of [1280, 900, 420, 280]) {
    const page = await newPage({ viewport: { width: width, height: 900 } });
    step(`windows: ${width}px`);
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=windows`);
    await page.getByRole("button", { name: "Window Types", exact: true }).click();
    const pane = page.locator("[data-pane=windows]");
    await pane.getByRole("button", { name: "Edit Window Type installs" }).waitFor();
    assert.strictEqual(await pane.locator("[data-window-element]").count(), 3);
    const toolStart = await page.evaluate(() => ({ revision: previewHost.revision,
      actions: previewHost.sent.filter(message => message.type === "action.invoke").length }));
    await pane.getByRole("button", { name: "Place", exact: true }).click();
    if (width === 1280) {
      const sidebar = await pane.locator(".window-layout > .library-sidebar-root:not([hidden])").boundingBox();
      assert.ok(sidebar.x + sidebar.width <= 1280, "the library sidebar ends inside the panel");
      assert.strictEqual(await pane.locator(".window-type-row > button:first-child").evaluateAll(nodes =>
        nodes.filter(node => node.scrollWidth > node.clientWidth).length), 0, "each rail name is shown whole");
    }
    if (width === 900) await pane.getByRole("button", { name: "Expand Window Types sidebar" }).waitFor();
    assert.strictEqual(await pane.locator(".window-placement").isVisible(), true, "the row shows while placing");
    const anchors = pane.getByRole("dialog", { name: "Placement anchor", exact: true });
    await pane.getByRole("button", { name: "Placement anchor: Sill center", exact: true }).click();
    assert.strictEqual(await anchors.getByRole("button").count(), 10, "nine anchors and Close");
    await page.keyboard.press("Escape");
    await pane.getByRole("button", { name: "Stop placing", exact: true }).waitFor();
    await pane.getByRole("button", { name: "Placement anchor: Sill center", exact: true }).click();
    await anchors.getByRole("button", { name: "Head right", exact: true }).click();
    await pane.getByRole("button", { name: "Placement anchor: Head right", exact: true }).waitFor();
    assert.strictEqual(await page.evaluate(() => previewHost.windows.place_tool.anchor), "head_right");
    await page.screenshot({ path: path.join(directory, "placement-" + width + ".png"), fullPage: true });
    await pane.getByRole("button", { name: "Stop placing", exact: true }).click();
    await pane.getByRole("button", { name: "Stop placing", exact: true }).waitFor({ state: "hidden" });
    assert.strictEqual(await pane.locator(".window-placement").isVisible(), false, "no placement row while idle");
    await pane.getByRole("tab", { name: "Schedule", exact: true }).click();
    const schedule = pane.locator(".window-schedule");
    await schedule.getByText(/Net opaque host area/).waitFor();
    if (width <= 420) assert(await schedule.locator(".phc-table-mount").evaluate(node => {
      const frame = node.getBoundingClientRect(), name = node.querySelector("th.col-name").getBoundingClientRect();
      return node.scrollLeft > 0 && name.left >= frame.left && name.right <= frame.right;
    }), "the narrow Schedule opens on complete identities at " + width);
    assert.strictEqual(await schedule.locator("[data-row-key='[100,300]'] .col-net_area").textContent(), "—");
    assert.strictEqual(await schedule.locator("[data-row-key='type:wnt_a'] .col-count").textContent(), "3");
    await schedule.getByText("Living Zone", { exact: true }).first().waitFor();
    await schedule.getByText("Detached definition", { exact: true }).waitFor();
    await schedule.getByRole("button", { name: "Locate Window", exact: true }).first().click();
    assert.deepStrictEqual(await page.evaluate(() => previewHost.selectedUnits[0].entity_path), [100, 300]);
    const located = schedule.locator("[data-row-key='[100,300]']");
    await schedule.locator("tr.host-selected[data-row-key='[100,300]']").waitFor();
    const named = located.getByRole("textbox", { name: /name$/ });
    assert.strictEqual(await named.inputValue(), "", "an unnamed Window has an empty name");
    assert.match(await named.getAttribute("placeholder"), / 1$/);
    const named302 = schedule.locator("[data-row-key='[200,302]'] input");
    assert.strictEqual(await named302.inputValue(), "W-101");
    // A short window puts the last row out of view; selecting it in SketchUp brings it back, clear of the header.
    const fullSize = page.viewportSize();
    await page.setViewportSize({ width: fullSize.width, height: 360 });
    const farRow = schedule.locator("[data-row-key='[200,302]']");
    const farRowFrame = () => farRow.evaluate(node => {
      const box = node.getBoundingClientRect(), header = node.closest("table").querySelector("thead").getBoundingClientRect();
      let host = node.parentElement;
      while (host && !["auto", "scroll"].includes(getComputedStyle(host).overflowY)) host = host.parentElement;
      const frame = host.getBoundingClientRect();
      return { clear: box.top >= header.bottom - 1, inside: box.bottom <= frame.bottom + 1 };
    });
    await page.evaluate(() => { previewHost.selectedUnits = [{ unit_id: "wun_c", entity_path: [200, 302] }];
      previewHost.snapshot(); });
    await schedule.locator("tr.host-selected[data-row-key='[200,302]']").waitFor();
    assert.deepStrictEqual(await farRowFrame(), { clear: true, inside: true },
      "the row selected in SketchUp comes into view at " + width);
    await page.setViewportSize(fullSize);
    await schedule.getByRole("button", { name: "Reset to Type", exact: true }).first().click();
    const repair = page.getByRole("dialog", { name: "Reset to Type", exact: true });
    await repair.getByRole("button", { name: "Cancel", exact: true }).click();
    assert.deepStrictEqual(await page.evaluate(() => ({ revision: previewHost.revision,
      actions: previewHost.sent.filter(message => message.type === "action.invoke").length })), toolStart);
    await page.screenshot({ path: path.join(directory, "schedule-" + width + ".png"), fullPage: true });
    await pane.getByRole("tab", { name: "Types", exact: true }).click();
    await page.screenshot({ path: path.join(directory, "builder-" + width + ".png"), fullPage: true });
    // A full-page screenshot resizes the page, and the drawing repaints on resize: let that repaint land
    // before holding one of its elements.
    await page.evaluate(() => new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done))));
    const shape = pane.getByRole("button", { name: "Element 1 glazed", exact: true });
    await shape.waitFor({ state: "visible" });
    await shape.scrollIntoViewIfNeeded();
    const box = await shape.boundingBox();
    await shape.click({ position: { x: box.width / 2, y: box.height / 4 } });
    assert.strictEqual(await pane.locator(".window-card:not([hidden])").count(), 1);
    await pane.getByRole("button", { name: "Clear element selection" }).click();
    await pane.getByRole("button", { name: "Edit Window Type installs" }).click();
    const installs = pane.locator(".window-install-editor");
    await installs.locator(".window-install-panel").scrollIntoViewIfNeeded();
    assert.ok(await installs.getByRole("button", { name: "Save Installs", exact: true }).evaluate(node => {
      const box = node.getBoundingClientRect(), frame = node.closest(".panel-panes").getBoundingClientRect();
      return box.top >= frame.top && box.bottom <= frame.bottom;
    }), "Save stays reachable while choosing products at " + width);
    await installs.locator(".phc-heading").scrollIntoViewIfNeeded();
    await page.screenshot({ path: path.join(directory, "installs-" + width + ".png"), fullPage: true });
    const before = await page.evaluate(() => previewHost.sent.filter(message => message.type === "action.invoke").length);
    await installs.locator(".window-install-list").getByRole("button", { name: /^Insulated junction/ }).click();
    const edge = installs.locator("[data-install-element=wel_a][data-install-side=top]");
    const edgeBox = await edge.boundingBox();
    await page.mouse.click(edgeBox.x + edgeBox.width / 2, edgeBox.y + edgeBox.height / 2);
    assert.strictEqual(await installs.locator(".window-install-edge.assigned").count(), 1, "the edge is painted");
    const saveBox = await installs.getByRole("button", { name: "Save Installs", exact: true }).boundingBox();
    assert.ok(saveBox.y + saveBox.height < 800, "Save Installs is in view without scrolling at " + width);
    assert.strictEqual(await installs.evaluate(root => {
      const boxes = Array.from(root.querySelectorAll(".window-install-drawing text")).map(node => node.getBoundingClientRect());
      return boxes.filter((a, index) => boxes.slice(index + 1).some(b => a.left < b.right && b.left < a.right &&
        a.top < b.bottom && b.top < a.bottom)).length;
    }), 0, "no two drawing labels overlap at " + width);
    const gaps = await installs.locator(".window-install-drawing").evaluate(node => {
      const svg = node.querySelector("svg").getBoundingClientRect(), frame = node.getBoundingClientRect();
      return { left: svg.left - frame.left, right: frame.right - svg.right, overflow: node.scrollWidth - node.clientWidth };
    });
    if (gaps.overflow <= 0) assert.ok(Math.abs(gaps.left - gaps.right) <= 1, "the drawing is centred at " + width + ": " + JSON.stringify(gaps));
    const lit = () => installs.locator(".window-install-hover").evaluateAll(lines =>
      lines.filter(line => getComputedStyle(line).visibility === "visible").map(line => getComputedStyle(line).strokeLinecap));
    await page.mouse.move(0, 0);
    assert.deepStrictEqual(await lit(), [], "no edge is lit at rest");
    const hovered = await edge.boundingBox();
    await page.mouse.move(hovered.x + hovered.width / 2, hovered.y + hovered.height / 2);
    assert.deepStrictEqual(await lit(), ["round"], "only the edge under the pointer lights, with round ends");
    await page.keyboard.press("Escape");
    await installs.getByRole("button", { name: "Keep editing" }).click();
    assert.strictEqual(await page.evaluate(() => previewHost.sent.filter(message => message.type === "action.invoke").length), before);
    assert.strictEqual(await installs.locator("[data-install-element=wel_a][data-install-side=right]").getAttribute("aria-disabled"), "true");
    await installs.getByRole("button", { name: "Save Installs", exact: true }).click();
    await installs.waitFor({ state: "hidden" });
    assert.strictEqual(await page.evaluate(() => previewHost.sent.filter(message => message.type === "action.invoke").length), before + 1);
    await pane.getByRole("tab", { name: "U-Values", exact: true }).click();
    await pane.getByText("Window Type calculation audit", { exact: true }).waitFor();
    await page.getByRole("button", { name: "Library", exact: true }).click();
    await page.getByRole("tab", { name: "Frames", exact: true }).click();
    await page.getByRole("button", { name: "+ New Frame", exact: true }).click();
    const form = page.getByRole("dialog", { name: "New Frame", exact: true });
    await form.getByRole("textbox", { name: "Name", exact: true }).fill("Manual frame");
    await form.getByRole("button", { name: "Create", exact: true }).click();
    await form.waitFor({ state: "hidden" });
    await page.getByRole("tab", { name: "Psi-Install Types", exact: true }).click();
    await page.getByRole("button", { name: /^Default Psi-Install: / }).waitFor();
    await page.getByRole("button", { name: "Export library", exact: true }).click();
    const libraryExport = page.getByRole("dialog", { name: "Export library", exact: true });
    assert.strictEqual(await libraryExport.getByRole("combobox", { name: "Definitions to export" }).inputValue(), "all");
    await libraryExport.getByText(/^Material: /).waitFor();
    await libraryExport.getByText(/^Frame \(\d+\): source attribution is not exported$/).waitFor();
    await libraryExport.getByText(/^Window Type( \(\d+\))?: not a library record; it stays in this Model$/).waitFor();
    assert.strictEqual(/ph_composer\.|_/.test(await libraryExport.locator(".library-export-summary").innerText()), false);
    await page.screenshot({ path: path.join(directory, "library-export-" + width + ".png"), fullPage: true });
    await libraryExport.locator("button[type=submit]").click();
    await libraryExport.getByText("File writes are unavailable in this browser preview.").waitFor();
    await libraryExport.locator("button.phc-action-cancel").click();
    assert.strictEqual(await page.evaluate(() => previewHost.sent.filter(message =>
      message.type === "action.invoke").length), before + 2, "library export adds no Model action");
    assert.strictEqual(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth + 1), false);
    await page.screenshot({ path: path.join(directory, "windows-" + width + ".png"), fullPage: true });
    await page.close();
    console.log("Window screens " + width + "px: pass");
  }
  // The audit list clips its overflow, so a grid wider than the list hides the Installed column.
  // 501 and 520 sit just above the narrow breakpoint, where the wide tracks fit least.
  for (const width of [520, 501, 360]) {
    step(`U-Values audit fits at ${width}px`);
    const page = await newPage({ viewport: { width: width, height: 732 } });
    await page.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=windows`);
    await page.locator("[data-tab=windows]").click();
    const pane = page.locator("[data-pane=windows]");
    await pane.getByRole("tab", { name: "U-Values", exact: true }).click();
    await pane.getByText("Window Type calculation audit", { exact: true }).waitFor();
    const facts = await pane.locator(".window-audit-list").evaluate(list => {
      const frame = list.getBoundingClientRect();
      const rows = Array.from(list.querySelectorAll(".window-audit-columns, .window-audit-type > summary"));
      return { rows: rows.length, overflow: list.scrollWidth - list.clientWidth,
        clipped: rows.filter(row => Array.from(row.children).some(cell =>
          cell.getBoundingClientRect().right > frame.right - 1)).length };
    });
    assert.ok(facts.rows > 1, "the audit shows its heading and at least one Window Type");
    assert.strictEqual(facts.overflow, 0, `the audit grid fits its list at ${width}px`);
    assert.strictEqual(facts.clipped, 0, `no audit cell ends past the list at ${width}px`);
    await page.screenshot({ path: path.join(directory, "audit-" + width + ".png") });
    await page.close();
  }
  console.log("U-Values audit fits at 520, 501 and 360px: pass");
  step("Installs commit stays visible at minimum height");
  const minimum = await newPage({ viewport: { width: 360, height: 520 } });
  await minimum.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=windows`);
  await minimum.locator("[data-tab=windows]").click();
  await minimum.getByRole("button", { name: "Edit Window Type installs", exact: true }).click();
  await minimum.locator(".window-install-panel").scrollIntoViewIfNeeded();
  assert.ok(await minimum.getByRole("button", { name: "Save Installs", exact: true }).evaluate(node => {
    const box = node.getBoundingClientRect(), frame = node.closest(".panel-panes").getBoundingClientRect();
    return box.top >= frame.top && box.bottom <= frame.bottom;
  }), "Save stays visible while choosing products at 360 x 520");
  await minimum.mouse.move(0, 0);
  await minimum.screenshot({ path: path.join(directory, "installs-minimum-scrolled.png") });
  step("Installs drawing is centred at the panel's default width");
  const standard = await newPage({ viewport: { width: 1030, height: 855 } });
  await standard.goto(`http://127.0.0.1:${port}/tools/ui-preview/?fixture=windows`);
  await standard.locator("[data-tab=windows]").click();
  await standard.getByRole("button", { name: "Edit Window Type installs", exact: true }).click();
  const room = await standard.locator(".window-install-drawing").evaluate(node => {
    const svg = node.querySelector("svg").getBoundingClientRect(), frame = node.getBoundingClientRect();
    return { left: svg.left - frame.left, right: frame.right - svg.right, overflow: node.scrollWidth - node.clientWidth };
  });
  assert.ok(room.overflow <= 0 && Math.abs(room.left - room.right) <= 1, "centred at 1030: " + JSON.stringify(room));
  return "Evidence: " + directory;
});
