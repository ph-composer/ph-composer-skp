/* The assign bar a line group's pill opens with, in the shape of an edge feature's (line_groups/shared.js has the
   spec): what SketchUp has selected and how many of those lines a write can reach, the feature's type, the feature's
   own values, Assign and Clear, and New <group> last. It always shows, so selecting never moves what is under it;
   with nothing to assign, Assign is disabled and its reason sits beside it. Each press is one <noun>s.assign or
   <noun>s.clear over the lines as the selection read them, one Undo step.

   A feature's bar calls Bar from its constructor and inherits from it, places its own controls with `place`, and
   gives `params()` (what Assign sends beside the targets), `blocked()` beyond the base's, `done(params, type,
   lines)` (the success notice) and `render(state, types)`, which calls `read` and then `paint`. */
PhComposerUI.define("line_groups/assign_bar", ["request", "snapshot", "workspace"], function (request, snapshot, ui) {
  "use strict";
  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  function assignable(row) { return Boolean(row.reference) && !row.write_refusal; }
  function assigned(row) { return Object.keys(row.values || {}).length > 0 || Boolean(row.record_problem); }
  function plural(count, word) { return count + " " + word + (count === 1 ? "" : "s"); }
  function labelled(text, control, className) {
    var label = ui.element("label", "line-group-bar-field" + (className ? " " + className : ""), text);
    label.appendChild(control);
    return label;
  }

  /* `guard()` names what holds the pill; `notify(message, tone)` raises the panel's notice; `newGroup()` opens New
     <group>. */
  function Bar(session, send, spec, guard, notify, newGroup) {
    var self = this;
    this.spec = spec; this.guard = guard; this.notify = notify;
    this.requests = request.channel(session, send, spec.key + "-assign");
    this.root = ui.element("div", "line-group-bar");
    this.root.setAttribute("role", "region");
    this.root.setAttribute("aria-label", "Assign to selected lines");
    this.count = ui.element("span", "line-group-bar-count");
    this.count.setAttribute("role", "status");
    this.type = ui.element("select");
    this.type.setAttribute("aria-label", spec.typeLabel + " for selected lines");
    this.type.addEventListener("change", function () { self.chosen = self.type.value; self.changed(); });
    this.assign = ui.button("Assign", function () { self.submit("assign"); });
    this.clear = ui.button("Clear", function () { self.submit("clear"); });
    this.clear.setAttribute("aria-label", "Clear " + spec.noun + " from selected lines");
    this.reason = ui.element("span", "line-group-bar-reason");
    this.newGroup = ui.button("+ New " + spec.label, function () {
      var reason = self.guard();
      if (reason) notify(reason, "warning"); else newGroup();
    });
    this.newGroup.className = "line-group-new";
    this.rows = []; this.writable = []; this.types = []; this.chosen = "";
  }
  /* Lays the bar out: the count and the type, the feature's `middle` controls, Assign with its reason and Clear,
     the feature's `end` controls, then New <group>. */
  Bar.prototype.place = function (middle, end) {
    [this.count, this.type].concat(middle, [this.assign, this.reason, this.clear], end, [this.newGroup])
      .forEach(function (node) { this.root.appendChild(node); }, this);
  };
  Bar.prototype.changed = function () { this.paint(); };
  Bar.prototype.why = function (row) {
    return row.write_refusal ? row.write_refusal.message : "A selected line is not directly inside a " +
      this.spec.label + ".";
  };
  /* Why the chosen type cannot be assigned, or null. */
  Bar.prototype.typeBlocked = function () {
    if (!this.types.length) return "Create a " + this.spec.typeLabel + " first.";
    return this.type.value ? null : "Choose a " + this.spec.typeLabel + ".";
  };
  /* Why Assign cannot run for the selection, or null; a feature adds its own values' reason after this. */
  Bar.prototype.selectionBlocked = function () {
    if (this.unavailable) return this.unavailable;
    if (!this.rows.length) return "Select lines in a " + this.spec.label + " in SketchUp.";
    return this.writable.length ? null : this.why(this.rows[0]);
  };
  Bar.prototype.chosenType = function () {
    return this.types.filter(function (entry) { return entry.id === this.type.value; }, this)[0] || null;
  };
  Bar.prototype.submit = function (action) {
    var self = this;
    if (this.disposed || this.requests.busy()) return;
    var reason = this.guard();
    if (reason) { this.notify(reason, "warning"); return; }
    var rows = action === "clear" ? this.writable.filter(assigned) : this.writable;
    if (action === "assign" ? this.blocked() : !rows.length) return;
    var params = action === "assign" ? this.params() : {}, type = this.chosenType();
    params.targets = rows.map(function (row) {
      return { reference: clone(row.reference), expected_values: clone(row.values || {}) };
    });
    var lines = plural(rows.length, "line");
    this.requests.run(this.spec.prefix + this.spec.noun + "s." + action, params, { onDone: function () {
      self.notify(action === "clear" ? "Cleared the " + self.spec.noun + " from " + lines + "." :
        self.done(params, type ? type.values.name : "the type", lines), "success");
    } });
    this.paint();
  };
  Bar.prototype.busy = function () { return this.requests.busy(); };
  /* Reads this state's selection and the Model's type rows (`types`) and settles a finished write. */
  Bar.prototype.read = function (state, types) {
    var selected = this.spec.selected, section = snapshot.section(state, selected);
    var value = snapshot.value(state, selected);
    this.state = state; this.typeRows = types;
    this.requests.consume(state);
    this.unavailable = value ? null : snapshot.message(section || {}, "The selected lines cannot be read.");
    this.rows = value ? value.edges : [];
    this.writable = this.rows.filter(assignable);
    this.types = types.slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name) || ui.compareText(a.id, b.id);
    });
  };
  /* The writable lines and their values, so a feature can tell a new selection from a repaint. */
  Bar.prototype.selectionKey = function () {
    return JSON.stringify(this.writable.map(function (row) { return [row.path, row.values]; }));
  };
  /* A value every writable line holds alike, or undefined. */
  Bar.prototype.common = function (field) {
    var held = this.writable.map(function (row) { return (row.values || {})[field]; });
    return held.length && held[0] !== undefined && held.every(function (item) { return item === held[0]; }) ?
      held[0] : undefined;
  };
  /* The type choices, rebuilt only when the catalog changes, and the chosen one while it exists. */
  Bar.prototype.paintTypes = function () {
    var catalog = JSON.stringify(this.types.map(function (type) { return [type.id, type.values.name]; }));
    if (catalog !== this.catalog) {
      this.catalog = catalog;
      this.type.replaceChildren(ui.option("", "Choose a type"));
      this.types.forEach(function (type) { this.type.appendChild(ui.option(type.id, type.values.name)); }, this);
    }
    this.type.value = this.types.some(function (type) { return type.id === this.chosen; }, this) ? this.chosen : "";
  };
  /* The count, Assign's reason, Assign, Clear and the type, from the state read; answers why Assign is blocked. */
  Bar.prototype.paintBase = function (busy) {
    var self = this, total = this.rows.length, writable = this.writable.length;
    var text = this.unavailable ? "Selected lines" : !total ? "No lines selected" :
      plural(total, "line") + " selected" + (writable < total ? ", " + writable + " assignable" : "");
    if (this.count.textContent !== text) this.count.textContent = text;
    var blocked = this.blocked();
    var reason = blocked || (writable < total ? plural(total - writable, "selected line") + " will be left as " +
      (total - writable === 1 ? "it is" : "they are") + ": " + this.why(this.rows.filter(function (row) {
        return !assignable(row);
      })[0]) : null);
    this.reason.hidden = !reason;
    if (reason && this.reason._reason !== reason) {
      this.reason._reason = reason;
      this.reason.replaceChildren(ui.reasonButton(blocked ? "Assign" : "Assign to every selected line", reason));
    }
    this.type.disabled = busy;
    this.assign.disabled = busy || Boolean(blocked);
    this.clear.disabled = busy || !self.writable.some(assigned);
    return blocked;
  };
  Bar.prototype.dispose = function () { this.disposed = true; this.requests.reset(); };
  return { Bar: Bar, labelled: labelled };
});
