/* Ventilation › Ventilators: the Model's Ventilators as an editable inventory. Tag first, then the values the
   export writes, the Zones each serves with the airflow balance over them, then Manufacturer, Model and Notes,
   which the Columns menu can hide. The subsoil heat exchanger and the preheated intake temperature stay behind
   each row's disclosure, blank by default. A Ventilator is only numbers, so New and Duplicate ask in the shared
   form dialog; Delete offers a replacement, or clearing, for the Zones it serves. Every control sends a
   registered operation; the balance is the host's (context/CONTRACTS.md, "Mechanical equipment"). */
PhComposerUI.define("features/mechanical/ventilators", ["panel", "snapshot", "workspace", "fields", "units",
  "unit_preferences", "record_form", "inventory", "inventory_forms", "sections/colour_by",
  "features/mechanical/systems", "features/mechanical/serves", "features/mechanical/optional_values"],
function (panel, snapshot, ui, fields, units, preferences, RecordForm, inventories, forms, colourBy, systems, serves,
  optional) {
  "use strict";
  var FEATURE = "ph_composer.mechanical", SECTION = FEATURE + ".ventilators", LABEL = "Ventilator";
  var BY_VENTILATOR = FEATURE + ".by_ventilator", NAME_HINT = "Enter a Tag to create the Ventilator.";
  var FRACTION = fields.FRACTION, EFFICIENCY = fields.ELECTRIC_EFFICIENCY, TEMPERATURE = fields.TEMPERATURE_C;
  var AIRFLOW = fields.AIRFLOW_M3H;
  var columns = [["name", "Tag"], ["quantity", "Quantity"], ["sensible_heat_recovery", "Sensible recovery"],
    ["latent_heat_recovery", "Latent recovery"], ["electric_efficiency_wh_m3", "Electric efficiency"],
    ["frost_protection_reqd", "Frost protection"], ["temperature_below_defrost_used_c", "Defrost below"],
    ["in_conditioned_space", "In conditioned space"], ["serves", "Serves"], ["supply_m3h", "Supply"],
    ["extract_m3h", "Extract"], ["manufacturer", "Manufacturer"], ["model", "Model"], ["notes", "Notes"]];
  var IDENTITY = [["manufacturer", "Manufacturer"], ["model", "Model"], ["notes", "Notes"]];
  var BOOLEANS = ["frost_protection_reqd", "in_conditioned_space"];
  var FRACTIONS = ["sensible_heat_recovery", "latent_heat_recovery"];
  var YES_NO = [{ value: "true", label: "Yes" }, { value: "false", label: "No" }];
  var OPTIONAL = [
    { key: "subsoil_heat_exchange_efficiency", label: "Subsoil heat exchanger",
      field: fields.with(FRACTION, { label: "Subsoil heat exchanger", allowBlank: true }) },
    { key: "preheated_intake_temperature_c", label: "Preheated intake temperature",
      field: fields.with(TEMPERATURE, { label: "Preheated intake temperature", allowBlank: true }) }];

  /* New Ventilator: its Tag. Every other value starts at honeybee-ph's default and is edited on the row. */
  function VentilatorForm(session, send, changed) {
    RecordForm.call(this, session, send, { title: "New " + LABEL, action: SECTION + ".create",
      label: "ventilator-create", submitLabel: "Create " + LABEL, pendingText: "Creating...",
      failureText: "The " + LABEL + " was not created.", changed: changed });
    this.name = forms.labelled(this.form, "Tag", ui.element("input"));
    RecordForm.required(this.name.parentNode, this.name);
    var self = this;
    this.name.addEventListener("input", function () {
      if (!self.busy() && self.error.textContent !== NAME_HINT) self.error.textContent = "";
      self.updateButton();
    });
    this.finish();
  }
  RecordForm.extend(VentilatorForm);
  VentilatorForm.prototype.updateButton = function () {
    var unnamed = !this.name.value.trim();
    this.submitButton.disabled = !this.enabled || this.busy() || unnamed;
    if (unnamed && !this.busy() && !this.error.textContent) this.error.textContent = NAME_HINT;
    else if (!unnamed && this.error.textContent === NAME_HINT) this.error.textContent = "";
    this.error.classList.toggle("phc-form-hint", this.error.textContent === NAME_HINT);
  };
  VentilatorForm.prototype.open = function () {
    if (!this.enabled) return;
    this.name.value = ""; this.error.textContent = ""; this.updateButton();
    this.show(); this.name.focus();
  };
  VentilatorForm.prototype.submit = function () {
    var name = this.name.value.trim();
    if (!this.enabled || this.busy() || !name) { this.updateButton(); return; }
    this.run({ values: { name: name } });
  };
  VentilatorForm.prototype.refresh = function (state) {
    var outcome = forms.refreshForm(this, state, SECTION);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    else if (outcome) this.updateButton();
  };
  VentilatorForm.prototype.dispose = function () { this.enabled = false; this.withdraw(); };

  /* A value as the table shows, sorts and filters it: a yes or no as its choice's value. */
  function value(record, field) {
    if (field === "supply_m3h" || field === "extract_m3h") return (record.balance || {})[field];
    if (field === "serves") return (record.zones || []).map(function (zone) { return zone.name; }).join(", ");
    var stored = record.values[field];
    return BOOLEANS.indexOf(field) >= 0 ? String(stored !== false) : stored;
  }
  /* Typed or pasted text as the update sends it: an integer quantity, a yes or no (the choice's value or its label,
     in any case), a blank identity value removed. Anything else is refused before it is sent. */
  function normalize(field, text) {
    if (BOOLEANS.indexOf(field) >= 0) {
      var word = text.toLowerCase();
      if (word === "true" || word === "yes") return true;
      if (word === "false" || word === "no") return false;
      return { ok: false, message: "Enter Yes or No." };
    }
    if (field === "quantity") {
      return /^\d+$/.test(text) && Number(text) >= 1 ? Number(text) :
        { ok: false, message: "Enter a whole number of 1 or more." };
    }
    if (field === "manufacturer" || field === "model") return text === "" ? null : text;
    return undefined;
  }
  function searchText(record) {
    var values = record.values;
    return [values.name, values.manufacturer, values.model, values.notes].concat((record.zones || []).map(
      function (zone) { return zone.name; })).filter(Boolean).join(" ");
  }
  function validate(field, entered) {
    if (FRACTIONS.indexOf(field) >= 0 && (entered < 0 || entered > 1)) return "Enter a fraction from 0 to 1.";
    if (field === "electric_efficiency_wh_m3" && entered < 0) return "Enter 0 or more.";
    return "";
  }

  function Ventilators(root, context) {
    var self = this, session = context.session, send = context.send;
    this.root = root; this.records = [];
    function changed() { panel.repaint(); }
    function allowed() {
      var reason = self.guard();
      if (reason) panel.notify(reason, "warning");
      return !reason;
    }
    function layer(node) { return (node && node.closest && node.closest(".phc-workspace")) || document.body; }
    this.newVentilator = new VentilatorForm(session, send, changed);
    this.duplicate = new forms.DuplicateForm(session, send, changed, { section: SECTION, label: LABEL,
      datasheets: false });
    this.replacement = new forms.ReplacementForm(session, send, changed, { section: SECTION, label: LABEL,
      replacement: true, allowClear: true, usedOn: "Zone", usage: function (state, id) { return self.usage(id); } });
    this.forms = [this.newVentilator, this.duplicate, this.replacement];
    this.picker = new serves.Picker(session, send, { slot: "ventilator_id", family: LABEL, notify: panel.notify,
      changed: changed });
    this.optional = new optional.OptionalValues(session, send, { action: SECTION + ".update", family: LABEL,
      fields: OPTIONAL, changed: changed });
    this.create = ui.button("+ New " + LABEL, function () { if (allowed()) self.newVentilator.open(); });
    this.triggers = Object.create(null);
    var toggles = new colourBy.HeaderToggles({ serves: { mode: BY_VENTILATOR } });
    var table = ui.element("div", "mech-ventilators-table");
    root.appendChild(table);
    this.hidden = {};
    this.inventory = new inventories.Inventory(table, session, send, panel.notify, changed, {
      tableId: SECTION, section: SECTION, action: SECTION + ".update", label: LABEL, columns: columns,
      editable: ["name", "quantity", "sensible_heat_recovery", "latent_heat_recovery", "electric_efficiency_wh_m3",
        "frost_protection_reqd", "temperature_below_defrost_used_c", "in_conditioned_space", "manufacturer",
        "model", "notes"],
      quantities: { sensible_heat_recovery: FRACTION, latent_heat_recovery: FRACTION,
        electric_efficiency_wh_m3: EFFICIENCY, temperature_below_defrost_used_c: TEMPERATURE,
        supply_m3h: AIRFLOW, extract_m3h: AIRFLOW },
      selectFields: { frost_protection_reqd: YES_NO, in_conditioned_space: YES_NO },
      optionalColumns: IDENTITY, hiddenColumns: this.hidden, normalize: normalize, validate: validate,
      // The Tag stays beside Actions while the table scrolls to Serves and the balance; search reads the Tag, the
      // identity, the notes and the Zones served.
      stickyWidths: { name: 180 }, placeholder: "Tag, model or Zone", search: searchText,
      defaultWidths: { name: 180, quantity: 84, sensible_heat_recovery: 132, latent_heat_recovery: 124,
        electric_efficiency_wh_m3: 168, frost_protection_reqd: 128, temperature_below_defrost_used_c: 140,
        in_conditioned_space: 160, serves: 220, supply_m3h: 112, extract_m3h: 112, manufacturer: 130, model: 130 },
      // An absent optional value is null, so a range edit carries it as a value and as its guard.
      rawValue: function (row, field) {
        var stored = row.record.values[field];
        if (BOOLEANS.indexOf(field) >= 0) return stored !== false;
        return stored === undefined ? null : stored;
      },
      columnMenus: { sort: ["name", "quantity", "sensible_heat_recovery", "latent_heat_recovery",
        "electric_efficiency_wh_m3", "temperature_below_defrost_used_c", "serves", "supply_m3h", "extract_m3h",
        "manufacturer", "model", "notes"],
      filter: ["name", "frost_protection_reqd", "in_conditioned_space", "manufacturer", "model"] },
      headerActions: function (field, state) { return toggles.actions(state, field); },
      value: value,
      actions: function (row) {
        var name = row.record.values.name;
        return [{ id: "optional", icon: "chevron", pressed: self.optional.set(row.record),
          label: "Optional values of " + name + ": " + self.optional.summary(row.record) },
        { id: "duplicate", icon: "duplicate", label: "Duplicate " + name },
        { id: "delete", icon: "delete", label: "Delete " + name }];
      },
      actionFor: function (row, command, control) {
        if (!allowed()) return;
        if (command.id === "optional") self.optional.open(row.record, control, layer(control));
        else if (command.id === "duplicate") self.duplicate.open(row.record);
        else self.replacement.open(row.record, self.records);
      },
      cell: function (td, row, field) {
        if (field === "serves") { self.servesCell(td, row.record); return true; }
        if (field === "supply_m3h" || field === "extract_m3h") { self.balanceCell(td, row.record, field); return true; }
        return false;
      } });
    this.inventory.emptyAction = { label: "+ New " + LABEL, run: function () {
      if (allowed()) self.newVentilator.open();
    } };
    this.forms.forEach(function (form) { root.appendChild(form.root); });
    this.layer = layer;
  }
  /* The Zones a Ventilator serves, for its delete: a replacement takes its place on each, or clearing empties
     them. */
  Ventilators.prototype.usage = function (id) {
    var record = this.records.filter(function (entry) { return entry.id === id; })[0];
    var zones = record ? record.zones || [] : [];
    if (!zones.length) return { count: 0, description: "" };
    return { count: zones.length, description: "Serves " + zones.map(function (zone) { return zone.name; })
      .join(", ") + "." };
  };
  Ventilators.prototype.servesCell = function (td, record) {
    var self = this, busy = this.inventory.busy();
    var button = serves.chips(record, function (trigger) {
      var reason = self.guard();
      if (reason) { panel.notify(reason, "warning"); return; }
      self.picker.open(record, trigger, self.layer(trigger));
    });
    button.disabled = busy;
    td.replaceChildren(button);
    td.classList.add("mech-serves");
    this.triggers[record.id] = button;
  };
  /* Supply or extract, from the host's balance: the number alone under the header's unit; amber on both cells when
     they differ by more than a tenth; a dash with the reason while it is not known. */
  Ventilators.prototype.balanceCell = function (td, record, field) {
    var balance = record.balance || {}, flow = balance[field], known = flow !== null && flow !== undefined;
    td.textContent = known ? units.format(flow, AIRFLOW, units.profile(AIRFLOW, preferences.current()),
      { showUnit: false }) : "—";
    td.classList.add("mech-balance");
    td.classList.toggle("is-imbalanced", known && Boolean(balance.imbalanced));
    td.classList.toggle("mech-muted", !known);
    ui.tooltip(td, !known ? balance.missing || "" : balance.imbalanced ?
      "Supply and extract differ by more than a tenth of the larger." : "");
  };
  /* A Locate from Export narrows the table to the Ventilators it names. */
  Ventilators.prototype.accepts = function (intent) { return Boolean(intent.ventilator_ids); };
  Ventilators.prototype.navigate = function (intent) {
    // A Locate that arrives before the Ventilators are read waits for them.
    this.located = this.records.length ? null : intent;
    if (!this.records.length) return;
    var names = this.records.filter(function (record) { return intent.ventilator_ids.indexOf(record.id) >= 0; })
      .map(function (record) { return record.values.name; });
    if (!names.length) { panel.notify("Those Ventilators are no longer in the Model.", "warning"); return; }
    // The Ventilators located show whatever narrowed the table before: other filters and the search give way to
    // the Tag filter, which the Tag column's menu clears.
    var controls = this.inventory.controls, reason = this.guard();
    if (reason) { panel.notify(reason, "warning"); return; }
    Object.keys(controls.columnFilters).forEach(function (field) {
      if (field !== "name") controls.filterColumn(field, null);
    });
    controls.setSearch("");
    controls.filterColumn("name", names);
  };
  /* A row's disclosure action, as the table last drew it. */
  Ventilators.prototype.disclosure = function (id) {
    var row = this.inventory.scroll.querySelector("[data-row-key='" + id + "']");
    return row ? Array.prototype.filter.call(row.querySelectorAll("button"), function (node) {
      return /^Optional values of /.test(node.getAttribute("aria-label") || "");
    })[0] : null;
  };
  Ventilators.prototype.guard = function () {
    if (this.forms.some(function (form) { return !form.root.hidden; })) return "Finish or cancel the open form.";
    return this.picker.guard() || this.optional.guard() || this.inventory.guard();
  };
  Ventilators.prototype.render = function (state) {
    var payload = snapshot.value(state, SECTION);
    this.records = payload ? payload.records : [];
    this.state = state;
    this.newVentilator.refresh(state); this.duplicate.refresh(state); this.replacement.refresh(state);
    this.picker.refresh(state, this.records);
    this.optional.refresh(state, this.records);
    this.inventory.externalBusy = this.picker.busy() || this.optional.busy() || this.forms.some(function (form) {
      return form.busy ? form.busy() : form.requests.busy();
    });
    this.inventory.render(state);
    // A repaint redraws each row's cell; an open picker follows the cell it was opened from.
    if (this.picker.held && this.triggers[this.picker.held.record.id]) {
      this.picker.held.bubble.trigger = this.triggers[this.picker.held.record.id];
    }
    if (this.optional.held) this.optional.retarget(this.disclosure(this.optional.held.record.id));
    if (this.located && this.records.length) this.navigate(this.located);
    this.create.disabled = !payload || this.inventory.busy();
  };
  Ventilators.prototype.dispose = function () {
    this.forms.forEach(function (form) { form.dispose(); });
    this.picker.dispose(); this.optional.dispose(); this.inventory.dispose();
  };

  systems.system({ id: FEATURE + ".ventilation", label: "Ventilation", order: 10 });
  systems.table({ system: FEATURE + ".ventilation", id: SECTION, label: "Ventilators", order: 10,
    build: function (surface, context) { return new Ventilators(surface, context); } });
  return { Ventilators: Ventilators, VentilatorForm: VentilatorForm };
});
