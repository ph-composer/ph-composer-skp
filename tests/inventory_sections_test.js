"use strict";
var assert = require("assert");
var test = require("node:test");
var dom = require("./support/dom_stub");
var panelSource = require("./support/panel_source");
var fixtures = require("./support/inventory_fixtures");

function setup(beforePaint) {
  var document = dom.buildDocument("");
  var sections = {}, guards = {}, sent = [], notices = [], state = fixtures.state();
  var roots = { library: dom.element("div"), assemblies: dom.element("div") };
  Object.keys(roots).forEach(function (key) { document.body.appendChild(roots[key]); });
  function send(type, payload) { sent.push({ type: type, payload: payload }); }
  function paint() { Object.keys(sections).forEach(function (key) { sections[key](roots[key], state, send); }); }
  var panel = { section: function (name, render) { sections[name] = render; }, repaint: paint,
    navigationGuard: function (name, guard) { guards[name] = guard; }, workedOn: function () {},
    notify: function (message) { notices.push(message); } };
  var context = { document: document, Intl: Intl, innerWidth: 1280, innerHeight: 800,
    setTimeout: setTimeout, clearTimeout: clearTimeout };
  context.window = context;
  dom.attachEvents(context);
  var modules = panelSource.start(context, ["library/section", "features/assemblies/section",
    "features/assemblies/materials", "features/zones/attached_zones"], { panel: panel });
  if (beforePaint) beforePaint(modules);
  paint();
  return { roots: roots, state: state, sent: sent, notices: notices, modules: modules, paint: paint, guards: guards };
}
function enter(input, value) {
  input.value = value;
  input.listeners.input({});
  input.listeners.keydown({ key: "Enter", preventDefault: function () {}, stopImmediatePropagation: function () {} });
}
function text(node) { return node.textContent + node.children.map(text).join(" "); }
function materials(o) { return o.roots.library._view.surface("materials"); }

test("library export offers deduped actual grid selection and defaults to all despite the filter", function () {
  var o = setup(), view = o.roots.library._view, inventory = materials(o).inventory, grid = inventory.grid;
  grid.select(inventory.edits.cells["mat_a:name"]);
  grid.select(inventory.edits.cells["mat_a:conductivity_w_mk"], true);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(view.selection())), {
    record_kind: "ph_composer.assemblies.material", ids: ["mat_a"] });
  view.exportLibrary.listeners.click({});
  assert.strictEqual(o.sent[0].payload.params.scope, "all");
  assert.strictEqual(view.exportForm.selection.length, 1); view.exportForm.hide();
  inventory.controls.filter.value = "Wood"; inventory.controls.filter.listeners.input({});
  assert.strictEqual(view.selection().ids.length, 0, "a hidden selected row is withdrawn");
  view.exportLibrary.listeners.click({});
  assert.strictEqual(o.sent[1].payload.params.scope, "all");
  assert.strictEqual(view.exportForm.selection.length, 0, "visible filtered rows are not selected implicitly");
});

test("inventories render transport values, material uses and withheld U-value reasons", function () {
  var o = setup();
  assert.strictEqual(materials(o).inventory.edits.cells["mat_a:name"].input.value, "Mineral wool");
  assert.ok(!text(o.roots.library).includes("Definitions stored in this model."), "no caption under the title");
  var withheld = o.roots.assemblies.querySelector("[data-u-withheld]");
  assert.ok(withheld.getAttribute("aria-label").includes("Choose a Material for every Layer-Segment."));
  assert.strictEqual(o.roots.library.querySelector("[data-material-use-count]").textContent, "1");
  assert.strictEqual(o.sent.length, 0);
});

test("an inline edit sends expected_values once and retains a refused draft", function () {
  var o = setup(), input = materials(o).inventory.edits.cells["mat_a:conductivity_w_mk"].input;
  enter(input, "0.05");
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.assemblies.materials.update");
  assert.strictEqual(o.sent[0].payload.params.expected_values.conductivity_w_mk, 0.04);
  o.state.ui.actionResult = { session: "session", request_id: o.sent[0].payload.request_id,
    outcome: { status: "refused", message: "The Material changed. Nothing was written." } };
  o.paint();
  assert.strictEqual(input.value, "0.05");
  assert.ok(o.guards.library("assemblies"));
});

test("display preferences reformat clean cells and preserve a typing draft", function () {
  var o = setup(), view = materials(o).inventory;
  var input = view.edits.cells["mat_a:conductivity_w_mk"].input;
  input.value = "0.05";
  input.listeners.input({});
  o.modules.unit_preferences.set("unit_system", "IP");
  o.paint();
  assert.strictEqual(input.value, "0.05");
  assert.notStrictEqual(view.edits.cells["mat_b:conductivity_w_mk"].input.value, "0.12");
  assert.strictEqual(o.sent.length, 0);
});

test("an in-use Material delete requires an explicit replacement and names affected Assemblies", function () {
  var o = setup(), view = materials(o);
  view.replacement.open(o.state.sections["ph_composer.assemblies.materials"].value.records[0],
    o.state.sections["ph_composer.assemblies.materials"].value.records);
  assert.ok(view.replacement.uses.textContent.includes("Wall"));
  view.replacement.submit();
  assert.strictEqual(o.sent.length, 0);
  view.replacement.select.value = "mat_b";
  view.replacement.select.listeners.change({});
  view.replacement.submit();
  assert.strictEqual(o.sent[0].payload.params.replacement_id, "mat_b");
});

test("view controls send nothing and refuse hiding an active draft", function () {
  var o = setup(), view = materials(o).inventory;
  view.controls.filter.value = "Wood";
  view.controls.filter.listeners.input({});
  view.controls.groupBy.value = "category";
  view.controls.groupBy.listeners.change({});
  view.controls.orderBy.value = "conductivity_w_mk";
  view.controls.orderBy.listeners.change({});
  assert.strictEqual(o.sent.length, 0);
  var input = view.edits.cells["mat_b:name"].input;
  input.value = "Draft";
  input.listeners.input({});
  view.controls.filter.value = "Mineral";
  view.controls.filter.listeners.input({});
  assert.strictEqual(view.controls.filter.value, "Wood");
  assert.strictEqual(input.value, "Draft");
});

test("Attached zones use only the existing save and duplicate actions", function () {
  var o = setup(), view = o.roots.library._view;
  view.tabs.select("attached_zones");
  var input = view.surface("attached_zones").inventory.edits.cells["atz_a:name"].input;
  enter(input, "Carport");
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.zones.faces.attached_zone.save");
  assert.strictEqual(o.sent[0].payload.params.expected_values.name, "Garage");
});

test("Assembly Open shows the Builder and exposes no provider controls", function () {
  var o = setup(), view = o.roots.assemblies._view;
  view.open(o.state.sections["ph_composer.assemblies.assemblies"].value.records[0]);
  assert.ok(view.editor);
  assert.ok(view.listRoot.hidden);
  assert.ok(view.editor.root.querySelector("[aria-label='Back to Assemblies']"));
  assert.ok(!text(o.roots.assemblies).includes("designPH"));
  assert.ok(!o.roots.assemblies.querySelector("[data-row-action='faces']"));
  assert.strictEqual(o.sent.length, 0);
});

function result(o, index, status, value) {
  var payload = o.sent[index].payload;
  o.state.ui.actionResult = { session: "session", request_id: payload.request_id,
    outcome: { status: status, value: value, message: status === "completed" ? "" : "Changed in the Model." } };
  o.paint();
}

test("new Material converts IP entries and a refused create retains its fields", function () {
  var o = setup(), form = materials(o).newMaterial;
  o.modules.unit_preferences.set("unit_system", "IP");
  form.open();
  form.fields.name.value = "New insulation";
  form.fields.conductivity_w_mk.value = "0.04 W/(m K)";
  form.fields.conductivity_w_mk.listeners.input({});
  form.submit();
  var params = o.sent[0].payload.params;
  assert.strictEqual(params.values.conductivity_w_mk, 0.04);
  assert.strictEqual(params.values.density_kg_m3, null);
  assert.strictEqual(params.values.category, "");
  result(o, 0, "refused");
  assert.strictEqual(form.root.hidden, false);
  assert.strictEqual(form.fields.name.value, "New insulation");
  assert.strictEqual(form.fields.conductivity_w_mk.value, "0.04 W/(m K)");
  assert.strictEqual(form.cancel.disabled, false);
});

test("new Material reads a bare number in the chosen input form and stores W/(m K)", function () {
  var o = setup(), form = materials(o).newMaterial, field = form.unitFields.conductivity_w_mk;
  o.modules.unit_preferences.set("unit_system", "IP");
  assert.strictEqual(field.formChoice.value, "r_per_in", "R per inch first in IP");
  form.open();
  form.fields.name.value = "Mineral wool";
  form.fields.conductivity_w_mk.value = "4";
  form.fields.conductivity_w_mk.listeners.input({});
  // Choosing a form rereads what is typed; it does not convert it.
  field.formChoice.value = "btu_in_h_ft2_f";
  field.formChoice.listeners.change({});
  assert.strictEqual(form.fields.conductivity_w_mk.value, "4");
  field.formChoice.value = "r_per_in";
  field.formChoice.listeners.change({});
  form.submit();
  assert.ok(Math.abs(o.sent[0].payload.params.values.conductivity_w_mk - 0.036057) < 0.000001);
});

test("the shared table quantity keeps its own unit while the form shows R per inch", function () {
  var o = setup(), form = materials(o).newMaterial;
  o.modules.unit_preferences.set("unit_system", "IP");
  o.paint();
  assert.strictEqual(form.unitFields.conductivity_w_mk.field.inputForm, "r_per_in");
  assert.strictEqual(materials(o).inventory.edits.quantities.conductivity_w_mk.inputForm, undefined);
});

test("new Material sends the chosen color and starts the next one white", function () {
  var o = setup(), form = materials(o).newMaterial;
  form.open();
  form.fields.name.value = "Painted panel";
  form.color.swatches[9].button.listeners.click({ preventDefault: function () {} });
  assert.strictEqual(form.color.swatches[9].button.getAttribute("aria-pressed"), "true");
  form.submit();
  assert.strictEqual(o.sent[0].payload.params.values.color, form.color.swatches[9].color);
  result(o, 0, "completed");
  assert.strictEqual(form.color.color, "#ffffff");
});

test("an empty inventory offers the pane's create action and runs its guard", function () {
  var o = setup(), section = o.state.sections["ph_composer.assemblies.materials"];
  section.value.records = [];
  o.paint();
  var button = o.roots.library._view.surface("materials").inventory.scroll.querySelector(".phc-empty-action");
  assert.strictEqual(button.textContent, "+ New Material");
  button.listeners.click({ preventDefault: function () {} });
  assert.strictEqual(materials(o).newMaterial.root.hidden, false);
  button.listeners.click({ preventDefault: function () {} });
  assert.strictEqual(o.notices[o.notices.length - 1], "Finish or cancel the open form.");
});

test("an inventory with no records names the next step; a filter that hides them all says so instead", function () {
  var o = setup(), section = o.state.sections["ph_composer.assemblies.assemblies"], kept = section.value.records;
  section.value.records = [];
  o.paint();
  assert.ok(text(o.roots.assemblies).includes("No Assembly records yet."));
  section.value.records = kept;
  o.paint();
  var filter = o.roots.assemblies.querySelectorAll("input").filter(function (node) {
    return node.type === "search" || /Name or notes/.test(node.placeholder || node.getAttribute("aria-label") || "");
  })[0];
  filter.value = "no such assembly"; filter.listeners.input({});
  o.paint();
  assert.ok(text(o.roots.assemblies).includes("No Assembly records match this view."));
});

test("New Assembly creates at once under a free name and opens the new record in the Builder", function () {
  var o = setup(), view = o.roots.assemblies._view, section = o.state.sections["ph_composer.assemblies.assemblies"];
  section.value.records[0].values.name = "Assembly 1";
  o.paint();
  view.create.listeners.click({});
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.name, "ph_composer.assemblies.assemblies.create");
  assert.deepStrictEqual(JSON.parse(JSON.stringify(o.sent[0].payload.params.values)), { name: "Assembly 2" },
    "a name and nothing else: the Model supplies the rest and the Builder edits it");
  view.create.listeners.click({});
  assert.strictEqual(o.sent.length, 1, "a second click waits for the first");
  // The outcome names the new record; an unrelated record arriving first is not mistaken for it.
  var other_ = JSON.parse(JSON.stringify(section.value.records[0])), fresh = JSON.parse(JSON.stringify(other_));
  other_.id = "asm_elsewhere"; fresh.id = "asm_new"; fresh.values.name = "Assembly 2";
  section.value.records.push(other_);
  result(o, 0, "completed", { id: "asm_new" });
  assert.ok(!view.editor, "nothing opens until the new record is in the snapshot");
  section.value.records.push(fresh);
  o.paint();
  assert.ok(view.editor, "the Builder opens");
  assert.strictEqual(view.editor.assemblyId, "asm_new");
  // A refused create opens nothing and leaves the button ready.
  var other = setup(), refused = other.roots.assemblies._view;
  refused.create.listeners.click({});
  result(other, 0, "refused");
  assert.ok(!refused.editor);
  refused.create.listeners.click({});
  assert.strictEqual(other.sent.length, 2);
});

test("duplicate Material copies datasheet links only through the explicit checkbox", function () {
  var o = setup(), form = materials(o).duplicate;
  form.open(o.state.sections["ph_composer.assemblies.materials"].value.records[0]);
  assert.strictEqual(form.copyDatasheets.checked, false);
  form.submit();
  assert.strictEqual(o.sent[0].payload.params.copy_datasheets, false);
  result(o, 0, "refused");
  form.copyDatasheets.checked = true;
  form.submit();
  assert.strictEqual(o.sent[1].payload.params.copy_datasheets, true);
});

test("Assembly hint selects store honeybee words and clear with a null patch", function () {
  var o = setup(), cell = o.roots.assemblies._view.edits.cells["asm_a:type"];
  assert.ok(cell.input.classList.contains("phc-enum-cell"), "every select cell is the kit's enum cell");
  cell.input.value = "RoofCeiling";
  cell.input.listeners.change({});
  assert.strictEqual(o.sent[0].payload.params.values.type, "RoofCeiling");
  o.state.sections["ph_composer.assemblies.assemblies"].value.records[0].values.type = "RoofCeiling";
  result(o, 0, "completed");
  assert.strictEqual(cell.input.style["--category-fill"], "rgb(222, 194, 194)",
    "the chip takes its value's colour, the one the viewport draws");
  cell.input.value = "";
  cell.input.listeners.change({});
  assert.strictEqual(o.sent[1].payload.params.values.type, null);
  assert.strictEqual(cell.input.style["--category-fill"], undefined, "None takes the neutral pill");
  assert.strictEqual(o.sent[1].payload.params.expected_values.type, "RoofCeiling");
});

test("range writes stay canonical, serialize individual actions and stop at a refusal", function () {
  var o = setup(), inventory = materials(o).inventory;
  inventory.ranges.submit([
    { id: "mat_a", values: { conductivity_w_mk: 0.06 }, expected_values: { conductivity_w_mk: 0.04 } },
    { id: "mat_b", values: { conductivity_w_mk: 0.06 }, expected_values: { conductivity_w_mk: 0.12 } }
  ]);
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(o.sent[0].payload.params.values.conductivity_w_mk, 0.06);
  assert.ok(o.guards.library("assemblies"));
  result(o, 0, "refused");
  assert.strictEqual(o.sent.length, 1);
  assert.strictEqual(inventory.ranges.busy(), false);
  assert.ok(o.notices.includes("Changed in the Model."));
});

test("a host category change cannot collapse or filter away a refused draft", function () {
  var o = setup(), inventory = materials(o).inventory;
  inventory.controls.groupBy.value = "category";
  inventory.controls.groupBy.listeners.change({});
  var input = inventory.edits.cells["mat_b:name"].input;
  input.value = "Draft wood";
  input.listeners.input({});
  inventory.controls.collapsed[JSON.stringify(["category", "insulation"])] = true;
  o.state.sections["ph_composer.assemblies.materials"].value.records[1].values.category = "insulation";
  o.paint();
  assert.strictEqual(inventory.scroll._table.rows.mat_b.node.hidden, false);
  assert.strictEqual(input.value, "Draft wood");
});

test("changing Model sessions disposes every old draft and form", function () {
  var o = setup(), old = materials(o), cell = old.inventory.edits.cells["mat_a:name"];
  cell.input.value = "Old draft";
  cell.input.listeners.input({});
  o.state.session = "different-session";
  o.paint();
  old.inventory.edits.commit(cell);
  old.newMaterial.fields.name.value = "Old form";
  old.newMaterial.submit();
  assert.strictEqual(o.sent.length, 0);
  old.color.open(o.state.sections["ph_composer.assemblies.materials"].value.records[0],
    old.inventory.scroll._table.rows.mat_a.cells.color._color);
  old.color.submit();
  assert.strictEqual(o.sent.length, 0);
  assert.strictEqual(old.color.enabled, false);
  assert.strictEqual(old.inventory.edits.disposed, true);
  assert.strictEqual(materials(o).inventory.edits.cells["mat_a:name"].input.value, "Mineral wool");
});

test("the graphical color picker compares stored color even when the display color was computed", function () {
  var o = setup(), view = o.roots.assemblies._view;
  var record = o.state.sections["ph_composer.assemblies.assemblies"].value.records[0];
  delete record.values.color;
  record.display.color = "#64a4d8";
  view.color.open(record, view.inventory.scroll._table.rows.asm_a.cells.color._color);
  assert.strictEqual(view.color.hex.value, "#64a4d8");
  view.color.square.listeners.keydown({ key: "ArrowRight", preventDefault: function () {} });
  assert.notStrictEqual(view.color.hex.value, "#64a4d8");
  view.color.submit();
  assert.strictEqual(o.sent[0].payload.params.expected_values.color, null);
  view.color.hide();
  assert.strictEqual(view.color.root.hidden, false, "pending color edits cannot dismiss");
  result(o, 0, "refused");
  assert.strictEqual(view.color.root.hidden, false);
  view.color.hide();
  assert.strictEqual(view.color.root.hidden, true);
});

test("feature absence closes inventory forms and unreadable records have a visible explanation", function () {
  var o = setup(), library = o.roots.library._view, view = materials(o);
  o.state.sections["ph_composer.assemblies.materials"].value.unreadable = [
    { id: "mat_broken", message: "Unsupported record version." }
  ];
  o.paint();
  assert.ok(view.inventory.unreadable.textContent.includes("mat_broken: Unsupported record version."));
  view.newMaterial.open();
  delete o.state.sections["ph_composer.assemblies.materials"];
  o.paint();
  assert.strictEqual(view.newMaterial.root.hidden, true);
  assert.strictEqual(library.surfaces[0].create.disabled, true);
  view.newMaterial.fields.name.value = "Cannot create";
  view.newMaterial.submit();
  assert.strictEqual(o.sent.length, 0);
});

test("a modified color draft survives an outside navigation click", function () {
  var o = setup(), view = materials(o);
  var record = o.state.sections["ph_composer.assemblies.materials"].value.records[0];
  view.color.open(record, view.inventory.scroll._table.rows.mat_a.cells.color._color);
  view.color.hex.value = "#123456";
  var prevented = false;
  view.color.dismissOutside({ target: o.roots.assemblies, preventDefault: function () { prevented = true; } });
  assert.strictEqual(view.color.root.hidden, false);
  assert.strictEqual(prevented, true);
  assert.ok(o.guards.library("assemblies"));
  assert.strictEqual(o.sent.length, 0);
});

test("withdrawn create requests can reopen with an enabled Cancel after their feature returns", function () {
  var cases = [[function (o) { return materials(o).newMaterial; }, "ph_composer.assemblies.materials"]];
  cases.forEach(function (entry) {
    var o = setup(), form = entry[0](o), section = o.state.sections[entry[1]];
    form.open();
    form.fields.name.value = "Pending new record";
    form.submit();
    assert.strictEqual(form.cancel.disabled, true);
    delete o.state.sections[entry[1]];
    o.paint();
    assert.strictEqual(form.busy(), false);
    assert.strictEqual(form.root.hidden, true);
    o.state.sections[entry[1]] = section;
    o.paint();
    form.open();
    assert.strictEqual(form.cancel.disabled, false);
    form.cancel.listeners.click({});
    assert.strictEqual(form.root.hidden, true);
    assert.strictEqual(o.sent.length, 1);
  });
});

test("withdrawing an inventory forgets its queued range and ignores the late outcome", function () {
  var o = setup(), inventory = materials(o).inventory;
  var section = o.state.sections["ph_composer.assemblies.materials"];
  inventory.ranges.submit([
    { id: "mat_a", values: { notes: "First" }, expected_values: { notes: "" } },
    { id: "mat_b", values: { notes: "Second" }, expected_values: { notes: "" } }
  ]);
  delete o.state.sections["ph_composer.assemblies.materials"];
  o.paint();
  assert.strictEqual(inventory.ranges.busy(), false);
  assert.strictEqual(o.guards.library("assemblies"), null);
  result(o, 0, "completed");
  o.state.sections["ph_composer.assemblies.materials"] = section;
  o.paint();
  assert.strictEqual(o.sent.length, 1, "a late result must not start the abandoned next range write");
  assert.strictEqual(inventory.ranges.busy(), false);
});

test("withdrawing an inventory resets its pending row action", function () {
  var o = setup(), inventory = o.roots.assemblies._view.inventory;
  var section = o.state.sections["ph_composer.assemblies.assemblies"];
  inventory.requests.run("ph_composer.assemblies.assemblies.duplicate", { id: "asm_a" });
  delete o.state.sections["ph_composer.assemblies.assemblies"];
  o.paint();
  assert.strictEqual(inventory.requests.busy(), false);
  assert.strictEqual(o.guards.assemblies("library"), null);
  o.state.sections["ph_composer.assemblies.assemblies"] = section;
  o.paint();
  inventory.requests.run("ph_composer.assemblies.assemblies.duplicate", { id: "asm_b" });
  assert.strictEqual(o.sent.length, 2);
});

test("retained Assembly and Attached-zone Duplicate listeners cannot write after a Model switch", function () {
  var o = setup(), library = o.roots.library._view, assemblies = o.roots.assemblies._view;
  var assemblyDuplicate = assemblies.inventory.scroll._table.rows.asm_a.controls.duplicate.node;
  library.tabs.select("attached_zones");
  var attached = library.surface("attached_zones").inventory;
  var attachedDuplicate = attached.scroll._table.rows.atz_a.controls.duplicate.node;
  o.state.session = "new-model-session";
  o.paint();
  assemblyDuplicate.listeners.click({});
  attachedDuplicate.listeners.click({});
  assert.strictEqual(o.sent.length, 0);
  assert.strictEqual(assemblies.inventory.disposed, true);
  assert.strictEqual(attached.disposed, true);
});


test("Assembly numeric inventory cells follow the displayed SI and IP units", function () {
  var o = setup(), units = o.modules.units, fields = o.modules.fields;
  var rows = o.state.sections["ph_composer.assemblies.assemblies"].value.records;
  rows[0].display.total_thickness_mm = 165;
  rows[0].display.thermal.u_effective_w_m2k = 0.2;
  o.paint();
  function cells(field) {
    return o.roots.assemblies.querySelectorAll("td").filter(function (td) {
      return td.className.indexOf("col-" + field) >= 0;
    }).map(function (td) { return td.textContent; });
  }
  // The header names the unit, so a cell is the number alone.
  assert.ok(cells("total_thickness_mm").indexOf("165") >= 0);
  assert.ok(cells("u_effective_w_m2k").indexOf(units.format(0.2, fields.U_VALUE,
    units.profile(fields.U_VALUE, { unit_system: "SI" }), { showUnit: false })) >= 0);
  o.modules.unit_preferences.set("unit_system", "IP");
  o.paint();
  assert.ok(cells("total_thickness_mm").indexOf(units.format(165, fields.LENGTH_MM,
    units.profile(fields.LENGTH_MM, o.modules.unit_preferences.current()), { showUnit: false })) >= 0);
  assert.ok(cells("u_effective_w_m2k").indexOf(units.format(0.2, fields.U_VALUE,
    units.profile(fields.U_VALUE, o.modules.unit_preferences.current()), { showUnit: false })) >= 0);
  assert.strictEqual(o.sent.length, 0);
});

test("Library surfaces come from registrations in order, and the active one owns the New button", function () {
  var built = [];
  var o = setup(function (modules) {
    modules["library/section"].registerSurface({ id: "outside", label: "Outside", order: 15,
      createLabel: "+ New Outside", build: function (root) {
        built.push(root);
        return { records: [1, 2], guard: function () { return null; }, render: function () {},
          dispose: function () {}, create: function () { built.push("created"); },
          canCreate: function () { return true; } };
      } });
  });
  var view = o.roots.library._view;
  assert.strictEqual(view.surfaces.map(function (entry) { return entry.spec.id; }).join(),
    "materials,outside,attached_zones");
  assert.strictEqual(view.surfaces.map(function (entry) { return Boolean(entry.create.parentNode); }).join(),
    "true,false,false");
  view.tabs.select("outside");
  o.paint();
  assert.strictEqual(view.header.root.children.length, 2,
    "a tab counts its own records in its action bar, not in the page header");
  assert.strictEqual(view.surfaces[1].create.parentNode, view.header.root.querySelector(".phc-heading-actions"));
  view.surfaces[1].create.listeners.click({});
  assert.strictEqual(built[1], "created");
  assert.strictEqual(view.selection(), null, "a surface without a record kind exports nothing");
});

test("a surface missing what its spec declares is refused when the pane builds it", function () {
  assert.throws(function () {
    setup(function (modules) {
      modules["library/section"].registerSurface({ id: "broken", label: "Broken", createLabel: "+ New",
        build: function () {
          return { records: [], guard: function () { return null; }, render: function () {}, dispose: function () {} };
        } });
    });
  }, /Library surface broken is missing create, canCreate/);
});

test("an open library export form blocks a Library tab change", function () {
  var o = setup(), view = o.roots.library._view;
  view.exportLibrary.listeners.click({});
  assert.strictEqual(view.tabs.select("attached_zones"), false);
  assert.strictEqual(view.tabs.active, "materials");
  assert.ok(o.guards.library("assemblies"));
});

test("a feature's settings end the inventory action bar, and omitting them adds no group", function () {
  var o = setup(), Inventory = o.modules.inventory.Inventory, setting = dom.element("button");
  function build(settings) {
    return new Inventory(dom.element("div"), "session", function () {}, function () {}, function () {}, {
      section: "outside", action: "outside.update", label: "Outside", columns: [["name", "Name"]], editable: ["name"],
      groups: [], settings: settings });
  }
  var view = build([setting]), controls = view.controls.root, group = controls.children[controls.children.length - 1];
  assert.strictEqual(group, view.settingsRoot, "after every view control");
  assert.strictEqual(group.className, "phc-inventory-settings"); assert.strictEqual(group.children[0], setting);
  assert.strictEqual(build().controls.root.querySelector(".phc-inventory-settings"), null);
});

test("a record color outside #rrggbb paints white and never reaches the style as written", function () {
  var o = setup(), colorCell = o.modules.inventory_forms.colorCell, td = dom.element("td");
  var form = { enabled: true, requests: { busy: function () { return false; } }, open: function () {} };
  var hostile = "red; background-image: url(x)";
  colorCell(td, { values: { name: "Brick", color: hostile } }, form, function () { return true; });
  assert.strictEqual(td._color.style.backgroundColor, "#ffffff");
  assert.ok(!td._color.getAttribute("aria-label").includes("url("));
  colorCell(td, { values: { name: "Brick", color: "#A1b2C3" } }, form, function () { return true; });
  assert.strictEqual(td._color.style.backgroundColor, "#A1b2C3");
});
