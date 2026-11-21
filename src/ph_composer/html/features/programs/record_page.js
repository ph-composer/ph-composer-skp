/* One Programs subtab: the record editor and one right sidebar, the Builders' arrangement. The sidebar is
   the shared library sidebar (library/sidebar.js): this file's records grouped (Default and In this file;
   Schedules by type), + New, search, and for Programs the added library files, whose rows copy through the
   library coordinator with their Schedules. Choosing a record of this file opens it here.

   The editor's header names the record, in place for renaming, with its source and, at its right, Rename,
   Duplicate and an overflow menu holding Delete and, on PH-Composer's own default, Reset to PH-Composer default.
   New and Duplicate act at once under a free name and open the title for renaming; Delete confirms in the shared
   dialog and, while anything uses the record, asks for its replacement. Every request is the page's
   (features/programs/tab.js `run`), one at a time. `body(page)` makes the editor below the header. */
PhComposerUI.define("features/programs/record_page", ["workspace", "library/sidebar", "library/store"],
function (ui, Sidebar, Store) {
  "use strict";
  var el = ui.element;
  var GROUPS = [{ id: "a-default", label: "Default" }, { id: "b-file", label: "In this file" }];

  function RecordPage(kind, host, body) {
    var self = this;
    this.kind = kind; this.host = host;
    this.root = el("div", "pgm-layout");
    this.main = el("div", "pgm-main");
    this.head = el("div", "pgm-head");
    this.identity = el("div", "pgm-identity");
    this.titleRow = el("div", "pgm-title-row");
    this.title = el("h2", "pgm-title");
    this.badge = el("span", "pgm-badge");
    this.titleRow.appendChild(this.title); this.titleRow.appendChild(this.badge);
    this.identity.appendChild(this.titleRow);
    this.tools = el("div", "pgm-tools");
    this.renameButton = ui.iconButton("Rename " + kind.label, "pencil", function () { self.rename(); });
    this.duplicateButton = ui.iconButton("Duplicate " + kind.label, "duplicate", function () { self.duplicate(); });
    this.menu = new ui.ActionMenu(kind.label + " actions");
    this.resetItem = this.menu.add("Reset to PH-Composer default", function () { self.confirmReset(); });
    this.deleteItem = this.menu.add("Delete " + kind.label, function () { self.confirmDelete(); },
      { destructive: true });
    this.tools.appendChild(this.renameButton); this.tools.appendChild(this.duplicateButton);
    this.tools.appendChild(this.menu.root);
    this.head.appendChild(this.identity); this.head.appendChild(this.tools);
    this.empty = el("p", "muted pgm-empty");
    this.body = body(this);
    this.main.appendChild(this.head); this.main.appendChild(this.empty); this.main.appendChild(this.body.root);
    this.root.appendChild(this.main);
    if (kind.library) this.schedules = new Store(host.session, host.send, "schedules", host.changed);
    this.sidebar = new Sidebar({ session: host.session, send: host.send, changed: host.changed,
      localOnly: !kind.library, markKnown: true, adapter: this.adapter(),
      busy: function () { return host.busy(); },
      create: { label: "+ New " + kind.label, run: function () { self.create(); } },
      onOpen: function (row) { self.show(row.id); },
      active: function () { return self.active; },
      dependencyLoading: function (library) {
        return Boolean(self.schedules) && (self.schedules.catalogLoading(library.provider_id) ||
          (self.schedules.selected === library.provider_id && self.schedules.loading()));
      } });
    this.root.appendChild(this.sidebar.root);
  }

  /* The sidebar's view of this file's records: grouped Default and In this file, or as the kind groups them. */
  RecordPage.prototype.adapter = function () {
    var self = this, kind = this.kind;
    return { title: kind.label + " Library", localLabel: kind.plural + " in this file", wireKind: kind.library,
      emptyText: "No other " + kind.plural + " yet. Choose + New " + kind.label + (kind.library ?
        ", or a library above." : "."),
      read: function () {
        return self.records.map(function (row) {
          return { id: row.id, display_label: row.values.name, use_count: self.useCount(row),
            values: { category: kind.group ? kind.group(row) : (row.default ? GROUPS[0].id : GROUPS[1].id),
              notes: row.values.notes } };
        });
      },
      categories: function () { return kind.groups || GROUPS; },
      name: function (row) { return row.display_label || row.id; },
      decorate: function (node, row) {
        if (row.library || row.use_count === undefined) return;
        var count = el("span", "pgm-sidebar-count", String(row.use_count));
        // Read after the name, so its number stays out of the row's accessible name.
        count.setAttribute("aria-hidden", "true");
        var noun = kind.useNoun || "Zone";
        ui.tooltip(count, "Used by " + row.use_count + " " + noun + (row.use_count === 1 ? "" : "s"));
        node.appendChild(count);
      } };
  };

  /* How many use a record, as the sidebar and the header count it. */
  RecordPage.prototype.useCount = function (row) {
    return this.kind.useCount ? this.kind.useCount(row, this.context) : row.use_count;
  };

  /* One edit of the record's values, guarded by `expected` as the body drew them. */
  RecordPage.prototype.update = function (row, values, expected) {
    return this.host.run(this.host.prefix(this.kind) + ".update", { id: row.id, values: values,
      expected_values: expected });
  };

  RecordPage.prototype.record = function () {
    var active = this.active;
    return this.records.filter(function (row) { return row.id === active; })[0] || null;
  };

  /* Each paint: the records from the snapshot, the one shown (the asked-for one, else the first), its header and
     body, and the sidebar. */
  RecordPage.prototype.render = function (state, context) {
    this.state = state; this.context = context;
    this.records = context.records(this.kind);
    if (!this.record()) {
      var first = this.records.filter(function (row) { return row.default; })[0] || this.records[0];
      this.active = first ? first.id : null;
    }
    var row = this.record(), enabled = context.enabled && !this.host.busy();
    this.head.hidden = !row; this.body.root.hidden = !row; this.empty.hidden = Boolean(row);
    this.empty.textContent = context.available ? "No " + this.kind.plural + " in this file yet. Choose + New " +
      this.kind.label + "." : context.unavailable || "";
    if (row) {
      if (!this.renaming) this.title.textContent = row.values.name;
      var badge = this.kind.badge(row);
      this.badge.textContent = badge || ""; this.badge.hidden = !badge; ui.tooltip(this.badge, badge || "");
      this.badge.classList.toggle("is-lib", Boolean(row.values.source && row.values.source.kind === "library"));
      this.renameButton.disabled = !enabled || Boolean(this.renaming);
      this.duplicateButton.disabled = !enabled;
      this.resetItem.hidden = !this.kind.reserved || row.id !== this.kind.reserved;
      this.menu.setUnavailable(enabled ? null : "Wait for the last change to finish.");
      // Fields stay usable while a write is out, so a focused one keeps its focus; the page sends one at a time.
      this.body.render(row, Object.assign({ enabled: context.available }, context.bodyContext(this.kind, row)));
    }
    if (this.schedules) {
      this.schedules.update(state);
      var selected = this.sidebar.store && this.sidebar.store.selected;
      if (selected && this.schedules.selected !== selected) this.schedules.select(selected);
    }
    this.sidebar.refresh(state, {}, context.enabled);
    if (row && this.renameAfter === row.id) { this.renameAfter = null; this.rename(); }
  };

  /* Opens a record of this file. */
  RecordPage.prototype.show = function (id) {
    if (this.host.busy()) { this.host.refuse("Wait for the last change to finish."); return; }
    if (this.guard()) { this.host.refuse(this.guard()); return; }
    this.active = id;
    this.host.repaint();
  };

  RecordPage.prototype.guard = function () {
    if (this.renaming) return "Finish or cancel the name edit.";
    if (this.body.typing && this.body.typing()) return "Finish or cancel the value being typed.";
    return this.sidebar.guard();
  };

  /* ---------------------------------------------------------------- lifecycle */

  RecordPage.prototype.opened = function (outcome) {
    var id = outcome && outcome.value && outcome.value.id;
    if (!id) return;
    this.active = id; this.renameAfter = id;
    this.sidebar.revealLocal(id);
  };

  RecordPage.prototype.create = function () {
    var self = this;
    this.host.run(this.host.prefix(this.kind) + ".create", { values: this.kind.createValues || {} },
      function (outcome) { self.opened(outcome); return null; });
  };

  RecordPage.prototype.duplicate = function () {
    var self = this, row = this.record();
    if (!row) return;
    this.host.run(this.host.prefix(this.kind) + ".duplicate", { id: row.id },
      function (outcome) { self.opened(outcome); return null; });
  };

  /* The title becomes a field with check and cross: Enter or the check applies, Escape or the cross cancels,
     leaving the field applies. */
  RecordPage.prototype.rename = function () {
    var self = this, row = this.record();
    if (!row || this.renaming || this.host.busy()) return;
    var baseline = row.values.name, done = false;
    var editor = el("div", "pgm-title-editor"), input = el("input", "pgm-title-input");
    input.value = baseline; input.setAttribute("aria-label", this.kind.label + " name");
    var apply = ui.iconButton("Apply name", "check", function () { finish(true); });
    var cancel = ui.iconButton("Cancel rename", "clear", function () { finish(false); });
    [apply, cancel].forEach(function (button) {
      button.addEventListener("mousedown", function (event) { event.preventDefault(); });
    });
    editor.appendChild(input); editor.appendChild(apply); editor.appendChild(cancel);
    this.renaming = { id: row.id, cancel: function () { finish(false); } };
    function finish(commit, leaving) {
      if (done) return;
      var name = input.value.trim();
      var taken = self.records.some(function (other) {
        return other.id !== row.id && other.values.name.trim().toLowerCase() === name.toLowerCase();
      });
      // Leaving the field with a name that cannot apply cancels, so the field never holds the focus hostage.
      if (commit && leaving && name !== baseline && (!name || taken)) commit = false;
      if (commit && name !== baseline && (!name || taken)) {
        input.setAttribute("aria-invalid", "true");
        ui.tooltip(input, name ? "Another " + self.kind.label + " has this name." : "Enter a name.");
        input.focus();
        return;
      }
      done = true; self.renaming = null;
      if (editor.parentNode) editor.parentNode.replaceChild(self.title, editor);
      if (commit && name !== baseline) {
        self.title.textContent = name;
        self.host.run(self.host.prefix(self.kind) + ".update", { id: row.id, values: { name: name },
          expected_values: { name: baseline } });
      } else self.host.repaint();
      self.renameButton.focus({ preventScroll: true });
    }
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); finish(true); }
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); finish(false); }
    });
    input.addEventListener("blur", function () { finish(true, true); });
    this.titleRow.replaceChild(editor, this.title);
    input.focus(); input.select();
  };

  /* A confirmation in the shared dialog; `replacement` adds the select of the record that takes this one's place. */
  RecordPage.prototype.askFirst = function (heading, text, label, replacement, apply) {
    var self = this, trigger = document.activeElement, dialog = ui.formDialog("phc-confirm-dialog pgm-confirm", close);
    function close() {
      dialog.closeModal();
      if (dialog.parentNode) dialog.parentNode.removeChild(dialog);
      if (trigger && trigger.isConnected) trigger.focus({ preventScroll: true });
    }
    dialog.appendChild(el("h2", "", heading));
    dialog.appendChild(el("p", "", text));
    var select = null;
    if (replacement) {
      var label_ = el("label", "pgm-replacement", replacement.label);
      select = el("select");
      select.appendChild(ui.option("", "Choose a replacement"));
      replacement.rows.forEach(function (other) { select.appendChild(ui.option(other.id, other.values.name)); });
      select.value = "";
      label_.appendChild(select); dialog.appendChild(label_);
    }
    var cancel = ui.button("Cancel", close);
    var commit = ui.button(label, function () { var choice = select ? select.value : null; close(); apply(choice); });
    commit.className = "phc-confirm-delete";
    // A replacement is chosen, never assumed: the commit waits for one.
    function paint() {
      commit.disabled = Boolean(replacement && !select.value);
      ui.tooltip(commit, commit.disabled ? (replacement.rows.length ? "Choose a replacement first." :
        "There is no other " + self.kind.label + " to take its place.") : "");
    }
    if (select) select.addEventListener("change", paint);
    paint();
    dialog.appendChild(ui.actionRow(cancel, commit, true));
    self.root.appendChild(dialog); dialog.openModal(); cancel.focus({ preventScroll: true });
    return dialog;
  };

  /* Delete names what goes; a record something uses asks for the one that takes its place,
     which must be of the same type for a Schedule. */
  RecordPage.prototype.confirmDelete = function () {
    var self = this, row = this.record(), kind = this.kind;
    if (!row) return;
    // Anything naming it counts, Segment settings and Dwellings too (`use_count`); the words name its Zones.
    var uses = this.useCount(row), used = row.use_count > 0 || row.default;
    var others = this.records.filter(function (other) {
      return other.id !== row.id && (!kind.sameType || kind.sameType(other, row));
    });
    var text = used ? kind.usedText(row, uses) + " Choose the " + kind.label + " that takes its place." :
      "This removes " + row.values.name + " from this model.";
    this.askFirst("Delete " + kind.label + "?", text, "Delete " + kind.label, used ? {
      label: "Replace with", rows: others } : null, function (replacement) {
      var params = { id: row.id, expected_values: { name: row.values.name } };
      if (replacement) params.replacement_id = replacement;
      self.host.run(self.host.prefix(kind) + ".delete", params, function () {
        if (self.active === row.id) self.active = replacement || null;
        return row.values.name + " deleted.";
      });
    });
  };

  RecordPage.prototype.confirmReset = function () {
    var self = this, row = this.record();
    if (!row) return;
    this.askFirst("Reset to PH-Composer default?", "This rewrites " + row.values.name + " with PH-Composer's " +
      "values, replacing any edits made to it.", "Reset", null, function () {
      self.host.run("ph_composer.programs.reset_default", { kind: self.kind.resetKind }, function () {
        return row.values.name + " reset to PH-Composer's values.";
      });
    });
  };

  RecordPage.prototype.dispose = function () {
    if (this.renaming) this.renaming.cancel();
    this.sidebar.dispose();
    if (this.schedules) this.schedules.dispose();
    if (this.body.dispose) this.body.dispose();
  };

  return RecordPage;
});
