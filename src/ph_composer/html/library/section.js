/* The Library pane: model-owned definitions, one registered surface per record inventory. It owns the
 * heading, the sub-tabs, each surface's "+ New" button and the library export; every inventory comes
 * from a feature through `registerSurface`, built-in or not.
 *
 *   registerSurface({ id, label, order, recordKind, createLabel, build(root, state, send) })
 *
 * `build` returns the surface's view: `records`, `guard()`, `render(state)` and `dispose()`, plus
 * `inventory` (an html/inventory.js Inventory) when `recordKind` makes its rows exportable, and
 * `create()` and `canCreate()` when `createLabel` asks the pane for a "+ New" button, which the view's
 * `inventory`, when it has one, also offers in its empty state. A view missing
 * one of these throws when the pane builds it. Surfaces appear in `order` (built-ins use 10 to 32;
 * omitted is 0), then by id; `id` is also the sub-tab key the pane remembers per Model session.
 * Register when the module loads: the pane builds its surfaces once per Model session. */
PhComposerUI.define("library/section", ["panel", "workspace", "subtabs", "library/export"],
  function (panel, ui, Subtabs, ExportForm) {
  "use strict";
  var pages = Object.create(null), current, registered = [];
  var VIEW = ["guard", "render", "dispose"];
  function registerSurface(spec) {
    if (!spec.id || !spec.label || typeof spec.build !== "function") {
      throw new Error("A Library surface needs an id, a label and build");
    }
    if (registered.some(function (entry) { return entry.id === spec.id;
      })) throw new Error("Duplicate Library surface");
    registered.push(spec);
    registered.sort(function (a, b) { return (a.order || 0) - (b.order || 0) || ui.compareText(a.id, b.id); });
  }
  function guard(view) {
    if (!view) return null;
    if (!view.exportForm.root.hidden) return "Finish or cancel the open form.";
    return view.surfaces.map(function (entry) { return entry.view.guard(); }).filter(Boolean)[0] || null;
  }
  function checked(spec, view) {
    var needs = VIEW.concat(spec.createLabel ? ["create", "canCreate"] : []).filter(function (name) {
      return typeof view[name] !== "function";
    });
    if (spec.recordKind && !(view.inventory && view.inventory.grid)) needs.push("inventory");
    if (needs.length) throw new Error("Library surface " + spec.id + " is missing " + needs.join(", "));
    return view;
  }
  function active(view) {
    return view.surfaces.filter(function (entry) { return entry.spec.id === view.tabs.active; })[0];
  }
  function build(root, state, send) {
    var view = { session: state.session };
    var page = pages[state.session] || (pages[state.session] = {});
    function changed() { panel.repaint(); }
    function allowed() { var reason = guard(view);
    if (reason) panel.notify(reason);
    return !reason; }
    root.replaceChildren();
    view.header = ui.pageHeader({ title: "Library" });
    root.appendChild(view.header.root);
    view.surfaces = registered.map(function (spec) {
      var surface = ui.element("section", "phc-inventory-surface");
      return { spec: spec, root: surface, view: checked(spec, spec.build(surface, state, send)) };
    });
    view.surface = function (id) {
      var entry = view.surfaces.filter(function (item) { return item.spec.id === id; })[0];
      return entry ? entry.view : null;
    };
    view.tabs = new Subtabs({ label: "Library definitions", state: page, stateKey: "surface",
      tabs: view.surfaces.map(function (entry) {
        return { id: entry.spec.id, label: entry.spec.label, surface: entry.root };
      }), guard: function () { return guard(view); }, refused: function (reason) { panel.notify(reason); },
      changed: changed });
    root.appendChild(view.tabs.root);
    view.surfaces.forEach(function (entry) {
      root.appendChild(entry.root);
      if (!entry.spec.createLabel) return;
      function create() { if (allowed()) entry.view.create(); }
      entry.create = ui.button(entry.spec.createLabel, create);
      if (entry.view.inventory) entry.view.inventory.emptyAction = { label: entry.spec.createLabel, run: create };
    });
    view.exportForm = new ExportForm(state.session, send, changed);
    view.exportLibrary = ui.button("Export library", function () {
      if (!allowed()) return;
      var selection = view.selection();
      view.exportForm.open(selection ? selection.ids.map(function (id) {
        return { record_kind: selection.record_kind, id: id };
      }) : []);
    });
    view.header.setActions([view.exportLibrary]);
    root.appendChild(view.exportForm.root);
    view.selection = function () {
      var entry = active(view);
      if (!entry || !entry.spec.recordKind) return null;
      var inventory = entry.view.inventory;
      inventory.grid.sync();
      var ids = [], seen = Object.create(null);
      inventory.grid.matrix().forEach(function (row) { row.forEach(function (cell) {
        var id = cell && cell.row.record && cell.row.record.id;
        if (id && !seen[id]) { seen[id] = true; ids.push(id); }
      }); });
      return { record_kind: entry.spec.recordKind, ids: ids };
    };
    view.dispose = function () {
      view.tabs.dispose();
      view.exportForm.dispose();
      view.surfaces.forEach(function (entry) { entry.view.dispose(); });
    };
    return view;
  }
  function render(root, state, send) {
    var view = root._view;
    if (!view || view.session !== state.session) {
      if (view) view.dispose();
      view = root._view = build(root, state, send);
    }
    current = view;
    view.exportForm.refresh(state);
    view.surfaces.forEach(function (entry) {
      entry.view.render(state);
      if (entry.create) entry.create.disabled = !entry.view.canCreate();
    });
    // Each tab counts its own records in its action bar; the header carries the shown tab's New button.
    var shown = active(view);
    view.header.setPrimary(shown && shown.create || null);
  }
  panel.navigationGuard("library", function (next) { return next === "library" ? null : guard(current); },
    panel.notify);
  panel.section("library", render, { pane: "library", onNavigate: function (root, intent) {
    if (root._view && intent.kind) root._view.tabs.select(intent.kind);
  } });
  return { render: render, registerSurface: registerSurface, selection: function () {
    return current ? current.selection() : null;
  } };
});
