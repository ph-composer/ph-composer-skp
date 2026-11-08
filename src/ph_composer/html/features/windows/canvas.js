PhComposerUI.define("features/windows/canvas", ["workspace"], function (ui) {
  "use strict";
  var sides = ["top", "right", "bottom", "left"];
  var svg = ui.svg;
  /* An SVG node that behaves as a button: focusable, labelled, and activated by Enter or Space. */
  function action(node, label, callback) {
    node.setAttribute("tabindex", "0"); node.setAttribute("role", "button"); node.setAttribute("aria-label", label);
    node.addEventListener("click", callback); node.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); callback(e); } }); return node;
  }
  function sum(values) { return values.reduce(function (a, b) { return a + (b || 1); }, 0); }
  /* A swing draws a triangle: the two glass corners away from `direction` meet at the midpoint of that side. */
  function swingLines(glass, direction) {
    var x = glass.x, y = glass.y, w = glass.width, h = glass.height;
    return [{ dash: "4 3", points: { left: [[x + w, y], [x, y + h / 2], [x + w, y + h]],
      right: [[x, y], [x + w, y + h / 2], [x, y + h]], up: [[x, y + h], [x + w / 2, y], [x + w, y + h]],
      down: [[x, y], [x + w / 2, y + h], [x + w, y]] }[direction] }];
  }
  /* A slide draws one arrow across the glass, sight line to sight line, pointing in `direction`: a fine dashed
     shaft like every operation line, with a solid head, because dashes break up a head this small. */
  function slideLines(glass, direction, barb) {
    var axis = { left: [-1, 0], right: [1, 0], up: [0, -1], down: [0, 1] }[direction];
    var x = glass.x + glass.width / 2, y = glass.y + glass.height / 2;
    var reachX = axis[0] * glass.width / 2, reachY = axis[1] * glass.height / 2;
    var tip = [x + reachX, y + reachY], backX = tip[0] - axis[0] * barb, backY = tip[1] - axis[1] * barb;
    return [{ dash: "2 3", points: [[x - reachX, y - reachY], tip] }, { dash: "none", points: [[backX - axis[1] * barb,
      backY - axis[0] * barb], tip, [backX + axis[1] * barb, backY + axis[0] * barb]] }];
  }
  function Canvas(view) { this.view = view; this.root = svg("svg", { role: "group",
    "aria-label": "Window Type drawing" }); }
  Canvas.prototype.render = function (record, options) {
    options = options || {};
    var view = this.view, width = sum(record.columns_m), height = sum(record.rows_m);
    var availableWidth = Math.max(180, view.drawing.clientWidth || 500), availableHeight = Math.max(280,
      Math.min(480, (view.main.clientHeight || 600) - 180));
    /* Fit once per type and panel size, then hold the scale: a size edit changes the drawing's size, never its zoom.
       Fit drawing clears fitKey to fit the current size again. */
    var fitKey = record.id + ":" + availableWidth + ":" + availableHeight;
    if (fitKey !== this.fitKey) { this.fitKey = fitKey; this.scale = Math.min((availableWidth - 150) / width,
      (availableHeight - 120) / height); }
    /* Text, name pills, dimension lines and insert controls are screen furniture: they follow zoom only between
       0.9x and 1.25x of their base size, so zooming far out or in never makes them unreadable or huge. */
    var type = Math.min(Math.max(view.zoom, 0.9), 1.25) / view.zoom; this.type = type;
    var scale = this.scale, margin = 100 * type, top = 40 * type;
    var w = width * scale, h = height * scale;
    this.root.setAttribute("class", options.proposed ? "window-canvas proposed" : "window-canvas");
    this.root.setAttribute("viewBox", "0 0 " + (w + 150 * type) + " " + (h + 120 * type));
    this.root.style.width = (w + 150 * type) * view.zoom + "px";
    this.root.style.height = (h + 120 * type) * view.zoom + "px";
    this.root.style.setProperty("--window-type", type);
    this.root.style.setProperty("--phc-dimension-scale", type);
    this.root.style.maxWidth = "none";
    this.root.replaceChildren();
    var background = svg("rect", { width: "100%", height: "100%", fill: "transparent" });
    background.addEventListener("click", function () { view.select(null); }); this.root.appendChild(background);
    /* Elements paint in order, so a neighbour would cover strokes and controls on a shared edge.
       Hover, selection outlines and insert controls live in one overlay painted after all geometry. */
    var overlay = svg("g", { "class": "window-overlay" }); this.overlay = overlay;
    this.hoverOutline = svg("rect", { "class": "window-hover-outline" }); overlay.appendChild(this.hoverOutline);
    this.paintElements(record, options, overlay, { margin: margin, top: top, width: w, type: type, scale: scale });
    this.paintRules(record, options, { margin: margin, top: top, width: w, height: h, type: type, scale: scale });
    this.paintOverall(record, options, { margin: margin, top: top, width: w, height: h, type: type });
    this.root.appendChild(overlay);
  };

  /* One group per element: its frame, glazing or empty fill, its name control and its edge inserts. */
  Canvas.prototype.paintElements = function (record, options, overlay, box) {
    var self = this, view = this.view, margin = box.margin, top = box.top, w = box.width, type = box.type,
      scale = box.scale;
    record.elements.forEach(function (cell) {
      var x = sum(record.columns_m.slice(0, cell.column_span[0])) * scale, y = sum(record.rows_m.slice(0,
        cell.row_span[0])) * scale;
      var cw = sum(record.columns_m.slice(cell.column_span[0], cell.column_span[1] + 1)) * scale;
      var ch = sum(record.rows_m.slice(cell.row_span[0], cell.row_span[1] + 1)) * scale;
      if (view.interior) x = w - x - cw;
      x += margin; y += top;
      var selected = view.selected.indexOf(cell.id) >= 0;
      var group = svg("g", { "data-window-element": cell.id, "class": "window-geometry" +
        (selected ? " selected" : "") + (cell.id === view.source ? " source" : "") });
      var rect = svg("rect", { x: x, y: y, width: cw, height: ch,
        "class": cell.kind === "empty" ? "window-empty" : "window-glass" });
      action(rect, cell.name + " " + cell.kind, function (e) { view.select(cell.id, e); }); group.appendChild(rect);
      if (cell.kind !== "empty") {
        var widths = sides.map(function (side) { var product = view.product("frames", cell.frames[side]);
          return product && product.width_m != null ? product.width_m * scale : 0; });
        if (view.interior) { var temp = widths[1]; widths[1] = widths[3]; widths[3] = temp; }
        var t = Math.min(widths[0], ch / 2), r = Math.min(widths[1], cw / 2), b = Math.min(widths[2], ch / 2),
          l = Math.min(widths[3], cw / 2);
        var polygons = [ [[x,y],[x+cw,y],[x+cw-r,y+t],[x+l,y+t]], [[x+cw,y],[x+cw,y+ch],[x+cw-r,y+ch-b],[x+cw-r,y+t]],
          [[x,y+ch],[x+l,y+ch-b],[x+cw-r,y+ch-b],[x+cw,y+ch]], [[x,y],[x+l,y+t],[x+l,y+ch-b],[x,y+ch]] ];
        polygons.forEach(function (points, i) {
          var side = sides[view.interior && (i === 1 || i === 3) ? 4 - i : i];
          var frame = svg("polygon", { points: points.map(function (p) { return p.join(","); }).join(" "),
            "class": "window-frame" });
          ui.tooltip(frame, side + " frame"); action(frame, "Select " + cell.name + " " + side +
            " frame", function (e) { view.select(cell.id, e); }); group.appendChild(frame);
        });
        // Operation lines are secondary and anchored to the frame sight lines.
        var gx = x + l, gy = y + t, gw = cw - l - r, gh = ch - t - b;
        if (cell.operation && gw > 0 && gh > 0) cell.operation.directions.forEach(function (direction) {
          if (view.interior) direction = { left: "right", right: "left" }[direction] || direction;
          var glass = { x: gx, y: gy, width: gw, height: gh };
          (cell.operation.type === "slide" ? slideLines(glass, direction, Math.min(10 * type, gw / 4, gh / 4)) :
            swingLines(glass, direction)).forEach(function (line) {
            group.appendChild(svg("polyline", { points: line.points.map(function (p) { return p.join(",");
              }).join(" "), "class": "window-operation", "stroke-dasharray": line.dash }));
          });
        });
        // The element profile draws over its light frame lines at a medium weight.
        group.appendChild(svg("rect", { x: x, y: y, width: cw, height: ch, "class": "window-element-outline" }));
      }
      // The selection fill sits under the name label; its outline rides the overlay above neighbours.
      if (selected) {
        group.appendChild(svg("rect", { x: x, y: y, width: cw, height: ch, "class": "window-selection-fill" }));
        overlay.appendChild(svg("rect", { x: x - 1, y: y - 1, width: cw + 2, height: ch + 2,
          "class": "window-selection-outline" }));
      }
      group.addEventListener("mouseenter", function () { self.hover(x - 1, y - 1, cw + 2, ch + 2); });
      group.addEventListener("mouseleave", function (event) {
        if (!overlay.contains(event.relatedTarget)) self.hover(null); });
      var nameText = cell.name;
      var compactName = cw < 70 * type || ch < 40 * type, shownName = nameText;
      if (compactName) {
        var maxChars = Math.max(1, Math.floor((cw - 8 * type) / (7 * type)));
        if (shownName.length > maxChars) shownName = maxChars > 1 ? shownName.slice(0, maxChars - 1) + "…" : "…";
      }
      var nameControl = svg("g", { "class": "window-name-control" + (compactName ? " compact" : "") });
      if (!compactName) {
        var nameWidth = Math.min(Math.max(58, nameText.length * 7 + 18) * type, cw - 12 * type);
        nameControl.appendChild(svg("rect", { x: x + (cw - nameWidth) / 2, y: y + ch / 2 - 14 * type,
          width: nameWidth, height: 25 * type, rx: 4 * type }));
      }
      nameControl.appendChild(svg("text", { x: x + cw / 2, y: y + ch / 2 + 3 * type, "text-anchor": "middle",
        "class": "window-name" }, shownName));
      action(nameControl, "Rename " + cell.name, function () { view.editName(cell, nameControl); });
        group.appendChild(nameControl);
      // Empty is a state the user set, so it says so; an unmarked white element reads as unfinished.
      if (cell.kind === "empty" && ch > 60 * type && cw > 44 * type) group.appendChild(svg("text", { x: x + cw / 2,
        y: y + ch / 2 + 27 * type, "text-anchor": "middle", "class": "window-empty-mark" }, "Empty"));
      if (!options.proposed) self.edgeInserts(record, cell, group, overlay, x, y, cw, ch);
      self.root.appendChild(group);
    });
  };

  /* The unit perimeter and the dimension rules: a light rule per axis with a dot at every boundary, and the
     per-row and per-column measurements. Graphic only. */
  Canvas.prototype.paintRules = function (record, options, box) {
    var self = this, view = this.view, margin = box.margin, top = box.top, w = box.width, h = box.height,
      type = box.type, scale = box.scale;
    // The unit perimeter is the heaviest line, above every element.
    this.root.appendChild(svg("rect", { x: margin, y: top, width: w, height: h, "class": "window-unit-outline" }));
    // Dimension lines: a light rule per axis with a dot at every row and column boundary.
    // Graphic only.
    var ruleX = margin - 14 * type, ruleY = top + h + 14 * type;
    [record.rows_m, record.columns_m].forEach(function (values, axis) {
      var at = 0, points = [0].concat(values).map(function (value, i) {
        at += i ? (value || 1) * scale : 0;
        return axis ? margin + (view.interior ? w - at : at) : top + at;
      });
      self.root.appendChild(ui.dimensionRule({ axis: axis ? "horizontal" : "vertical",
        from: axis ? margin : top, to: axis ? margin + w : top + h, at: axis ? ruleY : ruleX,
        extension: axis ? top + h + 3 * type : margin - 3 * type, points: points, scale: type }));
    });
    [["columns_m", record.columns_m], ["rows_m", record.rows_m]].forEach(function (entry) {
      var axis = entry[0], values = entry[1], horizontal = axis === "columns_m";
      values.forEach(function (value, i) {
        var offset = (sum(values.slice(0, i)) + (value || 1) / 2) * scale;
        if (horizontal && view.interior) offset = w - offset;
        var name = (horizontal ? "column " : "row ") + (i + 1) + (horizontal ? " width" : " height"), label;
        if (value == null) {
          // A size still to set is an amber "?" pill, matching the Before placing warning, instead of long text that
    // clips.
          var cx = horizontal ? margin + offset : ruleX - 18 * type, cy = horizontal ? ruleY + 12 * type : top + offset;
          label = svg("g", { "class": "window-dimension-target is-missing" });
          ui.tooltip(label, "Set " + name);
          label.appendChild(svg("rect", { x: cx - 12 * type, y: cy - 9 * type, width: 24 * type, height: 18 * type,
            rx: 9 * type, "class": "window-dimension-missing" }));
          label.appendChild(ui.dimensionValue({ text: "?", className: "window-dimension is-missing",
            svg: { x: cx, y: cy + 4 * type, "text-anchor": "middle" } }));
          action(label, "Set " + name, function () { view.dimension(axis, i, label); });
        } else {
          label = ui.dimensionValue({ text: view.length(value), label: ui.titleCase(name),
            className: "window-dimension", svg: { x: horizontal ? margin + offset : ruleX - 8 * type,
              y: horizontal ? ruleY + 16 * type : top + offset + 4 * type,
              "text-anchor": horizontal ? "middle" : "end" },
            activate: function () { view.dimension(axis, i, label); } });
        }
        self.root.appendChild(label);
      });
    });
  };

  /* The overall size above the drawing, with the current size beside a proposed one. */
  Canvas.prototype.paintOverall = function (record, options, box) {
    var view = this.view, margin = box.margin, top = box.top, w = box.width, type = box.type;
    var width = sum(record.columns_m), height = sum(record.rows_m);
    var overall = (record.columns_m.every(Boolean) ? view.length(width) : "Width missing") + " × " +
      (record.rows_m.every(Boolean) ? view.length(height) : "Height missing");
    if (options.proposed && options.current) {
      var currentWidth = sum(options.current.columns_m), currentHeight = sum(options.current.rows_m);
      overall = "Proposed " + overall + " · Current " + view.length(currentWidth) + " × " + view.length(currentHeight);
    }
    this.root.appendChild(svg("text", { x: margin + w / 2, y: top - 12 * type, "text-anchor": "middle",
      "class": "window-overall-dimension" + (record.columns_m.every(Boolean) &&
      record.rows_m.every(Boolean) ? "" : " is-missing") }, overall));
  };
  Canvas.prototype.hover = function (x, y, width, height) {
    if (x === null) { this.hoverOutline.setAttribute("class", "window-hover-outline"); return; }
    ["x", "y", "width", "height"].forEach(function (key, i) { this.hoverOutline.setAttribute(key, [x, y, width,
      height][i]); }, this);
    this.hoverOutline.setAttribute("class", "window-hover-outline is-visible");
  };
  /* Visual edges of one element map to canonical grid insertions; Interior view mirrors left and right.
     Refusals the Model would raise are named here so the control explains itself before a click. */
  Canvas.prototype.edgeTargets = function (record, cell) {
    var interior = this.view.interior, rows = cell.row_span, columns = cell.column_span;
    return [["top", "rows_m", rows[0], "Insert row above"], ["bottom", "rows_m", rows[1] + 1, "Insert row below"],
      ["left", "columns_m", interior ? columns[1] + 1 : columns[0], "Insert column left"], ["right", "columns_m",
        interior ? columns[0] : columns[1] + 1, "Insert column right"]
    ].map(function (entry) {
      var span = entry[1] === "rows_m" ? "row_span" : "column_span", index = entry[2];
      var crossing = record.elements.filter(function (other) { return other[span][0] < index &&
        other[span][1] >= index; })[0];
      var blocked = crossing ? "Split " + crossing.name + " before inserting here." : "";
      return { edge: entry[0], axis: entry[1], index: index, label: entry[3], blocked: blocked };
    });
  };
  /* One insert control per edge, revealed only while the pointer is near that edge. */
  Canvas.prototype.edgeInserts = function (record, cell, group, overlay, x, y, cw, ch) {
    var self = this, view = this.view, controls = {};
    this.edgeTargets(record, cell).forEach(function (target) {
      var px = target.edge === "left" ? x : target.edge === "right" ? x + cw : x + cw / 2;
      var py = target.edge === "top" ? y : target.edge === "bottom" ? y + ch : y + ch / 2;
      var plus = svg("g", { "class": "window-insert" + (target.blocked ? " is-blocked" : ""), role: "button",
        "data-insert-edge": target.edge,
        "aria-label": target.blocked ? target.label + ". " + target.blocked : target.label });
      ui.tooltip(plus, target.blocked || target.label);
      plus.appendChild(svg("circle", { cx: px, cy: py, r: 9 * self.type }));
      plus.appendChild(svg("path", { d: "M" + (px - 4 * self.type) + " " + py + "h" + 8 * self.type + "M" + px +
        " " + (py - 4 * self.type) + "v" + 8 * self.type }));
      plus.addEventListener("click", function (event) {
        if (event.stopPropagation) event.stopPropagation();
        if (target.blocked) view.notice.show(target.blocked, { persistent: true, tone: "warning" });
        else view.insertBand(target.axis, target.index);
      });
      // Leaving the element for its own control keeps both visible; leaving both hides them.
      plus.addEventListener("mouseleave", function (event) { if (!group.contains(event.relatedTarget)) {
        reveal(null); self.hover(null); } });
      controls[target.edge] = plus; overlay.appendChild(plus);
    });
    function reveal(edge) {
      Object.keys(controls).forEach(function (key) {
        var base = controls[key].getAttribute("class").replace(/ is-hover/g, "");
        controls[key].setAttribute("class", key === edge ? base + " is-hover" : base);
      });
    }
    group.addEventListener("mousemove", function (event) {
      var point = self.point(event);
      if (!point || view.picking || view.source || view.requests.busy()) { reveal(null); return; }
      var distances = { top: Math.abs(point.y - y), bottom: Math.abs(point.y - y - ch), left: Math.abs(point.x - x),
        right: Math.abs(point.x - x - cw) };
      var edge = Object.keys(distances).sort(function (a, b) { return distances[a] - distances[b]; })[0];
      reveal(distances[edge] <= Math.min(40 * self.type, Math.max(14 * self.type, Math.min(cw,
        ch) * 0.3)) ? edge : null);
    });
    group.addEventListener("mouseleave", function (event) {
      if (!Object.keys(controls).some(function (edge) { return controls[edge].contains(event.relatedTarget);
        })) reveal(null);
    });
  };
  Canvas.prototype.point = function (event) {
    if (!this.root.createSVGPoint || !this.root.getScreenCTM) return null;
    var matrix = this.root.getScreenCTM(); if (!matrix) return null;
    var point = this.root.createSVGPoint(); point.x = event.clientX; point.y = event.clientY;
    return point.matrixTransform(matrix.inverse());
  };
  return Canvas;
});
