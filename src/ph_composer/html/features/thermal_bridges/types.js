/* The Types subtab: the Model's Thermal Bridge Types as an editable inventory under the assign bar. A type is
   only numbers, so New and Duplicate ask in the shared form dialog first; Delete offers a replacement, or
   clearing, for the Edges using it. Used length comes from the last schedule read, since it walks the Model. */
PhComposerUI.define("features/thermal_bridges/types", ["panel", "snapshot", "workspace", "fields", "units",
  "unit_preferences", "unit_field", "record_form", "inventory", "inventory_forms", "features/thermal_bridges/shared",
  "features/thermal_bridges/assign_bar"],
function (panel, snapshot, ui, fields, units, preferences, unitFields, RecordForm, inventories, forms, shared,
  bars) {
  "use strict";
  var LABEL = "Thermal Bridge Type", NAME_HINT = "Enter a name to create the type.";
  var PSI = fields.with(fields.LINEAR_PSI, { label: "ψ-value", allowBlank: true });
  var quantities = { psi_w_mk: PSI, length_m: fields.LENGTH_M };
  var columns = [["name", "Name"], ["color", "Color"], ["psi_w_mk", "ψ-value"], ["group", "Group"],
    ["length_m", "Used length"], ["notes", "Notes"], ["datasheet", "Datasheet"]];

  /* New Thermal Bridge Type: a name, and the psi-value and group it will most often need at once. */
  function TypeForm(session, send, changed) {
    RecordForm.call(this, session, send, { title: "New " + LABEL, action: shared.TYPES + ".create",
      label: "thermal-bridge-type-create", submitLabel: "Create " + LABEL, pendingText: "Creating...",
      failureText: "The " + LABEL + " was not created.", changed: changed });
    this.name = forms.labelled(this.form, "Name", ui.element("input"));
    RecordForm.required(this.name.parentNode, this.name);
    this.psi = new unitFields.UnitField({ input: ui.element("input"), field: PSI });
    this.psi.input.setAttribute("aria-label", "ψ-value");
    var psi = ui.element("label", "", "ψ-value");
    psi.appendChild(this.psi.root);
    this.form.appendChild(psi);
    this.group = forms.labelled(this.form, "Group", ui.element("select"));
    shared.GROUPS.forEach(function (group) { this.group.appendChild(ui.option(group.value, group.label)); }, this);
    this.notes = forms.labelled(this.form, "Notes", ui.element("input"));
    var self = this;
    this.name.addEventListener("input", function () {
      if (!self.busy() && self.error.textContent !== NAME_HINT) self.error.textContent = "";
      self.updateButton();
    });
    // Enter in any field creates, the ψ-value's unit field included, which keeps Enter for itself.
    [this.name, this.psi.input, this.notes].forEach(function (input) {
      input.addEventListener("keydown", function (event) {
        if (event.key !== "Enter") return;
        event.preventDefault();
        event.stopImmediatePropagation();
        self.submit();
      }, true);
    });
    this.finish();
  }
  RecordForm.extend(TypeForm);
  /* A disabled Create says what it waits for, in the hint tone; a pending or refused request keeps the status
     line for itself. */
  TypeForm.prototype.updateButton = function () {
    var unnamed = !this.name.value.trim();
    this.submitButton.disabled = !this.enabled || this.busy() || unnamed;
    if (unnamed && !this.busy() && !this.error.textContent) this.error.textContent = NAME_HINT;
    else if (!unnamed && this.error.textContent === NAME_HINT) this.error.textContent = "";
    this.error.classList.toggle("phc-form-hint", this.error.textContent === NAME_HINT);
  };
  TypeForm.prototype.open = function () {
    if (!this.enabled) return;
    this.name.value = ""; this.notes.value = ""; this.group.value = shared.GROUPS[0].value;
    this.psi.cancel(); this.psi.setValue(null);
    this.error.textContent = ""; this.updateButton();
    this.show(); this.name.focus();
  };
  TypeForm.prototype.submit = function () {
    if (!this.enabled || this.busy()) return;
    var name = this.name.value.trim(), psi = this.psi.parse();
    if (!name) { this.updateButton(); return; }
    if (!psi.ok) { this.error.textContent = psi.message; this.error.classList.remove("phc-form-hint"); return; }
    this.run({ values: { name: name, psi_w_mk: psi.value, group: this.group.value, notes: this.notes.value.trim() } });
  };
  TypeForm.prototype.refresh = function (state) {
    var outcome = forms.refreshForm(this, state, shared.TYPES);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    else if (outcome) this.updateButton();
  };
  TypeForm.prototype.dispose = function () { this.enabled = false; this.withdraw(); this.psi.dispose(); };

  function Types(root, session, send, read, changed) {
    var self = this;
    this.read = read; this.records = [];
    function allowed() {
      var reason = self.guard();
      if (reason) panel.notify(reason, "warning");
      return !reason;
    }
    this.newType = new TypeForm(session, send, changed);
    this.duplicate = new forms.DuplicateForm(session, send, changed, { section: shared.TYPES, label: LABEL });
    this.replacement = new forms.ReplacementForm(session, send, changed, { section: shared.TYPES, label: LABEL,
      replacement: true, allowClear: true, usage: function (state, id) { return self.usage(state, id); } });
    this.color = new forms.ColorForm(session, send, shared.TYPES + ".update", changed);
    this.forms = [this.newType, this.duplicate, this.replacement, this.color];
    this.create = ui.button("+ New " + LABEL, function () { if (allowed()) self.newType.open(); });
    this.bar = new bars.AssignBar(session, send, function () { return self.assignGuard(); }, function (reason) {
      panel.notify(reason, "warning");
    });
    root.appendChild(this.bar.root);
    var table = ui.element("div", "tb-types-table");
    root.appendChild(table);
    this.inventory = new inventories.Inventory(table, session, send, panel.notify, changed, {
      tableId: shared.TYPES, section: shared.TYPES, action: shared.TYPES + ".update", label: LABEL,
      columns: columns, editable: ["name", "psi_w_mk", "group", "notes"], quantities: quantities,
      selectFields: { group: shared.GROUPS }, groups: [["group", "Group"]], notice: panel.notify,
      columnMenus: { sort: ["name", "psi_w_mk", "group", "length_m", "notes"], filter: ["group"] },
      value: function (record, field) {
        if (field === "length_m") { var totals = self.read.totals(record.id); return totals && totals.length_m; }
        if (field === "datasheet") return (record.values.datasheet_links || [])[0] || "";
        return record.values[field];
      },
      group: function (record) { return { label: shared.groupLabel(record.values.group) }; },
      actions: function (row) { return [
        { id: "duplicate", icon: "duplicate", label: "Duplicate " + row.record.values.name },
        { id: "delete", icon: "delete", label: "Delete " + row.record.values.name }]; },
      actionFor: function (row, command) {
        if (!allowed()) return;
        if (command.id === "duplicate") self.duplicate.open(row.record);
        else self.replacement.open(row.record, self.records);
      },
      cell: function (td, row, field, value) {
        if (field === "color") { forms.colorCell(td, row.record, self.color, allowed); return true; }
        if (field === "length_m") { self.lengthCell(td, value); return true; }
        if (field === "datasheet") { self.datasheetCell(td, row.record); return true; }
        return false;
      } });
    this.forms.forEach(function (form) { root.appendChild(form.root); });
  }
  /* The Edges using a type, from a read of the Model as it is now. Unknown after an edit since the last read, or
     while assigned Edges sit outside every run (which the read does not count by type), so Delete then asks for
     a replacement or clearing, which an unused type takes as harmlessly. */
  Types.prototype.usage = function (state, id) {
    var value = this.read.value();
    var stray = value && value.edge_finding_total + value.unreadable_total > 0;
    var totals = this.read.stale(state) || stray ? null : this.read.totals(id);
    if (!totals) return { count: 1, description: "Choose a replacement for any Edges using it, or clear them." };
    var length = units.format(totals.length_m, fields.LENGTH_M, units.profile(fields.LENGTH_M, preferences.current()));
    return { count: totals.edge_count, description: "Used by " + totals.edge_count +
      (totals.edge_count === 1 ? " Edge, " : " Edges, ") + length + " in all." };
  };
  /* The number alone under a header naming the unit; a dash until the schedule is read, muted once the Model
     has changed since. */
  Types.prototype.lengthCell = function (td, value) {
    var known = value !== null && value !== undefined;
    td.textContent = known ? units.format(value, fields.LENGTH_M,
      units.profile(fields.LENGTH_M, preferences.current()), { showUnit: false }) : "—";
    var stale = known && this.stale;
    td.classList.toggle("tb-muted", !known || stale);
    ui.tooltip(td, !known ? (this.read.error ? "The schedule could not be read: " + this.read.error :
      "Open the Schedule or Refresh it to measure used length") :
      stale ? "Measured before the last change; Refresh the Schedule to update" : "");
  };
  /* The first datasheet link as text. Following it would navigate the panel, so it is shown, not opened. */
  Types.prototype.datasheetCell = function (td, record) {
    var links = record.values.datasheet_links || [];
    td.textContent = links[0] || "—";
    td.classList.toggle("tb-muted", !links.length);
    ui.tooltip(td, links.join("\n"));
  };
  /* The assign bar waits for an open form and for a write in flight, which share the one action result; a cell
     draft on a type is unrelated to the selected Edges. */
  Types.prototype.assignGuard = function () {
    if (this.forms.some(function (form) { return !form.root.hidden; })) return "Finish or cancel the open form.";
    return this.inventory.busy() ? "Wait for the Model operation to finish." : null;
  };
  Types.prototype.guard = function () {
    if (this.forms.some(function (form) { return !form.root.hidden; })) return "Finish or cancel the open form.";
    if (this.bar.busy()) return "Wait for the assignment to finish.";
    return this.inventory.guard();
  };
  Types.prototype.render = function (state) {
    var payload = snapshot.value(state, shared.TYPES);
    this.records = payload ? payload.records : [];
    this.stale = this.read.stale(state);
    this.newType.refresh(state); this.duplicate.refresh(state); this.replacement.refresh(state);
    this.color.refresh(state, Boolean(payload), this.records);
    // The bar settles its request first, so a finished assignment no longer holds the table.
    this.bar.render(state, this.records);
    this.inventory.externalBusy = this.bar.busy() || this.forms.some(function (form) {
      return form.busy ? form.busy() : form.requests.busy();
    });
    this.inventory.render(state);
    this.create.disabled = !payload || this.inventory.busy();
  };
  Types.prototype.dispose = function () {
    this.forms.forEach(function (form) { form.dispose(); });
    this.bar.dispose(); this.inventory.dispose();
  };
  return { Types: Types, TypeForm: TypeForm };
});
