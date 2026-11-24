/* Heat Pumps › Equipment · Indoor, Units · Outdoor and Units · Indoor, each an equipment table (equipment_table.js).

   Equipment · Indoor holds an indoor model's identity only: nothing on an indoor model exports.
   Units · Outdoor: the outdoor model each installs (chosen in place), how many and whether in conditioned space,
   and how many indoor units name it. Units · Indoor, grouped under the outdoor unit each names: its indoor model and
   outdoor unit (each chosen in place), the Zones it serves as chips with the Zone picker (a Zone may hold several
   indoor units), how many and whether in conditioned space. What the blend leaves out (a unit with nothing to pair,
   an outdoor unit across Building Segments) is said once per row in one note beneath the table. */
PhComposerUI.define("features/mechanical/heat_pump_units", ["panel", "workspace", "features/mechanical/systems",
  "features/mechanical/serves", "features/mechanical/equipment_table", "features/mechanical/heat_pumps"],
function (panel, ui, systems, serves, equipment, heatPumps) {
  "use strict";
  var SECTIONS = heatPumps.SECTIONS;
  var BOOLEANS = ["in_conditioned_space"];

  /* The findings beneath a table, each sentence once. */
  function paintNote(note, records) {
    var seen = Object.create(null), lines = [];
    records.forEach(function (record) {
      (record.findings || []).forEach(function (found) {
        if (!seen[found.message]) { seen[found.message] = true; lines.push(found.message); }
      });
    });
    note.textContent = lines.join(" ");
    note.hidden = !lines.length;
  }
  function tableNote(root) {
    var note = ui.element("p", "mech-table-note");
    note.setAttribute("role", "status");
    root.appendChild(note);
    return note;
  }
  /* Quantity and In conditioned space, as every unit table edits them. */
  var UNIT_INVENTORY = {
    selectFields: { in_conditioned_space: equipment.YES_NO },
    normalize: function (field, text) {
      if (field === "quantity") return equipment.wholeNumber(text, 1);
      if (BOOLEANS.indexOf(field) >= 0) return equipment.yesNo(text);
      return undefined;
    },
    rawValue: function (row, field) {
      if (BOOLEANS.indexOf(field) >= 0) return row.record.values[field] === true;
      return equipment.stored(row.record, field);
    }
  };
  function unitValue(record, field) {
    if (BOOLEANS.indexOf(field) >= 0) return String(record.values[field] === true);
    return record.values[field];
  }
  /* A view over one EquipmentTable, as systems.js takes it. */
  function delegate(View) {
    View.prototype.render = function (state, shown) {
      this.state = state;
      this.table.render(state, shown);
      if (this.note) paintNote(this.note, this.table.records);
    };
    View.prototype.guard = function () { return this.table.guard(); };
    View.prototype.accepts = function (intent) { return this.table.accepts(intent); };
    View.prototype.navigate = function (intent) { this.table.navigate(intent); };
    View.prototype.dispose = function () { this.table.dispose(); };
  }

  /* ------------------------------------------------------------- Equipment · Indoor */

  function IndoorEquipment(root, context) {
    this.table = new equipment.EquipmentTable(root, context, {
      section: SECTIONS.indoorEquipment, label: "Heat Pump Indoor Equipment", className: "mech-heat-pump-indoor",
      columns: [], editable: [],
      // An outdoor model's pairing may be emptied; an indoor unit needs its model, so clearing waits until none does.
      replacement: heatPumps.replacement({ usedOn: "outdoor model and indoor unit",
        referrers: [[SECTIONS.outdoorEquipment, "paired_indoor_equipment_id"],
          [SECTIONS.indoorUnits, "indoor_equipment_id"]],
        clearable: function (record) { return !record.unit_count; } }),
      inventory: { columnMenus: { sort: ["name", "manufacturer", "model", "notes"],
        filter: ["name", "manufacturer", "model"] } } });
    this.inventory = this.table.inventory;
    this.create = this.table.create;
  }
  delegate(IndoorEquipment);

  /* ------------------------------------------------------------- Units · Outdoor */

  function OutdoorUnits(root, context) {
    var self = this;
    this.state = null;
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTIONS.outdoorUnits, label: "Heat Pump Outdoor Unit", className: "mech-heat-pump-outdoor-units",
      locate: "hp_outdoor_unit_ids",
      parent: { key: "outdoor_equipment_id", label: "Outdoor equipment", section: SECTIONS.outdoorEquipment },
      replacement: heatPumps.replacement({ usedOn: "indoor unit",
        referrers: [[SECTIONS.indoorUnits, "outdoor_unit_id"]], clearable: function () { return false; } }),
      columns: [["outdoor_equipment_id", "Outdoor equipment"], ["quantity", "Quantity"],
        ["in_conditioned_space", "In conditioned space"], ["indoor_unit_count", "Indoor units"]],
      editable: ["quantity", "in_conditioned_space"],
      inventory: Object.assign({}, UNIT_INVENTORY, {
        defaultWidths: { outdoor_equipment_id: 180, quantity: 96, in_conditioned_space: 160, indoor_unit_count: 120 },
        columnMenus: { sort: ["name", "outdoor_equipment_id", "quantity", "indoor_unit_count", "manufacturer",
          "model", "notes"],
        filter: ["name", "outdoor_equipment_id", "in_conditioned_space", "manufacturer", "model"] },
        value: function (record, field) {
          if (field === "outdoor_equipment_id") {
            return heatPumps.nameOf(self.state, SECTIONS.outdoorEquipment, record.values[field]);
          }
          if (field === "indoor_unit_count") return record.indoor_unit_count || 0;
          return unitValue(record, field);
        }
      }),
      cell: function (td, row, field) {
        if (field === "outdoor_equipment_id") {
          heatPumps.referenceCell(table, td, row.record, self.state, { field: field,
            section: SECTIONS.outdoorEquipment, label: "Outdoor equipment" });
          return true;
        }
        if (field === "indoor_unit_count") {
          td.textContent = String(row.record.indoor_unit_count || 0);
          td.classList.add("mech-read-only", "mech-count");
          return true;
        }
        return false;
      } });
    this.note = tableNote(root);
    this.inventory = table.inventory;
    this.create = table.create;
  }
  delegate(OutdoorUnits);

  /* ------------------------------------------------------------- Units · Indoor */

  var SLOT = "hp_indoor_unit_ids", OUTDOOR_UNIT = "outdoor_unit_id";

  function IndoorUnits(root, context) {
    var self = this;
    this.state = null;
    this.triggers = Object.create(null);
    this.picker = new serves.Picker(context.session, context.send, { slot: SLOT, family: "Heat Pump Indoor Unit",
      many: true, notify: panel.notify, changed: function () { panel.repaint(); } });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTIONS.indoorUnits, label: "Heat Pump Indoor Unit", className: "mech-heat-pump-indoor-units",
      locate: "hp_indoor_unit_ids",
      parents: [{ key: "indoor_equipment_id", label: "Indoor equipment", section: SECTIONS.indoorEquipment },
        { key: OUTDOOR_UNIT, label: "Outdoor unit", section: SECTIONS.outdoorUnits }],
      columns: [["indoor_equipment_id", "Indoor equipment"], [OUTDOOR_UNIT, "Outdoor unit"], ["serves", "Serves"],
        ["quantity", "Quantity"], ["in_conditioned_space", "In conditioned space"]],
      editable: ["quantity", "in_conditioned_space"],
      replacement: heatPumps.replacement({ usedOn: "Zone", zones: SECTIONS.indoorUnits,
        clearable: function () { return true; } }),
      parts: [this.picker], repainted: function () { self.repainted(); },
      inventory: Object.assign({}, UNIT_INVENTORY, {
        groups: [[OUTDOOR_UNIT, "Outdoor unit"]],
        group: function (record) { return { label: self.outdoorLabel(record.values[OUTDOOR_UNIT]) }; },
        placeholder: "Tag, model or Zone",
        search: function (record) {
          var values = record.values;
          return [values.name, values.manufacturer, values.model, values.notes].concat((record.zones || []).map(
            function (zone) { return zone.name; })).filter(Boolean).join(" ");
        },
        defaultWidths: { indoor_equipment_id: 170, outdoor_unit_id: 150, serves: 220, quantity: 96,
          in_conditioned_space: 160 },
        columnMenus: { sort: ["name", "indoor_equipment_id", OUTDOOR_UNIT, "serves", "quantity", "manufacturer",
          "model", "notes"], filter: ["name", "indoor_equipment_id", OUTDOOR_UNIT, "in_conditioned_space",
          "manufacturer", "model"] },
        value: function (record, field) { return self.value(record, field); }
      }),
      cell: function (td, row, field) { return self.cell(td, row.record, field); } });
    // The units sit under the outdoor unit they name until the user groups them otherwise.
    table.inventory.controls.groupBy.value = OUTDOOR_UNIT;
    this.note = tableNote(root);
    this.inventory = table.inventory;
    this.create = table.create;
  }
  delegate(IndoorUnits);
  /* An outdoor unit as its group reads: its Tag and the model it installs. */
  IndoorUnits.prototype.outdoorLabel = function (id) {
    var unit = heatPumps.records(this.state, SECTIONS.outdoorUnits).filter(function (entry) {
      return entry.id === id;
    })[0];
    if (!unit) return "Missing outdoor unit";
    var model = heatPumps.nameOf(this.state, SECTIONS.outdoorEquipment, unit.values.outdoor_equipment_id);
    return unit.values.name + (model ? " · " + model : "");
  };
  IndoorUnits.prototype.value = function (record, field) {
    if (field === "indoor_equipment_id") {
      return heatPumps.nameOf(this.state, SECTIONS.indoorEquipment, record.values[field]);
    }
    if (field === OUTDOOR_UNIT) return heatPumps.nameOf(this.state, SECTIONS.outdoorUnits, record.values[field]);
    if (field === "serves") return (record.zones || []).map(function (zone) { return zone.name; }).join(", ");
    return unitValue(record, field);
  };
  IndoorUnits.prototype.cell = function (td, record, field) {
    var self = this, table = this.table;
    if (field === "indoor_equipment_id" || field === OUTDOOR_UNIT) {
      heatPumps.referenceCell(table, td, record, this.state, { field: field,
        section: field === OUTDOOR_UNIT ? SECTIONS.outdoorUnits : SECTIONS.indoorEquipment,
        label: field === OUTDOOR_UNIT ? "Outdoor unit" : "Indoor equipment" });
      return true;
    }
    if (field === "serves") {
      var button = serves.chips(record, function (trigger) {
        if (table.allowed()) self.picker.open(record, trigger, table.layer(trigger));
      });
      button.disabled = this.inventory.busy();
      td.replaceChildren(button);
      td.classList.add("mech-serves");
      this.triggers[record.id] = button;
      return true;
    }
    return false;
  };
  IndoorUnits.prototype.repainted = function () {
    if (this.picker.held && this.triggers[this.picker.held.record.id]) {
      this.picker.held.bubble.trigger = this.triggers[this.picker.held.record.id];
    }
  };

  systems.table({ system: heatPumps.SYSTEM, id: SECTIONS.indoorEquipment, label: "Equipment · Indoor", order: 20,
    build: function (surface, context) { return new IndoorEquipment(surface, context); } });
  systems.table({ system: heatPumps.SYSTEM, id: SECTIONS.outdoorUnits, label: "Units · Outdoor", order: 30,
    build: function (surface, context) { return new OutdoorUnits(surface, context); } });
  systems.table({ system: heatPumps.SYSTEM, id: SECTIONS.indoorUnits, label: "Units · Indoor", order: 40,
    build: function (surface, context) { return new IndoorUnits(surface, context); } });
  return { IndoorEquipment: IndoorEquipment, OutdoorUnits: OutdoorUnits, IndoorUnits: IndoorUnits };
});
