/* The Builder's toolbar and the selected Layer-Segment's anchored property editor. */
PhComposerUI.define("features/assemblies/inspector", ["features/assemblies/editor_shared",
  "features/assemblies/canvas", "fields", "unit_field", "workspace"],
  function (shared, canvas, fields, unitFields, ui) {
    "use strict";
    var el = ui.element;
    function run(owner, label, action, params, consequence) {
      if (action === "layers.remove" || action === "segments.remove") owner.remove(action, params, label, consequence);
      else owner.action(action, params);
    }
    // `icon` draws the action as an icon button named by `label`; without one it is a text button.
    function control(owner, root, label, action, params, disabled, consequence, icon) {
      var handler = function () { run(owner, label, action, params, consequence); };
      var button = icon ? ui.iconButton(label, icon, handler) : ui.button(label, handler, disabled);
      button.disabled = Boolean(disabled);
      button.setAttribute("data-builder-action", action);
      root.appendChild(button);
      return button;
    }
    /* Selection context comes first, followed by view and Assembly actions. Keep the drawing still
       when selection tools appear, including at widths where the toolbar needs a second row. */
    function inspector(record, materials, selected) {
      var self = this, root = el("section", "assembly-toolbar");
      root.setAttribute("aria-label", "Drawing tools");
      var selection = el("div", "assembly-tool-group assembly-selection-tools");
      root.appendChild(selection);
      var view = el("div", "assembly-tool-group");
      [["Zoom out", "zoom_out", function () { self.setZoom(canvas.previousZoom(self.zoom)); }],
        ["Fit drawing", "fit", function () { self.setZoom(null); }],
        ["Zoom in", "zoom_in", function () { self.setZoom(canvas.nextZoom(self.zoom)); }]].forEach(function (item) {
        var button = ui.iconButton(item[0], item[1], item[2]);
        button.setAttribute("data-editor-local", "");
        view.appendChild(button);
      });
      view.appendChild(unitFields.DimensionFormatControl("assemblies", this.chooseDimensionFormat).root);
      root.appendChild(view);
      var tools = el("div", "assembly-tool-group");
      var more = new ui.ActionMenu("More drawing actions");
      [["Mirror segments", "segments.mirror"], ["Flip Layers", "layers.flip"],
        ["Flip orientation", "layers.flip_orientation"]].forEach(function (item) {
        more.add(item[0], function () { self.action(item[1], {}); }).setAttribute("data-builder-action", item[1]);
      });
      tools.appendChild(more.root);
      root.appendChild(tools);
      if (!selected) {
        selection.appendChild(el("span", "muted assembly-selection-label", "Select a Layer-Segment"));
        // The sidebar already titles itself; the way to it is the kit's sidebar glyph, named in its tooltip.
        var library = ui.iconButton("Material Library", "sidebar", function () { self.sidebar.reveal(null); });
        library.setAttribute("data-editor-local", "");
        selection.appendChild(library);
        return root;
      }
      selection.appendChild(el("strong", "assembly-selection-label",
        "Layer " + (selected.layerIndex + 1) + " · Layer-Segment " + (selected.segmentIndex + 1)));
      var material = materials[selected.segment.material_id];
      var choose = ui.button(material ? material.name : "No Material", function () {
        self.sidebar.reveal(material && material.id);
      });
      choose.className = "assembly-material-chip";
      if (material) {
        var swatch = el("span", "library-sidebar-swatch");
        swatch.style.backgroundColor = material.color || "#ffffff";
        choose.insertBefore(swatch, choose.firstChild);
      }
      ui.tooltip(choose, material ? "Show " + material.name + " in the Material Library" :
        "Choose from the Material Library");
      choose.setAttribute("data-editor-local", "");
      selection.appendChild(choose);
      var only = selected.layer.segments.length === 1;
      var remove = control(this, selection, "Delete segment", "segments.remove",
        { layer_id: selected.layer.id, segment_id: selected.segment.id }, only,
        selected.segment.material_id ? "Delete this Layer-Segment and its Material assignment?" : null, "delete");
      // An icon that cannot act says why, where its name would be.
      if (only) ui.tooltip(remove, "A Layer keeps at least one Layer-Segment");
      var trigger = ui.iconButton("Segment properties", "settings");
      var spacingKey = "spacing:" + selected.layer.id + ":" + selected.segment.id;
      var bubble = new ui.Bubble(trigger, "Layer-Segment properties", { guard: function () {
        return self.painting ? null : self.settleDimension(spacingKey);
      }, refused: self.notice });
      var continuous = el("input");
      continuous.type = "checkbox";
      continuous.checked = Boolean(selected.segment.is_continuous_insulation);
      continuous.setAttribute("aria-label", "Continuous insulation");
      continuous.addEventListener("change", function () {
        self.action("segments.update", { layer_id: selected.layer.id, segment_id: selected.segment.id,
          values: { is_continuous_insulation: continuous.checked } });
      });
      bubble.content.appendChild(shared.field("Continuous insulation", continuous));
      var spacing = this.dimension(spacingKey,
        { value: selected.segment.steel_stud_spacing_mm, label: "Steel stud spacing", optional: true,
          action: "segments.update", params: { layer_id: selected.layer.id, segment_id: selected.segment.id },
          nested: "steel_stud_spacing_mm" });
      bubble.content.appendChild(shared.field("Steel stud spacing", spacing.root));
      bubble.content.appendChild(el("small", "muted", "One steel stud spacing per Layer. Leave blank when absent."));
      // The Material's own values, read only here; they are edited on the Material, for every use of it.
      var facts = el("div", "assembly-material-facts");
      facts.appendChild(el("small", "muted", material ? material.name : "No Material assigned"));
      if (material) [["Conductivity", "conductivity_w_mk", fields.CONDUCTIVITY],
        ["Density", "density_kg_m3", fields.DENSITY], ["Specific heat", "specific_heat_j_kgk", fields.SPECIFIC_HEAT],
        ["Emissivity", "emissivity", fields.FRACTION]].forEach(function (item) {
        var row = el("div", "phc-property-row");
        row.appendChild(el("span", "", item[0]));
        row.appendChild(el("span", "phc-property-value", ui.blank(material[item[1]]) ? "—" :
          shared.format(material[item[1]], item[2])));
        facts.appendChild(row);
      });
      bubble.content.appendChild(facts);
      bubble.content.appendChild(ui.button("Clear Material", function () {
        self.action("segments.set_material", { layer_id: selected.layer.id, segment_id: selected.segment.id,
          material_id: null });
      }));
      selection.appendChild(bubble.root);
      return root;
    }
    return { inspector: inspector };
  });
