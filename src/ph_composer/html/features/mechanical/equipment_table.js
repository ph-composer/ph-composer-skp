/* One Mechanical equipment table, the shape every family's table shares: the kit Inventory over one catalog section,
   Tag first and pinned beside Actions, Manufacturer, Model and Notes last behind the Columns menu, the page header's
   New, each row's Duplicate and Delete in the shared form dialog, Locate's narrowing, and the guards that hold the tab
   while a draft or a write is out. A family gives its columns and its own cells; parts that open over the table (the
   Zone picker, a row's optional values) join through `parts`.

   new EquipmentTable(root, context, spec) answers the systems.js view: render(state, shown), guard(), dispose(),
   create, accepts(intent), navigate(intent). spec:
     section, label, className    the snapshot section and its operations' prefix, the record's name, a table class
     columns, editable             [[field, label]] before the identity columns, and the fields edited in place
     identity                      the hideable columns last, edited in place: Manufacturer, Model and Notes
                                   unless a kind that has no manufacturer names its own (a Pipe Type, Notes)
     inventory                     further kit Inventory options (quantities, selectFields, normalize, validate,
                                   rawValue, defaultWidths, columnMenus, headerActions, value, search, placeholder,
                                   afterCell); `cell(td, row, field)` draws a family's own cell and answers true
     actions(row), act(row, command, control)   row actions before Duplicate and Delete, and their handler
     parent, parents               { key, label, section } for a kind that names its parent record, or a list of them
                                   for one that names several: New asks for each
     forms                         a family's own record forms in the shared dialog, each with refresh(state),
                                   busy() and dispose(); an open one holds the tab as New's does
     replacement                   inventory_forms ReplacementForm options for Delete beyond section and label
     locate                        the Locate param naming this table's records
     parts                         [{ busy(), guard(), refresh(state, records), dispose() }]
     repainted()                   after each repaint, for an open part to follow the cell it was opened from

   Cells that are one choice applied at once (a Heater's System) send through `choose(record, values, expected)`:
   one guarded update, its refusal a warning notice, the cell showing the Model's value again. */
PhComposerUI.define("features/mechanical/equipment_table", ["panel", "snapshot", "workspace", "request",
  "record_form", "inventory", "inventory_forms", "choice_cell", "unit_field"],
function (panel, snapshot, ui, request, RecordForm, inventories, forms, choiceCell, unitFields) {
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

  /* New <label>: its Tag and, for a kind that names its parent records, each of them (a heat pump indoor unit names
     its indoor model and its outdoor unit). Every other value starts at its default and is edited on the row. */
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
    this.parents = (options.parents || (options.parent ? [options.parent] : [])).map(function (parent) {
      var select = forms.labelled(self.form, parent.label, ui.element("select"));
      RecordForm.required(select.parentNode, select);
      select.addEventListener("change", edited);
      return { spec: parent, select: select, records: [] };
    });
    // The first parent's select, for a kind that names one.
    this.parent = this.parents.length ? this.parents[0].select : null;
    this.finish();
  }
  RecordForm.extend(TagForm);
  /* What Create waits for, or "". */
  TagForm.prototype.waitsFor = function () {
    if (!this.name.value.trim()) return "Enter a Tag to create the " + this.options.label + ".";
    var waiting = "";
    this.parents.some(function (parent) {
      if (!parent.records.length) waiting = "Create a " + parent.spec.label + " first.";
      else if (!parent.select.value) waiting = "Choose the " + parent.spec.label + " it belongs to.";
      return Boolean(waiting);
    });
    return waiting;
  };
  TagForm.prototype.updateButton = function () {
    var waiting = this.waitsFor(), hinted = this.error.classList.contains("phc-form-hint");
    this.submitButton.disabled = !this.enabled || this.busy() || Boolean(waiting);
    if (this.busy()) return;
    // A refusal stays until the user changes something; a hint says what Create waits for.
    if (waiting || hinted || !this.error.textContent) this.error.textContent = waiting;
    this.error.classList.toggle("phc-form-hint", Boolean(waiting));
  };
  /* Each parent's choices, from its section as the snapshot has it. The current choice is kept while it is there and
     cleared when it goes; only a form just opened takes the sole choice for the user. */
  TagForm.prototype.paintParents = function (fresh) {
    this.parents.forEach(function (parent) {
      var select = parent.select, chosen = select.value;
      select.replaceChildren(ui.option("", "Choose a " + parent.spec.label));
      parent.records.forEach(function (record) { select.appendChild(ui.option(record.id, record.values.name)); });
      select.value = parent.records.some(function (record) { return record.id === chosen; }) ? chosen :
        fresh && parent.records.length === 1 ? parent.records[0].id : "";
    });
  };
  TagForm.prototype.open = function () {
    if (!this.enabled) return;
    this.name.value = ""; this.error.textContent = "";
    this.parents.forEach(function (parent) { parent.select.value = ""; });
    this.paintParents(true);
    this.updateButton();
    this.show(); this.name.focus();
  };
  TagForm.prototype.submit = function () {
    this.updateButton();
    if (this.submitButton.disabled) return;
    var values = { name: this.name.value.trim() };
    this.parents.forEach(function (parent) { values[parent.spec.key] = parent.select.value; });
    this.run({ values: values });
  };
  TagForm.prototype.refresh = function (state) {
    this.parents.forEach(function (parent) {
      parent.records = ((snapshot.value(state, parent.spec.section) || {}).records || []).slice()
        .sort(function (a, b) { return ui.compareText(a.values.name, b.values.name); });
    });
    if (!this.root.hidden) this.paintParents();
    var outcome = forms.refreshForm(this, state, this.options.section);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    else this.updateButton();
  };
  TagForm.prototype.dispose = function () { this.enabled = false; this.withdraw(); };

  function present(value) { return value !== null && value !== undefined; }

  /* Change Type, for a kind whose variant takes its own values (a Hot Water Heater's Type, say): the
     new variant's values, each required, and what the old variant's values were, sent as one guarded update with a
     null for each old value, one Undo step. options: { section, label (request label), key (the variant field), word
     ("Type"), choices ([{ value, label }]), values ({ field: { label, field } }), fields ({ variant: [field] }),
     positive ([field] that must be above 0), none (said when the new variant takes no value), changed } */
  function VariantForm(session, send, options) {
    var word = options.word;
    RecordForm.call(this, session, send, { title: "Change " + word, action: options.section + ".update",
      label: options.label, submitLabel: "Change " + word, pendingText: "Changing...",
      failureText: "The " + word + " was not changed.", changed: options.changed });
    this.options = options;
    this.explanation = ui.element("p");
    this.form.appendChild(this.explanation);
    this.fieldsRoot = ui.element("div", "mech-type-fields");
    this.form.appendChild(this.fieldsRoot);
    this.units = [];
    this.finish();
  }
  RecordForm.extend(VariantForm);
  VariantForm.prototype.label = function (value) {
    var entry = this.options.choices.filter(function (choice) { return choice.value === value; })[0];
    return entry ? entry.label : value;
  };
  /* The one update a change sends: the new variant and its values, a null for each value of the old one, each
     guarded by what the row showed. */
  VariantForm.prototype.change = function (record, variant, entered) {
    var key = this.options.key, values = {}, expected = {}, wanted = this.options.fields[variant];
    values[key] = variant; expected[key] = record.values[key];
    Object.keys(this.options.values).forEach(function (field) {
      if (wanted.indexOf(field) >= 0) values[field] = entered[field];
      else if (present(record.values[field])) {
        values[field] = null;
        expected[field] = record.values[field];
      }
    });
    return { id: record.id, values: values, expected_values: expected };
  };
  VariantForm.prototype.open = function (record, variant) {
    if (!this.enabled) return;
    var self = this, options = this.options, wanted = options.fields[variant];
    this.record = record; this.variant = variant; this.stale = false; this.from = record.values[options.key];
    this.release();
    this.title.textContent = "Change " + record.values.name + " to " + this.label(variant);
    var going = Object.keys(options.values).filter(function (field) {
      return wanted.indexOf(field) < 0 && present(record.values[field]);
    }).map(function (field) { return options.values[field].label; });
    this.explanation.textContent = going.length ? "Removes its " + going.join(", ") + "." :
      wanted.length ? "" : options.none;
    this.explanation.hidden = !this.explanation.textContent;
    this.units = wanted.map(function (field) {
      var entry = options.values[field], label = ui.element("label", "mech-type-field");
      var unit = new unitFields.UnitField({ field: entry.field, value: null,
        onCommit: function () { self.updateButton(); } });
      unit.input.setAttribute("aria-label", entry.label);
      // A held change keeps saying why until the dialog closes.
      unit.input.addEventListener("input", function () { if (!self.stale) self.error.textContent = ""; });
      // Enter in any field submits, after the field has read what was typed.
      unit.input.addEventListener("keydown", function (event) { if (event.key === "Enter") self.submit(); });
      label.appendChild(ui.element("span", "", entry.label));
      label.appendChild(unit.root);
      RecordForm.required(label, unit.input);
      self.fieldsRoot.appendChild(label);
      return { key: field, unit: unit };
    });
    this.error.textContent = "";
    this.updateButton();
    this.show();
    if (this.units.length) this.units[0].unit.input.focus(); else this.submitButton.focus();
  };
  VariantForm.prototype.updateButton = function () {
    this.submitButton.disabled = !this.enabled || this.busy() || Boolean(this.stale);
  };
  /* Each value read as typed, or the first field's reason it cannot be. */
  VariantForm.prototype.entered = function () {
    var entered = {}, failed = false, options = this.options;
    this.units.forEach(function (held) {
      var outcome = held.unit.commit(), value = outcome.ok ? held.unit.baseline : null;
      var reason = !outcome.ok ? outcome.message : value === null ? "Enter the " +
        options.values[held.key].label + "." : options.positive.indexOf(held.key) >= 0 && value <= 0 ?
        "Enter a number above 0." : "";
      if (reason) {
        held.unit.error.textContent = reason; held.unit.error.hidden = false;
        held.unit.input.setAttribute("aria-invalid", "true");
        if (!failed) held.unit.input.focus();
        failed = true;
      }
      entered[held.key] = value;
    });
    return failed ? null : entered;
  };
  /* Enter in a field reaches here as the button does, so a held or disabled change sends nothing either way. */
  VariantForm.prototype.submit = function () {
    if (!this.record || !this.enabled || this.busy() || this.stale) return;
    var entered = this.entered();
    if (entered) this.run(this.change(this.record, this.variant, entered));
  };
  VariantForm.prototype.refresh = function (state) {
    var outcome = forms.refreshForm(this, state, this.options.section), key = this.options.key;
    if (outcome && outcome.status === "completed") { this.hide(); this.release(); return; }
    var record = this.record, records = (snapshot.value(state, this.options.section) || {}).records || [];
    var now = record && records.filter(function (entry) { return entry.id === record.id; })[0];
    if (!this.root.hidden && record && !this.busy()) {
      // The record went: nothing is left to change.
      if (!now) { this.hide(); this.release(); return; }
      // Its variant changed elsewhere: the change no longer means what it said. The typed values and any refusal stay
      // in view; the change is held, and Cancel lets the user choose again from the variant now shown.
      if (now.values[key] !== this.from && !this.stale) {
        this.stale = true;
        this.error.textContent = (this.error.textContent ? this.error.textContent + " " : "") +
          record.values.name + " is now " + this.label(now.values[key]) + "; cancel and choose its " +
          this.options.word + " again.";
      }
    }
    this.updateButton();
  };
  VariantForm.prototype.release = function () {
    this.units.forEach(function (held) { held.unit.dispose(); });
    this.units = [];
    this.fieldsRoot.replaceChildren();
  };
  VariantForm.prototype.dispose = function () { this.enabled = false; this.withdraw(); this.release(); };

  function EquipmentTable(root, context, spec) {
    var self = this, session = context.session, send = context.send, label = spec.label;
    this.root = root; this.spec = spec; this.records = []; this.parts = spec.parts || [];
    function changed() { panel.repaint(); }
    this.changed = changed;
    this.cells = request.channel(session, send, spec.section + "-cells");
    this.newRecord = new TagForm(session, send, changed, { section: spec.section, label: label,
      parent: spec.parent, parents: spec.parents });
    this.duplicate = new forms.DuplicateForm(session, send, changed, { section: spec.section, label: label,
      datasheets: false });
    this.replacement = new forms.ReplacementForm(session, send, changed, Object.assign({ section: spec.section,
      label: label }, spec.replacement || {}));
    this.forms = [this.newRecord, this.duplicate, this.replacement].concat(spec.forms || []);
    this.create = ui.button("+ New " + label, function () { if (self.allowed()) self.newRecord.open(); });
    this.hidden = {};
    var table = ui.element("div", "mech-equipment-table" + (spec.className ? " " + spec.className : ""));
    root.appendChild(table);
    var extra = spec.inventory || {}, identity = spec.identity || IDENTITY;
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
      columns: [["name", "Tag"]].concat(spec.columns, identity),
      editable: ["name"].concat(spec.editable, identity.map(function (column) { return column[0]; })),
      optionalColumns: identity, hiddenColumns: this.hidden,
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
    this.loaded = Boolean(payload);
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
    if (this.located && this.loaded) this.navigate(this.located);
    this.create.disabled = !payload || this.inventory.busy();
  };
  /* A Locate from Export names this table's records. */
  EquipmentTable.prototype.accepts = function (intent) { return Boolean(intent[this.spec.locate]); };
  EquipmentTable.prototype.navigate = function (intent) {
    var ids = intent[this.spec.locate];
    // A Locate that arrives before the records are read waits for them; an empty catalog read is an answer.
    this.located = this.loaded ? null : intent;
    if (!this.loaded) return;
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

  return { EquipmentTable: EquipmentTable, TagForm: TagForm, VariantForm: VariantForm, choiceCell: choiceCell,
    yesNo: yesNo, choice: choice, wholeNumber: wholeNumber, stored: stored, YES_NO: YES_NO, IDENTITY: IDENTITY };
});
