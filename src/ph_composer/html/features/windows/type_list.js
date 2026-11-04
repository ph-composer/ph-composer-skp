/* The Window Type rail's list and the actions that add, duplicate, delete, rename and group types. */
PhComposerUI.define("features/windows/type_list", ["features/windows/editor_shared", "unit_preferences", "workspace"],
function (shared, preferences, ui) {
  "use strict";
  var el = ui.element;
  var clone = shared.clone;
  var methods = {};
  /* A new Type's starting size in metres. The host's default is SI's round 1.0 by 1.5 m; the panel asks for the
     round imperial 40 by 60 in instead when the display system is IP, so the operation never reads a display
     preference. */
  var IP_SIZE_M = { columns_m: [1.016], rows_m: [1.524] };

  methods.confirmChange = function (trigger, heading, text, label, apply) {
    var self = this, dialog = ui.formDialog("phc-confirm-dialog", close);
    function close() { dialog.closeModal(); if (dialog.parentNode) dialog.parentNode.removeChild(dialog);
      if (self.root.contains(trigger)) trigger.focus({ preventScroll: true }); }
    dialog.appendChild(el("h2", "", heading)); dialog.appendChild(el("p", "", text));
    var cancel = ui.button("Cancel", close);
    var confirm = ui.button(label, function () { close(); apply(); });
    confirm.className = "phc-confirm-delete"; dialog.appendChild(ui.actionRow(cancel, confirm, true));
    this.root.appendChild(dialog); dialog.openModal(); cancel.focus({ preventScroll: true });
  };
  /* New and Duplicate act at once under a free default name, then open that title for renaming. */
  methods.uniqueName = function (base, numbered) {
    var taken = this.entries.map(function (entry) { return entry.record.name.trim().toLowerCase(); }),
      n = numbered ? 1 : 0, name;
    do { name = numbered ? base + " " + n : (n ? base + " " + (n + 1) : base); n += 1;
      } while (taken.indexOf(name.toLowerCase()) >= 0);
    return name;
  };
  methods.opened = function (result) { if (result && result.id) { this.active = result.id;
    this.renameAfter = result.id; } };
  methods.createType = function () {
    var self = this, values = { name: this.uniqueName("Window Type", true) };
    if (preferences.peek().unitSystem === "IP") Object.assign(values, clone(IP_SIZE_M));
    this.request("ph_composer.windows.types.create", { values: values }, function (result) {
      self.opened(result.value); });
  };
  methods.duplicateType = function (record) {
    var self = this; if (!record || this.requests.pending) return;
    this.request("ph_composer.windows.types.duplicate", { id: record.id, name: this.uniqueName(record.name +
      " (copy)") }, function (result) { self.opened(result.value); });
  };
  methods.deleteType = function (record, trigger) {
    var self = this, baseline = record && clone(record); if (!record || this.requests.pending) return;
    this.confirmChange(trigger, "Delete Window Type?", "This removes " + record.name +
      " from this model. Its definition is removed from this model.", "Delete Window Type", function () {
      self.request("ph_composer.windows.types.delete", { id: baseline.id,
      expected_values: self.authored(baseline) }); });
  };
  /* A Window Type name edits in place, in the header title or its sidebar row: Enter or the check applies,
     Escape or the cross cancels, leaving the field applies. */
  methods.renameInline = function (record, anchor) {
    record = record || this.record(); anchor = anchor || this.title;
    var self = this, row = anchor.parentNode, done = false;
    if (!record || this.guard() || this.disposed || !this.enabled || !row) return;
    var baseline = clone(record); this.renameDraft = true; this.renameTarget = record.id;
    var editor = el("div", "window-title-editor" +
      (anchor === this.title ? "" : " window-row-editor")), input = el("input", "window-title-input");
    input.value = record.name; input.setAttribute("aria-label", "Window Type name");
    var apply = ui.iconButton("Apply name", "check", function () { finish(true); }),
      cancel = ui.iconButton("Cancel rename", "clear", function () { finish(false); });
    this.renameNodes = [input, apply, cancel];
    // Keep focus in the field while pressing a button, so blur cannot apply before the cross cancels.
    [apply, cancel].forEach(function (button) { button.addEventListener("mousedown", function (event) {
      event.preventDefault(); }); });
    editor.appendChild(input); editor.appendChild(apply); editor.appendChild(cancel);
    function finish(commit) {
      if (done || self.requests.busy()) return;
      var candidate = input.value.trim();
      if (commit && (!candidate || self.entries.some(function (entry) { return entry.record.id !== baseline.id &&
        entry.record.name.trim().toLowerCase() === candidate.toLowerCase(); }))) {
        input.setAttribute("aria-invalid", "true"); ui.tooltip(input, "Enter a unique nonempty name."); input.focus();
        return; }
      var name = input.value.trim();
      if (commit && name !== baseline.name) {
        if (self.change("rename", { name: name }, baseline, restore)) {
          input.disabled = true; apply.disabled = true; cancel.disabled = true;
        }
      } else restore();
    }
    function restore() {
      done = true; self.renameDraft = false; self.renameTarget = null; self.renameNodes = null;
      self.cancelRename = null;
      if (editor.parentNode) { editor.parentNode.insertBefore(anchor, editor);
        editor.parentNode.removeChild(editor); }
      row.classList.remove("is-renaming"); self.listSignature = null;
      if (!self.disposed) { self.paint(); if (anchor.isConnected) anchor.focus({ preventScroll: true }); }
    }
    this.cancelRename = restore;
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") { event.preventDefault(); finish(true); }
      if (event.key === "Escape") { event.preventDefault(); finish(false); }
    });
    input.addEventListener("blur", function () { finish(true); });
    row.classList.add("is-renaming"); row.insertBefore(editor, anchor); row.removeChild(anchor); input.focus();
      input.select();
  };

  methods.editName = function (cell, trigger) {
    var self = this, record = clone(this.record()); this.form(trigger, "Element name", cell.name, function (name,
      done) { return self.change("set_element_name", { id: cell.id, name: name }, record, done); },
      null, null, { type_id: record.id, element_id: cell.id });
  };
  /* Eyedropper, then paint bucket: pick one source, paste onto as many elements as needed; the button or Escape ends
    // it. */
  methods.togglePick = function () {
    if (this.picking || this.source) { this.picking = false; this.source = null; this.notice.clear(); }
    else { this.picking = true;
      this.notice.show("Click a glazed element to copy its glazing, frames, operation and Psi-Install assignments.",
      { persistent: true }); }
    this.paint();
  };
  methods.choose = function (id) { if (this.guard()) { this.notice.show(this.guard());
    this.chooser.value = this.active; return; } this.active = id; this.selected = []; this.revealInserted = null;
    this.source = null; this.picking = false; if (this.bubble) this.bubble.close(false); this.paint(); };
  methods.select = function (id, event) {
    if (this.disposed || !this.enabled || this.requests.busy() || this.dimensionField &&
      this.dimensionField.editing) return;
    var cell = this.record() && this.record().elements.filter(function (c) { return c.id === id; })[0];
    if (this.picking) { if (!cell || cell.kind === "empty") return; this.source = id; this.picking = false;
      this.notice.show("Click elements to paste. Press Escape or click the paint bucket to stop.", {
      persistent: true }); }
    else if (this.source) { if (!cell || cell.kind === "empty" || id === this.source) return; this.change("paste", {
      source_id: this.source, ids: [id] }); return; }
    else if (!id) this.selected = [];
    else if (event && (event.shiftKey || event.metaKey || event.ctrlKey)) { var index = this.selected.indexOf(id);
      if (index >= 0) this.selected.splice(index, 1); else this.selected.push(id); }
    else this.selected = [id];
    this.paint();
  };

  methods.renderList = function () {
    var self = this, records = this.entries.map(function (e) { return e.record; });
    records.forEach(function (r) { if (self.order.indexOf(r.id) < 0) self.order.push(r.id); });
    records.sort(function (a, b) {
      return self.manual ? self.order.indexOf(a.id) - self.order.indexOf(b.id) : a.name.localeCompare(b.name); });
    var signature = JSON.stringify(records.map(function (r) { return [r.id, r.name]; }));
    if (signature !== this.chooserSignature) { this.chooserSignature = signature; this.chooser.replaceChildren();
      records.forEach(function (r) { self.chooser.appendChild(ui.option(r.id, r.name)); }); }
    this.chooser.value = this.active || "";
    var collapsed = this.railCollapsed(); this.railContent.hidden = collapsed; this.railStrip.hidden = !collapsed;
    this.rail.classList.toggle("window-rail-collapsed", collapsed); this.layout.classList.toggle("collapsed",
      collapsed);
    this.railStrip.setAttribute("aria-expanded", String(!collapsed));
      this.railCollapse.setAttribute("aria-expanded", String(!collapsed));
    ui.paintIconButton(this.sortTypes, this.manual ? "Use alphabetical Window Type order" :
      "Use manual Window Type order", "sort");
    this.sortTypes.setAttribute("aria-pressed", String(Boolean(this.manual)));
    var listSignature = JSON.stringify([signature, this.active, this.groups, this.groupNames, this.manual,
      this.placement.enabled, this.placement.channel.busy(), records.map(function (record) {
        return self.placement.available(record.id); }), this.entries.map(function (entry) {
        return entry.findings; })]);
    // Keep the target row and its focused input keyed until Apply or Cancel. Deferred labels repaint then.
    if (this.renameDraft) return;
    if (listSignature === this.listSignature) return; this.listSignature = listSignature;
    this.list.replaceChildren();
    this.groupNames.forEach(function (group) {
      var heading = el("div", "window-group", group || "Window Types"); heading.setAttribute("tabindex", "0");
      // The rail's own title already names the one ungrouped list; a caption only helps once groups exist.
      heading.hidden = self.groupNames.length === 1 && !group;
        self.list.appendChild(heading);
      function move(id) { self.groups[id] = group; self.manual = true; self.paint(); }
      heading.addEventListener("dragover", function (e) { e.preventDefault(); }); heading.addEventListener("drop",
        function (e) { e.preventDefault(); move(e.dataTransfer.getData("text/plain")); });
      records.filter(function (r) { return (self.groups[r.id] || "") === group; }).forEach(function (record) {
        var row = el("div", "window-type-row" + (record.id === self.active ? " selected" : ""));
          row.draggable = Boolean(self.manual);
        row.addEventListener("dragstart", function (e) { e.dataTransfer.setData("text/plain", record.id); });
        row.addEventListener("dragover", function (e) { e.preventDefault(); }); row.addEventListener("drop",
          function (e) { e.preventDefault(); var id = e.dataTransfer.getData("text/plain");
          if (self.order.indexOf(id) < 0) return; self.order.splice(self.order.indexOf(id), 1);
          self.order.splice(self.order.indexOf(record.id), 0, id); move(id); });
        var choose = ui.button(record.name, function () { self.choose(record.id); }); row.appendChild(choose);
        // "Not finished" is the amber mark it is on every other screen, with what is missing in its tooltip.
        var entry = self.entries.filter(function (item) { return item.record.id === record.id; })[0];
        var missing = entry ? entry.findings.map(function (finding) {
          return finding.message || String(finding);
        }).filter(function (message, index, all) { return all.indexOf(message) === index; }) : [];
        if (missing.length) {
          var flag = ui.glyph("alert"); flag.classList.add("window-type-flag"); flag.setAttribute("role", "img");
          flag.setAttribute("aria-label", record.name + " is incomplete");
          ui.tooltip(flag, missing.slice(0, 6).join(" ") + (missing.length > 6 ? " And more." : ""));
          row.appendChild(flag);
        }
        var actions = el("span", "window-type-row-actions");
        var place = ui.iconButton("Place " + record.name, "add", function () { self.placement.choose(record.id); });
        place.disabled = !self.placement.enabled || !self.placement.available(record.id);
        actions.appendChild(place);
        actions.appendChild(ui.iconButton("Rename " + record.name, "pencil", function () { self.renameInline(record,
          choose); }));
        actions.appendChild(ui.iconButton("Duplicate " + record.name, "duplicate", function () {
          self.duplicateType(record); }));
        var remove = ui.iconButton("Delete " + record.name, "delete", function () { self.deleteType(record, remove);
          }); actions.appendChild(remove);
        row.appendChild(actions);
        /* The move handle exists only in manual order, where dragging and group moves apply. */
        if (self.manual) {
          var organize = ui.iconButton("Move " + record.name, "grip", function () {
            self.form(organize, "Move to display group", self.groups[record.id] || "", function (name) {
              if (self.groupNames.indexOf(name) < 0) self.groupNames.push(name); self.groups[record.id] = name;
              self.manual = true; self.paint(); }, "Alphabetical or manual order changes this view only.",
              function (form) {
              form.appendChild(ui.button("Move up", function () { var i = self.order.indexOf(record.id);
                if (i > 0) { self.order.splice(i, 1); self.order.splice(i - 1, 0, record.id); } self.manual = true;
                self.paint(); }));
            });
          }); organize.classList.add("window-type-move"); actions.appendChild(organize);
        }
        self.list.appendChild(row);
      });
    });
  };

  return methods;
});
