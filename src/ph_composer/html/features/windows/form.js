/* Product lifecycle dialogs freeze the authored baseline and use the shared request/form contract. */
PhComposerUI.define("features/windows/form", ["dom", "record_form", "snapshot", "unit_field",
  "features/windows/editor_shared", "workspace"], function (dom, RecordForm, snapshot, unitFields, shared, ui) {
  "use strict";
  function Form(session, send, kind, spec, changed) {
    var self = this; this.kind = kind; this.productSpec = spec; this.fields = {}; this.unitFields = {};
    this.fieldLabels = {};
    RecordForm.call(this, session, send, { title: "New " + spec.label, label: "window-product-" + kind,
      action: shared.PREFIX + kind + ".create", submitLabel: "Create " + spec.label,
      pendingText: "Saving…", failureText: "The product was not changed.", changed: changed });
    spec.columns.filter(function (column) { return column[0] !== "color"; }).forEach(function (column) {
      // A PH symbol takes its subscript in the visible label ("Uf" reads U with f); the field keeps the plain name.
      var label = ui.element("label");
      label.appendChild(dom.symbolText(ui.element("span", "phc-symbol"), column[1]));
      var input = ui.element("input");
      self.fieldLabels[column[0]] = label;
      input.setAttribute("aria-label", column[1]); self.fields[column[0]] = input;
      if (spec.quantities[column[0]]) {
        self.unitFields[column[0]] = new unitFields.UnitField({ input: input, field: spec.quantities[column[0]] });
        label.appendChild(self.unitFields[column[0]].root);
      } else label.appendChild(input);
      if (column[0] === "name") {
        RecordForm.required(label, input);
        input.addEventListener("input", function () { self.paintReady(); });
      }
      if ((spec.autoName || []).indexOf(column[0]) >= 0) {
        input.addEventListener("input", function () { self.paintAutoName(); });
      }
      self.form.appendChild(label);
      if (column[0] === "name" && spec.autoName) self.buildAutoName();
    });
    this.explanation = ui.element("p", "muted"); this.form.appendChild(this.explanation);
    this.replacement = ui.element("select"); this.replacement.setAttribute("aria-label", "Replacement product");
    this.form.appendChild(this.replacement); this.finish();
  }
  RecordForm.extend(Form);
  /* An optional Name built from the fields a product kind declares, for a new record only. While ticked, the Name
     follows those fields and cannot be typed in; unticking leaves the text there to edit. */
  Form.prototype.buildAutoName = function () {
    var self = this, label = ui.element("label", "window-auto-name");
    this.autoName = ui.element("input"); this.autoName.type = "checkbox";
    label.appendChild(this.autoName); label.appendChild(ui.element("span", "", "Auto-name"));
    ui.tooltip(label, "Builds the Name from " + this.productSpec.autoName.map(function (key) {
      return self.productSpec.columns.filter(function (column) { return column[0] === key; })[0][1];
    }).join(", ") + ", leaving out any left blank.");
    this.autoName.addEventListener("change", function () {
      self.fields.name.disabled = self.autoName.checked; self.paintAutoName(); self.paintReady();
    });
    this.autoNameLabel = label; this.form.appendChild(label);
  };
  Form.prototype.paintAutoName = function () {
    if (!this.autoName || !this.autoName.checked) return;
    this.fields.name.value = this.productSpec.autoName.map(function (key) {
      return this.fields[key].value.trim();
    }, this).filter(Boolean).join("-");
    this.paintReady();
  };
  Form.prototype.open = function (method, record, records) {
    if (this.disposed || !this.enabled || this.busy()) return;
    this.method = method; this.record = record && shared.clone(record); this.records = (records || []).slice();
    this.spec.action = shared.PREFIX + this.kind + "." + method;
    // A new product's dialog is titled as every other record's: New, then what it makes.
    this.title.textContent = method === "create" ? "New " + this.productSpec.label :
      ui.titleCase(method) + " " + (record ? record.values.name : this.productSpec.label);
    this.root.setAttribute("aria-label", this.title.textContent);
    this.submitButton.textContent = method === "delete" ? "Delete" : method === "duplicate" ? "Duplicate" : "Create";
    this.submitButton.setAttribute("aria-label", this.submitButton.textContent);
    this.cancel.setAttribute("aria-label", "Cancel");
    this.submitButton.disabled = false; this.cancel.disabled = false; this.error.textContent = "";
    this.replacement.hidden = method !== "delete" || !record.use_count;
    this.replacement.replaceChildren(ui.option("", "Choose a replacement"));
    this.records.slice().sort(function (a, b) { return ui.compareText(a.values.name, b.values.name); })
      .forEach(function (row) { if (row.id !== (record && record.id)) {
        this.replacement.appendChild(ui.option(row.id, row.values.name));
      } }, this);
    if (this.autoName) {
      this.autoNameLabel.hidden = method !== "create"; this.autoName.checked = false; this.fields.name.disabled = false;
    }
    Object.keys(this.fields).forEach(function (key) {
      this.fieldLabels[key].hidden = method === "delete" || method === "duplicate" && key !== "name";
      if (this.unitFields[key]) { this.unitFields[key].cancel(); this.unitFields[key].setValue(null); }
      else this.fields[key].value = method === "duplicate" && key === "name" ? this.copyName(record) : "";
    }, this);
    this.explanation.textContent = method === "delete" ? record.use_count ? "Replace all " + record.use_count +
      " uses, including any Model default, before removing this product." : "Remove this unused product." :
      "Products remain editable definitions in this model.";
    this.paintReady();
    this.show(); if (method !== "delete") this.fields.name.focus();
  };
  /* Create and Duplicate wait for the required Name, and say so where the footer's hint goes, as the other
     record dialogs do. */
  var NAME_HINT = "Enter a name.", AUTO_NAME_HINT = "Fill in a field the name is built from.";
  function isNameHint(text) { return text === NAME_HINT || text === AUTO_NAME_HINT; }
  Form.prototype.paintReady = function () {
    if (this.method === "delete" || this.busy()) return;
    var missing = !String(this.fields.name.value || "").trim();
    this.submitButton.disabled = missing;
    var hint = this.autoName && this.autoName.checked ? AUTO_NAME_HINT : NAME_HINT;
    if (missing || isNameHint(this.error.textContent)) this.error.textContent = missing ? hint : "";
    this.error.classList.toggle("phc-form-hint", isNameHint(this.error.textContent));
  };
  Form.prototype.copyName = function (record) {
    var base = record.values.name.trim(), candidate = base + " (copy)", n = 1;
    var names = this.records.map(function (row) { return row.values.name.trim().toLowerCase(); });
    while (names.indexOf(candidate.toLowerCase()) >= 0) candidate = base + " (copy " + (++n) + ")";
    return candidate;
  };
  Form.prototype.submit = function () {
    if (this.disposed || !this.enabled || this.busy()) return;
    var params = {}, invalid;
    if (this.method === "delete") {
      params = { id: this.record.id, expected_values: shared.clone(this.record.values) };
      if (this.record.use_count && !this.replacement.value) {
        this.error.textContent = "Choose a replacement product."; return; }
      if (this.replacement.value) params.replacement_id = this.replacement.value;
    } else if (this.method === "duplicate") {
      if (!this.fields.name.value.trim()) { this.error.textContent = "Enter a name."; return; }
      params = { id: this.record.id, name: this.fields.name.value.trim() };
    } else {
      var values = {};
      Object.keys(this.fields).forEach(function (key) {
        var field = this.unitFields[key], parsed = field && field.parse();
        if (field && !parsed.ok) invalid = parsed.message;
        else values[key] = field ? parsed.value : this.fields[key].value.trim();
      }, this);
      if (!values.name || invalid) { this.error.textContent = invalid || "Enter a name."; return; }
      params.values = values;
    }
    this.run(params);
  };
  Form.prototype.refresh = function (state) {
    this.enabled = Boolean(snapshot.value(state, shared.PREFIX + this.kind));
    if (!this.enabled) { this.withdraw(); return; }
    var result = this.settle(state);
    if (result && result.status === "completed") this.hide(result.value);
    else if (result) this.submitButton.disabled = false;
  };
  Form.prototype.dispose = function () {
    this.disposed = true; this.enabled = false; this.withdraw();
    Object.keys(this.unitFields).forEach(function (key) { this.unitFields[key].dispose(); }, this);
  };
  return Form;
});
