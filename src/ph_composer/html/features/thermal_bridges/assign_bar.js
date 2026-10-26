/* The assign bar above the Types table: what SketchUp has selected, how many of those Edges a write can reach,
   and a type, a quantity, Assign and Clear for them. It always shows, so selecting never moves the table; with
   nothing to assign, Assign is disabled and its reason sits beside it. Each press is one public action and one
   Undo step over the Edges as the selection read them, so an Edge changed since refuses rather than writing. */
PhComposerUI.define("features/thermal_bridges/assign_bar", ["request", "snapshot", "workspace",
  "features/thermal_bridges/shared"], function (request, snapshot, ui, shared) {
  "use strict";
  var REASONS = { outside_zone: "it is not inside a Zone", not_found: "it could not be found in the Model",
    not_a_drawing_element: "it is not a drawing element", cutting_instance: "a cutting component holds it",
    nested_container: "a Group or component inside its Zone holds it" };
  function clone(value) { return JSON.parse(JSON.stringify(value)); }
  /* The same rule the right-click menu applies (Assignment::Selection.assignable?). */
  function assignable(row) { return Boolean(row.reference) && !row.write_refusal; }
  /* An Edge holding an assignment, an invalid one included: it reads with empty values and its problem, and
     Clear is how it goes. */
  function assigned(row) { return Object.keys(row.values || {}).length > 0 || Boolean(row.record_problem); }
  function plural(count, word) { return count + " " + word + (count === 1 ? "" : "s"); }
  function why(row) {
    if (row.write_refusal) return row.write_refusal.message;
    return "A selected Edge cannot be assigned because " + (REASONS[row.reason] || "no Zone holds it") + ".";
  }

  /* `notify(message, tone)` raises the panel's notice: a refusal's reason, or the confirmation of a write. */
  function AssignBar(session, send, guard, refused, notify) {
    var self = this;
    this.guard = guard; this.refused = refused; this.notify = notify;
    this.requests = request.channel(session, send, "thermal-bridge-assign");
    this.root = ui.element("div", "tb-assign-bar");
    this.root.setAttribute("role", "region");
    this.root.setAttribute("aria-label", "Assign to selected Edges");
    this.count = ui.element("span", "tb-assign-count");
    this.count.setAttribute("role", "status");
    this.type = ui.element("select");
    this.type.setAttribute("aria-label", "Thermal Bridge Type for selected Edges");
    this.quantity = ui.element("input", "tb-assign-quantity");
    this.quantity.setAttribute("aria-label", "Quantity for selected Edges");
    this.quantity.setAttribute("inputmode", "decimal");
    ui.tooltip(this.quantity, "How many times each Edge counts, such as 2 for a junction built twice");
    this.quantity.value = "1";
    this.assign = ui.button("Assign", function () { self.submit("assign"); });
    this.clear = ui.button("Clear", function () { self.submit("clear"); });
    this.clear.setAttribute("aria-label", "Clear thermal bridge from selected Edges");
    this.reason = ui.element("span", "tb-assign-reason");
    var quantity = ui.element("label", "tb-assign-field", "Quantity");
    quantity.appendChild(this.quantity);
    [this.count, this.type, quantity, this.assign, this.clear, this.reason].forEach(function (node) {
      self.root.appendChild(node);
    });
    this.type.addEventListener("change", function () { self.chosen = self.type.value; self.paint(); });
    this.quantity.addEventListener("input", function () { self.paint(); });
    this.quantity.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); self.submit("assign"); }
    });
    this.rows = []; this.types = []; this.chosen = "";
  }
  /* A positive number, or null. */
  AssignBar.prototype.quantityValue = function () {
    var text = this.quantity.value.trim(), value = Number(text);
    return text && Number.isFinite(value) && value > 0 ? value : null;
  };
  /* Why Assign cannot run now, or null. */
  AssignBar.prototype.blocked = function () {
    if (this.unavailable) return this.unavailable;
    if (!this.rows.length) return "Select Edges inside a Zone in SketchUp.";
    if (!this.writable.length) return why(this.rows[0]);
    if (!this.types.length) return "Create a Thermal Bridge Type first.";
    if (!this.type.value) return "Choose a Thermal Bridge Type.";
    if (this.quantityValue() === null) return "Enter a quantity greater than zero.";
    return null;
  };
  AssignBar.prototype.submit = function (action) {
    var self = this;
    if (this.disposed || this.requests.busy()) return;
    var reason = this.guard && this.guard();
    if (reason) { this.refused(reason); return; }
    var rows = action === "clear" ? this.writable.filter(assigned) : this.writable;
    if (action === "assign" ? this.blocked() : !rows.length) return;
    var params = { targets: rows.map(function (row) {
      return { reference: clone(row.reference), expected_values: clone(row.values || {}) };
    }) };
    if (action === "assign") {
      params.thermal_bridge_type_id = this.type.value;
      params.quantity = this.quantityValue();
    }
    var type = this.types.filter(function (entry) { return entry.id === params.thermal_bridge_type_id; })[0];
    var edges = plural(rows.length, "Edge");
    // A refusal already reaches the user through the panel's notice for action results.
    this.requests.run(shared.PREFIX + "edges." + action, params, { onDone: function () {
      self.notify(action === "clear" ? "Cleared the thermal bridge from " + edges + "." :
        "Assigned " + (type ? type.values.name : "the type") + " to " + edges + ".", "success");
    } });
    this.paint();
  };
  AssignBar.prototype.busy = function () { return this.requests.busy(); };
  /* `types` are the Thermal Bridge Type rows the Types table shows. A refusal reaches the user through the
     panel's own notice for action results, so the bar only settles its request. */
  AssignBar.prototype.render = function (state, types) {
    if (this.disposed) return;
    var section = snapshot.section(state, shared.SELECTED), value = snapshot.value(state, shared.SELECTED);
    this.requests.consume(state);
    this.unavailable = value ? null : snapshot.message(section || {}, "The selected Edges cannot be read.");
    this.rows = value ? value.edges : [];
    this.writable = this.rows.filter(assignable);
    this.types = types.slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name) || ui.compareText(a.id, b.id);
    });
    var writable = this.writable;
    function common(field, fallback) {
      var held = writable.map(function (row) { return (row.values || {})[field]; });
      return held.length && held[0] !== undefined && held.every(function (item) { return item === held[0]; }) ?
        held[0] : fallback;
    }
    // A new selection starts from what its Edges hold; the user's choice stands until the selection changes.
    var key = JSON.stringify(this.writable.map(function (row) { return [row.path, row.values]; }));
    if (key !== this.key) {
      this.key = key; this.chosen = common("thermal_bridge_type_id", "");
      this.quantity.value = String(common("quantity", 1));
    }
    // Rebuilt only when the catalog changes, so a repaint never closes an open list.
    var catalog = JSON.stringify(this.types.map(function (type) { return [type.id, type.values.name]; }));
    if (catalog !== this.catalog) {
      this.catalog = catalog;
      this.type.replaceChildren(ui.option("", "Choose a type"));
      this.types.forEach(function (type) { this.type.appendChild(ui.option(type.id, type.values.name)); }, this);
    }
    this.type.value = this.types.some(function (type) { return type.id === this.chosen; }, this) ? this.chosen : "";
    this.paint();
  };
  AssignBar.prototype.paint = function () {
    var busy = this.requests.busy(), total = this.rows.length, writable = this.writable.length;
    var text = this.unavailable ? "Selected Edges" : !total ? "No Edges selected" :
      plural(total, "Edge") + " selected" + (writable < total ? ", " + writable + " assignable" : "");
    if (this.count.textContent !== text) this.count.textContent = text;
    var blocked = this.blocked();
    // The reason Assign waits for, or why some selected Edges are left out of an Assign that can run.
    var reason = blocked || (writable < total ? plural(total - writable, "selected Edge") + " will be left as " +
      (total - writable === 1 ? "it is" : "they are") + ": " + why(this.rows.filter(function (row) {
        return !assignable(row);
      })[0]) : null);
    this.reason.hidden = !reason;
    if (reason && this.reason._reason !== reason) {
      this.reason._reason = reason;
      this.reason.replaceChildren(ui.reasonButton(blocked ? "Assign" : "Assign to every selected Edge", reason));
    }
    this.type.disabled = busy || !writable || !this.types.length;
    this.quantity.disabled = busy || !writable;
    this.quantity.setAttribute("aria-invalid", String(Boolean(writable) && this.quantityValue() === null));
    this.assign.disabled = busy || Boolean(blocked);
    this.clear.disabled = busy || !this.writable.some(assigned);
  };
  AssignBar.prototype.dispose = function () { this.disposed = true; this.requests.reset(); };
  return { AssignBar: AssignBar, assignable: assignable };
});
