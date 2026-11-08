/* New Material uses the same field descriptors as the inventory, so typing units and validation agree. The
   conductivity adds a selector for the form its datasheet states it in; the Model stores W/(m K) either way. */
PhComposerUI.define("features/assemblies/material_form", ["record_form", "snapshot", "unit_field", "fields",
  "inventory_forms", "workspace"],
function (RecordForm, snapshot, unitFields, fields, forms, ui) {
  "use strict";
  var SECTION = "ph_composer.assemblies.materials";
  var quantities = {
    conductivity_w_mk: fields.with(fields.CONDUCTIVITY, { label: "Conductivity", allowBlank: true, allowZero: false }),
    density_kg_m3: fields.with(fields.DENSITY, { label: "Density", allowBlank: true, allowZero: false }),
    specific_heat_j_kgk: fields.with(fields.SPECIFIC_HEAT, { label: "Specific heat", allowBlank: true,
      allowZero: false }),
    emissivity: fields.with(fields.FRACTION, { label: "Emissivity", max: 1, allowBlank: true })
  };
  var NAME_HINT = "Enter a name.";
  var DEFAULT_COLOR = "#ffffff";
  function choices(select, catalog, value) {
    select.replaceChildren(ui.option("", "None"));
    catalog.forEach(function (entry) { select.appendChild(ui.option(entry.id, entry.label)); });
    select.value = value || "";
  }
  function Form(session, send, changed) {
    var self = this;
    RecordForm.call(this, session, send, { title: "New Material", action: SECTION + ".create", label: "new-material",
      submitLabel: "Create Material", pendingText: "Creating Material...", failureText: "The Material was not created.",
      changed: changed });
    this.fields = {};
    this.unitFields = {};
    this.allowed = false;
    this.disposed = false;
    this.color = new forms.ColorChoice(DEFAULT_COLOR);
    [["name", "Name"], ["category", "Category"], ["color", "Color"], ["conductivity_w_mk", "Conductivity"],
      ["density_kg_m3", "Density"], ["specific_heat_j_kgk", "Specific heat"], ["emissivity", "Emissivity"],
      ["notes", "Notes"]].forEach(function (entry) {
      if (entry[0] === "color") {
        // Not a label: a label around the swatches would press the first swatch when its text is clicked.
        var row = ui.element("div", "phc-form-row");
        row.appendChild(ui.element("span", "", entry[1]));
        row.appendChild(self.color.root);
        self.form.appendChild(row);
        return;
      }
      var input = ui.element(entry[0] === "category" ? "select" : "input");
      var label = ui.element("label", "", entry[1]);
      input.setAttribute("aria-label", entry[1]);
      input.setAttribute("data-material-create-field", entry[0]);
      if (quantities[entry[0]]) {
        self.unitFields[entry[0]] = new unitFields.UnitField({ input: input, field: quantities[entry[0]],
          forms: entry[0] === "conductivity_w_mk" });
        label.appendChild(self.unitFields[entry[0]].root);
      } else label.appendChild(input);
      self.fields[entry[0]] = input;
      if (entry[0] === "name") RecordForm.required(label, input);
      input.addEventListener("input", function () {
        if (!self.busy()) self.error.textContent = "";
        self.updateButton();
      });
      input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") {
          event.preventDefault();
          event.stopImmediatePropagation();
          self.submit();
        }
      }, true);
      self.form.appendChild(label);
    });
    this.finish();
  }
  RecordForm.extend(Form);
  Form.prototype.open = function () {
    if (!this.allowed || this.disposed) return;
    this.show();
    this.fields.name.focus();
    this.updateButton();
  };
  Form.prototype.invalid = function () {
    var self = this, message = "";
    Object.keys(this.unitFields).some(function (key) {
      var parsed = self.unitFields[key].parse();
      if (!parsed.ok) message = parsed.message;
      return Boolean(message);
    });
    return message;
  };
  Form.prototype.updateButton = function () {
    var unnamed = !this.fields.name.value.trim();
    this.submitButton.disabled = !this.allowed || this.disposed || this.busy() || unnamed || Boolean(this.invalid());
    // A disabled Create says what it is waiting for, as guidance. A pending or refused request, and an entry
    // that does not parse, keep the status line for themselves.
    if (unnamed && !this.busy() && !this.error.textContent) this.error.textContent = NAME_HINT;
    else if (!unnamed && this.error.textContent === NAME_HINT) this.error.textContent = "";
    this.error.classList.toggle("phc-form-hint", this.error.textContent === NAME_HINT);
  };
  Form.prototype.submit = function () {
    this.updateButton();
    if (this.submitButton.disabled) { this.error.textContent = this.invalid() || NAME_HINT; return; }
    var values = {}, invalid;
    Object.keys(this.fields).forEach(function (key) {
      if (this.unitFields[key]) {
        var parsed = this.unitFields[key].parse();
        if (!parsed.ok) invalid = parsed.message;
        else values[key] = parsed.value;
      } else values[key] = this.fields[key].value.trim();
    }, this);
    if (invalid) { this.error.textContent = invalid; return; }
    values.color = this.color.color;
    this.run({ values: values });
    this.updateButton();
  };
  Form.prototype.refresh = function (state, busy) {
    var payload = snapshot.value(state, SECTION);
    this.allowed = Boolean(payload && !busy);
    if (payload) choices(this.fields.category, payload.categories, this.fields.category.value);
    else {
      this.withdraw();
    }
    var outcome = this.settle(state);
    if (outcome && outcome.status === "completed") {
      Object.keys(this.fields).forEach(function (key) {
        if (this.unitFields[key]) { this.unitFields[key].cancel();
        this.unitFields[key].setValue(null); }
        else this.fields[key].value = "";
      }, this);
      this.color.set(DEFAULT_COLOR);
      this.hide(outcome.value);
    }
    Object.keys(this.fields).forEach(function (key) { this.fields[key].disabled = !payload || this.busy(); }, this);
    this.color.setDisabled(!payload || this.busy());
    var conductivity = this.unitFields.conductivity_w_mk;
    if (conductivity.formChoice) conductivity.formChoice.disabled = !payload || this.busy();
    this.updateButton();
  };
  Form.prototype.dispose = function () {
    this.disposed = true;
    this.withdraw();
    Object.keys(this.unitFields).forEach(function (key) { this.unitFields[key].dispose(); }, this);
  };
  Form.quantities = quantities;
  Form.choices = choices;
  return Form;
});
