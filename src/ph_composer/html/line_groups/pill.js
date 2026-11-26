/* A line group's pill: the feature's assign bar with Make <group>, the groups and the schedule, and the one read the
   last two show. That read walks the Model, so it runs when the pill is shown, on Refresh and after a group's link
   changes, and only if the last read is missing or older than the Model (context/TECH_STACK.md, "Edge-owned
   assignments"). `options` are { bar(session, send, guard, notify, makeGroup) (the feature's bar), view (its
   schedule's, line_groups/schedule.js), types (its type section), intro (a line above the bar, or none) }. */
PhComposerUI.define("line_groups/pill", ["panel", "snapshot", "workspace", "line_groups/shared", "line_groups/groups",
  "line_groups/schedule"],
function (panel, snapshot, ui, shared, groups, schedules) {
  "use strict";

  function Pill(root, context, spec, options) {
    var self = this, session = context.session, send = context.send;
    this.spec = spec; this.types = options.types;
    this.read = new shared.Read(session, send, spec);
    this.groupForm = new groups.GroupForm(session, send, spec, function () { return self.bar.makePaths(); },
      function () {
        panel.notify("The new " + spec.label + " holds the selected lines. Double-click it in SketchUp to draw " +
          "more lines in it.", "info");
        self.read.read();
        panel.repaint();
      });
    if (options.intro) root.appendChild(ui.element("p", "line-group-intro", options.intro));
    this.bar = options.bar(session, send, function () { return self.barGuard(); }, panel.notify,
      function () { self.groupForm.open(self.state); });
    root.appendChild(this.bar.root);
    this.groups = new groups.Groups(root, session, send, spec, this.read);
    var surface = ui.element("section", "line-group-schedule-section");
    root.appendChild(surface);
    this.schedule = new schedules.Schedule(surface, session, send, spec, options.view, this.read, function () {
      if (self.read.read()) panel.repaint();
    }, panel.notify);
    root.appendChild(this.groupForm.root);
    this.create = null;
  }
  /* The bar waits for an open form and for a write in flight. */
  Pill.prototype.barGuard = function () {
    if (!this.groupForm.root.hidden) return "Finish or cancel the open form.";
    return this.groups.busy() ? "Wait for the " + this.spec.label + " to be linked." : null;
  };
  Pill.prototype.guard = function () {
    if (this.bar.busy()) return "Wait for the assignment to finish.";
    return this.barGuard() || this.schedule.guard();
  };
  Pill.prototype.render = function (state, shown) {
    this.state = state;
    this.read.refresh(state);
    if (shown && !this.shown && !this.read.busy() && (!this.read.value() || this.read.stale(state))) this.read.read();
    this.shown = shown;
    // The bar reads the selection first, so the open form takes the paths this state carries.
    this.bar.render(state, (snapshot.value(state, this.types) || {}).records || []);
    this.groupForm.refresh(state);
    this.groups.render(state);
    this.schedule.render(state, shown);
  };
  Pill.prototype.dispose = function () {
    this.groupForm.dispose(); this.bar.dispose(); this.groups.dispose(); this.schedule.dispose(); this.read.dispose();
  };
  return { Pill: Pill };
});
