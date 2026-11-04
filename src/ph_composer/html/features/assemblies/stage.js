/* Crisp keyed cross-section, accessible hit targets, dimension lines on both axes, and the edge insert control.
   Each dimension edits in place using the shared UnitField. */
PhComposerUI.define("features/assemblies/stage", ["features/assemblies/canvas", "features/assemblies/editor_shared",
  "features/assemblies/layer_tools", "face_words", "workspace"],
  function (canvas, shared, layerTools, words, ui) {
    "use strict";
    var el = ui.element;
    // How near an edge, in screen pixels, the pointer must be before its insert control shows.
    var EDGE_PX = { layer: 14, segment: 18 };
    // The thickness gutter left of the drawing: the Layer's gear and grip, then its value, then the rule.
    var GUTTER_PX = 128;
    // A width dimension narrower than this puts its label beside the line rather than over it.
    var NARROW_PX = 90;
    function boundary(thermal, exterior, values) {
      var condition = exterior && values.exterior_condition ? words.boundary(values.exterior_condition) + " · " : "";
      return el("div", "assembly-boundary", exterior ?
        "EXTERIOR · " + condition + "Rse " + shared.format(thermal.rse_m2k_w, shared.R_VALUE) :
        "INTERIOR · Rsi " + shared.format(thermal.rsi_m2k_w, shared.R_VALUE) +
        (thermal.direction ? " · " + thermal.direction + " heat flow" : ""));
    }
    /* What each edge of a drawn Layer-Segment inserts, named by its visual result. The top of the drawing is
       the exterior unless the Assembly is turned (last Layer outside). */
    function insertTargets(entry, values, topIsExterior) {
      var index = entry.layer.segments.indexOf(entry.segment);
      var membrane = entry.isMembrane ? "A membrane Layer has one Layer-Segment." : "";
      return {
        top: { label: "Insert layer above", action: "layers.add", kind: "layer",
          params: { anchor_layer_id: entry.layer.id, side: topIsExterior ? "outside" : "inside",
            thickness_mm: shared.newSize("layer") } },
        bottom: { label: "Insert layer below", action: "layers.add", kind: "layer",
          params: { anchor_layer_id: entry.layer.id, side: topIsExterior ? "inside" : "outside",
            thickness_mm: shared.newSize("layer") } },
        left: { label: "Insert Layer-Segment left", action: "segments.add", kind: "segment", blocked: membrane,
          params: { layer_id: entry.layer.id, index: index, width_mm: shared.newSize("segment") } },
        right: { label: "Insert Layer-Segment right", action: "segments.add", kind: "segment", blocked: membrane,
          params: { layer_id: entry.layer.id, index: index + 1, width_mm: shared.newSize("segment") } }
      };
    }
    /* One insert control for the whole drawing, moved to the edge the pointer is near and hidden otherwise,
       so a single control shows at a time. It sits above every hit target. */
    function insertControl(owner, drawing, layout, values) {
      var activeHit = null, activeEdge = null;
      var highlight = el("div", "assembly-edge-highlight");
      highlight.hidden = true;
      highlight.setAttribute("aria-hidden", "true");
      drawing.appendChild(highlight);
      var control = ui.button("", function () {
        var target = control._target;
        if (!target) return;
        if (target.blocked) { owner.notice(target.blocked); return; }
        owner.insert(target);
      });
      control.className = "assembly-insert";
      control.hidden = true;
      control.setAttribute("data-editor-local", "");
      control.innerHTML = ui.svgIcon("add", 14);
      var topIsExterior = values.orientation !== "last_layer_outside";
      function hide() {
        if (activeHit) activeHit.removeAttribute("data-hover-edge");
        activeHit = null;
        activeEdge = null;
        highlight.hidden = true;
        control.hidden = true;
        control._target = null;
      }
      drawing.addEventListener("mousemove", function (event) {
        if (owner.busy() || owner.dragging || owner.hasDimensionDraft()) { hide(); return; }
        // The control, its SVG and its paths belong to the active edge. Hiding it here lets the
        // segment underneath receive the next event and reveal it again, creating a flashing loop.
        if (control.contains(event.target)) return;
        var hit = event.target && event.target.closest ? event.target.closest(".assembly-hit-target") : null;
        if (!hit) { hide(); return; }
        var entry = layout.segments.filter(function (candidate) {
          return candidate.layer.id === hit.getAttribute("data-layer-id") &&
            candidate.segment.id === hit.getAttribute("data-segment-id");
        })[0];
        if (!entry) { hide(); return; }
        var box = hit.getBoundingClientRect(), x = event.clientX - box.left, y = event.clientY - box.top;
        // A thin band (a membrane) still gives its top and bottom a few pixels of reach.
        var band = Math.max(4, Math.min(EDGE_PX.layer, box.height / 4));
        var reach = { top: band, bottom: band,
          left: Math.min(EDGE_PX.segment, box.width / 4), right: Math.min(EDGE_PX.segment, box.width / 4) };
        var distance = { top: y, bottom: box.height - y, left: x, right: box.width - x };
        var edge = Object.keys(distance).filter(function (key) { return distance[key] <= reach[key]; })
          .sort(function (a, b) { return distance[a] - distance[b]; })[0];
        if (!edge) { hide(); return; }
        if (activeHit === hit && activeEdge === edge) return;
        if (activeHit) activeHit.removeAttribute("data-hover-edge");
        activeHit = hit;
        activeEdge = edge;
        hit.setAttribute("data-hover-edge", edge);
        var target = insertTargets(entry, values, topIsExterior)[edge], zoom = owner.zoom;
        var horizontal = edge === "top" || edge === "bottom";
        // A Layer insertion acts across the whole Layer; a Layer-Segment insertion acts on one side.
        var layerWidth = layout.segments.filter(function (candidate) { return candidate.layer === entry.layer; })
          .reduce(function (width, candidate) { return Math.max(width, candidate.xMm + candidate.widthMm); }, 0);
        var cx = edge === "left" ? entry.xMm : edge === "right" ? entry.xMm + entry.widthMm :
          layerWidth / 2;
        var cy = edge === "top" ? entry.yMm : edge === "bottom" ? entry.yMm + entry.heightMm :
          entry.yMm + entry.heightMm / 2;
        control._target = target;
        control.style.left = cx * zoom + "px";
        control.style.top = cy * zoom + "px";
        highlight.style.left = (horizontal ? 0 : cx * zoom) + "px";
        highlight.style.top = (horizontal ? cy * zoom : entry.yMm * zoom) + "px";
        highlight.style.width = (horizontal ? layerWidth * zoom : 5) + "px";
        highlight.style.height = (horizontal ? 5 : entry.heightMm * zoom) + "px";
        highlight.classList.toggle("is-horizontal", horizontal);
        highlight.classList.toggle("is-blocked", Boolean(target.blocked));
        highlight.hidden = false;
        control.classList.toggle("is-blocked", Boolean(target.blocked));
        control.setAttribute("aria-label", target.blocked ? target.label + ". " + target.blocked : target.label);
        control.setAttribute("data-insert-edge", edge);
        ui.tooltip(control, target.blocked || target.label);
        control.hidden = false;
      });
      drawing.addEventListener("mouseleave", hide);
      return control;
    }
    /* The input occupies the value's own slot; units and draft ownership stay with the Builder. */
    function dimensionInline(owner, button, dimension, compact) {
      var control = ui.inlineDimension({ trigger: button, editor: dimension.root,
        input: dimension.field.input, compact: compact, active: dimension.inlineOpen,
        begin: function () {
          if (!owner.allowed()) return false;
          ui.Bubble.closeActive(owner.main);
          dimension.inlineOpen = true;
          return true;
        } });
      dimension.inlineControl = control;
      return control.root;
    }
    function stage(record, materials) {
      var self = this, values = record.values, thermal = (record.display || {}).thermal || {};
      var layout = canvas.geometry(values, materials), root = el("div", "assembly-canvas-block");
      if (this.zoom === null) {
        // Less room for the scroll area's padding and a scrollbar, so a drawing that fits is not cut at its right.
        this.zoom = canvas.fitZoom(layout.widthMm, (this.main.clientWidth || window.innerWidth - 320) - 12);
      }
      var scroll = el("div", "assembly-stage-scroll"), drawingStage = el("div", "assembly-stage");
      // A balanced frame centers the geometry itself, with room for thickness dimensions at its left.
      // Keep labels and width dimensions in this frame so they follow the drawing when it grows or scrolls.
      var frame = el("div", "assembly-canvas-frame");
      frame.style.width = layout.widthMm * this.zoom + "px";
      frame.appendChild(boundary(thermal, values.orientation !== "last_layer_outside", values));
      var dimensions = el("div", "assembly-dimensions"), drawing = el("div", "assembly-drawing"), menus = [];
      var layerCells = {};
      var thicknessRules = ui.svg("svg", { width: GUTTER_PX, height: layout.heightMm * this.zoom,
        "class": "assembly-dimension-graphic", "aria-hidden": "true" });
      thicknessRules.appendChild(ui.dimensionRule({ axis: "vertical", from: 0,
        to: layout.heightMm * this.zoom, at: GUTTER_PX - 14, extension: GUTTER_PX - 3,
        points: layout.layers.map(function (entry) { return entry.yMm * self.zoom; })
          .concat([layout.heightMm * this.zoom]) }));
      dimensions.appendChild(thicknessRules);
      layout.layers.forEach(function (entry, index) {
        var cell = el("div", "assembly-dimension");
        cell.style.height = entry.heightMm * self.zoom + "px";
        cell.setAttribute("data-layer-row", entry.layer.id);
        layerCells[entry.layer.id] = cell;
        var gear = ui.iconButton("Layer " + (index + 1) + " tools", "settings");
        gear.classList.add("assembly-layer-gear");
        gear.setAttribute("data-layer-tools-trigger", entry.layer.id);
        var tools = layerTools.menu(self, record, entry.layer, entry.isMembrane, gear,
          "Layer " + (index + 1) + " tools", { detachedTrigger: true,
            onOpen: function () { cell.classList.add("has-open-tools"); },
            onClose: function () { cell.classList.remove("has-open-tools"); } });
        menus.push(tools.root);
        var button = ui.dimensionValue({ text: entry.isMembrane ? "Membrane" :
          shared.format(entry.layer.thickness_mm, shared.DIMENSION), label: "Layer " + (index + 1) + " thickness" });
        button.setAttribute("data-layer-thickness", entry.layer.id);
        var key = "thickness:" + entry.layer.id, previous = self.dimensions[key], dimension;
        // A category snapshot can remove numeric applicability, but only the user may cancel a draft.
        if (!entry.isMembrane || previous && previous.field.editing &&
            previous.field.input.value !== previous.field.seed) {
          dimension = self.dimension(key, { value: entry.layer.thickness_mm,
            label: "Layer " + (index + 1) + " thickness", action: "layers.update",
            params: { layer_id: entry.layer.id }, field: "thickness_mm", unavailableReason: entry.isMembrane ?
              "This Layer became a membrane. Escape to cancel this thickness draft." : null });
        }
        if (entry.isMembrane && (!dimension || !dimension.field.editing)) {
          ui.tooltip(button, "Select this membrane Layer for Layer tools");
          button.addEventListener("click", function () {
            self.select({ layerId: entry.layer.id, segmentId: entry.layer.segments[0].id });
          });
          cell.appendChild(button);
        } else {
          cell.appendChild(dimensionInline(self, button, dimension, true));
        }
        // The grip has no tab stop: Move outward and Move inward in the gear's menu are the keyboard route.
        var grip = ui.iconButton("Drag Layer " + (index + 1), "grip_vertical");
        grip.classList.add("assembly-layer-grip");
        grip.setAttribute("data-layer-drag-trigger", entry.layer.id);
        grip.setAttribute("data-editor-local", "");
        grip.setAttribute("tabindex", "-1");
        self.layerDrag.bind(grip, { layerId: entry.layer.id, index: index, layout: layout, drawing: drawing,
          frame: frame });
        cell.appendChild(gear);
        cell.appendChild(grip);
        dimensions.appendChild(cell);
      });
      canvas.render(this.svg, layout, materials, { zoom: this.zoom,
        selectedLayerId: this.selection && this.selection.layerId,
        selectedSegmentId: this.selection && this.selection.segmentId });
      this.svg.setAttribute("aria-label", "Assembly cross-section");
      drawing.style.width = layout.widthMm * this.zoom + "px";
      drawing.style.height = layout.heightMm * this.zoom + "px";
      drawing.appendChild(this.svg);
      layout.segments.forEach(function (entry) {
        var material = materials[entry.segment.material_id];
        var hit = ui.button("", function () {
          var chosen = self.selection && self.selection.layerId === entry.layer.id &&
            self.selection.segmentId === entry.segment.id;
          // A second click on the selected Layer-Segment lets it go, as Escape does.
          self.select(chosen ? null : { layerId: entry.layer.id, segmentId: entry.segment.id });
        });
        hit.className = "assembly-hit-target";
        hit.setAttribute("data-layer-id", entry.layer.id);
        hit.setAttribute("data-segment-id", entry.segment.id);
        hit.setAttribute("data-editor-local", "");
        hit.setAttribute("aria-label", "Layer " + (entry.layerIndex + 1) + " · Layer-Segment " +
          (entry.layer.segments.indexOf(entry.segment) + 1) + ": " + (material ? material.name : "No Material"));
        hit.setAttribute("aria-pressed", String(Boolean(self.selection && self.selection.layerId === entry.layer.id &&
          self.selection.segmentId === entry.segment.id)));
        hit.style.left = entry.xMm * self.zoom + "px";
        hit.style.top = entry.yMm * self.zoom + "px";
        hit.style.width = entry.widthMm * self.zoom + "px";
        hit.style.height = entry.heightMm * self.zoom + "px";
        drawing.appendChild(hit);
      });
      drawing.appendChild(insertControl(this, drawing, layout, values));
      // One hover row spans the Layer and its dimension gutter. Keep its gear and grip reachable while
      // crossing whitespace, segment seams or the icon's SVG descendants. Focus/menu state stays in CSS.
      var activeLayer = null;
      function showLayer(id) {
        if (activeLayer === id) return;
        if (activeLayer && layerCells[activeLayer]) layerCells[activeLayer].classList.remove("is-layer-hovered");
        activeLayer = id;
        if (id && layerCells[id]) layerCells[id].classList.add("is-layer-hovered");
      }
      frame.addEventListener("mousemove", function (event) {
        if (self.busy() || self.dragging) { showLayer(null); return; }
        var row = event.target && event.target.closest ? event.target.closest("[data-layer-row]") : null;
        var direct = event.target && event.target.closest ? event.target.closest("button, input") : null;
        if (row && direct && drawingStage.contains(row)) { showLayer(row.getAttribute("data-layer-row")); return; }
        // Thin Layers have taller icons than their rendered band. Retain the revealed row while
        // crossing the corridor from its label to those icons, including their protruding top/bottom.
        if (activeLayer) {
          var activeCell = layerCells[activeLayer];
          var gearBox = activeCell.querySelector(".assembly-layer-gear").getBoundingClientRect();
          var cellBox = activeCell.getBoundingClientRect();
          if (event.clientX >= gearBox.left && event.clientX <= cellBox.right - 22 &&
              event.clientY >= gearBox.top && event.clientY <= gearBox.bottom) return;
        }
        var box = drawing.getBoundingClientRect(), y = (event.clientY - box.top) / self.zoom;
        var entry = layout.layers.filter(function (candidate) {
          return y >= candidate.yMm && y < candidate.yMm + candidate.heightMm;
        })[0];
        showLayer(entry && entry.layer.id);
      });
      frame.addEventListener("mouseleave", function () { showLayer(null); });
      var selected = shared.selected(record, this.selection), widthRow = null;
      var selectedEntry = selected && layout.segments.filter(function (entry) {
        return entry.segment.id === selected.segment.id && entry.layer.id === selected.layer.id;
      })[0];
      // The selected Layer-Segment's width, as a dimension line under the drawing spanning exactly that segment.
      if (selectedEntry && !selectedEntry.isMembrane) {
        var widthKey = "width:" + selected.layer.id + ":" + selected.segment.id;
        var width = this.dimension(widthKey, { value: selected.segment.width_mm, label: "Layer-Segment width",
          action: "segments.update", params: { layer_id: selected.layer.id, segment_id: selected.segment.id },
          nested: "width_mm" });
        var span = selectedEntry.widthMm * this.zoom;
        var line = el("div", "assembly-width-dimension" + (span < NARROW_PX ? " is-narrow" : ""));
        line.style.left = selectedEntry.xMm * this.zoom + "px";
        line.style.width = span + "px";
        var widthRules = ui.svg("svg", { width: span, height: 40,
          "class": "assembly-dimension-graphic", "aria-hidden": "true" });
        widthRules.appendChild(ui.dimensionRule({ axis: "horizontal", from: 0, to: span,
          at: 14, extension: 3, points: [0, span] }));
        line.appendChild(widthRules);
        var label = ui.dimensionValue({ text: shared.format(selected.segment.width_mm, shared.DIMENSION),
          label: "Layer " + (selected.layerIndex + 1) + " · Layer-Segment " + (selected.segmentIndex + 1) + " width" });
        label.setAttribute("data-segment-width", selected.segment.id);
        line.appendChild(dimensionInline(this, label, width, false));
        widthRow = el("div", "assembly-width-row");
        var track = el("div", "assembly-width-track");
        track.style.width = layout.widthMm * this.zoom + "px";
        track.appendChild(line);
        widthRow.appendChild(track);
      }
      drawingStage.appendChild(dimensions);
      drawingStage.appendChild(drawing);
      frame.appendChild(drawingStage);
      // The width band is held open at rest, so selecting a Layer-Segment never moves the caption below.
      frame.appendChild(widthRow || el("div", "assembly-width-row is-empty"));
      frame.appendChild(boundary(thermal, values.orientation === "last_layer_outside", values));
      scroll.appendChild(frame);
      root.appendChild(scroll);
      menus.forEach(function (menu) { root.appendChild(menu); });
      return root;
    }
    return { stage: stage };
  });
