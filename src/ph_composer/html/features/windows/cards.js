/* The element cards beside the drawing: one card per element, its products, findings and dimension editors. */
PhComposerUI.define("features/windows/cards", ["panel", "unit_field", "units", "features/windows/editor_shared",
  "workspace"],
  function (panel, unitFields, units, shared, ui) {
  "use strict";
  var el = ui.element;
  var sides = shared.sides;
  var WINDOW_DIMENSION = shared.WINDOW_DIMENSION, U_VALUE = shared.U_VALUE, windowsState = shared.windowsState,
    LINEAR_PSI = shared.LINEAR_PSI,
    clone = shared.clone, format = shared.format, unitless = shared.unitless,
    INSTALL_SOURCES = shared.INSTALL_SOURCES, CARD_COLUMNS = shared.CARD_COLUMNS, bare = shared.bare;
  var methods = {};

  methods.change = function (command, values, baseline, done) {
    var record = baseline || this.record(); if (!record) return false;
    var params = Object.assign({ id: record.id, expected_values: this.authored(record) }, values);
    var element = command.indexOf("set_element_") === 0;
    if ((command === "split" || element) && params.id && values.id) {
      params.element_id = values.id; params.id = record.id;
    }
    if (command === "rename") return this.request("ph_composer.windows.types.update",
      { id: record.id, expected_values: { name: record.name }, values: { name: values.name } }, done, true);
    return this.request("ph_composer.windows.types.grid." + command, params, done,
      command === "dimension" || element && this.formApplying);
  };
  methods.openBubble = function (trigger, title) {
    if (this.bubble) { this.bubble.close(false);
      if (this.bubble.root.parentNode) this.bubble.root.parentNode.removeChild(this.bubble.root); }
    var bubble = new ui.Bubble(trigger, title, { ownTrigger: true, detachedTrigger: true }); this.bubble = bubble;
    // Keep SVG triggers in the drawing. The editor itself lives outside the scrollport.
    this.root.appendChild(bubble.root);
    return bubble;
  };
  methods.form = function (trigger, title, initial, submit, note, extra, target) {
    var self = this; if (this.disposed || !this.enabled || this.guard()) return;
    var bubble = this.openBubble(trigger, title);
    var form = el("form"), input = el("input"), error = el("div", "cell-error");
    var close = bubble.close, draft = { target: target || { type_id: this.active },
      dirty: function () { return input.value !== initial; }, cancel: finish };
    this.formDraft = draft;
    function finish(focus) {
      if (self.requests.busy() && !self.disposed && self.enabled) return false;
      if (self.formDraft === draft) self.formDraft = null;
      return close.call(bubble, focus);
    }
    bubble.close = function (focus) {
      if (!self.disposed && self.enabled && (self.requests.busy() || draft.dirty())) {
        self.notice.show(self.guard()); return false;
      }
      return finish(focus);
    };
    var cancel = ui.button("Cancel", function () { finish(true); });
    input.value = initial; input.setAttribute("aria-label", title);
    if (note) form.appendChild(el("p", "", note)); form.appendChild(input); form.appendChild(error);
    var save = el("button", "primary", "Apply"); save.type = "submit"; form.appendChild(ui.actionRow(cancel, save));
    input.addEventListener("input", function () { input.removeAttribute("aria-invalid"); });
    input.addEventListener("keydown", function (event) {
      if (event.key === "Escape") { event.preventDefault(); finish(true); }
    });
    if (extra) extra(form, bubble); bubble.content.appendChild(form);
    form.addEventListener("submit", function (event) {
      event.preventDefault(); if (self.disposed || !self.enabled || self.formDraft !== draft ||
        self.requests.busy()) return;
      self.formApplying = true;
      try { var result = submit(input.value, function () { finish(true); }, error);
        if (result !== false && !self.requests.busy()) finish(true); }
      catch (failure) { error.textContent = failure.message; input.setAttribute("aria-invalid", "true"); }
      finally { self.formApplying = false; }
    });
    bubble.open(); input.focus(); input.select();
  };
  methods.setKind = function (kind, trigger) {
    var self = this, record = clone(this.record()), ids = this.selected.slice(); if (!record ||
      this.requests.pending) return;
    var glazed = record.elements.filter(function (cell) { return ids.indexOf(cell.id) >= 0 &&
      cell.kind === "glazed"; });
    if (kind === "glazed" || !glazed.length) { this.change("kind", { ids: ids, kind: kind }, record); return; }
    this.confirmChange(trigger, "Set to Empty?",
      "This clears the glazing, frames, operation and Psi-Install assignments of " + glazed.map(function (cell) {
      return cell.name; }).join(", ") + ". Empty elements are wall area, not window.", "Set to Empty", function () {
      self.change("kind", { ids: ids, kind: kind }, record); });
  };
  /* Confirm only a change that discards what the user assigned; the dialog names exactly what goes. */

  methods.paintMetric = function (value, number, missing) {
    var profile = units.profile(U_VALUE);
    value.unit.textContent = " " + units.displayUnit(U_VALUE, profile);
    value.textContent = number == null ? "—" : units.format(number, U_VALUE, profile, { showUnit: false });
    ui.tooltip(value, number == null ? missing : "");
  };
  /* One value, applied like an Assembly Builder layer thickness: Enter or leaving the field applies, Escape restores.
    // */
  methods.editQuantity = function (trigger, title, descriptor, value, apply, extra) {
    var self = this; if (this.guard() || this.disposed) return;
    var bubble = this.openBubble(trigger, title);
    var edit = new unitFields.ValueBubble({ bubble: bubble, title: title, field: descriptor, value: value,
      apply: apply, busy: function () { return self.requests.busy(); }, once: true, blurFocus: true,
      active: function () { return !self.disposed && self.enabled; },
      onClose: function () { if (self.dimensionField === edit.field) self.dimensionField = null; } });
    this.valueEditor = edit; this.dimensionField = edit.field;
    var field = edit.field;
    bubble.content.appendChild(ui.button("Cancel edit", function () { field.cancel(); }));
    if (extra) extra(bubble, field);
    bubble.open(); field.input.focus(); field.input.select();
  };
  methods.dimension = function (axis, index, trigger) {
    var self = this, record = clone(this.record()); if (!record) return;
    var title = axis === "rows_m" ? "Row height" : "Column width", noun = axis === "rows_m" ? "row" : "column";
    this.editQuantity(trigger, title, WINDOW_DIMENSION, record[axis][index], function (value, done) {
      self.change("dimension", { axis: axis, index: index, value: value }, record, done);
    }, function (bubble, field) {
      var remove = ui.button("Delete " + noun, function () {
        if (field.editing || self.requests.busy()) { self.notice.show("Apply or cancel the dimension draft."); return; }
        bubble.close(false); self.confirmBandRemoval(axis, index, record, trigger);
      }); remove.hidden = record[axis].length === 1; bubble.content.appendChild(remove);
    });
  };
  methods.confirmBandRemoval = function (axis, index, record, trigger) {
    var self = this, noun = axis === "rows_m" ? "row" : "column", span = axis === "rows_m" ? "row_span" : "column_span";
    var removed = record.elements.filter(function (cell) { return cell[span][0] === index &&
      cell[span][1] === index; });
    var spanning = record.elements.filter(function (cell) { return cell[span][0] <= index &&
      cell[span][1] >= index && cell[span][0] !== cell[span][1]; }).length;
    var text = removed.length ? "This removes " + removed.map(function (cell) { return cell.name; }).join(", ") +
      " from " + record.name + "." : "No element sits only in this " + noun + ".";
    if (spanning) text += " " + spanning +
      (spanning === 1 ? " element spanning it gets " : " elements spanning it get ") +
      (axis === "rows_m" ? "shorter." : "narrower.");
    this.confirmChange(trigger, "Delete " + noun + "?", text, "Delete " + noun, function () { self.change("remove",
      { axis: axis, index: index }, record); });
  };
  /* Inserting a row or column asks nothing: a round default size, one Undo step, and the new elements selected so
    // their products come next. */
  methods.insertBand = function (axis, index) {
    var self = this, record = clone(this.record()); if (!record || this.requests.pending) return;
    var value = units.profile(WINDOW_DIMENSION).system === "IP" ? 0.508 : 0.5;
    var known = record.elements.map(function (cell) { return cell.id; }), installs = {};
    record.elements.forEach(function (cell) { installs[cell.id] = cell.installs || {}; });
    this.change("insert", { axis: axis, index: index, value: value }, record, function () { self.revealInserted = {
      type_id: record.id, axis: axis, known: known, installs: installs }; });
  };

  methods.picker = function (cellId, kind, side, trigger) {
    if (this.disposed || !this.enabled || this.guard()) return;
    var self = this, record = clone(this.record()), cell = record.elements.filter(function (c) {
      return c.id === cellId; })[0];
    var current = kind === "glazings" ? cell.glazing_id : cell.frames[side],
      noun = kind === "frames" ? "frames" : "glazings";
    this.form(trigger, "Choose " + (side ? side + " frame" : "glazing"), "", function () {});
    var bubble = this.bubble; bubble.content.replaceChildren(); bubble.panel.classList.add("window-picker");
    var records = ((windowsState(this.state).constituents || {})[kind] || []), makers = [];
    var searchBox = el("label", "library-sidebar-search"), search = el("input"), summary = el("p",
      "window-picker-filters"), choices = el("div", "window-picker-list");
    search.type = "search"; search.placeholder = "Search name or product code"; search.setAttribute("aria-label",
      "Search " + noun);
    searchBox.appendChild(ui.glyph("search")); searchBox.appendChild(search);
    bubble.content.appendChild(searchBox); bubble.content.appendChild(summary); bubble.content.appendChild(choices);
    /* Filters and infrequent actions sit behind the heading menu; the picker body is search and model-library choices
    // only. */
    var menu = new ui.ActionMenu("Filter and manage " + noun, { parent: bubble });
      menu.bubble.panel.classList.add("window-picker-menu");
    bubble.heading.insertBefore(menu.root, bubble.closeButton);
    function field(label, control) { var node = el("label", "window-picker-field"); node.appendChild(el("span", "",
      label)); node.appendChild(control); menu.content.appendChild(node); return control; }
    var manufacturer = field("Manufacturer", el("select")); manufacturer.appendChild(ui.option("",
      "All manufacturers"));
    records.forEach(function (r) { if (r.manufacturer &&
      makers.indexOf(r.manufacturer) < 0) makers.push(r.manufacturer); });
    makers.sort(ui.compareText).forEach(function (name) {
      manufacturer.appendChild(ui.option(name, name)); });
    var filters = [manufacturer];
    if (kind === "frames") ["Position", "Operation"].forEach(function (label) { var input = field(label,
      el("input")); input.placeholder = "Any " + label.toLowerCase(); input.setAttribute("data-filter",
      label.toLowerCase()); filters.push(input); });
    var clearFilters = menu.add("Clear filters", function () { filters.forEach(function (n) { n.value = ""; });
      render(); }, { icon: "clear" });
    var clearAssignment = menu.add("Clear assignment", function () { assign(null); }, { icon: "delete" });
    menu.add("Manage " + noun + " in Library", function () { bubble.close(false); self.openLibrary(kind); }, {
      icon: "enter" });
    function assign(id) {
      self.change(side ? "set_element_frame" : "set_element_glazing", side ? { id: cellId, side: side,
        frame_id: id } : { id: cellId, glazing_id: id }, record, function () { bubble.close(true); }); }
    function text(value) { return String(value == null ? "" : value).toLowerCase(); }
    function matches(r) {
      var query = text(search.value).trim();
      return (!query || text(r.name + " " + (r.product_code || "")).indexOf(query) >= 0) && (!manufacturer.value ||
        r.manufacturer === manufacturer.value) &&
        filters.slice(1).every(function (input) { var value = text(input.value).trim(); return !value ||
          text(r[input.getAttribute("data-filter")]).indexOf(value) >= 0; });
    }
    function choice(r, isCurrent) {
      var button = ui.button("", function () { if (isCurrent) bubble.close(true); else assign(r.id); });
      button.className = "window-picker-choice" + (isCurrent ? " is-current" : "");
        button.setAttribute("data-record-id", r.id);
      if (isCurrent) button.setAttribute("aria-current", "true");
      button.appendChild(el("span", "window-picker-name", r.name));
      button.appendChild(el("span", "window-picker-meta", (r.manufacturer || "Manual") + " · " +
        (kind === "frames" ? "Uf " + format(r.uf_w_m2k, U_VALUE) + " · " + self.length(r.width_m) : "Ug " +
        format(r.ug_w_m2k, U_VALUE) + " · g " + unitless(r.g_value))));
      if (isCurrent) button.appendChild(ui.glyph("check_circle"));
      return button;
    }
    function render() {
      var active = filters.filter(function (n) { return text(n.value).trim(); }), selected = self.product(kind,
        current);
      summary.hidden = !active.length; summary.textContent = active.length ? "Filtered by " +
        active.map(function (n) { return n.value.trim(); }).join(", ") : "";
      menu.trigger.classList.toggle("is-filtered", Boolean(active.length)); clearFilters.disabled = !active.length;
        clearAssignment.disabled = !current;
      choices.replaceChildren();
      // The current assignment stays visible even when filters exclude it.
      if (selected) choices.appendChild(choice(selected, true));
      else if (current) choices.appendChild(el("p", "window-picker-missing", "The assigned " +
        (kind === "frames" ? "frame" : "glazing") + " is no longer in this model. Choose a replacement."));
      var shown = records.filter(function (r) { return r.id !== current && matches(r); }).sort(function (a, b) {
        return ui.compareText(a.name, b.name) || ui.compareText(a.id, b.id); });
      // A Frame slot lists the Frames made for it first; the rest stay in reach beneath, each run in name order.
      function fits(r) { return kind === "frames" && shared.framePositionFits(side, r.position); }
      var fitting = shown.filter(fits), others = shown.filter(function (r) { return !fits(r); });
      fitting.forEach(function (r) { choices.appendChild(choice(r, false)); });
      if (fitting.length && others.length) choices.appendChild(el("p", "window-picker-group", "Other positions"));
      others.forEach(function (r) { choices.appendChild(choice(r, false)); });
      if (!records.length) choices.appendChild(el("p", "", "No " + noun + " in this model yet. Add them in Library."));
      else if (!shown.length && !(selected && matches(selected))) choices.appendChild(el("p", "", "No matching " +
        noun + "."));
    }
    filters.concat(search).forEach(function (n) { n.addEventListener("input", render); n.addEventListener("change",
      render); });
    // form() placed the bubble around its generic content; place it again for the list, once, so typing never flips it.
    render(); bubble.position(); search.focus();
  };
  methods.openLibrary = function (kind) { panel.navigate("library", { kind: kind }); };

  methods.card = function (cell) {
    var self = this, card = this.cards[cell.id];
    if (!card) {
      card = { root: el("section", "window-card"), rows: {} }; this.cards[cell.id] = card;
      card.heading = el("div", "window-card-heading"); card.root.appendChild(card.heading);
      card.name = ui.button("", function () { var current = self.record().elements.filter(function (c) {
        return c.id === cell.id; })[0]; self.editName(current, card.name); }); card.heading.appendChild(card.name);
      card.value = el("span", "window-card-uw"); card.value.appendChild(el("span", "", "U"));
        card.value.appendChild(el("sub", "", "w")); card.uw = el("strong"); card.value.appendChild(card.uw);
        card.heading.appendChild(card.value);
      /* One grid per card: units once in the column headings, bare numbers in cells, and each row flagged where an
    // input is missing. */
      card.content = el("div", "window-element-table"); card.content.setAttribute("role", "table");
        card.root.appendChild(card.content);
      function cellNode(tag, className, role) { var node = el(tag, className); node.setAttribute("role", role);
        return node; }
      var head = cellNode("div", "window-element-row window-element-head", "row"); card.units = [];
      head.appendChild(cellNode("span", "", "columnheader")); head.appendChild(cellNode("span", "", "columnheader"));
      CARD_COLUMNS.forEach(function (column) { var th = cellNode("span", "", "columnheader"), unit = el("small",
        "window-element-unit"); th.appendChild(el("span", "", column[0])); th.appendChild(unit);
        head.appendChild(th); card.units.push(unit); });
      card.content.appendChild(head);
      function rowLabel(row, text) { var label = cellNode("span", "window-element-label", "rowheader"),
        name = el("span", "", text), flag = ui.glyph("alert"); flag.setAttribute("role", "img");
        label.appendChild(name); label.appendChild(flag); row.appendChild(label); return { name: name, flag: flag }; }
      [["glazing", "Glazing"]].concat(sides.map(function (s) { return [s, s.charAt(0).toUpperCase() + s.slice(1) +
        " Frame"]; })).forEach(function (entry) {
        var row = cellNode("div", "window-element-row", "row"), label = rowLabel(row, entry[1]),
          product = cellNode("span", "window-element-product", "cell"), cells = [];
        var button = ui.button("", function () { self.picker(cell.id,
          entry[0] === "glazing" ? "glazings" : "frames", entry[0] === "glazing" ? null : entry[0], button); });
          button.className = "window-product-select " + (entry[0] === "glazing" ? "window-glazing-target" :
            "window-frame-target");
        button.setAttribute("data-element-id", cell.id);
        if (entry[0] !== "glazing") button.setAttribute("data-frame-side", entry[0]);
        product.appendChild(button); row.appendChild(product);
        CARD_COLUMNS.forEach(function () { var metric = cellNode("span", "window-element-metric", "cell");
          row.appendChild(metric); cells.push(metric); });
        card.content.appendChild(row); card.rows[entry[0]] = { row: row, label: label.name, flag: label.flag,
          button: button, cells: cells };
      });
      var operationRow = cellNode("div", "window-element-row", "row"), operationLabel = rowLabel(operationRow,
        "Operation"), operationControls = cellNode("span", "window-operation-controls", "cell");
      card.operationRow = operationRow; card.operationFlag = operationLabel.flag;
        operationRow.appendChild(operationControls);
      card.operation = el("select", "phc-select-arrow");
      [["", "Not specified"], ["fixed", "Fixed"], ["swing", "Swing"], ["slide", "Slide"]].forEach(function (entry) {
        card.operation.appendChild(ui.option(entry[0], entry[1])); });
      function setOperation(type, direction) {
        var current = self.record().elements.filter(function (c) { return c.id === cell.id; })[0],
          dirs = current.operation ? current.operation.directions.slice() : [];
        if (direction) { var index = dirs.indexOf(direction); if (index < 0) dirs.push(direction);
          else dirs.splice(index, 1); }
        self.change("set_element_operation", { id: cell.id, operation: type ? { type: type,
          directions: type === "fixed" ? [] : dirs } : null });
      }
      card.operation.addEventListener("change", function () { setOperation(card.operation.value); });
        operationControls.appendChild(card.operation); card.directions = {};
      ["left", "right", "up", "down"].forEach(function (direction) { var button = ui.button(ui.titleCase(direction),
        function () { var canonical = self.interior ? ({ left: "right", right: "left" }[direction] ||
        direction) : direction; setOperation(card.operation.value, canonical); });
        operationControls.appendChild(button); card.directions[direction] = button; });
      card.content.appendChild(operationRow);
      // Only findings that belong to no single row collect below the grid.
      card.findings = el("div", "window-findings"); card.root.appendChild(card.findings);
      card.empty = el("p", "window-card-empty",
        "Empty: excluded wall area. No window element or thermal contribution."); card.root.appendChild(card.empty);
    }
    card.name.textContent = cell.name; card.root.setAttribute("data-card-id", cell.id);
      card.operation.setAttribute("aria-label", "Operation for " + cell.name);
    var selected = this.selected.indexOf(cell.id) >= 0;
    card.root.className = "window-card" + (selected ? " selected" : "");
    // Selecting an element promotes its card and hides the others: pulse the card so the change is visible.
    if (selected && !card.wasSelected) ui.pulse(card.root);
    card.wasSelected = selected;
    var entry = this.entries.filter(function (e) { return e.record.id === self.active; })[0],
      detail = (entry.calculation.elements || []).filter(function (d) { return d.id === cell.id; })[0] || {};

    card.content.hidden = cell.kind === "empty"; card.empty.hidden = cell.kind !== "empty";
      card.value.hidden = cell.kind === "empty";
    this.paintCard(card, cell, entry, detail);
    return card.root;
  };

  /* Repaints one card in place: its reference flag, its Uw, its per-side product rows and their findings. */
  methods.paintCard = function (card, cell, entry, detail) {
    var self = this;
    var readOnly = !this.enabled || this.requests.busy() || Boolean(this.dimensionField && this.dimensionField.editing);
    card.name.disabled = readOnly; card.operation.disabled = readOnly;
    Object.keys(card.directions).forEach(function (direction) { card.directions[direction].disabled = readOnly; });
    card.uw.textContent = bare(detail.uw_w_m2k, U_VALUE);
    ui.tooltip(card.value, detail.uw_w_m2k == null ? "" : format(detail.uw_w_m2k, U_VALUE));
    card.units.forEach(function (unit, index) { var field = CARD_COLUMNS[index][1]; unit.textContent = field ? "[" +
      units.displayUnit(field, units.profile(field)) + "]" : ""; });
    var needs = cell.kind === "empty" ? {} : this.elementFindings(cell, detail);
    function flag(row, node, items) {
      row.classList.toggle("is-incomplete", Boolean(items && items.length)); node.hidden = !(items && items.length);
      var tooltip = items && items.length ? "Missing: " + items.join(", ") : "";
      ui.tooltip(node, tooltip); node.setAttribute("aria-label", tooltip);
    }
    Object.keys(card.rows).forEach(function (key) {
      var row = card.rows[key]; row.button.disabled = readOnly;
      var glazing = key === "glazing", canonical = self.interior ? ({ left: "right",
        right: "left" }[key] || key) : key;
      // Rows retain canonical identity; their labels state the visible side in Interior view.
      if (!glazing) row.label.textContent = canonical.charAt(0).toUpperCase() + canonical.slice(1) + " Frame";
      var id = glazing ? cell.glazing_id : cell.frames[key], product = self.product(glazing ? "glazings" : "frames",
        id);
      row.button.textContent = product ? product.name : id ? "Missing product" : "Choose product";
        row.button.classList.toggle("is-unset", !product);
      // The record id stays reachable for diagnosis without becoming the visible label.
      ui.tooltip(row.button, product ? product.name : id ? "The assigned record " + id +
        " is no longer in this model. Choose a replacement." : "");
      var edge = (detail.edges || []).filter(function (e) { return e.side === key; })[0], source = edge &&
        INSTALL_SOURCES[edge.install.source];
      var values = glazing ? [bare(product && product.ug_w_m2k, U_VALUE), "—", bare(product && product.g_value),
        "—"] : [bare(product && product.uf_w_m2k, U_VALUE), bare(product && product.width_m, WINDOW_DIMENSION), "—",
        bare(edge && edge.install.psi_w_mk, LINEAR_PSI)];
      row.cells.forEach(function (node, index) { node.textContent = values[index]; });
      row.cells[3].classList.toggle("is-muted", Boolean(source)); ui.tooltip(row.cells[3], source || "");
      flag(row.row, row.flag, needs[key]);
    });
    flag(card.operationRow, card.operationFlag, needs.operation);
    if (document.activeElement !== card.operation) card.operation.value = cell.operation ? cell.operation.type : "";
    Object.keys(card.directions).forEach(function (d) { var canonical = self.interior ? ({ left: "right",
      right: "left" }[d] || d) : d; card.directions[d].hidden = !cell.operation || cell.operation.type === "fixed";
      card.directions[d].setAttribute("aria-pressed", String(Boolean(cell.operation &&
      cell.operation.directions.indexOf(canonical) >= 0))); });
    var other = needs.other || [], list = el("ul");
    card.findings.replaceChildren(); card.findings.hidden = !other.length;
    if (other.length) {
      other.forEach(function (text) { list.appendChild(el("li", "", text)); });
      card.findings.appendChild(ui.glyph("alert")); card.findings.appendChild(list);
    }
  };

  /* Translates calculation finding codes into what each card row still needs; the codes stay the calculation's
    contract. */
  methods.elementFindings = function (cell, detail) {
    var self = this, findings = detail.findings || [], rows = { glazing: [], operation: [], other: [] }, handled = [];
    var glazing = this.product("glazings", cell.glazing_id);
    sides.forEach(function (side) { rows[side] = []; });
    function has(code, side) {
      var found = findings.filter(function (finding) { return finding.code === code && (!side || finding.side === side);
      });
      handled = handled.concat(found); return found.length > 0;
    }
    function add(key, text) { if (rows[key].indexOf(text) < 0) rows[key].push(text); }
    var widthMissing = has("window_type.frame_width_unresolved");
    var constructionMissing = has("window_type.construction_unresolved");
    if (!glazing) add("glazing", cell.glazing_id ? "Product not found" : "Product");
    else { if (glazing.ug_w_m2k == null) add("glazing", "Ug"); if (glazing.g_value == null) add("glazing", "g-value"); }
    if (has("window_type.g_value_missing")) add("glazing",
      !cell.glazing_id ? "Product" : glazing ? "g-Value" : "Product not found");
    if (constructionMissing && !cell.glazing_id) add("glazing", "Product");
    if (constructionMissing && glazing && glazing.ug_w_m2k == null) add("glazing", "Ug");
    sides.forEach(function (side) {
      var id = cell.frames[side], frame = self.product("frames", id);
      if (!frame) add(side, id ? "Product not found" : "Product");
      else { if (frame.width_m == null) add(side, "Width"); if (frame.uf_w_m2k == null) add(side, "Uf");
        if (frame.psi_g_w_mk == null) add(side, "ψ-g"); }
      if (widthMissing) { if (!id) add(side, "Product"); else if (!frame) add(side, "Product not found");
        else if (frame.width_m == null) add(side, "Width"); }
      if (constructionMissing && frame && frame.uf_w_m2k == null) add(side, "Uf");
      if (constructionMissing && frame && frame.psi_g_w_mk == null) add(side, "ψ-g");
      if (has("window_type.install_unresolved", side)) add(side, "Psi-Install Type");
    });
    if (has("window_type.glazing_area_nonpositive")) add("other", "Frame widths leave no glazing area");
    if (has("window_type.operation_incomplete")) add("operation", "Operation and direction");
    findings.forEach(function (finding) {
      if (handled.indexOf(finding) < 0) add("other", finding.message.replace(/\.$/, ""));
    });
    return rows;
  };

  return methods;
});
