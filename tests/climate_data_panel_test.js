"use strict";
/* Climate Data on This Computer and the Phius climate data pane while nothing is attached: the dialog's
   rows read from `folders.list` on every open, Add Folder through the native chooser with the new name open for
   editing, Remove, a folder not found with Locate, the three empty states, and the Setup view's route to the
   dialog. The page is the shipped index.html with the real panel, so what is sent is what the host receives. */
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");

var P = "ph_composer.climate.";
var SITE_UNSET = { latitude_deg: null, longitude_deg: null, elevation_m: null, climate_zone: null,
  hours_from_utc: null, climate_zone_label: null, state: "not_set" };
var SITE_SET = { latitude_deg: 42.75, longitude_deg: -73.8, elevation_m: 84, climate_zone: 15,
  hours_from_utc: -5, climate_zone_label: "5", state: "set" };
var DESIGN_UNSET = { heating_99_c: null, cooling_1_c: null, design_temperature_source: null, state: "not_set",
  warning: null };
// Synthetic folders: no name, location or count comes from a licensed dataset.
var MAIN = { id: "climate_folder_aaaaaaaaaaaa", name: "Station Set A", display_location: "~/Climate/Set A",
  found: true, format: "phius_station_file", station_count: 1007, state_count: 51,
  files_not_read: [{ extension: ".xls", count: 1100 }, { extension: ".xlsx", count: 50 },
    { extension: ".db", count: 3 },
    { extension: "", count: 1 }], files_not_read_total: 1154, complete: true };
var OTHER_ONLY = { id: "climate_folder_bbbbbbbbbbbb", name: "Spreadsheets", display_location: "Drive/Sheets",
  found: true, format: null, station_count: 0, state_count: 0, files_not_read: [{ extension: ".xlsx", count: 12 }],
  files_not_read_total: 12, complete: true };
var MISSING = { id: "climate_folder_cccccccccccc", name: "Custom sets", display_location: "~/Climate/Custom",
  found: false, format: null, station_count: null, state_count: null, files_not_read: null,
  files_not_read_total: null, complete: null };

function completed(value) { return { status: "completed", value: value }; }

function page(options) {
  var sent = [];
  var context = {
    document: dom.buildDocument(panelSource.markup("index.html")), Intl: Intl,
    innerWidth: 1280, innerHeight: 800, setTimeout: setTimeout, clearTimeout: clearTimeout,
    sketchup: { ph_composer_message: function (message) { sent.push(JSON.parse(message)); } }
  };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["sections/shell", "sections/setup", "features/climate/section"]);
  var p = { context: context, panel: modules.panel, sent: sent, session: "session-a", revision: 1,
    site: (options && options.site) || SITE_UNSET, climate: (options && options.climate) || "none" };
  p.receive = function (type, payload) { p.panel.receive({ type: type, payload: payload }); };
  p.publish = function () {
    var sections = {};
    sections[P + "site"] = completed(p.site);
    sections[P + "design_temperatures"] = completed(DESIGN_UNSET);
    sections[P + "summary"] = completed({ site: p.site.state, design_temperatures: { state: "not_set", warning: null },
      climate: { state: p.climate, origin: p.climate === "none" ? null : "station", verdict: null, edited: false } });
    p.receive("panel.snapshot", { product: "PH-Composer", version: "0.1.0-dev", session: p.session,
      revision: p.revision, file_name: "house.skp", edit_path: [], sections: sections,
      preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".", locale: "en-US" } } });
  };
  p.publish();
  return p;
}
function body(p) { return p.context.document.body; }
function pane(p) { return p.context.document.querySelector("[data-pane='climate']"); }
function phius(p) { return pane(p).querySelector(".climate-phius"); }
function dialog(p) { return p.context.document.querySelector(".climate-data-setup"); }
function all(root, selector) { return root.querySelectorAll(selector); }
function byText(root, selector, text) {
  return all(root, selector).filter(function (node) { return node.textContent === text; })[0] || null;
}
function labelled(root, label) { return all(root, "[aria-label='" + label + "']")[0] || null; }
function click(node) { node.listeners.click({ preventDefault: function () {}, currentTarget: node }); }
function key(input, name) {
  input.listeners.keydown({ key: name, preventDefault: function () {}, stopPropagation: function () {} });
}
function named(p, name) {
  return p.sent.filter(function (message) { return message.payload && message.payload.name === name; });
}
function last(p, name) { var found = named(p, name); return found[found.length - 1]; }
function answer(p, message, outcome) {
  var slot = message.type === "setup.invoke" ? "setup.result" : "query.result";
  p.receive(slot, { request_id: message.payload.request_id, session: p.session, outcome: outcome });
}
function list(p, folders, lastId) {
  answer(p, last(p, P + "folders.list"), completed({ folders: folders, last_dataset_id: lastId || null }));
}
function rows(p) { return all(dialog(p), "[data-folder-id]"); }
// The stub keeps text on the node that was given it, so a cell's text is gathered from its descendants.
function text(node) { return node.textContent + node.children.map(text).join(""); }
function notes(p) { return dialog(p).querySelector(".climate-data-notes").children; }
function cells(row) { return all(row, "td").map(text); }
function openDialog(p) {
  p.panel.showTab("climate");
  click(byText(pane(p), "button", "Climate Data on This Computer…"));
}
function selectPhius(p) {
  p.panel.showTab("climate");
  click(pane(p).querySelector("[data-card='phius']"));
}

test("the dialog lists each folder's name, location, format, counts and files not read by kind", function () {
  var p = page();
  openDialog(p);
  assert.strictEqual(dialog(p).hidden, false);
  assert.strictEqual(named(p, P + "folders.list").length, 1, "the list is read when the dialog opens");
  assert.ok(byText(dialog(p), "p", "Reading the climate data folders…"));
  list(p, [MAIN, OTHER_ONLY]);
  assert.deepStrictEqual(cells(rows(p)[0]).slice(0, 6), ["Station Set A", "~/Climate/Set A",
    "Phius monthly station files", "1,007", "51", "1,150 Excel files · 4 other"]);
  assert.deepStrictEqual(cells(rows(p)[1]).slice(0, 6), ["Spreadsheets", "Drive/Sheets", "No station files", "0", "0",
    "12 Excel files"], "a folder of other formats reads as zero stations, not as an error");
  assert.strictEqual(dialog(p).querySelector(".is-warning"), null);
  assert.ok(byText(dialog(p), "dt", "Kept on this computer"));
  assert.ok(byText(dialog(p), "dt", "Read when needed"));
  assert.ok(byText(dialog(p), "dt", "Kept in a Model"));
});

test("the dialog reads the list again on every open and offers no Rescan", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  assert.strictEqual(byText(dialog(p), "button", "Rescan"), null);
  assert.strictEqual(all(dialog(p), "button").filter(function (b) { return /rescan|refresh/i.test(b.textContent +
    (b.getAttribute("aria-label") || "")); }).length, 0);
  click(byText(dialog(p), "button", "Done"));
  assert.strictEqual(dialog(p).hidden, true);
  openDialog(p);
  assert.strictEqual(named(p, P + "folders.list").length, 2);
  assert.ok(byText(dialog(p), "p", "Reading the climate data folders…"), "the earlier rows are not shown again");
});

test("Add Folder sends the setup command and opens the new name for editing; committing renames", function () {
  var p = page();
  openDialog(p);
  list(p, []);
  assert.ok(byText(dialog(p), "p", "No climate data folder is set up on this computer."));
  click(byText(dialog(p), "button", "Add Folder…"));
  var add = last(p, P + "folders.add");
  assert.strictEqual(add.type, "setup.invoke");
  assert.deepStrictEqual(add.payload.params, {});
  assert.strictEqual(dialog(p).querySelector(".climate-data-status").textContent,
    "Choose the folder in the window that opened…");
  var added = Object.assign({}, MAIN, { name: "Set A" });
  answer(p, add, completed(added));
  var input = labelled(dialog(p), "Dataset name");
  assert.ok(input, "the new row's name is open for editing");
  assert.strictEqual(input.value, "Set A", "prefilled from the folder");
  input.value = "Station Set A";
  key(input, "Enter");
  var rename = last(p, P + "folders.rename");
  assert.deepStrictEqual(rename.payload.params, { id: MAIN.id, name: "Station Set A" });
  answer(p, rename, completed(MAIN));
  assert.strictEqual(labelled(dialog(p), "Dataset name"), null);
  assert.strictEqual(cells(rows(p)[0])[0], "Station Set A");
});

test("a name left unchanged, blank or put back with Escape sends nothing", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(labelled(dialog(p), "Rename Station Set A"));
  var input = labelled(dialog(p), "Dataset name");
  input.value = "Changed";
  key(input, "Escape");
  assert.strictEqual(named(p, P + "folders.rename").length, 0);
  assert.strictEqual(dialog(p).hidden, false, "Escape in the name closes only the edit");
  assert.strictEqual(cells(rows(p)[0])[0], "Station Set A");
  click(labelled(dialog(p), "Rename Station Set A"));
  input = labelled(dialog(p), "Dataset name");
  input.value = "  ";
  key(input, "Enter");
  assert.strictEqual(named(p, P + "folders.rename").length, 0);
  assert.strictEqual(input.getAttribute("aria-invalid"), "true", "a blank name keeps the field open");
  input.value = "Station Set A";
  input.listeners.blur({});
  assert.strictEqual(named(p, P + "folders.rename").length, 0, "an unchanged name applies nothing");
  assert.strictEqual(labelled(dialog(p), "Dataset name"), null);
});

test("Escape on the dialog while a name is open puts the name back and keeps the dialog", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(labelled(dialog(p), "Rename Station Set A"));
  dialog(p).listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(dialog(p).hidden, false);
  assert.strictEqual(labelled(dialog(p), "Dataset name"), null);
  dialog(p).listeners.cancel({ preventDefault: function () {} });
  assert.strictEqual(dialog(p).hidden, true, "a second Escape closes it");
});

test("a cancelled chooser changes nothing, and a refused folder says why and leaves the list", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(byText(dialog(p), "button", "Add Folder…"));
  answer(p, last(p, P + "folders.add"), { status: "cancelled", code: "approval.cancelled",
    message: "The folder was not chosen." });
  assert.strictEqual(rows(p).length, 1);
  assert.strictEqual(dialog(p).querySelector(".climate-data-status").textContent, "");
  assert.strictEqual(labelled(dialog(p), "Dataset name"), null);
  click(byText(dialog(p), "button", "Add Folder…"));
  var refusal = "That folder is, holds or sits inside the climate data folder \"Station Set A\", so its stations " +
    "would be listed twice. Nothing was written.";
  answer(p, last(p, P + "folders.add"), { status: "refused", code: "climate.folder_overlaps", message: refusal });
  assert.strictEqual(rows(p).length, 1);
  var status = dialog(p).querySelector(".climate-data-status");
  assert.strictEqual(status.textContent, refusal);
  assert.ok(status.classList.contains("is-warning"));
  assert.strictEqual(status.getAttribute("role"), "status", "said inside the dialog, above its top layer");
});

test("a folder not found shows Locate and Remove and its note; Locate repairs the row", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN, MISSING]);
  var row = rows(p)[1];
  assert.strictEqual(row.getAttribute("data-found"), "false");
  assert.deepStrictEqual(cells(row).slice(0, 6), ["Custom sets", "~/Climate/Custom", "Folder not found", "—",
    "—", "—"]);
  assert.ok(labelled(row, "Locate Custom sets"));
  assert.ok(labelled(row, "Remove Custom sets"));
  assert.strictEqual(labelled(rows(p)[0], "Locate Station Set A"), null, "a found folder offers no Locate");
  assert.ok(notes(p)[0].textContent.indexOf("Custom sets: the folder is not where " +
    "it was.") === 0);
  click(labelled(row, "Locate Custom sets"));
  var locate = last(p, P + "folders.locate");
  assert.deepStrictEqual(locate.payload.params, { id: MISSING.id });
  answer(p, locate, completed(Object.assign({}, MAIN, { id: MISSING.id, name: "Custom sets", station_count: 2,
    state_count: 1, files_not_read: [], files_not_read_total: 0 })));
  assert.strictEqual(rows(p)[1].getAttribute("data-found"), "true");
  assert.deepStrictEqual(cells(rows(p)[1]).slice(2, 6), ["Phius monthly station files", "2", "1", "—"]);
  assert.strictEqual(notes(p).length, 0);
});

test("Remove confirms naming the dataset and saying Models keep their climates", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN, MISSING]);
  click(labelled(rows(p)[1], "Remove Custom sets"));
  var confirm = all(body(p), ".phc-confirm-dialog")[0];
  assert.ok(byText(confirm, "h2", "Remove Custom sets?"));
  assert.ok(all(confirm, "p")[0].textContent.indexOf("Models keep the climates attached from it") >= 0);
  click(byText(confirm, "button", "Cancel"));
  assert.strictEqual(named(p, P + "folders.remove").length, 0);
  click(labelled(rows(p)[1], "Remove Custom sets"));
  confirm = all(body(p), ".phc-confirm-dialog")[0];
  click(byText(confirm, "button", "Remove"));
  var remove = last(p, P + "folders.remove");
  assert.deepStrictEqual(remove.payload.params, { id: MISSING.id });
  answer(p, remove, completed({ folders: [MAIN], last_dataset_id: null }));
  assert.strictEqual(rows(p).length, 1);
});

test("Done while a name is saving closes once it is answered; a refused name keeps the dialog", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(labelled(dialog(p), "Rename Station Set A"));
  var input = labelled(dialog(p), "Dataset name");
  input.value = "Renamed";
  input.listeners.blur({});
  click(byText(dialog(p), "button", "Done"));
  assert.strictEqual(dialog(p).hidden, false, "the rename is still running");
  answer(p, last(p, P + "folders.rename"), { status: "refused", code: "climate.folder_not_found",
    message: "No climate data folder with that id is set up on this computer. Nothing was written." });
  assert.strictEqual(dialog(p).hidden, false, "a refusal stays on screen");
  assert.strictEqual(cells(rows(p)[0])[0], "Station Set A");
  click(labelled(dialog(p), "Rename Station Set A"));
  input = labelled(dialog(p), "Dataset name");
  input.value = "Renamed";
  input.listeners.blur({});
  click(byText(dialog(p), "button", "Done"));
  answer(p, last(p, P + "folders.rename"), completed(Object.assign({}, MAIN, { name: "Renamed" })));
  assert.strictEqual(dialog(p).hidden, true);
});

// features/climate/folders/store.rb, SECTION_UNREADABLE
var UNREADABLE = { status: "refused", code: "climate.settings_unreadable", message: "PH-Composer's climate data " +
  "settings on this computer could not be read. They were left as stored." };

test("settings that cannot be read are said in the dialog and the pane, and Add Folder waits", function () {
  var p = page();
  openDialog(p);
  answer(p, last(p, P + "folders.list"), UNREADABLE);
  assert.ok(byText(dialog(p), "p", UNREADABLE.message));
  assert.strictEqual(byText(dialog(p), "button", "Add Folder…").disabled, true);
  click(byText(dialog(p), "button", "Done"));
  selectPhius(p);
  answer(p, last(p, P + "folders.list"), UNREADABLE);
  assert.strictEqual(phius(p).getAttribute("data-state"), "unreadable");
  assert.ok(byText(phius(p), "p", UNREADABLE.message));
  assert.strictEqual(byText(phius(p), "button", "Choose Climate Data Folder…"), null);
});

test("Locate cancelled changes nothing; Locate refused says why and keeps the row", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN, MISSING]);
  click(labelled(rows(p)[1], "Locate Custom sets"));
  answer(p, last(p, P + "folders.locate"), { status: "cancelled", code: "approval.cancelled", message: "Cancelled." });
  assert.strictEqual(rows(p)[1].getAttribute("data-found"), "false");
  assert.strictEqual(dialog(p).querySelector(".climate-data-status").textContent, "");
  click(labelled(rows(p)[1], "Locate Custom sets"));
  var refusal = "That folder is, holds or sits inside the climate data folder \"Station Set A\", so its stations " +
    "would be listed twice. Nothing was written.";
  answer(p, last(p, P + "folders.locate"), { status: "refused", code: "climate.folder_overlaps", message: refusal });
  assert.strictEqual(rows(p)[1].getAttribute("data-found"), "false");
  assert.strictEqual(dialog(p).querySelector(".climate-data-status").textContent, refusal);
});

// A real press: the dialog sees the button's mousedown before the name field loses focus.
function press(p, button) {
  dialog(p).listeners.mousedown({ target: button, preventDefault: function () {} });
}

test("pressing Add Folder while a changed name is open saves it and then adds", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(labelled(dialog(p), "Rename Station Set A"));
  labelled(dialog(p), "Dataset name").value = "Renamed";
  press(p, byText(dialog(p), "button", "Add Folder…"));
  assert.strictEqual(named(p, P + "folders.rename").length, 1, "the name is saved first");
  assert.strictEqual(named(p, P + "folders.add").length, 0, "one command at a time");
  answer(p, last(p, P + "folders.rename"), completed(Object.assign({}, MAIN, { name: "Renamed" })));
  assert.strictEqual(named(p, P + "folders.add").length, 1, "then the press does what it was for");
});

test("pressing another row's Remove while a name is open saves it and then confirms that row", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN, MISSING]);
  click(labelled(dialog(p), "Rename Station Set A"));
  labelled(dialog(p), "Dataset name").value = "Renamed";
  press(p, labelled(rows(p)[1], "Remove Custom sets"));
  assert.strictEqual(all(body(p), ".phc-confirm-dialog").length, 0);
  answer(p, last(p, P + "folders.rename"), completed(Object.assign({}, MAIN, { name: "Renamed" })));
  assert.ok(byText(all(body(p), ".phc-confirm-dialog")[0], "h2", "Remove Custom sets?"));
});

test("pressing Add Folder with the name unchanged adds at once; a refused name drops the press", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(labelled(dialog(p), "Rename Station Set A"));
  press(p, byText(dialog(p), "button", "Add Folder…"));
  assert.strictEqual(named(p, P + "folders.rename").length, 0);
  assert.strictEqual(named(p, P + "folders.add").length, 1);
  answer(p, last(p, P + "folders.add"), { status: "cancelled", code: "approval.cancelled", message: "Cancelled." });
  click(labelled(dialog(p), "Rename Station Set A"));
  labelled(dialog(p), "Dataset name").value = "Renamed";
  press(p, byText(dialog(p), "button", "Add Folder…"));
  answer(p, last(p, P + "folders.rename"), { status: "refused", code: "climate.folder_not_found",
    message: "No climate data folder with that id is set up on this computer. Nothing was written." });
  assert.strictEqual(named(p, P + "folders.add").length, 1, "the refusal is read before anything else runs");
});

test("Done while Add Folder runs closes on its answer, and a reopened dialog shows the fresh list", function () {
  var p = page();
  openDialog(p);
  list(p, []);
  click(byText(dialog(p), "button", "Add Folder…"));
  click(byText(dialog(p), "button", "Done"));
  answer(p, last(p, P + "folders.add"), completed(MAIN));
  assert.strictEqual(dialog(p).hidden, true);
  assert.strictEqual(labelled(dialog(p), "Dataset name"), null, "no name opens in a closed dialog");
  openDialog(p);
  list(p, [MAIN, OTHER_ONLY]);
  assert.strictEqual(rows(p).length, 2);
});

test("pressing Remove on the row being renamed confirms it under its new name", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(labelled(dialog(p), "Rename Station Set A"));
  labelled(dialog(p), "Dataset name").value = "Renamed";
  press(p, labelled(rows(p)[0], "Remove Station Set A"));
  answer(p, last(p, P + "folders.rename"), completed(Object.assign({}, MAIN, { name: "Renamed" })));
  assert.ok(byText(all(body(p), ".phc-confirm-dialog")[0], "h2", "Remove Renamed?"));
});

test("another Model while Remove is confirming takes the dialog and its confirm away", function () {
  var p = page();
  openDialog(p);
  list(p, [MAIN]);
  click(labelled(rows(p)[0], "Remove Station Set A"));
  assert.strictEqual(all(body(p), ".phc-confirm-dialog").length, 1);
  p.session = "session-b"; p.publish();
  assert.strictEqual(all(body(p), ".phc-confirm-dialog").length, 0);
  assert.strictEqual(all(body(p), ".climate-data-setup").length, 0);
});

test("a folder read only in part says so below the table", function () {
  var p = page();
  openDialog(p);
  list(p, [Object.assign({}, MAIN, { complete: false })]);
  assert.ok(notes(p)[0].textContent.indexOf("part of the folder could not be read") >= 0);
});

test("with no folder the Phius pane says why none ships and Choose Climate Data Folder starts Add", function () {
  var p = page();
  selectPhius(p);
  assert.strictEqual(phius(p).getAttribute("data-state"), "loading");
  list(p, []);
  assert.strictEqual(phius(p).getAttribute("data-state"), "no_folder");
  assert.ok(byText(phius(p), "h2", "No Phius climate data on this computer"));
  assert.ok(byText(phius(p), "p", "PH-Composer does not include climate data. Phius licenses its climate files to " +
    "you, so they stay on your computer."));
  var hand = byText(phius(p), "button", "Enter Values by Hand…");
  assert.strictEqual(hand.disabled, true);
  assert.ok(labelled(phius(p), "Why Enter Values by Hand is unavailable"), "its reason sits beside it");
  click(byText(phius(p), "button", "Choose Climate Data Folder…"));
  assert.strictEqual(dialog(p).hidden, false);
  assert.strictEqual(named(p, P + "folders.add").length, 1, "the chooser opens at once");
});

test("with a folder and no site the pane asks for the site and opens Set Location", function () {
  var p = page();
  selectPhius(p);
  list(p, [MAIN]);
  assert.strictEqual(phius(p).getAttribute("data-state"), "no_site");
  assert.ok(byText(phius(p), "h2", "Set the site location first"));
  assert.strictEqual(byText(phius(p), "button", "Enter Values by Hand…").disabled, true);
  click(byText(phius(p), "button", "Set Location…"));
  assert.ok(p.context.document.querySelector(".climate-set-location"), "Set Location opens");
});

test("with a folder and a site the pane names the picker's dataset and its stations", function () {
  var p = page({ site: SITE_SET });
  selectPhius(p);
  list(p, [OTHER_ONLY, MAIN], MAIN.id);
  assert.strictEqual(phius(p).getAttribute("data-state"), "ready");
  assert.ok(byText(phius(p), "h2", "No Phius climate data in this Model"));
  assert.ok(byText(phius(p), "p", "Station Set A · 1,007 stations on this computer."), "the dataset used last");
  var choose = byText(phius(p), "button", "Choose Station…");
  assert.strictEqual(choose.disabled, false, "Choose Station opens the station picker");
  assert.strictEqual(labelled(phius(p), "Why Choose Station is unavailable"), null);
  p.receive("panel.snapshot", Object.assign({}, p.panel.state, { revision: 2 }));
  assert.strictEqual(named(p, P + "folders.list").length, 1, "a refresh while shown does not read the disk");
});

test("with no dataset used last the pane names the first found folder that holds stations", function () {
  var p = page({ site: SITE_SET });
  selectPhius(p);
  list(p, [OTHER_ONLY, MISSING, MAIN], MISSING.id);
  assert.ok(byText(phius(p), "p", "Station Set A · 1,007 stations on this computer."));
});

test("folders that cannot be found read as none, and the pane reads again when the dialog closes", function () {
  var p = page({ site: SITE_SET });
  selectPhius(p);
  list(p, [MISSING]);
  assert.strictEqual(phius(p).getAttribute("data-state"), "no_folder");
  assert.ok(byText(phius(p), "h2", "The climate data folder cannot be found"));
  click(byText(phius(p), "button", "Climate Data on This Computer…"));
  assert.strictEqual(named(p, P + "folders.add").length, 0, "Locate is in the dialog, so nothing is added");
  list(p, [MISSING]);
  click(labelled(rows(p)[0], "Locate Custom sets"));
  answer(p, last(p, P + "folders.locate"), completed(Object.assign({}, MAIN, { id: MISSING.id })));
  click(byText(dialog(p), "button", "Done"));
  assert.strictEqual(named(p, P + "folders.list").length, 3, "the pane reads the folders again");
  list(p, [Object.assign({}, MAIN, { id: MISSING.id })]);
  assert.strictEqual(phius(p).getAttribute("data-state"), "ready");
});

test("with a climate in the Model the pane reads no folders and keeps its line", function () {
  var p = page({ site: SITE_SET, climate: "complete" });
  selectPhius(p);
  assert.strictEqual(phius(p).getAttribute("data-state"), "attached");
  assert.strictEqual(named(p, P + "folders.list").length, 0);
});

test("the Setup view's button reaches the host, whose route opens the dialog on the Climate tab", function () {
  var p = page();
  p.panel.showTab("setup");
  p.receive("panel.setup", { entries: [{ name: P + "data.open", menu: "Climate",
    label: "Climate Data on This Computer…", summary: "No climate data folder" }] });
  var setupPane = p.context.document.querySelector("[data-pane='setup']");
  assert.ok(byText(setupPane, "p", "No climate data folder"));
  click(byText(setupPane, "button", "Climate Data on This Computer…"));
  assert.deepStrictEqual(p.sent[p.sent.length - 1], { type: "panel.setup_open", payload: { name: P + "data.open" } });
  p.receive("panel.navigate", { session: "session-other", owner: "ph_composer.climate",
    intent: { open: "climate_data" } });
  assert.strictEqual(p.panel.state.ui.activeTab, "setup", "a route for another Model is dropped");
  p.receive("panel.navigate", { session: p.session, owner: "ph_composer.climate", intent: { open: "climate_data" } });
  assert.strictEqual(p.panel.state.ui.activeTab, "climate");
  assert.strictEqual(dialog(p).hidden, false);
  assert.strictEqual(named(p, P + "folders.list").length, 1);
});
