/* The Mechanical tab: one page header over a subtab per system and, beneath it, a pill row picking one table of
   that system. Systems and tables register themselves (features/mechanical/systems.js). The system and the table
   last shown are remembered on this computer as a display preference, never in the Model. The header's primary
   action is the shown table's New. */
PhComposerUI.define("features/mechanical/section", ["panel", "subtabs", "pill_row", "workspace", "unit_preferences",
  "features/mechanical/systems"],
function (panel, Subtabs, PillRow, ui, preferences, systems) {
  "use strict";
  var TAB = "mechanical", FEATURE = "ph_composer.mechanical";
  var current;

  function remember(scope, id) {
    if (preferences.tableView(scope) !== id) panel.setPreference("table_view", id, { scope: scope });
  }

  function View(root, state, send) {
    var self = this;
    this.session = state.session; this.root = root; this.tables = [];
    root.replaceChildren();
    this.header = ui.pageHeader({ title: "Mechanical" });
    root.appendChild(this.header.root);
    var shown = { system: preferences.tableView(FEATURE) }, tabs = [], bodies = [];
    this.systems = systems.list().map(function (entry) {
      var surface = ui.element("div", "mech-system"), pills = [], page = { table: preferences.tableView(entry.id) };
      entry.tables.forEach(function (table) {
        var tableSurface = ui.element("div", "mech-table");
        var view = table.build(tableSurface, { session: state.session, send: send });
        var held = { id: table.id, system: entry.id, view: view, surface: tableSurface };
        self.tables.push(held);
        pills.push({ id: table.id, label: table.label, surface: tableSurface });
      });
      var row = new PillRow({ label: entry.label + " tables", state: page, stateKey: "table", pills: pills,
        guard: function () { return self.guard(); },
        refused: function (reason) { panel.notify(reason, "warning"); },
        changed: function (id) { remember(entry.id, id); panel.repaint(); } });
      surface.appendChild(row.root);
      pills.forEach(function (pill) { surface.appendChild(pill.surface); });
      tabs.push({ id: entry.id, label: entry.label, surface: surface });
      bodies.push(surface);
      return { id: entry.id, pills: row };
    });
    if (!tabs.length) return;
    this.tabs = new Subtabs({ label: "Mechanical systems", state: shown, stateKey: "system", tabs: tabs,
      guard: function () { return self.guard(); },
      refused: function (reason) { panel.notify(reason, "warning"); },
      changed: function (id) { remember(FEATURE, id); panel.repaint(); } });
    root.appendChild(this.tabs.root);
    bodies.forEach(function (body) { root.appendChild(body); });
  }
  /* The table on screen: the shown system's chosen pill. */
  View.prototype.active = function () {
    if (!this.tabs) return null;
    var system = this.tabs.active, pills = this.systems.filter(function (entry) { return entry.id === system; })[0];
    return this.tables.filter(function (held) { return held.id === pills.pills.active; })[0];
  };
  View.prototype.guard = function () {
    var shown = this.active();
    return shown && shown.view.guard ? shown.view.guard() : null;
  };
  View.prototype.render = function (state) {
    var shown = this.active(), visible = state.ui.activeTab === TAB;
    this.tables.forEach(function (held) { held.view.render(state, visible && held === shown); });
    this.header.setPrimary(shown && shown.view.create ? shown.view.create : null);
  };
  /* A Locate names a table and what to show in it: its system and pill are chosen, then the table narrows. */
  View.prototype.navigate = function (intent) {
    var target = this.tables.filter(function (held) { return held.view.navigate && held.view.accepts &&
      held.view.accepts(intent); })[0];
    if (!target) return;
    if (this.tabs.active !== target.system && !this.tabs.select(target.system)) return;
    var system = this.systems.filter(function (entry) { return entry.id === target.system; })[0];
    if (system.pills.active !== target.id && !system.pills.select(target.id)) return;
    target.view.navigate(intent);
  };
  View.prototype.dispose = function () {
    this.tables.forEach(function (held) { if (held.view.dispose) held.view.dispose(); });
    if (this.tabs) this.tabs.dispose();
  };

  function render(root, state, send) {
    if (!root._view || root._view.session !== state.session) {
      if (root._view) root._view.dispose();
      root._view = new View(root, state, send);
    }
    current = root._view;
    current.render(state);
  }
  panel.navigationGuard(TAB, function (next) { return next === TAB || !current ? null : current.guard(); });
  panel.workedOn(FEATURE, TAB);
  panel.section(TAB, render, { pane: TAB, onNavigate: function (root, intent) {
    if (root._view) root._view.navigate(intent);
    panel.repaint();
  } });
  return { render: render };
});
