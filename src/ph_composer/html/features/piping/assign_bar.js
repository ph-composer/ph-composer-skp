/* The assign bar at the top of the Piping pill, on the shared line-group bar (html/line_groups/assign_bar.js): a Pipe
   Type, a role and only that role's values (a trunk's Multiplier and Demand recirculation, a recirculation pipe's
   Water temperature and Hours a day), Assign and Clear. The same values arm the pipe tool, the secondary route. */
PhComposerUI.define("features/piping/assign_bar", ["workspace", "fields", "unit_field", "line_groups/assign_bar",
  "features/piping/shared", "features/piping/pipe_tool"],
function (ui, fields, unitFields, lineBars, shared, pipeTool) {
  "use strict";
  var TEMPERATURE = fields.with(fields.TEMPERATURE_C, { label: "Water temperature" });
  var HOURS = fields.with(fields.HOURS_PER_DAY, { label: "Hours a day" });
  var DEFAULTS = { multiplier: 1, demand_recirculation: false, water_temp_c: 60, daily_period: 24 };
  var ROLE_KEYS = { trunk: ["multiplier", "demand_recirculation"], branch: [], twig: [],
    recirculation: ["water_temp_c", "daily_period"] };
  var Bar = lineBars.Bar, labelled = lineBars.labelled;
  /* A unit field's value as typed, or as last committed. */
  function read(field) { return field.editing ? field.parse() : { ok: true, value: field.baseline }; }

  /* `newGroup()` opens New Piping group; `notify(message, tone)` raises the panel's notice. */
  function AssignBar(session, send, guard, notify, newGroup) {
    var self = this;
    Bar.call(this, session, send, shared.SPEC, guard, notify, newGroup);
    this.role = ui.element("select");
    this.role.setAttribute("aria-label", "Role for selected lines");
    shared.ROLES.forEach(function (role) { self.role.appendChild(ui.option(role.value, role.label)); });
    this.role.value = "trunk";
    this.multiplier = ui.element("input", "line-group-number");
    this.multiplier.setAttribute("inputmode", "numeric");
    this.multiplier.setAttribute("aria-label", "Multiplier");
    ui.tooltip(this.multiplier, "How many identical risers this trunk stands for");
    this.demand = ui.element("input");
    this.demand.type = "checkbox";
    this.demand.setAttribute("aria-label", "Demand recirculation");
    // Escape puts a field back at its value, so Assign and its reason follow it.
    this.temperature = new unitFields.UnitField({ field: TEMPERATURE, value: DEFAULTS.water_temp_c,
      commitOnBlur: true, onCommit: function () { self.changed(); }, onCancel: function () { self.paint(); } });
    this.hours = new unitFields.UnitField({ field: HOURS, value: DEFAULTS.daily_period, commitOnBlur: true,
      onCommit: function () { self.changed(); }, onCancel: function () { self.paint(); } });
    this.fields = { multiplier: labelled("Multiplier", this.multiplier),
      demand_recirculation: labelled("Demand recirculation", this.demand),
      water_temp_c: labelled("Water temperature", this.temperature.root),
      daily_period: labelled("Hours a day", this.hours.root) };
    this.tool = new pipeTool.PipeToolControls(session, send, function (reason) {
      // The tool keeps what it was armed with, so the bar shows that again.
      self.armed = null;
      notify(reason, "warning");
    });
    this.tool.arm.addEventListener("click", function () {
      if (self.tool.active()) self.tool.stopTool(); else self.armTool();
    });
    this.place([this.role, this.fields.multiplier, this.fields.demand_recirculation, this.fields.water_temp_c,
      this.fields.daily_period], [this.tool.arm, this.tool.stop]);
    this.role.addEventListener("change", function () { self.changed(); });
    this.demand.addEventListener("change", function () { self.changed(); });
    // Typing repaints, so Assign follows the text; the tool re-arms only on a commit.
    [this.multiplier, this.temperature.input, this.hours.input].forEach(function (input) {
      input.addEventListener("input", function () { self.paint(); });
    });
    this.multiplier.addEventListener("change", function () { if (self.tool.active()) self.armTool(); });
    // A tool armed while the field had focus shows its multiplier once the field is left unchanged.
    this.multiplier.addEventListener("blur", function () {
      if (self.state && self.tool.active() && self.armed !== JSON.stringify(self.tool.state)) {
        self.render(self.state, self.typeRows);
      }
    });
    this.multiplier.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") return;
      event.preventDefault();
      if (self.tool.active()) self.armTool(); else self.submit("assign");
    });
    this.multiplier.value = "1";
  }
  AssignBar.prototype = Object.create(Bar.prototype);
  AssignBar.prototype.constructor = AssignBar;
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
  AssignBar.prototype.armBlocked = function () { return this.typeBlocked() || this.values().problem; };
  /* Why Assign cannot run now, or null. */
  AssignBar.prototype.blocked = function () { return this.selectionBlocked() || this.armBlocked(); };
  AssignBar.prototype.params = function () {
    return Object.assign({ pipe_type_id: this.type.value, role: this.role.value }, this.values().values);
  };
  AssignBar.prototype.done = function (params, type, lines) {
    return "Assigned " + type + " as " + shared.roleLabel(params.role).toLowerCase() + " to " + lines + ".";
  };
  AssignBar.prototype.armTool = function () {
    if (this.disposed) return;
    var reason = this.guard() || this.armBlocked();
    if (reason && this.tool.active()) {
      // A change the tool cannot take leaves it assigning what it was armed with, which the bar shows again.
      this.notify("The pipe tool keeps its last values: " + reason, "warning");
      this.armed = null;
      this.render(this.state, this.typeRows);
      return;
    }
    if (reason) { if (this.guard()) this.notify(reason, "warning"); return; }
    this.tool.choose(this.params());
    this.paint();
  };
  /* `types` are the Model's Pipe Type rows. */
  AssignBar.prototype.render = function (state, types) {
    if (this.disposed) return;
    this.read(state, types);
    this.tool.render(state);
    // A new selection whose lines share a type, role or value starts from it; otherwise the user's choice stands.
    // A running tool keeps what it was armed with: the bar then shows that, below, not the selection's.
    var key = this.selectionKey();
    if (key !== this.key && !this.tool.active()) {
      this.key = key;
      this.apply({ pipe_type_id: this.common("pipe_type_id"), role: this.common("role"),
        multiplier: this.common("multiplier"), demand_recirculation: this.common("demand_recirculation"),
        water_temp_c: this.common("water_temp_c"), daily_period: this.common("daily_period") });
    }
    // A running tool shows what it assigns, unless a change to it is on its way. It counts as shown once every
    // field shows it: a field with focus keeps the user's text until they leave it.
    var armed = JSON.stringify(this.tool.state), role = this.tool.state.role;
    if (this.tool.active() && !this.tool.busy() && this.armed !== armed) {
      // A value of its role the tool was armed without takes its default on a new pipe, so the bar shows the
      // default; another role's values are left as the user set them.
      var defaults = {};
      (ROLE_KEYS[role] || []).forEach(function (key) { defaults[key] = DEFAULTS[key]; });
      // A field held back by focus leaves nothing marked shown, so a later state is applied whole.
      this.armed = this.apply(Object.assign(defaults, { pipe_type_id: this.tool.state.pipe_type_id, role: role },
        this.tool.state.values)) ? armed : null;
    }
    this.paintTypes();
    this.paint();
  };
  /* Takes the given choices; an undefined one leaves the bar's own. Answers false when Multiplier has focus and
     so still shows another value. */
  AssignBar.prototype.apply = function (chosen) {
    var multiplier = chosen.multiplier === undefined ? undefined : String(chosen.multiplier);
    var held = multiplier !== undefined && document.activeElement === this.multiplier &&
      this.multiplier.value !== multiplier;
    if (chosen.pipe_type_id !== undefined) this.chosen = chosen.pipe_type_id;
    // A stored role this version does not know is left for Assign or Clear to replace.
    if (chosen.role !== undefined && ROLE_KEYS[chosen.role]) this.role.value = chosen.role;
    if (multiplier !== undefined && !held) this.multiplier.value = multiplier;
    if (chosen.demand_recirculation !== undefined) this.demand.checked = chosen.demand_recirculation;
    if (chosen.water_temp_c !== undefined) this.temperature.setValue(chosen.water_temp_c);
    if (chosen.daily_period !== undefined) this.hours.setValue(chosen.daily_period);
    return !held;
  };
  AssignBar.prototype.paint = function () {
    var self = this, busy = this.requests.busy() || this.tool.busy(), role = this.role.value;
    Object.keys(this.fields).forEach(function (key) {
      self.fields[key].hidden = (ROLE_KEYS[role] || []).indexOf(key) < 0;
    });
    this.paintBase(busy);
    [this.role, this.multiplier, this.demand].forEach(function (control) { control.disabled = busy; });
    this.temperature.setDisabled(busy); this.hours.setDisabled(busy);
    this.multiplier.setAttribute("aria-invalid", String(role === "trunk" && Boolean(this.values().problem)));
    var type = this.chosenType();
    this.tool.paint(this.armBlocked(), (type ? type.values.name : "the type") + " as " +
      shared.roleLabel(role).toLowerCase());
  };
  AssignBar.prototype.dispose = function () {
    Bar.prototype.dispose.call(this); this.tool.dispose();
    this.temperature.dispose(); this.hours.dispose();
  };
  return { AssignBar: AssignBar };
});
