/* One Mechanical equipment table, the shape every family's table shares: the kit Inventory over one catalog section,
   Tag first and pinned beside Actions, Manufacturer, Model and Notes last behind the Columns menu, the page header's
   New, each row's Duplicate and Delete in the shared form dialog, Locate's narrowing, and the guards that hold the tab
   while a draft or a write is out. A family gives its columns and its own cells; parts that open over the table (the
   Zone picker, a row's optional values) join through `parts`.

   new EquipmentTable(root, context, spec) answers the systems.js view: render(state, shown), guard(), dispose(),
   create, accepts(intent), navigate(intent). spec:
     section, label, className    the snapshot section and its operations' prefix, the record's name, a table class
     columns, editable             [[field, label]] before the identity columns, and the fields edited in place
     inventory                     further kit Inventory options (quantities, selectFields, normalize, validate,
                                   rawValue, defaultWidths, columnMenus, headerActions, value, search, placeholder,
                                   afterCell); `cell(td, row, field)` draws a family's own cell and answers true
     actions(row), act(row, command, control)   row actions before Duplicate and Delete, and their handler
     parent                        { key, label, section } for a kind that names its parent record: New asks for it
     forms                         a family's own record forms in the shared dialog, each with refresh(state),
                                   busy() and dispose(); an open one holds the tab as New's does
     replacement                   inventory_forms ReplacementForm options for Delete beyond section and label
     locate                        the Locate param naming this table's records
     parts                         [{ busy(), guard(), refresh(state, records), dispose() }]
     repainted()                   after each repaint, for an open part to follow the cell it was opened from

   Cells that are one choice applied at once (a Heater's System) send through `choose(record, values, expected)`:
   one guarded update, its refusal a warning notice, the cell showing the Model's value again. */
PhComposerUI.define("features/mechanical/equipment_table", ["panel", "snapshot", "workspace", "request",
  "record_form", "inventory", "inventory_forms"],
function (panel, snapshot, ui, request, RecordForm, inventories, forms) {
  "use strict";
  var IDENTITY = [["manufacturer", "Manufacturer"], ["model", "Model"], ["notes", "Notes"]];
  var YES_NO = [{ value: "true", label: "Yes" }, { value: "false", label: "No" }];

  /* Typed or pasted text for a yes or no: the choice's value or its label, in any case. */
  function yesNo(text) {
    var word = String(text).toLowerCase();
    if (word === "true" || word === "yes") return true;
    if (word === "false" || word === "no") return false;
    return { ok: false, message: "Enter Yes or No." };
  }
  /* A whole number of `minimum` or more; a blank is null where `blank` allows it. */
  function wholeNumber(text, minimum, blank) {
    if (blank && text === "") return null;
    var message = "Enter a whole number of " + minimum + " or more" + (blank ? ", or leave it blank." : ".");
    return /^\d+$/.test(text) && Number(text) >= minimum ? Number(text) : { ok: false, message: message };
  }
  /* Typed or pasted text for a choice: its value or its label, in any case; `cast` turns the value into what is
     stored. Anything else is refused before it is sent. */
  function choice(choices, text, cast) {
    var word = String(text).toLowerCase(), found = choices.filter(function (entry) {
      return String(entry.value).toLowerCase() === word || entry.label.toLowerCase() === word;
    })[0];
    if (!found) return { ok: false, message: "Choose one of " + choices.map(function (entry) {
      return entry.label;
    }).join(", ") + "." };
    return cast ? cast(found.value) : found.value;
  }
  /* An absent Manufacturer or Model is null, so a range edit carries it as a value and as its guard. */
  function stored(record, field) {
    var value = record.values[field];
    return value === undefined ? null : value;
  }

  /* New <label>: its Tag and, for a kind that names its parent record, that record. Every other value starts at
     its default and is edited on the row. */
  function TagForm(session, send, changed, options) {
    RecordForm.call(this, session, send, { title: "New " + options.label, action: options.section + ".create",
      label: options.section + "-create", submitLabel: "Create " + options.label, pendingText: "Creating...",
      failureText: "The " + options.label + " was not created.", changed: changed });
    var self = this;
    this.options = options;
    // An edit clears a refusal; the hint then says what Create still waits for.
    function edited() {
      if (!self.busy()) self.error.textContent = "";
      self.updateButton();
    }
    this.name = forms.labelled(this.form, "Tag", ui.element("input"));
    RecordForm.required(this.name.parentNode, this.name);
    this.name.addEventListener("input", edited);
    if (options.parent) {
      this.parent = forms.labelled(this.form, options.parent.label, ui.element("select"));
      RecordForm.required(this.parent.parentNode, this.parent);
      this.parent.addEventListener("change", edited);
    }
    this.parents = [];
    this.finish();
  }
  RecordForm.extend(TagForm);
  /* What Create waits for, or "". */
  TagForm.prototype.waitsFor = function () {
    if (!this.name.value.trim()) return "Enter a Tag to create the " + this.options.label + ".";
    if (this.parent && !this.parents.length) return "Create a " + this.options.parent.label + " first.";
    if (this.parent && !this.parent.value) return "Choose the " + this.options.parent.label + " it belongs to.";
    return "";
  };
  TagForm.prototype.updateButton = function () {
    var waiting = this.waitsFor(), hinted = this.error.classList.contains("phc-form-hint");
    this.submitButton.disabled = !this.enabled || this.busy() || Boolean(waiting);
    if (this.busy()) return;
    // A refusal stays until the user changes something; a hint says what Create waits for.
    if (waiting || hinted || !this.error.textContent) this.error.textContent = waiting;
    this.error.classList.toggle("phc-form-hint", Boolean(waiting));
  };
  /* The parent choices, from the parent's section as the snapshot has it. The current choice is kept while it is
     there and cleared when it goes; only a form just opened takes the sole choice for the user. */
  TagForm.prototype.paintParents = function (fresh) {
    if (!this.parent) return;
    var chosen = this.parent.value;
    this.parent.replaceChildren(ui.option("", "Choose a " + this.options.parent.label));
    this.parents.forEach(function (record) { this.parent.appendChild(ui.option(record.id, record.values.name)); },
      this);
    this.parent.value = this.parents.some(function (record) { return record.id === chosen; }) ? chosen :
      fresh && this.parents.length === 1 ? this.parents[0].id : "";
  };
  TagForm.prototype.open = function () {
    if (!this.enabled) return;
    this.name.value = ""; this.error.textContent = "";
    if (this.parent) { this.parent.value = ""; this.paintParents(true); }
    this.updateButton();
    this.show(); this.name.focus();
  };
  TagForm.prototype.submit = function () {
    this.updateButton();
    if (this.submitButton.disabled) return;
    var values = { name: this.name.value.trim() };
    if (this.parent) values[this.options.parent.key] = this.parent.value;
    this.run({ values: values });
  };
  TagForm.prototype.refresh = function (state) {
    if (this.parent) {
      this.parents = ((snapshot.value(state, this.options.parent.section) || {}).records || []).slice()
        .sort(function (a, b) { return ui.compareText(a.values.name, b.values.name); });
      if (!this.root.hidden) this.paintParents();
    }
    var outcome = forms.refreshForm(this, state, this.options.section);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    else this.updateButton();
  };
  TagForm.prototype.dispose = function () { this.enabled = false; this.withdraw(); };

  /* A choice applied at once, drawn as the tables' enum pill: `choices` are { value, label }, `value` the Model's.
     The select is kept across repaints, so focus a dialog returns to it (a Heater's Type change) finds it. */
  function choiceCell(td, options) {
    var select = td.mechChoice;
    if (!select) {
      select = td.mechChoice = ui.element("select", "phc-enum-cell");
      select.addEventListener("change", function () {
        var current = select.mechOptions, chosen = select.value;
        select.value = current.value;
        if (chosen !== current.value) current.choose(chosen, select);
      });
    }
    select.mechOptions = options;
    var listed = JSON.stringify(options.choices);
    if (select.mechListed !== listed) {
      select.mechListed = listed;
      select.replaceChildren();
      options.choices.forEach(function (choice) { select.appendChild(ui.option(choice.value, choice.label)); });
    }
    select.value = options.value;
    select.disabled = Boolean(options.disabled);
    select.setAttribute("aria-label", options.label);
    if (select.parentNode !== td) td.replaceChildren(select);
    td.classList.add("phc-editable-cell");
    return select;
  }

  function EquipmentTable(root, context, spec) {
    var self = this, session = context.session, send = context.send, label = spec.label;
    this.root = root; this.spec = spec; this.records = []; this.parts = spec.parts || [];
    function changed() { panel.repaint(); }
    this.changed = changed;
    this.cells = request.channel(session, send, spec.section + "-cells");
    this.newRecord = new TagForm(session, send, changed, { section: spec.section, label: label,
      parent: spec.parent });
    this.duplicate = new forms.DuplicateForm(session, send, changed, { section: spec.section, label: label,
      datasheets: false });
    this.replacement = new forms.ReplacementForm(session, send, changed, Object.assign({ section: spec.section,
      label: label }, spec.replacement || {}));
    this.forms = [this.newRecord, this.duplicate, this.replacement].concat(spec.forms || []);
    this.create = ui.button("+ New " + label, function () { if (self.allowed()) self.newRecord.open(); });
    this.hidden = {};
    var table = ui.element("div", "mech-equipment-table" + (spec.className ? " " + spec.className : ""));
    root.appendChild(table);
    var extra = spec.inventory || {};
    this.inventory = new inventories.Inventory(table, session, send, panel.notify, changed, Object.assign({
      // Search reads the Tag, the identity and the notes, and whatever else a family adds to it.
      placeholder: "Tag or model", search: function (record) {
        return ["name", "manufacturer", "model", "notes"].map(function (field) { return record.values[field]; })
          .filter(Boolean).join(" ");
      },
      value: function (record, field) { return record.values[field]; },
      rawValue: function (row, field) { return stored(row.record, field); }
    }, extra, {
      tableId: spec.section, section: spec.section, action: spec.section + ".update", label: label,
      columns: [["name", "Tag"]].concat(spec.columns, IDENTITY),
      editable: ["name"].concat(spec.editable, ["manufacturer", "model", "notes"]),
      optionalColumns: IDENTITY, hiddenColumns: this.hidden,
      // The Tag stays beside Actions while the table scrolls sideways (mechanical.css).
      stickyWidths: { name: 180 },
      defaultWidths: Object.assign({ name: 180, manufacturer: 130, model: 130 }, extra.defaultWidths),
      normalize: function (field, text) {
        if (field === "manufacturer" || field === "model") return text === "" ? null : text;
        return extra.normalize ? extra.normalize(field, text) : undefined;
      },
      actions: function (row) {
        var name = row.record.values.name;
        return (spec.actions ? spec.actions(row) : []).concat([
          { id: "duplicate", icon: "duplicate", label: "Duplicate " + name },
          { id: "delete", icon: "delete", label: "Delete " + name }]);
      },
      actionFor: function (row, command, control) {
        if (!self.allowed()) return;
        if (command.id === "duplicate") self.duplicate.open(row.record);
        else if (command.id === "delete") self.replacement.open(row.record, self.records);
        else if (spec.act) spec.act(row, command, control);
      },
      cell: function (td, row, field) { return Boolean(spec.cell && spec.cell(td, row, field)); }
    }));
    this.inventory.emptyAction = { label: "+ New " + label, run: function () {
      if (self.allowed()) self.newRecord.open();
    } };
    this.forms.forEach(function (form) { root.appendChild(form.root); });
  }
  /* A notice and false while something holds the table. */
  EquipmentTable.prototype.allowed = function () {
    var reason = this.guard();
    if (reason) panel.notify(reason, "warning");
    return !reason;
  };
  EquipmentTable.prototype.busy = function () {
    return this.inventory.busy() || this.cells.busy();
  };
  /* The layer a bubble mounts in: the workspace, outside the table's scroller. */
  EquipmentTable.prototype.layer = function (node) {
    return (node && node.closest && node.closest(".phc-workspace")) || document.body;
  };
  /* One guarded update from a cell applied at once. */
  EquipmentTable.prototype.choose = function (record, values, expected) {
    if (!this.allowed()) { this.changed(); return; }
    this.cells.run(this.spec.section + ".update", { id: record.id, values: values, expected_values: expected });
    this.changed();
  };
  EquipmentTable.prototype.guard = function () {
    if (this.forms.some(function (form) { return !form.root.hidden; })) return "Finish or cancel the open form.";
    if (this.cells.busy()) return "Wait for the " + this.spec.label + " to be saved.";
    var reason = null;
    this.parts.some(function (part) { reason = part.guard(); return Boolean(reason); });
    return reason || this.inventory.guard();
  };
  EquipmentTable.prototype.render = function (state) {
    var self = this, payload = snapshot.value(state, this.spec.section);
    this.records = payload ? payload.records : [];
    this.state = state;
    this.forms.forEach(function (form) { form.refresh(state); });
    var outcome = this.cells.consume(state);
    if (outcome && outcome.status !== "completed") {
      panel.notify(snapshot.message(outcome, "The " + this.spec.label + " was not changed."), "warning");
    }
    this.parts.forEach(function (part) { part.refresh(state, self.records); });
    this.inventory.externalBusy = this.cells.busy() || this.parts.some(function (part) { return part.busy(); }) ||
      this.forms.some(function (form) { return form.busy(); });
    this.inventory.render(state);
    // A repaint draws every row again; an open part follows the cell or action it was opened from.
    if (this.spec.repainted) this.spec.repainted();
    if (this.located && this.records.length) this.navigate(this.located);
    this.create.disabled = !payload || this.inventory.busy();
  };
  /* A Locate from Export names this table's records. */
  EquipmentTable.prototype.accepts = function (intent) { return Boolean(intent[this.spec.locate]); };
  EquipmentTable.prototype.navigate = function (intent) {
    var ids = intent[this.spec.locate];
    // A Locate that arrives before the records are read waits for them.
    this.located = this.records.length ? null : intent;
    if (!this.records.length) return;
    var names = this.records.filter(function (record) { return ids.indexOf(record.id) >= 0; })
      .map(function (record) { return record.values.name; });
    if (!names.length) {
      panel.notify("Those " + this.spec.label + " records are no longer in the Model.", "warning");
      return;
    }
    // The records located show whatever narrowed the table before: other filters and the search give way to the
    // Tag filter, which the Tag column's menu clears.
    var controls = this.inventory.controls, reason = this.guard();
    if (reason) { panel.notify(reason, "warning"); return; }
    Object.keys(controls.columnFilters).forEach(function (field) {
      if (field !== "name") controls.filterColumn(field, null);
    });
    controls.setSearch("");
    controls.filterColumn("name", names);
  };
  /* A row's action button with this accessible-name prefix, as the table last drew it. */
  EquipmentTable.prototype.rowAction = function (id, prefix) {
    var row = this.inventory.scroll.querySelector("[data-row-key='" + id + "']");
    return row ? Array.prototype.filter.call(row.querySelectorAll("button"), function (node) {
      return (node.getAttribute("aria-label") || "").indexOf(prefix) === 0;
    })[0] : null;
  };
  EquipmentTable.prototype.dispose = function () {
    this.forms.forEach(function (form) { form.dispose(); });
    this.parts.forEach(function (part) { part.dispose(); });
    this.cells.reset();
    this.inventory.dispose();
  };

  return { EquipmentTable: EquipmentTable, TagForm: TagForm, choiceCell: choiceCell, yesNo: yesNo, choice: choice,
    wholeNumber: wholeNumber, stored: stored, YES_NO: YES_NO, IDENTITY: IDENTITY };
});
