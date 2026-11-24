/* Heat Pumps › Equipment · Outdoor: the Model's outdoor heat pump models as an equipment table (equipment_table.js),
   holding the Phius Heat Pump Performance Estimator's inputs for each: its paired indoor model, its heating
   capacities at 17 °F and 47 °F (kW, or kBtu/h under IP), how heating is rated (COPs, HSPF or HSPF2) with the COP
   pair or the HSPF, its cooling capacity at 95 °F and how cooling is rated (none, EER and SEER, EER2 and SEER2, or
   IEER) with those values, then the outdoor units that install it. A rating mode reads only its own values: the
   others stay stored, muted and read only, so switching back restores them. A value the blend needs and the model
   lacks is amber, and the blend leaves the model out until it is entered.

   The Heat Pumps subtab's other pills (heat_pump_units.js, heat_pump_blended.js) share `SECTIONS`, `records`,
   `nameOf` and `referenceCell`, a reference chosen in place from another table's records. */
PhComposerUI.define("features/mechanical/heat_pumps", ["panel", "snapshot", "workspace", "fields",
  "features/mechanical/systems", "features/mechanical/equipment_table"],
function (panel, snapshot, ui, fields, systems, equipment) {
  "use strict";
  var FEATURE = "ph_composer.mechanical", SYSTEM = FEATURE + ".heat_pumps", PREFIX = SYSTEM + ".";
  var SECTIONS = { outdoorEquipment: PREFIX + "outdoor_equipment", indoorEquipment: PREFIX + "indoor_equipment",
    outdoorUnits: PREFIX + "outdoor_units", indoorUnits: PREFIX + "indoor_units",
    blended: FEATURE + ".heat_pumps_blended" };
  var SECTION = SECTIONS.outdoorEquipment, LABEL = "Heat Pump Outdoor Equipment";
  /* Every capacity and rating may be emptied: a blank stores null, and the model is incomplete again until it is
     entered. */
  function capacity(label) { return fields.with(fields.CAPACITY_KW, { label: label, allowBlank: true }); }
  function rating(label) { return fields.with(fields.FRACTION, { label: label, allowBlank: true }); }
  /* Each heating and cooling choice: the stored mode and version it writes. */
  var HEATING = [{ value: "cop_pair", label: "COPs", mode: "cop_pair", version: null },
    { value: "hspf", label: "HSPF", mode: "hspf", version: "hspf" },
    { value: "hspf2", label: "HSPF2", mode: "hspf", version: "hspf2" }];
  var COOLING = [{ value: "", label: "None", mode: null, version: null },
    { value: "eer_seer", label: "EER/SEER", mode: "eer_seer", version: "seer" },
    { value: "eer_seer2", label: "EER2/SEER2", mode: "eer_seer", version: "seer2" },
    { value: "ieer", label: "IEER", mode: "ieer", version: null }];
  /* What each mode reads, as the kind declares it (heat_pumps/outdoor_equipment.rb). */
  var HEATING_INPUTS = { cop_pair: ["cop_17f", "cop_47f"], hspf: ["hspf_value"] };
  var COOLING_INPUTS = { eer_seer: ["eer", "seer"], ieer: ["ieer"] };
  var RATINGS = ["cop_17f", "cop_47f", "hspf_value", "eer", "seer", "ieer"];
  var CAPACITIES = ["heating_cap_17f_kw", "heating_cap_47f_kw", "cooling_cap_95f_kw"];
  var CAPACITY_LABELS = { heating_cap_17f_kw: "Heating 17 °F", heating_cap_47f_kw: "Heating 47 °F",
    cooling_cap_95f_kw: "Cooling 95 °F" };
  var LABELS = { cop_17f: "COP 17 °F", cop_47f: "COP 47 °F", hspf_value: "HSPF", eer: "EER", seer: "SEER",
    ieer: "IEER" };
  var columns = [["paired_indoor_equipment_id", "Paired indoor"], ["heating_cap_17f_kw", "Heating 17 °F"],
    ["heating_cap_47f_kw", "Heating 47 °F"], ["heating_data", "Heating data"], ["cop_17f", LABELS.cop_17f],
    ["cop_47f", LABELS.cop_47f], ["hspf_value", LABELS.hspf_value], ["cooling_cap_95f_kw", "Cooling 95 °F"],
    ["cooling_data", "Cooling data"], ["eer", LABELS.eer], ["seer", LABELS.seer], ["ieer", LABELS.ieer],
    ["unit_count", "Outdoor units"]];

  function records(state, section) { return ((snapshot.value(state, section) || {}).records || []); }
  function nameOf(state, section, id) {
    var record = records(state, section).filter(function (entry) { return entry.id === id; })[0];
    return record ? record.values.name : "";
  }
  /* A reference chosen in place from `section`'s records: one guarded update through `table`, its refusal a notice
     and the cell back at the Model's value. `none` labels the empty choice of an optional reference. */
  function referenceCell(table, td, record, state, options) {
    var current = record.values[options.field] === undefined ? null : record.values[options.field];
    var choices = records(state, options.section).slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name);
    }).map(function (entry) { return { value: entry.id, label: entry.values.name }; });
    if (current && !choices.some(function (choice) { return choice.value === current; })) {
      choices.unshift({ value: current, label: "Missing " + options.label });
    }
    if (options.none) choices.unshift({ value: "", label: options.none });
    equipment.choiceCell(td, { choices: choices, value: current || "", disabled: table.busy(),
      label: record.values.name + " " + options.label, choose: function (chosen) {
        var values = {}, expected = {};
        values[options.field] = chosen || null; expected[options.field] = current;
        table.choose(record, values, expected);
      } });
  }
  function heatingChoice(values) {
    if (values.heating_rating_mode !== "hspf") return "cop_pair";
    return values.hspf_version === "hspf" ? "hspf" : "hspf2";
  }
  function coolingChoice(values) {
    if (values.cooling_rating_mode === "ieer") return "ieer";
    if (values.cooling_rating_mode !== "eer_seer") return "";
    return values.seer_version === "seer" ? "eer_seer" : "eer_seer2";
  }
  /* The ratings the model's modes read now. */
  function liveRatings(values) {
    return (HEATING_INPUTS[values.heating_rating_mode] || []).concat(COOLING_INPUTS[values.cooling_rating_mode] || []);
  }
  /* The values the blend needs that the model lacks: both heating capacities, its modes' ratings and, when it cools,
     its cooling capacity. */
  function missing(values) {
    var needed = ["heating_cap_17f_kw", "heating_cap_47f_kw"].concat(liveRatings(values));
    if (values.cooling_rating_mode) needed.push("cooling_cap_95f_kw");
    return needed.filter(function (field) {
      var value = values[field];
      return typeof value !== "number" || (field.indexOf("heating_cap") === 0 && value === 0);
    });
  }

  function OutdoorEquipment(root, context) {
    var self = this;
    this.state = null;
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-heat-pump-outdoor", locate: "hp_outdoor_equipment_ids",
      columns: columns, editable: CAPACITIES.concat(RATINGS),
      inventory: {
        quantities: CAPACITIES.concat(RATINGS).reduce(function (all, field) {
          all[field] = RATINGS.indexOf(field) >= 0 ? rating(LABELS[field]) : capacity(CAPACITY_LABELS[field]);
          return all;
        }, {}),
        validate: function (field, entered) {
          if (entered === null) return "";
          if (RATINGS.indexOf(field) >= 0 && !(entered > 0)) return "Enter a number above 0.";
          if (CAPACITIES.indexOf(field) >= 0 && entered < 0) return "Enter 0 or more.";
          return "";
        },
        readOnly: function (cell) { return self.inactive(cell.row.record, cell.field); },
        afterCell: function (td, row, field) { self.markCell(td, row.record, field); },
        defaultWidths: { paired_indoor_equipment_id: 150, heating_cap_17f_kw: 150, heating_cap_47f_kw: 150,
          heating_data: 120, cop_17f: 100, cop_47f: 100, hspf_value: 90, cooling_cap_95f_kw: 150, cooling_data: 140,
          eer: 80, seer: 80, ieer: 80, unit_count: 120 },
        columnMenus: { sort: ["name", "paired_indoor_equipment_id", "heating_cap_17f_kw", "heating_cap_47f_kw",
          "cooling_cap_95f_kw", "unit_count", "manufacturer", "model", "notes"],
        filter: ["name", "paired_indoor_equipment_id", "heating_data", "cooling_data", "manufacturer", "model"] },
        value: function (record, field) { return self.value(record, field); }
      },
      cell: function (td, row, field) { return self.cell(td, row.record, field); } });
    this.inventory = table.inventory;
    this.create = table.create;
  }
  OutdoorEquipment.prototype.value = function (record, field) {
    var values = record.values;
    if (field === "paired_indoor_equipment_id") {
      return values[field] ? nameOf(this.state, SECTIONS.indoorEquipment, values[field]) : "Not paired";
    }
    if (field === "heating_data") {
      var heating = heatingChoice(values);
      return HEATING.filter(function (entry) { return entry.value === heating; })[0].label;
    }
    if (field === "cooling_data") {
      var choice = coolingChoice(values);
      return COOLING.filter(function (entry) { return entry.value === choice; })[0].label;
    }
    if (field === "unit_count") return record.unit_count || 0;
    return values[field];
  };
  /* A rating its model's modes do not read. */
  OutdoorEquipment.prototype.inactive = function (record, field) {
    return RATINGS.indexOf(field) >= 0 && liveRatings(record.values).indexOf(field) < 0 ||
      field === "cooling_cap_95f_kw" && !record.values.cooling_rating_mode;
  };
  OutdoorEquipment.prototype.cell = function (td, record, field) {
    var table = this.table, values = record.values;
    if (field === "paired_indoor_equipment_id") {
      referenceCell(table, td, record, this.state, { field: field, section: SECTIONS.indoorEquipment,
        label: "Paired indoor", none: "Not paired" });
      return true;
    }
    if (field === "heating_data") {
      var heating = heatingChoice(values);
      equipment.choiceCell(td, { choices: HEATING, value: heating, disabled: table.busy(),
        label: values.name + " Heating data", choose: function (chosen) {
          var entry = HEATING.filter(function (option) { return option.value === chosen; })[0];
          var next = { heating_rating_mode: entry.mode };
          var expected = { heating_rating_mode: values.heating_rating_mode };
          if (entry.version) { next.hspf_version = entry.version; expected.hspf_version = values.hspf_version; }
          table.choose(record, next, expected);
        } });
      return true;
    }
    if (field === "cooling_data") {
      var cooling = coolingChoice(values);
      equipment.choiceCell(td, { choices: COOLING, value: cooling, disabled: table.busy(),
        label: values.name + " Cooling data", choose: function (chosen) {
          var entry = COOLING.filter(function (option) { return option.value === chosen; })[0];
          var next = { cooling_rating_mode: entry.mode };
          var expected = { cooling_rating_mode: values.cooling_rating_mode === undefined ? null :
            values.cooling_rating_mode };
          if (entry.version) { next.seer_version = entry.version; expected.seer_version = values.seer_version; }
          table.choose(record, next, expected);
        } });
      return true;
    }
    if (field === "unit_count") {
      td.textContent = String(record.unit_count || 0);
      td.classList.add("mech-read-only", "mech-count");
      return true;
    }
    return false;
  };
  /* A rating its modes do not read is muted and read only, with the reason; a value the blend needs and lacks is
     amber, with what it is. */
  OutdoorEquipment.prototype.markCell = function (td, record, field) {
    if (RATINGS.indexOf(field) < 0 && CAPACITIES.indexOf(field) < 0) return;
    var off = this.inactive(record, field), lacking = !off && missing(record.values).indexOf(field) >= 0;
    td.classList.toggle("mech-inactive", off);
    td.classList.toggle("mech-missing", lacking);
    ui.tooltip(td, off ? "Not read: the rating chosen in its data column does not use it." :
      lacking ? "The blend needs this value; until it is entered the blend leaves " + record.values.name +
        " out." : "");
  };
  OutdoorEquipment.prototype.render = function (state, shown) { this.state = state; this.table.render(state, shown); };
  OutdoorEquipment.prototype.guard = function () { return this.table.guard(); };
  OutdoorEquipment.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  OutdoorEquipment.prototype.navigate = function (intent) { this.table.navigate(intent); };
  OutdoorEquipment.prototype.dispose = function () { this.table.dispose(); };

  systems.system({ id: SYSTEM, label: "Heat Pumps", order: 20 });
  systems.table({ system: SYSTEM, id: SECTION, label: "Equipment · Outdoor", order: 10,
    build: function (surface, context) { return new OutdoorEquipment(surface, context); } });
  return { SYSTEM: SYSTEM, SECTIONS: SECTIONS, OutdoorEquipment: OutdoorEquipment, records: records, nameOf: nameOf,
    referenceCell: referenceCell, missing: missing, HEATING: HEATING, COOLING: COOLING };
});
