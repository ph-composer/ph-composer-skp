/* Ventilation › Ventilators: the Model's Ventilators as an editable equipment table (equipment_table.js). Tag
   first, then the values the export writes, the Zones each serves with the airflow balance over them, then
   Manufacturer, Model and Notes, which the Columns menu can hide. The subsoil heat exchanger and the preheated
   intake temperature stay behind each row's disclosure, blank by default. Delete offers a replacement, or clearing,
   for the Zones it serves. Every control sends a registered operation; the balance is the host's
   (context/CONTRACTS.md, "Mechanical equipment"). Another feature may contribute columns through the table's
   section (html/table_contributions.js). */
PhComposerUI.define("features/mechanical/ventilators", ["panel", "workspace", "fields", "units", "unit_preferences",
  "sections/colour_by", "features/mechanical/systems", "features/mechanical/serves",
  "features/mechanical/optional_values", "features/mechanical/equipment_table"],
function (panel, ui, fields, units, preferences, colourBy, systems, serves, optional, equipment) {
  "use strict";
  var FEATURE = "ph_composer.mechanical", SECTION = FEATURE + ".ventilators", LABEL = "Ventilator";
  var SYSTEM = FEATURE + ".ventilation";
  var BY_VENTILATOR = FEATURE + ".by_ventilator";
  var FRACTION = fields.FRACTION, EFFICIENCY = fields.ELECTRIC_EFFICIENCY, TEMPERATURE = fields.TEMPERATURE_C;
  var AIRFLOW = fields.AIRFLOW_M3H;
  var columns = [["quantity", "Quantity"], ["sensible_heat_recovery", "Sensible recovery"],
    ["latent_heat_recovery", "Latent recovery"], ["electric_efficiency_wh_m3", "Electric efficiency"],
    ["frost_protection_reqd", "Frost protection"], ["temperature_below_defrost_used_c", "Defrost below"],
    ["in_conditioned_space", "In conditioned space"], ["serves", "Serves"], ["supply_m3h", "Supply"],
    ["extract_m3h", "Extract"]];
  var BOOLEANS = ["frost_protection_reqd", "in_conditioned_space"];
  var FRACTIONS = ["sensible_heat_recovery", "latent_heat_recovery"];
  var OPTIONAL = [
    { key: "subsoil_heat_exchange_efficiency", label: "Subsoil heat exchanger",
      field: fields.with(FRACTION, { label: "Subsoil heat exchanger", allowBlank: true }) },
    { key: "preheated_intake_temperature_c", label: "Preheated intake temperature",
      field: fields.with(TEMPERATURE, { label: "Preheated intake temperature", allowBlank: true }) }];

  /* A value as the table shows, sorts and filters it: a yes or no as its choice's value. */
  function value(record, field) {
    if (field === "supply_m3h" || field === "extract_m3h") return (record.balance || {})[field];
    if (field === "serves") return (record.zones || []).map(function (zone) { return zone.name; }).join(", ");
    var stored = record.values[field];
    return BOOLEANS.indexOf(field) >= 0 ? String(stored !== false) : stored;
  }
  /* Typed or pasted text as the update sends it: an integer quantity, a yes or no. Anything else is refused before
     it is sent. */
  function normalize(field, text) {
    if (BOOLEANS.indexOf(field) >= 0) return equipment.yesNo(text);
    if (field === "quantity") return equipment.wholeNumber(text, 1);
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
    function changed() { panel.repaint(); }
    this.picker = new serves.Picker(session, send, { slot: "ventilator_id", family: LABEL, notify: panel.notify,
      changed: changed });
    this.optional = new optional.OptionalValues(session, send, { action: SECTION + ".update", family: LABEL,
      fields: OPTIONAL, changed: changed });
    this.triggers = Object.create(null);
    var toggles = new colourBy.HeaderToggles({ serves: { mode: BY_VENTILATOR } });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-ventilators-table", locate: "ventilator_ids",
      columns: columns,
      editable: ["quantity", "sensible_heat_recovery", "latent_heat_recovery", "electric_efficiency_wh_m3",
        "frost_protection_reqd", "temperature_below_defrost_used_c", "in_conditioned_space"],
      replacement: { replacement: true, allowClear: true, usedOn: "Zone",
        usage: function (state, id) { return self.usage(id); } },
      parts: [this.picker, this.optional], repainted: function () { self.retarget(); },
      inventory: {
        quantities: { sensible_heat_recovery: FRACTION, latent_heat_recovery: FRACTION,
          electric_efficiency_wh_m3: EFFICIENCY, temperature_below_defrost_used_c: TEMPERATURE,
          supply_m3h: AIRFLOW, extract_m3h: AIRFLOW },
        selectFields: { frost_protection_reqd: equipment.YES_NO, in_conditioned_space: equipment.YES_NO },
        normalize: normalize, validate: validate,
        placeholder: "Tag, model or Zone", search: searchText,
        defaultWidths: { quantity: 84, sensible_heat_recovery: 132, latent_heat_recovery: 124,
          electric_efficiency_wh_m3: 168, frost_protection_reqd: 128, temperature_below_defrost_used_c: 140,
          in_conditioned_space: 160, serves: 220, supply_m3h: 112, extract_m3h: 112 },
        rawValue: function (row, field) {
          if (BOOLEANS.indexOf(field) >= 0) return row.record.values[field] !== false;
          return equipment.stored(row.record, field);
        },
        columnMenus: { sort: ["name", "quantity", "sensible_heat_recovery", "latent_heat_recovery",
          "electric_efficiency_wh_m3", "temperature_below_defrost_used_c", "serves", "supply_m3h", "extract_m3h",
          "manufacturer", "model", "notes"],
        filter: ["name", "frost_protection_reqd", "in_conditioned_space", "manufacturer", "model"] },
        headerActions: function (field, state) { return toggles.actions(state, field); },
        value: value
      },
      actions: function (row) {
        return [{ id: "optional", icon: "chevron", pressed: self.optional.set(row.record),
          label: "Optional values of " + row.record.values.name + ": " + self.optional.summary(row.record) }];
      },
      act: function (row, command, control) { self.optional.open(row.record, control, table.layer(control)); },
      cell: function (td, row, field) {
        if (field === "serves") { self.servesCell(td, row.record); return true; }
        if (field === "supply_m3h" || field === "extract_m3h") { self.balanceCell(td, row.record, field); return true; }
        return false;
      } });
    this.inventory = table.inventory;
    this.create = table.create;
    this.duplicate = table.duplicate;
  }
  /* The Zones a Ventilator serves, for its delete: a replacement takes its place on each, or clearing empties
     them. */
  Ventilators.prototype.usage = function (id) {
    var record = this.table.records.filter(function (entry) { return entry.id === id; })[0];
    var zones = record ? record.zones || [] : [];
    if (!zones.length) return { count: 0, description: "" };
    return { count: zones.length, description: "Serves " + zones.map(function (zone) { return zone.name; })
      .join(", ") + "." };
  };
  Ventilators.prototype.servesCell = function (td, record) {
    var self = this, table = this.table;
    var button = serves.chips(record, function (trigger) {
      if (table.allowed()) self.picker.open(record, trigger, table.layer(trigger));
    });
    button.disabled = this.inventory.busy();
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
  /* An open picker follows the Serves cell it was opened from, and the optional values their row action. */
  Ventilators.prototype.retarget = function () {
    if (this.picker.held && this.triggers[this.picker.held.record.id]) {
      this.picker.held.bubble.trigger = this.triggers[this.picker.held.record.id];
    }
    if (this.optional.held) {
      this.optional.retarget(this.table.rowAction(this.optional.held.record.id, "Optional values of "));
    }
  };
  Ventilators.prototype.render = function (state, shown) { this.table.render(state, shown); };
  Ventilators.prototype.guard = function () { return this.table.guard(); };
  Ventilators.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  Ventilators.prototype.navigate = function (intent) { this.table.navigate(intent); };
  Ventilators.prototype.dispose = function () { this.table.dispose(); };

  systems.system({ id: SYSTEM, label: "Ventilation", order: 10 });
  systems.table({ system: SYSTEM, id: SECTION, label: "Ventilators", order: 10,
    build: function (surface, context) { return new Ventilators(surface, context); } });
  return { Ventilators: Ventilators, SYSTEM: SYSTEM, SECTION: SECTION };
});
