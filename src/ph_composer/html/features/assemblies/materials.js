/* The Materials surface of the Library pane: the model's Materials as an editable inventory beside
 * the Material Library sidebar, with New, Duplicate, color and Delete with a replacement. */
PhComposerUI.define("features/assemblies/materials", ["panel", "snapshot", "workspace", "fields", "inventory",
  "inventory_forms", "library/sidebar", "library/section", "features/assemblies/material_form"],
function (panel, snapshot, ui, fields, inventories, forms, Sidebar, library, MaterialForm) {
  "use strict";
  // A Material, local or a library row, is labelled by its name.
  function materialName(row) { return row.display_label || row.values.name; }
  var MATERIALS = "ph_composer.assemblies.materials";
  var categoryClasses = { warm: "category-warm", rose: "category-rose", wood: "category-wood",
    neutral: "category-neutral", blue: "category-blue", violet: "category-violet" };
  var columns = [["name", "Name"], ["color", "Color"], ["category", "Category"],
    ["conductivity_w_mk", "λ"], ["density_kg_m3", "ρ"], ["specific_heat_j_kgk", "c"],
    ["emissivity", "Emissivity"], ["notes", "Notes"]];
  function Surface(root, state, send) {
    var self = this;
    function changed() { panel.repaint(); }
    function allowed() { var reason = self.guard();
    if (reason) panel.notify(reason);
    return !reason; }
    this.records = [];
    this.categories = [];
    this.newMaterial = new MaterialForm(state.session, send, changed);
    this.duplicate = new forms.DuplicateForm(state.session, send, changed, { section: MATERIALS, label: "Material" });
    this.replacement = new forms.ReplacementForm(state.session, send, changed,
      { section: MATERIALS, label: "Material", replacement: true });
    this.color = new forms.ColorForm(state.session, send, MATERIALS + ".update", changed);
    this.forms = [this.newMaterial, this.duplicate, this.replacement, this.color];
    function category(record) {
      return self.categories.filter(function (entry) { return entry.id === record.values.category; })[0] ||
        { label: record.values.category || "None", tone: "neutral" };
    }
    this.sidebar = new Sidebar({ session: state.session, send: send, changed: changed, besideTable: true,
      busy: function () { return Boolean(self.inventory && self.inventory.guard()); },
      adapter: { title: "Material Library", wireKind: "materials", name: materialName, read: function (live) {
        return (snapshot.value(live, MATERIALS) || {}).records || [];
      }, categories: function () { return self.categories; }, properties: [
        ["Conductivity", "conductivity_w_mk", fields.CONDUCTIVITY], ["Density", "density_kg_m3", fields.DENSITY],
        ["Specific heat", "specific_heat_j_kgk", fields.SPECIFIC_HEAT],
        ["Emissivity", "emissivity", fields.FRACTION]] } });
    var workspace = ui.element("div", "library-material-workspace");
    var table = ui.element("div", "library-material-table");
    workspace.appendChild(table);
    workspace.appendChild(this.sidebar.root);
    root.appendChild(workspace);
    this.inventory = new inventories.Inventory(table, state.session, send, panel.notify, changed, {
      section: MATERIALS, action: MATERIALS + ".update", label: "Material", columns: columns,
      editable: columns.map(function (entry) { return entry[0]; }).filter(function (field) {
        return field !== "color";
      }),
      quantities: MaterialForm.quantities, selectFields: { category: [] }, groups: [["category", "Category"]],
      notice: panel.notify,
      value: function (record, field) { return record.values[field]; },
      group: function (record) { return category(record); },
      actions: function (row) { return [
        { id: "duplicate", icon: "duplicate", label: "Duplicate " + row.record.values.name },
        { id: "delete", icon: "delete", label: "Delete " + row.record.values.name }]; },
      actionFor: function (row, command) {
        if (!allowed()) return;
        if (command.id === "duplicate") self.duplicate.open(row.record);
        else self.replacement.open(row.record, self.inventory.records);
      }, actionsCell: function (td, row) { uses(td, row.record); },
      afterCell: function (td, row, field) {
        if (field !== "name") return;
        if (td._sourceBadge) td._sourceBadge.remove();
        var info = self.sidebar.store && self.sidebar.store.localInfo(row.record);
        if (!info) return;
        var badge = ui.button(info.changed ? "Library · source changed" : "Library", function () {
          if (!allowed() || !info.row || !info.comparisonAvailable) return;
          self.sidebar.copy.open(info.row);
        });
        badge.className = "library-source-badge"; ui.tooltip(badge, info.label);
        badge.setAttribute("aria-label", row.record.values.name + " library source: " + info.label +
          (info.changed ? ", source changed" : ""));
        badge.disabled = !info.row || !info.comparisonAvailable;
        td._sourceBadge = badge; td.appendChild(badge);
      },
      cell: function (td, row, field) {
        if (field === "color") { forms.colorCell(td, row.record, self.color, allowed);
        return true; }
        if (field === "category") {
          td.className = "col-category " + (categoryClasses[category(row.record).tone] || categoryClasses.neutral);
        }
        return false;
      } });
    this.forms.forEach(function (form) { root.appendChild(form.root); });
  }
  Surface.prototype.guard = function () {
    if (this.forms.some(function (form) { return !form.root.hidden; })) return "Finish or cancel the open form.";
    return this.sidebar.guard() || this.inventory.guard();
  };
  Surface.prototype.create = function () { this.newMaterial.open(); };
  Surface.prototype.canCreate = function () { return this.payload && !this.inventory.busy(); };
  Surface.prototype.render = function (state) {
    var payload = snapshot.value(state, MATERIALS);
    this.payload = Boolean(payload);
    this.records = payload ? payload.records : [];
    this.categories = payload ? payload.categories : [];
    this.inventory.edits.selectFields.category = [{ value: "", label: "None" }].concat(this.categories.map(
      function (entry) { return { value: entry.id, label: entry.label }; }));
    this.newMaterial.refresh(state);
    this.duplicate.refresh(state);
    this.replacement.refresh(state);
    this.color.refresh(state, Boolean(payload), this.records);
    this.inventory.externalBusy = Boolean(this.sidebar.guard()) || this.forms.some(function (form) {
      return form.busy ? form.busy() : form.requests.busy();
    });
    this.sidebar.refresh(state, {}, Boolean(payload));
    this.inventory.render(state);
  };
  Surface.prototype.dispose = function () {
    this.forms.forEach(function (form) { form.dispose(); });
    this.sidebar.dispose();
    this.inventory.dispose();
  };
  function uses(td, record) {
    if (!record.use_count) { if (td._uses) td._uses.root.hidden = true; return; }
    if (!td._uses) {
      var trigger = ui.button("");
      trigger.setAttribute("data-material-use-count", "");
      trigger.className = "phc-uses-count";
      td._uses = new ui.Bubble(trigger, "Used by Assemblies");
      td.appendChild(td._uses.root);
    }
    td._uses.root.hidden = false;
    td._uses.trigger.textContent = String(record.use_count);
    td._uses.trigger.setAttribute("aria-label", record.values.name + " used by " + record.use_count + " Assemblies");
    td._uses.content.replaceChildren();
    record.uses.forEach(function (use) { td._uses.content.appendChild(ui.element("p", "", use.name)); });
  }
  library.registerSurface({ id: "materials", label: "Materials", order: 10,
    recordKind: "ph_composer.assemblies.material", createLabel: "+ New Material",
    build: function (root, state, send) { return new Surface(root, state, send); } });
  return { Surface: Surface };
});
