/* Hot Water's piping pills on the Mechanical tab, after Tanks: Pipe Types (pipe_types.js) and Piping. The Piping pill
   holds the assign bar with New Piping group, the Piping groups and the schedule, and the one read the last two show.
   That read walks the Model, so it runs when the pill is shown, on Refresh and after a group's link changes, and only
   if the last read is missing or older than the Model (context/TECH_STACK.md, "Edge-owned assignments"). */
PhComposerUI.define("features/piping/section", ["panel", "snapshot", "workspace", "features/mechanical/systems",
  "features/mechanical/hot_water", "features/piping/shared", "features/piping/assign_bar", "features/piping/groups",
  "features/piping/schedule", "features/piping/pipe_types", "features/piping/systems_columns"],
function (panel, snapshot, ui, systems, hotWater, shared, bars, groups, schedules) {
  "use strict";
  var ID = shared.PREFIX + "piping";

  function Piping(root, context) {
    var self = this, session = context.session, send = context.send;
    this.read = new shared.Read(session, send);
    this.groupForm = new groups.GroupForm(session, send, function () {
      panel.notify("The new Piping group is open in SketchUp: draw its lines with the Line tool.", "info");
      self.read.read();
      panel.repaint();
    });
    this.bar = new bars.AssignBar(session, send, function () { return self.barGuard(); }, panel.notify,
      function () { self.groupForm.open(self.state); });
    root.appendChild(this.bar.root);
    this.groups = new groups.Groups(root, session, send, this.read);
    var surface = ui.element("section", "piping-schedule-section");
    root.appendChild(surface);
    this.schedule = new schedules.Schedule(surface, session, send, this.read, function () {
      if (self.read.read()) panel.repaint();
    });
    root.appendChild(this.groupForm.root);
    this.create = null;
  }
  /* The bar waits for an open form and for a write in flight. */
  Piping.prototype.barGuard = function () {
    if (!this.groupForm.root.hidden) return "Finish or cancel the open form.";
    return this.groups.busy() ? "Wait for the Piping group to be linked." : null;
  };
  Piping.prototype.guard = function () {
    if (this.bar.busy()) return "Wait for the assignment to finish.";
    return this.barGuard() || this.schedule.guard();
  };
  Piping.prototype.render = function (state, shown) {
    this.state = state;
    this.read.refresh(state);
    if (shown && !this.shown && !this.read.busy() && (!this.read.value() || this.read.stale(state))) this.read.read();
    this.shown = shown;
    this.groupForm.refresh(state);
    this.bar.render(state, (snapshot.value(state, shared.TYPES) || {}).records || []);
    this.groups.render(state);
    this.schedule.render(state, shown);
  };
  Piping.prototype.dispose = function () {
    this.groupForm.dispose(); this.bar.dispose(); this.groups.dispose(); this.schedule.dispose(); this.read.dispose();
  };

  systems.table({ system: hotWater.SYSTEM, id: ID, label: "Piping", order: 50,
    build: function (surface, context) { return new Piping(surface, context); } });
  return { Piping: Piping };
});
