/* The Piping groups on the Piping pill, as the last read found them: each group's name, the Hot Water System its
   pipes serve, chosen in place (one groups.link, or groups.unlink for None, guarded by the values read), its pipe
   count and where it sits somewhere pipes may not. New Piping group asks for a System and calls groups.create, which
   opens the new group so the Line tool draws into it. */
PhComposerUI.define("features/piping/groups", ["panel", "request", "snapshot", "workspace", "table", "record_form",
  "inventory_forms", "features/mechanical/equipment_table", "features/mechanical/hot_water", "features/piping/shared"],
function (panel, request, snapshot, ui, tables, RecordForm, forms, equipment, hotWater, shared) {
  "use strict";
  var SYSTEMS = hotWater.SECTIONS.systems;
  var WORDS = { "piping.group_in_zone": "A Zone holds it, so its pipes cannot be assigned or exported.",
    "piping.group_nested": "It sits inside another Piping group, so its pipes cannot be assigned or exported." };
  function systemRows(state) {
    return ((snapshot.value(state, SYSTEMS) || {}).records || []).slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name);
    });
  }

  /* New Piping group: the Hot Water System its pipes serve. */
  function GroupForm(session, send, done) {
    var self = this;
    RecordForm.call(this, session, send, { title: "New Piping group", action: shared.PREFIX + "groups.create",
      label: "piping-group-create", submitLabel: "Create and open", pendingText: "Creating...",
      failureText: "The Piping group was not created.", changed: function (value) { if (value) done(); } });
    this.system = forms.labelled(this.form, "Hot Water System", ui.element("select"));
    RecordForm.required(this.system.parentNode, this.system);
    this.system.addEventListener("change", function () { self.updateButton(); });
    this.form.appendChild(ui.element("p", "phc-form-hint", "The new group opens in SketchUp, so the lines you " +
      "draw next with the Line tool land inside it."));
    this.finish();
  }
  RecordForm.extend(GroupForm);
  GroupForm.prototype.updateButton = function () {
    this.submitButton.disabled = !this.enabled || this.busy() || !this.system.value;
  };
  /* The Systems as the snapshot has them; the choice is kept while its System exists. */
  GroupForm.prototype.paintSystems = function (state, fresh) {
    var rows = systemRows(state), chosen = this.system.value;
    this.system.replaceChildren(ui.option("", rows.length ? "Choose a Hot Water System" :
      "Create a Hot Water System first"));
    rows.forEach(function (row) { this.system.appendChild(ui.option(row.id, row.values.name)); }, this);
    // Only a form just opened takes the sole choice for the user.
    if (fresh) this.system.value = rows.length === 1 ? rows[0].id : "";
    else this.system.value = rows.some(function (row) { return row.id === chosen; }) ? chosen : "";
  };
  GroupForm.prototype.open = function (state) {
    if (!this.enabled) return;
    this.paintSystems(state, true);
    this.error.textContent = "";
    this.updateButton(); this.show(); this.system.focus();
  };
  GroupForm.prototype.submit = function () {
    this.updateButton();
    if (!this.submitButton.disabled) this.run({ hot_water_system_id: this.system.value });
  };
  GroupForm.prototype.refresh = function (state) {
    var outcome = forms.refreshForm(this, state, SYSTEMS);
    if (!this.root.hidden && !this.busy()) this.paintSystems(state, false);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    this.updateButton();
  };
  GroupForm.prototype.dispose = function () { this.enabled = false; this.withdraw(); };

  function Groups(root, session, send, read) {
    this.read = read; this.state = null;
    this.links = request.channel(session, send, "piping-group-link");
    this.root = ui.element("section", "piping-groups");
    this.root.appendChild(ui.element("h2", "", "Piping groups"));
    this.mount = ui.element("div", "piping-table");
    this.root.appendChild(this.mount);
    root.appendChild(this.root);
  }
  Groups.prototype.busy = function () { return this.links.busy(); };
  Groups.prototype.link = function (row, systemId) {
    var read = this.read;
    if (this.links.busy()) return;
    var targets = [{ reference: JSON.parse(JSON.stringify(row.reference)),
      expected_values: JSON.parse(JSON.stringify(row.values)) }];
    this.links.run(shared.PREFIX + (systemId ? "groups.link" : "groups.unlink"),
      systemId ? { targets: targets, hot_water_system_id: systemId } : { targets: targets },
      { onDone: function () { read.read(); } });
    panel.repaint();
  };
  Groups.prototype.render = function (state) {
    var self = this, outcome = this.links.consume(state);
    this.state = state;
    if (outcome && outcome.status === "refused") {
      panel.notify(snapshot.message(outcome, "The Piping group was not changed."), "warning");
    }
    var rows = this.read.groupRows || [], systems = systemRows(state);
    var choices = [{ value: "", label: "None" }].concat(systems.map(function (system) {
      return { value: system.id, label: system.values.name };
    }));
    tables.table(this.mount, rows, { rows: rows.map(function (row) {
      return { key: row.path.join("/"), record: row, tier: "Group", depth: 0, parent: null };
    }), columns: [["group_name", "Piping group"], ["system", "Hot Water System"], ["pipe_count", "Pipes"],
      ["note", "Note"]], defaultWidths: { group_name: 180, system: 200, pipe_count: 80, note: 320 },
    value: function (row, name) { return row.record[name]; },
    cell: function (td, row, name) { return self.cell(td, row.record, name, choices); },
    empty: this.read.groupRows ? "No Piping groups yet. New Piping group makes one to draw pipes in." :
      this.read.error || "Reading the Piping groups..." });
  };
  Groups.prototype.cell = function (td, group, name, choices) {
    var self = this;
    if (name === "group_name") { td.textContent = shared.groupLabel(group.name, group.path); return true; }
    if (name === "system") {
      var current = (group.values || {}).hot_water_system_id || "";
      var listed = choices.some(function (choice) { return choice.value === current; }) ? choices :
        choices.concat([{ value: current, label: "Missing Hot Water System" }]);
      var select = equipment.choiceCell(td, { choices: listed, value: current, label: shared.groupLabel(group.name,
        group.path) +
        " Hot Water System", disabled: this.links.busy() || !group.reference || Boolean(group.write_refusal),
      choose: function (chosen) { self.link(group, chosen); } });
      ui.tooltip(select, group.write_refusal ? group.write_refusal.message : "");
      return true;
    }
    if (name === "note") {
      var notes = (group.findings || []).map(function (code) { return WORDS[code] || code; });
      if (group.record_problem) notes.push(group.record_problem);
      if (!(group.values || {}).hot_water_system_id) notes.push("Link it to a Hot Water System to export its pipes.");
      if (group.copied) notes.push("A pasted copy shares its storage; make one unique to assign it.");
      td.textContent = notes.join(" ");
      td.classList.toggle("piping-warning", notes.length > 0);
      return true;
    }
    return false;
  };
  Groups.prototype.dispose = function () { this.links.reset(); };
  return { Groups: Groups, GroupForm: GroupForm };
});
