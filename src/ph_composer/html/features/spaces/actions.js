/* The Spaces view's row actions: Locate every row; Open or Close a Space; Enter a Volume;
 * Delete a Space, Remove a Space keeping its floors and Delete a Volume with its floor Faces, each after a
 * confirmation naming what goes (a Space's only Volume offers Delete Space instead); Move a Space to Zone; and the
 * repair a row's finding names (Restore position, Make independent).
 *
 * Every Model change carries the revision the row was painted from, so a row from a stale snapshot refuses
 * rather than acting on what has changed. Context commands are view commands (they move the edit context and
 * the selection, never a record); entering a protected Volume unprotects it first and opens it only once that
 * has completed. The open row is the one on the snapshot's edit path, never the selection or the expansion.
 */
PhComposerUI.define("features/spaces/actions", ["panel", "request", "workspace", "units", "unit_preferences", "fields"],
function (panel, requests, ui, units, preferences, fields) {
  "use strict";
  var PREFIX = "ph_composer.spaces";

  function copy(value) { return JSON.parse(JSON.stringify(value)); }

  function startsWith(path, prefix) {
    return path.length >= prefix.length && prefix.every(function (id, index) { return path[index] === id; });
  }

  function SpaceActions(host) {
    var self = this;
    this.host = host;
    this.editPath = [];
    this.zones = [];
    // A change carries the revision its row was read at: the current one, or the one a confirmation opened at.
    this.edits = requests.channel(host.session, function (type, payload) {
      var revision = self.pinned !== undefined ? self.pinned : self.host.revision;
      send(type, Object.assign({}, payload, { expected_revision: revision }));
    }, "spaces-actions");
    this.context = requests.channel(host.session, function (type, payload) { send(type, payload); },
      "spaces-context", "view.invoke");
    this.reads = requests.channel(host.session, function (type, payload) { send(type, payload); },
      "spaces-reads", "query.invoke");
    function send(type, payload) { self.host.send(type, payload); }
  }

  /* What a snapshot says: the edit path, the Zones a Space may move to, and the outcomes this view awaits. */
  SpaceActions.prototype.consume = function (state, zones) {
    this.editPath = state.edit_path || [];
    this.zones = zones || [];
    var self = this;
    this.reads.consume(state);
    [this.edits, this.context].forEach(function (channel) {
      var outcome = channel.consume(state);
      if (!outcome) return;
      if (outcome.status !== "completed") {
        self.entering = null;
        self.closing = null;
        self.host.refuse(outcome.message || "The Spaces command was not applied. Nothing was written.");
      } else if (channel === self.context && self.closing) {
        // Close leaves the innermost context; a Space closes through any Volume of it that is open.
        var path = outcome.value && outcome.value.path || [];
        if (startsWith(path, self.closing)) self.context.run(PREFIX + ".context.close", {});
        else self.closing = null;
      } else if (channel === self.edits && self.entering) {
        // Unprotected: now the Volume may be opened.
        var volume = self.entering;
        self.entering = null;
        self.context.run(PREFIX + ".context.open", { reference: volume });
      }
    });
  };

  /* Whether a row is open in the edit context: a Space or Volume on the path the snapshot reports. */
  SpaceActions.prototype.open = function (row) {
    var target = row.record.volume || (row.record.segment ? null : row.record.space);
    return Boolean(target) && startsWith(this.editPath, target.reference.entity_path);
  };

  SpaceActions.prototype.busy = function () { return this.edits.busy() || this.context.busy() || this.reads.busy(); };

  /* What names a row's record to the user even when it has no name: "Living", or "Space 101", or
     "Volume 1 of Living". */
  function describe(record) {
    var space = record.space;
    var spaceName = space ? space.values.name || "Space " + space.values.number : "";
    if (record.volume) {
      return (record.volume.values.display_name || "Volume " + record.volume.values.number) + " of " + spaceName;
    }
    if (record.segment) return record.segment.values.display_name || "Floor Segment of " + spaceName;
    return spaceName;
  }

  function repairs(record) {
    return (record.findings || []).map(function (finding) { return finding.repair; }).filter(Boolean);
  }

  /* A row's actions, Locate first, the destructive ones last. */
  SpaceActions.prototype.actions = function (row) {
    var record = row.record, target = record.segment || record.volume || record.space, items = [];
    if (!target) return items;
    var busy = this.busy(), name = record.volume || record.segment ? record.name || describe(record) :
      describe(record);
    items.push({ id: "spaces.locate", icon: "locate", label: "Locate " + name, disabled: busy });
    var fixes = repairs(target);
    if (record.volume && fixes.indexOf("restore_position") >= 0) {
      items.push({ id: "spaces.restore", icon: "repair", label: "Restore the position of " + name, disabled: busy });
    }
    if (fixes.indexOf("unhost") >= 0) {
      items.push({ id: "spaces.unhost", icon: "repair", label: "Remove " + name + " from its missing Zone",
        disabled: busy });
    }
    if (fixes.indexOf("make_independent") >= 0) {
      items.push({ id: "spaces.independent", icon: "repair", label: "Make " + name + " independent", disabled: busy });
    }
    if (record.space && !record.volume && !record.segment) {
      var open = this.open(row);
      items.push(open ? { id: "spaces.close", icon: "close", label: "Close " + name, disabled: busy } :
        { id: "spaces.open", icon: "enter", label: "Open " + name, disabled: busy });
      if (this.zones.length > 1 || !record.space.zone && this.zones.length) {
        items.push({ id: "spaces.move", icon: "assign", label: "Move " + name + " to Zone", disabled: busy });
      }
      items.push({ id: "spaces.remove", icon: "ungroup", label: "Remove " + name + ", keep its floors",
        disabled: busy });
      items.push({ id: "spaces.delete", icon: "delete", label: "Delete " + name, disabled: busy });
    }
    if (record.volume && !record.segment) {
      if (!this.open(row)) items.push({ id: "spaces.enter", icon: "enter", label: "Enter " + name, disabled: busy });
      items.push({ id: "spaces.height_from_solid", icon: "ruler", label: "Height of " + name + " from a solid",
        disabled: busy });
      items.push({ id: "spaces.delete_volume", icon: "delete", label: "Delete " + name, disabled: busy });
    }
    return items;
  };

  // The actions that change records or the edit context's protection; a held cell draft must not be lost to one.
  var CHANGES = { "spaces.enter": true, "spaces.restore": true, "spaces.independent": true, "spaces.delete": true,
    "spaces.remove": true, "spaces.delete_volume": true, "spaces.move": true, "spaces.unhost": true,
    "spaces.height_from_solid": true };

  /* Runs one of this view's actions; false for an action it does not own. */
  SpaceActions.prototype.run = function (row, item) {
    var record = row.record, target = record.segment || record.volume || record.space;
    if (item.id.indexOf("spaces.") !== 0 || !target) return false;
    if (this.busy()) return true;
    var held = CHANGES[item.id] && this.host.draftReason();
    if (held) { this.host.refuse(held); return true; }
    var reference = copy(target.reference), self = this;
    switch (item.id) {
      case "spaces.locate": this.context.run(PREFIX + ".locate", { reference: reference }); break;
      case "spaces.unhost": this.edits.run(PREFIX + ".unhost", { space: reference }); break;
      case "spaces.open": this.context.run(PREFIX + ".context.open", { reference: reference }); break;
      case "spaces.close":
        this.closing = copy(reference.entity_path);
        this.context.run(PREFIX + ".context.close", {});
        break;
      case "spaces.enter":
        // A protected Volume is unlocked first; consume opens it once that completes.
        if (record.volume.protected) {
          this.entering = reference;
          this.edits.run(PREFIX + ".volumes.unprotect", { volume: reference });
        } else this.context.run(PREFIX + ".context.open", { reference: reference });
        break;
      case "spaces.restore": this.edits.run(PREFIX + ".volumes.restore_position", { volume: reference }); break;
      case "spaces.independent": this.edits.run(PREFIX + ".make_independent", { reference: reference }); break;
      case "spaces.delete":
        this.askFirst("Delete Space?", describe(record) + ", its Volumes and their Floor Segments will be erased.",
          "Delete", function (revision) {
          self.runAt(revision, PREFIX + ".delete", { space: reference });
        });
        break;
      case "spaces.remove":
        this.askFirst("Remove Space?", describe(record) + " and its Volumes will be removed. Their floor Faces stay " +
          "where they are as plain geometry. One Undo brings the Space back.", "Remove", function (revision) {
          self.runAt(revision, PREFIX + ".remove", { space: reference });
        });
        break;
      case "spaces.delete_volume": this.deleteVolume(record, reference); break;
      case "spaces.move": this.pickZone(record, reference); break;
      case "spaces.height_from_solid": this.heightFromSolid(record, reference); break;
      default: return false;
    }
    return true;
  };

  /* Delete a Volume and its floor Faces, and any Volume nested in it. When no other Volume of the Space would be
     left, it offers Delete Space instead, so the panel never leaves a Space empty. */
  SpaceActions.prototype.deleteVolume = function (record, reference) {
    var self = this, space = copy(record.space.reference);
    var left = (record.space.volumes || []).filter(function (volume) {
      return !startsWith(volume.reference.entity_path, reference.entity_path);
    });
    if (!left.length) {
      var spaceName = describe({ space: record.space });
      this.askFirst("Delete Space?", (record.volume.values.display_name || "Volume " + record.volume.values.number) +
        " is the only Volume of " + spaceName + ", so the Space goes with it: " + spaceName + " and everything in " +
        "it will be erased. One Undo brings it back.", "Delete Space", function (revision) {
        self.runAt(revision, PREFIX + ".delete", { space: space });
      });
      return;
    }
    this.askFirst("Delete Volume?", describe(record) + " and its floor Faces will be erased. One Undo brings them " +
      "back.", "Delete", function (revision) {
      self.runAt(revision, PREFIX + ".volumes.delete", { volume: reference });
    });
  };

  /* Sends a change as of the revision a confirmation opened at, so one reviewed against older rows refuses. */
  SpaceActions.prototype.runAt = function (revision, name, params) {
    this.pinned = revision;
    try { this.edits.run(name, params); } finally { this.pinned = undefined; }
  };

  /* A confirmation in the shared dialog, naming exactly what goes; Cancel changes nothing. What it confirms
     is as of the revision it opened at. */
  SpaceActions.prototype.askFirst = function (title, consequence, commit, run) {
    var dialog = this.dialog || (this.dialog = ui.formDialog("", function () { dialog.closeModal(); }));
    if (!dialog.parentNode) document.body.appendChild(dialog);
    var cancel = ui.button("Cancel", function () { dialog.closeModal(); });
    var self = this, revision = this.host.revision;
    dialog.replaceChildren(ui.element("h2", "", title), ui.element("p", "", consequence),
      ui.actionRow(cancel, ui.button(commit, function () {
        dialog.closeModal();
        if (!self.host.disposed && !self.busy()) { run(revision); panel.repaint(); }
      }), true));
    dialog.openModal();
    cancel.focus();
  };

  /* Move to Zone: the Zones the Space may move to, chosen in the shared dialog. */
  SpaceActions.prototype.pickZone = function (record, reference) {
    var current = record.space.zone && JSON.stringify(record.space.zone.zone_path);
    var choices = this.zones.filter(function (zone) { return JSON.stringify(zone.zone_path) !== current; });
    var dialog = this.dialog || (this.dialog = ui.formDialog("", function () { dialog.closeModal(); }));
    if (!dialog.parentNode) document.body.appendChild(dialog);
    var select = ui.element("select");
    select.setAttribute("aria-label", "Zone to move " + describe(record) + " to");
    choices.forEach(function (zone, index) { select.appendChild(ui.option(String(index), zone.name || "Zone")); });
    var cancel = ui.button("Cancel", function () { dialog.closeModal(); }), self = this;
    var revision = this.host.revision;
    dialog.replaceChildren(ui.element("h2", "", "Move " + describe(record) + " to Zone"),
      ui.element("p", "", "The Space is hosted in the Zone you pick. It stays where it stands, with its Volumes and " +
        "Floor Segments; its number and values are kept."), select,
      ui.actionRow(cancel, ui.button("Move", function () {
        var zone = choices[Number(select.value)];
        dialog.closeModal();
        if (!zone || self.host.disposed || self.busy()) return;
        self.runAt(revision, PREFIX + ".move_to_zone", { space: reference,
          zone: { zone_id: zone.zone_id, zone_path: copy(zone.zone_path) } });
        panel.repaint();
      })));
    dialog.openModal();
    select.focus();
  };

  /* Height from solid: the solid selected in SketchUp, then what it would give, then a confirmation showing the
     solid's volume, the net floor area and the height before anything is written. */
  SpaceActions.prototype.heightFromSolid = function (record, reference) {
    var self = this, name = record.name || describe(record);
    function refused(outcome) { panel.notify(outcome.message || "Height from solid could not run.", "warning"); }
    this.reads.run(PREFIX + ".selected_solid", {}, { onFail: refused, onDone: function (selected) {
      var params = { volume: copy(reference), solid: copy(selected.value.solid) };
      self.reads.run(PREFIX + ".volumes.height_from_solid_preview", params, { onFail: refused, onDone: function (seen) {
        self.confirmHeight(name, params, seen);
      } });
    } });
  };

  /* The reads are asynchronous, so a draft begun while they ran is checked again before the confirmation opens
     and before it writes. */
  SpaceActions.prototype.confirmHeight = function (name, params, seen) {
    var value = seen.value, self = this;
    function held() {
      var reason = self.host.draftReason && self.host.draftReason();
      if (reason) self.host.refuse(reason);
      return Boolean(reason);
    }
    // A preview that lands after the user left the Spaces view is dropped: its confirmation would open elsewhere.
    var shown = (!panel.state.ui || panel.state.ui.activeTab === "overview") &&
      (!this.host.activeView || this.host.activeView() === "ph_composer.spaces");
    if (!shown || held()) return;
    function text(number, field) { return units.format(number, field, units.profile(field, preferences.current())); }
    var dialog = this.dialog || (this.dialog = ui.formDialog("", function () { dialog.closeModal(); }));
    if (!dialog.parentNode) document.body.appendChild(dialog);
    var cancel = ui.button("Cancel", function () { dialog.closeModal(); });
    dialog.replaceChildren(ui.element("h2", "", "Height of " + name + " from a solid"),
      ui.element("p", "", "The solid encloses " + text(value.solid_volume_m3, fields.VOLUME_M3) + " over a net floor " +
        "area of " + text(value.net_floor_area_m2, fields.AREA_M2) + ", so the average clear ceiling height becomes " +
        text(value.height_m, fields.LENGTH_M) + ". The solid is left as it is."),
      ui.actionRow(cancel, ui.button("Set height", function () {
        dialog.closeModal();
        if (self.host.disposed || self.busy() || held()) return;
        self.runAt(seen.revision, PREFIX + ".volumes.height_from_solid", Object.assign({}, params,
          { expected_values: { avg_ceiling_height_m: value.current_height_m } }));
        panel.repaint();
      })));
    dialog.openModal();
    cancel.focus();
  };

  SpaceActions.prototype.dispose = function () {
    this.edits.reset();
    this.reads.reset();
    this.context.reset();
    if (this.dialog) {
      this.dialog.closeModal();
      if (this.dialog.parentNode) this.dialog.parentNode.removeChild(this.dialog);
    }
  };

  return SpaceActions;
});
