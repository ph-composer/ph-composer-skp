/* Hot Water › Pipe Types: the Model's Pipe Types as an equipment table (features/mechanical/equipment_table.js). Tag,
   Material, Diameter (one of the eight nominal sizes, labelled by its inch size in both unit systems), Insulation,
   Conductivity, Reflective, Quality, Colour and Used length (read only: the drawn length of the pipes naming it, as
   the snapshot measured it), then Notes behind the Columns menu. New asks for the Tag; Delete moves the pipes using a
   type to another, or clears them. */
PhComposerUI.define("features/piping/pipe_types", ["panel", "workspace", "fields", "units", "unit_preferences",
  "inventory_forms", "sections/colour_by", "features/mechanical/systems", "features/mechanical/equipment_table",
  "features/mechanical/hot_water", "features/piping/shared"],
function (panel, ui, fields, units, preferences, forms, colourBy, systems, equipment, hotWater, shared) {
  "use strict";
  var SECTION = shared.TYPES, LABEL = "Pipe Type";
  // honeybee-ph's material numbers and the eight nominal sizes in mm, as features/piping/type/schema.rb keeps them.
  var MATERIALS = ["Copper M", "Copper L", "Copper K", "CPVC CTS SDR", "CPVC Sch 40", "PEX", "PE", "PEX CTS SDR"]
    .map(function (label, index) { return { value: String(index + 1), label: label }; });
  var DIAMETERS = [["9.525", "3/8 in"], ["12.7", "1/2 in"], ["15.875", "5/8 in"], ["19.05", "3/4 in"],
    ["25.4", "1 in"], ["31.75", "1 1/4 in"], ["38.1", "1 1/2 in"], ["50.8", "2 in"]]
    .map(function (pair) { return { value: pair[0], label: pair[1] }; });
  var QUALITIES = [{ value: "1", label: "None" }, { value: "2", label: "Moderate" }, { value: "3", label: "Good" }];
  var CHOICES = { material: MATERIALS, diameter_mm: DIAMETERS, insulation_quality: QUALITIES,
    insulation_reflective: equipment.YES_NO };
  var USED = fields.with(fields.LENGTH_M, { label: "Used length" });
  var columns = [["material", "Material"], ["diameter_mm", "Diameter"], ["insulation_thickness_mm", "Insulation"],
    ["insulation_conductivity_w_mk", "Conductivity"], ["insulation_reflective", "Reflective"],
    ["insulation_quality", "Quality"], ["color", "Colour"], ["used_length_m", "Used length"]];

  /* The Colour cell's form, held as an equipment table part so an open one holds the tab. */
  function ColourPart(form) { this.form = form; }
  ColourPart.prototype.busy = function () { return this.form.requests.busy(); };
  ColourPart.prototype.guard = function () { return this.form.root.hidden ? null : "Finish or cancel the open form."; };
  ColourPart.prototype.refresh = function (state, records) { this.form.refresh(state, true, records); };
  ColourPart.prototype.dispose = function () { this.form.dispose(); };

  function PipeTypes(root, context) {
    var self = this;
    this.colour = new forms.ColorForm(context.session, context.send, SECTION + ".update", panel.repaint);
    var toggles = new colourBy.HeaderToggles({ name: shared.BY_TYPE });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "piping-types", locate: "pipe_type_ids", columns: columns,
      identity: [["notes", "Notes"]],
      editable: ["material", "diameter_mm", "insulation_thickness_mm", "insulation_conductivity_w_mk",
        "insulation_reflective", "insulation_quality"],
      replacement: { replacement: true, allowClear: true, usedOn: "pipe",
        usage: function (state, id) { return self.usage(id); } },
      parts: [new ColourPart(this.colour)],
      inventory: {
        quantities: { insulation_thickness_mm: fields.LENGTH_MM, used_length_m: USED,
          insulation_conductivity_w_mk: fields.with(fields.CONDUCTIVITY, { allowBlank: true }) },
        selectFields: CHOICES,
        normalize: function (field, text) {
          if (field === "insulation_reflective") return equipment.yesNo(text);
          if (CHOICES[field]) return equipment.choice(CHOICES[field], text, Number);
          return undefined;
        },
        validate: function (field, entered) {
          return field === "insulation_thickness_mm" && entered < 0 ? "Enter 0 or more." : "";
        },
        defaultWidths: { material: 130, diameter_mm: 100, insulation_thickness_mm: 120,
          insulation_conductivity_w_mk: 160, insulation_reflective: 100, insulation_quality: 110, color: 70,
          used_length_m: 130 },
        columnMenus: { sort: ["name", "material", "diameter_mm", "used_length_m", "notes"],
          filter: ["material", "diameter_mm"] },
        headerActions: function (field, state) { return toggles.actions(state, field); },
        placeholder: "Tag or notes",
        value: function (record, field) {
          var stored = record.values[field];
          if (field === "used_length_m") return record.used_length_m;
          return CHOICES[field] && stored !== undefined && stored !== null ? String(stored) : stored;
        }
      },
      cell: function (td, row, field) {
        if (field === "color") { forms.colorCell(td, row.record, self.colour, function () { return table.allowed(); });
          return true; }
        if (field === "used_length_m") { self.usedCell(td, row.record); return true; }
        return false;
      } });
    root.appendChild(this.colour.root);
    this.inventory = table.inventory;
    this.create = table.create;
  }
  /* The pipes a type's Delete moves or clears, from the drawn length the snapshot measured. */
  PipeTypes.prototype.usage = function (id) {
    var record = this.table.records.filter(function (entry) { return entry.id === id; })[0];
    var used = record ? record.used_length_m || 0 : 0;
    return { count: used > 0 ? 1 : 0, description: "Pipes " + units.format(used, fields.LENGTH_M,
      units.profile(fields.LENGTH_M, preferences.current())) + " long use it." };
  };
  PipeTypes.prototype.usedCell = function (td, record) {
    td.textContent = units.format(record.used_length_m || 0, USED, units.profile(USED, preferences.current()),
      { showUnit: false });
    td.classList.add("mech-read-only");
    ui.tooltip(td, "Read only: the drawn length of every pipe using it.");
  };
  PipeTypes.prototype.render = function (state, shown) { this.table.render(state, shown); };
  PipeTypes.prototype.guard = function () { return this.table.guard(); };
  PipeTypes.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  PipeTypes.prototype.navigate = function (intent) { this.table.navigate(intent); };
  PipeTypes.prototype.dispose = function () { this.table.dispose(); };

  systems.table({ system: hotWater.SYSTEM, id: SECTION, label: "Pipe Types", order: 40,
    build: function (surface, context) { return new PipeTypes(surface, context); } });
  return { PipeTypes: PipeTypes, DIAMETERS: DIAMETERS };
});
