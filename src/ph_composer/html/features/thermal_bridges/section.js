/* The Thermal Bridges tab: one page header over two peer subtabs, Types and Schedule, and the one schedule
   read they share. The read walks the Model, so it runs when the tab is opened, when a subtab is chosen, and
   on Refresh, and only if the last read is missing or older than the Model (context/TECH_STACK.md,
   "Edge-owned assignments"). */
PhComposerUI.define("features/thermal_bridges/section", ["panel", "subtabs", "workspace",
  "features/thermal_bridges/shared", "features/thermal_bridges/types", "features/thermal_bridges/schedule"],
function (panel, Subtabs, ui, shared, types, schedules) {
  "use strict";
  var TAB = "thermal_bridges";
  var pages = Object.create(null), current;

  function View(root, state, send) {
    var self = this, page = pages[state.session] || (pages[state.session] = {});
    this.session = state.session; this.root = root;
    root.replaceChildren();
    this.read = new shared.ScheduleRead(state.session, send);
    this.header = ui.pageHeader({ title: "Thermal Bridges" });
    root.appendChild(this.header.root);
    var typesSurface = ui.element("div", "tb-types"), scheduleSurface = ui.element("div", "tb-schedule");
    this.types = new types.Types(typesSurface, state.session, send, this.read, panel.repaint);
    this.schedule = new schedules.Schedule(scheduleSurface, state.session, send, this.read, function () {
      if (self.read.read()) panel.repaint();
    });
    this.tabs = new Subtabs({ label: "Thermal Bridges", state: page, stateKey: "tab", tabs: [
      { id: "types", label: "Types", surface: typesSurface },
      { id: "schedule", label: "Schedule", surface: scheduleSurface }],
    guard: function () { return self.guard(); },
    refused: function (reason) { panel.notify(reason, "warning"); },
    changed: function () {
      // Choosing a subtab is a request: either one shows the read, so a missing or stale one is read again.
      self.readIfNeeded(self.state);
      panel.repaint();
    } });
    root.appendChild(this.tabs.root);
    root.appendChild(typesSurface); root.appendChild(scheduleSurface);
  }
  View.prototype.guard = function () { return this.types.guard() || this.schedule.guard(); };
  View.prototype.readIfNeeded = function (state) {
    if (!this.read.busy() && (!this.read.value() || this.read.stale(state))) this.read.read();
  };
  View.prototype.render = function (state) {
    this.state = state;
    this.read.refresh(state);
    var shown = state.ui.activeTab === TAB;
    if (shown && !this.shown) this.readIfNeeded(state);
    this.shown = shown;
    this.header.setPrimary(this.tabs.active === "types" ? this.types.create : null);
    this.types.render(state);
    this.schedule.render(state, shown && this.tabs.active === "schedule");
  };
  View.prototype.dispose = function () {
    this.types.dispose(); this.schedule.dispose(); this.read.dispose(); this.tabs.dispose();
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
  panel.workedOn("ph_composer.thermal_bridges", TAB);
  panel.section(TAB, render, { pane: TAB });
  return { render: render };
});
