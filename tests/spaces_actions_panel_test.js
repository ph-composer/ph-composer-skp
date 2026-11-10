"use strict";

/* The Spaces view's row actions, finding markers, open row and weighting factor filter. */

var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixture = require("./support/spaces_fixture");

function page() {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "features/zones/overview", "features/zones/faces_view",
    "features/spaces/view"]);
  var p = { context: context, panel: modules.panel, modules: modules, sent: sent };
  p.section = function () { return context.document.querySelector("[data-section='ph_composer.overview']"); };
  p.receive = function (state) { p.panel.receive({ type: "panel.snapshot", payload: state }); };
  p.action = function (label) {
    return p.section().querySelectorAll("[data-row-action]").filter(function (node) {
      return node.getAttribute("aria-label") === label;
    })[0];
  };
  p.click = function (node) { node.listeners.click({ preventDefault: function () {} }); };
  p.result = function (message, outcome) {
    var types = { "view.invoke": "view.result", "query.invoke": "query.result" };
    p.panel.receive({ type: types[message.type] || "action.result",
      payload: { request_id: message.payload.request_id, session: "session-a", outcome: outcome } });
  };
  return p;
}

function snapshot(change, editPath) {
  var state = {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: editPath || [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: {
      decimal: ".", locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: fixture.section() }
    }
  };
  if (change) change(state.sections["ph_composer.spaces.spaces"].value);
  return state;
}

function expandAll(p) {
  fixture.expandAll(p.section());
}

function last(p) { return p.sent[p.sent.length - 1]; }

test("Locate selects and frames one row through the view command, with the issuing session", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.action("Locate Living"));
  var message = last(p);
  assert.strictEqual(message.type, "view.invoke");
  assert.strictEqual(message.payload.name, "ph_composer.spaces.locate");
  assert.strictEqual(message.payload.session, "session-a");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(message.payload.params)),
    { reference: { space_id: "spc_101", entity_path: [100, 101] } });
});

test("the open row follows the snapshot's edit path, offering Close where it is open", function () {
  var p = page();
  p.receive(snapshot(null, [100, 101]));
  var living = p.section().querySelectorAll("[data-row-key]").filter(function (node) {
    return node.getAttribute("data-row-key") === JSON.stringify(["Space", [100, 101]]);
  })[0];
  assert.ok(living.classList.contains("host-selected"));
  assert.ok(p.action("Close Living"));
  assert.ok(p.action("Open Bath"));
  p.click(p.action("Close Living"));
  assert.strictEqual(last(p).payload.name, "ph_composer.spaces.context.close");
});

test("Enter unprotects a protected Volume, then opens it once that has completed", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  p.click(p.section().querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("aria-label") === "Enter Volume 1";
  })[0]);
  var unprotect = last(p);
  assert.strictEqual(unprotect.payload.name, "ph_composer.spaces.volumes.unprotect");
  assert.strictEqual(unprotect.payload.expected_revision, 4, "a stale row refuses on the host");
  p.result(unprotect, { status: "completed", effect: "committed", value: { volume_id: "svl_100_101_1" } });
  p.receive(snapshot());
  var open = last(p);
  assert.strictEqual(open.payload.name, "ph_composer.spaces.context.open");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(open.payload.params)),
    { reference: { volume_id: "svl_100_101_1", entity_path: [100, 101, 1] } });
});

test("Remove confirms that the floors stay, beside a Delete that is unchanged, and Cancel sends nothing", function () {
  var p = page();
  p.receive(snapshot());
  assert.ok(p.action("Delete Bath"));
  p.click(p.action("Remove Bath, keep its floors"));
  var dialog = p.context.document.querySelector("dialog");
  assert.strictEqual(dialog.querySelector("h2").textContent, "Remove Space?");
  assert.strictEqual(dialog.querySelector("p").textContent, "Bath and its Volumes will be removed. Their floor Faces " +
    "stay where they are as plain geometry. One Undo brings the Space back.");
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Cancel"; })[0]);
  assert.strictEqual(p.sent.length, 0);
  p.click(p.action("Remove Bath, keep its floors"));
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Remove"; })[0]);
  assert.strictEqual(last(p).payload.name, "ph_composer.spaces.remove");
  assert.strictEqual(last(p).payload.expected_revision, 4);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(last(p).payload.params)),
    { space: { space_id: "spc_102", entity_path: [100, 102] } });
});

test("Delete confirms in the shared dialog, naming what goes, and Cancel sends nothing", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.action("Delete Bath"));
  var dialog = p.context.document.querySelector("dialog");
  assert.strictEqual(dialog.querySelector("h2").textContent, "Delete Space?");
  assert.strictEqual(dialog.querySelector("p").textContent,
    "Bath, its Volumes and their Floor Segments will be erased.");
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Cancel"; })[0]);
  assert.strictEqual(p.sent.length, 0);
  p.click(p.action("Delete Bath"));
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Delete"; })[0]);
  assert.strictEqual(last(p).payload.name, "ph_composer.spaces.delete");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(last(p).payload.params)),
    { space: { space_id: "spc_102", entity_path: [100, 102] } });
});

test("Move to Zone offers the other Zones and sends the chosen one", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.action("Move Living to Zone"));
  var dialog = p.context.document.querySelector("dialog");
  var select = dialog.querySelector("select");
  assert.deepStrictEqual(select.querySelectorAll("option").map(function (node) { return node.textContent; }),
    ["Zone B"]);
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Move"; })[0]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(last(p).payload.params)), {
    space: { space_id: "spc_101", entity_path: [100, 101] }, zone: { zone_id: "zon_b", zone_path: [200] } });
});

test("a finding's repair is the row's action; a refusal says why", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    section.spaces[0].volumes[0].moved = true;
    section.spaces[0].volumes[0].findings = [{ code: "space.volume_moved", blocks_export: false,
      message: "Volume 1 moved inside its Space. Restore its position.", repair: "restore_position" }];
  }));
  expandAll(p);
  p.click(p.section().querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("aria-label") === "Restore the position of Volume 1";
  })[0]);
  var restore = last(p);
  assert.strictEqual(restore.payload.name, "ph_composer.spaces.volumes.restore_position");
  p.result(restore, { status: "refused", code: "target.changed", effect: "none",
    message: "The Volume changed after it was read. Nothing was written." });
  assert.match(p.panel.state.ui.notice.message, /Nothing was written/);
});

test("a row's findings are its marker, those that block export named first", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    section.spaces[1].volumes[0].findings = [
      { code: "space.volume_unprotected", blocks_export: false, message: "Volume 1 is not protected." },
      { code: "space.height_missing", blocks_export: true, message: "Volume 1 needs a height." }];
  }));
  expandAll(p);
  var markers = p.section().querySelectorAll(".phc-row-marker").filter(function (node) { return !node.hidden; })
    .map(function (node) { return node.getAttribute("aria-label"); });
  assert.ok(markers.indexOf("Blocks export. Volume 1 needs a height. Volume 1 is not protected.") >= 0, markers);
});

test("the weighting factor column filters by band and its toggle colours the Model by it", function () {
  var p = page(), state = snapshot();
  state.sections["ph_composer.colour_by.legend"] = { status: "completed", value: { mode: null, rows: [], modes: [
    { name: "ph_composer.spaces.by_weighting_factor", label: "Weighting factor", group: null }] } };
  p.receive(state);
  expandAll(p);
  assert.ok(p.section().querySelectorAll("button").some(function (node) {
    return node.getAttribute("aria-label") === "Colour by Weighting factor";
  }), "the column header carries the mode's toggle");
  var menu = p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Weighting factor column menu";
  })[0];
  p.click(menu);
  var boxes = menu.parentNode.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; });
  assert.deepStrictEqual(boxes.map(function (box) { return box.parentNode.children[1].textContent; }),
    ["0", "1"]);
  boxes[1].checked = false; boxes[1].listeners.change({});
  var shown = p.section().querySelectorAll("[data-row-key]").filter(function (node) { return !node.hidden; })
    .map(function (node) { return JSON.parse(node.getAttribute("data-row-key"))[0]; });
  assert.deepStrictEqual(shown, ["Zone", "Space", "Volume", "Segment"], "Zone A's Hall, Volume 2 and its Segment");
  var filter = p.sent.filter(function (message) { return message.payload.name === "ph_composer.colour_by.filter"; });
  assert.deepStrictEqual(JSON.parse(JSON.stringify(filter[filter.length - 1].payload.params)),
    { paths: [[100, 103, 2, 1]] });
});

/* ---------------------------------------------------------------- review (PR #152) */

test("a confirmation sends the revision it was opened at, not a later one", function () {
  var p = page();
  p.receive(snapshot());
  p.click(p.action("Delete Bath"));
  var later = snapshot();
  later.revision = 5;
  p.receive(later);
  var dialog = p.context.document.querySelector("dialog");
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Delete"; })[0]);
  assert.strictEqual(last(p).payload.expected_revision, 4);
});

test("a row change waits while a cell draft is held", function () {
  var p = page();
  p.receive(snapshot());
  var name = p.section().querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Living name";
  })[0];
  name.value = "Lounge"; name.listeners.input({});
  var before = p.sent.length;
  p.click(p.action("Move Living to Zone"));
  assert.strictEqual(p.sent.length, before);
  assert.strictEqual(p.context.document.querySelector("dialog"), null, "no dialog opens over the draft");
  assert.match(p.panel.state.ui.notice.message, /Finish or cancel/);
});

test("Close on a Space closes through it even while one of its Volumes is open", function () {
  var p = page();
  p.receive(snapshot(null, [100, 101, 1]));
  p.click(p.action("Close Living"));
  var first = last(p);
  assert.strictEqual(first.payload.name, "ph_composer.spaces.context.close");
  p.result(first, { status: "completed", value: { path: [100, 101] } });
  var second = last(p);
  assert.notStrictEqual(second, first, "a second close leaves the Space itself");
  assert.strictEqual(second.payload.name, "ph_composer.spaces.context.close");
  p.result(second, { status: "completed", value: { path: [100] } });
  assert.strictEqual(last(p), second, "and stops there");
});

test("a matching Space outside every Zone joins the viewport mask", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    var shed = JSON.parse(JSON.stringify(section.spaces[3]));
    shed.id = "spc_301"; shed.zone = null; shed.reference = { space_id: "spc_301", entity_path: [300] };
    shed.values.number = "301"; shed.values.name = "Shed";
    shed.volumes[0].reference = { volume_id: "svl_300_1", entity_path: [300, 1] };
    shed.volumes[0].floor_segments[0].reference = { floor_segment_id: "sfs_300_1_1", entity_path: [300, 1, 1] };
    section.spaces.push(shed);
  }));
  var menu = p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Weighting factor column menu";
  })[0];
  p.click(menu);
  var boxes = menu.parentNode.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; });
  boxes[0].checked = false; boxes[0].listeners.change({});
  var filter = p.sent.filter(function (message) { return message.payload.name === "ph_composer.colour_by.filter"; });
  var paths = JSON.parse(JSON.stringify(filter[filter.length - 1].payload.params)).paths;
  assert.ok(paths.some(function (path) { return JSON.stringify(path) === "[300,1,1]"; }), JSON.stringify(paths));
});

test("weighting factor bands keep values apart that round alike", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    section.spaces[0].volumes[0].floor_segments[0].weighting_band = "0.1234561";
    section.spaces[1].volumes[0].floor_segments[0].weighting_band = "0.1234562";
  }));
  var menu = p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Weighting factor column menu";
  })[0];
  p.click(menu);
  var labels = menu.parentNode.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; })
    .map(function (box) { return box.parentNode.children[1].textContent; });
  assert.deepStrictEqual(labels, ["0", "0.1234561", "0.1234562", "1"], "the host's bands, never re-derived");
});

test("a confirmation names a record with no name by its number and its Space", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    section.spaces[1].values.name = "";
    section.spaces[1].volumes[0].values.display_name = "";
  }));
  expandAll(p);
  p.click(p.action("Delete Space 102"));
  var dialog = p.context.document.querySelector("dialog");
  assert.strictEqual(dialog.querySelector("h2").textContent, "Delete Space?");
  assert.match(dialog.querySelector("p").textContent, /^Space 102, /);
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Cancel"; })[0]);
  p.click(p.action("Delete Volume 1 of Space 102"));
  assert.strictEqual(dialog.querySelector("h2").textContent, "Delete Space?");
  assert.match(dialog.querySelector("p").textContent, /^Volume 1 is the only Volume of Space 102, /);
});

test("a Volume's trash icon confirms, then erases it with its floor Faces through volumes.delete", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  p.click(p.action("Delete Volume 2"));
  var dialog = p.context.document.querySelector("dialog");
  assert.strictEqual(dialog.querySelector("h2").textContent, "Delete Volume?");
  assert.strictEqual(dialog.querySelector("p").textContent,
    "Volume 2 of Hall and its floor Faces will be erased. One Undo brings them back.");
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Cancel"; })[0]);
  assert.strictEqual(p.sent.length, 0);
  p.click(p.action("Delete Volume 2"));
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Delete"; })[0]);
  assert.strictEqual(last(p).payload.name, "ph_composer.spaces.volumes.delete");
  assert.strictEqual(last(p).payload.expected_revision, 4);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(last(p).payload.params)),
    { volume: { volume_id: "svl_100_103_2", entity_path: [100, 103, 2] } });
});

test("a Space's only Volume offers Delete Space instead, so the panel never empties a Space", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  p.click(p.action("Delete Volume 1"));
  var dialog = p.context.document.querySelector("dialog");
  assert.strictEqual(dialog.querySelector("h2").textContent, "Delete Space?");
  assert.strictEqual(dialog.querySelector("p").textContent, "Volume 1 is the only Volume of Living, so the Space " +
    "goes with it: Living and everything in it will be erased. One Undo brings it back.");
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Delete Space"; })[0]);
  assert.strictEqual(last(p).payload.name, "ph_composer.spaces.delete");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(last(p).payload.params)),
    { space: { space_id: "spc_101", entity_path: [100, 101] } });
});

test("only a Volume left outside the deleted one keeps the Space: one nested inside it goes with it", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    // Hall's Volume 2 nested inside its Volume 1; a sibling of Living's Volume 1 in a plain Group.
    section.spaces[2].volumes[1].reference.entity_path = [100, 103, 1, 2];
    var sibling = JSON.parse(JSON.stringify(section.spaces[2].volumes[0]));
    sibling.reference.entity_path = [100, 101, 9, 1];
    sibling.values.display_name = "Volume 9";
    section.spaces[0].volumes.push(sibling);
  }));
  expandAll(p);
  var dialog;
  p.click(p.action("Delete Volume 1"));
  dialog = p.context.document.querySelector("dialog");
  assert.strictEqual(dialog.querySelector("h2").textContent, "Delete Volume?", "Living keeps its nested sibling");
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Cancel"; })[0]);
  var hall = p.section().querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("aria-label") === "Delete Volume 1";
  })[2];
  p.click(hall);
  assert.strictEqual(dialog.querySelector("h2").textContent, "Delete Space?", "Hall's Volume 2 goes with Volume 1");
});

test("Height from solid reads the selected solid, previews, and writes only once confirmed", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  p.click(p.section().querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("aria-label") === "Height of Volume 1 from a solid";
  })[0]);
  var selected = last(p);
  assert.deepStrictEqual([selected.type, selected.payload.name],
    ["query.invoke", "ph_composer.spaces.selected_solid"]);
  p.result(selected, { status: "completed", revision: 4, value: { solid: [100, 101, 900] } });
  var preview = last(p);
  assert.strictEqual(preview.payload.name, "ph_composer.spaces.volumes.height_from_solid_preview");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(preview.payload.params.solid)), [100, 101, 900]);
  var sent = p.sent.length;
  p.result(preview, { status: "completed", revision: 4, value: { height_m: 3, solid_volume_m3: 36,
    net_floor_area_m2: 12, current_height_m: 2.5 } });
  var dialog = p.context.document.querySelector("dialog");
  assert.match(dialog.querySelector("p").textContent, /becomes 3 m\./);
  assert.strictEqual(p.sent.length, sent, "nothing is written before the confirmation");
  p.click(dialog.querySelectorAll("button").filter(function (node) { return node.textContent === "Set height"; })[0]);
  var write = last(p);
  assert.strictEqual(write.payload.name, "ph_composer.spaces.volumes.height_from_solid");
  assert.strictEqual(write.payload.expected_revision, 4);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(write.payload.params.expected_values)),
    { avg_ceiling_height_m: 2.5 });
});

test("Height from solid with no solid selected says so and writes nothing", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  p.click(p.section().querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("aria-label") === "Height of Volume 1 from a solid";
  })[0]);
  p.result(last(p), { status: "refused", code: "selection.invalid", message: "Select one closed Group." });
  assert.strictEqual(p.context.document.querySelector(".phc-floating-notice-message").textContent,
    "Select one closed Group.");
  assert.strictEqual(p.sent.filter(function (message) { return message.type === "action.invoke"; }).length, 0);
});

test("a draft begun while Height from solid reads holds the confirmation", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  p.click(p.section().querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("aria-label") === "Height of Volume 1 from a solid";
  })[0]);
  p.result(last(p), { status: "completed", revision: 4, value: { solid: [100, 101, 900] } });
  var preview = last(p);
  var height = p.section().querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Volume 1 height";
  })[0];
  if (height.listeners.focus) height.listeners.focus({ target: height });
  height.value = "abc";
  height.listeners.input({ target: height });
  p.result(preview, { status: "completed", revision: 4, value: { height_m: 3, solid_volume_m3: 36,
    net_floor_area_m2: 12, current_height_m: 2.5 } });
  var dialog = p.context.document.querySelector("dialog");
  assert.ok(!dialog || dialog.hidden, "no confirmation over the held draft");
  assert.strictEqual(p.sent.filter(function (message) {
    return message.payload && message.payload.name === "ph_composer.spaces.volumes.height_from_solid";
  }).length, 0);
});

test("a Height from solid preview that lands after leaving the Spaces view opens nothing", function () {
  var p = page();
  p.receive(snapshot());
  expandAll(p);
  p.click(p.section().querySelectorAll("[data-row-action]").filter(function (node) {
    return node.getAttribute("aria-label") === "Height of Volume 1 from a solid";
  })[0]);
  p.result(last(p), { status: "completed", revision: 4, value: { solid: [100, 101, 900] } });
  var preview = last(p);
  p.panel.showTab("library");
  p.result(preview, { status: "completed", revision: 4, value: { height_m: 3, solid_volume_m3: 36,
    net_floor_area_m2: 12, current_height_m: 2.5 } });
  var dialog = p.context.document.querySelector("dialog");
  assert.ok(!dialog || dialog.hidden, "no confirmation over another tab");
});

test("a Space whose Zone is gone offers Remove from its missing Zone", function () {
  var p = page();
  p.receive(snapshot(function (section) {
    section.spaces[0].zone = null;
    section.spaces[0].findings = [{ code: "space.zone_missing", blocks_export: true,
      message: "Space 101 Living is hosted in a Zone that is no longer in the Model.", repair: "unhost" }];
  }));
  p.click(p.action("Remove Living from its missing Zone"));
  assert.strictEqual(last(p).payload.name, "ph_composer.spaces.unhost");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(last(p).payload.params)), {
    space: { space_id: "spc_101", entity_path: [100, 101] } });
});
