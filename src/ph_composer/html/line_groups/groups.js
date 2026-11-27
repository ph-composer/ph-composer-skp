/* A feature's line groups on its pill, as the last read found them (line_groups/shared.js has the spec): each
   group's name, the record it links to, chosen in place (one groups.link, or groups.unlink for None, guarded by the
   values read), its line count and where it sits somewhere its lines may not. Make <group> asks for the record to
   link and calls groups.make with the selected loose lines, which it wraps in the new group where they are drawn. */
PhComposerUI.define("line_groups/groups", ["panel", "request", "snapshot", "workspace", "table", "record_form",
  "inventory_forms", "choice_cell", "line_groups/shared"],
function (panel, request, snapshot, ui, tables, RecordForm, forms, choiceCell, shared) {
  "use strict";
  function linkRows(spec, state) {
    return ((snapshot.value(state, spec.link.section) || {}).records || []).slice().sort(function (a, b) {
      return ui.compareText(a.values.name, b.values.name);
    });
  }

  /* Make <group>: the record its lines serve. `paths()` is the selected lines' paths as the bar read them, or null
     while Make is blocked; `done(value)` gets the made group's name and the count of Faces it erased. */
  function GroupForm(session, send, spec, paths, done) {
    var self = this;
    // RecordForm keeps its own spec, so the line group's is held apart.
    this.lines = spec; this.paths = paths;
    RecordForm.call(this, session, send, { title: "Make " + spec.label, action: spec.prefix + "groups.make",
      label: spec.key + "-group-make", submitLabel: "Make " + spec.label, pendingText: "Making...",
      failureText: "The " + spec.label + " was not made.", changed: function (value) { if (value) done(value); } });
    this.link = forms.labelled(this.form, spec.link.label, ui.element("select"));
    RecordForm.required(this.link.parentNode, this.link);
    this.link.addEventListener("change", function () { self.updateButton(); });
    this.hint = ui.element("p", "phc-form-hint");
    this.form.appendChild(this.hint);
    this.finish();
  }
  RecordForm.extend(GroupForm);
  GroupForm.prototype.updateButton = function () {
    var paths = this.paths(), count = paths ? paths.length : 0;
    var hint = count ? count + " selected line" + (count === 1 ? "" : "s") + " move into the new group where " +
      (count === 1 ? "it is" : "they are") + " drawn. Double-click the group in SketchUp to draw more lines in it." :
      "Select the loose lines to make it from.";
    if (this.hint.textContent !== hint) this.hint.textContent = hint;
    this.submitButton.disabled = !this.enabled || this.busy() || !this.link.value || !count;
  };
  /* The records as the snapshot has them; the choice is kept while its record exists. */
  GroupForm.prototype.paintLinks = function (state, fresh) {
    var rows = linkRows(this.lines, state), chosen = this.link.value, label = this.lines.link.label;
    this.link.replaceChildren(ui.option("", rows.length ? "Choose a " + label : "Create a " + label + " first"));
    rows.forEach(function (row) { this.link.appendChild(ui.option(row.id, row.values.name)); }, this);
    // Only a form just opened takes the sole choice for the user.
    if (fresh) this.link.value = rows.length === 1 ? rows[0].id : "";
    else this.link.value = rows.some(function (row) { return row.id === chosen; }) ? chosen : "";
  };
  GroupForm.prototype.open = function (state) {
    if (!this.enabled) return;
    this.paintLinks(state, true);
    this.error.textContent = "";
    this.updateButton(); this.show(); this.link.focus();
  };
  GroupForm.prototype.submit = function () {
    this.updateButton();
    var params = { edge_paths: this.paths() };
    params[this.lines.link.key] = this.link.value;
    if (!this.submitButton.disabled) this.run(params);
  };
  GroupForm.prototype.refresh = function (state) {
    var outcome = forms.refreshForm(this, state, this.lines.link.section);
    if (!this.root.hidden && !this.busy()) this.paintLinks(state, false);
    if (outcome && outcome.status === "completed") this.hide(outcome.value);
    this.updateButton();
  };
  GroupForm.prototype.dispose = function () { this.enabled = false; this.withdraw(); };

  function Groups(root, session, send, spec, read) {
    this.spec = spec; this.read = read;
    this.links = request.channel(session, send, spec.key + "-group-link");
    this.root = ui.element("section", "line-group-groups");
    this.root.appendChild(ui.element("h2", "", spec.label + "s"));
    this.mount = ui.element("div", "line-group-table");
    this.root.appendChild(this.mount);
    root.appendChild(this.root);
  }
  Groups.prototype.busy = function () { return this.links.busy(); };
  Groups.prototype.link = function (row, linkedId) {
    var read = this.read, params = { targets: [{ reference: JSON.parse(JSON.stringify(row.reference)),
      expected_values: JSON.parse(JSON.stringify(row.values)) }] };
    if (this.links.busy()) return;
    if (linkedId) params[this.spec.link.key] = linkedId;
    this.links.run(this.spec.prefix + (linkedId ? "groups.link" : "groups.unlink"), params,
      { onDone: function () { read.read(); } });
    panel.repaint();
  };
  Groups.prototype.render = function (state) {
    var self = this, spec = this.spec, outcome = this.links.consume(state);
    if (outcome && outcome.status === "refused") {
      panel.notify(snapshot.message(outcome, "The " + spec.label + " was not changed."), "warning");
    }
    var rows = this.read.groupRows || [];
    var choices = [{ value: "", label: "None" }].concat(linkRows(spec, state).map(function (linked) {
      return { value: linked.id, label: linked.values.name };
    }));
    tables.table(this.mount, rows, { rows: rows.map(function (row) {
      return { key: row.path.join("/"), record: row, tier: "Group", depth: 0, parent: null };
    }), columns: [["group_name", spec.label], ["link", spec.link.label], ["line_count", spec.plural],
      ["note", "Note"]], defaultWidths: { group_name: 180, link: 200, line_count: 80, note: 320 },
    value: function (row, name) {
      return row.record[name === "line_count" ? spec.noun + "_count" : name];
    },
    cell: function (td, row, name) { return self.cell(td, row.record, name, choices); },
    empty: this.read.groupRows ? "No " + spec.label + "s yet. Draw " + spec.noun + "s as loose lines, select " +
      "them and use Make " + spec.label + "." : this.read.error || "Reading the " + spec.label + "s..." });
  };
  Groups.prototype.cell = function (td, group, name, choices) {
    var self = this, spec = this.spec, label = shared.groupLabel(spec, group.name, group.path);
    if (name === "group_name") { td.textContent = label; return true; }
    if (name === "link") {
      var current = (group.values || {})[spec.link.key] || "";
      var listed = choices.some(function (choice) { return choice.value === current; }) ? choices :
        choices.concat([{ value: current, label: "Missing " + spec.link.label }]);
      var select = choiceCell(td, { choices: listed, value: current, label: label + " " + spec.link.label,
        disabled: this.links.busy() || !group.reference || Boolean(group.write_refusal),
        choose: function (chosen) { self.link(group, chosen); } });
      ui.tooltip(select, group.write_refusal ? group.write_refusal.message : "");
      return true;
    }
    if (name === "note") {
      var notes = (group.findings || []).map(function (code) { return spec.words[code] || code; });
      if (group.record_problem) notes.push(group.record_problem);
      if (!(group.values || {})[spec.link.key]) {
        notes.push("Link it to a " + spec.link.label + " to export its " + spec.noun + "s.");
      }
      if (group.copied) notes.push("A pasted copy shares its storage; make one unique to assign it.");
      td.textContent = notes.join(" ");
      td.classList.toggle("line-group-warning", notes.length > 0);
      return true;
    }
    return false;
  };
  Groups.prototype.dispose = function () { this.links.reset(); };
  return { Groups: Groups, GroupForm: GroupForm };
});
