/* Hot Water › Tanks: the Model's Hot Water Tanks as an equipment table (equipment_table.js). Tag, the System each
   names (chosen in place), its Role, the export slot its Role and Tag give it among its System's Tanks (read only,
   the host's tank slotting; a Tank its Role has no free slot for is amber, and the export leaves it out), its Type,
   quantity, capacity in litres or US gallons, standby losses and whether it sits in conditioned space, then the rest
   of honeybee-ph's tank values, then Manufacturer, Model and Notes. */
PhComposerUI.define("features/mechanical/hot_water_tanks", ["workspace", "fields", "features/mechanical/systems",
  "features/mechanical/equipment_table", "features/mechanical/hot_water"],
function (ui, fields, systems, equipment, hotWater) {
  "use strict";
  var SECTION = hotWater.SECTIONS.tanks, LABEL = "Hot Water Tank";
  var UNSLOTTED = "mechanical.tank_unslotted";
  var ROLES = [{ value: "storage", label: "Storage" }, { value: "buffer", label: "Buffer" },
    { value: "solar", label: "Solar" }];
  // honeybee-ph's tank types, stored as its enumeration reads them back.
  var TYPES = [{ value: "0-NO STORAGE TANK", label: "No storage tank" },
    { value: "1-DHW AND HEATING", label: "Hot water and heating" }, { value: "2-DHW ONLY", label: "Hot water only" }];
  var SLOTS = { tank_1: "Tank 1", tank_2: "Tank 2", tank_buffer: "Buffer tank", tank_solar: "Solar tank" };
  var BOOLEANS = ["in_conditioned_space", "solar_connection"];
  var NON_NEGATIVE = ["storage_capacity_l", "standby_losses_w_k", "storage_loss_rate_w_k", "solar_losses_w"];
  var columns = [["hot_water_system_id", "System"], ["role", "Role"], ["slot", "Export slot"],
    ["tank_type", "Type"], ["quantity", "Quantity"], ["storage_capacity_l", "Capacity"],
    ["standby_losses_w_k", "Standby losses"], ["in_conditioned_space", "In conditioned space"],
    ["standby_fraction", "Standby fraction"], ["storage_loss_rate_w_k", "Storage loss rate"],
    ["room_temp_c", "Room temperature"], ["water_temp_c", "Water temperature"],
    ["solar_connection", "Solar connection"], ["solar_losses_w", "Solar losses"]];

  function label(choices, value) {
    var choice = choices.filter(function (entry) { return entry.value === value; })[0];
    return choice ? choice.label : value;
  }
  function unslotted(record) {
    return (record.findings || []).filter(function (found) { return found.code === UNSLOTTED; })[0];
  }

  function Tanks(root, context) {
    var self = this;
    this.state = null;
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-hot-water-tanks", locate: "hot_water_tank_ids",
      parent: { key: "hot_water_system_id", label: "Hot Water System", section: hotWater.SECTIONS.systems },
      columns: columns,
      editable: ["role", "tank_type", "quantity", "storage_capacity_l", "standby_losses_w_k", "in_conditioned_space",
        "standby_fraction", "storage_loss_rate_w_k", "room_temp_c", "water_temp_c", "solar_connection",
        "solar_losses_w"],
      inventory: {
        quantities: { storage_capacity_l: fields.VOLUME_L, standby_losses_w_k: fields.HEAT_LOSS,
          standby_fraction: fields.FRACTION, storage_loss_rate_w_k: fields.HEAT_LOSS,
          room_temp_c: fields.TEMPERATURE_C, water_temp_c: fields.TEMPERATURE_C, solar_losses_w: fields.POWER_W },
        selectFields: { role: ROLES, tank_type: TYPES, in_conditioned_space: equipment.YES_NO,
          solar_connection: equipment.YES_NO },
        normalize: function (field, text) {
          if (BOOLEANS.indexOf(field) >= 0) return equipment.yesNo(text);
          if (field === "quantity") return equipment.wholeNumber(text, 1);
          if (field === "role") return equipment.choice(ROLES, text);
          if (field === "tank_type") return equipment.choice(TYPES, text);
          return undefined;
        },
        validate: function (field, entered) {
          if (field === "standby_fraction" && (entered < 0 || entered > 1)) return "Enter a fraction from 0 to 1.";
          if (NON_NEGATIVE.indexOf(field) >= 0 && entered < 0) return "Enter 0 or more.";
          return "";
        },
        rawValue: function (row, field) {
          if (BOOLEANS.indexOf(field) >= 0) return row.record.values[field] === true;
          return equipment.stored(row.record, field);
        },
        defaultWidths: { hot_water_system_id: 150, role: 112, slot: 128, tank_type: 180, quantity: 92,
          storage_capacity_l: 120, standby_losses_w_k: 210, in_conditioned_space: 160, standby_fraction: 140,
          storage_loss_rate_w_k: 220, room_temp_c: 180, water_temp_c: 180, solar_connection: 140,
          solar_losses_w: 160 },
        columnMenus: { sort: ["name", "hot_water_system_id", "role", "slot", "tank_type", "quantity",
          "storage_capacity_l", "standby_losses_w_k", "manufacturer", "model", "notes"],
        filter: ["name", "hot_water_system_id", "role", "slot", "tank_type", "in_conditioned_space", "manufacturer",
          "model"] },
        value: function (record, field) { return self.value(record, field); }
      },
      cell: function (td, row, field) {
        if (field === "hot_water_system_id") { hotWater.systemCell(table, td, row.record, self.state); return true; }
        if (field === "slot") { self.slotCell(td, row.record); return true; }
        return false;
      } });
    this.inventory = table.inventory;
    this.create = table.create;
  }
  Tanks.prototype.value = function (record, field) {
    if (field === "hot_water_system_id") return hotWater.systemName(this.state, record.values[field]);
    if (field === "slot") return record.slot ? SLOTS[record.slot] : "No slot left";
    if (BOOLEANS.indexOf(field) >= 0) return String(record.values[field] === true);
    return record.values[field];
  };
  /* The slot the export puts it in, read only; amber with the reason when its Role has none free. */
  Tanks.prototype.slotCell = function (td, record) {
    var missing = unslotted(record);
    td.textContent = record.slot ? SLOTS[record.slot] : "No slot left";
    td.classList.add("mech-read-only");
    td.classList.toggle("is-unslotted", !record.slot);
    ui.tooltip(td, missing ? missing.message : "Read only: set by its Role and Tag among its System's " +
      label(ROLES, record.values.role).toLowerCase() + " Tanks.");
  };
  Tanks.prototype.render = function (state, shown) { this.state = state; this.table.render(state, shown); };
  Tanks.prototype.guard = function () { return this.table.guard(); };
  Tanks.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  Tanks.prototype.navigate = function (intent) { this.table.navigate(intent); };
  Tanks.prototype.dispose = function () { this.table.dispose(); };

  systems.table({ system: hotWater.SYSTEM, id: SECTION, label: "Tanks", order: 30,
    build: function (surface, context) { return new Tanks(surface, context); } });
  return { Tanks: Tanks };
});
