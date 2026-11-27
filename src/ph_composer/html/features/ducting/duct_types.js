/* Ventilation › Duct Types: the Model's Duct Types as an equipment table (features/mechanical/equipment_table.js). Tag,
   Shape, the Round shape's Diameter or the Rectangular shape's Width and Height (the other shape's read as a dash),
   Insulation, Conductivity, Reflective, Colour and Used length (read only: every duct naming it, each line times its
   quantity, as the snapshot measured it), then Notes behind the Columns menu. A Shape change asks for the new shape's
   dimensions in the shared dialog before it sends one update. New asks for the Tag and makes a 160 mm round type;
   Delete moves the ducts using a type to another, or clears them. */
PhComposerUI.define("features/ducting/duct_types", ["panel", "workspace", "fields", "inventory_forms",
  "sections/colour_by", "features/mechanical/systems", "features/mechanical/equipment_table",
  "features/mechanical/ventilators", "line_groups/shared", "features/ducting/shared"],
function (panel, ui, fields, forms, colourBy, systems, equipment, ventilators, lineGroups, shared) {
  "use strict";
  var SECTION = shared.TYPES, LABEL = "Duct Type";
  var SHAPES = [{ value: "round", label: "Round" }, { value: "rectangular", label: "Rectangular" }];
  /* Each shape's dimensions, as features/ducting/type/schema.rb keeps them; the host refuses any other. */
  var SHAPE_FIELDS = { round: ["diameter_mm"], rectangular: ["width_mm", "height_mm"] };
  var DIMENSIONS = { diameter_mm: "Diameter", width_mm: "Width", height_mm: "Height" };
  var SIZES = Object.keys(DIMENSIONS).reduce(function (all, field) {
    all[field] = { label: DIMENSIONS[field], field: fields.with(fields.LENGTH_MM, { label: DIMENSIONS[field] }) };
    return all;
  }, {});
  var CHOICES = { insulation_reflective: equipment.YES_NO };
  var columns = [["shape", "Shape"], ["diameter_mm", "Diameter"], ["width_mm", "Width"], ["height_mm", "Height"],
    ["insulation_thickness_mm", "Insulation"], ["insulation_conductivity_w_mk", "Conductivity"],
    ["insulation_reflective", "Reflective"], ["color", "Colour"], ["used_length_m", "Used length"]];

  /* Whether a type takes `field`: the other shape's dimensions are read only. */
  function inactive(record, field) {
    return Boolean(DIMENSIONS[field]) && (SHAPE_FIELDS[record.values.shape] || []).indexOf(field) < 0;
  }
  function shapeLabel(value) {
    var shape = SHAPES.filter(function (entry) { return entry.value === value; })[0];
    return shape ? shape.label : value;
  }

  function DuctTypes(root, context) {
    var self = this;
    this.colour = new forms.ColorForm(context.session, context.send, SECTION + ".update", panel.repaint,
      { defaultColor: lineGroups.assignedColor });
    this.shapeForm = new equipment.VariantForm(context.session, context.send, { section: SECTION,
      label: "duct-type-shape", key: "shape", word: "Shape", choices: SHAPES, values: SIZES, fields: SHAPE_FIELDS,
      positive: Object.keys(DIMENSIONS), none: "", changed: function () { panel.repaint(); } });
    var toggles = new colourBy.HeaderToggles({ name: shared.BY_TYPE });
    var table = this.table = new equipment.EquipmentTable(root, context, {
      section: SECTION, label: LABEL, className: "ducting-types", locate: "duct_type_ids", columns: columns,
      identity: [["notes", "Notes"]], forms: [this.shapeForm],
      editable: Object.keys(DIMENSIONS).concat(["insulation_thickness_mm", "insulation_conductivity_w_mk",
        "insulation_reflective"]),
      replacement: { replacement: true, allowClear: true, usedOn: "duct",
        usage: function (state, id) { return lineGroups.usage(shared.SPEC, self.table.records, id); } },
      parts: [new lineGroups.ColourPart(this.colour)],
      inventory: {
        quantities: { diameter_mm: SIZES.diameter_mm.field, width_mm: SIZES.width_mm.field,
          height_mm: SIZES.height_mm.field, insulation_thickness_mm: fields.LENGTH_MM, used_length_m: lineGroups.USED,
          insulation_conductivity_w_mk: fields.with(fields.CONDUCTIVITY, { allowBlank: true }) },
        selectFields: CHOICES,
        normalize: function (field, text) {
          return field === "insulation_reflective" ? equipment.yesNo(text) : undefined;
        },
        validate: function (field, entered) {
          if (field === "insulation_thickness_mm" && entered < 0) return "Enter 0 or more.";
          var sized = DIMENSIONS[field] || field === "insulation_conductivity_w_mk";
          return sized && entered !== null && !(entered > 0) ? "Enter a number above 0." : "";
        },
        rawValue: function (row, field) {
          if (field === "insulation_reflective") return row.record.values[field] !== false;
          return equipment.stored(row.record, field);
        },
        readOnly: function (cell) { return inactive(cell.row.record, cell.field); },
        afterCell: function (td, row, field) {
          if (!DIMENSIONS[field]) return;
          var off = inactive(row.record, field);
          td.classList.toggle("mech-inactive", off);
          ui.tooltip(td, off ? shapeLabel(row.record.values.shape) + " takes no " + DIMENSIONS[field] + "." : "");
        },
        defaultWidths: { shape: 130, diameter_mm: 110, width_mm: 100, height_mm: 100, insulation_thickness_mm: 120,
          insulation_conductivity_w_mk: 160, insulation_reflective: 100, color: 70, used_length_m: 130 },
        columnMenus: { sort: ["name", "shape", "used_length_m", "notes"], filter: ["shape"] },
        headerActions: function (field, state) { return toggles.actions(state, field); },
        placeholder: "Tag or notes",
        value: function (record, field) {
          if (field === "used_length_m") return record.used_length_m;
          if (field === "shape") return shapeLabel(record.values.shape);
          return field === "insulation_reflective" ? String(record.values[field] !== false) : record.values[field];
        }
      },
      cell: function (td, row, field) {
        var record = row.record;
        if (field === "shape") {
          equipment.choiceCell(td, { choices: SHAPES, value: record.values.shape, disabled: table.busy(),
            label: record.values.name + " Shape", choose: function (chosen) {
              if (table.allowed()) self.shapeForm.open(record, chosen);
            } });
          return true;
        }
        if (field === "color") {
          forms.colorCell(td, record, self.colour, function () { return table.allowed(); });
          return true;
        }
        if (field === "used_length_m") {
          lineGroups.usedCell(td, record, "Read only: the length of every duct using it, each line times its " +
            "quantity.");
          return true;
        }
        return false;
      } });
    root.appendChild(this.colour.root);
    this.inventory = table.inventory;
    this.create = table.create;
  }
  DuctTypes.prototype.render = function (state, shown) { this.table.render(state, shown); };
  DuctTypes.prototype.guard = function () { return this.table.guard(); };
  DuctTypes.prototype.accepts = function (intent) { return this.table.accepts(intent); };
  DuctTypes.prototype.navigate = function (intent) { this.table.navigate(intent); };
  DuctTypes.prototype.dispose = function () { this.table.dispose(); };

  systems.table({ system: ventilators.SYSTEM, id: SECTION, label: "Duct Types", order: 20,
    build: function (surface, context) { return new DuctTypes(surface, context); } });
  return {};
});
