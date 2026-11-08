/* A Schedule counts authored occurrences, including detached definitions and copied identities. */
PhComposerUI.define("features/windows/schedule", ["request", "snapshot", "table", "face_words",
  "workspace", "units", "fields", "record_edits"],
function (request, snapshot, tables, faceWords, ui, units, fields, RecordEdits) {
  "use strict";
  var PREFIX = "ph_composer.windows.", clone = function (value) { return JSON.parse(JSON.stringify(value)); };
  var STATES = { "window.definition_detached": "Detached definition", "window.geometry_differs": "Geometry differs",
    "window.unknown_type": "Unknown Type", "window.copy_id_pending": "Copy, id pending",
    "window.unhosted": "Unhosted", "window.off_host": "Off host", "window.overhang": "Overhangs host",
    "window.overlap": "Overlapping", "window.surface_host": "Surface host",
    "window.host_zone_unresolved": "Host Zone unresolved", "window.host_unclassified": "Host unclassified",
    "window.host_type_unsupported": "Host not a wall or roof", "window.host_boundary_unsupported": "Host not outdoors",
    "window.scaled": "Scaled", "window.sheared": "Sheared", "window.mirrored": "Mirrored" };
  /* Each repair the Ruby findings name, in the order the row menu offers them. */
  var REPAIRS = [["reset_to_type", "Reset to Type", "undo"], ["new_flipped_type", "New flipped Type", "mirror"],
    ["rehost", "Re-host Window", "enter"], ["repair_copied_identities", "Repair copied identities", "repair"]];
  function Schedule(owner) {
    this.owner = owner; this.expanded = owner.page.scheduleExpanded || {};
    owner.page.scheduleExpanded = this.expanded;
    this.root = ui.element("div", "window-schedule"); this.summary = ui.element("p", "muted");
    this.root.appendChild(this.summary); this.mount = ui.element("div", "phc-table-mount");
    this.root.appendChild(this.mount);
    this.edits = request.channel(owner.session, owner.send, "window-schedule");
    this.views = request.channel(owner.session, owner.send, "window-schedule-locate", "view.invoke");
    this.selected = {};
    var self = this;
    this.names = new RecordEdits(owner.session, owner.send, function (text) { owner.notice.show(text); }, {
      action: PREFIX + "units.rename", fields: ["name"], recordLabel: "Window", navigateOnCommit: false,
      cancelControl: true, enabled: function () { return self.enabled && self.owner.enabled; },
      eligible: function (row) { return Boolean(row.record.unit); },
      readOnly: function () { return self.edits.busy(); },
      rawValue: function (row) { return row.record.unit ? row.record.unit.name : ""; },
      placeholder: function (row) { return row.record.defaultName; },
      label: function (row) { return row.record.defaultName + " name"; },
      send: function (cell) {
        var unit = cell.row.record.unit;
        return { action: PREFIX + "units.rename", params: { unit: clone(unit.reference), name: cell.submitted,
          expected_name: unit.name } };
      }
    });
  }
  Schedule.prototype.guard = function () {
    return this.edits.busy() || this.views.busy() || this.names.pending ? "Wait for the Window command." :
      this.dialog ? "Apply or cancel the Window repair." : null;
  };
  Schedule.prototype.zone = function (unit) {
    var path = unit.host ? unit.host.zone_path : unit.reference.entity_path;
    return this.zones.filter(function (zone) {
      var own = zone.reference.zone_path;
      return own.length <= path.length && own.every(function (id, index) { return id === path[index]; });
    }).sort(function (a, b) { return b.reference.zone_path.length - a.reference.zone_path.length; })[0];
  };
  Schedule.prototype.faceName = function (reference) {
    var path = reference.zone_path.concat(reference.entity_path);
    var found = this.faces.filter(function (face) { return JSON.stringify(face.reference.zone_path.concat(
      face.reference.entity_path)) === JSON.stringify(path); })[0];
    if (!found) return "Host Face";
    var own = this.faces.filter(function (face) { return JSON.stringify(face.reference.zone_path) ===
      JSON.stringify(reference.zone_path); });
    return faceWords.faceName(found, own);
  };
  Schedule.prototype.netArea = function (unit) {
    if (!unit.host) return "—";
    var host = this.areas.filter(function (row) {
      return row.reference.zone_id === unit.host.zone_id && row.reference.entity_id === unit.host.entity_id &&
        JSON.stringify(row.reference.zone_path.concat(row.reference.entity_path)) ===
          JSON.stringify(unit.host.zone_path.concat(unit.host.entity_path));
    })[0];
    return !host || host.net_opaque_area_m2 === null ? "—" :
      units.format(host.net_opaque_area_m2, fields.AREA_M2, units.profile(fields.AREA_M2), { showUnit: false });
  };
  Schedule.prototype.rows = function () {
    var self = this, ids = {}, types = this.owner.entries.map(function (entry) { return entry.record; })
      .sort(function (a, b) { return ui.compareText(a.name, b.name); });
    types.forEach(function (type) { ids[type.id] = true; });
    this.units.forEach(function (unit) { var id = unit.values.window_type_id;
      if (!ids[id]) { ids[id] = true; types.push({ id: id, name: "Unknown Type", unknown: true }); } });
    var rows = [];
    types.forEach(function (type) {
      var units = self.units.filter(function (unit) { return unit.values.window_type_id === type.id; });
      var key = "type:" + type.id;
      rows.push({ key: key, depth: 0, tier: "Type", record: { name: type.name, type: type,
        count: self.enabled ? units.length : "—", audit: type.unknown ? "Window Type id: " + type.id : null } });
      units.forEach(function (unit, index) {
        var zone = self.zone(unit);
        rows.push({ key: JSON.stringify(unit.reference.entity_path), parent: key, depth: 2, tier: "Unit",
          // Numbered per Type, so the Type in the name keeps two Types' first Windows apart.
          record: { name: unit.name || type.name + " " + (index + 1), defaultName: type.name + " " + (index + 1),
            unit: unit, zone: zone ? zone.values.name : "—",
            audit: "Window Type: " + type.name + "; Unit id: " + unit.id + "; occurrence path: " +
              unit.reference.entity_path.join(" / "),
            level: zone && zone.values.level !== null && zone.values.level !== undefined ? zone.values.level : "—",
            host: unit.host ? self.faceName(unit.host) : "Unhosted", net_area: self.netArea(unit),
            state: (unit.findings || []).map(function (finding) {
              return STATES[finding.code] || "Needs review";
            }).join("; ") || "Matches Type" } });
      });
    }); return rows;
  };
  /* The repair operations a Unit's findings name, keyed by action: `{ name, params }`. */
  function repairs(unit) {
    var named = {};
    (unit.findings || []).forEach(function (finding) {
      if (finding.repair) named[finding.repair.name.slice((PREFIX + "units.").length)] = finding.repair;
    });
    return named;
  }
  Schedule.prototype.actions = function (row) {
    if (row.record.type) return [{ id: "place", label: "Place " + row.record.name, icon: "add",
      disabled: !this.owner.placement.enabled || !this.owner.placement.available(row.record.type.id) }];
    // Every Unit row's own actions come first, so they line up down the column; the repairs its findings name
    // follow as a set-apart group, which only some rows have.
    var named = repairs(row.record.unit), actions = [{ id: "locate", label: "Locate Window", icon: "locate" },
      { id: "swap_type", label: "Swap Window Type", icon: "variant" },
      { id: "remove", label: "Remove Window", icon: "delete" }];
    REPAIRS.filter(function (repair) { return named[repair[0]]; }).forEach(function (repair, index) {
      actions.push({ id: repair[0], label: repair[1], icon: repair[2], starts: index === 0 });
    });
    actions.forEach(function (action) { if (action.id !== "locate") action.disabled = !this.owner.enabled; }, this);
    return actions;
  };
  Schedule.prototype.act = function (row, action, trigger) {
    if (this.disposed || !this.enabled) return;
    if (this.owner.guard()) { this.owner.notice.show(this.owner.guard()); return; }
    if (action.id === "place") { this.owner.placement.choose(row.record.type.id); return; }
    var unit = clone(row.record.unit);
    if (action.id === "locate") {
      this.views.run(PREFIX + "units.locate", { units: [unit.reference] }); this.paint(); return;
    }
    if (!this.owner.enabled) return;
    if (!this.units.some(function (current) { return JSON.stringify(current.reference) ===
      JSON.stringify(unit.reference); })) return;
    this.openRepair(unit, action.id, trigger);
  };
  Schedule.prototype.close = function () {
    var dialog = this.dialog; if (!dialog) return;
    this.dialog = null; this.target = null; this.stale = false; dialog.closeModal();
    if (dialog.parentNode) dialog.parentNode.removeChild(dialog);
    this.paint();
    if (this.trigger && this.root.contains(this.trigger)) this.trigger.focus({ preventScroll: true });
  };
  Schedule.prototype.openRepair = function (unit, action, trigger) {
    var self = this, dialog = ui.formDialog("window-repair-dialog", function () {
      if (!self.edits.busy()) self.close();
    });
    this.dialog = dialog; this.target = unit; this.trigger = trigger;
    this.revision = this.owner.state.revision;
    var labels = { reset_to_type: "Reset to Type", new_flipped_type: "New flipped Type", swap_type: "Swap Type",
      rehost: "Re-host Window", repair_copied_identities: "Repair copied identities", remove: "Remove Window" };
    dialog.appendChild(ui.element("h2", "", labels[action]));
    var text = action === "reset_to_type" ? "Reset this Window to its Type. If the primary definition was edited, " +
      "all Windows using that primary definition are reset together." : action === "remove" ?
      "Remove this Window and its native opening. Use SketchUp Undo to restore it." : action === "new_flipped_type" ?
      "Create an independent horizontally flipped Type while keeping the Window panes and anchor in place." :
      action === "rehost" ? "Choose a Face in the same parent storage. Re-host keeps the Window in place." :
      action === "repair_copied_identities" ? "Give the copies sharing this Window's identity new identities. " +
      "Geometry, glue and metadata stay." :
      "Choose a Type. Swap preserves the Window anchor and checks its full outline.";
    dialog.appendChild(ui.element("p", "", text));
    var choices = action === "swap_type" ? this.owner.entries.map(function (entry) {
      return { value: entry.record.id, label: entry.record.name };
    }) : action === "rehost" ? this.faces.filter(function (face) {
      var path = face.reference.zone_path.concat(face.reference.entity_path).slice(0, -1);
      return JSON.stringify(path) === JSON.stringify(unit.reference.entity_path.slice(0, -1)) &&
        (face.values || {}).boundary_condition !== "Surface";
    }).map(function (face) { return { value: JSON.stringify(face.reference),
      label: self.faceName(face.reference) }; }) : null;
    var picker;
    if (choices) { picker = ui.element("select"); picker.setAttribute("aria-label", action === "rehost" ?
      "Replacement host Face" : "Replacement Window Type");
      picker.appendChild(ui.option("", "Choose…")); choices.forEach(function (choice) {
        picker.appendChild(ui.option(choice.value, choice.label)); }); dialog.appendChild(picker); }
    this.error = ui.element("p", "phc-field-error"); this.error.hidden = true; dialog.appendChild(this.error);
    var cancel = ui.button("Cancel", function () { if (!self.edits.busy()) self.close(); });
    cancel.setAttribute("aria-label", "Cancel");
    var apply = ui.button(labels[action], function () {
      if (self.dialog !== dialog || self.disposed || !self.enabled || !self.owner.enabled || apply.disabled) return;
      if (picker && !picker.value) { self.error.textContent = "Choose a replacement first.";
        self.error.hidden = false; return; }
      var repair = repairs(unit)[action];
      var params = repair ? clone(repair.params) : { units: [clone(unit.reference)] };
      if (action === "swap_type") params.type_id = picker.value;
      if (action === "rehost") params.host = JSON.parse(picker.value);
      self.edits.run(PREFIX + "units." + action, params, { onDone: function () { self.close(); },
        onFail: function (outcome) { self.error.textContent = self.stale ?
          "The Model changed. Cancel and reopen the repair." : outcome.message || "The repair was refused.";
          self.error.hidden = false; } }); self.paint();
    }); apply.setAttribute("data-schedule-apply", "true");
    apply.setAttribute("aria-label", labels[action]);
    if (action === "remove") apply.className = "phc-confirm-delete";
    this.cancel = cancel; this.apply = apply;
    dialog.appendChild(ui.actionRow(cancel, apply, action === "remove" || action === "reset_to_type"));
    this.root.appendChild(dialog); dialog.openModal(); cancel.focus({ preventScroll: true });
  };
  Schedule.prototype.render = function (state) {
    if (this.disposed) return;
    var value = snapshot.value(state, PREFIX + "units"); this.enabled = Boolean(value);
    this.units = value ? value.units : [];
    this.areas = (snapshot.value(state, PREFIX + "unit_areas") || {}).faces || [];
    this.zones = (snapshot.value(state, "ph_composer.zones.overview") || {}).zones || [];
    this.faces = (snapshot.value(state, "ph_composer.zones.faces.faces") || {}).faces || [];
    if (!this.enabled) { this.edits.reset(); this.views.reset(); this.close(); }
    if (!this.owner.enabled) { this.edits.reset(); this.close(); }
    if (this.target) {
      var current = this.units.filter(function (unit) { return JSON.stringify(unit.reference.entity_path) ===
        JSON.stringify(this.target.reference.entity_path); }, this)[0];
      if (!current) { this.edits.reset(); this.close(); }
      else if (JSON.stringify(current) !== JSON.stringify(this.target)) {
        this.stale = true; this.error.textContent = "The Window changed. Cancel and reopen its repair.";
        this.error.hidden = false;
      }
      if (this.dialog && state.revision !== this.revision) {
        this.stale = true; this.error.textContent = "The Model changed. Cancel and reopen the repair.";
        this.error.hidden = false;
      }
    }
    this.selected = {};
    ((snapshot.value(state, PREFIX + "units.selected") || {}).units || []).forEach(function (reference) {
      this.selected[JSON.stringify(reference.entity_path)] = true;
    }, this);
    var rows = this.rows(); this.names.refresh(rows, state);
    this.edits.consume(state); this.views.consume(state); this.paint(rows);
  };
  /* The Window rows SketchUp's selection has just reached, each under an open Type so it can be seen. */
  Schedule.prototype.follow = function (rows) {
    var previous = this.followed || {}, fresh = rows.filter(function (row) {
      return row.record.unit && this.selected[row.key] && !previous[row.key];
    }, this);
    this.followed = this.selected;
    fresh.forEach(function (row) { this.expanded[row.parent] = true; }, this);
    return fresh[0];
  };
  Schedule.prototype.paint = function (built) {
    if (this.disposed || !this.units) return;
    var self = this, rows = built || this.rows();
    this.summary.textContent = this.enabled ? this.units.length + " Window" + (this.units.length === 1 ? "" : "s") :
      "Window occurrences are unavailable.";
    var reached = this.follow(rows);
    tables.table(this.mount, this.units, { rows: rows, expanded: this.expanded, tree: true,
      defaultWidths: { count: 84 },
      columns: [["actions", "Actions"], ["hierarchy", "Hierarchy"], ["name", "Window Type / Unit"], ["count", "Count"],
        ["zone", "Zone"], ["host", "Host Face"],
        ["net_area", units.header("Net opaque host area", fields.AREA_M2, units.profile(fields.AREA_M2))],
        ["level", "Level"], ["state", "State"]],
      value: function (row, field) { return row.record[field] === undefined ? "" : row.record[field]; },
      selected: function (row) { return Boolean(row.record.unit && self.selected[row.key]); },
      cell: function (cell, row, field) {
        if (field !== "name" || !self.names.render(cell, row, field)) return false;
        ui.tooltip(cell, row.record.audit);
        return true;
      },
      decorate: function (cell, row, field) {
        if (field === "name") {
          ui.tooltip(cell, row.record.audit || row.record.name);
        }
        // A Window Type nobody has placed yet reads as a quiet zero.
        if (field === "count") cell.classList.toggle("is-muted", row.record.count === 0);
      },
      disabled: Boolean(this.owner.guard()), actions: function (row) { return self.actions(row); },
      action: function (row, action, trigger) { self.act(row, action, trigger); },
      empty: "Add a Window Type, then Place it in SketchUp.",
      emptyAction: { label: "+ New Window Type", disabled: Boolean(this.owner.guard()), run: function () {
        self.owner.createType();
      } } });
    tables.orientNarrow(this.mount);
    if (reached && this.mount._table.rows[reached.key].node.scrollIntoView) {
      this.mount._table.rows[reached.key].node.scrollIntoView({ block: "nearest" });
    }
    if (this.dialog) { this.apply.disabled = Boolean(this.edits.busy() || this.stale);
      this.cancel.disabled = this.edits.busy(); }
  };
  Schedule.prototype.dispose = function () {
    this.disposed = true; this.enabled = false; this.edits.reset(); this.views.reset(); this.close();
    this.names.dispose();
  };
  return { Schedule: Schedule };
});
