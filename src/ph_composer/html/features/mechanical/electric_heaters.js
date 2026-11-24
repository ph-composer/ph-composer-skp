/* Electric Heating › Heaters: the Model's Electric Heaters as an equipment table (equipment_table.js). Tag, its
   coverage, the Zones it serves as chips with the Zone picker, then Manufacturer, Model and Notes, which the Columns
   menu can hide. Coverage is the share of the heating load the heater covers, stored as a fraction and shown and
   entered as a percentage (the `percent` quantity), so its drafts, guards and readback stay in the stored fraction.
   A Zone may hold several heaters, so the picker adds a heater beside those a Zone holds and nothing is replaced;
   coverages are not added up. Delete offers a replacement, or clearing, for the Zones it serves
   (context/CONTRACTS.md, "Mechanical equipment"). */
PhComposerUI.define("features/mechanical/electric_heaters", ["panel", "fields", "features/mechanical/systems",
  "features/mechanical/serves", "features/mechanical/equipment_table"],
function (panel, fields, systems, serves, equipment) {
  "use strict";
  var FEATURE = "ph_composer.mechanical", SYSTEM = FEATURE + ".electric_heating";
  var SECTION = FEATURE + ".electric_heaters", LABEL = "Electric Heater", SLOT = "heater_ids";
  var COVERAGE = fields.with(fields.PERCENT, { label: "Coverage" });

  function value(record, field) {
    if (field === "serves") return (record.zones || []).map(function (zone) { return zone.name; }).join(", ");
    return record.values[field];
  }
  function searchText(record) {
    var values = record.values;
    return [values.name, values.manufacturer, values.model, values.notes].concat((record.zones || []).map(
      function (zone) { return zone.name; })).filter(Boolean).join(" ");
  }

  function Heaters(root, context) {
    var self = this;
    this.triggers = Object.create(null);
    this.picker = new serves.Picker(context.session, context.send, { slot: SLOT, family: LABEL, many: true,
      notify: panel.notify, changed: function () { panel.repaint(); } });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-electric-heaters", locate: "electric_heater_ids",
      columns: [["percent_coverage", "Coverage"], ["serves", "Serves"]], editable: ["percent_coverage"],
      replacement: { replacement: true, allowClear: true, usedOn: "Zone",
        usage: function (state, id) { return self.usage(id); } },
      parts: [this.picker], repainted: function () { self.retarget(); },
      inventory: {
        quantities: { percent_coverage: COVERAGE },
        validate: function (field, entered) {
          return field === "percent_coverage" && (entered < 0 || entered > 1) ? "Enter a percentage from 0 to 100." :
            "";
        },
        rawValue: function (row, field) { return equipment.stored(row.record, field); },
        placeholder: "Tag, model or Zone", search: searchText,
        defaultWidths: { percent_coverage: 104, serves: 220 },
        columnMenus: { sort: ["name", "percent_coverage", "serves", "manufacturer", "model", "notes"],
          filter: ["name", "manufacturer", "model"] },
        value: value
      },
      cell: function (td, row, field) {
        if (field !== "serves") return false;
        self.servesCell(td, row.record);
        return true;
      } });
    this.inventory = table.inventory;
    this.create = table.create;
  }
  /* The Zones a heater serves, for its delete: a replacement takes its place in each Zone's heaters, or clearing
     takes it out of them. */
  Heaters.prototype.usage = function (id) {
    var record = this.table.records.filter(function (entry) { return entry.id === id; })[0];
    var zones = record ? record.zones || [] : [];
    if (!zones.length) return { count: 0, description: "" };
    return { count: zones.length, description: "Serves " + zones.map(function (zone) { return zone.name; })
      .join(", ") + "." };
  };
  Heaters.prototype.servesCell = function (td, record) {
    var self = this, table = this.table;
    var button = serves.chips(record, function (trigger) {
      if (table.allowed()) self.picker.open(record, trigger, table.layer(trigger));
    });
    button.disabled = this.inventory.busy();
    td.replaceChildren(button);
    td.classList.add("mech-serves");
    this.triggers[record.id] = button;
  };
  /* An open picker follows the Serves cell it was opened from. */
  Heaters.prototype.retarget = function () {
    if (this.picker.held && this.triggers[this.picker.held.record.id]) {
      this.picker.held.bubble.trigger = this.triggers[this.picker.held.record.id];
    }
  };
  Heaters.prototype.render = function (state, shown) { this.table.render(state, shown); };
  Heaters.prototype.guard = function () { return this.table.guard(); };
  Heaters.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  Heaters.prototype.navigate = function (intent) { this.table.navigate(intent); };
  Heaters.prototype.dispose = function () { this.table.dispose(); };

  systems.system({ id: SYSTEM, label: "Electric Heating", order: 60 });
  systems.table({ system: SYSTEM, id: SECTION, label: "Heaters", order: 10,
    build: function (surface, context) { return new Heaters(surface, context); } });
  return { Heaters: Heaters, SECTION: SECTION, SYSTEM: SYSTEM };
});
