/* Hot Water › Heaters: the Model's Hot Water Heaters as an equipment table (equipment_table.js). Tag, the System
   each names (chosen in place), its Type, its coverage and whether it sits in conditioned space, then the efficiency
   values, of which only those its Type takes are live: an annual heat pump its performance ratio, a monthly one
   two COPs at two rating temperatures, one inside the envelope its energy factor, an electric heater none
   (context/CONTRACTS.md, "Mechanical equipment"). The others read as a dash and are read only, so a typed edit or a
   paste across them is refused whole. Coverage is stored as a fraction and shown and entered as a percentage (the
   `percent` quantity), so its drafts, guards and readback stay in the stored fraction.

   A Type is changed in the shared form dialog (equipment_table.js, VariantForm), since the new Type needs its own
   values and the old Type's values go. */
PhComposerUI.define("features/mechanical/hot_water_heaters", ["panel", "workspace", "fields",
  "features/mechanical/systems", "features/mechanical/equipment_table", "features/mechanical/hot_water"],
function (panel, ui, fields, systems, equipment, hotWater) {
  "use strict";
  var SECTION = hotWater.SECTIONS.heaters, LABEL = "Hot Water Heater";
  var FRACTION = fields.FRACTION, TEMPERATURE = fields.TEMPERATURE_C;
  var TYPES = [{ value: "electric", label: "Electric" }, { value: "heat_pump_annual", label: "Heat pump · annual" },
    { value: "heat_pump_monthly", label: "Heat pump · monthly" },
    { value: "heat_pump_inside", label: "Heat pump · inside" }];
  /* Each efficiency value: its column label and how it is entered. A number with no unit reads as a fraction does
     (the user's number format, no suffix); a temperature in °C or °F. */
  var EFFICIENCY = {
    total_system_perf_ratio: { label: "Performance ratio",
      field: fields.with(FRACTION, { label: "Performance ratio" }) },
    cop_1: { label: "COP 1", field: fields.with(FRACTION, { label: "COP 1" }) },
    ambient_temp_1_c: { label: "Rating temperature 1",
      field: fields.with(TEMPERATURE, { label: "Rating temperature 1" }) },
    cop_2: { label: "COP 2", field: fields.with(FRACTION, { label: "COP 2" }) },
    ambient_temp_2_c: { label: "Rating temperature 2",
      field: fields.with(TEMPERATURE, { label: "Rating temperature 2" }) },
    annual_energy_factor: { label: "Energy factor", field: fields.with(FRACTION, { label: "Energy factor" }) }
  };
  /* The values each Type takes, as the Heater kind declares them (features/mechanical/hot_water/heaters.rb,
     VARIANT_FIELDS); the host refuses any other combination. */
  var TYPE_FIELDS = { electric: [], heat_pump_annual: ["total_system_perf_ratio"],
    heat_pump_monthly: ["cop_1", "ambient_temp_1_c", "cop_2", "ambient_temp_2_c"],
    heat_pump_inside: ["annual_energy_factor"] };
  var EFFICIENCY_FIELDS = Object.keys(EFFICIENCY);
  var POSITIVE = ["total_system_perf_ratio", "cop_1", "cop_2", "annual_energy_factor"];
  var COVERAGE = fields.with(fields.PERCENT, { label: "Coverage" });
  var columns = [["hot_water_system_id", "System"], ["variant", "Type"], ["percent_coverage", "Coverage"],
    ["in_conditioned_space", "In conditioned space"]].concat(EFFICIENCY_FIELDS.map(function (field) {
    return [field, EFFICIENCY[field].label];
  }));

  function typeLabel(value) {
    var type = TYPES.filter(function (entry) { return entry.value === value; })[0];
    return type ? type.label : value;
  }
  /* Whether a Heater takes `field`: a value of another Type is read only. */
  function inactive(record, field) {
    return Boolean(EFFICIENCY[field]) && (TYPE_FIELDS[record.values.variant] || []).indexOf(field) < 0;
  }

  function Heaters(root, context) {
    var self = this;
    this.state = null;
    this.typeForm = new equipment.VariantForm(context.session, context.send, { section: SECTION,
      label: "hot-water-heater-type", key: "variant", word: "Type", choices: TYPES, values: EFFICIENCY,
      fields: TYPE_FIELDS, positive: POSITIVE, none: "An electric heater takes no efficiency value.",
      changed: function () { panel.repaint(); } });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-hot-water-heaters", locate: "hot_water_heater_ids",
      parent: { key: "hot_water_system_id", label: "Hot Water System", section: hotWater.SECTIONS.systems },
      columns: columns, editable: ["percent_coverage", "in_conditioned_space"].concat(EFFICIENCY_FIELDS),
      forms: [this.typeForm],
      inventory: {
        quantities: Object.assign({ percent_coverage: COVERAGE }, EFFICIENCY_FIELDS.reduce(function (all, field) {
          all[field] = EFFICIENCY[field].field; return all;
        }, {})),
        selectFields: { in_conditioned_space: equipment.YES_NO },
        normalize: function (field, text) {
          return field === "in_conditioned_space" ? equipment.yesNo(text) : undefined;
        },
        validate: function (field, entered) {
          if (field === "percent_coverage" && (entered < 0 || entered > 1)) {
            return "Enter a percentage from 0 to 100.";
          }
          if (POSITIVE.indexOf(field) >= 0 && !(entered > 0)) return "Enter a number above 0.";
          return "";
        },
        rawValue: function (row, field) {
          if (field === "in_conditioned_space") return row.record.values[field] !== false;
          return equipment.stored(row.record, field);
        },
        readOnly: function (cell) { return inactive(cell.row.record, cell.field); },
        afterCell: function (td, row, field) { self.inactiveCell(td, row.record, field); },
        defaultWidths: { hot_water_system_id: 150, variant: 170, percent_coverage: 104, in_conditioned_space: 160,
          total_system_perf_ratio: 140, cop_1: 84, ambient_temp_1_c: 168, cop_2: 84, ambient_temp_2_c: 168,
          annual_energy_factor: 120 },
        columnMenus: { sort: ["name", "hot_water_system_id", "variant", "percent_coverage", "manufacturer", "model",
          "notes"], filter: ["name", "hot_water_system_id", "variant", "in_conditioned_space", "manufacturer",
          "model"] },
        value: function (record, field) { return self.value(record, field); }
      },
      cell: function (td, row, field) { return self.cell(td, row.record, field); } });
    this.inventory = table.inventory;
    this.create = table.create;
  }
  Heaters.prototype.value = function (record, field) {
    if (field === "hot_water_system_id") return hotWater.systemName(this.state, record.values[field]);
    if (field === "variant") return typeLabel(record.values.variant);
    if (field === "in_conditioned_space") return String(record.values[field] !== false);
    return record.values[field];
  };
  /* The System and the Type are chosen in place; an efficiency value the Type does not take is a dash. */
  Heaters.prototype.cell = function (td, record, field) {
    var self = this, table = this.table;
    if (field === "hot_water_system_id") { hotWater.systemCell(table, td, record, this.state); return true; }
    if (field === "variant") {
      equipment.choiceCell(td, { choices: TYPES, value: record.values.variant, disabled: table.busy(),
        label: record.values.name + " Type", choose: function (chosen) {
          if (table.allowed()) self.typeForm.open(record, chosen);
        } });
      return true;
    }
    return false;
  };
  /* An efficiency value the Type does not take: the cell stays drawn, read only and empty (its dash), muted, with
     the reason as its tooltip; a draft it held when the Type changed elsewhere can still be cancelled. */
  Heaters.prototype.inactiveCell = function (td, record, field) {
    if (!EFFICIENCY[field]) return;
    var off = inactive(record, field);
    td.classList.toggle("mech-inactive", off);
    ui.tooltip(td, off ? typeLabel(record.values.variant) + " takes no " + EFFICIENCY[field].label + "." : "");
  };
  Heaters.prototype.render = function (state, shown) { this.state = state; this.table.render(state, shown); };
  Heaters.prototype.guard = function () { return this.table.guard(); };
  Heaters.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  Heaters.prototype.navigate = function (intent) { this.table.navigate(intent); };
  Heaters.prototype.dispose = function () { this.table.dispose(); };

  systems.table({ system: hotWater.SYSTEM, id: SECTION, label: "Heaters", order: 20,
    build: function (surface, context) { return new Heaters(surface, context); } });
  return { Heaters: Heaters, TYPE_FIELDS: TYPE_FIELDS };
});
