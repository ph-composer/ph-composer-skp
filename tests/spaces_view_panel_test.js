"use strict";

/* The Spaces view of the Zones tab: its rows three deep under each Zone, the No Zone group,
   the read-only columns, the airflow cell states and the Zone sums, all read from the
   `spaces` snapshot section. */

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
  return p;
}

function snapshot(options) {
  return {
    product: "PH-Composer", version: "0.1.0-dev", session: "session-a", revision: 4, file_name: "house.skp",
    edit_path: [], preferences: { unit_system: "SI", dimension_formats: {}, number_format: { decimal: ".",
      locale: "en-US" }, table_views: { "ph_composer.zones": "ph_composer.spaces" } },
    sections: {
      "ph_composer.zones.overview": { status: "completed", value: { zones: fixture.zones(), make_zone: null,
        units: {} } },
      "ph_composer.spaces.spaces": { status: "completed", value: fixture.section(options) }
    }
  };
}

/* What a cell shows: an editable cell is an input, and an empty one reads as its placeholder. */
function text(td) {
  var input = td.querySelector("input");
  return input ? input.value || input.placeholder || "" : td.textContent;
}

function shown(p) {
  return p.section().querySelectorAll(".phc-zone-view").filter(function (node) { return !node.hidden; })[0];
}

/* Every row the shown table paints and shows, as [kind, Name, then the asked columns]. */
function table(p, fields) {
  var surface = shown(p);
  return surface.querySelectorAll("tr").filter(function (tr) { return tr.getAttribute("data-row-key") && !tr.hidden; })
    .map(function (tr) {
      var cells = tr.querySelectorAll("td");
      function cell(field) {
        return cells.filter(function (td) { return td.className.split(" ").indexOf("col-" + field) >= 0; })[0];
      }
      return [JSON.parse(tr.getAttribute("data-row-key"))[0], text(cell("name"))]
        .concat(fields.map(function (field) { return text(cell(field)); }));
    });
}

function expandAll(p) {
  var button = p.section().querySelectorAll("button").filter(function (node) {
    return node.textContent === "Expand all";
  })[0];
  button.listeners.click({ preventDefault: function () {} });
}

test("Spaces, Volumes and Floor Segments sit three deep under their Zone, with no Space Floor row", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  expandAll(p);
  assert.deepStrictEqual(table(p, ["number", "floor_area_m2", "weighting_factor", "weighted_area_m2"]), [
    ["Zone", "Zone A", "", "22", "", "20"],
    ["Space", "Living", "101", "12", "", "12"],
    ["Volume", "Volume 1", "", "12", "", "12"],
    ["Segment", "Segment 1", "", "12", "1", "12"],
    ["Space", "Bath", "102", "4", "", "4"],
    ["Volume", "Volume 1", "", "4", "", "4"],
    ["Segment", "Segment 1", "", "4", "1", "4"],
    ["Space", "Hall", "103", "6", "", "4"],
    ["Volume", "Volume 1", "", "4", "", "4"],
    ["Segment", "Segment 1", "", "4", "1", "4"],
    ["Volume", "Volume 2", "", "2", "", "0"],
    ["Segment", "Segment 1", "", "2", "0", "0"],
    ["Zone", "Zone B", "", "12", "", "12"],
    ["Space", "Loft", "201", "12", "", "12"],
    ["Volume", "Volume 1", "", "12", "", "12"],
    ["Segment", "Segment 1", "", "12", "1", "12"]]);
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "2 Zones · 4 Spaces");
});

test("a Space no Zone holds is listed under one group row after the Zones", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot({ outside: true }) });
  var rows = table(p, ["number"]);
  assert.deepStrictEqual(rows.slice(-2), [["NoZone", "Outside every Zone", ""], ["Space", "Shed", "301"]]);
});

test("height and airflow cells read what the row sets, muted where it does not", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  expandAll(p);
  var rows = table(p, ["height_m", "net_volume_m3", "v_sup_m3h", "v_eta_m3h", "v_tran_m3h"]);
  assert.deepStrictEqual(rows.filter(function (row) { return row[0] !== "Volume" && row[0] !== "Segment"; }), [
    ["Zone", "Zone A", "", "59.6", "60", "40", "20"],
    ["Space", "Living", "", "30", "60", "0", "0"],
    ["Space", "Bath", "", "9.6", "0", "40", "0"],
    ["Space", "Hall", "", "20", "0", "0", "20"],
    ["Zone", "Zone B", "", "36", "—", "—", "—"],
    ["Space", "Loft", "", "36", "Zone", "Zone", "Zone"]]);
  var volumes = rows.filter(function (row) { return row[0] === "Volume"; });
  assert.deepStrictEqual(volumes.map(function (row) { return row[2]; }), ["2.5", "2.4", "2.5", "5", "3"],
    "Height shows on the Volume row, where it is set");
  var muted = shown(p).querySelectorAll("td").filter(function (td) { return td.classList.contains("is-muted"); });
  assert.ok(muted.some(function (td) { return text(td) === "Zone"; }), "an inheriting Space reads a muted Zone");
  assert.ok(muted.some(function (td) { return text(td) === "—"; }), "and its Zone a muted dash");
  assert.ok(muted.some(function (td) { return text(td) === "0"; }),
    "an unset rate beside a set one is a muted 0");
});

test("a Zone whose supply and extract differ carries no marker; one with an inheriting Space shows a dash",
  function () {
    var p = page();
    p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
    assert.strictEqual(shown(p).querySelectorAll(".phc-row-marker").filter(function (node) {
      return !node.hidden;
    }).length, 0, "Zone A sums 60 supply and 40 extract");
    var zoneB = shown(p).querySelectorAll("td").filter(function (td) {
      return td.classList.contains("col-v_sup_m3h") && text(td) === "—";
    })[0];
    assert.match(zoneB.getAttribute("data-tooltip"), /^1 Space in this Zone inherits/);
  });

test("a Floor Segment's row reads Floor in the Hierarchy column", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  expandAll(p);
  var deepest = shown(p).querySelectorAll("tr").filter(function (tr) {
    return (tr.getAttribute("data-row-key") || "").indexOf("[\"Segment\"") === 0;
  })[0];
  assert.strictEqual(deepest.querySelector(".row-target").textContent, "Floor");
});

test("Spaces list by number, read as numbers, whatever order the host reads them in", function () {
  var p = page(), state = snapshot(), spaces = state.sections["ph_composer.spaces.spaces"].value.spaces;
  // Living, Bath and Hall arrive in path order, which is the order they were drawn.
  spaces[0].values.number = "103"; spaces[1].values.number = "9"; spaces[2].values.number = "101";
  p.panel.receive({ type: "panel.snapshot", payload: state });
  expandAll(p);
  assert.deepStrictEqual(table(p, ["number"]).filter(function (row) { return row[0] === "Space"; }).slice(0, 3),
    [["Space", "Bath", "9"], ["Space", "Hall", "101"], ["Space", "Living", "103"]]);
});

test("Zone rows sort by the view's sums, and Spaces within each Zone by their own values", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var menu = p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Floor area m² column menu";
  })[0];
  menu.listeners.click({ preventDefault: function () {} });
  menu.parentNode.querySelectorAll("button").filter(function (node) {
    return node.textContent === "Sort Z to A";
  })[0].listeners.click({ preventDefault: function () {} });
  assert.deepStrictEqual(table(p, ["floor_area_m2"]).filter(function (row) {
    return row[0] === "Zone" || row[0] === "Space";
  }), [["Zone", "Zone A", "22"], ["Space", "Living", "12"], ["Space", "Hall", "6"],
    ["Space", "Bath", "4"], ["Zone", "Zone B", "12"], ["Space", "Loft", "12"]]);
});

test("Building-Segment, Level and Net area factor are hidden by default and offered in Table options", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  var hidden = shown(p).querySelectorAll("th").filter(function (th) { return th.hidden; }).map(function (th) {
    return th.className.split(" ")[0];
  });
  assert.deepStrictEqual(hidden, ["col-building_segment", "col-level", "col-net_area_factor"]);
  var options = p.section().querySelectorAll("button").filter(function (node) {
    return node.getAttribute("aria-label") === "Table options";
  })[0];
  options.listeners.click({ preventDefault: function () {} });
  assert.deepStrictEqual(options.parentNode.querySelectorAll(".phc-action-menu-item").map(function (node) {
    return node.textContent;
  }), ["Building-Segment column", "Level column", "Net area factor column"]);
});

test("filtering, sorting, expansion and switching views send nothing to the Model", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  expandAll(p);
  var text = p.section().querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Filter Zones";
  })[0];
  text.value = "Hall"; text.listeners.input({});
  assert.deepStrictEqual(table(p, []).filter(function (row) { return row[0] === "Zone"; }).length, 1);
  assert.deepStrictEqual(p.sent.map(function (message) { return message.payload.name || message.type; }), []);
});

test("a filter matching a Space lists only that Space; one matching the Zone lists all its Spaces", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  expandAll(p);
  var text = p.section().querySelectorAll("input").filter(function (node) {
    return node.getAttribute("aria-label") === "Filter Zones";
  })[0];
  function spaces() {
    return table(p, []).filter(function (row) { return row[0] === "Space"; }).map(function (row) { return row[1]; });
  }
  text.value = "Hall"; text.listeners.input({});
  assert.deepStrictEqual(spaces(), ["Hall"]);
  assert.ok(table(p, []).some(function (row) { return row[0] === "Volume"; }), "Hall's Volumes stay beneath it");
  text.value = "Zone A"; text.listeners.input({});
  assert.deepStrictEqual(spaces().sort(), ["Bath", "Hall", "Living"]);
  text.value = "Living 102"; text.listeners.input({});
  assert.deepStrictEqual(spaces().sort(), ["Bath", "Hall", "Living"], "a query no single Space matches lists all");
});

/* ---------------------------------------------------------------- review (PR #150) */

function button(p, text) {
  return p.section().querySelectorAll("button").filter(function (node) { return node.textContent === text; })[0];
}

function labelled(p, label) {
  return p.section().closest("[data-pane]").querySelectorAll("button, input").filter(function (node) {
    return node.getAttribute("aria-label") === label;
  })[0];
}

test("Expand all is offered while Spaces and Volumes start collapsed", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  assert.strictEqual(button(p, "Expand all").disabled, false);
});

test("the group of Spaces outside every Zone counts as no Zone and stays last in any sort", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot({ outside: true }) });
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "2 Zones · 5 Spaces");
  ["No.", "Height m", "Weighting factor"].forEach(function (label) {
    ["Sort A to Z", "Sort Z to A"].forEach(function (order) {
      var menu = labelled(p, label + " column menu");
      menu.listeners.click({ preventDefault: function () {} });
      menu.parentNode.querySelectorAll("button").filter(function (node) {
        return node.textContent === order;
      })[0].listeners.click({ preventDefault: function () {} });
      var tops = table(p, []).filter(function (row) { return row[0] === "Zone" || row[0] === "NoZone"; });
      assert.strictEqual(tops[tops.length - 1][0], "NoZone", label + " " + order);
    });
  });
});

test("a Model whose only Space is outside every Zone counts no Zone", function () {
  var p = page(), state = snapshot({ outside: true });
  state.sections["ph_composer.zones.overview"].value.zones = [];
  state.sections["ph_composer.spaces.spaces"].value.spaces =
    state.sections["ph_composer.spaces.spaces"].value.spaces.filter(function (space) { return !space.zone; });
  p.panel.receive({ type: "panel.snapshot", payload: state });
  assert.strictEqual(p.section().querySelector(".phc-view-count").textContent, "0 Zones · 1 Space");
  assert.deepStrictEqual(table(p, []).map(function (row) { return row[0]; }), ["NoZone", "Space"]);
});

test("hiding a column through Table options drops its filter", function () {
  var p = page();
  p.panel.receive({ type: "panel.snapshot", payload: snapshot() });
  function option(text) {
    var options = labelled(p, "Table options");
    options.listeners.click({ preventDefault: function () {} });
    options.parentNode.querySelectorAll(".phc-action-menu-item").filter(function (node) {
      return node.textContent === text;
    })[0].listeners.click({ preventDefault: function () {} });
  }
  option("Building-Segment column");
  var menu = labelled(p, "Building-Segment column menu");
  menu.listeners.click({ preventDefault: function () {} });
  var box = menu.parentNode.querySelectorAll("input").filter(function (node) { return node.type === "checkbox"; })[0];
  box.checked = false; box.listeners.change({});
  assert.match(p.section().querySelector(".phc-view-count").textContent, /1 filter$/);
  p.context.document.activeElement && p.context.document.activeElement.blur();
  option("Building-Segment column");
  assert.doesNotMatch(p.section().querySelector(".phc-view-count").textContent, /filter/);
});
