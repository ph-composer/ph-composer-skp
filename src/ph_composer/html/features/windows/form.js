/* Product lifecycle dialogs freeze the authored baseline and use the shared request/form contract. */
PhComposerUI.define("features/windows/form", ["record_form", "snapshot", "unit_field",
  "features/windows/editor_shared", "workspace"], function (RecordForm, snapshot, unitFields, shared, ui) {
  "use strict";
  function Form(session, send, kind, spec, changed) {
    var self = this; this.kind = kind; this.productSpec = spec; this.fields = {}; this.unitFields = {};
    this.fieldLabels = {};
    RecordForm.call(this, session, send, { title: "New " + spec.label, label: "window-product-" + kind,
      action: shared.PREFIX + kind + ".create", submitLabel: "Create " + spec.label,
      pendingText: "Saving…", failureText: "The product was not changed.", changed: changed });
    spec.columns.filter(function (column) { return column[0] !== "color"; }).forEach(function (column) {
      var label = ui.element("label", "", column[1]), input = ui.element("input");
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
      self.form.appendChild(label);
    });
    this.explanation = ui.element("p", "muted"); this.form.appendChild(this.explanation);
    this.replacement = ui.element("select"); this.replacement.setAttribute("aria-label", "Replacement product");
    this.form.appendChild(this.replacement); this.finish();
  }
  RecordForm.extend(Form);
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
    this.records.forEach(function (row) { if (row.id !== (record && record.id)) {
      this.replacement.appendChild(ui.option(row.id, row.values.name));
    } }, this);
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
  var NAME_HINT = "Enter a name.";
  Form.prototype.paintReady = function () {
    if (this.method === "delete" || this.busy()) return;
    var missing = !String(this.fields.name.value || "").trim();
    this.submitButton.disabled = missing;
    if (missing || this.error.textContent === NAME_HINT) this.error.textContent = missing ? NAME_HINT : "";
    this.error.classList.toggle("phc-form-hint", this.error.textContent === NAME_HINT);
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
