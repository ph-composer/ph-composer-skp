/* Detached Installs session: products, perimeter assignments and compatible copies commit together. */
PhComposerUI.define("features/windows/install_editor", ["features/windows/editor_shared", "request", "snapshot",
  "unit_field", "units", "fields", "library/sidebar", "features/windows/library", "features/windows/library_stage",
  "workspace"],
  function (shared, request, snapshot, unitFields, units, fields, Sidebar, library, StagedCopy, ui) {
  "use strict";
  var el = ui.element, clone = shared.clone, sides = shared.sides;
  // Drawing units an edge needs before its value is written beside it: along the edge, and across a line of text.
  var VALUE_ROOM = 44, LINE_ROOM = 40, INSIDE_ROOM = 96;
  // Which edges take an installation and which Types accept a copy are the host's facts, read with each Type
  // (display.install_topology); the editor never classifies an edge itself. Staging changes no topology, so the
  // facts read with a draft's baseline hold for the session.
  function topologyOf(row) { return row && row.display && row.display.install_topology || null; }
  // An edge's stroke class is its source: assigned, default or missing, or else the host's classification
  // ("shared", "partial") or "unavailable" when the facts were not read. Only a glazed element is offered, so
  // any other element's edge reads as one that cannot be painted.
  var PARTIAL_LABEL = "Partly shared edge · cannot paint";
  function Editor(session, send, close) {
    var self = this; this.requests = request.channel(session, send, "window-installs"); this.close = close;
    this.root = el("section", "window-install-editor"); this.root.hidden = true;
    this.cancel = ui.button("Cancel", function () { self.cancelSession(); });
    this.save = ui.button("Save Installs", function () { self.saveAction(); });
    this.save.setAttribute("aria-label", "Save Installs"); this.cancel.setAttribute("aria-label", "Cancel Installs");
    this.header = ui.pageHeader({ title: "Window Type Installs", actions: [this.cancel], primary: this.save });
    this.header.root.classList.add("phc-sticky-heading");
    this.root.appendChild(this.header.root);
    this.notice = el("p", "muted"); this.notice.setAttribute("role", "status"); this.root.appendChild(this.notice);
    this.body = el("div", "window-install-body"); this.root.appendChild(this.body);
    this.drawing = el("div", "window-install-drawing"); this.body.appendChild(this.drawing);
    this.panel = el("aside", "window-install-panel"); this.body.appendChild(this.panel);
    var heading = el("div", "window-install-heading"); this.panel.appendChild(heading);
    heading.appendChild(el("strong", "", "Psi-Install Types"));
    heading.appendChild(ui.helpButton("Painting installs", "Choose a Psi-Install Type, then click perimeter edges " +
      "to paint them. Click a painted edge again to return it to the Model default."));
    this.unit = el("small", "muted"); heading.appendChild(this.unit);
    this.list = el("div", "window-install-list"); this.panel.appendChild(this.list);
    this.add = ui.button("+ New Psi-Install Type", function () { self.editProduct(); });
      this.panel.appendChild(this.add);
    this.apply = ui.button("Apply to perimeter edges", function () { self.applyAll(); });
      this.panel.appendChild(this.apply);
    this.copyButton = ui.button("Copy to other Window Types", function () { self.showCopy(); });
      this.panel.appendChild(this.copyButton);
    this.form = el("form", "window-install-form"); this.form.hidden = true; this.panel.appendChild(this.form);
    this.sidebar = new Sidebar({ session: session, send: send, changed: function () { self.paint(); },
      busy: function () { return self.requests.busy() || !self.form.hidden || Boolean(self.sidebar.guard()); },
      adapter: library.adapter("psi_install_types", function () { return self.root.hidden ?
        { hint: "Open an Installs session first." } : { params: {} }; }),
      onUse: function (row) { if (self.root.hidden || self.disposed) return false;
        self.selected = row.id; self.paint(); return true; } });
    var oldCopy = this.sidebar.copy; oldCopy.dispose(); oldCopy.root.parentNode.removeChild(oldCopy.root);
    this.sidebar.copy = new StagedCopy(session, send, this.sidebar.adapter, function () { self.paint(); },
      function (copy, values) { return self.stageImport(copy, values); });
    this.sidebar.root.appendChild(this.sidebar.copy.root);
    this.body.appendChild(this.sidebar.root);
    var details = this.sidebar.renderDetails;
    this.sidebar.renderDetails = function () { details.call(this);
      if (this.detail && this.detail.add) this.detail.add.textContent = "Stage in Installs";
    };
    this.copyForm = el("div", "window-install-copy"); this.copyForm.hidden = true;
      this.panel.appendChild(this.copyForm);
    this.confirm = ui.formDialog("", function () { self.confirm.closeModal(); }); this.root.appendChild(this.confirm);
    // The owning view also sends its own Escape here, so the key works from the subtabs and from the page body,
    // where a repaint of the drawing or the list leaves focus.
    this.onKeydown = function (event) {
      if (event.defaultPrevented || event.key !== "Escape" || self.disposed || self.root.hidden ||
        self.requests.busy() || !self.confirm.hidden || self.sidebar.guard()) return;
      event.preventDefault(); self.escape();
    };
    this.root.addEventListener("keydown", this.onKeydown);
  }
  // One layer at a time: the Psi-Install form, then the copy list, then the session itself.
  Editor.prototype.escape = function () {
    if (!this.form.hidden) { this.dismissForm(); this.add.focus(); }
    else if (!this.copyForm.hidden) { this.copyForm.hidden = true; this.copyButton.focus(); }
    else this.cancelSession();
  };
  Editor.prototype.open = function (record) {
    if (this.disposed || this.requests.busy() || !this.root.hidden) return;
    if (!snapshot.value(this.state, shared.PREFIX + "settings")) return;
    this.baselines = {}; this.drafts = {}; this.facts = {}; this.baselines[record.id] = clone(record.values);
    this.facts[record.id] = topologyOf(record);
    this.drafts[record.id] = clone(record.values); this.active = record.id; this.selected = null;
    this.products = shared.records(this.state, "psi_install_types").map(function (row) { return clone(row); });
    this.creates = {}; this.updates = {}; this.imports = {};
    this.settings = clone(snapshot.value(this.state, shared.PREFIX + "settings"));
    this.dirty = false; this.root.hidden = false; this.notice.textContent = ""; this.copyForm.hidden = true;
    this.paint(); if (this.current) this.current.focus();
  };
  Editor.prototype.guard = function () {
    if (this.root.hidden || this.disposed) return null;
    return this.requests.busy() ? "Wait for Installs Save." : "Save or cancel the Installs session before leaving.";
  };
  // The edge as the host classified it, or null when this Type's facts were not read or are malformed.
  Editor.prototype.edge = function (cell, side) {
    var facts = this.facts[this.active], edges = facts && facts.edges && facts.edges[cell.id];
    var edge = edges && edges[side];
    return edge && typeof edge.paintable === "boolean" && typeof edge.classification === "string" ? edge : null;
  };
  // This screen offers glazed elements' edges; the host decides which of those are paintable.
  Editor.prototype.eligible = function (cell, side) {
    var edge = this.edge(cell, side);
    return cell.kind === "glazed" && Boolean(edge && edge.paintable);
  };
  Editor.prototype.stageImport = function (copy, values) {
    if (this.disposed || this.root.hidden || this.requests.busy()) return false;
    var identity = JSON.stringify([copy.provider_id, copy.kind, copy.generation, copy.library_id, copy.record_id]);
    var id = Object.keys(this.imports).filter(function (key) { return this.imports[key].identity === identity; },
      this)[0] || "library_draft_" + (++Editor.sequence);
    this.imports[id] = { identity: identity, client_id: id, copy: copy };
    var existing = this.products.filter(function (row) { return row.id === id; })[0];
    if (existing) existing.values = values;
    else this.products.push({ id: id, values: values, libraryDraft: true });
    this.selected = id; this.dirty = true; this.paint(); return true;
  };
  Editor.prototype.paintEdge = function (elementId, side) {
    if (this.disposed || this.root.hidden || this.requests.busy()) return false;
    var cell = this.drafts[this.active].elements.filter(function (row) { return row.id === elementId; })[0];
    if (!cell || !this.eligible(cell, side)) return false;
    cell.installs[side] = cell.installs[side] === this.selected ? null : this.selected;
    this.dirty = true; this.paint(); return true;
  };
  Editor.prototype.applyAll = function () {
    if (this.disposed || this.root.hidden || this.requests.busy()) return;
    this.drafts[this.active].elements.forEach(function (cell) {
      sides.forEach(function (side) { if (this.eligible(cell, side)) cell.installs[side] = this.selected; }, this);
    }, this); this.dirty = true; this.paint();
  };
  Editor.prototype.showCopy = function () {
    var self = this; if (this.requests.busy() || this.disposed) return;
    this.copyForm.replaceChildren(el("p", "",
      "Replace installations on types with the same dimensions and mapped grid."));
    var candidates = shared.records(this.state, "types").filter(function (row) { return self.compatible(row); });
    if (!candidates.length) this.copyForm.appendChild(el("p", "muted", "No compatible Window Types."));
    candidates.forEach(function (row) {
      var button = ui.button("Copy to " + row.values.name, function () { self.copyTo(row); });
      self.copyForm.appendChild(button);
    }); this.copyForm.hidden = false;
  };
  // A copy target is another Type whose copy key equals this draft's, which is when Save accepts the copy.
  Editor.prototype.compatible = function (row) {
    var facts = this.facts[this.active], other = topologyOf(row);
    function key(topology) { return topology && typeof topology.copy_key === "string" && topology.copy_key; }
    return row.id !== this.active && Boolean(key(facts)) && key(other) === key(facts);
  };
  /* Each target element's source element, joined on the host's copy slots, or null unless every element on
     both sides has a slot and the slots pair the two sides one to one. */
  function slotMapping(source, sourceSlots, target, targetSlots) {
    if (!sourceSlots || !targetSlots) return null;
    var bySlot = {}, complete = source.elements.every(function (cell) {
      var slot = sourceSlots[cell.id];
      if (typeof slot !== "string" || bySlot[slot]) return false;
      bySlot[slot] = cell; return true;
    });
    var mapping = {}, used = {};
    complete = complete && target.elements.length === source.elements.length && target.elements.every(function (cell) {
      var slot = targetSlots[cell.id];
      if (typeof slot !== "string" || !bySlot[slot] || used[slot]) return false;
      used[slot] = true; mapping[cell.id] = bySlot[slot]; return true;
    });
    return complete ? mapping : null;
  }
  Editor.prototype.copyTo = function (row) {
    if (this.disposed || this.requests.busy() || !this.compatible(row)) return false;
    // A target keeps the values and facts it was first staged with; one changed in the Model since then is
    // refused rather than mixed with them.
    if (this.baselines[row.id] && JSON.stringify(this.baselines[row.id]) !== JSON.stringify(row.values)) {
      this.notice.textContent = row.values.name + " changed in the Model. Cancel and reopen Installs to copy to it.";
      return false;
    }
    var source = this.drafts[this.active], facts = this.baselines[row.id] ? this.facts[row.id] : topologyOf(row);
    var mapping = slotMapping(source, this.facts[this.active].copy_slots, row.values, facts && facts.copy_slots);
    if (!mapping) {
      this.notice.textContent = "Installation facts for " + row.values.name + " were not read."; return false;
    }
    if (!this.baselines[row.id]) { this.baselines[row.id] = clone(row.values); this.facts[row.id] = facts; }
    var draft = clone(row.values);
    draft.elements.forEach(function (cell) { cell.installs = clone(mapping[cell.id].installs); });
    this.drafts[row.id] = draft; this.dirty = true;
    this.notice.textContent = "Installs will also replace assignments on " + row.values.name + " when saved.";
    this.copyForm.hidden = true; return true;
  };
  Editor.prototype.editProduct = function (row) {
    if (this.disposed || this.requests.busy()) return;
    var self = this; this.dismissForm(); this.form.hidden = false; this.form.replaceChildren();
    var name = el("input"); name.setAttribute("aria-label", "Psi-Install Type name");
      name.value = row ? row.values.name : "";
    var psi = this.productField = new unitFields.UnitField({ field: fields.with(fields.LINEAR_PSI,
      { label: "Psi-install", allowBlank: true }), value: row ? row.values.psi_w_mk : null });
    this.form.appendChild(name); this.form.appendChild(psi.root);
    var impact = row ? (row.uses || []).map(function (use) { return use.name; }).join(", ") : "New local definition";
    this.form.appendChild(el("p", "muted", "Model-wide uses: " + (impact || "None")));
    var accept = el("button", "primary", "Accept into session"); accept.type = "submit";
    this.form.appendChild(ui.actionRow(ui.button("Cancel edit", function () { self.dismissForm(); }), accept));
    this.form.onsubmit = function (event) {
      event.preventDefault(); if (self.disposed || self.requests.busy() || !name.value.trim()) return;
      var parsed = psi.editing ? psi.parse() : { ok: true, value: psi.baseline };
      if (!parsed.ok) { psi.error.textContent = parsed.message; psi.error.hidden = false; return; }
      var values = { name: name.value.trim(), psi_w_mk: parsed.value };
      if (row && self.creates[row.id]) {
        self.creates[row.id].values = values; row.values = Object.assign({}, row.values, values);
      } else if (row) {
        if (!self.updates[row.id]) self.updates[row.id] = { id: row.id, expected_values: clone(row.values),
          values: values };
        else self.updates[row.id].values = values;
        row.values = Object.assign({}, row.values, values);
      } else {
        var id = "draft_" + (++Editor.sequence); self.creates[id] = { client_id: id, values: values };
        self.products.push({ id: id, values: values }); self.selected = id;
      }
      self.dirty = true; self.dismissForm(); self.paint(); (self.current || self.add).focus();
    };
    this.form.addEventListener("submit", this.form.onsubmit); name.focus();
  };
  Editor.sequence = 0;
  Editor.prototype.dismissForm = function () {
    if (this.productField) this.productField.dispose(); this.productField = null; this.form.hidden = true;
    if (this.form.onsubmit) this.form.removeEventListener("submit", this.form.onsubmit); this.form.onsubmit = null;
  };
  Editor.prototype.paint = function () {
    if (this.root.hidden || this.disposed) return;
    var self = this, record = this.drafts[this.active]; this.header.setTitle(record.name + " Installs");
    var held = this.list.contains(document.activeElement), chosen = "Model default";
    this.list.replaceChildren(); this.current = null;
    this.unit.textContent = units.displayUnit(fields.LINEAR_PSI, units.profile(fields.LINEAR_PSI));
    function choice(id, name, value, row) {
      var root = el("div", "window-install-choice"), button = ui.button("", function () { self.selected = id;
        self.paint(); });
      button.className = "phc-setting-choice"; // The current choice keeps its tint under hover and focus.
      button.appendChild(el("span", "window-install-choice-name", name));
      button.appendChild(el("span", "window-install-choice-value", value == null ? "Missing" :
        shared.bare(value, fields.LINEAR_PSI)));
      button.setAttribute("aria-pressed", String(self.selected === id)); root.appendChild(button);
      if (self.selected === id) { self.current = button; chosen = name; }
      if (row) root.appendChild(ui.iconButton("Edit " + name, "pencil", function () { self.editProduct(row); }));
      self.list.appendChild(root);
    }
    var defaultId = this.settings.default_psi_install_id, defaultProduct = this.products.filter(function (row) {
      return row.id === defaultId; })[0];
    choice(null, "Model default", defaultId ? defaultProduct && defaultProduct.values.psi_w_mk :
      this.settings.default_psi_install_w_mk);
    this.products.forEach(function (row) { choice(row.id, row.values.name, row.values.psi_w_mk,
      row.libraryDraft ? null : row); });
    ui.tooltip(this.apply, "Apply " + chosen + " to every perimeter edge");
    if (held && this.current) this.current.focus();
    this.sidebar.refresh(this.state, {}, true);
    this.paintDrawing(record);
    [this.save, this.cancel, this.apply, this.copyButton, this.add].forEach(function (button) {
      button.disabled = self.requests.busy();
    });
  };
  // Layers, back to front: element fills and names, edge targets, edge strokes, value labels.
  Editor.prototype.paintDrawing = function (record) {
    var self = this, svg = ui.svg, targets = [], strokes = [], labels = [];
    function sum(bands) { return bands.reduce(function (total, value) { return total + (value || 1); }, 0); }
    var width = sum(record.columns_m), height = sum(record.rows_m);
    var drawing = svg("svg", { viewBox: "0 0 600 430", role: "group", "aria-label": "Window installation edges" });
    var scale = Math.min(480 / width, 340 / height), x0 = 60, y0 = 40;
    function value(x, y, anchor, text) {
      labels.push(svg("text", { x: x, y: y, "text-anchor": anchor, "class": "window-install-edge-label" }, text));
    }
    record.elements.forEach(function (cell) {
      var x = x0 + sum(record.columns_m.slice(0, cell.column_span[0])) * scale;
      var y = y0 + sum(record.rows_m.slice(0, cell.row_span[0])) * scale;
      var w = sum(record.columns_m.slice(cell.column_span[0], cell.column_span[1] + 1)) * scale;
      var h = sum(record.rows_m.slice(cell.row_span[0], cell.row_span[1] + 1)) * scale;
      drawing.appendChild(svg("rect", { x: x, y: y, width: w, height: h,
        "class": cell.kind === "empty" ? "window-empty" : "window-glass" }));
      drawing.appendChild(svg("text", { x: x + w / 2, y: y + h / 2 + 4, "text-anchor": "middle" }, cell.name));
      if (cell.kind === "empty") {
        if (h > 60 && w > 44) drawing.appendChild(svg("text", { x: x + w / 2, y: y + h / 2 + 22,
          "text-anchor": "middle", "class": "window-empty-mark" }, "Empty"));
        return;
      }
      sides.forEach(function (side) {
        var edge = self.edge(cell, side), classification = edge ? edge.classification : "unavailable";
        var eligible = self.eligible(cell, side);
        var assigned = cell.installs[side], id = assigned || self.settings.default_psi_install_id;
        var product = self.products.filter(function (row) { return row.id === id; })[0];
        // No Type on the edge and none as the default: the edge takes the Model's own value.
        var modelValue = !id, source = eligible ? product || modelValue ? assigned ? "assigned" : "default" :
          "missing" : classification;
        var label = cell.name + " " + side + ": " + (!eligible ? classification === "shared" ?
          "Shared edge · derived zero" : classification === "unavailable" ? "Edge not read · cannot paint" :
            PARTIAL_LABEL : product ? product.values.name +
            (!assigned ? " · Model default" : "") : modelValue ? "Model default" :
            assigned ? "Missing product" : "Missing default");
        var points = { top: [x, y, x + w, y], right: [x + w, y, x + w, y + h],
          bottom: [x, y + h, x + w, y + h], left: [x, y, x, y + h] }[side];
        var ends = { x1: points[0], y1: points[1], x2: points[2], y2: points[3] };
        strokes.push(svg("line", Object.assign({ "class": "window-install-edge " + source }, ends)));
        // The target is wider than the stroke it sits under, so a thin edge is still easy to hit.
        var target = svg("line", Object.assign({ "class": "window-install-target", role: eligible ? "button" : "img",
          tabindex: eligible ? "0" : "-1", "aria-label": label,
          "aria-disabled": String(!eligible || self.requests.busy()), "data-install-element": cell.id,
          "data-install-side": side }, ends));
        ui.tooltip(target, label);
        function paint() { self.paintEdge(cell.id, side); }
        target.addEventListener("click", paint);
        target.addEventListener("keydown", function (event) {
          if (event.key === "Enter" || event.key === " ") { event.preventDefault(); paint(); }
        }); targets.push(target);
        var across = side === "top" || side === "bottom", middleX = (points[0] + points[2]) / 2,
          middleY = (points[1] + points[3]) / 2;
        // A value is drawn only where its edge has room for it; the edge's tooltip always carries it.
        if ((across ? w : h) < (across ? VALUE_ROOM : LINE_ROOM)) return;
        if (classification === "shared") {
          if (side === "right" || side === "bottom") value(middleX, middleY + 4, "middle", "0");
        } else if (eligible) {
          var text = product ? shared.bare(product.values.psi_w_mk, fields.LINEAR_PSI) :
            modelValue ? shared.bare(self.settings.default_psi_install_w_mk, fields.LINEAR_PSI) : "?";
          // Outside the Window Type where the edge is on its outline. An edge that faces an Empty element keeps
          // its value inside its own element, so two facing values never share the Empty element between them.
          var outer = { top: y < y0 + 1, bottom: y + h > y0 + height * scale - 1, left: x < x0 + 1,
            right: x + w > x0 + width * scale - 1 }[side], out = outer ? 1 : -1;
          if (!outer && (across ? h : w) < INSIDE_ROOM) return;
          // Left and right values sit above the line an element's name is written on.
          if (side === "top") value(middleX, y - (outer ? 9 : -19), "middle", text);
          else if (side === "bottom") value(middleX, y + h + (outer ? 19 : -9), "middle", text);
          else if (side === "left") value(x - 9 * out, middleY - 14, outer ? "end" : "start", text);
          else value(x + w + 9 * out, middleY - 14, outer ? "start" : "end", text);
        }
      });
    });
    targets.concat(strokes, labels).forEach(function (node) { drawing.appendChild(node); });
    this.drawing.replaceChildren(drawing);
  };
  Editor.prototype.saveAction = function () {
    if (this.disposed || this.root.hidden || this.requests.busy() || !this.form.hidden || this.sidebar.guard()) {
      return false;
    }
    var self = this, params = { types: Object.keys(this.drafts).map(function (id) { return { id: id,
      expected_values: clone(self.baselines[id]), installs: self.drafts[id].elements.filter(function (cell) {
        return cell.kind === "glazed";
      }).map(function (cell) { return { element_id: cell.id, sides: clone(cell.installs) }; }) }; }),
      psi_install_types: { create: Object.keys(this.creates).map(function (id) { return self.creates[id]; }),
        update: Object.keys(this.updates).map(function (id) { return self.updates[id]; }) },
      expected_settings: clone(this.settings) };
    if (Object.keys(this.imports).length) params.imports = Object.keys(this.imports).map(function (id) {
      return { client_id: id, copy: clone(self.imports[id].copy) };
    });
    if (!this.requests.run(shared.PREFIX + "types.installs.save", params)) return false;
    this.notice.textContent = "Saving the complete Installs session…"; this.paint(); return true;
  };
  Editor.prototype.cancelSession = function (discard, after) {
    if (this.disposed || this.requests.busy()) return;
    var self = this;
    if (this.dirty && !discard) {
      this.confirm.replaceChildren(el("h2", "", "Discard Installs changes?"), el("p", "",
        "No staged change has been written."));
      this.confirm.appendChild(ui.actionRow(ui.button("Keep editing", function () { self.confirm.closeModal(); }),
        ui.button("Discard changes", function () { self.confirm.closeModal(); self.cancelSession(true, after); }),
          true));
      this.confirm.openModal(); return;
    }
    this.dismissForm(); this.root.hidden = true; this.dirty = false; this.sidebar.copy.withdraw();
    this.sidebar.closeDetails(); this.close("Installs cancelled.");
      if (after) after();
  };
  Editor.prototype.render = function (state) {
    if (this.disposed) return; this.state = state;
    var record = shared.records(state, "types").filter(function (row) { return row.id === this.active; }, this)[0];
    if (!this.root.hidden && (!record || !snapshot.value(state, shared.PREFIX + "settings"))) {
      this.requests.reset(); this.dismissForm(); this.confirm.closeModal(); this.root.hidden = true;
      this.sidebar.refresh(state, {}, false); this.dirty = false; return;
    }
    var outcome = this.requests.consume(state);
    if (outcome && outcome.status === "completed") {
      this.dismissForm(); this.root.hidden = true; this.dirty = false; this.close("Installs saved.");
      this.sidebar.copy.withdraw(); this.sidebar.closeDetails();
    } else if (outcome) this.notice.textContent = outcome.message || "The draft is retained. Review and retry.";
    this.paint();
  };
  Editor.prototype.dispose = function () {
    this.disposed = true; this.requests.reset(); this.dismissForm(); this.confirm.closeModal(); this.root.hidden = true;
    this.root.removeEventListener("keydown", this.onKeydown);
    this.sidebar.dispose();
  };
  return Editor;
});
