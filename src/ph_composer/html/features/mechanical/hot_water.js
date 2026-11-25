/* Hot Water › Systems: the Model's Hot Water Systems as an equipment table (equipment_table.js). Tag, the Zones each
   serves, its tap points, the Heaters and Tanks that name it, its piping calculation method, then Manufacturer, Model
   and Notes; another feature may contribute columns through the table's section (html/table_contributions.js). A
   System serving Zones that another System also serves in one Building Segment is pooled downstream; that note, from
   the rows' findings, sits beneath the table. Delete offers a replacement for the Zones, Heaters and Tanks that name
   it, and clearing only while no Heater or Tank does.

   The Hot Water subtab's Heaters and Tanks pills (hot_water_heaters.js, hot_water_tanks.js) share `systemCell`, the
   System a Heater or Tank names, chosen in place. */
PhComposerUI.define("features/mechanical/hot_water", ["panel", "snapshot", "workspace", "sections/colour_by",
  "features/mechanical/systems", "features/mechanical/serves", "features/mechanical/equipment_table"],
function (panel, snapshot, ui, colourBy, systems, serves, equipment) {
  "use strict";
  var FEATURE = "ph_composer.mechanical", SYSTEM = FEATURE + ".hot_water";
  var SECTION = FEATURE + ".hot_water_systems", LABEL = "Hot Water System";
  var SECTIONS = { systems: SECTION, heaters: FEATURE + ".hot_water_heaters", tanks: FEATURE + ".hot_water_tanks" };
  var BY_HOT_WATER_SYSTEM = FEATURE + ".by_hot_water_system";
  var POOLED = "mechanical.hot_water_pooled", METHOD_NOT_EXPORTED = "mechanical.method_not_exported";
  // PHX's four piping calculation methods (PhxHotWaterPipingCalcMethod), stored as their numbers.
  var METHODS = [{ value: "", label: "None" }, { value: "1", label: "Individual pipes (simplified)" },
    { value: "2", label: "Hot water calculator (simplified)" }, { value: "3", label: "Piping per unit" },
    { value: "4", label: "Piping per floor" }];
  var columns = [["serves", "Serves"], ["number_tap_points", "Tap points"], ["heaters", "Heaters"],
    ["tanks", "Tanks"], ["piping_calc_method", "Calculation method"]];

  function names(records) {
    return records.map(function (record) { return record.values.name; }).sort(ui.compareText);
  }
  function findings(record, code) {
    return (record.findings || []).filter(function (found) { return found.code === code; });
  }

  /* The System a Heater or Tank names, chosen in place from the Model's Systems: one guarded update through
     `table`, its refusal a notice and the cell back at the Model's value. */
  function systemCell(table, td, record, state) {
    var choices = ((snapshot.value(state, SECTION) || {}).records || []).slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name);
    }).map(function (system) { return { value: system.id, label: system.values.name }; });
    var current = record.values.hot_water_system_id;
    if (!choices.some(function (choice) { return choice.value === current; })) {
      choices.unshift({ value: current, label: "Missing Hot Water System" });
    }
    equipment.choiceCell(td, { choices: choices, value: current, disabled: table.busy(),
      label: record.values.name + " Hot Water System", choose: function (chosen) {
        table.choose(record, { hot_water_system_id: chosen }, { hot_water_system_id: current });
      } });
  }
  /* The name of the System a Heater or Tank names, as its column sorts and filters it. */
  function systemName(state, id) {
    var system = ((snapshot.value(state, SECTION) || {}).records || []).filter(function (entry) {
      return entry.id === id;
    })[0];
    return system ? system.values.name : "";
  }

  function Systems(root, context) {
    var self = this, session = context.session, send = context.send;
    this.members = { heaters: [], tanks: [] };
    this.picker = new serves.Picker(session, send, { slot: "hot_water_system_id", family: LABEL,
      notify: panel.notify, changed: function () { panel.repaint(); } });
    this.triggers = Object.create(null);
    var toggles = new colourBy.HeaderToggles({ serves: { mode: BY_HOT_WATER_SYSTEM } });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "mech-hot-water-systems", locate: "hot_water_system_ids",
      columns: columns, editable: ["number_tap_points", "piping_calc_method"],
      replacement: { replacement: true, usedOn: "Zone, Heater and Tank",
        // Heaters and Tanks need a System, so clearing is offered only while none names this one.
        allowClear: function (record) { return !record.heater_count && !record.tank_count; },
        usage: function (state, id) { return self.usage(id); } },
      parts: [this.picker], repainted: function () { self.repainted(); },
      inventory: {
        selectFields: { piping_calc_method: METHODS },
        normalize: function (field, text) {
          if (field === "number_tap_points") return equipment.wholeNumber(text, 1, true);
          if (field === "piping_calc_method") {
            return equipment.choice(METHODS, text, function (value) { return value === "" ? null : Number(value); });
          }
          return undefined;
        },
        placeholder: "Tag, model or Zone",
        search: function (record) {
          var values = record.values;
          return [values.name, values.manufacturer, values.model, values.notes].concat((record.zones || []).map(
            function (zone) { return zone.name; })).filter(Boolean).join(" ");
        },
        defaultWidths: { serves: 220, number_tap_points: 100, heaters: 150, tanks: 150, piping_calc_method: 250 },
        columnMenus: { sort: ["name", "serves", "number_tap_points", "heaters", "tanks", "manufacturer", "model",
          "notes"], filter: ["name", "piping_calc_method", "manufacturer", "model"] },
        headerActions: function (field, state) { return toggles.actions(state, field); },
        value: function (record, field) { return self.value(record, field); },
        afterCell: function (td, row, field) { if (field === "piping_calc_method") self.methodBadge(td, row.record); }
      },
      cell: function (td, row, field) {
        if (field === "serves") { self.servesCell(td, row.record); return true; }
        if (field === "heaters" || field === "tanks") { self.membersCell(td, row.record, field); return true; }
        return false;
      } });
    this.note = ui.element("p", "mech-table-note");
    this.note.setAttribute("role", "status");
    root.appendChild(this.note);
    this.inventory = table.inventory;
    this.create = table.create;
  }
  /* The Heaters or Tanks naming a System. */
  Systems.prototype.membersOf = function (record, kind) {
    return this.members[kind].filter(function (member) { return member.values.hot_water_system_id === record.id; });
  };
  Systems.prototype.value = function (record, field) {
    if (field === "serves") return (record.zones || []).map(function (zone) { return zone.name; }).join(", ");
    if (field === "heaters" || field === "tanks") return names(this.membersOf(record, field)).join(", ");
    var stored = record.values[field];
    return field === "piping_calc_method" ? (stored === null || stored === undefined ? "" : String(stored)) : stored;
  };
  /* What a System's delete moves: the Zones it serves, and the Heaters and Tanks that name it. */
  Systems.prototype.usage = function (id) {
    var record = this.table.records.filter(function (entry) { return entry.id === id; })[0];
    if (!record) return { count: 0, description: "" };
    var zones = record.zones || [], members = names(this.membersOf(record, "heaters"))
      .concat(names(this.membersOf(record, "tanks")));
    var parts = [];
    if (zones.length) parts.push("Serves " + zones.map(function (zone) { return zone.name; }).join(", ") + ".");
    if (members.length) {
      parts.push(members.join(", ") + (members.length === 1 ? " names it" : " name it") +
        ", so a replacement System takes " + (members.length === 1 ? "it" : "them") + " over.");
    }
    return { count: zones.length + (record.heater_count || 0) + (record.tank_count || 0),
      description: parts.join(" ") };
  };
  Systems.prototype.servesCell = function (td, record) {
    var self = this, table = this.table;
    var button = serves.chips(record, function (trigger) {
      if (table.allowed()) self.picker.open(record, trigger, table.layer(trigger));
    });
    button.disabled = this.inventory.busy();
    td.replaceChildren(button);
    td.classList.add("mech-serves");
    this.triggers[record.id] = button;
  };
  /* The Tags of the Heaters or Tanks that name it, or a muted "None". */
  Systems.prototype.membersCell = function (td, record, kind) {
    var listed = names(this.membersOf(record, kind));
    td.textContent = listed.length ? listed.join(", ") : "None";
    td.classList.toggle("mech-muted", !listed.length);
    ui.tooltip(td, listed.length ? listed.join(", ") : "No " + (kind === "heaters" ? "Heater" : "Tank") +
      " names " + record.values.name + ".");
  };
  /* A calculation method the export leaves out carries the finding's sentence on an info badge in its cell. */
  Systems.prototype.methodBadge = function (td, record) {
    var found = findings(record, METHOD_NOT_EXPORTED)[0], badge = td.querySelector(".mech-cell-badge");
    if (found && !badge) {
      badge = ui.glyph("info");
      badge.classList.add("mech-cell-badge");
      badge.setAttribute("role", "img");
      td.appendChild(badge);
    }
    td.classList.toggle("has-badge", Boolean(found));
    if (!badge) return;
    badge.hidden = !found;
    badge.setAttribute("aria-label", found ? found.message : "");
    ui.tooltip(badge, found ? found.message : "");
  };
  /* Under the table: each Building Segment's pooling note once, from the rows' findings. */
  Systems.prototype.repainted = function () {
    var seen = Object.create(null), lines = [];
    this.table.records.forEach(function (record) {
      findings(record, POOLED).forEach(function (found) {
        if (!seen[found.message]) { seen[found.message] = true; lines.push(found.message); }
      });
    });
    this.note.textContent = lines.join(" ");
    this.note.hidden = !lines.length;
    if (this.picker.held && this.triggers[this.picker.held.record.id]) {
      this.picker.held.bubble.trigger = this.triggers[this.picker.held.record.id];
    }
  };
  Systems.prototype.render = function (state, shown) {
    this.members = { heaters: (snapshot.value(state, SECTIONS.heaters) || {}).records || [],
      tanks: (snapshot.value(state, SECTIONS.tanks) || {}).records || [] };
    this.table.render(state, shown);
  };
  Systems.prototype.guard = function () { return this.table.guard(); };
  Systems.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  Systems.prototype.navigate = function (intent) { this.table.navigate(intent); };
  Systems.prototype.dispose = function () { this.table.dispose(); };

  systems.system({ id: SYSTEM, label: "Hot Water", order: 30 });
  systems.table({ system: SYSTEM, id: SECTION, label: "Systems", order: 10,
    build: function (surface, context) { return new Systems(surface, context); } });
  return { Systems: Systems, SYSTEM: SYSTEM, SECTIONS: SECTIONS, systemCell: systemCell, systemName: systemName };
});
