/* The three local product inventories share grid editing, lifecycle forms and use-site inspection. */
PhComposerUI.define("features/windows/inventory", ["panel", "inventory", "inventory_forms", "features/windows/form",
  "features/windows/editor_shared", "fields", "request", "snapshot", "unit_field", "library/sidebar",
  "features/windows/library", "units", "workspace"],
function (panel, inventories, forms, Form, shared, fields, request, snapshot, unitFields, Sidebar, library, units, ui) {
  "use strict";
  var quantities = {
    width_m: fields.with(fields.WIDTH_M_AS_MM, { label: "Width", allowBlank: true }),
    uf_w_m2k: fields.with(fields.U_VALUE, { label: "Uf", allowBlank: true }),
    psi_g_w_mk: fields.with(fields.LINEAR_PSI, { label: "ψ-g", allowBlank: true }),
    ug_w_m2k: fields.with(fields.U_VALUE, { label: "Ug", allowBlank: true }),
    g_value: fields.with(fields.FRACTION, { label: "g-value", max: 1, allowBlank: true }),
    psi_w_mk: fields.with(fields.LINEAR_PSI, { label: "ψ-install", allowBlank: true })
  };
  var common = [["name", "Name"], ["manufacturer", "Manufacturer"], ["product_code", "Product code"]];
  var definitions = {
    frames: { label: "Frame", title: "Frames", recordKind: "ph_composer.windows.frame",
      columns: common.concat([["width_m", "Width"],
      ["uf_w_m2k", "Uf"], ["psi_g_w_mk", "ψ-g"], ["position", "Position"], ["operation", "Operation"],
      ["color", "Color"], ["notes", "Notes"]]) },
    glazings: { label: "Glazing", title: "Glazings", recordKind: "ph_composer.windows.glazing",
      columns: common.concat([["ug_w_m2k", "Ug"],
      ["g_value", "g-value"], ["description", "Description"], ["color", "Color"], ["notes", "Notes"]]) },
    psi_install_types: { label: "Psi-Install Type", title: "Psi-Install Types",
      recordKind: "ph_composer.windows.psi_install_type", columns: [["name", "Name"],
      ["psi_w_mk", "ψ-install"], ["notes", "Notes"]] }
  };
  function Inventory(root, session, send, kind, changed) {
    var self = this; this.root = root; this.kind = kind; this.spec = definitions[kind]; this.changed = changed;
    var spec = Object.assign({}, this.spec, { quantities: quantities });
    this.form = new Form(session, send, kind, spec, changed);
    this.requests = request.channel(session, send, "window-defaults");
    this.body = ui.element("div", "window-product-workspace"); root.appendChild(this.body);
    this.tableRoot = ui.element("div", "window-product-table"); this.body.appendChild(this.tableRoot);
    var adapter = library.adapter(kind, function () {
      return kind === "psi_install_types" && self.settings ? { params: {
        mode: "model_default", expected_settings: shared.clone(self.settings) } } :
        { hint: "Choose a target in Window Types." };
    });
    // The Psi-Install list also sets the Model default, so it stays; the others would only repeat their table.
    this.sidebar = new Sidebar({ session: session, send: send, adapter: adapter, changed: changed,
      besideTable: kind !== "psi_install_types",
      busy: function () { return Boolean(self.guard()); }, onUse: kind === "psi_install_types" ?
        function (row, target) {
          return self.requests.run(shared.PREFIX + "settings.update", { values: {
            default_psi_install_id: row.id, default_install_depth_m: target.expected_settings.default_install_depth_m },
            expected_values: target.expected_settings });
        } : null });
    this.body.appendChild(this.sidebar.root);
    this.color = new forms.ColorForm(session, send, shared.PREFIX + kind + ".update", changed);
    if (kind === "psi_install_types") this.buildDefaults();
    this.inventory = new inventories.Inventory(this.tableRoot, session, send, panel.notify, changed, {
      section: shared.PREFIX + kind, action: shared.PREFIX + kind + ".update", label: spec.label,
      columns: spec.columns, editable: spec.columns.map(function (column) { return column[0];
        }).filter(function (field) {
        return field !== "color";
      }), quantities: quantities,
      // Psi-Install Types have no grouping, so the kit leaves out its Group by control.
      groups: kind === "psi_install_types" ? undefined : [["manufacturer", "Manufacturer"]],
      value: function (record, field) { return record.values[field]; },
      group: function (record) { return { label: record.values.manufacturer || "Manual" }; },
      settings: this.defaults,
      actions: function (row) { return [{ id: "duplicate", icon: "duplicate", label: "Duplicate " +
        row.record.values.name },
        { id: "delete", icon: "delete", label: "Delete " + row.record.values.name }]; },
      actionFor: function (row, command) { if (!self.guard()) self.form.open(command.id, row.record, self.records); },
      actionsCell: function (td, row) { self.uses(td, row.record); },
      cell: function (td, row, field) {
        if (field !== "color") return false;
        forms.colorCell(td, row.record, self.color, function () { return !self.guard(); }); return true;
      } });
    root.appendChild(this.form.root); root.appendChild(this.color.root);
  }
  Inventory.prototype.uses = function (td, record) {
    var self = this; if (!record.use_count) { if (td._uses) td._uses.root.hidden = true; return; }
    if (!td._uses) {
      var trigger = ui.button(""); td._uses = new ui.Bubble(trigger, "Window Type uses"); td.appendChild(td._uses.root);
    }
    td._uses.root.hidden = false; td._uses.trigger.textContent = String(record.element_use_count || record.use_count);
    td._uses.trigger.setAttribute("aria-label", record.values.name + " uses"); td._uses.content.replaceChildren();
    var rows = useRows(record.uses || []), elements = rows.filter(function (row) { return row.sides.length; }).length;
    td._uses.content.appendChild(ui.element("p", "muted", !elements ? "Used as the Model default" :
      "Used by " + elements + (elements === 1 ? " element" : " elements") +
      (rows.length > elements ? " and the Model default" : "")));
    rows.forEach(function (row) {
      var root = ui.element("div", "window-use-row"), label = ui.element("span", "window-use-label");
      label.appendChild(ui.element("span", "", row.name));
      if (row.sides.length) {
        label.appendChild(ui.element("span", "window-use-sides", ui.titleCase(row.sides.join(", "))));
      }
      root.appendChild(label);
      if (row.use.type_id) root.appendChild(ui.button("Open type", function () {
        if (self.guard()) return; td._uses.close(false); panel.navigate("windows", { use: row.use });
      })); td._uses.content.appendChild(root);
    });
  };
  /* One row per element with its sides beneath, in first-use order. The snapshot keeps one use per side, named
     "Type / Element / side" with "(default)" after an inherited side; Open type navigates with the element's
     first use. The Model default stays its own row. */
  function useRows(uses) {
    var rows = [], byElement = {};
    uses.forEach(function (use) {
      if (!use.element_id) { rows.push({ name: use.name, use: use, sides: [] }); return; }
      var key = use.type_id + " " + use.element_id, split = use.name.lastIndexOf(" / " + use.side);
      if (!byElement[key]) {
        rows.push(byElement[key] = { name: split < 0 ? use.name : use.name.slice(0, split), use: use, sides: [] });
      }
      byElement[key].sides.push(split < 0 ? use.side : use.name.slice(split + 3));
    });
    rows.forEach(function (row) {
      row.sides.sort(function (a, b) {
        return shared.sides.indexOf(a.split(" ")[0]) - shared.sides.indexOf(b.split(" ")[0]);
      });
    });
    return rows;
  }
  /* The Model's installation defaults, as two action-bar controls: a choice list for the default Psi-Install
     Type, applied on choosing, and a single-value bubble for the install depth, applied on Enter or leaving. */
  var DEPTH = fields.with(fields.LENGTH_M, { label: "Default install depth", min: 0, allowBlank: false });
  function settingControl(label) {
    var trigger = ui.button(""), value = ui.element("span", "window-default-value");
    trigger.className = "window-default-control";
    trigger.replaceChildren(ui.element("span", "", label), value, ui.glyph("chevron"));
    trigger.valueText = value; return trigger;
  }
  Inventory.prototype.buildDefaults = function () {
    var self = this;
    // Short visible labels keep the action bar on one line; the accessible names say "Default".
    this.defaultPsi = new ui.Bubble(settingControl("Psi-Install"), "Default Psi-Install");
    this.depthEditor = new unitFields.ValueBubble({ trigger: settingControl("Depth"), title: "Default install depth",
      field: DEPTH, busy: function () { return self.requests.busy(); },
      active: function () { return !self.disposed && self.enabled && Boolean(self.settings); },
      apply: function (value) { return self.saveDefaults(self.settings.default_psi_install_id || null, value); },
      onCancel: function () { self.settingsExpected = null; },
      onClose: function () { self.settingsExpected = null; } });
    this.depthBubble = this.depthEditor.bubble; this.depth = this.depthEditor.field;
    this.depth.input.addEventListener("input", function () { self.captureSettings(); });
    this.defaults = [this.defaultPsi.root, this.depthBubble.root];
  };
  Inventory.prototype.closeDepth = function (focus) {
    if (!this.depthBubble.panel.hidden) this.depthBubble.close(focus);
  };
  Inventory.prototype.choosePsi = function (id) {
    this.defaultPsi.close(true);
    if (id !== (this.settings.default_psi_install_id || null)) {
      this.saveDefaults(id, this.settings.default_install_depth_m);
    }
  };
  Inventory.prototype.paintDefaults = function () {
    var self = this, current = this.settings.default_psi_install_id || null, busy = this.requests.busy();
    var chosen = this.records.filter(function (row) { return row.id === current; })[0];
    var name = chosen ? chosen.values.name : "None", trigger = this.defaultPsi.trigger;
    trigger.valueText.textContent = name; trigger.valueText.classList.toggle("muted", !chosen);
    trigger.setAttribute("aria-label", "Default Psi-Install: " + name); ui.tooltip(trigger, name);
    var choices = [[null, "None"]].concat(this.records.map(function (row) { return [row.id, row.values.name]; }));
    var key = JSON.stringify([current, choices]);
    if (key !== this.choicesKey) {
      this.choicesKey = key;
      this.defaultPsi.content.replaceChildren.apply(this.defaultPsi.content, choices.map(function (choice) {
        var button = ui.button(choice[1], function () { self.choosePsi(choice[0]); });
        button.className = "phc-setting-choice";
        button.setAttribute("aria-pressed", String(choice[0] === current)); return button;
      }));
    }
    var depth = this.settings.default_install_depth_m, text = units.format(depth, DEPTH, units.profile(DEPTH));
    trigger = this.depthBubble.trigger; trigger.valueText.textContent = text;
    trigger.setAttribute("aria-label", "Default install depth: " + text);
    this.depth.setValue(depth); this.depth.setDisabled(busy);
  };
  Inventory.prototype.captureSettings = function () {
    if (!this.settingsExpected) this.settingsExpected = shared.clone(this.settings);
  };
  Inventory.prototype.saveDefaults = function (psiId, depth) {
    if (this.disposed || !this.enabled || this.requests.busy() || !this.defaults || !this.settings) return false;
    this.captureSettings();
    return this.requests.run(shared.PREFIX + "settings.update", { values: { default_psi_install_id: psiId,
      default_install_depth_m: depth }, expected_values: shared.clone(this.settingsExpected) });
  };
  // The Library pane owns the "+ New" button and runs its guard before calling create.
  Inventory.prototype.create = function () { this.form.open("create", null, this.records); };
  Inventory.prototype.canCreate = function () { return Boolean(this.enabled) && !this.inventory.busy(); };
  Inventory.prototype.guard = function () {
    if (this.disposed) return null;
    if (!this.form.root.hidden || !this.color.root.hidden) return "Finish or cancel the product form.";
    if (this.requests.busy()) return "Wait for the defaults edit.";
    if (this.depth && this.depth.editing) return "Correct the install depth or press Escape.";
    if (this.sidebar.guard()) return this.sidebar.guard();
    return this.inventory.guard();
  };
  Inventory.prototype.render = function (state) {
    if (this.disposed) return;
    var payload = snapshot.value(state, shared.PREFIX + this.kind); this.records = payload ? payload.records : [];
    this.enabled = Boolean(payload); this.form.refresh(state); this.color.refresh(state, this.enabled, this.records);
    var self = this;
    function renderInventory() {
      self.inventory.externalBusy = self.form.busy() || self.color.requests.busy() || self.requests.busy();
      self.inventory.render(state);
      self.sidebar.refresh(state, {}, self.enabled);
    }
    if (!this.defaults) { renderInventory(); return; }
    this.settings = snapshot.value(state, shared.PREFIX + "settings");
    var shown = Boolean(payload && this.settings);
    this.defaultPsi.root.hidden = !shown; this.depthBubble.root.hidden = !shown;
    if (!shown) {
      this.requests.reset(); this.settingsExpected = null; this.depth.editing = false; this.depth.repaint();
      this.defaultPsi.close(false); this.closeDepth(false); renderInventory(); return;
    }
    var outcome = this.requests.consume(state);
    if (outcome) this.settingsExpected = null;
    var focus = document.activeElement, refused = outcome && outcome.status !== "completed";
    var kept = refused && this.depth.editing;
    if (outcome && !kept) {
      // Return focus to the trigger unless the user has already moved it somewhere else.
      this.depthEditor.accept(this.settings.default_install_depth_m,
        !focus || focus === document.body || this.depthBubble.panel.contains(focus));
    }
    if (kept) {
      this.depthEditor.refuse(snapshot.message(outcome, "The install depth was not applied."));
    } else if (refused) panel.notify(snapshot.message(outcome, "The default was not applied."), "warning");
    this.paintDefaults(); renderInventory();
    if (kept) this.depth.input.focus();
  };
  Inventory.prototype.dispose = function () {
    this.disposed = true; this.enabled = false; this.requests.reset(); this.form.dispose(); this.inventory.dispose();
    this.color.dispose(); if (this.depthEditor) this.depthEditor.dispose();
    this.sidebar.dispose();
  };
  return { Inventory: Inventory, definitions: definitions, quantities: quantities };
});
