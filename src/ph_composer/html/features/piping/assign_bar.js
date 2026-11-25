/* The assign bar at the top of the Piping pill, in the shape of an edge feature's: what SketchUp has selected,
   how many of those lines a write can reach, then a Pipe Type, a role and only that role's values (a trunk's
   Multiplier and Demand recirculation, a recirculation pipe's Water temperature and Hours a day), Assign and Clear.
   It always shows, so selecting never moves what is under it; with nothing to assign, Assign is disabled and its
   reason sits beside it. Each press is one pipes.assign or pipes.clear over the lines as the selection read them, one
   Undo step. The same values arm the pipe tool, the secondary route; New Piping group closes the row. */
PhComposerUI.define("features/piping/assign_bar", ["request", "snapshot", "workspace", "fields", "unit_field",
  "features/piping/shared", "features/piping/pipe_tool"],
function (request, snapshot, ui, fields, unitFields, shared, pipeTool) {
  "use strict";
  var TEMPERATURE = fields.with(fields.TEMPERATURE_C, { label: "Water temperature" });
  var HOURS = fields.with(fields.HOURS_PER_DAY, { label: "Hours a day" });
  var DEFAULTS = { multiplier: 1, demand_recirculation: false, water_temp_c: 60, daily_period: 24 };
  var ROLE_KEYS = { trunk: ["multiplier", "demand_recirculation"], branch: [], twig: [],
    recirculation: ["water_temp_c", "daily_period"] };
  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function assignable(row) { return Boolean(row.reference) && !row.write_refusal; }
  function assigned(row) { return Object.keys(row.values || {}).length > 0 || Boolean(row.record_problem); }
  function plural(count, word) { return count + " " + word + (count === 1 ? "" : "s"); }
  function why(row) {
    return row.write_refusal ? row.write_refusal.message : "A selected line is not directly inside a Piping group.";
  }
  function labelled(text, control, className) {
    var label = ui.element("label", "piping-bar-field" + (className ? " " + className : ""), text);
    label.appendChild(control);
    return label;
  }
  /* A unit field's value as typed, or as last committed. */
  function read(field) { return field.editing ? field.parse() : { ok: true, value: field.baseline }; }

  /* `newGroup()` opens New Piping group; `notify(message, tone)` raises the panel's notice. */
  function AssignBar(session, send, guard, notify, newGroup) {
    var self = this;
    this.guard = guard; this.notify = notify;
    this.requests = request.channel(session, send, "piping-assign");
    this.root = ui.element("div", "piping-assign-bar");
    this.root.setAttribute("role", "region");
    this.root.setAttribute("aria-label", "Assign to selected lines");
    this.count = ui.element("span", "piping-assign-count");
    this.count.setAttribute("role", "status");
    this.type = ui.element("select");
    this.type.setAttribute("aria-label", "Pipe Type for selected lines");
    this.role = ui.element("select");
    this.role.setAttribute("aria-label", "Role for selected lines");
    shared.ROLES.forEach(function (role) { self.role.appendChild(ui.option(role.value, role.label)); });
    this.role.value = "trunk";
    this.multiplier = ui.element("input", "piping-multiplier");
    this.multiplier.setAttribute("inputmode", "numeric");
    this.multiplier.setAttribute("aria-label", "Multiplier");
    ui.tooltip(this.multiplier, "How many identical risers this trunk stands for");
    this.demand = ui.element("input");
    this.demand.type = "checkbox";
    this.demand.setAttribute("aria-label", "Demand recirculation");
    this.temperature = new unitFields.UnitField({ field: TEMPERATURE, value: DEFAULTS.water_temp_c,
      commitOnBlur: true, onCommit: function () { self.changed(); } });
    this.hours = new unitFields.UnitField({ field: HOURS, value: DEFAULTS.daily_period, commitOnBlur: true,
      onCommit: function () { self.changed(); } });
    this.fields = { multiplier: labelled("Multiplier", this.multiplier),
      demand_recirculation: labelled("Demand recirculation", this.demand, "piping-bar-check"),
      water_temp_c: labelled("Water temperature", this.temperature.root),
      daily_period: labelled("Hours a day", this.hours.root) };
    this.assign = ui.button("Assign", function () { self.submit("assign"); });
    this.clear = ui.button("Clear", function () { self.submit("clear"); });
    this.clear.setAttribute("aria-label", "Clear pipe from selected lines");
    this.reason = ui.element("span", "piping-assign-reason");
    this.tool = new pipeTool.PipeToolControls(session, send, function (reason) { notify(reason, "warning"); });
    this.tool.arm.addEventListener("click", function () {
      if (self.tool.active()) self.tool.stopTool(); else self.armTool();
    });
    this.newGroup = ui.button("+ New Piping group", function () {
      var reason = self.guard();
      if (reason) notify(reason, "warning"); else newGroup();
    });
    this.newGroup.className = "piping-new-group";
    [this.count, this.type, this.role, this.fields.multiplier, this.fields.demand_recirculation,
      this.fields.water_temp_c, this.fields.daily_period, this.assign, this.reason, this.clear, this.tool.arm,
      this.tool.stop, this.newGroup].forEach(function (node) { self.root.appendChild(node); });
    this.type.addEventListener("change", function () { self.chosen = self.type.value; self.changed(); });
    this.role.addEventListener("change", function () { self.changed(); });
    this.demand.addEventListener("change", function () { self.changed(); });
    this.multiplier.addEventListener("input", function () { self.paint(); });
    this.multiplier.addEventListener("change", function () { if (self.tool.active()) self.armTool(); });
    this.multiplier.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      event.preventDefault();
      if (self.tool.active()) self.armTool(); else self.submit("assign");
    });
    this.multiplier.value = "1";
    this.rows = []; this.writable = []; this.types = []; this.chosen = "";
  }
  /* A choice changed: a running tool takes it for its next gesture. */
  AssignBar.prototype.changed = function () {
    if (this.tool.active()) this.armTool();
    this.paint();
  };
  /* The role's values as they will be sent, or the reason one cannot be. */
  AssignBar.prototype.values = function () {
    var role = this.role.value, values = {}, problem = null, text = this.multiplier.value.trim();
    if (role === "trunk") {
      if (!/^\d+$/.test(text) || Number(text) < 1) problem = "Enter a whole multiplier of 1 or more.";
      values.multiplier = Number(text);
      values.demand_recirculation = this.demand.checked;
    } else if (role === "recirculation") {
      var temperature = read(this.temperature), hours = read(this.hours);
      if (!temperature.ok || temperature.value === null) problem = temperature.message || "Enter a water temperature.";
      else if (temperature.value < 0 || temperature.value > 100) {
        problem = "Enter a water temperature between freezing and boiling.";
      }
      else if (!hours.ok || hours.value === null) problem = hours.message || "Enter the hours a day.";
      else if (hours.value < 0 || hours.value > 24) problem = "Enter from 0 to 24 hours a day.";
      values.water_temp_c = temperature.value; values.daily_period = hours.value;
    }
    return { values: values, problem: problem };
  };
  /* Why the bar's choices cannot arm the tool or assign, or null. */
  AssignBar.prototype.armBlocked = function () {
    if (!this.types.length) return "Create a Pipe Type first.";
    if (!this.type.value) return "Choose a Pipe Type.";
    return this.values().problem;
  };
  /* Why Assign cannot run now, or null. */
  AssignBar.prototype.blocked = function () {
    if (this.unavailable) return this.unavailable;
    if (!this.rows.length) return "Select lines in a Piping group in SketchUp.";
    if (!this.writable.length) return why(this.rows[0]);
    return this.armBlocked();
  };
  AssignBar.prototype.params = function () {
    return Object.assign({ pipe_type_id: this.type.value, role: this.role.value }, this.values().values);
  };
  AssignBar.prototype.armTool = function () {
    if (this.disposed) return;
    var reason = this.guard();
    if (reason) { this.notify(reason, "warning"); return; }
    if (!this.armBlocked()) this.tool.choose(this.params());
    this.paint();
  };
  AssignBar.prototype.submit = function (action) {
    var self = this;
    if (this.disposed || this.requests.busy()) return;
    var reason = this.guard();
    if (reason) { this.notify(reason, "warning"); return; }
    var rows = action === "clear" ? this.writable.filter(assigned) : this.writable;
    if (action === "assign" ? this.blocked() : !rows.length) return;
    var params = action === "assign" ? this.params() : {};
    params.targets = rows.map(function (row) {
      return { reference: clone(row.reference), expected_values: clone(row.values || {}) };
    });
    var type = this.types.filter(function (entry) { return entry.id === params.pipe_type_id; })[0];
    var lines = plural(rows.length, "line");
    this.requests.run(shared.PREFIX + "pipes." + action, params, { onDone: function () {
      self.notify(action === "clear" ? "Cleared the pipe from " + lines + "." : "Assigned " +
        (type ? type.values.name : "the type") + " as " + shared.roleLabel(params.role).toLowerCase() + " to " +
        lines + ".", "success");
    } });
    this.paint();
  };
  AssignBar.prototype.busy = function () { return this.requests.busy(); };
  /* `types` are the Model's Pipe Type rows. */
  AssignBar.prototype.render = function (state, types) {
    if (this.disposed) return;
    var section = snapshot.section(state, shared.SELECTED), value = snapshot.value(state, shared.SELECTED);
    this.requests.consume(state);
    this.tool.render(state);
    this.unavailable = value ? null : snapshot.message(section || {}, "The selected lines cannot be read.");
    this.rows = value ? value.edges : [];
    this.writable = this.rows.filter(assignable);
    this.types = types.slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name) || ui.compareText(a.id, b.id);
    });
    // A new selection whose lines share a type, role or value starts from it; otherwise the user's choice stands.
    var writable = this.writable, key = JSON.stringify(writable.map(function (row) { return [row.path, row.values]; }));
    function common(field) {
      var held = writable.map(function (row) { return (row.values || {})[field]; });
      return held.length && held[0] !== undefined && held.every(function (item) { return item === held[0]; }) ?
        held[0] : undefined;
    }
    // A running tool keeps what it was armed with: the bar then shows that, below, not the selection's.
    if (key !== this.key && !this.tool.active()) {
      this.key = key;
      this.apply({ pipe_type_id: common("pipe_type_id"), role: common("role"), multiplier: common("multiplier"),
        demand_recirculation: common("demand_recirculation"), water_temp_c: common("water_temp_c"),
        daily_period: common("daily_period") });
    }
    // A running tool shows what it assigns, unless a change to it is on its way.
    var armed = JSON.stringify(this.tool.state);
    if (this.tool.active() && !this.tool.busy() && this.armed !== armed) {
      this.armed = armed;
      this.apply(Object.assign({ pipe_type_id: this.tool.state.pipe_type_id, role: this.tool.state.role },
        this.tool.state.values));
    }
    var catalog = JSON.stringify(this.types.map(function (type) { return [type.id, type.values.name]; }));
    if (catalog !== this.catalog) {
      this.catalog = catalog;
      this.type.replaceChildren(ui.option("", "Choose a type"));
      this.types.forEach(function (type) { this.type.appendChild(ui.option(type.id, type.values.name)); }, this);
    }
    this.type.value = this.types.some(function (type) { return type.id === this.chosen; }, this) ? this.chosen : "";
    this.paint();
  };
  /* Takes the given choices; an undefined one leaves the bar's own. */
  AssignBar.prototype.apply = function (chosen) {
    if (chosen.pipe_type_id !== undefined) this.chosen = chosen.pipe_type_id;
    if (chosen.role !== undefined) this.role.value = chosen.role;
    if (chosen.multiplier !== undefined && document.activeElement !== this.multiplier) {
      this.multiplier.value = String(chosen.multiplier);
    }
    if (chosen.demand_recirculation !== undefined) this.demand.checked = chosen.demand_recirculation;
    if (chosen.water_temp_c !== undefined) this.temperature.setValue(chosen.water_temp_c);
    if (chosen.daily_period !== undefined) this.hours.setValue(chosen.daily_period);
  };
  AssignBar.prototype.paint = function () {
    var self = this, busy = this.requests.busy() || this.tool.busy(), total = this.rows.length;
    var writable = this.writable.length, role = this.role.value;
    var text = this.unavailable ? "Selected lines" : !total ? "No lines selected" :
      plural(total, "line") + " selected" + (writable < total ? ", " + writable + " assignable" : "");
    if (this.count.textContent !== text) this.count.textContent = text;
    Object.keys(this.fields).forEach(function (key) {
      self.fields[key].hidden = ROLE_KEYS[role].indexOf(key) < 0;
    });
    var blocked = this.blocked();
    var reason = blocked || (writable < total ? plural(total - writable, "selected line") + " will be left as " +
      (total - writable === 1 ? "it is" : "they are") + ": " + why(this.rows.filter(function (row) {
        return !assignable(row);
      })[0]) : null);
    this.reason.hidden = !reason;
    if (reason && this.reason._reason !== reason) {
      this.reason._reason = reason;
      this.reason.replaceChildren(ui.reasonButton(blocked ? "Assign" : "Assign to every selected line", reason));
    }
    [this.type, this.role, this.multiplier, this.demand].forEach(function (control) { control.disabled = busy; });
    this.temperature.setDisabled(busy); this.hours.setDisabled(busy);
    this.multiplier.setAttribute("aria-invalid", String(role === "trunk" && Boolean(this.values().problem)));
    this.assign.disabled = busy || Boolean(blocked);
    this.clear.disabled = busy || !this.writable.some(assigned);
    var type = this.types.filter(function (entry) { return entry.id === self.type.value; })[0];
    this.tool.paint(this.armBlocked(), (type ? type.values.name : "the type") + " as " +
      shared.roleLabel(role).toLowerCase());
  };
  AssignBar.prototype.dispose = function () {
    this.disposed = true; this.requests.reset(); this.tool.dispose();
    this.temperature.dispose(); this.hours.dispose();
  };
  return { AssignBar: AssignBar, assignable: assignable };
});
