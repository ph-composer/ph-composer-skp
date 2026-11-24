/* Pumps › Pumps: the Model's Pumps as an equipment table (equipment_table.js). Tag, its type, quantity, power in W,
   operation in kilohours a year and whether it sits in conditioned space, the Zones it serves as chips with the Zone
   picker, then Manufacturer, Model and Notes, which the Columns menu can hide. Its internal heat gain values (the
   share of its energy that becomes a gain, and where the gain lands) stay behind each row's disclosure: the usage
   profile follows the pump's type until the user picks one, and the row action is pressed while the factor is not 1
   or a profile is chosen. A Zone may hold several pumps, so the picker adds a pump beside those a Zone holds and
   nothing is replaced. Delete offers a replacement, or clearing, for the Zones it serves (context/CONTRACTS.md,
   "Mechanical equipment"). */
PhComposerUI.define("features/mechanical/pumps", ["panel", "fields", "features/mechanical/systems",
  "features/mechanical/serves", "features/mechanical/optional_values", "features/mechanical/equipment_table"],
function (panel, fields, systems, serves, optional, equipment) {
  "use strict";
  var FEATURE = "ph_composer.mechanical", SYSTEM = FEATURE + ".pumps";
  var SECTION = FEATURE + ".pumps", LABEL = "Pump", SLOT = "pump_ids";
  // honeybee-ph's supportive device types a Pump offers, stored as their numbers.
  var TYPES = [{ value: "4", label: "Heating circulation pump" }, { value: "6", label: "Hot water circulation pump" },
    { value: "7", label: "Hot water storage load pump" }, { value: "10", label: "Other" }];
  // Where a pump's internal heat gain lands, honeybee-ph's usage profiles.
  var PROFILES = [{ value: "1", label: "All year" }, { value: "2", label: "Winter" }, { value: "3", label: "Summer" },
    { value: "4", label: "None (hot water)" }];
  var BOOLEANS = ["in_conditioned_space"];
  var NUMBERS = ["norm_energy_demand_w", "annual_period_operation_khrs"];
  var columns = [["device_type", "Type"], ["quantity", "Quantity"], ["norm_energy_demand_w", "Power"],
    ["annual_period_operation_khrs", "Operation"], ["in_conditioned_space", "In conditioned space"],
    ["serves", "Serves"]];
  var OPTIONAL = [
    { key: "ihg_utilization_factor", label: "Utilization factor", defaultValue: 1,
      field: fields.with(fields.FRACTION, { label: "Utilization factor" }) },
    { key: "ihg_usage_profile", label: "Usage profile", parse: Number,
      choices: function (record) {
        return [{ value: "", label: "From type (" + label(PROFILES, String(record.ihg_usage_profile_default)) + ")" }]
          .concat(PROFILES);
      } }];

  function label(choices, value) {
    var choice = choices.filter(function (entry) { return entry.value === value; })[0];
    return choice ? choice.label : value;
  }
  /* A value as the table shows, sorts and filters it: a type or a yes or no as its choice's value. */
  function value(record, field) {
    if (field === "serves") return (record.zones || []).map(function (zone) { return zone.name; }).join(", ");
    var stored = record.values[field];
    if (BOOLEANS.indexOf(field) >= 0) return String(stored !== false);
    return field === "device_type" ? String(stored) : stored;
  }
  /* Typed or pasted text as the update sends it: a type, an integer quantity, a yes or no. Power and operation are
     unit quantities, read in the regional number format. Anything else is refused before it is sent. */
  function normalize(field, text) {
    if (BOOLEANS.indexOf(field) >= 0) return equipment.yesNo(text);
    if (field === "device_type") return equipment.choice(TYPES, text, Number);
    if (field === "quantity") return equipment.wholeNumber(text, 1);
    return undefined;
  }
  function searchText(record) {
    var values = record.values;
    return [values.name, values.manufacturer, values.model, values.notes].concat((record.zones || []).map(
      function (zone) { return zone.name; })).filter(Boolean).join(" ");
  }

  function Pumps(root, context) {
    var self = this, session = context.session, send = context.send;
    function changed() { panel.repaint(); }
    this.triggers = Object.create(null);
    this.picker = new serves.Picker(session, send, { slot: SLOT, family: LABEL, many: true, notify: panel.notify,
      changed: changed });
    this.optional = new optional.OptionalValues(session, send, { action: SECTION + ".update", family: LABEL,
      title: "Internal heat gains", unset: "Defaults", fields: OPTIONAL, changed: changed });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-pumps", locate: "pump_ids", columns: columns,
      editable: ["device_type", "quantity", "norm_energy_demand_w", "annual_period_operation_khrs",
        "in_conditioned_space"],
      replacement: { replacement: true, allowClear: true, usedOn: "Zone",
        usage: function (state, id) { return self.usage(id); } },
      parts: [this.picker, this.optional], repainted: function () { self.retarget(); },
      inventory: {
        quantities: { norm_energy_demand_w: fields.with(fields.ELECTRIC_POWER_W, { label: "Power" }),
          annual_period_operation_khrs: fields.with(fields.KILOHOURS, { label: "Operation" }) },
        selectFields: { device_type: TYPES, in_conditioned_space: equipment.YES_NO },
        normalize: normalize,
        validate: function (field, entered) {
          return NUMBERS.indexOf(field) >= 0 && entered < 0 ? "Enter 0 or more." : "";
        },
        rawValue: function (row, field) {
          if (BOOLEANS.indexOf(field) >= 0) return row.record.values[field] !== false;
          return equipment.stored(row.record, field);
        },
        placeholder: "Tag, model or Zone", search: searchText,
        defaultWidths: { device_type: 240, quantity: 92, norm_energy_demand_w: 112,
          annual_period_operation_khrs: 156, in_conditioned_space: 160, serves: 220 },
        columnMenus: { sort: ["name", "device_type", "quantity", "norm_energy_demand_w",
          "annual_period_operation_khrs", "serves", "manufacturer", "model", "notes"],
        filter: ["name", "device_type", "in_conditioned_space", "manufacturer", "model"] },
        value: value
      },
      actions: function (row) {
        return [{ id: "optional", icon: "chevron", pressed: self.optional.set(row.record),
          label: "Internal heat gains of " + row.record.values.name + ": " + self.optional.summary(row.record) }];
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
  /* The Zones a pump serves, for its delete: a replacement takes its place in each Zone's pumps, or clearing takes
     it out of them. */
  Pumps.prototype.usage = function (id) {
    var record = this.table.records.filter(function (entry) { return entry.id === id; })[0];
    var zones = record ? record.zones || [] : [];
    if (!zones.length) return { count: 0, description: "" };
    return { count: zones.length, description: "Serves " + zones.map(function (zone) { return zone.name; })
      .join(", ") + "." };
  };
  Pumps.prototype.servesCell = function (td, record) {
    var self = this, table = this.table;
    var button = serves.chips(record, function (trigger) {
      if (table.allowed()) self.picker.open(record, trigger, table.layer(trigger));
    });
    button.disabled = this.inventory.busy();
    td.replaceChildren(button);
    td.classList.add("mech-serves");
    this.triggers[record.id] = button;
  };
  /* An open picker follows the Serves cell it was opened from, and the internal heat gains their row action. */
  Pumps.prototype.retarget = function () {
    if (this.picker.held && this.triggers[this.picker.held.record.id]) {
      this.picker.held.bubble.trigger = this.triggers[this.picker.held.record.id];
    }
    if (this.optional.held) {
      this.optional.retarget(this.table.rowAction(this.optional.held.record.id, "Internal heat gains of "));
    }
  };
  /* Each repaint draws the Serves cells again, so the map holds only the rows on screen. */
  Pumps.prototype.render = function (state, shown) {
    this.triggers = Object.create(null);
    this.table.render(state, shown);
  };
  Pumps.prototype.guard = function () { return this.table.guard(); };
  Pumps.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  Pumps.prototype.navigate = function (intent) { this.table.navigate(intent); };
  Pumps.prototype.dispose = function () { this.table.dispose(); };

  systems.system({ id: SYSTEM, label: "Pumps", order: 40 });
  systems.table({ system: SYSTEM, id: SECTION, label: "Pumps", order: 10,
    build: function (surface, context) { return new Pumps(surface, context); } });
  return { Pumps: Pumps, SECTION: SECTION, SYSTEM: SYSTEM };
});
