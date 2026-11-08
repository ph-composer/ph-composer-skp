"use strict";
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
function choice(id, name, live, recoverable) {
  return { id: id, values: { name: name, colour: "#268589" }, usage: { live: live || 0,
    recoverable: recoverable || 0 } };
}
function fixture() {
  return { building_segments: [choice("bsg_a", "House", 1, 2), choice("bsg_b", "Annex")],
    levels: [choice("lvl_a", "Ground", 1, 1), choice("lvl_b", "Upper")],
    default_segment_id: "bsg_a", adoption: { required: false, sources: [] } };
}
function page(data) {
  var context = { document: dom.buildDocument(""), Object: Object, Array: Array, Math: Math, setTimeout: setTimeout,
    clearTimeout: clearTimeout };
  context.window = context; dom.attachEvents(context);
  var modules = panelSource.start(context, ["features/zones/option_dialog"]), sent = [], notices = [], results = [];
  var dialog = new modules["features/zones/option_dialog"]("session-a", function (type, payload) {
    sent.push({ type: type, payload: JSON.parse(JSON.stringify(payload)) });
  }, function () { return null; }, function (message, tone) { notices.push({ message: message, tone: tone }); },
  function (collection, value) { results.push({ collection: collection, value: value }); });
  dialog.consume({ revision: 4, ui: {} }, data || fixture());
  return { context: context, dialog: dialog, sent: sent, notices: notices, results: results,
    find: function (label) { return context.document.querySelectorAll("input, button, select").filter(function (node) {
      return node.getAttribute("aria-label") === label || node.textContent === label;
    })[0]; } };
}
function type(control, text) { control.value = text; control.listeners.input({}); }
function click(node) { node.listeners.click({}); }
function outcome(p, status, message) {
  var held = p.sent[p.sent.length - 1].payload;
  p.dialog.consume({ revision: 4, ui: { actionResult: { request_id: held.request_id, session: held.session,
    outcome: { status: status, message: message, value: { replacement_ids: { lvl_a: null } } } } } }, fixture());
}

test("the same dialog manages either collection with palette/hex/usage and guarded one-message Save", function () {
  var p = page(); p.dialog.open("building_segment");
  assert.strictEqual(p.dialog.dialog.querySelector("h2").textContent, "Manage Building Segments");
  assert.strictEqual(p.dialog.list.querySelector(".phc-zone-option-usage").textContent, "1 live Zone · 2 recoverable");
  assert.strictEqual(p.dialog.list.querySelector(".phc-zone-option-palette").children.length, 8);
  type(p.find("House name"), "North House");
  type(p.find("House hex colour"), "#ffffff");
  p.dialog.dialog.listeners.keydown({ key: "Enter", target: p.find("House name"), preventDefault: function () {} });
  click(p.dialog.save);
  assert.strictEqual(p.sent.length, 1);
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.options.manage");
  assert.strictEqual(p.sent[0].payload.expected_revision, 4);
  assert.deepStrictEqual(p.sent[0].payload.params.options[0], { id: "bsg_a", name: "North House", colour: "#ffffff" });
  assert.strictEqual(p.sent[0].payload.params.expected_options[0].name, "House");
  p.dialog.cancel(); assert.ok(p.dialog.active(), "pending Cancel keeps the work surface");
  assert.strictEqual(p.dialog.dialog.closeButton.disabled, true);
  outcome(p, "completed"); assert.strictEqual(p.dialog.active(), false); assert.strictEqual(p.results.length, 1);
  assert.strictEqual(p.notices[0].tone, "success");
  p.dialog.open("level"); assert.strictEqual(p.dialog.dialog.querySelector("h2").textContent, "Manage Levels");
});

test("invalid names and colours block Save while edits remain in the draft", function () {
  var p = page(); p.dialog.open("level");
  type(p.find("Upper name"), " ground "); assert.ok(p.dialog.error.textContent.includes("Equivalent names"));
  p.dialog.submit(); assert.strictEqual(p.sent.length, 0);
  type(p.find("Upper name"), "Level 2"); type(p.find("Upper hex colour"), "red");
  assert.ok(p.dialog.error.textContent.includes("#RRGGBB"));
  type(p.find("Upper name"), ""); assert.ok(p.dialog.error.textContent.includes("Enter a name"));
  p.dialog.cancel(); assert.strictEqual(p.sent.length, 0); assert.strictEqual(p.dialog.active(), false);
});

test("Add uses temporary IDs and removing a new choice never creates a replacement source", function () {
  var p = page({ building_segments: [], levels: [], default_segment_id: null, adoption: { required: false,
    sources: [] } });
  p.dialog.open("building_segment"); assert.strictEqual(p.dialog.save.disabled, true);
  click(p.dialog.add); assert.ok(p.dialog.draft[0].id.startsWith("new:"));
  assert.strictEqual(p.dialog.defaultId, p.dialog.draft[0].id);
  click(p.dialog.add); var second = p.dialog.draft[1];
  assert.strictEqual(second.name, "Building Segment 2");
  p.dialog.removal(second, p.dialog.list.children[1]); var replacement = p.find("Replacement for Building Segment 2");
  replacement.value = ""; replacement.listeners.change({}); click(p.find("Remove"));
  assert.strictEqual(Object.keys(p.dialog.replacements).length, 0); p.dialog.submit();
    assert.strictEqual(p.sent[0].payload.params.options.length, 1);
});

test("merge retargets recoverable use and the default in one draft; removing a survivor resolves chains", function () {
  var data = fixture(); data.building_segments.push(choice("bsg_c", "Wing"));
  var p = page(data); p.dialog.open("building_segment");
  p.dialog.removal(p.dialog.draft[0], p.dialog.list.children[0]);
  var replacement = p.find("Replacement for House");
  assert.ok(!replacement.children.some(function (node) { return node.value === ""; }),
    "used/default Segment cannot clear");
  replacement.value = "bsg_b"; replacement.listeners.change({}); click(p.find("Remove"));
  assert.strictEqual(p.dialog.defaultId, "bsg_b"); assert.strictEqual(p.dialog.replacements.bsg_a, "bsg_b");
  p.dialog.removal(p.dialog.draft[0], p.dialog.list.children[0]); replacement = p.find("Replacement for Annex");
  replacement.value = "bsg_c"; replacement.listeners.change({}); click(p.find("Remove"));
  assert.strictEqual(p.dialog.replacements.bsg_a, "bsg_c"); assert.strictEqual(p.dialog.replacements.bsg_b, "bsg_c");
  p.dialog.submit(); assert.strictEqual(p.sent.length, 1);
    assert.strictEqual(p.sent[0].payload.params.default_segment_id, "bsg_c");
});

test("used Level deletion explicitly clears live and recovery assignments", function () {
  var p = page(); p.dialog.open("level"); p.dialog.removal(p.dialog.draft[0], p.dialog.list.children[0]);
  var replacement = p.find("Replacement for Ground"); replacement.value = ""; replacement.listeners.change({});
    click(p.find("Remove"));
  p.dialog.submit(); assert.strictEqual(p.sent[0].payload.params.replacements.lvl_a, null);
});

test("refused Save keeps the draft, permits correction, and a revision change freezes it until Cancel", function () {
  var p = page(); p.dialog.open("level"); type(p.find("Upper name"), "Roof"); p.dialog.submit();
  outcome(p, "refused", "Locked recovery reference."); assert.ok(p.dialog.active());
  assert.strictEqual(p.find("Upper name").value, "Roof"); assert.ok(p.dialog.error.textContent.includes("Locked"));
  type(p.find("Upper name"), "Attic"); assert.strictEqual(p.dialog.save.disabled, false);
  p.dialog.consume({ revision: 5, ui: {} }, fixture());
  assert.strictEqual(p.dialog.save.disabled, true); assert.strictEqual(p.find("Upper name").disabled, true);
  assert.ok(p.dialog.error.textContent.includes("Model changed")); p.dialog.cancel();
    assert.strictEqual(p.dialog.active(), false);
});

function legacy() {
  var data = fixture(); data.adoption = { required: true, sources: [
    { key: "legacy:one", collection: "level", name: "Level-1", colour: "#5588BB", live: 1, recoverable: 2 },
    { key: "legacy:two", collection: "level", name: "level 1", colour: "#9977AA", live: 1, recoverable: 0 }
  ] }; return data;
}
test("adoption requires explicit normalized-collision resolution and preserves the chosen survivor colour",
  function () {
  var p = page(legacy()); p.dialog.open("level"); assert.strictEqual(p.dialog.save.disabled, true);
  var target = p.find("Adopt level 1 as"); target.value = "source:legacy:one"; target.listeners.change({});
  assert.strictEqual(p.dialog.save.disabled, false); p.dialog.submit();
  assert.strictEqual(p.sent[0].payload.name, "ph_composer.zones.options.adopt");
  var mappings = p.sent[0].payload.params.mappings;
  assert.deepStrictEqual(mappings[0], { source: "legacy:one", target_id: null, name: "Level-1", colour: "#5588BB" });
  assert.deepStrictEqual(mappings[1], { source: "legacy:two", target_id: null, name: "Level-1", colour: "#5588BB",
    target_source: "legacy:one" });
});

test("adoption can map to a local choice, rejects cycles, and Cancel does not write", function () {
  var p = page(legacy()); p.dialog.open("building_segment");
  var target = p.find("Adopt Level-1 as"); target.value = "source:legacy:two"; target.listeners.change({});
  target = p.find("Adopt level 1 as"); target.value = "source:legacy:one"; target.listeners.change({});
  assert.ok(p.dialog.error.textContent.includes("cycle")); p.dialog.submit(); assert.strictEqual(p.sent.length, 0);
  target = p.find("Adopt Level-1 as"); target.value = "lvl_a"; target.listeners.change({});
  assert.strictEqual(p.dialog.save.disabled, false);
  var params = p.dialog.adoptionParams(); assert.strictEqual(params.mappings[1].target_id, null);
  assert.strictEqual(params.mappings[1].colour, "#268589");
  p.dialog.cancel(); assert.strictEqual(p.sent.length, 0);
});

test("model switch disposal withdraws pending draft and ignores its late outcome", function () {
  var p = page(); p.dialog.open("level"); p.dialog.submit(); p.dialog.dispose();
  assert.strictEqual(p.context.document.querySelector("dialog"), null); outcome(p, "completed");
  assert.strictEqual(p.results.length, 0); assert.strictEqual(p.notices.length, 0);
});

test("valid names that match Object prototype keys remain available", function () {
  var p = page(); p.dialog.open("level");
  type(p.find("Upper name"), "constructor"); assert.strictEqual(p.dialog.save.disabled, false);
  type(p.find("Upper name"), "__proto__"); assert.strictEqual(p.dialog.save.disabled, false);
});

// A source edge stays explicit even when its eventual survivor is an existing local option.
test("adoption source merge terminating at existing choice serializes no competing target ID", function () {
  var p = page(legacy()); p.dialog.open("level");
  var target = p.find("Adopt Level-1 as"); target.value = "source:legacy:two"; target.listeners.change({});
  target = p.find("Adopt level 1 as"); target.value = "lvl_a"; target.listeners.change({});
  p.dialog.submit();
  var mappings = p.sent[0].payload.params.mappings;
  assert.strictEqual(mappings[0].target_source, "legacy:two");
  assert.strictEqual(mappings[0].target_id, null);
  assert.strictEqual(mappings[1].target_id, "lvl_a");
});

test("each collection's merge note offers what that collection allows", function () {
  function note(collection) {
    var p = page(); p.dialog.open(collection);
    click(p.find("Merge / Delete"));
    return p.dialog.list.querySelector(".phc-zone-option-help").textContent;
  }
  assert.strictEqual(note("building_segment"), "House: 1 live Zone · 2 recoverable. Choose a survivor to merge.");
  assert.strictEqual(note("level"),
    "Ground: 1 live Zone · 1 recoverable. Choose a survivor to merge, or clear the Level assignment.");
});

function chipModules() {
  var context = { document: dom.buildDocument(""), Object: Object, Array: Array, Math: Math, setTimeout: setTimeout,
    clearTimeout: clearTimeout };
  context.window = context; dom.attachEvents(context);
  return panelSource.start(context, ["features/zones/zone_options", "features/zones/option_dialog"]);
}
function luminance(hex) {
  var channels = [1, 3, 5].map(function (start) {
    var value = parseInt(hex.slice(start, start + 2), 16) / 255;
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}
function contrast(a, b) {
  var lighter = Math.max(luminance(a), luminance(b)), darker = Math.min(luminance(a), luminance(b));
  return (lighter + 0.05) / (darker + 0.05);
}
function inkOn(options, hex) {
  var node = dom.element("span");
  options.paint(node, hex);
  return node.style["--category-ink"];
}
test("a chip's text is the ink that reads best, so a mid teal never carries dark text (W-019)", function () {
  var options = chipModules()["features/zones/zone_options"];
  assert.strictEqual(inkOn(options, "#268589"), "#FFFFFF");
});
test("every colour a chip can take meets the contrast floor, and the dialog's palette sits clear of it", function () {
  var options = chipModules()["features/zones/zone_options"], steps = [0, 51, 102, 119, 136, 153, 204, 255];
  steps.forEach(function (red) { steps.forEach(function (green) { steps.forEach(function (blue) {
    var hex = "#" + [red, green, blue].map(function (value) { return (value + 256).toString(16).slice(1); }).join("");
    assert.ok(contrast(hex, inkOn(options, hex)) >= 4.3, hex);
  }); }); });
  assert.ok(options.PALETTE.length >= 8);
  options.PALETTE.forEach(function (hex) {
    assert.ok(contrast(hex, inkOn(options, hex)) >= 4.5, "palette colour " + hex + " is clear of the cut-off");
  });
});
