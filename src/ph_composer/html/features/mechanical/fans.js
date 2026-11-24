/* Fans › Fans: the Model's Fans as an equipment table (equipment_table.js). Tag, its type, quantity, exhaust flow,
   runtime in minutes a year and power in W (blank when its electricity is not modelled), the Zones it serves as chips
   with the Zone picker, then Manufacturer, Model and Notes, which the Columns menu can hide. Its electric values
   (whether it sits in conditioned space, and an operation in kilohours a year that overrides the one its runtime
   gives) stay behind each row's disclosure; they export only with Power. The row action is pressed while the fan is
   outside conditioned space or names an operation. A Zone may hold several fans, so the picker adds a fan beside those
   a Zone holds and nothing is replaced. Delete offers a replacement, or clearing, for the Zones it serves
   (context/CONTRACTS.md, "Mechanical equipment"). */
PhComposerUI.define("features/mechanical/fans", ["panel", "fields", "units", "unit_preferences",
  "features/mechanical/systems", "features/mechanical/serves", "features/mechanical/optional_values",
  "features/mechanical/equipment_table"],
function (panel, fields, units, preferences, systems, serves, optional, equipment) {
  "use strict";
  var FEATURE = "ph_composer.mechanical", SYSTEM = FEATURE + ".fans";
  var SECTION = FEATURE + ".fans", LABEL = "Fan", SLOT = "fan_ids";
  // honeybee-ph's exhaust ventilator classes a Fan offers, stored by name.
  var TYPES = [{ value: "kitchen_hood", label: "Kitchen hood" }, { value: "dryer", label: "Dryer" },
    { value: "user_defined", label: "User-defined" }];
  var NUMBERS = ["exhaust_flow_rate_m3h", "annual_runtime_minutes", "norm_energy_demand_w"];
  var POWER = fields.with(fields.ELECTRIC_POWER_W, { label: "Power", allowBlank: true });
  var OPERATION = fields.with(fields.KILOHOURS, { label: "Operation", allowBlank: true });
  var columns = [["exhaust_type", "Type"], ["quantity", "Quantity"], ["exhaust_flow_rate_m3h", "Flow"],
    ["annual_runtime_minutes", "Runtime"], ["norm_energy_demand_w", "Power"], ["serves", "Serves"]];
  var OPTIONAL = [
    { key: "in_conditioned_space", label: "In conditioned space", defaultValue: true,
      parse: function (text) { return text === "true"; },
      choices: function () { return equipment.YES_NO; } },
    { key: "annual_period_operation_khrs", label: "Operation", field: OPERATION,
      placeholder: function (record) {
        return "From runtime (" + units.format(record.annual_period_operation_khrs_default, OPERATION,
          units.profile(OPERATION, preferences.current())) + ")";
      } }];

  /* A value as the table shows, sorts and filters it: a type as its choice's value. */
  function value(record, field) {
    if (field === "serves") return (record.zones || []).map(function (zone) { return zone.name; }).join(", ");
    return record.values[field];
  }
  /* Typed or pasted text as the update sends it: a type, an integer quantity. Flow, runtime and power are unit
     quantities, read in the regional number format. Anything else is refused before it is sent. */
  function normalize(field, text) {
    if (field === "exhaust_type") return equipment.choice(TYPES, text);
    if (field === "quantity") return equipment.wholeNumber(text, 1);
    return undefined;
  }
  function searchText(record) {
    var values = record.values;
    return [values.name, values.manufacturer, values.model, values.notes].concat((record.zones || []).map(
      function (zone) { return zone.name; })).filter(Boolean).join(" ");
  }

  function Fans(root, context) {
    var self = this, session = context.session, send = context.send;
    function changed() { panel.repaint(); }
    this.triggers = Object.create(null);
    this.picker = new serves.Picker(session, send, { slot: SLOT, family: LABEL, many: true, notify: panel.notify,
      changed: changed });
    this.optional = new optional.OptionalValues(session, send, { action: SECTION + ".update", family: LABEL,
      title: "Electric values", unset: "Defaults", fields: OPTIONAL, changed: changed });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-fans", locate: "fan_ids", columns: columns,
      editable: ["exhaust_type", "quantity", "exhaust_flow_rate_m3h", "annual_runtime_minutes",
        "norm_energy_demand_w"],
      replacement: { replacement: true, allowClear: true, usedOn: "Zone",
        usage: function (state, id) { return self.usage(id); } },
      parts: [this.picker, this.optional], repainted: function () { self.retarget(); },
      inventory: {
        quantities: { exhaust_flow_rate_m3h: fields.with(fields.AIRFLOW_M3H, { label: "Flow" }),
          annual_runtime_minutes: fields.with(fields.ANNUAL_MINUTES, { label: "Runtime" }),
          norm_energy_demand_w: POWER },
        selectFields: { exhaust_type: TYPES },
        normalize: normalize,
        validate: function (field, entered) {
          return NUMBERS.indexOf(field) >= 0 && entered < 0 ? "Enter 0 or more." : "";
        },
        rawValue: function (row, field) { return equipment.stored(row.record, field); },
        placeholder: "Tag, model or Zone", search: searchText,
        defaultWidths: { exhaust_type: 150, quantity: 92, exhaust_flow_rate_m3h: 112, annual_runtime_minutes: 128,
          norm_energy_demand_w: 104, serves: 220 },
        columnMenus: { sort: ["name", "exhaust_type", "quantity", "exhaust_flow_rate_m3h", "annual_runtime_minutes",
          "norm_energy_demand_w", "serves", "manufacturer", "model", "notes"],
        filter: ["name", "exhaust_type", "manufacturer", "model"] },
        value: value
      },
      actions: function (row) {
        var unpowered = row.record.values.norm_energy_demand_w === undefined ? " (exported only with Power)" : "";
        return [{ id: "optional", icon: "chevron", pressed: self.optional.set(row.record),
          label: "Electric values of " + row.record.values.name + ": " + self.optional.summary(row.record) +
            unpowered }];
      },
      act: function (row, command, control) { self.optional.open(row.record, control, table.layer(control)); },
      cell: function (td, row, field) {
        if (field !== "serves") return false;
        self.servesCell(td, row.record);
        return true;
      } });
    this.inventory = table.inventory;
    this.create = table.create;
  }
  /* The Zones a fan serves, for its delete: a replacement takes its place in each Zone's fans, or clearing takes it
     out of them. */
  Fans.prototype.usage = function (id) {
    var record = this.table.records.filter(function (entry) { return entry.id === id; })[0];
    var zones = record ? record.zones || [] : [];
    if (!zones.length) return { count: 0, description: "" };
    return { count: zones.length, description: "Serves " + zones.map(function (zone) { return zone.name; })
      .join(", ") + "." };
  };
  Fans.prototype.servesCell = function (td, record) {
    var self = this, table = this.table;
    var button = serves.chips(record, function (trigger) {
      if (table.allowed()) self.picker.open(record, trigger, table.layer(trigger));
    });
    button.disabled = this.inventory.busy();
    td.replaceChildren(button);
    td.classList.add("mech-serves");
    this.triggers[record.id] = button;
  };
  /* An open picker follows the Serves cell it was opened from, and the electric values their row action. */
  Fans.prototype.retarget = function () {
    if (this.picker.held && this.triggers[this.picker.held.record.id]) {
      this.picker.held.bubble.trigger = this.triggers[this.picker.held.record.id];
    }
    if (this.optional.held) {
      this.optional.retarget(this.table.rowAction(this.optional.held.record.id, "Electric values of "));
    }
  };
  /* Each repaint draws the Serves cells again, so the map holds only the rows on screen. */
  Fans.prototype.render = function (state, shown) {
    this.triggers = Object.create(null);
    this.table.render(state, shown);
  };
  Fans.prototype.guard = function () { return this.table.guard(); };
  Fans.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  Fans.prototype.navigate = function (intent) { this.table.navigate(intent); };
  Fans.prototype.dispose = function () { this.table.dispose(); };

  systems.system({ id: SYSTEM, label: "Fans", order: 50 });
  systems.table({ system: SYSTEM, id: SECTION, label: "Fans", order: 10,
    build: function (surface, context) { return new Fans(surface, context); } });
  return { Fans: Fans, SECTION: SECTION, SYSTEM: SYSTEM };
});
